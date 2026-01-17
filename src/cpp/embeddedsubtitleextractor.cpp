#include "embeddedsubtitleextractor.h"
#include "ffmpegsubtitleextractor.h"
#include <QProcess>
#include <QDebug>
#include <QFileInfo>
#include <QStandardPaths>
#include <QDir>
#include <QRegularExpression>
#include <QTimer>
#include <QCryptographicHash>
#include <QDateTime>
#include <QSharedPointer>
#include <QThread>
#include <QtConcurrent>
#include <QTextStream>
#include <QSet>
#include <algorithm>
#include <QMutexLocker>

EmbeddedSubtitleExtractor::EmbeddedSubtitleExtractor(QObject *parent)
    : QObject(parent)
    , m_activeSubtitleTrack(-1)
    , m_enabled(false)
    , m_extracting(false)
    , m_currentProcess(nullptr)
    , m_ffmpegExtractor(nullptr)
{
    // Initialize FFmpeg library extractor if available
    if (FFmpegSubtitleExtractor::isAvailable()) {
        m_ffmpegExtractor = new FFmpegSubtitleExtractor(this);
        qDebug() << "[EmbeddedSubtitleExtractor] ✅ FFmpeg libraries available - fast subtitle extraction enabled";
    } else {
        qDebug() << "[EmbeddedSubtitleExtractor] ⚠️ FFmpeg libraries not available - using CLI extraction (slower)";
    }
}

EmbeddedSubtitleExtractor::~EmbeddedSubtitleExtractor()
{
}

bool EmbeddedSubtitleExtractor::isFFmpegAvailable() const
{
    QStringList commands = QStringList() << "ffmpeg" << "ffmpeg.exe";
    
    for (const QString &command : commands) {
        QProcess process;
        process.start(command, QStringList() << "-version");
        if (process.waitForFinished(3000)) {
            if (process.exitCode() == 0) {
                return true;
            }
        }
    }
    
    return false;
}

void EmbeddedSubtitleExtractor::extractSubtitleInfo(const QUrl &videoUrl)
{
    if (!isFFmpegAvailable()) {
        qWarning() << "[EmbeddedSubtitleExtractor] FFmpeg not available";
        return;
    }
    
    const QString localPath = videoUrl.isLocalFile()
            ? videoUrl.toLocalFile()
            : videoUrl.toString(QUrl::PreferLocalFile);
    
    if (localPath.isEmpty() || !QFileInfo::exists(localPath)) {
        qWarning() << "[EmbeddedSubtitleExtractor] Invalid video file path:" << localPath;
        return;
    }
    
    // Use ffprobe to get stream information (better than ffmpeg for probing)
    // Fallback to ffmpeg if ffprobe is not available
    QString program = "ffprobe";
    #ifdef Q_OS_WIN
    program = "ffprobe.exe";
    #endif
    
    QStringList arguments;
    arguments << "-v" << "error"
              << "-select_streams" << "s"  // Select only subtitle streams
              << "-show_entries" << "stream=index,codec_name,codec_type"
              << "-of" << "default=noprint_wrappers=1:nokey=0"
              << localPath;
    
    QVariantList newTracks;
    
    QProcess process;
    process.setProcessChannelMode(QProcess::MergedChannels);
    process.start(program, arguments);
    
    bool finished = process.waitForFinished(10000);
    int exitCode = process.exitCode();
    
    // Try ffmpeg if ffprobe fails or is not available
    if (!finished || exitCode != 0) {
        qDebug() << "[EmbeddedSubtitleExtractor] ffprobe failed, trying ffmpeg...";
        program = "ffmpeg";
        #ifdef Q_OS_WIN
        program = "ffmpeg.exe";
        #endif
        
        arguments.clear();
        arguments << "-i" << localPath
                  << "-hide_banner";
        // Don't use -loglevel error, as it suppresses stream information
        // Stream info is output to stderr before the error about missing output file
        
        process.setProcessChannelMode(QProcess::SeparateChannels);
        process.start(program, arguments);
        finished = process.waitForFinished(10000);
        
        if (!finished) {
            qWarning() << "[EmbeddedSubtitleExtractor] FFmpeg probe timed out";
            return;
        }
        
        // FFmpeg outputs stream info to stderr even when it exits with error
        QByteArray output = process.readAllStandardError();
        QString outputStr = QString::fromUtf8(output);
        
        qDebug() << "[EmbeddedSubtitleExtractor] FFmpeg stderr length:" << outputStr.length();
        
        // Parse FFmpeg output format
        parseFFmpegOutput(outputStr, newTracks);
    } else {
        // Parse ffprobe output format
        QByteArray output = process.readAllStandardOutput();
        QString outputStr = QString::fromUtf8(output);
        
        qDebug() << "[EmbeddedSubtitleExtractor] ffprobe output length:" << outputStr.length();
        if (outputStr.length() < 500) {
            qDebug() << "[EmbeddedSubtitleExtractor] ffprobe output:" << outputStr;
        }
        
        parseFFprobeOutput(outputStr, newTracks);
    }
    
    if (m_subtitleTracks != newTracks) {
        m_subtitleTracks = newTracks;
        emit subtitleTracksChanged();
    }
}

