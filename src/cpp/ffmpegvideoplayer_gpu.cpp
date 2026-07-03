#include "ffmpegvideoplayer.h"
#include "ffmpegvideoplayer_p.h"
#include "ffmpegvideorenderer.h"
#include <QDebug>
#include <QDir>
#include <QVideoFrame>
#include <QVideoFrameFormat>
#include <QImage>
#include <QQuickWindow>
#include <QtGui/rhi/qrhi.h>
#include <QCoreApplication>
#include <QtGlobal>
#include <QStandardPaths>
#include <QFileInfo>
#include <QMetaObject>
#include <QThread>
#include <QMutex>
#include <QMutexLocker>
#include <QWaitCondition>
#include <cstdint>
#include <cmath>

#if 0
#define FFLOG(x) qDebug() << x
#else
#define FFLOG(x) do{}while(0)
#endif

#ifdef Q_OS_WIN
#include <windows.h>
#include <d3d11.h>
#include <d3d11_1.h>
#include <dxgi1_6.h>
#pragma comment(lib, "d3d11.lib")
#pragma comment(lib, "dxgi.lib")
#endif

extern "C" {
#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h>
#include <libavutil/avutil.h>
#include <libavutil/hwcontext.h>
#include <libavutil/hwcontext_d3d11va.h>
#include <libavutil/imgutils.h>
#include <libavutil/time.h>
#include <libavutil/version.h>
#include <libavutil/channel_layout.h>
#include <libavutil/samplefmt.h>
#include <libswresample/swresample.h>
#include <libswscale/swscale.h>
#include <libavfilter/avfilter.h>
#include <libavfilter/buffersink.h>
#include <libavfilter/buffersrc.h>
}

#ifdef _MSC_VER
#pragma comment(lib, "swscale.lib")
#pragma comment(lib, "avfilter.lib")
#endif

using namespace FfVp;

bool FFmpegVideoPlayer::initD3D11FromRHI()
{
#ifdef Q_OS_WIN
    if (!m_window) {
        qWarning() << "[FFmpeg] No window set - cannot get D3D11 device from RHI";
        return false;
    }
    
    QRhi* rhi = m_window->rhi();
    if (!rhi) {
        qWarning() << "[FFmpeg] No RHI available - window may not be shown yet";
        return false;
    }
    
    if (rhi->backend() != QRhi::D3D11) {
        qWarning() << "[FFmpeg] RHI backend is not D3D11:" << rhi->backend();
        return false;
    }
    
    const auto* nh = static_cast<const QRhiD3D11NativeHandles*>(rhi->nativeHandles());
    if (!nh || !nh->dev || !nh->context) {
        qWarning() << "[FFmpeg] Failed to get D3D11 native handles from RHI or handles are null";
        return false;
    }
    
    m_d3d11Device = reinterpret_cast<ID3D11Device*>(nh->dev);
    m_d3d11Context = reinterpret_cast<ID3D11DeviceContext*>(nh->context);
    
    m_d3d11Device->AddRef();
    m_d3d11Context->AddRef();
    
    qDebug() << "[FFmpeg] D3D11 device imported from Qt RHI";
    return true;
#else
    return false;
#endif
}

void FFmpegVideoPlayer::cleanupD3D11()
{
#ifdef Q_OS_WIN
    if (m_outputTexture) {
        m_outputTexture->Release();
        m_outputTexture = nullptr;
    }
    
    if (m_videoProcessor) {
        m_videoProcessor->Release();
        m_videoProcessor = nullptr;
    }
    
    if (m_videoProcessorEnumerator) {
        m_videoProcessorEnumerator->Release();
        m_videoProcessorEnumerator = nullptr;
    }
    
    if (m_videoContext) {
        m_videoContext->Release();
        m_videoContext = nullptr;
    }
    
    if (m_videoDevice) {
        m_videoDevice->Release();
        m_videoDevice = nullptr;
    }
    
    if (m_ffmpegD3DContext) {
        m_ffmpegD3DContext->Release();
        m_ffmpegD3DContext = nullptr;
    }
    
    if (m_ffmpegD3DDevice) {
        m_ffmpegD3DDevice->Release();
        m_ffmpegD3DDevice = nullptr;
    }
    
    if (m_d3d11Context) {
        m_d3d11Context->Release();
        m_d3d11Context = nullptr;
    }
    
    if (m_d3d11Device) {
        m_d3d11Device->Release();
        m_d3d11Device = nullptr;
    }
#endif
}

