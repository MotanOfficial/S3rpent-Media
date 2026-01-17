#ifndef WINDOWFRAMEHELPER_H
#define WINDOWFRAMEHELPER_H

#include <QObject>
#include <QQuickWindow>
#include <QPoint>
#include <QAbstractNativeEventFilter>
#include <QMutex>
#include <atomic>

class WindowFrameHelper : public QObject, public QAbstractNativeEventFilter
{
    Q_OBJECT
    Q_PROPERTY(int titleBarHeight READ titleBarHeight WRITE setTitleBarHeight NOTIFY titleBarHeightChanged)
    Q_PROPERTY(bool titleBarVisible READ titleBarVisible WRITE setTitleBarVisible NOTIFY titleBarVisibleChanged)
    Q_PROPERTY(bool hotZoneActive READ hotZoneActive WRITE setHotZoneActive NOTIFY hotZoneActiveChanged)
    Q_PROPERTY(int buttonAreaWidth READ buttonAreaWidth WRITE setButtonAreaWidth NOTIFY buttonAreaWidthChanged)
    Q_PROPERTY(bool fullscreen READ fullscreen WRITE setFullscreen NOTIFY fullscreenChanged)

public:
    explicit WindowFrameHelper(QObject *parent = nullptr);
    
    int titleBarHeight() const { return m_titleBarHeight; }
    void setTitleBarHeight(int height);
    
    bool titleBarVisible() const { return m_titleBarVisible.load(std::memory_order_seq_cst); }
    void setTitleBarVisible(bool visible);
    
    bool hotZoneActive() const;
    void setHotZoneActive(bool active);
    
    int buttonAreaWidth() const;
    void setButtonAreaWidth(int width);
    
    bool fullscreen() const;
    void setFullscreen(bool fullscreen);
    
    // Initialize frameless window with DWM support
    Q_INVOKABLE void setupFramelessWindow(QQuickWindow *window);
    
    // Start system window drag manually (called from QML when user starts dragging)
    Q_INVOKABLE void startSystemMove();
    
    // Toggle native Windows maximize/restore
    Q_INVOKABLE void toggleMaximize();
    
    // Handle native Windows events (QAbstractNativeEventFilter interface)
    bool nativeEventFilter(const QByteArray &eventType, void *message, qintptr *result) override;

signals:
    void titleBarHeightChanged();
    void titleBarVisibleChanged();
    void hotZoneActiveChanged();
    void buttonAreaWidthChanged();
    void fullscreenChanged();

private:
    int m_titleBarHeight = 50;  // Default title bar height
    std::atomic<bool> m_titleBarVisible{true};  // Default to visible - atomic for thread-safe access
    std::atomic<bool> m_hotZoneActive{false};  // Hot zone active state - directly controlled by QML
    std::atomic<int> m_buttonAreaWidth{280};  // Button area width - dynamically set from QML
    std::atomic<bool> m_fullscreen{false};  // Fullscreen state - prevents resizing when true
    QQuickWindow *m_window = nullptr;
    
    // Windows-specific helpers
#ifdef Q_OS_WIN
    void extendFrameIntoClientArea(void *hwnd);
    void removeFrameExtension(void *hwnd);  // Remove DWM frame extension (for fullscreen)
    void enableResize(void *hwnd);
    qintptr handleNCHitTest(void *msg, const QPoint &globalPos);
#endif
};

#endif // WINDOWFRAMEHELPER_H