void EmbeddedSubtitleExtractor::extractFromFile(const QUrl &videoUrl, int trackIndex)
{
    // Prevent concurrent extractions
    if (m_extracting) {
        qDebug() << "[EmbeddedSubtitleExtractor] Extraction already in progress, ignoring duplicate request for track" << trackIndex;
        return;
    }
    
    if (!isFFmpegAvailable()) {
        qWarning() << "[EmbeddedSubtitleExtractor] FFmpeg not available";
        emit extractionFinished(false);
        return;
    }
    
    const QString localPath = videoUrl.isLocalFile()
            ? videoUrl.toLocalFile()
            : videoUrl.toString(QUrl::PreferLocalFile);
    
    if (localPath.isEmpty() || !QFileInfo::exists(localPath)) {
        qWarning() << "[EmbeddedSubtitleExtractor] Invalid video file path:" << localPath;
        emit extractionFinished(false);
        return;
    }
    
    m_currentVideoUrl = videoUrl;
    
    // First, extract subtitle stream info if not already done
    if (m_subtitleTracks.isEmpty()) {
        qDebug() << "[EmbeddedSubtitleExtractor] No tracks cached, extracting subtitle info...";
        extractSubtitleInfo(videoUrl);
    }
    
    // If no tracks found, return
    if (m_subtitleTracks.isEmpty()) {
        qWarning() << "[EmbeddedSubtitleExtractor] No subtitle tracks found in video after extraction";
        qWarning() << "[EmbeddedSubtitleExtractor] Video path:" << localPath;
        emit extractionFinished(false);
        return;
    }
    
    // Use trackIndex or active track
    int targetTrack = (trackIndex >= 0) ? trackIndex : m_activeSubtitleTrack;
    if (targetTrack < 0 || targetTrack >= m_subtitleTracks.size()) {
        targetTrack = 0;  // Default to first track
    }
    
    // Check if subtitles are already extracted and cached in memory
    if (m_subtitleData.contains(targetTrack) && !m_subtitleData[targetTrack].isEmpty()) {
        qDebug() << "[EmbeddedSubtitleExtractor] ✅ Subtitles already cached in memory for track" << targetTrack << "- skipping extraction";
        emit extractionFinished(true);
        return;
    }
    
    // Check if subtitles are cached on disk
    QString cachePath = getCachePath(localPath, targetTrack);
    if (QFileInfo::exists(cachePath)) {
        qDebug() << "[EmbeddedSubtitleExtractor] 📁 Loading subtitles from disk cache:" << cachePath;
        QFile file(cachePath);
        if (file.open(QIODevice::ReadOnly | QIODevice::Text)) {
            QTextStream in(&file);
            QString srtData = in.readAll();
            file.close();
            
            QList<SubtitleEntry> entries = parseSRT(srtData);
            
            // If cache is empty or invalid, delete it and extract fresh
            if (entries.isEmpty()) {
                qWarning() << "[EmbeddedSubtitleExtractor] ⚠️ Cache file is empty or invalid, deleting and extracting fresh";
                QFile::remove(cachePath);
                // Fall through to extraction below
            } else {
                // Sort entries by start time to ensure correct lookup
                std::sort(entries.begin(), entries.end(), [](const SubtitleEntry &a, const SubtitleEntry &b) {
                    return a.startTime < b.startTime;
                });
                m_subtitleData[targetTrack] = entries;
                
                qDebug() << "[EmbeddedSubtitleExtractor] ✅ Loaded" << entries.size() << "subtitle entries from cache for track" << targetTrack;
                emit extractionFinished(true);
                return;
            }
        } else {
            // Cache file exists but can't be opened - delete it and extract fresh
            qWarning() << "[EmbeddedSubtitleExtractor] ⚠️ Cache file exists but can't be opened, deleting and extracting fresh";
            QFile::remove(cachePath);
        }
    }
    
    qDebug() << "[EmbeddedSubtitleExtractor] Found" << m_subtitleTracks.size() << "subtitle tracks, extracting track" << trackIndex;
    
    QVariantMap trackInfo = m_subtitleTracks[targetTrack].toMap();
    int ffmpegStreamIndex = trackInfo["ffmpegIndex"].toInt();
    
    // Try FFmpeg library extraction first (FAST - uses container index!)
    if (m_ffmpegExtractor && m_ffmpegExtractor->isAvailable()) {
        qDebug() << "[EmbeddedSubtitleExtractor] 🚀 Using FFmpeg libraries for FAST extraction (stream" << ffmpegStreamIndex << ")";
        
        m_extracting = true;
        emit extractingChanged();
        emit extractionProgress(0);
        
        // Extract in background thread to avoid blocking UI
        EmbeddedSubtitleExtractor *self = this;
        QFuture<void> future = QtConcurrent::run([self, localPath, ffmpegStreamIndex, targetTrack]() {
            QMutexLocker locker(&self->m_extractionMutex);
            
            // Extract subtitles incrementally using callback (emits as found, not all at once!)
            // Use a shared pointer to safely pass entries between threads
            QSharedPointer<QList<EmbeddedSubtitleExtractor::SubtitleEntry>> entriesShared(new QList<EmbeddedSubtitleExtractor::SubtitleEntry>());
            QSharedPointer<QMutex> entriesMutex(new QMutex());
            qint64 lastUpdateTime = QDateTime::currentMSecsSinceEpoch();
            int processedCount = 0;
            
            // Callback that gets called for each subtitle as it's found - updates immediately!
            FFmpegSubtitleExtractor::SubtitleCallback callback = [self, targetTrack, entriesShared, entriesMutex, &lastUpdateTime, &processedCount](const FFmpegSubtitleExtractor::SubtitleEntry &libEntry) {
                // Convert to our format
                EmbeddedSubtitleExtractor::SubtitleEntry entry;
                entry.startTime = libEntry.startTime;
                entry.endTime = libEntry.endTime;
                entry.text = libEntry.text;
                
                // Add to shared list (thread-safe)
                {
                    QMutexLocker lock(entriesMutex.data());
                    entriesShared->append(entry);
                    processedCount = entriesShared->size();
                }
                
                // Emit update immediately for first 20 subtitles, then every 5 or every 50ms
                bool shouldUpdate = (processedCount <= 20) || (processedCount % 5 == 0);
                qint64 now = QDateTime::currentMSecsSinceEpoch();
                if (!shouldUpdate) {
                    shouldUpdate = ((now - lastUpdateTime) > 50); // Every 50ms
                }
                
                if (shouldUpdate) {
                    // Copy entries (NO SORTING - subtitles arrive in time order, sorting is O(n log n) waste!)
                    QList<EmbeddedSubtitleExtractor::SubtitleEntry> entriesCopy;
                    {
                        QMutexLocker lock(entriesMutex.data());
                        entriesCopy = *entriesShared;
                    }
                    
                    // Emit update on main thread immediately - subtitles are NOW available for rendering!
                    QMetaObject::invokeMethod(self, [self, entriesCopy, targetTrack, processedCount]() {
                        self->m_subtitleData[targetTrack] = entriesCopy;
                        if (processedCount % 50 == 0 || processedCount <= 20) {
                            qDebug() << "[EmbeddedSubtitleExtractor] 📊 Incremental update: now have" << processedCount << "subtitles for track" << targetTrack << "- AVAILABLE FOR RENDERING";
                        }
                    }, Qt::QueuedConnection);
                    lastUpdateTime = now;
                }
            };
            
            // Extract with incremental callback - subtitles are emitted as they're found!
            bool success = self->m_ffmpegExtractor->extractSubtitlesIncremental(localPath, ffmpegStreamIndex, callback);
            
            // Final update with all entries (sorted)
            QList<EmbeddedSubtitleExtractor::SubtitleEntry> finalEntries;
            {
                QMutexLocker lock(entriesMutex.data());
                finalEntries = *entriesShared;
            }
            
            if (success && !finalEntries.isEmpty()) {
                // Final sort (entries were already updated incrementally, but ensure completeness)
                std::sort(finalEntries.begin(), finalEntries.end(), [](const EmbeddedSubtitleExtractor::SubtitleEntry &a, const EmbeddedSubtitleExtractor::SubtitleEntry &b) {
                    return a.startTime < b.startTime;
                });
                
                // Final update on main thread (entries were already updated incrementally, but ensure final state)
                QMetaObject::invokeMethod(self, [self, finalEntries, targetTrack, localPath, success]() {
                    self->m_subtitleData[targetTrack] = finalEntries;
                    
                    // Save to cache
                    QString cachePath = self->getCachePath(localPath, targetTrack);
                    QFileInfo cacheInfo(cachePath);
                    QDir cacheDir = cacheInfo.absoluteDir();
                    if (!cacheDir.exists()) {
                        cacheDir.mkpath(".");
                    }
                    
                    // Write cache as SRT
                    QFile cacheFile(cachePath);
                    if (cacheFile.open(QIODevice::WriteOnly | QIODevice::Text)) {
                        QTextStream out(&cacheFile);
                        int index = 1;
                        for (const EmbeddedSubtitleExtractor::SubtitleEntry &entry : finalEntries) {
                            out << index++ << "\n";
                            int startH = entry.startTime / 3600000;
                            int startM = (entry.startTime % 3600000) / 60000;
                            int startS = (entry.startTime % 60000) / 1000;
                            int startMs = entry.startTime % 1000;
                            int endH = entry.endTime / 3600000;
                            int endM = (entry.endTime % 3600000) / 60000;
                            int endS = (entry.endTime % 60000) / 1000;
                            int endMs = entry.endTime % 1000;
                            out << QString("%1:%2:%3,%4 --> %5:%6:%7,%8\n")
                                   .arg(startH, 2, 10, QChar('0'))
                                   .arg(startM, 2, 10, QChar('0'))
                                   .arg(startS, 2, 10, QChar('0'))
                                   .arg(startMs, 3, 10, QChar('0'))
                                   .arg(endH, 2, 10, QChar('0'))
                                   .arg(endM, 2, 10, QChar('0'))
                                   .arg(endS, 2, 10, QChar('0'))
                                   .arg(endMs, 3, 10, QChar('0')) << "\n";
                            out << entry.text << "\n\n";
                        }
                        cacheFile.close();
                    }
                    
                    qDebug() << "[EmbeddedSubtitleExtractor] ✅ FAST extraction complete:" << finalEntries.size() << "entries";
                    
                    self->m_extracting = false;
                    emit self->extractingChanged();
                    emit self->extractionFinished(success);
                }, Qt::QueuedConnection);
            } else {
                qWarning() << "[EmbeddedSubtitleExtractor] Library extraction failed, falling back to CLI";
                // Reset extracting flag and fall through to CLI extraction
                QMetaObject::invokeMethod(self, [self, localPath, ffmpegStreamIndex, targetTrack]() {
                    self->m_extracting = false;
                    emit self->extractingChanged();
                    self->extractFromFileCLI(localPath, ffmpegStreamIndex, targetTrack);
                }, Qt::QueuedConnection);
            }
        });
        
        return;
    }
    
    // Fallback to CLI extraction (slower)
    extractFromFileCLI(localPath, ffmpegStreamIndex, targetTrack);
}

