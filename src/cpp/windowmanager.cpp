#include "windowmanager.h"
#include <QQmlApplicationEngine>
#include <QQmlComponent>
#include <QQuickWindow>
#include <QTimer>
#include <QDebug>
#include <QVariant>
#include <QVariantMap>
#include <QMetaObject>

#include "colorutils.h"
#include "singleinstancemanager.h"

WindowManager::WindowManager(QObject *parent)
    : QObject(parent)
    , m_secondaryWindowCount(0)
    , m_engine(nullptr)
    , m_colorUtils(nullptr)
    , m_instanceManager(nullptr)
    , m_debugConsole(nullptr)
{
    // Reserve capacity to avoid reallocations
    m_windowPoolStorage.reserve(MAX_POOL_SIZE + 1);
}

WindowManager::~WindowManager()
{
    cleanup();
}

void WindowManager::setEngine(QQmlApplicationEngine *engine)
{
    m_engine = engine;
}

void WindowManager::setColorUtils(ColorUtils *colorUtils)
{
    m_colorUtils = colorUtils;
}

void WindowManager::setInstanceManager(SingleInstanceManager *instanceManager)
{
    m_instanceManager = instanceManager;
}

void WindowManager::setDebugConsole(QObject *debugConsole)
{
    m_debugConsole = debugConsole;
}

void WindowManager::addMainWindow(QObject *mainWindow)
{
    if (!mainWindow) {
        return;
    }

    ViewerWindow vw;
    vw.window = mainWindow;
    vw.context = nullptr;  // Main window doesn't own root context
    vw.busy = false;  // Starts idle (no image loaded yet)
    vw.isMainWindow = true;
    vw.ownsContext = false;  // Don't own root context
    
    // Reserve capacity to avoid reallocations
    if (m_windowPoolStorage.capacity() < MAX_POOL_SIZE + 1) {
        m_windowPoolStorage.reserve(MAX_POOL_SIZE + 1);
    }
    
    int index = m_windowPoolStorage.size();
    m_windowPoolStorage.append(vw);
    m_windowPool.insert(mainWindow, index);
}

ViewerWindow* WindowManager::getWindowFromHash(QObject* window)
{
    auto it = m_windowPool.find(window);
    if (it != m_windowPool.end() && *it >= 0 && *it < m_windowPoolStorage.size()) {
        return &m_windowPoolStorage[*it];
    }
    return nullptr;
}

ViewerWindow* WindowManager::findReusableWindow()
{
    ViewerWindow* mainWindowCandidate = nullptr;
    ViewerWindow* secondaryCandidate = nullptr;
    
    // Single pass: find both candidates, prefer main window
    for (auto &vw : m_windowPoolStorage) {
        if (!vw.window || vw.busy) {
            continue;  // Skip invalid or busy windows
        }
        
        QQuickWindow *quickWindow = qobject_cast<QQuickWindow*>(vw.window);
        if (!quickWindow || quickWindow->isVisible()) {
            continue;  // Skip visible windows
        }
        
        if (vw.isMainWindow && !mainWindowCandidate) {
            mainWindowCandidate = &vw;
        } else if (!vw.isMainWindow && !secondaryCandidate) {
            secondaryCandidate = &vw;
        }
        
        // Early exit if we found both
        if (mainWindowCandidate && secondaryCandidate) {
            break;
        }
    }
    
    // Prefer main window, fall back to secondary
    return mainWindowCandidate ? mainWindowCandidate : secondaryCandidate;
}

ViewerWindow* WindowManager::findMainWindow()
{
    for (auto &vw : m_windowPoolStorage) {
        if (vw.isMainWindow && vw.window) {
            return &vw;
        }
    }
    return nullptr;
}

ViewerWindow* WindowManager::findHiddenMainWindow()
{
    for (auto &vw : m_windowPoolStorage) {
        if (vw.isMainWindow && vw.window) {
            QQuickWindow *quickWindow = qobject_cast<QQuickWindow*>(vw.window);
            if (quickWindow) {
                bool isVisible = quickWindow->isVisible();
                QVariant currentImage = vw.window->property("currentImage");
                
                if (!isVisible) {
                    // Check if currentImage is empty (window has no media)
                    if (currentImage.isValid() && (currentImage.toString().isEmpty() || currentImage.toUrl().isEmpty())) {
                        return &vw;
                    }
                }
            }
        }
    }
    return nullptr;
}

ViewerWindow* WindowManager::findOldestSecondaryWindow()
{
    for (auto &vw : m_windowPoolStorage) {
        if (!vw.isMainWindow && vw.window) {
            return &vw;
        }
    }
    return nullptr;
}

