#ifndef WEBRTCLISTENTOGETHERMANAGER_H
#define WEBRTCLISTENTOGETHERMANAGER_H

#include <QObject>
#include <QTimer>
#include <QNetworkAccessManager>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QUuid>
#include <QSet>
#include <QTcpServer>
#include <QDir>
#include <rtc/rtc.hpp>

class QTcpSocket;
class QFile;
class QProcess;

class WebRTCListenTogetherManager : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool isHost READ isHost NOTIFY isHostChanged)
    Q_PROPERTY(bool isConnected READ isConnected NOTIFY connectionStateChanged)
    Q_PROPERTY(QString sessionId READ sessionId NOTIFY sessionIdChanged)
    Q_PROPERTY(int peerCount READ peerCount NOTIFY peerCountChanged)
    Q_PROPERTY(int playbackPosition READ playbackPosition WRITE setPlaybackPosition NOTIFY playbackPositionChanged)
    Q_PROPERTY(bool isPlaying READ isPlaying WRITE setIsPlaying NOTIFY isPlayingChanged)
    Q_PROPERTY(QString currentSource READ currentSource WRITE setCurrentSource NOTIFY currentSourceChanged)
    Q_PROPERTY(QString signalingServerUrl READ signalingServerUrl WRITE setSignalingServerUrl NOTIFY signalingServerUrlChanged)
    Q_PROPERTY(QString currentTitle READ currentTitle WRITE setCurrentTitle NOTIFY currentTitleChanged)
    Q_PROPERTY(QString currentArtist READ currentArtist WRITE setCurrentArtist NOTIFY currentArtistChanged)
    Q_PROPERTY(QString currentAlbum READ currentAlbum WRITE setCurrentAlbum NOTIFY currentAlbumChanged)
    Q_PROPERTY(QString currentCoverUrl READ currentCoverUrl WRITE setCurrentCoverUrl NOTIFY currentCoverUrlChanged)
    Q_PROPERTY(int streamDuration READ streamDuration WRITE setStreamDuration NOTIFY streamDurationChanged)
    Q_PROPERTY(qint64 streamBytesReceived READ streamBytesReceived NOTIFY streamReceiveProgressChanged)
    Q_PROPERTY(qint64 streamTotalBytes READ streamTotalBytes NOTIFY streamReceiveProgressChanged)
    Q_PROPERTY(qreal streamReceiveProgress READ streamReceiveProgress NOTIFY streamReceiveProgressChanged)
    Q_PROPERTY(int syncEpoch READ syncEpoch NOTIFY syncEpochChanged)
    Q_PROPERTY(bool compressStreamsForPeer READ compressStreamsForPeer WRITE setCompressStreamsForPeer NOTIFY compressStreamsForPeerChanged)
    Q_PROPERTY(bool streamPreparing READ streamPreparing NOTIFY streamPreparingChanged)
    Q_PROPERTY(bool hostWantedPlayback READ hostWantedPlayback NOTIFY hostWantedPlaybackChanged)

