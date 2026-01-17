#include "vlcvideoitem.h"
#include <QQuickWindow>
#include <QDebug>
#include <QtMultimedia/QVideoSink>

VLCVideoItem::VLCVideoItem(QQuickItem *parent)
    : QQuickItem(parent)
{
    // This item doesn't render anything itself - it just connects the player to a VideoOutput
    // The actual rendering is done by VideoOutput in QML
}

VLCVideoItem::~VLCVideoItem()
{
    // Cleanup is handled by QML parent
}

VLCVideoPlayer* VLCVideoItem::player() const
{
    return m_player;
}

void VLCVideoItem::setPlayer(VLCVideoPlayer* player)
{
    if (m_player == player) return;
    
    // Disconnect old player
    if (m_player) {
        m_player->setVideoSink(nullptr);
    }
    
    m_player = player;
    emit playerChanged();

    // Setup video sink connection
    if (m_player) {
        setupVideoSink();
    }
}

void VLCVideoItem::itemChange(ItemChange change, const ItemChangeData &value)
{
    if (change == ItemSceneChange) {
        if (value.window) {
            // Window is available, setup video sink
            setupVideoSink();
        }
    }
    QQuickItem::itemChange(change, value);
}

void VLCVideoItem::setupVideoSink()
{
    if (!m_player || !window()) return;

    // Find VideoOutput in parent hierarchy
    // The VideoOutput should be a sibling or child that provides videoSink
    QQuickItem* parent = this->parentItem();
    if (!parent) return;
    
    // Look for VideoOutput in children
    QQuickItem* videoOutput = nullptr;
    QList<QQuickItem*> children = parent->childItems();
    for (QQuickItem* child : children) {
        if (child->metaObject()->className() == QByteArray("QQuickVideoOutput")) {
            videoOutput = child;
            break;
        }
    }
    
    if (videoOutput) {
        // Get videoSink property from VideoOutput
        QVariant sinkVariant = videoOutput->property("videoSink");
        if (sinkVariant.isValid()) {
            QVideoSink* sink = qvariant_cast<QVideoSink*>(sinkVariant);
            if (sink) {
                m_player->setVideoSink(sink);
                qDebug() << "[VLCVideoItem] Connected to VideoOutput videoSink";
                return;
            }
        }
    }
    
    qWarning() << "[VLCVideoItem] VideoOutput not found - video will not render";
}
