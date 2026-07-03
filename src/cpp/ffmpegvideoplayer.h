#ifndef FFMPEGVIDEOPLAYER_H
#define FFMPEGVIDEOPLAYER_H

#include <QObject>
#include <QUrl>
#include <QVideoSink>
#include <QVideoFrame>
#include <QAudioSink>
#include <QAudioFormat>
#include <QAudioDevice>
#include <QMediaDevices>
#include <QIODevice>
#include <QMutex>
#include <QRecursiveMutex>
#include <QThread>
#include <QWaitCondition>
#include <QQuickWindow>
#include <QProcess>
#include <QByteArray>
#include <QAtomicInteger>
#include <QtConcurrent/QtConcurrent>
#include <QtGui/rhi/qrhi.h>
#include <memory>
#include <cstdint>
#include <atomic>
#include <deque>

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
struct AVIOContext;
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
    Q_PROPERTY(bool useYtDlpPipe READ useYtDlpPipe WRITE setUseYtDlpPipe NOTIFY useYtDlpPipeChanged)
    Q_PROPERTY(int ytDlpMaxHeight READ ytDlpMaxHeight WRITE setYtDlpMaxHeight NOTIFY ytDlpMaxHeightChanged)
    Q_PROPERTY(qint64 position READ position NOTIFY positionChanged)
    Q_PROPERTY(qint64 duration READ duration NOTIFY durationChanged)
    Q_PROPERTY(int playbackState READ playbackState NOTIFY playbackStateChanged)
    Q_PROPERTY(float volume READ volume WRITE setVolume NOTIFY volumeChanged)
    Q_PROPERTY(bool audioEnabled READ audioEnabled WRITE setAudioEnabled NOTIFY audioEnabledChanged)
    Q_PROPERTY(bool seekable READ seekable NOTIFY seekableChanged)
    Q_PROPERTY(QVideoSink* videoSink READ videoSink WRITE setVideoSink NOTIFY videoSinkChanged)
    Q_PROPERTY(int implicitWidth READ implicitWidth NOTIFY implicitSizeChanged)
    Q_PROPERTY(int implicitHeight READ implicitHeight NOTIFY implicitSizeChanged)
    Q_PROPERTY(QQuickWindow* window READ window WRITE setWindow NOTIFY windowChanged)
    Q_PROPERTY(QString logTag READ logTag WRITE setLogTag NOTIFY logTagChanged)

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

    bool useYtDlpPipe() const { return m_useYtDlpPipe; }
    void setUseYtDlpPipe(bool v);

    int ytDlpMaxHeight() const { return m_ytDlpMaxHeight; }
    void setYtDlpMaxHeight(int v);

    qint64 position() const;
    qint64 duration() const;
    int playbackState() const;
    float volume() const;
    void setVolume(float volume);
    bool audioEnabled() const { return m_audioEnabled; }
    void setAudioEnabled(bool v);
    bool seekable() const;

    QVideoSink* videoSink() const { return m_videoSink; }
    void setVideoSink(QVideoSink* sink);

    int implicitWidth() const { return m_width; }
    int implicitHeight() const { return m_height; }

    QQuickWindow* window() const { return m_window; }
    void setWindow(QQuickWindow* window);

    QString logTag() const { return m_logTag; }
    void setLogTag(const QString& v);

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
    void useYtDlpPipeChanged();
    void ytDlpMaxHeightChanged();
    void positionChanged();
    void durationChanged();
    void playbackStateChanged();
    void volumeChanged();
    void audioEnabledChanged();
    void seekableChanged();
    void videoSinkChanged();
    void implicitSizeChanged();
    void windowChanged();
    void logTagChanged();
    void errorOccurred(int error, const QString &errorString);
    void durationAvailable();

private slots:
    void onSceneGraphInitialized(); // Called when RHI is ready

