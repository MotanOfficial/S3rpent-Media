#include "ziparchivereader.h"

#include <QFile>
#include <QFileInfo>
#include <QDir>
#include <QDirIterator>
#include <QProcess>
#include <QStandardPaths>
#include <QRegularExpression>
#include <QSettings>
#include <QtConcurrent>
#include <QtMath>
#include <QUuid>
#ifdef HAS_LIBARCHIVE
#include <archive.h>
#include <archive_entry.h>
#endif

namespace {
constexpr quint32 EOCD_SIGNATURE = 0x06054b50u;
constexpr quint32 CEN_SIGNATURE = 0x02014b50u;
constexpr qint64 MAX_EOCD_SEARCH = 22 + 0xFFFF;
}

namespace {
QString psEscape(const QString &value)
{
    QString escaped = value;
    escaped.replace("'", "''");
    return escaped;
}

QString findFirstExecutable(const QStringList &candidates)
{
    for (const QString &candidate : candidates) {
        const QString exe = QStandardPaths::findExecutable(candidate);
        if (!exe.isEmpty()) {
            return exe;
        }
    }
    return QString();
}
}

QString ZipArchiveReader::replacePlaceholders(QString text, const QString &zipPath, const QString &destinationPath)
{
    text.replace(QStringLiteral("{zip}"), QDir::toNativeSeparators(zipPath));
    text.replace(QStringLiteral("{dest}"), QDir::toNativeSeparators(destinationPath));
    text.replace(QStringLiteral("%ZIP%"), QDir::toNativeSeparators(zipPath));
    text.replace(QStringLiteral("%DEST%"), QDir::toNativeSeparators(destinationPath));
    return text;
}

bool ZipArchiveReader::tryCustomExtractor(const QString &zipPath,
                                          const QString &destinationPath,
                                          QString &programOut,
                                          QStringList &argsOut,
                                          QString &errorOut) const
{
    QSettings settings;
    settings.beginGroup(QStringLiteral("zip"));
    QString customProgram = settings.value(QStringLiteral("extractorProgram")).toString().trimmed();
    QString customArgs = settings.value(QStringLiteral("extractorArgs")).toString().trimmed();
    settings.endGroup();

    if (customProgram.isEmpty()) {
        customProgram = qEnvironmentVariable("S3RP3NT_ZIP_EXTRACTOR_PROGRAM").trimmed();
    }
    if (customArgs.isEmpty()) {
        customArgs = qEnvironmentVariable("S3RP3NT_ZIP_EXTRACTOR_ARGS").trimmed();
    }

    if (customProgram.isEmpty()) {
        return false;
    }

    customProgram = replacePlaceholders(customProgram, zipPath, destinationPath);
    customArgs = replacePlaceholders(customArgs, zipPath, destinationPath);

    QString resolvedProgram = customProgram;
    if (!QFileInfo(customProgram).isAbsolute()) {
        const QString found = QStandardPaths::findExecutable(customProgram);
        if (!found.isEmpty()) {
            resolvedProgram = found;
        }
    }
    if (!QFileInfo::exists(resolvedProgram)) {
        errorOut = tr("Custom extractor not found: %1").arg(customProgram);
        return false;
    }

    programOut = resolvedProgram;
    argsOut = customArgs.isEmpty() ? QStringList() : QProcess::splitCommand(customArgs);
    return true;
}

ZipArchiveReader::ZipArchiveReader(QObject *parent)
    : QObject(parent)
{
    m_progressTimer.setInterval(1000);
    m_progressTimer.setSingleShot(false);
    connect(&m_progressTimer, &QTimer::timeout, this, &ZipArchiveReader::updateProgressStats);

#ifdef HAS_LIBARCHIVE
    connect(&m_libArchiveWatcher, &QFutureWatcher<QPair<bool, QString>>::finished, this, [this]() {
        const QPair<bool, QString> result = m_libArchiveWatcher.result();
        if (result.first) {
            updateProgressStats();
            setProgressPercent(100.0);
            if (m_lastExtractedPath != m_pendingDestinationPath) {
                m_lastExtractedPath = m_pendingDestinationPath;
                emit lastExtractedPathChanged();
            }
            finishExtraction(true, tr("Extracted to: %1").arg(QDir::toNativeSeparators(m_pendingDestinationPath)));
        } else {
            finishExtraction(false, result.second.isEmpty() ? tr("libarchive extraction failed.") : result.second);
        }
    });
#endif
}

void ZipArchiveReader::setSource(const QUrl &source)
{
    if (m_source == source) {
        return;
    }
    m_source = source;
    emit sourceChanged();
    reload();
}

