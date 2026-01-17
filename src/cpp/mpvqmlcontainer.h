#ifndef MPVQMLCONTAINER_H
#define MPVQMLCONTAINER_H

#include <QWidget>
#include <QVBoxLayout>

class MPVGlWidget;
// Include full definition for Q_PROPERTY meta type registration
#include "mpvvideoplayer.h"

// QWidget container for embedding mpv widget in QML
// This widget can be embedded in QML using QWidget::createWindowContainer()
// This is the bridge between QML and the native OpenGL mpv widget (mpc-qt style)
class MPVQmlContainer : public QWidget
{
    Q_OBJECT
    Q_PROPERTY(MPVVideoPlayer* player READ player WRITE setPlayer NOTIFY playerChanged)

public:
    explicit MPVQmlContainer(QWidget *parent = nullptr);
    ~MPVQmlContainer();

    MPVVideoPlayer* player() const { return m_player; }
    void setPlayer(MPVVideoPlayer *player);

    // Get the underlying mpv widget (for advanced use cases)
    MPVGlWidget* mpvWidget() const { return m_mpvWidget; }

signals:
    void playerChanged();

private:
    MPVVideoPlayer *m_player;
    MPVGlWidget *m_mpvWidget;
    QVBoxLayout *m_layout;
};

#endif // MPVQMLCONTAINER_H

