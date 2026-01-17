#ifndef FFMPEGVIDEOPLAYER_H
#define FFMPEGVIDEOPLAYER_H

#include <QObject>
#include <QUrl>
#include <QVideoSink>
#include <QAudioSink>
#include <QAudioFormat>
#include <QAudioDevice>
#include <QMediaDevices>
#include <QIODevice>
#include <QMutex>
#include <QThread>
#include <QWaitCondition>
#include <QQuickWindow>
#include <QtGui/rhi/qrhi.h>
#include <memory>
#include <cstdint>
#include <atomic>

// Forward declarations
#ifdef Q_OS_WIN
struct ID3D11Device;
struct ID3D11DeviceContext;
struct ID3D11Texture2D;
struct ID3D11VideoDevice;
struct ID3D11VideoContext;
struct ID3D11VideoProcessor;
struct ID3D11VideoProcessorEnumerator;
#endif

// Forward declaration for renderer (global class, not nested)
class FFmpegVideoRenderer;

// Forward declarations for FFmpeg
struct AVFormatContext;
struct AVCodecContext;
struct AVFrame;
struct AVPacket;
struct AVBufferRef;
struct AVStream;  // Required for m_videoStream member
struct AVD3D11FrameDescriptor;
struct SwrContext;  // For audio resampling

// Include FFmpeg pixel format enum (needed for AV_PIX_FMT_NONE and other constants)
extern "C" {
#include <libavutil/pixfmt.h>  // Required for AVPixelFormat enum and AV_PIX_FMT_* constants
}

// Forward declarations for D3D11
#ifdef Q_OS_WIN
struct ID3D11Device;
struct ID3D11DeviceContext;
struct ID3D11Texture2D;
struct ID3D11VideoDevice;
struct ID3D11VideoContext;
struct ID3D11VideoProcessor;
struct ID3D11VideoProcessorEnumerator;
#endif

class FFmpegVideoPlayer : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QUrl source READ source WRITE setSource NOTIFY sourceChanged)
    Q_PROPERTY(qint64 position READ position NOTIFY positionChanged)
    Q_PROPERTY(qint64 duration READ duration NOTIFY durationChanged)
    Q_PROPERTY(int playbackState READ playbackState NOTIFY playbackStateChanged)
    Q_PROPERTY(float volume READ volume WRITE setVolume NOTIFY volumeChanged)
    Q_PROPERTY(bool seekable READ seekable NOTIFY seekableChanged)
    Q_PROPERTY(QVideoSink* videoSink READ videoSink WRITE setVideoSink NOTIFY videoSinkChanged)
    Q_PROPERTY(int implicitWidth READ implicitWidth NOTIFY implicitSizeChanged)
    Q_PROPERTY(int implicitHeight READ implicitHeight NOTIFY implicitSizeChanged)
    Q_PROPERTY(QQuickWindow* window READ window WRITE setWindow NOTIFY windowChanged)

public:
    enum PlaybackState {
        StoppedState,
        PlayingState,
        PausedState
    };
    Q_ENUM(PlaybackState)

    explicit FFmpegVideoPlayer(QObject* parent = nullptr);
    ~FFmpegVideoPlayer();

    QUrl source() const;
    void setSource(const QUrl& source);

    qint64 position() const;
    qint64 duration() const;
    int playbackState() const;
    float volume() const;
    void setVolume(float volume);
    bool seekable() const;

    QVideoSink* videoSink() const { return m_videoSink; }
    void setVideoSink(QVideoSink* sink);

    int implicitWidth() const { return m_width; }
    int implicitHeight() const { return m_height; }

    QQuickWindow* window() const { return m_window; }
    void setWindow(QQuickWindow* window);

    Q_INVOKABLE void play();
    Q_INVOKABLE void pause();
    Q_INVOKABLE void stop();
    Q_INVOKABLE void seek(int ms);
    
    // Set the renderer to receive frames (C++ connection, not QML - QML can't receive native pointers)
    Q_INVOKABLE void setRenderer(QObject* renderer);
    
    // Get pending frame from decode thread (called from render thread only)
    // Returns true if a new frame was available and consumed
    bool getPendingFrame(ID3D11Texture2D** texture, int* width, int* height);

signals:
    void sourceChanged();
    void positionChanged();
    void durationChanged();
    void playbackStateChanged();
    void volumeChanged();
    void seekableChanged();
    void videoSinkChanged();
    void implicitSizeChanged();
    void windowChanged();
    void errorOccurred(int error, const QString &errorString);
    void durationAvailable();

