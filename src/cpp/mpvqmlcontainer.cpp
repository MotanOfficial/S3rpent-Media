#include "mpvqmlcontainer.h"
#include "mpvglwidget.h"
#include "mpvvideoplayer.h"
#include <QDebug>
#include <QPalette>

MPVQmlContainer::MPVQmlContainer(QWidget *parent)
    : QWidget(parent)
    , m_player(nullptr)
    , m_mpvWidget(nullptr)
    , m_layout(nullptr)
{
    // CRITICAL: Set black background to prevent white border in maximized/fullscreen
    setStyleSheet("background-color: black;");
    setAutoFillBackground(true);
    QPalette palette = this->palette();
    palette.setColor(QPalette::Window, Qt::black);
    setPalette(palette);
    
    // Create layout with no margins (video should fill entire container)
    m_layout = new QVBoxLayout(this);
    m_layout->setContentsMargins(0, 0, 0, 0);
    m_layout->setSpacing(0);

    // TEMPORARILY DISABLED: Create mpv widget (will be connected to player later)
    // m_mpvWidget = new MPVGlWidget(nullptr, this);
    // m_layout->addWidget(m_mpvWidget);
    m_mpvWidget = nullptr;  // Disabled for testing

    qDebug() << "[MPVQmlContainer] Container created with black background (MPVGlWidget DISABLED for testing)";
}

MPVQmlContainer::~MPVQmlContainer()
{
    qDebug() << "[MPVQmlContainer] Container destroyed";
}

void MPVQmlContainer::setPlayer(MPVVideoPlayer *player)
{
    if (m_player == player) {
        return;
    }

    m_player = player;

    // TEMPORARILY DISABLED: Set player on widget
    // if (m_mpvWidget) {
    //     m_mpvWidget->setPlayer(player);
    // }

    emit playerChanged();
    qDebug() << "[MPVQmlContainer] Player set (MPVGlWidget DISABLED for testing)";
}

