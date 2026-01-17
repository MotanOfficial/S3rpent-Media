#include "mpvvideoplayer.h"
#include <QDebug>
#include <QFileInfo>
#include <QSettings>
#include <QQuickWindow>
#include <QQuickFramebufferObject>
#include <QQuickOpenGLUtils>  // For resetOpenGLState() - required by Qt Quick
#include <QOpenGLFramebufferObject>
#include <QOpenGLContext>
#include <QOpenGLFunctions>
#include <QScreen>
#include <cstring>  // For strstr

// libmpv includes
#ifdef HAS_LIBMPV
#include <mpv/client.h>
#include <mpv/render.h>
#include <mpv/render_gl.h>  // OpenGL render API (official, works on all platforms)

#ifdef Q_OS_WIN
#include <windows.h>
#endif
#endif

bool MPVVideoPlayer::s_mpvAvailable = false;
bool MPVVideoPlayer::s_mpvChecked = false;

MPVVideoPlayer::MPVVideoPlayer(QObject *parent)
    : QObject(parent)
    , m_position(0)
    , m_duration(0)
    , m_playbackState(0) // Stopped
    , m_volume(1.0)
    , m_seekable(false)
    , m_hasAudio(true)
    , m_mpv(nullptr)
    , m_mpvRenderContext(nullptr)
    , m_positionTimer(nullptr)
    , m_eventTimer(nullptr)
{
    // Load saved volume from settings
    QSettings settings;
    m_volume = settings.value("video/volume", 1.0).toReal();
    qDebug() << "[MPVVideoPlayer] Loaded saved volume:" << m_volume;
    
    // CRITICAL: Create timers BEFORE initializeMPV() (which uses m_eventTimer)
    m_positionTimer = new QTimer(this);
    m_positionTimer->setInterval(100); // Update every 100ms
    connect(m_positionTimer, &QTimer::timeout, this, &MPVVideoPlayer::updatePosition);
    
    m_eventTimer = new QTimer(this);
    m_eventTimer->setInterval(10); // Process events every 10ms
    connect(m_eventTimer, &QTimer::timeout, this, &MPVVideoPlayer::processEvents);
    
    // Check if libmpv is available
    if (!s_mpvChecked) {
        s_mpvAvailable = isAvailable();
        s_mpvChecked = true;
    }
    
    // Now initialize MPV (timers are ready)
    if (s_mpvAvailable) {
        initializeMPV();
    } else {
        qWarning() << "[MPVVideoPlayer] libmpv not available - player will not work";
    }
}

MPVVideoPlayer::~MPVVideoPlayer()
{
    shutdownMPV();
}

bool MPVVideoPlayer::isAvailable()
{
#ifdef HAS_LIBMPV
    // Try to create a test mpv handle
    mpv_handle *test = mpv_create();
    if (test) {
        mpv_destroy(test);
        return true;
    }
#endif
    return false;
}

void MPVVideoPlayer::initializeMPV()
{
#ifdef HAS_LIBMPV
    qDebug() << "[MPVVideoPlayer] initializeMPV() called";
    
    m_mpv = mpv_create();
    if (!m_mpv) {
        qWarning() << "[MPVVideoPlayer] Failed to create mpv handle";
        return;
    }
    
    qDebug() << "[MPVVideoPlayer] mpv handle created";
    
    setupMPVOptions();
    
    qDebug() << "[MPVVideoPlayer] Calling mpv_initialize()";
    int initResult = mpv_initialize((mpv_handle*)m_mpv);
    if (initResult < 0) {
        qWarning() << "[MPVVideoPlayer] Failed to initialize mpv, error:" << initResult;
        mpv_destroy((mpv_handle*)m_mpv);
        m_mpv = nullptr;
        return;
    }
    
    qDebug() << "[MPVVideoPlayer] mpv_initialize() succeeded";
    
    // Set up event handling
    mpv_set_wakeup_callback((mpv_handle*)m_mpv, [](void *ctx) {
        MPVVideoPlayer *player = static_cast<MPVVideoPlayer*>(ctx);
        QMetaObject::invokeMethod(player, "processEvents", Qt::QueuedConnection);
    }, this);
    
    qDebug() << "[MPVVideoPlayer] Wakeup callback set";
    
    if (!m_eventTimer) {
        qWarning() << "[MPVVideoPlayer] Event timer is null!";
    } else {
        m_eventTimer->start();
        qDebug() << "[MPVVideoPlayer] Event timer started";
    }
    
    qDebug() << "[MPVVideoPlayer] ✓ Initialized successfully with HDR support";
#endif
}

