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

void FFmpegVideoPlayer::startPresenterThreadIfNeeded()
{
    if (m_presentThreadRunning.load(std::memory_order_acquire))
        return;
    if (m_presentThread)
        return;
    m_presentThreadRunning.store(true, std::memory_order_release);
    m_presentThread = QThread::create([this]() { presenterThreadFunc(); });
    m_presentThread->start();
}

void FFmpegVideoPlayer::stopPresenterThread()
{
    m_presentThreadRunning.store(false, std::memory_order_release);
    {
        QMutexLocker lock(&m_videoQueueMutex);
        m_videoQueue.clear();
        m_videoQueueCond.wakeAll();
    }
    if (m_presentThread) {
        m_presentThread->wait(2000);
        delete m_presentThread;
        m_presentThread = nullptr;
    }
}

void FFmpegVideoPlayer::presenterThreadFunc()
{
    while (m_presentThreadRunning.load(std::memory_order_acquire)) {
        QueuedVideoItem item;
        {
            QMutexLocker lock(&m_videoQueueMutex);
            while (m_presentThreadRunning.load(std::memory_order_acquire) && m_videoQueue.empty()) {
                m_videoQueueCond.wait(&m_videoQueueMutex, 50);
            }
            if (!m_presentThreadRunning.load(std::memory_order_acquire))
                break;
            if (m_videoQueue.empty())
                continue;
            item = std::move(m_videoQueue.front());
        }

        while (m_presentThreadRunning.load(std::memory_order_acquire)
               && m_presentInFlight.load(std::memory_order_acquire) >= 1) {
            QThread::msleep(1);
        }
        if (!m_presentThreadRunning.load(std::memory_order_acquire))
            break;

        const double videoPts = (item.startUs >= 0) ? (double(item.startUs) / 1000000.0) : 0.0;
        double master = videoPts;
        if (m_audioSink && m_audioCodecContext && !std::isnan(m_audioBasePts) && m_audioDevice && m_audioDevice->isOpen()) {
            refreshAudioMasterClockForSync(master);
        } else if (m_timingInitialized) {
            master = m_startPts + (nowSeconds() - m_startTime);
        }

        if (m_startupNoDropFrames <= 0 && (videoPts < master - 0.15)) {
            QMutexLocker lock(&m_videoQueueMutex);
            if (!m_videoQueue.empty())
                m_videoQueue.pop_front();
            continue;
        }

        constexpr double kMaxVideoLeadSec = 0.10;
        const bool firstFrameBootstrap = !m_presentedAnyVideo.load(std::memory_order_acquire);

        int spins = 0;
        while (!firstFrameBootstrap
               && m_presentThreadRunning.load(std::memory_order_acquire)
               && (videoPts > master + kMaxVideoLeadSec)) {
            if (m_audioSink && m_audioCodecContext && !std::isnan(m_audioBasePts) && m_audioDevice && m_audioDevice->isOpen()) {
                refreshAudioMasterClockForSync(master);
            } else if (m_timingInitialized) {
                master = m_startPts + (nowSeconds() - m_startTime);
            }
            if (videoPts <= master + kMaxVideoLeadSec)
                break;
            QThread::usleep(500);
            if (++spins > 600)
                break;
        }

        {
            QMutexLocker lock(&m_videoQueueMutex);
            if (m_videoQueue.empty())
                continue;
            m_videoQueue.pop_front();
            m_videoQueueCond.wakeAll();
        }

        m_presentInFlight.fetch_add(1, std::memory_order_acq_rel);
        QMetaObject::invokeMethod(this, [this, item]() mutable {
            if (!m_videoSink)
            {
                m_presentInFlight.fetch_sub(1, std::memory_order_acq_rel);
                return;
            }
            if (item.kind == QueuedVideoItem::Kind::NV12) {
                QVideoFrameFormat format(QSize(item.width, item.height), QVideoFrameFormat::Format_NV12);
                QVideoFrame vf(format);
                if (!vf.map(QVideoFrame::WriteOnly))
                    return;
                const int dstYStride = vf.bytesPerLine(0);
                const int dstUVStride = vf.bytesPerLine(1);
                for (int y = 0; y < item.height; ++y)
                    memcpy(vf.bits(0) + y * dstYStride, item.p0.constData() + y * item.width, item.width);
                for (int y = 0; y < (item.height / 2); ++y)
                    memcpy(vf.bits(1) + y * dstUVStride, item.p1.constData() + y * item.width, item.width);
                vf.unmap();
                if (item.startUs >= 0) vf.setStartTime(item.startUs);
                if (item.endUs >= 0) vf.setEndTime(item.endUs);
                avDiagLogFirstVideoSink(item.startUs, item.endUs, item.tag);
                m_videoSink->setVideoFrame(vf);
            } else if (item.kind == QueuedVideoItem::Kind::YUV420P) {
                QVideoFrameFormat format(QSize(item.width, item.height), QVideoFrameFormat::Format_YUV420P);
                QVideoFrame vf(format);
                if (!vf.map(QVideoFrame::WriteOnly))
                    return;
                const int dstYStride = vf.bytesPerLine(0);
                const int dstUStride = vf.bytesPerLine(1);
                const int dstVStride = vf.bytesPerLine(2);
                for (int y = 0; y < item.height; ++y)
                    memcpy(vf.bits(0) + y * dstYStride, item.p0.constData() + y * item.width, item.width);
                const int uvW = item.width / 2;
                for (int y = 0; y < (item.height / 2); ++y) {
                    memcpy(vf.bits(1) + y * dstUStride, item.p1.constData() + y * uvW, uvW);
                    memcpy(vf.bits(2) + y * dstVStride, item.p2.constData() + y * uvW, uvW);
                }
                vf.unmap();
                if (item.startUs >= 0) vf.setStartTime(item.startUs);
                if (item.endUs >= 0) vf.setEndTime(item.endUs);
                avDiagLogFirstVideoSink(item.startUs, item.endUs, item.tag);
                m_videoSink->setVideoFrame(vf);
            } else {
                QVideoFrame copy = item.frame;
                if (copy.isValid()) {
                    avDiagLogFirstVideoSink(copy.startTime(), copy.endTime(), item.tag);
                    m_videoSink->setVideoFrame(copy);
                }
            }
            m_presentedAnyVideo.store(true, std::memory_order_release);
            if (m_startupNoDropFrames > 0)
                --m_startupNoDropFrames;
            m_presentInFlight.fetch_sub(1, std::memory_order_acq_rel);
        }, Qt::QueuedConnection);
    }
}

