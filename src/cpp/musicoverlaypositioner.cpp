#include "musicoverlaypositioner.h"

namespace {
// Set true only when debugging setOverlayPosition (not used for cursor-drag path).
constexpr bool kLogEveryOverlayMove = false;
// Overlay drag lerp: higher = snappier (try 0.12–0.35).
constexpr qreal kOverlayDragSmoothing = 0.18;
// Inset from screen edges for snap targets (try 12–24).
constexpr qreal kOverlayCornerPadding = 16.0;
// Release snap toward nearest screen corner (pixels).
constexpr qreal kOverlaySnapDistance = 120.0;
// Distance at which snap-corner preview reaches full strength (fade in from here inward).
constexpr qreal kOverlaySnapPreviewRange = kOverlaySnapDistance * 2.35;
// Snap animation lerp (typically slightly higher than drag for a tighter finish).
constexpr qreal kOverlaySnapSmoothing = 0.22;
// Post-release inertia (cursor-derived velocity, friction per ~16 ms tick).
constexpr qreal kOverlayInertiaFriction = 0.90;
constexpr qreal kOverlayMinInertiaSpeed = 0.35;
constexpr qreal kOverlayVelocityScale = 1.0;
constexpr bool kLogSnapPreviewHint = false;
}

#include <QCursor>
#include <QGuiApplication>
#include <QDebug>
#include <QPoint>
#include <QPointF>
#include <QQuickWindow>
#include <QScreen>
#include <QVariantMap>
#include <QtGlobal>
#include <cmath>
#include <limits>

MusicOverlayPositioner::MusicOverlayPositioner(QObject *parent)
    : QObject(parent)
{
}

bool MusicOverlayPositioner::nearestCornerMetrics(QQuickWindow *win, qreal *outBestDist2,
                                                  int *outCornerIndex, QPointF *outBestCorner,
                                                  QRect *outWorkGeom) const
{
    if (!win)
        return false;

    const QRect fg = win->frameGeometry();
    QScreen *screen = QGuiApplication::screenAt(fg.center());
    if (!screen)
        screen = win->screen();
    if (!screen)
        screen = QGuiApplication::primaryScreen();
    if (!screen)
        return false;

    const QRect g = screen->availableGeometry();

    const qreal x = win->x();
    const qreal y = win->y();
    const qreal w = win->width();
    const qreal h = win->height();

    const qreal pad = kOverlayCornerPadding;
    const QPointF corners[4] = {
        QPointF(g.left() + pad, g.top() + pad),
        QPointF(g.right() - w + 1 - pad, g.top() + pad),
        QPointF(g.left() + pad, g.bottom() - h + 1 - pad),
        QPointF(g.right() - w + 1 - pad, g.bottom() - h + 1 - pad),
    };

    QPointF best = corners[0];
    qreal bestDist2 = std::numeric_limits<qreal>::max();
    int bestIndex = 0;

    for (int i = 0; i < 4; ++i) {
        const QPointF &c = corners[i];
        const qreal dx = x - c.x();
        const qreal dy = y - c.y();
        const qreal d2 = dx * dx + dy * dy;
        if (d2 < bestDist2) {
            bestDist2 = d2;
            best = c;
            bestIndex = i;
        }
    }

    if (outBestDist2)
        *outBestDist2 = bestDist2;
    if (outCornerIndex)
        *outCornerIndex = bestIndex;
    if (outBestCorner)
        *outBestCorner = best;
    if (outWorkGeom)
        *outWorkGeom = g;
    return true;
}

QPointF MusicOverlayPositioner::nearestCornerForWindow(QQuickWindow *win, qreal snapDistance,
                                                       bool *shouldSnap) const
{
    if (shouldSnap)
        *shouldSnap = false;

    qreal bestDist2 = 0;
    QPointF best;
    if (!nearestCornerMetrics(win, &bestDist2, nullptr, &best, nullptr))
        return QPointF(win ? win->position() : QPoint());

    if (shouldSnap)
        *shouldSnap = std::sqrt(bestDist2) <= snapDistance;

    return best;
}

