#include "ffmpegvideoplayer.h"
#include "ffmpegvideorenderer.h"
#include <QDebug>
#include <QDir>
#include <QVideoFrame>
#include <QVideoFrameFormat>
#include <QImage>
#include <QQuickWindow>
#include <QtGui/rhi/qrhi.h>
#include <cstdint>  // For INT64_MIN, INT64_MAX
#include <cmath>     // For std::isnan

// Debug logging macro - disable in hot loops for performance
#if 0
#define FFLOG(x) qDebug() << x
#else
#define FFLOG(x) do{}while(0)
#endif

// ---- Windows / D3D FIRST (MUST be outside extern "C") ----
#ifdef Q_OS_WIN
#include <windows.h>
#include <d3d11.h>      // Contains ID3D11VideoDevice, ID3D11VideoContext, VideoProcessorBlt (modern SDK)
#include <d3d11_1.h>
#include <dxgi1_6.h>
#pragma comment(lib, "d3d11.lib")
#pragma comment(lib, "dxgi.lib")
#endif

// ---- FFmpeg SECOND (inside extern "C") ----
extern "C" {
#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h>
#include <libavutil/avutil.h>
#include <libavutil/hwcontext.h>
#include <libavutil/hwcontext_d3d11va.h>  // vcpkg FFmpeg only provides D3D11VA (not D3D11)
#include <libavutil/hwcontext_cuda.h>     // For CUVID support
#include <libavutil/imgutils.h>
#include <libavutil/time.h>               // For av_gettime_relative() and av_usleep()
#include <libavutil/version.h>  // For version macros
#include <libavutil/channel_layout.h>     // For channel layout functions
#include <libavutil/samplefmt.h>          // For sample format definitions
#include <libswresample/swresample.h>     // For audio resampling
#include <libswscale/swscale.h>           // For 10-bit to 8-bit video conversion
#include <libavfilter/avfilter.h>         // For HDR tone mapping
#include <libavfilter/buffersink.h>       // For filter output
#include <libavfilter/buffersrc.h>        // For filter input
}

// MSVC pragma comment for linking FFmpeg libraries (fallback if CMake doesn't link them)
#ifdef _MSC_VER
#pragma comment(lib, "swscale.lib")
#pragma comment(lib, "avfilter.lib")
#endif

FFmpegVideoPlayer::FFmpegVideoPlayer(QObject* parent)
    : QObject(parent)
{
    initFFmpeg();
    
    // Initialize FFmpeg (register all codecs, formats, etc.)
    av_log_set_level(AV_LOG_WARNING); // Reduce FFmpeg spam
}

FFmpegVideoPlayer::~FFmpegVideoPlayer()
{
    stop();
    
    // Stop decode thread
    {
        QMutexLocker locker(&m_decodeMutex);
        m_decodeThreadRunning = false;
        m_decodeCondition.wakeAll();
    }
    
    if (m_decodeThread) {
        m_decodeThread->wait(5000);
        delete m_decodeThread;
        m_decodeThread = nullptr;
    }
    
    closeMedia();
    cleanupD3D11();
    cleanupFFmpeg();
}

void FFmpegVideoPlayer::initFFmpeg()
{
    // FFmpeg is initialized globally (av_register_all is deprecated in newer versions)
    // We just need to ensure we're ready to use it
    
    // Print FFmpeg version information
    qDebug() << "[FFmpeg] Player initialized";
    qDebug() << "[FFmpeg] Version:" << av_version_info();
    qDebug() << "[FFmpeg] libavformat version:" << LIBAVFORMAT_VERSION_MAJOR << "." << LIBAVFORMAT_VERSION_MINOR << "." << LIBAVFORMAT_VERSION_MICRO;
    qDebug() << "[FFmpeg] libavcodec version:" << LIBAVCODEC_VERSION_MAJOR << "." << LIBAVCODEC_VERSION_MINOR << "." << LIBAVCODEC_VERSION_MICRO;
    qDebug() << "[FFmpeg] libavutil version:" << LIBAVUTIL_VERSION_MAJOR << "." << LIBAVUTIL_VERSION_MINOR << "." << LIBAVUTIL_VERSION_MICRO;
    
    // Note: AV_PIX_FMT_D3D11 and AV_HWDEVICE_TYPE_D3D11VA are enum values, not macros
    // They are always available if the headers are included correctly
    // We use AV_HWDEVICE_TYPE_D3D11VA (not AV_HWDEVICE_TYPE_D3D11) for device creation
    // We use AV_PIX_FMT_D3D11 for pixel format (renderable D3D11 texture)
}

void FFmpegVideoPlayer::cleanupFFmpeg()
{
    // Cleanup is done in closeMedia()
}

void FFmpegVideoPlayer::onSceneGraphInitialized()
{
    qDebug() << "[FFmpeg] Scene graph initialized — RHI is now available";
    
    // Initialize Qt's D3D11 device (needed for Video Processor, not for decoding)
    if (!initD3D11FromRHI()) {
        qWarning() << "[FFmpeg] Failed to initialize D3D11 from RHI (Video Processor may not work)";
        // Don't fail completely - decoding can still work with FFmpeg's own device
    } else {
        qDebug() << "[FFmpeg] Qt D3D11 device acquired (for Video Processor)";
    }
    
    // Open media (FFmpeg will create its own video-capable device for decoding)
    if (!m_source.isEmpty() && !m_formatContext) {
        qDebug() << "[FFmpeg] Opening media (FFmpeg will create its own video device)";
        openMedia();
    }
}

void FFmpegVideoPlayer::openMedia()
{
    // Guard: prevent multiple concurrent calls to openMedia()
    if (m_mediaOpening || m_mediaOpened) {
        qDebug() << "[FFmpeg] openMedia() ignored (already opening/opened)";
        return;
    }
    
    if (m_source.isEmpty() || !m_source.isValid()) {
        qWarning() << "[FFmpeg] Invalid source";
        m_mediaOpening = false;
        m_mediaOpened = false;
        return;
    }
    
    m_mediaOpening = true;
    
    // Note: We no longer require Qt's D3D11 device for decoding
    // FFmpeg will create its own video-capable device
    // Qt's device is still needed for Video Processor (will be initialized later if needed)
    
    QString filePath = m_source.toLocalFile();
    if (filePath.isEmpty()) {
        filePath = m_source.toString();
    }
    
    qDebug() << "[FFmpeg] Opening media:" << filePath;
    
    // Open input file
    m_formatContext = avformat_alloc_context();
    if (!m_formatContext) {
        qWarning() << "[FFmpeg] Failed to allocate format context";
        emit errorOccurred(-1, "Failed to allocate format context");
        m_mediaOpening = false;
        m_mediaOpened = false;
        return;
    }
    
    int ret = avformat_open_input(&m_formatContext, filePath.toUtf8().constData(), nullptr, nullptr);
    if (ret < 0) {
        char errbuf[AV_ERROR_MAX_STRING_SIZE];
        av_strerror(ret, errbuf, AV_ERROR_MAX_STRING_SIZE);
        qWarning() << "[FFmpeg] Failed to open input:" << errbuf;
        emit errorOccurred(ret, QString::fromUtf8(errbuf));
        avformat_free_context(m_formatContext);
        m_formatContext = nullptr;
        return;
    }
    
    // Find stream info
    ret = avformat_find_stream_info(m_formatContext, nullptr);
    if (ret < 0) {
        qWarning() << "[FFmpeg] Failed to find stream info";
        avformat_close_input(&m_formatContext);
        m_formatContext = nullptr;
        m_mediaOpening = false;
        m_mediaOpened = false;
        return;
    }
    
    // Find video stream
    m_videoStreamIndex = -1;
    for (unsigned int i = 0; i < m_formatContext->nb_streams; i++) {
        if (m_formatContext->streams[i]->codecpar->codec_type == AVMEDIA_TYPE_VIDEO) {
            m_videoStreamIndex = static_cast<int>(i);
            m_videoStream = m_formatContext->streams[i];  // Store stream pointer for time_base
            break;
        }
    }
    
    if (m_videoStreamIndex < 0) {
        qWarning() << "[FFmpeg] No video stream found";
        avformat_close_input(&m_formatContext);
        m_formatContext = nullptr;
        m_mediaOpening = false;
        m_mediaOpened = false;
        return;
    }
    
    // Find audio stream
    m_audioStreamIndex = -1;
    for (unsigned int i = 0; i < m_formatContext->nb_streams; i++) {
        if (m_formatContext->streams[i]->codecpar->codec_type == AVMEDIA_TYPE_AUDIO) {
            m_audioStreamIndex = static_cast<int>(i);
            break;
        }
    }
    
    // Open audio decoder if audio stream exists
    if (m_audioStreamIndex >= 0) {
        AVStream* audioStream = m_formatContext->streams[m_audioStreamIndex];
        const AVCodec* audioCodec = avcodec_find_decoder(audioStream->codecpar->codec_id);
        
        if (audioCodec) {
            m_audioCodecContext = avcodec_alloc_context3(audioCodec);
            if (m_audioCodecContext) {
                int ret = avcodec_parameters_to_context(m_audioCodecContext, audioStream->codecpar);
                if (ret >= 0) {
                    ret = avcodec_open2(m_audioCodecContext, audioCodec, nullptr);
                    if (ret >= 0) {
                        m_audioFrame = av_frame_alloc();
                        int inputChannels = m_audioCodecContext->ch_layout.nb_channels;
                        int inputSampleRate = m_audioCodecContext->sample_rate;
                        qDebug() << "[FFmpeg] Audio decoder opened - sample rate:" << inputSampleRate 
                                 << "channels:" << inputChannels;
                        
                        // ✅ FIX #1: Query device capabilities and find supported format
                        // Don't assume device supports multi-channel audio - fallback to stereo
                        QAudioDevice defaultDevice = QMediaDevices::defaultAudioOutput();
                        // In Qt 6, check if device is valid by checking description (empty means invalid)
                        if (defaultDevice.description().isEmpty()) {
                            qWarning() << "[FFmpeg] No default audio output device available - audio disabled";
                            // Clean up audio codec context since we can't use audio
                            avcodec_free_context(&m_audioCodecContext);
                            m_audioCodecContext = nullptr;
                        } else {
                            qDebug() << "[FFmpeg] Default audio device:" << defaultDevice.description();
                        
                        // Try to find a supported format: prefer original, fallback to stereo
                        int outputChannels = inputChannels;
                        int outputSampleRate = inputSampleRate;
                        
                        // Try original format first
                        m_audioFormat.setSampleRate(outputSampleRate);
                        m_audioFormat.setChannelCount(outputChannels);
                        m_audioFormat.setSampleFormat(QAudioFormat::Int16);
                        
                        // Check if format is supported
                        if (!defaultDevice.isFormatSupported(m_audioFormat)) {
                            qDebug() << "[FFmpeg] Original format (" << outputSampleRate << "Hz," << outputChannels 
                                     << "ch) not supported - trying stereo fallback";
                            // Fallback 1: Try stereo at same sample rate
                            outputChannels = 2;
                            m_audioFormat.setChannelCount(outputChannels);
                            
                            if (!defaultDevice.isFormatSupported(m_audioFormat)) {
                                qDebug() << "[FFmpeg] Stereo at" << outputSampleRate << "Hz not supported - trying 44.1kHz";
                                // Fallback 2: Try 44.1kHz stereo
                                outputSampleRate = 44100;
                                m_audioFormat.setSampleRate(outputSampleRate);
                                
                                if (!defaultDevice.isFormatSupported(m_audioFormat)) {
                                    qDebug() << "[FFmpeg] 44.1kHz stereo not supported - using device preferred format";
                                    // Fallback 3: Use device preferred format
                                    m_audioFormat = defaultDevice.preferredFormat();
                                    // Force Int16 for consistency
                                    if (m_audioFormat.sampleFormat() != QAudioFormat::Int16) {
                                        m_audioFormat.setSampleFormat(QAudioFormat::Int16);
                                        // Re-check if Int16 variant is supported
                                        if (!defaultDevice.isFormatSupported(m_audioFormat)) {
                                            m_audioFormat = defaultDevice.preferredFormat(); // Use as-is if Int16 not supported
                                        }
                                    }
                                    outputSampleRate = m_audioFormat.sampleRate();
                                    outputChannels = m_audioFormat.channelCount();
                                    qDebug() << "[FFmpeg] Using device preferred format:" << outputSampleRate << "Hz," 
                                             << outputChannels << "channels, format:" << m_audioFormat.sampleFormat();
                                }
                            }
                        }
                        
                        qDebug() << "[FFmpeg] Selected audio output format:" << m_audioFormat.sampleRate() << "Hz,"
                                 << m_audioFormat.channelCount() << "channels,"
                                 << "format:" << m_audioFormat.sampleFormat();
                        
                        m_audioSink = new QAudioSink(defaultDevice, m_audioFormat, this);
                        m_audioSink->setBufferSize(256 * 1024); // 256 KB buffer to prevent underruns
                        m_audioSink->setVolume(m_volume); // Apply current volume setting
                        m_audioDevice = m_audioSink->start();
                        
                        if (!m_audioDevice || !m_audioDevice->isOpen()) {
                            qWarning() << "[FFmpeg] Failed to start audio device - audio playback disabled";
                            m_audioSink->deleteLater();
                            m_audioSink = nullptr;
                            m_audioDevice = nullptr;
                        } else {
                            m_audioRemainder.clear();
                            qDebug() << "[FFmpeg] Audio sink created successfully with volume:" << m_volume;
                        }
                        
                        // ----- Setup audio resampler -----
                        // Only setup resampler if audio device started successfully
                        if (m_audioDevice && m_audioDevice->isOpen() && m_audioSink) {
                            if (m_swr) {
                                swr_free(&m_swr);
                            }
                            
                            AVChannelLayout outLayout = {};
                            // Use the selected output format (may be different from input if fallback was used)
                            av_channel_layout_default(&outLayout, m_audioFormat.channelCount());
                            
                            const AVChannelLayout* inLayout = &m_audioCodecContext->ch_layout;
                            
                            // ✅ Configure resampler to output format we selected (handles downmix if needed)
                            int r = swr_alloc_set_opts2(
                                &m_swr,
                                &outLayout,
                                AV_SAMPLE_FMT_S16,
                                m_audioFormat.sampleRate(),  // Output sample rate (may differ from input)
                                inLayout,
                                m_audioCodecContext->sample_fmt,
                                m_audioCodecContext->sample_rate,  // Input sample rate
                                0,
                                nullptr
                            );
                            
                            av_channel_layout_uninit(&outLayout);
                            
                            if (r < 0 || !m_swr) {
                                qWarning() << "[FFmpeg] Failed to allocate resampler - audio disabled";
                                swr_free(&m_swr);
                                m_swr = nullptr;
                                // Cleanup audio sink if resampler failed
                                if (m_audioSink) {
                                    if (m_audioDevice) {
                                        m_audioDevice->close();
                                    }
                                    m_audioSink->stop();
                                    m_audioSink->deleteLater();
                                    m_audioSink = nullptr;
                                    m_audioDevice = nullptr;
                                }
                            } else {
                                if (swr_init(m_swr) < 0) {
                                    qWarning() << "[FFmpeg] Failed to init resampler - audio disabled";
                                    swr_free(&m_swr);
                                    m_swr = nullptr;
                                    // Cleanup audio sink if resampler failed
                                    if (m_audioSink) {
                                        if (m_audioDevice) {
                                            m_audioDevice->close();
                                        }
                                        m_audioSink->stop();
                                        m_audioSink->deleteLater();
                                        m_audioSink = nullptr;
                                        m_audioDevice = nullptr;
                                    }
                                } else {
                                    qDebug() << "[FFmpeg] Audio resampler initialized - input:" << inputSampleRate << "Hz," 
                                             << inputChannels << "ch -> output:" << m_audioFormat.sampleRate() << "Hz," 
                                             << m_audioFormat.channelCount() << "ch";
                                }
                            }
                        }
                        } // End of else block for valid audio device
                    } else {
                        qWarning() << "[FFmpeg] Failed to open audio decoder";
                        avcodec_free_context(&m_audioCodecContext);
                        m_audioCodecContext = nullptr;
                    }
                } else {
                    qWarning() << "[FFmpeg] Failed to copy audio codec parameters";
                    avcodec_free_context(&m_audioCodecContext);
                    m_audioCodecContext = nullptr;
                }
            } else {
                qWarning() << "[FFmpeg] Failed to allocate audio codec context";
            }
        } else {
            qWarning() << "[FFmpeg] Audio codec not found";
        }
    } else {
        qDebug() << "[FFmpeg] No audio stream found";
    }
    
    // Get codec parameters
    AVCodecParameters* codecpar = m_formatContext->streams[m_videoStreamIndex]->codecpar;
    
    // Find decoder
    const AVCodec* codec = avcodec_find_decoder(codecpar->codec_id);
    if (!codec) {
        qWarning() << "[FFmpeg] Codec not found";
        avformat_close_input(&m_formatContext);
        m_formatContext = nullptr;
        m_mediaOpening = false;
        m_mediaOpened = false;
        return;
    }
    
    // Allocate codec context
    m_codecContext = avcodec_alloc_context3(codec);
    if (!m_codecContext) {
        qWarning() << "[FFmpeg] Failed to allocate codec context";
        avformat_close_input(&m_formatContext);
        m_formatContext = nullptr;
        m_mediaOpening = false;
        m_mediaOpened = false;
        return;
    }
    
    // Copy codec parameters to context
    ret = avcodec_parameters_to_context(m_codecContext, codecpar);
    if (ret < 0) {
        qWarning() << "[FFmpeg] Failed to copy codec parameters";
        avcodec_free_context(&m_codecContext);
        avformat_close_input(&m_formatContext);
        m_formatContext = nullptr;
        m_mediaOpening = false;
        m_mediaOpened = false;
        return;
    }
    
    // Detect GPU vendor and setup appropriate hardware decoder
    m_gpuVendor = detectGPUVendor();
    if (!setupHardwareDecoder()) {
        qWarning() << "[FFmpeg] Failed to setup hardware decoder";
        avcodec_free_context(&m_codecContext);
        avformat_close_input(&m_formatContext);
        m_formatContext = nullptr;
        m_mediaOpening = false;
        m_mediaOpened = false;
        return;
    }
    
    // ✅ Ensure opaque is set before opening codec (callback may be called during open)
    if (!m_codecContext->opaque) {
        m_codecContext->opaque = this;
    }
    
    // Open codec
    // Note: codec is the original decoder found above
    // For D3D11VA, we don't replace the codec context, so this is correct
    // (If we were using CUVID, we'd need to pass nullptr or the CUVID codec here)
    ret = avcodec_open2(m_codecContext, codec, nullptr);
    if (ret < 0) {
        char errbuf[AV_ERROR_MAX_STRING_SIZE];
        av_strerror(ret, errbuf, AV_ERROR_MAX_STRING_SIZE);
        qWarning() << "[FFmpeg] Failed to open codec:" << errbuf;
        avcodec_free_context(&m_codecContext);
        avformat_close_input(&m_formatContext);
        m_formatContext = nullptr;
        m_mediaOpening = false;
        m_mediaOpened = false;
        return;
    }
    
    // Get video dimensions (coded size)
    m_width = m_codecContext->width;
    m_height = m_codecContext->height;
    
    // Video Processor will be initialized lazily on first frame with actual texture dimensions
    emit implicitSizeChanged();
    
    // Get duration
    if (m_formatContext->duration != AV_NOPTS_VALUE) {
        m_duration = (m_formatContext->duration / AV_TIME_BASE) * 1000; // Convert to ms
        emit durationChanged();
        emit durationAvailable();
    }
    
    // ✅ FIX: Properly detect if stream is seekable
    // Check if format context has a seekable I/O context and supports seeking
    m_isSeekable = m_formatContext->pb != nullptr && 
                   (m_formatContext->pb->seekable & AVIO_SEEKABLE_NORMAL) != 0;
    emit seekableChanged();
    
    // Allocate frames
    m_frame = av_frame_alloc();
    m_hwFrame = av_frame_alloc();
    if (m_useCUDA) {
        m_swFrame = av_frame_alloc();  // For CUDA → system memory transfer
    }
    m_transferFrame = av_frame_alloc();  // ✅ Persistent frame for D3D11 → CPU transfer (reused, no per-frame alloc/free)
    m_packet = av_packet_alloc();
    
    if (!m_frame || !m_hwFrame || !m_packet || (m_useCUDA && !m_swFrame) || !m_transferFrame) {
        qWarning() << "[FFmpeg] Failed to allocate frames/packet";
        closeMedia();
        return;
    }
    
    qDebug() << "[FFmpeg] Media opened successfully:" << m_width << "x" << m_height << "duration:" << m_duration << "ms";
    
    // Mark media as successfully opened
    m_mediaOpening = false;
    m_mediaOpened = true;
    
    // Start decode thread
    {
        QMutexLocker locker(&m_decodeMutex);
        m_decodeThreadRunning = true;
    }
    
    m_decodeThread = QThread::create([this]() { decodeThreadFunc(); });
    m_decodeThread->start();
}