void ZipArchiveReader::reload()
{
    if (m_source.isEmpty()) {
        setEntries({}, 0, 0);
        setError(QString());
        if (m_loaded) {
            m_loaded = false;
            emit loadedChanged();
        }
        return;
    }

    const QString filePath = m_source.isLocalFile() ? m_source.toLocalFile() : m_source.toString(QUrl::PreferLocalFile);
    QString error;
    bool ok = false;
#ifdef HAS_LIBARCHIVE
    ok = parseZipFile(filePath, error);
    if (!ok) {
        ok = parseZipFileWithLibArchive(filePath, error);
    }
#else
    ok = parseZipFile(filePath, error);
#endif

    if (!ok) {
        setEntries({}, 0, 0);
        setError(error);
        if (m_loaded) {
            m_loaded = false;
            emit loadedChanged();
        }
        return;
    }

    setError(QString());
    if (!m_loaded) {
        m_loaded = true;
        emit loadedChanged();
    }
}

quint16 ZipArchiveReader::readU16(const char *p)
{
    const auto b = reinterpret_cast<const uchar *>(p);
    return quint16(b[0] | (quint16(b[1]) << 8));
}

quint32 ZipArchiveReader::readU32(const char *p)
{
    const auto b = reinterpret_cast<const uchar *>(p);
    return quint32(b[0]
                   | (quint32(b[1]) << 8)
                   | (quint32(b[2]) << 16)
                   | (quint32(b[3]) << 24));
}

QDateTime ZipArchiveReader::dosDateTimeToQDateTime(quint16 dosDate, quint16 dosTime)
{
    const int year = ((dosDate >> 9) & 0x7F) + 1980;
    const int month = (dosDate >> 5) & 0x0F;
    const int day = dosDate & 0x1F;
    const int hour = (dosTime >> 11) & 0x1F;
    const int minute = (dosTime >> 5) & 0x3F;
    const int second = (dosTime & 0x1F) * 2;

    const QDate date(year, month, day);
    const QTime time(hour, minute, second);
    if (!date.isValid() || !time.isValid()) {
        return {};
    }
    return QDateTime(date, time, Qt::LocalTime);
}

void ZipArchiveReader::setEntries(const QVariantList &entries, qlonglong totalSize, int files)
{
    if (m_entries != entries) {
        m_entries = entries;
        emit entriesChanged();
    }
    if (m_totalUncompressedSize != totalSize) {
        m_totalUncompressedSize = totalSize;
        emit totalUncompressedSizeChanged();
    }
    if (m_fileCount != files) {
        m_fileCount = files;
        emit fileCountChanged();
    }
}

void ZipArchiveReader::setError(const QString &error)
{
    if (m_errorString != error) {
        m_errorString = error;
        emit errorStringChanged();
    }
}

void ZipArchiveReader::setExtracting(bool extracting)
{
    if (m_extracting != extracting) {
        m_extracting = extracting;
        emit extractingChanged();
    }
}

void ZipArchiveReader::setExtractedBytes(qlonglong value)
{
    if (m_extractedBytes != value) {
        m_extractedBytes = value;
        emit extractedBytesChanged();
    }
}

void ZipArchiveReader::setExtractedFiles(int value)
{
    if (m_extractedFiles != value) {
        m_extractedFiles = value;
        emit extractedFilesChanged();
    }
}

void ZipArchiveReader::setProgressPercent(double value)
{
    const double clamped = qBound(0.0, value, 100.0);
    if (!qFuzzyCompare(m_progressPercent + 1.0, clamped + 1.0)) {
        m_progressPercent = clamped;
        emit progressPercentChanged();
    }
}

void ZipArchiveReader::setSpeedBytesPerSecond(double value)
{
    const double bounded = qMax(0.0, value);
    if (!qFuzzyCompare(m_speedBytesPerSecond + 1.0, bounded + 1.0)) {
        m_speedBytesPerSecond = bounded;
        emit speedBytesPerSecondChanged();
    }
}

void ZipArchiveReader::setElapsedSeconds(int value)
{
    if (m_elapsedSeconds != value) {
        m_elapsedSeconds = value;
        emit elapsedSecondsChanged();
    }
}

void ZipArchiveReader::setEtaSeconds(int value)
{
    if (m_etaSeconds != value) {
        m_etaSeconds = value;
        emit etaSecondsChanged();
    }
}

void ZipArchiveReader::resetProgressStats()
{
    setExtractedBytes(0);
    setExtractedFiles(0);
    setProgressPercent(0.0);
    setSpeedBytesPerSecond(0.0);
    setElapsedSeconds(0);
    setEtaSeconds(-1);
}

