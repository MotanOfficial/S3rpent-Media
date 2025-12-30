#ifndef DISCORDRPC_H
#define DISCORDRPC_H

#include <QObject>
#include <QString>
#include <QTimer>
#include <QJsonObject>
#include <QJsonDocument>
#include <QFileInfo>

#ifdef Q_OS_WIN
#include <windows.h>
#else
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>
#endif

class DiscordRPC : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool enabled READ enabled WRITE setEnabled NOTIFY enabledChanged)

public:
    explicit DiscordRPC(QObject *parent = nullptr);
    ~DiscordRPC();

    bool enabled() const { return m_enabled; }
    void setEnabled(bool enabled);

    // Update presence with audio player information
    Q_INVOKABLE void updatePresence(const QString &title, const QString &artist, 
                                     qint64 position, qint64 duration, 
                                     int playbackState, const QString &album = "", 
                                     const QString &coverArtUrl = "");

    // Clear presence
    Q_INVOKABLE void clearPresence();

signals:
    void enabledChanged();
    void connectionStatusChanged(bool connected);

private slots:
    void reconnectTimer();

private:
    bool connectToDiscord();
    void disconnectFromDiscord();
    bool sendHandshake();
    bool sendCommand(const QJsonObject &command);
    bool writeToPipe(const QByteArray &data);
    QByteArray readFromPipe();
    QString findDiscordPipe();
    QString formatTime(qint64 milliseconds);

    bool m_enabled;
    bool m_connected;
    QString m_minimalClientId;  // Minimal client_id required by Discord protocol
    
#ifdef Q_OS_WIN
    HANDLE m_pipeHandle;
#else
    int m_socketFd;
#endif

    QTimer *m_reconnectTimer;
    QJsonObject m_lastPresence;
    bool m_hasLastPresence;
};

#endif // DISCORDRPC_H