void FFmpegVideoPlayer::closeMedia()
{
    // Reset timing
    m_timingInitialized = false;
    m_startTime = 0.0;
    m_startPts = 0.0;
    m_videoStream = nullptr;
    
    // Stop decode thread
    {
        QMutexLocker locker(&m_decodeMutex);
        m_decodeThreadRunning = false;
        m_decodeCondition.wakeAll();
    }
    
    if (m_decodeThread) {
        m_decodeThread->wait(5000);
        delete m_decodeThread;
        m_decodeThread = nullptr;
    }
    
    // Frame queue is no longer used (zero-copy path)
    // Frames are passed directly via frameReady signal
    
    // Free FFmpeg resources
    if (m_packet) {
        av_packet_free(&m_packet);
        m_packet = nullptr;
    }
    
    if (m_frame) {
        av_frame_free(&m_frame);
        m_frame = nullptr;
    }
    
    if (m_hwFrame) {
        av_frame_free(&m_hwFrame);
        m_hwFrame = nullptr;
    }
    
    if (m_swFrame) {
        av_frame_free(&m_swFrame);
        m_swFrame = nullptr;
    }
    
    if (m_transferFrame) {
        av_frame_free(&m_transferFrame);
        m_transferFrame = nullptr;
    }
    
    if (m_codecContext) {
        avcodec_free_context(&m_codecContext);
        m_codecContext = nullptr;
    }
    
    if (m_hwFramesContext) {
        av_buffer_unref(&m_hwFramesContext);
        m_hwFramesContext = nullptr;
    }
    
    if (m_hwDeviceContext) {
        av_buffer_unref(&m_hwDeviceContext);
        m_hwDeviceContext = nullptr;
    }
    
    // Cleanup audio
    if (m_audioSink) {
        m_audioSink->stop();
        delete m_audioSink;
        m_audioSink = nullptr;
        m_audioDevice = nullptr;
    }
    
    if (m_swr) {
        swr_free(&m_swr);
        m_swr = nullptr;
    }
    
    // Cleanup 10-bit to 8-bit video converter (fallback, not used if filter graph active)
    if (m_sws10to8) {
        sws_freeContext(m_sws10to8);
        m_sws10to8 = nullptr;
    }
    if (m_tmp8bitFrame) {
        av_frame_free(&m_tmp8bitFrame);
        m_tmp8bitFrame = nullptr;
    }
    
    // Cleanup HDR tone mapping filter graph (explicit cleanup - reset initialization flag)
    // ✅ Use cleanup function to ensure flag is reset and all resources are freed properly
    cleanupHDRToneMappingFilter();
    
    if (m_audioFrame) {
        av_frame_free(&m_audioFrame);
        m_audioFrame = nullptr;
    }
    
    if (m_audioCodecContext) {
        avcodec_free_context(&m_audioCodecContext);
        m_audioCodecContext = nullptr;
    }
    
    if (m_formatContext) {
        avformat_close_input(&m_formatContext);
        m_formatContext = nullptr;
    }
    
    m_videoStreamIndex = -1;
    m_audioStreamIndex = -1;
    m_audioRemainder.clear();
    m_width = 0;
    m_height = 0;
    m_duration = 0;
    m_position = 0;
    m_audioClock = 0.0;
    
    // Reset lifecycle flags
    m_mediaOpened = false;
    m_mediaOpening = false;
    
    // Reset decoder state
    m_decoderDrained = false;
    m_sentAnyPacket = false;
    
    // Reset output texture dimensions
    m_outWidth = 0;
    m_outHeight = 0;
    
    emit implicitSizeChanged();
    emit durationChanged();
}

FFmpegVideoPlayer::GPUVendor FFmpegVideoPlayer::detectGPUVendor()
{
#ifdef Q_OS_WIN
    if (!m_d3d11Device) {
        qWarning() << "[FFmpeg] Cannot detect GPU vendor: D3D11 device not available";
        return GPU_VENDOR_UNKNOWN;
    }
    
    // Query DXGI adapter from D3D11 device
    IDXGIDevice* dxgiDevice = nullptr;
    HRESULT hr = m_d3d11Device->QueryInterface(__uuidof(IDXGIDevice), reinterpret_cast<void**>(&dxgiDevice));
    if (FAILED(hr) || !dxgiDevice) {
        qWarning() << "[FFmpeg] Failed to query DXGI device:" << hr;
        return GPU_VENDOR_UNKNOWN;
    }
    
    IDXGIAdapter* adapter = nullptr;
    hr = dxgiDevice->GetAdapter(&adapter);
    dxgiDevice->Release();
    
    if (FAILED(hr) || !adapter) {
        qWarning() << "[FFmpeg] Failed to get DXGI adapter:" << hr;
        return GPU_VENDOR_UNKNOWN;
    }
    
    DXGI_ADAPTER_DESC desc = {};
    hr = adapter->GetDesc(&desc);
    adapter->Release();
    
    if (FAILED(hr)) {
        qWarning() << "[FFmpeg] Failed to get adapter description:" << hr;
        return GPU_VENDOR_UNKNOWN;
    }
    
    // Check vendor ID
    // NVIDIA: 0x10DE
    // Intel: 0x8086
    // AMD: 0x1002
    GPUVendor vendor = GPU_VENDOR_UNKNOWN;
    if (desc.VendorId == 0x10DE) {
        vendor = GPU_VENDOR_NVIDIA;
        qDebug() << "[FFmpeg] Detected NVIDIA GPU:" << QString::fromWCharArray(desc.Description);
    } else if (desc.VendorId == 0x8086) {
        vendor = GPU_VENDOR_INTEL;
        qDebug() << "[FFmpeg] Detected Intel GPU:" << QString::fromWCharArray(desc.Description);
    } else if (desc.VendorId == 0x1002) {
        vendor = GPU_VENDOR_AMD;
        qDebug() << "[FFmpeg] Detected AMD GPU:" << QString::fromWCharArray(desc.Description);
    } else {
        qDebug() << "[FFmpeg] Unknown GPU vendor ID:" << QString::number(desc.VendorId, 16) << QString::fromWCharArray(desc.Description);
    }
    
    return vendor;
#else
    return GPU_VENDOR_UNKNOWN;
#endif
}

bool FFmpegVideoPlayer::setupHardwareDecoder()
{
#ifdef Q_OS_WIN
    // On Windows, use D3D11VA for all GPUs (NVIDIA, Intel, AMD)
    // D3D11VA uses NVDEC under the hood on NVIDIA GPUs, so we get hardware acceleration
    // without needing CUDA/CUVID, and we get zero-copy D3D11 textures
    qDebug() << "[FFmpeg] Using D3D11VA hardware decode (works on NVIDIA/Intel/AMD)";
    m_useCUDA = false;
    return setupD3D11VADecoder();
#else
    // Non-Windows platforms would use other hwaccel (VAAPI, VideoToolbox, etc.)
    return false;
#endif
}