void ZipArchiveReader::updateDerivedSpeedAndEta()
{
    const int elapsed = int(m_extractionElapsedTimer.elapsed() / 1000);
    setElapsedSeconds(elapsed);
    if (elapsed > 0) {
        const double speed = double(m_extractedBytes) / double(elapsed);
        setSpeedBytesPerSecond(speed);
        if (m_totalUncompressedSize > 0 && speed > 0.0 && m_extractedBytes < m_totalUncompressedSize) {
            const qlonglong remaining = m_totalUncompressedSize - m_extractedBytes;
            setEtaSeconds(int(remaining / speed));
        } else {
            setEtaSeconds(0);
        }
    } else {
        setSpeedBytesPerSecond(0.0);
        setEtaSeconds(-1);
    }
}

void ZipArchiveReader::handleProcessProgressChunk(const QString &chunk)
{
    if (chunk.isEmpty()) {
        return;
    }

    // 7z emits lines like: " 23% 123 - path/to/file"
    QRegularExpression percentRe(QStringLiteral("(\\d{1,3})%"));
    QRegularExpressionMatchIterator pit = percentRe.globalMatch(chunk);
    int maxPercent = -1;
    while (pit.hasNext()) {
        const auto m = pit.next();
        const int pct = m.captured(1).toInt();
        if (pct > maxPercent) {
            maxPercent = pct;
        }
    }
    if (maxPercent >= 0) {
        setProgressPercent(double(maxPercent));
        if (m_totalUncompressedSize > 0) {
            const qlonglong bytes = qlonglong((double(m_totalUncompressedSize) * double(maxPercent)) / 100.0);
            setExtractedBytes(bytes);
        }
    }

    // Count extracted files from 7z textual output.
    QRegularExpression fileRe(QStringLiteral("(?:\\r|\\n|^)\\s*(Extracting|Inflating)\\s+"));
    int increment = 0;
    QRegularExpressionMatchIterator fit = fileRe.globalMatch(chunk);
    while (fit.hasNext()) {
        fit.next();
        ++increment;
    }
    if (increment > 0) {
        setExtractedFiles(m_extractedFiles + increment);
    }

    updateDerivedSpeedAndEta();
}

void ZipArchiveReader::calculateDirectoryStats(const QString &rootPath, qlonglong &bytesOut, int &filesOut)
{
    bytesOut = 0;
    filesOut = 0;
    QDir root(rootPath);
    if (!root.exists()) {
        return;
    }

    QDirIterator it(rootPath, QDir::Files, QDirIterator::Subdirectories);
    while (it.hasNext()) {
        it.next();
        const QFileInfo fi = it.fileInfo();
        if (fi.isFile()) {
            bytesOut += fi.size();
            ++filesOut;
        }
    }
}

void ZipArchiveReader::updateProgressStats()
{
    if (!m_extracting || m_pendingDestinationPath.isEmpty()) {
        return;
    }

#ifdef HAS_LIBARCHIVE
    if (m_libArchiveWatcher.isRunning()) {
        const qlonglong bytes = m_workerExtractedBytes.load(std::memory_order_relaxed);
        const int files = m_workerExtractedFiles.load(std::memory_order_relaxed);
        setExtractedBytes(bytes);
        setExtractedFiles(files);
        if (m_totalUncompressedSize > 0) {
            const double pct = (double(bytes) * 100.0) / double(m_totalUncompressedSize);
            setProgressPercent(pct);
        }
        updateDerivedSpeedAndEta();
        return;
    }
#endif

    if (!m_useDirectorySampling) {
        updateDerivedSpeedAndEta();
        return;
    }

    qlonglong currentBytes = 0;
    int currentFiles = 0;
    calculateDirectoryStats(m_pendingDestinationPath, currentBytes, currentFiles);

    const qlonglong deltaBytes = qMax<qlonglong>(0, currentBytes - m_baselineBytes);
    const int deltaFiles = qMax(0, currentFiles - m_baselineFiles);
    setExtractedBytes(deltaBytes);
    setExtractedFiles(deltaFiles);

    if (m_totalUncompressedSize > 0) {
        const double pct = (double(deltaBytes) * 100.0) / double(m_totalUncompressedSize);
        setProgressPercent(pct);
    } else {
        setProgressPercent(0.0);
    }

    updateDerivedSpeedAndEta();
}

