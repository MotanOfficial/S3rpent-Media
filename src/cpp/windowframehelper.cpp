#include "windowframehelper.h"
#include <QQuickWindow>
#include <QDebug>
#include <QMutexLocker>

#ifdef Q_OS_WIN
#include <windows.h>
#include <windowsx.h>  // For GET_X_LPARAM, GET_Y_LPARAM macros
#include <dwmapi.h>
#pragma comment(lib, "dwmapi.lib")
#include <QPoint>
#endif

WindowFrameHelper::WindowFrameHelper(QObject *parent)
    : QObject(parent)
{
}

void WindowFrameHelper::setTitleBarHeight(int height)
{
    if (m_titleBarHeight != height) {
        m_titleBarHeight = height;
        emit titleBarHeightChanged();
    }
}

void WindowFrameHelper::setTitleBarVisible(bool visible)
{
    bool oldValue = m_titleBarVisible.load(std::memory_order_seq_cst);
    if (oldValue != visible) {
        qDebug() << "[WindowFrameHelper] titleBarVisible changed from" << oldValue << "to" << visible;
        // CRITICAL: Use atomic store with sequential consistency to ensure the write is immediately visible to all threads
        // The hit-test runs on Windows message thread, property updates on Qt event loop
        // Sequential consistency provides the strongest guarantees - all threads see operations in the same order
        m_titleBarVisible.store(visible, std::memory_order_seq_cst);
        // Force a full memory barrier to ensure the store is visible to all threads immediately
        std::atomic_thread_fence(std::memory_order_seq_cst);
        // Verify the store completed
        bool verifyValue = m_titleBarVisible.load(std::memory_order_seq_cst);
        if (verifyValue != visible) {
            qWarning() << "[WindowFrameHelper] WARNING: Atomic store verification failed! Expected" << visible << "but got" << verifyValue;
        }
        emit titleBarVisibleChanged();
    }
}

bool WindowFrameHelper::hotZoneActive() const
{
    return m_hotZoneActive.load(std::memory_order_seq_cst);
}

void WindowFrameHelper::setHotZoneActive(bool active)
{
    bool oldValue = m_hotZoneActive.load(std::memory_order_seq_cst);
    if (oldValue != active) {
        qDebug() << "[WindowFrameHelper] hotZoneActive changed from" << oldValue << "to" << active;
        // CRITICAL: Use atomic store with sequential consistency to ensure the write is immediately visible to all threads
        // The hit-test runs on Windows message thread, property updates on Qt event loop
        m_hotZoneActive.store(active, std::memory_order_seq_cst);
        // Force a full memory barrier to ensure the store is visible to all threads immediately
        std::atomic_thread_fence(std::memory_order_seq_cst);
        emit hotZoneActiveChanged();
    }
}

int WindowFrameHelper::buttonAreaWidth() const
{
    return m_buttonAreaWidth.load(std::memory_order_seq_cst);
}

void WindowFrameHelper::setButtonAreaWidth(int width)
{
    int oldValue = m_buttonAreaWidth.load(std::memory_order_seq_cst);
    if (oldValue != width) {
        qDebug() << "[WindowFrameHelper] buttonAreaWidth changed from" << oldValue << "to" << width;
        m_buttonAreaWidth.store(width, std::memory_order_seq_cst);
        emit buttonAreaWidthChanged();
    }
}

void WindowFrameHelper::setupFramelessWindow(QQuickWindow *window)
{
    if (!window) {
        qWarning() << "[WindowFrameHelper] setupFramelessWindow: window is null";
        return;
    }
    
    m_window = window;
    
#ifdef Q_OS_WIN
    // Note: Window flags and color should be set in QML, not here
    // This function only extends the DWM frame
    
    // Wait for window to be created, then extend frame and enable resize
    if (window->winId()) {
        void *hwnd = reinterpret_cast<void*>(window->winId());
        extendFrameIntoClientArea(hwnd);
        enableResize(hwnd);
    } else {
        // If window ID not ready, connect to afterRendering
        connect(window, &QQuickWindow::afterRendering, this, [this, window]() {
            if (window->winId()) {
                void *hwnd = reinterpret_cast<void*>(window->winId());
                extendFrameIntoClientArea(hwnd);
                enableResize(hwnd);
                disconnect(window, &QQuickWindow::afterRendering, this, nullptr);
            }
        }, Qt::SingleShotConnection);
    }
    
    qDebug() << "[WindowFrameHelper] Frameless window setup complete";
#else
    qWarning() << "[WindowFrameHelper] Frameless window setup only supported on Windows";
#endif
}

void WindowFrameHelper::startSystemMove()
{
#ifdef Q_OS_WIN
    if (!m_window || !m_window->winId()) {
        qWarning() << "[WindowFrameHelper] startSystemMove: window or window ID is null";
        return;
    }
    
    HWND hwnd = reinterpret_cast<HWND>(m_window->winId());
    
    // Release any existing capture (in case QML has it)
    ReleaseCapture();
    
    // Send WM_NCLBUTTONDOWN with HTCAPTION to start system drag
    // This tells Windows to start dragging the window, even though
    // the hit-test returned HTCLIENT. This is the key trick that allows
    // QML to own hover while Windows handles drag on demand.
    SendMessage(hwnd, WM_NCLBUTTONDOWN, HTCAPTION, 0);
    
    qDebug() << "[WindowFrameHelper] Started system window drag";
#else
    qWarning() << "[WindowFrameHelper] startSystemMove only supported on Windows";
#endif
}