void FFmpegVideoPlayer::processFrame(AVFrame* frame)
{
    if (!frame) {
        return;
    }

    static int s_skipInFlight = 0;
    
    AVPixelFormat frameFormat = (AVPixelFormat)frame->format;
    if (frameFormat == AV_PIX_FMT_P010LE || frameFormat == AV_PIX_FMT_YUV420P10LE) {
        int width = frame->width;
        int height = frame->height;
        
        if (width <= 0 || height <= 0) {
            return;
        }
        
        frame->color_range = AVCOL_RANGE_MPEG;
        frame->color_primaries = AVCOL_PRI_BT2020;
        frame->color_trc = AVCOL_TRC_SMPTE2084;
        frame->colorspace = AVCOL_SPC_BT2020_NCL;
        
        bool needsRecreation = false;
        if (!m_filterGraph || !m_filterGraphInitialized) {
            needsRecreation = true;
            if (m_filterGraphInitialized && m_isPlaying.load(std::memory_order_acquire)) {
                qWarning() << "[FFmpeg] Filter graph lost during playback - recreating (this should not happen)";
            }
        } else if (m_filterWidth != width || 
                   m_filterHeight != height || 
                   m_filterInputFormat != frameFormat) {
            needsRecreation = true;
            qDebug() << "[FFmpeg] Filter graph dimensions/format changed:" 
                     << m_filterWidth << "x" << m_filterHeight << "->" << width << "x" << height
                     << "format:" << av_get_pix_fmt_name(m_filterInputFormat) 
                     << "->" << av_get_pix_fmt_name(frameFormat);
        }
        
        if (needsRecreation) {
            int displayWidth = 0;
            int displayHeight = 0;
            if (m_videoSink) {
                displayWidth = 0;
                displayHeight = 0;
            }
            
            if (!initHDRToneMappingFilter(width, height, frameFormat, displayWidth, displayHeight)) {
                qWarning() << "[FFmpeg] Failed to initialize HDR tone mapping filter - video may not display";
                m_filterGraphInitialized = false;
                return;
            }
            m_filterWidth = width;
            m_filterHeight = height;
            m_filterInputFormat = frameFormat;
            m_filterGraphInitialized = true;
        }
        
        if (m_videoStream) {
            if (frame->best_effort_timestamp == AV_NOPTS_VALUE && frame->pts == AV_NOPTS_VALUE) {
                frame->pts = 0;
                frame->best_effort_timestamp = 0;
                qDebug() << "[FFmpeg] Frame has no valid PTS, using default PTS=0 for filter graph";
            }
        }
        
        int framesInFlight = m_framesInFilter.load(std::memory_order_relaxed);
        if (framesInFlight >= MAX_IN_FLIGHT) {
            static int dropCount = 0;
            dropCount++;
            if (dropCount <= 10 || (dropCount % 60 == 0)) {
                qDebug() << "[FFmpeg] Dropping frame (backpressure):" << framesInFlight << "frames in filter graph (max:" << MAX_IN_FLIGHT << ")";
            }
            return;
        }
        
        AVFrame* clonedFrame = av_frame_clone(frame);
        if (!clonedFrame) {
            qWarning() << "[FFmpeg] Failed to clone frame for filter graph - out of memory";
            return;
        }
        
        int ret = av_buffersrc_add_frame_flags(m_filterSrcCtx, clonedFrame, AV_BUFFERSRC_FLAG_KEEP_REF);
        
        if (ret < 0) {
            char errbuf[AV_ERROR_MAX_STRING_SIZE];
            av_strerror(ret, errbuf, sizeof(errbuf));
            qWarning() << "[FFmpeg] Failed to add frame to filter graph:" << errbuf << "- recreating graph";
            
            av_frame_free(&clonedFrame);
            
            cleanupHDRToneMappingFilter();
            m_filterWidth = 0;
            m_filterHeight = 0;
            m_filterInputFormat = AV_PIX_FMT_NONE;
            m_filterGraphInitialized = false;
            m_framesInFilter.store(0, std::memory_order_relaxed);
            return;
        }
        
        m_framesInFilter.fetch_add(1, std::memory_order_relaxed);
        
        ret = av_buffersink_get_frame(m_filterSinkCtx, m_filterFrame);
        if (ret < 0) {
            if (ret == AVERROR(EAGAIN)) {
                return;
            } else if (ret == AVERROR_EOF) {
                return;
            } else {
                char errbuf[AV_ERROR_MAX_STRING_SIZE];
                av_strerror(ret, errbuf, sizeof(errbuf));
                static int consecutiveSinkErrors = 0;
                consecutiveSinkErrors++;
                if (consecutiveSinkErrors <= 5) {
                    qWarning() << "[FFmpeg] Failed to get frame from filter graph:" << errbuf 
                               << "(" << ret << ") - attempt" << consecutiveSinkErrors;
                } else if (consecutiveSinkErrors == 6) {
                    qWarning() << "[FFmpeg] Filter graph sink errors persisting - may need to recreate graph";
                }
                return;
            }
        }
        
        m_framesInFilter.fetch_sub(1, std::memory_order_relaxed);
        
        static int consecutiveSinkErrors = 0;
        if (consecutiveSinkErrors > 0) {
            consecutiveSinkErrors = 0;
        }
        
        if (m_filterFrame->width <= 0 || m_filterFrame->height <= 0) {
            qWarning() << "[FFmpeg] Filter output frame has invalid dimensions:" 
                       << m_filterFrame->width << "x" << m_filterFrame->height << "- skipping";
            av_frame_unref(m_filterFrame);
            return;
        }
        if (!m_filterFrame->data[0] || m_filterFrame->linesize[0] <= 0) {
            qWarning() << "[FFmpeg] Filter output frame has invalid data pointer or stride - skipping";
            av_frame_unref(m_filterFrame);
            return;
        }
        AVPixelFormat outFormat = (AVPixelFormat)m_filterFrame->format;
        int minStride = 0;
        if (outFormat == AV_PIX_FMT_NV12) {
            minStride = m_filterFrame->width;
        } else if (outFormat == AV_PIX_FMT_YUV420P) {
            minStride = m_filterFrame->width;
        } else if (outFormat == AV_PIX_FMT_BGRA) {
            minStride = m_filterFrame->width * 4;
        }
        if (minStride > 0 && m_filterFrame->linesize[0] < minStride) {
            qWarning() << "[FFmpeg] Filter output frame stride too small:" 
                       << "format:" << av_get_pix_fmt_name(outFormat)
                       << "stride[0]:" << m_filterFrame->linesize[0] 
                       << "needs:" << minStride << "- skipping";
            av_frame_unref(m_filterFrame);
            return;
        }
        
        processFrame(m_filterFrame);
        
        av_frame_unref(m_filterFrame);
        return;
    }
    
    int width = frame->width;
    int height = frame->height;
    
    if (width <= 0 || height <= 0) {
        qWarning() << "[FFmpeg] Invalid frame dimensions:" << width << "x" << height;
        return;
    }
    
    if (!frame->data[0] || frame->linesize[0] <= 0) {
        qWarning() << "[FFmpeg] Invalid frame data pointer or linesize:" 
                   << "data[0]=" << (void*)frame->data[0] << "linesize[0]=" << frame->linesize[0];
        return;
    }
    
    if (m_width != width || m_height != height) {
        m_width = width;
        m_height = height;
        emit implicitSizeChanged();
    }
    
    if (!m_videoSink) {
        return;
    }

    {
        QMutexLocker lock(&m_videoQueueMutex);
        while ((int)m_videoQueue.size() >= kMaxQueuedVideoItems) {
            if (!m_presentThreadRunning.load(std::memory_order_acquire)
                || !m_isPlaying.load(std::memory_order_acquire)
                || m_isPaused.load(std::memory_order_acquire)) {
                s_skipInFlight++;
                return;
            }
            m_videoQueueCond.wait(&m_videoQueueMutex, 50);
        }
    }
    
    QVideoFrame videoFrame;
    AVPixelFormat pixFormat = (AVPixelFormat)frame->format;
    
        if (pixFormat == AV_PIX_FMT_NV12) {
            const int yBytes = width;
            const int uvBytes = width;
            const int srcYStride = frame->linesize[0];
            const int srcUVStride = frame->linesize[1];
            if (srcYStride < yBytes || srcUVStride < uvBytes || !frame->data[0] || !frame->data[1]) {
                qWarning() << "[FFmpeg] Invalid NV12 frame buffers/stride";
                return;
            }

            QByteArray yPlane;
            QByteArray uvPlane;
            yPlane.resize(yBytes * height);
            uvPlane.resize(uvBytes * (height / 2));
            for (int y = 0; y < height; ++y)
                memcpy(yPlane.data() + y * yBytes, frame->data[0] + y * srcYStride, yBytes);
            for (int y = 0; y < (height / 2); ++y)
                memcpy(uvPlane.data() + y * uvBytes, frame->data[1] + y * srcUVStride, uvBytes);

            avDiagLogFirstVideoDecodeQueued("NV12");
            QueuedVideoItem qi;
            qi.kind = QueuedVideoItem::Kind::NV12;
            qi.width = width;
            qi.height = height;
            qi.p0 = std::move(yPlane);
            qi.p1 = std::move(uvPlane);
            qi.startUs = m_curVideoStartUs;
            qi.endUs = m_curVideoEndUs;
            qi.tag = "NV12";
            {
                QMutexLocker lock(&m_videoQueueMutex);
                m_videoQueue.push_back(std::move(qi));
                m_videoQueueCond.wakeOne();
            }
            return;

        } else if (pixFormat == AV_PIX_FMT_YUV420P) {
            const int yBytes = width;
            const int uvBytes = width / 2;
            const int srcYStride = frame->linesize[0];
            const int srcUStride = frame->linesize[1];
            const int srcVStride = frame->linesize[2];
            if (srcYStride < yBytes || srcUStride < uvBytes || srcVStride < uvBytes
                || !frame->data[0] || !frame->data[1] || !frame->data[2]) {
                qWarning() << "[FFmpeg] Invalid YUV420P frame buffers/stride";
                return;
            }

            QByteArray yPlane;
            QByteArray uPlane;
            QByteArray vPlane;
            yPlane.resize(yBytes * height);
            uPlane.resize(uvBytes * (height / 2));
            vPlane.resize(uvBytes * (height / 2));
            for (int y = 0; y < height; ++y)
                memcpy(yPlane.data() + y * yBytes, frame->data[0] + y * srcYStride, yBytes);
            for (int y = 0; y < (height / 2); ++y) {
                memcpy(uPlane.data() + y * uvBytes, frame->data[1] + y * srcUStride, uvBytes);
                memcpy(vPlane.data() + y * uvBytes, frame->data[2] + y * srcVStride, uvBytes);
            }

            avDiagLogFirstVideoDecodeQueued("YUV420P");
            QueuedVideoItem qi;
            qi.kind = QueuedVideoItem::Kind::YUV420P;
            qi.width = width;
            qi.height = height;
            qi.p0 = std::move(yPlane);
            qi.p1 = std::move(uPlane);
            qi.p2 = std::move(vPlane);
            qi.startUs = m_curVideoStartUs;
            qi.endUs = m_curVideoEndUs;
            qi.tag = "YUV420P";
            {
                QMutexLocker lock(&m_videoQueueMutex);
                m_videoQueue.push_back(std::move(qi));
                m_videoQueueCond.wakeOne();
            }
            return;

        } else if (pixFormat == AV_PIX_FMT_BGRA) {
            const int srcStride = frame->linesize[0];
            const int expectedStride = width * 4;
            if (srcStride < expectedStride) {
                qWarning() << "[FFmpeg] Invalid BGRA stride:" << srcStride << "needs:" << expectedStride;
                return;
            }
            if (!frame->data[0]) {
                qWarning() << "[FFmpeg] Invalid BGRA data pointer";
                return;
            }
            QImage image(frame->data[0], width, height, srcStride, QImage::Format_ARGB32);
            image = image.copy();
            videoFrame = QVideoFrame(image);
        } else {
            qWarning() << "[FFmpeg] Unsupported pixel format for QVideoSink:" << av_get_pix_fmt_name((AVPixelFormat)frame->format);
            return;
        }

        if (videoFrame.isValid()) {
            if (m_curVideoStartUs >= 0)
                videoFrame.setStartTime(m_curVideoStartUs);
            if (m_curVideoEndUs >= 0)
                videoFrame.setEndTime(m_curVideoEndUs);
        }
        
        if (videoFrame.isValid()) {
            avDiagLogFirstVideoDecodeQueued("generic");
            QueuedVideoItem qi;
            qi.kind = QueuedVideoItem::Kind::Frame;
            qi.frame = videoFrame;
            qi.startUs = videoFrame.startTime();
            qi.endUs = videoFrame.endTime();
            qi.tag = "generic";
            QMutexLocker lock(&m_videoQueueMutex);
            m_videoQueue.push_back(std::move(qi));
            m_videoQueueCond.wakeOne();
        }
}