void WindowManager::logToDebugConsole(const QString &message, const QString &type)
{
    // Always log to qDebug first (shows in console) - this will ALWAYS work
    qDebug() << "[C++]" << message;
    
    // Try to log via main window's logToDebugConsole method (most reliable)
    // NOTE: QML functions accept QVariant parameters in the meta-object system
    ViewerWindow* mainWindow = findMainWindow();
    if (mainWindow && mainWindow->window) {
        QVariant msgVar = QVariant("[C++] " + message);
        QVariant typeVar = QVariant(type);
        bool success = QMetaObject::invokeMethod(mainWindow->window, "logToDebugConsole", 
            Qt::QueuedConnection,  // Use QueuedConnection to avoid blocking
            Q_ARG(QVariant, msgVar), 
            Q_ARG(QVariant, typeVar));
        if (!success) {
            qDebug() << "[C++] WARNING: Failed to invoke logToDebugConsole on main window";
        }
        return;
    }
    
    // Fallback: try direct debug console
    if (m_debugConsole) {
        bool success = QMetaObject::invokeMethod(m_debugConsole, "addLog", 
            Qt::QueuedConnection,
            Q_ARG(QString, "[C++] " + message), 
            Q_ARG(QString, type));
        if (!success) {
            qDebug() << "[C++] WARNING: Failed to invoke addLog on debug console";
        }
    } else {
        qDebug() << "[C++] WARNING: m_debugConsole is null";
    }
}