void EmbeddedSubtitleExtractor::extractFromFileCLI(const QString &localPath, int ffmpegStreamIndex, int targetTrack)
{
    m_extracting = true;
    emit extractingChanged();
    emit extractionProgress(0);
    
    QString program = "ffmpeg";
    #ifdef Q_OS_WIN
    program = "ffmpeg.exe";
    #endif
    
    qDebug() << "[EmbeddedSubtitleExtractor] Using CLI extraction (slower) for stream" << ffmpegStreamIndex << "track" << targetTrack;
    
    // Output directly to stdout instead of a file - much faster, no disk I/O!
    QStringList arguments;
    arguments << "-i" << localPath
              << "-map" << QString("0:%1").arg(ffmpegStreamIndex)  // Map stream using absolute stream index
              << "-c:s" << "srt"                                    // Convert to SRT
              << "-threads" << "0"                                  // Use all available CPU threads
              << "-loglevel" << "error"
              << "-hide_banner"
              << "-nostdin"                                         // Don't wait for stdin (faster)
              << "-f" << "srt"                                      // Force SRT format
              << "-";                                               // Output to stdout instead of file
    
    qDebug() << "[EmbeddedSubtitleExtractor] Starting FFmpeg process with arguments:" << arguments;
    
    QProcess *process = new QProcess(this);
    
    // Store subtitle data in a shared pointer to avoid lambda capture issues
    QSharedPointer<QString> srtData(new QString());
    
    // Read subtitle data from stdout as it comes in (streaming)
    connect(process, &QProcess::readyReadStandardOutput, [this, process, srtData]() {
        QByteArray data = process->readAllStandardOutput();
        *srtData += QString::fromUtf8(data);
    });
    
    // Add error handler
    connect(process, &QProcess::errorOccurred, [this, process](QProcess::ProcessError error) {
        qWarning() << "[EmbeddedSubtitleExtractor] ❌ FFmpeg process error:" << error << process->errorString();
        m_extracting = false;
        emit extractingChanged();
        emit extractionFinished(false);
        process->deleteLater();
    });
    
    connect(process, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
            [this, process, targetTrack, ffmpegStreamIndex, localPath, srtData](int exitCode, QProcess::ExitStatus) {
        qDebug() << "[EmbeddedSubtitleExtractor] FFmpeg process finished with exit code:" << exitCode;
        m_extracting = false;
        emit extractingChanged();
        
        if (exitCode == 0 && !srtData->isEmpty()) {
            // Parse SRT data directly from stdout (no file I/O!)
            QList<SubtitleEntry> entries = parseSRT(*srtData);
            // Sort entries by start time to ensure correct lookup
            std::sort(entries.begin(), entries.end(), [](const SubtitleEntry &a, const SubtitleEntry &b) {
                return a.startTime < b.startTime;
            });
            m_subtitleData[targetTrack] = entries;
            
            qDebug() << "[EmbeddedSubtitleExtractor] ✅ Loaded" << entries.size() << "subtitle entries for track" << targetTrack << "(stream" << ffmpegStreamIndex << ")";
            
            // Save to disk cache for future use (instant loading next time)
            QString cachePath = getCachePath(localPath, targetTrack);
            QFileInfo cacheInfo(cachePath);
            QDir cacheDir = cacheInfo.absoluteDir();
            if (!cacheDir.exists()) {
                cacheDir.mkpath(".");
            }
            
            QFile cacheFile(cachePath);
            if (cacheFile.open(QIODevice::WriteOnly | QIODevice::Text)) {
                QTextStream out(&cacheFile);
                out << *srtData;
                cacheFile.close();
                qDebug() << "[EmbeddedSubtitleExtractor] 💾 Saved subtitles to cache:" << cachePath;
            }
            
            emit extractionFinished(true);
        } else {
            QByteArray errorOutput = process->readAllStandardError();
            qWarning() << "[EmbeddedSubtitleExtractor] ❌ FFmpeg loading failed with exit code:" << exitCode;
            if (!errorOutput.isEmpty()) {
                qWarning() << "[EmbeddedSubtitleExtractor] FFmpeg error:" << QString::fromUtf8(errorOutput);
            }
            if (srtData->isEmpty()) {
                qWarning() << "[EmbeddedSubtitleExtractor] No subtitle data received from FFmpeg";
            }
            emit extractionFinished(false);
        }
        
        process->deleteLater();
    });
    
    qDebug() << "[EmbeddedSubtitleExtractor] Starting FFmpeg process...";
    process->start(program, arguments);
    
    if (!process->waitForStarted(5000)) {
        qWarning() << "[EmbeddedSubtitleExtractor] ❌ Failed to start FFmpeg:" << process->errorString();
        m_extracting = false;
        emit extractingChanged();
        emit extractionFinished(false);
        process->deleteLater();
        return;
    } else {
        qDebug() << "[EmbeddedSubtitleExtractor] ✅ FFmpeg process started successfully, PID:" << process->processId();
        qDebug() << "[EmbeddedSubtitleExtractor] Waiting for extraction to complete (this may take a while for large files)...";
        emit extractionProgress(50);
    }
}