private slots:
    void onSceneGraphInitialized(); // Called when RHI is ready

private:
    void initFFmpeg();
    void cleanupFFmpeg();
    void openMedia();
    void closeMedia();
    void decodeFrame();
    
    // D3D11 setup - import from Qt RHI
    bool initD3D11FromRHI();
    void cleanupD3D11();
    bool initVideoProcessor(uint32_t width, uint32_t height);  // Initialize Video Processor with actual dimensions
    
    // HDR tone mapping filter graph setup
    bool initHDRToneMappingFilter(int width, int height, AVPixelFormat inputFormat, int displayWidth = 0, int displayHeight = 0);
    void cleanupHDRToneMappingFilter();
    
    void processFrame(AVFrame* frame);
    
    // Decode thread
    void decodeThreadFunc();
    
    // GPU vendor detection
    enum GPUVendor {
        GPU_VENDOR_UNKNOWN,
        GPU_VENDOR_NVIDIA,
        GPU_VENDOR_INTEL,
        GPU_VENDOR_AMD
    };
    GPUVendor detectGPUVendor();
    
    // FFmpeg hardware decoder setup
    bool setupHardwareDecoder();  // Unified setup that chooses D3D11VA or CUVID
    bool setupD3D11VADecoder();
    bool setupCUDADecoder();
    
    // CUDA → D3D11 interop
    bool transferCUDAToD3D11(AVFrame* cudaFrame, ID3D11Texture2D** outTexture);
    
    // Static callback for codec format selection
    static enum AVPixelFormat getFormatCallback(AVCodecContext* ctx, const enum AVPixelFormat* pix_fmts);
    
    QUrl m_source;
    QVideoSink* m_videoSink = nullptr;
    QQuickWindow* m_window = nullptr;
    
    // FFmpeg
    AVFormatContext* m_formatContext = nullptr;
    AVCodecContext* m_codecContext = nullptr;
    AVFrame* m_frame = nullptr;
    AVFrame* m_hwFrame = nullptr; // Hardware frame
    AVFrame* m_swFrame = nullptr; // Software frame (for CUDA transfer)
    AVFrame* m_transferFrame = nullptr; // Persistent frame for D3D11 → CPU transfer (reused, no per-frame alloc/free)
    AVPacket* m_packet = nullptr;
    AVBufferRef* m_hwDeviceContext = nullptr;
    AVBufferRef* m_hwFramesContext = nullptr;
    int m_videoStreamIndex = -1;
    AVStream* m_videoStream = nullptr;  // Video stream for time_base
    GPUVendor m_gpuVendor = GPU_VENDOR_UNKNOWN;
    bool m_useCUDA = false;  // True if using CUVID, false if using D3D11VA
    
    // FFmpeg audio
    int m_audioStreamIndex = -1;
    AVCodecContext* m_audioCodecContext = nullptr;
    AVFrame* m_audioFrame = nullptr;
    SwrContext* m_swr = nullptr;
    
    // FFmpeg video conversion (10-bit to 8-bit)
    struct SwsContext* m_sws10to8 = nullptr;  // For converting YUV420P10LE to YUV420P (fallback, not used if filter graph active)
    AVFrame* m_tmp8bitFrame = nullptr;        // Temporary 8-bit frame for conversion
    
    // FFmpeg filter graph for HDR → SDR tone mapping
    struct AVFilterGraph* m_filterGraph = nullptr;
    struct AVFilterContext* m_filterSrcCtx = nullptr;   // Input buffer source
    struct AVFilterContext* m_filterSinkCtx = nullptr;  // Output buffer sink
    AVFrame* m_filterFrame = nullptr;                   // Frame for filter output
    int m_filterWidth = 0;                              // Width for filter graph (to detect dimension changes)
    int m_filterHeight = 0;                             // Height for filter graph (to detect dimension changes)
    AVPixelFormat m_filterInputFormat = AV_PIX_FMT_NONE; // Input format for filter graph
    std::atomic<int> m_framesInFilter{0};               // ✅ Backpressure: Track frames in filter graph pipeline
    static constexpr int MAX_IN_FLIGHT = 2;             // ✅ Max frames in filter graph (prevents unbounded memory growth)
    bool m_filterGraphInitialized = false;              // ✅ Guard: Track if filter graph is initialized for current playback session
    
    // Qt audio
    QAudioSink* m_audioSink = nullptr;
    QIODevice* m_audioDevice = nullptr;
    QAudioFormat m_audioFormat;  // Audio format (needed for latency compensation)
    QByteArray m_audioRemainder;  // Buffer for audio data that couldn't be written immediately
    
    // Audio clock (seconds)
    double m_audioClock = 0.0;
    double m_audioBasePts = NAN;  // First audio PTS seen (absolute stream seconds)
    qint64 m_audioProcessedBaseUSecs = 0;  // Snapshot of processedUSecs() when audio base PTS was set (for rebasing after seek)
    
    // Frame queue control - prevent GUI thread flooding
    std::atomic_bool m_framePending{false};  // Only ONE frame in flight to GUI thread
    
    // Playback timing
    double m_startTime = 0.0;  // Wall-clock time when playback started (seconds)
    double m_startPts = 0.0;    // PTS of first frame (seconds)
    double m_pauseTime = 0.0;   // Wall-clock time when paused (seconds)
    bool m_timingInitialized = false;  // True after first frame sets timing
    
    // Seek state
    std::atomic<bool> m_seekPending{false};  // Whether a video seek is in progress
    double m_seekTargetPts = 0.0;            // Target PTS for video seek (in seconds)
    std::atomic<bool> m_audioSeekPending{false};  // Whether an audio seek is in progress
    double m_audioSeekTargetSec = 0.0;       // Target PTS for audio seek (in seconds)
    std::atomic_bool m_holdVideoUntilAudio{false};  // Hold video presentation until audio is ready after seek
    
    // Decode thread
    QThread* m_decodeThread = nullptr;
    QMutex m_decodeMutex;
    QWaitCondition m_decodeCondition;
    bool m_decodeThreadRunning = false;
    
    // Demuxer mutex (protects AVFormatContext operations from concurrent access)
    QMutex m_demuxMutex;
    
    // Audio mutex (protects QAudioSink/QIODevice from concurrent access between decode thread and UI thread)
    QMutex m_audioMutex;
    
    // Playback start wall time (for grace window to prevent frame drops at startup)
    double m_playStartWallTime = 0.0;
    
    // Force software HDR path (for stability testing - avoids D3D11VA for HDR files)
    bool m_forceSoftwareHDRPath = false;
    
    // D3D11
