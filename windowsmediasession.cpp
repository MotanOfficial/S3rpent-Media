#include "windowsmediasession.h"
#include <QDebug>
#include <QFileInfo>
#include <QImageReader>
#include <QStandardPaths>
#include <QDir>
#include <QTimer>

// Windows-specific includes are in windowsmediasession_windows.cpp

WindowsMediaSession::WindowsMediaSession(QObject *parent)
    : QObject(parent)
    , m_playbackStatus(0) // Stopped
    , m_position(0)
    , m_duration(0)
    , m_syncingState(false)
#ifdef Q_OS_WIN
    , m_windowsSessionInitialized(false)
#ifdef _MSC_VER
    , m_systemControls(nullptr)
#endif
#endif
    , m_sessionPlayer(nullptr)
    , m_audioOutput(nullptr)
{
    initializeSession();
#ifdef Q_OS_WIN
    initializeWindowsMediaSession();
#endif
}

WindowsMediaSession::~WindowsMediaSession()
{
#ifdef Q_OS_WIN
    cleanupWindowsMediaSession();
#endif
    if (m_audioOutput) {
        delete m_audioOutput;
    }
    if (m_sessionPlayer) {
        delete m_sessionPlayer;
    }
}

void WindowsMediaSession::initializeSession()
{
#ifdef Q_OS_WIN
#ifdef _MSC_VER
    // MSVC/WinRT path: NO QMediaPlayer session owner
    // We use WinRT MediaPlayer directly, so don't create competing QMediaPlayer
    qDebug() << "[WindowsMediaSession] MSVC WinRT mode - no QMediaPlayer session owner";
    return;
#endif
#endif

    // MinGW / fallback: QMediaPlayer session owner
    // Create a QMediaPlayer that will handle Windows media session integration
    // QMediaPlayer automatically integrates with Windows Media Session on Windows 10+
    m_sessionPlayer = new QMediaPlayer(this);
    m_audioOutput = new QAudioOutput(this);
    m_audioOutput->setVolume(0.0); // Mute - we only use this for metadata/session
    m_sessionPlayer->setAudioOutput(m_audioOutput);
    
    // Connect to player signals for Windows media controls
    // When Windows sends play/pause commands, they change the session player's state
    // We detect those changes and forward them to the actual player
    connect(m_sessionPlayer, &QMediaPlayer::playbackStateChanged, this, [this]() {
        // Ignore state changes that we're causing ourselves (to prevent feedback loops)
        if (m_syncingState) {
            return;
        }
        
        QMediaPlayer::PlaybackState state = m_sessionPlayer->playbackState();
        
        // Only emit if the state change came from Windows (not from our own updateSessionPlaybackState)
        // We detect this by checking if the state doesn't match our current playbackStatus
        if (state == QMediaPlayer::PlayingState && m_playbackStatus != 1) {
            // Windows requested play - forward to actual player
            emit playRequested();
        } else if (state == QMediaPlayer::PausedState && m_playbackStatus != 2) {
            // Windows requested pause - forward to actual player
            emit pauseRequested();
        } else if (state == QMediaPlayer::StoppedState && m_playbackStatus != 0) {
            // Windows requested stop - forward to actual player
            emit stopRequested();
        }
    });
    
    // Handle position changes from Windows seeking
    connect(m_sessionPlayer, &QMediaPlayer::positionChanged, this, [this](qint64 pos) {
        // Only update if it's a significant change (user seeking)
        if (qAbs(pos - m_position) > 1000) { // More than 1 second difference
            m_position = pos;
            emit positionChanged();
        }
    });
    
    qDebug() << "[WindowsMediaSession] Initialized media session (QMediaPlayer fallback)";
}

void WindowsMediaSession::setSource(const QUrl &source)
{
    // HARD GUARD: If Windows Media Session is disabled, return immediately (no logging, no work)
    if (!m_windowsSessionInitialized) {
        return;
    }
    
    // Early return if source unchanged (avoid all work)
    if (m_source == source) {
        return;
    }
    
    qDebug() << "[WindowsMediaSession] setSource() changed:" << m_source << "->" << source;
    m_source = source;
    
    // Set source on QMediaPlayer - this automatically exposes file metadata to Windows
    // QMediaPlayer reads metadata from the file and Windows Media Session picks it up
    if (m_sessionPlayer && source.isValid()) {
        m_sessionPlayer->setSource(source);
        // Update metadata after source is loaded (QMediaPlayer will read it from file)
        QTimer::singleShot(100, this, &WindowsMediaSession::updateSessionMetadata);
        // Sync playback state after source is set (so Windows sees the current state)
        // Use a longer delay to ensure source is fully loaded and metadata is available
        QTimer::singleShot(500, this, &WindowsMediaSession::updateSessionPlaybackState);
        qDebug() << "[WindowsMediaSession] Source set on QMediaPlayer:" << source;
    }
}