QList<EmbeddedSubtitleExtractor::SubtitleEntry> EmbeddedSubtitleExtractor::parseSRT(const QString &srtData)
{
    QList<SubtitleEntry> entries;
    QStringList lines = srtData.split('\n');
    
    SubtitleEntry currentEntry;
    bool inSubtitleBlock = false;
    
    for (int i = 0; i < lines.size(); ++i) {
        QString line = lines[i].trimmed();
        
        // Skip empty lines (they separate subtitle blocks)
        if (line.isEmpty()) {
            if (inSubtitleBlock && !currentEntry.text.isEmpty()) {
                entries.append(currentEntry);
                currentEntry = SubtitleEntry();
            }
            inSubtitleBlock = false;
            continue;
        }
        
        // Check if line is a sequence number (just digits)
        if (QRegularExpression(R"(\d+)").match(line).hasMatch() && 
            line.toInt() > 0 && 
            (i == 0 || lines[i-1].trimmed().isEmpty())) {
            inSubtitleBlock = true;
            continue;
        }
        
        // Check if line is a timestamp (contains -->)
        if (line.contains("-->")) {
            QStringList parts = line.split("-->");
            if (parts.size() == 2) {
                // Parse start time: "00:00:00,000" or "00:00:00.000"
                QString startStr = parts[0].trimmed().replace(',', '.');
                QStringList startParts = startStr.split(':');
                if (startParts.size() == 3) {
                    int hours = startParts[0].toInt();
                    int minutes = startParts[1].toInt();
                    QStringList secondsParts = startParts[2].split('.');
                    int seconds = secondsParts[0].toInt();
                    int milliseconds = (secondsParts.size() > 1) ? secondsParts[1].toInt() : 0;
                    currentEntry.startTime = (hours * 3600 + minutes * 60 + seconds) * 1000 + milliseconds;
                }
                
                // Parse end time
                QString endStr = parts[1].trimmed().replace(',', '.');
                QStringList endParts = endStr.split(':');
                if (endParts.size() == 3) {
                    int hours = endParts[0].toInt();
                    int minutes = endParts[1].toInt();
                    QStringList secondsParts = endParts[2].split('.');
                    int seconds = secondsParts[0].toInt();
                    int milliseconds = (secondsParts.size() > 1) ? secondsParts[1].toInt() : 0;
                    currentEntry.endTime = (hours * 3600 + minutes * 60 + seconds) * 1000 + milliseconds;
                }
            }
            continue;
        }
        
        // This is subtitle text
        if (inSubtitleBlock) {
            if (!currentEntry.text.isEmpty()) {
                currentEntry.text += "\n";
            }
            // Strip ASS formatting codes like {\an8}, {\b1}, etc.
            QString cleanedLine = line;
            cleanedLine.remove(QRegularExpression(R"(\{[^}]*\})"));
            // Convert ASS newline codes to actual newlines
            cleanedLine.replace("\\N", "\n");
            cleanedLine.replace("\\n", "\n");
            currentEntry.text += cleanedLine;
        }
    }
    
    // Add last entry if exists
    if (!currentEntry.text.isEmpty()) {
        entries.append(currentEntry);
    }
    
    return entries;
}