public:
    explicit WebRTCListenTogetherManager(QObject *parent = nullptr);
    ~WebRTCListenTogetherManager();

    bool isHost() const { return m_isHost; }
    bool isConnected() const { return m_isConnected; }
    QString sessionId() const { return m_sessionId; }
    int peerCount() const { return m_isConnected ? 1 : 0; }
    
    int playbackPosition() const { return m_playbackPosition; }
    void setPlaybackPosition(int pos) {
        if (m_playbackPosition != pos) {
            m_playbackPosition = pos;
            emit playbackPositionChanged();
        }
    }
    
    bool isPlaying() const { return m_isPlaying; }
    void setIsPlaying(bool playing) {
        if (m_isPlaying != playing) {
            m_isPlaying = playing;
            emit isPlayingChanged();
        }
    }
    
    QString currentTitle() const { return m_currentTitle; }
    void setCurrentTitle(const QString &t) {
        if (m_currentTitle != t) { m_currentTitle = t; emit currentTitleChanged(); }
    }
    QString currentArtist() const { return m_currentArtist; }
    void setCurrentArtist(const QString &a) {
        if (m_currentArtist != a) { m_currentArtist = a; emit currentArtistChanged(); }
    }
    QString currentAlbum() const { return m_currentAlbum; }
    void setCurrentAlbum(const QString &a) {
        if (m_currentAlbum != a) { m_currentAlbum = a; emit currentAlbumChanged(); }
    }
    QString currentCoverUrl() const { return m_currentCoverUrl; }
    void setCurrentCoverUrl(const QString &u) {
        if (m_currentCoverUrl != u) { m_currentCoverUrl = u; emit currentCoverUrlChanged(); }
    }
    int streamDuration() const { return m_streamDuration; }
    void setStreamDuration(int d) {
        if (m_streamDuration != d) { m_streamDuration = d; emit streamDurationChanged(); }
    }

    qint64 streamBytesReceived() const { return m_receivedBytes; }
    qint64 streamTotalBytes() const { return m_streamTotalSize; }
    qreal streamReceiveProgress() const {
        if (m_streamTotalSize <= 0) return 0.0;
        return qreal(m_receivedBytes) / qreal(m_streamTotalSize);
    }

    int syncEpoch() const { return m_syncEpoch; }

    bool compressStreamsForPeer() const { return m_compressStreamsForPeer; }
    void setCompressStreamsForPeer(bool enabled) {
        if (m_compressStreamsForPeer != enabled) {
            m_compressStreamsForPeer = enabled;
            emit compressStreamsForPeerChanged();
        }
    }

    bool streamPreparing() const { return m_streamPreparing; }
    bool hostWantedPlayback() const { return m_hostWantedPlayback; }
    
    QString currentSource() const { return m_currentSource; }
    void setCurrentSource(const QString &src) {
        if (m_currentSource != src) {
            m_currentSource = src;
            emit currentSourceChanged();
        }
    }
    
    QString signalingServerUrl() const { return m_signalingServerUrl; }
    void setSignalingServerUrl(const QString &url) {
        if (m_signalingServerUrl != url) {
            m_signalingServerUrl = url;
            emit signalingServerUrlChanged();
        }
    }

public slots:
    Q_INVOKABLE void createSession();
    Q_INVOKABLE void joinSession(const QString &code);
    Q_INVOKABLE void leaveSession();
    
    // Sync actions
    Q_INVOKABLE void broadcastPlay();
    Q_INVOKABLE void broadcastPause();
    Q_INVOKABLE void broadcastSeek(int position);
    Q_INVOKABLE void broadcastTrackChange(const QString &source, bool wantsPlayback = true);
    Q_INVOKABLE void requestFullState();
    Q_INVOKABLE void publishFullStateToPeer();
    Q_INVOKABLE void startStreaming(const QString &filePath);
    Q_INVOKABLE void notifyClientSyncReady();
    Q_INVOKABLE void beginSyncedPlayback(int position = 0, bool affectHost = true, bool play = true);
    Q_INVOKABLE void broadcastMetadata();
    Q_INVOKABLE void broadcastSyncPosition(int position);

signals:
    void isHostChanged();
    void connectionStateChanged();
    void sessionIdChanged();
    void peerCountChanged();
    void playbackPositionChanged();
    void isPlayingChanged();
    void currentSourceChanged();
    void signalingServerUrlChanged();
    
    // Metadata sync
    void currentTitleChanged();
    void currentArtistChanged();
    void currentAlbumChanged();
    void currentCoverUrlChanged();
    void streamDurationChanged();
    void streamReceiveProgressChanged();
    void syncEpochChanged();
    void compressStreamsForPeerChanged();
    void streamPreparingChanged();
    void hostWantedPlaybackChanged();

    // Remote actions
    void remotePlayRequested();
    void remotePauseRequested();
    void remoteSeekRequested(int position);
    void remoteTrackChanged(const QString &source, bool isPlaying);
    void fullStateRequested(const QString &peerId);
    void fullStateReceived(const QJsonObject &state);
    void audioStreamReady(QString filePath, QString mimeType);
    void audioStreamComplete();
    void hostPauseForSync(bool wantedPlay);
    void clientSyncReady();
    void hostStateSyncRequested();
    void clientCatchUpStarted();
    void syncStartRequested(int position, bool play);
    void metadataUpdated();
    void remoteSyncPositionRequested(int position);