QVariantMap MusicOverlayPositioner::overlaySnapPreviewHint(QObject *overlayWindow) const
{
    QVariantMap m;
    m[QStringLiteral("strength")] = 0.0;
    m[QStringLiteral("corner")] = -1;

    auto *win = qobject_cast<QQuickWindow *>(overlayWindow);
    if (!win) {
        if (kLogSnapPreviewHint) {
            static int loggedNull = 0;
            if (!loggedNull++)
                qDebug() << "[SnapPreview] overlaySnapPreviewHint: window pointer null";
        }
        return m;
    }

    qreal bestDist2 = 0;
    int cornerIndex = -1;
    QRect gWork;
    if (!nearestCornerMetrics(win, &bestDist2, &cornerIndex, nullptr, &gWork)) {
        if (kLogSnapPreviewHint) {
            static int loggedMetricsFail = 0;
            if (!loggedMetricsFail++)
                qDebug() << "[SnapPreview] nearestCornerMetrics failed for" << win;
        }
        return m;
    }

    const qreal dist = std::sqrt(bestDist2);
    if (dist >= kOverlaySnapPreviewRange) {
        m[QStringLiteral("corner")] = -1;
        m[QStringLiteral("strength")] = 0.0;
        if (kLogSnapPreviewHint) {
            static int oorSn = 0;
            if (++oorSn <= 12)
                qDebug() << "[SnapPreview] out of range dist" << dist << "range" << kOverlaySnapPreviewRange
                         << "winPos" << win->position();
        }
        return m;
    }

    qreal t = 1.0 - dist / kOverlaySnapPreviewRange;
    t = qBound(0.0, t, 1.0);
    t = qMax(t, 0.08);

    m[QStringLiteral("corner")] = cornerIndex;
    m[QStringLiteral("strength")] = t;

    qreal gx = 0;
    qreal gy = 0;
    switch (cornerIndex) {
    case 0:
        gx = gWork.left();
        gy = gWork.top();
        break;
    case 1:
        gx = gWork.right();
        gy = gWork.top();
        break;
    case 2:
        gx = gWork.left();
        gy = gWork.bottom();
        break;
    case 3:
        gx = gWork.right();
        gy = gWork.bottom();
        break;
    default:
        break;
    }
    m[QStringLiteral("screenGlobalX")] = gx;
    m[QStringLiteral("screenGlobalY")] = gy;

    if (kLogSnapPreviewHint) {
        static int sn = 0;
        ++sn;
        if (sn <= 20 || (sn % 90) == 0)
            qDebug() << "[SnapPreview] hint #" << sn << "corner" << cornerIndex << "str" << t << "dist" << dist;
    }
    return m;
}

QPointF MusicOverlayPositioner::clampWindowTopLeft(QQuickWindow *win, const QPointF &pos) const
{
    if (!win)
        return pos;

    const qreal w = win->width();
    const qreal h = win->height();
    const QPoint center(qRound(pos.x() + w * 0.5), qRound(pos.y() + h * 0.5));

    QScreen *screen = QGuiApplication::screenAt(center);
    if (!screen) {
        const QRect fg = win->frameGeometry();
        screen = QGuiApplication::screenAt(fg.center());
    }
    if (!screen)
        screen = win->screen();
    if (!screen)
        screen = QGuiApplication::primaryScreen();
    if (!screen)
        return pos;

    const QRect g = screen->availableGeometry();
    const int wi = qMax(1, qRound(w));
    const int hi = qMax(1, qRound(h));

    const qreal minX = g.left();
    const qreal minY = g.top();
    qreal maxX = g.right() - wi + 1;
    qreal maxY = g.bottom() - hi + 1;

    if (maxX < minX)
        maxX = minX;
    if (maxY < minY)
        maxY = minY;

    return QPointF(qBound(minX, pos.x(), maxX), qBound(minY, pos.y(), maxY));
}