void WindowsMediaSession::setTitle(const QString &title)
{
    if (m_title != title) {
        m_title = title;
        emit titleChanged();
        updateSessionMetadata();
    }
}

void WindowsMediaSession::setArtist(const QString &artist)
{
    if (m_artist != artist) {
        m_artist = artist;
        emit artistChanged();
        updateSessionMetadata();
    }
}

void WindowsMediaSession::setAlbum(const QString &album)
{
    if (m_album != album) {
        m_album = album;
        emit albumChanged();
        updateSessionMetadata();
    }
}

void WindowsMediaSession::setThumbnail(const QUrl &thumbnail)
{
    if (m_thumbnail != thumbnail) {
        m_thumbnail = thumbnail;
        emit thumbnailChanged();
        updateSessionMetadata();
    }
}

void WindowsMediaSession::setPlaybackStatus(int status)
{
    // Early return if status unchanged (avoid all work)
    if (m_playbackStatus == status) {
        return;
    }
    
    qDebug() << "[WindowsMediaSession] setPlaybackStatus() changed:" << m_playbackStatus << "->" << status;
    m_playbackStatus = status;
    emit playbackStatusChanged();
    
    // CRITICAL: Sync to Windows Media Session
    // HARD GUARD: Only sync if Windows Media Session is initialized
    if (m_windowsSessionInitialized) {
        updateSessionPlaybackState();
    }
}

void WindowsMediaSession::setPosition(qint64 position)
{
    // HARD GUARD: Early return if unchanged (avoid all work including logging)
    if (m_position == position) {
        return;
    }
    
    m_position = position;
    emit positionChanged();
}

void WindowsMediaSession::setDuration(qint64 duration)
{
    // HARD GUARD: Early return if unchanged (avoid all work including logging)
    if (m_duration == duration) {
        return;
    }
    
    m_duration = duration;
    emit durationChanged();
}

void WindowsMediaSession::updateMetadata(const QString &title, const QString &artist, 
                                         const QString &album, const QUrl &thumbnailUrl)
{
    // Early return if nothing changed (avoid all work)
    if (m_title == title && m_artist == artist && m_album == album && m_thumbnail == thumbnailUrl) {
        return;
    }
    
    qDebug() << "[WindowsMediaSession] updateMetadata() changed";
    m_title = title;
    m_artist = artist;
    m_album = album;
    m_thumbnail = thumbnailUrl;
    emit titleChanged();
    emit artistChanged();
    emit albumChanged();
    emit thumbnailChanged();
    
    // CRITICAL: Sync to Windows Media Session
    // HARD GUARD: Only sync if Windows Media Session is initialized
    if (m_windowsSessionInitialized) {
        updateSessionMetadata();
    }
}

void WindowsMediaSession::updatePlaybackState(int state)
{
    // This function updates playback state and syncs to Windows Media Session
    if (m_playbackStatus == state) {
        return;
    }
    
    m_playbackStatus = state;
    emit playbackStatusChanged();
    
    // CRITICAL: Sync to Windows Media Session
    // HARD GUARD: Only sync if Windows Media Session is initialized
    if (m_windowsSessionInitialized) {
        updateSessionPlaybackState();
    }
}

void WindowsMediaSession::updateTimeline(qint64 position, qint64 duration)
{
    // Early return if nothing changed (avoid ALL work including logging)
    if (m_position == position && m_duration == duration) {
        return;
    }
    
    // Update internal state for UI signals
    bool posChanged = false;
    bool durChanged = false;
    
    if (m_position != position) {
        m_position = position;
        posChanged = true;
        emit positionChanged();
    }
    if (m_duration != duration) {
        m_duration = duration;
        durChanged = true;
        emit durationChanged();
    }
    
    // CRITICAL: Sync to Windows Media Session (throttled)
    // HARD GUARD: Only sync if Windows Media Session is initialized
    if (m_windowsSessionInitialized) {
#ifdef Q_OS_WIN
        updateWindowsMediaSessionTimeline();
#endif
    }
}

