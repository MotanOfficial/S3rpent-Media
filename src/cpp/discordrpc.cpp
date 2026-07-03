#include "discordrpc.h"
#include <QStandardPaths>
#include <QDir>
#include <QJsonObject>
#include <QJsonDocument>
#include <QDateTime>
#include <QCoreApplication>
#include <QSettings>
#include <QMetaObject>

#ifdef Q_OS_WIN
#include <windows.h>
#include <string>
#else
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>
#include <fcntl.h>
#endif

DiscordRPC::DiscordRPC(QObject *parent)
    : QObject(parent)
    , m_enabled(true)  // Enabled by default
    , m_connected(false)
#ifdef Q_OS_WIN
    , m_pipeHandle(INVALID_HANDLE_VALUE)
#else
    , m_socketFd(-1)
#endif
    , m_hasLastPresence(false)
    , m_minimalClientId("1397125867238588416")  // Application ID for Listening activity with cover art
    , m_ioThread(nullptr)
    , m_ioObject(nullptr)
    , m_lastPresenceSendMs(0)
{
    // Load settings
    QSettings settings;
    settings.beginGroup("discord");
    m_enabled = settings.value("enabled", true).toBool();  // Default to enabled
    settings.endGroup();

    ensureIoThread();
    
    m_reconnectTimer = new QTimer(this);
    m_reconnectTimer->setInterval(5000); // Try to reconnect every 5 seconds
    m_reconnectTimer->setSingleShot(false);
    connect(m_reconnectTimer, &QTimer::timeout, this, &DiscordRPC::reconnectTimer);
    
    // Auto-connect if enabled
    if (m_enabled) {
        QTimer::singleShot(1000, this, [this]() {
            connectToDiscord();
            m_reconnectTimer->start();
        });
    }
}

DiscordRPC::~DiscordRPC()
{
    disconnectFromDiscord();
    if (m_ioThread) {
        m_ioThread->quit();
        m_ioThread->wait(2000);
        m_ioThread = nullptr;
        m_ioObject = nullptr;
    }
}

void DiscordRPC::setEnabled(bool enabled)
{
    if (m_enabled == enabled)
        return;
    
    m_enabled = enabled;
    
    // Save to settings
    QSettings settings;
    settings.beginGroup("discord");
    settings.setValue("enabled", m_enabled);
    settings.endGroup();
    
    if (enabled) {
        connectToDiscord();
        m_reconnectTimer->start();
    } else {
        disconnectFromDiscord();
        m_reconnectTimer->stop();
    }
    
    emit enabledChanged();
}

// setApplicationId removed - application ID is always the default value

