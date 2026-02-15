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
    
    anchors.fill: parent

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
            color: appWindow.backdropBlurEnabled
                   ? "transparent"  // Completely transparent when backdrop blur is active
                   : (appWindow.ambientGradientEnabled
                      ? "transparent"  // Transparent when ambient gradient is active
                      : (appWindow.snowEffectEnabled || appWindow.badAppleEffectEnabled
                         ? "transparent"  // Transparent when snow or Bad Apple effect is active
                         : (appWindow.gradientBackgroundEnabled && appWindow.paletteColors && appWindow.paletteColors.length > 1
                            ? Qt.rgba(0, 0, 0, 0.15)  // Less dark overlay when gradient is active
                            : Qt.darker(appWindow.accentColor, 1.15))))  // Solid color when gradient is off
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
                onFileDropped: function(fileUrl) {
                    // Ignore self-generated drag-out temp files/folders from ZIP panel.
                    const dropped = fileUrl ? fileUrl.toString().replace(/\\/g, "/").toLowerCase() : ""
                    if (dropped.indexOf("/s3rp3nt_media_zip_drag/") >= 0) {
                        return
                    }
                    appWindow.logToDebugConsole("[QML] File dropped, setting currentImage: " + fileUrl.toString(), "info")
                    // Ensure window is visible when dropping file
                    if (!appWindow.visible) {
                        appWindow.show()
                        appWindow.raise()
                    }
                    appWindow.currentImage = fileUrl
                }
                onDropActiveChanged: function(active) {
                    appWindow.dropActive = active
                }
            }

            // Media viewer loaders - all media viewer Loader components encapsulated here
            MediaViewerLoaders {
                id: _mediaViewerLoaders
                anchors.fill: parent
                appWindow: pageStack.appWindow
                resizeTimers: pageStack.resizeTimers
                metadataPopup: pageStack.metadataPopup
                metadataPopupManager: pageStack.appWindow.metadataPopupManager
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
                }
            }
        }
    }

    // Settings page - overlays on top of media viewer
    SettingsPage {
        id: settingsPage
        anchors.fill: parent
        appWindow: pageStack.appWindow
        mediaViewerItem: pageStack.mediaViewerItem  // Pass media viewer for blur capture
        showingSettings: appWindow.showingSettings
        accentColor: appWindow.accentColor
        visible: appWindow.showingSettings
        z: 10  // Above media viewer
        foregroundColor: appWindow.foregroundColor
        dynamicColoringEnabled: appWindow.dynamicColoringEnabled
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
        
        onBackClicked: appWindow.showingSettings = false
        onDynamicColoringToggled: function(enabled) {
            appWindow.dynamicColoringEnabled = enabled
            appWindow.updateAccentColor()
        }
        onGradientBackgroundToggled: function(enabled) {
            appWindow.gradientBackgroundEnabled = enabled
            if (enabled) {
                appWindow.backdropBlurEnabled = false  // Disable backdrop blur when gradient is enabled
                appWindow.ambientGradientEnabled = false  // Disable ambient gradient when gradient is enabled
                // Snow can layer on top, so don't disable it
            }
            appWindow.updateAccentColor()
        }
        onBackdropBlurToggled: function(enabled) {
            appWindow.backdropBlurEnabled = enabled
            if (enabled) {
                appWindow.gradientBackgroundEnabled = false  // Disable gradient when backdrop blur is enabled
                appWindow.ambientGradientEnabled = false  // Disable ambient gradient when backdrop blur is enabled
                // Snow can layer on top, so don't disable it
            }
        }
        onAmbientGradientToggled: function(enabled) {
            appWindow.ambientGradientEnabled = enabled
            if (enabled) {
                appWindow.gradientBackgroundEnabled = false  // Disable gradient when ambient gradient is enabled
                appWindow.backdropBlurEnabled = false  // Disable backdrop blur when ambient gradient is enabled
                // Snow can layer on top, so don't disable it
            }
        }
        onSnowEffectToggled: function(enabled) {
            appWindow.snowEffectEnabled = enabled
            // Snow can layer on top of other effects, so no need to disable them
        }
        onBadAppleEffectToggled: function(enabled) {
            appWindow.badAppleEffectEnabled = enabled
            // Bad Apple replaces snow when enabled
            if (enabled) {
                appWindow.snowEffectEnabled = false
            }
        }
        onBadAppleEasterEggClicked: {
            // Start Bad Apple easter egg
            if (appWindow.startBadAppleEasterEgg) {
                appWindow.startBadAppleEasterEgg()
                // Show ESC to exit notification
                badAppleEscNotification.show()
            }
        }
        onUndertaleEasterEggClicked: {
            // Start Undertale fight easter egg
            if (appWindow.startUndertaleFight) {
                appWindow.startUndertaleFight()
            }
        }
        onLyricsTranslationToggled: function(enabled) {
            appWindow.lyricsTranslationEnabled = enabled
        }
        onLyricsTranslationApiKeyEdited: function(apiKey) {
            appWindow.lyricsTranslationApiKey = apiKey
        }
        onLyricsTranslationTargetLanguageEdited: function(language) {
            appWindow.lyricsTranslationTargetLanguage = language
        }
        onAppLanguageEdited: function(language) {
            appWindow.appLanguage = language
            // Show message that restart is required
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
            // If enabled, resize to current media if available
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
            // Update DiscordRPC component in AudioPlayer if available
            // AudioPlayer has a discordRPCEnabled property that syncs with the DiscordRPC component
            if (pageStack.audioPlayer) {
                pageStack.audioPlayer.discordRPCEnabled = enabled
            }
        }
        onCoverArtSourceSelected: function(source) {
            appWindow.coverArtSource = source
            // Update AudioPlayer if available
            if (pageStack.audioPlayer) {
                pageStack.audioPlayer.coverArtSource = source
            }
        }
        onLastFMApiKeyEdited: function(apiKey) {
            appWindow.lastFMApiKey = apiKey
            // Update AudioPlayer if available
            if (pageStack.audioPlayer) {
                pageStack.audioPlayer.lastFMApiKey = apiKey
            }
        }
        onDebugConsoleToggled: function(enabled) {
            appWindow.debugConsoleEnabled = enabled
            console.log("[Settings] Debug console " + (enabled ? "ENABLED" : "DISABLED") + " - restart required")
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

