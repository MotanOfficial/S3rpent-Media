#ifndef MPVVIDEOPLAYER_H
#define MPVVIDEOPLAYER_H

#include <QObject>
#include <QUrl>
#include <QString>
#include <QTimer>
#include <QQuickFramebufferObject>
#include <QQuickWindow>
#include <QMutex>
#include <QWaitCondition>
#include <QThread>

// Forward declaration for mpv handle
struct mpv_handle;
struct mpv_render_context;

class MPVVideoPlayer : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QUrl source READ source WRITE setSource NOTIFY sourceChanged)
    Q_PROPERTY(int position READ position NOTIFY positionChanged)
    Q_PROPERTY(int duration READ duration NOTIFY durationChanged)
    Q_PROPERTY(int playbackState READ playbackState NOTIFY playbackStateChanged)
    Q_PROPERTY(qreal volume READ volume WRITE setVolume NOTIFY volumeChanged)
    Q_PROPERTY(bool seekable READ seekable NOTIFY seekableChanged)
    Q_PROPERTY(bool hasAudio READ hasAudio NOTIFY hasAudioChanged)

public:
    explicit MPVVideoPlayer(QObject *parent = nullptr);
    ~MPVVideoPlayer();

    QUrl source() const { return m_source; }
    void setSource(const QUrl &source);

    int position() const { return m_position; }
    int duration() const { return m_duration; }
    int playbackState() const { return m_playbackState; }
    qreal volume() const { return m_volume; }
    void setVolume(qreal volume);
    bool seekable() const { return m_seekable; }
    bool hasAudio() const { return m_hasAudio; }

    Q_INVOKABLE void play();
    Q_INVOKABLE void pause();
    Q_INVOKABLE void stop();
    Q_INVOKABLE void seek(int position);
    Q_INVOKABLE void setRotation(int degrees); // Set video rotation (0, 90, 180, 270)
    Q_INVOKABLE void loadSourceAfterRenderContext(); // Load source after render context is ready

    // Get mpv handle for rendering (used by QML component)
    void* mpvHandle() const { return m_mpv; }
    void* mpvRenderContext() const { return m_mpvRenderContext; }
    
    // Public setters for renderer (avoids accessing private members)
    void setMpvRenderContext(void *ctx) { m_mpvRenderContext = ctx; }
    void ensureRenderCallbackRegistered() { setupRenderContextCallback(); }

    // Check if libmpv is available
    static bool isAvailable();

signals:
    void sourceChanged();
    void positionChanged();
    void durationChanged();
    void playbackStateChanged();
    void volumeChanged();
    void seekableChanged();
    void hasAudioChanged();
    void errorOccurred(int error, const QString &errorString);
    void frameReady(); // Signal when a new frame is ready for rendering

private slots:
    void updatePosition();
    void processEvents();

private:
    void initializeMPV();
    void shutdownMPV();
    void setupMPVOptions();
    void handleMPVEvent(void *event);
    void updatePlaybackState();
    void updateDuration();
    void updateSeekable();
    void updateHasAudio();
    
    // Setup render context callback (called by MPVVideoItem after context creation)
    void setupRenderContextCallback();

    QUrl m_source;
    int m_position;
    int m_duration;
    int m_playbackState; // 0=Stopped, 1=Playing, 2=Paused
    qreal m_volume;
    bool m_seekable;
    bool m_hasAudio;
    
    void* m_mpv; // mpv_handle* (void* to avoid including mpv headers in header)
    void* m_mpvRenderContext; // mpv_render_context* (void* to avoid including mpv headers in header)
    QTimer *m_positionTimer;
    QTimer *m_eventTimer;
    QMutex m_mpvMutex;
    
    // Allow renderer to set render context
    friend class MPVVideoRenderer;
    friend class MPVVideoItem;  // Allow MPVVideoItem to set render context
    
    static bool s_mpvAvailable;
    static bool s_mpvChecked;
};

// Forward declaration for renderer
class MPVVideoItemRenderer;

// QML Rendering Component using QQuickFramebufferObject (matches mpv examples)
// This is the standard approach for mpv + Qt Quick integration
class MPVVideoItem : public QQuickFramebufferObject
{
    Q_OBJECT
    Q_PROPERTY(MPVVideoPlayer* player READ player WRITE setPlayer NOTIFY playerChanged)

public:
    MPVVideoItem(QQuickItem *parent = nullptr);
    ~MPVVideoItem();

    MPVVideoPlayer* player() const { return m_player; }
    void setPlayer(MPVVideoPlayer *player);

    // QQuickFramebufferObject interface
    Renderer *createRenderer() const override;

signals:
    void playerChanged();

private slots:
    void onFrameReady();

private:
    MPVVideoPlayer *m_player;
    
    // Allow renderer to access private members
    friend class MPVVideoItemRenderer;
};

#endif // MPVVIDEOPLAYER_H

