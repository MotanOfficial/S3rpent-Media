import QtQuick
import QtQuick.Window
import Qt5Compat.GraphicalEffects

Window {
    id: bassPulseWindow
    
    property real bassAmplitude: 0.0
    property Window mainWindow: null
    property color pulseColor: "#ff0000"  // Default red, will be overridden by dynamic color
    property bool enabled: false
    
    property int padding: 40  // Increased padding for bigger window
    property bool isWindowMoving: false  // Track if main window is being moved
    
    // Glow effect properties - transient, like a kick
    property real glowIntensity: 0.0  // Current glow intensity (0.0 to 1.0)
    property real previousBassAmplitude: 0.0  // Track previous value to detect spikes
    property bool glowEnabled: false  // Throttle glow detection
    property real peakBassAmplitude: 0.0  // Track peak for glow intensity
    property int glowStartTime: 0  // Track when glow started for ripple effect
    property int currentGlowWave: -1  // Which wave is currently glowing (-1 = none)
    
    visible: enabled && mainWindow !== null && bassAmplitude > 0.1 && !isWindowMoving
    flags: Qt.Window | Qt.FramelessWindowHint | Qt.Tool | Qt.WindowTransparentForInput
    color: "transparent"
    
    // Position and size to surround the main window
    x: mainWindow ? mainWindow.x - padding : 0
    y: mainWindow ? mainWindow.y - padding : 0
    width: mainWindow ? mainWindow.width + (padding * 2) : 0
    height: mainWindow ? mainWindow.height + (padding * 2) : 0
    
    // Optimized movement detection - use timer to check position less frequently
    property int lastMainWindowX: mainWindow ? mainWindow.x : 0
    property int lastMainWindowY: mainWindow ? mainWindow.y : 0
    
    // Check for movement periodically instead of on every pixel change
    Timer {
        id: movementCheckTimer
        interval: 50  // Check every 50ms instead of every pixel
        running: enabled && mainWindow !== null
        repeat: true
        onTriggered: {
            if (mainWindow) {
                const xDiff = Math.abs(mainWindow.x - lastMainWindowX)
                const yDiff = Math.abs(mainWindow.y - lastMainWindowY)
                
                if (xDiff > 2 || yDiff > 2) {  // Window moved
                    if (!isWindowMoving) {
                        isWindowMoving = true
                    }
                    movementStopTimer.restart()
                    lastMainWindowX = mainWindow.x
                    lastMainWindowY = mainWindow.y
                }
            }
        }
    }
    
    // Timer to detect when movement has stopped
    Timer {
        id: movementStopTimer
        interval: 150  // Wait 150ms after last detected movement
        onTriggered: {
            isWindowMoving = false
        }
    }
    
    // Update position when window becomes visible (for initial positioning)
    // Also reset glow when window becomes invisible
    onVisibleChanged: {
        if (visible && mainWindow) {
            x = mainWindow.x - padding
            y = mainWindow.y - padding
            width = mainWindow.width + (padding * 2)
            height = mainWindow.height + (padding * 2)
            lastMainWindowX = mainWindow.x
            lastMainWindowY = mainWindow.y
        } else if (!visible) {
            // Reset glow when window becomes invisible
            glowIntensity = 0.0
            glowEnabled = false
            currentGlowWave = -1
            rippleTimer.stop()
        }
    }
    
    // Circular wave effects - ripples emanating from the main window
    // Position circles to match main window dimensions and expand outward
    property int mainWindowWidth: mainWindow ? mainWindow.width : 0
    property int mainWindowHeight: mainWindow ? mainWindow.height : 0
    property int baseOffset: 40  // Offset from main window edges (matches padding)
    
    // Apply non-linear curve to bass amplitude for more gradual response
    // Square root curve: takes more bass to reach maximum expansion
    property real adjustedBass: Math.pow(bassAmplitude, 1.5)  // Power curve for gradual response
    
    // Detect bass spikes (kicks) and trigger glow - direct response, no smoothing
    onBassAmplitudeChanged: {
        if (visible && enabled) {
            // Detect bass spikes (kicks) - more sensitive
            const bassIncrease = bassAmplitude - previousBassAmplitude
            if (bassIncrease > 0.05 && bassAmplitude > 0.15) {
                // Kick detected - start ripple effect
                peakBassAmplitude = bassAmplitude
                glowIntensity = Math.min(1.0, bassAmplitude * 2.0)  // Strong glow on kick
                glowEnabled = true
                glowStartTime = Date.now()  // Record when glow started
                currentGlowWave = 0  // Start with first wave
                rippleTimer.restart()  // Start ripple propagation
                glowDecayTimer.restart()
                glowThrottleTimer.restart()
            } else if (bassAmplitude > 0.1) {
                // Continuous bass - maintain some glow but let it decay
                if (glowIntensity < bassAmplitude * 0.5) {
                    glowIntensity = bassAmplitude * 0.5  // Subtle glow for continuous bass
                }
            }
        }
        previousBassAmplitude = bassAmplitude
    }
    
    // Ripple timer - propagates glow from inner to outer waves
    Timer {
        id: rippleTimer
        interval: 30  // 30ms delay between each wave (6 waves = 180ms total) - faster ripple
        running: false
        repeat: true
        onTriggered: {
            if (currentGlowWave < 5) {  // 6 waves (0-5)
                currentGlowWave++
            } else {
                // Ripple complete, let it fade
                rippleTimer.stop()
            }
        }
    }
    
    // Throttle glow detection to prevent excessive triggering
    Timer {
        id: glowThrottleTimer
        interval: 80  // Minimum 80ms between glow triggers
        onTriggered: {
            glowEnabled = false
        }
    }
    
    // Decay glow over time (like a kick fading) - fast decay
    Timer {
        id: glowDecayTimer
        interval: 30  // 30ms updates for smooth but fast decay
        running: visible && enabled && glowIntensity > 0.01
        repeat: true
        onTriggered: {
            glowIntensity = Math.max(0.0, glowIntensity - 0.12)  // Fast decay
            if (glowIntensity <= 0.01) {
                glowIntensity = 0.0
                currentGlowWave = -1  // Reset ripple when glow fades
                rippleTimer.stop()
            }
        }
    }
    
    Repeater {
        model: 6  // Multiple ripples, closer together
        
        Rectangle {
            id: waveRect
            // Start at main window size, expand outward
            // Position: start at baseOffset (20px) from bass pulse window edge to match main window position
            // Then expand outward (negative x/y and larger width/height)
            // Reduced multipliers and non-linear response for gradual expansion
            x: baseOffset - (adjustedBass * 8 * (index + 1))  // Reduced from 15 to 8
            y: baseOffset - (adjustedBass * 8 * (index + 1))
            width: mainWindowWidth + (adjustedBass * 16 * (index + 1))  // Reduced from 30 to 16
            height: mainWindowHeight + (adjustedBass * 16 * (index + 1))
            radius: 20  // Rounded corners like the main window
            color: "transparent"
            border.width: 3  // Thicker borders for more visibility
            opacity: (bassAmplitude > 0.1) ? (0.6 / (index + 1)) * (0.5 + adjustedBass * 0.5) : 0  // Use adjustedBass for opacity too
            antialiasing: true
            
            // Brighten border color on bass hits - ripple effect from inner to outer
            // Calculate brightened color based on whether this wave is currently glowing
            property color brightenedColor: {
                // Check if this wave is part of the current ripple
                if (glowIntensity > 0.01 && currentGlowWave >= index) {
                    // Calculate brightness - strongest when wave is actively glowing, fades as ripple passes
                    let brightness = 0.0
                    if (currentGlowWave === index) {
                        // This wave is currently glowing - full brightness
                        brightness = glowIntensity
                    } else if (currentGlowWave > index) {
                        // Ripple has passed this wave - fade it out
                        const wavesSince = currentGlowWave - index
                        brightness = glowIntensity * Math.max(0, 1.0 - (wavesSince * 0.3))
                    }
                    
                    // Brighten the color by mixing with white
                    return Qt.rgba(
                        Math.min(1.0, pulseColor.r + (1.0 - pulseColor.r) * brightness * 0.9),
                        Math.min(1.0, pulseColor.g + (1.0 - pulseColor.g) * brightness * 0.9),
                        Math.min(1.0, pulseColor.b + (1.0 - pulseColor.b) * brightness * 0.9),
                        1.0
                    )
                } else {
                    return pulseColor
                }
            }
            
            // Use brightened color for border
            border.color: brightenedColor
            
            // Fast color transitions for responsive brightness changes
            Behavior on border.color {
                ColorAnimation {
                    duration: 50  // Fast response to bass hits
                    easing.type: Easing.OutQuad
                }
            }
            
            // Less smooth, more direct bass response
            Behavior on x {
                NumberAnimation {
                    duration: 30  // Faster response
                    easing.type: Easing.Linear  // Linear for more direct response
                }
            }
            Behavior on y {
                NumberAnimation {
                    duration: 30
                    easing.type: Easing.Linear
                }
            }
            Behavior on width {
                NumberAnimation {
                    duration: 30
                    easing.type: Easing.Linear
                }
            }
            Behavior on height {
                NumberAnimation {
                    duration: 30
                    easing.type: Easing.Linear
                }
            }
            Behavior on opacity {
                NumberAnimation {
                    duration: 50  // Faster opacity changes
                    easing.type: Easing.Linear
                }
            }
            
            // Update when main window size or bass amplitude changes
            Connections {
                target: bassPulseWindow
                function onMainWindowWidthChanged() {
                    if (waveRect) {
                        waveRect.width = mainWindowWidth + (bassAmplitude * 30 * (index + 1))
                    }
                }
                function onMainWindowHeightChanged() {
                    if (waveRect) {
                        waveRect.height = mainWindowHeight + (bassAmplitude * 30 * (index + 1))
                    }
                }
                function onBassAmplitudeChanged() {
                    if (waveRect) {
                        const adjBass = Math.pow(bassAmplitude, 1.5)
                        waveRect.x = baseOffset - (adjBass * 8 * (index + 1))
                        waveRect.y = baseOffset - (adjBass * 8 * (index + 1))
                        waveRect.width = mainWindowWidth + (adjBass * 16 * (index + 1))
                        waveRect.height = mainWindowHeight + (adjBass * 16 * (index + 1))
                    }
                }
            }
        }
    }
}

