import QtQuick

Item {
    id: windowBackground
    
    // Do not use enabled: false here — it can suppress rendering for ShaderEffect / Loader children.
    // This item is stacked behind MainVisuals content; pointer hits target the top layers first.
    enabled: true
    
    property color accentColor: "#121216"
    property var paletteColors: []  // Array of colors for gradient
    property bool dynamicColoringEnabled: true
    property bool gradientBackgroundEnabled: true
    property bool backdropBlurEnabled: false  // Blurred cover-art backdrop
    property bool ambientGradientEnabled: false  // Spotify-style ambient animated gradient
    property bool snowEffectEnabled: false  // Hybrid snow effect (shader + particles)
    property bool badAppleEffectEnabled: false  // Bad Apple!! shader renderer
    property url backdropImageSource: ""  // Image source for backdrop blur (cover art or current image)
    property var audioPlayer: null  // Reference to main audio player
    property bool startupEffectsReady: false  // Enables expensive effects shortly after first frame
    property bool _badAppleStartPending: false  // Bad Apple loader is async; finish start in onLoaded

    // Only treat blur as active when we have a source; otherwise "backdrop blur" must not
    // block ambient/gradient (otherwise mode 2 is set but the Loader never opens → blank).
    readonly property bool backdropBlurActive: backdropBlurEnabled && backdropImageSource.toString() !== ""

    // Background mode: 0 = basic, 1 = canvas gradient, 2 = blur, 3 = ambient
    // Snow is separate and can layer on top of any background mode
    property int backgroundMode: backdropBlurActive ? 2
                                 : ambientGradientEnabled ? 3
                                 : gradientBackgroundEnabled ? 1
                                 : 0
    
    anchors.fill: parent
    width: parent ? parent.width : 0
    height: parent ? parent.height : 0

    // Root has enabled: false (pointer passthrough). A Timer child can inherit effective
    // enabled: false in Qt Quick and never fire — startupEffectsReady would stay false forever.
    Component.onCompleted: {
        Qt.callLater(function() {
            startupEffectsReady = true
        })
    }

    onBadAppleEffectEnabledChanged: {
        if (!badAppleEffectEnabled)
            _badAppleStartPending = false
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
    Loader {
        id: backdropBlurLoader
        anchors.fill: parent
        asynchronous: true
        active: startupEffectsReady && backgroundMode === 2
        sourceComponent: BackdropBlur {
            imageSource: windowBackground.backdropImageSource
            enabled: true
            visible: true
            z: -5
        }
    }
    
    // --- MODE 3: Spotify-style ambient animated gradient (GPU shader-based) ---
    Loader {
        id: ambientGradientLoader
        anchors.fill: parent
        asynchronous: true
        active: startupEffectsReady && backgroundMode === 3
        sourceComponent: AmbientGradient {
            paletteColors: windowBackground.paletteColors
            enabled: true
            z: -5
        }
    }
    
    // --- MODE 1: Spotify-style multi-color gradient background (Canvas-based) ---
    Loader {
        id: gradientCanvasLoader
        anchors.fill: parent
        asynchronous: true
        active: startupEffectsReady && backgroundMode === 1
        sourceComponent: GradientBackground {
            accentColor: windowBackground.accentColor
            paletteColors: windowBackground.paletteColors
            enabled: true
            visible: true
            z: -5
        }
    }
    
    // --- Snow effect (can layer on top of any background) ---
    Loader {
        id: snowEffectLoader
        anchors.fill: parent
        asynchronous: true
        active: startupEffectsReady && snowEffectEnabled && !badAppleEffectEnabled
        sourceComponent: SnowEffect {
            enabled: true
            z: -3  // Above background effects but below UI
        }
    }
    
    // --- Bad Apple!! effect (replaces snow when enabled) ---
    Loader {
        id: badAppleEffectLoader
        anchors.fill: parent
        asynchronous: true
        active: startupEffectsReady && badAppleEffectEnabled
        onLoaded: {
            if (windowBackground._badAppleStartPending && item
                    && typeof item.startPlayback === "function") {
                windowBackground._badAppleStartPending = false
                item.startPlayback()
            }
        }
        sourceComponent: BadAppleEffect {
            effectEnabled: true
            z: -3  // Same layer as snow
        }
    }
    
    // Expose BadAppleEffect to parent for easter egg activation
    function startBadAppleEasterEgg() {
        // Set pending before activating loader so onLoaded cannot fire before we're listening.
        _badAppleStartPending = true
        startupEffectsReady = true

        if (badAppleEffectLoader.item && typeof badAppleEffectLoader.item.startPlayback === "function") {
            badAppleEffectLoader.item.startPlayback()
            _badAppleStartPending = false
            return
        }
        // Async Loader: onLoaded calls startPlayback (first click).
    }
    
    // Expose BadAppleEffect for stopping
    property var badAppleEffect: badAppleEffectLoader.item
    
    // Universal darkening overlay (safe, no triangles)
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.35)
        z: -4
        visible: backgroundMode !== 0 && !snowEffectEnabled  // No overlay when snow is enabled
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

