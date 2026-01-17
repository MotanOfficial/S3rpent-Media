#ifndef MPVQMLITEM_H
#define MPVQMLITEM_H

#include <QQuickItem>
#include <QPointer>

class MPVQmlContainer;

// QQuickItem wrapper for embedding MPVQmlContainer (QWidget) in QML
// Uses QWidget::createWindowContainer() internally (Qt 6 way)
class MPVQmlItem : public QQuickItem
{
    Q_OBJECT
    Q_PROPERTY(QObject* player READ player WRITE setPlayer NOTIFY playerChanged)

public:
    explicit MPVQmlItem(QQuickItem *parent = nullptr);
    ~MPVQmlItem();

    QObject* player() const;
    void setPlayer(QObject *player);

signals:
    void playerChanged();

protected:
    void geometryChange(const QRectF &newGeometry, const QRectF &oldGeometry) override;
    void itemChange(ItemChange change, const ItemChangeData &value) override;

private:
    void updateWidgetGeometry();
    void createWidget();

    QPointer<MPVQmlContainer> m_container;
    QObject *m_player;
};

#endif // MPVQMLITEM_H

