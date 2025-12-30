import QtQuick
import QtQuick.Controls

/**
 * AppShortcuts.qml
 * Centralized keyboard shortcuts configuration
 */
Item {
    id: appShortcuts
    
    // Properties to bind to (passed from parent)
    property var window: null
    property var openDialog: null
    
    Shortcut {
        sequences: [ StandardKey.Open ]
        onActivated: {
            if (appShortcuts.openDialog) {
                appShortcuts.openDialog.open()
            }
        }
    }
    
    // Image navigation shortcuts
    Shortcut {
        sequence: "Left"
        enabled: appShortcuts.window && appShortcuts.window.isImageType && appShortcuts.window.directoryImages.length > 1
        onActivated: {
            if (appShortcuts.window) {
                appShortcuts.window.previousImage()
            }
        }
    }
    
    Shortcut {
        sequence: "Right"
        enabled: appShortcuts.window && appShortcuts.window.isImageType && appShortcuts.window.directoryImages.length > 1
        onActivated: {
            if (appShortcuts.window) {
                appShortcuts.window.nextImage()
            }
        }
    }
    
    Shortcut {
        sequence: "Home"
        enabled: appShortcuts.window && appShortcuts.window.isImageType && appShortcuts.window.directoryImages.length > 1
        onActivated: {
            if (appShortcuts.window) {
                appShortcuts.window.navigateToImage(0)
            }
        }
    }
    
    Shortcut {
        sequence: "End"
        enabled: appShortcuts.window && appShortcuts.window.isImageType && appShortcuts.window.directoryImages.length > 1
        onActivated: {
            if (appShortcuts.window) {
                appShortcuts.window.navigateToImage(appShortcuts.window.directoryImages.length - 1)
            }
        }
    }
    
    // ESC key to exit Bad Apple easter egg
    Shortcut {
        sequence: "Escape"
        enabled: appShortcuts.window && appShortcuts.window.badAppleEffectEnabled
        onActivated: {
            if (appShortcuts.window) {
                appShortcuts.window.stopBadAppleEasterEgg()
            }
        }
    }
}