void MusicOverlayPositioner::clampOverlayToScreen(QObject *overlayWindow)
{
    auto *win = qobject_cast<QQuickWindow *>(overlayWindow);
    if (!win)
        return;
    const QPointF p = clampWindowTopLeft(win, QPointF(win->position()));
    win->setPosition(qRound(p.x()), qRound(p.y()));
}

void MusicOverlayPositioner::positionTopRight(QObject *overlayWindow, QObject *referenceWindow)
{
    auto *overlay = qobject_cast<QQuickWindow *>(overlayWindow);
    if (!overlay)
        return;

    QScreen *screen = nullptr;
    if (auto *ref = qobject_cast<QQuickWindow *>(referenceWindow))
        screen = ref->screen();
    if (!screen)
        screen = QGuiApplication::primaryScreen();
    if (!screen)
        return;

    const QRect geom = screen->availableGeometry();
    constexpr int margin = 12;
    const int w = qMax(1, overlay->width());
    const int x = geom.x() + geom.width() - w - margin;
    const int y = geom.y() + margin;
    overlay->setPosition(x, y);
}

void MusicOverlayPositioner::setOverlayPosition(QObject *overlayWindow, double x, double y)
{
    auto *overlay = qobject_cast<QQuickWindow *>(overlayWindow);
    if (!overlay)
        return;
    const QPointF clamped = clampWindowTopLeft(overlay, QPointF(x, y));
    const QPoint requested = clamped.toPoint();
    overlay->setPosition(requested);
    const QPoint actual = overlay->position();
    if (kLogEveryOverlayMove) {
        qDebug() << "[MusicOverlayPosition] requested" << requested << "actual" << actual
                 << "delta" << (actual - requested);
    } else if (requested != actual) {
        qDebug() << "[MusicOverlayPosition] requested" << requested << "actual" << actual
                 << "delta" << (actual - requested);
    }
}

void MusicOverlayPositioner::overlayDragBegin(QObject *overlayWindow)
{
    auto *win = qobject_cast<QQuickWindow *>(overlayWindow);
    if (!win)
        return;

    m_snapActive = false;
    m_snapWindow = nullptr;
    m_inertiaActive = false;
    m_inertiaWindow = nullptr;
    m_releaseVelocity = QPointF(0, 0);

    m_dragOverlay = win;
    m_dragActive = true;

    const QPoint global = QCursor::pos();
    QPoint winPos = win->position();
    const QPointF clampedPos = clampWindowTopLeft(win, QPointF(winPos));
    if (clampedPos != QPointF(winPos)) {
        winPos = QPoint(qRound(clampedPos.x()), qRound(clampedPos.y()));
        win->setPosition(winPos);
    }
    m_dragGrabOffsetGlobal = global - winPos;
    m_dragCurrentPos = clampedPos;
    m_dragTargetPos = clampedPos;

    m_lastCursorPos = QPointF(global);
    m_dragVelocityTimer.restart();
}

void MusicOverlayPositioner::overlayDragMove(QObject *overlayWindow)
{
    auto *win = qobject_cast<QQuickWindow *>(overlayWindow);
    if (!win || !m_dragActive || m_dragOverlay != win)
        return;

    const QPoint global = QCursor::pos();
    m_dragTargetPos = clampWindowTopLeft(win, QPointF(global - m_dragGrabOffsetGlobal));

    const qint64 elapsedMs = qMax<qint64>(1, m_dragVelocityTimer.restart());
    const QPointF delta = QPointF(global) - m_lastCursorPos;
    m_lastCursorPos = QPointF(global);

    const qreal dt = qreal(elapsedMs) / 16.0;
    m_releaseVelocity = (delta / dt) * kOverlayVelocityScale;
}