void MPVVideoPlayer::setupMPVOptions()
{
#ifdef HAS_LIBMPV
    mpv_handle *mpv = (mpv_handle*)m_mpv;
    
    // REQUIRED: Use render API (matches mpv QML example exactly)
    // This tells mpv to use the render API instead of creating its own window
    mpv_set_option_string(mpv, "vo", "libmpv");
    
    // Note: Do NOT use "gpu-context=external" - Qt owns the GL context lifecycle
    // mpv will use the current Qt GL context via getProcAddress
    
    // CRITICAL: On Windows + OpenGL, hwdec=auto uses D3D11 which cannot share textures with OpenGL
    // Use auto-copy (hardware decode + copy to system memory) or no (CPU decode)
    mpv_set_option_string(mpv, "hwdec", "auto-copy"); // Hardware decode with copy (compatible with OpenGL)
    
    // Optional but good for quality
    mpv_set_option_string(mpv, "tone-mapping", "auto"); // Automatic tone mapping for HDR
    mpv_set_option_string(mpv, "target-prim", "auto"); // Auto-detect display primaries
    mpv_set_option_string(mpv, "target-trc", "auto"); // Auto-detect display transfer
    mpv_set_option_string(mpv, "video-output-levels", "auto"); // Auto-detect output levels
    mpv_set_option_string(mpv, "video-rotate", "0"); // No rotation by default
    
    qDebug() << "[mpv] Using render API (vo=libmpv) - Qt owns GL context";
#endif
}

void MPVVideoPlayer::shutdownMPV()
{
#ifdef HAS_LIBMPV
    if (m_mpvRenderContext) {
        mpv_render_context_free((mpv_render_context*)m_mpvRenderContext);
        m_mpvRenderContext = nullptr;
    }
    
    if (m_mpv) {
        // Use mpv_destroy instead of mpv_terminate_destroy for compatibility
        // mpv_terminate_destroy may not be available in all libmpv builds
        mpv_destroy((mpv_handle*)m_mpv);
        m_mpv = nullptr;
    }
#endif
}

void MPVVideoPlayer::setSource(const QUrl &source)
{
    qDebug() << "[MPVVideoPlayer] setSource called with:" << source << "current source:" << m_source << "mpv handle:" << m_mpv;
    
    if (m_source == source)
        return;

    m_source = source;
    emit sourceChanged();

    if (!source.isEmpty()) {
        if (!m_mpv) {
            qWarning() << "[MPVVideoPlayer] setSource called but mpv handle is null - initializing now";
            initializeMPV();
        }
        
        // CRITICAL: Do NOT load file here if render context doesn't exist yet
        // mpv requires render context to exist BEFORE loadfile, otherwise it never enters video-configured state
        // The render context will trigger loadSourceAfterRenderContext() when ready
        if (m_mpv && m_mpvRenderContext) {
            // Render context exists, safe to load immediately
            loadSourceAfterRenderContext();
        } else {
            qDebug() << "[MPVVideoPlayer] Render context not ready yet - will load file when render context is created";
        }
    } else {
        qDebug() << "[MPVVideoPlayer] Source is empty, clearing";
    }
}

