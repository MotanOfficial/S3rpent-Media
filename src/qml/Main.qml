import QtMultimedia
import QtQuick
import QtQuick.Window
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import QtCore
import "../js/FileTypeUtils.js" as FileTypeUtils
import "../js/MediaFormatUtils.js" as MediaFormatUtils
import "../js/ImageNavigationUtils.js" as ImageNavigationUtils
import "../js/AudioUtils.js" as AudioUtils
import "../js/DebugUtils.js" as DebugUtils
import "../js/ViewManagementUtils.js" as ViewManagementUtils
import "../js/MediaLoaderUtils.js" as MediaLoaderUtils
import "../js/ColorManagementUtils.js" as ColorManagementUtils
import "../js/MediaUnloadUtils.js" as MediaUnloadUtils
import "../js/WindowLifecycleUtils.js" as WindowLifecycleUtils
import "../js/WindowResizeUtils.js" as WindowResizeUtils
import "../js/MediaChangeHandlerUtils.js" as MediaChangeHandlerUtils
import "../js/MediaLoaderFunctions.js" as MediaLoaderFunctions
import "../js/AudioProcessingFunctions.js" as AudioProcessingFunctions
import "../js/WindowResizeFunctions.js" as WindowResizeFunctions

ApplicationWindow {
    id: window
    width: 960
    height: 720
    minimumWidth: 640
    minimumHeight: 480
    visible: true
    title: qsTr("s3rpent media · Media Viewer")
    flags: Qt.Window | Qt.FramelessWindowHint
    color: "#000000"  // Black background to prevent white border in maximized/fullscreen (was Qt.transparent for DWM)
    // Full visuals (title bar, frame helper, media UI) load asynchronously — see MainVisuals.qml

    property url initialImage: ""
    property url currentImage: ""
    property bool isMainWindow: true  // Default to true for main window
    property var debugConsole: null  // Reference to debug console window
    
    // Watch for debugConsole being set
    onDebugConsoleChanged: {
        if (debugConsole) {
            logToDebugConsole("[App] Debug console reference received", "info")
            // Test the connection
            Qt.callLater(function() {
                if (typeof debugConsole.addLog === "function") {
                    logToDebugConsole("[App] Debug console connection verified", "info")
                } else {
                    console.log("[App] ERROR: debugConsole.addLog is not a function")
                }
            })
        }
    }
    property bool isVideo: false
    property bool isGif: false
    property bool isAudio: false
    property bool isMarkdown: false
    property bool isText: false
    property bool isPdf: false
    property bool isZip: false
    property bool isModel: false

    // Playback queue (Up Next)
    // - `playbackQueue` holds upcoming items (urls)
    // - `playbackHistory` holds already-played items (for Previous)
    // - repeatMode: "off" | "one" | "all" (applies to the queue)
    property var playbackQueue: []
    property var playbackHistory: []
    property bool queueShuffle: false
    property string queueRepeatMode: "off"
    property real zoomFactor: 1.0
    property real panX: 0
    property real panY: 0
    property bool dropActive: false
    property bool showingSettings: false
    property bool showingMetadata: false
    /** Top-level always-on-top overlay (see musicOverlayWindowComponent); toggle with Ctrl+Shift+O (or Ctrl+Alt+O fallback) */
    property bool musicOverlayVisible: false

    // Shell-level shortcut — always loaded (unlike AppShortcuts inside async MainVisuals).
    // Disabled when Win32 RegisterHotKey succeeds (see overlayHotkey.qtShortcutFallback).
    Shortcut {
        sequence: (typeof overlayHotkey !== "undefined" && overlayHotkey.activeShortcutSequence)
                  ? overlayHotkey.activeShortcutSequence
                  : "Ctrl+Shift+O"
        context: Qt.ApplicationShortcut
        enabled: typeof overlayHotkey === "undefined" || overlayHotkey.qtShortcutFallback
        onActivated: window.musicOverlayVisible = !window.musicOverlayVisible
    }
    property var musicOverlayWindowRef: null
    /** YouTube music-video UI (cover toggle + popup). Disabled while playback is unstable. */
    property bool musicVideoFeatureEnabled: false

    /** Listen Together (WebRTC P2P sync) — enabled when libdatachannel is built in. */
    property bool listenTogetherEnabled: typeof webrtcP2PAvailable !== "undefined" && webrtcP2PAvailable
    property bool showingListenTogether: false

    /** Video-only overlay for YouTube music videos. */
    property bool musicVideoOverlayVisible: false
    property var musicVideoOverlayWindowRef: null
    property bool _metadataClosingViaButton: false  // survives MetadataPopupManager Loader unload
    property real videoVolume: 1.0
    property real audioVolume: 1.0
    property bool videoHasNoAudio: false  // Track if current video has no audio track
    
    // Settings blocks - must be in same scope as properties they alias to
    // Note: Settings components cannot be moved to a child component because
    // property aliases require direct access to the properties in the same scope
    Settings {
        id: videoSettings
        category: "video"
        property alias volume: window.videoVolume
    }
    
    Settings {
        id: audioSettings
        category: "audio"
        property alias volume: window.audioVolume
    }
    
    Settings {
        id: appearanceSettings
        category: "appearance"
        property alias dynamicColoringEnabled: window.dynamicColoringEnabled
        property alias gradientBackgroundEnabled: window.gradientBackgroundEnabled
        property alias backdropBlurEnabled: window.backdropBlurEnabled
        property alias ambientGradientEnabled: window.ambientGradientEnabled
        property alias snowEffectEnabled: window.snowEffectEnabled
        property alias imageInterpolationMode: window.imageInterpolationMode
        property alias dynamicResolutionEnabled: window.dynamicResolutionEnabled
        property alias matchMediaAspectRatio: window.matchMediaAspectRatio
        property alias autoHideTitleBar: window.autoHideTitleBar
        property alias windowsAccentColorEnabled: window.windowsAccentColorEnabled
    }
    
    Settings {
        id: lyricsSettings
        category: "lyrics"
        property alias translationEnabled: window.lyricsTranslationEnabled
        property alias translationApiKey: window.lyricsTranslationApiKey
        property alias translationTargetLanguage: window.lyricsTranslationTargetLanguage
    }
    
    Settings {
        id: appSettings
        category: "app"
        property alias language: window.appLanguage
    }
    
    Settings {
        id: discordSettings
        category: "discord"
        property alias enabled: window.discordRPCEnabled
    }
    
    Settings {
        id: coverArtSettings
        category: "coverart"
        property alias source: window.coverArtSource
        property alias lastFMApiKey: window.lastFMApiKey
    }
    
    Settings {
        id: debugSettings
        category: "debug"
        property alias consoleEnabled: window.debugConsoleEnabled
    }

    // Queue persistence
    Settings {
        id: queueSettings
        category: "queue"
        property string stateJson: ""
        property bool shuffle: false
        property string repeatMode: "off"
    }

    // Favorites persistence
    Settings {
        id: favoritesSettings
        category: "favorites"
        property string itemsJson: "[]"
    }

    Settings {
        id: overlaySettings
        category: "overlay"
        property string positionsJson: "{}"
        property bool hasCustomPosition: false
    }

    // Music video quality preference (used by YouTube extractor when picking a video stream URL).
    // 0 = auto, otherwise cap to that height.
    Settings {
        id: musicVideoSettings
        category: "video"
        property int musicVideoMaxHeight: 0
    }

    property int musicVideoMaxHeight: musicVideoSettings.musicVideoMaxHeight
    onMusicVideoMaxHeightChanged: {
        musicVideoSettings.musicVideoMaxHeight = musicVideoMaxHeight
        if (typeof YouTubePlayback !== "undefined" && YouTubePlayback.setPreferredVideoMaxHeight) {
            YouTubePlayback.setPreferredVideoMaxHeight(musicVideoMaxHeight)
        }
    }

    Connections {
        target: YouTubePlayback
        function onPlayUrlRequested(url, title, artist, thumbnailUrl, videoStreamUrl) {
            window._forceNextOpenAsAudio = true
            streamOverrideTitle = (title !== undefined && title !== null) ? String(title) : ""
            streamOverrideArtist = (artist !== undefined && artist !== null) ? String(artist) : ""
            if (thumbnailUrl !== undefined && thumbnailUrl !== null && String(thumbnailUrl) !== "")
                audioCoverArt = Qt.url(String(thumbnailUrl))
            if (musicVideoFeatureEnabled
                    && videoStreamUrl !== undefined && videoStreamUrl !== null && String(videoStreamUrl) !== "")
                audioVideoStreamUrl = Qt.url(String(videoStreamUrl))
            else
                audioVideoStreamUrl = ""
            window.currentImage = url
            Qt.callLater(function() { window.updateAccentColor() })
        }
        function onExtractFailed(reason) {
            lastPlayedYoutubeWatchUrl = ""
            streamOverrideTitle = ""
            streamOverrideArtist = ""
            audioVideoStreamUrl = ""
            console.warn("[YouTube]", reason)
            logToDebugConsole("[YouTube] " + reason, "error")
        }
    }

    function playFromUrl(urlString) {
        const u = (urlString || "").trim()
        if (u === "")
            return
        if (typeof YouTubePlayback === "undefined" || !YouTubePlayback.playFromUrl) {
            console.warn("[YouTube] YouTubePlayback not available")
            return
        }
        YouTubePlayback.playFromUrl(u)
    }

    function playYouTube(videoUrl) {
        const u = (videoUrl || "").trim()
        if (u === "")
            return
        if (typeof YouTubePlayback === "undefined" || !YouTubePlayback.playYouTube) {
            console.warn("[YouTube] YouTubePlayback not available")
            return
        }
        lastPlayedYoutubeWatchUrl = u
        YouTubePlayback.playYouTube(u)
    }

    /** Play a row from favoriteItems (stored normalized key: https URL or local path). YouTube → yt-dlp; other http(s) → direct stream. */
    function playFavoriteEntry(normKey) {
        const k = (normKey || "").trim()
        if (!k)
            return
        if (k.indexOf("http://") === 0 || k.indexOf("https://") === 0) {
            if (/youtube\.com(\/watch|\/shorts|\/embed)|youtu\.be\//i.test(k)) {
                playYouTube(k)
            } else {
                playFromUrl(k)
            }
            return
        }
        const fileUrl = k.indexOf("/") === 0 ? ("file://" + k) : ("file:///" + k)
        currentImage = Qt.url(fileUrl)
    }

    function openYoutubeUrlDialog() {
        youtubePasteField.text = ""
        youtubeUrlDialog.open()
    }

    function _submitYoutubeUrlDialog() {
        const t = youtubePasteField.text.trim()
        if (!t)
            return
        youtubeUrlDialog.close()
        if (/youtube\.com(\/watch|\/shorts|\/embed)|youtu\.be\//i.test(t))
            playYouTube(t)
        else if (t.indexOf("http://") === 0 || t.indexOf("https://") === 0)
            playFromUrl(t)
        else
            playYouTube(t)
    }

    /** Set by YouTubePlayback before assigning a resolved stream URL so http(s) without extension still opens as audio */
    property bool _forceNextOpenAsAudio: false

    /** Last page URL passed to playYouTube(); used so ♥ saves the watch link, not the temporary googlevideo stream. */
    property string lastPlayedYoutubeWatchUrl: ""

    /** If available, a video-only stream URL for the current YouTube track. */
    property url audioVideoStreamUrl: ""

    /** Rate-limit auto re-fetch when the googlevideo stream dies (TLS/expiry/demux). */
    property int _lastYoutubeStreamRecoverMs: 0

    function restartYoutubeStreamFromPageUrl() {
        const u = (lastPlayedYoutubeWatchUrl || "").trim()
        if (!u || !/youtube\.com(\/watch|\/shorts|\/embed)|youtu\.be\//i.test(u))
            return
        const cur = currentImage ? currentImage.toString() : ""
        if (cur.indexOf("http://") !== 0 && cur.indexOf("https://") !== 0)
            return
        const now = Date.now()
        if (_lastYoutubeStreamRecoverMs > 0 && now - _lastYoutubeStreamRecoverMs < 40000)
            return
        _lastYoutubeStreamRecoverMs = now
        logToDebugConsole("[YouTube] Stream failed; fetching a fresh URL with yt-dlp…", "info")
        playYouTube(u)
    }

    property var favoriteItems: []
    property var overlayPositions: ({})
    function _overlayScreenKey(scr) {
        if (!scr) return "default"
        const n = scr.name ? scr.name.toString() : "screen"
        const g = scr.geometry
        if (!g || g.width === undefined || g.width <= 0)
            return n
        return n + "|" + g.x + "," + g.y + "," + g.width + "x" + g.height
    }
    function _loadOverlayPositions() {
        try {
            const raw = overlaySettings.positionsJson || "{}"
            const parsed = JSON.parse(raw)
            overlayPositions = parsed || ({})
        } catch (e) {
            overlayPositions = ({})
        }
    }
    function _saveOverlayPositions() {
        try {
            overlaySettings.positionsJson = JSON.stringify(overlayPositions || {})
            overlaySettings.hasCustomPosition = true
        } catch (e) {
        }
    }
    function _loadFavorites() {
        try {
            const raw = favoritesSettings.itemsJson || "[]"
            const arr = JSON.parse(raw)
            favoriteItems = (arr && arr.length) ? arr : []
        } catch (e) {
            favoriteItems = []
        }
    }
    function _saveFavorites() {
        try {
            favoritesSettings.itemsJson = JSON.stringify(favoriteItems || [])
        } catch (e) {
        }
    }
    function _favKey(url) { return _queueNorm(url) }
    function isFavorite(url) {
        const k = _favKey(url)
        if (!k) return false
        const arr = favoriteItems || []
        for (let i = 0; i < arr.length; i++) {
            if (arr[i] === k) return true
        }
        return false
    }
    function isCurrentFavorite() {
        const cur = currentImage ? currentImage.toString() : ""
        const yt = lastPlayedYoutubeWatchUrl || ""
        if (yt !== "" && cur.indexOf("googlevideo.com") >= 0)
            return isFavorite(yt)
        return isFavorite(currentImage)
    }
    function toggleFavorite(url) {
        const k = _favKey(url)
        if (!k) return
        const arr = (favoriteItems || []).slice()
        const idx = arr.indexOf(k)
        if (idx >= 0) arr.splice(idx, 1)
        else arr.unshift(k)
        favoriteItems = arr
        _saveFavorites()
    }
    function toggleFavoriteCurrent() {
        const cur = currentImage ? currentImage.toString() : ""
        const yt = lastPlayedYoutubeWatchUrl || ""
        if (yt !== "" && cur.indexOf("googlevideo.com") >= 0)
            toggleFavorite(yt)
        else
            toggleFavorite(currentImage)
    }
    
    property url audioCoverArt: ""
    /** yt-dlp metadata for network streams (googlevideo); used when player has no tags */
    property string streamOverrideTitle: ""
    property string streamOverrideArtist: ""
    property var audioFormatInfo: ({ sampleRate: 0, bitrate: 0 })
    property int lastAudioDuration: 0  // Track last duration to prevent infinite loops
    readonly property color fallbackAccent: "#121216"
    property color accentColor: fallbackAccent
    property color foregroundColor: "#f5f5f5"
    
    // Color extraction component
    ColorExtractor {
        id: colorExtractor
        target: window
        dynamicColoringEnabled: window.dynamicColoringEnabled
        windowsAccentColorEnabled: window.windowsAccentColorEnabled
        gradientBackgroundEnabled: window.gradientBackgroundEnabled
        currentImage: window.currentImage
        isAudio: window.isAudio
        audioCoverArt: window.audioCoverArt
        fallbackAccent: window.fallbackAccent
    }
    
    // Smooth transitions for dynamic accent color
    Behavior on accentColor { 
        ColorAnimation { 
            duration: 300
            easing.type: Easing.OutCubic 
        } 
    }
    Behavior on foregroundColor { ColorAnimation { duration: 300; easing.type: Easing.OutCubic } }
    
    property bool dynamicColoringEnabled: true
    property bool windowsAccentColorEnabled: false

    onWindowsAccentColorEnabledChanged: updateAccentColor()
    property bool betaAudioProcessingEnabled: true
    property bool gradientBackgroundEnabled: true
    property bool backdropBlurEnabled: false  // Blurred cover-art backdrop effect
    property bool ambientGradientEnabled: false  // Spotify-style ambient animated gradient
    property bool snowEffectEnabled: false  // Hybrid snow effect (shader + particles)
    property bool badAppleEffectEnabled: false  // Bad Apple!! shader renderer
    property bool undertaleFightEnabled: false  // Undertale fight easter egg
    property bool undertaleFightStartPending: false
    property bool imageInterpolationMode: true  // Image interpolation: true = smooth/antialiased, false = nearest neighbor
    property bool dynamicResolutionEnabled: true  // Dynamic resolution adjustment based on zoom level
    property bool matchMediaAspectRatio: false  // Match window aspect ratio to loaded media
    property bool autoHideTitleBar: false  // Auto-hide titlebar when not hovered (like Windows)
    property var paletteColors: []  // Array of colors for gradient background
    property bool lyricsTranslationEnabled: false  // Enable lyrics translation
    property string lyricsTranslationApiKey: ""  // RapidAPI key for translation
    property string lyricsTranslationTargetLanguage: "en"  // Target language code
    property string appLanguage: "en"  // Application interface language
    property bool discordRPCEnabled: true  // Enable Discord Rich Presence
    property string coverArtSource: "coverartarchive"  // "coverartarchive" or "lastfm"
    property string lastFMApiKey: ""  // Last.fm API key (optional)
    property bool debugConsoleEnabled: false  // Enable debug console (disabled by default)

    // Debounced queue persistence
    property bool _queueRestoring: false
    Timer {
        id: queuePersistTimer
        interval: 300
        repeat: false
        onTriggered: saveQueueState()
    }
    
    // Image source for backdrop blur (cover art for audio, currentImage for images)
    // For audio: prefer cover art, fallback to currentImage if cover art not available yet
    // For images: use currentImage directly
    readonly property url backdropImageSource: (isAudio && audioCoverArt && audioCoverArt !== "") 
                                                ? audioCoverArt 
                                                : (isAudio && currentImage && currentImage !== "")
                                                  ? currentImage  // Fallback to audio file itself if cover art not extracted yet
                                                  : (isImageType && currentImage && currentImage !== "") 
                                                    ? currentImage 
                                                    : ""
    
    onGradientBackgroundEnabledChanged: {
    }
    
    onPaletteColorsChanged: {
    }
    
    property real loadStartTime: 0
    property url pendingLoadSource: ""
    property string pendingLoadType: ""
    
    // Image navigation properties
    property var directoryImages: []
    property int currentImageIndex: 0
    property bool isImageType: !isVideo && !isAudio && !isMarkdown && !isText && !isPdf && !isZip && !isModel && currentImage.toString() !== ""
    property bool _navigatingImages: false  // Flag to prevent re-scanning during navigation
    property bool showImageControls: false  // Toggle for image controls visibility

    // Helper properties to get viewers from Loaders (returns null if not loaded)
    property var imageViewer: pageStack.mediaViewerLoaders.viewerLoader.item
    property var videoPlayer: pageStack.mediaViewerLoaders.videoPlayerLoader.item
    property var audioPlayer: pageStack.mediaViewerLoaders.audioPlayerLoader.item
    property var markdownViewer: pageStack.mediaViewerLoaders.markdownViewerLoader.item
    property var textViewer: pageStack.mediaViewerLoaders.textViewerLoader.item
    property var pdfViewer: pageStack.mediaViewerLoaders.pdfViewerLoader.item
    property var zipViewer: pageStack.mediaViewerLoaders.zipViewerLoader.item
    property var modelViewer: pageStack.mediaViewerLoaders.modelViewerLoader.item

    function adjustZoom(delta) {
        ViewManagementUtils.adjustZoom(delta, pageStack.mediaViewerLoaders.viewerLoader.item, currentImage !== "", isVideo, isAudio, isMarkdown, isText, isPdf, isZip, isModel)
    }
    
    // Image navigation functions
    function loadDirectoryImages(imageUrl) {
        if (!imageUrl || imageUrl === "" || typeof ColorUtils === "undefined" || !ColorUtils.getImagesInDirectory)
            return
        
        const result = ImageNavigationUtils.loadDirectoryImages(imageUrl, ColorUtils.getImagesInDirectory)
        directoryImages = result.directoryImages
        currentImageIndex = result.currentImageIndex
    }

    function loadDirectoryAudio(audioUrl) {
        if (!audioUrl || audioUrl === "" || typeof ColorUtils === "undefined" || !ColorUtils.getAudioFilesInDirectory)
            return
        
        const result = ImageNavigationUtils.loadDirectoryImages(audioUrl, ColorUtils.getAudioFilesInDirectory)
        directoryImages = result.directoryImages
        currentImageIndex = result.currentImageIndex
    }
    
    function navigateToImage(index) {
        if (directoryImages.length === 0) return
        
        const validIndex = ImageNavigationUtils.getValidImageIndex(index, directoryImages.length)
        currentImageIndex = validIndex
        _navigatingImages = true  // Prevent re-scanning directory
        currentImage = directoryImages[validIndex]
        _navigatingImages = false
    }
    
    function nextImage() {
        // For audio/video, Next should advance the queue first.
        if ((isAudio || isVideo) && (playbackQueue && playbackQueue.length > 0)) {
            playNextInQueue()
            return
        }
        // If queue shuffle is enabled and we have a browsable list, pick a random next item.
        // This makes shuffle work even when the explicit queue is empty.
        if ((isAudio || isVideo) && queueShuffle && directoryImages && directoryImages.length > 1) {
            let nextIndex = currentImageIndex
            let guard = 0
            while (nextIndex === currentImageIndex && guard < 12) {
                nextIndex = Math.floor(Math.random() * directoryImages.length)
                guard++
            }
            navigateToImage(nextIndex)
            return
        }
        const nextIndex = ImageNavigationUtils.getNextImageIndex(currentImageIndex, directoryImages.length)
        navigateToImage(nextIndex)
    }
    
    function previousImage() {
        // For audio/video, Previous should use playback history first.
        if ((isAudio || isVideo) && (playbackHistory && playbackHistory.length > 0)) {
            playPreviousInQueue()
            return
        }
        const prevIndex = ImageNavigationUtils.getPreviousImageIndex(currentImageIndex, directoryImages.length)
        navigateToImage(prevIndex)
    }

    function enqueueToQueue(url) {
        if (!url || url === "") return
        playbackQueue = playbackQueue.concat([url])
    }

    function enqueueManyToQueue(urls) {
        _enqueueMany(urls)
    }

    function enqueueNextInQueue(url) {
        if (!url || url === "") return
        playbackQueue = [url].concat(playbackQueue)
    }

    function removeFromQueue(index) {
        if (!playbackQueue || index < 0 || index >= playbackQueue.length) return
        const copy = playbackQueue.slice()
        copy.splice(index, 1)
        playbackQueue = copy
    }

    function clearQueue() {
        playbackQueue = []
        playbackHistory = []
    }

    function _queueNorm(url) {
        if (!url || url === "") return ""
        const s = url.toString()
        try {
            return decodeURIComponent(s.replace(/^file:\/\//, "")).replace(/\\/g, "/").toLowerCase()
        } catch (e) {
            return s.replace(/^file:\/\//, "").replace(/\\/g, "/").toLowerCase()
        }
    }

    function _queueContains(url) {
        const n = _queueNorm(url)
        if (!n) return true
        if (currentImage && _queueNorm(currentImage) === n) return true
        for (let i = 0; i < playbackQueue.length; i++) {
            if (_queueNorm(playbackQueue[i]) === n) return true
        }
        for (let i = 0; i < playbackHistory.length; i++) {
            if (_queueNorm(playbackHistory[i]) === n) return true
        }
        return false
    }

    function _enqueueMany(list) {
        if (!list || list.length === 0) return
        let added = false
        let q = playbackQueue.slice()
        for (let i = 0; i < list.length; i++) {
            const u = list[i]
            if (!u || u === "") continue
            if (_queueContains(u)) continue
            q.push(u)
            added = true
        }
        if (added) {
            playbackQueue = q
        }
    }

    // Queue builder helpers (audio-folder based)
    function queueAddFolderAll() {
        if (!isAudio) return
        if (!directoryImages || directoryImages.length === 0) return
        const list = []
        for (let i = 0; i < directoryImages.length; i++) {
            const u = directoryImages[i]
            if (_queueNorm(u) === _queueNorm(currentImage)) continue
            list.push(u)
        }
        _enqueueMany(list)
    }

    function queueAddFolderRemaining() {
        if (!isAudio) return
        if (!directoryImages || directoryImages.length === 0) return
        const start = Math.max(0, currentImageIndex + 1)
        const list = []
        for (let i = start; i < directoryImages.length; i++) {
            const u = directoryImages[i]
            if (_queueNorm(u) === _queueNorm(currentImage)) continue
            list.push(u)
        }
        _enqueueMany(list)
    }

    function shuffleQueueNow() {
        if (!playbackQueue || playbackQueue.length < 2) return
        const copy = playbackQueue.slice()
        for (let i = copy.length - 1; i > 0; --i) {
            const j = Math.floor(Math.random() * (i + 1))
            const t = copy[i]
            copy[i] = copy[j]
            copy[j] = t
        }
        playbackQueue = copy
    }

    function playNextInQueue() {
        if (queueRepeatMode === "one" && currentImage !== "") {
            // Restart current item (AudioPlayer/VideoPlayer handles actual replay)
            currentImage = currentImage
            return
        }

        if (!playbackQueue || playbackQueue.length === 0) {
            if (queueRepeatMode === "all" && playbackHistory && playbackHistory.length > 0) {
                playbackQueue = playbackHistory.slice()
                playbackHistory = []
            } else {
                return
            }
        }

        // Move current to history (so Previous works)
        if (currentImage && currentImage !== "") {
            playbackHistory = playbackHistory.concat([currentImage])
        }

        const idx = queueShuffle ? Math.floor(Math.random() * playbackQueue.length) : 0
        const nextUrl = playbackQueue[idx]
        const copy = playbackQueue.slice()
        copy.splice(idx, 1)
        playbackQueue = copy
        currentImage = nextUrl
    }

    function playPreviousInQueue() {
        if (!playbackHistory || playbackHistory.length === 0) {
            return
        }
        // Put current back to the front of the queue
        if (currentImage && currentImage !== "") {
            playbackQueue = [currentImage].concat(playbackQueue || [])
        }

        const prevUrl = playbackHistory[playbackHistory.length - 1]
        playbackHistory = playbackHistory.slice(0, playbackHistory.length - 1)
        currentImage = prevUrl
    }

    // Jump to a specific entry in the playback queue (used by the overlay "Up next" peek).
    function skipToQueueIndex(index) {
        if (!playbackQueue || playbackQueue.length === 0) return
        const i = Math.max(0, Math.min(index, playbackQueue.length - 1))

        // Move current to history (so Previous works)
        if (currentImage && currentImage !== "") {
            playbackHistory = playbackHistory.concat([currentImage])
        }

        const nextUrl = playbackQueue[i]
        const copy = playbackQueue.slice()
        copy.splice(i, 1)
        playbackQueue = copy
        currentImage = nextUrl
    }

    function onActiveMediaFinished() {
        // Called by players when playback naturally reaches the end.
        if (queueRepeatMode === "one") {
            // Replay is handled by re-setting currentImage (keeps behavior consistent across audio/video)
            currentImage = currentImage
            return
        }
        if (playbackQueue && playbackQueue.length > 0) {
            playNextInQueue()
            return
        }
        if (queueRepeatMode === "all" && playbackHistory && playbackHistory.length > 0) {
            playbackQueue = playbackHistory.slice()
            playbackHistory = []
            playNextInQueue()
        }
    }

    // Queue reorder helpers
    function moveQueueItem(fromIndex, toIndex) {
        if (!playbackQueue || playbackQueue.length === 0) return
        if (fromIndex < 0 || fromIndex >= playbackQueue.length) return
        if (toIndex < 0 || toIndex >= playbackQueue.length) return
        if (fromIndex === toIndex) return
        console.log("[Queue] moveQueueItem", fromIndex, "->", toIndex, "len", playbackQueue.length)
        const copy = playbackQueue.slice()
        const item = copy[fromIndex]
        copy.splice(fromIndex, 1)
        copy.splice(toIndex, 0, item)
        playbackQueue = copy
    }

    function queueMoveUp(index) {
        moveQueueItem(index, index - 1)
    }

    function queueMoveDown(index) {
        moveQueueItem(index, index + 1)
    }

    function resetView() {
        ViewManagementUtils.resetView(pageStack.mediaViewerLoaders.viewerLoader.item, isVideo, isAudio, isMarkdown, isText, isPdf, isZip, isModel)
    }
    
    function unloadMedia() {
        // Set flag to prevent onCurrentImageChanged from triggering load logic
        _isUnloading = true
        logToDebugConsole("[Unload] Unloading flag set", "info")
        
        // Use utility function for cleanup
        MediaUnloadUtils.unloadMedia({
            window: window,
            unloadAllViewers: unloadAllViewers,
            resetView: resetView,
            useFallbackAccent: useFallbackAccent,
            logToDebugConsole: logToDebugConsole,
            ColorUtils: (typeof ColorUtils !== "undefined" ? ColorUtils : null)
        })
        
        // Clear the unloading flag
        _isUnloading = false
        logToDebugConsole("[Unload] Unloading flag cleared, function returning", "info")
    }
    
    function loadFile(fileUrl) {
        ViewManagementUtils.loadFile(fileUrl, window)
    }

    function clampPan() {
        ViewManagementUtils.clampPan(pageStack.mediaViewerLoaders.viewerLoader.item, currentImage !== "", isVideo, isAudio, isMarkdown, isText, isPdf, isZip, isModel, window)
    }

    function saveQueueState() {
        if (_queueRestoring) return
        try {
            const obj = {
                playbackQueue: (playbackQueue || []).map(u => u ? u.toString() : ""),
                playbackHistory: (playbackHistory || []).map(u => u ? u.toString() : "")
            }
            queueSettings.stateJson = JSON.stringify(obj)
            queueSettings.shuffle = !!queueShuffle
            queueSettings.repeatMode = queueRepeatMode || "off"
        } catch (e) {
            // ignore
        }
    }

    function loadQueueState() {
        _queueRestoring = true
        try {
            queueShuffle = !!queueSettings.shuffle
            queueRepeatMode = queueSettings.repeatMode || "off"

            const raw = queueSettings.stateJson || ""
            if (!raw) {
                _queueRestoring = false
                return
            }
            const obj = JSON.parse(raw)
            const q = (obj && obj.playbackQueue) ? obj.playbackQueue : []
            const h = (obj && obj.playbackHistory) ? obj.playbackHistory : []
            playbackQueue = q.filter(s => s && s !== "").map(s => QUrl(s))
            playbackHistory = h.filter(s => s && s !== "").map(s => QUrl(s))
        } catch (e) {
            // ignore parse errors
        }
        _queueRestoring = false
    }

    onPlaybackQueueChanged: if (!_queueRestoring) queuePersistTimer.restart()
    onPlaybackHistoryChanged: if (!_queueRestoring) queuePersistTimer.restart()
    onQueueShuffleChanged: if (!_queueRestoring) queuePersistTimer.restart()
    onQueueRepeatModeChanged: if (!_queueRestoring) queuePersistTimer.restart()

    Component {
        id: musicOverlayWindowComponent
        Window {
            id: musicOverlayWin
            width: 420
            transientParent: null
            flags: Qt.Window | Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint
            color: "transparent"
            modality: Qt.NonModal
            visible: window.musicOverlayVisible
            Behavior on height { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

            property int _repositionTicks: 0
            property bool _allowSavedPosition: false
            property bool _dragActive: false
            property real _snapPreviewStrength: 0
            property int _snapPreviewCorner: -1
            property real _snapScreenGx: 0
            property real _snapScreenGy: 0
            /** Dev only: true shows top-left hint without dragging. */
            property bool snapPreviewForceVisibleTest: false
            /** Log snap-preview path (QML console). */
            readonly property bool _snapPreviewDebugLog: false
            property int _snapPreviewLogCounter: 0
            function _screenAtWindowCenter(winX, winY) {
                const cx = winX + musicOverlayWin.width * 0.5
                const cy = winY + musicOverlayWin.height * 0.5
                if (Qt.application && Qt.application.screens && Qt.application.screens.length > 0) {
                    for (let i = 0; i < Qt.application.screens.length; i++) {
                        const s = Qt.application.screens[i]
                        const g = s.geometry
                        if (g && cx >= g.x && cx < (g.x + g.width) && cy >= g.y && cy < (g.y + g.height))
                            return s
                    }
                }
                return musicOverlayWin.screen || window.screen || (Qt.application ? Qt.application.primaryScreen : null)
            }
            function _clampOverlayIntoScreen() {
                if (typeof MusicOverlayPositioning !== "undefined"
                        && MusicOverlayPositioning.clampOverlayToScreen) {
                    MusicOverlayPositioning.clampOverlayToScreen(musicOverlayWin)
                }
            }
            function _screenRect(winX, winY) {
                let scr = _screenAtWindowCenter(winX, winY)
                if (!scr)
                    return Qt.rect(0, 0, 1920, 1080)
                // Prefer full monitor geometry for legacy QML snap helpers; C++ overlay uses availableGeometry.
                let g = scr.geometry
                if (!g || g.width === undefined || g.width <= 0)
                    g = scr.availableGeometry
                if (!g || g.width === undefined || g.width <= 0)
                    g = scr.virtualGeometry
                if (!g || g.width === undefined || g.width <= 0)
                    return Qt.rect(0, 0, 1920, 1080)
                return Qt.rect(g.x, g.y, g.width, g.height)
            }
            function _saveCurrentPosition() {
                // Do not assign musicOverlayWin.screen here — setScreen() can recreate the window
                // and cause request/actual position oscillation during drag/save.
                const scr = _screenAtWindowCenter(musicOverlayWin.x, musicOverlayWin.y)
                const key = window._overlayScreenKey(scr || musicOverlayWin.screen || window.screen)
                const map = Object.assign({}, window.overlayPositions || {})
                map[key] = { x: Math.round(musicOverlayWin.x), y: Math.round(musicOverlayWin.y) }
                window.overlayPositions = map
                window._saveOverlayPositions()
                musicOverlayWin._allowSavedPosition = true
            }
            function snapToNearestCornerAndSave() {
                const scr = _screenAtWindowCenter(musicOverlayWin.x, musicOverlayWin.y)
                const g = _screenRect(musicOverlayWin.x, musicOverlayWin.y)
                const margin = 0
                const corners = [
                    { x: g.x + margin, y: g.y + margin },
                    { x: g.x + g.width - musicOverlayWin.width - margin, y: g.y + margin },
                    { x: g.x + margin, y: g.y + g.height - musicOverlayWin.height - margin },
                    { x: g.x + g.width - musicOverlayWin.width - margin, y: g.y + g.height - musicOverlayWin.height - margin }
                ]
                let best = corners[0]
                let bestD = Number.MAX_VALUE
                for (let i = 0; i < corners.length; i++) {
                    const c = corners[i]
                    const dx = musicOverlayWin.x - c.x
                    const dy = musicOverlayWin.y - c.y
                    const d2 = dx * dx + dy * dy
                    if (d2 < bestD) {
                        bestD = d2
                        best = c
                    }
                }
                // Soft-snap only when release is actually near a corner.
                // Prevents sudden jumps when user intends free placement.
                const snapDistance = 120
                if (Math.sqrt(bestD) <= snapDistance) {
                    musicOverlayWin.x = best.x
                    musicOverlayWin.y = best.y
                }
                // If not near a corner, keep the exact release position (no clamping).
                _saveCurrentPosition()
            }
            function applySavedOrDefaultPosition() {
                if (!musicOverlayWin._allowSavedPosition) {
                    repositionDefaultTopRight()
                    return
                }
                const scr = musicOverlayWin.screen || window.screen || (Qt.application ? Qt.application.primaryScreen : null)
                const key = window._overlayScreenKey(scr)
                const map = window.overlayPositions || ({})
                const saved = map[key]
                if (overlaySettings.hasCustomPosition && saved && saved.x !== undefined && saved.y !== undefined) {
                    musicOverlayWin.x = saved.x
                    musicOverlayWin.y = saved.y
                    _clampOverlayIntoScreen()
                    return
                }
                repositionDefaultTopRight()
            }
            function repositionDefaultTopRight() {
                if (typeof MusicOverlayPositioning !== "undefined"
                        && MusicOverlayPositioning.positionTopRight) {
                    MusicOverlayPositioning.positionTopRight(musicOverlayWin, window)
                    _clampOverlayIntoScreen()
                    return
                }
                let scr = window.screen
                if (!scr && musicOverlayWin.screen)
                    scr = musicOverlayWin.screen
                if (!scr && Qt.application && Qt.application.primaryScreen)
                    scr = Qt.application.primaryScreen
                if (!scr && Qt.application && Qt.application.screens && Qt.application.screens.length > 0)
                    scr = Qt.application.screens[0]
                if (!scr)
                    return
                let g = scr.availableGeometry
                if (!g || g.width === undefined || g.width <= 0)
                    g = scr.virtualGeometry
                if (!g || g.width === undefined || g.width <= 0)
                    g = scr.geometry
                if (!g || g.width === undefined || g.width <= 0)
                    return
                const margin = 12
                const ww = 420
                musicOverlayWin.x = g.x + g.width - ww - margin
                musicOverlayWin.y = g.y + margin
                _clampOverlayIntoScreen()
            }
            function clearOverlaySavedPositionForCurrentScreen() {
                const scr = musicOverlayWin.screen || window.screen || (Qt.application ? Qt.application.primaryScreen : null)
                const key = window._overlayScreenKey(scr)
                const map = Object.assign({}, window.overlayPositions || {})
                if (map[key] !== undefined) {
                    delete map[key]
                    window.overlayPositions = map
                    window._saveOverlayPositions()
                }
            }
            Timer {
                id: overlayRepositionTimer
                interval: 32
                repeat: true
                running: false
                onTriggered: {
                    if (musicOverlayWin._dragActive) {
                        musicOverlayWin._repositionTicks = 0
                        return
                    }
                    musicOverlayWin.applySavedOrDefaultPosition()
                    musicOverlayWin._repositionTicks--
                }
            }
            Timer {
                id: overlaySmoothTimer
                interval: 16
                repeat: true
                running: window.musicOverlayVisible
                onTriggered: {
                    if (typeof MusicOverlayPositioning !== "undefined"
                            && MusicOverlayPositioning.overlayDragTick) {
                        MusicOverlayPositioning.overlayDragTick(musicOverlayWin)
                    }
                    // Single source for snap hint while dragging (tracks lerp even if centroid is still).
                    if (musicOverlayWin._dragActive && typeof MusicOverlayPositioning !== "undefined"
                            && MusicOverlayPositioning.overlaySnapPreviewHint) {
                        const h = MusicOverlayPositioning.overlaySnapPreviewHint(musicOverlayWin)
                        musicOverlayWin._snapPreviewStrength = h.strength !== undefined ? h.strength : 0
                        musicOverlayWin._snapPreviewCorner = h.corner !== undefined ? h.corner : -1
                        if (h.screenGlobalX !== undefined)
                            musicOverlayWin._snapScreenGx = h.screenGlobalX
                        if (h.screenGlobalY !== undefined)
                            musicOverlayWin._snapScreenGy = h.screenGlobalY
                        if (musicOverlayWin._snapPreviewDebugLog) {
                            musicOverlayWin._snapPreviewLogCounter++
                            if ((musicOverlayWin._snapPreviewLogCounter % 90) === 1)
                                console.log("[snapPreview] hint", "corner=", h.corner, "str=", h.strength)
                        }
                    }
                }
            }
            Connections {
                target: MusicOverlayPositioning
                function onOverlayPositionSaveRequested() {
                    musicOverlayWin._saveCurrentPosition()
                }
            }
            onVisibleChanged: {
                if (musicOverlayWin._snapPreviewDebugLog)
                    console.log("[snapPreview] musicOverlayWin.visible=", visible,
                        "forceTest=", musicOverlayWin.snapPreviewForceVisibleTest,
                        "corner=", musicOverlayWin._snapPreviewCorner,
                        "strength=", musicOverlayWin._snapPreviewStrength)
                if (visible) {
                    _repositionTicks = 0
                    _allowSavedPosition = !!overlaySettings.hasCustomPosition
                    // Select the target screen once on open, based on saved/default coordinates.
                    let probeX = musicOverlayWin.x
                    let probeY = musicOverlayWin.y
                    if (_allowSavedPosition) {
                        const scr0 = musicOverlayWin.screen || window.screen || (Qt.application ? Qt.application.primaryScreen : null)
                        const key0 = window._overlayScreenKey(scr0)
                        const saved0 = (window.overlayPositions || ({}))[key0]
                        if (saved0 && saved0.x !== undefined && saved0.y !== undefined) {
                            probeX = saved0.x
                            probeY = saved0.y
                        }
                    }
                    const targetScreen = _screenAtWindowCenter(probeX, probeY)
                    if (targetScreen)
                        musicOverlayWin.screen = targetScreen
                    Qt.callLater(applySavedOrDefaultPosition)
                }
            }
            Component.onCompleted: {
                if (musicOverlayWin._snapPreviewDebugLog) {
                    console.log("[snapPreview] Window.Component.onCompleted",
                        "forceTest=", musicOverlayWin.snapPreviewForceVisibleTest,
                        "MusicOverlayPositioning=", typeof MusicOverlayPositioning,
                        "overlaySnapPreviewHint=", typeof MusicOverlayPositioning !== "undefined"
                            ? typeof MusicOverlayPositioning.overlaySnapPreviewHint : "n/a")
                }
                if (musicOverlayWin.snapPreviewForceVisibleTest) {
                    musicOverlayWin._snapPreviewCorner = 0
                    musicOverlayWin._snapPreviewStrength = 1
                    if (musicOverlayWin._snapPreviewDebugLog)
                        console.log("[snapPreview] force test applied corner=0 strength=1")
                }
            }
            // Intentionally no screen-change auto-reposition: it caused restore churn/jumps.
            // Size from window width + same height as Window binding — NOT musicOverlayWin.height (cycles root to 0×0).
            Item {
                id: musicOverlayRoot
                width: musicOverlayWin.width
                height: overlayContent.implicitHeight + 12
                Component.onCompleted: {
                    if (musicOverlayWin._snapPreviewDebugLog)
                        console.log("[snapPreview] musicOverlayRoot size", width, height,
                            "win size", musicOverlayWin.width, musicOverlayWin.height,
                            "implicitH=", overlayContent.implicitHeight)
                }

                // Drag pill using DragHandler (no OS drag).
                Rectangle {
                    id: overlayDragHandle
                    anchors.top: parent.top
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.topMargin: 6
                    width: 76
                    height: 10
                    radius: 5
                    color: overlayDragHandler.active
                           ? Qt.rgba(window.foregroundColor.r, window.foregroundColor.g, window.foregroundColor.b, 0.58)
                           : (dragHandleHover.hovered
                              ? Qt.rgba(window.foregroundColor.r, window.foregroundColor.g, window.foregroundColor.b, 0.45)
                              : Qt.rgba(window.foregroundColor.r, window.foregroundColor.g, window.foregroundColor.b, 0.30))
                    z: 5000

                    HoverHandler {
                        id: dragHandleHover
                        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                        cursorShape: overlayDragHandler.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                    }

                    DragHandler {
                        id: overlayDragHandler
                        target: null
                        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad

                        onActiveChanged: {
                            if (active) {
                                musicOverlayWin._dragActive = true
                                musicOverlayWin._repositionTicks = 0
                                if (typeof MusicOverlayPositioning !== "undefined"
                                        && MusicOverlayPositioning.overlayDragBegin) {
                                    MusicOverlayPositioning.overlayDragBegin(musicOverlayWin)
                                }
                                if (typeof MusicOverlayPositioning !== "undefined"
                                        && MusicOverlayPositioning.overlaySnapPreviewHint) {
                                    const h0 = MusicOverlayPositioning.overlaySnapPreviewHint(musicOverlayWin)
                                    musicOverlayWin._snapPreviewStrength = h0.strength !== undefined ? h0.strength : 0
                                    musicOverlayWin._snapPreviewCorner = h0.corner !== undefined ? h0.corner : -1
                                    if (h0.screenGlobalX !== undefined)
                                        musicOverlayWin._snapScreenGx = h0.screenGlobalX
                                    if (h0.screenGlobalY !== undefined)
                                        musicOverlayWin._snapScreenGy = h0.screenGlobalY
                                    if (musicOverlayWin._snapPreviewDebugLog)
                                        console.log("[snapPreview] drag begin hint",
                                            "corner=", musicOverlayWin._snapPreviewCorner,
                                            "strength=", musicOverlayWin._snapPreviewStrength)
                                }
                            } else {
                                if (typeof MusicOverlayPositioning !== "undefined"
                                        && MusicOverlayPositioning.overlayDragEnd) {
                                    MusicOverlayPositioning.overlayDragEnd(musicOverlayWin)
                                }
                                musicOverlayWin._dragActive = false
                                musicOverlayWin._snapPreviewStrength = 0
                                musicOverlayWin._snapPreviewCorner = -1
                                musicOverlayWin._snapScreenGx = 0
                                musicOverlayWin._snapScreenGy = 0
                            }
                        }

                        // Target from global cursor in C++; window follows via overlaySmoothTimer + lerp.
                        onCentroidChanged: {
                            if (!active)
                                return
                            if (typeof MusicOverlayPositioning !== "undefined"
                                    && MusicOverlayPositioning.overlayDragMove) {
                                MusicOverlayPositioning.overlayDragMove(musicOverlayWin)
                            }
                        }
                    }
                }

                MusicPlayerOverlay {
                    id: overlayContent
                    anchors.top: parent.top
                    anchors.left: parent.left
                    width: parent.width
                    accentColor: window.accentColor
                    foregroundColor: window.foregroundColor
                    overlayActive: window.musicOverlayVisible
                    lowQualityWhileDragging: musicOverlayWin._dragActive
                    appWindow: window
                    audioPlayer: window.audioPlayer
                    onClosed: window.musicOverlayVisible = false
                }
            }

            // Debug: compare requested (drag) vs actual window position — watch stderr when investigating jitter.
            readonly property bool _overlayMoveDebug: false
            onXChanged: {
                if (_overlayMoveDebug)
                    console.log("[overlay] actual x =", x)
            }
            onYChanged: {
                if (_overlayMoveDebug)
                    console.log("[overlay] actual y =", y)
            }
            onScreenChanged: {
                if (_overlayMoveDebug)
                    console.log("[overlay] screen =", screen ? screen.name : "null")
            }

            height: overlayContent.implicitHeight + 12
        }
    }

    Component {
        id: musicVideoOverlayWindowComponent
        Window {
            id: musicVideoOverlayWin
            width: 420
            transientParent: null
            flags: Qt.Window | Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint
            color: "transparent"
            modality: Qt.NonModal
            visible: window.musicVideoOverlayVisible
            Behavior on height { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

            property int _repositionTicks: 0
            property bool _allowSavedPosition: false
            property bool _dragActive: false

            Timer {
                id: videoOverlaySmoothTimer
                interval: 16
                repeat: true
                running: window.musicVideoOverlayVisible
                onTriggered: {
                    if (typeof MusicOverlayPositioning !== "undefined"
                            && MusicOverlayPositioning.overlayDragTick) {
                        MusicOverlayPositioning.overlayDragTick(musicVideoOverlayWin)
                    }
                }
            }

            function _screenAtWindowCenter(winX, winY) {
                const cx = winX + musicVideoOverlayWin.width * 0.5
                const cy = winY + musicVideoOverlayWin.height * 0.5
                if (Qt.application && Qt.application.screens && Qt.application.screens.length > 0) {
                    for (let i = 0; i < Qt.application.screens.length; i++) {
                        const s = Qt.application.screens[i]
                        const g = s.geometry
                        if (g && cx >= g.x && cx < (g.x + g.width) && cy >= g.y && cy < (g.y + g.height))
                            return s
                    }
                }
                return musicVideoOverlayWin.screen || window.screen || (Qt.application ? Qt.application.primaryScreen : null)
            }

            function _overlayKeyForScreen(scr) {
                return "video:" + window._overlayScreenKey(scr)
            }

            function _saveCurrentPosition() {
                const scr = _screenAtWindowCenter(musicVideoOverlayWin.x, musicVideoOverlayWin.y)
                const key = _overlayKeyForScreen(scr || musicVideoOverlayWin.screen || window.screen)
                const map = Object.assign({}, window.overlayPositions || {})
                map[key] = { x: Math.round(musicVideoOverlayWin.x), y: Math.round(musicVideoOverlayWin.y) }
                window.overlayPositions = map
                window._saveOverlayPositions()
                musicVideoOverlayWin._allowSavedPosition = true
            }

            function applySavedOrDefaultPosition() {
                if (!musicVideoOverlayWin._allowSavedPosition) {
                    repositionDefaultTopRight()
                    return
                }
                const scr = musicVideoOverlayWin.screen || window.screen || (Qt.application ? Qt.application.primaryScreen : null)
                const key = _overlayKeyForScreen(scr)
                const map = window.overlayPositions || ({})
                const saved = map[key]
                if (overlaySettings.hasCustomPosition && saved && saved.x !== undefined && saved.y !== undefined) {
                    musicVideoOverlayWin.x = saved.x
                    musicVideoOverlayWin.y = saved.y
                    return
                }
                repositionDefaultTopRight()
            }

            function repositionDefaultTopRight() {
                let scr = window.screen
                if (!scr && musicVideoOverlayWin.screen)
                    scr = musicVideoOverlayWin.screen
                if (!scr && Qt.application && Qt.application.primaryScreen)
                    scr = Qt.application.primaryScreen
                if (!scr && Qt.application && Qt.application.screens && Qt.application.screens.length > 0)
                    scr = Qt.application.screens[0]
                if (!scr)
                    return
                let g = scr.availableGeometry
                if (!g || g.width === undefined || g.width <= 0)
                    g = scr.virtualGeometry
                if (!g || g.width === undefined || g.width <= 0)
                    g = scr.geometry
                if (!g || g.width === undefined || g.width <= 0)
                    return
                const margin = 12
                const ww = 420
                musicVideoOverlayWin.x = g.x + g.width - ww - margin
                musicVideoOverlayWin.y = g.y + margin + 64
            }

            onVisibleChanged: {
                if (visible) {
                    _repositionTicks = 0
                    _allowSavedPosition = !!overlaySettings.hasCustomPosition
                    const probeX = musicVideoOverlayWin.x
                    const probeY = musicVideoOverlayWin.y
                    const targetScreen = _screenAtWindowCenter(probeX, probeY)
                    if (targetScreen)
                        musicVideoOverlayWin.screen = targetScreen
                    Qt.callLater(applySavedOrDefaultPosition)
                    Qt.callLater(function() {
                        musicVideoOverlayWin.raise()
                        musicVideoOverlayWin.requestActivate()
                    })
                }
            }

            Item {
                id: musicVideoOverlayRoot
                width: musicVideoOverlayWin.width
                height: overlayContent.implicitHeight + 12

                Rectangle {
                    id: overlayDragHandle2
                    anchors.top: parent.top
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.topMargin: 6
                    width: 76
                    height: 10
                    radius: 5
                    color: overlayDragHandler2.active
                           ? Qt.rgba(window.foregroundColor.r, window.foregroundColor.g, window.foregroundColor.b, 0.58)
                           : Qt.rgba(window.foregroundColor.r, window.foregroundColor.g, window.foregroundColor.b, 0.30)
                    z: 5000

                    HoverHandler {
                        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                        cursorShape: overlayDragHandler2.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                    }

                    DragHandler {
                        id: overlayDragHandler2
                        target: null
                        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                        onActiveChanged: {
                            musicVideoOverlayWin._dragActive = active
                            if (active) {
                                if (typeof MusicOverlayPositioning !== "undefined"
                                        && MusicOverlayPositioning.overlayDragBegin) {
                                    MusicOverlayPositioning.overlayDragBegin(musicVideoOverlayWin)
                                }
                            } else {
                                if (typeof MusicOverlayPositioning !== "undefined"
                                        && MusicOverlayPositioning.overlayDragEnd) {
                                    MusicOverlayPositioning.overlayDragEnd(musicVideoOverlayWin)
                                }
                                musicVideoOverlayWin._saveCurrentPosition()
                            }
                        }
                        onCentroidChanged: {
                            if (!active)
                                return
                            if (typeof MusicOverlayPositioning !== "undefined"
                                    && MusicOverlayPositioning.overlayDragMove) {
                                MusicOverlayPositioning.overlayDragMove(musicVideoOverlayWin)
                            }
                        }
                    }
                }

                MusicVideoOverlay {
                    id: overlayContent
                    anchors.top: parent.top
                    anchors.left: parent.left
                    width: parent.width
                    accentColor: window.accentColor
                    foregroundColor: window.foregroundColor
                    overlayActive: window.musicVideoOverlayVisible
                    appWindow: window
                    audioPlayer: window.audioPlayer
                    playAudio: true
                    // Prefer the page URL for yt-dlp pipe playback (avoids 403 on googlevideo URLs).
                    videoSource: (window.lastPlayedYoutubeWatchUrl && window.lastPlayedYoutubeWatchUrl !== "")
                        ? Qt.url(window.lastPlayedYoutubeWatchUrl)
                        : window.audioVideoStreamUrl
                    onClosed: window.musicVideoOverlayVisible = false
                }
            }

            height: overlayContent.implicitHeight + 12
        }
    }

    // Snap hint: separate Window so it can sit on the desktop past the overlay edge.
    // Loader = no extra QWindow while idle. Never raise() the overlay here — that breaks DragHandler on Windows.
    readonly property bool _musicSnapHintLoaderActive: musicOverlayWindowRef !== null
            && musicOverlayVisible
            && (musicOverlayWindowRef.snapPreviewForceVisibleTest
                || (musicOverlayWindowRef._dragActive && musicOverlayWindowRef._snapPreviewCorner >= 0))

    Loader {
        id: musicOverlaySnapHintLoader
        active: window._musicSnapHintLoaderActive
        sourceComponent: Component {
            Window {
                id: musicOverlaySnapHintWin
                // Ghost matches overlay window footprint; inner radius matches MusicPlayerOverlay mainMusicCard (35).
                readonly property var ol: window.musicOverlayWindowRef
                readonly property int cSnap: ol ? ol._snapPreviewCorner : -1
                readonly property real gxs: ol ? ol._snapScreenGx : 0
                readonly property real gys: ol ? ol._snapScreenGy : 0
                readonly property real pad: 16
                readonly property real ow: ol ? ol.width : 420
                readonly property real oh: ol ? ol.height : 400
                // musicOverlayRoot = mainMusicCard height + 12; card radius matches MusicPlayerOverlay.
                readonly property real cardW: Math.min(420, ow)
                readonly property real cardH: Math.max(1, oh - 12)
                readonly property real cardXInWin: (ow - cardW) * 0.5

                width: cardW
                height: cardH
                color: "transparent"
                modality: Qt.NonModal
                // No WindowStaysOnTopHint — overlay stays topmost; ghost sits underneath so the border does not cover the card.
                flags: Qt.Window | Qt.FramelessWindowHint | Qt.Tool | Qt.WindowTransparentForInput

                // Window snap top-left + horizontal inset (mainMusicCard is centered in the window).
                x: ((cSnap === 0 || cSnap === 2) ? (gxs + pad) : (gxs - ow + 1 - pad)) + cardXInWin
                y: (cSnap === 0 || cSnap === 1) ? (gys + pad) : (gys - oh + 1 - pad)
                visible: true
                opacity: ol && ol.snapPreviewForceVisibleTest ? 1
                         : ol ? Math.min(1, Math.max(0, ol._snapPreviewStrength)) : 0

                Rectangle {
                    anchors.fill: parent
                    radius: 35
                    antialiasing: true
                    color: Qt.rgba(0, 0, 0, 0.18 * Math.max(0.12,
                        musicOverlaySnapHintWin.ol ? musicOverlaySnapHintWin.ol._snapPreviewStrength : 0))
                    border.width: 3
                    border.color: Qt.rgba(window.foregroundColor.r, window.foregroundColor.g, window.foregroundColor.b, 0.95)
                }
            }
        }
    }

    Component.onCompleted: {
        // Restore queue once the window is ready
        loadQueueState()
        _loadOverlayPositions()
        _loadFavorites()

        // Apply persisted YouTube music video quality setting to extractor helper.
        if (typeof YouTubePlayback !== "undefined" && YouTubePlayback.setPreferredVideoMaxHeight) {
            YouTubePlayback.setPreferredVideoMaxHeight(musicVideoMaxHeight)
        }

        // Defer overlay window creation to improve startup time.
        // These windows aren't needed until the user enables the overlay.
        Qt.callLater(function() {
            musicOverlayWindowRef = musicOverlayWindowComponent.createObject(null)
            musicVideoOverlayWindowRef = musicVideoOverlayWindowComponent.createObject(null)
        })
    }

    // Drag & drop handling for multiple files
    property var _pendingDropUrls: []
    property string _pendingDropMode: "" // "audio-multi"

    function handleDroppedFiles(urls) {
        if (!urls || urls.length === 0) return
        if (urls.length === 1) {
            currentImage = urls[0]
            return
        }

        // If all dropped are audio, offer queue actions
        let allAudio = true
        for (let i = 0; i < urls.length; i++) {
            if (!checkIfAudio(urls[i])) {
                allAudio = false
                break
            }
        }
        if (allAudio) {
            _pendingDropUrls = urls
            _pendingDropMode = "audio-multi"
            dropQueuePopup.open()
            return
        }

        // Default behavior: open first
        currentImage = urls[0]
    }

    function _enqueueNextMany(list) {
        if (!list || list.length === 0) return
        // preserve order: first item should become next, de-dupe against current/queue/history
        const toAdd = []
        for (let i = 0; i < list.length; i++) {
            const u = list[i]
            if (!u || u === "") continue
            if (_queueContains(u)) continue
            toAdd.push(u)
        }
        if (toAdd.length > 0) {
            playbackQueue = toAdd.concat(playbackQueue || [])
        }
    }

    Popup {
        id: dropQueuePopup
        modal: true
        focus: true
        width: Math.min(520, window.width - 80)
        height: 180
        closePolicy: Popup.CloseOnPressOutside | Popup.CloseOnEscape
        x: Math.max(0, (window.width - width) / 2)
        y: Math.max(0, (window.height - height) / 2)

        background: Rectangle {
            radius: 20
            color: Qt.rgba(
                Qt.lighter(accentColor, 1.3).r,
                Qt.lighter(accentColor, 1.3).g,
                Qt.lighter(accentColor, 1.3).b,
                0.95
            )
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

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 20
            spacing: 14

            Text {
                Layout.fillWidth: true
                text: "Dropped " + (_pendingDropUrls ? _pendingDropUrls.length : 0) + " audio files"
                color: "#000000"
                font.pixelSize: 18
                font.weight: Font.Medium
                elide: Text.ElideRight
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Button {
                    text: "Play now"
                    onClicked: {
                        const list = _pendingDropUrls || []
                        if (list.length === 0) return
                        currentImage = list[0]
                        _enqueueMany(list.slice(1))
                        dropQueuePopup.close()
                    }
                }
                Button {
                    text: "Add to queue"
                    onClicked: {
                        const list = _pendingDropUrls || []
                        _enqueueMany(list)
                        dropQueuePopup.close()
                    }
                }
                Button {
                    text: "Add next"
                    onClicked: {
                        const list = _pendingDropUrls || []
                        _enqueueNextMany(list)
                        dropQueuePopup.close()
                    }
                }
                Item { Layout.fillWidth: true }
                Button { text: "Cancel"; onClicked: dropQueuePopup.close() }
            }
        }
    }

    function useFallbackAccent() {
        ColorManagementUtils.useFallbackAccent(colorExtractor)
    }

    function updateAccentColor() {
        ColorManagementUtils.updateAccentColor(colorExtractor)
    }

    // File type detection functions - now imported from FileTypeUtils.js
    function checkIfVideo(url) { return FileTypeUtils.checkIfVideo(url) }
    function checkIfGif(url) { return FileTypeUtils.checkIfGif(url) }
    function checkIfAudio(url) { return FileTypeUtils.checkIfAudio(url) }
    function checkIfMarkdown(url) { return FileTypeUtils.checkIfMarkdown(url) }
    function checkIfText(url) { return FileTypeUtils.checkIfText(url) }
    function checkIfPdf(url) { return FileTypeUtils.checkIfPdf(url) }
    function checkIfZip(url) { return FileTypeUtils.checkIfZip(url) }
    function checkIfModel(url) { return FileTypeUtils.checkIfModel(url) }
    
    // Format time function - now imported from MediaFormatUtils.js
    function formatTime(ms) { return MediaFormatUtils.formatTime(ms) }
    
    // Audio processing functions - now using AudioProcessingFunctions.js
    function extractAudioCoverArt() {
        // YouTube DASH URLs have no embedded art; extraction fails and would clear audioCoverArt.
        // MediaChangeHandlerUtils skips this when preserveStreamCoverArt is true, but onDurationAvailable
        // and MetadataPopupManager still call here — guard so the yt-dlp thumbnail is not wiped.
        const curStr = currentImage ? currentImage.toString() : ""
        if (lastPlayedYoutubeWatchUrl !== ""
            && curStr.indexOf("googlevideo.com") >= 0
            && audioCoverArt !== "") {
            return
        }
        AudioProcessingFunctions.extractAudioCoverArt({
            isAudio: isAudio,
            currentImage: currentImage,
            audioCoverArt: audioCoverArt,
            updateAccentColor: updateAccentColor,
            AudioUtils: AudioUtils,
            ColorUtils: (typeof ColorUtils !== "undefined" ? ColorUtils : null),
            Qt: Qt,
            onCoverArtExtracted: function(coverArtUrl) {
                if (!currentImage || currentImage === "")
                    return
                audioCoverArt = coverArtUrl
            }
        })
    }
    
    function getAudioFormatInfo(durationMs) {
        const formatInfo = AudioProcessingFunctions.getAudioFormatInfo({
            isAudio: isAudio,
            currentImage: currentImage,
            audioFormatInfo: audioFormatInfo,
            durationMs: durationMs,
            audioPlayerLoader: pageStack.mediaViewerLoaders.audioPlayerLoader,
            showingMetadata: showingMetadata,
            metadataPopup: metadataPopup,
            metadataPopupManager: metadataPopupManager,
            getMetadataList: getMetadataList,
            ColorUtils: (typeof ColorUtils !== "undefined" ? ColorUtils : null),
            AudioUtils: AudioUtils,
            Qt: Qt
        })
        audioFormatInfo = formatInfo
    }

    function logToDebugConsole(message, type) {
        DebugUtils.logToDebugConsole(message, type, debugConsole)
    }

    function startLoadTimer(typeLabel) {
        if (typeLabel === "Audio") {
            lastAudioDuration = 0
        }
        const timerData = DebugUtils.startLoadTimer(typeLabel, currentImage, logToDebugConsole, debugConsoleEnabled)
        loadStartTime = timerData.loadStartTime
        pendingLoadSource = timerData.pendingLoadSource
        pendingLoadType = timerData.pendingLoadType
    }

    function logLoadDuration(statusLabel, sourceUrl) {
        const timerData = {
            loadStartTime: loadStartTime,
            pendingLoadSource: pendingLoadSource,
            pendingLoadType: pendingLoadType
        }
        const updatedData = DebugUtils.logLoadDuration(statusLabel, sourceUrl, timerData, logToDebugConsole, debugConsoleEnabled)
        loadStartTime = updatedData.loadStartTime
        pendingLoadSource = updatedData.pendingLoadSource
        pendingLoadType = updatedData.pendingLoadType
    }

    // Flag to prevent loading when we're intentionally clearing
    property bool _isUnloading: false

    // Media loader/unloader functions - now using MediaLoaderFunctions.js
    property bool _loadingAudioPlayer: false  // Guard to prevent double-loading (used by MediaLoaderFunctions)
    property bool _loadingImageViewer: false
    property bool _loadingVideoPlayer: false
    
    function loadImageViewer() {
        MediaLoaderFunctions.loadImageViewer({
            mediaViewerLoaders: pageStack.mediaViewerLoaders,
            logToDebugConsole: logToDebugConsole,
            MediaLoaderUtils: MediaLoaderUtils
        })
    }
    
    function unloadImageViewer() {
        MediaLoaderFunctions.unloadImageViewer({
            mediaViewerLoaders: pageStack.mediaViewerLoaders,
            MediaLoaderUtils: MediaLoaderUtils
        })
    }
    
    function loadVideoPlayer() {
        MediaLoaderFunctions.loadVideoPlayer({
            mediaViewerLoaders: pageStack.mediaViewerLoaders,
            currentImage: currentImage,
            logToDebugConsole: logToDebugConsole,
            MediaLoaderUtils: MediaLoaderUtils
        })
    }
    
    function unloadVideoPlayer() {
        MediaLoaderFunctions.unloadVideoPlayer({
            mediaViewerLoaders: pageStack.mediaViewerLoaders,
            MediaLoaderUtils: MediaLoaderUtils
        })
    }
    
    function loadAudioPlayer() {
        MediaLoaderFunctions.loadAudioPlayer({
            mediaViewerLoaders: pageStack.mediaViewerLoaders,
            window: window,
            logToDebugConsole: logToDebugConsole,
            MediaLoaderUtils: MediaLoaderUtils,
            Qt: Qt
        })
    }
    
    function unloadAudioPlayer() {
        MediaLoaderFunctions.unloadAudioPlayer({
            mediaViewerLoaders: pageStack.mediaViewerLoaders,
            MediaLoaderUtils: MediaLoaderUtils
        })
    }
    
    function loadMarkdownViewer() {
        MediaLoaderFunctions.loadMarkdownViewer({
            mediaViewerLoaders: pageStack.mediaViewerLoaders,
            MediaLoaderUtils: MediaLoaderUtils
        })
    }
    
    function unloadMarkdownViewer() {
        MediaLoaderFunctions.unloadMarkdownViewer({
            mediaViewerLoaders: pageStack.mediaViewerLoaders,
            MediaLoaderUtils: MediaLoaderUtils
        })
    }
    
    function loadTextViewer() {
        MediaLoaderFunctions.loadTextViewer({
            mediaViewerLoaders: pageStack.mediaViewerLoaders,
            MediaLoaderUtils: MediaLoaderUtils
        })
    }
    
    function unloadTextViewer() {
        MediaLoaderFunctions.unloadTextViewer({
            mediaViewerLoaders: pageStack.mediaViewerLoaders,
            MediaLoaderUtils: MediaLoaderUtils
        })
    }
    
    function loadPdfViewer() {
        MediaLoaderFunctions.loadPdfViewer({
            mediaViewerLoaders: pageStack.mediaViewerLoaders,
            MediaLoaderUtils: MediaLoaderUtils
        })
    }

    function loadZipViewer() {
        MediaLoaderFunctions.loadZipViewer({
            mediaViewerLoaders: pageStack.mediaViewerLoaders,
            MediaLoaderUtils: MediaLoaderUtils
        })
    }

    function loadModelViewer() {
        MediaLoaderFunctions.loadModelViewer({
            mediaViewerLoaders: pageStack.mediaViewerLoaders,
            MediaLoaderUtils: MediaLoaderUtils
        })
    }
    
    function unloadPdfViewer() {
        MediaLoaderFunctions.unloadPdfViewer({
            mediaViewerLoaders: pageStack.mediaViewerLoaders,
            MediaLoaderUtils: MediaLoaderUtils
        })
    }

    function unloadZipViewer() {
        MediaLoaderFunctions.unloadZipViewer({
            mediaViewerLoaders: pageStack.mediaViewerLoaders,
            MediaLoaderUtils: MediaLoaderUtils
        })
    }

    function unloadModelViewer() {
        MediaLoaderFunctions.unloadModelViewer({
            mediaViewerLoaders: pageStack.mediaViewerLoaders,
            MediaLoaderUtils: MediaLoaderUtils
        })
    }
    
    function unloadAllViewers() {
        MediaLoaderFunctions.unloadAllViewers({
            mediaViewerLoaders: pageStack.mediaViewerLoaders,
            MediaLoaderUtils: MediaLoaderUtils
        })
    }

    onCurrentImageChanged: {
        const forceNetworkAudio = _forceNextOpenAsAudio
        _forceNextOpenAsAudio = false
        {
            const s = currentImage ? currentImage.toString() : ""
            if (s.indexOf("file:") === 0 || s.indexOf("qrc:") === 0) {
                lastPlayedYoutubeWatchUrl = ""
                streamOverrideTitle = ""
                streamOverrideArtist = ""
                audioVideoStreamUrl = ""
            } else if (s !== "" && s.indexOf("googlevideo.com") < 0 && s.indexOf("http://") !== 0 && s.indexOf("https://") !== 0) {
                lastPlayedYoutubeWatchUrl = ""
                streamOverrideTitle = ""
                streamOverrideArtist = ""
                audioVideoStreamUrl = ""
            }
        }
        logToDebugConsole("[MediaChange] onCurrentImageChanged triggered, currentImage: " + currentImage, "info")
        logToDebugConsole("[MediaChange] isVideo: " + isVideo + ", isAudio: " + isAudio + ", isGif: " + isGif, "info")
        const curStr = currentImage ? currentImage.toString() : ""
        const preserveStreamCoverArt = lastPlayedYoutubeWatchUrl !== ""
            && curStr.indexOf("googlevideo.com") >= 0
            && audioCoverArt !== ""

        const result = MediaChangeHandlerUtils.handleCurrentImageChanged({
            currentImage: currentImage,
            _isUnloading: _isUnloading,
            matchMediaAspectRatio: matchMediaAspectRatio,
            _navigatingImages: _navigatingImages,
            mediaViewerLoaders: pageStack.mediaViewerLoaders,
            MediaLoaderUtils: MediaLoaderUtils,
            MediaPlayer: MediaPlayer,
            Qt: Qt,
            checkIfVideo: checkIfVideo,
            checkIfGif: checkIfGif,
            checkIfAudio: checkIfAudio,
            checkIfMarkdown: checkIfMarkdown,
            checkIfText: checkIfText,
            checkIfPdf: checkIfPdf,
            checkIfZip: checkIfZip,
            checkIfModel: checkIfModel,
            resetView: resetView,
            restoreDefaultWindowSize: restoreDefaultWindowSize,
            loadVideoPlayer: loadVideoPlayer,
            loadAudioPlayer: loadAudioPlayer,
            loadMarkdownViewer: loadMarkdownViewer,
            loadTextViewer: loadTextViewer,
            loadPdfViewer: loadPdfViewer,
            loadZipViewer: loadZipViewer,
            loadModelViewer: loadModelViewer,
            loadImageViewer: loadImageViewer,
            unloadImageViewer: unloadImageViewer,
            unloadVideoPlayer: unloadVideoPlayer,
            unloadAudioPlayer: unloadAudioPlayer,
            unloadMarkdownViewer: unloadMarkdownViewer,
            unloadTextViewer: unloadTextViewer,
            unloadPdfViewer: unloadPdfViewer,
            unloadZipViewer: unloadZipViewer,
            unloadModelViewer: unloadModelViewer,
            useFallbackAccent: useFallbackAccent,
            startLoadTimer: startLoadTimer,
            loadDirectoryImages: loadDirectoryImages,
            loadDirectoryAudio: loadDirectoryAudio,
            extractAudioCoverArt: extractAudioCoverArt,
            getAudioFormatInfo: getAudioFormatInfo,
            logToDebugConsole: logToDebugConsole,
            forceNetworkAudio: forceNetworkAudio,
            preserveStreamCoverArt: preserveStreamCoverArt
        })
        
        // Apply property changes
        if (result.propertiesToSet._isUnloading !== undefined) {
            _isUnloading = result.propertiesToSet._isUnloading
        }
        if (result.propertiesToSet.isVideo !== undefined) {
            isVideo = result.propertiesToSet.isVideo
        }
        if (result.propertiesToSet.isGif !== undefined) {
            isGif = result.propertiesToSet.isGif
        }
        if (result.propertiesToSet.isAudio !== undefined) {
            isAudio = result.propertiesToSet.isAudio
        }
        if (result.propertiesToSet.isMarkdown !== undefined) {
            isMarkdown = result.propertiesToSet.isMarkdown
        }
        if (result.propertiesToSet.isText !== undefined) {
            isText = result.propertiesToSet.isText
        }
        if (result.propertiesToSet.isPdf !== undefined) {
            isPdf = result.propertiesToSet.isPdf
        }
        if (result.propertiesToSet.isZip !== undefined) {
            isZip = result.propertiesToSet.isZip
        }
        if (result.propertiesToSet.isModel !== undefined) {
            isModel = result.propertiesToSet.isModel
        }
        if (result.propertiesToSet.showImageControls !== undefined) {
            showImageControls = result.propertiesToSet.showImageControls
        }
        if (result.propertiesToSet.videoHasNoAudio !== undefined) {
            videoHasNoAudio = result.propertiesToSet.videoHasNoAudio
        }
        if (result.propertiesToSet.videoPlayerLoaderActive !== undefined) {
            pageStack.mediaViewerLoaders.videoPlayerLoader.active = result.propertiesToSet.videoPlayerLoaderActive
        }
        if (result.propertiesToSet.audioCoverArt !== undefined) {
            audioCoverArt = result.propertiesToSet.audioCoverArt
        }
        if (result.propertiesToSet.audioFormatInfo !== undefined) {
            audioFormatInfo = result.propertiesToSet.audioFormatInfo
        }
        
        // Execute actions
        logToDebugConsole("[MediaChange] Executing " + result.actionsToPerform.length + " actions", "info")
        for (let i = 0; i < result.actionsToPerform.length; i++) {
            try {
                result.actionsToPerform[i]()
                logToDebugConsole("[MediaChange] Action " + i + " executed successfully", "info")
            } catch (e) {
                logToDebugConsole("[MediaChange] Error executing action " + i + ": " + e.toString(), "error")
            }
        }
        
        // Return early if needed
        if (result.shouldReturn) {
            return
        }
    }

    // Placeholders matching MainVisuals.qml until async shell content is ready
    QtObject {
        id: nullLoader
        property var item: null
        property bool active: false
    }
    QtObject {
        id: nullTimer
        function restart() {}
    }
    QtObject {
        id: nullImageControls
        property bool thumbnailPopupVisible: false
        function hideThumbnailPopup() {}
    }
    QtObject {
        id: nullMediaViewerLoaders
        property var viewerLoader: nullLoader
        property var videoPlayerLoader: nullLoader
        property var audioPlayerLoader: nullLoader
        property var markdownViewerLoader: nullLoader
        property var textViewerLoader: nullLoader
        property var pdfViewerLoader: nullLoader
        property var zipViewerLoader: nullLoader
        property var modelViewerLoader: nullLoader
        property var imageControlsHideTimer: nullTimer
        property var imageControls: nullImageControls
    }
    QtObject {
        id: nullPageStack
        property var mediaViewerLoaders: nullMediaViewerLoaders
        property var audioPlayer: null
        property var imageViewer: null
        property var videoPlayer: null
        property var markdownViewer: null
        property var textViewer: null
        property var pdfViewer: null
        property var zipViewer: null
        property var modelViewer: null
    }

    // Window resize timers component
    WindowResizeTimers {
        id: resizeTimers
        window: window
        matchMediaAspectRatio: window.matchMediaAspectRatio
        currentImage: window.currentImage
        isVideo: window.isVideo
        videoPlayerLoader: pageStack.mediaViewerLoaders.videoPlayerLoader
    }

    // Loader sourceComponent runs in a JS scope where bare `window` is the browser global, not this id.
    QtObject {
        id: shellWindowRef
        readonly property ApplicationWindow target: window
    }

    Loader {
        id: visualsLoader
        anchors.fill: parent
        asynchronous: true
        active: false  // Defer loading to improve startup time
        sourceComponent: MainVisuals {
            shellResizeTimers: resizeTimers
            appWindow: shellWindowRef.target
        }

        // Enable after initial frame render for perceived faster startup
        Timer {
            id: enableVisualsTimer
            interval: 1  // 1ms - next event loop iteration
            onTriggered: visualsLoader.active = true
        }

        Component.onCompleted: enableVisualsTimer.start()
    }

    property var pageStack: visualsLoader.item ? visualsLoader.item.pageStack : nullPageStack
    property var metadataPopup: visualsLoader.item ? visualsLoader.item.metadataPopup : null
    property var openDialog: visualsLoader.item ? visualsLoader.item.openDialog : null
    property var undertaleFight: visualsLoader.item ? visualsLoader.item.undertaleFight : null

    QtObject {
        id: nullMetadataPopupManagerShell
        property var popup: null
        function updateMetadataList() {}
    }
    property var metadataPopupManager: visualsLoader.item ? visualsLoader.item.metadataPopupManager : nullMetadataPopupManagerShell
    property var listenTogetherBridge: visualsLoader.item ? visualsLoader.item.listenTogetherBridge : null

    function getMetadataList() {
        return MediaFormatUtils.getMetadataList({
            currentImage: window.currentImage,
            streamWatchUrl: window.lastPlayedYoutubeWatchUrl,
            streamOverrideTitle: window.streamOverrideTitle,
            streamOverrideArtist: window.streamOverrideArtist,
            isVideo: window.isVideo,
            isAudio: window.isAudio,
            isGif: window.isGif,
            isMarkdown: window.isMarkdown,
            isText: window.isText,
            isPdf: window.isPdf,
            isZip: window.isZip,
            isModel: window.isModel,
            zoomFactor: window.zoomFactor,
            videoPlayer: pageStack.mediaViewerLoaders.videoPlayerLoader.item,
            audioPlayer: pageStack.mediaViewerLoaders.audioPlayerLoader.item,
            imageViewer: pageStack.mediaViewerLoaders.viewerLoader.item,
            markdownViewer: pageStack.mediaViewerLoaders.markdownViewerLoader.item,
            textViewer: pageStack.mediaViewerLoaders.textViewerLoader.item,
            pdfViewer: pageStack.mediaViewerLoaders.pdfViewerLoader.item,
            zipViewer: pageStack.mediaViewerLoaders.zipViewerLoader.item,
            modelViewer: pageStack.mediaViewerLoaders.modelViewerLoader.item,
            audioFormatInfo: window.audioFormatInfo,
            ColorUtils: ColorUtils,
            qsTr: qsTr,
            MediaMetaData: MediaMetaData
        })
    }

    // Window resize functions - now using WindowResizeFunctions.js
    property bool isResizing: false  // Prevent infinite loops
    property int lastResizeWidth: 0
    property int lastResizeHeight: 0
    property int defaultWidth: 960
    property int defaultHeight: 720
    
    function restoreDefaultWindowSize() {
        WindowResizeFunctions.restoreDefaultWindowSize({
            window: window,
            isResizing: isResizing,
            defaultWidth: defaultWidth,
            defaultHeight: defaultHeight,
            lastResizeWidth: lastResizeWidth,
            lastResizeHeight: lastResizeHeight,
            logToDebugConsole: logToDebugConsole,
            Qt: Qt,
            Window: Window,
            onResizingChanged: function(value) {
                isResizing = value
            },
            onLastResizeChanged: function(width, height) {
                lastResizeWidth = width
                lastResizeHeight = height
            }
        })
    }
    
    function resizeToMediaAspectRatio() {
        WindowResizeFunctions.resizeToMediaAspectRatio({
            window: window,
            matchMediaAspectRatio: matchMediaAspectRatio,
            currentImage: currentImage,
            isResizing: isResizing,
            isVideo: isVideo,
            isImageType: isImageType,
            videoPlayerLoader: pageStack.mediaViewerLoaders.videoPlayerLoader,
            viewerLoader: pageStack.mediaViewerLoaders.viewerLoader,
            customTitleBar: visualsLoader.item ? visualsLoader.item._customTitleBar : null,
            lastResizeWidth: lastResizeWidth,
            lastResizeHeight: lastResizeHeight,
            logToDebugConsole: logToDebugConsole,
            Qt: Qt,
            Screen: Screen,
            Window: Window,
            WindowResizeUtils: WindowResizeUtils,
            onResizingChanged: function(value) {
                isResizing = value
            },
            onLastResizeChanged: function(width, height) {
                lastResizeWidth = width
                lastResizeHeight = height
            }
        })
    }

    // Track if window was hidden with media loaded
    property bool wasHiddenWithMedia: false

    // Handle close event - minimize to tray instead of closing
    onClosing: function(close) {
        const result = WindowLifecycleUtils.handleWindowClosing(window, isMainWindow, currentImage, unloadMedia)
        close.accepted = result.accepted
        
        if (result.wasHiddenWithMedia !== undefined) {
            wasHiddenWithMedia = result.wasHiddenWithMedia
        }
        
        if (result.unloadBeforeHide) {
            unloadMedia()
        }
        
        if (result.hideWindow) {
            window.visible = false
            window.hide()
        }
            
        if (result.unloadAfterHide) {
            unloadMedia()
        }
    }
    
    onVisibleChanged: {
        wasHiddenWithMedia = WindowLifecycleUtils.handleWindowVisibleChanged(visible, wasHiddenWithMedia, unloadMedia)
    }
    
    // Track visibility changes to update fullscreen/maximized state in WindowFrameHelper
    onVisibilityChanged: {
        const fh = visualsLoader.item ? visualsLoader.item._frameHelper : null
        if (fh) {
            const isFullscreen = (window.visibility === Window.FullScreen)
            const isMaximized = (window.visibility === Window.Maximized)
            fh.fullscreen = (isFullscreen || isMaximized)
        }
    }
    
    // When secondary window is about to be destroyed, ensure everything is cleaned up
    Component.onDestruction: {
        WindowLifecycleUtils.handleComponentDestruction(isMainWindow, window, unloadAllViewers)
    }

    // Function to reset window state for reuse (called by C++ before reusing)
    function resetForReuse() {
        WindowLifecycleUtils.resetForReuse(window, unloadAllViewers, logToDebugConsole)
    }
    
    // Function to start Bad Apple easter egg
    function startBadAppleEasterEgg() {
        // Close settings page
        showingSettings = false
        
        // Clear current media to show blank page with just animation
        currentImage = ""
        unloadMedia()
        
        // Enable Bad Apple effect
        badAppleEffectEnabled = true
        // Disable snow if it's enabled
        if (snowEffectEnabled) {
            snowEffectEnabled = false
        }
        
        const vg = visualsLoader.item ? visualsLoader.item.windowBg : null
        if (vg && typeof vg.startBadAppleEasterEgg === "function") {
            vg.startBadAppleEasterEgg()
        }
        logToDebugConsole("[BadApple] Easter egg activated!", "info")
    }
    
    // Function to stop Bad Apple easter egg
    function stopBadAppleEasterEgg() {
        const vg = visualsLoader.item ? visualsLoader.item.windowBg : null
        if (vg && vg.badAppleEffect && typeof vg.badAppleEffect.stopPlayback === "function") {
            vg.badAppleEffect.stopPlayback()
        }
        // Disable Bad Apple effect
        badAppleEffectEnabled = false
        logToDebugConsole("[BadApple] Easter egg stopped!", "info")
    }
    
    // Function to start Undertale fight easter egg
    function startUndertaleFight() {
        // Close settings page
        showingSettings = false
        
        // Clear current media to show blank page
        currentImage = ""
        unloadMedia()
        
        // Enable Undertale fight
        undertaleFightStartPending = true
        undertaleFightEnabled = true
        
        // Start the fight after lazy loader instantiates the component.
        let tries = 0
        function tryStartFight() {
            if (undertaleFight && typeof undertaleFight.startFight === "function") {
                undertaleFight.startFight()
                undertaleFightStartPending = false
                return
            }
            if (tries < 30) {
                tries++
                Qt.callLater(tryStartFight)
            }
        }
        Qt.callLater(tryStartFight)
        logToDebugConsole("[UndertaleFight] Easter egg activated!", "info")
    }
    
    // Function to stop Undertale fight easter egg
    function stopUndertaleFight() {
        // Stop the fight
        if (undertaleFight && typeof undertaleFight.stopFight === "function") {
            undertaleFight.stopFight()
        }
        undertaleFightStartPending = false
        // Disable Undertale fight
        undertaleFightEnabled = false
        logToDebugConsole("[UndertaleFight] Easter egg stopped!", "info")
    }

    Dialog {
        id: youtubeUrlDialog
        title: qsTr("YouTube / stream")
        modal: true
        x: Math.round((window.width - width) / 2)
        y: Math.round((window.height - height) / 2)
        width: Math.min(480, window.width - 48)
        standardButtons: Dialog.NoButton

        ColumnLayout {
            width: parent.width
            spacing: 12

            Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: qsTr("Paste a YouTube watch, Shorts, or youtu.be link (uses yt-dlp; must be on PATH). Other https links are played as direct streams.")
            }
            TextField {
                id: youtubePasteField
                Layout.fillWidth: true
                placeholderText: qsTr("https://…")
                selectByMouse: true
                onAccepted: window._submitYoutubeUrlDialog()
            }
            RowLayout {
                Layout.alignment: Qt.AlignRight
                spacing: 8
                Button {
                    text: qsTr("Cancel")
                    onClicked: youtubeUrlDialog.close()
                }
                Button {
                    text: qsTr("Play")
                    highlighted: true
                    onClicked: window._submitYoutubeUrlDialog()
                }
            }
        }
    }

    // Keep on shell so initialImage / image cache run before async visuals finish loading
    WindowInitializationManager {
        mainWindow: window
        initialImage: initialImage
        logToDebugConsole: logToDebugConsole
        updateAccentColor: updateAccentColor
        windowLifecycleUtils: WindowLifecycleUtils
    }
}