void DiscordRPC::updatePresence(const QString &title, const QString &artist, 
                                 qint64 position, qint64 duration, 
                                 int playbackState, const QString &album,
                                 const QString &coverArtUrl)
{
    if (!m_enabled) {
        return;
    }
    if (!m_connected) {
        connectToDiscord();
        return;
    }

    // Build presence object
    QJsonObject presence;
    
    // Match WatchDis format for YouTube Music:
    // - details: track title
    // - state: artist name
    // - name: "YouTube Music" (but we'll use a generic name or omit it)
    
    QString details;
    if (!title.isEmpty()) {
        details = title;
    } else if (!artist.isEmpty()) {
        details = artist;
    } else {
        details = "Unknown Track";
    }
    
    QString state;
    if (!artist.isEmpty()) {
        state = artist;
    }
    
    presence["details"] = details;
    if (!state.isEmpty()) {
        presence["state"] = state;
    }
    
    // Set activity type to 2 (Listening) - matches WatchDis and CustomRP format
    // Type 2 = Listening activity (shows as "Listening to..." in Discord)
    presence["type"] = 2;
    
    // Timestamps - match WatchDis calculation exactly
    // WatchDis: start = Math.floor(Date.now() - currentTime), end = Math.floor(Date.now() - currentTime + duration)
    // All values in milliseconds, then converted to seconds
    if (playbackState == 1 && duration > 0) {
        QJsonObject timestamps;
        qint64 currentTimeMs = QDateTime::currentMSecsSinceEpoch();
        qint64 startTime = (currentTimeMs - position) / 1000;  // Convert to seconds
        qint64 endTime = (currentTimeMs - position + duration) / 1000;  // Convert to seconds
        timestamps["start"] = static_cast<qint64>(startTime);
        timestamps["end"] = static_cast<qint64>(endTime);
        presence["timestamps"] = timestamps;
    } else if (playbackState == 2 && position > 0 && duration > 0) {
        // Paused - include timestamps but no end time
        QJsonObject timestamps;
        qint64 currentTimeMs = QDateTime::currentMSecsSinceEpoch();
        qint64 startTime = (currentTimeMs - position) / 1000;
        timestamps["start"] = static_cast<qint64>(startTime);
        // Don't set end when paused (Discord will show paused state)
        presence["timestamps"] = timestamps;
    }
    
    // Assets (large image: album art if available) - match WatchDis format
    QJsonObject assets;
    if (!coverArtUrl.isEmpty()) {
        // Use cover art URL if provided
        // Try using file:// URLs - Discord might accept them or convert them
        QString imageUrl = coverArtUrl;
        
        // Try using the URL as-is (including file:// URLs)
        // Discord might handle file:// URLs or convert them internally
        assets["large_image"] = imageUrl;
        if (!album.isEmpty()) {
            assets["large_text"] = album;
        } else if (!title.isEmpty()) {
            assets["large_text"] = title;
        }
        
    }
    // Always include assets object (even if empty) to match WatchDis behavior
    if (!assets.isEmpty()) {
        presence["assets"] = assets;
    }
    
    // Build the command
    QJsonObject args;
    args["pid"] = static_cast<int>(QCoreApplication::applicationPid());
    args["activity"] = presence;
    
    QJsonObject command;
    command["cmd"] = "SET_ACTIVITY";
    command["args"] = args;
    command["nonce"] = QString::number(QDateTime::currentMSecsSinceEpoch());
    
    // Throttle + dedupe to avoid GUI-thread churn and Discord IPC spam.
    const qint64 nowMs = QDateTime::currentMSecsSinceEpoch();
    if (m_hasLastPresence && presence == m_lastPresence && (nowMs - m_lastPresenceSendMs) < 1000) {
        return;
    }
    if ((nowMs - m_lastPresenceSendMs) < 1000 && playbackState == 1) {
        // While playing, update at most once per second.
        return;
    }

    m_lastPresence = presence;
    m_hasLastPresence = true;
    m_lastPresenceSendMs = nowMs;

    // Send the command asynchronously (IPC can block on Windows pipes).
    ensureIoThread();
    QMetaObject::invokeMethod(m_ioObject, [this, command]() {
        if (!sendCommand(command)) {
            // Treat as disconnected; force reconnect later.
            disconnectFromDiscord();
        }
    }, Qt::QueuedConnection);
}

void DiscordRPC::clearPresence()
{
    if (!m_enabled || !m_connected) {
        return;
    }
    
    // Send empty presence to clear
    QJsonObject args;
    args["pid"] = static_cast<int>(QCoreApplication::applicationPid());
    
    QJsonObject command;
    command["cmd"] = "SET_ACTIVITY";
    command["args"] = args;
    command["nonce"] = QString::number(QDateTime::currentMSecsSinceEpoch());
    
    ensureIoThread();
    QMetaObject::invokeMethod(m_ioObject, [this, command]() {
        if (!sendCommand(command)) {
            disconnectFromDiscord();
        }
    }, Qt::QueuedConnection);
    m_hasLastPresence = false;
}

void DiscordRPC::reconnectTimer()
{
    if (m_enabled && !m_connected) {
        connectToDiscord();
    }
}

void DiscordRPC::ensureIoThread()
{
    if (m_ioThread && m_ioObject) {
        return;
    }
    m_ioThread = new QThread(this);
    m_ioObject = new QObject();
    m_ioObject->moveToThread(m_ioThread);
    connect(m_ioThread, &QThread::finished, m_ioObject, &QObject::deleteLater);
    m_ioThread->start();
}