bool FFmpegVideoPlayer::setupD3D11VADecoder()
{
#ifdef Q_OS_WIN
    if (!m_codecContext) {
        qWarning() << "[FFmpeg] Missing codec context";
        return false;
    }

    // ✅ FIX: Let FFmpeg create its own D3D11VA device instead of injecting Qt's device
    // Qt's RHI D3D11 device is great for rendering but can cause HEVC decode failures
    // (e.g., "Failed to add bitstream or slice control buffer") when used as a decode device
    // FFmpeg creating its own device is more stable across different drivers
    // We still transfer D3D11→CPU anyway, so device unification doesn't buy us much
    
    // Free any existing device context
    av_buffer_unref(&m_hwDeviceContext);
    
    // Let FFmpeg create its own D3D11VA device (nullptr = auto-create)
    int ret = av_hwdevice_ctx_create(&m_hwDeviceContext, AV_HWDEVICE_TYPE_D3D11VA, nullptr, nullptr, 0);
    if (ret < 0) {
        char errbuf[AV_ERROR_MAX_STRING_SIZE];
        av_strerror(ret, errbuf, sizeof(errbuf));
        qWarning() << "[FFmpeg] Failed to create D3D11VA device:" << errbuf;
        av_buffer_unref(&m_hwDeviceContext);
        return false;
    }
    
    qDebug() << "[FFmpeg] D3D11VA device created by FFmpeg (independent device, more stable for decode)";
    
    // CRITICAL: For D3D11VA, FFmpeg manages frames internally
    // DO NOT call av_hwframe_ctx_alloc() - it's not supported for D3D11VA
    // Only set hw_device_ctx and get_format callback
    
    // Attach device to codec context
    m_codecContext->hw_device_ctx = av_buffer_ref(m_hwDeviceContext);
    
    // Let FFmpeg pick the format via callback
    // ✅ Set opaque pointer so static callback can access instance
    m_codecContext->opaque = this;
    m_codecContext->get_format = getFormatCallback;

    qDebug() << "[FFmpeg] D3D11VA device initialized (FFmpeg-managed frames)";
    return true;
#else
    return false;
#endif
}

bool FFmpegVideoPlayer::setupCUDADecoder()
{
#ifdef Q_OS_WIN
    if (!m_codecContext || !m_formatContext || m_videoStreamIndex < 0) {
        qWarning() << "[FFmpeg] Missing codec context or stream info for CUVID setup";
        return false;
    }
    
    // Get codec ID from stream parameters (before we replace codec context)
    AVCodecParameters* codecpar = m_formatContext->streams[m_videoStreamIndex]->codecpar;
    AVCodecID codecId = codecpar->codec_id;
    
    // Get codec name based on codec ID
    const char* codecName = nullptr;
    switch (codecId) {
        case AV_CODEC_ID_H264:
            codecName = "h264_cuvid";
            break;
        case AV_CODEC_ID_HEVC:
            codecName = "hevc_cuvid";
            break;
        case AV_CODEC_ID_VP8:
            codecName = "vp8_cuvid";
            break;
        case AV_CODEC_ID_VP9:
            codecName = "vp9_cuvid";
            break;
        case AV_CODEC_ID_AV1:
            codecName = "av1_cuvid";
            break;
        default:
            qWarning() << "[FFmpeg] CUVID decoder not available for codec:" << codecId;
            return false;
    }
    
    // Create CUDA device context
    int ret = av_hwdevice_ctx_create(&m_hwDeviceContext, AV_HWDEVICE_TYPE_CUDA, nullptr, nullptr, 0);
    if (ret < 0) {
        char errbuf[AV_ERROR_MAX_STRING_SIZE];
        av_strerror(ret, errbuf, sizeof(errbuf));
        qWarning() << "[FFmpeg] Failed to create CUDA device context:" << errbuf;
        return false;
    }
    
    // Find CUVID decoder
    const AVCodec* cuvidCodec = avcodec_find_decoder_by_name(codecName);
    if (!cuvidCodec) {
        qWarning() << "[FFmpeg] CUVID decoder not found:" << codecName;
        av_buffer_unref(&m_hwDeviceContext);
        return false;
    }
    
    // Replace codec context with CUVID decoder
    avcodec_free_context(&m_codecContext);
    m_codecContext = avcodec_alloc_context3(cuvidCodec);
    if (!m_codecContext) {
        qWarning() << "[FFmpeg] Failed to allocate CUVID codec context";
        av_buffer_unref(&m_hwDeviceContext);
        return false;
    }
    
    // Copy codec parameters from stream
    ret = avcodec_parameters_to_context(m_codecContext, codecpar);
    if (ret < 0) {
        qWarning() << "[FFmpeg] Failed to copy codec parameters to CUVID context";
        avcodec_free_context(&m_codecContext);
        av_buffer_unref(&m_hwDeviceContext);
        return false;
    }
    
    // Attach CUDA device to codec context
    m_codecContext->hw_device_ctx = av_buffer_ref(m_hwDeviceContext);
    
    // Create hardware frames context for CUDA
    m_hwFramesContext = av_hwframe_ctx_alloc(m_hwDeviceContext);
    if (!m_hwFramesContext) {
        qWarning() << "[FFmpeg] Failed to allocate CUDA frames context";
        avcodec_free_context(&m_codecContext);
        av_buffer_unref(&m_hwDeviceContext);
        return false;
    }
    
    AVHWFramesContext* framesCtx = reinterpret_cast<AVHWFramesContext*>(m_hwFramesContext->data);
    framesCtx->format = AV_PIX_FMT_CUDA;
    framesCtx->sw_format = AV_PIX_FMT_NV12;  // CUVID outputs NV12
    framesCtx->width = m_codecContext->width;
    framesCtx->height = m_codecContext->height;
    framesCtx->initial_pool_size = 20;  // Frame pool size
    
    ret = av_hwframe_ctx_init(m_hwFramesContext);
    if (ret < 0) {
        char errbuf[AV_ERROR_MAX_STRING_SIZE];
        av_strerror(ret, errbuf, sizeof(errbuf));
        qWarning() << "[FFmpeg] Failed to initialize CUDA frames context:" << errbuf;
        av_buffer_unref(&m_hwFramesContext);
        avcodec_free_context(&m_codecContext);
        av_buffer_unref(&m_hwDeviceContext);
        return false;
    }
    
    m_codecContext->hw_frames_ctx = av_buffer_ref(m_hwFramesContext);
    
    qDebug() << "[FFmpeg] CUVID decoder initialized:" << codecName;
    return true;
#else
    return false;
#endif
}

// Helper function for wall-clock time
static inline double nowSeconds()
{
    return av_gettime_relative() / 1000000.0;
}