bool ZipArchiveReader::startExtractionProcess(const QString &zipPath, const QString &destinationPath, QString &errorOut)
{
    if (m_extractProcess) {
        errorOut = tr("Extraction already in progress.");
        return false;
    }

    m_extractProcess = new QProcess(this);
    m_pendingDestinationPath = destinationPath;

    QString program;
    QStringList args;
    m_useDirectorySampling = true;
    m_useProcessProgress = false;

    QString customError;
    if (tryCustomExtractor(zipPath, destinationPath, program, args, customError)) {
        // If caller provides its own command, keep directory-sampling progress generic.
        m_useDirectorySampling = true;
        m_useProcessProgress = false;
    } else {
#ifdef HAS_LIBARCHIVE
        if (startLibArchiveExtraction(zipPath, destinationPath, errorOut)) {
            m_useDirectorySampling = false;
            m_useProcessProgress = false;
            return true;
        }
#endif
#ifdef Q_OS_WIN
        const QString sevenZipExe = findFirstExecutable({QStringLiteral("7z"), QStringLiteral("7za"), QStringLiteral("7zz")});
        if (!sevenZipExe.isEmpty()) {
            program = sevenZipExe;
            args << "x" << "-y" << "-bsp1" << "-bso1" << "-bse1"
                 << ("-o" + QDir::toNativeSeparators(destinationPath))
                 << QDir::toNativeSeparators(zipPath);
            m_useDirectorySampling = false;
            m_useProcessProgress = true;
        } else {
            const QString tarExe = findFirstExecutable({QStringLiteral("tar")});
            if (!tarExe.isEmpty()) {
                program = tarExe;
                args << "-xf" << QDir::toNativeSeparators(zipPath)
                     << "-C" << QDir::toNativeSeparators(destinationPath);
                m_useDirectorySampling = true;
            } else {
                program = QStringLiteral("powershell");
                args << "-NoProfile"
                     << "-NonInteractive"
                     << "-ExecutionPolicy" << "Bypass"
                     << "-Command"
                     << QStringLiteral("Expand-Archive -LiteralPath '%1' -DestinationPath '%2' -Force")
                            .arg(psEscape(QDir::toNativeSeparators(zipPath)),
                                 psEscape(QDir::toNativeSeparators(destinationPath)));
                m_useDirectorySampling = true;
            }
        }
#else
        program = QStringLiteral("unzip");
        args = QStringList() << "-o" << zipPath << "-d" << destinationPath;
        m_useDirectorySampling = true;
#endif
    }

    connect(m_extractProcess, &QProcess::finished, this,
            [this](int exitCode, QProcess::ExitStatus exitStatus) {
        QProcess *proc = m_extractProcess;
        m_extractProcess = nullptr;

        const QString stderrOut = QString::fromLocal8Bit(proc->readAllStandardError()).trimmed();
        proc->deleteLater();

        if (exitStatus != QProcess::NormalExit || exitCode != 0) {
            const QString msg = stderrOut.isEmpty()
                    ? tr("Extraction failed.")
                    : stderrOut;
            finishExtraction(false, msg);
            return;
        }

        updateProgressStats();
        setProgressPercent(100.0);
        if (m_lastExtractedPath != m_pendingDestinationPath) {
            m_lastExtractedPath = m_pendingDestinationPath;
            emit lastExtractedPathChanged();
        }
        finishExtraction(true, tr("Extracted to: %1").arg(QDir::toNativeSeparators(m_pendingDestinationPath)));
    });

    connect(m_extractProcess, &QProcess::errorOccurred, this,
            [this](QProcess::ProcessError) {
        if (!m_extractProcess) {
            return;
        }
        QProcess *proc = m_extractProcess;
        m_extractProcess = nullptr;
        const QString msg = proc->errorString().isEmpty()
                ? tr("Failed to start extraction process.")
                : proc->errorString();
        proc->deleteLater();
        finishExtraction(false, msg);
    });

    if (m_useProcessProgress) {
        connect(m_extractProcess, &QProcess::readyReadStandardOutput, this, [this]() {
            if (!m_extractProcess) return;
            handleProcessProgressChunk(QString::fromLocal8Bit(m_extractProcess->readAllStandardOutput()));
        });
        connect(m_extractProcess, &QProcess::readyReadStandardError, this, [this]() {
            if (!m_extractProcess) return;
            handleProcessProgressChunk(QString::fromLocal8Bit(m_extractProcess->readAllStandardError()));
        });
    }

    m_extractProcess->start(program, args);
    return true;
}

