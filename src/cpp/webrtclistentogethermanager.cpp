#include "webrtclistentogethermanager.h"
#include <QNetworkRequest>
#include <QNetworkReply>
#include <QJsonArray>
#include <QTimer>
#include <QDebug>
#include <QTcpSocket>
#include <QFile>
#include <QFileInfo>
#include <QDir>
#include <QNetworkInterface>
#include <QUrl>
#include <QCoreApplication>
#include <QProcess>
#include <cstring>
#include <algorithm>
#include <rtc/rtc.hpp>

namespace {

QString streamExtensionFromMime(const QString &mimeType)
{
    const QString m = mimeType.toLower();
    if (m.contains(QStringLiteral("flac")))
        return QStringLiteral("flac");
    if (m.contains(QStringLiteral("ogg")))
        return QStringLiteral("ogg");
    if (m.contains(QStringLiteral("wav")))
        return QStringLiteral("wav");
    if (m.contains(QStringLiteral("opus")))
        return QStringLiteral("opus");
    if (m.contains(QStringLiteral("mp4")) || m.contains(QStringLiteral("m4a")))
        return QStringLiteral("m4a");
    if (m.contains(QStringLiteral("webm")))
        return QStringLiteral("webm");
    return QStringLiteral("mp3");
}

QString coverUrlForPeerTransfer(const QString &coverUrl)
{
    if (coverUrl.isEmpty())
        return coverUrl;
    if (coverUrl.startsWith(QStringLiteral("data:"), Qt::CaseInsensitive))
        return coverUrl;
    if (coverUrl.startsWith(QStringLiteral("http://"), Qt::CaseInsensitive)
        || coverUrl.startsWith(QStringLiteral("https://"), Qt::CaseInsensitive)) {
        return coverUrl;
    }

    QString localPath;
    const QUrl url(coverUrl);
    if (url.isLocalFile())
        localPath = url.toLocalFile();
    else if (QFileInfo::exists(coverUrl))
        localPath = coverUrl;

    if (localPath.isEmpty() || !QFileInfo::exists(localPath))
        return QString();

    QFile file(localPath);
    if (!file.open(QIODevice::ReadOnly))
        return QString();

    const QByteArray bytes = file.readAll();
    if (bytes.isEmpty())
        return QString();

    QString mime = QStringLiteral("image/jpeg");
    const QString lower = localPath.toLower();
    if (lower.endsWith(QStringLiteral(".png")))
        mime = QStringLiteral("image/png");
    else if (lower.endsWith(QStringLiteral(".webp")))
        mime = QStringLiteral("image/webp");
    else if (lower.endsWith(QStringLiteral(".gif")))
        mime = QStringLiteral("image/gif");

    return QStringLiteral("data:%1;base64,%2").arg(mime, QString::fromLatin1(bytes.toBase64()));
}

QString coverUrlForLog(const QString &coverUrl)
{
    if (coverUrl.isEmpty())
        return coverUrl;
    if (coverUrl.startsWith(QStringLiteral("data:"), Qt::CaseInsensitive))
        return QStringLiteral("<data-url %1 bytes>").arg(coverUrl.size());
    if (coverUrl.size() > 96)
        return coverUrl.left(64) + QStringLiteral("…");
    return coverUrl;
}

} // namespace

WebRTCListenTogetherManager::WebRTCListenTogetherManager(QObject *parent)
    : QObject(parent)
    , m_signalingServerUrl("http://localhost:3847/api/signal") // Local testing (avoid Windows reserved port 3000)
    , m_networkManager(new QNetworkAccessManager(this))
    , m_heartbeatTimer(new QTimer(this))
    , m_connectionTimeoutTimer(new QTimer(this))
    , m_pollTimer(new QTimer(this))
{
    // Initialize WebRTC logging
    rtc::InitLogger(rtc::LogLevel::Info);
    
    // Setup timers
    m_heartbeatTimer->setInterval(30000); // 30 seconds
    connect(m_heartbeatTimer, &QTimer::timeout, this, [this]() {
        sendToAllPeers(QJsonObject{{"type", "heartbeat"}});
    });
    
    m_connectionTimeoutTimer->setInterval(15000); // 15 seconds timeout
    connect(m_connectionTimeoutTimer, &QTimer::timeout, this, &WebRTCListenTogetherManager::checkConnectionTimeout);

    m_pollTimer->setInterval(1000); // Poll every 1 second
    connect(m_pollTimer, &QTimer::timeout, this, &WebRTCListenTogetherManager::pollMessages);
}

WebRTCListenTogetherManager::~WebRTCListenTogetherManager() {
    leaveSession();
}

void WebRTCListenTogetherManager::createSession() {
    m_sessionId = QUuid::createUuid().toString(QUuid::WithoutBraces).left(8);
    m_isHost = true;

    startHttpServer();

    emit sessionIdChanged();
    emit isHostChanged();

    // Register session on signaling server BEFORE creating the offer (avoids 404 race).
    QJsonObject msg{
        {"type", "create_session"},
        {"sessionId", m_sessionId},
    };
    sendSignalingMessage(msg);

    m_pollTimer->start();

    qDebug() << "[WebRTC][" << (m_isHost ? "HOST" : "CLIENT") << "] Creating session:" << m_sessionId;
}

void WebRTCListenTogetherManager::startHostPeerConnection() {
    if (!m_isHost || m_peerConnection)
        return;

    setupPeerConnection();

    qDebug() << "[WebRTC][ HOST ] Creating data channel (triggers offer)...";
    m_dataChannel = m_peerConnection->createDataChannel("listen-together");
    setupDataChannel();
}

void WebRTCListenTogetherManager::joinSession(const QString &code) {
    if (m_peerConnection)
        tearDownPeerConnection();

    m_sessionId = code.toLower();
    m_isHost = false;
    
    setupPeerConnection();
    
    // Join session on signaling server
    QJsonObject msg{
        {"type", "join_session"},
        {"sessionId", m_sessionId}
    };
    sendSignalingMessage(msg);
    
    m_pollTimer->start();
    
    emit sessionIdChanged();
    emit isHostChanged();
    
    // Start connection timeout
    m_connectionTimeoutTimer->start();
    
    qDebug() << "[WebRTC][" << (m_isHost ? "HOST" : "CLIENT") << "] Joining session:" << m_sessionId;
}

