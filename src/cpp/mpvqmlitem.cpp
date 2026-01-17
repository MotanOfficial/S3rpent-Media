#include "mpvqmlitem.h"
#include "mpvqmlcontainer.h"
#include "mpvvideoplayer.h"
#include <QWidget>
#include <QWindow>
#include <QDebug>
#include <QSizePolicy>
#include <QPalette>

MPVQmlItem::MPVQmlItem(QQuickItem *parent)
    : QQuickItem(parent)
    , m_container(nullptr)
    , m_player(nullptr)
{
    setFlag(ItemHasContents, true);
    qDebug() << "[MPVQmlItem] Created";
}

MPVQmlItem::~MPVQmlItem()
{
    if (m_container) {
        m_container->deleteLater();
    }
    qDebug() << "[MPVQmlItem] Destroyed";
}

QObject* MPVQmlItem::player() const
{
    return m_player;
}

void MPVQmlItem::setPlayer(QObject *player)
{
    if (m_player == player) {
        return;
    }

    m_player = player;

    if (m_container) {
        MPVVideoPlayer *mpvPlayer = qobject_cast<MPVVideoPlayer*>(player);
        m_container->setPlayer(mpvPlayer);
    }

    emit playerChanged();
    qDebug() << "[MPVQmlItem] Player set";
}

void MPVQmlItem::geometryChange(const QRectF &newGeometry, const QRectF &oldGeometry)
{
    QQuickItem::geometryChange(newGeometry, oldGeometry);
    
    // Update widget geometry when QML item size or position changes
    if (newGeometry.size() != oldGeometry.size() || newGeometry.topLeft() != oldGeometry.topLeft()) {
        updateWidgetGeometry();
    }
}

void MPVQmlItem::itemChange(ItemChange change, const ItemChangeData &value)
{
    if (change == ItemSceneChange) {
        if (value.window) {
            createWidget();
            // Track window position and state changes to keep widget aligned
            connect(value.window, &QWindow::xChanged, this, &MPVQmlItem::updateWidgetGeometry);
            connect(value.window, &QWindow::yChanged, this, &MPVQmlItem::updateWidgetGeometry);
            // Track window visibility state changes (maximized/fullscreen)
            connect(value.window, &QWindow::visibilityChanged, this, &MPVQmlItem::updateWidgetGeometry);
        } else if (m_container) {
            if (window()) {
                disconnect(window(), &QWindow::xChanged, this, &MPVQmlItem::updateWidgetGeometry);
                disconnect(window(), &QWindow::yChanged, this, &MPVQmlItem::updateWidgetGeometry);
                disconnect(window(), &QWindow::visibilityChanged, this, &MPVQmlItem::updateWidgetGeometry);
            }
            m_container->deleteLater();
            m_container = nullptr;
        }
    }
    QQuickItem::itemChange(change, value);
}

void MPVQmlItem::createWidget()
{
    // TEMPORARILY DISABLED: Don't create widget for testing
    qDebug() << "[MPVQmlItem] createWidget() called but DISABLED for testing white border issue";
    return;
    
    /*
    if (m_container || !window()) {
        return;
    }

    // Create widget container
    m_container = new MPVQmlContainer();
    
    // In Qt 6, embedding QWidget in QML is complex
    // We'll create the widget as a child window positioned over the QML item
    QWindow *qmlWindow = window();
    if (!qmlWindow) {
        qWarning() << "[MPVQmlItem] No window available";
        delete m_container;
        m_container = nullptr;
        return;
    }
    
    // Make widget a native window child of the QML window
    // Use proper flags for embedded child window (not resizable, frameless)
    m_container->setParent(nullptr);
    m_container->setWindowFlags(Qt::FramelessWindowHint | Qt::Window | Qt::WindowStaysOnTopHint);
    m_container->setAttribute(Qt::WA_ShowWithoutActivating, true);
    
    // CRITICAL: Set black background to prevent white border in maximized/fullscreen
    m_container->setStyleSheet("background-color: black;");
    m_container->setAutoFillBackground(true);
    QPalette palette = m_container->palette();
    palette.setColor(QPalette::Window, Qt::black);
    m_container->setPalette(palette);
    
    // Make window non-resizable
    m_container->setFixedSize(size().toSize());
    m_container->setSizePolicy(QSizePolicy::Fixed, QSizePolicy::Fixed);
    
    // Force window creation and parent it
    m_container->winId();
    QWindow *widgetWindow = m_container->windowHandle();
    if (widgetWindow) {
        widgetWindow->setParent(qmlWindow);
        // Disable resizing at the window level
        widgetWindow->setFlags(widgetWindow->flags() & ~Qt::WindowMaximizeButtonHint);
    }
    
    // Position and show the widget
    updateWidgetGeometry();
    m_container->show();

    // Connect player if already set
    if (m_player) {
        MPVVideoPlayer *mpvPlayer = qobject_cast<MPVVideoPlayer*>(m_player);
        if (mpvPlayer) {
            m_container->setPlayer(mpvPlayer);
        }
    }

    qDebug() << "[MPVQmlItem] Widget container created and embedded";
    */
}

void MPVQmlItem::updateWidgetGeometry()
{
    if (!m_container || !window()) {
        return;
    }

    // Since the QML item uses anchors.fill: parent, it should be at (0,0) relative to window content
    // For child windows, position is relative to parent window's client area
    // Use the item's scene position which accounts for all parent transforms
    QPointF itemScenePos = mapToScene(QPointF(0, 0));
    QPoint widgetPos = itemScenePos.toPoint();
    
    // Set widget size to match QML item size exactly
    QSize itemSize = size().toSize();
    m_container->setFixedSize(itemSize);
    m_container->setSizePolicy(QSizePolicy::Fixed, QSizePolicy::Fixed);
    
    // Position widget window relative to parent window (child windows use parent-relative coordinates)
    m_container->move(widgetPos);
    
    // CRITICAL: Ensure widget background stays black (especially important when maximized/fullscreen)
    // Re-apply black background in case it was reset
    m_container->setStyleSheet("background-color: black;");
    QPalette palette = m_container->palette();
    palette.setColor(QPalette::Window, Qt::black);
    m_container->setPalette(palette);
    
    qDebug() << "[MPVQmlItem] Updated widget geometry - itemScenePos:" << itemScenePos << "widgetPos:" << widgetPos << "size:" << itemSize;
}

