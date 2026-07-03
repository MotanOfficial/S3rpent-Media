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
#include <libavutil/intreadwrite.h>
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

static double audioSkipSamplesStartSec(const AVFrame* f, int sampleRate)
{
    if (!f || sampleRate <= 0)
        return 0.0;
    const AVFrameSideData* sd = av_frame_get_side_data(const_cast<AVFrame*>(f), AV_FRAME_DATA_SKIP_SAMPLES);
    if (!sd || !sd->data || sd->size < 4)
        return 0.0;
    const uint32_t skip = AV_RL32(sd->data);
    if (skip == 0)
        return 0.0;
    return double(skip) / double(sampleRate);
}

void FFmpegVideoPlayer::refreshAudioMasterClockForSync(double& masterClockAbs)
{
    qint64 queuedUSecs = 0;
    {
        QMutexLocker audioLock(&m_audioMutex);
        if (m_audioSink && m_audioDevice && m_audioDevice->isOpen()) {
            const int bytesPerFrame = m_audioFormat.bytesPerFrame();
            const int sampleRate = m_audioFormat.sampleRate();
            if (bytesPerFrame > 0 && sampleRate > 0) {
                const qint64 bufferUSecs = (qint64(m_audioSink->bufferSize()) * 1000000) /
                                           (bytesPerFrame * sampleRate);
                const qint64 freeUSecsRaw = (qint64(m_audioSink->bytesFree()) * 1000000) /
                                            (bytesPerFrame * sampleRate);
                const qint64 freeClamped = qBound<qint64>(0, freeUSecsRaw, bufferUSecs);
                queuedUSecs = bufferUSecs - freeClamped;
            }
        }
    }
    m_lastQueuedAudioUSecs.store(queuedUSecs, std::memory_order_release);

    // Clamp processedUSecs-based clock to a wall-based estimate to avoid wild jumps,
    // but allow enough range to cover typical WASAPI buffer + scheduling jitter.
    constexpr double kMasterClampSec = 0.50;
    constexpr qint64 kUnderrunBackwardUSecs = 50000;

    const double wallMaster = m_audioBasePts + qMax(0.0, nowSeconds() - m_audioBaseWallTime);
    double procAbs = wallMaster;

    if (!m_audioSink || !m_audioDevice || !m_audioDevice->isOpen()) {
        masterClockAbs = wallMaster;
        m_audioClock = masterClockAbs;
        return;
    }

    for (int pass = 0; pass < 2; ++pass) {
        QMutexLocker audioLock(&m_audioMutex);
        if (!m_audioSink || !m_audioDevice || !m_audioDevice->isOpen()) {
            procAbs = wallMaster;
            break;
        }
        const qint64 proc = m_audioSink->processedUSecs();
        const qint64 dProc = proc - m_audioProcessedBaseUSecs;
        if (dProc < -kUnderrunBackwardUSecs && pass == 0) {
            if (ffmpegAvDiagEnabled()) {
                qDebug() << "[FFmpeg][AVDiag] AUDIUnderrun: reset processed base procUs="
                         << proc << "dProcUs=" << dProc
                         << "baseWasUs=" << m_audioProcessedBaseUSecs;
            }
            m_audioProcessedBaseUSecs = proc;
            continue;
        }
        procAbs = m_audioBasePts + (double(qMax(qint64(0), dProc)) / 1000000.0);
        break;
    }

    // On some backends/devices, QAudioSink::processedUSecs() already tracks the played position well enough.
    // Subtracting queued/buffered audio here can double-count latency and introduce a constant A/V offset
    // (e.g. video always ahead by ~buffer duration). Keep queuedUSecs for diagnostics only.
    masterClockAbs = qBound(wallMaster - kMasterClampSec, procAbs,
                            wallMaster + kMasterClampSec);
    m_audioClock = masterClockAbs;
}

