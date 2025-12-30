#ifndef SINGLEINSTANCEMANAGER_H
#define SINGLEINSTANCEMANAGER_H

#include <QObject>
#include <QLocalServer>
#include <QLocalSocket>
#include <QSharedMemory>
#include <QSystemTrayIcon>
#include <QApplication>
#include <QWindow>

class SingleInstanceManager : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool isPrimaryInstance READ isPrimaryInstance NOTIFY isPrimaryInstanceChanged)

public:
    explicit SingleInstanceManager(QObject *parent = nullptr);
    ~SingleInstanceManager();

    bool isPrimaryInstance() const { return m_isPrimaryInstance; }
    bool tryActivateExistingInstance(const QString &filePath = QString());
    void updateTrayIcon();  // Update tray icon after app icon is set

signals:
    void isPrimaryInstanceChanged();
    void fileOpenRequested(const QString &filePath);
    void showRequested();

private slots:
    void handleNewConnection();
    void readSocketData();

private:
    bool m_isPrimaryInstance;
    QLocalServer *m_localServer;
    QSharedMemory *m_sharedMemory;
    QString m_serverName;
    QSystemTrayIcon *m_trayIcon;
    QList<QWindow*> m_windows;

    bool createSingleInstanceLock();
    void releaseSingleInstanceLock();
    void setupSystemTray();
};

#endif // SINGLEINSTANCEMANAGER_H

