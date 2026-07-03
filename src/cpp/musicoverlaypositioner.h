#ifndef MUSICOVERLAYPOSITIONER_H
#define MUSICOVERLAYPOSITIONER_H

#include <QElapsedTimer>
#include <QObject>
#include <QPoint>
#include <QPointF>
#include <QPointer>
#include <QRect>
#include <QVariantMap>

class QQuickWindow;

/// Positions the music overlay window. Drag uses global cursor + grab offset so QML DragHandler
/// translation is not used (that path oscillates when the parent window moves each frame).
class MusicOverlayPositioner : public QObject
{
    Q_OBJECT
public:
    explicit MusicOverlayPositioner(QObject *parent = nullptr);

    /// Place @a overlayWindow at the top-right of the work area on @a referenceWindow's screen
    /// (or the primary screen if needed). Uses QWindow::setPosition — reliable on Windows when QML x/y is ignored.
    Q_INVOKABLE void positionTopRight(QObject *overlayWindow, QObject *referenceWindow);

    /// Move @a overlayWindow to absolute position (@a x, @a y) via QWindow::setPosition.
    /// Uses floating point from QML to avoid double-quantizing; rounds once in C++ for setPosition(int).
    Q_INVOKABLE void setOverlayPosition(QObject *overlayWindow, double x, double y);

    /// Clamp @a overlayWindow top-left into the current screen's availableGeometry (call after restore / if off-screen).
    Q_INVOKABLE void clampOverlayToScreen(QObject *overlayWindow);

    /// During drag: nearest snap corner index (0–3: TL,TR,BL,BR) and strength 0..1 for UI preview.
    Q_INVOKABLE QVariantMap overlaySnapPreviewHint(QObject *overlayWindow) const;

    /// Begin drag: records global_cursor - window.position() so move follows QCursor::pos() without feedback.
    Q_INVOKABLE void overlayDragBegin(QObject *overlayWindow);
    /// Update target from cursor (call on centroid change while dragging).
    Q_INVOKABLE void overlayDragMove(QObject *overlayWindow);
    /// Lerp current position toward target (~60 Hz from QML Timer while dragging).
    Q_INVOKABLE void overlayDragTick(QObject *overlayWindow);
    /// End drag: may start corner snap animation or apply final cursor target.
    Q_INVOKABLE void overlayDragEnd(QObject *overlayWindow);

signals:
    /// Emitted when the overlay should persist position (after release with no snap, or when snap animation finishes).
    void overlayPositionSaveRequested();

private:
    bool nearestCornerMetrics(QQuickWindow *win, qreal *outBestDist2, int *outCornerIndex,
                              QPointF *outBestCorner, QRect *outWorkGeom = nullptr) const;
    QPointF nearestCornerForWindow(QQuickWindow *win, qreal snapDistance, bool *shouldSnap) const;
    QPointF clampWindowTopLeft(QQuickWindow *win, const QPointF &pos) const;

    QPointer<QQuickWindow> m_dragOverlay;
    QPointer<QQuickWindow> m_snapWindow;
    QPointer<QQuickWindow> m_inertiaWindow;
    bool m_dragActive = false;
    bool m_snapActive = false;
    bool m_inertiaActive = false;
    QPoint m_dragGrabOffsetGlobal;
    QPointF m_dragTargetPos;
    QPointF m_dragCurrentPos;
    QPointF m_snapTargetPos;
    QPointF m_releaseVelocity;
    QPointF m_lastCursorPos;
    QElapsedTimer m_dragVelocityTimer;
};

#endif