void WebRTCListenTogetherManager::leaveSession() {
    // Unregister from signaling server while we still have the ID
    if (!m_sessionId.isEmpty()) {
        QJsonObject msg{
            {"type", "leave_session"},
            {"sessionId", m_sessionId},
            {"isHost", m_isHost},
        };
        sendSignalingMessage(msg);
    }

    m_isConnected = false;
    m_heartbeatTimer->stop();
    m_connectionTimeoutTimer->stop();
    m_pollTimer->stop();
    m_processedMessages.clear();
    m_localDescriptionSent = false;
    m_hasRemoteDescription = false;
    m_pendingCandidates.clear();
    
    stopStreaming();
    if (m_receiveFile) {
        m_receiveFile->close();
        delete m_receiveFile;
        m_receiveFile = nullptr;
    }
    if (!m_receiveFilePath.isEmpty()) {
        QFile::remove(m_receiveFilePath);
        m_receiveFilePath.clear();
    }
    m_streamTotalSize = 0;
    m_receivedBytes = 0;
    m_streamReadyNotified = false;
    
    stopHttpServer();
    
    m_sessionId.clear();
    m_playbackPosition = 0;
    m_isPlaying = false;
    m_currentSource.clear();
    m_syncEpoch = 0;
    m_hostWantedPlayback = true;
    m_hostRejoinPending = false;
    
    // Close all peer connections
    for (auto &peer : m_peers) {
        if (peer) {
            peer->close();
        }
    }
    m_peers.clear();
    
    if (m_dataChannel) {
        m_dataChannel->close();
        m_dataChannel.reset();
    }
    
    if (m_peerConnection) {
        ++m_peerConnectionGeneration;
        m_peerConnection->close();
        m_peerConnection.reset();
    }
    
    emit connectionStateChanged();
    emit sessionIdChanged();
    emit peerCountChanged();
    
    qDebug() << "[WebRTC][" << (m_isHost ? "HOST" : "CLIENT") << "] Left session";
}

void WebRTCListenTogetherManager::tearDownPeerConnection()
{
    ++m_peerConnectionGeneration;

    stopStreaming();
    if (m_receiveFile) {
        m_receiveFile->close();
        delete m_receiveFile;
        m_receiveFile = nullptr;
    }
    if (!m_receiveFilePath.isEmpty()) {
        QFile::remove(m_receiveFilePath);
        m_receiveFilePath.clear();
    }
    m_streamTotalSize = 0;
    m_receivedBytes = 0;
    m_streamReadyNotified = false;
    m_streamCompleteNotified = false;

    if (m_dataChannel) {
        m_dataChannel->close();
        m_dataChannel.reset();
    }

    if (m_peerConnection) {
        m_peerConnection->close();
        m_peerConnection.reset();
    }

    m_isConnected = false;
    m_localDescriptionSent = false;
    m_hasRemoteDescription = false;
    m_pendingCandidates.clear();
    m_processedMessages.clear();
    m_heartbeatTimer->stop();

    emit connectionStateChanged();
    emit peerCountChanged();
}

void WebRTCListenTogetherManager::clearSignalingMessages()
{
    if (m_sessionId.isEmpty())
        return;

    sendSignalingMessage(QJsonObject{
        {QStringLiteral("type"), QStringLiteral("clear_signaling")},
        {QStringLiteral("sessionId"), m_sessionId},
    });
}

void WebRTCListenTogetherManager::resetHostForClientRejoin()
{
    if (!m_isHost || m_sessionId.isEmpty() || m_hostRejoinPending)
        return;

    m_hostRejoinPending = true;
    qDebug() << "[WebRTC][ HOST ] Preparing room for client rejoin";

    tearDownPeerConnection();

    if (m_sessionId.isEmpty()) {
        m_hostRejoinPending = false;
        return;
    }

    QJsonObject msg{
        {QStringLiteral("type"), QStringLiteral("clear_signaling")},
        {QStringLiteral("sessionId"), m_sessionId},
    };
    QJsonDocument doc(msg);
    QNetworkRequest request(m_signalingServerUrl);
    request.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");
    QNetworkReply *reply = m_networkManager->post(request, doc.toJson());
    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        reply->deleteLater();
        m_hostRejoinPending = false;
        if (m_isHost && !m_sessionId.isEmpty() && !m_peerConnection)
            startHostPeerConnection();
    });
}

void WebRTCListenTogetherManager::setupPeerConnection() {
    // Reset signaling state for this peer connection
    m_localDescriptionSent = false;
    m_hasRemoteDescription = false;
    m_pendingCandidates.clear();

    const int generation = m_peerConnectionGeneration;
    
    // Create peer connection configuration
    rtc::Configuration config;
    config.iceServers.emplace_back("stun:stun.l.google.com:19302");
    
    m_peerConnection = std::make_shared<rtc::PeerConnection>(config);
    
    // Setup peer connection callbacks
    m_peerConnection->onLocalDescription([this, generation](rtc::Description description) {
        if (generation != m_peerConnectionGeneration)
            return;
        // libdatachannel may fire this multiple times as ICE gathering updates the SDP.
        // We only need to send the initial offer/answer; candidates are sent separately.
        if (m_localDescriptionSent) return;
        m_localDescriptionSent = true;
        
        QString sdp = QString::fromStdString(description);
        QMetaObject::invokeMethod(this, [this, sdp, generation]() {
            if (generation != m_peerConnectionGeneration)
                return;
            QJsonObject msg{
                {"type", "description"},
                {"sessionId", m_sessionId},
                {"sdp", sdp},
                {"isHost", m_isHost}
            };
            sendSignalingMessage(msg);
        }, Qt::QueuedConnection);
    });
    
    m_peerConnection->onLocalCandidate([this, generation](rtc::Candidate candidate) {
        if (generation != m_peerConnectionGeneration)
            return;
        QString cand = QString::fromStdString(candidate);
        QString mid = QString::fromStdString(candidate.mid());
        QMetaObject::invokeMethod(this, [this, cand, mid, generation]() {
            if (generation != m_peerConnectionGeneration)
                return;
            QJsonObject msg{
                {"type", "candidate"},
                {"sessionId", m_sessionId},
                {"candidate", cand},
                {"mid", mid},
                {"isHost", m_isHost}
            };
            sendSignalingMessage(msg);
        }, Qt::QueuedConnection);
    });
    
    m_peerConnection->onDataChannel([this, generation](std::shared_ptr<rtc::DataChannel> dc) {
        QMetaObject::invokeMethod(this, [this, dc, generation]() {
            if (generation != m_peerConnectionGeneration)
                return;
            m_dataChannel = dc;
            setupDataChannel();
            
            // Client requests full state (includes catch-up stream when host has a local track).
            if (!m_isHost) {
                qDebug() << "[WebRTC][" << (m_isHost ? "HOST" : "CLIENT") << "] Data channel ready, requesting full state...";
                requestFullState();
            }
        }, Qt::QueuedConnection);
    });
    
    m_peerConnection->onStateChange([this, generation](rtc::PeerConnection::State state) {
        QMetaObject::invokeMethod(this, [this, state, generation]() {
            if (generation != m_peerConnectionGeneration)
                return;
            if (state == rtc::PeerConnection::State::Connected) {
                m_isConnected = true;
                m_connectionTimeoutTimer->stop();
                m_heartbeatTimer->start();
                
                emit connectionStateChanged();
                qDebug() << "[WebRTC][" << (m_isHost ? "HOST" : "CLIENT") << "] Connected to peer";
            } else if (state == rtc::PeerConnection::State::Disconnected || 
                       state == rtc::PeerConnection::State::Failed || 
                       state == rtc::PeerConnection::State::Closed) {
                m_isConnected = false;
                m_heartbeatTimer->stop();
                
                emit connectionStateChanged();
                qDebug() << "[WebRTC][" << (m_isHost ? "HOST" : "CLIENT") << "] Connection lost (state:" << (int)state << ")";

                if (m_isHost && !m_sessionId.isEmpty()
                    && state == rtc::PeerConnection::State::Closed) {
                    resetHostForClientRejoin();
                }
            }
        }, Qt::QueuedConnection);
    });
}