void MPVVideoPlayer::loadSourceAfterRenderContext()
{
    if (m_source.isEmpty() || !m_mpv) {
        return;
    }

#ifdef HAS_LIBMPV
    const QString localPath = m_source.isLocalFile() 
        ? m_source.toLocalFile() 
        : m_source.toString(QUrl::PreferLocalFile);
    
    qDebug() << "[MPVVideoPlayer] loadSourceAfterRenderContext: Resolved local path:" << localPath;
    
    if (QFileInfo::exists(localPath)) {
        mpv_handle *mpv = (mpv_handle*)m_mpv;
        const char *cmd[] = {"loadfile", localPath.toUtf8().constData(), nullptr};
        int err = mpv_command(mpv, cmd);
        
        if (err < 0) {
            qWarning() << "[MPVVideoPlayer] mpv_command failed with error:" << err;
        } else {
            qDebug() << "[MPVVideoPlayer] Loading file (render context ready):" << localPath;
        }
        
        // Wait a bit for file to load, then update properties
        QTimer::singleShot(500, this, [this]() {
            updateDuration();
            updateSeekable();
            updateHasAudio();
        });
    } else {
        qWarning() << "[MPVVideoPlayer] File does not exist:" << localPath;
    }
#else
    qWarning() << "[MPVVideoPlayer] libmpv not available";
#endif
}

void MPVVideoPlayer::play()
{
    if (!m_mpv) return;
    
#ifdef HAS_LIBMPV
    mpv_handle *mpv = (mpv_handle*)m_mpv;
    const char *cmd[] = {"set", "pause", "no", nullptr};
    mpv_command(mpv, cmd);
    m_playbackState = 1; // Playing
    emit playbackStateChanged();
    
    if (!m_positionTimer->isActive()) {
        m_positionTimer->start();
    }
#endif
}

void MPVVideoPlayer::pause()
{
    if (!m_mpv) return;
    
#ifdef HAS_LIBMPV
    mpv_handle *mpv = (mpv_handle*)m_mpv;
    const char *cmd[] = {"set", "pause", "yes", nullptr};
    mpv_command(mpv, cmd);
    m_playbackState = 2; // Paused
    emit playbackStateChanged();
#endif
}

void MPVVideoPlayer::stop()
{
    if (!m_mpv) return;
    
#ifdef HAS_LIBMPV
    mpv_handle *mpv = (mpv_handle*)m_mpv;
    const char *cmd[] = {"stop", nullptr};
    mpv_command(mpv, cmd);
    m_playbackState = 0; // Stopped
    emit playbackStateChanged();
    
    m_positionTimer->stop();
    m_eventTimer->stop();
    m_position = 0;
    emit positionChanged();
#endif
}

void MPVVideoPlayer::seek(int position)
{
    if (!m_mpv || !m_seekable) return;
    
#ifdef HAS_LIBMPV
    mpv_handle *mpv = (mpv_handle*)m_mpv;
    QString posStr = QString::number(position / 1000.0); // Convert ms to seconds
    const char *cmd[] = {"seek", posStr.toUtf8().constData(), "absolute", nullptr};
    mpv_command(mpv, cmd);
#endif
}

void MPVVideoPlayer::setRotation(int degrees)
{
    if (!m_mpv) return;
    
#ifdef HAS_LIBMPV
    mpv_handle *mpv = (mpv_handle*)m_mpv;
    QString rotStr = QString::number(degrees);
    const char *cmd[] = {"set", "video-rotate", rotStr.toUtf8().constData(), nullptr};
    mpv_command(mpv, cmd);
#endif
}

void MPVVideoPlayer::setVolume(qreal volume)
{
    if (qFuzzyCompare(m_volume, volume))
        return;
    
    m_volume = qBound(0.0, volume, 1.0);
    
    if (m_mpv) {
#ifdef HAS_LIBMPV
        mpv_handle *mpv = (mpv_handle*)m_mpv;
        QString volStr = QString::number(m_volume * 100.0);
        const char *cmd[] = {"set", "volume", volStr.toUtf8().constData(), nullptr};
        mpv_command(mpv, cmd);
        
        // Save volume to settings
        QSettings settings;
        settings.setValue("video/volume", m_volume);
#endif
    }
    
    emit volumeChanged();
}

