#ifndef WMFVIDEOPLAYER_H
#define WMFVIDEOPLAYER_H

#include <QObject>
#include <QUrl>
#include <QString>
#include <QTimer>
#include <QVideoSink>
#include <QVideoFrame>
#include <QImage>
#include <QAudioSink>
#include <QIODevice>
#include <QByteArray>
#include <QThread>
#include <QMutex>
#include <QWaitCondition>
#include <QProcess>
#include <QMediaPlayer>

class WMFVideoPlayer : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QUrl source READ source WRITE setSource NOTIFY sourceChanged)
    Q_PROPERTY(int position READ position NOTIFY positionChanged)
    Q_PROPERTY(int duration READ duration NOTIFY durationChanged)
    Q_PROPERTY(int playbackState READ playbackState NOTIFY playbackStateChanged)
    Q_PROPERTY(qreal volume READ volume WRITE setVolume NOTIFY volumeChanged)
    Q_PROPERTY(bool seekable READ seekable NOTIFY seekableChanged)
    Q_PROPERTY(QVideoSink* videoSink READ videoSink WRITE setVideoSink NOTIFY videoSinkChanged)

public:
    explicit WMFVideoPlayer(QObject *parent = nullptr);
    ~WMFVideoPlayer();

    QUrl source() const { return m_source; }
    void setSource(const QUrl &source);

    int position() const { return m_position; }
    int duration() const { return m_duration; }
    int playbackState() const { return m_playbackState; }
    qreal volume() const { return m_volume; }
    void setVolume(qreal volume);
    bool seekable() const { return m_seekable; }

    QVideoSink* videoSink() const { return m_videoSink; }
    void setVideoSink(QVideoSink *sink);

    Q_INVOKABLE void play();
    Q_INVOKABLE void pause();
    Q_INVOKABLE void stop();
    Q_INVOKABLE void seek(int position);

signals:
    void sourceChanged();
    void positionChanged();
    void durationChanged();
    void playbackStateChanged();
    void volumeChanged();
    void seekableChanged();
    void videoSinkChanged();
    void errorOccurred(int error, const QString &errorString);

private slots:
    void updatePosition();
    void processVideoFrames();
    void playbackWorker(); // Worker thread function for continuous playback

private:
    // FFmpeg audio functions
    void setupAudioOutput(int channels = 2);
    void decodeAllAudio(); // Decode entire audio track into memory buffer using FFmpeg
    void feedAudioToSink(); // Continuously feed decoded audio to QAudioSink
    int calculateAudioPosition(); // Calculate current position from audio bytes written (master timeline)
    
    // Qt Multimedia video
    void setupMediaPlayer(); // Setup QMediaPlayer for video
    void detectSpecialHandling(); // Check if video needs special handling (broken timestamps)

    QUrl m_source;
    int m_position;
    int m_duration; // Actual duration from audio (accurate)
    int m_containerDuration; // Container duration from QMediaPlayer (may be broken)
    int m_playbackState; // 0=Stopped, 1=Playing, 2=Paused
    qreal m_volume;
    bool m_seekable;
    bool m_videoReady; // Whether video is fully loaded and ready for playback
    QVideoSink *m_videoSink;
    QTimer *m_positionTimer;
    QAudioSink *m_audioSink;
    QIODevice *m_audioDevice;
    QByteArray m_audioBuffer;
    QByteArray m_decodedAudioData; // Complete decoded audio track
    bool m_audioDecoded; // Whether audio has been fully decoded
    qint64 m_audioBytesWritten; // How many bytes of decoded audio we've written to QAudioSink
    QTimer *m_audioFeedTimer; // Timer to continuously feed audio to QAudioSink
    bool m_needsSpecialHandling; // Whether video has broken timestamps and needs FFmpeg audio extraction
    qint64 m_lastSyncTime; // Timestamp of last video sync to debounce repeated syncs
    
    // Qt Multimedia for video
    QMediaPlayer *m_mediaPlayer;
    QAudioOutput *m_audioOutput; // Audio output for QMediaPlayer (can be muted/unmuted)
    
    // FFmpeg audio decoding (via subprocess to handle HE-AAC correctly)
    QProcess *m_ffmpegProcess;
};

#endif // WMFVIDEOPLAYER_H

