import QtMultimedia
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Window
import Qt5Compat.GraphicalEffects
import QtCore
import s3rp3nt_media 1.0 as S3rp3ntMedia

Item {
    id: videoPlayer
    
    // CRITICAL: Ensure no default white background shows through
    // Item doesn't have a color property, but we ensure children fill completely
    
    property var windowRef: null  // Window reference for accessing window properties
    property var resizeTimersRef: null  // Resize timers reference
    property url source: ""
    property real volume: 1.0
    property int videoRotation: 0  // Rotation in degrees (0, 90, 180, 270)
    
    // Update libmpv rotation when videoRotation changes
    onVideoRotationChanged: {
        if (useLibmpv && mpvPlayer) {
            mpvPlayer.setRotation(videoRotation)
        }
    }
    
    // MediaPlayerWrapper for subtitle formatting (not used for playback, only formatting)
    S3rp3ntMedia.MediaPlayerWrapper {
        id: subtitleWrapper
        // Note: MediaPlayerWrapper is a QObject, not a visual item, so it doesn't have 'visible' property
    }
    
    // Compact loading indicator for subtitle extraction (top-left)
    Rectangle {
        id: subtitleExtractionIndicator
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.margins: 12
        width: extractionText.width + extractionSpinner.width + 20
        height: 32
        radius: 16
        color: Qt.rgba(0, 0, 0, 0.75)
        opacity: 0
        visible: opacity > 0
        z: 1000
        
        property bool shouldShow: false
        
        onShouldShowChanged: {
            if (shouldShow) {
                // Show immediately, then fade out after 1.5 seconds
                opacity = 1.0
                fadeOutTimer.restart()
            }
        }
        
        Connections {
            target: embeddedSubtitleExtractor
            function onExtractingChanged() {
                if (embeddedSubtitleExtractor.extracting) {
                    subtitleExtractionIndicator.shouldShow = true
                }
            }
        }
        
        Timer {
            id: fadeOutTimer
            interval: 1500
            onTriggered: {
                fadeOutAnimation.start()
            }
        }
        
        NumberAnimation {
            id: fadeOutAnimation
            target: subtitleExtractionIndicator
            property: "opacity"
            to: 0.0
            duration: 300
        }
        
        Row {
            anchors.centerIn: parent
            spacing: 8
            leftPadding: 14
            rightPadding: 14
            
            BusyIndicator {
                id: extractionSpinner
                running: embeddedSubtitleExtractor.extracting && subtitleExtractionIndicator.opacity > 0
                width: 14
                height: 14
            }
            
            Text {
                id: extractionText
                text: "Extracting Subtitles..."
                color: "#FFFFFF"
                font.pixelSize: 12
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }
    
    // Compact notification for subtitle extraction status (top-left)
    Rectangle {
        id: subtitleExtractionNotification
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.margins: 12
        width: notificationText.width + 20
        height: 28
        radius: 14
        color: notificationError ? Qt.rgba(200, 50, 50, 0.85) : Qt.rgba(50, 150, 50, 0.85)
        opacity: 0
        visible: opacity > 0
        z: 1000
        
        property bool notificationError: false
        
        function show(message, isError) {
            notificationText.text = message
            notificationError = isError
            notificationAnimation.restart()
        }
        
        Text {
            id: notificationText
            anchors.centerIn: parent
            color: "#FFFFFF"
            font.pixelSize: 12
            font.bold: true
        }
        
        SequentialAnimation {
            id: notificationAnimation
            NumberAnimation { 
                target: subtitleExtractionNotification
                property: "opacity"
                to: 1.0
                duration: 200
            }
            PauseAnimation { duration: 1500 }
            NumberAnimation { 
                target: subtitleExtractionNotification
                property: "opacity"
                to: 0.0
                duration: 300
            }
        }
    }
    
    // Embedded subtitle extractor - extracts subtitles using FFmpeg
    // Used in "external" mode to extract embedded subtitles for custom engine rendering
    S3rp3ntMedia.EmbeddedSubtitleExtractor {
        id: embeddedSubtitleExtractor
        enabled: subtitleEngine === "external"  // Custom engine works with both external files and embedded subtitles
        
        onExtractingChanged: {
            if (extracting) {
                console.log("[VideoPlayer] ⏳ Starting subtitle extraction (this may take a moment for large files)...")
                console.log("[VideoPlayer] 💡 Tip: This is a one-time process. Subtitles will load instantly from cache next time!")
            }
        }
        
        onExtractionFinished: function(success) {
            if (success) {
                console.log("[VideoPlayer] ===== ✅ EMBEDDED SUBTITLE EXTRACTION SUCCESSFUL =====")
                console.log("[VideoPlayer] Subtitles extracted and ready for custom engine rendering")
                subtitleExtractionNotification.show("Loaded", false)
                // Start updating subtitles based on video position (for custom engine)
                if (subtitleEngine === "external") {
                    console.log("[VideoPlayer] Starting subtitle update timer for custom engine")
                    embeddedSubtitleUpdateTimer.restart()
                } else {
                    console.warn("[VideoPlayer] ⚠️  WARNING: Extraction finished but subtitleEngine is not 'external' - custom engine won't be used!")
                    console.warn("[VideoPlayer] ⚠️  Please switch to 'external' mode in settings to use the custom engine")
                }
            } else {
                console.error("[VideoPlayer] ===== ❌ EMBEDDED SUBTITLE EXTRACTION FAILED =====")
                console.error("[VideoPlayer] FFmpeg extraction failed - check if FFmpeg is installed and accessible")
                subtitleExtractionNotification.show("Failed", true)
            }
        }
        
        onCurrentSubtitleTextChanged: {
            // Update the displayed subtitle text (for custom engine)
            if (subtitleEngine === "external") {
                // Format the subtitle text using the formatter
                if (embeddedSubtitleExtractor.currentSubtitleText !== "") {
                    var rawText = embeddedSubtitleExtractor.currentSubtitleText
                    // Strip ASS formatting codes like {\an8}, {\b1}, etc.
                    var cleanedText = rawText.replace(/\{[^}]*\}/g, "")
                    // Use subtitleWrapper to format the text (handles ASS/SSA codes)
                    subtitleWrapper.setSubtitleText(cleanedText)
                    var formatted = subtitleWrapper.formattedSubtitleText
                    // Convert \n to <br> for RichText display AFTER formatting (RichText doesn't render \n)
                    formatted = formatted.replace(/\n/g, "<br>")
                    formattedSubtitleText = formatted
                    console.log("[VideoPlayer] Custom engine: Updated subtitle text (length:", formattedSubtitleText.length, ")")
                } else {
                    // Clear if no subtitle text
                    formattedSubtitleText = ""
                    console.log("[VideoPlayer] Custom engine: Cleared subtitle text")
                }
            }
        }
    }
    
    // Timer to update embedded subtitles based on video position (for custom engine)
    // Uses cached subtitle data - no FFmpeg calls during playback
    Timer {
        id: embeddedSubtitleUpdateTimer
        interval: 100  // Update every 100ms
        running: subtitleEngine === "external" && embeddedSubtitleExtractor.enabled && 
                 embeddedSubtitleExtractor.activeSubtitleTrack >= 0 &&
                 ((useLibmpv && mpvPlayer && mpvPlayer.playbackState === 1) ||
                  (useWMF && wmfPlayer && wmfPlayer.playbackState === 1) || 
                  (useLibvlc && vlcPlayer && vlcPlayer.playbackState === 1) ||
                  (useFFmpeg && ffmpegPlayer && ffmpegPlayer.playbackState === 1) ||
                  (!useWMF && !useLibmpv && !useLibvlc && !useFFmpeg && mediaPlayer && mediaPlayer.playbackState === MediaPlayer.PlayingState))
        repeat: true
        onRunningChanged: {
            console.log("[VideoPlayer] Subtitle timer running:", running, "subtitleEngine:", subtitleEngine, "enabled:", embeddedSubtitleExtractor.enabled, "track:", embeddedSubtitleExtractor.activeSubtitleTrack)
        }
        onTriggered: {
            var currentPosition = (useLibmpv && mpvPlayer) ? mpvPlayer.position :
                                  (useWMF && wmfPlayer) ? wmfPlayer.position :
                                  (useLibvlc && vlcPlayer) ? vlcPlayer.position :
                                  (useFFmpeg && ffmpegPlayer) ? ffmpegPlayer.position :
                                  (!useWMF && !useLibmpv && !useLibvlc && !useFFmpeg && mediaPlayer ? mediaPlayer.position : 0)
            
            // Use cached subtitle data (no FFmpeg calls - instant!)
            if (currentPosition > 0) {
                embeddedSubtitleExtractor.updateCurrentSubtitle(currentPosition)
            }
        }
    }
    
    // Pre-load subtitle chunks in background when track is selected
    Connections {
        target: embeddedSubtitleExtractor
        function onActiveSubtitleTrackChanged() {
            if (subtitleEngine === "external" && embeddedSubtitleExtractor.activeSubtitleTrack >= 0 && videoPlayer.source !== "") {
                console.log("[VideoPlayer] Pre-loading subtitle chunks for track", embeddedSubtitleExtractor.activeSubtitleTrack)
                // Pre-load first 5 minutes of subtitles in background
                for (var i = 0; i < 5; i++) {
                    var positionMs = i * 60000  // Every minute
                    Qt.callLater(function(pos) {
                        embeddedSubtitleExtractor.readSubtitleAtPosition(videoPlayer.source, embeddedSubtitleExtractor.activeSubtitleTrack, pos)
                    }, positionMs)
                }
            }
        }
    }
    
    // Load saved subtitle engine preference
    Settings {
        id: videoSubtitleSettings
        category: "video"
        property string subtitleEngine: "external"  // "embedded" or "external"
    }
    
    property string subtitleEngine: videoSubtitleSettings.subtitleEngine
    
    // Property to store parsed subtitle entries with timestamps
    property var subtitleEntries: []  // Array of {start: ms, end: ms, text: "..."}
    property string currentSubtitleText: ""  // Current subtitle text to display (raw from extractor)
    property string formattedSubtitleText: ""  // Formatted subtitle text for display
    
    // Function to parse SRT timestamps
    function parseSRTTimestamps(srtText) {
        var entries = []
        var lines = srtText.split('\n')
        var currentEntry = null
        var inSubtitleBlock = false
        
        for (var i = 0; i < lines.length; i++) {
            var line = lines[i].trim()
            
            // Skip empty lines (they separate subtitle blocks)
            if (line === "") {
                if (currentEntry && currentEntry.text !== "") {
                    entries.push(currentEntry)
                }
                currentEntry = null
                inSubtitleBlock = false
                continue
            }
            
            // Check if line is a sequence number (just digits)
            if (/^\d+$/.test(line)) {
                currentEntry = {start: 0, end: 0, text: ""}
                inSubtitleBlock = true
                continue
            }
            
            // Check if line is a timestamp (contains -->)
            if (line.indexOf('-->') !== -1) {
                if (currentEntry) {
                    // Parse timestamp: "00:00:00,000 --> 00:00:05,000"
                    var parts = line.split('-->')
                    if (parts.length === 2) {
                        var startTime = parseSRTTime(parts[0].trim())
                        var endTime = parseSRTTime(parts[1].trim())
                        currentEntry.start = startTime
                        currentEntry.end = endTime
                    }
                }
                continue
            }
            
            // This is subtitle text
            if (inSubtitleBlock && currentEntry) {
                if (currentEntry.text !== "") {
                    currentEntry.text += "<br>"
                }
                currentEntry.text += line
            }
        }
        
        // Add last entry if exists
        if (currentEntry && currentEntry.text !== "") {
            entries.push(currentEntry)
        }
        
        return entries
    }
    
    // Function to parse SRT time format: "00:00:00,000" or "00:00:00.000"
    function parseSRTTime(timeStr) {
        // Replace comma with dot for milliseconds
        timeStr = timeStr.replace(',', '.')
        // Parse format: HH:MM:SS.mmm
        var parts = timeStr.split(':')
        if (parts.length === 3) {
            var hours = parseInt(parts[0]) || 0
            var minutes = parseInt(parts[1]) || 0
            var secondsParts = parts[2].split('.')
            var seconds = parseInt(secondsParts[0]) || 0
            var milliseconds = parseInt(secondsParts[1]) || 0
            
            return (hours * 3600 + minutes * 60 + seconds) * 1000 + milliseconds
        }
        return 0
    }
    
    // Update current subtitle based on video position
    function updateCurrentSubtitle() {
        if (!(videoPlayer.useWMF && videoPlayer.wmfPlayer) && mediaPlayer) {
            var currentPosition = mediaPlayer.position  // in milliseconds
            var currentText = ""
            
            // Find subtitle entry that matches current position
            for (var i = 0; i < subtitleEntries.length; i++) {
                var entry = subtitleEntries[i]
                if (currentPosition >= entry.start && currentPosition <= entry.end) {
                    currentText = entry.text
                    break
                }
            }
            
            if (currentSubtitleText !== currentText) {
                currentSubtitleText = currentText
            }
        }
    }
    
    // Timer to update subtitle based on video position
    Timer {
        id: subtitleUpdateTimer
        interval: 100  // Update every 100ms
        running: !(videoPlayer.useWMF && videoPlayer.wmfPlayer) && mediaPlayer && mediaPlayer.playbackState === MediaPlayer.PlayingState && subtitleEntries.length > 0
        repeat: true
        onTriggered: {
            updateCurrentSubtitle()
        }
    }
    
    // Load saved volume and player preference - Settings will automatically load and save
    Settings {
        id: videoSettings
        category: "video"
        property alias volume: videoPlayer.volume
        property bool useWMF: false  // Legacy: kept for backward compatibility
        property string videoBackend: "mediaplayer"  // "mediaplayer", "wmf", "libmpv", "libvlc", or "ffmpeg"
        property string mpvRendererMode: "opengl"  // "opengl" or "d3d11" (only applies when videoBackend is "libmpv")
        
        onVideoBackendChanged: {
            console.log("[VideoPlayer] Settings videoBackend changed to:", videoBackend)
            // Trigger backend update
            videoPlayer.updateBackendReadyFlags()
        }
    }
    
    property bool showControls: false
    property color accentColor: "#121216"
    property color foregroundColor: "#f5f5f5"
    property real savedVolume: 0.0  // Save volume before muting
    
    // Seek debouncing state
    property bool _isSeeking: false
    property real _pendingSeekPos: -1.0  // -1 means no pending seek
    property bool _wasPlayingBeforeSeek: false
    
    // Determine which backend to use (new setting with legacy fallback)
    readonly property string videoBackend: {
        var backend = videoSettings.videoBackend || "mediaplayer"
        // Legacy compatibility: if videoBackend not set but useWMF is, use that
        if (backend === "mediaplayer" && videoSettings.useWMF) {
            return "wmf"
        }
        return backend
    }
    
    // Legacy properties for backward compatibility
    property bool useWMF: videoBackend === "wmf"
    property bool useLibmpv: videoBackend === "libmpv"
    property bool useLibvlc: videoBackend === "libvlc"
    property bool useFFmpeg: videoBackend === "ffmpeg"
    property bool wmfReady: false  // Set to true only when actually needed
    property bool libmpvReady: false  // Set to true only when libmpv is needed
    property bool libvlcReady: false  // Set to true only when libvlc is needed
    property bool ffmpegReady: false  // Set to true only when FFmpeg is needed
    
    // Function to update backend ready flags when backend changes
    function updateBackendReadyFlags() {
        console.log("[VideoPlayer] Updating backend ready flags, backend:", videoBackend, "useFFmpeg:", useFFmpeg, "source:", source !== "" ? "loaded" : "none")
        // Update ready flags based on current backend
        if (source !== "") {
            // If video is already loaded, update ready flags and reload
            if (useWMF) {
                console.log("[VideoPlayer] Setting WMF ready")
                wmfReady = true
                libmpvReady = false
                libvlcReady = false
                ffmpegReady = false
            } else if (useLibmpv) {
                console.log("[VideoPlayer] Setting libmpv ready")
                wmfReady = false
                libmpvReady = true
                libvlcReady = false
                ffmpegReady = false
            } else if (useLibvlc) {
                console.log("[VideoPlayer] Setting libvlc ready")
                wmfReady = false
                libmpvReady = false
                libvlcReady = true
                ffmpegReady = false
            } else if (useFFmpeg) {
                console.log("[VideoPlayer] Setting FFmpeg ready")
                wmfReady = false
                libmpvReady = false
                libvlcReady = false
                ffmpegReady = true
            } else {
                console.log("[VideoPlayer] Setting MediaPlayer (no backend ready flags)")
                wmfReady = false
                libmpvReady = false
                libvlcReady = false
                ffmpegReady = false
            }
            
            // Trigger reload by temporarily clearing and restoring source.
            // Keep an immutable copy to avoid restoring an emptied URL object.
            const currentSource = source.toString()
            source = ""
            Qt.callLater(function() {
                if (videoPlayer.source === "" && currentSource !== "") {
                    videoPlayer.source = currentSource
                }
            })
        } else {
            // No video loaded, just reset ready flags
            wmfReady = false
            libmpvReady = false
            libvlcReady = false
            ffmpegReady = false
        }
    }
    
    // Sync volume changes from videoPlayer to active player (but not via binding to avoid initial 1.0)
    onVolumeChanged: {
        if (wmfPlayer && wmfPlayer.volume !== undefined && Math.abs(wmfPlayer.volume - videoPlayer.volume) > 0.001) {
            console.log("[VideoPlayer] onVolumeChanged: Syncing", videoPlayer.volume, "-> wmfPlayer")
            wmfPlayer.volume = videoPlayer.volume
        }
        if (ffmpegPlayer && ffmpegPlayer.volume !== undefined && Math.abs(ffmpegPlayer.volume - videoPlayer.volume) > 0.001) {
            console.log("[VideoPlayer] onVolumeChanged: Syncing", videoPlayer.volume, "-> ffmpegPlayer")
            ffmpegPlayer.volume = videoPlayer.volume
        }
        if (mpvPlayer && mpvPlayer.volume !== undefined && Math.abs(mpvPlayer.volume - videoPlayer.volume) > 0.001) {
            console.log("[VideoPlayer] onVolumeChanged: Syncing", videoPlayer.volume, "-> mpvPlayer")
            mpvPlayer.volume = videoPlayer.volume
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
    

    // libmpv Video Player (HDR support, proper tone mapping)
    // Lazy-loaded to avoid slow startup when not viewing videos
    // Select appropriate player based on renderer mode
    property var mpvPlayer: {
        var rendererMode = videoSettings.mpvRendererMode || "opengl"
        if (rendererMode === "d3d11") {
            return null  // D3D11 uses mpvPlayerD3D11
        } else {
            return mpvLoader.item
        }
    }
    property var mpvPlayerD3D11: {
        var rendererMode = videoSettings.mpvRendererMode || "opengl"
        if (rendererMode === "d3d11") {
            return mpvLoader.item
        } else {
            return null  // OpenGL uses mpvPlayer
        }
    }
    
    // VLC Video Player
    property var vlcPlayer: vlcLoader.item
    
    // FFmpeg Video Player
    property var ffmpegPlayer: ffmpegLoader.item ? ffmpegLoader.item.playerInstance : null
    
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
                // Autoplay video when ready
                Qt.callLater(function() {
                    if (playbackState !== 1) { // Not already playing
                        console.log("[WMF] Autoplaying video")
                        play()
                        // Don't start hardware decoder detection timer for WMF - it uses hardware acceleration by default
                    }
                })
            }
        }
        
        onPlaybackStateChanged: {
                videoPlayer.playbackStateUpdated()
                if (playbackState === 1) { // Playing
                    videoPlayer.showControls = true
                controlsHideTimer.start()
                // Check hardware decoder for webm files (even with WMF) or for MediaPlayer
                const isWebm = videoPlayer.source.toString().toLowerCase().endsWith('.webm')
                if (isWebm && videoPlayer.source !== "") {
                    hardwareDecoderDetectionTimer.restart()
                }
            } else {
                    videoPlayer.showControls = true
                controlsHideTimer.stop()
                hardwareDecoderDetectionTimer.stop()
            }
        }
        
        onHasAudioChanged: {
            // hasAudio property changed - QML automatically emits hasAudioChanged signal
            // No need to manually emit, just update the property binding
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

    Loader {
        id: vlcLoader
        active: videoPlayer.libvlcReady && videoPlayer.useLibvlc && videoPlayer.source !== ""
        sourceComponent: S3rp3ntMedia.VLCVideoPlayer {
            id: vlcPlayerInstance
            source: videoPlayer.source

            Component.onCompleted: {
                volume = videoPlayer.volume
                console.log("[VideoPlayer] vlcPlayer onCompleted: Set volume to", volume)
            }

            onDurationChanged: {
                if (duration > 0) {
                    console.log("[VLC] Duration available:", duration, "ms")
                    if (Math.abs(volume - videoPlayer.volume) > 0.001) {
                        volume = videoPlayer.volume
                    }
                    videoPlayer.durationAvailable()
                    Qt.callLater(function() {
                        if (playbackState !== 1) { 
                            play()
                        }
                    })
                }
            }

                onPlaybackStateChanged: {
                    videoPlayer.playbackStateUpdated()
                    if (playbackState === 1) { // Playing
                        videoPlayer.showControls = true
                        if (videoPlayer.controlsHideTimer) {
                            videoPlayer.controlsHideTimer.start()
                        }
                    } else {
                        videoPlayer.showControls = true
                        if (videoPlayer.controlsHideTimer) {
                            videoPlayer.controlsHideTimer.stop()
                        }
                    }
                }
        }
    }
    
    // FFmpeg Video Player (D3D11VA, HDR support)
    Loader {
        id: ffmpegLoader
        active: videoPlayer.ffmpegReady && videoPlayer.useFFmpeg && videoPlayer.source !== ""
        sourceComponent: Item {
            id: ffmpegPlayerContainer
            
            // Expose player instance to parent
            property var playerInstance: ffmpegPlayerInstance
            
            S3rp3ntMedia.FFmpegVideoPlayer {
                id: ffmpegPlayerInstance
                source: videoPlayer.source

                Component.onCompleted: {
                    volume = videoPlayer.volume
                    console.log("[VideoPlayer] ffmpegPlayer onCompleted: Set volume to", volume)
                    
                    // Try to set window immediately if available
                    if (ffmpegPlayerContainer.window) {
                        console.log("[QML] Window available in Component.onCompleted, passing to FFmpeg")
                        ffmpegPlayerInstance.window = ffmpegPlayerContainer.window
                    } else {
                        console.log("[QML] Window not available yet in Component.onCompleted, will wait for onWindowChanged")
                    }
                }

                onDurationChanged: {
                    if (duration > 0) {
                        console.log("[FFmpeg] Duration available:", duration, "ms")
                        if (Math.abs(volume - videoPlayer.volume) > 0.001) {
                            volume = videoPlayer.volume
                        }
                        videoPlayer.durationAvailable()
                        Qt.callLater(function() {
                            if (playbackState !== 1) { 
                                play()
                            }
                        })
                    }
                }

                onPlaybackStateChanged: {
                    videoPlayer.playbackStateUpdated()
                    if (playbackState === 1) { // Playing
                        videoPlayer.showControls = true
                        if (videoPlayer.controlsHideTimer) {
                            videoPlayer.controlsHideTimer.start()
                        }
                    } else {
                        videoPlayer.showControls = true
                        if (videoPlayer.controlsHideTimer) {
                            videoPlayer.controlsHideTimer.stop()
                        }
                    }
                }
                
                onErrorOccurred: function(error, errorString) {
                    console.error("[FFmpeg] Error occurred:", error, errorString)
                    // Fallback to MediaPlayer on error (only for critical errors)
                    // Don't fallback for window-not-available errors - window may become available
                    if (videoPlayer.useFFmpeg && errorString.indexOf("window") === -1) {
                        console.log("[FFmpeg] Falling back to MediaPlayer due to critical error")
                        if (videoPlayer.videoSettings) {
                            videoPlayer.videoSettings.videoBackend = "mediaplayer"
                        }
                    } else if (errorString.indexOf("window") !== -1) {
                        console.log("[FFmpeg] Window not available yet - will retry when window is set")
                    }
                }
            }
            
            // CRITICAL: React when window becomes available (this fires when scene graph is created)
            onWindowChanged: function(w) {
                if (w) {
                    console.log("[QML] Window became available, passing to FFmpeg")
                    ffmpegPlayerInstance.window = w
                } else {
                    console.log("[QML] Window became null")
                }
            }
        }
    }
    
    // libmpv Video Player (HDR support, proper tone mapping)
    // Use a separate QML file so Loader can handle errors gracefully
    // Select D3D11 or OpenGL component based on mpvRendererMode setting
    Loader {
        id: mpvLoader
        active: videoPlayer.libmpvReady && videoPlayer.useLibmpv && videoPlayer.source !== ""
        source: {
            // Force OpenGL component since D3D11 is currently unavailable
            console.log("[VideoPlayer] Using OpenGL MPV player component (D3D11 disabled)")
            return "MPVVideoPlayerComponent.qml"

            /*
            // Check mpvRendererMode from settings
            var rendererMode = videoSettings.mpvRendererMode || "opengl"
            if (rendererMode === "d3d11") {
                console.log("[VideoPlayer] Using D3D11 MPV player component")
                return "MPVVideoPlayerComponentD3D11.qml"
            } else {
                console.log("[VideoPlayer] Using OpenGL MPV player component")
                return "MPVVideoPlayerComponent.qml"
            }
            */
        }
        onStatusChanged: {
            if (status === Loader.Error) {
                var rendererMode = videoSettings.mpvRendererMode || "opengl"
                var componentName = rendererMode === "d3d11" ? "MPVVideoPlayerD3D11" : "MPVVideoPlayer"
                console.log("[VideoPlayer] " + componentName + " type not available - libmpv not compiled or D3D11 not available")
                active = false
                // Fallback to MediaPlayer
                if (videoPlayer.useLibmpv) {
                    console.log("[VideoPlayer] Falling back to MediaPlayer backend")
                    videoPlayer.videoSettings.videoBackend = "mediaplayer"
                }
            }
        }
        onItemChanged: {
            if (item) {
                item.source = videoPlayer.source
            }
        }
    }
    
    // VLC video rendering (when using libvlc backend)
    // VLC video rendering using vmem -> QVideoSink (integrates with QML z-order)
    Loader {
        id: vlcVideoDisplayLoader
        anchors.fill: parent
        active: videoPlayer.useLibvlc && videoPlayer.libvlcReady && videoPlayer.source !== ""
        visible: active && videoPlayer.source !== ""
        
        sourceComponent: Item {
            anchors.fill: parent
            
            // Black background to prevent white rectangles from showing through
            Rectangle {
                id: videoBackgroundVLC
                anchors.fill: parent
                color: "#000000"
                z: 0
            }
            
            // VideoOutput for VLC vmem rendering (integrates with QML scene graph)
            // This allows QML UI elements (settings, controls) to render above the video
            VideoOutput {
                id: vlcVideoOutput
                anchors.fill: parent
                fillMode: VideoOutput.PreserveAspectFit
                z: 0  // Video renders at z:0, UI elements can be above
                
                Component.onCompleted: {
                    // Connect VLC player to VideoOutput's videoSink
                    // This enables vmem rendering through Qt's scene graph
                    if (videoPlayer.vlcPlayer && videoSink) {
                        videoPlayer.vlcPlayer.videoSink = videoSink
                        console.log("[VLC] Connected VLC player to VideoOutput videoSink (vmem rendering)")
                    } else {
                        console.warn("[VLC] Failed to connect videoSink - video will not render")
                    }
                }
                
                // Update connection when player or sink changes
                Connections {
                    target: videoPlayer
                    function onVlcPlayerChanged() {
                        if (videoPlayer.vlcPlayer && vlcVideoOutput.videoSink) {
                            videoPlayer.vlcPlayer.videoSink = vlcVideoOutput.videoSink
                            console.log("[VLC] Reconnected videoSink after player change")
                        }
                    }
                }
                
                // Apply rotation transform
                transform: Rotation {
                    origin.x: vlcVideoOutput.width / 2
                    origin.y: vlcVideoOutput.height / 2
                    angle: videoPlayer.videoRotation
                }
            }
        }
    }
    
    // FFmpeg video rendering (when using FFmpeg backend)
    Loader {
        id: ffmpegVideoDisplayLoader
        anchors.fill: parent
        active: videoPlayer.useFFmpeg && videoPlayer.ffmpegReady && videoPlayer.source !== ""
        visible: active && videoPlayer.source !== ""
        
        sourceComponent: Item {
            anchors.fill: parent
            
            // Black background to prevent white rectangles from showing through
            Rectangle {
                id: videoBackgroundFFmpeg
                anchors.fill: parent
                color: "#000000"
                z: 0
            }
            
            // FFmpeg uses QVideoSink for stable, hardware-accelerated rendering
            VideoOutput {
                id: ffmpegVideoOutput
                anchors.fill: parent
                z: 0
                fillMode: VideoOutput.PreserveAspectFit
                
                Component.onCompleted: {
                    console.log("[FFmpeg] VideoOutput created")
                    // Connect FFmpeg player to VideoOutput's videoSink
                    if (videoPlayer.ffmpegPlayer && ffmpegVideoOutput.videoSink) {
                        videoPlayer.ffmpegPlayer.videoSink = ffmpegVideoOutput.videoSink
                        console.log("[FFmpeg] Connected FFmpeg player to VideoOutput videoSink")
                    }
                }
                
                Connections {
                    target: videoPlayer
                    function onFfmpegPlayerChanged() {
                        if (videoPlayer.ffmpegPlayer && ffmpegVideoOutput.videoSink) {
                            videoPlayer.ffmpegPlayer.videoSink = ffmpegVideoOutput.videoSink
                            console.log("[FFmpeg] Reconnected FFmpeg player to VideoOutput videoSink")
                        }
                    }
                }
                
                // Apply rotation transform
                transform: Rotation {
                    origin.x: ffmpegVideoOutput.width / 2
                    origin.y: ffmpegVideoOutput.height / 2
                    angle: videoPlayer.videoRotation
                }
            }
        }
    }

    // libmpv video rendering (when using libmpv backend)
    // Select D3D11 or OpenGL renderer based on mpvRendererMode setting
    Loader {
        id: mpvVideoDisplayLoader
        anchors.fill: parent
        active: videoPlayer.useLibmpv && videoPlayer.libmpvReady && videoPlayer.source !== ""
        visible: active && videoPlayer.source !== ""
        
        onActiveChanged: {
            console.log("[MPVVideoDisplayLoader] active changed to:", active, "useLibmpv:", videoPlayer.useLibmpv, "libmpvReady:", videoPlayer.libmpvReady, "source:", videoPlayer.source !== "")
        }
        
        onVisibleChanged: {
            console.log("[MPVVideoDisplayLoader] visible changed to:", visible, "active:", active)
        }
        
        sourceComponent: {
            // Force OpenGL renderer component since D3D11 is currently unavailable
            console.log("[MPVVideoDisplayLoader] Using OpenGL renderer component (D3D11 disabled)")
            return mpvOpenGLRendererComponent
            
            /*
            // Check mpvRendererMode from settings
            var rendererMode = videoSettings.mpvRendererMode || "opengl"
            if (rendererMode === "d3d11") {
                console.log("[MPVVideoDisplayLoader] Using D3D11 renderer component")
                return mpvD3D11RendererComponent
            } else {
                console.log("[MPVVideoDisplayLoader] Using OpenGL renderer component")
                return mpvOpenGLRendererComponent
            }
            */
        }
    }
    
    // D3D11 renderer component (QRhi-based) - TEMPORARILY DISABLED
    /*
    Component {
        id: mpvD3D11RendererComponent
        Item {
            anchors.fill: parent
            
            // Black background to prevent white rectangles from showing through
            Rectangle {
                id: videoBackgroundD3D11
                anchors.fill: parent
                color: "#000000"
                z: 0
            }
            
            S3rp3ntMedia.MPVVideoItemD3D11 {
                id: mpvVideoDisplayD3D11
                player: videoPlayer.mpvPlayerD3D11 || null
                anchors.fill: parent
                visible: mpvVideoDisplayLoader.visible && videoPlayer.mpvPlayerD3D11 !== null && videoPlayer.mpvPlayerD3D11 !== undefined
                enabled: true
                z: 1
                
                Component.onCompleted: {
                    console.log("[MPVVideoItemD3D11] Component created, player:", player)
                    console.log("[MPVVideoItemD3D11] Size:", width, "x", height)
                    console.log("[MPVVideoItemD3D11] Using QRhi/D3D11-based renderer")
                }
                
                onPlayerChanged: {
                    console.log("[MPVVideoItemD3D11] Player changed")
                }
                
                // Apply rotation transform
                transform: Rotation {
                    origin.x: mpvVideoDisplayD3D11.width / 2
                    origin.y: mpvVideoDisplayD3D11.height / 2
                    angle: videoPlayer.videoRotation
                }
            }
        }
    }
    */
    
    // OpenGL renderer component (QQuickFramebufferObject-based)
    Component {
        id: mpvOpenGLRendererComponent
        Item {
            anchors.fill: parent
            
            // Black background to prevent white rectangles from showing through
            Rectangle {
                id: videoBackgroundOpenGL
                anchors.fill: parent
                color: "#000000"
                z: 0
            }
            
            S3rp3ntMedia.MPVVideoItem {
                id: mpvVideoDisplayOpenGL
                player: videoPlayer.mpvPlayer
                anchors.fill: parent
                visible: mpvVideoDisplayLoader.visible && videoPlayer.mpvPlayer !== null
                enabled: true
                z: 1
                
                Component.onCompleted: {
                    console.log("[MPVVideoItem] Component created, player:", player)
                    console.log("[MPVVideoItem] Size:", width, "x", height)
                    console.log("[MPVVideoItem] Using QQuickFramebufferObject-based renderer (Qt Quick native)")
                }
                
                onPlayerChanged: {
                    console.log("[MPVVideoItem] Player changed")
                }
                
                // Apply rotation transform
                transform: Rotation {
                    origin.x: mpvVideoDisplayOpenGL.width / 2
                    origin.y: mpvVideoDisplayOpenGL.height / 2
                    angle: videoPlayer.videoRotation
                }
            }
        }
    }
    
    // Fallback MediaPlayer (FFmpeg-based) - only active when not using WMF or libmpv
    MediaPlayer {
        id: mediaPlayer
        source: (videoPlayer.useWMF || videoPlayer.useLibmpv) ? "" : videoPlayer.source
        audioOutput: AudioOutput {
            id: audioOutput
            volume: videoPlayer.volume
        }
        videoOutput: videoDisplay
        // Explicitly stop when using WMF or libmpv to prevent FFmpeg initialization
        // Also connect embedded subtitle extractor when media player is ready
        Component.onCompleted: {
            if (videoPlayer.useWMF) {
                mediaPlayer.stop()
            }
            // Setup embedded subtitle extractor for external mode (custom engine)
            if (embeddedSubtitleExtractor && subtitleEngine === "external") {
                // Disable QMediaPlayer subtitle rendering for custom engine
                mediaPlayer.activeSubtitleTrack = -1
                console.log("[VideoPlayer] Disabled QMediaPlayer subtitle rendering for custom engine")
            }
        }
        
        // HDR/Color Space Diagnostic Logging
        onSourceChanged: {
            if (source !== "") {
                console.log("[VideoPlayer] 🎨 ===== MEDIA PLAYER SOURCE CHANGED =====")
                console.log("[VideoPlayer] 🎨 Source:", source)
                console.log("[VideoPlayer] 🎨 Source file:", source.toString())
                // Check if file name suggests HDR
                const sourceStr = source.toString().toLowerCase()
                const isHDR = sourceStr.includes("hdr") || sourceStr.includes("dv") || sourceStr.includes("dolby")
                console.log("[VideoPlayer] 🎨 File name suggests HDR:", isHDR)
                console.log("[VideoPlayer] 🎨 ========================================")
            }
        }
        
        onMetaDataChanged: {
            console.log("[VideoPlayer] 🎨 ===== MEDIA METADATA CHANGED =====")
            logMediaMetadata()
            console.log("[VideoPlayer] 🎨 ====================================")
        }
        
        function logMediaMetadata() {
            console.log("[VideoPlayer] 🎨 Attempting to access metadata...")
            
            // Try to get metadata keys - keys is a function in QMediaMetaData
            var keys = []
            try {
                // QMediaMetaData.keys is a function that returns an array
                if (typeof metaData.keys === "function") {
                    keys = metaData.keys()
                    console.log("[VideoPlayer] 🎨 Found", keys.length, "metadata keys")
                } else if (metaData.keys && Array.isArray(metaData.keys)) {
                    keys = metaData.keys
                    console.log("[VideoPlayer] 🎨 Found", keys.length, "metadata keys (direct array)")
                } else {
                    console.log("[VideoPlayer] 🎨 metaData.keys type:", typeof metaData.keys)
                }
            } catch(e) {
                console.log("[VideoPlayer] 🎨 Error accessing metadata keys:", e)
            }
            
            // Log all available metadata
            if (keys && keys.length > 0) {
                for (var i = 0; i < keys.length; i++) {
                    var key = keys[i]
                    try {
                        var value = metaData.value(key)
                        // Log all metadata, but highlight color/HDR related ones
                        var keyLower = String(key).toLowerCase()
                        if (keyLower.includes("color") || 
                            keyLower.includes("hdr") || 
                            keyLower.includes("gamma") ||
                            keyLower.includes("transfer") ||
                            keyLower.includes("primaries") ||
                            keyLower.includes("matrix") ||
                            keyLower.includes("chroma") ||
                            keyLower.includes("space") ||
                            keyLower.includes("brightness") ||
                            keyLower.includes("luminance")) {
                            console.log("[VideoPlayer] 🎨 ⭐ COLOR/HDR:", key, "=", value, "(type:", typeof value, ")")
                        } else {
                            console.log("[VideoPlayer] 🎨", key, "=", value, "(type:", typeof value, ")")
                        }
                    } catch(e) {
                        console.log("[VideoPlayer] 🎨 Error reading key", key, ":", e)
                    }
                }
            }
            
            // Try to access HDR/color metadata using QMediaMetaData enum keys
            // The keys we see are numeric enums. Let's try the enum constants
            console.log("[VideoPlayer] 🎨 Trying QMediaMetaData enum constants for HDR/color info...")
            try {
                // QMediaMetaData enum values (from Qt docs, these are the numeric values)
                // Color-related: ColorSpace=29, ColorTransfer=30, ColorPrimaries=31, ColorRange=32
                var colorSpace = metaData.value(29)  // MediaMetaData.ColorSpace
                var colorTransfer = metaData.value(30)  // MediaMetaData.ColorTransfer  
                var colorPrimaries = metaData.value(31)  // MediaMetaData.ColorPrimaries
                var colorRange = metaData.value(32)  // MediaMetaData.ColorRange
                
                if (colorSpace !== undefined && colorSpace !== null) {
                    console.log("[VideoPlayer] 🎨 ⭐ ColorSpace (key 29) =", colorSpace, "(type:", typeof colorSpace, ")")
                } else {
                    console.log("[VideoPlayer] 🎨 ColorSpace (key 29) = not available")
                }
                if (colorTransfer !== undefined && colorTransfer !== null) {
                    console.log("[VideoPlayer] 🎨 ⭐ ColorTransfer (key 30) =", colorTransfer, "(type:", typeof colorTransfer, ")")
                } else {
                    console.log("[VideoPlayer] 🎨 ColorTransfer (key 30) = not available")
                }
                if (colorPrimaries !== undefined && colorPrimaries !== null) {
                    console.log("[VideoPlayer] 🎨 ⭐ ColorPrimaries (key 31) =", colorPrimaries, "(type:", typeof colorPrimaries, ")")
                } else {
                    console.log("[VideoPlayer] 🎨 ColorPrimaries (key 31) = not available")
                }
                if (colorRange !== undefined && colorRange !== null) {
                    console.log("[VideoPlayer] 🎨 ⭐ ColorRange (key 32) =", colorRange, "(type:", typeof colorRange, ")")
                } else {
                    console.log("[VideoPlayer] 🎨 ColorRange (key 32) = not available")
                }
                
                // Other useful metadata we already found
                console.log("[VideoPlayer] 🎨 Known metadata:")
                console.log("[VideoPlayer] 🎨   Key 27 (Resolution) =", metaData.value(27))
                console.log("[VideoPlayer] 🎨   Key 28 (unknown boolean) =", metaData.value(28))
                console.log("[VideoPlayer] 🎨   Key 17 (FrameRate) =", metaData.value(17))
                console.log("[VideoPlayer] 🎨   Key 13 (VideoBitRate) =", metaData.value(13))
                
                // DIAGNOSIS SUMMARY
                console.log("[VideoPlayer] 🎨 ===== HDR COLOR DIAGNOSIS SUMMARY =====")
                console.log("[VideoPlayer] 🎨 ⚠️  PROBLEM IDENTIFIED:")
                console.log("[VideoPlayer] 🎨    Color space metadata (keys 29-32) is NOT available")
                console.log("[VideoPlayer] 🎨    This means Qt MediaPlayer is NOT detecting HDR color info")
                console.log("[VideoPlayer] 🎨    Video is being treated as SDR (Rec.709) instead of HDR (Rec.2020)")
                console.log("[VideoPlayer] 🎨")
                console.log("[VideoPlayer] 🎨 📋 Video Info:")
                console.log("[VideoPlayer] 🎨    Resolution: 3840x2160 (4K)")
                console.log("[VideoPlayer] 🎨    File suggests HDR: true (DV.HDR in filename)")
                console.log("[VideoPlayer] 🎨    Key 28 (HDR flag?):", metaData.value(28))
                console.log("[VideoPlayer] 🎨")
                console.log("[VideoPlayer] 🎨 💡 POSSIBLE SOLUTIONS:")
                console.log("[VideoPlayer] 🎨    1. Use libmpv player - FULL HDR10/Dolby Vision support!")
                console.log("[VideoPlayer] 🎨    2. Use WMF player (Windows) - may handle HDR better")
                console.log("[VideoPlayer] 🎨    3. Use ffprobe to extract color space info directly")
                console.log("[VideoPlayer] 🎨    4. Check if display HDR is enabled in Windows")
                console.log("[VideoPlayer] 🎨 ==========================================")
            } catch(e) {
                console.log("[VideoPlayer] 🎨 Error accessing enum keys:", e)
            }
            
            // Try to access common video properties
            console.log("[VideoPlayer] 🎨 Video resolution:", implicitWidth, "x", implicitHeight)
            console.log("[VideoPlayer] 🎨 Video duration:", duration, "ms")
            console.log("[VideoPlayer] 🎨 Has video:", hasVideo)
            console.log("[VideoPlayer] 🎨 Has audio:", hasAudio)
            
            // Try to access video format info if available
            try {
                if (metaData.videoCodec) {
                    console.log("[VideoPlayer] 🎨 Video codec:", metaData.videoCodec)
                }
                if (metaData.resolution) {
                    console.log("[VideoPlayer] 🎨 Resolution metadata:", metaData.resolution)
                }
            } catch(e) {
                // Some properties might not be available
            }
        }
        
        // Also disable when media status changes and we're in external mode (custom engine)
        // Also log HDR/color space metadata when media loads
        onMediaStatusChanged: {
            if (mediaStatus === MediaPlayer.LoadedMedia) {
                // HDR/Color Space Diagnostic Logging
                console.log("[VideoPlayer] 🎨 Media loaded - logging metadata")
                logMediaMetadata()
                
                // Disable QMediaPlayer subtitle rendering for custom engine
                if (subtitleEngine === "external") {
                    mediaPlayer.activeSubtitleTrack = -1
                    console.log("[VideoPlayer] Disabled QMediaPlayer subtitle rendering for custom engine after media loaded")
                }
            }
        }
        
        // Monitor activeSubtitleTrack changes and force disable if in external mode (custom engine)
        onActiveSubtitleTrackChanged: {
            if (subtitleEngine === "external" && activeSubtitleTrack !== -1) {
                console.log("[VideoPlayer] WARNING: activeSubtitleTrack was set to", activeSubtitleTrack, "but we're using custom engine - forcing to -1")
                // Use Qt.callLater to avoid recursion and ensure it happens after any other handlers
                Qt.callLater(function() {
                    if (subtitleEngine === "external" && mediaPlayer.activeSubtitleTrack !== -1) {
                        mediaPlayer.activeSubtitleTrack = -1
                        console.log("[VideoPlayer] Successfully forced activeSubtitleTrack to -1 for custom engine")
                    }
                })
            }
        }
        
        // Check hasAudio after media is loaded - QMediaPlayer might not report correctly for webm
        onHasAudioChanged: {
            // For webm files, double-check by examining audio tracks
            if (!videoPlayer.useWMF && videoPlayer.source.toString().toLowerCase().endsWith('.webm')) {
                // Force re-check after a delay to ensure media is fully loaded
                Qt.callLater(function() {
                    // If hasAudio is true but we suspect it might be wrong, check audio tracks
                    // This is a workaround for QMediaPlayer sometimes reporting hasAudio=true for webm without audio
                    if (mediaPlayer.hasAudio) {
                        // Check if audio actually works by trying to access audio tracks
                        // If no audio tracks exist, hasAudio should be false
                        // Note: QMediaPlayer doesn't expose audio tracks directly, so we rely on hasAudio
                        // But we can check if the audio output is actually receiving data
                    }
                })
            }
        }
        
        // Update subtitle when position changes (for manual seeking)
        onPositionChanged: {
            if (subtitleEntries.length > 0 && subtitleEngine === "external") {
                updateCurrentSubtitle()
            }
        }
        
        // Update subtitle timer when playback state changes
        onPlaybackStateChanged: {
            if (subtitleEntries.length > 0 && subtitleEngine === "external") {
                if (playbackState === MediaPlayer.PlayingState) {
                    subtitleUpdateTimer.restart()
                } else {
                    subtitleUpdateTimer.stop()
                }
            }
        }
        
        // Listen for error messages to detect hardware decoder issues
        onErrorOccurred: function(error, errorString) {
            if (errorString && (errorString.toLowerCase().includes("hw decoder") || 
                errorString.toLowerCase().includes("hardware decoder") ||
                errorString.toLowerCase().includes("no hw decoder"))) {
                videoPlayer.hardwareDecoderUnavailable = true
            }
        }
    }
    
    // Disable QMediaPlayer subtitle rendering when switching to external mode (custom engine)
    Connections {
        target: videoPlayer
        function onSubtitleEngineChanged() {
            if (subtitleEngine === "external" && mediaPlayer) {
                // Force disable QMediaPlayer's built-in subtitle rendering (we use custom engine)
                mediaPlayer.activeSubtitleTrack = -1
                console.log("[VideoPlayer] Disabled QMediaPlayer subtitle rendering for custom engine")
            }
        }
    }
    
    VideoOutput {
        id: videoDisplay
        anchors.fill: parent
        fillMode: VideoOutput.PreserveAspectFit
        visible: videoPlayer.source !== "" && !videoPlayer.useLibmpv && !videoPlayer.useLibvlc
        
        // Apply rotation transform
        transform: Rotation {
            origin.x: videoDisplay.width / 2
            origin.y: videoDisplay.height / 2
            angle: videoPlayer.videoRotation
        }
        
        // HDR/Color Space Diagnostic Logging
        Component.onCompleted: {
            console.log("[VideoPlayer] 🎨 VideoOutput initialized")
            logVideoOutputInfo()
        }
        
        function logVideoOutputInfo() {
            console.log("[VideoPlayer] 🎨 ===== VIDEO OUTPUT INFO =====")
            console.log("[VideoPlayer] 🎨 VideoOutput width:", width, "height:", height)
            console.log("[VideoPlayer] 🎨 VideoOutput fillMode:", fillMode)
            console.log("[VideoPlayer] 🎨 VideoOutput videoSink:", videoSink ? "available" : "null")
            if (videoSink) {
                console.log("[VideoPlayer] 🎨 VideoSink properties:")
                try {
                    // Try to access video sink properties if available
                    console.log("[VideoPlayer] 🎨   - videoSink type:", typeof videoSink)
                } catch(e) {
                    console.log("[VideoPlayer] 🎨   - videoSink properties not accessible:", e)
                }
            }
            console.log("[VideoPlayer] 🎨 ================================")
        }
        
        
        // Custom subtitle overlay for formatted subtitles (external files only)
        // Embedded subtitles are rendered by QMediaPlayer automatically
        // Positioned relative to the actual video content area (accounts for letterboxing)
        Item {
            id: subtitleContainer
            // Calculate actual video content bounds (accounts for PreserveAspectFit letterboxing)
            readonly property real videoAspectRatio: videoPlayer.implicitWidth > 0 && videoPlayer.implicitHeight > 0 
                ? videoPlayer.implicitWidth / videoPlayer.implicitHeight : 0
            readonly property real containerAspectRatio: parent.width > 0 && parent.height > 0 
                ? parent.width / parent.height : 0
            readonly property real actualVideoWidth: videoAspectRatio > 0 && containerAspectRatio > 0
                ? (videoAspectRatio > containerAspectRatio ? parent.width : parent.height * videoAspectRatio)
                : parent.width
            readonly property real actualVideoHeight: videoAspectRatio > 0 && containerAspectRatio > 0
                ? (videoAspectRatio > containerAspectRatio ? parent.width / videoAspectRatio : parent.height)
                : parent.height
            readonly property real videoOffsetX: (parent.width - actualVideoWidth) / 2
            readonly property real videoOffsetY: (parent.height - actualVideoHeight) / 2
            
            // Position relative to actual video content area (not letterboxed area)
            anchors.bottom: parent.bottom
            anchors.bottomMargin: videoOffsetY + (actualVideoHeight * 0.08)  // 8% from bottom of actual video
            anchors.horizontalCenter: parent.horizontalCenter
            width: actualVideoWidth * 0.85  // 85% of actual video width
            height: actualVideoHeight * 0.15  // 15% of actual video height (for multi-line support)
            visible: subtitleEngine === "external" && formattedSubtitleText !== "" && !(videoPlayer.useWMF && videoPlayer.wmfPlayer)
            
            // Text element that scales smoothly with container width (like AudioPlayer)
            Text {
                id: subtitleOverlay
                anchors.centerIn: parent
                width: parent.width * 0.95  // 95% of container width
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: formattedSubtitleText
                onVisibleChanged: {
                    if (visible) {
                        console.log("[VideoPlayer] Subtitle overlay visible, text:", formattedSubtitleText.substring(0, 50))
                    }
                }
                color: "#FFFFFF"
                // Font size scales smoothly with container width (like AudioPlayer title/artist)
                // Formula: width * percentage, clamped between min and max
                // This gives smooth, continuous scaling as window resizes
                font.pixelSize: Math.max(18, Math.min(56, subtitleContainer.width * 0.04))
                font.bold: true
                style: Text.Outline
                styleColor: "#000000"
                wrapMode: Text.WordWrap
                textFormat: Text.RichText  // Enable HTML formatting
                maximumLineCount: 3  // Limit to 3 lines max
                elide: Text.ElideRight
            }
        }
    }
    
    // Video rotation buttons (similar to ImageControls)
    Item {
        id: videoRotationControls
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 12
        width: 80
        height: 36
        visible: videoPlayer.source !== ""
        z: 100
        
        // Calculate if background is light or dark to determine icon color
        readonly property color backgroundColor: Qt.rgba(
            Qt.lighter(videoPlayer.accentColor, 1.1).r,
            Qt.lighter(videoPlayer.accentColor, 1.1).g,
            Qt.lighter(videoPlayer.accentColor, 1.1).b,
            0.85
        )
        readonly property real backgroundLuminance: (0.299 * backgroundColor.r + 0.587 * backgroundColor.g + 0.114 * backgroundColor.b)
        readonly property color iconColor: backgroundLuminance > 0.5 ? "#000000" : "#ffffff"
        readonly property color pressedButtonColor: backgroundLuminance > 0.5 
            ? Qt.rgba(0, 0, 0, 0.15) : Qt.rgba(255, 255, 255, 0.2)
        readonly property color hoverButtonColor: backgroundLuminance > 0.5 
            ? Qt.rgba(0, 0, 0, 0.08) : Qt.rgba(255, 255, 255, 0.12)
        
        Rectangle {
            anchors.fill: parent
            radius: 18
            color: videoRotationControls.backgroundColor
            border.color: Qt.rgba(255, 255, 255, 0.2)
            border.width: 1
            opacity: 0.85
            
            layer.enabled: true
            layer.effect: DropShadow {
                radius: 20
                samples: 41
                color: Qt.rgba(0, 0, 0, 0.5)
                verticalOffset: 4
                horizontalOffset: 0
            }
            
            Row {
                anchors.centerIn: parent
                spacing: 8
                
                // Rotate left button
                Item {
                    width: 28
                    height: 28
                    
                    Rectangle {
                        id: rotateLeftButton
                        anchors.fill: parent
                        radius: 6
                        property bool isHovered: false
                        property bool isPressed: false
                        
                        color: isPressed
                               ? videoRotationControls.pressedButtonColor
                               : (isHovered ? videoRotationControls.hoverButtonColor : "transparent")
                        
                        Behavior on color {
                            ColorAnimation { duration: 200; easing.type: Easing.OutCubic }
                        }
                        Behavior on scale {
                            NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                        }
                        
                        scale: isPressed ? 0.9 : (isHovered ? 1.05 : 1.0)
                        
                        Text {
                            anchors.centerIn: parent
                            text: "↺"
                            color: videoRotationControls.iconColor
                            font.pixelSize: 16
                            font.family: "Segoe UI"
                            opacity: 0.9
                        }
                        
                        TapHandler {
                            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                            acceptedButtons: Qt.LeftButton
                            
                            onTapped: {
                                videoPlayer.videoRotation = (videoPlayer.videoRotation - 90 + 360) % 360
                                // Update libmpv rotation if using libmpv
                                if (videoPlayer.useLibmpv && videoPlayer.mpvPlayer) {
                                    videoPlayer.mpvPlayer.setRotation(videoPlayer.videoRotation)
                                }
                            }
                            onPressedChanged: rotateLeftButton.isPressed = pressed
                        }
                        
                        HoverHandler {
                            cursorShape: Qt.PointingHandCursor
                            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                            onHoveredChanged: rotateLeftButton.isHovered = hovered
                        }
                    }
                }
                
                // Rotate right button
                Item {
                    width: 28
                    height: 28
                    
                    Rectangle {
                        id: rotateRightButton
                        anchors.fill: parent
                        radius: 6
                        property bool isHovered: false
                        property bool isPressed: false
                        
                        color: isPressed
                               ? videoRotationControls.pressedButtonColor
                               : (isHovered ? videoRotationControls.hoverButtonColor : "transparent")
                        
                        Behavior on color {
                            ColorAnimation { duration: 200; easing.type: Easing.OutCubic }
                        }
                        Behavior on scale {
                            NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                        }
                        
                        scale: isPressed ? 0.9 : (isHovered ? 1.05 : 1.0)
                        
                        Text {
                            anchors.centerIn: parent
                            text: "↻"
                            color: videoRotationControls.iconColor
                            font.pixelSize: 16
                            font.family: "Segoe UI"
                            opacity: 0.9
                        }
                        
                        TapHandler {
                            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                            acceptedButtons: Qt.LeftButton
                            
                            onTapped: {
                                videoPlayer.videoRotation = (videoPlayer.videoRotation + 90) % 360
                                // Update libmpv rotation if using libmpv
                                if (videoPlayer.useLibmpv && videoPlayer.mpvPlayer) {
                                    videoPlayer.mpvPlayer.setRotation(videoPlayer.videoRotation)
                                }
                            }
                            onPressedChanged: rotateRightButton.isPressed = pressed
                        }
                        
                        HoverHandler {
                            cursorShape: Qt.PointingHandCursor
                            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                            onHoveredChanged: rotateRightButton.isHovered = hovered
                        }
                    }
                }
            }
        }
    }
    
    // Right-click context menu for video player
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.RightButton
        visible: videoPlayer.source !== ""
        onClicked: function(mouse) {
            if (mouse.button === Qt.RightButton) {
                videoContextMenu.x = mouse.x
                videoContextMenu.y = mouse.y
                videoContextMenu.open()
            }
        }
    }
    
    Popup {
        id: videoContextMenu
        width: 220
        height: contextMenuContent.height + 24
        modal: false
        closePolicy: Popup.CloseOnPressOutside | Popup.CloseOnEscape
        
        background: Rectangle {
            radius: 10
            color: Qt.rgba(
                Qt.lighter(accentColor, 1.3).r,
                Qt.lighter(accentColor, 1.3).g,
                Qt.lighter(accentColor, 1.3).b,
                0.95
            )
            border.color: Qt.rgba(255, 255, 255, 0.2)
            border.width: 1
            
            // Drop shadow
            layer.enabled: true
            layer.effect: DropShadow {
                transparentBorder: true
                horizontalOffset: 0
                verticalOffset: 4
                radius: 16
                samples: 32
                color: Qt.rgba(0, 0, 0, 0.25)
            }
        }
        
        Column {
            id: contextMenuContent
            width: parent.width - 24
            anchors.centerIn: parent
            spacing: 4
            topPadding: 12
            bottomPadding: 12
            
            // Audio Track
            Rectangle {
                width: parent.width
                height: 40
                radius: 8
                color: audioTrackMouseArea.containsMouse ? Qt.rgba(255, 255, 255, 0.1) : "transparent"
                
                MouseArea {
                    id: audioTrackMouseArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        if (audioTrackPopup.visible) {
                            audioTrackPopup.close()
                        } else {
                            audioTrackPopup.open()
                        }
                    }
                }
                
                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 12
                    
                    Image {
                        id: audioTrackIcon
                        source: "qrc:/qlementine/icons/16/hardware/speaker.svg"
                        sourceSize: Qt.size(16, 16)
                        
                        ColorOverlay {
                            anchors.fill: parent
                            source: audioTrackIcon
                            color: foregroundColor
                            opacity: 0.9
                        }
                    }
                    
                    Text {
                        text: "Audio Track"
                        color: foregroundColor
                        font.pixelSize: 14
                    }
                }
                
                Image {
                    id: audioTrackChevron
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    source: "qrc:/qlementine/icons/16/navigation/chevron-right.svg"
                    sourceSize: Qt.size(16, 16)
                }
                
                ColorOverlay {
                    anchors.fill: audioTrackChevron
                    source: audioTrackChevron
                    color: foregroundColor
                    opacity: 0.7
                }
            }
            
            // Subtitle Track
            Rectangle {
                width: parent.width
                height: 40
                radius: 8
                color: subtitleTrackMouseArea.containsMouse ? Qt.rgba(255, 255, 255, 0.1) : "transparent"
                
                MouseArea {
                    id: subtitleTrackMouseArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        if (subtitleTrackPopup.visible) {
                            subtitleTrackPopup.close()
                        } else {
                            subtitleTrackPopup.open()
                        }
                    }
                }
                
                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 12
                    
                    Image {
                        id: subtitleTrackIcon
                        source: "qrc:/qlementine/icons/16/text/text.svg"
                        sourceSize: Qt.size(16, 16)
                        
                        ColorOverlay {
                            anchors.fill: parent
                            source: subtitleTrackIcon
                            color: foregroundColor
                            opacity: 0.9
                        }
                    }
                    
                    Text {
                        text: "Subtitle Track"
                        color: foregroundColor
                        font.pixelSize: 14
                    }
                }
                
                Image {
                    id: subtitleTrackChevron
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    source: "qrc:/qlementine/icons/16/navigation/chevron-right.svg"
                    sourceSize: Qt.size(16, 16)
                }
                
                ColorOverlay {
                    anchors.fill: subtitleTrackChevron
                    source: subtitleTrackChevron
                    color: foregroundColor
                    opacity: 0.7
                }
            }
            
            // Import Subtitles
            Rectangle {
                width: parent.width
                height: 40
                radius: 8
                color: importSubtitlesMouseArea.containsMouse ? Qt.rgba(255, 255, 255, 0.1) : "transparent"
                
                MouseArea {
                    id: importSubtitlesMouseArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        subtitleFileDialog.open()
                        videoContextMenu.close()
                    }
                }
                
                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 12
                    
                    Image {
                        id: importSubtitlesIcon
                        source: "qrc:/qlementine/icons/16/file/folder-open.svg"
                        sourceSize: Qt.size(16, 16)
                        
                        ColorOverlay {
                            anchors.fill: parent
                            source: importSubtitlesIcon
                            color: foregroundColor
                            opacity: 0.9
                        }
                    }
                    
                    Text {
                        text: "Import Subtitles"
                        color: foregroundColor
                        font.pixelSize: 14
                    }
                }
            }
        }
    }
    
    // Audio Track Selection Popup
    Popup {
        id: audioTrackPopup
        x: videoContextMenu.x + videoContextMenu.width + 8
        y: videoContextMenu.y
        width: 200
        height: Math.min(400, Math.max(150, audioTrackList.implicitHeight + 24))
        modal: false
        closePolicy: Popup.CloseOnPressOutside | Popup.CloseOnEscape
        
        onOpened: {
            console.log("[VideoPlayer] ===== Audio track popup opened =====")
            console.log("[VideoPlayer] MediaPlayer reports", mediaPlayer.audioTracks.length, "audio tracks")
            console.log("[VideoPlayer] Repeater count:", audioTrackRepeater.count)
            console.log("[VideoPlayer] Track list height:", audioTrackList.height)
            console.log("[VideoPlayer] Popup height:", height)
            console.log("[VideoPlayer] Current activeAudioTrack:", mediaPlayer.activeAudioTrack)
            // Force update all track items
            for (var i = 0; i < audioTrackRepeater.count; i++) {
                var item = audioTrackRepeater.itemAt(i)
                if (item) {
                    item.currentActiveTrack = mediaPlayer.activeAudioTrack
                    console.log("[VideoPlayer] Updated track item", i, "currentActiveTrack to:", item.currentActiveTrack, "isActive:", item.isActive)
                }
            }
            // Log each track individually
            for (var j = 0; j < mediaPlayer.audioTracks.length; j++) {
                var track = mediaPlayer.audioTracks[j]
                var trackInfo = "Track " + (j + 1)
                if (track) {
                    if (track.title) trackInfo += " - " + track.title
                    if (track.language) trackInfo += " (" + track.language + ")"
                }
                console.log("[VideoPlayer]   Track", j, ":", trackInfo)
            }
        }
        
        background: Rectangle {
            radius: 10
            color: Qt.rgba(
                Qt.lighter(accentColor, 1.3).r,
                Qt.lighter(accentColor, 1.3).g,
                Qt.lighter(accentColor, 1.3).b,
                0.95
            )
            border.color: Qt.rgba(255, 255, 255, 0.2)
            border.width: 1
            
            layer.enabled: true
            layer.effect: DropShadow {
                transparentBorder: true
                horizontalOffset: 0
                verticalOffset: 4
                radius: 16
                samples: 32
                color: Qt.rgba(0, 0, 0, 0.25)
            }
        }
        
        ScrollView {
            anchors.fill: parent
            anchors.margins: 12
            clip: true
            
            Column {
                id: audioTrackList
                width: parent.width
                spacing: 4
                
                // Get available audio tracks
                Repeater {
                    id: audioTrackRepeater
                    model: (videoPlayer.useWMF && videoPlayer.wmfPlayer) ? [] : mediaPlayer.audioTracks
                    
                    onItemAdded: function(index, item) {
                        console.log("[VideoPlayer] Repeater item added at index:", index)
                    }
                    
                    onCountChanged: {
                        console.log("[VideoPlayer] Audio track Repeater count changed to:", audioTrackRepeater.count)
                        console.log("[VideoPlayer] MediaPlayer reports", mediaPlayer.audioTracks.length, "audio tracks")
                    }
                    
                    Rectangle {
                        id: audioTrackItem
                        width: audioTrackList.width
                        height: 36
                        radius: 8
                        color: audioTrackItemMouseArea.containsMouse ? Qt.rgba(255, 255, 255, 0.1) : "transparent"
                        // Force binding update by using a function that gets re-evaluated
                        property int currentActiveTrack: mediaPlayer.activeAudioTrack
                        property bool isActive: !(videoPlayer.useWMF && videoPlayer.wmfPlayer) && currentActiveTrack === index
                        
                        // Monitor activeAudioTrack changes and force update
                        Connections {
                            target: mediaPlayer
                            function onActiveAudioTrackChanged() {
                                console.log("[VideoPlayer] activeAudioTrack changed to:", mediaPlayer.activeAudioTrack, "Track", index, "isActive:", audioTrackItem.isActive)
                                // Force property update
                                audioTrackItem.currentActiveTrack = mediaPlayer.activeAudioTrack
                            }
                        }
                        
                        // Also update when popup opens
                        Component.onCompleted: {
                            currentActiveTrack = mediaPlayer.activeAudioTrack
                            console.log("[VideoPlayer] Audio track item created - index:", index, "displayed as Track", (index + 1))
                        }
                        
                        MouseArea {
                            id: audioTrackItemMouseArea
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                if (!(videoPlayer.useWMF && videoPlayer.wmfPlayer)) {
                                    var trackIndex = index
                                    var track = modelData
                                    
                                    console.log("[VideoPlayer] ===== Track Selection Debug =====")
                                    console.log("[VideoPlayer] Clicked Repeater index:", index)
                                    console.log("[VideoPlayer] Track object type:", typeof track)
                                    console.log("[VideoPlayer] Current activeAudioTrack:", mediaPlayer.activeAudioTrack)
                                    console.log("[VideoPlayer] Total audio tracks:", mediaPlayer.audioTracks.length)
                                    
                                    // Log all available tracks and their properties
                                    for (var i = 0; i < mediaPlayer.audioTracks.length; i++) {
                                        var t = mediaPlayer.audioTracks[i]
                                        console.log("[VideoPlayer] Track", i, ":", t)
                                        if (t) {
                                            // Try to access common properties
                                            try {
                                                console.log("[VideoPlayer]   - index:", t.index)
                                                console.log("[VideoPlayer]   - trackIndex:", t.trackIndex)
                                                console.log("[VideoPlayer]   - title:", t.title)
                                                console.log("[VideoPlayer]   - language:", t.language)
                                            } catch(e) {
                                                console.log("[VideoPlayer]   - Error accessing properties:", e)
                                            }
                                        }
                                    }
                                    
                                    // Ensure media is loaded before setting track
                                    if (mediaPlayer.source === "" || mediaPlayer.playbackState === MediaPlayer.StoppedState) {
                                        console.log("[VideoPlayer] WARNING: Media not loaded, cannot set track")
                                    } else {
                                        // Use the Repeater index directly (0-based indexing)
                                        console.log("[VideoPlayer] Setting activeAudioTrack to:", trackIndex, "(0-based index)")
                                        
                                        mediaPlayer.activeAudioTrack = trackIndex
                                        
                                        // Verify
                                        Qt.callLater(function() {
                                            var verified = mediaPlayer.activeAudioTrack
                                            console.log("[VideoPlayer] Verified activeAudioTrack:", verified, "Expected:", trackIndex)
                                        }, 150)
                                    }
                                }
                                audioTrackPopup.close()
                            }
                        }
                        
                        Row {
                            anchors.left: parent.left
                            anchors.leftMargin: 12
                            anchors.right: parent.right
                            anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 12
                            
                            Text {
                                text: audioTrackItem.isActive ? "✓" : ""
                                color: foregroundColor
                                font.pixelSize: 14
                                width: 16
                            }
                            
                            Text {
                                text: {
                                    if (videoPlayer.useWMF && videoPlayer.wmfPlayer) return "Not available (WMF)"
                                    var track = modelData
                                    if (!track) return "Track " + (index + 1)
                                    var title = track.title || ""
                                    var lang = track.language || ""
                                    if (title) return title
                                    if (lang) return "Track " + (index + 1) + " (" + lang + ")"
                                    return "Track " + (index + 1)
                                }
                                color: foregroundColor
                                font.pixelSize: 14
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
                
                // Show message if no tracks or using WMF
                Text {
                    width: audioTrackList.width
                    visible: (videoPlayer.useWMF && videoPlayer.wmfPlayer) || (!(videoPlayer.useWMF && videoPlayer.wmfPlayer) && mediaPlayer.audioTracks.length === 0)
                    text: (videoPlayer.useWMF && videoPlayer.wmfPlayer) ? "Audio track selection\nnot available with WMF" : "No audio tracks available"
                    color: foregroundColor
                    font.pixelSize: 12
                    opacity: 0.7
                    padding: 12
                    horizontalAlignment: Text.AlignHCenter
                }
            }
        }
    }
    
    // Subtitle Track Selection Popup
    Popup {
        id: subtitleTrackPopup
        x: videoContextMenu.x + videoContextMenu.width + 8
        y: videoContextMenu.y
        width: 200
        height: Math.min(300, subtitleTrackList.height + 24)
        modal: false
        closePolicy: Popup.CloseOnPressOutside | Popup.CloseOnEscape
        
        onOpened: {
            console.log("[VideoPlayer] ===== Subtitle track popup opened =====")
            var currentTrack = subtitleEngine === "external" ? 
                               embeddedSubtitleExtractor.activeSubtitleTrack : 
                               (subtitleEngine === "embedded" ? 
                                embeddedSubtitleExtractor.activeSubtitleTrack : 
                                mediaPlayer.activeSubtitleTrack)
            console.log("[VideoPlayer] Current activeSubtitleTrack:", currentTrack, "engine:", subtitleEngine)
            // Force update "None" option
            disableSubtitlesItem.currentActiveTrack = currentTrack
            // Force update all track items
            for (var i = 0; i < subtitleTrackRepeater.count; i++) {
                var item = subtitleTrackRepeater.itemAt(i)
                if (item) {
                    item.currentActiveTrack = currentTrack
                    console.log("[VideoPlayer] Updated subtitle track item", i, "currentActiveTrack to:", item.currentActiveTrack, "isActive:", item.isActive)
                }
            }
        }
        
        background: Rectangle {
            radius: 10
            color: Qt.rgba(
                Qt.lighter(accentColor, 1.3).r,
                Qt.lighter(accentColor, 1.3).g,
                Qt.lighter(accentColor, 1.3).b,
                0.95
            )
            border.color: Qt.rgba(255, 255, 255, 0.2)
            border.width: 1
            
            layer.enabled: true
            layer.effect: DropShadow {
                transparentBorder: true
                horizontalOffset: 0
                verticalOffset: 4
                radius: 16
                samples: 32
                color: Qt.rgba(0, 0, 0, 0.25)
            }
        }
        
        ScrollView {
            anchors.fill: parent
            anchors.margins: 12
            clip: true
            
            Column {
                id: subtitleTrackList
                width: parent.width
                spacing: 4
                
                // Option to disable subtitles
                Rectangle {
                    id: disableSubtitlesItem
                    width: subtitleTrackList.width
                    height: 36
                    radius: 8
                    color: disableSubtitlesMouseArea.containsMouse ? Qt.rgba(255, 255, 255, 0.1) : "transparent"
                    // Force binding update by using a property that gets updated
                    // IMPORTANT: In external mode, use embeddedSubtitleExtractor.activeSubtitleTrack
                    property int currentActiveTrack: subtitleEngine === "external" ? 
                                                     embeddedSubtitleExtractor.activeSubtitleTrack : 
                                                     (subtitleEngine === "embedded" ? 
                                                      embeddedSubtitleExtractor.activeSubtitleTrack : 
                                                      mediaPlayer.activeSubtitleTrack)
                    property bool isActive: !(videoPlayer.useWMF && videoPlayer.wmfPlayer) && currentActiveTrack === -1
                    
                    // Monitor activeSubtitleTrack changes and force update
                    Connections {
                        target: mediaPlayer
                        function onActiveSubtitleTrackChanged() {
                            disableSubtitlesItem.currentActiveTrack = subtitleEngine === "external" ? 
                                                                      embeddedSubtitleExtractor.activeSubtitleTrack : 
                                                                      (subtitleEngine === "embedded" ? 
                                                                       embeddedSubtitleExtractor.activeSubtitleTrack : 
                                                                       mediaPlayer.activeSubtitleTrack)
                        }
                    }
                    
                    // Also monitor embedded extractor's activeSubtitleTrack changes
                    Connections {
                        target: embeddedSubtitleExtractor
                        function onActiveSubtitleTrackChanged() {
                            if (subtitleEngine === "external" || subtitleEngine === "embedded") {
                                disableSubtitlesItem.currentActiveTrack = embeddedSubtitleExtractor.activeSubtitleTrack
                            }
                        }
                    }
                    
                    MouseArea {
                        id: disableSubtitlesMouseArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            if (!(videoPlayer.useWMF && videoPlayer.wmfPlayer)) {
                                if (subtitleEngine === "external") {
                                    embeddedSubtitleExtractor.activeSubtitleTrack = -1
                                } else if (subtitleEngine === "embedded") {
                                    embeddedSubtitleExtractor.activeSubtitleTrack = -1
                                } else {
                                    mediaPlayer.activeSubtitleTrack = -1
                                }
                                console.log("[VideoPlayer] Disabled subtitles")
                            }
                            subtitleTrackPopup.close()
                        }
                    }
                    
                    Row {
                        anchors.left: parent.left
                        anchors.leftMargin: 12
                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 12
                        
                        Text {
                            text: disableSubtitlesItem.isActive ? "✓" : ""
                            color: foregroundColor
                            font.pixelSize: 14
                            width: 16
                        }
                        
                        Text {
                            text: "None"
                            color: foregroundColor
                            font.pixelSize: 14
                        }
                    }
                }
                
                // Get available subtitle tracks
                Repeater {
                    id: subtitleTrackRepeater
                    model: (videoPlayer.useWMF && videoPlayer.wmfPlayer) ? [] : mediaPlayer.subtitleTracks
                    
                    Rectangle {
                        id: subtitleTrackItem
                        width: subtitleTrackList.width
                        height: 36
                        radius: 8
                        color: subtitleTrackItemMouseArea.containsMouse ? Qt.rgba(255, 255, 255, 0.1) : "transparent"
                        // Force binding update by using a function that gets re-evaluated
                        // IMPORTANT: In external mode, use embeddedSubtitleExtractor.activeSubtitleTrack
                        // In embedded mode, use mediaPlayer.activeSubtitleTrack
                        property int currentActiveTrack: subtitleEngine === "external" ? 
                                                         embeddedSubtitleExtractor.activeSubtitleTrack : 
                                                         (subtitleEngine === "embedded" ? 
                                                          embeddedSubtitleExtractor.activeSubtitleTrack : 
                                                          mediaPlayer.activeSubtitleTrack)
                        property bool isActive: !(videoPlayer.useWMF && videoPlayer.wmfPlayer) && currentActiveTrack === index
                        
                        // Monitor activeSubtitleTrack changes and force update
                        Connections {
                            target: mediaPlayer
                            function onActiveSubtitleTrackChanged() {
                                console.log("[VideoPlayer] activeSubtitleTrack changed to:", mediaPlayer.activeSubtitleTrack, "Track", index, "isActive:", subtitleTrackItem.isActive)
                                // Force property update - use correct source based on engine
                                subtitleTrackItem.currentActiveTrack = subtitleEngine === "external" ? 
                                                                       embeddedSubtitleExtractor.activeSubtitleTrack : 
                                                                       (subtitleEngine === "embedded" ? 
                                                                        embeddedSubtitleExtractor.activeSubtitleTrack : 
                                                                        mediaPlayer.activeSubtitleTrack)
                            }
                        }
                        
                        // Also monitor embedded extractor's activeSubtitleTrack changes (for both external and embedded modes)
                        Connections {
                            target: embeddedSubtitleExtractor
                            function onActiveSubtitleTrackChanged() {
                                if (subtitleEngine === "external" || subtitleEngine === "embedded") {
                                    console.log("[VideoPlayer] embeddedSubtitleExtractor.activeSubtitleTrack changed to:", embeddedSubtitleExtractor.activeSubtitleTrack, "Track", index, "isActive:", subtitleTrackItem.isActive)
                                    // Force property update
                                    subtitleTrackItem.currentActiveTrack = embeddedSubtitleExtractor.activeSubtitleTrack
                                }
                            }
                        }
                        
                        // Also update when popup opens
                        Component.onCompleted: {
                            currentActiveTrack = subtitleEngine === "external" ? 
                                                 embeddedSubtitleExtractor.activeSubtitleTrack : 
                                                 (subtitleEngine === "embedded" ? 
                                                  embeddedSubtitleExtractor.activeSubtitleTrack : 
                                                  mediaPlayer.activeSubtitleTrack)
                        }
                        
                        MouseArea {
                            id: subtitleTrackItemMouseArea
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                if (!(videoPlayer.useWMF && videoPlayer.wmfPlayer)) {
                                    // Use the Repeater index directly - it should match the track index
                                    var trackIndex = index
                                    console.log("[VideoPlayer] Clicked subtitle track at Repeater index:", index)
                                    console.log("[VideoPlayer] Track data:", modelData)
                                    console.log("[VideoPlayer] Current activeSubtitleTrack:", mediaPlayer.activeSubtitleTrack)
                                    console.log("[VideoPlayer] Total subtitle tracks:", mediaPlayer.subtitleTracks.length)
                                    console.log("[VideoPlayer] MediaPlayer source:", mediaPlayer.source)
                                    console.log("[VideoPlayer] MediaPlayer playbackState:", mediaPlayer.playbackState)
                                    
                                    console.log("[VideoPlayer] ===== SUBTITLE TRACK SELECTION =====")
                                    console.log("[VideoPlayer] Subtitle engine:", subtitleEngine, "useWMF:", videoPlayer.useWMF)
                                    console.log("[VideoPlayer] Selected track index:", trackIndex)
                                    
                                    if (subtitleEngine === "embedded") {
                                        console.log("[VideoPlayer] ⚠️  WARNING: You are in 'embedded' mode - using QMediaPlayer's built-in rendering")
                                        console.log("[VideoPlayer] ⚠️  To use the CUSTOM ENGINE with embedded subtitles, switch to 'external' mode in settings!")
                                        // Embedded mode: Use QMediaPlayer's built-in subtitle rendering
                                        // Ensure media is loaded before setting track
                                        if (mediaPlayer.source === "" || mediaPlayer.playbackState === MediaPlayer.StoppedState) {
                                            console.log("[VideoPlayer] WARNING: Media not loaded, cannot set track")
                                        } else {
                                            // Use the Repeater index directly (0-based indexing)
                                            console.log("[VideoPlayer] Setting activeSubtitleTrack to:", trackIndex, "(0-based index) for QMediaPlayer rendering")
                                            
                                            mediaPlayer.activeSubtitleTrack = trackIndex
                                            
                                            // Verify
                                            Qt.callLater(function() {
                                                var verified = mediaPlayer.activeSubtitleTrack
                                                console.log("[VideoPlayer] Verified activeSubtitleTrack:", verified, "Expected:", trackIndex)
                                            }, 150)
                                        }
                                    } else {
                                        // External mode: Extract track once, then use cache (no lag!)
                                        console.log("[VideoPlayer] ===== EXTERNAL MODE: Using CUSTOM subtitle engine =====")
                                        console.log("[VideoPlayer] Setting active subtitle track:", trackIndex)
                                        
                                        // Set active track
                                        embeddedSubtitleExtractor.activeSubtitleTrack = trackIndex
                                        
                                        // Extract entire track in background (one-time, then cached - no lag during playback!)
                                        if (videoPlayer.source !== "") {
                                            console.log("[VideoPlayer] Extracting subtitle track", trackIndex, "in background...")
                                            embeddedSubtitleExtractor.extractFromFile(videoPlayer.source, trackIndex)
                                        }
                                        
                                        // CRITICAL: Force disable QMediaPlayer subtitle rendering (we use custom engine)
                                        mediaPlayer.activeSubtitleTrack = -1
                                        console.log("[VideoPlayer] Disabled QMediaPlayer subtitle rendering - using CUSTOM ENGINE")
                                    }
                                    
                                    // Final safeguard: if in external mode, always disable QMediaPlayer rendering
                                    if (subtitleEngine === "external") {
                                        Qt.callLater(function() {
                                            if (mediaPlayer.activeSubtitleTrack !== -1) {
                                                console.log("[VideoPlayer] SAFEGUARD: Forcing activeSubtitleTrack to -1 for custom engine")
                                                mediaPlayer.activeSubtitleTrack = -1
                                            }
                                        }, 50)
                                    }
                                }
                                subtitleTrackPopup.close()
                            }
                        }
                        
                        Row {
                            anchors.left: parent.left
                            anchors.leftMargin: 12
                            anchors.right: parent.right
                            anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 12
                            
                            Text {
                                text: subtitleTrackItem.isActive ? "✓" : ""
                                color: foregroundColor
                                font.pixelSize: 14
                                width: 16
                            }
                            
                            Text {
                                text: {
                                    if (videoPlayer.useWMF && videoPlayer.wmfPlayer) return "Not available (WMF)"
                                    var track = modelData
                                    if (!track) return "Track " + (index + 1)
                                    var title = track.title || ""
                                    var lang = track.language || ""
                                    if (title) return title
                                    if (lang) return "Track " + (index + 1) + " (" + lang + ")"
                                    return "Track " + (index + 1)
                                }
                                color: foregroundColor
                                font.pixelSize: 14
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
                
                // Show message if no tracks or using WMF
                Text {
                    width: subtitleTrackList.width
                    visible: (videoPlayer.useWMF && videoPlayer.wmfPlayer) || (!(videoPlayer.useWMF && videoPlayer.wmfPlayer) && mediaPlayer.subtitleTracks.length === 0)
                    text: (videoPlayer.useWMF && videoPlayer.wmfPlayer) ? "Subtitle track selection\nnot available with WMF" : "No subtitle tracks available"
                    color: foregroundColor
                    font.pixelSize: 12
                    opacity: 0.7
                    padding: 12
                    horizontalAlignment: Text.AlignHCenter
                }
            }
        }
    }
    
    // Subtitle File Dialog
    FileDialog {
        id: subtitleFileDialog
        title: "Import Subtitle File"
        fileMode: FileDialog.OpenFile
        nameFilters: [
            "Subtitle Files (*.srt *.vtt *.ass *.ssa *.sub)",
            "SRT Files (*.srt)",
            "WebVTT Files (*.vtt)",
            "ASS/SSA Files (*.ass *.ssa)",
            "SUB Files (*.sub)",
            "All Files (*)"
        ]
        
        onAccepted: {
            var subtitleUrl = selectedFile
            console.log("[VideoPlayer] Importing subtitle file:", subtitleUrl)
            
            if (videoPlayer.useWMF && videoPlayer.wmfPlayer) {
                console.log("[VideoPlayer] Subtitle import not available with WMF")
                return
            }
            
            // Load subtitle file using ColorUtils (C++ function that can read local files)
            var subtitleText = S3rp3ntMedia.ColorUtils.readTextFile(subtitleUrl)
            
            if (subtitleText && subtitleText.length > 0) {
                console.log("[VideoPlayer] Loaded subtitle file, length:", subtitleText.length)
                
                // Parse subtitle file based on extension
                var filePath = subtitleUrl.toString()
                if (filePath.endsWith(".srt") || filePath.endsWith(".vtt") || 
                    filePath.endsWith(".ass") || filePath.endsWith(".ssa")) {
                    
                    // Parse subtitle file based on format
                    if (filePath.endsWith(".srt")) {
                        // Parse SRT file with timestamps
                        subtitleEntries = parseSRTTimestamps(subtitleText)
                        console.log("[VideoPlayer] SRT parsed, found", subtitleEntries.length, "subtitle entries")
                        if (subtitleEntries.length > 0) {
                            console.log("[VideoPlayer] First subtitle:", subtitleEntries[0].text.substring(0, 50), "at", subtitleEntries[0].start, "ms")
                            // Start the update timer
                            subtitleUpdateTimer.restart()
                            // Update immediately
                            updateCurrentSubtitle()
                        }
                    } else if (filePath.endsWith(".ass") || filePath.endsWith(".ssa")) {
                        // For ASS/SSA files, format the codes
                        subtitleWrapper.setSubtitleText(subtitleText)
                        currentSubtitleText = subtitleWrapper.formattedSubtitleText
                        console.log("[VideoPlayer] ASS/SSA file loaded, formatted length:", currentSubtitleText.length)
                    } else {
                        // For other formats (VTT, etc.), just set the text
                        subtitleWrapper.setSubtitleText(subtitleText)
                        currentSubtitleText = subtitleWrapper.formattedSubtitleText
                        console.log("[VideoPlayer] Subtitle file loaded")
                    }
                } else {
                    console.log("[VideoPlayer] Unsupported subtitle format")
                }
            } else {
                console.error("[VideoPlayer] Failed to load subtitle file or file is empty")
            }
        }
    }
    
    property bool isFixingVideo: false
    property url originalVideoSource: ""
    property url fixedVideoUrl: ""
    property int lastPosition: 0
    property int positionStallCount: 0
    property bool hardwareDecoderUnavailable: false  // Track if hardware decoder is not available
    
    // Timer to detect hardware decoder unavailability after video starts playing
    // Since "No HW decoder found" is a console warning (not an error), we use a heuristic:
    // Show notification for MediaPlayer and for webm files (which may not have hardware decoding even with WMF)
    // Note: The warning can appear in console for both WMF and MediaPlayer
    Timer {
        id: hardwareDecoderDetectionTimer
        interval: 1500  // Check 1.5 seconds after video starts playing
        running: false
        onTriggered: {
            // Heuristic: Show notification for MediaPlayer or webm files
            // MediaPlayer (FFmpeg-based) is more likely to use software decoding
            // Webm files may not have hardware decoding even with WMF
            const isPlaying = (videoPlayer.useWMF && wmfPlayer && wmfPlayer.playbackState === 1) || 
                             (!videoPlayer.useWMF && mediaPlayer.playbackState === MediaPlayer.PlayingState)
            const isWebm = videoPlayer.source.toString().toLowerCase().endsWith('.webm')
            
            if (isPlaying && videoPlayer.source !== "") {
                // Show notification for MediaPlayer or webm files
                if (!videoPlayer.useWMF || isWebm) {
                    videoPlayer.hardwareDecoderUnavailable = true
                }
            }
        }
    }
    
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
            const fixedUrlStr = String(fixedUrl || "")
            console.log("[Video] Fix result:", fixedUrlStr)
            if (fixedUrl && fixedUrlStr !== "" && fixedUrlStr !== "null" && fixedUrlStr !== "undefined") {
                console.log("[Video] Fixed video ready, switching to fixed version:", fixedUrlStr)
                videoPlayer.fixedVideoUrl = fixedUrl
                videoPlayer.source = fixedUrl
            } else {
                console.log("[Video] Failed to fix video - keeping original source. Check FFmpeg output above")
                // Don't clear the source - keep playing the original video
                videoPlayer.isFixingVideo = false
                // Keep originalVideoSource set so we don't try to fix again
                // Don't clear it - this prevents infinite retry loops
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
                // Autoplay video when ready (if not already playing)
                if (mediaPlayer.playbackState !== MediaPlayer.PlayingState) {
                    Qt.callLater(function() {
                        console.log("[Video] Autoplaying video")
                        mediaPlayer.play()
                        // Start hardware decoder detection timer after auto-play
                        Qt.callLater(function() {
                            if (videoPlayer.source !== "") {
                                hardwareDecoderDetectionTimer.restart()
                            }
                        }, 500)  // Small delay to ensure playback has started
                    })
                }
                // Don't auto-fix automatically - only fix when there's an actual problem (stuttering/errors)
                // The positionMonitor timer will detect stuttering and trigger a fix if needed
                // Auto-fixing every video causes issues when FFmpeg fails
                console.log("[Video] Video loaded successfully - auto-fix disabled (will fix only on stuttering/errors)")
            }
        }
        function onPlaybackStateChanged() {
            playbackStateUpdated()
            if (mediaPlayer.playbackState === MediaPlayer.PlayingState) {
                showControls = true
                controlsHideTimer.start()
                // Check for hardware decoder availability after playback starts (if using MediaPlayer)
                if (!videoPlayer.useWMF && videoPlayer.source !== "") {
                    hardwareDecoderDetectionTimer.restart()
                }
            } else {
                showControls = true
                controlsHideTimer.stop()
                hardwareDecoderDetectionTimer.stop()
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
    
    // Video controls overlay - styled like AudioControls
    Item {
        id: controlsContainer
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 24
        anchors.horizontalCenter: parent.horizontalCenter
        // Match AudioPlayer controls width exactly
        width: Math.min(500, parent.width - 48)
        height: 56
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
                // ✅ Pause on first seek request (when dragging starts)
                if (!videoPlayer._isSeeking) {
                    videoPlayer._isSeeking = true
                    // Store playback state - was it playing before seek?
                    videoPlayer._wasPlayingBeforeSeek = (videoPlayer.playbackState === 1) // 1 = PlayingState
                    // Pause playback when seeking starts
                    if (videoPlayer.playbackState === 1) {
                        videoPlayer.pause()
                    }
                }
                // Store pending seek position (will be committed on release)
                const duration = videoPlayer.duration
                videoPlayer._pendingSeekPos = Math.max(0, Math.min(pos, duration > 0 ? duration - 1 : pos))
            }
            
            onSeekReleased: {
                console.log("[VideoPlayer] onSeekReleased called - _isSeeking:", videoPlayer._isSeeking, "_pendingSeekPos:", videoPlayer._pendingSeekPos)
                // ✅ Commit seek only on release (not while dragging)
                if (videoPlayer._isSeeking && videoPlayer._pendingSeekPos >= 0) {
                    videoPlayer._isSeeking = false
                    
                    // Perform the actual seek
                    const seekPos = videoPlayer._pendingSeekPos
                    const wasPlaying = videoPlayer._wasPlayingBeforeSeek
                    
                    console.log("[VideoPlayer] Committing seek to:", seekPos, "wasPlaying:", wasPlaying)
                    
                    // Reset state before seeking
                    videoPlayer._pendingSeekPos = -1
                    videoPlayer._wasPlayingBeforeSeek = false
                    
                    if (videoPlayer.useLibmpv && videoPlayer.mpvPlayer) {
                        videoPlayer.mpvPlayer.seek(seekPos)
                    } else if (videoPlayer.useWMF && wmfPlayer) {
                        wmfPlayer.seek(seekPos)
                    } else if (videoPlayer.useFFmpeg && videoPlayer.ffmpegPlayer) {
                        videoPlayer.ffmpegPlayer.seek(seekPos)
                    } else {
                        mediaPlayer.position = seekPos
                    }
                    
                    // Resume playback if it was playing before seek (after a short delay to let seek complete)
                    // ✅ Use same backend object that was seeked to prevent accidental reset
                    if (wasPlaying) {
                        Qt.callLater(function() {
                            console.log("[VideoPlayer] Resuming playback after seek")
                            if (videoPlayer.useFFmpeg && videoPlayer.ffmpegPlayer) {
                                videoPlayer.ffmpegPlayer.play()
                            } else if (videoPlayer.useLibmpv && videoPlayer.mpvPlayer) {
                                videoPlayer.mpvPlayer.play()
                            } else if (videoPlayer.useWMF && wmfPlayer) {
                                wmfPlayer.play()
                            } else {
                                videoPlayer.play()
                            }
                        })
                    }
                } else {
                    console.log("[VideoPlayer] onSeekReleased called but no valid pending seek - resetting state")
                    // Safety: reset state even if seek wasn't properly initialized
                    videoPlayer._isSeeking = false
                    videoPlayer._pendingSeekPos = -1
                    videoPlayer._wasPlayingBeforeSeek = false
                }
            }
            
            onVolumeAdjusted: function(vol) {
                videoPlayer.volume = vol
                if (videoPlayer.useFFmpeg && videoPlayer.ffmpegPlayer) {
                    videoPlayer.ffmpegPlayer.volume = vol
                } else if (videoPlayer.useLibmpv && videoPlayer.mpvPlayer) {
                    videoPlayer.mpvPlayer.volume = vol
                } else if (videoPlayer.useWMF && wmfPlayer) {
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
                    if (videoPlayer.useLibmpv && videoPlayer.mpvPlayer) {
                        videoPlayer.mpvPlayer.volume = 0
                    } else if (videoPlayer.useWMF && wmfPlayer) {
                        wmfPlayer.volume = 0
                    } else {
                        audioOutput.volume = 0
                    }
                } else {
                    // Restore saved volume
                    if (videoPlayer.savedVolume > 0) {
                        videoPlayer.volume = videoPlayer.savedVolume
                        if (videoPlayer.useLibmpv && videoPlayer.mpvPlayer) {
                            videoPlayer.mpvPlayer.volume = videoPlayer.savedVolume
                        } else if (videoPlayer.useWMF && wmfPlayer) {
                            wmfPlayer.volume = videoPlayer.savedVolume
                        } else {
                            audioOutput.volume = videoPlayer.savedVolume
                        }
                    } else {
                        // If no saved volume, restore to a reasonable default (0.5)
                        videoPlayer.volume = 0.5
                        if (videoPlayer.useLibmpv && videoPlayer.mpvPlayer) {
                            videoPlayer.mpvPlayer.volume = 0.5
                        } else if (videoPlayer.useWMF && wmfPlayer) {
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
    property int duration: (useLibmpv && mpvPlayer) ? mpvPlayer.duration : 
                           ((useWMF && wmfPlayer) ? wmfPlayer.duration :
                            (useFFmpeg && ffmpegPlayer) ? ffmpegPlayer.duration :
                            mediaPlayer.duration)
    property int position: (useLibmpv && mpvPlayer) ? mpvPlayer.position : 
                           ((useWMF && wmfPlayer) ? wmfPlayer.position :
                            (useFFmpeg && ffmpegPlayer) ? ffmpegPlayer.position :
                            mediaPlayer.position)
    property int playbackState: (useLibmpv && mpvPlayer) ? mpvPlayer.playbackState : 
                                 ((useWMF && wmfPlayer) ? wmfPlayer.playbackState :
                                  (useFFmpeg && ffmpegPlayer) ? ffmpegPlayer.playbackState :
                                  mediaPlayer.playbackState)
    property bool hasVideo: (useLibmpv && mpvPlayer) ? true : 
                            ((useWMF && wmfPlayer) ? true : mediaPlayer.hasVideo)
    // For webm files, check hasAudio more carefully - WMF player might not detect correctly
    property bool hasAudio: {
        if (useLibmpv && mpvPlayer) {
            return mpvPlayer.hasAudio !== undefined ? mpvPlayer.hasAudio : true
        } else if (useWMF && wmfPlayer) {
            // WMF player - use its hasAudio property if available
            if (wmfPlayer.hasAudio !== undefined) {
                return wmfPlayer.hasAudio
            }
            // If undefined, check if source is webm - for webm, default to false if undefined
            // (webm files might not have audio, and WMF might not detect it correctly)
            if (source.toString().toLowerCase().endsWith('.webm')) {
                return false  // Default to no audio for webm if WMF doesn't report it
            }
            return true  // Default to true for other formats
        } else if (useLibvlc && vlcPlayer) {
            return vlcPlayer.hasAudio !== undefined ? vlcPlayer.hasAudio : true
        } else {
            // MediaPlayer - use its hasAudio property
            return mediaPlayer.hasAudio
        }
    }
    property var metaData: (useLibmpv && mpvPlayer) ? ({}) : ((useWMF && wmfPlayer) ? ({}) : ((useLibvlc && vlcPlayer) ? ({}) : mediaPlayer.metaData))
    property int implicitWidth: (useLibmpv && mpvPlayer) ? 0 : videoDisplay.implicitWidth  // libmpv doesn't expose this via VideoOutput
    property int implicitHeight: (useLibmpv && mpvPlayer) ? 0 : videoDisplay.implicitHeight  // libmpv doesn't expose this via VideoOutput
    property bool seekable: (useLibmpv && mpvPlayer) ? mpvPlayer.seekable : 
                            ((useWMF && wmfPlayer) ? wmfPlayer.seekable : 
                            ((useLibvlc && vlcPlayer) ? vlcPlayer.seekable :
                            (useFFmpeg && ffmpegPlayer) ? ffmpegPlayer.seekable :
                            mediaPlayer.seekable))
    
    // HDR/Color Space Diagnostic - Log when video dimensions change
    onImplicitWidthChanged: {
        if (implicitWidth > 0 && implicitHeight > 0) {
            console.log("[VideoPlayer] 🎨 Video dimensions changed:", implicitWidth, "x", implicitHeight)
            const aspectRatio = implicitWidth / implicitHeight
            console.log("[VideoPlayer] 🎨 Aspect ratio:", aspectRatio.toFixed(2))
            // 4K HDR content is often 3840x2160 or 4096x2160
            const is4K = implicitWidth >= 3840 || implicitHeight >= 2160
            console.log("[VideoPlayer] 🎨 Is 4K/UHD:", is4K)
        }
    }
    
    onImplicitHeightChanged: {
        if (implicitWidth > 0 && implicitHeight > 0) {
            console.log("[VideoPlayer] 🎨 Video dimensions changed:", implicitWidth, "x", implicitHeight)
        }
    }
    property real playbackRate: (useWMF && wmfPlayer) ? 1.0 : ((useLibvlc && vlcPlayer) ? 1.0 : mediaPlayer.playbackRate)
    
    function play() { 
        if (useLibmpv && mpvPlayer) {
            mpvPlayer.play()
        } else if (useWMF && wmfPlayer) {
            wmfPlayer.play()
        } else if (useLibvlc && vlcPlayer) {
            vlcPlayer.play()
        } else if (useFFmpeg && ffmpegPlayer) {
            ffmpegPlayer.play()
        } else {
            mediaPlayer.play()
        }
    }
    function pause() { 
        if (useLibmpv && mpvPlayer) {
            mpvPlayer.pause()
        } else if (useWMF && wmfPlayer) {
            wmfPlayer.pause()
        } else if (useLibvlc && vlcPlayer) {
            vlcPlayer.pause()
        } else if (useFFmpeg && ffmpegPlayer) {
            ffmpegPlayer.pause()
        } else {
            mediaPlayer.pause()
        }
    }
    function stop() { 
        if (useLibmpv && mpvPlayer) {
            mpvPlayer.stop()
        } else if (useWMF && wmfPlayer) {
            wmfPlayer.stop()
        } else if (useLibvlc && vlcPlayer) {
            vlcPlayer.stop()
        } else if (useFFmpeg && ffmpegPlayer) {
            ffmpegPlayer.stop()
        } else {
            mediaPlayer.stop()
        }
    }
    
    onSourceChanged: {
        if (source !== "") {
            // HDR/Color Space Diagnostic Logging
            console.log("[VideoPlayer] 🎨 ===== VIDEO SOURCE CHANGED =====")
            console.log("[VideoPlayer] 🎨 Source URL:", source)
            const sourceStr = source.toString().toLowerCase()
            const isHDR = sourceStr.includes("hdr") || sourceStr.includes("dv") || sourceStr.includes("dolby")
            console.log("[VideoPlayer] 🎨 File name suggests HDR:", isHDR)
            console.log("[VideoPlayer] 🎨 Using WMF:", useWMF)
            console.log("[VideoPlayer] 🎨 Using libmpv:", useLibmpv)
            console.log("[VideoPlayer] 🎨 Using libvlc:", useLibvlc)
            console.log("[VideoPlayer] 🎨 Using FFmpeg:", useFFmpeg)
            console.log("[VideoPlayer] 🎨 Video dimensions:", implicitWidth, "x", implicitHeight)
            console.log("[VideoPlayer] 🎨 =================================")
            
            // Reset fixing state when source changes (unless it's the fixed version)
            if (source !== fixedVideoUrl) {
                isFixingVideo = false
                // Only clear originalVideoSource if we're loading a completely new video
                // Don't clear it if we're just retrying the same video (prevents auto-fix retry loops)
                const sourceStr2 = String(source)
                const originalStr = String(originalVideoSource)
                if (sourceStr2 !== originalStr) {
                originalVideoSource = ""
                }
                positionStallCount = 0
                lastPosition = 0
            }
            // Extract subtitle info if using custom engine (external mode)
            if (subtitleEngine === "external" && embeddedSubtitleExtractor) {
                console.log("[VideoPlayer] Custom engine mode: Extracting subtitle info from:", source)
                embeddedSubtitleExtractor.extractSubtitleInfo(source)
                // Disable QMediaPlayer's built-in subtitle rendering (we use custom engine)
                if (mediaPlayer) {
                    mediaPlayer.activeSubtitleTrack = -1
                    console.log("[VideoPlayer] Disabled QMediaPlayer subtitle rendering for custom engine")
                }
                // Don't pre-extract - let user choose which track they want (saves time)
            }
            
            // Enable backend loaders now that we have a real source
            if (useWMF) {
                wmfReady = true
            } else if (useLibmpv) {
                libmpvReady = true
            } else if (useLibvlc) {
                libvlcReady = true
            } else if (useFFmpeg) {
                ffmpegReady = true
            } else {
                wmfReady = false
                libmpvReady = false
                libvlcReady = false
                ffmpegReady = false
            }
            // Only set MediaPlayer source if NOT using WMF or libmpv or libvlc or FFmpeg
            // WMF, libmpv, libvlc, and FFmpeg players get source automatically via binding
            if (!useWMF && !useLibmpv && !useLibvlc && !useFFmpeg) {
                mediaPlayer.source = source
                mediaPlayer.play()
            } else {
                // When using WMF or libmpv or libvlc or FFmpeg, ensure MediaPlayer is stopped and cleared
                mediaPlayer.stop()
                mediaPlayer.source = ""
            }
        } else {
            // Disable backend loaders when source is cleared
            wmfReady = false
            libmpvReady = false
            libvlcReady = false
            ffmpegReady = false
        }
    }
}

