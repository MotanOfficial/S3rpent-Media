#ifndef WINDOWSMEDIASESSION_H
#define WINDOWSMEDIASESSION_H

#include <QObject>
#include <QString>
#include <QUrl>
#include <QImage>
#include <QMediaPlayer>
#include <QMediaMetaData>
#include <QAudioOutput>

#ifdef Q_OS_WIN
// WinRT types are fully defined in .cpp file only
// Header is WinRT-agnostic to avoid MOC issues
#endif

class WindowsMediaSession : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString title READ title WRITE setTitle NOTIFY titleChanged)
    Q_PROPERTY(QString artist READ artist WRITE setArtist NOTIFY artistChanged)
    Q_PROPERTY(QString album READ album WRITE setAlbum NOTIFY albumChanged)
    Q_PROPERTY(QUrl thumbnail READ thumbnail WRITE setThumbnail NOTIFY thumbnailChanged)
    Q_PROPERTY(int playbackStatus READ playbackStatus WRITE setPlaybackStatus NOTIFY playbackStatusChanged)
    Q_PROPERTY(qint64 position READ position WRITE setPosition NOTIFY positionChanged)
    Q_PROPERTY(qint64 duration READ duration WRITE setDuration NOTIFY durationChanged)

public:
    explicit WindowsMediaSession(QObject *parent = nullptr);
    ~WindowsMediaSession();

    QString title() const { return m_title; }
    void setTitle(const QString &title);
    
    QString artist() const { return m_artist; }
    void setArtist(const QString &artist);
    
    QString album() const { return m_album; }
    void setAlbum(const QString &album);
    
    QUrl thumbnail() const { return m_thumbnail; }
    void setThumbnail(const QUrl &thumbnail);
    
    int playbackStatus() const { return m_playbackStatus; }
    void setPlaybackStatus(int status);
    
    qint64 position() const { return m_position; }
    void setPosition(qint64 position);
    
    qint64 duration() const { return m_duration; }
    void setDuration(qint64 duration);

    // Set the source file (required for Windows media session)
    Q_INVOKABLE void setSource(const QUrl &source);
    
    // Initialize with window handle (for WinRT - call after window is created)
    Q_INVOKABLE void initializeWithWindow(QObject* window);
    
    // Update all metadata at once
    Q_INVOKABLE void updateMetadata(const QString &title, const QString &artist, 
                                    const QString &album, const QUrl &thumbnailUrl);
    
    // Update playback state
    Q_INVOKABLE void updatePlaybackState(int state); // 0=Stopped, 1=Playing, 2=Paused
    
    // Update timeline
    Q_INVOKABLE void updateTimeline(qint64 position, qint64 duration);

signals:
    void titleChanged();
    void artistChanged();
    void albumChanged();
    void thumbnailChanged();
    void playbackStatusChanged();
    void positionChanged();
    void durationChanged();
    
    // Signals for Windows media controls
    void playRequested();
    void pauseRequested();
    void stopRequested();
    void nextRequested();
    void previousRequested();

private slots:
    void onPlayRequested();
    void onPauseRequested();
    void onStopRequested();
    void onNextRequested();
    void onPreviousRequested();

private:
    void initializeSession();
    void updateSessionMetadata();
    void updateSessionPlaybackState();
    void updateSessionTimeline();
    QImage loadThumbnailImage(const QUrl &url);
    
#ifdef Q_OS_WIN
    void initializeWindowsMediaSession();
    void cleanupWindowsMediaSession();
    void updateWindowsMediaSessionMetadata();
    void updateWindowsMediaSessionPlaybackState();
    void updateWindowsMediaSessionTimeline();
    
#ifdef _MSC_VER
    // WinRT data (C++/WinRT types stored as void* to avoid header pollution)
    void* m_systemControls = nullptr;
#endif
    bool m_windowsSessionInitialized = false;
#endif

    QString m_title;
    QString m_artist;
    QString m_album;
    QUrl m_thumbnail;
    int m_playbackStatus; // 0=Stopped, 1=Playing, 2=Paused
    qint64 m_position;
    qint64 m_duration;
    QUrl m_source; // Track current source to avoid duplicate setSource calls
    bool m_syncingState; // Flag to prevent feedback loops when syncing state
    
    // Optimization: Track last applied values to avoid redundant updates
    QString m_lastAppliedTitle;
    QString m_lastAppliedArtist;
    QString m_lastAppliedAlbum;
    QString m_lastAppliedThumbnailPath;
    uint64_t m_sessionId = 0; // Session ID to guard async callbacks
    
    QMediaPlayer *m_sessionPlayer;
    QAudioOutput *m_audioOutput;
};

#endif // WINDOWSMEDIASESSION_H