private slots:
    void onSignalingMessage(const QJsonObject &msg);
    void checkConnectionTimeout();
    void pollMessages();

private:
    void setupPeerConnection();
    void setupDataChannel();
    void startHostPeerConnection();
    void tearDownPeerConnection();
    void resetHostForClientRejoin();
    void clearSignalingMessages();
    void sendSignalingMessage(const QJsonObject &msg);
    void handleSignalingResponse(const QJsonObject &response);
    void handleDataChannelMessage(const std::string &message);
    void sendToAllPeers(const QJsonObject &msg);
    void sendFullStateToPeer();
    void sendNextAudioChunk();
    void handleAudioChunk(const QByteArray &chunk);
    void startReceivingStream(const QJsonObject &startMsg);
    void stopStreaming();
    void cancelStreamEncode();
    void startStreamEncode(const QString &filePath);
    bool shouldCompressStream(const QString &filePath) const;
    QString resolveFfmpegPath() const;
    void beginStreamingPreparedFile(const QString &filePath, const QString &displayFileName = QString());
    void setStreamPreparing(bool preparing);
    
    // HTTP server for file sharing
    void startHttpServer();
    void stopHttpServer();
    void handleNewHttpConnection();
    void sendNextChunk(QTcpSocket *socket, QFile *file, qint64 rangeStart, qint64 rangeEnd);
    QString getLocalIpAddress() const;
    QString getSyncUrl() const;

    // WebRTC components
    std::shared_ptr<rtc::PeerConnection> m_peerConnection;
    std::shared_ptr<rtc::DataChannel> m_dataChannel;
    
    // Session management
    QString m_sessionId;
    bool m_isHost = false;
    bool m_isConnected = false;
    int m_playbackPosition = 0;
    bool m_isPlaying = false;
    QString m_currentSource;
    QMap<QString, std::shared_ptr<rtc::PeerConnection>> m_peers;
    QSet<int> m_processedMessages;
    
    // Signaling state tracking
    bool m_localDescriptionSent = false;
    bool m_hasRemoteDescription = false;
    QList<QPair<QString, QString>> m_pendingCandidates;
    int m_peerConnectionGeneration = 0;
    bool m_hostRejoinPending = false;
    
    // Network
    QNetworkAccessManager *m_networkManager;
    QString m_signalingServerUrl = "https://your-vercel-app.vercel.app"; // Your Vercel function
    QTimer *m_heartbeatTimer;
    QTimer *m_connectionTimeoutTimer;
    QTimer *m_pollTimer;
    
    // HTTP Server
    QTcpServer *m_httpServer = nullptr;
    quint16 m_httpPort = 0;

    // Metadata (synced to peers)
    QString m_currentTitle;
    QString m_currentArtist;
    QString m_currentAlbum;
    QString m_currentCoverUrl;
    int m_streamDuration = 0;
    int m_syncEpoch = 0;
    bool m_hostWantedPlayback = true;
    bool m_compressStreamsForPeer = true;
    bool m_streamPreparing = false;

    // Audio streaming (host)
    QFile *m_streamFile = nullptr;
    QTimer *m_streamTimer = nullptr;
    QProcess *m_streamEncodeProcess = nullptr;
    QString m_streamEncodeTempPath;
    QString m_pendingStreamSourcePath;
    int m_streamChunkIndex = 0;
    int m_streamSkipCount = 0;
    static constexpr int STREAM_CHUNK_SIZE = 65536;
    static constexpr int STREAM_TIMER_MS = 10;

    // Audio streaming (client)
    QFile *m_receiveFile = nullptr;
    QString m_receiveFilePath;
    qint64 m_receivedBytes = 0;
    qint64 m_streamTotalSize = 0;
    QString m_streamMimeType;
    bool m_streamReadyNotified = false;
    bool m_streamCompleteNotified = false;
};

#endif // WEBRTCLISTENTOGETHERMANAGER_H
