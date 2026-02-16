import QtQuick
import QtQuick.Shapes
import s3rpent_media

Item {
    id: visualizer
    
    property int bandCount: 32
    property real amplitude: 0.5
    property color visualizerColor: "#ffffff"
    property bool active: false
    property var audioAnalyzer: null
    
    // Animated frequency bands using Canvas for smooth rendering
    Canvas {
        id: canvas
        anchors.fill: parent
        antialiasing: true
        
        onPaint: {
            const ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            
            if (!active) return
            
            const barWidth = width / bandCount
            const centerY = height / 2
            
            ctx.fillStyle = visualizerColor
            ctx.globalAlpha = 0.3
            
            // Use real frequency bands if available, otherwise use simulated
            const bands = audioAnalyzer && audioAnalyzer.frequencyBands ? audioAnalyzer.frequencyBands : []
            const useRealData = bands.length > 0
            
            // Smooth the bands array for even smoother transitions
            let smoothedBands = []
            if (useRealData && bands.length > 0) {
                for (let i = 0; i < bands.length; i++) {
                    const prev = i > 0 ? bands[i - 1] : bands[i]
                    const curr = bands[i] || 0
                    const next = i < bands.length - 1 ? bands[i + 1] : bands[i]
                    // Apply simple moving average for extra smoothness
                    smoothedBands[i] = (prev * 0.2 + curr * 0.6 + next * 0.2)
                }
            }
            
            for (let i = 0; i < bandCount; i++) {
                let barHeight = 0
                
                if (useRealData && i < smoothedBands.length) {
                    // Use smoothed real frequency data
                    const bandValue = smoothedBands[i] || 0
                    barHeight = bandValue * height * 0.5
                } else if (useRealData && i < bands.length) {
                    // Fallback to unsmoothed if smoothing failed
                    const bandValue = bands[i] || 0
                    barHeight = bandValue * height * 0.5
                } else {
                    // Fallback to simulated data
                    const phase = (i * 0.3) + (Date.now() * 0.001)
                    const wave1 = Math.sin(phase) * 0.5 + 0.5
                    const wave2 = Math.sin(phase * 2.3) * 0.3 + 0.7
                    const wave3 = Math.sin(phase * 1.7 + i) * 0.2 + 0.8
                    barHeight = (amplitude * height * 0.4 * wave1 * wave2 * wave3)
                }
                
                const x = i * barWidth + barWidth * 0.1
                const y = centerY - barHeight / 2
                
                // Draw rounded rectangle
                ctx.beginPath()
                const radius = barWidth * 0.2
                ctx.moveTo(x + radius, y)
                ctx.lineTo(x + barWidth * 0.8 - radius, y)
                ctx.quadraticCurveTo(x + barWidth * 0.8, y, x + barWidth * 0.8, y + radius)
                ctx.lineTo(x + barWidth * 0.8, y + barHeight - radius)
                ctx.quadraticCurveTo(x + barWidth * 0.8, y + barHeight, x + barWidth * 0.8 - radius, y + barHeight)
                ctx.lineTo(x + radius, y + barHeight)
                ctx.quadraticCurveTo(x, y + barHeight, x, y + barHeight - radius)
                ctx.lineTo(x, y + radius)
                ctx.quadraticCurveTo(x, y, x + radius, y)
                ctx.closePath()
                ctx.fill()
            }
        }
        
        Timer {
            interval: 16  // 60 FPS for smooth animation
            running: active
            repeat: true
            onTriggered: canvas.requestPaint()
        }
    }
    
    // Circular wave effects
    Repeater {
        model: 4
        
        Rectangle {
            anchors.centerIn: parent
            width: parent.width * 0.8 + (amplitude * 100 * (index + 1))
            height: parent.height * 0.8 + (amplitude * 100 * (index + 1))
            radius: width / 2
            color: "transparent"
            border.color: visualizerColor
            border.width: 1
            opacity: active ? (0.15 / (index + 1)) : 0
            
            SequentialAnimation on scale {
                running: active
                loops: Animation.Infinite
                NumberAnimation {
                    from: 0.8
                    to: 1.2
                    duration: 2000 + (index * 500)
                    easing.type: Easing.InOutSine
                }
                NumberAnimation {
                    from: 1.2
                    to: 0.8
                    duration: 2000 + (index * 500)
                    easing.type: Easing.InOutSine
                }
            }
            
            Behavior on opacity {
                NumberAnimation {
                    duration: 500
                }
            }
        }
    }
    
    // Particle-like dots
    Repeater {
        model: 20
        
        Rectangle {
            width: 4
            height: 4
            radius: 2
            color: visualizerColor
            opacity: active ? (0.2 + amplitude * 0.3) : 0
            
            property real phase: index * 0.5
            
            Timer {
                interval: 50
                running: active
                repeat: true
                onTriggered: {
                    phase += 0.025
                    const radiusX = visualizer.width * 0.3 + amplitude * 50
                    const radiusY = visualizer.height * 0.3 + amplitude * 50
                    x = visualizer.width / 2 + Math.cos(phase) * radiusX - width / 2
                    y = visualizer.height / 2 + Math.sin(phase) * radiusY - height / 2
                }
            }
            
            Component.onCompleted: {
                const initialPhase = index * 0.5
                const radiusX = visualizer.width * 0.3 + amplitude * 50
                const radiusY = visualizer.height * 0.3 + amplitude * 50
                x = visualizer.width / 2 + Math.cos(initialPhase) * radiusX - width / 2
                y = visualizer.height / 2 + Math.sin(initialPhase) * radiusY - height / 2
            }
            
            Behavior on opacity {
                NumberAnimation {
                    duration: 300
                }
            }
        }
    }
}

