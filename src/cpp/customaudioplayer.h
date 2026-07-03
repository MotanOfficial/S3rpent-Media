#ifndef CUSTOMAUDIOPLAYER_H
#define CUSTOMAUDIOPLAYER_H

#include <QObject>
#include <QUrl>
#include <QAudioDecoder>
#include <QAudioBuffer>
#include <QAudioSink>
#include <QIODevice>
#include <QTimer>
#include <QAudioFormat>
#include <QElapsedTimer>
#include <QMutex>
#include <QMediaPlayer>
#include <QMediaMetaData>
#include "customaudioprocessor.h"

class AudioVisualizer;  // Forward declaration

class CustomAudioPlayer : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QUrl source READ source WRITE setSource NOTIFY sourceChanged)
    Q_PROPERTY(qint64 position READ position NOTIFY positionChanged)
    Q_PROPERTY(qint64 duration READ duration NOTIFY durationChanged)
    Q_PROPERTY(int playbackState READ playbackState NOTIFY playbackStateChanged)
    Q_PROPERTY(qreal volume READ volume WRITE setVolume NOTIFY volumeChanged)
    Q_PROPERTY(bool seekable READ seekable NOTIFY seekableChanged)
    Q_PROPERTY(QVariantMap metaData READ metaData NOTIFY metaDataChanged)
    Q_PROPERTY(QObject* audioVisualizer READ audioVisualizer WRITE setAudioVisualizer)
    Q_PROPERTY(bool loop READ loop WRITE setLoop NOTIFY loopChanged)

public:
    enum PlaybackState {
        StoppedState = 0,
        PlayingState = 1,
        PausedState = 2
    };
    Q_ENUM(PlaybackState)

    explicit CustomAudioPlayer(QObject *parent = nullptr);
    ~CustomAudioPlayer();

    QUrl source() const { return m_source; }
    void setSource(const QUrl &source);

    qint64 position() const { return m_position; }
    qint64 duration() const { return m_duration; }
    int playbackState() const { return m_playbackState; }
    qreal volume() const { return m_volume; }
    void setVolume(qreal volume);
    bool seekable() const { return m_seekable; }
    QVariantMap metaData() const { return m_metaData; }
    bool loop() const { return m_loop; }
    void setLoop(bool loop);

    // EQ control
    Q_INVOKABLE void setBandGain(int band, qreal gainDb);
    Q_INVOKABLE qreal getBandGain(int band) const;
    Q_INVOKABLE void setAllBandGains(const QVariantList &gains);
    Q_INVOKABLE void setEQEnabled(bool enabled);
    Q_INVOKABLE bool isEQEnabled() const;

    // Playback control
    Q_INVOKABLE void play();
    Q_INVOKABLE void pause();
    Q_INVOKABLE void stop();
    Q_INVOKABLE void seek(qint64 position);
    
    // Set audio visualizer to feed samples to (avoids WASAPI loopback capturing all system audio)
    void setAudioVisualizer(QObject* visualizer);
    QObject* audioVisualizer() const { return m_audioVisualizer; }

signals:
    void sourceChanged();
    void positionChanged();
    void durationChanged();
    void playbackStateChanged();
    void volumeChanged();
    void seekableChanged();
    void errorOccurred(int error, const QString &errorString);
    void metaDataChanged();
    void loopChanged();

private slots:
    void onBufferReady();
    void onFinished();
    void onError();
    void updatePosition();
    void onMetadataDurationChanged(qint64 durationMs);
    void onMetadataMediaStatusChanged(QMediaPlayer::MediaStatus status);

private:
    void setupAudioPipeline();
    void cleanupAudioPipeline();
    void updatePlaybackState(PlaybackState state);
    void writeChunkToDevice();  // Non-blocking chunk writer
    void onMetaDataChanged();  // Handle metadata extraction from QMediaPlayer
    bool applyDurationMs(qint64 ms);  // Set duration from metadata player / tags when ms > 0
    void ensureMetadataPlayer();
    void scheduleMetadataLoad(const QString &localFilePath);
    void scheduleMetadataLoadUrl(const QUrl &url);
    void rebindDecoderSource();

#ifdef HAS_FFMPEG_LIBS
    bool initFfmpegLocalDecoder(const QString &path);
    void shutdownFfmpegLocalDecoder();
    void pumpFfmpegAudio();
    void seekFfmpegLocal(qint64 positionMs);
    void enqueuePcmBuffer(const QByteArray &pcm, int sampleRate, int channels);
#endif

    QUrl m_source;
    qint64 m_position;
    qint64 m_duration;
    PlaybackState m_playbackState;
    qreal m_volume;
    bool m_seekable;
    bool m_loop;

    QAudioDecoder *m_decoder;
    QAudioSink *m_audioSink;
    QIODevice *m_audioDevice;  // Returned by QAudioSink::start()
    CustomAudioProcessor *m_processor;
    QTimer *m_positionTimer;
    QTimer *m_errorCheckTimer;
    QAudioFormat m_audioFormat;
    bool m_formatInitialized;
    qint64 m_totalFrames;  // Track total frames decoded for accurate duration calculation
    qint64 m_seekTargetPosition;  // Target position when seeking (0 = not seeking)
    PlaybackState m_seekPreserveState;  // Playback state to restore after seeking completes
    bool m_durationCalculated;  // Whether duration has been calculated (preserve it after first calculation)
    qint64 m_bytesWritten;  // Track bytes written to audio device for accurate position tracking
    QElapsedTimer m_playbackStartTime;  // Track when audio actually starts playing
    qint64 m_basePosition;  // Base position when playback starts (for elapsed time calculation)
    
    // Metadata extraction using QMediaPlayer (reused across tracks; loaded after decode pipeline starts)
    QMediaPlayer *m_metadataPlayer;
    QVariantMap m_metaData;
    
    // Audio visualizer for feeding samples directly (avoids WASAPI loopback)
    QObject *m_audioVisualizer;
    
    QMutex m_writeMutex;
    QList<QAudioBuffer> m_pendingWrites;  // Raw buffers; EQ applied in writeChunkToDevice
    QByteArray m_partialProcessedData;  // Partial processed buffer if we couldn't write it all
    QTimer *m_writeTimer;  // Timer to periodically write chunks without blocking
    
    // Cleanup synchronization
    bool m_cleaningUp;  // Flag to prevent callbacks during cleanup
    QMutex m_cleanupMutex;  // Mutex to protect cleanup operations

#ifdef HAS_FFMPEG_LIBS
    bool m_ffmpegActive = false;
    bool m_ffmpegEof = false;
    struct AVFormatContext *m_avFmt = nullptr;
    struct AVCodecContext *m_avCodec = nullptr;
    struct SwrContext *m_swr = nullptr;
    struct AVPacket *m_avPacket = nullptr;
    struct AVFrame *m_avFrame = nullptr;
    int m_avAudioStream = -1;
    QTimer *m_ffmpegPumpTimer = nullptr;
#endif
};

#endif // CUSTOMAUDIOPLAYER_H