QList<EmbeddedSubtitleExtractor::SubtitleEntry> EmbeddedSubtitleExtractor::parseASS(const QString &assData)
{
    QList<SubtitleEntry> entries;
    QStringList lines = assData.split('\n');
    
    bool inEventsSection = false;
    
    for (const QString &line : lines) {
        QString trimmed = line.trimmed();
        
        if (trimmed.startsWith("[Events]")) {
            inEventsSection = true;
            continue;
        }
        
        if (inEventsSection && trimmed.startsWith("Dialogue:")) {
            // Parse ASS dialogue line: Dialogue: Marked, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
            QStringList parts = trimmed.split(',');
            if (parts.size() >= 10) {
                SubtitleEntry entry;
                
                // Parse start time (format: H:MM:SS.cc)
                QString startStr = parts[1].trimmed();
                QStringList startParts = startStr.split(':');
                if (startParts.size() == 3) {
                    int hours = startParts[0].toInt();
                    int minutes = startParts[1].toInt();
                    QStringList secondsParts = startParts[2].split('.');
                    int seconds = secondsParts[0].toInt();
                    int centiseconds = (secondsParts.size() > 1) ? secondsParts[1].toInt() : 0;
                    entry.startTime = (hours * 3600 + minutes * 60 + seconds) * 1000 + centiseconds * 10;
                }
                
                // Parse end time
                QString endStr = parts[2].trimmed();
                QStringList endParts = endStr.split(':');
                if (endParts.size() == 3) {
                    int hours = endParts[0].toInt();
                    int minutes = endParts[1].toInt();
                    QStringList secondsParts = endParts[2].split('.');
                    int seconds = secondsParts[0].toInt();
                    int centiseconds = (secondsParts.size() > 1) ? secondsParts[1].toInt() : 0;
                    entry.endTime = (hours * 3600 + minutes * 60 + seconds) * 1000 + centiseconds * 10;
                }
                
                // Text is everything after the 9th comma
                QString rawText = parts.mid(9).join(',').trimmed();
                // Strip ASS formatting codes like {\an8}, {\b1}, etc.
                rawText.remove(QRegularExpression(R"(\{[^}]*\})"));
                entry.text = rawText;
                
                entries.append(entry);
            }
        }
    }
    
    return entries;
}

