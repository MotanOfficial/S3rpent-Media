#ifndef MPVGLWIDGET_H
#define MPVGLWIDGET_H

#include <QOpenGLWidget>
#include <QOpenGLContext>
#include <QOpenGLFunctions>

// Forward declarations
struct mpv_handle;
struct mpv_render_context;
class MPVVideoPlayer;

// QOpenGLWidget-based mpv renderer (mpc-qt style)
// This widget owns its own OpenGL context and renders mpv video directly
class MPVGlWidget : public QOpenGLWidget
{
    Q_OBJECT

public:
    explicit MPVGlWidget(MPVVideoPlayer *player, QWidget *parent = nullptr);
    ~MPVGlWidget();

    // Set the mpv player instance
    void setPlayer(MPVVideoPlayer *player);

protected:
    void initializeGL() override;
    void paintGL() override;
    void resizeGL(int w, int h) override;

private:
    static void *get_proc_address(void *ctx, const char *name);
    static void render_update(void *ctx);

private slots:
    void maybeUpdate();

private:
    MPVVideoPlayer *m_player;
    mpv_render_context *m_renderContext;
    // Note: m_glWidth/m_glHeight removed - size calculated dynamically in paintGL()
};

#endif // MPVGLWIDGET_H

