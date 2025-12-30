import QtQuick
import QtQuick.Controls

// WindowInitializationManager - Handles window initialization logic
Item {
    id: windowInitManager
    
    required property Window mainWindow
    required property url initialImage
    required property var logToDebugConsole
    required property var updateAccentColor
    required property var windowLifecycleUtils
    
    Component.onCompleted: {
        // CRITICAL: Limit Qt's global image cache to prevent excessive RAM usage
        // This alone can cut RAM growth in half
        Qt.imageCacheSize = 32 * 1024 * 1024  // 32 MB (can be increased to 64 MB if needed)
        if (typeof windowInitManager.logToDebugConsole === "function") {
            windowInitManager.logToDebugConsole("[App] Set Qt.imageCacheSize to 32 MB", "info")
        }
        
        windowInitManager.windowLifecycleUtils.handleComponentCompleted(
            windowInitManager.initialImage, 
            windowInitManager.mainWindow, 
            windowInitManager.logToDebugConsole, 
            windowInitManager.updateAccentColor, 
            Qt.callLater
        )
    }
}

