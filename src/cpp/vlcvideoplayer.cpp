#include "vlcvideoplayer.h"
#include <QDebug>
#include <QDir>
#include <QMutexLocker>
#include <atomic>
#include <cstring>

VLCVideoPlayer::VLCVideoPlayer(QObject* parent)
    : QObject(parent)
{
    initVLC();

    m_pollTimer = new QTimer(this);
    m_pollTimer->setInterval(100);
    connect(m_pollTimer, &QTimer::timeout, this, &VLCVideoPlayer::updateState);
    m_pollTimer->start();
}

VLCVideoPlayer::~VLCVideoPlayer()
{
    cleanupVideoCallbacks();
    if (m_buffer) {
        delete[] m_buffer;
        m_buffer = nullptr;
    }
    cleanupVLC();
}

void VLCVideoPlayer::initVLC()
{
    // CRITICAL: On Windows, use API-only vmem (libvlc_video_set_callbacks + format callbacks)
    // Do NOT use --vout=vmem as it can break DXVA fallback logic
    //
    // MANDATORY: Disable hardware decoding when using vmem
    // Hardware decoding (DXVA/D3D11VA) uses GPU surfaces that cannot be mapped to vmem
    // VLC will silently skip video callbacks if hardware decoding is enabled
    const char* args[] = {
        "--avcodec-hw=none",    // REQUIRED: Disable hardware decoding for vmem
        "--no-video-title-show",
        "--no-sub-autodetect-file",
        "--quiet"
    };

    m_vlcInstance = libvlc_new(sizeof(args) / sizeof(args[0]), args);
    if (!m_vlcInstance) {
        qFatal("Failed to create libVLC instance");
        return;
    }

    m_mediaPlayer = libvlc_media_player_new(m_vlcInstance);
    if (!m_mediaPlayer) {
        qCritical() << "Failed to create libVLC media player";
    }
}

void VLCVideoPlayer::cleanupVLC()
{
    if (m_mediaPlayer) {
        libvlc_media_player_stop(m_mediaPlayer);
        libvlc_media_player_release(m_mediaPlayer);
        m_mediaPlayer = nullptr;
    }
    if (m_vlcInstance) {
        libvlc_release(m_vlcInstance);
        m_vlcInstance = nullptr;
    }
}

void VLCVideoPlayer::setVideoSink(QVideoSink* sink)
{
    if (m_videoSink == sink) return;
    
    cleanupVideoCallbacks();
    m_videoSink = sink;
    
    emit videoSinkChanged();
    
    // Try to start playback if source is already set
    if (m_videoSink) {
        tryStartPlayback();
    }
}

void VLCVideoPlayer::setupVideoCallbacks()
{
    // This is now called from onVideoFormatKnown() after format callback provides dimensions
    if (!m_mediaPlayer || !m_videoSink || m_width <= 0 || m_height <= 0) {
        return;
    }
    
    libvlc_video_set_callbacks(
        m_mediaPlayer,
        lock,
        unlock,
        display,
        this
    );
    
    qDebug() << "[VLC] Lock/unlock/display callbacks registered for" << m_width << "x" << m_height;
}

// onVideoFormatKnown is no longer needed - format callback handles everything directly

void VLCVideoPlayer::cleanupVideoCallbacks()
{
    if (m_mediaPlayer) {
        libvlc_video_set_format_callbacks(m_mediaPlayer, nullptr, nullptr);
        libvlc_video_set_callbacks(m_mediaPlayer, nullptr, nullptr, nullptr, nullptr);
        libvlc_video_set_format(m_mediaPlayer, nullptr, 0, 0, 0);
    }
}