void FFmpegVideoPlayer::decodeThreadFunc()
{
    qDebug() << "[FFmpeg] Decode thread started";
    
    while (m_decodeThreadRunning) {
        QMutexLocker locker(&m_decodeMutex);
        
        while (m_decodeThreadRunning && (!m_isPlaying.load(std::memory_order_acquire) || m_isPaused.load(std::memory_order_acquire))) {
            m_decodeCondition.wait(&m_decodeMutex, 100);
        }
        
        if (!m_decodeThreadRunning) {
            break;
        }
        
        locker.unlock();
        
        if (!m_formatContext || !m_codecContext) {
            QThread::msleep(10);
            continue;
        }
        
        int ret = avcodec_receive_frame(m_codecContext, m_frame);
        
        if (ret == 0) {
            if (m_frame->width <= 0 || m_frame->height <= 0) {
                qWarning() << "[FFmpeg] Received invalid frame from decoder - dimensions:" 
                           << m_frame->width << "x" << m_frame->height << "- skipping";
                av_frame_unref(m_frame);
                continue;
            }
            
            AVPixelFormat frameFormat = (AVPixelFormat)m_frame->format;
            if (frameFormat != AV_PIX_FMT_D3D11) {
                if (!m_frame->data[0] || m_frame->linesize[0] <= 0) {
                    qWarning() << "[FFmpeg] Received invalid frame from decoder - null data or invalid stride - skipping";
                    av_frame_unref(m_frame);
                    continue;
                }
            }
            
            FFLOG("[FFmpeg] received frame format:" << av_get_pix_fmt_name(frameFormat));
            
            if (m_videoStream && m_videoSink) {
                auto tsToSec = [](const AVStream* st, int64_t ts) -> double {
                    if (!st || ts == AV_NOPTS_VALUE)
                        return NAN;
                    const int64_t start = (st->start_time != AV_NOPTS_VALUE) ? st->start_time : 0;
                    const double sec = double(ts - start) * av_q2d(st->time_base);
                    return sec;
                };
                double framePts = tsToSec(m_videoStream, m_frame->best_effort_timestamp);
                if (std::isnan(framePts))
                    framePts = tsToSec(m_videoStream, m_frame->pts);
                if (std::isnan(framePts))
                    framePts = 0.0;

                double estFrameDurSec = 0.0;
                if (m_videoStream) {
                    const int64_t dur = (m_frame && m_frame->duration > 0) ? m_frame->duration : 0;
                    if (dur > 0)
                        estFrameDurSec = double(dur) * av_q2d(m_videoStream->time_base);
                }
                if (estFrameDurSec <= 0.0) {
                    if (m_videoStream && m_videoStream->avg_frame_rate.num > 0 && m_videoStream->avg_frame_rate.den > 0)
                        estFrameDurSec = 1.0 / av_q2d(m_videoStream->avg_frame_rate);
                    else
                        estFrameDurSec = 1.0 / 30.0;
                }

                if (!std::isnan(m_lastVideoPtsRaw)) {
                    const double jumpFwd = framePts - m_lastVideoPtsRaw;
                    const double jumpBack = m_lastVideoPtsRaw - framePts;
                    const double sinceStart = (m_playStartWallTime > 0.0) ? (nowSeconds() - m_playStartWallTime) : 0.0;
                    if (!m_seekPending.load(std::memory_order_acquire) && sinceStart < 30.0) {
                        if (jumpFwd > 2.0) {
                            if (ffmpegAvDiagEnabled()) {
                                qDebug() << "[FFmpeg][AVDiag] PTS jump forward, smoothing:"
                                         << "prev=" << m_lastVideoPtsRaw << "new=" << framePts
                                         << "jump=" << jumpFwd << "dur=" << estFrameDurSec;
                            }
                            framePts = m_lastVideoPtsRaw + estFrameDurSec;
                        } else if (jumpBack > 0.5) {
                            if (ffmpegAvDiagEnabled()) {
                                qDebug() << "[FFmpeg][AVDiag] PTS jump backward, clamping:"
                                         << "prev=" << m_lastVideoPtsRaw << "new=" << framePts
                                         << "jump=" << (-jumpBack) << "dur=" << estFrameDurSec;
                            }
                            framePts = m_lastVideoPtsRaw + estFrameDurSec;
                        }
                    }
                }
                m_lastVideoPtsRaw = framePts;

                if (m_audioCodecContext && m_holdVideoUntilAudio.load(std::memory_order_acquire)) {
                    if (m_audioSeekPending.load(std::memory_order_acquire)
                        || std::isnan(m_firstAudioPts)
                        || (m_audioBaseWallTime > 0.0 && nowSeconds() < m_audioBaseWallTime)) {
                        av_frame_unref(m_frame);
                        continue;
                    }
                    m_holdVideoUntilAudio.store(false, std::memory_order_release);
                    FFLOG("[FFmpeg] Audio ready - video presentation can now start");
                    if (ffmpegAvDiagEnabled()) {
                        qDebug() << "[FFmpeg][AVDiag] Hold released (video can proceed): wallUs=" << avWallMicros()
                                 << "nowSec=" << nowSeconds()
                                 << "framePts=" << framePts
                                 << "firstAudioPts=" << m_firstAudioPts
                                 << "rawVideoPts_minus_firstAudioPts=" << (framePts - m_firstAudioPts)
                                 << "audioBaseWallTime=" << m_audioBaseWallTime
                                 << "audioBasePts=" << m_audioBasePts
                                 << "audioSeekPending=" << m_audioSeekPending.load()
                                 << "lastQueuedUSecs_est=" << m_lastQueuedAudioUSecs.load();
                    }
                }
                
                if (m_seekPending.load(std::memory_order_acquire)) {
                    constexpr double EPS = 0.0005;
                    if (std::isnan(framePts) || framePts + EPS < m_seekTargetPts) {
                        FFLOG("[FFmpeg] Dropping frame before seek target - frame PTS:" << framePts 
                                     << "target PTS:" << m_seekTargetPts);
                        av_frame_unref(m_frame);
                        continue;
                    } else {
                        FFLOG("[FFmpeg] Reached seek target - frame PTS:" << framePts 
                                 << "target PTS:" << m_seekTargetPts);
                        m_seekPending.store(false, std::memory_order_release);
                        m_timingInitialized = false;
                        
                        goto process_frame;
                    }
                } else {
                    process_frame:
                        
                        if (!m_timingInitialized && !std::isnan(framePts)) {
                        if (m_audioCodecContext && std::isnan(m_firstAudioPts)) {
                            av_frame_unref(m_frame);
                            continue;
                        }
                        if (std::isnan(m_firstVideoPts))
                            m_firstVideoPts = framePts;
                        m_startPts = framePts;
                        m_startTime = nowSeconds();
                        m_timingInitialized = true;
                        qDebug() << "[FFmpeg] Timing initialized - start time:" << m_startTime << "start PTS:" << m_startPts
                                 << "audio ready:" << (!std::isnan(m_audioBasePts) && m_audioSink);
                        if (ffmpegAvDiagEnabled()) {
                            qDebug() << "[FFmpeg][AVDiag] Timing init detail: wallUs=" << avWallMicros()
                                     << "startPts=" << m_startPts
                                     << "startWallSec=" << m_startTime
                                     << "playStartWallSec=" << m_playStartWallTime
                                     << "audioBasePts=" << m_audioBasePts
                                     << "audioBaseWallTime=" << m_audioBaseWallTime
                                     << "firstAudioPts=" << m_firstAudioPts
                                     << "startPts_minus_firstAudioPts=" << (m_startPts - m_firstAudioPts);
                        }
                    }
                    
                    if (m_timingInitialized && !std::isnan(framePts)) {
                        double masterClockAbs;
                        if (m_audioSink && m_audioCodecContext) {
                            if (!std::isnan(m_audioBasePts) && m_audioDevice && m_audioDevice->isOpen()) {
                                refreshAudioMasterClockForSync(masterClockAbs);

                                if (qgetenv("S3_FFMPEG_DISABLE_STREAM_PTS_GATE") != QByteArray("1") && !m_streamPtsGateDone) {
                                    m_streamPtsGateDone = true;
                                    if (ffmpegAvDiagEnabled()) {
                                        qDebug() << "[FFmpeg][AVDiag] stream PTS gate (once, non-blocking): finalMasterAudSec="
                                                 << masterClockAbs << "rawFramePts=" << framePts
                                                 << "wallUs=" << avWallMicros();
                                    }
                                }
                            } else {
                                masterClockAbs = m_startPts + (nowSeconds() - m_startTime);
                            }
                        } else {
                            masterClockAbs = m_startPts + (nowSeconds() - m_startTime);
                        }

                        if (!m_avSyncOffsetValid && !std::isnan(m_firstAudioPts) && !std::isnan(m_firstVideoPts)) {
                            const bool suspiciousFirstAudio = (m_firstAudioPts <= 0.0005);
                            if (suspiciousFirstAudio && m_audioCodecContext && m_audioCodecContext->codec_id == AV_CODEC_ID_AAC) {
                                m_avSyncNeedMasterCalib = true;
                            } else {
                                const double off = m_firstVideoPts - m_firstAudioPts;
                                if (std::isfinite(off) && std::fabs(off) < 60.0) {
                                    m_avSyncOffsetSec = off;
                                    m_avSyncOffsetValid = true;
                                    m_avSyncNeedMasterCalib = false;
                                    qDebug() << "[FFmpeg] First-PTS A/V offset:" << m_avSyncOffsetSec
                                             << "firstV=" << m_firstVideoPts << "firstA=" << m_firstAudioPts;
                                }
                            }
                        }

                        if (!m_avSyncOffsetValid && m_avSyncNeedMasterCalib
                            && m_audioSink && m_audioDevice && m_audioDevice->isOpen()
                            && std::isfinite(masterClockAbs) && std::isfinite(framePts)) {
                            if (masterClockAbs >= 0.10) {
                                const double off = framePts - masterClockAbs;
                                if (std::isfinite(off) && std::fabs(off) < 60.0) {
                                    m_avSyncOffsetSec = off;
                                    m_avSyncOffsetValid = true;
                                    m_avSyncNeedMasterCalib = false;
                                    qDebug() << "[FFmpeg] Master-clock A/V offset:" << m_avSyncOffsetSec
                                             << "framePts=" << framePts << "audioMaster=" << masterClockAbs;
                                }
                            }
                        }
                        
                        double videoClockAbs = framePts;
                        if (m_avSyncOffsetValid) {
                            videoClockAbs = framePts - m_avSyncOffsetSec;
                        }

                        if (m_avSyncOffsetValid
                            && m_audioSink && m_audioCodecContext && !std::isnan(m_audioBasePts)
                            && m_audioDevice && m_audioDevice->isOpen()
                            && m_playStartWallTime > 0.0
                            && (nowSeconds() - m_playStartWallTime) < 20.0) {
                            const double curDiff = (videoClockAbs - masterClockAbs);
                            const double sincePlay = nowSeconds() - m_playStartWallTime;
                            if (sincePlay > 1.5 && m_avSyncRefineCount < 2
                                && std::isfinite(curDiff) && std::fabs(curDiff) > 0.20 && std::fabs(curDiff) < 2.5) {
                                m_avSyncOffsetSec += curDiff;
                                videoClockAbs = framePts - m_avSyncOffsetSec;
                                m_avSyncRefineCount++;
                                m_avSyncOffsetRefinedFromMaster = true;
                                qDebug() << "[FFmpeg] Refined A/V offset from audio master (cancel diff):" << m_avSyncOffsetSec
                                         << "diffWas=" << curDiff << "refineCount=" << m_avSyncRefineCount;
                            }
                        }

                        static double s_lastStatsWall = 0.0;
                        const double diff = (videoClockAbs - masterClockAbs);

                        double frameDurationSec = estFrameDurSec;
                        const qint64 startUs = static_cast<qint64>(videoClockAbs * 1000000.0);
                        qint64 endUs = static_cast<qint64>((videoClockAbs + frameDurationSec) * 1000000.0);
                        if (endUs <= startUs) {
                            endUs = startUs + qMax<qint64>(1, static_cast<qint64>(frameDurationSec * 1000000.0));
                        }
                        m_curVideoStartUs = startUs;
                        m_curVideoEndUs = endUs;

                        avDiagLogPacedFrame(framePts, masterClockAbs, videoClockAbs, diff,
                                            m_avSyncOffsetValid ? m_avSyncOffsetSec : NAN);
                        
                        const qint64 newPosMs = static_cast<qint64>(masterClockAbs * 1000.0);
                        if (qAbs(newPosMs - m_position) >= 15) {
                            m_position = newPosMs;
                            emit positionChanged();
                        }
                        
                        static int frameCount = 0;
                        if ((frameCount++ % 30) == 0) {
                            qDebug() << "[FFmpeg] Frame timing - video:" << videoClockAbs
                                     << "master:" << masterClockAbs
                                     << "delay:" << diff
                                     << "audio:" << (!std::isnan(m_audioBasePts) && m_audioSink && m_audioDevice && m_audioDevice->isOpen());
                        }

                        const double nowWall = nowSeconds();
                        if (s_lastStatsWall <= 0.0)
                            s_lastStatsWall = nowWall;
                        if ((nowWall - s_lastStatsWall) >= 2.0) {
                            int queuedSz = 0;
                            {
                                QMutexLocker ql(&m_videoQueueMutex);
                                queuedSz = int(m_videoQueue.size());
                            }
                            qDebug() << "[FFmpeg] Pacing stats (2s)"
                                     << "queuedVideo=" << queuedSz;
                            s_lastStatsWall = nowWall;
                        }
                    }
                }
            }
                
            if (m_frame->format == AV_PIX_FMT_NV12 || 
                m_frame->format == AV_PIX_FMT_YUV420P || 
                m_frame->format == AV_PIX_FMT_BGRA) {
                processFrame(m_frame);
                if (m_startupNoDropFrames > 0)
                    --m_startupNoDropFrames;
            } else if (m_frame->format == AV_PIX_FMT_D3D11) {
                if (m_transferFrame && m_codecContext->hw_device_ctx) {
                    av_frame_unref(m_transferFrame);
                    
                    int ret = av_hwframe_transfer_data(m_transferFrame, m_frame, 0);
                    if (ret == 0) {
                        static int consecutiveFailures = 0;
                        if (consecutiveFailures > 0) {
                            consecutiveFailures = 0;
                        }
                        
                        AVPixelFormat transferredFormat = (AVPixelFormat)m_transferFrame->format;
                        
                        if (m_videoStream) {
                            m_transferFrame->pts = m_frame->pts;
                            m_transferFrame->best_effort_timestamp = m_frame->best_effort_timestamp;
                            m_transferFrame->pkt_dts = m_frame->pkt_dts;
                            m_transferFrame->pkt_pos = m_frame->pkt_pos;
                            m_transferFrame->duration = m_frame->duration;
                        }
                        
                        if (transferredFormat == AV_PIX_FMT_P010LE || 
                            transferredFormat == AV_PIX_FMT_YUV420P10LE) {
                            m_transferFrame->color_range = AVCOL_RANGE_MPEG;
                            m_transferFrame->color_primaries = AVCOL_PRI_BT2020;
                            m_transferFrame->color_trc = AVCOL_TRC_SMPTE2084;
                            m_transferFrame->colorspace = AVCOL_SPC_BT2020_NCL;
                            processFrame(m_transferFrame);
                            if (m_startupNoDropFrames > 0)
                                --m_startupNoDropFrames;
                        } else if (transferredFormat == AV_PIX_FMT_NV12 || 
                                   transferredFormat == AV_PIX_FMT_YUV420P ||
                                   transferredFormat == AV_PIX_FMT_BGRA) {
                            processFrame(m_transferFrame);
                            if (m_startupNoDropFrames > 0)
                                --m_startupNoDropFrames;
                        } else {
                            qWarning() << "[FFmpeg] Unsupported format from D3D11 transfer:" 
                                       << av_get_pix_fmt_name(transferredFormat) 
                                       << "- attempting conversion to NV12";
                            processFrame(m_transferFrame);
                        }
                    } else {
                        char errbuf[AV_ERROR_MAX_STRING_SIZE];
                        av_strerror(ret, errbuf, sizeof(errbuf));
                        
                        static int consecutiveFailures = 0;
                        if (ret == AVERROR(ENOMEM) || ret == -1313558101 || ret == AVERROR(EAGAIN)) {
                            consecutiveFailures++;
                            if (consecutiveFailures <= 3) {
                                qDebug() << "[FFmpeg] D3D11 transfer failed (surface busy/memory):" << errbuf 
                                         << "- skipping frame (attempt" << consecutiveFailures << ")";
                            } else if (consecutiveFailures == 4) {
                                qWarning() << "[FFmpeg] D3D11 transfer failing repeatedly (" << consecutiveFailures 
                                          << " consecutive failures) - may indicate resource leak or GPU device issue";
                            }
                        } else {
                            consecutiveFailures = 0;
                            qWarning() << "[FFmpeg] Failed to transfer D3D11 frame to system memory:" << ret << errbuf;
                        }
                        
                        av_frame_unref(m_frame);
                    }
                } else {
                    qWarning() << "[FFmpeg] Cannot transfer D3D11 frame - missing transfer frame or context";
                }
            } else if (m_frame->format == AV_PIX_FMT_CUDA) {
                FFLOG("[FFmpeg] Received CUDA frame (unexpected with D3D11VA)");
                ID3D11Texture2D* d3d11Texture = nullptr;
                if (transferCUDAToD3D11(m_frame, &d3d11Texture) && d3d11Texture) {
                    D3D11_TEXTURE2D_DESC desc;
                    d3d11Texture->GetDesc(&desc);
                    
                    {
                        QMutexLocker locker(&m_pendingFrameMutex);
                        
                        if (m_pendingFrame.texture) {
                            m_pendingFrame.texture->Release();
                        }
                        
                        d3d11Texture->AddRef();
                        m_pendingFrame.texture = d3d11Texture;
                        m_pendingFrame.width = static_cast<int>(desc.Width);
                        m_pendingFrame.height = static_cast<int>(desc.Height);
                    }
                    
                    if (m_window) {
                        QMetaObject::invokeMethod(m_window, "update", Qt::QueuedConnection);
                    }
                }
            }
                
            av_frame_unref(m_frame);
        } else if (ret == AVERROR(EAGAIN)) {
            // Decoder needs more input - read and send packets
            {
                QMutexLocker demuxLocker(&m_demuxMutex);
                ret = av_read_frame(m_formatContext, m_packet);
            }
            
            if (ret == AVERROR_EOF) {
                // End of stream - drain decoder ONCE if we've sent packets
                if (!m_decoderDrained && m_sentAnyPacket) {
                    FFLOG("[FFmpeg] End of stream, draining decoder");
                    ret = avcodec_send_packet(m_codecContext, nullptr);
                    if (ret < 0 && ret != AVERROR(EAGAIN)) {
                        qWarning() << "[FFmpeg] Failed to send drain packet:" << ret;
                    } else {
                        m_decoderDrained = true;
                    }
                } else {
                    // Already drained or no packets sent - stop decoding
                    if (m_decoderDrained) {
                        // Decoder already drained - stop playback
                        QMutexLocker stateLocker(&m_decodeMutex);
                        m_isPlaying.store(false, std::memory_order_release);
                        emit playbackStateChanged();
                        FFLOG("[FFmpeg] Playback finished (decoder drained)");
                    }
                    QThread::msleep(100);
                }
            } else if (ret < 0) {
                // Read error
                qWarning() << "[FFmpeg] av_read_frame error:" << ret;
                QThread::msleep(10);
            } else {
                // Valid packet - process video or audio stream
                if (m_packet->stream_index == m_videoStreamIndex) {
                    ret = avcodec_send_packet(m_codecContext, m_packet);
                    FFLOG("[FFmpeg] send_packet ret:" << ret
                             << "pkt pts:" << m_packet->pts
                             << "dts:" << m_packet->dts
                             << "size:" << m_packet->size);
                    if (ret == 0) {
                        // Successfully sent packet
                        m_sentAnyPacket = true;
                        // Reset error counter on success
                        static int consecutiveSendErrors = 0;
                        if (consecutiveSendErrors > 0) {
                            consecutiveSendErrors = 0;
                        }
                    } else if (ret != AVERROR(EAGAIN)) {
                        // HEVC decode failures are often recoverable - log but continue
                        // The decoder will flush and continue with next packets
                        char errbuf[AV_ERROR_MAX_STRING_SIZE];
                        av_strerror(ret, errbuf, sizeof(errbuf));
                        static int consecutiveSendErrors = 0;
                        consecutiveSendErrors++;
                        if (consecutiveSendErrors <= 3) {
                            qDebug() << "[FFmpeg] Failed to send video packet:" << ret << errbuf << "- attempt" << consecutiveSendErrors;
                        } else if (consecutiveSendErrors == 4) {
                            qWarning() << "[FFmpeg] Video packet send failing repeatedly - may indicate codec/device issue";
                        }
                        // Continue to next packet - decoder might recover
                    }
                } else if (m_packet->stream_index == m_audioStreamIndex && m_audioCodecContext) {
                    // Handle audio packet
                    ret = avcodec_send_packet(m_audioCodecContext, m_packet);
                    if (ret == 0) {
                        // Decode audio frames
                        while (avcodec_receive_frame(m_audioCodecContext, m_audioFrame) == 0) {
                            if (!m_swr || !m_audioDevice) {
                                av_frame_unref(m_audioFrame);
                                continue;
                            }
                            
                            // ✅ Drop audio frames until we reach seek target (same as video)
                            if (m_audioSeekPending.load(std::memory_order_acquire)) {
                                double aPts = NAN;
                                AVStream* audioStream = m_formatContext->streams[m_audioStreamIndex];
                                auto tsToSec = [](const AVStream* st, int64_t ts) -> double {
                                    if (!st || ts == AV_NOPTS_VALUE)
                                        return NAN;
                                    const int64_t start = (st->start_time != AV_NOPTS_VALUE) ? st->start_time : 0;
                                    const double sec = double(ts - start) * av_q2d(st->time_base);
                                    return sec;
                                };
                                aPts = tsToSec(audioStream, m_audioFrame->best_effort_timestamp);
                                if (std::isnan(aPts))
                                    aPts = tsToSec(audioStream, m_audioFrame->pts);
                                
                                // Drop frames before target (allow small tolerance for imprecise seeks)
                                constexpr double EPS = 0.0005; // 0.5ms tolerance
                                if (std::isnan(aPts) || aPts + EPS < m_audioSeekTargetSec) {
                                    av_frame_unref(m_audioFrame);
                                    continue; // Drop this frame
                                }
                                
                                // ✅ First good audio frame after seek - clear seek pending and set clock
                                m_audioSeekPending.store(false, std::memory_order_release);
                                // AAC (and some other codecs) can report a first decoded frame at PTS=0 even though
                                // the first *audible* sample is later due to decoder priming/skip samples.
                                // Compensate using AV_FRAME_DATA_SKIP_SAMPLES when available.
                                const double skipSec = audioSkipSamplesStartSec(m_audioFrame, m_audioCodecContext ? m_audioCodecContext->sample_rate : 0);
                                m_audioBasePts = aPts + skipSec;  // Set audio base PTS to audible start
                                // Anchor wall clock at decode time (do NOT delay by queued audio).
                                // Audible position is handled in refreshAudioMasterClockForSync() by subtracting queued.
                                {
                                    qint64 queuedUSecs = 0;
                                    QMutexLocker audioLock(&m_audioMutex);
                                    if (m_audioSink && m_audioDevice && m_audioDevice->isOpen()) {
                                        const int bytesPerFrame = m_audioFormat.bytesPerFrame();
                                        const int sampleRate = m_audioFormat.sampleRate();
                                        if (bytesPerFrame > 0 && sampleRate > 0) {
                                            const qint64 bufferUSecs = (qint64(m_audioSink->bufferSize()) * 1000000) /
                                                                       (bytesPerFrame * sampleRate);
                                            const qint64 freeUSecsRaw = (qint64(m_audioSink->bytesFree()) * 1000000) /
                                                                        (bytesPerFrame * sampleRate);
                                            const qint64 freeClamped = qBound<qint64>(0, freeUSecsRaw, bufferUSecs);
                                            queuedUSecs = bufferUSecs - freeClamped;
                                        }
                                    }
                                    m_lastQueuedAudioUSecs.store(queuedUSecs, std::memory_order_release);
                                    m_audioBaseWallTime = nowSeconds();
                                    if (ffmpegAvDiagEnabled()) {
                                        qDebug() << "[FFmpeg][AVDiag] First audio clock anchor (post-seek): wallUs=" << avWallMicros()
                                                 << "aPts=" << aPts
                                                 << "audioSeekTargetSec=" << m_audioSeekTargetSec
                                                 << "queuedUSecs_raw=" << queuedUSecs
                                                 << "audioBaseWallTime=" << m_audioBaseWallTime
                                                 << "nowSec=" << nowSeconds()
                                                 << "processedUSecs=" << (m_audioSink ? m_audioSink->processedUSecs() : qint64(-1));
                                    }
                                }
                                m_audioClock = m_audioBasePts;    // Initialize clock to audible PTS
                                // Reset A/V offset after seek; we'll re-learn using the new stream start.
                                m_firstAudioPts = m_audioBasePts; // mark first audible audio PTS post-seek
                                m_firstVideoPts = NAN;
                                m_avSyncOffsetValid = false;
                                
                                // ✅ FIX #2: Rebase processedUSecs() to this moment (prevents clock jump from old playback)
                                // Snapshot the current processedUSecs() so we can compute delta from this point
                                {
                                    QMutexLocker audioLock(&m_audioMutex);
                                    m_audioProcessedBaseUSecs = m_audioSink ? m_audioSink->processedUSecs() : 0;
                                }
                                
                                // ✅ Clear video hold flag - audio is now ready, video can start presenting
                                m_holdVideoUntilAudio.store(false, std::memory_order_release);
                                
                                qDebug() << "[FFmpeg] First good audio frame after seek - PTS:" << aPts
                                         << "skipSec:" << skipSec
                                         << "target:" << m_audioSeekTargetSec
                                         << "processedBaseUSecs:" << m_audioProcessedBaseUSecs
                                         << "(video hold cleared)";
                            }

                            double frameAudioPts = NAN;
                            {
                                AVStream* aStream = m_formatContext->streams[m_audioStreamIndex];
                                auto tsToSec = [](const AVStream* st, int64_t ts) -> double {
                                    if (!st || ts == AV_NOPTS_VALUE)
                                        return NAN;
                                    const int64_t start = (st->start_time != AV_NOPTS_VALUE) ? st->start_time : 0;
                                    const double sec = double(ts - start) * av_q2d(st->time_base);
                                    return sec;
                                };
                                frameAudioPts = tsToSec(aStream, m_audioFrame->best_effort_timestamp);
                                if (std::isnan(frameAudioPts))
                                    frameAudioPts = tsToSec(aStream, m_audioFrame->pts);
                            }
                            
                            // Flush any remainder from previous write
                            if (!m_audioRemainder.isEmpty()) {
                                QMutexLocker audioLock(&m_audioMutex);
                                if (m_audioSink && m_audioDevice && m_audioDevice->isOpen()) {
                                    int freeBytes = m_audioSink->bytesFree();
                                    if (freeBytes > 0) {
                                        int toWrite = qMin(freeBytes, m_audioRemainder.size());
                                        qint64 written = m_audioDevice->write(m_audioRemainder.constData(), toWrite);
                                        if (written > 0) {
                                            m_audioRemainder.remove(0, written);
                                            const qint64 snapProc = m_audioSink ? m_audioSink->processedUSecs() : qint64(-1);
                                            const qint64 snapBuf = m_audioSink ? qint64(m_audioSink->bufferSize()) : qint64(-1);
                                            const int snapFree = (m_audioDevice && m_audioDevice->isOpen() && m_audioSink)
                                                                     ? m_audioSink->bytesFree()
                                                                     : -1;
                                            const int snapSt = m_audioSink ? int(m_audioSink->state()) : -1;
                                            avDiagLogFirstAudioWrite(written, snapProc, snapBuf, snapFree, snapSt);
                                            avDiagLogAudioWriteSeq(written, snapProc, snapFree);
                                            reanchorAudioMasterIfCriticallyLowBytesFreeLocked(frameAudioPts, snapFree);
                                        }
                                    }
                                }
                            }
                            
                            // ✅ CRITICAL FIX: Use OUTPUT channel count, not input channel count
                            // We resample to m_audioFormat.channelCount() (often 2 stereo), not input channels (often 6)
                            // Wrong channel count causes incorrect buffer sizes, wrong bytes calculation, and audio sync issues
                            const int outChannels = m_audioFormat.channelCount();  // Output channels (what we're resampling TO)
                            const int outBps = outChannels * sizeof(int16_t);      // Bytes per sample (output format)
                            
                            // Calculate output buffer size
                            int outSamples = swr_get_out_samples(m_swr, m_audioFrame->nb_samples);
                            int outBufferSize = outSamples * outBps;  // Use output bytes per sample
                            
                            QByteArray buffer;
                            buffer.resize(outBufferSize);
                            uint8_t* outData[1] = { reinterpret_cast<uint8_t*>(buffer.data()) };
                            
                            // Resample audio
                            int samplesConverted = swr_convert(
                                m_swr,
                                outData,
                                outSamples,
                                const_cast<const uint8_t**>(m_audioFrame->data),
                                m_audioFrame->nb_samples
                            );
                            
                            if (samplesConverted > 0) {
                                int bytes = samplesConverted * outBps;  // Use output bytes per sample
                                
                                // Write to audio device (non-blocking with bytesFree check)
                                // ✅ FIX: Protect all audio device/sink access with mutex
                                {
                                    QMutexLocker audioLock(&m_audioMutex);
                                    if (m_audioSink && m_audioDevice && m_audioDevice->isOpen()) {
                                        int freeBytes = m_audioSink->bytesFree();
                                        if (freeBytes > 0) {
                                            int toWrite = qMin(freeBytes, bytes);
                                            qint64 written = m_audioDevice->write(buffer.constData(), toWrite);
                                            if (written > 0) {
                                                const qint64 snapProc = m_audioSink ? m_audioSink->processedUSecs() : qint64(-1);
                                                const qint64 snapBuf = m_audioSink ? qint64(m_audioSink->bufferSize()) : qint64(-1);
                                                const int snapFree = (m_audioDevice && m_audioDevice->isOpen() && m_audioSink)
                                                                         ? m_audioSink->bytesFree()
                                                                         : -1;
                                                const int snapSt = m_audioSink ? int(m_audioSink->state()) : -1;
                                                avDiagLogFirstAudioWrite(written, snapProc, snapBuf, snapFree, snapSt);
                                                avDiagLogAudioWriteSeq(written, snapProc, snapFree);
                                                reanchorAudioMasterIfCriticallyLowBytesFreeLocked(frameAudioPts, snapFree);
                                            }
                                            // Periodic audio health stats (helps diagnose "no sound" cases)
                                            static double s_lastAudStatWall = 0.0;
                                            const double nowWall = nowSeconds();
                                            if (s_lastAudStatWall <= 0.0)
                                                s_lastAudStatWall = nowWall;
                                            if ((nowWall - s_lastAudStatWall) >= 1.0) {
                                                qDebug() << "[FFmpeg][Audio] write"
                                                         << "want=" << bytes
                                                         << "toWrite=" << toWrite
                                                         << "written=" << written
                                                         << "free=" << freeBytes
                                                         << "buf=" << (m_audioSink ? m_audioSink->bufferSize() : -1)
                                                         << "state=" << (m_audioSink ? int(m_audioSink->state()) : -1)
                                                         << "vol=" << (m_audioSink ? m_audioSink->volume() : -1.0)
                                                         << "procUs=" << (m_audioSink ? m_audioSink->processedUSecs() : qint64(-1))
                                                         << "framePts=" << frameAudioPts;
                                                s_lastAudStatWall = nowWall;
                                            }
                                            
                                            // If we couldn't write everything, keep the remainder for later
                                            if (written < bytes) {
                                                m_audioRemainder = buffer.mid(written, bytes - written);
                                            } else if (!m_audioRemainder.isEmpty() && written == toWrite) {
                                                // Try to write remainder if we wrote everything
                                                int remainderFree = m_audioSink->bytesFree();
                                                if (remainderFree > 0) {
                                                    int remainderToWrite = qMin(remainderFree, m_audioRemainder.size());
                                                    qint64 remainderWritten = m_audioDevice->write(m_audioRemainder.constData(), remainderToWrite);
                                                    if (remainderWritten > 0) {
                                                        m_audioRemainder.remove(0, remainderWritten);
                                                        const qint64 snapProc = m_audioSink ? m_audioSink->processedUSecs() : qint64(-1);
                                                        const qint64 snapBuf = m_audioSink ? qint64(m_audioSink->bufferSize()) : qint64(-1);
                                                        const int snapFree = (m_audioDevice && m_audioDevice->isOpen() && m_audioSink)
                                                                                 ? m_audioSink->bytesFree()
                                                                                 : -1;
                                                        const int snapSt = m_audioSink ? int(m_audioSink->state()) : -1;
                                                        avDiagLogFirstAudioWrite(remainderWritten, snapProc, snapBuf, snapFree, snapSt);
                                                        avDiagLogAudioWriteSeq(remainderWritten, snapProc, snapFree);
                                                        reanchorAudioMasterIfCriticallyLowBytesFreeLocked(frameAudioPts, snapFree);
                                                    }
                                                }
                                            }
                                        } else {
                                            // Buffer full - store remainder
                                            m_audioRemainder = buffer;
                                            static double s_lastAudFullWall = 0.0;
                                            const double nowWall = nowSeconds();
                                            if (s_lastAudFullWall <= 0.0 || (nowWall - s_lastAudFullWall) >= 1.0) {
                                                const int st = int(m_audioSink->state());
                                                qWarning() << "[FFmpeg][Audio] bytesFree=0 (buffer full), storing remainder"
                                                           << "bytes=" << bytes
                                                           << "rem=" << m_audioRemainder.size()
                                                           << "state=" << st
                                                           << "vol=" << m_audioSink->volume()
                                                           << "procUs=" << m_audioSink->processedUSecs();
                                                s_lastAudFullWall = nowWall;
                                            }

                                            // If the sink has stopped, try to restart it (otherwise we will stay silent forever).
                                            if (m_audioSink && m_audioSink->state() == QAudio::StoppedState) {
                                                // Restart on the object's thread.
                                                QMetaObject::invokeMethod(this, [this]() {
                                                    QMutexLocker al(&m_audioMutex);
                                                    if (!m_audioSink)
                                                        return;
                                                    qWarning() << "[FFmpeg][Audio] Sink is StoppedState - restarting audio sink";
                                                    if (m_audioDevice && m_audioDevice->isOpen())
                                                        m_audioDevice->close();
                                                    m_audioSink->stop();
                                                    m_audioDevice = nullptr;
                                                    m_audioSink->setVolume(m_volume);
                                                    m_audioDevice = m_audioSink->start();
                                                    if (!m_audioDevice || !m_audioDevice->isOpen()) {
                                                        qWarning() << "[FFmpeg][Audio] Restart failed - device not open";
                                                    } else {
                                                        qWarning() << "[FFmpeg][Audio] Restarted - bytesFree=" << m_audioSink->bytesFree()
                                                                   << "state=" << int(m_audioSink->state());
                                                    }
                                                }, Qt::BlockingQueuedConnection);
                                            }
                                        }
                                    }
                                    else {
                                        static double s_lastAudNoDevWall = 0.0;
                                        const double nowWall = nowSeconds();
                                        if (s_lastAudNoDevWall <= 0.0 || (nowWall - s_lastAudNoDevWall) >= 1.0) {
                                            qWarning() << "[FFmpeg][Audio] cannot write (sink/device not open)"
                                                       << "sink=" << (m_audioSink != nullptr)
                                                       << "dev=" << (m_audioDevice != nullptr)
                                                       << "open=" << (m_audioDevice && m_audioDevice->isOpen())
                                                       << "state=" << (m_audioSink ? int(m_audioSink->state()) : -1);
                                            s_lastAudNoDevWall = nowWall;
                                        }
                                    }
                                }
                                
                                // Update audio base PTS from frame timestamps (first frame only, if not already set by seek)
                                if (std::isnan(m_audioBasePts) && !m_audioSeekPending.load(std::memory_order_acquire)) {
                                    double ptsSec = NAN;
                                    AVStream* audioStream = m_formatContext->streams[m_audioStreamIndex];
                                    auto tsToSec = [](const AVStream* st, int64_t ts) -> double {
                                        if (!st || ts == AV_NOPTS_VALUE)
                                            return NAN;
                                        const int64_t start = (st->start_time != AV_NOPTS_VALUE) ? st->start_time : 0;
                                        const double sec = double(ts - start) * av_q2d(st->time_base);
                                        return sec;
                                    };
                                    ptsSec = tsToSec(audioStream, m_audioFrame->best_effort_timestamp);
                                    if (std::isnan(ptsSec))
                                        ptsSec = tsToSec(audioStream, m_audioFrame->pts);
                                    
                                    if (!std::isnan(ptsSec)) {
                                        const double skipSec = audioSkipSamplesStartSec(m_audioFrame, m_audioCodecContext ? m_audioCodecContext->sample_rate : 0);
                                        m_audioBasePts = ptsSec + skipSec;
                                        // Anchor wall clock at decode time (do NOT delay by queued audio).
                                        // Audible position is handled in refreshAudioMasterClockForSync() by subtracting queued.
                                        {
                                            qint64 queuedUSecs = 0;
                                            QMutexLocker audioLock(&m_audioMutex);
                                            if (m_audioSink && m_audioDevice && m_audioDevice->isOpen()) {
                                                const int bytesPerFrame = m_audioFormat.bytesPerFrame();
                                                const int sampleRate = m_audioFormat.sampleRate();
                                                if (bytesPerFrame > 0 && sampleRate > 0) {
                                                    const qint64 bufferUSecs = (qint64(m_audioSink->bufferSize()) * 1000000) /
                                                                               (bytesPerFrame * sampleRate);
                                                    const qint64 freeUSecsRaw = (qint64(m_audioSink->bytesFree()) * 1000000) /
                                                                                (bytesPerFrame * sampleRate);
                                                    const qint64 freeClamped = qBound<qint64>(0, freeUSecsRaw, bufferUSecs);
                                                    queuedUSecs = bufferUSecs - freeClamped;
                                                }
                                            }
                                            m_lastQueuedAudioUSecs.store(queuedUSecs, std::memory_order_release);
                                            m_audioBaseWallTime = nowSeconds();
                                            if (ffmpegAvDiagEnabled()) {
                                                qDebug() << "[FFmpeg][AVDiag] First audio clock anchor (startup): wallUs=" << avWallMicros()
                                                         << "ptsSec=" << ptsSec
                                                         << "queuedUSecs_raw=" << queuedUSecs
                                                         << "audioBaseWallTime=" << m_audioBaseWallTime
                                                         << "nowSec=" << nowSeconds()
                                                         << "processedUSecs=" << (m_audioSink ? m_audioSink->processedUSecs() : qint64(-1));
                                            }
                                        }
                                        m_audioClock = m_audioBasePts;  // Initialize clock (audible)
                                        // Learn A/V offset after initial audio start.
                                        m_firstAudioPts = m_audioBasePts; // mark first audible audio PTS at startup
                                        m_firstVideoPts = NAN;
                                        m_avSyncOffsetValid = false;
                                        // ✅ Also snapshot processedUSecs() for initial playback (not just after seek)
                                        {
                                            QMutexLocker audioLock(&m_audioMutex);
                                            m_audioProcessedBaseUSecs = m_audioSink ? m_audioSink->processedUSecs() : 0;
                                        }
                                    }
                                }
                                
                                // Audio clock is now updated from QAudioSink->processedUSecs() in video sync block
                            }
                            
                            av_frame_unref(m_audioFrame);
                        }
                    } else if (ret != AVERROR(EAGAIN)) {
                        qWarning() << "[FFmpeg] Failed to send audio packet:" << ret;
                    }
                }
                av_packet_unref(m_packet);
            }
        } else if (ret == AVERROR_EOF) {
            // Decoder fully drained
            FFLOG("[FFmpeg] Decoder fully drained (EOF)");
            m_decoderDrained = true;
            {
                QMutexLocker stateLocker(&m_decodeMutex);
                m_isPlaying.store(false, std::memory_order_release);
                emit playbackStateChanged();
            }
            QThread::msleep(100);
        } else {
            // Other receive_frame error (not EAGAIN, not EOF, not success)
            qWarning() << "[FFmpeg] receive_frame error:" << ret;
        }
    }
    
    qDebug() << "[FFmpeg] Decode thread stopped";
}

void FFmpegVideoPlayer::decodeFrame()
{
    // This is called from the timer on GUI thread
    // Frame processing is now done in decode thread via frameReady signal
    // The renderer receives frames via frameReady signal
}