bool FFmpegVideoPlayer::initVideoProcessor(uint32_t width, uint32_t height)
{
#ifdef Q_OS_WIN
    if (!m_ffmpegD3DDevice || !m_ffmpegD3DContext) {
        qWarning() << "[FFmpeg] FFmpeg D3D11 device/context not available for Video Processor";
        return false;
    }
    
    if (width == 0 || height == 0) {
        qWarning() << "[FFmpeg] Invalid dimensions for Video Processor:" << width << "x" << height;
        return false;
    }
    
    HRESULT hr = m_ffmpegD3DDevice->QueryInterface(__uuidof(ID3D11VideoDevice), reinterpret_cast<void**>(&m_videoDevice));
    if (FAILED(hr) || !m_videoDevice) {
        qWarning() << "[FFmpeg] Failed to get ID3D11VideoDevice:" << hr;
        return false;
    }
    
    hr = m_ffmpegD3DContext->QueryInterface(__uuidof(ID3D11VideoContext), reinterpret_cast<void**>(&m_videoContext));
    if (FAILED(hr) || !m_videoContext) {
        qWarning() << "[FFmpeg] Failed to get ID3D11VideoContext:" << hr;
        m_videoDevice->Release();
        m_videoDevice = nullptr;
        return false;
    }
    
    D3D11_VIDEO_PROCESSOR_CONTENT_DESC desc = {};
    desc.InputFrameFormat = D3D11_VIDEO_FRAME_FORMAT_PROGRESSIVE;
    desc.InputFrameRate.Numerator = 30;
    desc.InputFrameRate.Denominator = 1;
    desc.InputWidth = width;
    desc.InputHeight = height;
    desc.OutputFrameRate.Numerator = 30;
    desc.OutputFrameRate.Denominator = 1;
    desc.OutputWidth = width;
    desc.OutputHeight = height;
    desc.Usage = D3D11_VIDEO_USAGE_PLAYBACK_NORMAL;
    
    hr = m_videoDevice->CreateVideoProcessorEnumerator(&desc, &m_videoProcessorEnumerator);
    if (FAILED(hr) || !m_videoProcessorEnumerator) {
        qWarning() << "[FFmpeg] Failed to create Video Processor Enumerator:" << hr;
        m_videoContext->Release();
        m_videoContext = nullptr;
        m_videoDevice->Release();
        m_videoDevice = nullptr;
        return false;
    }
    
    UINT index = 0;
    hr = m_videoDevice->CreateVideoProcessor(m_videoProcessorEnumerator, index, &m_videoProcessor);
    if (FAILED(hr) || !m_videoProcessor) {
        qWarning() << "[FFmpeg] Failed to create Video Processor:" << hr;
        m_videoProcessorEnumerator->Release();
        m_videoProcessorEnumerator = nullptr;
        m_videoContext->Release();
        m_videoContext = nullptr;
        m_videoDevice->Release();
        m_videoDevice = nullptr;
        return false;
    }
    
    qDebug() << "[FFmpeg] Video Processor initialized successfully";
    return true;
#else
    return false;
#endif
}