void FFmpegVideoPlayer::decodeThreadFunc()
{
    qDebug() << "[FFmpeg] Decode thread started";
    
    while (m_decodeThreadRunning) {
        QMutexLocker locker(&m_decodeMutex);
        
        // Wait for work or stop signal (block while paused)
        while (m_decodeThreadRunning && (!m_isPlaying || m_isPaused)) {
            m_decodeCondition.wait(&m_decodeMutex, 100);
        }
        
        if (!m_decodeThreadRunning) {
            break;
        }
        
        // Unlock for decoding
        locker.unlock();
        
        if (!m_formatContext || !m_codecContext) {
            QThread::msleep(10);
            continue;
        }
        
        // CRITICAL: Decode frames continuously - don't artificially slow down
        // QVideoSink + vsync will naturally pace frame presentation
        // Only decode one frame per iteration to prevent busy loop, but don't sleep aggressively
        int ret = avcodec_receive_frame(m_codecContext, m_frame);
        
        if (ret == 0) {
            // ✅ CRITICAL: Validate frame after receiving from decoder to prevent assertion crashes
            // After HEVC decode failures, decoder might output frames with invalid parameters
            if (m_frame->width <= 0 || m_frame->height <= 0) {
                qWarning() << "[FFmpeg] Received invalid frame from decoder - dimensions:" 
                           << m_frame->width << "x" << m_frame->height << "- skipping";
                av_frame_unref(m_frame);
                continue;
            }
            
            // ✅ CRITICAL: D3D11 hardware frames don't have CPU-visible data pointers
            // They will be validated after av_hwframe_transfer_data() transfers to system memory
            // Only validate data pointers for system memory formats (NV12, YUV420P, BGRA)
            AVPixelFormat frameFormat = (AVPixelFormat)m_frame->format;
            if (frameFormat != AV_PIX_FMT_D3D11) {
                // System memory frame - validate data pointers
                if (!m_frame->data[0] || m_frame->linesize[0] <= 0) {
                    qWarning() << "[FFmpeg] Received invalid frame from decoder - null data or invalid stride - skipping";
                    av_frame_unref(m_frame);
                    continue;
                }
            }
            // For D3D11 frames, data pointers will be NULL until transfer - that's expected
            
            // Successfully received a frame - process it
            FFLOG("[FFmpeg] received frame format:" << av_get_pix_fmt_name(frameFormat));
            
            // Frame timing: Calculate when this frame should be displayed
            if (m_videoStream && m_videoSink) {
                // Get frame PTS in seconds
                double framePts = 0.0;
                if (m_frame->best_effort_timestamp != AV_NOPTS_VALUE) {
                    framePts = m_frame->best_effort_timestamp * av_q2d(m_videoStream->time_base);
                } else if (m_frame->pts != AV_NOPTS_VALUE) {
                    framePts = m_frame->pts * av_q2d(m_videoStream->time_base);
                }
                
                // 🚨 DROP FRAMES AFTER SEEK UNTIL WE REACH TARGET
                // FFmpeg seeks to a keyframe (usually before target), so we must discard
                // frames until we reach the seek target PTS
                if (m_seekPending.load(std::memory_order_acquire)) {
                    constexpr double EPS = 0.0005; // 0.5ms tolerance
                    // Drop frames with invalid/zero PTS or frames before target
                    if (framePts <= 0.0 || framePts + EPS < m_seekTargetPts) {
                        // Drop this frame - it's before the seek target or has invalid PTS
                        FFLOG("[FFmpeg] Dropping frame before seek target - frame PTS:" << framePts 
                                     << "target PTS:" << m_seekTargetPts);
                        av_frame_unref(m_frame);
                        continue; // Continue to next iteration (don't process this frame)
                    } else {
                        // First valid frame after seek - clear seek pending flag
                        FFLOG("[FFmpeg] Reached seek target - frame PTS:" << framePts 
                                 << "target PTS:" << m_seekTargetPts);
                        m_seekPending.store(false, std::memory_order_release);
                        m_timingInitialized = false; // Re-initialize timing cleanly for this frame
                        
                        // Continue processing this frame
                        goto process_frame;
                    }
                } else {
                    // Normal playback - check for late frames
                    process_frame:
                        
                        // ✅ Hold video until audio is ready after seek (prevents A/V desync)
                        // If audio exists and we just seeked, don't present video until audio is ready.
                        // Otherwise video visibly "starts" early while audio is still catching up.
                        if (m_audioCodecContext && m_holdVideoUntilAudio.load(std::memory_order_acquire)) {
                            // While audio seek is pending (or base not set), drop video frames.
                            // This keeps A/V start aligned after seeks.
                            if (m_audioSeekPending.load(std::memory_order_acquire) || std::isnan(m_audioBasePts)) {
                                FFLOG("[FFmpeg] Holding video frame until audio is ready - dropping frame PTS:" << framePts);
                                av_frame_unref(m_frame);
                                continue; // Drop this frame, wait for audio
                            }
                            // Audio is ready - clear the hold flag (only need to check once)
                            m_holdVideoUntilAudio.store(false, std::memory_order_release);
                            FFLOG("[FFmpeg] Audio ready - video presentation can now start");
                        }
                        
                        // Initialize timing on first frame (or after seek)
                    // CRITICAL: Initialize even if audio isn't ready yet - use wall clock
                    if (!m_timingInitialized && framePts > 0.0) {
                        m_startPts = framePts;        // absolute pts at start
                        m_startTime = nowSeconds();   // wall time when that pts started
                        m_timingInitialized = true;
                        qDebug() << "[FFmpeg] Timing initialized - start time:" << m_startTime << "start PTS:" << m_startPts 
                                 << "audio ready:" << (!std::isnan(m_audioBasePts) && m_audioSink);
                    }
                    
                    // Frame pacing: sync to audio clock if available, otherwise use wall-clock
                    if (m_timingInitialized && framePts > 0.0) {
                        // ✅ FIX #2: Make AUDIO the master clock - always
                        // ✅ OPTION A: Audio is ALWAYS master whenever audio exists
                        // If we have audio, wait for it to be ready rather than using wall clock
                        // This ensures no switching between clocks (prevents discontinuities)
                        double masterClockAbs;
                        if (m_audioSink && m_audioCodecContext) {
                            // We have audio stream - audio is master (even if not ready yet)
                            if (!std::isnan(m_audioBasePts) && m_audioDevice && m_audioDevice->isOpen()) {
                                // ✅ FIX #2: Use delta from snapshot to prevent clock jump after seek
                                // ✅ LATENCY COMPENSATION: Subtract queued audio to get audible position
                                // processedUSecs() tells us what WASAPI has accepted, not what we hear
                                // We need to subtract the buffered/queued audio to get the actual audible position
                                
                                // ✅ FIX: Clamp audio latency calculations to prevent clock jumps
                                // WASAPI can report bytesFree() > bufferSize() or negative queued values,
                                // causing master clock to jump ahead and drop all frames
                                qint64 proc = 0;
                                qint64 queuedUSecs = 0;
                                qint64 deltaUSecs = 0;
                                
                                {
                                    QMutexLocker audioLock(&m_audioMutex);
                                    if (m_audioSink && m_audioDevice && m_audioDevice->isOpen()) {
                                        proc = m_audioSink->processedUSecs();
                                        const int bytesPerFrame = m_audioFormat.bytesPerFrame();
                                        const int sampleRate = m_audioFormat.sampleRate();
                                        
                                        if (bytesPerFrame > 0 && sampleRate > 0) {
                                            // Total buffer size in microseconds
                                            const qint64 bufferUSecs = (qint64(m_audioSink->bufferSize()) * 1000000) / 
                                                                       (bytesPerFrame * sampleRate);
                                            
                                            // Free space in microseconds - CLAMP to [0, bufferSize]
                                            const qint64 freeUSecsRaw = (qint64(m_audioSink->bytesFree()) * 1000000) / 
                                                                        (bytesPerFrame * sampleRate);
                                            const qint64 freeClamped = qBound<qint64>(0, freeUSecsRaw, bufferUSecs);
                                            
                                            // Queued audio = what's buffered but not yet played
                                            queuedUSecs = bufferUSecs - freeClamped;
                                        }
                                        
                                        // Clamp delta - processedUSecs can jump when device starts/restarts
                                        deltaUSecs = qMax<qint64>(0, proc - m_audioProcessedBaseUSecs);
                                    }
                                }
                                
                                // Audible delta = processed delta - queued latency
                                const double audibleDelta = double(deltaUSecs - queuedUSecs) / 1000000.0;
                                
                                m_audioClock = m_audioBasePts + audibleDelta;
                                masterClockAbs = m_audioClock;
                            } else {
                                // Audio exists but not ready yet (e.g., after seek, before first frame)
                                // Use wall clock temporarily, but audio will become master once ready
                                // This prevents frames from being dropped unnecessarily while audio initializes
                                masterClockAbs = m_startPts + (nowSeconds() - m_startTime);
                            }
                        } else {
                            // No audio stream at all - use wall clock
                            masterClockAbs = m_startPts + (nowSeconds() - m_startTime);
                        }
                        
                        // Video clock in ABSOLUTE stream seconds
                        double videoClockAbs = framePts;
                        
                        // ✅ FIX #3: Only drop frames if they're WAY behind (300ms+)
                        // BUT: Skip dropping for first 500ms of playback to allow A/V sync to stabilize
                        // This prevents "never starts" issue when audio clock initializes ahead of video
                        double timeSincePlayStart = nowSeconds() - m_playStartWallTime;
                        bool inGraceWindow = (timeSincePlayStart < 0.5) && (m_playStartWallTime > 0.0);
                        
                        if (!inGraceWindow && videoClockAbs < masterClockAbs - 0.3) {
                            qDebug() << "[FFmpeg] Dropping very late frame - video:" << videoClockAbs << "master:" << masterClockAbs 
                                     << "diff:" << (videoClockAbs - masterClockAbs);
                            av_frame_unref(m_frame);
                            continue; // Skip to next iteration (before any expensive processing)
                        }
                        
                        double delay = videoClockAbs - masterClockAbs;
                        
                        // ✅ CRITICAL FIX: Pace decode loop to prevent decoding all frames instantly
                        // If we're ahead, sleep for frame duration to slow down decode loop to realtime speed
                        // Normal frames arriving 50-150ms early don't need sleep - QVideoSink handles that
                        // Only sleep if significantly ahead (>200ms) to prevent decode loop from running too fast
                        if (delay > 0.2) {
                            // Calculate frame duration from stream (assume 30fps if unknown)
                            double frameDuration = 0.0333; // Default 30fps
                            if (m_videoStream && m_videoStream->avg_frame_rate.num > 0 && m_videoStream->avg_frame_rate.den > 0) {
                                frameDuration = 1.0 / av_q2d(m_videoStream->avg_frame_rate);
                            }
                            // Sleep for one frame duration to pace decode loop
                            // This prevents decode loop from decoding all frames instantly
                            int64_t sleep_us = static_cast<int64_t>(frameDuration * 1000000);
                            av_usleep(sleep_us);
                        }
                        // For normal delays (<200ms), don't sleep - frames are within normal buffer range
                        
                        // Only reset timing if way behind (catch-up scenario)
                        if (delay < -0.3) {
                            // More than 200ms behind - reset timing to catch up
                            qDebug() << "[FFmpeg] Frame way behind, resetting timing - delay:" << delay;
                            if (m_audioSink && m_audioClock > 0.0 && m_audioDevice && m_audioDevice->isOpen()) {
                                // Sync to audio clock (absolute)
                                m_startPts = framePts - m_audioClock;
                                m_startTime = nowSeconds();
                            } else {
                                // Sync to wall-clock
                                m_startTime = nowSeconds();
                                m_startPts = framePts;
                            }
                        }
                        
                        // Update position (in milliseconds) - use absolute clock
                        m_position = static_cast<qint64>(masterClockAbs * 1000.0);
                        emit positionChanged();
                        
                        // Debug logging for timing (only log every 30 frames to avoid spam)
                        static int frameCount = 0;
                        if ((frameCount++ % 30) == 0) {
                            qDebug() << "[FFmpeg] Frame timing - video:" << videoClockAbs 
                                     << "master:" << masterClockAbs 
                                     << "delay:" << delay 
                                     << "audio:" << (!std::isnan(m_audioBasePts) && m_audioSink && m_audioDevice && m_audioDevice->isOpen());
                        }
                    }
                }
            }
                
            // Process frame - now handles system memory formats (NV12, YUV420P, BGRA)
            // FFmpeg uses D3D11VA internally for hardware decode, but outputs CPU-visible frames
            // This is the stable QVideoSink path - no D3D11 texture handling
            if (m_frame->format == AV_PIX_FMT_NV12 || 
                m_frame->format == AV_PIX_FMT_YUV420P || 
                m_frame->format == AV_PIX_FMT_BGRA) {
                // System memory frame - Process directly for QVideoSink
                processFrame(m_frame);
            } else if (m_frame->format == AV_PIX_FMT_D3D11) {
                // ✅ D3D11 texture frame (selected for HDR/DV to avoid CPU 10-bit conversion)
                // Transfer to system memory - may get p010le (10-bit) which Qt doesn't support
                // ✅ CRITICAL PERFORMANCE FIX: Reuse persistent transfer frame (no per-frame alloc/free)
                if (m_transferFrame && m_codecContext->hw_device_ctx) {
                    av_frame_unref(m_transferFrame);  // Clear previous frame data before reuse
                    
                    // ✅ CRITICAL: Transfer D3D11 texture to system memory
                    // Use flags=0 (default) - AV_HWFRAME_TRANSFER_DIRECTION_FROM is not a valid flag value
                    // The direction is implicit (from hardware to system memory)
                    int ret = av_hwframe_transfer_data(m_transferFrame, m_frame, 0);
                    if (ret == 0) {
                        // ✅ Reset consecutive failure counter on success
                        static int consecutiveFailures = 0;
                        if (consecutiveFailures > 0) {
                            consecutiveFailures = 0;
                        }
                        
                        AVPixelFormat transferredFormat = (AVPixelFormat)m_transferFrame->format;
                        
                        // ✅ CRITICAL: Copy PTS and metadata from original frame to transferred frame
                        // av_hwframe_transfer_data() doesn't copy PTS/metadata, so we must do it manually
                        if (m_videoStream) {
                            // Copy PTS from original frame (D3D11 frame has it, transferred frame doesn't)
                            // NOTE: pkt_duration was removed in FFmpeg 7.x, only copy available fields
                            m_transferFrame->pts = m_frame->pts;
                            m_transferFrame->best_effort_timestamp = m_frame->best_effort_timestamp;
                            m_transferFrame->pkt_dts = m_frame->pkt_dts;
                            m_transferFrame->pkt_pos = m_frame->pkt_pos;
                            // duration is now stored in duration field (not pkt_duration)
                            m_transferFrame->duration = m_frame->duration;
                        }
                        
                        // ✅ CRITICAL: Set HDR color metadata IMMEDIATELY after D3D11 transfer
                        // D3D11 → CPU transfer loses metadata, and we MUST set it before ANY frame touches the filter graph
                        // This prevents "unknown range/colorspace" frames from locking the graph in an invalid state
                        if (transferredFormat == AV_PIX_FMT_P010LE || 
                            transferredFormat == AV_PIX_FMT_YUV420P10LE) {
                            // Set HDR metadata on frame BEFORE it goes to processFrame
                            m_transferFrame->color_range = AVCOL_RANGE_MPEG;
                            m_transferFrame->color_primaries = AVCOL_PRI_BT2020;
                            m_transferFrame->color_trc = AVCOL_TRC_SMPTE2084;
                            m_transferFrame->colorspace = AVCOL_SPC_BT2020_NCL;
                            // Convert 10-bit → 8-bit NV12 (Qt supports NV12)
                            processFrame(m_transferFrame);  // processFrame will handle the conversion
                        } else if (transferredFormat == AV_PIX_FMT_NV12 || 
                                   transferredFormat == AV_PIX_FMT_YUV420P ||
                                   transferredFormat == AV_PIX_FMT_BGRA) {
                            // Already 8-bit - can use directly
                            processFrame(m_transferFrame);
                        } else {
                            // Unknown/unsupported format - try to convert to NV12
                            qWarning() << "[FFmpeg] Unsupported format from D3D11 transfer:" 
                                       << av_get_pix_fmt_name(transferredFormat) 
                                       << "- attempting conversion to NV12";
                            // Let processFrame handle it (it will try to convert if needed)
                            processFrame(m_transferFrame);
                        }
                    } else {
                        // D3D11 transfer failed - handle gracefully
                        // Error -1313558101 = 0x8007000e = E_OUTOFMEMORY / D3D11 surface lock failure
                        // This can happen if the surface is still in use by another operation or GPU is busy
                        char errbuf[AV_ERROR_MAX_STRING_SIZE];
                        av_strerror(ret, errbuf, sizeof(errbuf));
                        
                        static int consecutiveFailures = 0;
                        if (ret == AVERROR(ENOMEM) || ret == -1313558101 || ret == AVERROR(EAGAIN)) {
                            // D3D11 surface lock/memory error - skip this frame, try next one
                            // This is often recoverable - the next frame might work
                            consecutiveFailures++;
                            if (consecutiveFailures <= 3) {
                                qDebug() << "[FFmpeg] D3D11 transfer failed (surface busy/memory):" << errbuf 
                                         << "- skipping frame (attempt" << consecutiveFailures << ")";
                            } else if (consecutiveFailures == 4) {
                                qWarning() << "[FFmpeg] D3D11 transfer failing repeatedly (" << consecutiveFailures 
                                          << " consecutive failures) - may indicate resource leak or GPU device issue";
                            }
                            // Counter will reset on next successful transfer
                        } else {
                            consecutiveFailures = 0;  // Reset on other error types
                            qWarning() << "[FFmpeg] Failed to transfer D3D11 frame to system memory:" << ret << errbuf;
                        }
                        
                        // Unref the original frame to avoid holding references to locked surfaces
                        av_frame_unref(m_frame);
                        // Don't process this frame, continue to next one
                    }
                } else {
                    qWarning() << "[FFmpeg] Cannot transfer D3D11 frame - missing transfer frame or context";
                }
            } else if (m_frame->format == AV_PIX_FMT_CUDA) {
                // CUDA frame (shouldn't happen with D3D11VA, but handle it if it does)
                FFLOG("[FFmpeg] Received CUDA frame (unexpected with D3D11VA)");
                ID3D11Texture2D* d3d11Texture = nullptr;
                if (transferCUDAToD3D11(m_frame, &d3d11Texture) && d3d11Texture) {
                    // Get texture dimensions
                    D3D11_TEXTURE2D_DESC desc;
                    d3d11Texture->GetDesc(&desc);
                    
                    // Store texture atomically for render thread
                    {
                        QMutexLocker locker(&m_pendingFrameMutex);
                        
                        // Release old pending texture if any
                        if (m_pendingFrame.texture) {
                            m_pendingFrame.texture->Release();
                        }
                        
                        // Store new texture (AddRef to keep alive until render thread consumes it)
                        d3d11Texture->AddRef();
                        m_pendingFrame.texture = d3d11Texture;
                        m_pendingFrame.width = static_cast<int>(desc.Width);
                        m_pendingFrame.height = static_cast<int>(desc.Height);
                    }
                    
                    // Schedule render update (safe to call from decode thread)
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
                        m_isPlaying = false;
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
                                if (m_audioFrame->best_effort_timestamp != AV_NOPTS_VALUE) {
                                    aPts = m_audioFrame->best_effort_timestamp * av_q2d(audioStream->time_base);
                                } else if (m_audioFrame->pts != AV_NOPTS_VALUE) {
                                    aPts = m_audioFrame->pts * av_q2d(audioStream->time_base);
                                }
                                
                                // Drop frames before target (allow small tolerance for imprecise seeks)
                                constexpr double EPS = 0.0005; // 0.5ms tolerance
                                if (std::isnan(aPts) || aPts + EPS < m_audioSeekTargetSec) {
                                    av_frame_unref(m_audioFrame);
                                    continue; // Drop this frame
                                }
                                
                                // ✅ First good audio frame after seek - clear seek pending and set clock
                                m_audioSeekPending.store(false, std::memory_order_release);
                                m_audioBasePts = aPts;  // Set audio base PTS immediately
                                m_audioClock = aPts;    // Initialize clock to frame PTS
                                
                                // ✅ FIX #2: Rebase processedUSecs() to this moment (prevents clock jump from old playback)
                                // Snapshot the current processedUSecs() so we can compute delta from this point
                                {
                                    QMutexLocker audioLock(&m_audioMutex);
                                    m_audioProcessedBaseUSecs = m_audioSink ? m_audioSink->processedUSecs() : 0;
                                }
                                
                                // ✅ Clear video hold flag - audio is now ready, video can start presenting
                                m_holdVideoUntilAudio.store(false, std::memory_order_release);
                                
                                qDebug() << "[FFmpeg] First good audio frame after seek - PTS:" << aPts 
                                         << "target:" << m_audioSeekTargetSec
                                         << "processedBaseUSecs:" << m_audioProcessedBaseUSecs
                                         << "(video hold cleared)";
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
                                                    }
                                                }
                                            }
                                        } else {
                                            // Buffer full - store remainder
                                            m_audioRemainder = buffer;
                                        }
                                    }
                                }
                                
                                // Update audio base PTS from frame timestamps (first frame only, if not already set by seek)
                                if (std::isnan(m_audioBasePts) && !m_audioSeekPending.load(std::memory_order_acquire)) {
                                    double ptsSec = NAN;
                                    AVStream* audioStream = m_formatContext->streams[m_audioStreamIndex];
                                    if (m_audioFrame->best_effort_timestamp != AV_NOPTS_VALUE) {
                                        ptsSec = m_audioFrame->best_effort_timestamp * av_q2d(audioStream->time_base);
                                    } else if (m_audioFrame->pts != AV_NOPTS_VALUE) {
                                        ptsSec = m_audioFrame->pts * av_q2d(audioStream->time_base);
                                    }
                                    
                                    if (!std::isnan(ptsSec)) {
                                        m_audioBasePts = ptsSec;
                                        m_audioClock = ptsSec;  // Initialize clock
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
                m_isPlaying = false;
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
    
    // Qt provides QRhiD3D11NativeHandles via qrhi.h (no forward declaration needed)
    // Note: Qt uses void* pointers for backend-agnostic ABI stability
    const auto* nh = static_cast<const QRhiD3D11NativeHandles*>(rhi->nativeHandles());
    if (!nh || !nh->dev || !nh->context) {
        qWarning() << "[FFmpeg] Failed to get D3D11 native handles from RHI or handles are null";
        return false;
    }
    
    // Explicit cast from void* to typed D3D11 pointers (required by Qt's ABI design)
    m_d3d11Device = reinterpret_cast<ID3D11Device*>(nh->dev);
    m_d3d11Context = reinterpret_cast<ID3D11DeviceContext*>(nh->context);
    
    // We are borrowing from Qt → AddRef is REQUIRED to keep device alive
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
    
    // Release FFmpeg's D3D11 device and context references
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
    
    // Query for ID3D11VideoDevice from FFmpeg's device (same device as decoded textures)
    HRESULT hr = m_ffmpegD3DDevice->QueryInterface(__uuidof(ID3D11VideoDevice), reinterpret_cast<void**>(&m_videoDevice));
    if (FAILED(hr) || !m_videoDevice) {
        qWarning() << "[FFmpeg] Failed to get ID3D11VideoDevice:" << hr;
        return false;
    }
    
    // Query for ID3D11VideoContext from FFmpeg's context (same context as decoded textures)
    hr = m_ffmpegD3DContext->QueryInterface(__uuidof(ID3D11VideoContext), reinterpret_cast<void**>(&m_videoContext));
    if (FAILED(hr) || !m_videoContext) {
        qWarning() << "[FFmpeg] Failed to get ID3D11VideoContext:" << hr;
        m_videoDevice->Release();
        m_videoDevice = nullptr;
        return false;
    }
    
    // Create Video Processor Enumerator with actual texture dimensions
    D3D11_VIDEO_PROCESSOR_CONTENT_DESC desc = {};
    desc.InputFrameFormat = D3D11_VIDEO_FRAME_FORMAT_PROGRESSIVE;
    desc.InputFrameRate.Numerator = 30;
    desc.InputFrameRate.Denominator = 1;
    desc.InputWidth = width;   // Use actual texture width
    desc.InputHeight = height; // Use actual texture height
    desc.OutputFrameRate.Numerator = 30;
    desc.OutputFrameRate.Denominator = 1;
    desc.OutputWidth = width;   // Use actual texture width
    desc.OutputHeight = height; // Use actual texture height
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
    
    // Create Video Processor
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
    
    // Transfer CUDA frame to system memory first
    // This is the simplest approach: CUDA → system → D3D11
    // For true zero-copy, we'd need CUDA Graphics API interop (more complex)
    int ret = av_hwframe_transfer_data(m_swFrame, cudaFrame, 0);
    if (ret < 0) {
        char errbuf[AV_ERROR_MAX_STRING_SIZE];
        av_strerror(ret, errbuf, sizeof(errbuf));
        qWarning() << "[FFmpeg] Failed to transfer CUDA frame to system memory:" << errbuf;
        return false;
    }
    
    // Get frame dimensions
    int width = m_swFrame->width;
    int height = m_swFrame->height;
    
    // Create D3D11 texture for NV12 data
    D3D11_TEXTURE2D_DESC texDesc = {};
    texDesc.Width = width;
    texDesc.Height = height;
    texDesc.MipLevels = 1;
    texDesc.ArraySize = 1;
    texDesc.Format = DXGI_FORMAT_NV12;  // CUVID outputs NV12
    texDesc.SampleDesc.Count = 1;
    texDesc.Usage = D3D11_USAGE_DEFAULT;
    texDesc.BindFlags = D3D11_BIND_SHADER_RESOURCE;
    texDesc.CPUAccessFlags = 0;
    
    D3D11_SUBRESOURCE_DATA initData = {};
    initData.pSysMem = m_swFrame->data[0];  // Y plane
    initData.SysMemPitch = m_swFrame->linesize[0];
    initData.SysMemSlicePitch = 0;
    
    // For NV12, we need to upload Y and UV planes separately
    // This is a simplified version - full implementation would handle both planes
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
    // Cleanup any existing filter graph
    cleanupHDRToneMappingFilter();
    
    // Allocate filter graph
    m_filterGraph = avfilter_graph_alloc();
    if (!m_filterGraph) {
        qWarning() << "[FFmpeg] Failed to allocate filter graph for HDR tone mapping";
        return false;
    }
    
    // ✅ CRITICAL: Buffer source args must be MINIMAL - color metadata goes on AVFrame, not buffer
    // D3D11 → CPU transfer loses color metadata, so we set it on the frame before pushing
    // Buffer filter only needs: video_size, pix_fmt, time_base
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
    
    // ✅ CRITICAL: Set buffer source parameters (format, dimensions, timing)
    // NOTE: AVBufferSrcParameters does NOT support color metadata fields in FFmpeg 7.x
    // Color metadata MUST be set on AVFrame (which we do in processFrame before pushing)
    // This just locks the basic format/dimensions to prevent mismatches
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
            // Continue anyway - frame metadata should still work
        } else {
            qDebug() << "[FFmpeg] Locked buffer source parameters (format/dimensions)";
        }
    }
    
    // ✅ OPTIMIZATION 1: Scale down early if display is smaller than source (or if source is very large)
    // Don't tonemap full 4K if display is 960x720 - scale down first to reduce expensive processing
    int processWidth = width;
    int processHeight = height;
    bool needsScale = false;
    
    if (displayWidth > 0 && displayHeight > 0 && (displayWidth < width || displayHeight < height)) {
        // Scale to display size (with aspect ratio preserved)
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
        // If source is larger than 1080p, scale to 1080p max (reasonable intermediate size)
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
    
    // Scale filter (early, before expensive HDR processing)
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
    
    // zscale: Convert to linear light (PQ HDR -> linear)
    // ✅ CRITICAL: Explicitly specify input metadata (*_in parameters)
    // This tells zscale what we're converting FROM (bt2020 + PQ), not just what we want
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
    
    // ✅ OPTIMIZATION 2: tonemap - try to avoid expensive float RGB conversion
    // tonemap by default converts to float RGB (gbrpf32le) which is very expensive.
    // If tonemap supports format parameter, we can try to keep it in YUV, but this may not be available.
    // ✅ CRITICAL FIX #4: Don't probe for tonemap format= option - it's not supported in this FFmpeg build
    // The "No such option: format" error is expected - tonemap will use default (float RGB)
    // We convert to NV12 later anyway, so the intermediate format doesn't matter
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
    
    // zscale: Convert to SDR color space (bt709)
    // Input is linear YUV (from tonemap with format=p010le), output is bt709 SDR
    // Explicitly specify input is linear to avoid color space path errors
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
    
    // format: Convert to NV12 (8-bit, Qt compatible)
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
    
    // Output buffer sink
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
    
    // Link filters: in -> [scale] -> zscale1 -> tonemap -> zscale2 -> format -> out
    // (scale is optional, only if needsScale is true)
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
    
    // ✅ Configure the filter graph
    // NOTE: Buffer source will have "unknown" colorspace/range at this point - that's expected
    // The first frame we push will "change" it to bt2020nc/tv, causing a harmless warning:
    // "Changing video frame properties on the fly is not supported by all filters"
    // This is a FFmpeg limitation - buffer source can't specify color metadata at creation in FFmpeg 7.x
    // The warning is harmless as long as ALL subsequent frames have the same metadata (which we ensure)
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
    
    // Allocate output frame
    m_filterFrame = av_frame_alloc();
    if (!m_filterFrame) {
        qWarning() << "[FFmpeg] Failed to allocate filter output frame";
        avfilter_graph_free(&m_filterGraph);
        return false;
    }
    
    // Log filter graph description for debugging
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
    m_filterGraphInitialized = false; // ✅ Mark as not initialized when cleaned up
    // ✅ Reset backpressure counter when cleaning up filter graph
    m_framesInFilter.store(0, std::memory_order_relaxed);
}