void DiscordRPC::setConnected(bool connected)
{
    if (m_connected == connected) {
        return;
    }
    m_connected = connected;
    emit connectionStatusChanged(connected);
}

bool DiscordRPC::connectToDiscord()
{
    if (m_connected) {
        return true;
    }

    ensureIoThread();
    QMetaObject::invokeMethod(m_ioObject, [this]() {
        const QString pipePath = findDiscordPipe();
        if (pipePath.isEmpty()) {
            return;
        }

#ifdef Q_OS_WIN
        std::wstring pipePathW = pipePath.toStdWString();
        m_pipeHandle = CreateFileW(pipePathW.c_str(), GENERIC_READ | GENERIC_WRITE, 0, nullptr, OPEN_EXISTING, 0, nullptr);
        if (m_pipeHandle == INVALID_HANDLE_VALUE) {
            return;
        }
#else
        struct sockaddr_un addr;
        memset(&addr, 0, sizeof(addr));
        addr.sun_family = AF_UNIX;
        strncpy(addr.sun_path, pipePath.toLocal8Bit().constData(), sizeof(addr.sun_path) - 1);

        m_socketFd = socket(AF_UNIX, SOCK_STREAM, 0);
        if (m_socketFd < 0) {
            return;
        }
        if (connect(m_socketFd, (struct sockaddr*)&addr, sizeof(addr)) < 0) {
            close(m_socketFd);
            m_socketFd = -1;
            return;
        }
#endif

        bool ok = false;
        if (sendHandshake()) {
            const QByteArray response = readFromPipe();
            if (!response.isEmpty()) {
                const QJsonDocument responseDoc = QJsonDocument::fromJson(response);
                const QJsonObject responseObj = responseDoc.object();
                const int code = responseObj.value("code").toInt();
                ok = (code == 0);
            } else {
                ok = true;
            }
        }

        if (!ok) {
#ifdef Q_OS_WIN
            if (m_pipeHandle != INVALID_HANDLE_VALUE) {
                CloseHandle(m_pipeHandle);
                m_pipeHandle = INVALID_HANDLE_VALUE;
            }
#else
            if (m_socketFd >= 0) {
                close(m_socketFd);
                m_socketFd = -1;
            }
#endif
            return;
        }

        QMetaObject::invokeMethod(this, [this]() {
            setConnected(true);
        }, Qt::QueuedConnection);
    }, Qt::QueuedConnection);

    return false;
}

void DiscordRPC::disconnectFromDiscord()
{
    if (m_connected) {
        setConnected(false);
    }
    if (!m_ioObject) {
        return;
    }
    QMetaObject::invokeMethod(m_ioObject, [this]() {
#ifdef Q_OS_WIN
        if (m_pipeHandle != INVALID_HANDLE_VALUE) {
            CloseHandle(m_pipeHandle);
            m_pipeHandle = INVALID_HANDLE_VALUE;
        }
#else
        if (m_socketFd >= 0) {
            close(m_socketFd);
            m_socketFd = -1;
        }
#endif
    }, Qt::QueuedConnection);
}

bool DiscordRPC::sendHandshake()
{
    QJsonObject handshake;
    handshake["v"] = 1;
    handshake["client_id"] = m_minimalClientId;  // Built-in application ID - no user configuration needed
    
    return sendCommand(handshake);
}

bool DiscordRPC::sendCommand(const QJsonObject &command)
{
    QJsonDocument doc(command);
    QByteArray jsonData = doc.toJson(QJsonDocument::Compact);
    
    // Discord IPC uses a simple protocol:
    // [opcode: 4 bytes][length: 4 bytes][data: length bytes]
    // Opcode 0 = HANDSHAKE, 1 = FRAME
    
    // If command contains "v" (version), it's a handshake (opcode 0)
    // Otherwise it's a frame (opcode 1)
    quint32 opcode = command.contains("v") ? 0 : 1;
    quint32 length = static_cast<quint32>(jsonData.size());
    
    QByteArray packet;
    packet.append(reinterpret_cast<const char*>(&opcode), 4);
    packet.append(reinterpret_cast<const char*>(&length), 4);
    packet.append(jsonData);
    
    return writeToPipe(packet);
}