void WindowsMediaSession::updateSessionMetadata()
{
    
    if (m_sessionPlayer) {
        // In Qt 6, QMediaPlayer automatically exposes metadata to Windows Media Session
        // when a source is set. The metadata comes from the media file itself.
        // We can't directly set metadata on QMediaPlayer, but Windows will read it
        // from the file when the source is set.
        
        qDebug() << "[WindowsMediaSession] Metadata will be read from source file. Custom:" << m_title << "-" << m_artist;
    }
    
#ifdef Q_OS_WIN
    // Update Windows Media Session with custom metadata
    updateWindowsMediaSessionMetadata();
#endif
}

void WindowsMediaSession::updateSessionPlaybackState()
{
    
    if (m_sessionPlayer && !m_source.isEmpty()) {
        // Sync the session player's state to match our playback status
        // This allows Windows to see the current state and control it
        // IMPORTANT: The session player must actually be playing (even if muted)
        // for Windows to recognize it as an active media session
        QMediaPlayer::PlaybackState currentState = m_sessionPlayer->playbackState();
        
        // Set flag to prevent feedback loop
        m_syncingState = true;
        
        if (m_playbackStatus == 1 && currentState != QMediaPlayer::PlayingState) {
            // Set to playing state (but audio is muted, so no sound)
            // Windows needs the player to actually be playing to recognize it
            m_sessionPlayer->play();
        } else if (m_playbackStatus == 2 && currentState != QMediaPlayer::PausedState) {
            m_sessionPlayer->pause();
        } else if (m_playbackStatus == 0 && currentState != QMediaPlayer::StoppedState) {
            m_sessionPlayer->stop();
        }
        
        // Reset flag after a short delay to allow state change to propagate
        QTimer::singleShot(50, this, [this]() {
            m_syncingState = false;
        });
    }
    
#ifdef Q_OS_WIN
    // Update Windows SystemMediaTransportControls playback state
    updateWindowsMediaSessionPlaybackState();
#endif
}

void WindowsMediaSession::updateSessionTimeline()
{
    // Timeline updates disabled - Windows handles this automatically via MediaPlayer
    // No manual updates needed, reducing overhead and preventing lag
    qDebug() << "[WindowsMediaSession] updateSessionTimeline() called: position=" << m_position << "ms, duration=" << m_duration << "ms, sessionPlayer=" << (m_sessionPlayer ? "exists" : "NULL") << "- DISABLED (early return)";
    return;
}

QImage WindowsMediaSession::loadThumbnailImage(const QUrl &url)
{
    if (url.isEmpty()) {
        return QImage();
    }
    
    QString localPath;
    if (url.isLocalFile()) {
        localPath = url.toLocalFile();
    } else if (url.scheme() == "qrc") {
        localPath = ":" + url.path();
    } else {
        return QImage();
    }
    
    QImageReader reader(localPath);
    QImage image = reader.read();
    
    // Resize if too large (Windows recommends 200x200 or smaller)
    if (!image.isNull() && (image.width() > 200 || image.height() > 200)) {
        image = image.scaled(200, 200, Qt::KeepAspectRatio, Qt::SmoothTransformation);
    }
    
    return image;
}

void WindowsMediaSession::onPlayRequested()
{
    qDebug() << "[WindowsMediaSession] Play requested from Windows";
    emit playRequested();
}

void WindowsMediaSession::onPauseRequested()
{
    qDebug() << "[WindowsMediaSession] Pause requested from Windows";
    emit pauseRequested();
}

void WindowsMediaSession::onStopRequested()
{
    qDebug() << "[WindowsMediaSession] Stop requested from Windows";
    emit stopRequested();
}

void WindowsMediaSession::onNextRequested()
{
    qDebug() << "[WindowsMediaSession] Next requested from Windows";
    emit nextRequested();
}

void WindowsMediaSession::onPreviousRequested()
{
    qDebug() << "[WindowsMediaSession] Previous requested from Windows";
    emit previousRequested();
}