bool ZipArchiveReader::extractAllTo(const QUrl &destinationUrl)
{
    if (m_extracting) {
        const QString msg = tr("Extraction already in progress.");
        setError(msg);
        emit extractionFinished(false, msg);
        return false;
    }

    if (m_source.isEmpty()) {
        setError(tr("No ZIP source selected."));
        emit extractionFinished(false, m_errorString);
        return false;
    }

    const QString zipPath = m_source.isLocalFile() ? m_source.toLocalFile() : m_source.toString(QUrl::PreferLocalFile);
    const QString destinationPath = destinationUrl.isLocalFile() ? destinationUrl.toLocalFile() : destinationUrl.toString(QUrl::PreferLocalFile);

    if (zipPath.isEmpty() || !QFileInfo::exists(zipPath)) {
        setError(tr("ZIP source does not exist."));
        emit extractionFinished(false, m_errorString);
        return false;
    }
    if (destinationPath.isEmpty()) {
        setError(tr("Please select a destination folder."));
        emit extractionFinished(false, m_errorString);
        return false;
    }

    QDir destinationDir(destinationPath);
    if (!destinationDir.exists() && !destinationDir.mkpath(QStringLiteral("."))) {
        setError(tr("Unable to create destination folder."));
        emit extractionFinished(false, m_errorString);
        return false;
    }

    QString error;
    setExtracting(true);
    resetProgressStats();
    calculateDirectoryStats(destinationPath, m_baselineBytes, m_baselineFiles);
    m_extractionElapsedTimer.restart();
    m_progressTimer.start();
    const bool ok = startExtractionProcess(zipPath, destinationPath, error);

    if (!ok) {
        m_progressTimer.stop();
        setExtracting(false);
        setError(error.isEmpty() ? tr("Extraction failed.") : error);
        emit extractionFinished(false, m_errorString);
        return false;
    }

    setError(QString());
    return true;
}

QUrl ZipArchiveReader::prepareEntryForExternalDrag(const QString &entryPath, bool isDirectory)
{
    if (m_source.isEmpty() || entryPath.isEmpty()) {
        return {};
    }

    const QString zipPath = m_source.isLocalFile() ? m_source.toLocalFile() : m_source.toString(QUrl::PreferLocalFile);
    if (zipPath.isEmpty() || !QFileInfo::exists(zipPath)) {
        return {};
    }

    const QString tempRoot = QDir::cleanPath(QStandardPaths::writableLocation(QStandardPaths::TempLocation)
                                             + "/s3rpent_media_zip_drag");
    QDir().mkpath(tempRoot);
    const QString sessionDir = tempRoot + "/" + QUuid::createUuid().toString(QUuid::WithoutBraces);
    QDir().mkpath(sessionDir);

    const QString cleanEntry = QDir::cleanPath(entryPath).replace('\\', '/');
    if (cleanEntry.isEmpty() || cleanEntry == "." || cleanEntry == "..") {
        return {};
    }

    QString error;
    bool ok = false;
#ifdef HAS_LIBARCHIVE
    ok = extractSelectionWithLibArchive(zipPath, sessionDir, cleanEntry, isDirectory, error);
#endif

    if (!ok) {
        const QString sevenZipExe = findFirstExecutable({QStringLiteral("7z"), QStringLiteral("7za"), QStringLiteral("7zz")});
        if (!sevenZipExe.isEmpty()) {
            QProcess p;
            QStringList args;
            args << "x" << "-y"
                 << ("-o" + QDir::toNativeSeparators(sessionDir))
                 << QDir::toNativeSeparators(zipPath);
            if (isDirectory) {
                args << (cleanEntry + "/*");
            } else {
                args << cleanEntry;
            }
            p.start(sevenZipExe, args);
            if (p.waitForStarted(5000) && p.waitForFinished(120000) && p.exitCode() == 0) {
                ok = true;
            }
        }
    }

    if (!ok) {
        return {};
    }

    const QString extractedPath = QDir(sessionDir).filePath(cleanEntry);
    if (QFileInfo::exists(extractedPath)) {
        return QUrl::fromLocalFile(extractedPath);
    }

    // Some tools may strip a top-level prefix; fallback to session folder.
    return QUrl::fromLocalFile(sessionDir);
}

void ZipArchiveReader::finishExtraction(bool success, const QString &message)
{
    m_progressTimer.stop();
    updateProgressStats();
    setExtracting(false);
    setEtaSeconds(0);
    if (!success) {
        setError(message);
    } else {
        setError(QString());
    }
    emit extractionFinished(success, message);
}