bool FFmpegVideoPlayer::transferCUDAToD3D11(AVFrame* cudaFrame, ID3D11Texture2D** outTexture)
{
#ifdef Q_OS_WIN
    if (!cudaFrame || cudaFrame->format != AV_PIX_FMT_CUDA || !outTexture || !m_swFrame) {
        return false;
    }
    
    if (!m_d3d11Device || !m_d3d11Context) {
        qWarning() << "[FFmpeg] D3D11 device not available for CUDA transfer";
        return false;
    }
    
    int ret = av_hwframe_transfer_data(m_swFrame, cudaFrame, 0);
    if (ret < 0) {
        char errbuf[AV_ERROR_MAX_STRING_SIZE];
        av_strerror(ret, errbuf, sizeof(errbuf));
        qWarning() << "[FFmpeg] Failed to transfer CUDA frame to system memory:" << errbuf;
        return false;
    }
    
    int width = m_swFrame->width;
    int height = m_swFrame->height;
    
    D3D11_TEXTURE2D_DESC texDesc = {};
    texDesc.Width = width;
    texDesc.Height = height;
    texDesc.MipLevels = 1;
    texDesc.ArraySize = 1;
    texDesc.Format = DXGI_FORMAT_NV12;
    texDesc.SampleDesc.Count = 1;
    texDesc.Usage = D3D11_USAGE_DEFAULT;
    texDesc.BindFlags = D3D11_BIND_SHADER_RESOURCE;
    texDesc.CPUAccessFlags = 0;
    
    D3D11_SUBRESOURCE_DATA initData = {};
    initData.pSysMem = m_swFrame->data[0];
    initData.SysMemPitch = m_swFrame->linesize[0];
    initData.SysMemSlicePitch = 0;
    
    HRESULT hr = m_d3d11Device->CreateTexture2D(&texDesc, &initData, outTexture);
    if (FAILED(hr)) {
        qWarning() << "[FFmpeg] Failed to create D3D11 texture from CUDA frame:" << hr;
        return false;
    }
    
    qDebug() << "[FFmpeg] Transferred CUDA frame to D3D11 texture:" << width << "x" << height;
    return true;
#else
    return false;
#endif
}