void MPVVideoPlayer::updatePosition()
{
    if (!m_mpv) return;
    
#ifdef HAS_LIBMPV
    mpv_handle *mpv = (mpv_handle*)m_mpv;
    double timePos = 0.0;
    if (mpv_get_property(mpv, "time-pos", MPV_FORMAT_DOUBLE, &timePos) >= 0) {
        int newPosition = static_cast<int>(timePos * 1000.0); // Convert seconds to ms
        if (newPosition != m_position) {
            m_position = newPosition;
            emit positionChanged();
        }
    }
#endif
}

void MPVVideoPlayer::processEvents()
{
    if (!m_mpv) return;
    
#ifdef HAS_LIBMPV
    mpv_handle *mpv = (mpv_handle*)m_mpv;
    while (true) {
        mpv_event *event = mpv_wait_event(mpv, 0);
        if (event->event_id == MPV_EVENT_NONE) {
            break;
        }
        handleMPVEvent(event);
    }
#endif
}

void MPVVideoPlayer::setupRenderContextCallback()
{
#ifdef HAS_LIBMPV
    if (!m_mpvRenderContext) {
        qWarning() << "[MPVVideoPlayer] Cannot setup callback: render context is null";
        return;
    }
    
    mpv_render_context *ctx = (mpv_render_context*)m_mpvRenderContext;
    
#ifdef Q_OS_WIN
    // On Windows, mpv_render_context_set_update_callback is not exported from the DLL
    // Use dynamic loading to get the function pointer
    typedef void (*mpv_render_update_fn)(void *cb_ctx);
    typedef void (*set_update_callback_fn)(mpv_render_context *ctx, mpv_render_update_fn callback, void *callback_ctx);
    
    HMODULE mpvModule = GetModuleHandleA("libmpv-2.dll");
    if (!mpvModule) {
        mpvModule = LoadLibraryA("libmpv-2.dll");
    }
    
    if (mpvModule) {
        set_update_callback_fn setCallback = (set_update_callback_fn)GetProcAddress(mpvModule, "mpv_render_context_set_update_callback");
        if (setCallback) {
            setCallback(
                ctx,
                [](void *userdata) {
                    MPVVideoPlayer *player = static_cast<MPVVideoPlayer *>(userdata);
                    if (player) {
                        // Emit frameReady signal on GUI thread
                        QMetaObject::invokeMethod(player, [player]() {
                            emit player->frameReady();
                        }, Qt::QueuedConnection);
                    }
                },
                this
            );
            qDebug() << "[MPVVideoPlayer] Render context callback registered via dynamic loading - will emit frameReady()";
        } else {
            qWarning() << "[MPVVideoPlayer] Failed to get mpv_render_context_set_update_callback function address";
        }
    } else {
        qWarning() << "[MPVVideoPlayer] Failed to load libmpv-2.dll module";
    }
#else
    // On non-Windows platforms, the function is exported normally
    mpv_render_context_set_update_callback(
        ctx,
        [](void *userdata) {
            MPVVideoPlayer *player = static_cast<MPVVideoPlayer *>(userdata);
            if (player) {
                // Emit frameReady signal on GUI thread
                QMetaObject::invokeMethod(player, [player]() {
                    emit player->frameReady();
                }, Qt::QueuedConnection);
            }
        },
        this
    );
    qDebug() << "[MPVVideoPlayer] Render context callback registered - will emit frameReady()";
#endif
#endif
}