void EmbeddedSubtitleExtractor::parseFFmpegOutput(const QString &output, QVariantList &tracks)
{
    // Improved regex to match subtitle streams - handles various formats
    // Examples: "Stream #0:5(eng): Subtitle: subrip" or "Stream #0:7: Subtitle: ass"
    QRegularExpression streamRegex(R"(Stream\s+#(\d+):(\d+)(?:\((\w+)\))?.*?Subtitle:\s*(\w+))");
    QRegularExpressionMatchIterator matches = streamRegex.globalMatch(output);
    
    int trackIndex = 0;
    while (matches.hasNext()) {
        QRegularExpressionMatch match = matches.next();
        QString codec = match.captured(4);  // Subtitle codec
        QString language = match.captured(3);  // Language code (optional)
        int streamIndex = match.captured(2).toInt();
        
        QVariantMap trackMap;
        trackMap["index"] = trackIndex;
        trackMap["ffmpegIndex"] = streamIndex;
        trackMap["codec"] = codec;
        QString title = QString("Track %1 (%2)").arg(trackIndex + 1).arg(codec);
        if (!language.isEmpty()) {
            title += " [" + language + "]";
        }
        trackMap["title"] = title;
        trackMap["language"] = language;
        tracks.append(trackMap);
        
        qDebug() << "[EmbeddedSubtitleExtractor] Found subtitle track:" << trackIndex << "codec:" << codec << "language:" << language << "stream:" << streamIndex;
        
        trackIndex++;
    }
    
    qDebug() << "[EmbeddedSubtitleExtractor] Total subtitle tracks found (FFmpeg):" << tracks.size();
}

