#ifndef MEDIAPLAYERWRAPPER_H
#define MEDIAPLAYERWRAPPER_H

#include <QObject>
#include <QMediaPlayer>
#include <QAudioOutput>
#include <QVideoSink>
#include <QString>
#include <QUrl>
#include "subtitleformatter.h"

class MediaPlayerWrapper : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QUrl source READ source WRITE setSource NOTIFY sourceChanged)
    Q_PROPERTY(qreal volume READ volume WRITE setVolume NOTIFY volumeChanged)
    Q_PROPERTY(qint64 duration READ duration NOTIFY durationChanged)
    Q_PROPERTY(qint64 position READ position WRITE setPosition NOTIFY positionChanged)
    Q_PROPERTY(bool playing READ isPlaying NOTIFY playingChanged)
    Q_PROPERTY(bool paused READ isPaused NOTIFY pausedChanged)
    Q_PROPERTY(bool stopped READ isStopped NOTIFY stoppedChanged)
    Q_PROPERTY(bool hasVideo READ hasVideo NOTIFY hasVideoChanged)
    Q_PROPERTY(bool hasAudio READ hasAudio NOTIFY hasAudioChanged)
    Q_PROPERTY(bool seekable READ seekable NOTIFY seekableChanged)
    Q_PROPERTY(qreal playbackRate READ playbackRate WRITE setPlaybackRate NOTIFY playbackRateChanged)
    Q_PROPERTY(QVariantList audioTracks READ audioTracks NOTIFY audioTracksChanged)
    Q_PROPERTY(int activeAudioTrack READ activeAudioTrack WRITE setActiveAudioTrack NOTIFY activeAudioTrackChanged)
    Q_PROPERTY(QVariantList subtitleTracks READ subtitleTracks NOTIFY subtitleTracksChanged)
    Q_PROPERTY(int activeSubtitleTrack READ activeSubtitleTrack WRITE setActiveSubtitleTrack NOTIFY activeSubtitleTrackChanged)
    Q_PROPERTY(QString formattedSubtitleText READ formattedSubtitleText NOTIFY formattedSubtitleTextChanged)
    Q_PROPERTY(QString rawSubtitleText READ rawSubtitleText NOTIFY rawSubtitleTextChanged)
    
public:
    explicit MediaPlayerWrapper(QObject *parent = nullptr);
    ~MediaPlayerWrapper();
    
    // Properties
    QUrl source() const { return m_source; }
    void setSource(const QUrl &source);
    
    qreal volume() const;
    void setVolume(qreal volume);
    
    qint64 duration() const;
    qint64 position() const;
    void setPosition(qint64 position);
    
    bool isPlaying() const;
    bool isPaused() const;
    bool isStopped() const;
    
    bool hasVideo() const;
    bool hasAudio() const;
    bool seekable() const;
    qreal playbackRate() const;
    void setPlaybackRate(qreal rate);
    
    QVariantList audioTracks() const;
    int activeAudioTrack() const;
    void setActiveAudioTrack(int index);
    
    QVariantList subtitleTracks() const;
    int activeSubtitleTrack() const;
    void setActiveSubtitleTrack(int index);
    
    QString formattedSubtitleText() const { return m_formattedSubtitleText; }
    QString rawSubtitleText() const { return m_rawSubtitleText; }
    
    // Methods
    Q_INVOKABLE void play();
    Q_INVOKABLE void pause();
    Q_INVOKABLE void stop();
    Q_INVOKABLE void seek(qint64 position);
    
    // Get the underlying QMediaPlayer for video output
    QMediaPlayer* mediaPlayer() const { return m_mediaPlayer; }
    
    // Set subtitle text manually (for external subtitle files)
    Q_INVOKABLE void setSubtitleText(const QString &text);
    
signals:
    void sourceChanged();
    void volumeChanged();
    void durationChanged();
    void positionChanged();
    void playingChanged();
    void pausedChanged();
    void stoppedChanged();
    void hasVideoChanged();
    void hasAudioChanged();
    void seekableChanged();
    void playbackRateChanged();
    void audioTracksChanged();
    void activeAudioTrackChanged();
    void subtitleTracksChanged();
    void activeSubtitleTrackChanged();
    void formattedSubtitleTextChanged();
    void rawSubtitleTextChanged();
    void errorOccurred(int error, const QString &errorString);
    void metaDataChanged();
    
private slots:
    void onPlaybackStateChanged(QMediaPlayer::PlaybackState state);
    void onMediaStatusChanged(QMediaPlayer::MediaStatus status);
    void onDurationChanged(qint64 duration);
    void onPositionChanged(qint64 position);
    void onErrorOccurred(QMediaPlayer::Error error, const QString &errorString);
    void onMetaDataChanged();
    void onActiveSubtitleTrackChanged();
    
private:
    void updateSubtitleText();
    void updateTracks();
    
    QMediaPlayer *m_mediaPlayer;
    QAudioOutput *m_audioOutput;
    SubtitleFormatter *m_subtitleFormatter;
    
    QUrl m_source;
    QString m_rawSubtitleText;
    QString m_formattedSubtitleText;
    
    QVariantList m_audioTracks;
    QVariantList m_subtitleTracks;
    int m_activeAudioTrack;
    int m_activeSubtitleTrack;
};

#endif // MEDIAPLAYERWRAPPER_H

