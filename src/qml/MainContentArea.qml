import QtMultimedia
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects

// MainContentArea component - media viewer with overlay settings page
Item {
    id: pageStack
    
    // Required properties from window
    required property var appWindow
    required property var resizeTimers
    required property var metadataPopup
    required property var openDialog
    
    // Expose mediaViewerLoaders to parent for access
    property alias mediaViewerLoaders: _mediaViewerLoaders
    property bool mediaLoadersReady: false
    
    anchors.fill: parent

    Component.onCompleted: {
        // Defer heavy loader tree until first event-loop turn.
        Qt.callLater(function() {
            mediaLoadersReady = true
        })
    }

    // Fallback placeholders so external code can safely access loader fields
    // before MediaViewerLoaders is instantiated.
    QtObject {
        id: _nullLoader
        property var item: null
        property bool active: false
    }
    QtObject {
        id: _nullTimer
        function restart() {}
    }
    QtObject {
        id: _nullImageControls
        property bool thumbnailPopupVisible: false
        function hideThumbnailPopup() {}
    }

    // Media viewer - always visible, behind settings
    // Expose as property for blur capture
    property alias mediaViewerItem: _mediaViewerItem
    Item {
        id: _mediaViewerItem
        anchors.fill: parent
        visible: true  // Always visible, settings overlays on top

        Rectangle {
            id: viewer
            anchors.fill: parent
            // Let WindowBackground show through whenever a backdrop effect is on.
            // Gradient canvas only paints when palette has 2+ colors, but the tint still
            // must not be opaque or only "multi-color" mode would ever show the gradient.
            color: !appWindow
                   ? Qt.darker("#121216", 1.15)
                   : appWindow.backdropBlurEnabled
                     ? "transparent"
                     : (appWindow.ambientGradientEnabled
                        ? "transparent"
                        : (appWindow.snowEffectEnabled || appWindow.badAppleEffectEnabled
                           ? "transparent"
                           : (appWindow.gradientBackgroundEnabled
                              ? Qt.rgba(0, 0, 0, 0.15)
                              : Qt.darker(appWindow.accentColor, 1.15))))
            clip: true
            focus: true
            property int padding: 0
            border.width: 0  // Ensure no border is visible
            border.color: "transparent"  // Ensure border color is transparent too
            // Don't set opacity to 0 - it makes children invisible too

            // Input handlers component
            InputHandlers {
                id: inputHandlers
                anchors.fill: parent
                currentImage: appWindow.currentImage
                isVideo: appWindow.isVideo
                isAudio: appWindow.isAudio
                isMarkdown: appWindow.isMarkdown
                isText: appWindow.isText
                isPdf: appWindow.isPdf
                isZip: appWindow.isZip
                isModel: appWindow.isModel
                isImageType: appWindow.isImageType
                showImageControls: appWindow.showImageControls
                videoPlayerLoader: _mediaViewerLoaders.videoPlayerLoader
                viewerLoader: _mediaViewerLoaders.viewerLoader
                imageControls: _mediaViewerLoaders.imageControls
                
                onAdjustZoomRequested: function(delta) {
                    appWindow.adjustZoom(delta)
                }
                onResetViewRequested: appWindow.resetView()
                onToggleImageControls: {
                    appWindow.showImageControls = !appWindow.showImageControls
                    if (appWindow.showImageControls) {
                        _mediaViewerLoaders.imageControlsHideTimer.restart()
                    }
                }
                onToggleVideoPlayback: {
                    if (_mediaViewerLoaders.videoPlayerLoader.item) {
                        const wasPlaying = _mediaViewerLoaders.videoPlayerLoader.item.playbackState === MediaPlayer.PlayingState
                        if (wasPlaying) {
                            _mediaViewerLoaders.videoPlayerLoader.item.pause()
                        } else {
                            _mediaViewerLoaders.videoPlayerLoader.item.play()
                        }
                    }
                }
                onFilesDropped: function(fileUrls) {
                    if (!fileUrls || fileUrls.length === 0) return
                    // Ignore self-generated drag-out temp files/folders from ZIP panel.
                    const filtered = []
                    for (let i = 0; i < fileUrls.length; i++) {
                        const u = fileUrls[i]
                        const dropped = u ? u.toString().replace(/\\/g, "/").toLowerCase() : ""
                        if (dropped.indexOf("/s3rpent_media_zip_drag/") >= 0) {
                            continue
                        }
                        filtered.push(u)
                    }
                    if (filtered.length === 0) return

                    if (!appWindow.visible) {
                        appWindow.show()
                        appWindow.raise()
                    }

                    if (typeof appWindow.handleDroppedFiles === "function") {
                        appWindow.handleDroppedFiles(filtered)
                        return
                    }

                    // Fallback: open first
                    appWindow.currentImage = filtered[0]
                }
                onDropActiveChanged: function(active) {
                    appWindow.dropActive = active
                }
            }

            // Media viewer loaders - all media viewer Loader components encapsulated here
            Loader {
                id: _mediaViewerLoaders
                anchors.fill: parent
                active: mediaLoadersReady
                asynchronous: true

                // Mirror key properties so callers can keep using
                // pageStack.mediaViewerLoaders.<loader> safely.
                property var viewerLoader: item ? item.viewerLoader : _nullLoader
                property var videoPlayerLoader: item ? item.videoPlayerLoader : _nullLoader
                property var audioPlayerLoader: item ? item.audioPlayerLoader : _nullLoader
                property var markdownViewerLoader: item ? item.markdownViewerLoader : _nullLoader
                property var textViewerLoader: item ? item.textViewerLoader : _nullLoader
                property var pdfViewerLoader: item ? item.pdfViewerLoader : _nullLoader
                property var zipViewerLoader: item ? item.zipViewerLoader : _nullLoader
                property var modelViewerLoader: item ? item.modelViewerLoader : _nullLoader
                property var imageControlsHideTimer: item ? item.imageControlsHideTimer : _nullTimer
                property var imageControls: item ? item.imageControls : _nullImageControls

                sourceComponent: MediaViewerLoaders {
                    anchors.fill: parent
                    appWindow: pageStack.appWindow
                    resizeTimers: pageStack.resizeTimers
                    metadataPopup: pageStack.metadataPopup
                    metadataPopupManager: pageStack.appWindow.metadataPopupManager
                }
            }

            // Drop overlay
            Rectangle {
                anchors.fill: parent
                color: Qt.rgba(appWindow.accentColor.r, appWindow.accentColor.g, appWindow.accentColor.b, 0.25)
                visible: appWindow.dropActive
                border.color: Qt.rgba(appWindow.accentColor.r, appWindow.accentColor.g, appWindow.accentColor.b, 0.5)
                border.width: 2
                z: 10
            }

            // Empty state placeholder - now using EmptyState.qml component
            // Must be after MediaViewerLoaders to be on top, but before drop overlay
            Item {
                id: emptyStateContainer
                anchors.fill: parent
                visible: appWindow && appWindow.currentImage.toString() === "" && !appWindow.showingSettings && !appWindow.badAppleEffectEnabled
                z: 5
                
                EmptyState {
                    id: emptyStatePlaceholder
                anchors.centerIn: parent
                    showingSettings: appWindow ? appWindow.showingSettings : false
                    listenTogetherEnabled: appWindow ? appWindow.listenTogetherEnabled : false
                    appWindow: pageStack.appWindow
                    onOpenFileRequested: {
                        // Access dialog through pageStack (passed from Main.qml)
                        if (pageStack.openDialog) {
                            pageStack.openDialog.open()
                        } else if (pageStack.appWindow && pageStack.appWindow.openDialog) {
                            // Fallback: try accessing through window
                            pageStack.appWindow.openDialog.open()
                        }
                    }
                    onOpenListenTogetherRequested: {
                        if (pageStack.appWindow) {
                            pageStack.appWindow.showingMetadata = false
                            pageStack.appWindow.showingSettings = false
                            pageStack.appWindow.showingListenTogether = true
                        }
                    }
                }
            }
        }
    }

    // Settings page - instantiate lazily only when opened.
    Loader {
        id: settingsPageLoader
        anchors.fill: parent
        active: appWindow.showingSettings
        visible: active
        asynchronous: true
        z: 10

        sourceComponent: SettingsPage {
            appWindow: pageStack.appWindow
            mediaViewerItem: pageStack.mediaViewerItem  // Pass media viewer for blur capture
            showingSettings: appWindow.showingSettings
            accentColor: appWindow.accentColor
            foregroundColor: appWindow.foregroundColor
            dynamicColoringEnabled: appWindow.dynamicColoringEnabled
            windowsAccentColorEnabled: appWindow.windowsAccentColorEnabled
            gradientBackgroundEnabled: appWindow.gradientBackgroundEnabled
            backdropBlurEnabled: appWindow.backdropBlurEnabled
            ambientGradientEnabled: appWindow.ambientGradientEnabled
            snowEffectEnabled: appWindow.snowEffectEnabled
            badAppleEffectEnabled: appWindow.badAppleEffectEnabled
            lyricsTranslationEnabled: appWindow.lyricsTranslationEnabled
            lyricsTranslationApiKey: appWindow.lyricsTranslationApiKey
            lyricsTranslationTargetLanguage: appWindow.lyricsTranslationTargetLanguage
            appLanguage: appWindow.appLanguage
            imageInterpolationMode: appWindow.imageInterpolationMode
            dynamicResolutionEnabled: appWindow.dynamicResolutionEnabled
            matchMediaAspectRatio: appWindow.matchMediaAspectRatio
            autoHideTitleBar: appWindow.autoHideTitleBar
            discordRPCEnabled: appWindow.discordRPCEnabled
            coverArtSource: appWindow.coverArtSource
            lastFMApiKey: appWindow.lastFMApiKey
            debugConsoleEnabled: appWindow.debugConsoleEnabled
            musicVideoMaxHeight: appWindow.musicVideoMaxHeight
            audioVisualizer3DEnabled: appWindow.audioVisualizer3DEnabled
            audioVisualizerPreset: appWindow.audioVisualizerPreset

            onBackClicked: appWindow.showingSettings = false
            onDynamicColoringToggled: function(enabled) {
                appWindow.dynamicColoringEnabled = enabled
                appWindow.updateAccentColor()
            }
            onWindowsAccentColorToggled: function(enabled) {
                appWindow.windowsAccentColorEnabled = enabled
                appWindow.updateAccentColor()
            }
            onGradientBackgroundToggled: function(enabled) {
                appWindow.gradientBackgroundEnabled = enabled
                if (enabled) {
                    appWindow.backdropBlurEnabled = false
                    appWindow.ambientGradientEnabled = false
                }
                appWindow.updateAccentColor()
            }
            onBackdropBlurToggled: function(enabled) {
                appWindow.backdropBlurEnabled = enabled
                if (enabled) {
                    appWindow.gradientBackgroundEnabled = false
                    appWindow.ambientGradientEnabled = false
                }
            }
            onAmbientGradientToggled: function(enabled) {
                appWindow.ambientGradientEnabled = enabled
                if (enabled) {
                    appWindow.gradientBackgroundEnabled = false
                    appWindow.backdropBlurEnabled = false
                }
            }
            onSnowEffectToggled: function(enabled) {
                appWindow.snowEffectEnabled = enabled
            }
            onBadAppleEffectToggled: function(enabled) {
                appWindow.badAppleEffectEnabled = enabled
                if (enabled) {
                    appWindow.snowEffectEnabled = false
                }
            }
            onBadAppleEasterEggClicked: {
                if (appWindow.startBadAppleEasterEgg) {
                    appWindow.startBadAppleEasterEgg()
                    badAppleEscNotification.show()
                }
            }
            onUndertaleEasterEggClicked: {
                if (appWindow.startUndertaleFight) {
                    appWindow.startUndertaleFight()
                }
            }
            onLyricsTranslationToggled: function(enabled) {
                appWindow.lyricsTranslationEnabled = enabled
            }
            onAudioVisualizer3DToggled: function(enabled) {
                appWindow.audioVisualizer3DEnabled = enabled
            }
            onAudioVisualizerPresetSelected: function(preset) {
                appWindow.audioVisualizerPreset = preset
            }
            onLyricsTranslationApiKeyEdited: function(apiKey) {
                appWindow.lyricsTranslationApiKey = apiKey
            }
            onLyricsTranslationTargetLanguageEdited: function(language) {
                appWindow.lyricsTranslationTargetLanguage = language
            }
            onAppLanguageEdited: function(language) {
                appWindow.appLanguage = language
                console.log("[App] Language changed to:", language, "- Please restart the application for changes to take effect")
            }
            onImageInterpolationModeSelected: function(smooth) {
                appWindow.imageInterpolationMode = smooth
            }
            onDynamicResolutionToggled: function(enabled) {
                console.log("[Settings] Dynamic resolution toggled:", enabled ? "ENABLED" : "DISABLED")
                appWindow.dynamicResolutionEnabled = enabled
                if (appWindow.logToDebugConsole) {
                    appWindow.logToDebugConsole("[Settings] Dynamic resolution " + (enabled ? "ENABLED" : "DISABLED"), "info")
                }
            }
            onMatchMediaAspectRatioToggled: function(enabled) {
                appWindow.matchMediaAspectRatio = enabled
                if (enabled && appWindow.currentImage !== "") {
                    Qt.callLater(function() {
                        appWindow.resizeToMediaAspectRatio()
                    })
                }
            }
            onAutoHideTitleBarToggled: function(enabled) {
                appWindow.autoHideTitleBar = enabled
            }
            onDiscordRPCToggled: function(enabled) {
                appWindow.discordRPCEnabled = enabled
                if (pageStack.audioPlayer) {
                    pageStack.audioPlayer.discordRPCEnabled = enabled
                }
            }
            onCoverArtSourceSelected: function(source) {
                appWindow.coverArtSource = source
                if (pageStack.audioPlayer) {
                    pageStack.audioPlayer.coverArtSource = source
                }
            }
            onLastFMApiKeyEdited: function(apiKey) {
                appWindow.lastFMApiKey = apiKey
                if (pageStack.audioPlayer) {
                    pageStack.audioPlayer.lastFMApiKey = apiKey
                }
            }
            onDebugConsoleToggled: function(enabled) {
                appWindow.debugConsoleEnabled = enabled
                console.log("[Settings] Debug console " + (enabled ? "ENABLED" : "DISABLED") + " - restart required")
            }
            onMusicVideoMaxHeightSelected: function(h) {
                appWindow.musicVideoMaxHeight = h
            }
        }
    }

    // Bad Apple ESC to exit notification - shown when Bad Apple starts
    Rectangle {
        id: badAppleEscNotification
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.topMargin: 24
        width: Math.min(280, parent.width - 48)
        height: 36
        radius: 18
        color: Qt.rgba(0, 0, 0, 0.7)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.2)
        visible: opacity > 0
        opacity: 0
        z: 100
        
        Behavior on opacity { 
            NumberAnimation { 
                duration: 300
                easing.type: Easing.OutCubic
            } 
        }
        
        // Timer to fade out after 2.5 seconds (shorter than no audio)
        Timer {
            id: badAppleEscFadeTimer
            interval: 2500
            running: badAppleEscNotification.opacity > 0
            onTriggered: {
                badAppleEscNotification.opacity = 0
            }
        }
        
        function show() {
            opacity = 1
            badAppleEscFadeTimer.restart()
        }
        
        Row {
            anchors.centerIn: parent
            spacing: 8
            
            // ESC key icon - try keyboard icon as fallback
            Image {
                id: escIcon
                width: 16
                height: 16
                source: "qrc:/qlementine/icons/16/hardware/keyboard.svg"
                sourceSize.width: 16
                sourceSize.height: 16
                fillMode: Image.PreserveAspectFit
                
                ColorOverlay {
                    anchors.fill: parent
                    source: parent
                    color: "#ffffff"
                }
            }
            
            Text {
                text: "Press ESC to exit"
                font.pixelSize: 13
                font.weight: Font.Medium
                color: "#ffffff"
            }
        }
    }
}

