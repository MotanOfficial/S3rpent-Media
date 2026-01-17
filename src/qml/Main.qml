import QtMultimedia
import QtQuick
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
    title: qsTr("s3rp3nt media · Media Viewer")
    flags: Qt.Window | Qt.FramelessWindowHint
    color: "#000000"  // Black background to prevent white border in maximized/fullscreen (was Qt.transparent for DWM)
    background: WindowBackground {
        accentColor: window.accentColor
        dynamicColoringEnabled: window.dynamicColoringEnabled
        gradientBackgroundEnabled: window.gradientBackgroundEnabled
        backdropBlurEnabled: window.backdropBlurEnabled
        ambientGradientEnabled: window.ambientGradientEnabled
        snowEffectEnabled: window.snowEffectEnabled
        badAppleEffectEnabled: window.badAppleEffectEnabled
        backdropImageSource: window.backdropImageSource
        paletteColors: window.paletteColors
        audioPlayer: window.audioPlayer  // Pass audio player to WindowBackground
    }

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
    property real zoomFactor: 1.0
    property real panX: 0
    property real panY: 0
    property bool dropActive: false
    property bool showingSettings: false
    property bool showingMetadata: false
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
        property alias imageInterpolationMode: window.imageInterpolationMode
        property alias dynamicResolutionEnabled: window.dynamicResolutionEnabled
        property alias matchMediaAspectRatio: window.matchMediaAspectRatio
        property alias autoHideTitleBar: window.autoHideTitleBar
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
    
    property url audioCoverArt: ""
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
    property bool betaAudioProcessingEnabled: true
    property bool gradientBackgroundEnabled: true
    property bool backdropBlurEnabled: false  // Blurred cover-art backdrop effect
    property bool ambientGradientEnabled: false  // Spotify-style ambient animated gradient
    property bool snowEffectEnabled: false  // Hybrid snow effect (shader + particles)
    property bool badAppleEffectEnabled: false  // Bad Apple!! shader renderer
    property bool undertaleFightEnabled: false  // Undertale fight easter egg
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
    property bool isImageType: !isVideo && !isAudio && !isMarkdown && !isText && !isPdf && currentImage.toString() !== ""
    property bool _navigatingImages: false  // Flag to prevent re-scanning during navigation
    property bool showImageControls: false  // Toggle for image controls visibility

    // Helper properties to get viewers from Loaders (returns null if not loaded)
    property var imageViewer: pageStack.mediaViewerLoaders.viewerLoader.item
    property var videoPlayer: pageStack.mediaViewerLoaders.videoPlayerLoader.item
    property var audioPlayer: pageStack.mediaViewerLoaders.audioPlayerLoader.item
    property var markdownViewer: pageStack.mediaViewerLoaders.markdownViewerLoader.item
    property var textViewer: pageStack.mediaViewerLoaders.textViewerLoader.item
    property var pdfViewer: pageStack.mediaViewerLoaders.pdfViewerLoader.item

    function adjustZoom(delta) {
        ViewManagementUtils.adjustZoom(delta, pageStack.mediaViewerLoaders.viewerLoader.item, currentImage !== "", isVideo, isAudio, isMarkdown, isText, isPdf)
    }
    
    // Image navigation functions
    function loadDirectoryImages(imageUrl) {
        if (!imageUrl || imageUrl === "" || typeof ColorUtils === "undefined" || !ColorUtils.getImagesInDirectory)
            return
        
        const result = ImageNavigationUtils.loadDirectoryImages(imageUrl, ColorUtils.getImagesInDirectory)
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
        const nextIndex = ImageNavigationUtils.getNextImageIndex(currentImageIndex, directoryImages.length)
        navigateToImage(nextIndex)
    }
    
    function previousImage() {
        const prevIndex = ImageNavigationUtils.getPreviousImageIndex(currentImageIndex, directoryImages.length)
        navigateToImage(prevIndex)
    }

    function resetView() {
        ViewManagementUtils.resetView(pageStack.mediaViewerLoaders.viewerLoader.item, isVideo, isAudio, isMarkdown, isText, isPdf)
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
        ViewManagementUtils.clampPan(pageStack.mediaViewerLoaders.viewerLoader.item, currentImage !== "", isVideo, isAudio, isMarkdown, isText, isPdf, window)
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
    
    // Format time function - now imported from MediaFormatUtils.js
    function formatTime(ms) { return MediaFormatUtils.formatTime(ms) }
    
    // Audio processing functions - now using AudioProcessingFunctions.js
    function extractAudioCoverArt() {
        AudioProcessingFunctions.extractAudioCoverArt({
            isAudio: isAudio,
            currentImage: currentImage,
            audioCoverArt: audioCoverArt,
            updateAccentColor: updateAccentColor,
            AudioUtils: AudioUtils,
            ColorUtils: (typeof ColorUtils !== "undefined" ? ColorUtils : null),
            Qt: Qt,
            onCoverArtExtracted: function(coverArtUrl) {
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
        const timerData = DebugUtils.startLoadTimer(typeLabel, currentImage)
        loadStartTime = timerData.loadStartTime
        pendingLoadSource = timerData.pendingLoadSource
        pendingLoadType = timerData.pendingLoadType
        if (timerData.message) {
            logToDebugConsole(timerData.message, "info")
        }
    }

    function logLoadDuration(statusLabel, sourceUrl) {
        const timerData = {
            loadStartTime: loadStartTime,
            pendingLoadSource: pendingLoadSource,
            pendingLoadType: pendingLoadType
        }
        const updatedData = DebugUtils.logLoadDuration(statusLabel, sourceUrl, timerData, logToDebugConsole)
        loadStartTime = updatedData.loadStartTime
        pendingLoadSource = updatedData.pendingLoadSource
        pendingLoadType = updatedData.pendingLoadType
    }

    // Flag to prevent loading when we're intentionally clearing
    property bool _isUnloading: false

    // Media loader/unloader functions - now using MediaLoaderFunctions.js
    property bool _loadingAudioPlayer: false  // Guard to prevent double-loading (used by MediaLoaderFunctions)
    
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
    
    function unloadPdfViewer() {
        MediaLoaderFunctions.unloadPdfViewer({
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
        logToDebugConsole("[MediaChange] onCurrentImageChanged triggered, currentImage: " + currentImage, "info")
        logToDebugConsole("[MediaChange] isVideo: " + isVideo + ", isAudio: " + isAudio + ", isGif: " + isGif, "info")
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
            resetView: resetView,
            restoreDefaultWindowSize: restoreDefaultWindowSize,
            loadVideoPlayer: loadVideoPlayer,
            loadAudioPlayer: loadAudioPlayer,
            loadMarkdownViewer: loadMarkdownViewer,
            loadTextViewer: loadTextViewer,
            loadPdfViewer: loadPdfViewer,
            loadImageViewer: loadImageViewer,
            unloadImageViewer: unloadImageViewer,
            unloadVideoPlayer: unloadVideoPlayer,
            unloadAudioPlayer: unloadAudioPlayer,
            unloadMarkdownViewer: unloadMarkdownViewer,
            unloadTextViewer: unloadTextViewer,
            unloadPdfViewer: unloadPdfViewer,
            useFallbackAccent: useFallbackAccent,
            startLoadTimer: startLoadTimer,
            loadDirectoryImages: loadDirectoryImages,
            extractAudioCoverArt: extractAudioCoverArt,
            getAudioFormatInfo: getAudioFormatInfo,
            logToDebugConsole: logToDebugConsole
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
    // Window resize timers component
    WindowResizeTimers {
        id: resizeTimers
        window: window
        matchMediaAspectRatio: window.matchMediaAspectRatio
        currentImage: window.currentImage
        isVideo: window.isVideo
        videoPlayerLoader: pageStack.mediaViewerLoaders.videoPlayerLoader
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
            customTitleBar: customTitleBar,
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

    header: TitleBar {
        id: customTitleBar
        windowTitle: window.title
        currentFilePath: window.currentImage
        accentColor: window.accentColor
        foregroundColor: window.foregroundColor
        hasMedia: window.currentImage !== ""
        window: window
        frameHelper: frameHelper  // Pass frameHelper reference for immediate updates
        autoHideEnabled: window.autoHideTitleBar
        
        // Update C++ button area width when QML button layout changes
        onRightControlsHitWidthChanged: {
            if (frameHelper) {
                frameHelper.buttonAreaWidth = rightControlsHitWidth
            }
        }
        
        Component.onCompleted: {
            if (frameHelper) {
                // Set initial button area width after layout is complete
                Qt.callLater(function() {
                    frameHelper.buttonAreaWidth = rightControlsHitWidth
                })
            }
        }
        
        onMetadataClicked: {
            // Don't open metadata if settings is open
            if (!window.showingSettings) {
                window.showingMetadata = !window.showingMetadata
            }
        }
        onSettingsClicked: {
            // Close metadata when opening settings
            if (window.showingSettings === false) {
                window.showingMetadata = false
            }
            window.showingSettings = !window.showingSettings
        }
        onMinimizeClicked: window.showMinimized()
        onMaximizeClicked: {
            // Use native Windows maximize/restore via WindowFrameHelper
            if (frameHelper) {
                frameHelper.toggleMaximize()
            } else {
                // Fallback to Qt's maximize if frameHelper not available
                            if (window.visibility === Window.Maximized)
                                window.showNormal()
                            else
                                window.showMaximized()
            }
                        }
        onCloseClicked: {
            // Always trigger close event - let onClosing handle the logic
            window.close()
        }
        // Note: windowMoveRequested removed - native dragging via WM_NCHITTEST in WindowFrameHelper
    }
    
    // WindowFrameHelper for frameless window support (Windows only)
    WindowFrameHelper {
        id: frameHelper
        titleBarHeight: customTitleBar.barHeight  // Use actual bar height, not layout height
        // NOTE: titleBarVisible is NOT bound here - it's updated via Connections block below
        // for immediate synchronous updates needed by the hit-test
        
        // Setup after window is fully created and visible
        Component.onCompleted: {
            // Initialize titleBarVisible from QML property
            titleBarVisible = customTitleBar.titleBarVisible
            
            if (Qt.platform.os === "windows") {
                // Use Qt.callLater to ensure window handle is ready
                Qt.callLater(function() {
                    frameHelper.setupFramelessWindow(window)
                })
            }
        }
    }
    
    // NOTE: titleBarVisible is updated directly in TitleBar.qml's onTitleBarVisibleChanged handler
    // This ensures immediate synchronous updates needed by the hit-test

    // Metadata popup manager
    MetadataPopupManager {
        id: metadataPopupManager
        mainWindow: window
        customTitleBar: customTitleBar
        pageStack: pageStack  // Pass the MainContentArea component
    }
    
    // Expose popup for external access
    property alias metadataPopup: metadataPopupManager.popup
    // Expose manager for external access (e.g., from MediaViewerLoaders to call updateMetadataList)
    property alias metadataPopupManager: metadataPopupManager
    
    // Metadata list function - now uses MediaFormatUtils.js
    function getMetadataList() {
        return MediaFormatUtils.getMetadataList({
            currentImage: window.currentImage,
            isVideo: window.isVideo,
            isAudio: window.isAudio,
            isGif: window.isGif,
            isMarkdown: window.isMarkdown,
            isText: window.isText,
            isPdf: window.isPdf,
            zoomFactor: window.zoomFactor,
            videoPlayer: pageStack.mediaViewerLoaders.videoPlayerLoader.item,
            audioPlayer: pageStack.mediaViewerLoaders.audioPlayerLoader.item,
            imageViewer: pageStack.mediaViewerLoaders.viewerLoader.item,
            markdownViewer: pageStack.mediaViewerLoaders.markdownViewerLoader.item,
            textViewer: pageStack.mediaViewerLoaders.textViewerLoader.item,
            pdfViewer: pageStack.mediaViewerLoaders.pdfViewerLoader.item,
            audioFormatInfo: window.audioFormatInfo,
            ColorUtils: ColorUtils,
            qsTr: qsTr,
            MediaMetaData: MediaMetaData
        })
    }

    // Main content area - StackLayout with media viewer and settings page
    MainContentArea {
        id: pageStack
        anchors.fill: parent
        appWindow: window
        resizeTimers: resizeTimers
        metadataPopup: metadataPopup
        openDialog: openDialog
    }
    
    // Undertale fight easter egg overlay
    UndertaleFight {
        id: undertaleFight
        enabled: window.undertaleFightEnabled
        appWindow: window
        titleBar: customTitleBar
        z: 2000000  // Above hotZone (which is 1000000) to block all input
    }
    
    // Global MouseArea to detect cursor position and drive titlebar hiding
    // This works because it's in the content area, below the titlebar
    // Windows drag has already ended when cursor reaches here, so no conflict with HTCAPTION
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton  // Don't intercept clicks
        z: -1  // Behind everything, just for position tracking
        
        onPositionChanged: (mouse) => {
            if (!window.autoHideTitleBar || !customTitleBar.autoHideEnabled)
                return
            
            // Only manage hide timer if titlebar is currently visible
            if (!customTitleBar.titleBarVisible)
                return
            
            // If cursor is below the titlebar + margin → start hide timer
            // This detects when cursor leaves the titlebar area
            const margin = 10
            if (mouse.y > customTitleBar.barHeight + margin) {
                if (!customTitleBar.hideTimer.running) {
                    console.log("[Main] Cursor below titlebar (y:", mouse.y, "), starting hide timer")
                    customTitleBar.hideTimer.restart()
                }
            } else {
                // Cursor is in or near titlebar area - stop hide timer
                if (customTitleBar.hideTimer.running) {
                    console.log("[Main] Cursor in titlebar area (y:", mouse.y, "), stopping hide timer")
                    customTitleBar.hideTimer.stop()
                }
            }
        }
    }

    // PERMANENT TOP-EDGE HOT ZONE - Global overlay above all content
    // This MUST be a sibling of MainContentArea, NOT inside header or titlebar
    // It's a floating overlay that never collapses and always receives pointer events
    // This is the Qt equivalent of Windows' WM_NCHITTEST for non-client area
    // 
    // IMPORTANT: Use MouseArea, NOT HoverHandler, because HoverHandler doesn't work
    // in transparent frameless windows. MouseArea forces Qt to enable mouse tracking.
    Item {
        id: topHotZone
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 30  // Larger hot zone for easier cursor detection (was 8px)
        z: 1000000  // Always on top of everything
        // CRITICAL: Hot zone must be disabled when titlebar is visible to prevent overlap deadlock
        // The hot zone should ONLY be active when the titlebar is hidden
        // Also disable when Undertale fight is active
        visible: window.autoHideTitleBar && !customTitleBar.titleBarVisible && !window.undertaleFightEnabled
        enabled: visible  // Must be enabled to receive events
        
        // CRITICAL: Drive C++ hotZoneActive property directly from QML visibility
        // This ensures the hit-test knows when the hot zone is active, avoiding sync issues
        onVisibleChanged: {
            console.log("[HotZone] Visibility changed to:", visible, "autoHideTitleBar:", window.autoHideTitleBar, "titleBarVisible:", customTitleBar ? customTitleBar.titleBarVisible : "null")
            if (frameHelper) {
                frameHelper.hotZoneActive = visible
            }
        }
        
        Component.onCompleted: {
            if (frameHelper) {
                frameHelper.hotZoneActive = visible
            }
        }
        
        onEnabledChanged: {
            console.log("[HotZone] Enabled changed to:", enabled)
        }
        
        // MouseArea to detect cursor in the top edge
        // IMPORTANT: Hot zone ONLY reveals the titlebar, never hides it
        // Hiding is handled by position detection in the global MouseArea below
        // Use explicit anchors to ensure full width coverage, including left edge
        MouseArea {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            hoverEnabled: true  // Forces Qt to enable mouse tracking at window level
            acceptedButtons: Qt.NoButton  // Don't intercept clicks
            propagateComposedEvents: false  // Don't propagate to items below
            
            onEntered: {
                console.log("[HotZone] Mouse entered at x:", mouseX, "y:", mouseY, "width:", width, "autoHideTitleBar:", window.autoHideTitleBar, "titleBarVisible:", customTitleBar ? customTitleBar.titleBarVisible : "null")
                if (!window.autoHideTitleBar || !customTitleBar)
                    return
                    
                console.log("[HotZone] reveal")
                customTitleBar.titleBarVisible = true
                customTitleBar.hideTimer.stop()
            }
            
            onExited: {
                console.log("[HotZone] Mouse exited")
            }
            // DO NOTHING on exited - let the titlebar's own hover handle hiding
        }
    }

    // File dialog manager - handles file selection dialog
    FileDialogManager {
        id: fileDialogManager
        mainWindow: window
        logToDebugConsole: logToDebugConsole
    }
    
    // Expose dialog for external access (e.g., AppShortcuts)
    property alias openDialog: fileDialogManager.dialog

    // Keyboard shortcuts - now using AppShortcuts.qml component
    AppShortcuts {
        window: window
        openDialog: openDialog
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
        if (frameHelper) {
            const isFullscreen = (window.visibility === Window.FullScreen)
            const isMaximized = (window.visibility === Window.Maximized)
            // Remove DWM frame extension for both fullscreen AND maximized to prevent white border
            frameHelper.fullscreen = (isFullscreen || isMaximized)
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
        
        // Start playback via WindowBackground
        if (window.background && typeof window.background.startBadAppleEasterEgg === "function") {
            window.background.startBadAppleEasterEgg()
        }
        logToDebugConsole("[BadApple] Easter egg activated!", "info")
    }
    
    // Function to stop Bad Apple easter egg
    function stopBadAppleEasterEgg() {
        // Stop playback via WindowBackground
        if (window.background && typeof window.background.badAppleEffect !== "undefined" && typeof window.background.badAppleEffect.stopPlayback === "function") {
            window.background.badAppleEffect.stopPlayback()
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
        undertaleFightEnabled = true
        
        // Start the fight (this will make it fullscreen)
        if (undertaleFight && typeof undertaleFight.startFight === "function") {
            undertaleFight.startFight()
        }
        logToDebugConsole("[UndertaleFight] Easter egg activated!", "info")
    }
    
    // Function to stop Undertale fight easter egg
    function stopUndertaleFight() {
        // Stop the fight
        if (undertaleFight && typeof undertaleFight.stopFight === "function") {
            undertaleFight.stopFight()
        }
        // Disable Undertale fight
        undertaleFightEnabled = false
        logToDebugConsole("[UndertaleFight] Easter egg stopped!", "info")
    }

    // Window initialization manager - handles Component.onCompleted logic
    WindowInitializationManager {
        mainWindow: window
        initialImage: initialImage
        logToDebugConsole: logToDebugConsole
        updateAccentColor: updateAccentColor
        windowLifecycleUtils: WindowLifecycleUtils
    }

    // Bass pulse manager - handles bass pulse window and window management
    BassPulseManager {
        mainWindow: window
        isAudio: window.isAudio
        audioPlayerLoader: pageStack.mediaViewerLoaders.audioPlayerLoader
        accentColor: window.accentColor
    }
}


