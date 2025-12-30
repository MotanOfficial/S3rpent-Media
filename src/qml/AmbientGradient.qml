import QtQuick

// Spotify-style ambient animated gradient using GPU shaders
ShaderEffect {
    id: ambientGradient
    
    property var paletteColors: []  // Array of colors from palette extraction
    property bool enabled: true
    property real speed: 0.01  // Animation speed (Spotify-slow)
    property real distortion: 0.15  // Distortion amount (more organic variation)
    property real effectOpacity: 0.8  // Overall opacity (increased for visibility)
    
    anchors.fill: parent
    width: parent ? parent.width : 0
    height: parent ? parent.height : 0
    visible: enabled  // Visible when enabled
    
    // Animation time (drives the noise)
    property real time: 0.0
    
    NumberAnimation on time {
        from: 0
        to: 1000
        duration: 60000  // 60 seconds - Spotify-style slow animation
        loops: Animation.Infinite
        running: enabled && opacity > 0
    }
    
    // Helper functions for color derivation
    function lighter(c, f) { return Qt.lighter(c, f) }
    function darker(c, f) { return Qt.darker(c, f) }
    
    // Base color from palette or fallback
    property color baseColor: (paletteColors && paletteColors.length > 0) ? paletteColors[0] : "#ff6a00"
    
    // Extract colors from palette, derive variations if needed
    // Create MORE DISTINCT color variations with hue shifts for richer gradients
    property color color1: baseColor
    property color color2: (paletteColors && paletteColors.length > 1) ? paletteColors[1] : Qt.hsla((baseColor.hslHue + 0.1) % 1.0, Math.min(1.0, baseColor.hslSaturation * 1.2), Math.min(1.0, baseColor.hslLightness * 1.5), 1.0)
    property color color3: (paletteColors && paletteColors.length > 2) ? paletteColors[2] : Qt.hsla((baseColor.hslHue - 0.05) % 1.0, Math.min(1.0, baseColor.hslSaturation * 1.1), Math.max(0.0, baseColor.hslLightness * 0.5), 1.0)
    property color color4: (paletteColors && paletteColors.length > 3) ? paletteColors[3] : Qt.hsla((baseColor.hslHue + 0.15) % 1.0, Math.min(1.0, baseColor.hslSaturation * 1.4), Math.min(1.0, baseColor.hslLightness * 1.3), 1.0)
    property color color5: (paletteColors && paletteColors.length > 4) ? paletteColors[4] : Qt.hsla((baseColor.hslHue - 0.1) % 1.0, Math.min(1.0, baseColor.hslSaturation * 0.9), Math.max(0.0, baseColor.hslLightness * 0.4), 1.0)
    
    // Smooth color transitions when palette changes
    Behavior on color1 {
        ColorAnimation {
            duration: 600
            easing.type: Easing.OutCubic
        }
    }
    Behavior on color2 {
        ColorAnimation {
            duration: 600
            easing.type: Easing.OutCubic
        }
    }
    Behavior on color3 {
        ColorAnimation {
            duration: 600
            easing.type: Easing.OutCubic
        }
    }
    Behavior on color4 {
        ColorAnimation {
            duration: 600
            easing.type: Easing.OutCubic
        }
    }
    Behavior on color5 {
        ColorAnimation {
            duration: 600
            easing.type: Easing.OutCubic
        }
    }
    
    // Uniforms for shader
    property real u_time: time
    property real u_distortion: distortion
    
    // Reference the compiled shader files - Qt will find the .qsb files automatically
    vertexShader: Qt.resolvedUrl("qrc:/resources/shaders/ambientgradient.vert.qsb")
    fragmentShader: Qt.resolvedUrl("qrc:/resources/shaders/ambientgradient.frag.qsb")
    
    // Opacity control - ShaderEffect uses qt_Opacity uniform automatically
    opacity: enabled ? effectOpacity : 0.0
    // z ordering - behind content but above base background
    z: 0
    
    
    Behavior on opacity {
        NumberAnimation {
            duration: 400
            easing.type: Easing.OutCubic
        }
    }
    
    // Check shader status (only log errors)
    onStatusChanged: {
        if (status === ShaderEffect.Error) {
            console.log("[AmbientGradient] Shader error:", log)
        }
    }
}

