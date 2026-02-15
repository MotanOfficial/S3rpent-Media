import QtMultimedia
import QtQuick
import QtQuick.Controls
import Qt5Compat.GraphicalEffects

// MediaViewerLoaders component - encapsulates all media viewer Loader components
// This includes ImageViewer, VideoPlayer, AudioPlayer, MarkdownViewer, TextViewer, PdfViewer, ZipViewer, and ModelViewer
Item {
    id: mediaViewerLoaders
    
    // Required properties from window
    required property var appWindow
    required property var resizeTimers
    required property var metadataPopup
    property var metadataPopupManager: null  // Optional: MetadataPopupManager for advanced updates
    
    anchors.fill: parent
    
    // When appWindow becomes available, update any existing items
    onAppWindowChanged: {
        if (appWindow) {
            if (viewerLoader.item) {
                viewerLoader.item.windowRef = appWindow
                viewerLoader.item.resizeTimersRef = resizeTimers
                viewerLoader.item.source = appWindow.currentImage
                viewerLoader.item.isGif = appWindow.isGif
                viewerLoader.item.zoomFactor = appWindow.zoomFactor
                viewerLoader.item.panX = appWindow.panX
                viewerLoader.item.panY = appWindow.panY
                viewerLoader.item.accentColor = appWindow.accentColor
                viewerLoader.item.imageInterpolationMode = appWindow.imageInterpolationMode
                viewerLoader.item.dynamicResolutionEnabled = appWindow.dynamicResolutionEnabled
            }
            if (videoPlayerLoader.item) {
                videoPlayerLoader.item.windowRef = appWindow
                videoPlayerLoader.item.resizeTimersRef = resizeTimers
                videoPlayerLoader.item.source = appWindow.currentImage
                // Don't set volume here - VideoPlayer's Settings component will load the saved volume automatically
                videoPlayerLoader.item.accentColor = appWindow.accentColor
                videoPlayerLoader.item.foregroundColor = appWindow.foregroundColor
            }
            if (audioPlayerLoader.item) {
                audioPlayerLoader.item.source = appWindow.currentImage
                // Don't set volume here - CustomAudioPlayer loads the saved volume from Settings automatically
                // coverArt, accentColor, and foregroundColor are bound via Bindings in the Component
                audioPlayerLoader.item.showingMetadata = appWindow.showingMetadata
                audioPlayerLoader.item.lyricsTranslationEnabled = appWindow.lyricsTranslationEnabled
                audioPlayerLoader.item.lyricsTranslationApiKey = appWindow.lyricsTranslationApiKey
                audioPlayerLoader.item.lyricsTranslationTargetLanguage = appWindow.lyricsTranslationTargetLanguage
                audioPlayerLoader.item.betaAudioProcessingEnabled = appWindow.betaAudioProcessingEnabled
            }
            if (markdownViewerLoader.item) {
                markdownViewerLoader.item.source = appWindow.currentImage
                // accentColor and foregroundColor are bound via Bindings in the Component
            }
            if (textViewerLoader.item) {
                textViewerLoader.item.source = appWindow.currentImage
                // accentColor and foregroundColor are bound via Bindings in the Component
            }
            if (pdfViewerLoader.item) {
                pdfViewerLoader.item.source = appWindow.currentImage
                // accentColor and foregroundColor are bound via Bindings in the Component
            }
            if (zipViewerLoader.item) {
                zipViewerLoader.item.source = appWindow.currentImage
                // accentColor and foregroundColor are bound via Bindings in the Component
            }
            if (modelViewerLoader.item) {
                modelViewerLoader.item.source = appWindow.currentImage
                // accentColor and foregroundColor are bound via Bindings in the Component
            }
        }
    }
    
    // Image viewer component - wrapped in Loader to allow recreation on reuse
    // CRITICAL: Loader recreates the ImageViewer each time, ensuring proper scene graph rebinding
    // This fixes the issue where Image/AnimatedImage don't reload after window hide/show
    Loader {
        id: viewerLoader
        anchors.fill: parent
        active: false
        visible: appWindow ? (!appWindow.isVideo && !appWindow.isAudio && !appWindow.isMarkdown && !appWindow.isText && !appWindow.isPdf && !appWindow.isZip && !appWindow.isModel && appWindow.currentImage !== "") : false
        
        
        onItemChanged: {
            if (item) {
                const win = mediaViewerLoaders.appWindow
                const timers = mediaViewerLoaders.resizeTimers
                if (win) {
                    item.windowRef = win
                    item.resizeTimersRef = timers
                    item.source = win.currentImage
                    item.isGif = win.isGif
                    item.zoomFactor = win.zoomFactor
                    item.panX = win.panX
                    item.panY = win.panY
                    item.accentColor = win.accentColor
                    item.imageInterpolationMode = win.imageInterpolationMode
                    item.dynamicResolutionEnabled = win.dynamicResolutionEnabled
                } else {
                    // If appWindow isn't available yet, try again later
                    Qt.callLater(function() {
                        const win2 = mediaViewerLoaders.appWindow
                        const timers2 = mediaViewerLoaders.resizeTimers
                        if (item && win2) {
                            item.windowRef = win2
                            item.resizeTimersRef = timers2
                            item.source = win2.currentImage
                            item.isGif = win2.isGif
                            item.zoomFactor = win2.zoomFactor
                            item.panX = win2.panX
                            item.panY = win2.panY
                            item.accentColor = win2.accentColor
                            item.imageInterpolationMode = win2.imageInterpolationMode
                            item.dynamicResolutionEnabled = win2.dynamicResolutionEnabled
                        }
                    })
                }
            }
        }
        
        sourceComponent: Component {
            ImageViewer {
                id: imageViewer
                anchors.fill: parent
                
                
                onImageReady: {
                    if (!windowRef) return
                    // Log duration FIRST so image appears immediately
                    windowRef.logLoadDuration(windowRef.isGif ? "GIF ready" : "Image ready", imageViewer.source)
                    // Then update accent color after a short delay (doesn't block image display)
                    accentColorTimer.restart()
                    
                    // Resize window to match aspect ratio if enabled
                    // Wait a bit for sourceWidth/sourceHeight to be available
                    if (windowRef && windowRef.matchMediaAspectRatio && windowRef.visibility !== Window.Maximized && windowRef.visibility !== Window.FullScreen) {
                        Qt.callLater(function() {
                            // Check if dimensions are available now
                            if (imageViewer.sourceWidth > 0 && imageViewer.sourceHeight > 0) {
                                if (imageViewer.resizeTimersRef) imageViewer.resizeTimersRef.resizeAspectTimer.restart()
                            } else {
                                // Retry after a short delay
                                Qt.callLater(function() {
                                    if (imageViewer.sourceWidth > 0 && imageViewer.sourceHeight > 0) {
                                        if (imageViewer.resizeTimersRef) imageViewer.resizeTimersRef.resizeAspectTimer.restart()
                                    }
                                }, 50)
                            }
                        }, 50)
                    }
                    
                    // Log memory after image loads
                    Qt.callLater(function() {
                        if (typeof ColorUtils !== "undefined" && ColorUtils.getMemoryUsage) {
                            const memAfter = ColorUtils.getMemoryUsage()
                            if (windowRef) windowRef.logToDebugConsole("[Memory] After image load: " + memAfter.toFixed(2) + " MB", "info")
                        }
                    })
                }
                
                onPaintedSizeChanged: {
                    if (!windowRef) return
                    windowRef.clampPan()
                    // Resize window to match aspect ratio if enabled (dimensions now available)
                    // Use a timer to debounce rapid size changes and prevent infinite loops
                    // Only resize if image is ready (status === Image.Ready = 2) and dimensions are available
                    if (windowRef.matchMediaAspectRatio && windowRef.currentImage !== "" && windowRef.visibility !== Window.Maximized && windowRef.visibility !== Window.FullScreen && !windowRef.isResizing) {
                        // We're inside the ImageViewer, so we can reference it directly
                        const imageStatus = imageViewer.status
                        const isReady = (imageStatus === 2) // Image.Ready = 2
                        
                        // Only resize if image is ready and dimensions are available
                        if (isReady && imageViewer.sourceWidth > 0 && imageViewer.sourceHeight > 0) {
                            if (imageViewer.resizeTimersRef) imageViewer.resizeTimersRef.resizeAspectTimer.restart()
                        }
                    }
                }
                
                Binding {
                    target: windowRef || null
                    property: "zoomFactor"
                    value: imageViewer.zoomFactor
                    when: windowRef ? (!windowRef.isVideo && !windowRef.isAudio && !windowRef.isMarkdown && !windowRef.isText && !windowRef.isPdf && !windowRef.isZip && !windowRef.isModel) : false
                }
                
                Binding {
                    target: windowRef || null
                    property: "panX"
                    value: imageViewer.panX
                    when: windowRef ? (!windowRef.isVideo && !windowRef.isAudio && !windowRef.isMarkdown && !windowRef.isText && !windowRef.isPdf && !windowRef.isZip && !windowRef.isModel) : false
                }
                
                Binding {
                    target: windowRef || null
                    property: "panY"
                    value: imageViewer.panY
                    when: windowRef ? (!windowRef.isVideo && !windowRef.isAudio && !windowRef.isMarkdown && !windowRef.isText && !windowRef.isPdf && !windowRef.isZip && !windowRef.isModel) : false
                }
                
                // Binding to keep dynamicResolutionEnabled in sync with window
                Binding {
                    target: imageViewer
                    property: "dynamicResolutionEnabled"
                    value: windowRef ? windowRef.dynamicResolutionEnabled : true
                    when: windowRef ? true : false
                }
                
                Timer {
                    id: accentColorTimer
                    interval: 50  // Small delay to let image render first
                    onTriggered: {
                        if (windowRef) windowRef.updateAccentColor()
                    }
                }
            }
        }
    }
    
    // Image controls bar
    ImageControls {
        id: imageControls
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottomMargin: 32
        width: Math.min(500, parent.width - 48)
        height: 56
        z: 50
        
        currentIndex: appWindow ? appWindow.currentImageIndex : 0
        totalImages: appWindow ? appWindow.directoryImages.length : 0
        zoomFactor: appWindow ? appWindow.zoomFactor : 1.0
        accentColor: appWindow ? appWindow.accentColor : "#1e1e1e"
        directoryImages: appWindow ? appWindow.directoryImages : []
        imageControlsHideTimer: imageControlsHideTimer
        
        onThumbnailNavigationRequested: function(index) {
            if (appWindow && appWindow.navigateToImage) {
                appWindow.navigateToImage(index)
                imageControlsHideTimer.restart()
            }
        }
        
        onPreviousClicked: {
            if (appWindow) appWindow.previousImage()
            imageControlsHideTimer.restart()
        }
        onNextClicked: {
            if (appWindow) appWindow.nextImage()
            imageControlsHideTimer.restart()
        }
        onZoomInClicked: {
            if (appWindow) appWindow.adjustZoom(100)
            imageControlsHideTimer.restart()
        }
        onZoomOutClicked: {
            if (appWindow) appWindow.adjustZoom(-100)
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
        property bool shouldBeVisible: appWindow ? (appWindow.isImageType && appWindow.showImageControls && appWindow.currentImage.toString() !== "" && !appWindow.showingSettings && !appWindow.showingMetadata) : false
        
        opacity: shouldBeVisible ? 1 : 0
        visible: opacity > 0  // Keep visible during fade-out animation
        
        Behavior on opacity { 
            NumberAnimation { 
                duration: 300
                easing.type: Easing.OutCubic
            } 
        }
    }
    
    // Background overlay to close thumbnail popup when clicking outside
    Rectangle {
        id: thumbnailPopupOverlay
        anchors.fill: parent
        color: "transparent"
        visible: imageControls.thumbnailPopupVisible
        z: 49  // Below the popup (z: 200) but above other content
        
        TapHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            gesturePolicy: TapHandler.ReleaseWithinBounds
            onTapped: {
                if (imageControls.thumbnailPopupVisible) {
                    imageControls.hideThumbnailPopup()
                }
            }
        }
    }
    
    // Auto-hide timer for image controls
    Timer {
        id: imageControlsHideTimer
        interval: 3000
        onTriggered: {
            if (appWindow) appWindow.showImageControls = false
        }
    }
    
    // Image navigation arrows and preloaders - now using ImageNavigationArrows.qml component
    ImageNavigationArrows {
        anchors.fill: parent
        appWindow: mediaViewerLoaders.appWindow
        imageControlsHideTimer: imageControlsHideTimer
    }

    // Video player component - wrapped in Loader for proper recreation
    Loader {
        id: videoPlayerLoader
        anchors.fill: parent
        active: false
        visible: appWindow ? (appWindow.isVideo && appWindow.currentImage !== "") : false
        
        onItemChanged: {
            if (item) {
                const win = mediaViewerLoaders.appWindow
                const timers = mediaViewerLoaders.resizeTimers
                if (win) {
                    item.windowRef = win
                    item.resizeTimersRef = timers
                    item.source = win.currentImage
                    // Don't set volume here - VideoPlayer's Settings component will load the saved volume automatically
                    item.showControls = true
                    // accentColor and foregroundColor should be bound, but set initial values
                    item.accentColor = win.accentColor
                    item.foregroundColor = win.foregroundColor
                } else {
                    // If appWindow isn't available yet, try again later
                    Qt.callLater(function() {
                        const win2 = mediaViewerLoaders.appWindow
                        const timers2 = mediaViewerLoaders.resizeTimers
                        if (item && win2) {
                            item.windowRef = win2
                            item.resizeTimersRef = timers2
                            item.source = win2.currentImage
                            // Don't set volume here - VideoPlayer's Settings component will load the saved volume automatically
                            item.showControls = true
                            item.accentColor = win2.accentColor
                            item.foregroundColor = win2.foregroundColor
                        }
                    })
                }
            }
        }
        
        sourceComponent: Component {
            VideoPlayer {
                id: videoPlayer
                anchors.fill: parent
                
                onDurationAvailable: {
                    if (!windowRef) return
                    if (videoPlayer.duration > 0) {
                        windowRef.logLoadDuration("Video ready", videoPlayer.source)
                        
                        // Try to resize window to match aspect ratio if enabled
                        // Dimensions might not be available yet, so we'll retry with a delay
                        if (windowRef.matchMediaAspectRatio && windowRef.visibility !== Window.Maximized && windowRef.visibility !== Window.FullScreen) {
                            // Try immediately if dimensions are available
                            if (videoPlayer.implicitWidth > 0 && videoPlayer.implicitHeight > 0) {
                                if (videoPlayer.resizeTimersRef) videoPlayer.resizeTimersRef.resizeAspectTimer.restart()
                            } else {
                                // Retry after a short delay when dimensions become available
                                Qt.callLater(function() {
                                    if (videoPlayer.implicitWidth > 0 && videoPlayer.implicitHeight > 0) {
                                        if (videoPlayer.resizeTimersRef) videoPlayer.resizeTimersRef.resizeAspectTimer.restart()
                                    } else {
                                        // One more retry after video has had time to load
                                        if (videoPlayer.resizeTimersRef) videoPlayer.resizeTimersRef.videoDimensionRetryTimer.restart()
                                    }
                                })
                            }
                        }
                        
                        if (windowRef && windowRef.showingMetadata) {
                            Qt.callLater(function() {
                        if (windowRef && mediaViewerLoaders.metadataPopup) {
                            mediaViewerLoaders.metadataPopup.metadataList = windowRef.getMetadataList()
                        }
                            })
                        }
                    }
                }
                
                // Watch for video dimensions becoming available
                Connections {
                    target: videoPlayer
                    function onImplicitWidthChanged() {
                        if (windowRef && windowRef.matchMediaAspectRatio && windowRef.isVideo && windowRef.currentImage !== "" && 
                            windowRef.visibility !== Window.Maximized && windowRef.visibility !== Window.FullScreen &&
                            videoPlayer.implicitWidth > 0 && videoPlayer.implicitHeight > 0) {
                            if (videoPlayer.resizeTimersRef) videoPlayer.resizeTimersRef.resizeAspectTimer.restart()
                        }
                    }
                    function onImplicitHeightChanged() {
                        if (windowRef && windowRef.matchMediaAspectRatio && windowRef.isVideo && windowRef.currentImage !== "" && 
                            windowRef.visibility !== Window.Maximized && windowRef.visibility !== Window.FullScreen &&
                            videoPlayer.implicitWidth > 0 && videoPlayer.implicitHeight > 0) {
                            if (videoPlayer.resizeTimersRef) videoPlayer.resizeTimersRef.resizeAspectTimer.restart()
                        }
                    }
                }
                
                onHasAudioChanged: {
                    if (windowRef) {
                        // Force update - especially important for webm files
                        windowRef.videoHasNoAudio = !videoPlayer.hasAudio
                    }
                }
                
                Component.onCompleted: {
                    // Check initial audio state
                    if (windowRef) {
                        windowRef.videoHasNoAudio = !videoPlayer.hasAudio
                    }
                    // Also check after a delay to ensure WMF player has loaded
                    Qt.callLater(function() {
                        if (windowRef && videoPlayer) {
                            windowRef.videoHasNoAudio = !videoPlayer.hasAudio
                        }
                    }, 500)
                }
                
                // Binding to keep accentColor in sync with appWindow.accentColor
                Binding {
                    target: videoPlayer
                    property: "accentColor"
                    value: windowRef ? windowRef.accentColor : "#121216"
                    when: windowRef ? true : false
                }
                
                // Binding to keep foregroundColor in sync with appWindow.foregroundColor
                Binding {
                    target: videoPlayer
                    property: "foregroundColor"
                    value: windowRef ? windowRef.foregroundColor : "#f5f5f5"
                    when: windowRef ? true : false
                }
                
                Binding {
                    target: windowRef || null
                    property: "videoVolume"
                    value: videoPlayer.volume
                    when: windowRef ? true : false
                }
            }
        }
    }
    
    // No audio notification - shown at top when video has no audio
    Rectangle {
        id: noAudioNotification
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.topMargin: 24
        width: Math.min(300, parent.width - 48)
        height: 40
        radius: 20
        color: Qt.rgba(0, 0, 0, 0.7)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.2)
        property bool shouldShow: appWindow ? (appWindow.isVideo && appWindow.videoHasNoAudio && appWindow.currentImage !== "" && !appWindow.showingSettings && !appWindow.showingMetadata) : false
        visible: shouldShow && opacity > 0
        opacity: shouldShow ? 1 : 0
        z: 100
        
        Behavior on opacity { NumberAnimation { duration: 300 } }
        
        // Timer to fade out after 4 seconds
        Timer {
            id: noAudioFadeTimer
            interval: 4000
            running: noAudioNotification.shouldShow && noAudioNotification.opacity > 0
            onTriggered: {
                noAudioNotification.opacity = 0
            }
        }
        
        // Restart timer when notification becomes visible
        onShouldShowChanged: {
            if (shouldShow) {
                opacity = 1
                noAudioFadeTimer.restart()
            }
        }
        
        Row {
            anchors.centerIn: parent
            spacing: 8
            
            Image {
                width: 18
                height: 18
                source: "qrc:/qlementine/icons/16/audio/speaker-mute.svg"
                sourceSize.width: 18
                sourceSize.height: 18
                fillMode: Image.PreserveAspectFit
                anchors.verticalCenter: parent.verticalCenter
                
                ColorOverlay {
                    anchors.fill: parent
                    source: parent
                    color: "#ffffff"
                }
            }
            
            Text {
                text: qsTr("No audio")
                font.pixelSize: 14
                font.family: "Segoe UI"
                font.weight: Font.Medium
                color: "#ffffff"
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }
    
    // Hardware decoder unavailable notification
    Rectangle {
        id: hardwareDecoderNotification
        anchors.top: noAudioNotification.visible ? noAudioNotification.bottom : parent.top
        anchors.topMargin: noAudioNotification.visible ? 8 : 24
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(350, parent.width - 48)
        height: 40
        radius: 20
        color: Qt.rgba(0, 0, 0, 0.7)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.2)
        property bool shouldShow: {
            if (!appWindow || !appWindow.isVideo || appWindow.currentImage === "" || appWindow.showingSettings || appWindow.showingMetadata) {
                return false
            }
            // Check if video player has hardware decoder unavailable flag
            const videoPlayer = videoPlayerLoader.item
            return videoPlayer ? videoPlayer.hardwareDecoderUnavailable : false
        }
        visible: shouldShow && opacity > 0
        opacity: shouldShow ? 1 : 0
        z: 99
        
        Behavior on opacity { NumberAnimation { duration: 300 } }
        
        // Timer to fade out after 4 seconds
        Timer {
            id: hardwareDecoderFadeTimer
            interval: 4000
            running: hardwareDecoderNotification.shouldShow && hardwareDecoderNotification.opacity > 0
            onTriggered: {
                hardwareDecoderNotification.opacity = 0
            }
        }
        
        // Restart timer when notification becomes visible
        onShouldShowChanged: {
            if (shouldShow) {
                opacity = 1
                hardwareDecoderFadeTimer.restart()
            }
        }
        
        Row {
            anchors.centerIn: parent
            spacing: 8
            
            Image {
                width: 18
                height: 18
                source: "qrc:/qlementine/icons/16/misc/warning.svg"
                sourceSize.width: 18
                sourceSize.height: 18
                fillMode: Image.PreserveAspectFit
                anchors.verticalCenter: parent.verticalCenter
                
                ColorOverlay {
                    anchors.fill: parent
                    source: parent
                    color: "#ffaa00"
                }
            }
            
            Text {
                text: qsTr("Hardware decoding unavailable")
                font.pixelSize: 14
                font.family: "Segoe UI"
                font.weight: Font.Medium
                color: "#ffffff"
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }
    
    // Audio player component - wrapped in Loader for proper recreation
    Loader {
        id: audioPlayerLoader
        anchors.fill: parent
        active: false
        visible: appWindow ? (appWindow.isAudio && appWindow.currentImage !== "") : false
        
        onItemChanged: {
            if (item) {
                const win = mediaViewerLoaders.appWindow
                if (win) {
                    item.source = win.currentImage
                    // Don't set volume here - CustomAudioPlayer loads the saved volume from Settings automatically
                    item.showControls = true
                    // coverArt, accentColor, and foregroundColor are bound via Bindings in the Component
                    // Set initial values for other properties
                    item.showingMetadata = win.showingMetadata
                    item.lyricsTranslationEnabled = win.lyricsTranslationEnabled
                    item.lyricsTranslationApiKey = win.lyricsTranslationApiKey
                    item.lyricsTranslationTargetLanguage = win.lyricsTranslationTargetLanguage
                    item.betaAudioProcessingEnabled = win.betaAudioProcessingEnabled
                    item.discordRPCEnabled = win.discordRPCEnabled
                    item.coverArtSource = win.coverArtSource
                    item.lastFMApiKey = win.lastFMApiKey
                } else {
                    // If appWindow isn't available yet, try again later
                    Qt.callLater(function() {
                        const win2 = mediaViewerLoaders.appWindow
                        if (item && win2) {
                            item.source = win2.currentImage
                            // Don't set volume here - CustomAudioPlayer loads the saved volume from Settings automatically
                            item.showControls = true
                            // coverArt, accentColor, and foregroundColor are bound via Bindings in the Component
                            // Set initial values for other properties
                            item.showingMetadata = win2.showingMetadata
                            item.lyricsTranslationEnabled = win2.lyricsTranslationEnabled
                            item.lyricsTranslationApiKey = win2.lyricsTranslationApiKey
                            item.lyricsTranslationTargetLanguage = win2.lyricsTranslationTargetLanguage
                            item.betaAudioProcessingEnabled = win2.betaAudioProcessingEnabled
                            item.discordRPCEnabled = win2.discordRPCEnabled
                            item.coverArtSource = win2.coverArtSource
                            item.lastFMApiKey = win2.lastFMApiKey
                        }
                    })
                }
            }
        }
        
        sourceComponent: Component {
            AudioPlayer {
                id: audioPlayer
                anchors.fill: parent
                
                onDurationAvailable: {
                    const win = mediaViewerLoaders.appWindow
                    if (!win) return
                    if (audioPlayer.duration > 0) {
                        // Debounce: Only update if duration changed significantly
                        // This prevents infinite loops from rapid duration updates
                        const lastDuration = win.lastAudioDuration || 0
                        if (Math.abs(audioPlayer.duration - lastDuration) > 100) {
                            win.lastAudioDuration = audioPlayer.duration
                            win.logLoadDuration("Audio ready", audioPlayer.source)
                            // Get format info with the actual duration (async to avoid blocking)
                            Qt.callLater(function() {
                                if (win) win.getAudioFormatInfo(audioPlayer.duration)
                            })
                            // Extract cover art when duration is available (metadata should be ready)
                            win.extractAudioCoverArt()
                            // Always refresh metadata list when duration is available
                            Qt.callLater(function() {
                                if (win) {
                                    // Try to update through MetadataPopupManager first (preferred)
                                    if (mediaViewerLoaders.metadataPopupManager && 
                                        typeof mediaViewerLoaders.metadataPopupManager.updateMetadataList === "function") {
                                        mediaViewerLoaders.metadataPopupManager.updateMetadataList()
                                    } else if (mediaViewerLoaders.metadataPopup) {
                                        // Fallback: direct update (for backwards compatibility)
                                        mediaViewerLoaders.metadataPopup.metadataList = win.getMetadataList()
                                    } else {
                                    }
                                }
                            })
                        }
                    }
                }
                
                // Binding to keep coverArt in sync with appWindow.audioCoverArt
                Binding {
                    target: audioPlayer
                    property: "coverArt"
                    value: mediaViewerLoaders.appWindow ? mediaViewerLoaders.appWindow.audioCoverArt : ""
                    when: mediaViewerLoaders.appWindow ? true : false
                }
                
                // Binding to keep accentColor in sync with appWindow.accentColor
                Binding {
                    target: audioPlayer
                    property: "accentColor"
                    value: mediaViewerLoaders.appWindow ? mediaViewerLoaders.appWindow.accentColor : "#121216"
                    when: mediaViewerLoaders.appWindow ? true : false
                }
                
                // Binding to keep foregroundColor in sync with appWindow.foregroundColor
                Binding {
                    target: audioPlayer
                    property: "foregroundColor"
                    value: mediaViewerLoaders.appWindow ? mediaViewerLoaders.appWindow.foregroundColor : "#f5f5f5"
                    when: mediaViewerLoaders.appWindow ? true : false
                }
                
                Connections {
                    target: mediaViewerLoaders.appWindow
                    function onAudioCoverArtChanged() {
                        const win = mediaViewerLoaders.appWindow
                        if (!win) return
                        // Update accent color when cover art changes
                        if (win.audioCoverArt !== "") {
                            Qt.callLater(function() {
                                if (win) win.updateAccentColor()
                            })
                        }
                    }
                }
                
                Binding {
                    target: mediaViewerLoaders.appWindow || null
                    property: "audioVolume"
                    value: audioPlayer.volume
                    when: mediaViewerLoaders.appWindow ? true : false
                }
                
                // Binding to keep discordRPCEnabled in sync with appWindow.discordRPCEnabled
                Binding {
                    target: audioPlayer
                    property: "discordRPCEnabled"
                    value: mediaViewerLoaders.appWindow ? mediaViewerLoaders.appWindow.discordRPCEnabled : true
                    when: mediaViewerLoaders.appWindow ? true : false
                }
                
                // Binding to keep coverArtSource in sync with appWindow.coverArtSource
                Binding {
                    target: audioPlayer
                    property: "coverArtSource"
                    value: mediaViewerLoaders.appWindow ? mediaViewerLoaders.appWindow.coverArtSource : "coverartarchive"
                    when: mediaViewerLoaders.appWindow ? true : false
                }
                
                // Binding to keep lastFMApiKey in sync with appWindow.lastFMApiKey
                Binding {
                    target: audioPlayer
                    property: "lastFMApiKey"
                    value: mediaViewerLoaders.appWindow ? mediaViewerLoaders.appWindow.lastFMApiKey : ""
                    when: mediaViewerLoaders.appWindow ? true : false
                }
            }
        }
    }
    
    // Markdown viewer component - wrapped in Loader for proper recreation
    Loader {
        id: markdownViewerLoader
        anchors.fill: parent
        active: false
        visible: appWindow ? (appWindow.isMarkdown && appWindow.currentImage !== "") : false
        
        onItemChanged: {
            if (item) {
                const win = mediaViewerLoaders.appWindow
                if (win) {
                    item.source = win.currentImage
                    item.accentColor = win.accentColor
                    item.foregroundColor = win.foregroundColor
                } else {
                    Qt.callLater(function() {
                        const win2 = mediaViewerLoaders.appWindow
                        if (item && win2) {
                            item.source = win2.currentImage
                            item.accentColor = win2.accentColor
                            item.foregroundColor = win2.foregroundColor
                        }
                    })
                }
            }
        }
        
        sourceComponent: Component {
            MarkdownViewer {
                id: markdownViewer
                anchors.fill: parent
                
                // Binding to keep accentColor in sync with appWindow.accentColor
                Binding {
                    target: markdownViewer
                    property: "accentColor"
                    value: mediaViewerLoaders.appWindow ? mediaViewerLoaders.appWindow.accentColor : "#1e1e1e"
                    when: mediaViewerLoaders.appWindow ? true : false
                }
                
                // Binding to keep foregroundColor in sync with appWindow.foregroundColor
                Binding {
                    target: markdownViewer
                    property: "foregroundColor"
                    value: mediaViewerLoaders.appWindow ? mediaViewerLoaders.appWindow.foregroundColor : "#f5f5f5"
                    when: mediaViewerLoaders.appWindow ? true : false
                }
                
                onContentChanged: {
                    const win = mediaViewerLoaders.appWindow
                    if (win && win.isMarkdown && markdownViewer.content !== "" && markdownViewer.source !== "") {
                        win.logLoadDuration("Markdown ready", markdownViewer.source)
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
        visible: appWindow ? (appWindow.isText && appWindow.currentImage !== "") : false
        
        onItemChanged: {
            if (item) {
                const win = mediaViewerLoaders.appWindow
                if (win) {
                    item.source = win.currentImage
                    item.accentColor = win.accentColor
                    item.foregroundColor = win.foregroundColor
                } else {
                    Qt.callLater(function() {
                        const win2 = mediaViewerLoaders.appWindow
                        if (item && win2) {
                            item.source = win2.currentImage
                            item.accentColor = win2.accentColor
                            item.foregroundColor = win2.foregroundColor
                        }
                    })
                }
            }
        }
        
        sourceComponent: Component {
            TextViewer {
                id: textViewer
                anchors.fill: parent
                
                // Binding to keep accentColor in sync with appWindow.accentColor
                Binding {
                    target: textViewer
                    property: "accentColor"
                    value: mediaViewerLoaders.appWindow ? mediaViewerLoaders.appWindow.accentColor : "#1e1e1e"
                    when: mediaViewerLoaders.appWindow ? true : false
                }
                
                // Binding to keep foregroundColor in sync with appWindow.foregroundColor
                Binding {
                    target: textViewer
                    property: "foregroundColor"
                    value: mediaViewerLoaders.appWindow ? mediaViewerLoaders.appWindow.foregroundColor : "#f5f5f5"
                    when: mediaViewerLoaders.appWindow ? true : false
                }
                
                onSaved: {
                    saveToast.show("File saved successfully", false)
                }
                
                onSaveError: function(message) {
                    saveToast.show(message, true)
                }
                
                onContentLoaded: {
                    const win = mediaViewerLoaders.appWindow
                    if (win && win.isText && textViewer.content !== "" && textViewer.source !== "") {
                        win.logLoadDuration("Text ready", textViewer.source)
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
        visible: appWindow ? (appWindow.isPdf && appWindow.currentImage !== "") : false
        
        onItemChanged: {
            if (item) {
                const win = mediaViewerLoaders.appWindow
                if (win) {
                    item.source = win.currentImage
                    item.accentColor = win.accentColor
                    item.foregroundColor = win.foregroundColor
                } else {
                    Qt.callLater(function() {
                        const win2 = mediaViewerLoaders.appWindow
                        if (item && win2) {
                            item.source = win2.currentImage
                            item.accentColor = win2.accentColor
                            item.foregroundColor = win2.foregroundColor
                        }
                    })
                }
            }
        }
        
        sourceComponent: Component {
            PdfViewer {
                id: pdfViewer
                anchors.fill: parent
                
                // Binding to keep accentColor in sync with appWindow.accentColor
                Binding {
                    target: pdfViewer
                    property: "accentColor"
                    value: mediaViewerLoaders.appWindow ? mediaViewerLoaders.appWindow.accentColor : "#1e1e1e"
                    when: mediaViewerLoaders.appWindow ? true : false
                }
                
                // Binding to keep foregroundColor in sync with appWindow.foregroundColor
                Binding {
                    target: pdfViewer
                    property: "foregroundColor"
                    value: mediaViewerLoaders.appWindow ? mediaViewerLoaders.appWindow.foregroundColor : "#f5f5f5"
                    when: mediaViewerLoaders.appWindow ? true : false
                }
                
                onLoaded: {
                    const win = mediaViewerLoaders.appWindow
                    if (!win) return
                    win.logLoadDuration("PDF ready", pdfViewer.source)
                    if (win.showingMetadata) {
                        Qt.callLater(function() {
                            if (win && mediaViewerLoaders.metadataPopup) {
                                mediaViewerLoaders.metadataPopup.metadataList = win.getMetadataList()
                            }
                        })
                    }
                }
            }
        }
    }

    // ZIP viewer component - wrapped in Loader for proper recreation
    Loader {
        id: zipViewerLoader
        anchors.fill: parent
        active: false
        visible: appWindow ? (appWindow.isZip && appWindow.currentImage !== "") : false

        onItemChanged: {
            if (item) {
                const win = mediaViewerLoaders.appWindow
                if (win) {
                    item.source = win.currentImage
                    item.accentColor = win.accentColor
                    item.foregroundColor = win.foregroundColor
                } else {
                    Qt.callLater(function() {
                        const win2 = mediaViewerLoaders.appWindow
                        if (item && win2) {
                            item.source = win2.currentImage
                            item.accentColor = win2.accentColor
                            item.foregroundColor = win2.foregroundColor
                        }
                    })
                }
            }
        }

        sourceComponent: Component {
            ZipViewer {
                id: zipViewer
                anchors.fill: parent

                Binding {
                    target: zipViewer
                    property: "accentColor"
                    value: mediaViewerLoaders.appWindow ? mediaViewerLoaders.appWindow.accentColor : "#1e1e1e"
                    when: mediaViewerLoaders.appWindow ? true : false
                }

                Binding {
                    target: zipViewer
                    property: "foregroundColor"
                    value: mediaViewerLoaders.appWindow ? mediaViewerLoaders.appWindow.foregroundColor : "#f5f5f5"
                    when: mediaViewerLoaders.appWindow ? true : false
                }

                onLoaded: {
                    const win = mediaViewerLoaders.appWindow
                    if (!win) return
                    win.logLoadDuration("ZIP ready", zipViewer.source)
                    if (win.showingMetadata) {
                        Qt.callLater(function() {
                            if (win && mediaViewerLoaders.metadataPopup) {
                                mediaViewerLoaders.metadataPopup.metadataList = win.getMetadataList()
                            }
                        })
                    }
                }
            }
        }
    }

    // 3D model viewer component - wrapped in Loader for proper recreation
    Loader {
        id: modelViewerLoader
        anchors.fill: parent
        active: false
        visible: appWindow ? (appWindow.isModel && appWindow.currentImage !== "") : false

        onItemChanged: {
            if (item) {
                const win = mediaViewerLoaders.appWindow
                if (win) {
                    item.source = win.currentImage
                    item.accentColor = win.accentColor
                    item.foregroundColor = win.foregroundColor
                } else {
                    Qt.callLater(function() {
                        const win2 = mediaViewerLoaders.appWindow
                        if (item && win2) {
                            item.source = win2.currentImage
                            item.accentColor = win2.accentColor
                            item.foregroundColor = win2.foregroundColor
                        }
                    })
                }
            }
        }

        sourceComponent: Component {
            ModelViewer {
                id: modelViewer
                anchors.fill: parent

                Binding {
                    target: modelViewer
                    property: "accentColor"
                    value: mediaViewerLoaders.appWindow ? mediaViewerLoaders.appWindow.accentColor : "#1e1e1e"
                    when: mediaViewerLoaders.appWindow ? true : false
                }

                Binding {
                    target: modelViewer
                    property: "foregroundColor"
                    value: mediaViewerLoaders.appWindow ? mediaViewerLoaders.appWindow.foregroundColor : "#f5f5f5"
                    when: mediaViewerLoaders.appWindow ? true : false
                }

                onLoaded: {
                    const win = mediaViewerLoaders.appWindow
                    if (!win) return
                    win.logLoadDuration("Model ready", modelViewer.source)
                    if (win.showingMetadata) {
                        Qt.callLater(function() {
                            if (win && mediaViewerLoaders.metadataPopup) {
                                mediaViewerLoaders.metadataPopup.metadataList = win.getMetadataList()
                            }
                        })
                    }
                }
            }
        }
    }
    
    // Save toast notification - now using ToastNotification.qml component
    ToastNotification {
        id: saveToast
    }
    
    // Expose loaders to parent for access
    property alias viewerLoader: viewerLoader
    property alias videoPlayerLoader: videoPlayerLoader
    property alias audioPlayerLoader: audioPlayerLoader
    property alias markdownViewerLoader: markdownViewerLoader
    property alias textViewerLoader: textViewerLoader
    property alias pdfViewerLoader: pdfViewerLoader
    property alias zipViewerLoader: zipViewerLoader
    property alias modelViewerLoader: modelViewerLoader
    property alias imageControlsHideTimer: imageControlsHideTimer
    property alias imageControls: imageControls
}