void MPVVideoPlayer::handleMPVEvent(void *event)
{
#ifdef HAS_LIBMPV
    mpv_event *ev = (mpv_event*)event;
    
    switch (ev->event_id) {
        case MPV_EVENT_FILE_LOADED:
            qDebug() << "[MPVVideoPlayer] File loaded";
            
            // DEBUG: Check if mpv actually has video (not just audio)
            {
                mpv_handle *mpv = (mpv_handle*)m_mpv;
                int64_t vid = 0;
                if (mpv_get_property(mpv, "vid", MPV_FORMAT_INT64, &vid) >= 0) {
                    qDebug() << "[MPVVideoPlayer] vid property:" << vid << "(0 = no video track)";
                }
                
                // CRITICAL: Use dwidth/dheight for render API (not width/height)
                // width/height are 0 when using vo=libmpv, dwidth/dheight show display size
                int64_t w = 0, h = 0;
                mpv_get_property(mpv, "dwidth", MPV_FORMAT_INT64, &w);
                mpv_get_property(mpv, "dheight", MPV_FORMAT_INT64, &h);
                qDebug() << "[MPVVideoPlayer] Video display size (dwidth x dheight):" << w << "x" << h;
                
                if (vid == 0 || w == 0 || h == 0) {
                    qWarning() << "[MPVVideoPlayer] WARNING: No video track or zero size - will show black screen";
                }
            }
            
            updateDuration();
            updateSeekable();
            updateHasAudio();
            // Ensure playback starts automatically
            {
                mpv_handle *mpv = (mpv_handle*)m_mpv;
                const char *cmd[] = {"set", "pause", "no", nullptr};
                mpv_command(mpv, cmd);
                m_playbackState = 1; // Playing
                emit playbackStateChanged();
                qDebug() << "[MPVVideoPlayer] Auto-started playback after file load";
            }
            break;
        case MPV_EVENT_END_FILE:
            qDebug() << "[MPVVideoPlayer] Playback ended";
            m_playbackState = 0; // Stopped
            emit playbackStateChanged();
            break;
        case MPV_EVENT_PLAYBACK_RESTART:
            qDebug() << "[MPVVideoPlayer] Playback restarted";
            break;
        case MPV_EVENT_PROPERTY_CHANGE: {
            mpv_event_property *prop = (mpv_event_property *)ev->data;
            if (strcmp(prop->name, "pause") == 0) {
                updatePlaybackState();
            }
            break;
        }
        default:
            break;
    }
#endif
}

void MPVVideoPlayer::updatePlaybackState()
{
    if (!m_mpv) return;
    
#ifdef HAS_LIBMPV
    mpv_handle *mpv = (mpv_handle*)m_mpv;
    int flag = 0;
    if (mpv_get_property(mpv, "pause", MPV_FORMAT_FLAG, &flag) >= 0) {
        int newState = flag ? 2 : 1; // 2=Paused, 1=Playing
        if (newState != m_playbackState) {
            m_playbackState = newState;
            emit playbackStateChanged();
            
            if (m_playbackState == 1) {
                if (!m_positionTimer->isActive()) {
                    m_positionTimer->start();
                }
            } else {
                m_positionTimer->stop();
            }
        }
    }
#endif
}

void MPVVideoPlayer::updateDuration()
{
    if (!m_mpv) return;
    
#ifdef HAS_LIBMPV
    mpv_handle *mpv = (mpv_handle*)m_mpv;
    double duration = 0.0;
    if (mpv_get_property(mpv, "duration", MPV_FORMAT_DOUBLE, &duration) >= 0) {
        int newDuration = static_cast<int>(duration * 1000.0); // Convert seconds to ms
        if (newDuration != m_duration) {
            m_duration = newDuration;
            emit durationChanged();
        }
    }
#endif
}

void MPVVideoPlayer::updateSeekable()
{
    if (!m_mpv) return;
    
#ifdef HAS_LIBMPV
    mpv_handle *mpv = (mpv_handle*)m_mpv;
    int flag = 0;
    if (mpv_get_property(mpv, "seekable", MPV_FORMAT_FLAG, &flag) >= 0) {
        bool newSeekable = (flag != 0);
        if (newSeekable != m_seekable) {
            m_seekable = newSeekable;
            emit seekableChanged();
        }
    }
#endif
}

