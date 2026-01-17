#ifndef FFMPEGVIDEORENDERER_H
#define FFMPEGVIDEORENDERER_H

#include <QtQuick/QQuickItem>

// Forward declarations
#ifdef Q_OS_WIN
struct ID3D11Texture2D;
#endif

class FFmpegVideoPlayer;

class FFmpegVideoRenderer : public QQuickItem
{
    Q_OBJECT
    Q_PROPERTY(int videoWidth READ videoWidth NOTIFY videoSizeChanged)
    Q_PROPERTY(int videoHeight READ videoHeight NOTIFY videoSizeChanged)

public:
    explicit FFmpegVideoRenderer(QQuickItem* parent = nullptr);
    ~FFmpegVideoRenderer();

    int videoWidth() const { return m_videoWidth; }
    int videoHeight() const { return m_videoHeight; }

    // Called from render thread to get pending frame from player
    // Returns true if a new frame was available
    bool getPendingFrame(ID3D11Texture2D** texture, int* width, int* height);

signals:
    void videoSizeChanged();

protected:
    QSGNode* updatePaintNode(QSGNode* oldNode, UpdatePaintNodeData* data) override;

private slots:
    // Set video size (called from render thread via invokeMethod)
    void setVideoSize(int w, int h);

private:
    friend class FFmpegVideoPlayer;
    FFmpegVideoPlayer* m_player = nullptr;
    
    int m_videoWidth = 0;
    int m_videoHeight = 0;
};

#endif // FFMPEGVIDEORENDERER_H