void FFmpegVideoPlayer::processFrame(AVFrame* frame)
{
    if (!frame) {
        return;
    }
    
    // ✅ Handle 10-bit HDR frames (Dolby Vision, HEVC Main10) - use FFmpeg HDR tone mapping
    // Qt QVideoSink does not support 10-bit formats (p010le, yuv420p10le), so we must convert
    // Use FFmpeg filter graph for proper HDR → SDR tone mapping (better than simple format conversion)
    AVPixelFormat frameFormat = (AVPixelFormat)frame->format;
    if (frameFormat == AV_PIX_FMT_P010LE || frameFormat == AV_PIX_FMT_YUV420P10LE) {
        int width = frame->width;
        int height = frame->height;
        
        if (width <= 0 || height <= 0) {
            return;
        }
        
        // ✅ CRITICAL: Set HDR color metadata on EVERY frame BEFORE filter graph initialization
        // This prevents "unknown range/colorspace" from locking the graph in invalid state
        // FFmpeg requires ALL frames to have IDENTICAL metadata from the FIRST frame onward
        // D3D11 → CPU transfer loses metadata, so we must restore it explicitly on every frame
        frame->color_range = AVCOL_RANGE_MPEG;        // TV range (16-235)
        frame->color_primaries = AVCOL_PRI_BT2020;    // BT.2020 primaries (HDR)
        frame->color_trc = AVCOL_TRC_SMPTE2084;       // PQ (Perceptual Quantizer) transfer
        frame->colorspace = AVCOL_SPC_BT2020_NCL;    // BT.2020 non-constant luminance matrix
        
        // ✅ CRITICAL: Initialize filter graph on first frame (even without PTS)
        // We'll set a default PTS if needed - waiting for PTS causes infinite loop
        // The filter graph must be initialized before we can process any 10-bit frames
        // ✅ CRITICAL GUARD: Only recreate if graph doesn't exist OR dimensions/format actually changed
        // This prevents repeated recreation during playback (which causes memory leaks from zscale/tonemap LUTs)
        // Rule: Filter graph MUST NOT be recreated during playback unless dimensions/format change
        bool needsRecreation = false;
        if (!m_filterGraph || !m_filterGraphInitialized) {
            // Graph doesn't exist or wasn't properly initialized - must create
            needsRecreation = true;
            if (m_filterGraphInitialized && m_isPlaying) {
                qWarning() << "[FFmpeg] Filter graph lost during playback - recreating (this should not happen)";
            }
        } else if (m_filterWidth != width || 
                   m_filterHeight != height || 
                   m_filterInputFormat != frameFormat) {
            // Dimensions or format changed - must recreate (legitimate reason)
            needsRecreation = true;
            qDebug() << "[FFmpeg] Filter graph dimensions/format changed:" 
                     << m_filterWidth << "x" << m_filterHeight << "->" << width << "x" << height
                     << "format:" << av_get_pix_fmt_name(m_filterInputFormat) 
                     << "->" << av_get_pix_fmt_name(frameFormat);
        } else {
            // Graph exists, is initialized, and dimensions/format match - do NOT recreate
            // This prevents memory leaks from repeated graph creation during playback
        }
        
        if (needsRecreation) {
            // Get display dimensions for scaling optimization (if available)
            int displayWidth = 0;
            int displayHeight = 0;
            if (m_videoSink) {
                // Try to get display size from video sink if available
                // For now, we'll use 0 to trigger the "scale to 1080p max" logic for large sources
                displayWidth = 0;
                displayHeight = 0;
            }
            
            if (!initHDRToneMappingFilter(width, height, frameFormat, displayWidth, displayHeight)) {
                qWarning() << "[FFmpeg] Failed to initialize HDR tone mapping filter - video may not display";
                m_filterGraphInitialized = false; // Mark as not initialized on failure
                return;
            }
            // Store dimensions and format for next check
            m_filterWidth = width;
            m_filterHeight = height;
            m_filterInputFormat = frameFormat;
            m_filterGraphInitialized = true; // ✅ Mark as initialized for current playback session
        }
        
        // ✅ CRITICAL FIX #2: Ensure ALL metadata and PTS is set BEFORE cloning
        // Once we clone and push to filter graph, we must NEVER mutate the original frame
        // Set PTS if missing
        if (m_videoStream) {
            if (frame->best_effort_timestamp == AV_NOPTS_VALUE && frame->pts == AV_NOPTS_VALUE) {
                // No PTS available - set default to prevent filter graph errors
                frame->pts = 0;
                frame->best_effort_timestamp = 0;
                qDebug() << "[FFmpeg] Frame has no valid PTS, using default PTS=0 for filter graph";
            }
        }
        
        // ✅ CRITICAL BACKPRESSURE: Check if filter graph is full BEFORE cloning
        // Dropping BEFORE cloning saves memory - we avoid allocating a clone that we'd just drop
        // This prevents unbounded memory growth when decoding is faster than filter graph consumption
        int framesInFlight = m_framesInFilter.load(std::memory_order_relaxed);
        if (framesInFlight >= MAX_IN_FLIGHT) {
            // Filter graph is full - drop this frame to prevent memory explosion
            // This is expected when decode rate > filter graph processing rate
            // The dropped frame will be compensated by later frames being processed faster
            static int dropCount = 0;
            dropCount++;
            if (dropCount <= 10 || (dropCount % 60 == 0)) {
                qDebug() << "[FFmpeg] Dropping frame (backpressure):" << framesInFlight << "frames in filter graph (max:" << MAX_IN_FLIGHT << ")";
            }
            return; // Drop frame BEFORE cloning - saves ~16MB per 4K frame
        }
        
        // ✅ CRITICAL FIX #1: NEVER pass a reusable frame to filter graph with KEEP_REF
        // The filter graph will hold a reference to the frame, and if we reuse/mutate it,
        // the graph will see inconsistent data (width/height from one frame, linesize from another)
        // This causes imgutils.c assertion failures when copying frame data
        // SOLUTION: Clone the frame before pushing - filter graph owns the clone, we can reuse original
        AVFrame* clonedFrame = av_frame_clone(frame);
        if (!clonedFrame) {
            qWarning() << "[FFmpeg] Failed to clone frame for filter graph - out of memory";
            return;
        }
        
        // Add cloned frame to filter graph input (filter graph now owns it)
        // NOTE: First frame will cause "Changing video frame properties" warning - this is expected and harmless
        int ret = av_buffersrc_add_frame_flags(m_filterSrcCtx, clonedFrame, AV_BUFFERSRC_FLAG_KEEP_REF);
        
        // ✅ CRITICAL FIX #3: If filter graph rejects frame, it's poisoned - recreate it
        // Don't try to "recover" - once a filter graph error occurs, it's in an invalid state
        if (ret < 0) {
            char errbuf[AV_ERROR_MAX_STRING_SIZE];
            av_strerror(ret, errbuf, sizeof(errbuf));
            qWarning() << "[FFmpeg] Failed to add frame to filter graph:" << errbuf << "- recreating graph";
            
            // Free the cloned frame we created (filter graph didn't take it)
            av_frame_free(&clonedFrame);
            
            // Cleanup and recreate filter graph - it's poisoned
            cleanupHDRToneMappingFilter();
            m_filterWidth = 0;  // Force recreation on next frame
            m_filterHeight = 0;
            m_filterInputFormat = AV_PIX_FMT_NONE;
            m_filterGraphInitialized = false; // ✅ Mark as not initialized - will recreate on next frame
            m_framesInFilter.store(0, std::memory_order_relaxed); // ✅ Reset counter on cleanup
            return;
        }
        
        // ✅ BACKPRESSURE: Increment counter after successful push
        m_framesInFilter.fetch_add(1, std::memory_order_relaxed);
        
        // Filter graph now owns clonedFrame - we can safely reuse 'frame' (m_transferFrame) for next decode
        // Don't free clonedFrame - filter graph will free it when done
        
        // Get output frame from filter graph (tone-mapped, 8-bit NV12)
        // Filter graph may need multiple input frames before producing output (especially first time)
        ret = av_buffersink_get_frame(m_filterSinkCtx, m_filterFrame);
        if (ret < 0) {
            if (ret == AVERROR(EAGAIN)) {
                // Filter graph needs more input - this is normal, especially on first frames
                // Continue to next iteration to feed more frames
                // Note: We already incremented the counter on push, so it stays incremented
                return;
            } else if (ret == AVERROR_EOF) {
                // End of stream - this is normal
                return;
            } else {
                // Real error - log it but don't crash
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
                // Continue to next frame - filter graph might recover
                // Note: Counter already incremented, but frame wasn't consumed - this is OK
                // The filter graph still holds the frame, so counter is accurate
                return;
            }
        }
        
        // ✅ BACKPRESSURE: Decrement counter after successful pull (one frame consumed from filter graph)
        m_framesInFilter.fetch_sub(1, std::memory_order_relaxed);
        
        // ✅ Reset sink error counter on success
        static int consecutiveSinkErrors = 0;
        if (consecutiveSinkErrors > 0) {
            consecutiveSinkErrors = 0;
        }
        
        // ✅ CRITICAL: Validate filter output frame before processing to prevent assertion crashes
        // Filter graph may output frames with invalid stride/width after decode errors or format issues
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
        // Validate stride matches minimum required width (prevents assertion in imgutils.c)
        AVPixelFormat outFormat = (AVPixelFormat)m_filterFrame->format;
        int minStride = 0;
        if (outFormat == AV_PIX_FMT_NV12) {
            minStride = m_filterFrame->width; // NV12 luma: 1 byte per pixel
        } else if (outFormat == AV_PIX_FMT_YUV420P) {
            minStride = m_filterFrame->width; // YUV420P Y: 1 byte per pixel
        } else if (outFormat == AV_PIX_FMT_BGRA) {
            minStride = m_filterFrame->width * 4; // BGRA: 4 bytes per pixel
        }
        if (minStride > 0 && m_filterFrame->linesize[0] < minStride) {
            qWarning() << "[FFmpeg] Filter output frame stride too small:" 
                       << "format:" << av_get_pix_fmt_name(outFormat)
                       << "stride[0]:" << m_filterFrame->linesize[0] 
                       << "needs:" << minStride << "- skipping";
            av_frame_unref(m_filterFrame);
            return;
        }
        
        // ✅ CRITICAL: Filter graph processing is CPU-intensive and can block decode thread
        // This can cause D3D11 resource contention when QVideoFrame.map() is called
        // Add a small yield after filter processing to allow Qt's render thread to access D3D11 device
        // This prevents "Failed to map buffer" COM errors from resource exhaustion
        processFrame(m_filterFrame);
        
        // ✅ CRITICAL: Add throttle after filter graph processing to prevent D3D11 resource exhaustion
        // Filter graph + QVideoFrame.map() from decode thread can create D3D11 staging textures faster
        // than Qt's render thread can release them, causing resource exhaustion and crashes after ~2 seconds
        // Even with m_framePending checks, filter graph processing can overwhelm D3D11 resource pool
        // Longer delay needed for filter graph path (CPU-intensive processing + D3D11 allocation)
        // 5ms delay = ~200fps max, which is still faster than any video (30fps typical)
        QThread::msleep(5); // 5ms delay - prevents D3D11 resource exhaustion, minimal impact on 30fps video
        
        // Unref the filter output frame (will be reused next time)
        av_frame_unref(m_filterFrame);
        return;
    }
    
    // For QVideoSink: Handle system memory frames (NV12, YUV420P, BGRA)
    // FFmpeg uses D3D11VA internally for hardware decode, but outputs CPU-visible frames
    // This is the stable path - no D3D11 texture handling needed
    
    int width = frame->width;
    int height = frame->height;
    
    if (width <= 0 || height <= 0) {
        qWarning() << "[FFmpeg] Invalid frame dimensions:" << width << "x" << height;
        return;
    }
    
    // ✅ CRITICAL: Validate frame data pointers and stride before copying
    // Invalid stride can cause assertion failures in imgutils.c when copying
    if (!frame->data[0] || frame->linesize[0] <= 0) {
        qWarning() << "[FFmpeg] Invalid frame data pointer or linesize:" 
                   << "data[0]=" << (void*)frame->data[0] << "linesize[0]=" << frame->linesize[0];
        return;
    }
    
    // Update size properties
    if (m_width != width || m_height != height) {
        m_width = width;
        m_height = height;
        emit implicitSizeChanged();
    }
    
    // ✅ CRITICAL: Check if frame is pending BEFORE creating QVideoFrame to avoid D3D11 resource allocation
    // QVideoFrame.map() allocates D3D11 staging textures even if we skip the frame later
    // This check prevents unnecessary D3D11 resource allocation when GUI thread is still processing previous frame
    // NOTE: We check AFTER filter graph processing - filter graph input frames should always be processed to drain buffer
    if (!m_videoSink) {
        return; // No sink - can't display frames
    }
    
    // Feed frame to QVideoSink (Qt handles everything - GPU upload, rendering, sync)
    QVideoFrame videoFrame;  // Declare outside format checks so it's available in all branches
    AVPixelFormat pixFormat = (AVPixelFormat)frame->format;
    
        if (pixFormat == AV_PIX_FMT_NV12) {
            // ✅ CRITICAL: Check m_framePending BEFORE creating/mapping QVideoFrame to avoid D3D11 resource allocation
            // QVideoFrame.map() allocates D3D11 staging textures immediately, even if we skip the frame later
            // This check prevents D3D11 resource exhaustion when GUI thread is still processing previous frame
            if (m_framePending.load(std::memory_order_acquire)) {
                return; // Skip frame - GUI thread still processing previous one
            }
            
            // NV12: Y plane + interleaved UV plane
            QVideoFrameFormat format(QSize(width, height), QVideoFrameFormat::Format_NV12);
            videoFrame = QVideoFrame(format);
            
            // ✅ CRITICAL: QVideoFrame.map() can fail with D3D11 backend when called from decode thread
            // This is a known issue - D3D11 staging texture allocation can conflict with render thread
            // Add error handling and skip frame if mapping fails (better than crashing)
            if (!videoFrame.map(QVideoFrame::WriteOnly)) {
                static int mapFailures = 0;
                mapFailures++;
                if (mapFailures <= 3) {
                    qWarning() << "[FFmpeg] Failed to map QVideoFrame buffer (D3D11 resource conflict?) - skipping frame. This can happen with HDR filter graph processing.";
                } else if (mapFailures == 4) {
                    qWarning() << "[FFmpeg] QVideoFrame mapping failing repeatedly - may indicate D3D11 resource exhaustion or threading issue";
                }
                return; // Skip this frame - next one might work
            }
            
            // ✅ CRITICAL PERFORMANCE FIX: Copy only active pixel width, not stride padding
            // NV12 luma is 1 byte per pixel, chroma row is width bytes (UV interleaved)
            // Copying stride padding wastes memory bandwidth and cache, causing lag
            const int yBytes = width;         // NV12 luma: 1 byte per pixel
            const int uvBytes = width;        // NV12 chroma: width bytes per row (UV interleaved)
            
            // ✅ CRITICAL: Validate stride before copying to prevent assertion failures
            // Assertion failure: ((src_linesize) >= 0 ? (src_linesize) : (-(src_linesize))) >= bytewidth
            const int srcYStride = frame->linesize[0];
            const int srcUVStride = frame->linesize[1];
            if (srcYStride < yBytes || srcUVStride < uvBytes) {
                qWarning() << "[FFmpeg] Invalid stride for NV12 frame - Y stride:" << srcYStride 
                           << "needs:" << yBytes << "UV stride:" << srcUVStride << "needs:" << uvBytes;
                videoFrame.unmap();
                return;
            }
            
            // Copy Y plane
            uint8_t* dstY = videoFrame.bits(0);
            const uint8_t* srcY = frame->data[0];
            const int dstYStride = videoFrame.bytesPerLine(0);
            
            if (!srcY || !dstY) {
                qWarning() << "[FFmpeg] Invalid NV12 Y plane pointers";
                videoFrame.unmap();
                return;
            }
            
            for (int y = 0; y < height; ++y) {
                memcpy(dstY + y * dstYStride, srcY + y * srcYStride, yBytes);
            }
            
            // Copy UV plane (interleaved)
            uint8_t* dstUV = videoFrame.bits(1);
            const uint8_t* srcUV = frame->data[1];
            const int dstUVStride = videoFrame.bytesPerLine(1);
            const int uvHeight = height / 2;
            
            if (!srcUV || !dstUV) {
                qWarning() << "[FFmpeg] Invalid NV12 UV plane pointers";
                videoFrame.unmap();
                return;
            }
            
            for (int y = 0; y < uvHeight; ++y) {
                memcpy(dstUV + y * dstUVStride, srcUV + y * srcUVStride, uvBytes);
            }
            
            videoFrame.unmap();
            
            // Reset failure counter on success
            static int mapFailures = 0;
            if (mapFailures > 0) {
                mapFailures = 0;
            }
        } else if (pixFormat == AV_PIX_FMT_YUV420P) {
            // ✅ CRITICAL: Check m_framePending BEFORE creating/mapping QVideoFrame
            if (m_framePending.load(std::memory_order_acquire)) {
                return; // Skip frame - GUI thread still processing previous one
            }
            
            // YUV420P: Separate Y, U, V planes
            QVideoFrameFormat format(QSize(width, height), QVideoFrameFormat::Format_YUV420P);
            videoFrame = QVideoFrame(format);
            
            // ✅ CRITICAL: QVideoFrame.map() can fail with D3D11 backend when called from decode thread
            if (!videoFrame.map(QVideoFrame::WriteOnly)) {
                static int mapFailures = 0;
                mapFailures++;
                if (mapFailures <= 3) {
                    qWarning() << "[FFmpeg] Failed to map QVideoFrame buffer (YUV420P) - skipping frame";
                }
                return;
            }
            
            // ✅ CRITICAL PERFORMANCE FIX: Copy only active pixel width, not stride padding
            // YUV420P: Y is full width, U/V are half width
            const int yBytes = width;         // Y plane: 1 byte per pixel
            const int uvBytes = width / 2;    // U/V planes: half width (subsampled)
            
            // ✅ CRITICAL: Validate stride before copying to prevent assertion failures
            const int srcYStride = frame->linesize[0];
            const int srcUStride = frame->linesize[1];
            const int srcVStride = frame->linesize[2];
            if (srcYStride < yBytes || srcUStride < uvBytes || srcVStride < uvBytes) {
                qWarning() << "[FFmpeg] Invalid stride for YUV420P frame - Y:" << srcYStride 
                           << "U:" << srcUStride << "V:" << srcVStride 
                           << "needs Y:" << yBytes << "UV:" << uvBytes;
                videoFrame.unmap();
                return;
            }
            
            // Validate data pointers
            if (!frame->data[0] || !frame->data[1] || !frame->data[2]) {
                qWarning() << "[FFmpeg] Invalid YUV420P data pointers";
                videoFrame.unmap();
                return;
            }
            
            // Copy Y plane
            uint8_t* dstY = videoFrame.bits(0);
            const uint8_t* srcY = frame->data[0];
            const int dstYStride = videoFrame.bytesPerLine(0);
            
            for (int y = 0; y < height; ++y) {
                memcpy(dstY + y * dstYStride, srcY + y * srcYStride, yBytes);
            }
            
            // Copy U plane
            uint8_t* dstU = videoFrame.bits(1);
            const uint8_t* srcU = frame->data[1];
            const int dstUStride = videoFrame.bytesPerLine(1);
            const int uHeight = height / 2;
            
            for (int y = 0; y < uHeight; ++y) {
                memcpy(dstU + y * dstUStride, srcU + y * srcUStride, uvBytes);
            }
            
            // Copy V plane
            uint8_t* dstV = videoFrame.bits(2);
            const uint8_t* srcV = frame->data[2];
            const int dstVStride = videoFrame.bytesPerLine(2);
            const int vHeight = height / 2;
            
            for (int y = 0; y < vHeight; ++y) {
                memcpy(dstV + y * dstVStride, srcV + y * srcVStride, uvBytes);
            }
            
            videoFrame.unmap();
            
            // Reset failure counter on success
            static int mapFailures = 0;
            if (mapFailures > 0) {
                mapFailures = 0;
            }
        } else if (pixFormat == AV_PIX_FMT_BGRA) {
            // BGRA: Already in RGB format, convert to QImage
            // ✅ Validate stride before creating QImage to prevent assertion failures
            const int srcStride = frame->linesize[0];
            const int expectedStride = width * 4; // BGRA = 4 bytes per pixel
            if (srcStride < expectedStride) {
                qWarning() << "[FFmpeg] Invalid BGRA stride:" << srcStride << "needs:" << expectedStride;
                return;
            }
            if (!frame->data[0]) {
                qWarning() << "[FFmpeg] Invalid BGRA data pointer";
                return;
            }
            QImage image(frame->data[0], width, height, srcStride, QImage::Format_ARGB32);
            image = image.copy(); // Ensure Qt owns the pixel data
            videoFrame = QVideoFrame(image);
        } else {
            // Fallback: Convert to RGB using swscale (if available) or return
            qWarning() << "[FFmpeg] Unsupported pixel format for QVideoSink:" << av_get_pix_fmt_name((AVPixelFormat)frame->format);
            return;
        }
        
        // ✅ CRITICAL FIX: Queue frame to GUI thread (m_framePending already checked at function start)
        // We checked m_framePending before creating QVideoFrame, so we know we can queue this frame
        if (videoFrame.isValid()) {
            // Mark as pending BEFORE queuing to prevent race condition
            m_framePending.store(true, std::memory_order_release);
            
            QVideoFrame copy = videoFrame; // implicit shared copy
            QMetaObject::invokeMethod(this, [this, copy]() mutable {
                if (m_videoSink) {
                    m_videoSink->setVideoFrame(copy);
                }
                m_framePending.store(false, std::memory_order_release); // Frame delivered, allow next one
            }, Qt::QueuedConnection);
            
            // ✅ CRITICAL: Small throttle after queuing frame to allow Qt's render thread to process D3D11 resources
            // QVideoFrame.map() was called from decode thread, allocating D3D11 staging texture
            // Qt's render thread needs time to process and release these resources
            // Without this throttle, we create frames faster than resources can be released → crash after ~2 seconds
            // For HDR filter graph path, delay is already applied above, so this is for direct frames only
            if (pixFormat != AV_PIX_FMT_P010LE && pixFormat != AV_PIX_FMT_YUV420P10LE) {
                // Non-filter-graph path: smaller delay (filter graph already has 5ms delay)
                QThread::msleep(2); // 2ms delay - minimal impact (~30fps = 33ms per frame, 2ms is ~6% overhead)
            }
        } else {
            // Invalid frame - reset pending flag since we're not queueing
            m_framePending.store(false, std::memory_order_release);
        }
}

