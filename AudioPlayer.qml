import QtMultimedia
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Qt5Compat.GraphicalEffects
import s3rp3nt_media

Item {
    id: audioPlayer
    
    property url source: ""
    property real volume: 1.0
    property bool showControls: false
    property url coverArt: ""
    property color accentColor: "#121216"
    property color foregroundColor: "#f5f5f5"
    property bool showingMetadata: false
    property real savedVolume: 0.0  // Save volume before muting (0 means not saved yet)
    property bool showLyrics: true
    property int currentLyricIndex: -1
    property string lastFetchedSignature: ""  // Track last fetched song to avoid duplicates
    property bool showVisualizer: true
    property real currentPitch: 1.0  // Store pitch locally (MediaPlayer doesn't support it directly)
    property bool betaAudioProcessingEnabled: true
    property bool metadataReady: false
    property int metadataRetryRemaining: 0
    property var lastLyricsStatus: ({ status: 0, statusName: "idle", message: "" })
    
    // Custom audio player for real EQ processing
    property CustomAudioPlayer customPlayer: null
    
    signal durationAvailable()
    signal playbackStateUpdated()
    signal coverArtExtracted()
    
    function formatTime(ms) {
        if (!ms || ms <= 0) return "0:00"
        const totalSeconds = Math.floor(ms / 1000)
        const minutes = Math.floor(totalSeconds / 60)
        const seconds = totalSeconds % 60
        return minutes + ":" + (seconds < 10 ? "0" : "") + seconds
    }
    
    // Custom audio player for real EQ processing (when beta is enabled)
    CustomAudioPlayer {
        id: customPlayer
        // Duration changed is handled in Connections block below to avoid duplicate handlers
    }
    
    MediaPlayer {
        id: player
        audioOutput: AudioOutput {
            id: audioOutput
            Component.onCompleted: {
                volume = audioPlayer.volume
            }
        }
        onErrorOccurred: function(error, errorString) {
            console.error("[Audio] Error occurred:", error, errorString)
        }
    }
    
    Connections {
        target: player.audioOutput
        function onVolumeChanged(vol) {
            if (Math.abs(audioPlayer.volume - vol) > 0.001) {
                audioPlayer.volume = vol
            }
        }
    }
    
    Connections {
        target: player
        function onDurationChanged() {
            if (player.duration > 0) {
                // Only emit durationAvailable if duration changed significantly (more than 100ms)
                // This prevents infinite loops during decoding
                const lastDuration = audioPlayer.duration || 0
                if (Math.abs(player.duration - lastDuration) > 100) {
                    durationAvailable()
                    // Fetch lyrics when duration is available
                    Qt.callLater(function() {
                        fetchLyrics()
                    })
                }
            }
        }
        function onPlaybackStateChanged() {
            playbackStateUpdated()
            if (player.playbackState === MediaPlayer.PlayingState) {
                showControls = true
                controlsHideTimer.start()
            } else {
                showControls = true
                controlsHideTimer.stop()
            }
        }
        function onSourceChanged() {
            handleMetadataSourceChange("player-source")
        }
        function onMetaDataChanged() {
            scheduleMetadataRefresh(0, "player-metadata")
        }
    }
    
    // Connections for CustomAudioPlayer when beta processing is enabled
    Connections {
        target: (betaAudioProcessingEnabled && customPlayer) ? customPlayer : null
        function onDurationChanged() {
            if (customPlayer && customPlayer.duration > 0) {
                // Only emit durationAvailable if duration changed significantly (more than 100ms)
                // This prevents infinite loops during decoding
                const lastDuration = audioPlayer.duration || 0
                if (Math.abs(customPlayer.duration - lastDuration) > 100) {
                    durationAvailable()
                    // Fetch lyrics when duration is available
                    Qt.callLater(function() {
                        fetchLyrics()
                    })
                }
            }
        }
        function onPlaybackStateChanged() {
            if (customPlayer) {
                playbackStateUpdated()
                if (customPlayer.playbackState === CustomAudioPlayer.PlayingState) {
                    showControls = true
                    controlsHideTimer.start()
                } else {
                    showControls = true
                    controlsHideTimer.stop()
                }
            }
        }
        function onSourceChanged() {
            handleMetadataSourceChange("custom-player-source")
        }
        function onMetaDataChanged() {
            if (customPlayer) {
                scheduleMetadataRefresh(0, "custom-metadata")
            }
        }
    }
    
    // Timer to retry metadata refresh a few times while metadata is loading asynchronously
    Timer {
        id: metadataRetryTimer
        interval: 300
        repeat: false
        onTriggered: {
            attemptMetadataRefresh("retry")
        }
    }
    
    Timer {
        id: controlsHideTimer
        interval: 3000
        running: false
        onTriggered: {
            if (player.playbackState === MediaPlayer.PlayingState && !controlsMouseArea.containsMouse) {
                showControls = false
            }
        }
    }
    
    // LRCLIB client for fetching lyrics
    LRCLibClient {
        id: lyricsClient
        
        onLyricsFetched: function(success, errorMessage) {
            audioPlayer.lastLyricsStatus = lyricsClient.lastStatusInfo || audioPlayer.lastLyricsStatus
            if (success) {
                console.log("[Lyrics] Lyrics fetched successfully")
            } else {
                const statusInfo = audioPlayer.lastLyricsStatus || {}
                const message = statusInfo.message || errorMessage
                currentLyricIndex = -1
            }
        }
        
        onLyricLinesChanged: {
            if (lyricsClient.lyricLines.length === 0) {
                currentLyricIndex = -1
            }
        }
    }

    Connections {
        target: lyricsClient
        function onLastStatusChanged() {
            audioPlayer.lastLyricsStatus = lyricsClient.lastStatusInfo || audioPlayer.lastLyricsStatus
        }
    }
    
    // Timer to update current lyric line based on playback position
    Timer {
        id: lyricsUpdateTimer
        interval: 100  // Update every 100ms for smooth scrolling
        running: {
            const state = (betaAudioProcessingEnabled && customPlayer) ? customPlayer.playbackState : player.playbackState
            return state === MediaPlayer.PlayingState && showLyrics && lyricsClient.lyricLines.length > 0
        }
        repeat: true
        onTriggered: {
            const position = (betaAudioProcessingEnabled && customPlayer) ? customPlayer.position : player.position
            const newIndex = lyricsClient.getCurrentLyricLineIndex(position)
            if (newIndex !== currentLyricIndex) {
                currentLyricIndex = newIndex
                // Scrolling is handled automatically by the Connections block watching currentLyricIndex
            }
        }
    }
    
    // Debounce timer to prevent duplicate fetch requests
    Timer {
        id: lyricsFetchTimer
        interval: 300  // Wait 300ms before fetching to allow both signals to fire
        running: false
        repeat: false
        onTriggered: {
            doFetchLyrics()
        }
    }
    
    function fetchLyrics() {
        // Reset the timer - this will debounce multiple rapid calls
        lyricsFetchTimer.restart()
    }
    
    function doFetchLyrics() {
        // Get metadata - use customPlayer if available, otherwise player
        const meta = (betaAudioProcessingEnabled && customPlayer && customPlayer.metaData) ? customPlayer.metaData : (player.metaData ? player.metaData : null)
        if (!meta) {
            console.log("[Lyrics] Missing metadata for lyrics fetch")
            return
        }
        
        const trackName = getMetaString(MediaMetaData.Title) || getMetaString("Title") || ""
        let artistName = getMetaString(MediaMetaData.ContributingArtist) || getMetaString("ContributingArtist") || getMetaString("Artist") || ""
        const albumName = getMetaString(MediaMetaData.AlbumTitle) || getMetaString("AlbumTitle") || getMetaString("Album") || ""
        
        // Track name is required (search API requires at least track_name)
        if (!trackName) {
            console.log("[Lyrics] Missing required metadata for lyrics fetch - trackName:", trackName)
            return
        }
        
        // Artist and album are optional - search API can work with just track_name
        if (!artistName) {
            console.log("[Lyrics] Artist name missing, will try fetching with track and album only")
        }
        if (!albumName) {
            console.log("[Lyrics] Album name missing, will try fetching with track and artist only")
        }
        
        // Clean up artist name - normalize separators but preserve original order
        // The API works best with the full artist list in the original order
        let originalArtistName = artistName
        
        // Normalize semicolons to commas (API prefers commas)
        // Use a more careful replacement to preserve order
        if (artistName.indexOf(";") !== -1) {
            // Replace semicolons with commas, preserving spacing
            artistName = artistName.replace(/;\s*/g, ", ")
            console.log("[Lyrics] Normalized semicolons to commas")
        }
        
        // Normalize ampersands (both " & " and " &amp; ") to ", "
        // Be careful to preserve the order - only replace standalone ampersands between artists
        artistName = artistName.replace(/\s+&amp;\s+/g, ", ")
        artistName = artistName.replace(/\s+&\s+/g, ", ")
        
        // Clean up extra spaces around commas (but preserve order)
        // Remove multiple spaces, normalize comma spacing
        artistName = artistName.replace(/\s+/g, " ")  // Multiple spaces to single space
        artistName = artistName.replace(/,\s*,/g, ",")  // Comma-space-comma to comma
        artistName = artistName.replace(/,\s+/g, ", ")  // Normalize comma-space
        artistName = artistName.replace(/\s+,/g, ",")  // Space-comma to comma
        artistName = artistName.trim()  // Remove leading/trailing spaces
        
        if (originalArtistName !== artistName) {
            console.log("[Lyrics] Cleaned artist name:", originalArtistName, "->", artistName)
        }
        
        // Create a signature for this song to avoid duplicate fetches (without duration)
        const signature = trackName + "|" + artistName + "|" + albumName
        
        // Only fetch if this is a different song or if we haven't fetched yet
        if (signature === lastFetchedSignature) {
            console.log("[Lyrics] Already fetched lyrics for this song, skipping")
            return
        }
        
        // Don't fetch if already loading
        if (lyricsClient.loading) {
            console.log("[Lyrics] Already loading lyrics, skipping")
            return
        }
        
        lastFetchedSignature = signature
        lyricsClient.fetchLyrics(trackName, artistName, albumName, 0)  // Pass 0 to indicate no duration
    }
    
    // Audio controls overlay
    Item {
        id: controlsContainer
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 24
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(500, parent.width - 48)
        height: 50
        visible: audioPlayer.source !== ""
        opacity: (controlsMouseArea.containsMouse || player.playbackState !== MediaPlayer.PlayingState || showControls) ? 1.0 : 0.0
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
                if (player.playbackState === MediaPlayer.PlayingState) {
                    showControls = true
                    controlsHideTimer.restart()
                }
            }
        }
        
        AudioControls {
            id: audioControls
            anchors.fill: parent
            position: (betaAudioProcessingEnabled && customPlayer) ? customPlayer.position : player.position
            duration: (betaAudioProcessingEnabled && customPlayer) ? customPlayer.duration : player.duration
            volume: audioPlayer.volume
            playbackState: (betaAudioProcessingEnabled && customPlayer) ? customPlayer.playbackState : player.playbackState
            seekable: (betaAudioProcessingEnabled && customPlayer) ? customPlayer.seekable : player.seekable
            accentColor: audioPlayer.accentColor
            muted: (betaAudioProcessingEnabled && customPlayer) 
                   ? (customPlayer.volume === 0 && audioPlayer.volume > 0)
                   : (player.audioOutput.volume === 0 && audioPlayer.volume > 0)
            pitch: audioPlayer.currentPitch
            tempo: (!betaAudioProcessingEnabled) ? (player.playbackRate || 1.0) : 1.0
            loop: (betaAudioProcessingEnabled && customPlayer) ? customPlayer.loop : (player.loops === MediaPlayer.Infinite)
            
            // Initialize EQ enabled state from saved settings
            Component.onCompleted: {
                if (betaAudioProcessingEnabled && customPlayer) {
                    eqEnabled = customPlayer.isEQEnabled()
                }
            }
            
            onPlayClicked: {
                // CRITICAL: Stop the other player first to prevent dual playback
                if (betaAudioProcessingEnabled && customPlayer) {
                    player.stop()  // Stop regular player
                    customPlayer.play()
                } else {
                    if (customPlayer) {
                        customPlayer.stop()  // Stop custom player
                    }
                    player.play()
                }
                showControls = true
                controlsHideTimer.restart()
            }
            
            onPauseClicked: {
                if (betaAudioProcessingEnabled && customPlayer) {
                    customPlayer.pause()
                } else {
                    player.pause()
                }
                showControls = true
            }
            
            onSeekRequested: function(pos) {
                if (betaAudioProcessingEnabled && customPlayer) {
                    customPlayer.seek(pos)
                } else {
                    player.position = pos
                }
            }
            
            onVolumeAdjusted: function(vol) {
                audioPlayer.volume = vol
                if (betaAudioProcessingEnabled && customPlayer) {
                    customPlayer.volume = vol
                } else {
                    player.audioOutput.volume = vol
                }
                // If volume is adjusted while muted, unmute and update saved volume
                if (vol > 0 && audioPlayer.savedVolume === 0) {
                    audioPlayer.savedVolume = vol
                } else if (vol > 0) {
                    audioPlayer.savedVolume = vol
                }
            }
            
            onMuteToggled: function(isMuted) {
                if (betaAudioProcessingEnabled && customPlayer) {
                    // Handle mute for CustomAudioPlayer
                    if (isMuted) {
                        // Save current volume before muting (only if not already muted)
                        const currentVol = customPlayer.volume
                        if (currentVol > 0) {
                            audioPlayer.savedVolume = currentVol
                            audioPlayer.volume = currentVol  // Sync the property
                        }
                        // Mute by setting volume to 0
                        customPlayer.volume = 0
                    } else {
                        // Restore saved volume
                        if (audioPlayer.savedVolume > 0) {
                            audioPlayer.volume = audioPlayer.savedVolume
                            customPlayer.volume = audioPlayer.savedVolume
                        } else {
                            // If no saved volume, restore to a reasonable default (0.5)
                            audioPlayer.volume = 0.5
                            customPlayer.volume = 0.5
                        }
                    }
                } else {
                    // Handle mute for standard player
                    if (isMuted) {
                        // Save current volume before muting (only if not already muted)
                        const currentVol = player.audioOutput.volume
                        if (currentVol > 0) {
                            audioPlayer.savedVolume = currentVol
                            audioPlayer.volume = currentVol  // Sync the property
                        }
                        // Mute by setting volume to 0
                        player.audioOutput.volume = 0
                    } else {
                        // Restore saved volume
                        if (audioPlayer.savedVolume > 0) {
                            audioPlayer.volume = audioPlayer.savedVolume
                            player.audioOutput.volume = audioPlayer.savedVolume
                        } else {
                            // If no saved volume, restore to a reasonable default (0.5)
                            audioPlayer.volume = 0.5
                            player.audioOutput.volume = 0.5
                        }
                    }
                }
            }
            
            onPitchAdjusted: function(newPitch) {
                // Note: Qt's MediaPlayer doesn't support pitch directly
                // Pitch adjustment would require audio processing (e.g., using FFmpeg or audio effects)
                // For now, we'll store it but can't apply it directly
                audioPlayer.currentPitch = newPitch
                console.log("[Audio] Pitch adjusted to:", newPitch, "(not applied - requires audio processing)")
            }
            
            onTempoAdjusted: function(newTempo) {
                player.playbackRate = newTempo
            }
            
            onEqBandChanged: function(band, value) {
                // AudioEqualizer now automatically syncs to CustomAudioPlayer when beta is enabled
                if (equalizer) {
                    equalizer.setBandGain(band, value)
                    if (betaAudioProcessingEnabled && customPlayer) {
                        console.log("[Audio] EQ band", band, "set to", value, "dB (real EQ via CustomAudioPlayer)")
                    } else if (equalizer.enabled) {
                        // Fallback to old volume-based EQ for non-beta mode
                        let multiplier = equalizer.getVolumeMultiplier()
                        let baseVolume = audioPlayer.volume
                        player.audioOutput.volume = Math.min(1.0, baseVolume * multiplier)
                    } else {
                        player.audioOutput.volume = audioPlayer.volume
                    }
                }
            }
            
            onEqToggled: function(enabled) {
                // AudioEqualizer now automatically syncs to CustomAudioPlayer when beta is enabled
                if (equalizer) {
                    equalizer.enabled = enabled
                    if (betaAudioProcessingEnabled && customPlayer) {
                        console.log("[Audio] EQ", (enabled ? "enabled" : "disabled"), "(real EQ via CustomAudioPlayer)")
                    } else if (enabled) {
                        // Fallback to old volume-based EQ for non-beta mode
                        let multiplier = equalizer.getVolumeMultiplier()
                        let baseVolume = audioPlayer.volume
                        player.audioOutput.volume = Math.min(1.0, baseVolume * multiplier)
                    } else {
                        player.audioOutput.volume = audioPlayer.volume
                    }
                }
                // Update the toggle state
            }
            
            onLoopClicked: {
                if (betaAudioProcessingEnabled && customPlayer) {
                    customPlayer.loop = !customPlayer.loop
                } else {
                    // Standard player loop (if supported)
                    player.loops = (player.loops === MediaPlayer.Once) ? MediaPlayer.Infinite : MediaPlayer.Once
                }
            }
            
            // Sync EQ enabled state when popup opens
            onShowEQChanged: {
                if (audioControls.showEQ && betaAudioProcessingEnabled && customPlayer) {
                    // Sync toggle with actual EQ state
                    audioControls.eqEnabled = customPlayer.isEQEnabled()
                }
            }
        }
    }
    
    // Audio visualizer background
    AudioVisualizerView {
        id: audioVisualizer
        anchors.fill: parent
        z: -1  // Behind everything
        visualizerColor: foregroundColor
        active: {
            if (!showVisualizer || source === "") return false
            // Check the correct player based on betaAudioProcessingEnabled
            if (betaAudioProcessingEnabled && customPlayer) {
                return customPlayer.playbackState === CustomAudioPlayer.PlayingState
            } else {
                return player.playbackState === MediaPlayer.PlayingState
            }
        }
        audioAnalyzer: analyzerInstance
        
        property real baseAmplitude: volume * 0.6
        property real animatedAmplitude: 0.0
        
        amplitude: analyzerInstance && analyzerInstance.overallAmplitude ? analyzerInstance.overallAmplitude * 2.0 : animatedAmplitude
        
        Timer {
            interval: 100
            running: audioVisualizer.active && (!analyzerInstance || !analyzerInstance.active)
            repeat: true
            onTriggered: {
                // Fallback: Create smooth varying amplitude if analyzer not available
                const time = Date.now() * 0.001
                const wave1 = Math.sin(time * 2.0) * 0.3 + 0.7
                const wave2 = Math.sin(time * 3.5) * 0.2 + 0.8
                const wave3 = Math.sin(time * 1.3) * 0.1 + 0.9
                audioVisualizer.animatedAmplitude = audioVisualizer.baseAmplitude * wave1 * wave2 * wave3
            }
        }
        
        Behavior on amplitude {
            NumberAnimation {
                duration: 300
                easing.type: Easing.OutCubic
            }
        }
    }
    
    // Audio analyzer (C++ backend)
    property alias analyzer: analyzerInstance
    AudioVisualizer {
        id: analyzerInstance
        Component.onCompleted: {
            // Set the appropriate player based on betaAudioProcessingEnabled
            if (betaAudioProcessingEnabled && customPlayer) {
                // For CustomAudioPlayer, feed samples directly to avoid WASAPI loopback capturing all system audio
                customPlayer.audioVisualizer = analyzerInstance
                // CustomAudioPlayer is not a QMediaPlayer, but AudioVisualizer accepts QObject for compatibility
                analyzerInstance.setMediaPlayer(customPlayer)
            } else {
                // For standard player, use WASAPI loopback
                analyzerInstance.setMediaPlayer(player)
            }
        }
    }
    
    // Audio equalizer (C++ backend)
    AudioEqualizer {
        id: equalizer
        // Connect to CustomAudioPlayer when beta processing is enabled
        customAudioPlayer: (betaAudioProcessingEnabled && customPlayer) ? customPlayer : null
        
        Component.onCompleted: {
            // Note: applyToAudioOutput is not needed for the simplified volume-based approach
            // Real EQ processing uses CustomAudioProcessor when betaAudioProcessingEnabled is true
        }
        
        onEqBandsChanged: {
            // When EQ bands change, update the audio output (for non-beta mode)
            // Beta mode is handled automatically via customAudioPlayer property
        }
        
        onEnabledChanged: {
            console.log("[Audio] EQ", enabled ? "enabled" : "disabled")
        }
    }
    
    // Connections for standard player
    Connections {
        target: player
        enabled: !betaAudioProcessingEnabled
        function onPlaybackStateChanged() {
            if (player.playbackState === MediaPlayer.PlayingState && showVisualizer) {
                analyzerInstance.start()
            } else {
                analyzerInstance.stop()
            }
        }
    }
    
    // Connections for CustomAudioPlayer when beta is enabled
    Connections {
        target: (betaAudioProcessingEnabled && customPlayer) ? customPlayer : null
        function onPlaybackStateChanged() {
            if (customPlayer && customPlayer.playbackState === CustomAudioPlayer.PlayingState && showVisualizer) {
                analyzerInstance.start()
            } else {
                analyzerInstance.stop()
            }
        }
    }
    
    Connections {
        target: audioPlayer
        function onSourceChanged() {
            if (source !== "") {
                // Set the appropriate player based on betaAudioProcessingEnabled
                if (betaAudioProcessingEnabled && customPlayer) {
                    analyzerInstance.setMediaPlayer(customPlayer)
                } else {
                    analyzerInstance.setMediaPlayer(player)
                }
            }
        }
    }
    
    // Main content area with cover art on left and title/artist on right
    RowLayout {
        id: mainContent
        anchors.horizontalCenter: parent.horizontalCenter
        y: lyricsSection.visible 
            ? Math.max(30, parent.height * 0.08)  // Higher up when lyrics are visible
            : (parent.height - implicitHeight) / 2  // Center vertically when no lyrics
        width: Math.min(parent.width * 0.8, parent.width - 80)
        spacing: Math.max(24, parent.width * 0.04)
        visible: source !== "" && !showingMetadata
        
        Behavior on y {
            NumberAnimation {
                duration: 400
                easing.type: Easing.InOutCubic
            }
        }
        
        // Cover art on the left - scales with window size
        Rectangle {
            id: coverArtDisplay
            Layout.preferredWidth: Math.min(Math.max(150, parent.width * 0.25), 300)
            Layout.preferredHeight: Layout.preferredWidth
            Layout.alignment: Qt.AlignVCenter
            radius: Math.max(12, Layout.preferredWidth * 0.08)
            color: Qt.darker(accentColor, 1.3)
            border.color: Qt.darker(accentColor, 1.5)
            border.width: 2
            
            // Rounded mask for the image
            Rectangle {
                id: imageMask
                anchors.fill: parent
                anchors.margins: 2
                radius: parent.radius - 2
                color: "white"
                visible: false
            }
            
            // Cover art image with OpacityMask for rounded corners
            Image {
                id: coverArtImage
                anchors.fill: parent
                anchors.margins: 2
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                smooth: true
                cache: false
                source: coverArt !== "" ? coverArt : ""
                visible: coverArt !== "" && (status === Image.Ready || status === Image.Loading)
                layer.enabled: coverArt !== "" && status === Image.Ready
                layer.effect: OpacityMask {
                    maskSource: imageMask
                }
            }
            
            // Fallback background - only show when no cover art or image not ready
            Rectangle {
                anchors.fill: parent
                anchors.margins: 2
                radius: parent.radius - 2
                color: Qt.darker(accentColor, 1.2)
                visible: coverArt === "" || coverArtImage.status !== Image.Ready
            }
            
            // Song icon when no cover art
            Text {
                anchors.centerIn: parent
                visible: coverArt === ""
                text: "🎵"
                font.pixelSize: 80
                color: foregroundColor
                opacity: 0.7
                z: 10
            }
        }
        
        // Title and artist on the right
        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: Math.max(8, mainContent.width * 0.02)
            
            // Title (big) - scales with window size
            Text {
                id: titleText
                Layout.fillWidth: true
                text: getMetaString(MediaMetaData.Title) || getMetaString("Title") || "Unknown Title"
                color: foregroundColor
                font.pixelSize: Math.max(20, Math.min(48, mainContent.width * 0.05))
                font.bold: true
                wrapMode: Text.WordWrap
                elide: Text.ElideRight
                maximumLineCount: 2
            }
            
            // Artist (under title) - scales with window size
            Text {
                id: artistText
                Layout.fillWidth: true
                text: getMetaString(MediaMetaData.ContributingArtist) || getMetaString("ContributingArtist") || getMetaString("Artist") || "Unknown Artist"
                color: Qt.lighter(foregroundColor, 1.2)
                font.pixelSize: Math.max(14, Math.min(28, mainContent.width * 0.03))
                wrapMode: Text.WordWrap
                elide: Text.ElideRight
                maximumLineCount: 1
            }
        }
    }
    
    // Helper function to get metadata string
    function getMetaString(key) {
        // Use customPlayer metadata if available, otherwise fall back to player
        const meta = (betaAudioProcessingEnabled && customPlayer && customPlayer.metaData) ? customPlayer.metaData : (player.metaData ? player.metaData : null)
        if (!meta) return null
        
        try {
            // For QVariantMap (CustomAudioPlayer), access directly
            if (meta[key] !== undefined && meta[key] !== null && meta[key] !== "") {
                return String(meta[key])
            }
            // For QMediaMetaData (standard player), use stringValue if available
            if (typeof meta.stringValue === "function") {
                const result = meta.stringValue(key)
                if (result !== undefined && result !== null && result !== "") {
                    return String(result)
                }
            }
        } catch (e) {
            // ignore
        }
        return null
    }
    
    function refreshMetadataDisplay(options) {
        options = options || {}
        const forceUnknown = options.forceUnknown === true
        let title = forceUnknown ? "" : (getMetaString(MediaMetaData.Title) || getMetaString("Title") || "")
        let artist = forceUnknown ? "" : (getMetaString(MediaMetaData.ContributingArtist) || getMetaString("ContributingArtist") || getMetaString("Artist") || "")
        
        const hasTitle = !!title
        const hasArtist = !!artist
        
        if (!hasTitle) {
            title = "Unknown Title"
        }
        if (!hasArtist) {
            artist = "Unknown Artist"
        }
        
        if (titleText.text !== title) {
            titleText.text = title
        }
        if (artistText.text !== artist) {
            artistText.text = artist
        }
        
        const ready = hasTitle || hasArtist
        if (forceUnknown) {
            metadataReady = false
        } else if (ready) {
            const shouldTrigger = (options.triggerLyrics === undefined) ? true : options.triggerLyrics
            const forceLyrics = options.forceLyrics === true
            if (!metadataReady || forceLyrics) {
                metadataReady = true
                if (shouldTrigger) {
                    fetchLyrics()
                }
            }
        } else {
            metadataReady = false
        }
        return ready
    }
    
    function attemptMetadataRefresh(reason) {
        if (audioPlayer.source === "") {
            metadataRetryRemaining = 0
            metadataReady = false
            refreshMetadataDisplay({ forceUnknown: true, triggerLyrics: false })
            return
        }
        
        const ready = refreshMetadataDisplay({ reason: reason })
        if (!ready && metadataRetryRemaining > 0) {
            metadataRetryRemaining = Math.max(0, metadataRetryRemaining - 1)
            metadataRetryTimer.restart()
        } else {
            metadataRetryRemaining = 0
        }
    }
    
    function scheduleMetadataRefresh(retries, reason) {
        if (retries !== undefined) {
            metadataRetryRemaining = Math.max(0, retries)
        }
        metadataRetryTimer.stop()
        attemptMetadataRefresh(reason)
    }
    
    function handleMetadataSourceChange(reason) {
        metadataReady = false
        metadataRetryTimer.stop()
        refreshMetadataDisplay({ forceUnknown: true, triggerLyrics: false })
        if (audioPlayer.source === "") {
            metadataRetryRemaining = 0
            return
        }
        metadataRetryRemaining = 8
        attemptMetadataRefresh(reason)
    }
    
    // Lyrics display section
    ColumnLayout {
        id: lyricsSection
        anchors.top: mainContent.bottom
        anchors.topMargin: 24
        anchors.horizontalCenter: mainContent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 100  // Leave space for audio controls
        width: Math.min(mainContent.width, parent.width * 0.7)
        spacing: 8
        visible: source !== "" && !showingMetadata && showLyrics && lyricsClient.lyricLines.length > 0
        opacity: visible ? 1.0 : 0.0
        
        Behavior on opacity {
            NumberAnimation {
                duration: 500
                easing.type: Easing.InOutQuad
            }
        }
        
        // Scrollable list of all lyrics
        Flickable {
            id: lyricsFlickable
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: width
            contentHeight: lyricsColumn.implicitHeight
            interactive: false  // Disable manual scrolling, we control it programmatically
            
            // Smooth scroll animation
            Behavior on contentY {
                NumberAnimation {
                    duration: 600
                    easing.type: Easing.OutCubic
                }
            }
            
            Column {
                id: lyricsColumn
                width: lyricsFlickable.width
                spacing: 12
                
                Repeater {
                    id: lyricsRepeater
                    model: lyricsClient.lyricLines
                    
                    Text {
                        id: lyricItem
                        width: lyricsColumn.width
                        text: {
                            if (modelData && typeof modelData === "object") {
                                return modelData.text || ""
                            }
                            return ""
                        }
                        color: index === currentLyricIndex ? foregroundColor : Qt.lighter(foregroundColor, 1.3)
                        font.pixelSize: index === currentLyricIndex 
                            ? Math.max(18, Math.min(28, lyricsSection.width * 0.04))
                            : Math.max(14, Math.min(20, lyricsSection.width * 0.03))
                        font.bold: index === currentLyricIndex
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        opacity: index === currentLyricIndex ? 1.0 : 0.5
                        Behavior on opacity { 
                            NumberAnimation { 
                                duration: 500
                                easing.type: Easing.OutCubic
                            } 
                        }
                        Behavior on color { 
                            ColorAnimation { 
                                duration: 500
                                easing.type: Easing.OutCubic
                            } 
                        }
                        Behavior on font.pixelSize { 
                            NumberAnimation { 
                                duration: 500
                                easing.type: Easing.OutCubic
                            } 
                        }
                    }
                }
            }
            
            // Update scroll position when current lyric changes
            Connections {
                target: audioPlayer
                function onCurrentLyricIndexChanged() {
                    if (currentLyricIndex >= 0 && currentLyricIndex < lyricsClient.lyricLines.length && lyricsColumn.children.length > currentLyricIndex) {
                        // Get the actual item at the current index
                        const currentItem = lyricsColumn.children[currentLyricIndex]
                        if (currentItem) {
                            // Calculate target position to center the current line
                            const itemY = currentItem.y
                            const itemHeight = currentItem.height
                            const targetY = itemY - (lyricsFlickable.height / 2) + (itemHeight / 2)
                            
                            // Clamp to valid range and animate
                            lyricsFlickable.contentY = Math.max(0, Math.min(targetY, lyricsFlickable.contentHeight - lyricsFlickable.height))
                        }
                    }
                }
            }
        }
        
        // Loading indicator
        Text {
            Layout.fillWidth: true
            visible: lyricsClient.loading
            text: qsTr("Loading lyrics...")
            color: Qt.lighter(foregroundColor, 1.3)
            font.pixelSize: 14
            horizontalAlignment: Text.AlignHCenter
        }
    }

    Text {
        id: lyricsStatusText
        anchors.top: lyricsSection.bottom
        anchors.horizontalCenter: lyricsSection.horizontalCenter
        anchors.topMargin: 12
        text: {
            if (lyricsClient.loading) {
                return "Searching for lyrics..."
            }
            const info = audioPlayer.lastLyricsStatus || {}
            return info && info.message ? info.message : ""
        }
        visible: showLyrics && lyricsClient.lyricLines.length === 0 &&
                 ((lyricsClient.loading) ||
                  ((audioPlayer.lastLyricsStatus || {}).statusName !== "idle" &&
                   (audioPlayer.lastLyricsStatus || {}).message !== ""))
        color: Qt.lighter(foregroundColor, 1.3)
        font.pixelSize: 16
        opacity: visible ? 0.9 : 0.0
        Behavior on opacity { NumberAnimation { duration: 200 } }
    }
    
    // Expose player properties
    property int duration: (betaAudioProcessingEnabled && customPlayer) ? customPlayer.duration : player.duration
    property int position: (betaAudioProcessingEnabled && customPlayer) ? customPlayer.position : player.position
    property int playbackState: (betaAudioProcessingEnabled && customPlayer) ? customPlayer.playbackState : player.playbackState
    property var metaData: (betaAudioProcessingEnabled && customPlayer) ? customPlayer.metaData : player.metaData
    property bool seekable: (betaAudioProcessingEnabled && customPlayer) ? customPlayer.seekable : player.seekable
    
    signal coverArtAvailable(url coverArtUrl)
    
    function play() {
        // CRITICAL: Stop the other player first to prevent dual playback
        if (betaAudioProcessingEnabled && customPlayer) {
            player.stop()  // Stop regular player
            customPlayer.play()
        } else {
            if (customPlayer) {
                customPlayer.stop()  // Stop custom player
            }
            player.play()
        }
    }
    function pause() {
        if (betaAudioProcessingEnabled && customPlayer) {
            customPlayer.pause()
        } else {
            player.pause()
        }
    }
    function stop() {
        if (betaAudioProcessingEnabled && customPlayer) {
            customPlayer.stop()
        }
        player.stop()
    }
    
    onSourceChanged: {
        currentLyricIndex = -1
        lastFetchedSignature = ""  // Reset signature when source changes
        lyricsFetchTimer.stop()  // Cancel any pending fetch
        
        // Clear old lyrics when source changes to prevent showing lyrics from previous song
        if (lyricsClient) {
            lyricsClient.clearLyrics()
        }
        
        // Clear old lyrics when source changes to prevent showing lyrics from previous song
        if (lyricsClient && lyricsClient.lyricLines && lyricsClient.lyricLines.length > 0) {
            // Clear lyrics by triggering a clear (if available) or by resetting
            // Since we can't directly clear, we'll mark that we need to clear on next fetch
            // The lyrics will be cleared when new fetch starts or fails
        }
        
        handleMetadataSourceChange("audio-source-changed")

        // CRITICAL: Stop BOTH players first to prevent dual playback
        // Always stop both, regardless of which one we're about to use
        if (customPlayer) {
            customPlayer.stop()
        }
        player.stop()
        
        // Small delay to ensure audio devices are fully released
        Qt.callLater(function() {
            if (source !== "") {
                if (betaAudioProcessingEnabled && customPlayer) {
                    // Use custom player for real EQ processing
                    // CRITICAL: Only set source if it's different to prevent duplicate loading
                    if (customPlayer.source !== source) {
                        customPlayer.source = source
                    }
                    customPlayer.volume = audioPlayer.volume

                    // Only play if not already playing
                    if (customPlayer.playbackState !== CustomAudioPlayer.PlayingState) {
                        customPlayer.play()
                    }
                } else {
                    // Use standard player
                    if (player.source !== source) {
                        player.source = source
                    }
                    if (player.playbackState !== MediaPlayer.PlayingState) {
                        player.play()
                    }
                }
            }
        })
    }
    
    // Cover art updates are handled automatically via binding to window.audioCoverArt
    // No need for manual onCoverArtChanged handler - it was causing the flash
}

