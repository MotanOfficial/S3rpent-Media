#include "mediaplayerwrapper.h"
#include <QMediaPlayer>
#include <QAudioOutput>
#include <QVideoSink>
#include <QDebug>
#include <QMediaMetaData>
#include <QTimer>

MediaPlayerWrapper::MediaPlayerWrapper(QObject *parent)
    : QObject(parent)
    , m_mediaPlayer(new QMediaPlayer(this))
    , m_audioOutput(new QAudioOutput(this))
    , m_subtitleFormatter(new SubtitleFormatter(this))
    , m_activeAudioTrack(-1)
    , m_activeSubtitleTrack(-1)
{
    m_mediaPlayer->setAudioOutput(m_audioOutput);
    
    // Connect signals
    connect(m_mediaPlayer, &QMediaPlayer::playbackStateChanged, this, &MediaPlayerWrapper::onPlaybackStateChanged);
    connect(m_mediaPlayer, &QMediaPlayer::mediaStatusChanged, this, &MediaPlayerWrapper::onMediaStatusChanged);
    connect(m_mediaPlayer, &QMediaPlayer::durationChanged, this, &MediaPlayerWrapper::onDurationChanged);
    connect(m_mediaPlayer, &QMediaPlayer::positionChanged, this, &MediaPlayerWrapper::onPositionChanged);
    connect(m_mediaPlayer, &QMediaPlayer::errorOccurred, this, &MediaPlayerWrapper::onErrorOccurred);
    connect(m_mediaPlayer, &QMediaPlayer::metaDataChanged, this, &MediaPlayerWrapper::onMetaDataChanged);
    
    // Note: QMediaPlayer doesn't have activeSubtitleTrackChanged signal
    // We'll check for changes in updateTracks() instead
    
    // Try to intercept subtitle text - Qt 6 doesn't have direct subtitle text signal
    // We'll use a timer to periodically check for subtitle updates
    // Note: This is a workaround since QMediaPlayer doesn't expose subtitle text directly
    QTimer *subtitleCheckTimer = new QTimer(this);
    connect(subtitleCheckTimer, &QTimer::timeout, this, &MediaPlayerWrapper::updateSubtitleText);
    subtitleCheckTimer->start(100); // Check every 100ms
    
    // Initial track update
    updateTracks();
}

MediaPlayerWrapper::~MediaPlayerWrapper()
{
}

void MediaPlayerWrapper::setSource(const QUrl &source)
{
    if (m_source != source) {
        m_source = source;
        m_mediaPlayer->setSource(source);
        m_rawSubtitleText.clear();
        m_formattedSubtitleText.clear();
        emit sourceChanged();
        emit rawSubtitleTextChanged();
        emit formattedSubtitleTextChanged();
        updateTracks();
    }
}

qreal MediaPlayerWrapper::volume() const
{
    return m_audioOutput->volume();
}

void MediaPlayerWrapper::setVolume(qreal volume)
{
    if (m_audioOutput->volume() != volume) {
        m_audioOutput->setVolume(volume);
        emit volumeChanged();
    }
}

qint64 MediaPlayerWrapper::duration() const
{
    return m_mediaPlayer->duration();
}

qint64 MediaPlayerWrapper::position() const
{
    return m_mediaPlayer->position();
}

void MediaPlayerWrapper::setPosition(qint64 position)
{
    m_mediaPlayer->setPosition(position);
}

bool MediaPlayerWrapper::isPlaying() const
{
    return m_mediaPlayer->playbackState() == QMediaPlayer::PlayingState;
}

bool MediaPlayerWrapper::isPaused() const
{
    return m_mediaPlayer->playbackState() == QMediaPlayer::PausedState;
}

bool MediaPlayerWrapper::isStopped() const
{
    return m_mediaPlayer->playbackState() == QMediaPlayer::StoppedState;
}

bool MediaPlayerWrapper::hasVideo() const
{
    return m_mediaPlayer->hasVideo();
}

bool MediaPlayerWrapper::hasAudio() const
{
    return m_mediaPlayer->hasAudio();
}

bool MediaPlayerWrapper::seekable() const
{
    return m_mediaPlayer->isSeekable();
}

qreal MediaPlayerWrapper::playbackRate() const
{
    return m_mediaPlayer->playbackRate();
}

void MediaPlayerWrapper::setPlaybackRate(qreal rate)
{
    if (m_mediaPlayer->playbackRate() != rate) {
        m_mediaPlayer->setPlaybackRate(rate);
        emit playbackRateChanged();
    }
}

QVariantList MediaPlayerWrapper::audioTracks() const
{
    return m_audioTracks;
}

int MediaPlayerWrapper::activeAudioTrack() const
{
    return m_activeAudioTrack;
}