void WebRTCListenTogetherManager::setupDataChannel() {
    if (!m_dataChannel) return;
    
    m_dataChannel->onMessage([this](rtc::message_variant message) {
        if (std::holds_alternative<rtc::binary>(message)) {
            auto &binary = std::get<rtc::binary>(message);
            QByteArray chunk(reinterpret_cast<const char*>(binary.data()), static_cast<int>(binary.size()));
            QMetaObject::invokeMethod(this, [this, chunk]() {
                handleAudioChunk(chunk);
            }, Qt::QueuedConnection);
        } else if (std::holds_alternative<std::string>(message)) {
            std::string msg_str = std::get<std::string>(message);
            QMetaObject::invokeMethod(this, [this, msg_str]() {
                handleDataChannelMessage(msg_str);
            }, Qt::QueuedConnection);
        }
    });
    
    m_dataChannel->onOpen([this]() {
        QMetaObject::invokeMethod(this, [this]() {
            qDebug() << "[WebRTC][" << (m_isHost ? "HOST" : "CLIENT") << "] Data channel opened";
        }, Qt::QueuedConnection);
    });
    
    m_dataChannel->onClosed([this]() {
        QMetaObject::invokeMethod(this, [this]() {
            qDebug() << "[WebRTC][" << (m_isHost ? "HOST" : "CLIENT") << "] Data channel closed";
        }, Qt::QueuedConnection);
    });
}

void WebRTCListenTogetherManager::handleDataChannelMessage(const std::string &message) {
    QByteArray data = QByteArray::fromStdString(message);
    QJsonDocument doc = QJsonDocument::fromJson(data);
    if (!doc.isObject()) return;
    
    QJsonObject msg = doc.object();
    QString type = msg["type"].toString();
    
    if (type == "play") {
        emit remotePlayRequested();
    } else if (type == "pause") {
        emit remotePauseRequested();
    } else if (type == "seek") {
        emit remoteSeekRequested(msg["position"].toInt());
    } else if (type == "track_change") {
        if (msg.contains(QStringLiteral("title")))
            setCurrentTitle(msg[QStringLiteral("title")].toString());
        if (msg.contains(QStringLiteral("artist")))
            setCurrentArtist(msg[QStringLiteral("artist")].toString());
        if (msg.contains(QStringLiteral("album")))
            setCurrentAlbum(msg[QStringLiteral("album")].toString());
        if (msg.contains(QStringLiteral("coverUrl")))
            setCurrentCoverUrl(msg[QStringLiteral("coverUrl")].toString());
        if (msg.contains(QStringLiteral("streamDuration")))
            setStreamDuration(msg[QStringLiteral("streamDuration")].toInt());
        if (msg.contains(QStringLiteral("syncEpoch"))) {
            const int epoch = msg[QStringLiteral("syncEpoch")].toInt();
            if (m_syncEpoch != epoch) {
                m_syncEpoch = epoch;
                emit syncEpochChanged();
            }
        }
        bool isLocalFile = msg["isLocalFile"].toBool();
        bool isPlaying = msg["isPlaying"].toBool();
        if (!m_isHost && isLocalFile) {
            qDebug() << "[WebRTC][" << (m_isHost ? "HOST" : "CLIENT") << "] Remote track changed (local file), waiting for stream...";
            if (m_receiveFile) {
                m_receiveFile->close();
                delete m_receiveFile;
                m_receiveFile = nullptr;
            }
            m_streamReadyNotified = false;
            m_streamCompleteNotified = false;
            m_receivedBytes = 0;
            m_streamTotalSize = 0;
            m_receiveFilePath.clear();
        }
        emit remoteTrackChanged(msg["source"].toString(), isPlaying);
    } else if (type == "metadata_update") {
        const QString title = msg[QStringLiteral("title")].toString();
        const QString artist = msg[QStringLiteral("artist")].toString();
        const QString album = msg[QStringLiteral("album")].toString();
        if (!m_isHost && title.isEmpty() && artist.isEmpty() && album.isEmpty())
            return;
        setCurrentTitle(title);
        setCurrentArtist(msg[QStringLiteral("artist")].toString());
        setCurrentAlbum(msg[QStringLiteral("album")].toString());
        setCurrentCoverUrl(msg[QStringLiteral("coverUrl")].toString());
        if (msg.contains(QStringLiteral("streamDuration")))
            setStreamDuration(msg[QStringLiteral("streamDuration")].toInt());
        qDebug() << "[WebRTC][" << (m_isHost ? "HOST" : "CLIENT") << "] Metadata update:"
                 << "title=" << m_currentTitle << "artist=" << m_currentArtist
                 << "album=" << m_currentAlbum << "duration=" << m_streamDuration;
        emit metadataUpdated();
    } else if (type == "request_full_state") {
        if (m_isHost) {
            emit hostStateSyncRequested();
        }
    } else if (type == "full_state") {
        if (!m_isHost && msg.contains(QStringLiteral("syncEpoch"))) {
            const int epoch = msg[QStringLiteral("syncEpoch")].toInt();
            if (m_syncEpoch != epoch) {
                m_syncEpoch = epoch;
                emit syncEpochChanged();
            }
        }
        qDebug() << "[WebRTC][" << (m_isHost ? "HOST" : "CLIENT") << "] Received full state:" << "source=" << msg["source"].toString()
                 << "pos=" << msg["position"].toDouble() << "playing=" << msg["isPlaying"].toBool()
                 << "isLocal=" << msg["isLocalFile"].toBool()
                 << "title=" << msg["title"].toString() << "artist=" << msg["artist"].toString()
                 << "album=" << msg["album"].toString()
                 << "coverUrl=" << coverUrlForLog(msg["coverUrl"].toString())
                 << "duration=" << msg["streamDuration"].toInt();
        emit fullStateReceived(msg);
    } else if (type == "audio_stream_start") {
        if (!m_isHost) {
            qDebug() << "[WebRTC][" << (m_isHost ? "HOST" : "CLIENT") << "] Starting audio stream:" << "file=" << msg["fileName"].toString()
                     << "size=" << msg["fileSize"].toInt() << "mime=" << msg["mimeType"].toString();
            startReceivingStream(msg);
        }
    } else if (type == "audio_stream_end") {
        if (!m_isHost && m_receiveFile) {
            m_receiveFile->close();
            qDebug() << "[WebRTC][" << (m_isHost ? "HOST" : "CLIENT") << "] Audio stream received complete:" << m_receivedBytes << "bytes";
            // Emit ready if this is the first notification for this stream
            if (!m_streamReadyNotified && m_receivedBytes > 0) {
                m_streamReadyNotified = true;
                emit audioStreamReady(m_receiveFilePath, m_streamMimeType);
            }
            if (!m_streamCompleteNotified) {
                m_streamCompleteNotified = true;
                emit audioStreamComplete();
            }
            emit streamReceiveProgressChanged();
        }
    } else if (type == "heartbeat") {
        // Just a heartbeat, nothing to do
    } else if (type == "sync_ready") {
        if (m_isHost) {
            const int epoch = msg.value(QStringLiteral("syncEpoch")).toInt(-1);
            if (epoch >= 0 && epoch != m_syncEpoch) {
                qDebug() << "[WebRTC][ HOST ] Ignoring stale sync_ready epoch" << epoch << "(current" << m_syncEpoch << ")";
                return;
            }
            qDebug() << "[WebRTC][" << (m_isHost ? "HOST" : "CLIENT") << "] Client sync ready";
            emit clientSyncReady();
        }
    } else if (type == "sync_go") {
        if (!m_isHost) {
            const int epoch = msg.value(QStringLiteral("syncEpoch")).toInt(-1);
            if (epoch >= 0 && epoch != m_syncEpoch) {
                qDebug() << "[WebRTC][ CLIENT ] Ignoring stale sync_go epoch" << epoch << "(current" << m_syncEpoch << ")";
                return;
            }
            const int pos = msg[QStringLiteral("position")].toInt(0);
            const bool play = msg[QStringLiteral("isPlaying")].toBool(true);
            qDebug() << "[WebRTC][ CLIENT ] Sync go: pos=" << pos << "play=" << play;
            emit syncStartRequested(pos, play);
        }
    } else if (type == "sync_position") {
        if (!m_isHost)
            emit remoteSyncPositionRequested(msg[QStringLiteral("position")].toInt(0));
    }
}

