import QtMultimedia
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Qt5Compat.GraphicalEffects
import s3rpent_media

Item {
    id: audioPlayer
    
    // Debug flag - set to true to enable verbose logging
    readonly property bool debugMode: Qt.application.arguments.indexOf("--debug") !== -1 || false
    
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
    property bool lyricsTranslationEnabled: false
    property string lyricsTranslationApiKey: ""
    property string lyricsTranslationTargetLanguage: "en"
    property var translatedLyricLines: []  // Store translated lyrics
    property bool isTranslating: false
    property int instantDuration: 0  // Duration from C++ helper (instant, before player loads)
    property int _lastEmittedDuration: 0  // Track last emitted duration to prevent infinite loops
    
    // Computed properties to avoid repeated ternary expressions
    readonly property var currentPlayer: (betaAudioProcessingEnabled && customPlayer) ? customPlayer : player
    readonly property int currentPlaybackState: currentPlayer ? currentPlayer.playbackState : MediaPlayer.StoppedState
    readonly property var currentMetaData: (betaAudioProcessingEnabled && customPlayer && customPlayer.metaData) 
        ? customPlayer.metaData 
        : (player.metaData ? player.metaData : {})
    readonly property int currentPosition: (betaAudioProcessingEnabled && customPlayer) ? customPlayer.position : player.position
    readonly property int _playerDuration: (betaAudioProcessingEnabled && customPlayer) ? customPlayer.duration : player.duration
    
    // Debounced seeking properties
    property bool _isSeeking: false
    property int _pendingSeekPos: -1
    property int _lastCommittedSeekPos: -1
    property int _seekSpamCount: 0  // Debug counter
    
    // Custom audio player for real EQ processing
    property CustomAudioPlayer customPlayer: null
    
    // Discord Rich Presence integration
    DiscordRPC {
        id: discordRPC
        // Settings are loaded automatically in C++ constructor
        // Can be overridden by external property binding
    }
    
    // Property to control Discord RPC from settings
    // Default to false - will be set from window property via Binding
    property bool discordRPCEnabled: false
    
    // Sync external property with DiscordRPC component
    onDiscordRPCEnabledChanged: {
        if (discordRPC) {
            discordRPC.enabled = discordRPCEnabled
            // If enabled and we have a current track, update presence after connection
            if (discordRPCEnabled && source !== "") {
                // Wait for Discord to connect, then update
                // The connectionStatusChanged signal will handle the actual update
            }
        }
    }
    
    // Listen for Discord connection status changes
    Connections {
        target: discordRPC
        function onConnectionStatusChanged(connected) {
            // When Discord connects and we have a track playing, update presence
            if (connected && discordRPCEnabled && source !== "") {
                // Small delay to ensure connection is fully established
                Qt.callLater(function() {
                    if (discordRPC && discordRPC.enabled && source !== "") {
                        updateDiscordRPC()
                        // Also fetch cover art if we have metadata but no cover art URL yet
                        const meta = (betaAudioProcessingEnabled && customPlayer && customPlayer.metaData) 
                            ? customPlayer.metaData 
                            : (player.metaData ? player.metaData : {})
                        const title = getMetaString(MediaMetaData.Title) || getMetaString("Title") || ""
                        const artist = getMetaString(MediaMetaData.ContributingArtist) || getMetaString("ContributingArtist") || getMetaString("Artist") || ""
                        const album = getMetaString(MediaMetaData.AlbumTitle) || getMetaString("AlbumTitle") || getMetaString("Album") || ""
                        if (title !== "") {
                            // Check if we already have cover art from the selected source
                            const hasCoverArt = (coverArtSource === "lastfm" && lastFMClient.fetchedCoverArtUrl !== "") ||
                                               (coverArtSource === "coverartarchive" && coverArtClient.fetchedCoverArtUrl !== "")
                            const isLoading = (coverArtSource === "lastfm" && lastFMClient.loading) ||
                                            (coverArtSource === "coverartarchive" && coverArtClient.loading)
                            if (!hasCoverArt && !isLoading) {
                                if (coverArtSource === "lastfm") {
                                    lastFMClient.fetchCoverArt(title, artist, lastFMApiKey)
                                } else if (coverArtSource === "coverartarchive") {
                                    coverArtClient.fetchCoverArt(title, artist, album)
                                }
                            }
                        }
                    }
                }, 200)
            }
        }
    }
    
    // Also sync when DiscordRPC component is ready
    // Use Qt.callLater to ensure DiscordRPC is fully initialized
    Component.onCompleted: {
        Qt.callLater(function() {
            if (discordRPC) {
                discordRPC.enabled = discordRPCEnabled
            }
        })
    }
    
    // Cover Art Archive client for fetching cover art
    CoverArtClient {
        id: coverArtClient
        
        property string fetchedCoverArtUrl: ""
        
        onCoverArtFound: function(url) {
            fetchedCoverArtUrl = url
            // Update Discord RPC with the fetched cover art
            if (discordRPC && discordRPC.enabled) {
                updateDiscordRPC()
            }
        }
        
        onCoverArtNotFound: {
            fetchedCoverArtUrl = ""
            // Fall back to local cover art if available
            if (discordRPC && discordRPC.enabled) {
                updateDiscordRPC()
            }
        }
    }
    
    // Last.fm client for fetching cover art
    LastFMClient {
        id: lastFMClient
        
        property string fetchedCoverArtUrl: ""
        
        onCoverArtFound: function(url) {
            fetchedCoverArtUrl = url
            // Update Discord RPC with the fetched cover art
            if (discordRPC && discordRPC.enabled) {
                updateDiscordRPC()
            }
        }
        
        onCoverArtNotFound: {
            fetchedCoverArtUrl = ""
            // Fall back to local cover art if available
            if (discordRPC && discordRPC.enabled) {
                updateDiscordRPC()
            }
        }
    }
    
    // Property to control which cover art source to use
    property string coverArtSource: "coverartarchive"  // "coverartarchive" or "lastfm"
    property string lastFMApiKey: ""  // Last.fm API key (optional)
    
    // Windows media session integration
    WindowsMediaSession {
        id: windowsMediaSession
        
        // Initialize with window handle after window is created
        Component.onCompleted: {
            // Get the window from the parent hierarchy
            // Look for ApplicationWindow or appWindow property
            var windowObj = null
            var parentItem = parent
            
            while (parentItem && !windowObj) {
                // Check if it's an ApplicationWindow (has title, width, height properties)
                if (parentItem.hasOwnProperty("title") && 
                    parentItem.hasOwnProperty("width") && 
                    parentItem.hasOwnProperty("height")) {
                    windowObj = parentItem
                    break
                }
                // Check for appWindow property (used in MainContentArea)
                if (parentItem.hasOwnProperty("appWindow") && parentItem.appWindow) {
                    windowObj = parentItem.appWindow
                    break
                }
                // Check for window property
                if (parentItem.hasOwnProperty("window") && parentItem.window) {
                    windowObj = parentItem.window
                    break
                }
                parentItem = parentItem.parent
            }
            
            if (windowObj) {
                // Found the window, initialize Windows Media Session after a short delay
                // to ensure the window is fully created and has a valid HWND
                Qt.callLater(function() {
                    windowsMediaSession.initializeWithWindow(windowObj)
                })
            } else {
                console.log("[WindowsMediaSession] Could not find window for initialization")
            }
        }
        
        // Handle Windows media control commands
        onPlayRequested: {
            if (betaAudioProcessingEnabled && customPlayer) {
                customPlayer.play()
            } else {
                player.play()
            }
            // Update Windows Media Session immediately to keep it in sync
            // Use a short delay to ensure state change has propagated
            Qt.callLater(function() {
                updateWindowsMediaSessionPlaybackState()
            }, 100)
        }
        onPauseRequested: {
            if (betaAudioProcessingEnabled && customPlayer) {
                customPlayer.pause()
            } else {
                player.pause()
            }
            // Update Windows Media Session immediately to keep it in sync
            // Use a short delay to ensure state change has propagated
            Qt.callLater(function() {
                updateWindowsMediaSessionPlaybackState()
            }, 100)
        }
        onStopRequested: {
            // Windows sometimes sends "Stop" when play/pause key is pressed while paused
            // Instead of stopping (which resets position), treat it as a play/pause toggle
            // Only actually stop if we're already stopped
            if (currentPlaybackState === MediaPlayer.StoppedState) {
                // Already stopped, do nothing (or could restart if desired)
                return
            } else if (currentPlaybackState === MediaPlayer.PlayingState) {
                // Playing -> pause
                // Update Windows Media Session to Paused BEFORE changing state
                // This ensures Windows knows the correct state immediately
                if (windowsMediaSession) {
                    windowsMediaSession.updatePlaybackState(2) // Paused
                }
            if (betaAudioProcessingEnabled && customPlayer) {
                    customPlayer.pause()
            } else {
                    player.pause()
                }
            } else {
                // Paused -> play (treat stop as unpause when paused)
                // Update Windows Media Session to Playing BEFORE changing state
                // This ensures Windows knows the correct state immediately
                if (windowsMediaSession) {
                    windowsMediaSession.updatePlaybackState(1) // Playing
                }
                if (betaAudioProcessingEnabled && customPlayer) {
                    customPlayer.play()
                } else {
                    player.play()
                }
            }
            
            // Also update after state change propagates (onPlaybackStateChanged will also handle this)
            Qt.callLater(function() {
                updateWindowsMediaSessionPlaybackState()
            }, 100)
        }
        onNextRequested: {
            // Could implement next track if you have a playlist
            console.log("[WindowsMediaSession] Next requested")
        }
        onPreviousRequested: {
            // Could implement previous track if you have a playlist
            console.log("[WindowsMediaSession] Previous requested")
        }
    }
    
    // Function to update Windows media session
    // Track last source to avoid repeated setSource calls
    property string lastWindowsMediaSessionSource: ""
    
    // EVENT-DRIVEN Windows Media Session updates (NOT timer-based)
    // Windows SMTC is state-based, not timeline-based - only update on actual events
    
    function updateWindowsMediaSessionMetadata() {
        if (!windowsMediaSession || source === "") return
        
        // Only set source when it actually changes
        if (lastWindowsMediaSessionSource !== source) {
            windowsMediaSession.setSource(source)
            lastWindowsMediaSessionSource = source
        }
        
        // Extract metadata ONCE and reuse
        const title = getMetaString(MediaMetaData.Title) || getMetaString("Title") || ""
        const artist = getMetaString(MediaMetaData.ContributingArtist) || getMetaString("ContributingArtist") || getMetaString("Artist") || ""
        const album = getMetaString(MediaMetaData.AlbumTitle) || getMetaString("AlbumTitle") || getMetaString("Album") || ""
        
        // Update metadata (ONLY when track changes)
        windowsMediaSession.updateMetadata(title, artist, album, coverArt)
    }
    
    function updateWindowsMediaSessionPlaybackState() {
        if (!windowsMediaSession) {
            if (debugMode) {
                console.log("[WindowsMediaSession] updateWindowsMediaSessionPlaybackState - windowsMediaSession is null")
            }
            return
        }
        
        // Use computed property for playback state
        const state = (currentPlaybackState === MediaPlayer.PlayingState) ? 1 
            : (currentPlaybackState === MediaPlayer.PausedState) ? 2 
            : 0
        
        if (debugMode) {
            console.log("[WindowsMediaSession] updateWindowsMediaSessionPlaybackState - player state:", currentPlaybackState, "(0=Stopped, 1=Playing, 2=Paused), updating Windows to:", state, "(0=Stopped, 1=Playing, 2=Paused)")
        }
        windowsMediaSession.updatePlaybackState(state)
    }
    
    // Function to update Discord Rich Presence
    function updateDiscordRPC() {
        if (!discordRPC || !discordRPC.enabled || source === "") {
            return
        }
        
        // Use computed properties to avoid repeated metadata extraction
        const meta = currentMetaData
        
        // Extract metadata strings ONCE
        const title = getMetaString(MediaMetaData.Title) || getMetaString("Title") || ""
        const artist = getMetaString(MediaMetaData.ContributingArtist) || getMetaString("ContributingArtist") || getMetaString("Artist") || ""
        const album = getMetaString(MediaMetaData.AlbumTitle) || getMetaString("AlbumTitle") || getMetaString("Album") || ""
        
        // Skip updating Discord RPC if we don't have a title yet (metadata is still loading)
        // This prevents showing "unknown song" when switching tracks
        if (title === "") {
            return
        }
        
        // Skip updating Discord RPC if metadata is not fully initialized
        // This prevents using wrong duration from previous track during autoplay
        if (!metadataInitialized) {
            return
        }
        
        // Use computed property for playback state
        const playbackState = (currentPlaybackState === MediaPlayer.PlayingState) ? 1 
            : (currentPlaybackState === MediaPlayer.PausedState) ? 2 
            : 0
        
        // Use computed properties for position and duration
        // For duration, prefer instantDuration (from C++ helper) as it's more reliable and available earlier
        const pos = currentPosition
        const dur = instantDuration > 0 ? instantDuration : _playerDuration
        
        // Get cover art URL - prefer fetched URL (HTTP), fall back to local file
        let coverArtUrl = ""
        
        // First, try fetched cover art URL (HTTP/HTTPS - works with Discord)
        if (coverArtSource === "lastfm" && lastFMClient.fetchedCoverArtUrl !== "") {
            coverArtUrl = lastFMClient.fetchedCoverArtUrl
        } else if (coverArtSource === "coverartarchive" && coverArtClient.fetchedCoverArtUrl !== "") {
            coverArtUrl = coverArtClient.fetchedCoverArtUrl
        } else if (coverArt && coverArt !== "") {
            // Fall back to local cover art (file:// URL - Discord might not accept it)
            coverArtUrl = coverArt.toString()
            // If it's a local file path, ensure it's a proper file:// URL
            if (coverArtUrl.startsWith("file:///")) {
                // Already a file URL, use as-is
            } else if (coverArtUrl.startsWith("/") || coverArtUrl.match(/^[A-Za-z]:/)) {
                // Windows path or absolute path, convert to file:// URL
                coverArtUrl = "file:///" + coverArtUrl.replace(/\\/g, "/")
            }
        }
        
        // Update Discord presence with cover art
        discordRPC.updatePresence(title, artist, pos, dur, playbackState, album, coverArtUrl)
    }
    
    // OLD FUNCTION - REMOVED: updateWindowsMediaSession()
    // This was being called from timers every 200-300ms, causing lag
    // Windows SMTC does NOT need timeline updates - it handles position internally
    
    // Update Windows media session when cover art changes (event-driven, no timer)
    onCoverArtChanged: {
        updateWindowsMediaSessionMetadata()
    }
    
    
    signal durationAvailable()
    signal playbackStateUpdated()
    signal coverArtExtracted()
    
    // When duration becomes available, check if metadata is initialized
    onDurationAvailable: {
        checkMetadataInitialized()
    }
    
    function formatTime(ms) {
        if (!ms || ms <= 0) return "0:00"
        const totalSeconds = Math.floor(ms / 1000)
        const minutes = Math.floor(totalSeconds / 60)
        const seconds = totalSeconds % 60
        return minutes + ":" + (seconds < 10 ? "0" : "") + seconds
    }
    
    // Function to fetch cover art if needed (consolidates duplicate logic)
    function fetchCoverArtIfNeeded() {
        // Get metadata using computed property
        const meta = currentMetaData
        if (!meta) return
        
        const title = getMetaString(MediaMetaData.Title) || getMetaString("Title") || ""
        const artist = getMetaString(MediaMetaData.ContributingArtist) || getMetaString("ContributingArtist") || getMetaString("Artist") || ""
        const album = getMetaString(MediaMetaData.AlbumTitle) || getMetaString("AlbumTitle") || getMetaString("Album") || ""
        
        if (title === "") return
        
        // Check if we already have cover art from the selected source
        const hasCoverArt = (coverArtSource === "lastfm" && lastFMClient.fetchedCoverArtUrl !== "") ||
                           (coverArtSource === "coverartarchive" && coverArtClient.fetchedCoverArtUrl !== "")
        const isLoading = (coverArtSource === "lastfm" && lastFMClient.loading) ||
                         (coverArtSource === "coverartarchive" && coverArtClient.loading)
        
        if (!hasCoverArt && !isLoading) {
            if (coverArtSource === "lastfm") {
                lastFMClient.fetchCoverArt(title, artist, lastFMApiKey)
            } else if (coverArtSource === "coverartarchive") {
                coverArtClient.fetchCoverArt(title, artist, album)
            }
        }
    }
    
    // Custom audio player for real EQ processing (when beta is enabled)
    CustomAudioPlayer {
        id: customPlayer
        // Duration changed is handled in Connections block below to avoid duplicate handlers
        Component.onCompleted: {
            // Sync volume from CustomAudioPlayer (which loads from Settings) to AudioPlayer's volume property
            if (customPlayer.volume !== undefined) {
                audioPlayer.volume = customPlayer.volume
            }
        }
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
            // Always log errors, even in production
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
        // Removed onDurationChanged - using instant duration from C++ helper instead
        function onPlaybackStateChanged() {
            if (debugMode) {
                console.log("[AudioPlayer] player.onPlaybackStateChanged - new state:", player.playbackState, "(0=Stopped, 1=Playing, 2=Paused)")
            }
            playbackStateUpdated()
            // EVENT-DRIVEN: Update Windows Media Session ONLY on state change (not from timers)
            updateWindowsMediaSessionPlaybackState()
            // Update Discord RPC on state change
            updateDiscordRPC()
            if (player.playbackState === MediaPlayer.PlayingState) {
                showControls = true
                controlsHideTimer.start()
                // After starting playback, do an additional Windows Media Session update
                // with a small delay to ensure Windows has fully registered the session
                // This fixes the issue where first pause by key doesn't work properly
                Qt.callLater(function() {
                    if (debugMode) {
                        console.log("[AudioPlayer] player.onPlaybackStateChanged - delayed update after PlayingState")
                    }
                    updateWindowsMediaSessionPlaybackState()
                }, 200)
            } else {
                showControls = true
                controlsHideTimer.stop()
            }
        }
        function onSourceChanged() {
            handleMetadataSourceChange("player-source")
            // Source change handled by main onSourceChanged
        }
        function onPositionChanged() {
            // Throttle position updates (update every 500ms max)
            if (!positionUpdateTimer.running) {
                positionUpdateTimer.restart()
            }
            // DO NOT call Windows Media Session from position updates - Windows handles this internally
            // Update Discord RPC position (throttled via timer)
            if (discordRPC && discordRPC.enabled) {
                updateDiscordRPC()
            }
        }
        function onDurationChanged() {
            // DO NOT call Windows Media Session from duration updates - Windows handles this internally
            // Check if metadata is now fully initialized (duration might have just become available)
            checkMetadataInitialized()
        }
        function onMetaDataChanged() {
            scheduleMetadataRefresh(0, "player-metadata")
            // EVENT-DRIVEN: Update metadata when it actually changes (track loaded)
            updateWindowsMediaSessionMetadata()
            // Fetch cover art when metadata changes
            fetchCoverArtIfNeeded()
            // Check if metadata is now fully initialized
            checkMetadataInitialized()
            // Update Discord RPC when metadata changes (only if initialized)
            updateDiscordRPC()
        }
    }
    
    // Connections for CustomAudioPlayer when beta processing is enabled
    Connections {
        target: (betaAudioProcessingEnabled && customPlayer) ? customPlayer : null
        function onVolumeChanged() {
            if (customPlayer && Math.abs(audioPlayer.volume - customPlayer.volume) > 0.001) {
                // Sync CustomAudioPlayer's volume (loaded from Settings) to AudioPlayer's volume property
                audioPlayer.volume = customPlayer.volume
            }
        }
        // Removed onDurationChanged - using instant duration from C++ helper instead
        function onPlaybackStateChanged() {
            if (customPlayer) {
                if (debugMode) {
                    console.log("[AudioPlayer] customPlayer.onPlaybackStateChanged - new state:", customPlayer.playbackState, "(0=Stopped, 1=Playing, 2=Paused)")
                }
                playbackStateUpdated()
                // EVENT-DRIVEN: Update Windows Media Session ONLY on state change (not from timers)
                updateWindowsMediaSessionPlaybackState()
                // Update Discord RPC on state change
                updateDiscordRPC()
                if (customPlayer.playbackState === CustomAudioPlayer.PlayingState) {
                    showControls = true
                    controlsHideTimer.start()
                    // After starting playback, do an additional Windows Media Session update
                    // with a small delay to ensure Windows has fully registered the session
                    // This fixes the issue where first pause by key doesn't work properly
                    Qt.callLater(function() {
                        if (debugMode) {
                            console.log("[AudioPlayer] customPlayer.onPlaybackStateChanged - delayed update after PlayingState")
                        }
                        updateWindowsMediaSessionPlaybackState()
                    }, 200)
                } else {
                    showControls = true
                    controlsHideTimer.stop()
                }
            }
        }
        function onSourceChanged() {
            handleMetadataSourceChange("custom-player-source")
            // Source change handled by main onSourceChanged
        }
        function onMetaDataChanged() {
            if (customPlayer) {
                scheduleMetadataRefresh(0, "custom-metadata")
                // EVENT-DRIVEN: Update metadata when it actually changes (track loaded)
                updateWindowsMediaSessionMetadata()
                // Fetch cover art when metadata changes
                fetchCoverArtIfNeeded()
                // Check if metadata is now fully initialized
                checkMetadataInitialized()
                // Update Discord RPC when metadata changes (only if initialized)
                updateDiscordRPC()
            }
        }
        function onPositionChanged() {
            // Throttle position updates (update every 500ms max)
            if (!positionUpdateTimer.running) {
                positionUpdateTimer.restart()
            }
            // DO NOT call Windows Media Session from position updates - Windows handles this internally
        }
        function onDurationChanged() {
            // DO NOT call Windows Media Session from duration updates - Windows handles this internally
            // Duration is handled automatically by Windows when source is set
            // Check if metadata is now fully initialized (duration might have just become available)
            checkMetadataInitialized()
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
            if (currentPlaybackState === MediaPlayer.PlayingState && !controlsMouseArea.containsMouse) {
                showControls = false
            }
        }
    }
    
    // Timer to throttle position updates for UI (NOT for Windows Media Session)
    Timer {
        id: positionUpdateTimer
        interval: 500  // Update UI every 500ms
        running: false
        repeat: false
        onTriggered: {
            // Position updates are for UI only - Windows handles position internally
            // DO NOT call Windows Media Session from position updates
        }
    }
    
    // REMOVED: windowsMediaSessionUpdateTimer
    // Windows SMTC is event-driven, not timer-driven
    // Updates now happen only on actual events (track change, play/pause)
    
    // Debounce timer for seeking (prevents seek spam while dragging)
    Timer {
        id: seekCommitTimer
        interval: 120  // Commit seek after 120ms of no new seek requests
        repeat: false
        onTriggered: {
            if (_pendingSeekPos < 0) return
            const pos = _pendingSeekPos
            _pendingSeekPos = -1
            _lastCommittedSeekPos = pos
            _isSeeking = false
            
            // Preserve playback state - don't auto-start if paused
            const wasPlaying = currentPlaybackState === MediaPlayer.PlayingState
            
            if (betaAudioProcessingEnabled && customPlayer) {
                // CustomPlayer now handles state preservation internally
                customPlayer.seek(pos)
            } else {
                // For QMediaPlayer, we need to manually preserve state
                player.position = pos
                // Restore playback state after a brief delay (QMediaPlayer might auto-resume)
                Qt.callLater(function() {
                    if (!wasPlaying && player.playbackState === MediaPlayer.PlayingState) {
                        player.pause()
                    }
                })
            }
        }
    }
    
    // Debug timer to show seek spam rate (only runs in debug mode)
    Timer {
        interval: 1000
        running: debugMode
        repeat: true
        onTriggered: {
            if (_seekSpamCount > 0 && debugMode) {
                console.log("[AudioPlayer] Seek spam rate:", _seekSpamCount, "seeks/sec")
                _seekSpamCount = 0
            } else if (_seekSpamCount > 0) {
                _seekSpamCount = 0
            }
        }
    }
    
    // Timer to check playback state after autoplay (fixes issue where state isn't detected immediately)
    // Autoplay doesn't always fire onPlaybackStateChanged signal, so we need to force updates
    Timer {
        id: autoplayStateCheckTimer
        interval: 100  // Start with quick check
        running: false
        repeat: false
        property int checkCount: 0
        property bool hasActivatedSession: false  // Track if we've "activated" Windows Media Session
        onTriggered: {
            // Use computed property for playback state
            if (debugMode) {
                console.log("[AudioPlayer] autoplayStateCheckTimer triggered - checkCount:", checkCount, "current player state:", currentPlaybackState, "(0=Stopped, 1=Playing, 2=Paused), hasActivatedSession:", hasActivatedSession)
            }
            
            // Always update state-dependent features after autoplay
            // This ensures they're in sync even if onPlaybackStateChanged didn't fire
            playbackStateUpdated()
            updateWindowsMediaSessionPlaybackState()
            // Check if metadata is initialized before updating Discord RPC
            checkMetadataInitialized()
            if (discordRPC && discordRPC.enabled && metadataInitialized) {
                updateDiscordRPC()
            }
            
            // Check multiple times to catch delayed state changes
            checkCount++
            if (checkCount < 3) {
                interval = 100 + (checkCount * 100)  // 100ms, 200ms, 300ms
                if (debugMode) {
                    console.log("[AudioPlayer] autoplayStateCheckTimer - restarting with interval:", interval)
                }
                restart()
            } else {
                // After all checks, "activate" Windows Media Session by simulating a state transition
                // Windows Media Session needs to see a pause/play cycle to fully activate
                // This is what happens when you manually pause/unpause, which fixes the media keys
                if (!hasActivatedSession && currentPlaybackState === MediaPlayer.PlayingState) {
                    if (debugMode) {
                        console.log("[AudioPlayer] autoplayStateCheckTimer - activating Windows Media Session with state transition")
                    }
                    hasActivatedSession = true
                    // Simulate a brief pause/play cycle to activate the session
                    // Update to Paused first, then immediately back to Playing
                    // This doesn't actually pause the player, just tells Windows about the transition
                    if (windowsMediaSession) {
                        windowsMediaSession.updatePlaybackState(2)  // Paused
                        Qt.callLater(function() {
                            if (windowsMediaSession) {
                                windowsMediaSession.updatePlaybackState(1)  // Playing
                                if (debugMode) {
                                    console.log("[AudioPlayer] autoplayStateCheckTimer - Windows Media Session activated")
                                }
                            }
                        }, 50)
                    }
                } else {
                    // Final update
                    if (debugMode) {
                        console.log("[AudioPlayer] autoplayStateCheckTimer - all checks complete, final update")
                    }
                    Qt.callLater(function() {
                        updateWindowsMediaSessionPlaybackState()
                    })
                }
                checkCount = 0  // Reset for next autoplay
                interval = 100   // Reset interval
            }
        }
    }
    
    // LRCLIB client for fetching lyrics
    LRCLibClient {
        id: lyricsClient
        
        onLyricsFetched: function(success, errorMessage) {
            audioPlayer.lastLyricsStatus = lyricsClient.lastStatusInfo || audioPlayer.lastLyricsStatus
            if (success) {
                if (debugMode) {
                console.log("[Lyrics] Lyrics fetched successfully")
                }
                // Trigger translation if enabled
                if (lyricsTranslationEnabled && lyricsClient.lyricLines.length > 0) {
                    translateCurrentLyrics()
                } else {
                    // Clear translated lyrics if translation is disabled
                    translatedLyricLines = []
                }
            } else {
                const statusInfo = audioPlayer.lastLyricsStatus || {}
                const message = statusInfo.message || errorMessage
                currentLyricIndex = -1
                translatedLyricLines = []
            }
        }
        
        onLyricLinesChanged: {
            if (lyricsClient.lyricLines.length === 0) {
                currentLyricIndex = -1
                translatedLyricLines = []
            }
            // Translation is handled in onLyricsFetched to avoid duplicate calls
        }
    }
    
    // Translation client for lyrics
    LyricsTranslationClient {
        id: translationClient
        
        onTranslationComplete: function(translatedLines) {
            if (debugMode) {
            console.log("[Translation] Translation complete:", translatedLines.length, "lines")
            }
            translatedLyricLines = translatedLines
            isTranslating = false
        }
        
        onTranslationFailed: function(error) {
            if (debugMode) {
            console.warn("[Translation] Translation failed:", error)
            }
            // Keep original lyrics if translation fails
            translatedLyricLines = []
            isTranslating = false
        }
    }
    
    // Helper function to clean artist name (extracted to avoid duplication)
    function cleanArtistName(artistName) {
        if (!artistName) return ""
        
        let cleaned = artistName
        
        // Normalize semicolons to commas
        if (cleaned.indexOf(";") !== -1) {
            cleaned = cleaned.replace(/;\s*/g, ", ")
        }
        
        // Normalize ampersands
        cleaned = cleaned.replace(/\s+&amp;\s+/g, ", ")
        cleaned = cleaned.replace(/\s+&\s+/g, ", ")
        
        // Clean up spaces
        cleaned = cleaned.replace(/\s+/g, " ")
        cleaned = cleaned.replace(/,\s*,/g, ",")
        cleaned = cleaned.replace(/,\s+/g, ", ")
        cleaned = cleaned.replace(/\s+,/g, ",")
        
        return cleaned.trim()
    }
    
    function translateCurrentLyrics() {
        if (!lyricsTranslationEnabled || lyricsTranslationApiKey === "" || lyricsClient.lyricLines.length === 0) {
            return
        }
        
        // Get metadata for cache key
        const meta = currentMetaData
        if (!meta) {
            if (debugMode) {
            console.log("[Translation] Missing metadata for translation")
            }
            return
        }
        
        // Use the existing getMetaString function defined at the top of AudioPlayer
        const trackName = getMetaString(MediaMetaData.Title) || getMetaString("Title") || ""
        let artistName = getMetaString(MediaMetaData.ContributingArtist) || getMetaString("ContributingArtist") || getMetaString("Artist") || ""
        const albumName = getMetaString(MediaMetaData.AlbumTitle) || getMetaString("AlbumTitle") || getMetaString("Album") || ""
        
        // Clean artist name using helper function
        artistName = cleanArtistName(artistName)
        
        if (trackName === "") {
            if (debugMode) {
            console.log("[Translation] Missing track name for translation")
            }
            return
        }
        
        if (debugMode) {
        console.log("[Translation] Starting translation for:", trackName, artistName, albumName)
        }
        isTranslating = true
        translationClient.translateLyrics(
            trackName,
            artistName,
            albumName,
            lyricsClient.lyricLines,
            lyricsTranslationApiKey,
            lyricsTranslationTargetLanguage
        )
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
            const hasLyrics = lyricsClient.lyricLines.length > 0 || translatedLyricLines.length > 0
            return currentPlaybackState === MediaPlayer.PlayingState && showLyrics && hasLyrics
        }
        repeat: true
        onTriggered: {
            const position = currentPosition
            // Use original lyrics for timing (translated lyrics have same timestamps)
            const linesToUse = translatedLyricLines.length > 0 ? translatedLyricLines : lyricsClient.lyricLines
            // Find current index based on timestamp
            let newIndex = -1
            for (let i = 0; i < linesToUse.length; i++) {
                const line = linesToUse[i]
                if (line && line.timestamp !== undefined && position >= line.timestamp) {
                    newIndex = i
                } else {
                    break
                }
            }
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
        const meta = currentMetaData
        if (!meta) {
            if (debugMode) {
            console.log("[Lyrics] Missing metadata for lyrics fetch")
            }
            return
        }
        
        const trackName = getMetaString(MediaMetaData.Title) || getMetaString("Title") || ""
        let artistName = getMetaString(MediaMetaData.ContributingArtist) || getMetaString("ContributingArtist") || getMetaString("Artist") || ""
        const albumName = getMetaString(MediaMetaData.AlbumTitle) || getMetaString("AlbumTitle") || getMetaString("Album") || ""
        
        // Track name is required (search API requires at least track_name)
        if (!trackName) {
            if (debugMode) {
            console.log("[Lyrics] Missing required metadata for lyrics fetch - trackName:", trackName)
            }
            return
        }
        
        // Artist and album are optional - search API can work with just track_name
        if (!artistName && debugMode) {
            console.log("[Lyrics] Artist name missing, will try fetching with track and album only")
        }
        if (!albumName && debugMode) {
            console.log("[Lyrics] Album name missing, will try fetching with track and artist only")
        }
        
        // Clean up artist name using helper function
        const originalArtistName = artistName
        artistName = cleanArtistName(artistName)
        
        if (originalArtistName !== artistName && debugMode) {
            console.log("[Lyrics] Cleaned artist name:", originalArtistName, "->", artistName)
        }
        
        // Create a signature for this song to avoid duplicate fetches (without duration)
        const signature = trackName + "|" + artistName + "|" + albumName
        
        // Only fetch if this is a different song or if we haven't fetched yet
        if (signature === lastFetchedSignature) {
            if (debugMode) {
            console.log("[Lyrics] Already fetched lyrics for this song, skipping")
            }
            return
        }
        
        // Don't fetch if already loading
        if (lyricsClient.loading) {
            if (debugMode) {
            console.log("[Lyrics] Already loading lyrics, skipping")
            }
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
        height: 56
        visible: audioPlayer.source !== ""
        opacity: (controlsMouseArea.containsMouse || currentPlaybackState !== MediaPlayer.PlayingState || showControls) ? 1.0 : 0.0
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
                if (currentPlaybackState === MediaPlayer.PlayingState) {
                    showControls = true
                    controlsHideTimer.restart()
                }
            }
        }
        
        AudioControls {
            id: audioControls
            anchors.fill: parent
            position: audioPlayer.position  // Use debounced position (shows preview while seeking)
            duration: audioPlayer.duration  // Use AudioPlayer's duration property which uses instantDuration when available
            volume: audioPlayer.volume
            playbackState: currentPlaybackState
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
                // Debounced seeking: update preview immediately, commit after pause or on release
                _seekSpamCount++  // Debug counter
                _isSeeking = true
                // Clamp position to valid range
                const duration = audioPlayer.duration
                _pendingSeekPos = Math.max(0, Math.min(pos, duration > 0 ? duration - 1 : pos))
                
                // Restart the commit timer - this collapses many seeks into one
                // If user keeps dragging, timer keeps restarting
                // Only when they pause or release does it actually seek
                seekCommitTimer.restart()
            }
            
            // If AudioControls exposes seekReleased signal, handle it here
            // Otherwise, the debounce timer will handle it after 120ms pause
            onSeekReleased: {
                _isSeeking = false
                // Commit immediately on release (don't wait for timer)
                if (seekCommitTimer.running) {
                    seekCommitTimer.stop()
                    seekCommitTimer.triggered()
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
                if (debugMode) {
                console.log("[Audio] Pitch adjusted to:", newPitch, "(not applied - requires audio processing)")
                }
            }
            
            onTempoAdjusted: function(newTempo) {
                player.playbackRate = newTempo
            }
            
            onEqBandChanged: function(band, value) {
                // AudioEqualizer now automatically syncs to CustomAudioPlayer when beta is enabled
                if (equalizer) {
                    equalizer.setBandGain(band, value)
                    if (betaAudioProcessingEnabled && customPlayer && debugMode) {
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
                    equalizer.setEnabled(enabled)
                    if (betaAudioProcessingEnabled && customPlayer && debugMode) {
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
            return currentPlaybackState === MediaPlayer.PlayingState
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
            if (debugMode) {
            console.log("[Audio] EQ", enabled ? "enabled" : "disabled")
            }
        }
    }
    
    // Connections for standard player
    Connections {
        target: player
        enabled: !betaAudioProcessingEnabled
        function onPlaybackStateChanged() {
            if (currentPlaybackState === MediaPlayer.PlayingState && showVisualizer) {
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
            if (currentPlaybackState === MediaPlayer.PlayingState && showVisualizer) {
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
        // Always visible when source is set - don't hide when metadata popup is open
        visible: source !== ""
        
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
                // CRITICAL: Use a property that can be explicitly set, but also reacts to metadata changes
                // When the UI is hidden and becomes visible, we need to ensure the text updates
                property string _titleText: getMetaString(MediaMetaData.Title) || getMetaString("Title") || "Unknown Title"
                text: _titleText
                color: foregroundColor
                font.pixelSize: Math.max(20, Math.min(48, mainContent.width * 0.05))
                font.bold: true
                wrapMode: Text.WordWrap
                elide: Text.ElideRight
                maximumLineCount: 2
                
                // CRITICAL: When mainContent becomes visible, force re-evaluation of metadata
                // This ensures the text updates even if it was set while the UI was hidden
                Connections {
                    target: mainContent
                    function onVisibleChanged() {
                        if (mainContent.visible) {
                            // Force refresh by calling the parent's refresh function
                            Qt.callLater(function() {
                                if (audioPlayer && typeof audioPlayer.refreshMetadataDisplay === "function") {
                                    audioPlayer.refreshMetadataDisplay({ triggerLyrics: false })
                                }
                            })
                        }
                    }
                }
            }
            
            // Artist (under title) - scales with window size
            Text {
                id: artistText
                Layout.fillWidth: true
                // CRITICAL: Use a property that can be explicitly set, but also reacts to metadata changes
                property string _artistText: getMetaString(MediaMetaData.ContributingArtist) || getMetaString("ContributingArtist") || getMetaString("Artist") || "Unknown Artist"
                text: _artistText
                color: Qt.lighter(foregroundColor, 1.2)
                font.pixelSize: Math.max(14, Math.min(28, mainContent.width * 0.03))
                wrapMode: Text.WordWrap
                elide: Text.ElideRight
                maximumLineCount: 1
                
                // CRITICAL: When mainContent becomes visible, force re-evaluation of metadata
                // This ensures the text updates even if it was set while the UI was hidden
                Connections {
                    target: mainContent
                    function onVisibleChanged() {
                        if (mainContent.visible) {
                            // Force refresh by calling the parent's refresh function
                            Qt.callLater(function() {
                                if (audioPlayer && typeof audioPlayer.refreshMetadataDisplay === "function") {
                                    audioPlayer.refreshMetadataDisplay({ triggerLyrics: false })
                                }
                            })
                        }
                    }
                }
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
        
        // Update the internal properties instead of directly setting text
        // This preserves the binding while allowing explicit updates
        if (titleText._titleText !== title) {
            titleText._titleText = title
        }
        if (artistText._artistText !== artist) {
            artistText._artistText = artist
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
                // EVENT-DRIVEN: Update Windows media session when metadata is ready (track loaded)
                updateWindowsMediaSessionMetadata()
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
        visible: source !== "" && !showingMetadata && showLyrics && 
                 ((lyricsClient.lyricLines.length > 0 || translatedLyricLines.length > 0) || 
                  lyricsClient.loading || isTranslating || showStatusMessage)
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
            Layout.minimumHeight: 0
            clip: true
            contentWidth: width
            contentHeight: lyricsColumn.implicitHeight
            interactive: false  // Disable manual scrolling, we control it programmatically
            visible: lyricsClient.lyricLines.length > 0 || translatedLyricLines.length > 0
            
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
                    // Use translated lyrics if available, otherwise use original
                    model: translatedLyricLines.length > 0 ? translatedLyricLines : lyricsClient.lyricLines
                    
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
                    const linesToUse = translatedLyricLines.length > 0 ? translatedLyricLines : lyricsClient.lyricLines
                    if (currentLyricIndex >= 0 && currentLyricIndex < linesToUse.length && lyricsColumn.children.length > currentLyricIndex) {
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
        
        // Loading indicator / Status message with spinner
        Row {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignHCenter
            spacing: 12
            visible: lyricsClient.loading || isTranslating || showStatusMessage
            opacity: visible ? 1.0 : 0.0
            
            Behavior on opacity {
                NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
            }
            
            // Spinner (only show when loading/translating)
            Item {
                width: 16
                height: 16
                anchors.verticalCenter: parent.verticalCenter
                visible: lyricsClient.loading || isTranslating
                
                Rectangle {
                    id: spinnerDot1
                    width: 4
                    height: 4
                    radius: 2
                    color: Qt.lighter(foregroundColor, 1.3)
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    opacity: 0.3
                }
                
                Rectangle {
                    id: spinnerDot2
                    width: 4
                    height: 4
                    radius: 2
                    color: Qt.lighter(foregroundColor, 1.3)
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    opacity: 0.6
                }
                
                Rectangle {
                    id: spinnerDot3
                    width: 4
                    height: 4
                    radius: 2
                    color: Qt.lighter(foregroundColor, 1.3)
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    opacity: 1.0
                }
                
                RotationAnimation on rotation {
                    from: 0
                    to: 360
                    duration: 1200
                    loops: Animation.Infinite
                    running: lyricsClient.loading || isTranslating
                }
            }
            
            Text {
                id: lyricsStatusIndicatorText
                anchors.verticalCenter: parent.verticalCenter
                text: {
                    if (lyricsClient.loading) {
                        return qsTr("Searching for lyrics...")
                    } else if (isTranslating) {
                        return qsTr("Translating lyrics...")
                    } else if (showStatusMessage) {
                        return lastStatusMessage
                    }
                    return ""
                }
                color: Qt.lighter(foregroundColor, 1.3)
                font.pixelSize: 14
                font.family: "Segoe UI"
                opacity: 0.8
            }
        }
    }

    // Status message (no lyrics found, instrumental, etc.)
    property bool showStatusMessage: false
    property string lastStatusMessage: ""
    
    Timer {
        id: statusMessageHideTimer
        interval: 3500  // Hide after 3.5 seconds
        onTriggered: {
            showStatusMessage = false
        }
    }
    
    Connections {
        target: lyricsClient
        function onLyricsFetched(success, errorMessage) {
            // Use a small delay to ensure lastLyricsStatus is updated
            Qt.callLater(function() {
                if (!success && !lyricsClient.loading) {
                    const info = audioPlayer.lastLyricsStatus || {}
                    const message = info && info.message ? info.message : (errorMessage || "")
                    if (message && message !== "Lyrics loaded" && !message.toLowerCase().includes("lyrics loaded")) {
                        lastStatusMessage = message
                        showStatusMessage = true
                        statusMessageHideTimer.restart()
                    }
                } else if (success) {
                    showStatusMessage = false
                    statusMessageHideTimer.stop()
                }
            })
        }
    }
    
    // Also watch for status changes directly
    Connections {
        target: lyricsClient
        function onLastStatusChanged() {
            if (!lyricsClient.loading && lyricsClient.lyricLines.length === 0) {
                const info = lyricsClient.lastStatusInfo || {}
                const statusName = info.statusName || ""
                const message = info.message || ""
                
                // Show message for "noMatch" or "instrumental" statuses
                if ((statusName === "noMatch" || statusName === "instrumental") && message) {
                    if (message !== "Lyrics loaded" && !message.toLowerCase().includes("lyrics loaded")) {
                        lastStatusMessage = message
                        showStatusMessage = true
                        statusMessageHideTimer.restart()
                    }
                }
            }
        }
    }
    
    // Expose player properties
    // Use instant duration from C++ helper if available, otherwise use player duration
    // Note: _playerDuration is already defined above as a computed property (line 46)
    // Use instant duration from C++ helper (same as metadata menu) when available, otherwise fall back to player duration
    property int duration: instantDuration > 0 ? instantDuration : (_playerDuration > 0 ? _playerDuration : 0)
    
    // Track if metadata is fully initialized (title and duration available)
    // This prevents Discord RPC and other features from using incomplete metadata
    property bool metadataInitialized: false
    // Live position from player (actual playback position)
    property int _livePosition: (betaAudioProcessingEnabled && customPlayer) ? customPlayer.position : player.position
    // Display position: show preview while seeking, otherwise show live position
    property int position: _isSeeking && _pendingSeekPos >= 0 ? _pendingSeekPos : _livePosition
    property int playbackState: (betaAudioProcessingEnabled && customPlayer) ? customPlayer.playbackState : player.playbackState
    property var metaData: (betaAudioProcessingEnabled && customPlayer) ? customPlayer.metaData : player.metaData
    property bool seekable: (betaAudioProcessingEnabled && customPlayer) ? customPlayer.seekable : player.seekable
    
    signal coverArtAvailable(url coverArtUrl)
    
    // Function to check if metadata is fully initialized (title + duration)
    function checkMetadataInitialized() {
        const title = getMetaString(MediaMetaData.Title) || getMetaString("Title") || ""
        const hasTitle = title !== ""
        
        // For duration, prefer instantDuration (from C++ helper) as it's more reliable
        // Only use player duration if instantDuration is not available yet
        // Also ensure duration is reasonable (at least 1 second, not just > 0)
        const currentDuration = instantDuration > 0 ? instantDuration : (_playerDuration > 0 ? _playerDuration : 0)
        const hasDuration = currentDuration >= 1000  // At least 1 second (1000ms)
        
        const wasInitialized = metadataInitialized
        metadataInitialized = hasTitle && hasDuration
        
        // If metadata just became initialized, update Discord RPC
        if (metadataInitialized && !wasInitialized && discordRPC && discordRPC.enabled) {
            Qt.callLater(function() {
                updateDiscordRPC()
            })
        }
    }
    
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
        // Reset Windows Media Session source tracking when source changes
        lastWindowsMediaSessionSource = ""
        
        // Clear Discord RPC when source changes
        if (discordRPC && discordRPC.enabled) {
            discordRPC.clearPresence()
        }
        
        // EVENT-DRIVEN: Update Windows media session when source changes (only once per track)
        // Note: This is called via onMetaDataChanged instead to avoid timing issues during component destruction
        // The metadata change handler will call updateWindowsMediaSessionMetadata() when metadata is ready
        
        // Reset instant duration and last emitted duration when source changes
        instantDuration = 0
        _lastEmittedDuration = 0
        // Reset metadata initialization flag when source changes
        metadataInitialized = false
        
        // Get duration instantly from C++ helper if available (same as metadata menu uses)
        if (source !== "" && typeof ColorUtils !== "undefined" && typeof ColorUtils.getAudioDuration === "function") {
            Qt.callLater(function() {
                try {
                    const duration = ColorUtils.getAudioDuration(source)
                    if (duration > 0) {
                        instantDuration = duration
                        _lastEmittedDuration = duration
                        // Emit durationAvailable when instant duration is set (same as metadata menu uses)
                        durationAvailable()
                        // Check if metadata is now fully initialized and fetch lyrics (consolidated into single delayed call)
                        Qt.callLater(function() {
                            // Guard: Check if component is still valid
                            if (source !== "") {
                                checkMetadataInitialized()
                                // Fetch lyrics when duration is available (consolidated into same call)
                            fetchLyrics()
                            }
                        }, 50)  // Small delay to ensure title metadata is also available
                    }
                } catch (e) {
                    // Ignore errors
                }
            })
        }
        
        currentLyricIndex = -1
        lastFetchedSignature = ""  // Reset signature when source changes
        lyricsFetchTimer.stop()  // Cancel any pending fetch
        
        // Clear old lyrics when source changes to prevent showing lyrics from previous song
        if (lyricsClient) {
            lyricsClient.clearLyrics()
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
                if (debugMode) {
                    console.log("[AudioPlayer] onSourceChanged - autoplay starting, source:", source)
                }
                // Reset activation flag when source changes
                autoplayStateCheckTimer.hasActivatedSession = false
                
                if (betaAudioProcessingEnabled && customPlayer) {
                    // Use custom player for real EQ processing
                    // CRITICAL: Only set source if it's different to prevent duplicate loading
                    if (customPlayer.source !== source) {
                        if (debugMode) {
                            console.log("[AudioPlayer] onSourceChanged - setting customPlayer.source")
                        }
                        customPlayer.source = source
                    }
                    customPlayer.volume = audioPlayer.volume

                    // Only play if not already playing
                    if (customPlayer.playbackState !== CustomAudioPlayer.PlayingState) {
                        if (debugMode) {
                            console.log("[AudioPlayer] onSourceChanged - calling customPlayer.play()")
                        }
                        customPlayer.play()
                        // Autoplay doesn't always fire onPlaybackStateChanged signal
                        // Force immediate state check and update
                        autoplayStateCheckTimer.interval = 100  // Check quickly first
                        autoplayStateCheckTimer.restart()
                        if (debugMode) {
                            console.log("[AudioPlayer] onSourceChanged - started autoplayStateCheckTimer")
                        }
                        // Note: Don't restart timer here - let it complete its 3-check cycle naturally
                        // The timer will activate Windows Media Session after completing all checks
                    }
                } else {
                    // Use standard player
                    if (player.source !== source) {
                        if (debugMode) {
                            console.log("[AudioPlayer] onSourceChanged - setting player.source")
                        }
                        player.source = source
                    }
                    if (player.playbackState !== MediaPlayer.PlayingState) {
                        if (debugMode) {
                            console.log("[AudioPlayer] onSourceChanged - calling player.play()")
                        }
                        player.play()
                        // Autoplay doesn't always fire onPlaybackStateChanged signal
                        // Force immediate state check and update
                        autoplayStateCheckTimer.interval = 100  // Check quickly first
                        autoplayStateCheckTimer.restart()
                        if (debugMode) {
                            console.log("[AudioPlayer] onSourceChanged - started autoplayStateCheckTimer")
                        }
                        // Note: Don't restart timer here - let it complete its 3-check cycle naturally
                        // The timer will activate Windows Media Session after completing all checks
                    }
                }
            }
        })
    }
    
    // Cover art updates are handled automatically via binding to window.audioCoverArt
    // No need for manual onCoverArtChanged handler - it was causing the flash
}