void MediaPlayerWrapper::setActiveAudioTrack(int index)
{
    if (m_activeAudioTrack != index) {
        m_activeAudioTrack = index;
        m_mediaPlayer->setActiveAudioTrack(index);
        emit activeAudioTrackChanged();
    }
}

QVariantList MediaPlayerWrapper::subtitleTracks() const
{
    return m_subtitleTracks;
}

int MediaPlayerWrapper::activeSubtitleTrack() const
{
    return m_activeSubtitleTrack;
}

void MediaPlayerWrapper::setActiveSubtitleTrack(int index)
{
    if (m_activeSubtitleTrack != index) {
        m_activeSubtitleTrack = index;
        m_mediaPlayer->setActiveSubtitleTrack(index);
        emit activeSubtitleTrackChanged();
        updateSubtitleText();
    }
}

void MediaPlayerWrapper::play()
{
    m_mediaPlayer->play();
}

void MediaPlayerWrapper::pause()
{
    m_mediaPlayer->pause();
}

void MediaPlayerWrapper::stop()
{
    m_mediaPlayer->stop();
}

void MediaPlayerWrapper::seek(qint64 position)
{
    m_mediaPlayer->setPosition(position);
}

void MediaPlayerWrapper::onPlaybackStateChanged(QMediaPlayer::PlaybackState state)
{
    emit playingChanged();
    emit pausedChanged();
    emit stoppedChanged();
}

void MediaPlayerWrapper::onMediaStatusChanged(QMediaPlayer::MediaStatus status)
{
    if (status == QMediaPlayer::LoadedMedia || status == QMediaPlayer::BufferedMedia) {
        updateTracks();
    }
}

void MediaPlayerWrapper::onDurationChanged(qint64 duration)
{
    emit durationChanged();
}

void MediaPlayerWrapper::onPositionChanged(qint64 position)
{
    emit positionChanged();
    updateSubtitleText();
}

void MediaPlayerWrapper::onErrorOccurred(QMediaPlayer::Error error, const QString &errorString)
{
    emit errorOccurred(static_cast<int>(error), errorString);
}

void MediaPlayerWrapper::onMetaDataChanged()
{
    emit metaDataChanged();
}

void MediaPlayerWrapper::onActiveSubtitleTrackChanged()
{
    m_activeSubtitleTrack = m_mediaPlayer->activeSubtitleTrack();
    emit activeSubtitleTrackChanged();
    updateSubtitleText();
}

void MediaPlayerWrapper::setSubtitleText(const QString &text)
{
    if (m_rawSubtitleText != text) {
        m_rawSubtitleText = text;
        m_formattedSubtitleText = m_subtitleFormatter->formatSubtitle(text);
        emit rawSubtitleTextChanged();
        emit formattedSubtitleTextChanged();
    }
}

void MediaPlayerWrapper::updateSubtitleText()
{
    // Note: QMediaPlayer doesn't expose subtitle text directly in Qt 6
    // This is a limitation - we can't intercept the rendered subtitle text
    // However, we can format subtitle text if we get it from external sources
    
    // For embedded subtitles, we can't extract the text directly
    // The subtitle text needs to be set manually via setSubtitleText()
    // when loading external subtitle files
    
    // TODO: Implement subtitle text extraction if possible
    // This might require using QVideoSink to analyze frames or
    // using a subtitle parsing library like libass
}

void MediaPlayerWrapper::updateTracks()
{
    // Update audio tracks
    QVariantList newAudioTracks;
    const auto audioTracks = m_mediaPlayer->audioTracks();
    for (int i = 0; i < audioTracks.size(); ++i) {
        const auto &track = audioTracks.at(i);
        QVariantMap trackMap;
        trackMap["index"] = i;  // Use loop index as track index
        // QMediaMetaData doesn't have direct title/language, use metadata if available
        newAudioTracks.append(trackMap);
    }
    
    if (m_audioTracks != newAudioTracks) {
        m_audioTracks = newAudioTracks;
        emit audioTracksChanged();
    }
    
    // Update subtitle tracks
    QVariantList newSubtitleTracks;
    const auto subtitleTracks = m_mediaPlayer->subtitleTracks();
    for (int i = 0; i < subtitleTracks.size(); ++i) {
        const auto &track = subtitleTracks.at(i);
        QVariantMap trackMap;
        trackMap["index"] = i;  // Use loop index as track index
        // QMediaMetaData doesn't have direct title/language, use metadata if available
        newSubtitleTracks.append(trackMap);
    }
    
    if (m_subtitleTracks != newSubtitleTracks) {
        m_subtitleTracks = newSubtitleTracks;
        emit subtitleTracksChanged();
    }
    
    // Update active tracks
    m_activeAudioTrack = m_mediaPlayer->activeAudioTrack();
    m_activeSubtitleTrack = m_mediaPlayer->activeSubtitleTrack();
}