void WebRTCListenTogetherManager::sendToAllPeers(const QJsonObject &msg) {
    if (!m_dataChannel || !m_dataChannel->isOpen()) return;
    
    QJsonDocument doc(msg);
    std::string data = doc.toJson().toStdString();
    
    m_dataChannel->send(data);
}

void WebRTCListenTogetherManager::broadcastPlay() {
    sendToAllPeers(QJsonObject{{"type", "play"}});
}

void WebRTCListenTogetherManager::broadcastPause() {
    sendToAllPeers(QJsonObject{{"type", "pause"}});
}

void WebRTCListenTogetherManager::broadcastSeek(int position) {
    sendToAllPeers(QJsonObject{{"type", "seek"}, {"position", position}});
}

void WebRTCListenTogetherManager::sendFullStateToPeer()
{
    if (!m_isHost)
        return;

    const bool isLocal = QUrl(m_currentSource).isLocalFile() || m_currentSource.startsWith('/');
    qDebug() << "[WebRTC][" << (m_isHost ? "HOST" : "CLIENT") << "] Sending full state:"
             << "source=" << m_currentSource << "pos=" << m_playbackPosition
             << "playing=" << m_isPlaying << "isLocal=" << isLocal
             << "title=" << m_currentTitle << "artist=" << m_currentArtist
             << "album=" << m_currentAlbum << "coverUrl=" << coverUrlForLog(m_currentCoverUrl)
             << "duration=" << m_streamDuration;

    sendToAllPeers(QJsonObject{
        {QStringLiteral("type"), QStringLiteral("full_state")},
        {QStringLiteral("position"), m_playbackPosition},
        {QStringLiteral("isPlaying"), m_isPlaying},
        {QStringLiteral("source"), m_currentSource},
        {QStringLiteral("isLocalFile"), isLocal},
        {QStringLiteral("title"), m_currentTitle},
        {QStringLiteral("artist"), m_currentArtist},
        {QStringLiteral("album"), m_currentAlbum},
        {QStringLiteral("coverUrl"), coverUrlForPeerTransfer(m_currentCoverUrl)},
        {QStringLiteral("streamDuration"), m_streamDuration},
        {QStringLiteral("syncEpoch"), m_syncEpoch},
    });

    if (isLocal && !m_currentSource.isEmpty()) {
        emit clientCatchUpStarted();
        const QUrl url(m_currentSource);
        startStreaming(url.isLocalFile() ? url.toLocalFile() : m_currentSource);
    }
}

void WebRTCListenTogetherManager::broadcastTrackChange(const QString &source, bool wantsPlayback)
{
    if (!m_isHost)
        return;

    // Never re-broadcast received P2P stream temp files.
    if (source.contains(QStringLiteral("s3rpent_stream_"), Qt::CaseInsensitive))
        return;

    setCurrentSource(source);

    QUrl url(source);
    bool isLocal = url.isLocalFile() || source.startsWith('/');

    if (isLocal) {
        const bool wantedPlay = wantsPlayback;
        if (m_hostWantedPlayback != wantedPlay) {
            m_hostWantedPlayback = wantedPlay;
            emit hostWantedPlaybackChanged();
        }
        m_syncEpoch++;
        emit syncEpochChanged();
        // Clear cached metadata — new file tags are pushed via metadata_update once loaded.
        setCurrentTitle(QString());
        setCurrentArtist(QString());
        setCurrentAlbum(QString());
        setCurrentCoverUrl(QString());
        setStreamDuration(0);

        QJsonObject trackMsg{
            {"type", "track_change"},
            {"source", ""},
            {"isLocalFile", true},
            {"isPlaying", false},
            {QStringLiteral("title"), QString()},
            {QStringLiteral("artist"), QString()},
            {QStringLiteral("album"), QString()},
            {QStringLiteral("coverUrl"), QString()},
            {QStringLiteral("streamDuration"), 0},
            {QStringLiteral("syncEpoch"), m_syncEpoch},
        };
        sendToAllPeers(trackMsg);
        emit hostPauseForSync(wantedPlay);
        startStreaming(url.isLocalFile() ? url.toLocalFile() : source);
    } else {
        sendToAllPeers(QJsonObject{
            {"type", "track_change"},
            {"source", source},
            {"isLocalFile", false},
            {"isPlaying", wantsPlayback},
        });
    }
}

void WebRTCListenTogetherManager::notifyClientSyncReady()
{
    if (m_isHost)
        return;
    qDebug() << "[WebRTC][ CLIENT ] Notifying host: sync ready (epoch" << m_syncEpoch << ")";
    sendToAllPeers(QJsonObject{
        {QStringLiteral("type"), QStringLiteral("sync_ready")},
        {QStringLiteral("syncEpoch"), m_syncEpoch},
    });
}

void WebRTCListenTogetherManager::beginSyncedPlayback(int position, bool affectHost, bool play)
{
    if (!m_isHost)
        return;
    qDebug() << "[WebRTC][ HOST ] Beginning synced playback at pos=" << position
             << "affectHost=" << affectHost << "play=" << play << "epoch=" << m_syncEpoch;
    sendToAllPeers(QJsonObject{
        {QStringLiteral("type"), QStringLiteral("sync_go")},
        {QStringLiteral("position"), position},
        {QStringLiteral("isPlaying"), play},
        {QStringLiteral("syncEpoch"), m_syncEpoch},
    });
    if (affectHost)
        emit syncStartRequested(position, play);
}

void WebRTCListenTogetherManager::broadcastMetadata()
{
    if (!m_isHost)
        return;
    sendToAllPeers(QJsonObject{
        {QStringLiteral("type"), QStringLiteral("metadata_update")},
        {QStringLiteral("title"), m_currentTitle},
        {QStringLiteral("artist"), m_currentArtist},
        {QStringLiteral("album"), m_currentAlbum},
        {QStringLiteral("coverUrl"), coverUrlForPeerTransfer(m_currentCoverUrl)},
        {QStringLiteral("streamDuration"), m_streamDuration},
    });
}