QUrl FFmpegVideoPlayer::source() const
{
    return m_source;
}

void FFmpegVideoPlayer::setSource(const QUrl& source)
{
    // 🔒 Ignore empty or invalid URLs (prevents QML from killing playback with empty source)
    if (!source.isValid() || source.isEmpty()) {
        qDebug() << "[FFmpeg] setSource(): ignoring empty/invalid source";
        return;
    }
    
    if (m_source == source) {
        return;
    }
    
    qDebug() << "[FFmpeg] setSource() called with:" << source;
    
    stop();
    closeMedia();
    
    m_source = source;
    emit sourceChanged();
    
    // Only open media if D3D11 is already initialized
    // Otherwise, onSceneGraphInitialized() will open it when RHI is ready
    if (m_d3d11Device && m_d3d11Context) {
        // D3D11 is ready, open immediately
        openMedia();
    } else {
        // D3D11 not ready yet - wait for scene graph initialization
        qDebug() << "[FFmpeg] Source set, waiting for D3D11 initialization...";
    }
}

void FFmpegVideoPlayer::setVideoSink(QVideoSink* sink)
{
    if (m_videoSink == sink) return;
    m_videoSink = sink;
    emit videoSinkChanged();
}

void FFmpegVideoPlayer::setWindow(QQuickWindow* window)
{
    qDebug() << "[FFmpeg] setWindow called with:" << (window ? "valid window" : "nullptr");
    
    if (m_window == window) {
        return;
    }
    
    // Disconnect from old window
    if (m_window) {
        disconnect(m_window, nullptr, this, nullptr);
    }
    
    m_window = window;
    emit windowChanged();
    
    if (!m_window) {
        qDebug() << "[FFmpeg] Window set to nullptr";
        return;
    }
    
    // Always connect to scene graph initialization signal
    // Use DirectConnection because sceneGraphInitialized is already on the render thread
    // and we need to grab RHI immediately
    connect(
        m_window,
        &QQuickWindow::sceneGraphInitialized,
        this,
        &FFmpegVideoPlayer::onSceneGraphInitialized,
        Qt::DirectConnection
    );
    
    // CRITICAL: If scene graph is already initialized, call immediately
    // This handles the case where window is set after scene graph is ready
    if (m_window->rhi()) {
        qDebug() << "[FFmpeg] Scene graph already initialized, initializing immediately";
        onSceneGraphInitialized();
    } else {
        qDebug() << "[FFmpeg] Window set, waiting for scene graph initialization...";
    }
}