void EmbeddedSubtitleExtractor::parseFFprobeOutput(const QString &output, QVariantList &tracks)
{
    // ffprobe output format with -of default=noprint_wrappers=1:nokey=0:
    // Each stream has 3 lines:
    // index=4\r\ncodec_name=subrip\r\ncodec_type=subtitle\r\nindex=5\r\n...
    
    QStringList lines = output.split(QRegularExpression(R"(\r?\n)"), Qt::SkipEmptyParts);
    
    qDebug() << "[EmbeddedSubtitleExtractor] Parsing" << lines.size() << "lines from ffprobe output";
    
    int trackIndex = 0;
    QMap<int, QString> streamCodecs;  // stream index -> codec name
    
    // Parse as key-value pairs, grouping by stream
    int currentStreamIndex = -1;
    QString currentCodec;
    
    for (const QString &line : lines) {
        QString trimmedLine = line.trimmed();
        
        if (trimmedLine.startsWith("index=")) {
            // Save previous stream if it was a subtitle
            if (currentStreamIndex >= 0 && !currentCodec.isEmpty()) {
                streamCodecs[currentStreamIndex] = currentCodec;
                qDebug() << "[EmbeddedSubtitleExtractor] Found subtitle stream:" << currentStreamIndex << "codec:" << currentCodec;
            }
            
            // Start new stream
            QRegularExpression indexRegex(R"(index=(\d+))");
            QRegularExpressionMatch match = indexRegex.match(trimmedLine);
            if (match.hasMatch()) {
                currentStreamIndex = match.captured(1).toInt();
                currentCodec.clear();
            }
        } else if (trimmedLine.startsWith("codec_name=")) {
            QRegularExpression codecRegex(R"(codec_name=(\w+))");
            QRegularExpressionMatch match = codecRegex.match(trimmedLine);
            if (match.hasMatch()) {
                currentCodec = match.captured(1);
            }
        } else if (trimmedLine.startsWith("codec_type=subtitle")) {
            // This confirms it's a subtitle stream, but we already have index and codec
            // The stream will be saved when we encounter the next index= line
        }
    }
    
    // Don't forget the last stream
    if (currentStreamIndex >= 0 && !currentCodec.isEmpty()) {
        streamCodecs[currentStreamIndex] = currentCodec;
        qDebug() << "[EmbeddedSubtitleExtractor] Found subtitle stream:" << currentStreamIndex << "codec:" << currentCodec;
    }
    
    // Create track entries in order
    QList<int> sortedStreams = streamCodecs.keys();
    std::sort(sortedStreams.begin(), sortedStreams.end());
    
    for (int streamIndex : sortedStreams) {
        QString codec = streamCodecs[streamIndex];
        
        QVariantMap trackMap;
        trackMap["index"] = trackIndex;
        trackMap["ffmpegIndex"] = streamIndex;
        trackMap["codec"] = codec;
        trackMap["title"] = QString("Track %1 (%2)").arg(trackIndex + 1).arg(codec);
        trackMap["language"] = "";
        tracks.append(trackMap);
        
        qDebug() << "[EmbeddedSubtitleExtractor] Added subtitle track:" << trackIndex << "codec:" << codec << "stream:" << streamIndex;
        
        trackIndex++;
    }
    
    qDebug() << "[EmbeddedSubtitleExtractor] Total subtitle tracks found (ffprobe):" << tracks.size();
}

void EmbeddedSubtitleExtractor::setActiveSubtitleTrack(int index)
{
    if (m_activeSubtitleTrack != index) {
        m_activeSubtitleTrack = index;
        emit activeSubtitleTrackChanged();
        
        // Extract subtitles for the selected track if not already extracted
        if (m_enabled && !m_currentVideoUrl.isEmpty() && !m_subtitleData.contains(index)) {
            extractFromFile(m_currentVideoUrl, index);
        }
    }
}

void EmbeddedSubtitleExtractor::setEnabled(bool enabled)
{
    if (m_enabled != enabled) {
        m_enabled = enabled;
        emit enabledChanged();
        
        if (!enabled) {
            m_currentSubtitleText.clear();
            emit currentSubtitleTextChanged();
        }
    }
}

