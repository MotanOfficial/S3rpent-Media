import QtQuick
import QtQuick.Controls

// BassPulseManager - Manages the bass pulse window and keeps main window on top
Item {
    id: bassPulseManager
    
    required property Window mainWindow
    required property bool isAudio
    required property var audioPlayerLoader
    required property color accentColor
    property bool suppressMainWindowRaise: false

    // After the music overlay closes, suppressMainWindowRaise flips false while audio (and bass pulse)
    // keeps running — the pulse timer would otherwise immediately raise the main window. Skip raises
    // for a short period so closing the overlay does not pop the app forward.
    property bool _blockMainRaise: suppressMainWindowRaise || overlayCloseCooldownTimer.running

    Timer {
        id: overlayCloseCooldownTimer
        interval: 4000
        repeat: false
    }

    property bool _prevMusicOverlayVisible: false
    Connections {
        target: bassPulseManager.mainWindow
        enabled: bassPulseManager.mainWindow !== null
        function onMusicOverlayVisibleChanged() {
            const v = bassPulseManager.mainWindow.musicOverlayVisible
            if (_prevMusicOverlayVisible && !v)
                overlayCloseCooldownTimer.restart()
            _prevMusicOverlayVisible = v
        }
    }

    // Sampled bass amplitude - updated by timer below rather than direct binding
    // to avoid triggering binding-engine cascades at audio frame rate.
    property real _sampledBassAmplitude: 0.0
    property bool _sampledBassEnabled: false

    // Sample the analyzer's bassAmplitude at a controlled rate (50ms = 20 FPS).
    // Direct binding to analyzer.bassAmplitude would cause the entire property
    // binding cascade (waveRect positions, opacity, visible, glow, etc.) to
    // re-evaluate at audio-frame rate, overwhelming the QML binding engine and
    // causing a stack overflow from the exponential cascade.
    Timer {
        id: bassSampleTimer
        interval: 50
        running: {
            // Only sample when we have an active analyzer with bass
            if (!bassPulseManager.isAudio || !bassPulseManager.audioPlayerLoader) return false
            const item = bassPulseManager.audioPlayerLoader.item
            if (!item || !item.analyzer || !item.analyzer.active) return false
            return item.analyzer.bassAmplitude > 0.1
        }
        repeat: true
        onTriggered: {
            if (!bassPulseManager.isAudio || !bassPulseManager.audioPlayerLoader) return
            const item = bassPulseManager.audioPlayerLoader.item
            if (!item || !item.analyzer || !item.analyzer.active) return
            
            const raw = item.analyzer.bassAmplitude || 0.0
            bassPulseManager._sampledBassAmplitude = raw
            bassPulseManager._sampledBassEnabled = raw > 0.1
        }
    }

    // Bass pulse window - transparent window with pulsing rounded rectangles
    BassPulseWindow {
        id: bassPulseWindow
        mainWindow: bassPulseManager.mainWindow
        // Use sampled value instead of direct analyzer binding to prevent
        // high-frequency re-evaluation cascades through the QML binding engine.
        bassAmplitude: bassPulseManager._sampledBassAmplitude
        enabled: bassPulseManager._sampledBassEnabled
        pulseColor: bassPulseManager.accentColor  // Use dynamic accent color
        
        onVisibleChanged: {
            if (visible && !bassPulseManager._blockMainRaise) {
                Qt.callLater(function() {
                    if (bassPulseManager.mainWindow) {
                        bassPulseManager.mainWindow.raise()
                    }
                })
            }
        }
    }
    
    // Keep bass pulse stacked with the main window without repeatedly stealing foreground.
    Timer {
        interval: 500
        running: bassPulseWindow.visible
        repeat: true
        onTriggered: {
            if (!bassPulseWindow.visible || !bassPulseManager.mainWindow || bassPulseManager._blockMainRaise)
                return
            // Re-stack the glow window only; avoid raising the main window every 500ms (that was
            // popping the app to the front when the music overlay closed while audio kept playing).
            bassPulseWindow.raise()
        }
    }
}