void FFmpegVideoPlayer::play()
{
    QMutexLocker locker(&m_decodeMutex);
    
    // play() should NEVER open media - it should only start/resume playback if media is already opened
    if (!m_mediaOpened) {
        qDebug() << "[FFmpeg] play(): media not opened yet";
        return;
    }
    
    if (!m_formatContext) {
        qWarning() << "[FFmpeg] Cannot play - format context is null despite media being opened";
        return;
    }
    
    // If already playing and not paused, do nothing
    if (m_isPlaying && !m_isPaused) {
        qDebug() << "[FFmpeg] play() called but already playing - ignoring";
        return;
    }
    
    // ✅ Set playback start wall time for grace window (prevents frame drops at startup)
    m_playStartWallTime = nowSeconds();
    
    // Handle resume from pause
    if (m_isPaused) {
        m_isPaused = false;
        double pausedDuration = nowSeconds() - m_pauseTime;
        qDebug() << "[FFmpeg] Resuming from pause - paused for:" << pausedDuration << "seconds";
        
        // Resume audio - check device state first to avoid AUDCLNT_E_NOT_STOPPED
        if (m_audioSink) {
            QMutexLocker audioLock(&m_audioMutex);
            if (m_audioDevice && m_audioDevice->isOpen()) {
                // Device is open - safe to resume
                // NOTE: QAudioSink::processedUSecs() automatically pauses when suspended,
                // so resume() will continue from where it left off - no timing adjustment needed
                m_audioSink->resume();
            } else {
                // Device was stopped - need to restart it
                qDebug() << "[FFmpeg] Audio device was stopped, restarting...";
                // Properly close device first to avoid AUDCLNT_E_NOT_STOPPED
                if (m_audioDevice && m_audioDevice->isOpen()) {
                    m_audioDevice->close();
                }
                m_audioSink->stop();
                m_audioSink->suspend();
                m_audioDevice = nullptr;
                QThread::msleep(20); // Wait for device release
                m_audioSink->setVolume(m_volume); // Ensure volume is set after restart
                m_audioDevice = m_audioSink->start();
                if (!m_audioDevice || !m_audioDevice->isOpen()) {
                    qWarning() << "[FFmpeg] Failed to restart audio device after pause";
                }
                audioLock.unlock(); // Release lock after audio operations
                // Reset audio base PTS since we're restarting
                m_audioBasePts = NAN;
                m_audioClock = 0.0;
            }
        }
        
        // ✅ CRITICAL: Only adjust wall clock timing if audio is NOT the master
        // If audio is master, processedUSecs() handles pause/resume automatically
        // Adjusting m_startTime when audio is master causes desync
        if (!m_audioSink || !m_audioDevice || !m_audioDevice->isOpen() || std::isnan(m_audioBasePts)) {
            // No audio - adjust wall clock to account for pause
            m_startTime += pausedDuration;
        }
        // If audio is available, don't adjust m_startTime - audio clock handles it
        
        // Wake up decode thread
        m_decodeCondition.wakeAll();
        locker.unlock();
        
        emit playbackStateChanged();
        return;
    }
    
    // START: Fresh playback from beginning
    // Only reset to beginning if we're not in the middle of a seek
    // (seeks set m_seekPending, so we should preserve that state)
    if (m_seekPending.load(std::memory_order_acquire)) {
        // We're in the middle of a seek - don't reset anything
        // Just ensure playback is active
        qDebug() << "[FFmpeg] play() called during seek - preserving seek state";
        m_isPlaying = true;
        m_isPaused = false;
        m_decodeCondition.wakeAll();
        locker.unlock();
        emit playbackStateChanged();
        return;
    }
    
    // Reset decoder state
    m_decoderDrained = false;
    m_sentAnyPacket = false;
    
    // Reset demuxer and seek to beginning (protected by demux mutex)
    {
        QMutexLocker demuxLocker(&m_demuxMutex);
        
        if (m_formatContext) {
            // Reset demuxer EOF + buffered packets
            avformat_flush(m_formatContext);
            
            // Seek to the start, stream-agnostic (more reliable than av_seek_frame)
            int seekRet = avformat_seek_file(
                m_formatContext,
                -1,                // any stream
                INT64_MIN,
                0,                 // target timestamp
                INT64_MAX,
                AVSEEK_FLAG_BACKWARD
            );
            
            if (seekRet < 0) {
                qWarning() << "[FFmpeg] avformat_seek_file(0) failed:" << seekRet;
            } else {
                qDebug() << "[FFmpeg] Reset to beginning of stream";
            }
        }
    }
    
    // Decoder flush must happen AFTER demux reset
    if (m_codecContext) {
        avcodec_flush_buffers(m_codecContext);
    }
    
    // Reset timing for fresh playback
    m_timingInitialized = false;
    m_startTime = 0.0;
    m_startPts = 0.0;
    m_position = 0;
    
    // ✅ CRITICAL: Reset audio clock on fresh playback from beginning
    // Otherwise audio clock continues from previous playback, causing all frames to be dropped
    m_audioBasePts = NAN;
    m_audioClock = 0.0;
    m_audioSeekPending.store(false, std::memory_order_release);
    m_audioProcessedBaseUSecs = 0;  // Reset base - will be snapshotted at first frame
    m_holdVideoUntilAudio.store(false, std::memory_order_release);  // No hold needed for fresh playback
    // Clear audio buffer for fresh playback
    m_audioRemainder.clear();
    
    // Only restart audio device if it's not already running
    // This prevents unnecessary stop/start cycles (and AUDCLNT_E_NOT_STOPPED)
    if (m_audioSink) {
        if (!m_audioDevice || !m_audioDevice->isOpen()) {
            // Device not running - start it
            m_audioSink->setVolume(m_volume);
            m_audioDevice = m_audioSink->start();
            if (!m_audioDevice || !m_audioDevice->isOpen()) {
                qWarning() << "[FFmpeg] Failed to start audio device on play()";
            }
        } else {
            // Device already running - just ensure volume is correct and resume if paused
            m_audioSink->setVolume(m_volume);
            if (m_audioSink->state() == QAudio::SuspendedState) {
                m_audioSink->resume();
            }
        }
    }
    
    m_isPlaying = true;
    m_isPaused = false;
    
    // Wake up decode thread
    m_decodeCondition.wakeAll();
    locker.unlock();
    
    emit playbackStateChanged();
    emit positionChanged();
    
    qDebug() << "[FFmpeg] play() called - starting playback from beginning";
}

void FFmpegVideoPlayer::pause()
{
    QMutexLocker locker(&m_decodeMutex);
    
    if (!m_isPlaying || m_isPaused) {
        return; // Already paused or not playing
    }
    
    m_isPaused = true;
    m_pauseTime = nowSeconds();
    
    // Pause audio
    if (m_audioSink) {
        QMutexLocker audioLock(&m_audioMutex);
        m_audioSink->suspend();
    }
    
    // Decode thread will block on wait condition (already handled in decode loop)
    locker.unlock();
    
    emit playbackStateChanged();
    
    qDebug() << "[FFmpeg] pause() called";
}