bool ZipArchiveReader::parseZipFile(const QString &filePath, QString &errorOut)
{
    QFileInfo fi(filePath);
    if (!fi.exists() || !fi.isFile()) {
        errorOut = tr("File not found.");
        return false;
    }

    QFile f(filePath);
    if (!f.open(QIODevice::ReadOnly)) {
        errorOut = tr("Unable to open archive.");
        return false;
    }

    const qint64 fileSize = f.size();
    if (fileSize < 22) {
        errorOut = tr("Invalid ZIP file.");
        return false;
    }

    const qint64 tailSize = qMin(fileSize, MAX_EOCD_SEARCH);
    if (!f.seek(fileSize - tailSize)) {
        errorOut = tr("Failed to seek archive.");
        return false;
    }
    const QByteArray tail = f.read(tailSize);
    if (tail.size() < 22) {
        errorOut = tr("Invalid ZIP footer.");
        return false;
    }

    int eocdPos = -1;
    for (int i = tail.size() - 22; i >= 0; --i) {
        if (readU32(tail.constData() + i) == EOCD_SIGNATURE) {
            eocdPos = i;
            break;
        }
    }
    if (eocdPos < 0) {
        errorOut = tr("ZIP central directory not found.");
        return false;
    }

    const char *eocd = tail.constData() + eocdPos;
    const quint16 entryCount = readU16(eocd + 10);
    const quint32 centralDirSize = readU32(eocd + 12);
    const quint32 centralDirOffset = readU32(eocd + 16);

    if (entryCount == 0xFFFFu || centralDirOffset == 0xFFFFFFFFu || centralDirSize == 0xFFFFFFFFu) {
        errorOut = tr("ZIP64 archives are not supported yet.");
        return false;
    }

    if (qint64(centralDirOffset) + qint64(centralDirSize) > fileSize) {
        errorOut = tr("ZIP central directory is out of bounds.");
        return false;
    }

    if (!f.seek(centralDirOffset)) {
        errorOut = tr("Failed to seek central directory.");
        return false;
    }

    QVariantList outEntries;
    outEntries.reserve(entryCount);
    qlonglong totalUncompressed = 0;
    int files = 0;

    for (quint16 i = 0; i < entryCount; ++i) {
        const QByteArray hdr = f.read(46);
        if (hdr.size() != 46 || readU32(hdr.constData()) != CEN_SIGNATURE) {
            errorOut = tr("Corrupt ZIP central directory.");
            return false;
        }

        const quint16 flags = readU16(hdr.constData() + 8);
        const quint32 compressedSize = readU32(hdr.constData() + 20);
        const quint32 uncompressedSize = readU32(hdr.constData() + 24);
        const quint16 dosTime = readU16(hdr.constData() + 12);
        const quint16 dosDate = readU16(hdr.constData() + 14);
        const quint16 nameLen = readU16(hdr.constData() + 28);
        const quint16 extraLen = readU16(hdr.constData() + 30);
        const quint16 commentLen = readU16(hdr.constData() + 32);
        const quint16 method = readU16(hdr.constData() + 10);

        const QByteArray nameBytes = f.read(nameLen);
        if (nameBytes.size() != nameLen) {
            errorOut = tr("Failed to read entry name.");
            return false;
        }

        const bool utf8 = (flags & 0x0800) != 0;
        QString name = utf8 ? QString::fromUtf8(nameBytes) : QString::fromLocal8Bit(nameBytes);
        const bool isDir = name.endsWith('/');

        if (extraLen > 0 && !f.seek(f.pos() + extraLen)) {
            errorOut = tr("Invalid ZIP extra field.");
            return false;
        }
        if (commentLen > 0 && !f.seek(f.pos() + commentLen)) {
            errorOut = tr("Invalid ZIP comment.");
            return false;
        }

        QVariantMap entry;
        entry.insert("name", name);
        entry.insert("compressedSize", static_cast<qlonglong>(compressedSize));
        entry.insert("packedSize", static_cast<qlonglong>(compressedSize));
        entry.insert("uncompressedSize", static_cast<qlonglong>(uncompressedSize));
        entry.insert("isDirectory", isDir);
        entry.insert("method", static_cast<int>(method));
        const QDateTime modified = dosDateTimeToQDateTime(dosDate, dosTime);
        entry.insert("modified", modified.isValid() ? modified.toString(Qt::ISODate) : QString());
        outEntries.push_back(entry);

        if (!isDir) {
            ++files;
            totalUncompressed += uncompressedSize;
        }
    }

    setEntries(outEntries, totalUncompressed, files);
    return true;
}