bool DiscordRPC::writeToPipe(const QByteArray &data)
{
#ifdef Q_OS_WIN
    if (m_pipeHandle == INVALID_HANDLE_VALUE) {
        return false;
    }
    
    DWORD bytesWritten = 0;
    if (!WriteFile(m_pipeHandle, data.constData(), static_cast<DWORD>(data.size()), &bytesWritten, nullptr)) {
        return false;
    }
    
    return bytesWritten == static_cast<DWORD>(data.size());
#else
    if (m_socketFd < 0) {
        return false;
    }
    
    ssize_t bytesWritten = write(m_socketFd, data.constData(), data.size());
    return bytesWritten == static_cast<ssize_t>(data.size());
#endif
}

QByteArray DiscordRPC::readFromPipe()
{
    QByteArray result;
    
#ifdef Q_OS_WIN
    if (m_pipeHandle == INVALID_HANDLE_VALUE) {
        return result;
    }
    
    quint32 opcode = 0;
    quint32 length = 0;
    DWORD bytesRead = 0;
    
    // Read opcode
    if (!ReadFile(m_pipeHandle, &opcode, 4, &bytesRead, nullptr) || bytesRead != 4) {
        return result;
    }
    
    // Read length
    if (!ReadFile(m_pipeHandle, &length, 4, &bytesRead, nullptr) || bytesRead != 4) {
        return result;
    }
    
    // Read data
    if (length > 0) {
        result.resize(static_cast<int>(length));
        if (!ReadFile(m_pipeHandle, result.data(), length, &bytesRead, nullptr) || bytesRead != length) {
            result.clear();
        }
    }
#else
    if (m_socketFd < 0) {
        return result;
    }
    
    quint32 opcode = 0;
    quint32 length = 0;
    
    // Read opcode
    if (read(m_socketFd, &opcode, 4) != 4) {
        return result;
    }
    
    // Read length
    if (read(m_socketFd, &length, 4) != 4) {
        return result;
    }
    
    // Read data
    if (length > 0) {
        result.resize(static_cast<int>(length));
        if (read(m_socketFd, result.data(), length) != static_cast<ssize_t>(length)) {
            result.clear();
        }
    }
#endif
    
    return result;
}

QString DiscordRPC::findDiscordPipe()
{
#ifdef Q_OS_WIN
    // Try pipes discord-ipc-0 through discord-ipc-9
    for (int i = 0; i < 10; ++i) {
        QString pipePath = QString("\\\\.\\pipe\\discord-ipc-%1").arg(i);
        std::wstring pipePathW = pipePath.toStdWString();
        
        HANDLE handle = CreateFileW(
            pipePathW.c_str(),
            GENERIC_READ | GENERIC_WRITE,
            0,
            nullptr,
            OPEN_EXISTING,
            0,
            nullptr
        );
        
        if (handle != INVALID_HANDLE_VALUE) {
            CloseHandle(handle);
            return pipePath;
        }
    }
#else
    // Try Unix sockets in common locations
    QStringList possiblePaths = {
        QStandardPaths::writableLocation(QStandardPaths::RuntimeLocation) + "/discord-ipc-0",
        QDir::homePath() + "/.config/discord-ipc-0",
        "/tmp/discord-ipc-0"
    };
    
    for (const QString &path : possiblePaths) {
        if (QFileInfo::exists(path)) {
            return path;
        }
    }
    
    // Try numbered sockets
    for (int i = 0; i < 10; ++i) {
        QString path = QStandardPaths::writableLocation(QStandardPaths::RuntimeLocation) + 
                       QString("/discord-ipc-%1").arg(i);
        if (QFileInfo::exists(path)) {
            return path;
        }
    }
#endif
    
    return QString();
}

QString DiscordRPC::formatTime(qint64 milliseconds)
{
    qint64 totalSeconds = milliseconds / 1000;
    qint64 minutes = totalSeconds / 60;
    qint64 seconds = totalSeconds % 60;
    return QString("%1:%2").arg(minutes, 2, 10, QChar('0')).arg(seconds, 2, 10, QChar('0'));
}