void WebRTCListenTogetherManager::broadcastSyncPosition(int position)
{
    if (!m_isHost)
        return;
    sendToAllPeers(QJsonObject{
        {QStringLiteral("type"), QStringLiteral("sync_position")},
        {QStringLiteral("position"), position},
    });
}

void WebRTCListenTogetherManager::requestFullState() {
    qDebug() << "[WebRTC][" << (m_isHost ? "HOST" : "CLIENT") << "] Requesting full state from host (current source:" << m_currentSource << ")";
    sendToAllPeers(QJsonObject{{"type", "request_full_state"}});
}

void WebRTCListenTogetherManager::publishFullStateToPeer()
{
    sendFullStateToPeer();
}

void WebRTCListenTogetherManager::startHttpServer() {
    if (m_httpServer) return;
    
    m_httpServer = new QTcpServer(this);
    connect(m_httpServer, &QTcpServer::newConnection, this, &WebRTCListenTogetherManager::handleNewHttpConnection);
    
    // Start on a random port
    if (m_httpServer->listen(QHostAddress::Any, 0)) {
        m_httpPort = m_httpServer->serverPort();
        qDebug() << "[WebRTC][" << (m_isHost ? "HOST" : "CLIENT") << "] HTTP File server started on port" << m_httpPort;
    } else {
        qWarning() << "[WebRTC] Failed to start HTTP File server:" << m_httpServer->errorString();
        delete m_httpServer;
        m_httpServer = nullptr;
    }
}

void WebRTCListenTogetherManager::stopHttpServer() {
    if (m_httpServer) {
        m_httpServer->close();
        m_httpServer->deleteLater();
        m_httpServer = nullptr;
        m_httpPort = 0;
    }
}

void WebRTCListenTogetherManager::handleNewHttpConnection() {
    QTcpSocket *socket = m_httpServer->nextPendingConnection();
    if (!socket) return;
    
    socket->setSocketOption(QAbstractSocket::LowDelayOption, 1);
    socket->setSocketOption(QAbstractSocket::KeepAliveOption, 1);

    // Use a struct to keep track of the file state for this socket
    struct StreamState {
        QFile *file;
        qint64 rangeStart;
        qint64 rangeEnd;
        qint64 totalSent;
    };
    
    // Store state in a property so we can access it in slots
    // Using a dynamic property on the socket is a quick way to associate state
    
    connect(socket, &QTcpSocket::readyRead, this, [this, socket]() {
        if (socket->bytesAvailable() < 10) return;
        
        QByteArray request = socket->readAll();
        if (request.startsWith("GET") || request.startsWith("HEAD")) {
            bool isHead = request.startsWith("HEAD");
            
            QUrl url(m_currentSource);
            QString filePath = url.isLocalFile() ? url.toLocalFile() : m_currentSource;
            if (filePath.startsWith("file:///")) filePath = filePath.mid(8);
            
            QFile *file = new QFile(filePath, socket);
            if (file->open(QIODevice::ReadOnly)) {
                qint64 fileSize = file->size();
                qint64 rangeStart = 0;
                qint64 rangeEnd = fileSize - 1;
                bool isRangeRequest = false;
                
                QString requestStr = QString::fromUtf8(request);
                QStringList lines = requestStr.split("\r\n");
                for (const QString &line : lines) {
                    if (line.startsWith("Range: bytes=", Qt::CaseInsensitive)) {
                        QString range = line.mid(13);
                        QStringList parts = range.split("-");
                        if (parts.size() >= 1 && !parts[0].isEmpty()) {
                            rangeStart = parts[0].toLongLong();
                            isRangeRequest = true;
                        }
                        if (parts.size() >= 2 && !parts[1].isEmpty()) {
                            rangeEnd = parts[1].toLongLong();
                        }
                        break;
                    }
                }

                if (rangeEnd >= fileSize) rangeEnd = fileSize - 1;
                if (rangeStart < 0) rangeStart = 0;
                qint64 contentLength = (rangeStart <= rangeEnd) ? (rangeEnd - rangeStart + 1) : 0;
                
                QByteArray response;
                if (isRangeRequest) {
                    response += "HTTP/1.1 206 Partial Content\r\n";
                    response += "Content-Range: bytes " + QByteArray::number(rangeStart) + "-" + QByteArray::number(rangeEnd) + "/" + QByteArray::number(fileSize) + "\r\n";
                } else {
                    response += "HTTP/1.1 200 OK\r\n";
                }
                
                response += "Content-Type: audio/mpeg\r\n";
                response += "Content-Length: " + QByteArray::number(contentLength) + "\r\n";
                response += "Accept-Ranges: bytes\r\n";
                response += "Access-Control-Allow-Origin: *\r\n";
                response += "Connection: keep-alive\r\n";
                response += "\r\n";
                
                socket->write(response);
                if (isHead) {
                    socket->flush();
                    return;
                }
                
                if (rangeStart > 0) file->seek(rangeStart);
                
                // Set up the streaming state
                socket->setProperty("totalSent", 0);
                socket->setProperty("contentLength", contentLength);
                socket->setProperty("rangeStart", rangeStart);
                socket->setProperty("rangeEnd", rangeEnd);
                
                // Connect bytesWritten to send the next chunk
                connect(socket, &QTcpSocket::bytesWritten, this, [this, socket, file](qint64 bytes) {
                    Q_UNUSED(bytes);
                    if (socket->bytesToWrite() < 128 * 1024) { // Buffer up to 128KB
                        sendNextChunk(socket, file, socket->property("rangeStart").toLongLong(), socket->property("rangeEnd").toLongLong());
                    }
                });
                
                // Start the first chunk
                sendNextChunk(socket, file, rangeStart, rangeEnd);
            } else {
                socket->write("HTTP/1.1 404 Not Found\r\n\r\n");
                socket->disconnectFromHost();
            }
        }
    });
    
    connect(socket, &QTcpSocket::disconnected, socket, &QTcpSocket::deleteLater);
}

void WebRTCListenTogetherManager::sendNextChunk(QTcpSocket *socket, QFile *file, qint64 rangeStart, qint64 rangeEnd) {
    Q_UNUSED(rangeStart);
    qint64 totalSent = socket->property("totalSent").toLongLong();
    qint64 contentLength = socket->property("contentLength").toLongLong();
    
    if (totalSent >= contentLength) {
        // All data sent, but don't close for keep-alive unless needed
        return;
    }
    
    qint64 toRead = qMin((qint64)64 * 1024, contentLength - totalSent);
    QByteArray chunk = file->read(toRead);
    if (chunk.isEmpty()) return;
    
    qint64 written = socket->write(chunk);
    if (written > 0) {
        socket->setProperty("totalSent", totalSent + written);
    }
}

QString WebRTCListenTogetherManager::getLocalIpAddress() const {
    QString localIp;
    const QList<QHostAddress> ipAddressesList = QNetworkInterface::allAddresses();
    for (const QHostAddress &address : ipAddressesList) {
        if (address != QHostAddress::LocalHost && address.toIPv4Address()) {
            localIp = address.toString();
            break;
        }
    }
    if (localIp.isEmpty())
        localIp = QHostAddress(QHostAddress::LocalHost).toString();
    return localIp;
}

