#ifndef EMBEDDEDSUBTITLEEXTRACTOR_H
#define EMBEDDEDSUBTITLEEXTRACTOR_H

#include <QObject>
#include <QString>
#include <QUrl>
#include <QVariantMap>
#include <QVariantList>
#include <QList>
#include <QMap>
#include <QPair>
#include <QMutex>

// Forward declarations
class FFmpegSubtitleExtractor;
class QProcess;

class EmbeddedSubtitleExtractor : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QVariantList subtitleTracks READ subtitleTracks NOTIFY subtitleTracksChanged)
    Q_PROPERTY(int activeSubtitleTrack READ activeSubtitleTrack WRITE setActiveSubtitleTrack NOTIFY activeSubtitleTrackChanged)
    Q_PROPERTY(QString currentSubtitleText READ currentSubtitleText NOTIFY currentSubtitleTextChanged)
    Q_PROPERTY(bool enabled READ enabled WRITE setEnabled NOTIFY enabledChanged)
    Q_PROPERTY(bool extracting READ extracting NOTIFY extractingChanged)
    
public:
    explicit EmbeddedSubtitleExtractor(QObject *parent = nullptr);
    ~EmbeddedSubtitleExtractor();
    
    // Extract subtitles from a video file (DEPRECATED - use readSubtitleAtPosition instead)
    Q_INVOKABLE void extractFromFile(const QUrl &videoUrl, int trackIndex = -1);
    
    // Read subtitle at specific position on-demand (fast, uses container index)
    Q_INVOKABLE QString readSubtitleAtPosition(const QUrl &videoUrl, int trackIndex, qint64 positionMs);
    
    // Update current subtitle text based on position (called from QML timer)
    Q_INVOKABLE void updateCurrentSubtitle(qint64 positionMs);
    
    // Extract subtitle stream info from video file
    Q_INVOKABLE void extractSubtitleInfo(const QUrl &videoUrl);
    
    // Properties
    QVariantList subtitleTracks() const { return m_subtitleTracks; }
    int activeSubtitleTrack() const { return m_activeSubtitleTrack; }
    void setActiveSubtitleTrack(int index);
    QString currentSubtitleText() const { return m_currentSubtitleText; }
    bool enabled() const { return m_enabled; }
    void setEnabled(bool enabled);
    bool extracting() const { return m_extracting; }
    
    // Get subtitle text for a specific position (in milliseconds)
    Q_INVOKABLE QString getSubtitleAtPosition(qint64 positionMs);
    
signals:
    void subtitleTracksChanged();
    void activeSubtitleTrackChanged();
    void currentSubtitleTextChanged();
    void enabledChanged();
    void extractingChanged();
    void extractionFinished(bool success);
    void extractionProgress(int percentage);
    
private:
    struct SubtitleEntry {
        qint64 startTime;  // in milliseconds
        qint64 endTime;    // in milliseconds
        QString text;      // subtitle text
    };
    
    // Parse SRT format subtitle data
    QList<SubtitleEntry> parseSRT(const QString &srtData);
    
    // Parse ASS/SSA format subtitle data
    QList<SubtitleEntry> parseASS(const QString &assData);
    
    // Check if FFmpeg is available
    bool isFFmpegAvailable() const;
    
    // Parse FFmpeg output format
    void parseFFmpegOutput(const QString &output, QVariantList &tracks);
    
    // Parse ffprobe output format
    void parseFFprobeOutput(const QString &output, QVariantList &tracks);
    
    // Get cache file path for a video file and track
    QString getCachePath(const QString &videoPath, int trackIndex) const;
    
    // CLI-based extraction (fallback when libraries not available)
    void extractFromFileCLI(const QString &localPath, int ffmpegStreamIndex, int targetTrack);
    
    QVariantList m_subtitleTracks;
    int m_activeSubtitleTrack;
    QString m_currentSubtitleText;
    bool m_enabled;
    bool m_extracting;
    
    // Store extracted subtitle data for each track
    QMap<int, QList<SubtitleEntry>> m_subtitleData;  // track index -> list of subtitle entries
    QUrl m_currentVideoUrl;
    
    // Cache for on-demand reading - stores subtitle chunks by time window
    QMap<QPair<int, qint64>, QList<SubtitleEntry>> m_subtitleCache;  // (trackIndex, windowStart) -> entries
    QProcess *m_currentProcess;  // Track current process to avoid overlapping calls
    
    // FFmpeg library-based extractor (fast, uses container index)
    FFmpegSubtitleExtractor *m_ffmpegExtractor;
    
    // Mutex to protect FFmpeg extractor from concurrent access
    QMutex m_extractionMutex;
};

#endif // EMBEDDEDSUBTITLEEXTRACTOR_H
