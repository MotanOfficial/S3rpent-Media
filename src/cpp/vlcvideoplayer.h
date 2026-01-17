#ifndef VLCVIDEOPLAYER_H
#define VLCVIDEOPLAYER_H

#include <QObject>
#include <QUrl>
#include <vlc/vlc.h>
#include <QTimer>
#include <QVideoSink>
#include <QMutex>
#include <QImage>
#include <QVideoFrame>

class VLCVideoPlayer : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QUrl source READ source WRITE setSource NOTIFY sourceChanged)
    Q_PROPERTY(qint64 position READ position NOTIFY positionChanged)
    Q_PROPERTY(qint64 duration READ duration NOTIFY durationChanged)
    Q_PROPERTY(int playbackState READ playbackState NOTIFY playbackStateChanged)
    Q_PROPERTY(float volume READ volume WRITE setVolume NOTIFY volumeChanged)
    Q_PROPERTY(bool seekable READ seekable NOTIFY seekableChanged)
    Q_PROPERTY(QVideoSink* videoSink READ videoSink WRITE setVideoSink NOTIFY videoSinkChanged)

public:
    enum PlaybackState {
        StoppedState,
        PlayingState,
        PausedState
    };
    Q_ENUM(PlaybackState)

    explicit VLCVideoPlayer(QObject* parent = nullptr);
    ~VLCVideoPlayer();

    QUrl source() const;
    void setSource(const QUrl& source);

    qint64 position() const;
    qint64 duration() const;
    int playbackState() const;
    float volume() const;
    void setVolume(float volume);
    bool seekable() const;

    QVideoSink* videoSink() const { return m_videoSink; }
    void setVideoSink(QVideoSink* sink);

    Q_INVOKABLE void play();
    Q_INVOKABLE void pause();
    Q_INVOKABLE void stop();
    Q_INVOKABLE void seek(int ms);

signals:
    void sourceChanged();
    void positionChanged();
    void durationChanged();
    void playbackStateChanged();
    void volumeChanged();
    void seekableChanged();
    void videoSinkChanged();
    void errorOccurred(int error, const QString &errorString);

private:
    void initVLC();
    void cleanupVLC();
    void updateState();
    void setupVideoCallbacks();
    void cleanupVideoCallbacks();
    void tryStartPlayback();  // Start playback if both source and sink are ready

    // VLC vmem callbacks (static, called from VLC thread)
    static unsigned videoFormatCallback(void** opaque, char* chroma, unsigned* width, unsigned* height, unsigned* pitches, unsigned* lines);
    static void videoCleanupCallback(void* opaque);
    static void* lock(void* opaque, void** planes);
    static void unlock(void* opaque, void*, void* const*);
    static void display(void* opaque, void*);

    libvlc_instance_t* m_vlcInstance = nullptr;
    libvlc_media_player_t* m_mediaPlayer = nullptr;
    
    QUrl m_source;
    QTimer* m_pollTimer = nullptr;
    
    // Cached state
    qint64 m_cachedDuration = 0;
    bool m_isSeekable = false;
    int m_lastPlaybackState = StoppedState;
    
    // vmem rendering
    QVideoSink* m_videoSink = nullptr;
    int m_width = 0;
    int m_height = 0;
    uchar* m_buffer = nullptr;
    QMutex m_mutex;
    bool m_pendingPlay = false;  // True when source is set but playback is waiting for videoSink
};

#endif // VLCVIDEOPLAYER_H