#ifdef HAS_LIBARCHIVE
bool ZipArchiveReader::parseZipFileWithLibArchive(const QString &filePath, QString &errorOut)
{
    QFileInfo fi(filePath);
    if (!fi.exists() || !fi.isFile()) {
        errorOut = tr("File not found.");
        return false;
    }

    struct archive *a = archive_read_new();
    if (!a) {
        errorOut = tr("Failed to initialize libarchive.");
        return false;
    }
    archive_read_support_filter_all(a);
    archive_read_support_format_zip(a);

    if (archive_read_open_filename(a, QFile::encodeName(filePath).constData(), 10240) != ARCHIVE_OK) {
        errorOut = QString::fromUtf8(archive_error_string(a));
        archive_read_free(a);
        return false;
    }

    QVariantList outEntries;
    qlonglong totalUncompressed = 0;
    int files = 0;

    struct archive_entry *entry = nullptr;
    while (archive_read_next_header(a, &entry) == ARCHIVE_OK) {
        const char *path = archive_entry_pathname(entry);
        const qlonglong size = archive_entry_size(entry);
        const bool isDir = archive_entry_filetype(entry) == AE_IFDIR;

        QVariantMap map;
        map.insert("name", QString::fromUtf8(path ? path : ""));
        map.insert("compressedSize", static_cast<qlonglong>(-1));
        map.insert("packedSize", static_cast<qlonglong>(-1));
        map.insert("uncompressedSize", size > 0 ? size : 0);
        map.insert("isDirectory", isDir);
        map.insert("method", 0);
        const time_t mt = archive_entry_mtime(entry);
        if (mt > 0) {
            map.insert("modified", QDateTime::fromSecsSinceEpoch(mt).toString(Qt::ISODate));
        } else {
            map.insert("modified", QString());
        }
        outEntries.push_back(map);

        if (!isDir && size > 0) {
            totalUncompressed += size;
            ++files;
        } else if (!isDir) {
            ++files;
        }
        archive_read_data_skip(a);
    }

    archive_read_close(a);
    archive_read_free(a);
    setEntries(outEntries, totalUncompressed, files);
    return true;
}

bool ZipArchiveReader::startLibArchiveExtraction(const QString &zipPath, const QString &destinationPath, QString &errorOut)
{
    if (m_libArchiveWatcher.isRunning()) {
        errorOut = tr("Extraction already in progress.");
        return false;
    }
    m_workerExtractedBytes.store(0, std::memory_order_relaxed);
    m_workerExtractedFiles.store(0, std::memory_order_relaxed);
    m_pendingDestinationPath = destinationPath;
    auto future = QtConcurrent::run([this, zipPath, destinationPath]() {
        return extractWithLibArchiveWorker(zipPath, destinationPath);
    });
    m_libArchiveWatcher.setFuture(future);
    return true;
}

QPair<bool, QString> ZipArchiveReader::extractWithLibArchiveWorker(const QString &zipPath, const QString &destinationPath)
{
    struct archive *in = archive_read_new();
    struct archive *out = archive_write_disk_new();
    if (!in || !out) {
        if (in) archive_read_free(in);
        if (out) archive_write_free(out);
        return {false, tr("Failed to initialize libarchive extraction.")};
    }

    archive_read_support_filter_all(in);
    archive_read_support_format_zip(in);
    archive_write_disk_set_options(out, ARCHIVE_EXTRACT_TIME | ARCHIVE_EXTRACT_PERM | ARCHIVE_EXTRACT_SECURE_NODOTDOT);
    archive_write_disk_set_standard_lookup(out);

    if (archive_read_open_filename(in, QFile::encodeName(zipPath).constData(), 10240) != ARCHIVE_OK) {
        const QString msg = QString::fromUtf8(archive_error_string(in));
        archive_write_free(out);
        archive_read_free(in);
        return {false, msg};
    }

    QDir dest(destinationPath);
    struct archive_entry *entry = nullptr;
    int r = ARCHIVE_OK;
    while ((r = archive_read_next_header(in, &entry)) == ARCHIVE_OK) {
        const char *origPath = archive_entry_pathname(entry);
        QString rel = QString::fromUtf8(origPath ? origPath : "");
        rel.replace('\\', '/');
        const QString clean = QDir::cleanPath(rel);
        const bool bad = clean.startsWith("../") || clean == ".." || clean.startsWith("/") || clean.contains(":/");
        if (bad) {
            archive_read_data_skip(in);
            continue;
        }

        const QString absPath = dest.filePath(clean);
        QByteArray absPathUtf8 = QFile::encodeName(absPath);
        archive_entry_set_pathname(entry, absPathUtf8.constData());

        r = archive_write_header(out, entry);
        if (r != ARCHIVE_OK) {
            // continue if non-fatal entry error
            archive_read_data_skip(in);
            continue;
        }

        if (archive_entry_filetype(entry) != AE_IFDIR) {
            m_workerExtractedFiles.fetch_add(1, std::memory_order_relaxed);
        }

        const void *buff = nullptr;
        size_t size = 0;
        la_int64_t offset = 0;
        while (true) {
            r = archive_read_data_block(in, &buff, &size, &offset);
            if (r == ARCHIVE_EOF) {
                break;
            }
            if (r != ARCHIVE_OK) {
                archive_write_free(out);
                archive_read_close(in);
                archive_read_free(in);
                return {false, QString::fromUtf8(archive_error_string(in))};
            }
            r = archive_write_data_block(out, buff, size, offset);
            if (r != ARCHIVE_OK) {
                archive_write_free(out);
                archive_read_close(in);
                archive_read_free(in);
                return {false, QString::fromUtf8(archive_error_string(out))};
            }
            m_workerExtractedBytes.fetch_add(static_cast<qlonglong>(size), std::memory_order_relaxed);
        }

        archive_write_finish_entry(out);
    }

    if (r != ARCHIVE_EOF && r != ARCHIVE_OK) {
        const QString msg = QString::fromUtf8(archive_error_string(in));
        archive_write_free(out);
        archive_read_close(in);
        archive_read_free(in);
        return {false, msg};
    }

    archive_write_free(out);
    archive_read_close(in);
    archive_read_free(in);
    return {true, QString()};
}

