#include "ffmpegvideorenderer.h"
#include "ffmpegvideoplayer.h"
#include <QDebug>
#include <QtQuick/QSGSimpleTextureNode>
#include <QtQuick/QSGTexture>
#include <QQuickWindow>
#include <QImage>
#include <QtGui/rhi/qrhi.h>

#ifdef Q_OS_WIN
#include <d3d11.h>
#endif

FFmpegVideoRenderer::FFmpegVideoRenderer(QQuickItem* parent)
    : QQuickItem(parent)
    , m_player(nullptr)
{
    setFlag(ItemHasContents, true);
}

FFmpegVideoRenderer::~FFmpegVideoRenderer()
{
}

bool FFmpegVideoRenderer::getPendingFrame(ID3D11Texture2D** texture, int* width, int* height)
{
    // This is called from render thread - get pending frame from player
    if (!m_player) {
        return false;
    }
    
    return m_player->getPendingFrame(texture, width, height);
}

void FFmpegVideoRenderer::setVideoSize(int w, int h)
{
    if (m_videoWidth == w && m_videoHeight == h) {
        return;
    }
    
    m_videoWidth = w;
    m_videoHeight = h;
    emit videoSizeChanged();
}

QSGNode* FFmpegVideoRenderer::updatePaintNode(QSGNode* oldNode, UpdatePaintNodeData* data)
{
    Q_UNUSED(data);
    
    // This is called on the render thread
    QSGSimpleTextureNode* node = static_cast<QSGSimpleTextureNode*>(oldNode);
    
    // Get pending frame from player
    ID3D11Texture2D* frameTexture = nullptr;
    int frameWidth = 0;
    int frameHeight = 0;
    
    if (!getPendingFrame(&frameTexture, &frameWidth, &frameHeight) || !frameTexture) {
        // No frame available - return existing node or nullptr
        return node;
    }
    
    // Update size properties (emit signal on GUI thread)
    if (m_videoWidth != frameWidth || m_videoHeight != frameHeight) {
        QMetaObject::invokeMethod(this,
                                  "setVideoSize",
                                  Qt::QueuedConnection,
                                  Q_ARG(int, frameWidth),
                                  Q_ARG(int, frameHeight));
    }
    
    // Get D3D11 device and context for mapping
    QQuickWindow* window = this->window();
    if (!window) {
        return node;
    }
    
    // Get D3D11 context from Qt's RHI (for mapping the texture)
    // Note: We're using Qt's RHI to get the D3D11 context, but we're not using QRhi for rendering
    QRhi* rhi = window->rhi();
    if (!rhi || rhi->backend() != QRhi::D3D11) {
        qWarning() << "[FFmpegRenderer] Not using D3D11 backend or RHI not available";
        return node;
    }
    
    const auto* nh = static_cast<const QRhiD3D11NativeHandles*>(rhi->nativeHandles());
    if (!nh || !nh->context) {
        qWarning() << "[FFmpegRenderer] Failed to get D3D11 context";
        return node;
    }
    
    ID3D11DeviceContext* ctx = reinterpret_cast<ID3D11DeviceContext*>(nh->context);
    ID3D11Device* device = reinterpret_cast<ID3D11Device*>(nh->dev);
    
    // Create staging texture for GPU→CPU copy (reused if size matches)
    static ID3D11Texture2D* s_stagingTexture = nullptr;
    static int s_stagingWidth = 0;
    static int s_stagingHeight = 0;
    static QByteArray s_cpuBuffer;
    
    if (!s_stagingTexture || s_stagingWidth != frameWidth || s_stagingHeight != frameHeight) {
        if (s_stagingTexture) {
            s_stagingTexture->Release();
        }
        
        D3D11_TEXTURE2D_DESC desc = {};
        desc.Width = frameWidth;
        desc.Height = frameHeight;
        desc.MipLevels = 1;
        desc.ArraySize = 1;
        desc.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
        desc.SampleDesc.Count = 1;
        desc.Usage = D3D11_USAGE_STAGING;
        desc.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
        
        if (device->CreateTexture2D(&desc, nullptr, &s_stagingTexture) != S_OK) {
            qWarning() << "[FFmpegRenderer] Failed to create staging texture";
            return node;
        }
        
        s_stagingWidth = frameWidth;
        s_stagingHeight = frameHeight;
        s_cpuBuffer.resize(frameWidth * frameHeight * 4);
    }
    
    // GPU→GPU copy: FFmpeg texture → staging texture
    ctx->CopyResource(s_stagingTexture, frameTexture);
    
    // GPU→CPU copy: Map staging texture and read to CPU buffer
    D3D11_MAPPED_SUBRESOURCE mapped = {};
    if (ctx->Map(s_stagingTexture, 0, D3D11_MAP_READ, 0, &mapped) == S_OK) {
        // Copy row by row (accounting for pitch differences)
        uint8_t* dst = reinterpret_cast<uint8_t*>(s_cpuBuffer.data());
        uint8_t* src = static_cast<uint8_t*>(mapped.pData);
        const int rowSize = frameWidth * 4;
        
        for (int y = 0; y < frameHeight; ++y) {
            memcpy(dst + y * rowSize, src + y * mapped.RowPitch, rowSize);
        }
        
        ctx->Unmap(s_stagingTexture, 0);
    } else {
        qWarning() << "[FFmpegRenderer] Failed to map staging texture";
        return node;
    }
    
    // Create QImage from CPU buffer
    // IMPORTANT: Create a copy so Qt owns the pixel data
    QImage image(reinterpret_cast<const uchar*>(s_cpuBuffer.constData()),
                 frameWidth, frameHeight,
                 QImage::Format_RGBA8888);
    image = image.copy(); // Ensure Qt owns the pixel memory
    
    // Create or reuse texture node
    if (!node) {
        node = new QSGSimpleTextureNode();
    }
    
    // Create QSGTexture from QImage (Qt handles upload to GPU)
    QSGTexture* texture = window->createTextureFromImage(image);
    if (!texture) {
        qWarning() << "[FFmpegRenderer] Failed to create QSGTexture from image";
        return node;
    }
    
    // Replace old texture (Qt will delete the old one)
    if (node->texture()) {
        delete node->texture();
    }
    
    node->setTexture(texture);
    node->setRect(boundingRect());
    node->setFiltering(QSGTexture::Linear);
    
    return node;
}