unsigned VLCVideoPlayer::videoFormatCallback(void** opaque, char* chroma, unsigned* width, unsigned* height, unsigned* pitches, unsigned* lines)
{
    auto* self = static_cast<VLCVideoPlayer*>(*opaque);
    
    // Set chroma format to RV32 (BGRA)
    strcpy(chroma, "RV32");
    
    // Store dimensions
    unsigned w = *width;
    unsigned h = *height;
    
    // CRITICAL: Set pitches and lines synchronously (VLC needs these immediately)
    pitches[0] = w * 4;  // 4 bytes per pixel (RGBA32)
    lines[0] = h;
    
    // Allocate buffer immediately (this callback is called from VLC thread)
    // We need the buffer ready before lock() is called
    {
        QMutexLocker locker(&self->m_mutex);
        self->m_width = static_cast<int>(w);
        self->m_height = static_cast<int>(h);
        
        if (self->m_buffer) {
            delete[] self->m_buffer;
        }
        self->m_buffer = new uchar[self->m_width * self->m_height * 4];
    }
    
    // Setup lock/unlock/display callbacks on main thread
    QMetaObject::invokeMethod(
        self,
        [self]() {
            self->setupVideoCallbacks();
        },
        Qt::QueuedConnection
    );
    
    qDebug() << "[VLC] videoFormatCallback:" << w << "x" << h << "- buffer allocated";
    
    return 1;  // Return 1 to indicate success
}

void VLCVideoPlayer::videoCleanupCallback(void* opaque)
{
    // Called when video format changes or playback stops
    // Cleanup is handled by the player's destructor and cleanupVideoCallbacks()
    Q_UNUSED(opaque);
}

void* VLCVideoPlayer::lock(void* opaque, void** planes)
{
    auto* self = static_cast<VLCVideoPlayer*>(opaque);
    self->m_mutex.lock();
    
    if (!self->m_buffer) {
        self->m_mutex.unlock();
        return nullptr;
    }
    
    // CRITICAL: planes is an array of pointers, not a single pointer
    // For RV32 format, we set planes[0] to our buffer
    planes[0] = self->m_buffer;
    return nullptr;
}

void VLCVideoPlayer::unlock(void* opaque, void*, void* const*)
{
    auto* self = static_cast<VLCVideoPlayer*>(opaque);
    self->m_mutex.unlock();
}

void VLCVideoPlayer::display(void* opaque, void*)
{
    auto* self = static_cast<VLCVideoPlayer*>(opaque);
    if (!self->m_videoSink || !self->m_buffer || self->m_width <= 0 || self->m_height <= 0) {
        return;
    }
    
    // Note: We don't lock here because unlock() was already called
    // The buffer is safe to read now
    
    // Create QImage from buffer (shallow copy for performance)
    // RV32 format is BGRA (little-endian), which matches Format_RGB32 on Windows
    QImage img(
        self->m_buffer,
        self->m_width,
        self->m_height,
        self->m_width * 4,
        QImage::Format_RGB32  // BGRA on little-endian systems (Windows)
    );
    
    // Deep copy the image data (required because buffer is owned by VLC and may be overwritten)
    QImage imgCopy = img.copy();
    
    // Create video frame and send to sink (must be on main thread)
    QVideoFrame frame(imgCopy);
    
    QMetaObject::invokeMethod(
        self->m_videoSink,
        [sink = self->m_videoSink, frame]() mutable {
            if (sink) {
                sink->setVideoFrame(frame);
            }
        },
        Qt::QueuedConnection
    );
    
    // Debug: log every 60 frames to confirm display() is being called
    static std::atomic<int> frames{0};
    if ((++frames % 60) == 0) {
        qDebug() << "[VLC] display() called" << frames.load() << "times";
    }
}

QUrl VLCVideoPlayer::source() const
{
    return m_source;
}

void VLCVideoPlayer::setSource(const QUrl& source)
{
    if (m_source == source) return;
    m_source = source;
    emit sourceChanged();

    if (m_mediaPlayer) {
        // Stop previous playback
        libvlc_media_player_stop(m_mediaPlayer);
        
        // Clean up old buffer and callbacks
        cleanupVideoCallbacks();
        if (m_buffer) {
            delete[] m_buffer;
            m_buffer = nullptr;
        }
        m_width = 0;
        m_height = 0;
        m_pendingPlay = false;

        QString path = source.toLocalFile();
        if (path.isEmpty()) {
            m_pendingPlay = false;
            return;
        }
        
        // Handle Windows paths
        path = QDir::toNativeSeparators(path);
        
        // Create media
        libvlc_media_t* media = libvlc_media_new_path(m_vlcInstance, path.toUtf8().constData());
        libvlc_media_player_set_media(m_mediaPlayer, media);
        libvlc_media_release(media);
        
        // Mark that we want to play, but wait for videoSink to be set
        m_pendingPlay = true;
        
        // Try to start playback (will only start if videoSink is already set)
        tryStartPlayback();
    }
}