QString WebRTCListenTogetherManager::getSyncUrl() const {
    QUrl url(m_currentSource);
    if (!url.isLocalFile() && !m_currentSource.startsWith("/")) {
        // Already a network URL (YouTube, etc.)
        return m_currentSource;
    }
    
    // Host the local file via our HTTP server
    if (m_httpPort > 0) {
        return QString("http://%1:%2/sync_file").arg(getLocalIpAddress()).arg(m_httpPort);
    }
    
    return m_currentSource;
}

void WebRTCListenTogetherManager::setStreamPreparing(bool preparing)
{
    if (m_streamPreparing == preparing)
        return;
    m_streamPreparing = preparing;
    emit streamPreparingChanged();
}

QString WebRTCListenTogetherManager::resolveFfmpegPath() const
{
    const QString appDir = QCoreApplication::applicationDirPath();
    const QStringList names = {QStringLiteral("ffmpeg.exe"), QStringLiteral("ffmpeg")};
    for (const QString &name : names) {
        const QString candidate = appDir + QLatin1Char('/') + name;
        if (QFileInfo::exists(candidate))
            return candidate;
    }
    return QStringLiteral("ffmpeg");
}

bool WebRTCListenTogetherManager::shouldCompressStream(const QString &filePath) const
{
    if (!m_compressStreamsForPeer)
        return false;

    const QFileInfo fi(filePath);
    if (!fi.exists() || !fi.isFile())
        return false;

    const QString ext = fi.suffix().toLower();
    if (ext == QLatin1String("mp3") || ext == QLatin1String("m4a") || ext == QLatin1String("aac")
        || ext == QLatin1String("opus") || ext == QLatin1String("ogg")) {
        return fi.size() > 15 * 1024 * 1024;
    }
    if (ext == QLatin1String("flac") || ext == QLatin1String("wav") || ext == QLatin1String("alac"))
        return true;

    return fi.size() > 12 * 1024 * 1024;
}

void WebRTCListenTogetherManager::cancelStreamEncode()
{
    setStreamPreparing(false);
    if (m_streamEncodeProcess) {
        m_streamEncodeProcess->kill();
        m_streamEncodeProcess->deleteLater();
        m_streamEncodeProcess = nullptr;
    }
    if (!m_streamEncodeTempPath.isEmpty()) {
        QFile::remove(m_streamEncodeTempPath);
        m_streamEncodeTempPath.clear();
    }
    m_pendingStreamSourcePath.clear();
}

void WebRTCListenTogetherManager::startStreamEncode(const QString &filePath)
{
    cancelStreamEncode();
    m_pendingStreamSourcePath = filePath;

    const QString ffmpeg = resolveFfmpegPath();
    const QString outPath = QDir::temp().filePath(
        QStringLiteral("s3rpent_lt_enc_%1_%2.mp3")
            .arg(m_sessionId, QUuid::createUuid().toString(QUuid::WithoutBraces).left(8)));
    m_streamEncodeTempPath = outPath;

    auto *proc = new QProcess(this);
    m_streamEncodeProcess = proc;
    setStreamPreparing(true);

    qDebug() << "[WebRTC][ HOST ] Compressing track for peer (MP3):" << QFileInfo(filePath).fileName();

    proc->setProgram(ffmpeg);
    proc->setArguments({
        QStringLiteral("-y"),
        QStringLiteral("-hide_banner"),
        QStringLiteral("-loglevel"),
        QStringLiteral("error"),
        QStringLiteral("-i"),
        filePath,
        QStringLiteral("-map"),
        QStringLiteral("0:a:0"),
        QStringLiteral("-map"),
        QStringLiteral("0:v?"),
        QStringLiteral("-c:a"),
        QStringLiteral("libmp3lame"),
        QStringLiteral("-b:a"),
        QStringLiteral("192k"),
        QStringLiteral("-map_metadata"),
        QStringLiteral("0"),
        QStringLiteral("-id3v2_version"),
        QStringLiteral("3"),
        QStringLiteral("-write_id3v1"),
        QStringLiteral("1"),
        QStringLiteral("-c:v"),
        QStringLiteral("copy"),
        QStringLiteral("-disposition:v:0"),
        QStringLiteral("attached_pic"),
        outPath,
    });

    connect(proc, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
            this, [this, proc, filePath, outPath](int exitCode, QProcess::ExitStatus status) {
        const bool ok = (status == QProcess::NormalExit && exitCode == 0
                         && QFileInfo::exists(outPath) && QFileInfo(outPath).size() > 0);
        m_streamEncodeProcess = nullptr;
        proc->deleteLater();
        setStreamPreparing(false);

        if (!m_isHost || !m_dataChannel || !m_dataChannel->isOpen()) {
            QFile::remove(outPath);
            m_streamEncodeTempPath.clear();
            m_pendingStreamSourcePath.clear();
            return;
        }

        if (ok) {
            const QString displayName = QFileInfo(filePath).completeBaseName() + QStringLiteral(".mp3");
            qDebug() << "[WebRTC][ HOST ] Compressed for peer:" << QFileInfo(outPath).size() << "bytes";
            beginStreamingPreparedFile(outPath, displayName);
        } else {
            qWarning() << "[WebRTC][ HOST ] Compression failed, streaming original file";
            QFile::remove(outPath);
            m_streamEncodeTempPath.clear();
            beginStreamingPreparedFile(filePath);
        }
        m_pendingStreamSourcePath.clear();
    });

    proc->start();
}

void WebRTCListenTogetherManager::startStreaming(const QString &filePath) {
    if (!m_dataChannel || !m_dataChannel->isOpen()) {
        qWarning() << "[WebRTC] Cannot start streaming: data channel not open";
        return;
    }
    if (!m_isHost) {
        qWarning() << "[WebRTC] Only host can stream audio";
        return;
    }

    stopStreaming();

    if (shouldCompressStream(filePath)) {
        startStreamEncode(filePath);
        return;
    }

    beginStreamingPreparedFile(filePath);
}

void WebRTCListenTogetherManager::beginStreamingPreparedFile(const QString &filePath, const QString &displayFileName)
{
    if (!m_dataChannel || !m_dataChannel->isOpen() || !m_isHost)
        return;

    m_streamFile = new QFile(filePath, this);
    if (!m_streamFile->open(QIODevice::ReadOnly)) {
        qWarning() << "[WebRTC] Failed to open file for streaming:" << filePath << "-" << m_streamFile->errorString();
        m_streamFile->deleteLater();
        m_streamFile = nullptr;
        return;
    }

    m_streamChunkIndex = 0;
    const qint64 fileSize = m_streamFile->size();

    QString mimeType = QStringLiteral("audio/mpeg");
    const QString ext = QFileInfo(filePath).suffix().toLower();
    if (ext == QLatin1String("flac"))
        mimeType = QStringLiteral("audio/flac");
    else if (ext == QLatin1String("ogg") || ext == QLatin1String("oga"))
        mimeType = QStringLiteral("audio/ogg");
    else if (ext == QLatin1String("wav"))
        mimeType = QStringLiteral("audio/wav");
    else if (ext == QLatin1String("m4a") || ext == QLatin1String("aac"))
        mimeType = QStringLiteral("audio/mp4");
    else if (ext == QLatin1String("opus"))
        mimeType = QStringLiteral("audio/opus");

    const QString streamName = displayFileName.isEmpty() ? QFileInfo(filePath).fileName() : displayFileName;

    qDebug() << "[WebRTC][" << (m_isHost ? "HOST" : "CLIENT") << "] Starting audio stream:" << streamName
             << "size:" << fileSize << "mime:" << mimeType;

    QJsonObject startMsg{
        {QStringLiteral("type"), QStringLiteral("audio_stream_start")},
        {QStringLiteral("fileSize"), fileSize},
        {QStringLiteral("mimeType"), mimeType},
        {QStringLiteral("fileName"), streamName},
    };
    sendToAllPeers(startMsg);

    m_streamChunkIndex = 0;
    m_streamSkipCount = 0;
    m_streamTimer = new QTimer(this);
    m_streamTimer->setInterval(STREAM_TIMER_MS);
    connect(m_streamTimer, &QTimer::timeout, this, &WebRTCListenTogetherManager::sendNextAudioChunk);
    m_streamTimer->start();
}