bool FFmpegVideoPlayer::initHDRToneMappingFilter(int width, int height, AVPixelFormat inputFormat, int displayWidth, int displayHeight)
{
    cleanupHDRToneMappingFilter();
    
    m_filterGraph = avfilter_graph_alloc();
    if (!m_filterGraph) {
        qWarning() << "[FFmpeg] Failed to allocate filter graph for HDR tone mapping";
        return false;
    }
    
    char args[512];
    snprintf(args, sizeof(args),
             "video_size=%dx%d:"
             "pix_fmt=%d:"
             "time_base=1/1000",
             width, height, (int)inputFormat);
    
    qDebug() << "[FFmpeg] Creating HDR tone mapping filter graph with buffer args:" << args;
    
    int ret = avfilter_graph_create_filter(&m_filterSrcCtx,
                                          avfilter_get_by_name("buffer"),
                                          "in", args, nullptr, m_filterGraph);
    if (ret < 0) {
        char errbuf[AV_ERROR_MAX_STRING_SIZE];
        av_strerror(ret, errbuf, sizeof(errbuf));
        qWarning() << "[FFmpeg] Failed to create buffer source filter:" << errbuf;
        avfilter_graph_free(&m_filterGraph);
        return false;
    }
    
    AVBufferSrcParameters* params = av_buffersrc_parameters_alloc();
    if (params) {
        params->format = inputFormat;
        params->width = width;
        params->height = height;
        params->time_base = {1, 1000};
        params->sample_aspect_ratio = {1, 1};
        
        ret = av_buffersrc_parameters_set(m_filterSrcCtx, params);
        av_free(params);
        
        if (ret < 0) {
            char errbuf[AV_ERROR_MAX_STRING_SIZE];
            av_strerror(ret, errbuf, sizeof(errbuf));
            qWarning() << "[FFmpeg] Failed to set buffer source parameters:" << errbuf;
        } else {
            qDebug() << "[FFmpeg] Locked buffer source parameters (format/dimensions)";
        }
    }
    
    int processWidth = width;
    int processHeight = height;
    bool needsScale = false;
    
    if (displayWidth > 0 && displayHeight > 0 && (displayWidth < width || displayHeight < height)) {
        double aspect = (double)width / height;
        if (displayWidth / aspect <= displayHeight) {
            processWidth = displayWidth;
            processHeight = (int)(displayWidth / aspect);
        } else {
            processWidth = (int)(displayHeight * aspect);
            processHeight = displayHeight;
        }
        needsScale = true;
        qDebug() << "[FFmpeg] Scaling down from" << width << "x" << height 
                 << "to" << processWidth << "x" << processHeight << "before HDR processing";
    } else if (width > 1920 || height > 1080) {
        double aspect = (double)width / height;
        if (width > height) {
            processWidth = 1920;
            processHeight = (int)(1920 / aspect);
        } else {
            processHeight = 1080;
            processWidth = (int)(1080 * aspect);
        }
        needsScale = true;
        qDebug() << "[FFmpeg] Scaling down from" << width << "x" << height 
                 << "to" << processWidth << "x" << processHeight << "before HDR processing (1080p max)";
    }
    
    AVFilterContext* scaleCtx = nullptr;
    if (needsScale) {
        char scaleArgs[256];
        snprintf(scaleArgs, sizeof(scaleArgs), "w=%d:h=%d:flags=fast_bilinear", processWidth, processHeight);
        ret = avfilter_graph_create_filter(&scaleCtx,
                                          avfilter_get_by_name("scale"),
                                          "scale", scaleArgs, nullptr, m_filterGraph);
        if (ret < 0) {
            char errbuf[AV_ERROR_MAX_STRING_SIZE];
            av_strerror(ret, errbuf, sizeof(errbuf));
            qWarning() << "[FFmpeg] Failed to create scale filter:" << errbuf;
            avfilter_graph_free(&m_filterGraph);
            return false;
        }
    }
    
    AVFilterContext* zscale1Ctx = nullptr;
    ret = avfilter_graph_create_filter(&zscale1Ctx,
                                      avfilter_get_by_name("zscale"),
                                      "zscale1", 
                                      "primariesin=bt2020:transferin=smpte2084:matrixin=bt2020nc:rangein=tv:"
                                      "transfer=linear:npl=100", 
                                      nullptr, m_filterGraph);
    if (ret < 0) {
        char errbuf[AV_ERROR_MAX_STRING_SIZE];
        av_strerror(ret, errbuf, sizeof(errbuf));
        qWarning() << "[FFmpeg] Failed to create zscale filter (linearize):" << errbuf;
        avfilter_graph_free(&m_filterGraph);
        return false;
    }
    
    AVFilterContext* tonemapCtx = nullptr;
    ret = avfilter_graph_create_filter(&tonemapCtx,
                                      avfilter_get_by_name("tonemap"),
                                      "tonemap", "tonemap=hable:desat=0", nullptr, m_filterGraph);
    if (ret < 0) {
        char errbuf[AV_ERROR_MAX_STRING_SIZE];
        av_strerror(ret, errbuf, sizeof(errbuf));
        qWarning() << "[FFmpeg] Failed to create tonemap filter:" << errbuf;
        avfilter_graph_free(&m_filterGraph);
        return false;
    }
    
    AVFilterContext* zscale2Ctx = nullptr;
    ret = avfilter_graph_create_filter(&zscale2Ctx,
                                      avfilter_get_by_name("zscale"),
                                      "zscale2", 
                                      "transferin=linear:primaries=bt709:transfer=bt709:matrix=bt709:range=tv", 
                                      nullptr, m_filterGraph);
    if (ret < 0) {
        char errbuf[AV_ERROR_MAX_STRING_SIZE];
        av_strerror(ret, errbuf, sizeof(errbuf));
        qWarning() << "[FFmpeg] Failed to create zscale filter (to SDR):" << errbuf;
        avfilter_graph_free(&m_filterGraph);
        return false;
    }
    
    AVFilterContext* formatCtx = nullptr;
    ret = avfilter_graph_create_filter(&formatCtx,
                                      avfilter_get_by_name("format"),
                                      "format", "pix_fmts=nv12", nullptr, m_filterGraph);
    if (ret < 0) {
        char errbuf[AV_ERROR_MAX_STRING_SIZE];
        av_strerror(ret, errbuf, sizeof(errbuf));
        qWarning() << "[FFmpeg] Failed to create format filter (to NV12):" << errbuf;
        avfilter_graph_free(&m_filterGraph);
        return false;
    }
    
    ret = avfilter_graph_create_filter(&m_filterSinkCtx,
                                      avfilter_get_by_name("buffersink"),
                                      "out", nullptr, nullptr, m_filterGraph);
    if (ret < 0) {
        char errbuf[AV_ERROR_MAX_STRING_SIZE];
        av_strerror(ret, errbuf, sizeof(errbuf));
        qWarning() << "[FFmpeg] Failed to create buffer sink filter:" << errbuf;
        avfilter_graph_free(&m_filterGraph);
        return false;
    }
    
    AVFilterContext* lastFilter = m_filterSrcCtx;
    
    if (needsScale && scaleCtx) {
        ret = avfilter_link(m_filterSrcCtx, 0, scaleCtx, 0);
        if (ret < 0) {
            qWarning() << "[FFmpeg] Failed to link buffer source to scale";
            avfilter_graph_free(&m_filterGraph);
            return false;
        }
        lastFilter = scaleCtx;
    }
    
    ret = avfilter_link(lastFilter, 0, zscale1Ctx, 0);
    if (ret < 0) {
        qWarning() << "[FFmpeg] Failed to link to zscale1";
        avfilter_graph_free(&m_filterGraph);
        return false;
    }
    
    ret = avfilter_link(zscale1Ctx, 0, tonemapCtx, 0);
    if (ret < 0) {
        qWarning() << "[FFmpeg] Failed to link zscale1 to tonemap";
        avfilter_graph_free(&m_filterGraph);
        return false;
    }
    
    ret = avfilter_link(tonemapCtx, 0, zscale2Ctx, 0);
    if (ret < 0) {
        qWarning() << "[FFmpeg] Failed to link tonemap to zscale2";
        avfilter_graph_free(&m_filterGraph);
        return false;
    }
    
    ret = avfilter_link(zscale2Ctx, 0, formatCtx, 0);
    if (ret < 0) {
        qWarning() << "[FFmpeg] Failed to link zscale2 to format";
        avfilter_graph_free(&m_filterGraph);
        return false;
    }
    
    ret = avfilter_link(formatCtx, 0, m_filterSinkCtx, 0);
    if (ret < 0) {
        qWarning() << "[FFmpeg] Failed to link format to buffer sink";
        avfilter_graph_free(&m_filterGraph);
        return false;
    }
    
    ret = avfilter_graph_config(m_filterGraph, nullptr);
    if (ret < 0) {
        char errbuf[AV_ERROR_MAX_STRING_SIZE];
        av_strerror(ret, errbuf, sizeof(errbuf));
        qWarning() << "[FFmpeg] Failed to configure filter graph:" << errbuf;
        qWarning() << "[FFmpeg] Filter graph args:" << args;
        qWarning() << "[FFmpeg] zscale1 args: primariesin=bt2020:transferin=smpte2084:matrixin=bt2020nc:rangein=tv:transfer=linear:npl=100";
        avfilter_graph_free(&m_filterGraph);
        return false;
    }
    
    qDebug() << "[FFmpeg] Filter graph configured - first frame will set color metadata (warning is expected and harmless)";
    
    m_filterFrame = av_frame_alloc();
    if (!m_filterFrame) {
        qWarning() << "[FFmpeg] Failed to allocate filter output frame";
        avfilter_graph_free(&m_filterGraph);
        return false;
    }
    
    char* graphDesc = avfilter_graph_dump(m_filterGraph, nullptr);
    if (graphDesc) {
        qDebug() << "[FFmpeg] HDR tone mapping filter graph initialized:" << width << "x" << height 
                 << "from" << av_get_pix_fmt_name(inputFormat) << "to NV12 (bt2020+PQ→linear→hable→bt709)";
        qDebug() << "[FFmpeg] Filter graph:" << graphDesc;
        av_free(graphDesc);
    } else {
        qDebug() << "[FFmpeg] HDR tone mapping filter graph initialized:" << width << "x" << height 
                 << "from" << av_get_pix_fmt_name(inputFormat) << "to NV12";
    }
    return true;
}

void FFmpegVideoPlayer::cleanupHDRToneMappingFilter()
{
    if (m_filterGraph) {
        avfilter_graph_free(&m_filterGraph);
        m_filterGraph = nullptr;
        m_filterSrcCtx = nullptr;
        m_filterSinkCtx = nullptr;
    }
    if (m_filterFrame) {
        av_frame_free(&m_filterFrame);
        m_filterFrame = nullptr;
    }
    m_filterWidth = 0;
    m_filterHeight = 0;
    m_filterInputFormat = AV_PIX_FMT_NONE;
    m_filterGraphInitialized = false;
    m_framesInFilter.store(0, std::memory_order_relaxed);
}