void MPVVideoPlayer::updateHasAudio()
{
    if (!m_mpv) return;
    
#ifdef HAS_LIBMPV
    mpv_handle *mpv = (mpv_handle*)m_mpv;
    int64_t audioId = 0;
    // Check if audio track exists
    if (mpv_get_property(mpv, "audio-id", MPV_FORMAT_INT64, &audioId) >= 0) {
        bool hasAudioTrack = (audioId != 0);
        if (hasAudioTrack != m_hasAudio) {
            m_hasAudio = hasAudioTrack;
            emit hasAudioChanged();
        }
    }
#endif
}

// MPVVideoItem implementation using QQuickFramebufferObject (matches mpv QML example exactly)
MPVVideoItem::MPVVideoItem(QQuickItem *parent)
    : QQuickFramebufferObject(parent)
    , m_player(nullptr)
{
    setMirrorVertically(false);  // mpv handles Y-flip via flipY parameter
    
    // NOTE: Do NOT use setTextureFollowsItemSize(true) - it causes a Qt 6 bug/design mismatch
    // with QQuickFramebufferObject + OpenGL on Windows when maximizing. Qt internally applies
    // a transform assuming logical pixels, but QQuickFramebufferObject already works in device
    // pixels, causing double offset/clipped quad. Qt already recreates the FBO when needed.
    
    setFlag(ItemHasContents, true);  // Tell Qt this item has content (fully opaque)
    setOpacity(1.0);  // Ensure fully opaque for correct composition
    qDebug() << "[MPVVideoItem] Constructor called, parent:" << parent;
}

MPVVideoItem::~MPVVideoItem()
{
    qDebug() << "[MPVVideoItem] Destructor called";
}

void MPVVideoItem::setPlayer(MPVVideoPlayer *player)
{
    if (m_player != player) {
        qDebug() << "[MPVVideoItem] setPlayer() called, player:" << player;
        
        if (m_player) {
            disconnect(m_player, &MPVVideoPlayer::frameReady, this, nullptr);
        }
        
        m_player = player;
        emit playerChanged();
        
        if (player) {
            connect(player, &MPVVideoPlayer::frameReady, this, &MPVVideoItem::onFrameReady, Qt::QueuedConnection);
            update();
        }
    }
}

void MPVVideoItem::onFrameReady()
{
    // Request render update when mpv signals a new frame
    // Note: update() is lightweight - it just marks the item as dirty for next frame
    // Qt Quick will call render() on the render thread when ready (throttled by vsync)
    update();
}

// MPVVideoItemRenderer - handles actual rendering on the render thread
// Uses QQuickFramebufferObject::Renderer (matches mpv examples pattern)
class MPVVideoItemRenderer : public QQuickFramebufferObject::Renderer
{
public:
    MPVVideoItemRenderer()
        : m_mpvCtx(nullptr)
        , m_player(nullptr)
        , m_window(nullptr)
    {
        qDebug() << "[MPVVideoItemRenderer] Constructor called";
    }
    
    ~MPVVideoItemRenderer()
    {
        if (m_mpvCtx) {
            mpv_render_context_free(m_mpvCtx);
            m_mpvCtx = nullptr;
        }
        qDebug() << "[MPVVideoItemRenderer] Destructor called";
    }
    