void WebRTCListenTogetherManager::sendNextAudioChunk() {
    if (!m_streamFile || !m_dataChannel || !m_dataChannel->isOpen()) {
        stopStreaming();
        return;
    }
    
    if (m_dataChannel->bufferedAmount() > 1024 * 1024) {
        m_streamSkipCount++;
        if (m_streamSkipCount > 40) {
            qWarning() << "[WebRTC] Stream buffer stalled for 2s, stopping";
            stopStreaming();
        }
        return;
    }
    m_streamSkipCount = 0;
    
    QByteArray chunk = m_streamFile->read(STREAM_CHUNK_SIZE);
    if (chunk.isEmpty()) {
        qDebug() << "[WebRTC][" << (m_isHost ? "HOST" : "CLIENT") << "] Audio stream complete. Sent" << m_streamChunkIndex << "chunks total";
        QJsonObject endMsg{{"type", "audio_stream_end"}};
        sendToAllPeers(endMsg);
        stopStreaming();
        return;
    }
    
    try {
        rtc::binary binaryData(chunk.size());
        std::memcpy(binaryData.data(), chunk.data(), chunk.size());
        m_dataChannel->send(binaryData);
        m_streamChunkIndex++;
    } catch (const std::exception &e) {
        qWarning() << "[WebRTC] Failed to send audio chunk (will retry):" << e.what();
        m_streamSkipCount++;
        if (m_streamSkipCount > 20) {
            qWarning() << "[WebRTC] Too many send failures, stopping stream";
            stopStreaming();
        }
    }
}

void WebRTCListenTogetherManager::stopStreaming() {
    qDebug() << "[WebRTC][" << (m_isHost ? "HOST" : "CLIENT") << "] Stopping audio stream (chunks sent:" << m_streamChunkIndex << ")";
    if (m_streamTimer) {
        m_streamTimer->stop();
        m_streamTimer->deleteLater();
        m_streamTimer = nullptr;
    }

    QString streamedPath;
    if (m_streamFile) {
        streamedPath = m_streamFile->fileName();
        m_streamFile->close();
        m_streamFile->deleteLater();
        m_streamFile = nullptr;
    }

    if (m_streamEncodeProcess) {
        m_streamEncodeProcess->kill();
        m_streamEncodeProcess->deleteLater();
        m_streamEncodeProcess = nullptr;
        setStreamPreparing(false);
    }
    m_pendingStreamSourcePath.clear();

    if (!m_streamEncodeTempPath.isEmpty()) {
        if (streamedPath.isEmpty() || streamedPath == m_streamEncodeTempPath)
            QFile::remove(m_streamEncodeTempPath);
        m_streamEncodeTempPath.clear();
    }

    m_streamChunkIndex = 0;
    m_streamSkipCount = 0;
}

void WebRTCListenTogetherManager::startReceivingStream(const QJsonObject &startMsg) {
    if (m_receiveFile) {
        m_receiveFile->close();
        delete m_receiveFile;
        m_receiveFile = nullptr;
    }
    
    m_streamTotalSize = static_cast<qint64>(startMsg["fileSize"].toDouble());
    m_streamMimeType = startMsg["mimeType"].toString();
    if (m_streamMimeType.isEmpty()) m_streamMimeType = "audio/mpeg";

    const QString originalName = startMsg[QStringLiteral("fileName")].toString();
    QString ext = QFileInfo(originalName).suffix();
    if (ext.isEmpty())
        ext = streamExtensionFromMime(m_streamMimeType);

    QString fileBase = QStringLiteral("s3rpent_stream_%1_%2")
                           .arg(m_sessionId, QUuid::createUuid().toString(QUuid::WithoutBraces).left(8));
    if (!ext.isEmpty())
        fileBase += QLatin1Char('.') + ext.toLower();

    m_receiveFilePath = QDir::temp().filePath(fileBase);
    
    m_receiveFile = new QFile(m_receiveFilePath);
    if (!m_receiveFile->open(QIODevice::WriteOnly)) {
        qWarning() << "[WebRTC] Failed to create temp file for audio stream:" << m_receiveFilePath;
        delete m_receiveFile;
        m_receiveFile = nullptr;
        return;
    }
    
    m_receivedBytes = 0;
    m_streamReadyNotified = false;
    m_streamCompleteNotified = false;
    emit streamReceiveProgressChanged();
    
    qDebug() << "[WebRTC][" << (m_isHost ? "HOST" : "CLIENT") << "] Receiving audio stream:" << startMsg["fileName"].toString()
             << "size:" << m_streamTotalSize << "mime:" << m_streamMimeType;
}

void WebRTCListenTogetherManager::handleAudioChunk(const QByteArray &chunk) {
    if (m_isHost) return;
    
    if (!m_receiveFile) {
        qWarning() << "[WebRTC] Received audio chunk but no stream is active";
        return;
    }
    
    if (m_receiveFile->write(chunk) != chunk.size()) {
        qWarning() << "[WebRTC] Failed to write audio chunk to temp file";
        return;
    }
    m_receivedBytes += chunk.size();
    
    if ((m_receivedBytes / STREAM_CHUNK_SIZE) % 5 == 0)
        emit streamReceiveProgressChanged();
    
    // Periodic flush so the media player sees new data on Windows
    if ((m_receivedBytes / STREAM_CHUNK_SIZE) % 10 == 0) {
        m_receiveFile->flush();
    }
    
    if (!m_streamReadyNotified && m_receivedBytes >= 65536) {
        m_streamReadyNotified = true;
        m_receiveFile->flush();
        qDebug() << "[WebRTC][" << (m_isHost ? "HOST" : "CLIENT") << "] Audio stream ready to play:" << m_receiveFilePath
                 << "received:" << m_receivedBytes << "bytes" << "mime:" << m_streamMimeType;
        emit audioStreamReady(m_receiveFilePath, m_streamMimeType);
    }

    // Complete only on audio_stream_end — size-based complete here raced with wrong totals.
}

void WebRTCListenTogetherManager::checkConnectionTimeout() {
    if (!m_isConnected) {
        qWarning() << "[WebRTC] Connection timeout";
        leaveSession();
    }
}