void FFmpegVideoPlayer::stop()
{
    QMutexLocker locker(&m_decodeMutex);
    
    m_isPlaying = false;
    m_isPaused = false;
    
    // Stop audio
    if (m_audioSink) {
        QMutexLocker audioLock(&m_audioMutex);
        m_audioSink->stop();
    }
    
    // Reset timing
    m_timingInitialized = false;
    m_startTime = 0.0;
    m_startPts = 0.0;
    m_position = 0;
    m_audioClock = 0.0;
    
    // Wake decode thread so it can exit cleanly
    m_decodeCondition.wakeAll();
    locker.unlock();
    
    emit playbackStateChanged();
    emit positionChanged();
    
    qDebug() << "[FFmpeg] stop() called";
}

void FFmpegVideoPlayer::seek(int ms)
{
    if (!m_formatContext || !m_codecContext || m_videoStreamIndex < 0 || !m_videoStream) {
        qWarning() << "[FFmpeg] Cannot seek - media not ready";
        return;
    }
    
    qDebug() << "[FFmpeg] seek() called from C++:" << ms << "ms";
    
    // Clamp seek position to valid range
    qint64 positionMs = qBound<qint64>(qint64(0), qint64(ms), m_duration);
    
    QMutexLocker decodeLocker(&m_decodeMutex);
    QMutexLocker demuxLocker(&m_demuxMutex);
    
    // Convert ms → stream timebase
    AVRational timeBase = m_videoStream->time_base;
    int64_t seekPts = av_rescale_q(
        positionMs,
        AVRational{1, 1000},
        timeBase
    );
    
    qDebug() << "[FFmpeg] seek pts:" << seekPts << "timebase:" << timeBase.num << "/" << timeBase.den;
    
    // Flush demuxer (clears packet queues)
    avformat_flush(m_formatContext);
    
    // Perform seek (AVSEEK_FLAG_BACKWARD ensures we get a keyframe)
    int ret = av_seek_frame(
        m_formatContext,
        m_videoStreamIndex,
        seekPts,
        AVSEEK_FLAG_BACKWARD
    );
    
    if (ret < 0) {
        char errbuf[AV_ERROR_MAX_STRING_SIZE];
        av_strerror(ret, errbuf, sizeof(errbuf));
        qWarning() << "[FFmpeg] av_seek_frame failed:" << ret << errbuf;
        return;
    }
    
    // Flush decoders AFTER seek (critical - prevents old frames after seek)
    avcodec_flush_buffers(m_codecContext);
    
    // Reset timing for new position
    m_timingInitialized = false;
    double seekPtsSeconds = seekPts * av_q2d(timeBase);
    m_startPts = seekPtsSeconds;
    m_startTime = nowSeconds();  // ✅ FIX #1: Set to now (not "now - pts") for correct wall clock calculation
    m_playStartWallTime = nowSeconds();  // ✅ Set grace window start time for frame drop prevention
    
    // Mark video seek as pending - decode loop will discard frames until we reach target
    m_seekTargetPts = seekPtsSeconds;
    m_seekPending.store(true, std::memory_order_release);
    
    // ✅ OPTION A: Keep audio device running - just clear buffers and mark seek pending
    if (m_audioCodecContext) {
        avcodec_flush_buffers(m_audioCodecContext);
        // Clear audio buffer - drop old audio data
        m_audioRemainder.clear();
        // Reset audio clock - will be set by first good frame after seek
        m_audioClock = 0.0;
        m_audioBasePts = NAN;
        // Clear processedUSecs base - will be snapshotted when first good frame arrives
        m_audioProcessedBaseUSecs = m_audioSink ? m_audioSink->processedUSecs() : 0;  // Optional snapshot, will be updated at first frame
        // Set audio seek target (in seconds) - decode loop will drop frames until we reach it
        m_audioSeekTargetSec = positionMs / 1000.0;  // Convert ms to seconds
        // Convert to audio stream timebase if available for better precision
        if (m_audioStreamIndex >= 0 && m_formatContext->streams[m_audioStreamIndex]) {
            AVStream* audioStream = m_formatContext->streams[m_audioStreamIndex];
            int64_t audioSeekPts = av_rescale_q(
                positionMs,
                AVRational{1, 1000},
                audioStream->time_base
            );
            m_audioSeekTargetSec = audioSeekPts * av_q2d(audioStream->time_base);
        }
        m_audioSeekPending.store(true, std::memory_order_release);
        
        // ✅ NEW: prevent video presentation until audio is ready after seek
        // This ensures video and audio start together, preventing A/V desync
        m_holdVideoUntilAudio.store(true, std::memory_order_release);
        
        qDebug() << "[FFmpeg] Audio seek pending - target:" << m_audioSeekTargetSec << "seconds (device kept running, video held)";
        
        // Optional: Write a small silence chunk to avoid pops (5-10ms)
        // This is optional - if you want smooth scrubbing you can add it
        // For now, we'll just let the buffer drain naturally
    } else {
        // No audio stream - video can present immediately
        m_holdVideoUntilAudio.store(false, std::memory_order_release);
    }
    
    // ✅ CRITICAL: Do NOT stop/start audio device - keep it running!
    // This prevents AUDCLNT_E_NOT_STOPPED errors during rapid seeking
    // The audio device stays active, we just drop old buffers and seek in the stream
    
    // Update position immediately
    m_position = positionMs;
    
    // Reset decoder state
    m_decoderDrained = false;
    m_sentAnyPacket = false;
    
    // Wake decode thread to continue from new position
    m_decodeCondition.wakeAll();
    
    // Locks automatically released by RAII when lockers go out of scope
    emit positionChanged();
    
    qDebug() << "[FFmpeg] seek() completed to:" << positionMs << "ms (PTS:" << seekPts << "seconds:" << seekPtsSeconds << ")";
}

qint64 FFmpegVideoPlayer::position() const
{
    return m_position;
}

qint64 FFmpegVideoPlayer::duration() const
{
    return m_duration;
}

int FFmpegVideoPlayer::playbackState() const
{
    if (m_isPaused) return PausedState;
    if (m_isPlaying) return PlayingState;
    return StoppedState;
}

float FFmpegVideoPlayer::volume() const
{
    return m_volume;
}

void FFmpegVideoPlayer::setVolume(float volume)
{
    float newVolume = qBound(0.0f, volume, 1.0f);
    if (qFuzzyCompare(m_volume, newVolume)) {
        qDebug() << "[FFmpeg] setVolume called with same value:" << volume << "(ignored)";
        return; // No change
    }
    
    qDebug() << "[FFmpeg] setVolume called:" << volume << "->" << newVolume << "audioSink:" << (m_audioSink != nullptr);
    
    m_volume = newVolume;
    
    // Apply volume to audio sink if it exists
    if (m_audioSink) {
        m_audioSink->setVolume(m_volume);
        qDebug() << "[FFmpeg] Volume applied to audio sink:" << m_volume << "actual:" << m_audioSink->volume();
    } else {
        qDebug() << "[FFmpeg] Volume set but audio sink not available yet (will be applied when audio opens)";
    }
    
    emit volumeChanged();
}

bool FFmpegVideoPlayer::seekable() const
{
    return m_isSeekable;
}

enum AVPixelFormat FFmpegVideoPlayer::getFormatCallback(AVCodecContext* ctx, const enum AVPixelFormat* pix_fmts)
{
    // ✅ Get instance from opaque pointer (set during codec init)
    auto* self = static_cast<FFmpegVideoPlayer*>(ctx->opaque);
    if (!self) {
        qWarning() << "[FFmpeg] getFormatCallback: opaque pointer is null, using fallback";
        return pix_fmts[0]; // Fallback to first format
    }
    
    // Log what formats FFmpeg is offering (debug)
    qDebug() << "[FFmpeg] get_format offered formats:";
    for (const enum AVPixelFormat* p = pix_fmts; *p != AV_PIX_FMT_NONE; ++p) {
        qDebug() << "  -" << av_get_pix_fmt_name(*p);
    }
    
    // Strategy: 
    // 1. Prefer fast system memory formats (NV12, YUV420P, BGRA) - direct QVideoSink support
    // 2. For HDR/DV where only 10-bit is available: prefer D3D11 texture over CPU conversion
    //    D3D11 → system memory via av_hwframe_transfer_data() often gives NV12 8-bit directly
    //    This avoids expensive 4K 10-bit → 8-bit CPU swscale conversion
    
    // Scan formats to understand what's available
    bool hasFastSysMem = false;
    bool has10BitOnly = false;
    bool hasD3D11 = false;
    
    for (const enum AVPixelFormat* p = pix_fmts; *p != AV_PIX_FMT_NONE; ++p) {
        if (*p == AV_PIX_FMT_NV12 || *p == AV_PIX_FMT_YUV420P || *p == AV_PIX_FMT_BGRA) {
            hasFastSysMem = true;
        } else if (*p == AV_PIX_FMT_YUV420P10LE) {
            has10BitOnly = true;
        } else if (*p == AV_PIX_FMT_D3D11) {
            hasD3D11 = true;
        }
    }
    
    // First: Prefer fast system memory formats (8-bit, direct QVideoSink support)
    for (const enum AVPixelFormat* p = pix_fmts; *p != AV_PIX_FMT_NONE; ++p) {
        if (*p == AV_PIX_FMT_NV12) {
            qDebug() << "[FFmpeg] Selected AV_PIX_FMT_NV12 (system memory, hardware decode)";
            return *p;
        }
        if (*p == AV_PIX_FMT_YUV420P) {
            qDebug() << "[FFmpeg] Selected AV_PIX_FMT_YUV420P (system memory, hardware decode)";
            return *p;
        }
        if (*p == AV_PIX_FMT_BGRA) {
            qDebug() << "[FFmpeg] Selected AV_PIX_FMT_BGRA (system memory, hardware decode)";
            return *p;
        }
    }
    
    // Second: For HDR/DV (only 10-bit available)
    // ✅ FIX: Check forceSoftwareHDRPath toggle for stability testing
    // If enabled, prefer software 10-bit path instead of D3D11 to isolate D3D11VA issues
    if (has10BitOnly && !hasFastSysMem) {
        if (self->m_forceSoftwareHDRPath) {
            // Force software path for stability testing - avoids D3D11VA entirely
            for (const enum AVPixelFormat* p = pix_fmts; *p != AV_PIX_FMT_NONE; ++p) {
                if (*p == AV_PIX_FMT_YUV420P10LE) {
                    qDebug() << "[FFmpeg] Selected AV_PIX_FMT_YUV420P10LE (software HDR path - stability mode)";
                    return *p;
                }
            }
        } else if (hasD3D11) {
            // Default: prefer D3D11 texture over CPU conversion (av_hwframe_transfer_data() often gives NV12 8-bit directly)
            for (const enum AVPixelFormat* p = pix_fmts; *p != AV_PIX_FMT_NONE; ++p) {
                if (*p == AV_PIX_FMT_D3D11) {
                    qDebug() << "[FFmpeg] Selected AV_PIX_FMT_D3D11 (GPU texture) - HDR/DV detected, avoiding CPU 10-bit conversion";
                    return *p;
                }
            }
        }
    }
    
    // Third: Fallback to 10-bit if D3D11 not available or software path forced (will convert to 8-bit on CPU)
    for (const enum AVPixelFormat* p = pix_fmts; *p != AV_PIX_FMT_NONE; ++p) {
        if (*p == AV_PIX_FMT_YUV420P10LE) {
            qDebug() << "[FFmpeg] Selected AV_PIX_FMT_YUV420P10LE (10-bit HDR, will convert to 8-bit on CPU)";
            return *p;
        }
    }
    
    // Reject decoder-only formats (not renderable) - skip them
    // (These would have been skipped in the loops above anyway)
    
    // If we reach here, no acceptable format was found - return first offered format as fallback
    // This prevents FFmpeg from aborting, though it may not work correctly
    qWarning() << "[FFmpeg] No suitable system memory format available - using first offered format";
    return pix_fmts[0];  // Return first format (last-resort fallback)
}

// ✅ FIX #4: Removed updateState() polling entirely
// Position is updated in decode thread when frames are processed
// Timer was causing extra wakeups, jitter, and event queue pollution

void FFmpegVideoPlayer::setRenderer(QObject* renderer)
{
    // Cast to FFmpegVideoRenderer
    FFmpegVideoRenderer* videoRenderer = qobject_cast<FFmpegVideoRenderer*>(renderer);
    if (videoRenderer) {
        m_renderer = videoRenderer;
        // Set player reference in renderer so it can get pending frames
        videoRenderer->m_player = this;
        
        // Renderer is set - QQuickRhiItemRenderer will call getPendingFrame() in synchronize()
        qDebug() << "[FFmpeg] Renderer set - frames will be delivered via thread-safe handoff in synchronize()";
    } else if (renderer) {
        qWarning() << "[FFmpeg] setRenderer: object is not a FFmpegVideoRenderer";
        m_renderer = nullptr;
    } else {
        m_renderer = nullptr;
    }
}

bool FFmpegVideoPlayer::getPendingFrame(ID3D11Texture2D** texture, int* width, int* height)
{
    QMutexLocker locker(&m_pendingFrameMutex);
    
    if (m_pendingFrame.texture && m_pendingFrame.width > 0 && m_pendingFrame.height > 0) {
        *texture = m_pendingFrame.texture;
        *width = m_pendingFrame.width;
        *height = m_pendingFrame.height;
        
        // Clear pending frame (renderer takes ownership via AddRef)
        m_pendingFrame.texture = nullptr;
        m_pendingFrame.width = 0;
        m_pendingFrame.height = 0;
        
        return true;
    }
    
    return false;
}

