#ifndef VLCVIDEOITEM_H
#define VLCVIDEOITEM_H

#include <QQuickItem>
#include <QPointer>
#include "vlcvideoplayer.h"

class VLCVideoItem : public QQuickItem
{
    Q_OBJECT
    Q_PROPERTY(VLCVideoPlayer* player READ player WRITE setPlayer NOTIFY playerChanged)

public:
    explicit VLCVideoItem(QQuickItem *parent = nullptr);
    ~VLCVideoItem();

    VLCVideoPlayer* player() const;
    void setPlayer(VLCVideoPlayer* player);

signals:
    void playerChanged();

protected:
    void itemChange(ItemChange change, const ItemChangeData &value) override;

private:
    void setupVideoSink();

    VLCVideoPlayer* m_player = nullptr;
};

#endif // VLCVIDEOITEM_H