void WebRTCListenTogetherManager::sendSignalingMessage(const QJsonObject &msg) {
    QJsonDocument doc(msg);
    QByteArray data = doc.toJson();
    const QString requestType = msg[QStringLiteral("type")].toString();

    QNetworkRequest request(m_signalingServerUrl);
    request.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");

    QNetworkReply *reply = m_networkManager->post(request, data);
    connect(reply, &QNetworkReply::finished, this, [this, reply, requestType]() {
        reply->deleteLater();
        const QByteArray body = reply->readAll();
        if (reply->error() != QNetworkReply::NoError) {
            qWarning() << "[WebRTC] Signaling error (" << requestType << "):" << reply->errorString()
                       << "HTTP" << reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt()
                       << body;
            if (requestType == QStringLiteral("join_session") && !m_isHost)
                m_connectionTimeoutTimer->stop();
            return;
        }

        QJsonDocument doc = QJsonDocument::fromJson(body);
        if (!doc.isObject())
            return;

        const QJsonObject response = doc.object();
        if (requestType == QStringLiteral("create_session") && m_isHost) {
            if (response[QStringLiteral("success")].toBool(false))
                startHostPeerConnection();
            else
                qWarning() << "[WebRTC] create_session failed:" << body;
        } else if (requestType == QStringLiteral("join_session") && !m_isHost) {
            if (!response[QStringLiteral("success")].toBool(false)) {
                qWarning() << "[WebRTC] join_session failed:" << body;
                m_connectionTimeoutTimer->stop();
            }
        }

        handleSignalingResponse(response);
    });
}

void WebRTCListenTogetherManager::handleSignalingResponse(const QJsonObject &response) {
    if (!response.contains(QStringLiteral("messages")) || !response[QStringLiteral("messages")].isArray())
        return;

    QList<QJsonObject> descriptions;
    QList<QJsonObject> candidates;
    QList<QJsonObject> other;
    const QJsonArray messages = response[QStringLiteral("messages")].toArray();
    for (const QJsonValue &val : messages) {
        if (!val.isObject())
            continue;
        const QJsonObject obj = val.toObject();
        const QString type = obj[QStringLiteral("type")].toString();
        if (type == QStringLiteral("description"))
            descriptions.append(obj);
        else if (type == QStringLiteral("candidate"))
            candidates.append(obj);
        else
            other.append(obj);
    }

    const auto byId = [](const QJsonObject &a, const QJsonObject &b) {
        return a[QStringLiteral("id")].toInt() < b[QStringLiteral("id")].toInt();
    };
    std::sort(descriptions.begin(), descriptions.end(), byId);
    std::sort(candidates.begin(), candidates.end(), byId);

    if (!m_isHost && descriptions.size() > 1) {
        QJsonObject latestHostOffer;
        int latestOfferId = -1;
        for (const QJsonObject &d : descriptions) {
            if (!d.value(QStringLiteral("isHost")).toBool(false))
                continue;
            const int id = d.value(QStringLiteral("id")).toInt();
            if (id > latestOfferId) {
                latestOfferId = id;
                latestHostOffer = d;
            }
        }
        if (!latestHostOffer.isEmpty()) {
            descriptions.clear();
            descriptions.append(latestHostOffer);
            QList<QJsonObject> filteredCandidates;
            for (const QJsonObject &c : candidates) {
                if (c.value(QStringLiteral("id")).toInt() >= latestOfferId)
                    filteredCandidates.append(c);
            }
            candidates = filteredCandidates;
        }
    }

    if (!m_isHost && !descriptions.isEmpty() && candidates.size() > 0 && !m_hasRemoteDescription) {
        qDebug() << "[WebRTC][ CLIENT ] Applying" << descriptions.size() << "SDP message(s) before"
                 << candidates.size() << "ICE candidate(s)";
    }

    for (const QJsonObject &obj : descriptions)
        onSignalingMessage(obj);
    for (const QJsonObject &obj : candidates)
        onSignalingMessage(obj);
    for (const QJsonObject &obj : other)
        onSignalingMessage(obj);

    if (!m_isHost && !m_hasRemoteDescription && !candidates.isEmpty()) {
        qWarning() << "[WebRTC][ CLIENT ] Have ICE candidates but no remote offer — check signaling server";
    }
}

void WebRTCListenTogetherManager::pollMessages() {
    if (m_sessionId.isEmpty()) return;
    
    QJsonObject msg{
        {"type", "poll"},
        {"sessionId", m_sessionId}
    };
    sendSignalingMessage(msg);
}

void WebRTCListenTogetherManager::onSignalingMessage(const QJsonObject &msg) {
    if (!m_peerConnection) return;
    
    QString type = msg["type"].toString();
    int msgId = msg["id"].toInt();
    
    // Skip messages we've already processed
    if (msgId > 0 && m_processedMessages.contains(msgId)) {
        return;
    }
    if (msgId > 0) {
        m_processedMessages.insert(msgId);
    }
    
    // Skip our own messages if we're polling
    // If "isHost" is missing, we assume it's NOT from us if we are host, 
    // which was the bug. Now we send it explicitly.
    if (msg.contains("isHost")) {
        bool isHostMsg = msg["isHost"].toBool();
        if (isHostMsg == m_isHost) {
            return;
        }
    } else {
        // Legacy or missing flag - skip if we are host to be safe
        if (m_isHost) return;
    }
    
    try {
        if (type == "description") {
            QString sdp = msg["sdp"].toString();
            if (sdp.isEmpty()) return;
            
            QString descType = m_isHost ? "answer" : "offer";
            qDebug() << "[WebRTC][" << (m_isHost ? "HOST" : "CLIENT") << "] Received description (" << descType << ")";
            
            rtc::Description desc(sdp.toStdString(), descType.toStdString());
            m_peerConnection->setRemoteDescription(desc);
            m_hasRemoteDescription = true;
            
            // Apply any candidates that arrived before the remote description
            for (const auto &pair : m_pendingCandidates) {
                try {
                    rtc::Candidate candidate(pair.first.toStdString(), pair.second.toStdString());
                    m_peerConnection->addRemoteCandidate(candidate);
                } catch (const std::exception &e) {
                    qWarning() << "[WebRTC] Failed to apply queued candidate:" << e.what();
                }
            }
            m_pendingCandidates.clear();
            
            if (!m_isHost) {
                // Client: after setting remote offer, generate local answer
                qDebug() << "[WebRTC][" << (m_isHost ? "HOST" : "CLIENT") << "] Generating answer...";
                m_peerConnection->setLocalDescription();
            }
        } else if (type == "candidate") {
            QString cand = msg["candidate"].toString();
            QString mid = msg["mid"].toString();
            if (cand.isEmpty()) return;
            
            qDebug() << "[WebRTC][" << (m_isHost ? "HOST" : "CLIENT") << "] Received candidate";
            if (!m_hasRemoteDescription) {
                qDebug() << "[WebRTC] Queuing candidate until remote description is set";
                m_pendingCandidates.append({cand, mid});
            } else {
                rtc::Candidate candidate(cand.toStdString(), mid.toStdString());
                m_peerConnection->addRemoteCandidate(candidate);
            }
        }
    } catch (const std::exception &e) {
        qWarning() << "[WebRTC] Exception in onSignalingMessage:" << e.what();
    } catch (...) {
        qWarning() << "[WebRTC] Unknown exception in onSignalingMessage";
    }
}