    QOpenGLFramebufferObject *createFramebufferObject(const QSize &size) override
    {
        // RULE 1: CRITICAL - Initialize mpv render context ONLY on render thread (in createFramebufferObject)
        // This is the ONLY safe place - render thread has stable GL context
        if (!m_mpvCtx && m_player && m_player->mpvHandle()) {
            QOpenGLContext *glContext = QOpenGLContext::currentContext();
            if (!glContext) {
                qWarning() << "[MPVVideoItemRenderer] No OpenGL context on render thread";
                return QQuickFramebufferObject::Renderer::createFramebufferObject(size);
            }
            
            mpv_handle *mpv = (mpv_handle*)m_player->mpvHandle();
            
            mpv_opengl_init_params gl_init_params{};
            gl_init_params.get_proc_address = [](void *ctx, const char *name) -> void* {
                auto *gl = static_cast<QOpenGLContext*>(ctx);
                return gl ? (void*)gl->getProcAddress(name) : nullptr;
            };
            gl_init_params.get_proc_address_ctx = glContext;
            
            mpv_render_param params[] = {
                { MPV_RENDER_PARAM_API_TYPE, (void*)MPV_RENDER_API_TYPE_OPENGL },
                { MPV_RENDER_PARAM_OPENGL_INIT_PARAMS, &gl_init_params },
                { MPV_RENDER_PARAM_INVALID, nullptr }
            };
            
            int err = mpv_render_context_create(&m_mpvCtx, mpv, params);
            if (err < 0 || !m_mpvCtx) {
                qWarning() << "[MPVVideoItemRenderer] mpv_render_context_create failed:" << err;
                m_mpvCtx = nullptr;
                return QQuickFramebufferObject::Renderer::createFramebufferObject(size);
            }
            
            // Store it in player
            m_player->setMpvRenderContext(m_mpvCtx);
            
            // RULE 2: Register update callback (callback is ONLY a signal, no mpv calls in callback)
            m_player->ensureRenderCallbackRegistered();
            
            qDebug() << "[MPVVideoItemRenderer] mpv render context created on render thread";
            
            // CRITICAL: Load source after render context is ready (mpv requirement)
            QMetaObject::invokeMethod(m_player, "loadSourceAfterRenderContext", Qt::QueuedConnection);
        }
        
        // CRITICAL FIX: In Qt 6, the 'size' parameter may already be in device pixels for FBO items.
        // Do NOT use setTextureFollowsItemSize(true) - it causes double-DPI scaling bug in Qt 6
        // on Windows when maximized/fullscreen.
        // 
        // Strategy A (trying first): Trust Qt's 'size' parameter as-is (it may already be in device pixels)
        // If this causes issues, we'll switch to Strategy B (multiply by DPR if size is logical)
        
        qreal dpr = 1.0;
        if (m_window) {
            dpr = m_window->effectiveDevicePixelRatio();  // Best for Qt Quick (matches scenegraph rendering)
        }
        
        // Debug logging to diagnose what 'size' represents
        qDebug() << "[MPVVideoItemRenderer] Creating FBO - size param:" << size
                 << "window size:" << (m_window ? m_window->size() : QSize())
                 << "window DPR:" << dpr
                 << "window screen DPR:" << (m_window && m_window->screen() ? m_window->screen()->devicePixelRatio() : 1.0);
        
        // Strategy A: Use size as-is (Qt 6 may already provide device pixels)
        // If this causes top-left clipping, switch to Strategy B: QSize(qRound(size.width() * dpr), qRound(size.height() * dpr))
        const QSize pixelSize = size;
        
        // Create FBO with explicit format
        QOpenGLFramebufferObjectFormat format;
        format.setAttachment(QOpenGLFramebufferObject::NoAttachment);  // No depth/stencil needed for video
        QOpenGLFramebufferObject *fbo = new QOpenGLFramebufferObject(pixelSize, format);
        
        // CRITICAL: Clear new FBO to black immediately to prevent white artifacts
        // This is especially important during resize when new FBOs are created
        fbo->bind();
        QOpenGLFunctions *gl = QOpenGLContext::currentContext()->functions();
        gl->glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
        gl->glClear(GL_COLOR_BUFFER_BIT);
        fbo->release();
        
        return fbo;
    }
    
    void synchronize(QQuickFramebufferObject *item) override
    {
        MPVVideoItem *videoItem = static_cast<MPVVideoItem*>(item);
        if (!videoItem) {
            return;
        }
        
        // Store player reference (thread-safe)
        // mpv context is created in createFramebufferObject() on first FBO creation
        m_player = videoItem->player();
        
        // Store window reference for DPR access (Qt 6 requires QScreen for DPR)
        m_window = videoItem->window();
    }
    
