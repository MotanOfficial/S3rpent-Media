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
    
    // F11 key to toggle fullscreen
    Shortcut {
        sequence: "F11"
        enabled: appShortcuts.window !== null
        onActivated: {
            if (appShortcuts.window) {
                if (appShortcuts.window.visibility === Window.FullScreen) {
                    appShortcuts.window.showNormal()
                } else {
                    appShortcuts.window.showFullScreen()
                }
            }
        }
    }
    
    // ESC key to exit fullscreen or easter eggs
    Shortcut {
        sequence: "Escape"
        enabled: appShortcuts.window !== null
        onActivated: {
            if (appShortcuts.window) {
                // First priority: exit Undertale fight if active (it uses fullscreen)
                if (appShortcuts.window.undertaleFightEnabled) {
                    appShortcuts.window.stopUndertaleFight()
                    return
                }
                // Second priority: exit fullscreen if in fullscreen
                if (appShortcuts.window.visibility === Window.FullScreen) {
                    appShortcuts.window.showNormal()
                    return
                }
                // Third priority: exit Bad Apple easter egg if active
                if (appShortcuts.window.badAppleEffectEnabled) {
                    appShortcuts.window.stopBadAppleEasterEgg()
                }
            }
        }
    }
}

