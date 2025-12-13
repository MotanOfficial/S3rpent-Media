import QtMultimedia
import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import QtCore

ApplicationWindow {
    id: window
    width: 960
    height: 720
    minimumWidth: 640
    minimumHeight: 480
    visible: true
    title: qsTr("s3rp3nt media · Media Viewer")
    flags: Qt.Window | Qt.CustomizeWindowHint | Qt.WindowMinimizeButtonHint
            | Qt.WindowMaximizeButtonHint | Qt.WindowCloseButtonHint
    background: WindowBackground {
        accentColor: window.accentColor
        dynamicColoringEnabled: window.dynamicColoringEnabled
        gradientBackgroundEnabled: window.gradientBackgroundEnabled
        backdropBlurEnabled: window.backdropBlurEnabled
        ambientGradientEnabled: window.ambientGradientEnabled
        snowEffectEnabled: window.snowEffectEnabled
        backdropImageSource: window.backdropImageSource
        paletteColors: window.paletteColors
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
    property var paletteColors: []  // Array of colors for gradient background
    
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
    property var imageViewer: viewerLoader.item
    property var videoPlayer: videoPlayerLoader.item
    property var audioPlayer: audioPlayerLoader.item
    property var markdownViewer: markdownViewerLoader.item
    property var textViewer: textViewerLoader.item
    property var pdfViewer: pdfViewerLoader.item

    function adjustZoom(delta) {
        if (currentImage === "" || isVideo || isAudio || isMarkdown || isText || isPdf)
            return;
        if (viewerLoader.item) {
            viewerLoader.item.adjustZoom(delta);
        }
    }
    
    // Image navigation functions
    function loadDirectoryImages(imageUrl) {
        if (!imageUrl || imageUrl === "" || typeof ColorUtils === "undefined" || !ColorUtils.getImagesInDirectory)
            return
        
        const images = ColorUtils.getImagesInDirectory(imageUrl)
        if (images && images.length > 0) {
            directoryImages = images
            // Find current image index
            const currentPath = imageUrl.toString()
            for (let i = 0; i < images.length; i++) {
                if (images[i].toString() === currentPath) {
                    currentImageIndex = i
                    break
                }
            }
        } else {
            directoryImages = [imageUrl]
            currentImageIndex = 0
        }
    }
    
    function navigateToImage(index) {
        if (directoryImages.length === 0) return
        
        // Wrap around navigation
        if (index < 0) index = directoryImages.length - 1
        if (index >= directoryImages.length) index = 0
        
        currentImageIndex = index
        _navigatingImages = true  // Prevent re-scanning directory
        currentImage = directoryImages[index]
        _navigatingImages = false
    }
    
    function nextImage() {
        navigateToImage(currentImageIndex + 1)
    }
    
    function previousImage() {
        navigateToImage(currentImageIndex - 1)
    }

    function resetView() {
        if (!isVideo && !isAudio && !isMarkdown && !isText && !isPdf) {
            if (viewerLoader.item) {
                viewerLoader.item.resetView()
            }
        }
    }
    
    function unloadMedia() {
        // Set flag to prevent onCurrentImageChanged from triggering load logic
        _isUnloading = true
        
        // Log memory before unload
        let memBefore = 0.0
        if (typeof ColorUtils !== "undefined" && ColorUtils.getMemoryUsage) {
            memBefore = ColorUtils.getMemoryUsage()
            logToDebugConsole("[Unload] Memory before unload: " + memBefore.toFixed(2) + " MB", "info")
        }
        
        logToDebugConsole("[Unload] Starting media unload...", "info")
        
        // FIRST: Make image viewer invisible to prevent any rendering/flash
        // Note: imageViewer.visible is bound to currentImage, so clearing currentImage will hide it
        // But we can also explicitly hide it for extra safety
        if (imageViewer) {
            logToDebugConsole("[Unload] Making image viewer invisible", "info")
        }
        
        // CRITICAL: Clear currentImage FIRST before anything else
        // This ensures all bound components (imageViewer, videoPlayer, audioPlayer) clear immediately
        currentImage = ""
        logToDebugConsole("[Unload] Cleared currentImage", "info")
        
        // Unload all viewers via Loaders to ensure proper cleanup
        try {
            unloadAllViewers()
            logToDebugConsole("[Unload] All viewers unloaded via Loaders", "info")
        } catch (e) {
            logToDebugConsole("[Unload] ERROR in unloadAllViewers: " + e, "error")
        }
        
        logToDebugConsole("[Unload] Step: About to clear media properties", "info")
        // Clear all other media properties
        initialImage = ""
        directoryImages = []
        currentImageIndex = 0
        audioCoverArt = ""
        audioFormatInfo = { sampleRate: 0, bitrate: 0 }
        logToDebugConsole("[Unload] Cleared media properties", "info")
        
        logToDebugConsole("[Unload] Step: About to reset view", "info")
        // Reset view
        resetView()
        logToDebugConsole("[Unload] Step: Reset view complete", "info")

        logToDebugConsole("[Unload] Step: About to reset accent color", "info")
        // Reset accent color to default (black)
        accentColor = Qt.rgba(0.07, 0.07, 0.09, 1.0)
        dynamicColoringEnabled = true  // Re-enable for next load
        logToDebugConsole("[Unload] Reset accent color to default", "info")
        
        logToDebugConsole("[Unload] Step: About to hide controls", "info")
        // Hide controls
        showImageControls = false
        showingSettings = false
        showingMetadata = false
        logToDebugConsole("[Unload] Step: Controls hidden", "info")
        
        logToDebugConsole("[Unload] Step: About to clear Qt image cache", "info")
        // Clear Qt's image cache immediately (synchronous)
        try {
            if (typeof ColorUtils !== "undefined" && ColorUtils.clearImageCache) {
                ColorUtils.clearImageCache()
                logToDebugConsole("[Unload] Cleared Qt image cache", "info")
            } else {
                logToDebugConsole("[Unload] WARNING: ColorUtils.clearImageCache not available", "warning")
            }
        } catch (e) {
            logToDebugConsole("[Unload] ERROR in clearImageCache: " + e, "error")
        }
        
        logToDebugConsole("[Unload] Step: About to force garbage collection", "info")
        // Force QML garbage collection to release memory immediately
        try {
            if (typeof Qt !== "undefined" && Qt.callLater) {
                // Force GC by processing events and calling GC
                Qt.callLater(function() {
                    // Give Qt a moment to process cleanup events
                    Qt.callLater(function() {
                        // Now measure memory after GC has had time to run
                        logToDebugConsole("[Unload] Step: About to get memory after unload (after GC)", "info")
                        try {
                            if (typeof ColorUtils !== "undefined" && ColorUtils.getMemoryUsage) {
                                const memAfter = ColorUtils.getMemoryUsage()
                                const freed = memBefore - memAfter
                                logToDebugConsole("[Unload] Memory after unload: " + memAfter.toFixed(2) + " MB (freed: " + freed.toFixed(2) + " MB)", "info")
                            } else {
                                logToDebugConsole("[Unload] WARNING: ColorUtils.getMemoryUsage not available", "warning")
                            }
                        } catch (e) {
                            logToDebugConsole("[Unload] ERROR in getMemoryUsage: " + e, "error")
                        }
                    }, 100)  // 100ms delay to allow GC to run
                })
            }
        } catch (e) {
            logToDebugConsole("[Unload] ERROR in GC delay: " + e, "error")
        }
        
        // Log memory immediately (before GC) for comparison
        try {
            if (typeof ColorUtils !== "undefined" && ColorUtils.getMemoryUsage) {
                const memAfterImmediate = ColorUtils.getMemoryUsage()
                const freedImmediate = memBefore - memAfterImmediate
                logToDebugConsole("[Unload] Memory immediately after unload (before GC): " + memAfterImmediate.toFixed(2) + " MB (freed: " + freedImmediate.toFixed(2) + " MB)", "info")
            }
        } catch (e) {
            // Ignore errors in immediate measurement
        }
        
        logToDebugConsole("[Unload] Media unload complete", "info")
        
        // Clear the unloading flag
        _isUnloading = false
        logToDebugConsole("[Unload] Unloading flag cleared, function returning", "info")
    }
    
    function loadFile(fileUrl) {
        if (fileUrl && fileUrl !== "") {
            currentImage = fileUrl
        }
    }

    function clampPan() {
        if (window.currentImage === "") {
            panX = 0
            panY = 0
            return
        }

        if (window.isVideo || window.isMarkdown || window.isText || window.isPdf) {
            // Videos, markdown, text, and PDF don't need pan clamping
                panX = 0
                panY = 0
                return
        } else if (!window.isAudio) {
            // For images, use the imageViewer component
            if (viewerLoader.item) {
                viewerLoader.item.clampPan()
            }
        }
    }

    function useFallbackAccent() {
        colorExtractor.useFallbackAccent()
    }

    function updateAccentColor() {
        colorExtractor.updateAccentColor()
    }

    function checkIfVideo(url) {
        if (!url || url === "")
            return false
        const path = url.toString().toLowerCase()
        // GIFs are images, not videos
        return path.endsWith(".mp4") || path.endsWith(".avi") || path.endsWith(".mov") ||
               path.endsWith(".mkv") || path.endsWith(".webm") || path.endsWith(".m4v") ||
               path.endsWith(".flv") || path.endsWith(".wmv") || path.endsWith(".mpg") ||
               path.endsWith(".mpeg") || path.endsWith(".3gp")
    }
    
    function checkIfGif(url) {
        if (!url || url === "")
            return false
        const path = url.toString().toLowerCase()
        return path.endsWith(".gif")
    }
    
    function checkIfAudio(url) {
        if (!url || url === "")
            return false
        const path = url.toString().toLowerCase()
        return path.endsWith(".mp3") || path.endsWith(".wav") || path.endsWith(".flac") ||
               path.endsWith(".ogg") || path.endsWith(".aac") || path.endsWith(".m4a") ||
               path.endsWith(".wma") || path.endsWith(".opus") || path.endsWith(".mp2") ||
               path.endsWith(".mp1") || path.endsWith(".amr") || path.endsWith(".3gp")
    }
    
    function checkIfMarkdown(url) {
        if (!url || url === "")
            return false
        const path = url.toString().toLowerCase()
        return path.endsWith(".md") || path.endsWith(".markdown") || path.endsWith(".mdown") ||
               path.endsWith(".mkd") || path.endsWith(".mkdn")
    }
    
    function checkIfText(url) {
        if (!url || url === "")
            return false
        const path = url.toString().toLowerCase()
        // Plain text
        if (path.endsWith(".txt") || path.endsWith(".log") || path.endsWith(".nfo"))
            return true
        // Config files
        if (path.endsWith(".ini") || path.endsWith(".cfg") || path.endsWith(".conf") ||
            path.endsWith(".env") || path.endsWith(".properties"))
            return true
        // Data formats
        if (path.endsWith(".json") || path.endsWith(".xml") || path.endsWith(".yaml") ||
            path.endsWith(".yml") || path.endsWith(".csv") || path.endsWith(".toml"))
            return true
        // Web development
        if (path.endsWith(".html") || path.endsWith(".htm") || path.endsWith(".css") ||
            path.endsWith(".scss") || path.endsWith(".sass") || path.endsWith(".less") ||
            path.endsWith(".js") || path.endsWith(".jsx") || path.endsWith(".ts") ||
            path.endsWith(".tsx") || path.endsWith(".vue") || path.endsWith(".svelte"))
            return true
        // C/C++
        if (path.endsWith(".c") || path.endsWith(".cpp") || path.endsWith(".cc") ||
            path.endsWith(".cxx") || path.endsWith(".h") || path.endsWith(".hpp") ||
            path.endsWith(".hxx") || path.endsWith(".hh"))
            return true
        // Qt/QML
        if (path.endsWith(".qml") || path.endsWith(".qrc") || path.endsWith(".pro") ||
            path.endsWith(".pri") || path.endsWith(".ui"))
            return true
        // Python
        if (path.endsWith(".py") || path.endsWith(".pyw") || path.endsWith(".pyx") ||
            path.endsWith(".pyi") || path.endsWith(".pyd"))
            return true
        // Java/Kotlin
        if (path.endsWith(".java") || path.endsWith(".kt") || path.endsWith(".kts") ||
            path.endsWith(".gradle"))
            return true
        // C#/F#
        if (path.endsWith(".cs") || path.endsWith(".fs") || path.endsWith(".csproj") ||
            path.endsWith(".sln"))
            return true
        // Ruby
        if (path.endsWith(".rb") || path.endsWith(".erb") || path.endsWith(".rake") ||
            path.endsWith(".gemspec"))
            return true
        // Go
        if (path.endsWith(".go") || path.endsWith(".mod") || path.endsWith(".sum"))
            return true
        // Rust
        if (path.endsWith(".rs") || path.endsWith(".toml"))
            return true
        // PHP
        if (path.endsWith(".php") || path.endsWith(".phtml"))
            return true
        // Shell/Scripts
        if (path.endsWith(".sh") || path.endsWith(".bash") || path.endsWith(".zsh") ||
            path.endsWith(".fish") || path.endsWith(".bat") || path.endsWith(".cmd") ||
            path.endsWith(".ps1") || path.endsWith(".psm1"))
            return true
        // SQL
        if (path.endsWith(".sql") || path.endsWith(".sqlite"))
            return true
        // Swift/Objective-C
        if (path.endsWith(".swift") || path.endsWith(".m") || path.endsWith(".mm"))
            return true
        // Lua
        if (path.endsWith(".lua"))
            return true
        // Perl
        if (path.endsWith(".pl") || path.endsWith(".pm"))
            return true
        // R
        if (path.endsWith(".r") || path.endsWith(".rmd"))
            return true
        // Scala
        if (path.endsWith(".scala") || path.endsWith(".sc"))
            return true
        // Dart
        if (path.endsWith(".dart"))
            return true
        // Assembly
        if (path.endsWith(".asm") || path.endsWith(".s"))
            return true
        // Makefiles and build
        if (path.endsWith(".mk") || path.endsWith(".cmake") || path.endsWith(".ninja") ||
            path.endsWith("makefile") || path.endsWith("cmakelists.txt"))
            return true
        // Docker
        if (path.endsWith(".dockerfile") || path.endsWith("dockerfile") ||
            path.endsWith(".dockerignore"))
            return true
        // Git
        if (path.endsWith(".gitignore") || path.endsWith(".gitattributes") ||
            path.endsWith(".gitmodules"))
            return true
        // Other
        if (path.endsWith(".diff") || path.endsWith(".patch") || path.endsWith(".rst") ||
            path.endsWith(".tex") || path.endsWith(".bib") || path.endsWith(".cls") ||
            path.endsWith(".sty"))
            return true
        return false
    }
    
    function checkIfPdf(url) {
        if (!url || url === "")
            return false
        const path = url.toString().toLowerCase()
        return path.endsWith(".pdf")
    }
    
    function formatTime(ms) {
        if (!ms || ms <= 0) return "0:00"
        const totalSeconds = Math.floor(ms / 1000)
        const minutes = Math.floor(totalSeconds / 60)
        const seconds = totalSeconds % 60
        return minutes + ":" + (seconds < 10 ? "0" : "") + seconds
    }
    
    function extractAudioCoverArt() {
        if (!isAudio || !currentImage || currentImage === "") {
            audioCoverArt = ""
            return
        }
        
        // Use C++ helper to extract cover art - call asynchronously to avoid blocking UI
        // Defer color extraction to after cover art is ready (non-blocking)
        if (typeof ColorUtils !== "undefined" && ColorUtils.extractCoverArt) {
            Qt.callLater(function() {
            const coverArtUrl = ColorUtils.extractCoverArt(currentImage)
            if (coverArtUrl && coverArtUrl !== "") {
                audioCoverArt = coverArtUrl
                    // Update accent color from cover art (also deferred, non-blocking)
                Qt.callLater(function() {
                    updateAccentColor()
                })
            } else {
                audioCoverArt = ""
            }
            })
        } else {
            audioCoverArt = ""
        }
    }
    
    function getAudioFormatInfo(durationMs) {
        if (!isAudio || !currentImage || currentImage === "") {
            audioFormatInfo = { sampleRate: 0, bitrate: 0 }
            return
        }
        // If duration not provided, try to get it from audioPlayer
        if (durationMs === undefined || durationMs === 0) {
            if (audioPlayerLoader.item && audioPlayerLoader.item.duration > 0) {
                durationMs = audioPlayerLoader.item.duration
            } else {
                // Still get sample rate even without duration (bitrate will be 0)
                durationMs = 0
            }
        }
        
        // Use C++ helper to get audio format info directly from the media file
        if (typeof ColorUtils !== "undefined" && ColorUtils.getAudioFormatInfo) {
            const formatInfo = ColorUtils.getAudioFormatInfo(currentImage, durationMs)
            if (formatInfo) {
                // Merge with existing to preserve values
                const newInfo = {
                    sampleRate: formatInfo.sampleRate || audioFormatInfo.sampleRate || 0,
                    bitrate: formatInfo.bitrate || audioFormatInfo.bitrate || 0
                }
                audioFormatInfo = newInfo
                // Refresh metadata if popup is open
                if (showingMetadata) {
                    Qt.callLater(function() {
                        if (metadataPopup) {
                            metadataPopup.metadataList = getMetadataList()
                        }
                    })
                }
            } else {
                if (!audioFormatInfo || (audioFormatInfo.sampleRate === 0 && audioFormatInfo.bitrate === 0)) {
                    audioFormatInfo = { sampleRate: 0, bitrate: 0 }
                }
            }
        } else {
            audioFormatInfo = { sampleRate: 0, bitrate: 0 }
        }
    }

    function logToDebugConsole(message, type) {
        // Always log to regular console first
        console.log(message)
        
        // Try to log to debug console
        if (debugConsole) {
            try {
                if (typeof debugConsole.addLog === "function") {
                    debugConsole.addLog(message, type || "info")
                } else {
                    console.log("[Debug] debugConsole.addLog not available")
                }
            } catch (e) {
                console.log("[Debug] Error logging to console:", e)
            }
        } else {
            console.log("[Debug] debugConsole is null")
        }
    }

    function startLoadTimer(typeLabel) {
        if (!currentImage || currentImage === "") {
            loadStartTime = 0
            pendingLoadSource = ""
            pendingLoadType = ""
            return
        }
        loadStartTime = Date.now()
        pendingLoadSource = currentImage
        pendingLoadType = typeLabel || "Unknown"
        const message = "[Load] Started " + pendingLoadType + " for " + decodeURIComponent(currentImage.toString())
        logToDebugConsole(message, "info")
    }

    function logLoadDuration(statusLabel, sourceUrl) {
        if (!loadStartTime)
            return
        const targetUrl = sourceUrl || currentImage
        if (pendingLoadSource && pendingLoadSource !== "" && targetUrl && targetUrl !== "" &&
                pendingLoadSource.toString() !== targetUrl.toString()) {
            return
        }
        const elapsed = Date.now() - loadStartTime
        const message = "[Load] " + statusLabel + " in " + elapsed + " ms (" + pendingLoadType + ")"
        logToDebugConsole(message, "info")
        loadStartTime = 0
        pendingLoadSource = ""
        pendingLoadType = ""
    }

    // Flag to prevent loading when we're intentionally clearing
    property bool _isUnloading: false

    // Functions to load/unload ImageViewer via Loader (recreates it for proper scene graph rebinding)
    function loadImageViewer() {
        viewerLoader.active = false
        viewerLoader.active = true
    }
    
    function unloadImageViewer() {
        viewerLoader.active = false
    }
    
    // Functions to load/unload VideoPlayer via Loader
    function loadVideoPlayer() {
        videoPlayerLoader.active = false
        videoPlayerLoader.active = true
    }
    
    function unloadVideoPlayer() {
        if (videoPlayerLoader.item) {
            videoPlayerLoader.item.stop()
            videoPlayerLoader.item.source = ""
        }
        videoPlayerLoader.active = false
    }
    
    // Functions to load/unload AudioPlayer via Loader
    function loadAudioPlayer() {
        audioPlayerLoader.active = false
        audioPlayerLoader.active = true
    }
    
    function unloadAudioPlayer() {
        if (audioPlayerLoader.item) {
            audioPlayerLoader.item.stop()
            audioPlayerLoader.item.source = ""
        }
        audioPlayerLoader.active = false
    }
    
    // Functions to load/unload MarkdownViewer via Loader
    function loadMarkdownViewer() {
        markdownViewerLoader.active = false
        markdownViewerLoader.active = true
    }
    
    function unloadMarkdownViewer() {
        markdownViewerLoader.active = false
    }
    
    // Functions to load/unload TextViewer via Loader
    function loadTextViewer() {
        textViewerLoader.active = false
        textViewerLoader.active = true
    }
    
    function unloadTextViewer() {
        textViewerLoader.active = false
    }
    
    // Functions to load/unload PdfViewer via Loader
    function loadPdfViewer() {
        pdfViewerLoader.active = false
        pdfViewerLoader.active = true
    }
    
    function unloadPdfViewer() {
        pdfViewerLoader.active = false
    }
    
    // Helper function to unload all viewers
    function unloadAllViewers() {
        unloadImageViewer()
        unloadVideoPlayer()
        unloadAudioPlayer()
        unloadMarkdownViewer()
        unloadTextViewer()
        unloadPdfViewer()
    }

    onCurrentImageChanged: {
        const imageStr = currentImage.toString()
        
        // If currentImage is empty, unload all viewers and return early
        // CRITICAL: Do NOT load any viewer when clearing - only unload
        if (currentImage === "") {
            // Unload all viewers (only if active to avoid unnecessary calls)
            if (viewerLoader.active) unloadImageViewer()
            if (videoPlayerLoader.active) unloadVideoPlayer()
            if (audioPlayerLoader.active) unloadAudioPlayer()
            if (markdownViewerLoader.active) unloadMarkdownViewer()
            if (textViewerLoader.active) unloadTextViewer()
            if (pdfViewerLoader.active) unloadPdfViewer()
            useFallbackAccent()
            logToDebugConsole("[Media] Cleared current image", "info")
            return  // CRITICAL: Return early - do NOT proceed to load logic below
        }
        
        // If we're in the middle of unloading, handle appropriately
        // This prevents race conditions when unloadMedia() or resetForReuse() sets currentImage = ""
        if (_isUnloading) {
            // If currentImage is empty, we're actually unloading - skip load
            if (currentImage === "") {
                logToDebugConsole("[Media] Skipping load - unload in progress (empty URL)", "info")
                return
            }
            // If we have a valid URL, this means resetForReuse() set the flag,
            // and now C++ is setting a new image - clear the flag and continue loading
            logToDebugConsole("[Media] Clearing unloading flag - new media URL set after reset", "info")
            _isUnloading = false
            // Continue to load logic below (don't return)
        }
        
        // New image to load - reset view and detect type
        resetView()
        isVideo = checkIfVideo(currentImage)
        isGif = checkIfGif(currentImage)
        isAudio = checkIfAudio(currentImage)
        isMarkdown = checkIfMarkdown(currentImage)
        isText = checkIfText(currentImage)
        isPdf = checkIfPdf(currentImage)
        
        // CRITICAL: Clear unloading flag before loading (in case it was set by resetForReuse)
        _isUnloading = false
        
        // CRITICAL: Recreate the appropriate viewer via Loader to ensure proper scene graph rebinding
        // This fixes the issue where components don't reload after window hide/show
        if (isVideo) {
            loadVideoPlayer()
        } else if (isAudio) {
            loadAudioPlayer()
        } else if (isMarkdown) {
            loadMarkdownViewer()
        } else if (isText) {
            loadTextViewer()
        } else if (isPdf) {
            loadPdfViewer()
        } else {
            // Image (including GIF)
            loadImageViewer()
        }
        
        // Log image change
        const fileName = currentImage.toString().split("/").pop() || currentImage.toString()
        if (isVideo) {
            useFallbackAccent()
            startLoadTimer("Video")
        } else if (isAudio) {
            // Audio keeps color until cover art is detected
            startLoadTimer("Audio")
        } else if (isMarkdown) {
            useFallbackAccent()
            startLoadTimer("Markdown")
        } else if (isText) {
            useFallbackAccent()
            startLoadTimer("Text")
        } else if (isPdf) {
            useFallbackAccent()
            startLoadTimer("PDF")
        } else {
            // Images: keep previous color until new one is detected (smooth transition)
            startLoadTimer(isGif ? "GIF" : "Image")
        }
        if (!isVideo && !isAudio && !isMarkdown && !isText && !isPdf) {
            // Don't call updateAccentColor here - it's called async in onImageReady
            // Load all images from directory for navigation (only if not already navigating)
            if (!_navigatingImages) {
                loadDirectoryImages(currentImage)
                showImageControls = false  // Hide controls when loading new image
            }
        } else if (isVideo) {
            // Stop audio if playing
            if (audioPlayerLoader.item) {
                audioPlayerLoader.item.stop()
            }
        } else if (isAudio) {
            // Stop video if playing
            if (videoPlayerLoader.item) {
                videoPlayerLoader.item.stop()
            }
            // Reset cover art and format info
            audioCoverArt = ""
            audioFormatInfo = { sampleRate: 0, bitrate: 0 }
            // Try to extract cover art immediately (might be available)
            Qt.callLater(function() {
                extractAudioCoverArt()
                getAudioFormatInfo(0) // Get sample rate only
            })
        } else if (isMarkdown || isText || isPdf) {
            // Stop video and audio if they have a source and are playing
            if (videoPlayerLoader.item && videoPlayerLoader.item.source !== "") {
                const state = videoPlayerLoader.item.playbackState
                if (state !== undefined && (state === MediaPlayer.PlayingState || state === MediaPlayer.PausedState || (typeof state === 'number' && state > 0))) {
                    if (videoPlayerLoader.item) {
                videoPlayerLoader.item.stop()
            }
                }
            }
            if (audioPlayerLoader.item && audioPlayerLoader.item.source !== "") {
                const state = audioPlayerLoader.item.playbackState
                if (state !== undefined && (state === MediaPlayer.PlayingState || state === MediaPlayer.PausedState || (typeof state === 'number' && state > 0))) {
                    if (audioPlayerLoader.item) {
                audioPlayerLoader.item.stop()
            }
                }
            }
        }
    }
    // Throttle clampPan during resize to avoid lag
    Timer {
        id: clampPanTimer
        interval: 16  // ~60fps
        onTriggered: clampPan()
    }
    
    onWidthChanged: {
        if (!clampPanTimer.running) {
            clampPanTimer.start()
        }
    }
    onHeightChanged: {
        if (!clampPanTimer.running) {
            clampPanTimer.start()
        }
    }

    header: TitleBar {
        id: customTitleBar
        windowTitle: window.title
        currentFilePath: window.currentImage
        accentColor: window.accentColor
        foregroundColor: window.foregroundColor
        hasMedia: window.currentImage !== ""
        window: window
        
        onMetadataClicked: window.showingMetadata = !window.showingMetadata
        onSettingsClicked: window.showingSettings = !window.showingSettings
        onMinimizeClicked: window.showMinimized()
        onMaximizeClicked: {
                            if (window.visibility === Window.Maximized)
                                window.showNormal()
                            else
                                window.showMaximized()
                        }
        onCloseClicked: {
            // Always trigger close event - let onClosing handle the logic
            window.close()
        }
        onWindowMoveRequested: window.startSystemMove()
    }

    // Metadata popup
    MetadataPopup {
        id: metadataPopup
        parent: window.contentItem
        x: customTitleBar.x + 4
        y: customTitleBar.height + 4
        visible: window.showingMetadata && window.currentImage !== ""
        metadataList: window.getMetadataList()
        accentColor: window.accentColor
        foregroundColor: window.foregroundColor
        onVisibleChanged: {
            if (!visible) {
                window.showingMetadata = false
            }
        }
    }
    
    function getMetadataList() {
        if (window.currentImage === "") return []
        
        const path = window.currentImage.toString().replace("file:///", "")
        const decodedPath = decodeURIComponent(path)
        const list = []
        
        // File name
        const fileName = decodedPath.split(/[/\\]/).pop()
        list.push({ label: "File Name", value: fileName })
        
        // File path (truncated if too long)
        const displayPath = decodedPath.length > 60 ? "..." + decodedPath.slice(-57) : decodedPath
        list.push({ label: "File Path", value: displayPath })
        
        // File extension
        const extension = fileName.split('.').pop().toUpperCase()
        list.push({ label: "File Format", value: extension })
        
        // File type
        if (window.isVideo) {
            list.push({ label: "Media Type", value: "Video" })
            
            // Duration
            if (videoPlayerLoader.item && videoPlayerLoader.item.duration > 0) {
                list.push({ label: "Duration", value: formatTime(videoPlayerLoader.item.duration) })
            }
            
            // Get resolution from implicit size (always available)
            if (videoPlayerLoader.item && videoPlayerLoader.item.implicitWidth > 0 && videoPlayerLoader.item.implicitHeight > 0) {
                list.push({ label: "Resolution", value: Math.round(videoPlayerLoader.item.implicitWidth) + " × " + Math.round(videoPlayerLoader.item.implicitHeight) + " px" })
            }
            
            // Try to get metadata - Qt 6 metadata access
            const metaData = videoPlayerLoader.item ? videoPlayerLoader.item.metaData : null
            if (metaData) {
                // Helper to safely get metadata
                const getMeta = function(key) {
                    try {
                        // Try stringValue method first (Qt 6 way)
                        if (typeof metaData.stringValue === 'function') {
                            const result = metaData.stringValue(key)
                            if (result !== undefined && result !== null && result !== "") {
                                return result
                            }
                        }
                        // Try direct property access
                        if (metaData[key] !== undefined && metaData[key] !== null) {
                            return metaData[key]
                        }
                    } catch(e) {
                        // Ignore errors
                    }
                    return null
                }
                
                // Video codec
                const videoCodec = getMeta(MediaMetaData.VideoCodec) || getMeta("VideoCodec")
                if (videoCodec) {
                    list.push({ label: "Video Codec", value: String(videoCodec) })
                }
                
                // Video bitrate
                const videoBitrate = getMeta(MediaMetaData.VideoBitRate) || getMeta("VideoBitRate")
                if (videoBitrate) {
                    const bitrate = parseInt(videoBitrate)
                    if (!isNaN(bitrate) && bitrate > 0) {
                        const bitrateStr = bitrate >= 1000000 
                            ? (bitrate / 1000000).toFixed(2) + " Mbps"
                            : (bitrate >= 1000 ? (bitrate / 1000).toFixed(0) + " kbps" : bitrate + " bps")
                        list.push({ label: "Video Bitrate", value: bitrateStr })
                    }
                }
                
                // Frame rate
                const frameRate = getMeta(MediaMetaData.FrameRate) || getMeta("FrameRate")
                if (frameRate) {
                    const rate = parseFloat(frameRate)
                    if (!isNaN(rate) && rate > 0) {
                        list.push({ label: "Frame Rate", value: rate.toFixed(2) + " fps" })
                    }
                }
                
                // Audio codec
                const audioCodec = getMeta(MediaMetaData.AudioCodec) || getMeta("AudioCodec")
                if (audioCodec) {
                    list.push({ label: "Audio Codec", value: String(audioCodec) })
                }
                
                // Audio bitrate
                const audioBitrate = getMeta(MediaMetaData.AudioBitRate) || getMeta("AudioBitRate")
                if (audioBitrate) {
                    const bitrate = parseInt(audioBitrate)
                    if (!isNaN(bitrate) && bitrate > 0) {
                        const bitrateStr = bitrate >= 1000000 
                            ? (bitrate / 1000000).toFixed(2) + " Mbps"
                            : (bitrate >= 1000 ? (bitrate / 1000).toFixed(0) + " kbps" : bitrate + " bps")
                        list.push({ label: "Audio Bitrate", value: bitrateStr })
                    }
                }
                
                // Sample rate
                const sampleRate = getMeta(MediaMetaData.SampleRate) || getMeta("SampleRate")
                if (sampleRate) {
                    const rate = parseInt(sampleRate)
                    if (!isNaN(rate) && rate > 0) {
                        list.push({ label: "Sample Rate", value: rate + " Hz" })
                    }
                }
                
                // Channel count
                const channelCount = getMeta(MediaMetaData.ChannelCount) || getMeta("ChannelCount")
                if (channelCount) {
                    const channels = parseInt(channelCount)
                    if (!isNaN(channels) && channels > 0) {
                        const channelStr = channels === 1 ? "Mono" : (channels === 2 ? "Stereo" : channels + " channels")
                        list.push({ label: "Audio Channels", value: channelStr })
                    }
                }
            }
            
            // Tracks
            if (videoPlayerLoader.item) {
                list.push({ label: "Video Track", value: videoPlayerLoader.item.hasVideo ? "Yes" : "No" })
                list.push({ label: "Audio Track", value: videoPlayerLoader.item.hasAudio ? "Yes" : "No" })
                
                // Playback info
                if (videoPlayerLoader.item.playbackRate !== undefined && videoPlayerLoader.item.playbackRate !== 1.0) {
                    list.push({ label: "Playback Rate", value: videoPlayerLoader.item.playbackRate.toFixed(2) + "x" })
                }
                if (videoPlayerLoader.item.playbackState !== undefined) {
                    const states = ["Stopped", "Playing", "Paused"]
                    list.push({ label: "Playback State", value: states[videoPlayerLoader.item.playbackState] || "Unknown" })
                }
            }
        } else if (window.isAudio) {
            list.push({ label: "Media Type", value: "Audio" })
            
            // Duration
            if (audioPlayerLoader.item && audioPlayerLoader.item.duration > 0) {
                list.push({ label: "Duration", value: formatTime(audioPlayerLoader.item.duration) })
            }
            
            // Try to get metadata
            const metaData = audioPlayerLoader.item ? audioPlayerLoader.item.metaData : null
            if (metaData) {
                const getMeta = function(key) {
                    try {
                        if (typeof metaData.stringValue === 'function') {
                            const result = metaData.stringValue(key)
                            if (result !== undefined && result !== null && result !== "") {
                                return result
                            }
                        }
                        if (metaData[key] !== undefined && metaData[key] !== null) {
                            return metaData[key]
                        }
                    } catch(e) {
                        // Ignore errors
                    }
                    return null
                }
                
                // Audio codec
                const audioCodec = getMeta(MediaMetaData.AudioCodec) || getMeta("AudioCodec")
                if (audioCodec) {
                    list.push({ label: "Audio Codec", value: String(audioCodec) })
                }
                
                // Sample rate - get from C++ helper (FFmpeg directly)
                if (window.audioFormatInfo && window.audioFormatInfo.sampleRate > 0) {
                    list.push({ label: "Sample Rate", value: window.audioFormatInfo.sampleRate.toLocaleString() + " Hz" })
                } else {
                    // Fallback to metadata
                    const sampleRate = getMeta(MediaMetaData.SampleRate) || getMeta("SampleRate")
                    if (sampleRate) {
                        const rate = parseInt(sampleRate)
                        if (!isNaN(rate) && rate > 0) {
                            list.push({ label: "Sample Rate", value: rate + " Hz" })
                        }
                    }
                }
                
                // Audio bitrate - get from C++ helper (FFmpeg directly)
                if (window.audioFormatInfo && window.audioFormatInfo.bitrate > 0) {
                    const bitrate = window.audioFormatInfo.bitrate
                    const bitrateStr = bitrate >= 1000000 
                        ? (bitrate / 1000000).toFixed(2) + " Mbps"
                        : (bitrate >= 1000 ? (bitrate / 1000).toFixed(0) + " kbps" : bitrate + " bps")
                    list.push({ label: "Bitrate", value: bitrateStr })
                } else {
                    // Fallback to metadata
                    const audioBitrate = getMeta(MediaMetaData.AudioBitRate) || getMeta("AudioBitRate")
                    if (audioBitrate) {
                        const bitrate = parseInt(audioBitrate)
                        if (!isNaN(bitrate) && bitrate > 0) {
                            const bitrateStr = bitrate >= 1000000 
                                ? (bitrate / 1000000).toFixed(2) + " Mbps"
                                : (bitrate >= 1000 ? (bitrate / 1000).toFixed(0) + " kbps" : bitrate + " bps")
                            list.push({ label: "Bitrate", value: bitrateStr })
                        }
                    }
                }
                
                // Channel count
                const channelCount = getMeta(MediaMetaData.ChannelCount) || getMeta("ChannelCount")
                if (channelCount) {
                    const channels = parseInt(channelCount)
                    if (!isNaN(channels) && channels > 0) {
                        const channelStr = channels === 1 ? "Mono" : (channels === 2 ? "Stereo" : channels + " channels")
                        list.push({ label: "Channels", value: channelStr })
                    }
                }
                
                // Title
                const title = getMeta(MediaMetaData.Title) || getMeta("Title")
                if (title) {
                    list.push({ label: "Title", value: String(title) })
                }
                
                // Contributing Artists
                const contributingArtists = getMeta(MediaMetaData.ContributingArtist) || getMeta("ContributingArtist") || getMeta("Artist")
                if (contributingArtists) {
                    list.push({ label: "Contributing Artists", value: String(contributingArtists) })
                }
                
                // Album Artist
                const albumArtist = getMeta(MediaMetaData.AlbumArtist) || getMeta("AlbumArtist")
                if (albumArtist) {
                    list.push({ label: "Album Artist", value: String(albumArtist) })
                }
                
                // Album
                const album = getMeta(MediaMetaData.AlbumTitle) || getMeta("AlbumTitle") || getMeta("Album")
                if (album) {
                    list.push({ label: "Album", value: String(album) })
                }
                
                // Track Number (#)
                const trackNumber = getMeta(MediaMetaData.TrackNumber) || getMeta("TrackNumber")
                if (trackNumber) {
                    const track = parseInt(trackNumber)
                    if (!isNaN(track) && track > 0) {
                        list.push({ label: "#", value: String(track) })
                    } else {
                        list.push({ label: "#", value: String(trackNumber) })
                    }
                }
                
                // Genre
                const genre = getMeta(MediaMetaData.Genre) || getMeta("Genre")
                if (genre) {
                    list.push({ label: "Genre", value: String(genre) })
                }
                
                // Year
                const year = getMeta(MediaMetaData.Year) || getMeta("Year") || getMeta(MediaMetaData.Date) || getMeta("Date")
                if (year) {
                    // Try to extract year from date if it's a full date
                    let yearValue = String(year)
                    const yearMatch = yearValue.match(/\b(19|20)\d{2}\b/)
                    if (yearMatch) {
                        yearValue = yearMatch[0]
                    }
                    list.push({ label: "Year", value: yearValue })
                }
                
                // Date Released
                const dateReleased = getMeta(MediaMetaData.Date) || getMeta("Date")
                if (dateReleased && dateReleased !== year) {
                    list.push({ label: "Date Released", value: String(dateReleased) })
                }
                
                // Encoded By
                const encodedBy = getMeta(MediaMetaData.Encoder) || getMeta("Encoder") || getMeta("EncodedBy")
                if (encodedBy) {
                    list.push({ label: "Encoded By", value: String(encodedBy) })
                }
                
                // Copyright
                const copyright = getMeta(MediaMetaData.Copyright) || getMeta("Copyright")
                if (copyright) {
                    list.push({ label: "Copyright", value: String(copyright) })
                }
            }
            
            // Playback info
            if (audioPlayerLoader.item && audioPlayerLoader.item.playbackState !== undefined) {
                const states = ["Stopped", "Playing", "Paused"]
                list.push({ label: "Playback State", value: states[audioPlayerLoader.item.playbackState] || "Unknown" })
            }
        } else if (window.isGif) {
            list.push({ label: "Media Type", value: "Animated GIF" })
            if (viewerLoader.item && viewerLoader.item.paintedWidth > 0 && viewerLoader.item.paintedHeight > 0) {
                list.push({ label: "Dimensions", value: viewerLoader.item.paintedWidth + " × " + viewerLoader.item.paintedHeight + " px" })
            }
            if (viewerLoader.item && viewerLoader.item.frameCount > 0) {
                list.push({ label: "Frame Count", value: viewerLoader.item.frameCount })
            }
            if (viewerLoader.item && viewerLoader.item.currentFrame !== undefined) {
                list.push({ label: "Current Frame", value: viewerLoader.item.currentFrame + 1 })
            }
        } else if (window.isMarkdown) {
            list.push({ label: "Media Type", value: "Markdown" })
            if (markdownViewerLoader.item && markdownViewerLoader.item.content) {
                const lineCount = markdownViewerLoader.item.content.split('\n').length
                const charCount = markdownViewerLoader.item.content.length
                list.push({ label: "Lines", value: lineCount })
                list.push({ label: "Characters", value: charCount.toLocaleString() })
            }
        } else if (window.isText) {
            list.push({ label: "Media Type", value: "Text" })
            if (textViewerLoader.item && textViewerLoader.item.lineCount > 0) {
                list.push({ label: "Lines", value: textViewerLoader.item.lineCount.toLocaleString() })
                list.push({ label: "Characters", value: textViewerLoader.item.characterCount.toLocaleString() })
                list.push({ label: "Status", value: textViewerLoader.item.modified ? "Modified" : "Saved" })
            }
        } else if (window.isPdf) {
            list.push({ label: "Media Type", value: "PDF Document" })
            if (pdfViewerLoader.item && pdfViewerLoader.item.isLoaded) {
                list.push({ label: "Pages", value: pdfViewerLoader.item.pageCount.toLocaleString() })
                list.push({ label: "Current Page", value: pdfViewerLoader.item.currentPage + " / " + pdfViewerLoader.item.pageCount })
                list.push({ label: "Zoom", value: Math.round(pdfViewerLoader.item.zoomLevel * 100) + "%" })
            }
        } else {
            list.push({ label: "Media Type", value: "Image" })
            if (viewerLoader.item && viewerLoader.item.paintedWidth > 0 && viewerLoader.item.paintedHeight > 0) {
                list.push({ label: "Dimensions", value: viewerLoader.item.paintedWidth + " × " + viewerLoader.item.paintedHeight + " px" })
            }
            if (viewerLoader.item && viewerLoader.item.status !== undefined) {
                const statuses = ["Null", "Ready", "Loading", "Error"]
                list.push({ label: "Status", value: statuses[viewerLoader.item.status] || "Unknown" })
            }
        }
        
        // View info (only for visual media, excluding PDF which has its own zoom in metadata)
        if (!window.isAudio && !window.isMarkdown && !window.isText && !window.isPdf) {
            list.push({ label: "Zoom Level", value: (window.zoomFactor * 100).toFixed(1) + "%" })
        }
        
        return list
    }

    StackLayout {
        id: pageStack
        anchors.fill: parent
        currentIndex: window.showingSettings ? 1 : 0

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            Rectangle {
                id: viewer
                anchors.fill: parent
                color: window.backdropBlurEnabled
                       ? "transparent"  // Completely transparent when backdrop blur is active
                       : (window.ambientGradientEnabled
                          ? "transparent"  // Transparent when ambient gradient is active
                          : (window.snowEffectEnabled
                             ? "transparent"  // Transparent when snow effect is active
                             : (window.gradientBackgroundEnabled && window.paletteColors && window.paletteColors.length > 1
                                ? Qt.rgba(0, 0, 0, 0.15)  // Less dark overlay when gradient is active
                                : Qt.darker(window.accentColor, 1.15))))  // Solid color when gradient is off
                clip: true
                focus: true
                property int padding: 0
                border.width: 0  // Ensure no border is visible
                border.color: "transparent"  // Ensure border color is transparent too
                // Don't set opacity to 0 - it makes children invisible too

                WheelHandler {
                    id: wheel
                    target: null
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onWheel: function(event) {
                        const delta = event.angleDelta && event.angleDelta.y !== 0
                                      ? event.angleDelta.y
                                      : (event.pixelDelta ? event.pixelDelta.y * 8 : 0)
                        if (delta !== 0)
                            window.adjustZoom(delta)
                    }
                    enabled: window.currentImage.toString() !== "" && !window.isVideo && !window.isAudio && !window.isMarkdown && !window.isText && !window.isPdf
                }

                TapHandler {
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    gesturePolicy: TapHandler.ReleaseWithinBounds
                    onDoubleTapped: window.resetView()
                    onTapped: {
                        // Toggle image controls on single tap
                        if (window.isImageType && window.currentImage.toString() !== "") {
                            window.showImageControls = !window.showImageControls
                            if (window.showImageControls) {
                                imageControlsHideTimer.restart()
                            }
                        }
                    }
                    enabled: window.currentImage.toString() !== "" && !window.isVideo
                }
                
                TapHandler {
                    id: videoTapHandler
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    gesturePolicy: TapHandler.ReleaseWithinBounds
                    onTapped: {
                        if (window.isVideo && window.currentImage !== "") {
                            // Toggle play/pause based on playbackState
                            if (videoPlayerLoader.item) {
                                const wasPlaying = videoPlayerLoader.item.playbackState === MediaPlayer.PlayingState
                                if (wasPlaying) {
                                    videoPlayerLoader.item.pause()
                                } else {
                                    videoPlayerLoader.item.play()
                                }
                            }
                        }
                    }
                    enabled: window.currentImage !== "" && window.isVideo
                }

                DragHandler {
                    id: drag
                    property real prevX: 0
                    property real prevY: 0
                    target: null
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad | PointerDevice.Stylus
                    enabled: window.currentImage.toString() !== "" && !window.isVideo && !window.isAudio && !window.isMarkdown && !window.isText && !window.isPdf
                    onActiveChanged: {
                        prevX = translation.x
                        prevY = translation.y
                    }
                    onTranslationChanged: {
                        const factor = imageViewer.zoomFactor === 0 ? 1 : imageViewer.zoomFactor
                        imageViewer.panX += (translation.x - prevX) / factor
                        imageViewer.panY += (translation.y - prevY) / factor
                        prevX = translation.x
                        prevY = translation.y
                        if (viewerLoader.item) {
                            viewerLoader.item.clampPan()
                        }
                    }
                }

                DropArea {
                    anchors.fill: parent
                    keys: [ "text/uri-list" ]
                    onEntered: window.dropActive = true
                    onExited: window.dropActive = false
                    onDropped: function(drop) {
                        window.dropActive = false
                        if (drop.hasUrls && drop.urls.length > 0) {
                            const fileUrl = drop.urls[0]
                            logToDebugConsole("[QML] File dropped, setting currentImage: " + fileUrl.toString(), "info")
                            // Ensure window is visible when dropping file
                            if (!window.visible) {
                                window.show()
                                window.raise()
                            }
                            window.currentImage = fileUrl
                            drop.acceptProposedAction()
                        }
                    }
                }

                // Empty state placeholder
                Column {
                    id: emptyStatePlaceholder
                    anchors.centerIn: parent
                    spacing: 20
                    visible: window.currentImage.toString() === "" && !window.showingSettings
                    opacity: visible ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                    
                    // Icon container with subtle glow
                    Rectangle {
                        width: 120
                        height: 120
                        radius: 60
                        color: Qt.rgba(1, 1, 1, 0.05)
                        border.width: 2
                        border.color: Qt.rgba(1, 1, 1, 0.1)
                        anchors.horizontalCenter: parent.horizontalCenter
                        
                        // Decorative ring
                        Rectangle {
                            anchors.centerIn: parent
                            width: 100
                            height: 100
                            radius: 50
                            color: "transparent"
                            border.width: 1
                            border.color: Qt.rgba(1, 1, 1, 0.08)
                        }
                        
                        Text {
                            anchors.centerIn: parent
                            text: "📁"
                            font.pixelSize: 48
                            opacity: 0.7
                        }
                    }
                    
                    // Main text
                    Text {
                        text: "No media loaded"
                        font.pixelSize: 24
                        font.weight: Font.Medium
                        font.family: "Segoe UI"
                        color: Qt.rgba(1, 1, 1, 0.8)
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                    
                    // Subtitle
                    Text {
                        text: "Drag & drop a file here to get started"
                        font.pixelSize: 14
                        font.family: "Segoe UI"
                        color: Qt.rgba(1, 1, 1, 0.5)
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                    
                    // Or divider
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 12
                        
                        Rectangle {
                            width: 40
                            height: 1
                            color: Qt.rgba(1, 1, 1, 0.2)
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        
                        Text {
                            text: "or"
                            font.pixelSize: 12
                            font.family: "Segoe UI"
                            color: Qt.rgba(1, 1, 1, 0.4)
                        }
                        
                        Rectangle {
                            width: 40
                            height: 1
                            color: Qt.rgba(1, 1, 1, 0.2)
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                    
                    // Open file button
                    Rectangle {
                        width: 160
                        height: 40
                        radius: 20
                        color: openFileMouseArea.containsMouse ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(1, 1, 1, 0.1)
                        border.width: 1
                        border.color: Qt.rgba(1, 1, 1, 0.2)
                        anchors.horizontalCenter: parent.horizontalCenter
                        
                        Behavior on color { ColorAnimation { duration: 150 } }
                        
                        Row {
                            anchors.centerIn: parent
                            spacing: 8
                            
                            Text {
                                text: "📂"
                                font.pixelSize: 16
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            
                            Text {
                                text: "Browse files"
                                font.pixelSize: 14
                                font.family: "Segoe UI"
                                font.weight: Font.Medium
                                color: Qt.rgba(1, 1, 1, 0.9)
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                        
                        MouseArea {
                            id: openFileMouseArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: openDialog.open()
                        }
                    }
                    
                    // Supported formats hint
                    Text {
                        text: "Images • Videos • Audio • Documents"
                        font.pixelSize: 11
                        font.family: "Segoe UI"
                        color: Qt.rgba(1, 1, 1, 0.3)
                        anchors.horizontalCenter: parent.horizontalCenter
                        topPadding: 8
                    }
                }

                // Image viewer component - wrapped in Loader to allow recreation on reuse
                // CRITICAL: Loader recreates the ImageViewer each time, ensuring proper scene graph rebinding
                // This fixes the issue where Image/AnimatedImage don't reload after window hide/show
                Loader {
                    id: viewerLoader
                    anchors.fill: parent
                    active: false  // Start inactive, will be activated when image is loaded
                    visible: !window.isVideo && !window.isAudio && !window.isMarkdown && !window.isText && !window.isPdf && window.currentImage !== ""
                    
                    sourceComponent: Component {
                ImageViewer {
                    id: imageViewer
                        anchors.fill: parent
                            source: window.currentImage
                    isGif: window.isGif
                    zoomFactor: window.zoomFactor
                    panX: window.panX
                    panY: window.panY
                    accentColor: window.accentColor
                    
                    onImageReady: {
                                // Log duration FIRST so image appears immediately
                                window.logLoadDuration(window.isGif ? "GIF ready" : "Image ready", imageViewer.source)
                                // Then update accent color after a short delay (doesn't block image display)
                                accentColorTimer.restart()
                                
                                // Log memory after image loads
                                Qt.callLater(function() {
                                    if (typeof ColorUtils !== "undefined" && ColorUtils.getMemoryUsage) {
                                        const memAfter = ColorUtils.getMemoryUsage()
                                        window.logToDebugConsole("[Memory] After image load: " + memAfter.toFixed(2) + " MB", "info")
                                    }
                                })
                    }
                    
                    onPaintedSizeChanged: {
                            window.clampPan()
                        }
                    
                    Binding {
                        target: window
                        property: "zoomFactor"
                        value: imageViewer.zoomFactor
                                when: !window.isVideo && !window.isAudio && !window.isMarkdown && !window.isText && !window.isPdf
                    }
                    
                    Binding {
                        target: window
                        property: "panX"
                        value: imageViewer.panX
                                when: !window.isVideo && !window.isAudio && !window.isMarkdown && !window.isText && !window.isPdf
                    }
                    
                    Binding {
                        target: window
                        property: "panY"
                        value: imageViewer.panY
                                when: !window.isVideo && !window.isAudio && !window.isMarkdown && !window.isText && !window.isPdf
                            }
                            
                            Timer {
                                id: accentColorTimer
                                interval: 50  // Small delay to let image render first
                                onTriggered: window.updateAccentColor()
                            }
                        }
                    }
                }
                
                // Image controls bar
                ImageControls {
                    id: imageControls
                    anchors.bottom: parent.bottom
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottomMargin: 24
                    width: Math.min(500, parent.width - 48)
                    height: 48
                    visible: window.isImageType && window.showImageControls && window.currentImage.toString() !== "" && !window.showingSettings && !window.showingMetadata
                    z: 50
                    
                    currentIndex: window.currentImageIndex
                    totalImages: window.directoryImages.length
                    zoomFactor: window.zoomFactor
                    accentColor: window.accentColor
                    
                    onPreviousClicked: {
                        window.previousImage()
                        imageControlsHideTimer.restart()
                    }
                    onNextClicked: {
                        window.nextImage()
                        imageControlsHideTimer.restart()
                    }
                    onZoomInClicked: {
                        window.adjustZoom(100)
                        imageControlsHideTimer.restart()
                    }
                    onZoomOutClicked: {
                        window.adjustZoom(-100)
                        imageControlsHideTimer.restart()
                    }
                    onFitToWindowClicked: {
                        if (viewerLoader.item) {
                            viewerLoader.item.fitToWindow()
                        }
                        imageControlsHideTimer.restart()
                    }
                    onActualSizeClicked: {
                        if (viewerLoader.item) {
                            viewerLoader.item.actualSize()
                        }
                        imageControlsHideTimer.restart()
                    }
                    onRotateLeftClicked: {
                        if (viewerLoader.item) {
                            viewerLoader.item.rotateLeft()
                        }
                        imageControlsHideTimer.restart()
                    }
                    onRotateRightClicked: {
                        if (viewerLoader.item) {
                            viewerLoader.item.rotateRight()
                        }
                        imageControlsHideTimer.restart()
                    }
                    
                    // Fade in/out animation
                    opacity: visible ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 200 } }
                }
                
                // Auto-hide timer for image controls
                Timer {
                    id: imageControlsHideTimer
                    interval: 3000
                    onTriggered: window.showImageControls = false
                }
                
                // Pre-load next image for faster navigation
                Image {
                    id: preloadNext
                    visible: false
                    asynchronous: true
                    cache: true
                    source: {
                        if (!window.isImageType || window.directoryImages.length <= 1) return ""
                        const nextIndex = (window.currentImageIndex + 1) % window.directoryImages.length
                        return window.directoryImages[nextIndex] || ""
                    }
                }
                
                // Pre-load previous image for faster navigation
                Image {
                    id: preloadPrev
                    visible: false
                    asynchronous: true
                    cache: true
                    source: {
                        if (!window.isImageType || window.directoryImages.length <= 1) return ""
                        const prevIndex = (window.currentImageIndex - 1 + window.directoryImages.length) % window.directoryImages.length
                        return window.directoryImages[prevIndex] || ""
                    }
                }
                
                // Left navigation arrow
                Rectangle {
                    id: leftArrow
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 12
                    width: 32
                    height: 48
                    radius: 8
                    color: leftArrowMouse.containsMouse 
                           ? Qt.rgba(0, 0, 0, 0.7) 
                           : Qt.rgba(0, 0, 0, 0.4)
                    visible: window.isImageType && window.showImageControls && window.currentImage.toString() !== "" && window.directoryImages.length > 1 && !window.showingSettings && !window.showingMetadata
                    opacity: leftArrowMouse.containsMouse ? 1 : 0.5
                    z: 50
                    
                    Behavior on color { ColorAnimation { duration: 150 } }
                    Behavior on opacity { NumberAnimation { duration: 150 } }
                    
                    Text {
                        anchors.centerIn: parent
                        text: "‹"
                        color: "#ffffff"
                        font.pixelSize: 24
                        font.bold: true
                    }
                    
                    MouseArea {
                        id: leftArrowMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            window.previousImage()
                            imageControlsHideTimer.restart()
                        }
                    }
                }
                
                // Right navigation arrow
                Rectangle {
                    id: rightArrow
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.rightMargin: 12
                    width: 32
                    height: 48
                    radius: 8
                    color: rightArrowMouse.containsMouse 
                           ? Qt.rgba(0, 0, 0, 0.7) 
                           : Qt.rgba(0, 0, 0, 0.4)
                    visible: window.isImageType && window.showImageControls && window.currentImage.toString() !== "" && window.directoryImages.length > 1 && !window.showingSettings && !window.showingMetadata
                    opacity: rightArrowMouse.containsMouse ? 1 : 0.5
                    z: 50
                    
                    Behavior on color { ColorAnimation { duration: 150 } }
                    Behavior on opacity { NumberAnimation { duration: 150 } }
                    
                    Text {
                        anchors.centerIn: parent
                        text: "›"
                        color: "#ffffff"
                        font.pixelSize: 24
                        font.bold: true
                    }
                    
                    MouseArea {
                        id: rightArrowMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            window.nextImage()
                            imageControlsHideTimer.restart()
                        }
                    }
                }

                // Video player component - wrapped in Loader for proper recreation
                Loader {
                    id: videoPlayerLoader
                    anchors.fill: parent
                    active: false
                    visible: window.isVideo && window.currentImage !== ""
                    
                    sourceComponent: Component {
                        VideoPlayer {
                            id: videoPlayer
                            anchors.fill: parent
                            source: window.currentImage
                            volume: window.videoVolume
                            showControls: true
                            accentColor: window.accentColor
                            foregroundColor: window.foregroundColor
                            
                            onDurationAvailable: {
                                if (videoPlayer.duration > 0) {
                                    console.log("[Video] Duration available:", videoPlayer.duration, "ms")
                                    window.logLoadDuration("Video ready", videoPlayer.source)
                                    if (window.showingMetadata) {
                                        Qt.callLater(function() {
                                            if (metadataPopup) {
                                                metadataPopup.metadataList = window.getMetadataList()
                                            }
                                        })
                                    }
                                }
                            }
                            
                            Binding {
                                target: window
                                property: "videoVolume"
                                value: videoPlayer.volume
                            }
                        }
                    }
                }
                // Audio player component - wrapped in Loader for proper recreation
                Loader {
                    id: audioPlayerLoader
                    anchors.fill: parent
                    active: false
                    visible: window.isAudio && window.currentImage !== ""
                    
                    sourceComponent: Component {
                        AudioPlayer {
                            id: audioPlayer
                            anchors.fill: parent
                            source: window.currentImage
                            volume: window.audioVolume
                            showControls: true
                            coverArt: window.audioCoverArt
                            accentColor: window.accentColor
                            foregroundColor: window.foregroundColor
                            showingMetadata: window.showingMetadata
                            betaAudioProcessingEnabled: window.betaAudioProcessingEnabled
                            
                            onDurationAvailable: {
                                if (audioPlayer.duration > 0) {
                                    console.log("[Audio] Duration available:", audioPlayer.duration, "ms")
                                    // Debounce: Only update if duration changed significantly
                                    // This prevents infinite loops from rapid duration updates
                                    const lastDuration = window.lastAudioDuration || 0
                                    if (Math.abs(audioPlayer.duration - lastDuration) > 100) {
                                        window.lastAudioDuration = audioPlayer.duration
                                        window.logLoadDuration("Audio ready", audioPlayer.source)
                                        // Get format info with the actual duration (async to avoid blocking)
                                        Qt.callLater(function() {
                                            window.getAudioFormatInfo(audioPlayer.duration)
                                        })
                                        // Extract cover art when duration is available (metadata should be ready)
                                        window.extractAudioCoverArt()
                                        // Always refresh metadata list when duration is available
                                        Qt.callLater(function() {
                                            if (metadataPopup) {
                                                metadataPopup.metadataList = window.getMetadataList()
                                            }
                                        })
                                    }
                                }
                            }
                            
                            Connections {
                                target: window
                                function onAudioCoverArtChanged() {
                                    // Cover art is already bound via coverArt: window.audioCoverArt
                                    // Just update accent color when cover art changes
                                    if (window.audioCoverArt !== "") {
                                        Qt.callLater(function() {
                                            window.updateAccentColor()
                                        })
                                    }
                                }
                            }
                            
                            Binding {
                                target: window
                                property: "audioVolume"
                                value: audioPlayer.volume
                            }
                        }
                    }
                }
                
                // Markdown viewer component - wrapped in Loader for proper recreation
                Loader {
                    id: markdownViewerLoader
                    anchors.fill: parent
                    active: false
                    visible: window.isMarkdown && window.currentImage !== ""
                    
                    sourceComponent: Component {
                        MarkdownViewer {
                            id: markdownViewer
                            anchors.fill: parent
                            source: window.currentImage
                            accentColor: window.accentColor
                            foregroundColor: window.foregroundColor
                            
                            onContentChanged: {
                                if (window.isMarkdown && markdownViewer.content !== "" && markdownViewer.source !== "") {
                                    window.logLoadDuration("Markdown ready", markdownViewer.source)
                                }
                            }
                        }
                    }
                }
                
                // Text viewer component - wrapped in Loader for proper recreation
                Loader {
                    id: textViewerLoader
                    anchors.fill: parent
                    active: false
                    visible: window.isText && window.currentImage !== ""
                    
                    sourceComponent: Component {
                        TextViewer {
                            id: textViewer
                            anchors.fill: parent
                            source: window.currentImage
                            accentColor: window.accentColor
                            foregroundColor: window.foregroundColor
                            
                            onSaved: {
                                saveToast.show("File saved successfully", false)
                            }
                            
                            onSaveError: function(message) {
                                saveToast.show(message, true)
                            }
                            
                            onContentLoaded: {
                                if (window.isText && textViewer.content !== "" && textViewer.source !== "") {
                                    window.logLoadDuration("Text ready", textViewer.source)
                                }
                            }
                        }
                    }
                }
                
                // PDF viewer component - wrapped in Loader for proper recreation
                Loader {
                    id: pdfViewerLoader
                    anchors.fill: parent
                    active: false
                    visible: window.isPdf && window.currentImage !== ""
                    
                    sourceComponent: Component {
                        PdfViewer {
                            id: pdfViewer
                            anchors.fill: parent
                            source: window.currentImage
                            accentColor: window.accentColor
                            foregroundColor: window.foregroundColor
                            
                            onLoaded: {
                                window.logLoadDuration("PDF ready", pdfViewer.source)
                                if (window.showingMetadata) {
                                    Qt.callLater(function() {
                                        if (metadataPopup) {
                                            metadataPopup.metadataList = window.getMetadataList()
                                        }
                                    })
                                }
                            }
                        }
                    }
                }
                
                // Save toast notification
                Rectangle {
                    id: saveToast
                    anchors.bottom: parent.bottom
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottomMargin: 32
                    width: toastText.width + 32
                    height: 40
                    radius: 20
                    color: toastError ? Qt.rgba(200, 50, 50, 0.9) : Qt.rgba(50, 150, 50, 0.9)
                    opacity: 0
                    visible: opacity > 0
                    z: 100
                    
                    property bool toastError: false
                    
                    function show(message, isError) {
                        toastText.text = message
                        toastError = isError
                        toastAnimation.restart()
                    }
                    
                    Text {
                        id: toastText
                        anchors.centerIn: parent
                        color: "#ffffff"
                        font.pixelSize: 14
                        font.family: "Segoe UI"
                    }
                    
                    SequentialAnimation {
                        id: toastAnimation
                        NumberAnimation { target: saveToast; property: "opacity"; to: 1; duration: 200 }
                        PauseAnimation { duration: 2000 }
                        NumberAnimation { target: saveToast; property: "opacity"; to: 0; duration: 300 }
                    }
                }

                Rectangle {
                    anchors.fill: parent
                    color: Qt.rgba(window.accentColor.r, window.accentColor.g, window.accentColor.b, 0.25)
                    visible: window.dropActive
                    border.color: Qt.rgba(window.accentColor.r, window.accentColor.g, window.accentColor.b, 0.5)
                    border.width: 2
                }

                Text {
                    anchors.centerIn: parent
                    visible: window.currentImage === ""
                    color: window.dropActive ? "#050505" : window.foregroundColor
                    font.pixelSize: 22
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: window.dropActive ? qsTr("Drop media to open") : qsTr("Drag & drop media\nor press Ctrl+O")
                }
            }
        }

        SettingsPage {
            id: settingsPage
            Layout.fillWidth: true
            Layout.fillHeight: true
            accentColor: window.accentColor
            foregroundColor: window.foregroundColor
            dynamicColoringEnabled: window.dynamicColoringEnabled
            gradientBackgroundEnabled: window.gradientBackgroundEnabled
            backdropBlurEnabled: window.backdropBlurEnabled
            ambientGradientEnabled: window.ambientGradientEnabled
            snowEffectEnabled: window.snowEffectEnabled
            
            onBackClicked: window.showingSettings = false
            onDynamicColoringToggled: function(enabled) {
                window.dynamicColoringEnabled = enabled
                window.updateAccentColor()
            }
            onGradientBackgroundToggled: function(enabled) {
                window.gradientBackgroundEnabled = enabled
                if (enabled) {
                    window.backdropBlurEnabled = false  // Disable backdrop blur when gradient is enabled
                    window.ambientGradientEnabled = false  // Disable ambient gradient when gradient is enabled
                    // Snow can layer on top, so don't disable it
                }
                window.updateAccentColor()
            }
            onBackdropBlurToggled: function(enabled) {
                window.backdropBlurEnabled = enabled
                if (enabled) {
                    window.gradientBackgroundEnabled = false  // Disable gradient when backdrop blur is enabled
                    window.ambientGradientEnabled = false  // Disable ambient gradient when backdrop blur is enabled
                    // Snow can layer on top, so don't disable it
                }
            }
            onAmbientGradientToggled: function(enabled) {
                window.ambientGradientEnabled = enabled
                if (enabled) {
                    window.gradientBackgroundEnabled = false  // Disable gradient when ambient gradient is enabled
                    window.backdropBlurEnabled = false  // Disable backdrop blur when ambient gradient is enabled
                    // Snow can layer on top, so don't disable it
                }
            }
            onSnowEffectToggled: function(enabled) {
                window.snowEffectEnabled = enabled
                // Snow can layer on top of other effects, so no need to disable them
            }
        }
    }

    FileDialog {
        id: openDialog
        title: qsTr("Select media")
        fileMode: FileDialog.OpenFile
        nameFilters: [
            qsTr("All Supported (*.png *.jpg *.jpeg *.bmp *.gif *.webp *.mp4 *.avi *.mov *.mkv *.webm *.m4v *.mp3 *.wav *.flac *.ogg *.aac *.m4a *.wma *.opus *.md *.markdown *.txt *.log *.json *.xml *.yaml *.yml *.csv *.html *.css *.js *.ts *.cpp *.c *.h *.hpp *.py *.java *.qml *.rs *.go *.rb *.php *.sh *.sql *.pdf)"),
            qsTr("Images (*.png *.jpg *.jpeg *.bmp *.gif *.webp)"),
            qsTr("Videos (*.mp4 *.avi *.mov *.mkv *.webm *.m4v *.flv *.wmv *.mpg *.mpeg *.3gp)"),
            qsTr("Audio (*.mp3 *.wav *.flac *.ogg *.aac *.m4a *.wma *.opus *.mp2 *.mp1 *.amr)"),
            qsTr("PDF Documents (*.pdf)"),
            qsTr("Markdown (*.md *.markdown *.mdown *.mkd *.mkdn)"),
            qsTr("Code - Web (*.html *.htm *.css *.scss *.sass *.less *.js *.jsx *.ts *.tsx *.vue *.svelte *.json)"),
            qsTr("Code - C/C++/Qt (*.c *.cpp *.cc *.cxx *.h *.hpp *.hxx *.qml *.qrc *.pro *.pri *.ui)"),
            qsTr("Code - Python (*.py *.pyw *.pyx *.pyi)"),
            qsTr("Code - Java/Kotlin (*.java *.kt *.kts *.gradle)"),
            qsTr("Code - Other (*.rs *.go *.rb *.php *.swift *.cs *.fs *.scala *.lua *.pl *.r *.dart *.sh *.bat *.ps1 *.sql)"),
            qsTr("Config (*.ini *.cfg *.conf *.env *.yaml *.yml *.toml *.xml *.properties)"),
            qsTr("Text (*.txt *.log *.nfo *.csv *.diff *.patch)"),
            qsTr("All files (*)")
        ]
        onAccepted: {
            logToDebugConsole("[QML] FileDialog accepted, setting currentImage: " + selectedFile.toString(), "info")
            // Ensure window is visible when loading file
            if (!window.visible) {
                window.show()
                window.raise()
            }
            window.currentImage = selectedFile
        }
    }

    Shortcut {
        sequences: [ StandardKey.Open ]
        onActivated: openDialog.open()
    }
    
    // Image navigation shortcuts
    Shortcut {
        sequence: "Left"
        enabled: window.isImageType && window.directoryImages.length > 1
        onActivated: window.previousImage()
    }
    
    Shortcut {
        sequence: "Right"
        enabled: window.isImageType && window.directoryImages.length > 1
        onActivated: window.nextImage()
    }
    
    Shortcut {
        sequence: "Home"
        enabled: window.isImageType && window.directoryImages.length > 1
        onActivated: window.navigateToImage(0)
    }
    
    Shortcut {
        sequence: "End"
        enabled: window.isImageType && window.directoryImages.length > 1
        onActivated: window.navigateToImage(window.directoryImages.length - 1)
    }

    // Handle close event - minimize to tray instead of closing
    onClosing: function(close) {
        if (isMainWindow) {
            // Main window: minimize to tray
            // Prevent close FIRST - this is critical
            close.accepted = false
            
            // Mark that we're hiding with media (if any)
            wasHiddenWithMedia = (currentImage !== "")
            
            // HIDE WINDOW FIRST, then unload media
            // This ensures the window disappears immediately
            window.visible = false
            window.hide()
            
            // Unload media after hiding (this can happen in background)
            unloadMedia()
        } else {
            // Secondary window: WINDOW POOLING - hide instead of destroy
            // Prevent close - we want to hide, not destroy (window pooling)
            close.accepted = false
            
            // Unload media before hiding (this clears image content)
            unloadMedia()
            
            // Hide the window - window stays alive and can be reused later (window pooling)
            // NOTE: currentImage is already cleared by unloadMedia()
            // NOTE: Busy flag will be updated when window is reused (in resetForReuse)
            window.visible = false
            window.hide()
        }
    }

    // Track if window was hidden with media loaded
    property bool wasHiddenWithMedia: false
    
    onVisibleChanged: {
        if (visible && wasHiddenWithMedia) {
            // Window is being shown after being hidden with media
            // Clear any residual media immediately
            wasHiddenWithMedia = false
            unloadMedia()
        }
    }
    
    // When secondary window is about to be destroyed, ensure everything is cleaned up
    Component.onDestruction: {
        if (!isMainWindow) {
            // Final cleanup before destruction - clear all references
            _isUnloading = true
            currentImage = ""
            initialImage = ""
            directoryImages = []
            currentImageIndex = 0
            audioCoverArt = ""
            audioFormatInfo = { sampleRate: 0, bitrate: 0 }
            
            // Clear all media components
            unloadAllViewers()
            
            // Clear Qt image cache one more time
            if (typeof ColorUtils !== "undefined" && ColorUtils.clearImageCache) {
                ColorUtils.clearImageCache()
            }
        }
    }

    // Function to reset window state for reuse (called by C++ before reusing)
    function resetForReuse() {
        logToDebugConsole("[QML] resetForReuse() called - resetting window state", "info")
        
        // CRITICAL: Set unloading flag to prevent onCurrentImageChanged from loading
        // when C++ sets currentImage to empty (which happens before setting new image)
        _isUnloading = true
        
        // CRITICAL: Unload all viewers via Loaders to destroy components
        // This ensures proper cleanup and allows recreation on next load
        unloadAllViewers()
        
        // Clear unloading flag AFTER unload is complete - next image load will work
        // This flag will be cleared when the new image is set (onCurrentImageChanged will handle it)
        
        // Reset media type flags
        isVideo = false
        isGif = false
        isAudio = false
        isMarkdown = false
        isText = false
        isPdf = false
        
        // Clear media properties
        directoryImages = []
        currentImageIndex = 0
        audioCoverArt = ""
        audioFormatInfo = { sampleRate: 0, bitrate: 0 }
        
        logToDebugConsole("[QML] resetForReuse() complete - window ready for new image", "info")
    }

    Component.onCompleted: {
        // CRITICAL: Limit Qt's global image cache to prevent excessive RAM usage
        // This alone can cut RAM growth in half
        Qt.imageCacheSize = 32 * 1024 * 1024  // 32 MB (can be increased to 64 MB if needed)
        logToDebugConsole("[App] Set Qt.imageCacheSize to 32 MB", "info")
        
        // Test logging to verify debug console is working
        console.log("[App] Application started - Component.onCompleted")
        logToDebugConsole("[App] Application started", "info")
        
        // Check debug console connection (it might be set later by main.cpp)
        Qt.callLater(function() {
            if (debugConsole) {
                logToDebugConsole("[App] Debug console connected", "info")
            } else {
                console.log("[App] WARNING: Debug console not connected yet (will be set by main.cpp)")
                // Try again after a short delay
                Qt.callLater(function() {
                    if (debugConsole) {
                        logToDebugConsole("[App] Debug console connected (delayed)", "info")
                    } else {
                        console.log("[App] ERROR: Debug console still not connected")
                    }
                }, 100)
            }
        })
        
        // CRITICAL: Do NOT load from initialImage here - loading happens ONLY via onCurrentImageChanged
        // This ensures windows can be reused properly (Component.onCompleted only runs once)
        // If initialImage was set, it will be copied to currentImage by C++ after window creation
        if (initialImage !== "") {
            // Only set currentImage if initialImage was provided (for first-time creation)
            // This triggers onCurrentImageChanged which handles the actual loading
            currentImage = initialImage
        } else {
            updateAccentColor()
    }
}

    // Bass pulse window - transparent window with pulsing rounded rectangles
    BassPulseWindow {
        id: bassPulseWindow
        mainWindow: window
        bassAmplitude: (window.isAudio && audioPlayerLoader.item && audioPlayerLoader.item.analyzer) ? (audioPlayerLoader.item.analyzer.bassAmplitude || 0.0) : 0.0
        enabled: window.isAudio && audioPlayerLoader.item && audioPlayerLoader.item.analyzer && audioPlayerLoader.item.analyzer.active && audioPlayerLoader.item.analyzer.bassAmplitude > 0.1
        pulseColor: accentColor  // Use dynamic accent color
        
        onVisibleChanged: {
            if (visible) {
                // Ensure main window stays on top
                Qt.callLater(function() {
                    window.raise()
                    window.requestActivate()
                })
            }
        }
    }
    
    // Keep main window on top when bass pulse is visible (less frequent to avoid flicker)
    Timer {
        interval: 500
        running: bassPulseWindow.visible
        repeat: true
        onTriggered: {
            if (bassPulseWindow.visible) {
                window.raise()
            }
        }
    }
}


