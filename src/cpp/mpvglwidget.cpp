#include "mpvglwidget.h"
#include "mpvvideoplayer.h"
#include <QDebug>
#include <QMetaObject>

#ifdef HAS_LIBMPV
#include <mpv/client.h>
#include <mpv/render.h>
#include <mpv/render_gl.h>

#ifdef Q_OS_WIN
#include <windows.h>
#endif
#endif

MPVGlWidget::MPVGlWidget(MPVVideoPlayer *player, QWidget *parent)
    : QOpenGLWidget(parent)
    , m_player(player)
    , m_renderContext(nullptr)
{
    // CRITICAL: Prevent Qt from clearing the framebuffer (mpv handles rendering)
    setAutoFillBackground(false);
    setAttribute(Qt::WA_OpaquePaintEvent);
    setAttribute(Qt::WA_NoSystemBackground);

    qDebug() << "[MPVGlWidget] Constructor called";
}

MPVGlWidget::~MPVGlWidget()
{
    makeCurrent();
#ifdef HAS_LIBMPV
    if (m_renderContext) {
        // Clear update callback (use dynamic loading on Windows)
#ifdef Q_OS_WIN
        typedef void (*set_update_callback_fn)(mpv_render_context *ctx, void (*callback)(void *), void *callback_ctx);
        HMODULE mpvModule = GetModuleHandleA("libmpv-2.dll");
        if (mpvModule) {
            set_update_callback_fn setCallback = (set_update_callback_fn)GetProcAddress(mpvModule, "mpv_render_context_set_update_callback");
            if (setCallback) {
                setCallback(m_renderContext, nullptr, nullptr);
            }
        }
#else
        mpv_render_context_set_update_callback(m_renderContext, nullptr, nullptr);
#endif
        mpv_render_context_free(m_renderContext);
        m_renderContext = nullptr;
    }
#endif
    doneCurrent();
    qDebug() << "[MPVGlWidget] Destructor called";
}

void MPVGlWidget::setPlayer(MPVVideoPlayer *player)
{
    if (m_player == player) {
        return;
    }

    m_player = player;

#ifdef HAS_LIBMPV
    if (m_player && m_player->mpvHandle()) {
        if (!isValid()) {
            // Widget not yet realized; Qt will call initializeGL later
            qDebug() << "[MPVGlWidget] Widget not yet valid, will initialize on first paint";
            return;
        }

        // Force GL initialization with correct timing (after player is ready)
        // This handles the case where setPlayer() is called after Qt already called initializeGL()
        if (!m_renderContext) {
            makeCurrent();
            initializeGL();
            doneCurrent();
        } else {
            // Context already exists, just trigger update
            qDebug() << "[MPVGlWidget] Render context already exists, triggering update";
        }

        update();
    }
#endif
}

void *MPVGlWidget::get_proc_address(void *ctx, const char *name)
{
    Q_UNUSED(ctx);
    auto glctx = QOpenGLContext::currentContext();
    if (!glctx) {
        qWarning() << "[MPVGlWidget] No OpenGL context for get_proc_address";
        return nullptr;
    }
    void *res = reinterpret_cast<void*>(glctx->getProcAddress(QByteArray(name)));
    if (!res) {
        qDebug() << "[MPVGlWidget] OpenGL function not available:" << name;
    }
    return res;
}

void MPVGlWidget::render_update(void *ctx)
{
    // Called from mpv's render thread - must use invokeMethod to update GUI thread
    // CRITICAL: This callback is ONLY a signal - do NOT call mpv_render_context_update() here!
    // mpv_render_context_update() must ONLY be called from paintGL() before rendering
    auto *self = static_cast<MPVGlWidget*>(ctx);
    QMetaObject::invokeMethod(self, "maybeUpdate", Qt::QueuedConnection);
}

void MPVGlWidget::maybeUpdate()
{
    if (window() && !window()->isMinimized()) {
        update();
    }
}

