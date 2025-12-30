import QtQuick
import QtQuick.Controls

// BassPulseManager - Manages the bass pulse window and keeps main window on top
Item {
    id: bassPulseManager
    
    required property Window mainWindow
    required property bool isAudio
    required property var audioPlayerLoader
    required property color accentColor
    
    // Bass pulse window - transparent window with pulsing rounded rectangles
    BassPulseWindow {
        id: bassPulseWindow
        mainWindow: bassPulseManager.mainWindow
        bassAmplitude: (bassPulseManager.isAudio && bassPulseManager.audioPlayerLoader && bassPulseManager.audioPlayerLoader.item && bassPulseManager.audioPlayerLoader.item.analyzer) 
                       ? (bassPulseManager.audioPlayerLoader.item.analyzer.bassAmplitude || 0.0) 
                       : 0.0
        enabled: bassPulseManager.isAudio && 
                 bassPulseManager.audioPlayerLoader && 
                 bassPulseManager.audioPlayerLoader.item && 
                 bassPulseManager.audioPlayerLoader.item.analyzer && 
                 bassPulseManager.audioPlayerLoader.item.analyzer.active && 
                 bassPulseManager.audioPlayerLoader.item.analyzer.bassAmplitude > 0.1
        pulseColor: bassPulseManager.accentColor  // Use dynamic accent color
        
        onVisibleChanged: {
            if (visible) {
                // Ensure main window stays on top
                Qt.callLater(function() {
                    if (bassPulseManager.mainWindow) {
                        bassPulseManager.mainWindow.raise()
                        bassPulseManager.mainWindow.requestActivate()
                    }
                })
            }
        }
    }
    
    // Keep main window on top when bass pulse is visible (less frequent to avoid flicker)
    Timer {
        interval: 500
        running: bassPulseWindow.visible
        repeat: true
        onTriggered: {
            if (bassPulseWindow.visible && bassPulseManager.mainWindow) {
                bassPulseManager.mainWindow.raise()
            }
        }
    }
}