bool ZipArchiveReader::extractSelectionWithLibArchive(const QString &zipPath, const QString &destinationPath,
                                                      const QString &entryPath, bool isDirectory, QString &errorOut)
{
    struct archive *in = archive_read_new();
    struct archive *out = archive_write_disk_new();
    if (!in || !out) {
        if (in) archive_read_free(in);
        if (out) archive_write_free(out);
        errorOut = tr("Failed to initialize libarchive.");
        return false;
    }

    archive_read_support_filter_all(in);
    archive_read_support_format_zip(in);
    archive_write_disk_set_options(out, ARCHIVE_EXTRACT_TIME | ARCHIVE_EXTRACT_PERM | ARCHIVE_EXTRACT_SECURE_NODOTDOT);
    archive_write_disk_set_standard_lookup(out);

    if (archive_read_open_filename(in, QFile::encodeName(zipPath).constData(), 10240) != ARCHIVE_OK) {
        errorOut = QString::fromUtf8(archive_error_string(in));
        archive_write_free(out);
        archive_read_free(in);
        return false;
    }

    const QString wanted = QDir::cleanPath(entryPath).replace('\\', '/');
    const QString wantedPrefix = wanted + "/";
    QDir dest(destinationPath);
    bool extractedAny = false;

    struct archive_entry *entry = nullptr;
    int r = ARCHIVE_OK;
    while ((r = archive_read_next_header(in, &entry)) == ARCHIVE_OK) {
        QString rel = QString::fromUtf8(archive_entry_pathname(entry) ? archive_entry_pathname(entry) : "");
        rel.replace('\\', '/');
        rel = QDir::cleanPath(rel);

        const bool match = isDirectory
                ? (rel == wanted || rel.startsWith(wantedPrefix))
                : (rel == wanted);
        if (!match) {
            archive_read_data_skip(in);
            continue;
        }

        const bool bad = rel.startsWith("../") || rel == ".." || rel.startsWith("/") || rel.contains(":/");
        if (bad) {
            archive_read_data_skip(in);
            continue;
        }

        const QString absPath = dest.filePath(rel);
        QByteArray absPathUtf8 = QFile::encodeName(absPath);
        archive_entry_set_pathname(entry, absPathUtf8.constData());

        r = archive_write_header(out, entry);
        if (r != ARCHIVE_OK) {
            archive_read_data_skip(in);
            continue;
        }
        extractedAny = true;

        const void *buff = nullptr;
        size_t size = 0;
        la_int64_t offset = 0;
        while (true) {
            r = archive_read_data_block(in, &buff, &size, &offset);
            if (r == ARCHIVE_EOF) break;
            if (r != ARCHIVE_OK) {
                errorOut = QString::fromUtf8(archive_error_string(in));
                archive_write_free(out);
                archive_read_close(in);
                archive_read_free(in);
                return false;
            }
            r = archive_write_data_block(out, buff, size, offset);
            if (r != ARCHIVE_OK) {
                errorOut = QString::fromUtf8(archive_error_string(out));
                archive_write_free(out);
                archive_read_close(in);
                archive_read_free(in);
                return false;
            }
        }
        archive_write_finish_entry(out);
    }

    archive_write_free(out);
    archive_read_close(in);
    archive_read_free(in);

    if (!extractedAny) {
        errorOut = tr("No matching entry found to drag.");
        return false;
    }
    return true;
}
#endif