bool WindowFrameHelper::nativeEventFilter(const QByteArray &eventType, void *message, qintptr *result)
{
#ifdef Q_OS_WIN
    if (eventType != "windows_generic_MSG") {
        return false;
    }
    
    MSG *msg = static_cast<MSG *>(message);
    
    // Only handle events for our window
    if (m_window && msg->hwnd != reinterpret_cast<HWND>(m_window->winId())) {
        return false;
    }
    
    if (msg->message == WM_NCHITTEST) {
        QPoint globalPos(GET_X_LPARAM(msg->lParam), GET_Y_LPARAM(msg->lParam));
        qintptr hit = handleNCHitTest(msg, globalPos);
        if (hit != 0) {
            *result = hit;
            return true;  // We handled it
        }
        // Return false to let Windows/Qt handle it
        return false;
    }
    
    return false;
#else
    Q_UNUSED(eventType)
    Q_UNUSED(message)
    Q_UNUSED(result)
    return false;
#endif
}

#ifdef Q_OS_WIN
void WindowFrameHelper::extendFrameIntoClientArea(void *hwnd)
{
    HWND hwndWin = static_cast<HWND>(hwnd);
    
    // Tell DWM the window still has a frame (keeps snapping, animations, etc.)
    // Using -1 for all margins extends the frame into the entire client area
    MARGINS margins = { -1, -1, -1, -1 };
    HRESULT hr = DwmExtendFrameIntoClientArea(hwndWin, &margins);
    
    if (SUCCEEDED(hr)) {
        qDebug() << "[WindowFrameHelper] DWM frame extended successfully - snapping and animations enabled";
    } else {
        qWarning() << "[WindowFrameHelper] Failed to extend DWM frame:" << hr;
    }
}

void WindowFrameHelper::enableResize(void *hwnd)
{
    HWND hwndWin = static_cast<HWND>(hwnd);
    
    // Restore native resize styles that Qt removes with FramelessWindowHint
    LONG style = GetWindowLong(hwndWin, GWL_STYLE);
    style |= WS_THICKFRAME | WS_MAXIMIZEBOX | WS_MINIMIZEBOX;
    SetWindowLong(hwndWin, GWL_STYLE, style);
    
    LONG exStyle = GetWindowLong(hwndWin, GWL_EXSTYLE);
    exStyle |= WS_EX_APPWINDOW;
    SetWindowLong(hwndWin, GWL_EXSTYLE, exStyle);
    
    // Tell Windows the frame changed (required after style changes)
    SetWindowPos(
        hwndWin, nullptr,
        0, 0, 0, 0,
        SWP_FRAMECHANGED | SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE
    );
    
    qDebug() << "[WindowFrameHelper] Resize styles restored (WS_THICKFRAME)";
}

qintptr WindowFrameHelper::handleNCHitTest(void *msg, const QPoint &globalPos)
{
    MSG *windowsMsg = static_cast<MSG *>(msg);
    HWND hwnd = windowsMsg->hwnd;
    
    // Get window border size
    const LONG border = GetSystemMetrics(SM_CXFRAME) + GetSystemMetrics(SM_CXPADDEDBORDER);
    
    // Get window rectangle
    RECT rect;
    GetWindowRect(hwnd, &rect);
    
    // Handle maximized window padding (Windows adds padding when maximized)
    if (IsZoomed(hwnd)) {
        const int padding = GetSystemMetrics(SM_CXPADDEDBORDER);
        rect.top += padding;
        rect.left += padding;
        rect.right -= padding;
        rect.bottom -= padding;
    }
    
    const LONG x = globalPos.x();
    const LONG y = globalPos.y();
    
    // --- Resize borders ---
    // Left edge
    if (x < rect.left + border) {
        if (y < rect.top + border) {
            return HTTOPLEFT;
        }
        if (y > rect.bottom - border) {
            return HTBOTTOMLEFT;
        }
        return HTLEFT;
    }
    
    // Right edge
    if (x > rect.right - border) {
        if (y < rect.top + border) {
            return HTTOPRIGHT;
        }
        if (y > rect.bottom - border) {
            return HTBOTTOMRIGHT;
        }
        return HTRIGHT;
    }
    
    // Top edge
    if (y < rect.top + border) {
        return HTTOP;
    }
    
    // Bottom edge
    if (y > rect.bottom - border) {
        return HTBOTTOM;
    }
    
    // NEW ARCHITECTURE: Return HTCLIENT everywhere (except resize borders)
    // QML handles all hover/click detection, and manually starts Windows drag
    // when user actually presses and moves. This eliminates pixel loss and
    // race conditions between QML hover and Windows drag capture.
    //
    // Benefits:
    // - 100% of titlebar available for hover/auto-hide
    // - No static zones that fight each other
    // - Simpler mental model: hover=QML, drag=Windows (on demand)
    // - Works perfectly with animations and dynamic layouts
    
    // Everything else is client area - QML owns it completely
    return HTCLIENT;
}
#endif