void VLCVideoPlayer::tryStartPlayback()
{
    // CRITICAL: Only start playback if BOTH source and videoSink are ready
    // VLC will not initialize video output if callbacks are not set before play()
    if (!m_mediaPlayer || !m_source.isValid() || !m_videoSink || !m_pendingPlay) {
        return;
    }
    
    // CRITICAL ORDER: Set video callbacks (with opaque) BEFORE format callbacks
    // The opaque pointer must be set before format callback is called
    libvlc_video_set_callbacks(
        m_mediaPlayer,
        lock,
        unlock,
        display,
        this  // This sets opaque - required for format callback
    );
    
    // THEN set format callbacks (VLC will call this when it knows dimensions)
    libvlc_video_set_format_callbacks(
        m_mediaPlayer,
        videoFormatCallback,
        videoCleanupCallback
    );
    
    qDebug() << "[VLC] Callbacks registered (video + format) - starting playback";
    
    // Now safe to start playback
    libvlc_media_player_play(m_mediaPlayer);
    m_pendingPlay = false;
}

void VLCVideoPlayer::play()
{
    if (m_mediaPlayer) {
        m_pendingPlay = true;
        tryStartPlayback();
    }
}

void VLCVideoPlayer::pause()
{
    if (m_mediaPlayer) {
        libvlc_media_player_set_pause(m_mediaPlayer, 1);
    }
}

void VLCVideoPlayer::stop()
{
    if (m_mediaPlayer) {
        libvlc_media_player_stop(m_mediaPlayer);
    }
}

void VLCVideoPlayer::seek(int ms)
{
    if (m_mediaPlayer) {
        libvlc_media_player_set_time(m_mediaPlayer, ms);
    }
}

float VLCVideoPlayer::volume() const
{
    if (m_mediaPlayer) {
        return libvlc_audio_get_volume(m_mediaPlayer) / 100.0f;
    }
    return 0.0f;
}

void VLCVideoPlayer::setVolume(float volume)
{
    if (m_mediaPlayer) {
        libvlc_audio_set_volume(m_mediaPlayer, static_cast<int>(volume * 100));
        emit volumeChanged();
    }
}

bool VLCVideoPlayer::seekable() const
{
    return m_isSeekable;
}

qint64 VLCVideoPlayer::position() const
{
    if (m_mediaPlayer) {
        return libvlc_media_player_get_time(m_mediaPlayer);
    }
    return 0;
}

qint64 VLCVideoPlayer::duration() const
{
    return m_cachedDuration;
}

int VLCVideoPlayer::playbackState() const
{
    if (!m_mediaPlayer) return StoppedState;
    
    libvlc_state_t state = libvlc_media_player_get_state(m_mediaPlayer);
    switch (state) {
        case libvlc_Playing: return PlayingState;
        case libvlc_Paused: return PausedState;
        case libvlc_Stopped: 
        case libvlc_Ended:
        case libvlc_Error:
            return StoppedState;
        default: return StoppedState;
    }
}

void VLCVideoPlayer::updateState()
{
    if (!m_mediaPlayer) return;

    // Update duration
    qint64 dur = libvlc_media_player_get_length(m_mediaPlayer);
    if (dur != m_cachedDuration) {
        m_cachedDuration = dur;
        emit durationChanged();
    }

    // Update position
    emit positionChanged();
    
    // Update seekable
    bool seek = libvlc_media_player_is_seekable(m_mediaPlayer);
    if (seek != m_isSeekable) {
        m_isSeekable = seek;
        emit seekableChanged();
    }
    
    // Update playback state
    int state = playbackState();
    if (m_lastPlaybackState != state) {
        m_lastPlaybackState = state;
        emit playbackStateChanged();
    }
}