QQuickWindow* WindowManager::createNewWindow(const QUrl &fileUrl)
{
    if (!m_engine || !m_colorUtils) {
        return nullptr;
    }
    
    // Helper to safely cast QObject* to QQuickWindow*
    auto toQuickWindow = [](QObject *obj) -> QQuickWindow* {
        return qobject_cast<QQuickWindow*>(obj);
    };
    
    ViewerWindow *targetWindow = nullptr;
    
    // WINDOW POOLING: Pick the best window to use
    // 1. Always reuse main window if it's hidden (only one main window exists)
    targetWindow = findHiddenMainWindow();
    if (!targetWindow) {
        if (m_secondaryWindowCount >= MAX_POOL_SIZE) {
            // 2. Pool is full - try to reuse an idle window first, then oldest if all are busy
            targetWindow = findReusableWindow();
            if (!targetWindow) {
                // All windows are busy - reuse oldest secondary window
                targetWindow = findOldestSecondaryWindow();
            }
        }
    }
    // 3. If targetWindow is still null, we'll create a new secondary window below (pool not full yet)
    
    // If we found a window to reuse, use it
    if (targetWindow) {
        targetWindow->busy = true;
        
        // Show the window FIRST
        QQuickWindow *quickWindow = toQuickWindow(targetWindow->window);
        if (!quickWindow) {
            qWarning() << "[C++] ERROR: targetWindow->window is not a QQuickWindow!";
            targetWindow->busy = false;
            return nullptr;
        }
        quickWindow->show();
        quickWindow->raise();
        
        // CRITICAL: Reset QML state before reusing window
        // This ensures the window is in a clean state and ready to load a new image
        // Mark as idle BEFORE reset (window has no media at this point)
        // Busy flag = has active media, not visibility
        targetWindow->busy = false;
        
        bool resetSuccess = QMetaObject::invokeMethod(
            targetWindow->window,
            "resetForReuse",
            Qt::DirectConnection
        );
        
        if (!resetSuccess) {
            // Reset failed, mark as not busy and return
            targetWindow->busy = false;
            return nullptr;
        }
        
        // CRITICAL: Force property change by setting to empty first, then to new URL
        // Use QTimer instead of processEvents() to avoid reentrancy issues
        // FIX: Use QPointer to safely capture window pointer
        QPointer<QQuickWindow> safeWindow(quickWindow);
        QUrl safeFileUrl = fileUrl;
        ViewerWindow* safeTargetWindow = targetWindow;  // Pointer to struct is stable
        
        quickWindow->setProperty("currentImage", QUrl());
        
        // Set new image on next event loop tick (safer than processEvents)
        QTimer::singleShot(0, [safeWindow, safeFileUrl, safeTargetWindow]() {
            if (safeWindow && safeTargetWindow) {
                safeWindow->setProperty("currentImage", safeFileUrl);
                // Mark as busy AFTER setting currentImage (window now has active media)
                safeTargetWindow->busy = true;
            }
        });
        
        return quickWindow;
    }
    
    // No window to reuse - create a new secondary window (use cached count)
    
    // Create component from the shared engine using module system
    QQmlComponent component(m_engine);
    component.loadFromModule("s3rp3nt_media", "Main");
    
    if (component.isError()) {
        qWarning() << "Failed to load Main.qml component:" << component.errorString();
        return nullptr;
    }
    
    // Create context for this window (child of root context)
    // Note: ColorUtils and InstanceManager are now QML singletons, no need to set as context properties
    QQmlContext *context = new QQmlContext(m_engine->rootContext());
    
    // Set initial properties
    QVariantMap initialProps;
    // Mark this as a secondary window (not the main window)
    initialProps.insert("isMainWindow", false);
    
    // Create the window object with initial properties
    QObject *windowObj = component.createWithInitialProperties(initialProps, context);
    
    if (!windowObj) {
        qWarning() << "Failed to create window from component:" << component.errorString();
        delete context;
        return nullptr;
    }
    
    // Cast to QQuickWindow (should always succeed for ApplicationWindow)
    QQuickWindow *window = qobject_cast<QQuickWindow*>(windowObj);
    if (!window) {
        qWarning() << "Failed to cast window to QQuickWindow!";
        delete windowObj;
        delete context;
        return nullptr;
    }
    
    // Add to pool (removed redundant context storage in window property)
    ViewerWindow vw;
    vw.window = window;  // Store as QObject* in struct, but we know it's QQuickWindow*
    vw.context = context;
    vw.busy = true;
    vw.isMainWindow = false;
    vw.ownsContext = true;  // We own this context
    // Reserve capacity to avoid reallocations
    if (m_windowPoolStorage.capacity() < MAX_POOL_SIZE + 1) {
        m_windowPoolStorage.reserve(MAX_POOL_SIZE + 1);
    }
    
    int index = m_windowPoolStorage.size();
    m_windowPoolStorage.append(vw);
    m_windowPool.insert(window, index);
    m_secondaryWindowCount++;  // Update cached count
    
    // Set currentImage if fileUrl provided (for new windows)
    if (!fileUrl.isEmpty()) {
        window->setProperty("currentImage", fileUrl);
    }
    
    // Share debug console reference with secondary windows
    if (m_debugConsole) {
        window->setProperty("debugConsole", QVariant::fromValue(m_debugConsole));
        // Ensure debug console is visible when a new window is created
        QQuickWindow *debugWindow = qobject_cast<QQuickWindow*>(m_debugConsole);
        if (debugWindow) {
            if (!debugWindow->isVisible()) {
                debugWindow->show();
            }
            debugWindow->raise();
        }
    }
    
    // Connect to window visibility changes to update pool state
    {
        // CRITICAL: Do NOT clear currentImage or change busy flag here!
        // Visibility changes happen AFTER we set new images, which would clear them
        // Busy flag should only be set when loading/unloading media, not based on visibility
        // Media lifecycle is controlled by resetForReuse() and unloadMedia(), not visibility
        
        // Connect to window destruction to clean up (should rarely happen now)
        // FIX: Use QPointer for safe context access
        QPointer<QQmlContext> safeContext(context);
        QObject::connect(window, &QObject::destroyed, [this, window, safeContext]() {
            
            // Remove from pool using O(1) hash lookup
            auto it = m_windowPool.find(window);
            if (it != m_windowPool.end()) {
                int index = *it;
                if (index >= 0 && index < m_windowPoolStorage.size()) {
                    ViewerWindow& vw = m_windowPoolStorage[index];
                    // Delete context if we own it
                    if (vw.ownsContext && safeContext) {
                        safeContext->deleteLater();
                    }
                }
                
                // Remove from storage list (this invalidates indices, so rebuild hash)
                m_windowPoolStorage.removeAt(index);
                m_secondaryWindowCount--;  // Update cached count
                
                // Rebuild hash with updated indices
                m_windowPool.clear();
                for (int i = 0; i < m_windowPoolStorage.size(); ++i) {
                    if (m_windowPoolStorage[i].window) {
                        m_windowPool.insert(m_windowPoolStorage[i].window, i);
                    }
                }
            }
            
            // Force garbage collection
            if (m_engine) {
                m_engine->collectGarbage();
            }
        });
    }
    
    return window;
}

void WindowManager::cleanup()
{
    // Clean up all contexts we own
    for (auto it = m_windowPoolStorage.begin(); it != m_windowPoolStorage.end(); ) {
        if (it->ownsContext && it->context) {
            it->context->deleteLater();
            it->context = nullptr;
        }
        it = m_windowPoolStorage.erase(it);
    }
    m_windowPool.clear();
    m_secondaryWindowCount = 0;
}