void MPVGlWidget::initializeGL()
{
#ifdef HAS_LIBMPV
    if (!m_player || !m_player->mpvHandle()) {
        qWarning() << "[MPVGlWidget] No mpv player or handle available";
        return;
    }

    // Clean up existing render context if any
    if (m_renderContext) {
        // Clear update callback (use dynamic loading on Windows)
#ifdef Q_OS_WIN
        typedef void (*set_update_callback_fn)(mpv_render_context *ctx, void (*callback)(void *), void *callback_ctx);
        HMODULE mpvModule = GetModuleHandleA("libmpv-2.dll");
        if (mpvModule) {
            set_update_callback_fn setCallback = (set_update_callback_fn)GetProcAddress(mpvModule, "mpv_render_context_set_update_callback");
            if (setCallback) {
                setCallback(m_renderContext, nullptr, nullptr);
            }
        }
#else
        mpv_render_context_set_update_callback(m_renderContext, nullptr, nullptr);
#endif
        mpv_render_context_free(m_renderContext);
        m_renderContext = nullptr;
    }

    mpv_handle *mpv = (mpv_handle*)m_player->mpvHandle();
    
    // Initialize mpv OpenGL render context (matches mpc-qt pattern)
    mpv_opengl_init_params glInit{};
    glInit.get_proc_address = &get_proc_address;
    glInit.get_proc_address_ctx = this;

    mpv_render_param params[] = {
        { MPV_RENDER_PARAM_API_TYPE, (void*)MPV_RENDER_API_TYPE_OPENGL },
        { MPV_RENDER_PARAM_OPENGL_INIT_PARAMS, &glInit },
        { MPV_RENDER_PARAM_INVALID, nullptr }
    };

    int err = mpv_render_context_create(&m_renderContext, mpv, params);
    if (err < 0 || !m_renderContext) {
        qWarning() << "[MPVGlWidget] Failed to create mpv render context:" << err;
        m_renderContext = nullptr;
        return;
    }

    // Set update callback (mpv will call this when a new frame is ready)
    // On Windows, mpv_render_context_set_update_callback is not exported from the DLL
    // Use dynamic loading to get the function pointer (same as in mpvvideoplayer.cpp)
#ifdef Q_OS_WIN
    typedef void (*mpv_render_update_fn)(void *cb_ctx);
    typedef void (*set_update_callback_fn)(mpv_render_context *ctx, mpv_render_update_fn callback, void *callback_ctx);
    
    HMODULE mpvModule = GetModuleHandleA("libmpv-2.dll");
    if (!mpvModule) {
        mpvModule = LoadLibraryA("libmpv-2.dll");
    }
    
    if (mpvModule) {
        set_update_callback_fn setCallback = (set_update_callback_fn)GetProcAddress(mpvModule, "mpv_render_context_set_update_callback");
        if (setCallback) {
            setCallback(m_renderContext, render_update, this);
        } else {
            qWarning() << "[MPVGlWidget] Failed to get mpv_render_context_set_update_callback function address";
        }
    } else {
        qWarning() << "[MPVGlWidget] Failed to load libmpv-2.dll module";
    }
#else
    // On non-Windows platforms, the function is exported normally
    mpv_render_context_set_update_callback(m_renderContext, render_update, this);
#endif

    // Store render context in player for cleanup
    m_player->setMpvRenderContext(m_renderContext);

    qDebug() << "[MPVGlWidget] mpv render context created successfully";
    
    // CRITICAL: Now that render context exists, load the source if one was set
    // mpv requires render context to exist BEFORE loadfile, otherwise it never enters video-configured state
    if (m_player) {
        QMetaObject::invokeMethod(
            m_player,
            "loadSourceAfterRenderContext",
            Qt::QueuedConnection
        );
    }
#else
    qWarning() << "[MPVGlWidget] libmpv not available";
#endif
}

void MPVGlWidget::paintGL()
{
#ifdef HAS_LIBMPV
    if (!m_renderContext) {
        return;
    }

    // Get OpenGL functions (required for state management)
    QOpenGLFunctions *f = QOpenGLContext::currentContext()->functions();

    // Calculate size dynamically (never use cached values - paintGL can run before resizeGL)
    const qreal dpr = devicePixelRatioF();
    const int w = static_cast<int>(width() * dpr);
    const int h = static_cast<int>(height() * dpr);

    if (w <= 0 || h <= 0) {
        return;
    }

    // REQUIRED: Reset GL state (Qt dirties it before paintGL)
    // mpv does not set viewport or disable scissor, so we must do it
    f->glDisable(GL_SCISSOR_TEST);
    f->glViewport(0, 0, w, h);

    // REQUIRED: mpv does NOT clear the framebuffer, so we must clear it ourselves
    // Otherwise we'd see garbage or Qt's background color
    f->glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
    f->glClear(GL_COLOR_BUFFER_BIT);

    // CRITICAL: Ask mpv if a frame is actually ready before rendering
    // This must be called to acknowledge updates and check frame readiness
    uint64_t flags = mpv_render_context_update(m_renderContext);
    
    // IMPORTANT: Don't gate the first render on MPV_RENDER_UPDATE_FRAME
    // mpv may require one unconditional render to transition into configured state
    // After that, we can gate on the flag for efficiency
    static bool firstRender = true;
    if (firstRender) {
        firstRender = false;
        // First render: always render (mpv will no-op if nothing ready)
    } else if (!(flags & MPV_RENDER_UPDATE_FRAME)) {
        // Subsequent renders: only render if frame is ready
        return;
    }

    // Render mpv frame into the default framebuffer (matches mpc-qt pattern)
    mpv_opengl_fbo fbo{
        static_cast<int>(defaultFramebufferObject()),
        w,
        h,
        0  // internal_format: 0 = let mpv decide
    };

    // IMPORTANT: QOpenGLWidget's defaultFramebufferObject uses Qt's coordinate system (origin at top-left)
    // mpv also renders with origin at top-left, so we should NOT flip Y
    // Setting flipY = 0 means no vertical flip (both use top-left origin)
    int flipY = 0;

    mpv_render_param params[] = {
        { MPV_RENDER_PARAM_OPENGL_FBO, &fbo },
        { MPV_RENDER_PARAM_FLIP_Y, &flipY },
        { MPV_RENDER_PARAM_INVALID, nullptr }
    };

    mpv_render_context_render(m_renderContext, params);
#else
    Q_UNUSED(this);
#endif
}

void MPVGlWidget::resizeGL(int w, int h)
{
    qreal ratio = devicePixelRatioF();
    int glW = static_cast<int>(w * ratio);
    int glH = static_cast<int>(h * ratio);
    qDebug() << "[MPVGlWidget] Resized to" << w << "x" << h << "(GL:" << glW << "x" << glH << ")";
    // Trigger repaint with new size
    update();
}

