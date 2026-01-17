#ifndef FFMPEGSUBTITLEEXTRACTOR_H
#define FFMPEGSUBTITLEEXTRACTOR_H

#include <QObject>
#include <QString>
#include <QUrl>
#include <QList>
#include <QMap>
#include <QVariant>
#include <memory>
#include <functional>

#ifdef HAS_FFMPEG_LIBS
// Forward declarations to avoid including FFmpeg headers in header file
struct AVFormatContext;
struct AVCodecContext;
struct AVCodec;
struct AVPacket;
struct AVSubtitle;
#endif

/**
 * Fast subtitle extractor using FFmpeg libraries (libavformat/libavcodec)
 * 
 * This class uses FFmpeg libraries directly instead of CLI, allowing:
 * - Direct seeking to subtitle packets using container index
 * - No linear file scanning
 * - 100x faster extraction for large files
 * - No external process overhead
 */
class FFmpegSubtitleExtractor : public QObject
{
    Q_OBJECT
    
public:
    struct SubtitleEntry {
        qint64 startTime;  // in milliseconds
        qint64 endTime;    // in milliseconds
        QString text;      // subtitle text
    };
    
    explicit FFmpegSubtitleExtractor(QObject *parent = nullptr);
    ~FFmpegSubtitleExtractor();
    
    // Check if FFmpeg libraries are available
    static bool isAvailable();
    
    // Extract all subtitles from a video file (fast, uses container index)
    bool extractSubtitles(const QString &filePath, int streamIndex, QList<SubtitleEntry> &entries);
    
    // Extract subtitles with incremental callback (emits as found, not all at once)
    typedef std::function<void(const SubtitleEntry&)> SubtitleCallback;
    bool extractSubtitlesIncremental(const QString &filePath, int streamIndex, SubtitleCallback callback);
    
    // Extract subtitle info (stream indices, codecs, etc.)
    bool extractSubtitleInfo(const QString &filePath, QList<QMap<QString, QVariant>> &tracks);
    
private:
#ifdef HAS_FFMPEG_LIBS
    // Initialize FFmpeg context
    bool openFile(const QString &filePath);
    void closeFile();
    
    // Find subtitle stream by index
    int findSubtitleStream(int streamIndex);
    
    // Read subtitle packets and convert to text
    bool readSubtitlePackets(int streamIndex, QList<SubtitleEntry> &entries);
    
    // Convert FFmpeg timestamp to milliseconds
    qint64 timestampToMs(int64_t pts, const void *timeBase) const;  // AVRational* but forward declared
    
    // Convert subtitle packet to text
    QString subtitlePacketToText(const void *sub) const;  // AVSubtitle* but forward declared
    
    AVFormatContext *m_formatContext;
    QMap<int, AVCodecContext*> m_codecContexts;  // stream index -> codec context
    bool m_fileOpen;
#else
    // Stub implementations when FFmpeg libraries not available
    bool m_fileOpen;
#endif
};

#endif // FFMPEGSUBTITLEEXTRACTOR_H