void MusicOverlayPositioner::overlayDragTick(QObject *overlayWindow)
{
    auto *win = qobject_cast<QQuickWindow *>(overlayWindow);
    if (!win)
        return;

    if (m_dragActive) {
        if (m_dragOverlay != win)
            return;

        m_dragCurrentPos.rx() += (m_dragTargetPos.x() - m_dragCurrentPos.x()) * kOverlayDragSmoothing;
        m_dragCurrentPos.ry() += (m_dragTargetPos.y() - m_dragCurrentPos.y()) * kOverlayDragSmoothing;

        m_dragCurrentPos = clampWindowTopLeft(win, m_dragCurrentPos);
        win->setPosition(qRound(m_dragCurrentPos.x()), qRound(m_dragCurrentPos.y()));
        return;
    }

    if (m_inertiaActive && m_inertiaWindow == win) {
        m_dragCurrentPos += m_releaseVelocity;
        m_releaseVelocity *= kOverlayInertiaFriction;

        m_dragCurrentPos = clampWindowTopLeft(win, m_dragCurrentPos);
        win->setPosition(qRound(m_dragCurrentPos.x()), qRound(m_dragCurrentPos.y()));

        bool shouldSnapInertia = false;
        const QPointF corner = nearestCornerForWindow(win, kOverlaySnapDistance, &shouldSnapInertia);
        if (shouldSnapInertia) {
            m_inertiaActive = false;
            m_inertiaWindow = nullptr;
            m_snapActive = true;
            m_snapTargetPos = corner;
            m_snapWindow = win;
            return;
        }

        const qreal speed2 = m_releaseVelocity.x() * m_releaseVelocity.x()
                + m_releaseVelocity.y() * m_releaseVelocity.y();

        if (speed2 < kOverlayMinInertiaSpeed * kOverlayMinInertiaSpeed) {
            m_inertiaActive = false;
            m_inertiaWindow = nullptr;
            emit overlayPositionSaveRequested();
        }
        return;
    }

    if (m_snapActive) {
        if (m_snapWindow != win)
            return;

        m_dragCurrentPos.rx() += (m_snapTargetPos.x() - m_dragCurrentPos.x()) * kOverlaySnapSmoothing;
        m_dragCurrentPos.ry() += (m_snapTargetPos.y() - m_dragCurrentPos.y()) * kOverlaySnapSmoothing;

        m_dragCurrentPos = clampWindowTopLeft(win, m_dragCurrentPos);
        win->setPosition(qRound(m_dragCurrentPos.x()), qRound(m_dragCurrentPos.y()));

        const qreal dx = m_snapTargetPos.x() - m_dragCurrentPos.x();
        const qreal dy = m_snapTargetPos.y() - m_dragCurrentPos.y();
        const qreal dist2 = dx * dx + dy * dy;

        if (dist2 < 1.5) {
            const QPointF snapped = clampWindowTopLeft(win, m_snapTargetPos);
            win->setPosition(qRound(snapped.x()), qRound(snapped.y()));
            m_dragCurrentPos = snapped;
            m_snapActive = false;
            m_snapWindow = nullptr;
            emit overlayPositionSaveRequested();
        }
    }
}

void MusicOverlayPositioner::overlayDragEnd(QObject *overlayWindow)
{
    auto *win = qobject_cast<QQuickWindow *>(overlayWindow);
    if (!win) {
        m_dragActive = false;
        m_dragOverlay = nullptr;
        return;
    }

    if (!m_dragActive || m_dragOverlay != win) {
        m_dragOverlay = nullptr;
        return;
    }

    m_dragActive = false;
    m_dragOverlay = nullptr;

    bool shouldSnap = false;
    const QPointF corner = nearestCornerForWindow(win, kOverlaySnapDistance, &shouldSnap);

    if (shouldSnap) {
        m_snapActive = true;
        m_snapTargetPos = corner;
        m_dragCurrentPos = QPointF(win->position());
        m_snapWindow = win;
    } else {
        m_snapActive = false;
        m_snapWindow = nullptr;
        m_inertiaActive = true;
        m_inertiaWindow = win;
        m_dragCurrentPos = QPointF(win->position());
    }
}