private:
    void initFFmpeg();
    void cleanupFFmpeg();
    void openMedia();
    void closeMedia();
    // yt-dlp piping (for YouTube / signed streams)
    void cleanupYtDlpPipe();
    bool startYtDlpPipeProcess(const QUrl &url);
    void openMediaFromYtDlpPipe();
    static int ytDlpReadPacket(void *opaque, uint8_t *buf, int buf_size);

    void decodeFrame();
    
    // D3D11 setup - import from Qt RHI
    bool initD3D11FromRHI();
    void cleanupD3D11();
    bool initVideoProcessor(uint32_t width, uint32_t height);  // Initialize Video Processor with actual dimensions
    
    // HDR tone mapping filter graph setup
    bool initHDRToneMappingFilter(int width, int height, AVPixelFormat inputFormat, int displayWidth = 0, int displayHeight = 0);
    void cleanupHDRToneMappingFilter();
    
    void processFrame(AVFrame* frame);

    // Optional A/V diagnostics (enable with env S3_FFMPEG_AV_DIAG=1)
    void avDiagLogFirstAudioWrite(qint64 writtenBytes,
                                  qint64 sinkProcUs = -1,
                                  qint64 bufBytes = -1,
                                  int bytesFree = -1,
                                  int sinkState = -1);
    void avDiagLogFirstVideoDecodeQueued(const char* pathTag);
    void avDiagLogFirstVideoSink(qint64 startUs, qint64 endUs, const char* pathTag);
    void avDiagLogPacedFrame(double rawFramePts, double masterClockAbs, double videoClockAbs, double diff,
                             double avOffsetSec);
    void avDiagLogAudioWriteSeq(qint64 writtenBytes, qint64 procUs, int bytesFree);
    // Called with m_audioMutex held; sink/device open. Re-anchor when writable headroom is critically low.
    void reanchorAudioMasterIfCriticallyLowBytesFreeLocked(double framePtsSec, int bytesFreeAfterWrite);
    // Decode-thread A/V sync: updates queued estimate + masterClockAbs from processedUSecs / wall anchor.
    void refreshAudioMasterClockForSync(double& masterClockAbs);
    void presenterThreadFunc();
    void startPresenterThreadIfNeeded();
    void stopPresenterThread();
    
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
    AVIOContext* m_avioContext = nullptr;
    uint8_t* m_avioBuffer = nullptr;
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
    bool m_audioEnabled = true;

    bool m_useYtDlpPipe = false;
    int m_ytDlpMaxHeight = 0;
    QProcess* m_ytDlpProcess = nullptr;
    QByteArray m_pipeBuffer;
    bool m_pipeEof = false;
    QMutex m_pipeMutex;
    QWaitCondition m_pipeCond;

    // YouTube direct URL mode (enables seeking via HTTP ranges when possible).
    bool m_tryYouTubeDirectUrl = true;
    QString m_youTubeDirectUrl;

    // YouTube adaptive mux (bestvideo+bestaudio) -> ffmpeg mux to stdout -> our pipe.
    bool m_tryYouTubeAdaptiveMux = true;
    QProcess* m_ytMuxProcess = nullptr;

    QString m_logTag;
    
    // Audio clock (seconds)
    double m_audioClock = 0.0;
    double m_audioBasePts = NAN;  // First audio PTS seen (absolute stream seconds)
    qint64 m_audioProcessedBaseUSecs = 0;  // Snapshot of processedUSecs() when audio base PTS was set (for rebasing after seek)
    std::atomic<qint64> m_lastQueuedAudioUSecs{0}; // Approx queued audio in device buffer (for startup/seek hold)

    // A/V sync offset (seconds)
    // Some files have audio/video streams with different start PTS. If we compare absolute PTS directly,
    // video can appear permanently ahead/behind by a constant offset (e.g. ~200ms).
    double m_firstVideoPts = NAN;
    double m_firstAudioPts = NAN;
    double m_avSyncOffsetSec = 0.0; // videoPts - audioPts
    bool m_avSyncOffsetValid = false;
    bool m_avSyncNeedMasterCalib = false; // If true, learn offset from running audio master clock (AAC priming/skip cases)
    bool m_avSyncOffsetRefinedFromMaster = false; // One-shot refine using audio master (audible) to remove constant latency
    int m_avSyncRefineCount = 0;
    
    // Frame queue control - prevent GUI thread flooding.
    // Allow a tiny queue (2 frames) to avoid stutter from over-aggressive skipping on busy UI frames.
    std::atomic_int m_framesInFlight{0};
    
    // Playback timing
    double m_startTime = 0.0;  // Wall-clock time when playback started (seconds)
    double m_startPts = 0.0;    // PTS of first frame (seconds)
    double m_pauseTime = 0.0;   // Wall-clock time when paused (seconds)
    bool m_timingInitialized = false;  // True after first frame sets timing

    // Audio master clock anchor (seconds). When audio base PTS becomes known, we anchor it to wall time
    // so master clock advances at real-time even if processedUSecs() is unreliable on some devices/files.
    double m_audioBaseWallTime = 0.0;

    // Current video frame timestamps (microseconds), used to tag QVideoFrame for QVideoSink pacing.
    // Written by decode thread right before calling processFrame().
    qint64 m_curVideoStartUs = -1;
    qint64 m_curVideoEndUs = -1;

    
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

    // yt-dlp open thread (keeps UI responsive while avformat_open_input waits for bytes)
    QThread* m_openThread = nullptr;
    std::atomic_bool m_openThreadRunning{false};
    
    // Demuxer mutex (protects AVFormatContext operations from concurrent access)
    QMutex m_demuxMutex;
    
    // Audio mutex (protects QAudioSink/QIODevice from concurrent access between decode thread and UI thread)
    QMutex m_audioMutex;
    
    // Playback start wall time (for grace window to prevent frame drops at startup)
    double m_playStartWallTime = 0.0;

    // Startup gating: avoid dropping the very first few video frames due to decode lead/lag.
    // Some files legitimately start with first decoded video PTS > 0 (encoder delay / cut),
    // and treating those as "late" can make startup feel like frames are skipped.
    int m_startupNoDropFrames = 0;

    // Raw video PTS sanity (network/pipe streams can jump forward unexpectedly).
    double m_lastVideoPtsRaw = NAN;

    // Presentation queue (decode thread -> presenter thread -> GUI).
    struct QueuedVideoItem {
        enum class Kind { NV12, YUV420P, Frame };
        Kind kind = Kind::Frame;
        int width = 0;
        int height = 0;
        QByteArray p0; // NV12: Y, YUV420P: Y
        QByteArray p1; // NV12: UV, YUV420P: U
        QByteArray p2; // YUV420P: V
        QVideoFrame frame; // used for BGRA/generic
        qint64 startUs = -1;
        qint64 endUs = -1;
        const char* tag = "queue";
    };
    QMutex m_videoQueueMutex;
    QWaitCondition m_videoQueueCond;
    std::deque<QueuedVideoItem> m_videoQueue;
    static constexpr int kMaxQueuedVideoItems = 6;
    std::atomic_bool m_presentThreadRunning{false};
    QThread* m_presentThread = nullptr;
    std::atomic_int m_presentInFlight{0};

    std::atomic_bool m_avDiagFirstAudioWriteLogged{false};
    std::atomic_bool m_avDiagFirstVideoQueuedLogged{false};
    std::atomic_bool m_avDiagFirstVideoSinkLogged{false};
    int m_avDiagPacedFrameIndex = 0;
    std::atomic_int m_avDiagAudioWriteSeq{0};

    // Presentation bootstrap: some files start video at non-zero PTS (e.g. ~2s). Never block the first frame.
    std::atomic_bool m_presentedAnyVideo{false};

    // Stream PTS gate: only first video frame after play/seek (see ffmpegvideoplayer.cpp). Never repeat per frame —
    // blocking the decode thread starves av_read_frame() and underruns audio after ~1–2s.
    bool m_streamPtsGateDone = false;
    
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
    std::atomic_bool m_isPlaying{false};
    std::atomic_bool m_isPaused{false};
    
    // Media lifecycle guards (prevent multiple openMedia() calls)
    bool m_mediaOpening = false;
    bool m_mediaOpened = false;

    // Serialize open/close/stop across threads (yt-dlp opens on worker thread).
    QRecursiveMutex m_mediaLifecycleMutex;
    
    // Decoder state tracking (for proper EOF/drain handling)
    bool m_decoderDrained = false;
    bool m_sentAnyPacket = false;
};

#endif // FFMPEGVIDEOPLAYER_H

