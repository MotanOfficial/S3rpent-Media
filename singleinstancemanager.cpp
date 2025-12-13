#include "singleinstancemanager.h"
#include <QDebug>
#include <QMessageBox>
#include <QDir>
#include <QStandardPaths>
#include <QFileInfo>
#include <QMenu>
#include <QStyle>

SingleInstanceManager::SingleInstanceManager(QObject *parent)
    : QObject(parent)
    , m_isPrimaryInstance(false)
    , m_localServer(nullptr)
    , m_sharedMemory(nullptr)
    , m_serverName("s3rp3nt_media_single_instance")
    , m_trayIcon(nullptr)
{
    m_isPrimaryInstance = createSingleInstanceLock();
    
    if (m_isPrimaryInstance) {
        // This is the primary instance - set up server
        m_localServer = new QLocalServer(this);
        
        // Remove any existing server (in case of crash)
        QLocalServer::removeServer(m_serverName);
        
        if (m_localServer->listen(m_serverName)) {
            connect(m_localServer, &QLocalServer::newConnection, this, &SingleInstanceManager::handleNewConnection);
        } else {
            qWarning() << "Failed to start local server:" << m_localServer->errorString();
        }
        
        setupSystemTray();
    }
    
    emit isPrimaryInstanceChanged();
}

SingleInstanceManager::~SingleInstanceManager()
{
    if (m_isPrimaryInstance) {
        releaseSingleInstanceLock();
        if (m_localServer) {
            QLocalServer::removeServer(m_serverName);
        }
    }
}

bool SingleInstanceManager::createSingleInstanceLock()
{
    m_sharedMemory = new QSharedMemory(m_serverName, this);
    
    // Try to attach - if successful, another instance exists
    if (m_sharedMemory->attach()) {
        m_sharedMemory->detach();
        delete m_sharedMemory;
        m_sharedMemory = nullptr;
        return false; // Not primary instance
    }
    
    // Create the shared memory segment
    if (!m_sharedMemory->create(1)) {
        qWarning() << "Failed to create shared memory:" << m_sharedMemory->errorString();
        delete m_sharedMemory;
        m_sharedMemory = nullptr;
        return false;
    }
    
    return true; // Primary instance
}

void SingleInstanceManager::releaseSingleInstanceLock()
{
    if (m_sharedMemory) {
        m_sharedMemory->detach();
        delete m_sharedMemory;
        m_sharedMemory = nullptr;
    }
}

bool SingleInstanceManager::tryActivateExistingInstance(const QString &filePath)
{
    if (m_isPrimaryInstance) {
        return false; // We are the primary instance
    }
    
    // Connect to the primary instance's server
    QLocalSocket socket;
    socket.connectToServer(m_serverName);
    
    if (!socket.waitForConnected(1000)) {
        return false; // Couldn't connect
    }
    
    // Send file path if provided
    if (!filePath.isEmpty()) {
        QByteArray data = filePath.toUtf8();
        socket.write(data);
        socket.flush();
        socket.waitForBytesWritten(1000);
    } else {
        // Just send show request
        socket.write("SHOW");
        socket.flush();
        socket.waitForBytesWritten(1000);
    }
    
    socket.disconnectFromServer();
    return true;
}

void SingleInstanceManager::handleNewConnection()
{
    QLocalSocket *socket = m_localServer->nextPendingConnection();
    if (socket) {
        connect(socket, &QLocalSocket::readyRead, this, &SingleInstanceManager::readSocketData);
        connect(socket, &QLocalSocket::disconnected, socket, &QLocalSocket::deleteLater);
    }
}

void SingleInstanceManager::readSocketData()
{
    QLocalSocket *socket = qobject_cast<QLocalSocket*>(sender());
    if (!socket) return;
    
    QByteArray data = socket->readAll();
    QString message = QString::fromUtf8(data);
    
    if (message == "SHOW") {
        emit showRequested();
    } else {
        // Assume it's a file path
        QFileInfo fileInfo(message);
        if (fileInfo.exists()) {
            emit fileOpenRequested(message);
        }
    }
}

void SingleInstanceManager::setupSystemTray()
{
    if (!QSystemTrayIcon::isSystemTrayAvailable()) {
        qWarning() << "System tray is not available";
        return;
    }
    
    m_trayIcon = new QSystemTrayIcon(this);
    
    // Try to use app icon, fallback to default
    QIcon icon = QApplication::windowIcon();
    if (icon.isNull()) {
        icon = QIcon(":/icon.png");
    }
    if (icon.isNull()) {
        icon = QIcon(":/icon.ico");
    }
    if (icon.isNull()) {
        icon = QApplication::style()->standardIcon(QStyle::SP_ComputerIcon);
    }
    m_trayIcon->setIcon(icon);
    m_trayIcon->setToolTip("s3rp3nt media");
    
    // Create tray menu
    QMenu *trayMenu = new QMenu();
    QAction *showAction = trayMenu->addAction("Show");
    QAction *quitAction = trayMenu->addAction("Quit");
    
    connect(showAction, &QAction::triggered, this, &SingleInstanceManager::showRequested);
    connect(quitAction, &QAction::triggered, qApp, &QApplication::quit);
    connect(m_trayIcon, &QSystemTrayIcon::activated, this, [this](QSystemTrayIcon::ActivationReason reason) {
        if (reason == QSystemTrayIcon::DoubleClick || reason == QSystemTrayIcon::Trigger) {
            emit showRequested();
        }
    });
    
    m_trayIcon->setContextMenu(trayMenu);
    
    // Show the tray icon - this is critical for keeping the app alive
    m_trayIcon->show();
    
    // Verify the tray icon is visible
    if (!m_trayIcon->isVisible()) {
        qWarning() << "System tray icon is not visible";
    } else {
        qDebug() << "System tray icon shown successfully";
    }
}