#ifdef Q_OS_WIN
    ID3D11Device* m_d3d11Device = nullptr;  // Qt's device (for rendering only)
    ID3D11DeviceContext* m_d3d11Context = nullptr;  // Qt's context (for rendering only)
    ID3D11Device* m_ffmpegD3DDevice = nullptr;  // FFmpeg's D3D11VA device (for decode + VideoProcessor)
    ID3D11DeviceContext* m_ffmpegD3DContext = nullptr;  // FFmpeg's D3D11VA context
    ID3D11VideoDevice* m_videoDevice = nullptr;
    ID3D11VideoContext* m_videoContext = nullptr;
    ID3D11VideoProcessor* m_videoProcessor = nullptr;
    ID3D11VideoProcessorEnumerator* m_videoProcessorEnumerator = nullptr;
    ID3D11Texture2D* m_outputTexture = nullptr;
    
    // Renderer reference (for thread-safe texture handoff)
    FFmpegVideoRenderer* m_renderer = nullptr;
    
    // Thread-safe pending texture storage (decode thread → render thread)
    // Decode thread stores texture here, render thread consumes it
    struct PendingFrame {
        ID3D11Texture2D* texture = nullptr;
        int width = 0;
        int height = 0;
    };
    QMutex m_pendingFrameMutex;
    PendingFrame m_pendingFrame;
#endif
    
    // State
    qint64 m_duration = 0;
    qint64 m_position = 0;
    bool m_isSeekable = false;
    int m_lastPlaybackState = StoppedState;
    float m_volume = 1.0f;
    
    // Video dimensions (coded size)
    int m_width = 0;
    int m_height = 0;
    
    // Output texture dimensions (actual decoded size)
    uint32_t m_outWidth = 0;
    uint32_t m_outHeight = 0;
    
    QMutex m_mutex;
    bool m_isPlaying = false;
    bool m_isPaused = false;
    
    // Media lifecycle guards (prevent multiple openMedia() calls)
    bool m_mediaOpening = false;
    bool m_mediaOpened = false;
    
    // Decoder state tracking (for proper EOF/drain handling)
    bool m_decoderDrained = false;
    bool m_sentAnyPacket = false;
};

#endif // FFMPEGVIDEOPLAYER_H