QString EmbeddedSubtitleExtractor::getSubtitleAtPosition(qint64 positionMs)
{
    if (!m_enabled || m_activeSubtitleTrack < 0) {
        return "";
    }
    
    // REMOVED: Don't block rendering during extraction - subtitles are available incrementally!
    // if (m_extracting) { return ""; }  // ❌ THIS WAS THE BUG
    
    if (!m_subtitleData.contains(m_activeSubtitleTrack)) {
        // Only log once per track to avoid spam
        static QSet<int> loggedMissingTracks;
        if (!loggedMissingTracks.contains(m_activeSubtitleTrack)) {
            qDebug() << "[EmbeddedSubtitleExtractor] No subtitle data for track" << m_activeSubtitleTrack << "(extraction may be in progress)";
            loggedMissingTracks.insert(m_activeSubtitleTrack);
        }
        return "";
    }
    
    const QList<SubtitleEntry> &entries = m_subtitleData[m_activeSubtitleTrack];
    
    if (entries.isEmpty()) {
        qDebug() << "[EmbeddedSubtitleExtractor] Subtitle data is empty for track" << m_activeSubtitleTrack;
        return "";
    }
    
    // Debug: show first and last entry times (only once)
    static QSet<int> loggedTracks;
    if (!loggedTracks.contains(m_activeSubtitleTrack) && !entries.isEmpty()) {
        qDebug() << "[EmbeddedSubtitleExtractor] Track" << m_activeSubtitleTrack << "has" << entries.size() << "entries";
        qDebug() << "[EmbeddedSubtitleExtractor] First entry:" << entries.first().startTime << "-" << entries.first().endTime << "ms:" << entries.first().text.left(30);
        qDebug() << "[EmbeddedSubtitleExtractor] Last entry:" << entries.last().startTime << "-" << entries.last().endTime << "ms";
        // Debug: show all entry times
        for (int i = 0; i < entries.size() && i < 5; ++i) {
            qDebug() << "[EmbeddedSubtitleExtractor] Entry" << i << ":" << entries[i].startTime << "-" << entries[i].endTime << "ms";
        }
        if (entries.size() > 5) {
            qDebug() << "[EmbeddedSubtitleExtractor] ... and" << (entries.size() - 5) << "more entries";
        }
        loggedTracks.insert(m_activeSubtitleTrack);
    }
    
    // Linear search through sorted entries (should be fast enough for typical subtitle counts)
    // Note: We search all entries because subtitles can overlap or have gaps
    for (const SubtitleEntry &entry : entries) {
        if (positionMs >= entry.startTime && positionMs <= entry.endTime) {
            return entry.text;
        }
    }
    
    return "";
}

void EmbeddedSubtitleExtractor::updateCurrentSubtitle(qint64 positionMs)
{
    // Allow updates during extraction - we now have incremental data
    QString newText = getSubtitleAtPosition(positionMs);
    
    if (m_currentSubtitleText != newText) {
        m_currentSubtitleText = newText;
        // Only log when subtitle actually changes (not on every empty check)
        if (!newText.isEmpty()) {
            qDebug() << "[EmbeddedSubtitleExtractor] Updated subtitle at" << positionMs << "ms:" << newText.left(50);
        }
        emit currentSubtitleTextChanged();
    }
}

QString EmbeddedSubtitleExtractor::readSubtitleAtPosition(const QUrl &videoUrl, int trackIndex, qint64 positionMs)
{
    // First check if we have this subtitle in our cached data (instant lookup)
    if (m_subtitleData.contains(trackIndex) && !m_subtitleData[trackIndex].isEmpty()) {
        const QList<SubtitleEntry> &entries = m_subtitleData[trackIndex];
        for (const SubtitleEntry &entry : entries) {
            if (positionMs >= entry.startTime && positionMs <= entry.endTime) {
                return entry.text;
            }
        }
    }
    
    // If not in cache, trigger background loading (but don't block)
    // This is called from the timer, so we can't wait - just trigger async load
    if (!m_currentProcess || m_currentProcess->state() == QProcess::NotRunning) {
        // Trigger background extraction of entire track if not already done
        if (!m_subtitleData.contains(trackIndex) || m_subtitleData[trackIndex].isEmpty()) {
            extractFromFile(videoUrl, trackIndex);
        }
    }
    
    return "";  // Will be populated once extraction completes
}

QString EmbeddedSubtitleExtractor::getCachePath(const QString &videoPath, int trackIndex) const
{
    // Create cache directory in AppData/Local
    QString cacheDir = QStandardPaths::writableLocation(QStandardPaths::CacheLocation);
    cacheDir += "/subtitle_cache";
    
    // Generate a hash of the video file path to create a unique, safe filename
    QCryptographicHash hash(QCryptographicHash::Sha256);
    hash.addData(videoPath.toUtf8());
    QString hashStr = hash.result().toHex().left(16);  // Use first 16 chars of hash
    
    // Create filename: hash_trackIndex.srt
    QString filename = QString("%1_track%2.srt").arg(hashStr).arg(trackIndex);
    
    return cacheDir + "/" + filename;
}