    void render() override
    {
#ifdef HAS_LIBMPV
        // RULE 3: Call mpv_render_context_render() ONLY in render() method
        if (!m_mpvCtx || !m_player) {
            return;
        }
        
        QOpenGLFramebufferObject *fbo = framebufferObject();
        if (!fbo) {
            return;
        }
        
        // CRITICAL: Call mpv_render_context_update() to acknowledge updates and check frame readiness
        // This MUST be called in render() method, NOT in the callback
        uint64_t flags = mpv_render_context_update(m_mpvCtx);
        
        // CRITICAL FIX: ALWAYS clear FBO to black FIRST (before any early returns)
        // This prevents white artifacts during resize/maximize when FBO is recreated
        // mpv does NOT clear uncovered regions, so uninitialized FBO memory shows as white
        // Qt Quick already has the FBO bound in render(), so we don't need to bind/release
        // NOTE: Do NOT set glViewport or glDisable(GL_SCISSOR_TEST) - Qt Quick manages these
        // for correct DPR handling. Overriding them causes corner cut-off when maximized.
        QOpenGLFunctions *gl = QOpenGLContext::currentContext()->functions();
        gl->glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
        gl->glClear(GL_COLOR_BUFFER_BIT);
        
        // Don't gate first render on MPV_RENDER_UPDATE_FRAME (mpv may need one unconditional render)
        static bool firstRender = true;
        if (firstRender) {
            firstRender = false;
            // First render: always render (mpv will no-op if nothing ready)
        } else if (!(flags & MPV_RENDER_UPDATE_FRAME)) {
            // Subsequent renders: only render if frame is ready
            // FBO was cleared above, so black screen is shown (correct behavior)
            return;
        }
        
        // CRITICAL: Set viewport and disable scissor BEFORE mpv renders
        // Qt Quick's scene graph may leave viewport/scissor set to the item's logical/old rect.
        // mpv does not set viewport/scissor - it renders into whatever GL state exists.
        // Without this, mpv renders into a smaller/scissored region causing top/left clipping.
        gl->glDisable(GL_SCISSOR_TEST);
        gl->glViewport(0, 0, fbo->width(), fbo->height());
        
        // mpv FBO description (matches mpv QML example exactly)
        mpv_opengl_fbo mpvFbo{};
        mpvFbo.fbo = fbo->handle();
        mpvFbo.w = fbo->width();
        mpvFbo.h = fbo->height();
        mpvFbo.internal_format = 0;  // Let mpv decide format (HDR/SDR/tone mapping)
        
        int flipY = 0;  // QQuickFramebufferObject uses top-left origin, same as mpv
        
        mpv_render_param params[] = {
            { MPV_RENDER_PARAM_OPENGL_FBO, &mpvFbo },
            { MPV_RENDER_PARAM_FLIP_Y, &flipY },
            { MPV_RENDER_PARAM_INVALID, nullptr }
        };
        
        // RULE 3: Render mpv frame into FBO (ONLY place mpv_render_context_render is called)
        mpv_render_context_render(m_mpvCtx, params);
        
        // CRITICAL: Reset Qt Quick's OpenGL state after rendering
        // Qt Quick does not provide a clean OpenGL state and expects you to restore it.
        // Without this, stale scissor/viewport state causes top/left clipping after maximize.
        QQuickOpenGLUtils::resetOpenGLState();
        
        // Note: Do NOT call fbo->release() - Qt Quick manages FBO binding
#endif
    }
    
private:
    mpv_render_context *m_mpvCtx;
    MPVVideoPlayer *m_player;
    QQuickWindow *m_window;  // Store window reference for DPR access (Qt 6 requires QScreen)
};

QQuickFramebufferObject::Renderer *MPVVideoItem::createRenderer() const
{
    qDebug() << "[MPVVideoItem] createRenderer() called - using QQuickFramebufferObject (minimal, clean implementation)";
    return new MPVVideoItemRenderer();
}

