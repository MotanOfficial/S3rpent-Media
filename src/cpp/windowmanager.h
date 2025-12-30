#ifndef WINDOWMANAGER_H
#define WINDOWMANAGER_H

#include <QObject>
#include <QUrl>
#include <QHash>
#include <QList>
#include <QPointer>
#include <QQmlContext>
#include <QQuickWindow>

class QQmlApplicationEngine;
class ColorUtils;
class SingleInstanceManager;

// Window pool structure for reusing windows (reduces RAM churn)
struct ViewerWindow {
    QPointer<QObject> window;  // Use QPointer for automatic nullification
    QQmlContext* context;      // Owned by this struct (except main window)
    bool busy;                 // true if window is currently showing an image
    bool isMainWindow;         // true if this is the main application window
    bool ownsContext;          // true if we own the context (false for main window)
    
    ViewerWindow() : window(nullptr), context(nullptr), busy(false), isMainWindow(false), ownsContext(false) {}
};

class WindowManager : public QObject
{
    Q_OBJECT

public:
    explicit WindowManager(QObject *parent = nullptr);
    ~WindowManager();

    // Initialize with required dependencies
    void setEngine(QQmlApplicationEngine *engine);
    void setColorUtils(ColorUtils *colorUtils);
    void setInstanceManager(SingleInstanceManager *instanceManager);
    void setDebugConsole(QObject *debugConsole);

    // Main window management
    void addMainWindow(QObject *mainWindow);
    QQuickWindow* createNewWindow(const QUrl &fileUrl = QUrl());
    
    // Window pool queries
    int getSecondaryWindowCount() const { return m_secondaryWindowCount; }
    int getTotalWindowCount() const { return m_windowPoolStorage.size(); }
    int getMaxPoolSize() const { return MAX_POOL_SIZE; }

    // Cleanup
    void cleanup();

private:
    // Window pool data
    QHash<QObject*, int> m_windowPool;  // Maps window pointer to index in storage
    QList<ViewerWindow> m_windowPoolStorage;  // Actual storage (reserved capacity)
    int m_secondaryWindowCount;  // Cached count for performance
    static const int MAX_POOL_SIZE = 5;  // Maximum number of windows in pool (excluding main window)

    // Dependencies
    QQmlApplicationEngine *m_engine;
    ColorUtils *m_colorUtils;
    SingleInstanceManager *m_instanceManager;
    QObject *m_debugConsole;

    // Helper functions
    ViewerWindow* getWindowFromHash(QObject* window);
    ViewerWindow* findReusableWindow();
    ViewerWindow* findMainWindow();
    ViewerWindow* findHiddenMainWindow();
    ViewerWindow* findOldestSecondaryWindow();
    void logToDebugConsole(const QString &message, const QString &type = "info");
};

#endif // WINDOWMANAGER_H


