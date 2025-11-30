import QtMultimedia
import QtQuick
import QtQuick.Layouts
import QtCore
import s3rp3nt_media 1.0 as S3rp3ntMedia

Item {
    id: videoPlayer
    
    property url source: ""
    property real volume: 1.0
    
    // Load saved volume - Settings will automatically load and save
    Settings {
        id: videoSettings
        category: "video"
        property alias volume: videoPlayer.volume
    }
    
    property bool showControls: false
    property color accentColor: "#121216"
    property color foregroundColor: "#f5f5f5"
    property real savedVolume: 0.0  // Save volume before muting
    property bool useWMF: true  // Use WMF on Windows, fallback to MediaPlayer
    property bool wmfReady: false  // Set to true only when actually needed
    
    // Sync volume changes from videoPlayer to wmfPlayer (but not via binding to avoid initial 1.0)
    onVolumeChanged: {
        if (wmfPlayer && wmfPlayer.volume !== undefined && Math.abs(wmfPlayer.volume - videoPlayer.volume) > 0.001) {
            console.log("[VideoPlayer] onVolumeChanged: Syncing", videoPlayer.volume, "-> wmfPlayer")
            wmfPlayer.volume = videoPlayer.volume
        }
    }
    
    signal durationAvailable()
    signal playbackStateUpdated()
    
    function formatTime(ms) {
        if (!ms || ms <= 0) return "0:00"
        const totalSeconds = Math.floor(ms / 1000)
        const minutes = Math.floor(totalSeconds / 60)
        const seconds = totalSeconds % 60
        return minutes + ":" + (seconds < 10 ? "0" : "") + seconds
    }
    
    // WMF Video Player (Windows only, better for problematic videos)
    // Lazy-loaded to avoid slow startup when not viewing videos
    property var wmfPlayer: wmfLoader.item
    
    Loader {
        id: wmfLoader
        // Only load when explicitly ready AND has a valid video source
        active: videoPlayer.wmfReady && videoPlayer.useWMF && videoPlayer.source !== ""
        sourceComponent: S3rp3ntMedia.WMFVideoPlayer {
            id: wmfPlayerInstance
            source: videoPlayer.source
        // Don't bind volume initially - set it manually after Settings loads
        videoSink: videoDisplay.videoSink
        
        Component.onCompleted: {
            // Set volume from videoPlayer after Settings has loaded
            // This prevents the binding from setting it to 1.0 before Settings loads
            volume = videoPlayer.volume
            console.log("[VideoPlayer] wmfPlayer onCompleted: Set volume to", volume)
        }
        
        onDurationChanged: {
                if (duration > 0) {
                    console.log("[WMF] Duration available:", duration, "ms")
                // Ensure volume is synced after video is loaded
                    if (Math.abs(volume - videoPlayer.volume) > 0.001) {
                    console.log("[WMF] Syncing volume:", videoPlayer.volume, "-> wmfPlayer")
                        volume = videoPlayer.volume
                }
                    videoPlayer.durationAvailable()
                // Don't trigger auto-fix for WMF - it handles problematic videos better
                console.log("[WMF] Using WMF player - no auto-fix needed")
            }
        }
        
        onPlaybackStateChanged: {
                videoPlayer.playbackStateUpdated()
                if (playbackState === 1) { // Playing
                    videoPlayer.showControls = true
                controlsHideTimer.start()
            } else {
                    videoPlayer.showControls = true
                controlsHideTimer.stop()
            }
        }
        
        onErrorOccurred: function(error, errorString) {
            console.error("[WMF] Error occurred:", error, errorString)
            // Fallback to MediaPlayer on error
            if (videoPlayer.useWMF) {
                console.log("[WMF] Falling back to MediaPlayer")
                videoPlayer.useWMF = false
                }
            }
        }
    }
    
    // Fallback MediaPlayer (FFmpeg-based) - only active when not using WMF
    MediaPlayer {
        id: mediaPlayer
        source: videoPlayer.useWMF ? "" : videoPlayer.source
        audioOutput: AudioOutput {
            id: audioOutput
            volume: videoPlayer.volume
        }
        videoOutput: videoDisplay
        // Explicitly stop when using WMF to prevent FFmpeg initialization
        Component.onCompleted: {
            if (videoPlayer.useWMF) {
                mediaPlayer.stop()
            }
        }
    }
    
    VideoOutput {
        id: videoDisplay
        anchors.fill: parent
        fillMode: VideoOutput.PreserveAspectFit
        visible: videoPlayer.source !== ""
    }
    
    property bool isFixingVideo: false
    property url originalVideoSource: ""
    property url fixedVideoUrl: ""
    property int lastPosition: 0
    property int positionStallCount: 0
    
    // Timer to auto-fix video after it loads (only for MediaPlayer/FFmpeg, not WMF)
    Timer {
        id: autoFixTimer
        interval: 3000
        running: false
        repeat: false
        onTriggered: {
            // Don't auto-fix if using WMF - WMF handles problematic videos better
            if (videoPlayer.useWMF) {
                console.log("[Video] Skipping auto-fix - using WMF which handles problematic videos better")
                return
            }
            
            console.log("[Video] ===== AUTO-FIX TIMER TRIGGERED =====")
            console.log("[Video] isFixingVideo:", videoPlayer.isFixingVideo)
            console.log("[Video] originalVideoSource:", videoPlayer.originalVideoSource)
            // Check if originalVideoSource is empty (url properties need special handling)
            const sourceStr = String(videoPlayer.originalVideoSource)
            const isEmpty = !videoPlayer.originalVideoSource || sourceStr === "" || sourceStr === "null" || sourceStr === "undefined"
            console.log("[Video] Timer isEmpty check:", isEmpty, "sourceStr:", sourceStr)
            if (!videoPlayer.isFixingVideo && isEmpty) {
                console.log("[Video] Checking ColorUtils availability...")
                if (typeof ColorUtils !== "undefined") {
                    console.log("[Video] ColorUtils is available")
                    if (ColorUtils.isFFmpegAvailable) {
                        console.log("[Video] Checking FFmpeg...")
                        const available = ColorUtils.isFFmpegAvailable()
                        console.log("[Video] FFmpeg available:", available)
                        if (available) {
                            console.log("[Video] Auto-fixing video...")
                            videoPlayer.attemptVideoFix()
                        } else {
                            console.log("[Video] FFmpeg not available for auto-fix")
                        }
                    } else {
                        console.log("[Video] ColorUtils.isFFmpegAvailable function not found")
                    }
                } else {
                    console.log("[Video] ColorUtils is not available")
                }
            } else {
                console.log("[Video] Skipping auto-fix - isFixingVideo:", videoPlayer.isFixingVideo, "isEmpty:", isEmpty)
            }
        }
    }
    
    function attemptVideoFix() {
        // Check if already fixing or already fixed (url properties need special handling)
        const sourceStr = String(videoPlayer.originalVideoSource)
        const hasOriginalSource = videoPlayer.originalVideoSource && sourceStr !== "" && sourceStr !== "null" && sourceStr !== "undefined"
        console.log("[Video] attemptVideoFix called - isFixingVideo:", videoPlayer.isFixingVideo, "hasOriginalSource:", hasOriginalSource, "sourceStr:", sourceStr)
        if (videoPlayer.isFixingVideo || hasOriginalSource) {
            console.log("[Video] Fix already in progress or completed")
            return
        }
        
        console.log("[Video] Attempting to fix video...")
        videoPlayer.isFixingVideo = true
        videoPlayer.originalVideoSource = videoPlayer.source
        
        if (typeof ColorUtils === "undefined") {
            console.log("[Video] ERROR: ColorUtils is not available")
            videoPlayer.isFixingVideo = false
            videoPlayer.originalVideoSource = ""
            return
        }
        
        if (!ColorUtils.isFFmpegAvailable) {
            console.log("[Video] ERROR: ColorUtils.isFFmpegAvailable function not found")
            videoPlayer.isFixingVideo = false
            videoPlayer.originalVideoSource = ""
            return
        }
        
        console.log("[Video] Checking FFmpeg availability...")
        const available = ColorUtils.isFFmpegAvailable()
        console.log("[Video] FFmpeg available:", available)
        
        if (!available) {
            console.log("[Video] FFmpeg is not available. Please install FFmpeg and add it to your PATH.")
            console.log("[Video] Download from: https://ffmpeg.org/download.html")
            videoPlayer.isFixingVideo = false
            videoPlayer.originalVideoSource = ""
            return
        }
        
        if (!ColorUtils.fixVideoFile) {
            console.log("[Video] ERROR: ColorUtils.fixVideoFile function not found")
            videoPlayer.isFixingVideo = false
            videoPlayer.originalVideoSource = ""
            return
        }
        
        console.log("[Video] FFmpeg is available, starting fix process...")
        console.log("[Video] Source video:", videoPlayer.originalVideoSource)
        Qt.callLater(function() {
            const fixedUrl = ColorUtils.fixVideoFile(videoPlayer.originalVideoSource)
            console.log("[Video] Fix result:", fixedUrl)
            if (fixedUrl && fixedUrl !== "") {
                console.log("[Video] Fixed video ready, switching to fixed version:", fixedUrl)
                videoPlayer.fixedVideoUrl = fixedUrl
                videoPlayer.source = fixedUrl
            } else {
                console.log("[Video] Failed to fix video - check FFmpeg output above")
                videoPlayer.isFixingVideo = false
                videoPlayer.originalVideoSource = ""
            }
        })
    }
    
    // Monitor for stuttering by tracking position updates
    Timer {
        id: positionMonitor
        interval: 500
        running: mediaPlayer.playbackState === MediaPlayer.PlayingState && videoPlayer.source !== "" && !videoPlayer.isFixingVideo
        repeat: true
        onTriggered: {
            const currentPos = mediaPlayer.position
            const expectedPos = videoPlayer.lastPosition + 500 // Expected position if playing normally
            
            // Check if position is significantly behind expected (stuttering)
            if (currentPos > 0 && mediaPlayer.duration > 0) {
                const diff = Math.abs(currentPos - expectedPos)
                if (diff > 1000 || currentPos === videoPlayer.lastPosition) {
                    videoPlayer.positionStallCount++
                    // If position is stalled or significantly behind for 2 seconds, likely stuttering
                    if (videoPlayer.positionStallCount >= 4 && !videoPlayer.isFixingVideo && videoPlayer.originalVideoSource === "") {
                        console.log("[Video] Detected stuttering (position stall) - attempting to fix video...")
                        videoPlayer.attemptVideoFix()
                    }
                } else {
                    videoPlayer.positionStallCount = 0
                }
            }
            videoPlayer.lastPosition = currentPos
        }
    }
    
    Connections {
        target: mediaPlayer
        function onSourceChanged() {
            if (mediaPlayer.source !== "") {
                console.log("[Video] Loading video:", mediaPlayer.source)
                // Small delay to let MediaPlayer initialize properly
                Qt.callLater(function() {
                    mediaPlayer.play()
                })
            }
        }
        function onErrorOccurred(error, errorString) {
            if (errorString) {
                console.error("[Video] Error occurred:", error, errorString)
            }
            // Try to continue playback even with minor errors
            if (mediaPlayer.playbackState === MediaPlayer.StoppedState) {
                Qt.callLater(function() {
                    mediaPlayer.play()
                })
            }
        }
        function onDurationChanged() {
            if (mediaPlayer.duration > 0 && !videoPlayer.useWMF) {
                console.log("[Video] Duration available:", mediaPlayer.duration, "ms")
                console.log("[Video] isFixingVideo:", videoPlayer.isFixingVideo)
                console.log("[Video] originalVideoSource:", videoPlayer.originalVideoSource)
                durationAvailable()
                // Automatically attempt fix 3 seconds after video loads (to catch timestamp warnings)
                // Only for MediaPlayer (FFmpeg), not for WMF
                // Check if originalVideoSource is empty (url properties need special handling)
                const sourceStr = String(videoPlayer.originalVideoSource)
                const isEmpty = !videoPlayer.originalVideoSource || sourceStr === "" || sourceStr === "null" || sourceStr === "undefined"
                console.log("[Video] isEmpty check:", isEmpty, "sourceStr:", sourceStr)
                if (!videoPlayer.isFixingVideo && isEmpty) {
                    console.log("[Video] Scheduling auto-fix in 3 seconds...")
                    autoFixTimer.start()
                } else {
                    console.log("[Video] Skipping auto-fix - isFixingVideo:", videoPlayer.isFixingVideo, "isEmpty:", isEmpty)
                }
            }
        }
        function onPlaybackStateChanged() {
            playbackStateUpdated()
            if (mediaPlayer.playbackState === MediaPlayer.PlayingState) {
                showControls = true
                controlsHideTimer.start()
            } else {
                showControls = true
                controlsHideTimer.stop()
            }
        }
    }
    
    Connections {
        target: audioOutput
        function onVolumeChanged(vol) {
            if (Math.abs(videoPlayer.volume - vol) > 0.001) {
                videoPlayer.volume = vol
            }
        }
    }
    
    Connections {
        target: wmfPlayer
        enabled: wmfPlayer !== null
        function onVolumeChanged(vol) {
            // Sync volume from wmfPlayer to videoPlayer (and save to Settings)
            if (Math.abs(videoPlayer.volume - vol) > 0.001) {
                videoPlayer.volume = vol
            }
        }
    }
    
    
    Timer {
        id: controlsHideTimer
        interval: 3000
        running: false
        onTriggered: {
            if (videoPlayer.playbackState === 1 && !controlsMouseArea.containsMouse) {
                showControls = false
            }
        }
    }
    
    // Video controls overlay
    Item {
        id: controlsContainer
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 24
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(500, parent.width - 48)
        height: 50
        visible: videoPlayer.source !== ""
        opacity: (controlsMouseArea.containsMouse || videoPlayer.playbackState !== 1 || showControls) ? 1.0 : 0.0
        Behavior on opacity { NumberAnimation { duration: 200 } }
        
        MouseArea {
            id: controlsMouseArea
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
            onEntered: {
                showControls = true
                controlsHideTimer.stop()
            }
            onExited: {
                if (videoPlayer.playbackState === 1) {
                    showControls = true
                    controlsHideTimer.restart()
                }
            }
        }
        
        AudioControls {
            id: audioControls
            anchors.fill: parent
            position: videoPlayer.position
            duration: videoPlayer.duration
            volume: videoPlayer.volume
            playbackState: videoPlayer.playbackState
            seekable: videoPlayer.seekable
            accentColor: videoPlayer.accentColor
            muted: (videoPlayer.useWMF && wmfPlayer) ? (wmfPlayer.volume === 0 && videoPlayer.volume > 0) : (audioOutput.volume === 0 && videoPlayer.volume > 0)
            
            onPlayClicked: {
                videoPlayer.play()
                showControls = true
                controlsHideTimer.restart()
            }
            
            onPauseClicked: {
                videoPlayer.pause()
                showControls = true
            }
            
            onSeekRequested: function(pos) {
                if (videoPlayer.useWMF && wmfPlayer) {
                    wmfPlayer.seek(pos)
                } else {
                    mediaPlayer.position = pos
                }
            }
            
            onVolumeAdjusted: function(vol) {
                videoPlayer.volume = vol
                if (videoPlayer.useWMF && wmfPlayer) {
                    wmfPlayer.volume = vol
                } else {
                    audioOutput.volume = vol
                }
                // If volume is adjusted while muted, unmute and update saved volume
                if (vol > 0 && videoPlayer.savedVolume === 0) {
                    videoPlayer.savedVolume = vol
                } else if (vol > 0) {
                    videoPlayer.savedVolume = vol
                }
            }
            
            onMuteToggled: function(isMuted) {
                if (isMuted) {
                    // Save current volume before muting (only if not already muted)
                    const currentVol = videoPlayer.volume
                    if (currentVol > 0) {
                        videoPlayer.savedVolume = currentVol
                        videoPlayer.volume = currentVol  // Sync the property
                    }
                    // Mute by setting volume to 0
                    if (videoPlayer.useWMF && wmfPlayer) {
                        wmfPlayer.volume = 0
                    } else {
                        audioOutput.volume = 0
                    }
                } else {
                    // Restore saved volume
                    if (videoPlayer.savedVolume > 0) {
                        videoPlayer.volume = videoPlayer.savedVolume
                        if (videoPlayer.useWMF && wmfPlayer) {
                            wmfPlayer.volume = videoPlayer.savedVolume
                        } else {
                            audioOutput.volume = videoPlayer.savedVolume
                        }
                    } else {
                        // If no saved volume, restore to a reasonable default (0.5)
                        videoPlayer.volume = 0.5
                        if (videoPlayer.useWMF && wmfPlayer) {
                            wmfPlayer.volume = 0.5
                        } else {
                            audioOutput.volume = 0.5
                        }
                    }
                }
            }
            
            onLoopClicked: {
                // Video loop functionality if needed
            }
            
            onMoreClicked: {
                // Trigger video fix manually
                console.log("[Video] Manual fix requested")
                if (typeof ColorUtils !== "undefined") {
                    if (ColorUtils.isFFmpegAvailable) {
                        const available = ColorUtils.isFFmpegAvailable()
                        console.log("[Video] FFmpeg available check:", available)
                        if (available) {
                            videoPlayer.attemptVideoFix()
                        } else {
                            console.log("[Video] FFmpeg is not available. Please install FFmpeg to fix videos.")
                            console.log("[Video] Download from: https://ffmpeg.org/download.html")
                            console.log("[Video] Make sure FFmpeg is in your system PATH")
                        }
                    } else {
                        console.log("[Video] ColorUtils.isFFmpegAvailable function not found")
                    }
                } else {
                    console.log("[Video] ColorUtils not available")
                }
            }
        }
    }
    
    
    // Expose video properties (use WMF if available and loaded, otherwise MediaPlayer)
    property int duration: (useWMF && wmfPlayer) ? wmfPlayer.duration : mediaPlayer.duration
    property int position: (useWMF && wmfPlayer) ? wmfPlayer.position : mediaPlayer.position
    property int playbackState: (useWMF && wmfPlayer) ? wmfPlayer.playbackState : mediaPlayer.playbackState
    property bool hasVideo: (useWMF && wmfPlayer) ? true : mediaPlayer.hasVideo
    property bool hasAudio: (useWMF && wmfPlayer) ? true : mediaPlayer.hasAudio
    property var metaData: (useWMF && wmfPlayer) ? ({}) : mediaPlayer.metaData
    property int implicitWidth: videoDisplay.implicitWidth
    property int implicitHeight: videoDisplay.implicitHeight
    property bool seekable: (useWMF && wmfPlayer) ? wmfPlayer.seekable : mediaPlayer.seekable
    property real playbackRate: (useWMF && wmfPlayer) ? 1.0 : mediaPlayer.playbackRate
    
    function play() { 
        if (useWMF && wmfPlayer) {
            wmfPlayer.play()
        } else {
            mediaPlayer.play()
        }
    }
    function pause() { 
        if (useWMF && wmfPlayer) {
            wmfPlayer.pause()
        } else {
            mediaPlayer.pause()
        }
    }
    function stop() { 
        if (useWMF && wmfPlayer) {
            wmfPlayer.stop()
        } else {
            mediaPlayer.stop()
        }
    }
    
    onSourceChanged: {
        if (source !== "") {
            // Reset fixing state when source changes (unless it's the fixed version)
            if (source !== fixedVideoUrl) {
                isFixingVideo = false
                originalVideoSource = ""
                positionStallCount = 0
                lastPosition = 0
            }
            // Enable WMF loader now that we have a real source
            wmfReady = true
            // Only set MediaPlayer source if NOT using WMF
            // WMF player gets source automatically via binding
            if (!useWMF) {
                mediaPlayer.source = source
                mediaPlayer.play()
            } else {
                // When using WMF, ensure MediaPlayer is stopped and cleared
                mediaPlayer.stop()
                mediaPlayer.source = ""
            }
        } else {
            // Disable WMF loader when source is cleared
            wmfReady = false
        }
    }
}

