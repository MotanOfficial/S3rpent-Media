#pragma once

#include <QObject>
#include <QUrl>
#include <QVariantList>
#include <QProcess>
#include <QTimer>
#include <QElapsedTimer>
#include <QStringList>
#include <QFutureWatcher>
#include <QPair>
#include <atomic>
#include <QDateTime>

class ZipArchiveReader : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QUrl source READ source WRITE setSource NOTIFY sourceChanged)
    Q_PROPERTY(QVariantList entries READ entries NOTIFY entriesChanged)
    Q_PROPERTY(int fileCount READ fileCount NOTIFY fileCountChanged)
    Q_PROPERTY(qlonglong totalUncompressedSize READ totalUncompressedSize NOTIFY totalUncompressedSizeChanged)
    Q_PROPERTY(bool loaded READ loaded NOTIFY loadedChanged)
    Q_PROPERTY(QString errorString READ errorString NOTIFY errorStringChanged)
    Q_PROPERTY(bool extracting READ extracting NOTIFY extractingChanged)
    Q_PROPERTY(QString lastExtractedPath READ lastExtractedPath NOTIFY lastExtractedPathChanged)
    Q_PROPERTY(qlonglong extractedBytes READ extractedBytes NOTIFY extractedBytesChanged)
    Q_PROPERTY(int extractedFiles READ extractedFiles NOTIFY extractedFilesChanged)
    Q_PROPERTY(double progressPercent READ progressPercent NOTIFY progressPercentChanged)
    Q_PROPERTY(double speedBytesPerSecond READ speedBytesPerSecond NOTIFY speedBytesPerSecondChanged)
    Q_PROPERTY(int elapsedSeconds READ elapsedSeconds NOTIFY elapsedSecondsChanged)
    Q_PROPERTY(int etaSeconds READ etaSeconds NOTIFY etaSecondsChanged)

public:
    explicit ZipArchiveReader(QObject *parent = nullptr);

    QUrl source() const { return m_source; }
    void setSource(const QUrl &source);

    QVariantList entries() const { return m_entries; }
    int fileCount() const { return m_fileCount; }
    qlonglong totalUncompressedSize() const { return m_totalUncompressedSize; }
    bool loaded() const { return m_loaded; }
    QString errorString() const { return m_errorString; }
    bool extracting() const { return m_extracting; }
    QString lastExtractedPath() const { return m_lastExtractedPath; }
    qlonglong extractedBytes() const { return m_extractedBytes; }
    int extractedFiles() const { return m_extractedFiles; }
    double progressPercent() const { return m_progressPercent; }
    double speedBytesPerSecond() const { return m_speedBytesPerSecond; }
    int elapsedSeconds() const { return m_elapsedSeconds; }
    int etaSeconds() const { return m_etaSeconds; }

    Q_INVOKABLE void reload();
    Q_INVOKABLE bool extractAllTo(const QUrl &destinationUrl);
    Q_INVOKABLE QUrl prepareEntryForExternalDrag(const QString &entryPath, bool isDirectory);

signals:
    void sourceChanged();
    void entriesChanged();
    void fileCountChanged();
    void totalUncompressedSizeChanged();
    void loadedChanged();
    void errorStringChanged();
    void extractingChanged();
    void lastExtractedPathChanged();
    void extractedBytesChanged();
    void extractedFilesChanged();
    void progressPercentChanged();
    void speedBytesPerSecondChanged();
    void elapsedSecondsChanged();
    void etaSecondsChanged();
    void extractionFinished(bool success, const QString &message);

private:
    bool parseZipFile(const QString &filePath, QString &errorOut);
    static quint16 readU16(const char *p);
    static quint32 readU32(const char *p);
    static QDateTime dosDateTimeToQDateTime(quint16 dosDate, quint16 dosTime);

    void setEntries(const QVariantList &entries, qlonglong totalSize, int files);
    void setError(const QString &error);
    void setExtracting(bool extracting);
    bool startExtractionProcess(const QString &zipPath, const QString &destinationPath, QString &errorOut);
    void finishExtraction(bool success, const QString &message);
    void resetProgressStats();
    void updateProgressStats();
    void updateDerivedSpeedAndEta();
    void handleProcessProgressChunk(const QString &chunk);
    void setExtractedBytes(qlonglong value);
    void setExtractedFiles(int value);
    void setProgressPercent(double value);
    void setSpeedBytesPerSecond(double value);
    void setElapsedSeconds(int value);
    void setEtaSeconds(int value);
    static void calculateDirectoryStats(const QString &rootPath, qlonglong &bytesOut, int &filesOut);
    bool tryCustomExtractor(const QString &zipPath, const QString &destinationPath, QString &programOut, QStringList &argsOut, QString &errorOut) const;
    static QString replacePlaceholders(QString text, const QString &zipPath, const QString &destinationPath);
#ifdef HAS_LIBARCHIVE
    bool parseZipFileWithLibArchive(const QString &filePath, QString &errorOut);
    bool startLibArchiveExtraction(const QString &zipPath, const QString &destinationPath, QString &errorOut);
    QPair<bool, QString> extractWithLibArchiveWorker(const QString &zipPath, const QString &destinationPath);
    bool extractSelectionWithLibArchive(const QString &zipPath, const QString &destinationPath,
                                        const QString &entryPath, bool isDirectory, QString &errorOut);
#endif

    QUrl m_source;
    QVariantList m_entries;
    int m_fileCount = 0;
    qlonglong m_totalUncompressedSize = 0;
    bool m_loaded = false;
    QString m_errorString;
    bool m_extracting = false;
    QString m_lastExtractedPath;
    QProcess *m_extractProcess = nullptr;
    QString m_pendingDestinationPath;
    QTimer m_progressTimer;
    QElapsedTimer m_extractionElapsedTimer;
    qlonglong m_baselineBytes = 0;
    int m_baselineFiles = 0;
    qlonglong m_extractedBytes = 0;
    int m_extractedFiles = 0;
    double m_progressPercent = 0.0;
    double m_speedBytesPerSecond = 0.0;
    int m_elapsedSeconds = 0;
    int m_etaSeconds = -1;
    bool m_useDirectorySampling = true;
    bool m_useProcessProgress = false;
    QFutureWatcher<QPair<bool, QString>> m_libArchiveWatcher;
    std::atomic<qlonglong> m_workerExtractedBytes{0};
    std::atomic<int> m_workerExtractedFiles{0};
};

