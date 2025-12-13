import QtQuick

Item {
    id: windowBackground
    
    property color accentColor: "#121216"
    property var paletteColors: []  // Array of colors for gradient
    property bool dynamicColoringEnabled: true
    property bool gradientBackgroundEnabled: true
    property bool backdropBlurEnabled: false  // Blurred cover-art backdrop
    property bool ambientGradientEnabled: false  // Spotify-style ambient animated gradient
    property bool snowEffectEnabled: false  // Hybrid snow effect (shader + particles)
    property url backdropImageSource: ""  // Image source for backdrop blur (cover art or current image)
    
    // Background mode: 0 = basic, 1 = canvas gradient, 2 = blur, 3 = ambient
    // Snow is separate and can layer on top of any background mode
    property int backgroundMode: backdropBlurEnabled ? 2
                                 : ambientGradientEnabled ? 3
                                 : gradientBackgroundEnabled ? 1
                                 : 0
    
    anchors.fill: parent
    width: parent ? parent.width : 0
    height: parent ? parent.height : 0

    Component.onCompleted: {
        console.log("[WindowBackground] Created - size:", width, "x", height, "parent:", parent)
    }
    
    onWidthChanged: {
        if (width > 0) {
            console.log("[WindowBackground] Width changed to:", width)
    }
    }
    
    onHeightChanged: {
        if (height > 0) {
            console.log("[WindowBackground] Height changed to:", height)
        }
    }
    
    onGradientBackgroundEnabledChanged: {
    }
    
    onDynamicColoringEnabledChanged: {
    }

    // Base dark background - Always present behind everything
    Rectangle {
        anchors.fill: parent
        color: "#0f111a"
        opacity: 1.0
        z: -10
    }

    // --- MODE 2: Blurred cover-art backdrop (like Apple Music, YouTube Music) ---
    BackdropBlur {
        id: backdropBlurEffect
        imageSource: windowBackground.backdropImageSource
        enabled: backgroundMode === 2 && backdropImageSource !== ""
        visible: enabled
        z: -5
    }
    
    // --- MODE 3: Spotify-style ambient animated gradient (GPU shader-based) ---
    AmbientGradient {
        id: ambientGradientEffect
        paletteColors: windowBackground.paletteColors
        enabled: backgroundMode === 3
        // visible is controlled by AmbientGradient.qml itself
        z: -5
    }
    
    // --- MODE 1: Spotify-style multi-color gradient background (Canvas-based) ---
    GradientBackground {
        id: gradientCanvas
        accentColor: windowBackground.accentColor
        paletteColors: windowBackground.paletteColors
        enabled: backgroundMode === 1
        visible: enabled
        z: -5
    }
    
    // --- Snow effect (can layer on top of any background) ---
    SnowEffect {
        id: snowEffect
        enabled: snowEffectEnabled
        z: -3  // Above background effects but below UI
    }
    
    // Universal darkening overlay (safe, no triangles)
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.35)
        z: -4
        visible: backgroundMode !== 0 && !snowEffectEnabled  // No overlay when snow is enabled
    }

    // Log when paletteColors changes
    onPaletteColorsChanged: {
    }

    // --- MODE 0: Fallback ONLY (simple, no rotated wedges) ---
    Rectangle {
        anchors.fill: parent
        visible: backgroundMode === 0
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.0) }
            GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0.08) }
        }
        z: -5
    }
}

