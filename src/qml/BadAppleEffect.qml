import QtQuick
import QtMultimedia

// Bad Apple renderer using shader (snow-style pixel rendering)
// Easter egg: plays Bad Apple!! audio and animation when activated
Item {
    id: badAppleEffect
    
    property bool effectEnabled: false  // Doesn't auto-play
    property real effectOpacity: 1.0
    property color silhouetteColor: "white"
    property real frameIndex: 0.0  // Current frame (0-6571 for full Bad Apple)
    property real frameRate: 30.0  // Frames per second
    property bool playing: false  // Only true when Bad Apple!! is actually playing (writable)
    property bool framesLoaded: false
    property url frameTextureUrl: ""
    
    // Actual visibility - only show when playing
    property bool shouldShow: effectEnabled && playing
    
    anchors.fill: parent
    visible: shouldShow
    
    // Keep startup fast: defer frame/texture loading until playback is requested.
    function ensureFramesLoaded() {
        if (framesLoaded) {
            return
        }
        if (typeof ColorUtils === "undefined") {
            console.log("[BadApple] ColorUtils unavailable - using procedural generation")
            return
        }

        const appDir = ColorUtils.getAppDirectory()
        const normalizedDir = appDir.replace(/\\/g, "/")
        const binaryPath = "file:///" + normalizedDir + "/badapple_frames.bin"

        if (ColorUtils.loadBadAppleFrames(binaryPath)) {
            frameTextureUrl = ColorUtils.createBadAppleTexture()
            framesLoaded = (frameTextureUrl !== "")
            if (framesLoaded) {
                console.log("[BadApple] Frames loaded successfully")
            } else {
                console.log("[BadApple] Texture creation failed - using procedural generation")
            }
        } else {
            console.log("[BadApple] Frame loading failed - using procedural generation")
        }
    }
    
    opacity: shouldShow ? effectOpacity : 0.0
    
    Behavior on opacity {
        NumberAnimation {
            duration: 300
            easing.type: Easing.OutCubic
        }
    }
    
    // Time property for animation
    property real time: 0.0
    
    // Hidden image to load the texture
    Image {
        id: frameTextureImage
        visible: false
        source: badAppleEffect.frameTextureUrl
        asynchronous: true
        smooth: false  // Pixel-perfect for Bad Apple
    }
    
    // ShaderEffectSource wraps the image for Vulkan-compatible texture binding
    ShaderEffectSource {
        id: frameTextureSource
        sourceItem: frameTextureImage
        visible: false
        smooth: false
        hideSource: true
        live: false  // Static texture, no need to update every frame
    }
    
    ShaderEffect {
        anchors.fill: parent
        
        property real u_time: badAppleEffect.time
        property real u_frameIndex: badAppleEffect.frameIndex
        property real u_intensity: badAppleEffect.effectOpacity
        property vector2d u_resolution: Qt.vector2d(width, height)
        property color u_color: badAppleEffect.silhouetteColor
        // Pass ShaderEffectSource for Vulkan-compatible texture binding
        property var u_frameTexture: (badAppleEffect.framesLoaded && frameTextureImage.status === Image.Ready) ? frameTextureSource : null
        property bool u_useFrameTexture: badAppleEffect.framesLoaded && frameTextureImage.status === Image.Ready
        
        fragmentShader: Qt.resolvedUrl("qrc:/resources/shaders/badapple.frag.qsb")
    }
    
    // Dedicated MediaPlayer for Bad Apple audio
    MediaPlayer {
        id: badAppleAudioPlayer
        audioOutput: AudioOutput {
            id: badAppleAudioOutput
            volume: 0.2  // 20% volume
        }
        
        // Load Bad Apple!!.mp3 from app directory
        Component.onCompleted: {
            if (typeof ColorUtils !== "undefined") {
                const appDir = ColorUtils.getAppDirectory()
                const normalizedDir = appDir.replace(/\\/g, "/")
                const audioPath = "file:///" + normalizedDir + "/Bad Apple!!.mp3"
                badAppleAudioPlayer.source = audioPath
            }
        }
        
        onPlaybackStateChanged: {
            if (playbackState === MediaPlayer.PlayingState) {
                badAppleEffect.playing = true
            } else if (playbackState === MediaPlayer.StoppedState || playbackState === MediaPlayer.PausedState) {
                badAppleEffect.playing = false
            }
        }
        
        onPositionChanged: function(position) {
            if (badAppleEffect.playing) {
                badAppleEffect.syncToAudioPosition(position)
            }
        }
    }
    
    // Monitor audio player position for Bad Apple!! playback
    // Sync at high frequency for smooth animation (8ms = 125 FPS checks)
    Timer {
        id: positionSyncTimer
        interval: 8  // Very high frequency sync for smooth animation
        running: shouldShow && playing
        repeat: true
        onTriggered: {
            if (playing && badAppleAudioPlayer.position !== undefined) {
                const position = badAppleAudioPlayer.position
                if (position > 0) {
                    syncToAudioPosition(position)
                }
            }
        }
    }
    
    // Drive time and frame index (fallback when not synced to audio)
    Timer {
        id: frameTimer
        interval: 1000.0 / badAppleEffect.frameRate  // ~33ms for 30 FPS
        running: shouldShow && !playing && badAppleEffect.opacity > 0
        repeat: true
        onTriggered: {
            badAppleEffect.frameIndex += 1.0
            badAppleEffect.time += interval / 1000.0
            
            // Loop at 6572 frames (Bad Apple!! length)
            if (badAppleEffect.frameIndex >= 6572.0) {
                badAppleEffect.frameIndex = 0.0
            }
        }
    }
    
    // Drive time continuously for shader effects
    NumberAnimation on time {
        from: 0
        to: 100000
        duration: 100000000
        loops: Animation.Infinite
        running: shouldShow && badAppleEffect.opacity > 0
    }
    
    // Function to sync with audio position (in milliseconds)
    function syncToAudioPosition(positionMs) {
        // Bad Apple is ~219 seconds at 30 FPS
        const totalFrames = 6572
        const totalDurationMs = 219000
        
        if (positionMs >= 0 && positionMs <= totalDurationMs) {
            // Calculate frame index with sub-frame precision for smoother updates
            const exactFrameIndex = (positionMs / totalDurationMs) * totalFrames
            // Always update for smooth synchronization (no frame change check)
            frameIndex = exactFrameIndex
            
            // Clamp to valid range
            if (frameIndex >= totalFrames) {
                frameIndex = frameIndex % totalFrames
            }
        } else if (positionMs > totalDurationMs) {
            // Loop back to start if past end
            frameIndex = 0
        }
    }
    
    // Function to start Bad Apple playback
    function startPlayback() {
        ensureFramesLoaded()
        // Enable the effect first
        effectEnabled = true
        // Reset animation state
        frameIndex = 0.0
        time = 0.0
        // Reset and start audio
        badAppleAudioPlayer.stop()
        badAppleAudioPlayer.position = 0
        Qt.callLater(function() {
            badAppleAudioPlayer.play()
            badAppleEffect.playing = true
        })
        console.log("[BadApple] Starting playback - effectEnabled:", effectEnabled)
    }
    
    // Function to stop Bad Apple playback
    function stopPlayback() {
        badAppleAudioPlayer.stop()
        badAppleAudioPlayer.position = 0
        frameIndex = 0.0
        time = 0.0
        playing = false
        effectEnabled = false
        console.log("[BadApple] Stopped playback")
    }
    
    // Function to reset to frame 0
    function reset() {
        frameIndex = 0.0
        time = 0.0
        badAppleAudioPlayer.stop()
        badAppleAudioPlayer.position = 0
    }
}
