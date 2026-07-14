import QtMultimedia
import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import QtCore

// Heavy UI tree loaded asynchronously from Main.qml (shell-boot).
Item {
    id: root
    anchors.fill: parent

    required property var shellResizeTimers
    required property ApplicationWindow appWindow
    // Do NOT alias as `window` — nested components/closures resolve bare `window` to the JS global.
    readonly property ApplicationWindow appWin: appWindow

    WindowBackground {
        id: windowBackgroundRoot
        z: -1000
        anchors.fill: parent
        accentColor: appWin.accentColor
        dynamicColoringEnabled: appWin.dynamicColoringEnabled
        gradientBackgroundEnabled: appWin.gradientBackgroundEnabled
        backdropBlurEnabled: appWin.backdropBlurEnabled
        ambientGradientEnabled: appWin.ambientGradientEnabled
        snowEffectEnabled: appWin.snowEffectEnabled
        badAppleEffectEnabled: appWin.badAppleEffectEnabled
        backdropImageSource: appWin.backdropImageSource
        paletteColors: appWin.paletteColors
        audioPlayer: appWin.audioPlayer
    }

    TitleBar {
        id: customTitleBar
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        windowTitle: appWin.title
        currentFilePath: appWin.currentImage
        accentColor: appWin.accentColor
        foregroundColor: appWin.foregroundColor
        hasMedia: appWin.currentImage !== ""
        listenTogetherEnabled: appWin.listenTogetherEnabled
        listenTogetherActive: appWin.showingListenTogether
        window: appWin
        frameHelper: frameHelper
        autoHideEnabled: appWin.autoHideTitleBar || (appWin.audioImmersive3D === true)

        Connections {
            target: appWin
            function onAudioImmersive3DChanged() {
                if (!appWin)
                    return
                if (appWin.audioImmersive3D) {
                    customTitleBar.titleBarVisible = false
                } else if (!appWin.autoHideTitleBar) {
                    customTitleBar.titleBarVisible = true
                }
            }
        }

        onRightControlsHitWidthChanged: {
            if (frameHelper) {
                frameHelper.buttonAreaWidth = rightControlsHitWidth
            }
        }

        Component.onCompleted: {
            if (frameHelper) {
                Qt.callLater(function() {
                    frameHelper.buttonAreaWidth = rightControlsHitWidth
                })
            }
        }

        onMetadataClicked: {
            if (!appWin.showingSettings && !appWin.showingListenTogether) {
                appWin.showingMetadata = !appWin.showingMetadata
            }
        }
        onListenTogetherClicked: {
            appWin.showingMetadata = false
            appWin.showingSettings = false
            appWin.showingListenTogether = !appWin.showingListenTogether
        }
        onSettingsClicked: {
            if (appWin.showingSettings === false) {
                appWin.showingMetadata = false
                appWin.showingListenTogether = false
            }
            appWin.showingSettings = !appWin.showingSettings
        }
        onMinimizeClicked: appWin.showMinimized()
        onMaximizeClicked: {
            if (frameHelper) {
                frameHelper.toggleMaximize()
            } else {
                if (appWin.visibility === Window.Maximized)
                    appWin.showNormal()
                else
                    appWin.showMaximized()
            }
        }
        onCloseClicked: appWin.close()
    }

    WindowFrameHelper {
        id: frameHelper
        titleBarHeight: customTitleBar.barHeight

        Component.onCompleted: {
            titleBarVisible = customTitleBar.titleBarVisible

            if (Qt.platform.os === "windows") {
                Qt.callLater(function() {
                    frameHelper.setupFramelessWindow(root.appWindow)
                })
            }
        }
    }

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

    FileDialogManager {
        id: fileDialogManager
        mainWindow: appWin
        logToDebugConsole: appWin.logToDebugConsole
    }

    property alias openDialog: fileDialogManager.dialog

    Item {
        id: contentRoot
        anchors.top: customTitleBar.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom

        Loader {
            id: pageStackLoader
            anchors.fill: parent
            active: true
            asynchronous: true
            sourceComponent: MainContentArea {
                appWindow: root.appWindow
                resizeTimers: root.shellResizeTimers
                metadataPopup: root.metadataPopup
                openDialog: root.openDialog
            }
        }

        Loader {
            id: undertaleFightLoader
            anchors.fill: parent
            active: root.appWindow ? root.appWindow.undertaleFightEnabled : false
            asynchronous: true
            visible: active
            z: 2000000
            onLoaded: {
                const w = root.appWindow
                if (w && w.undertaleFightStartPending && item && typeof item.startFight === "function") {
                    item.startFight()
                    w.undertaleFightStartPending = false
                }
            }
            sourceComponent: UndertaleFight {
                enabled: true
                appWindow: root.appWindow
                titleBar: customTitleBar
            }
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
            z: -1

            onPositionChanged: (mouse) => {
                const w = root.appWindow
                if (!w || !customTitleBar.autoHideEnabled)
                    return
                if (!w.autoHideTitleBar && !w.audioImmersive3D)
                    return
                if (!customTitleBar.titleBarVisible)
                    return
                const margin = 10
                if (mouse.y > customTitleBar.barHeight + margin) {
                    if (!customTitleBar.hideTimer.running) {
                        customTitleBar.hideTimer.restart()
                    }
                } else {
                    if (customTitleBar.hideTimer.running) {
                        customTitleBar.hideTimer.stop()
                    }
                }
            }
        }

        Item {
            id: topHotZone
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 30
            z: 1000000
            visible: root.appWindow
                     && !customTitleBar.titleBarVisible
                     && !root.appWindow.undertaleFightEnabled
                     && (root.appWindow.autoHideTitleBar || root.appWindow.audioImmersive3D)
            enabled: visible

            onVisibleChanged: {
                if (frameHelper) {
                    frameHelper.hotZoneActive = visible
                }
            }

            Component.onCompleted: {
                if (frameHelper) {
                    frameHelper.hotZoneActive = visible
                }
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.NoButton
                propagateComposedEvents: false

                onEntered: {
                    const w = root.appWindow
                    if (!w || !customTitleBar)
                        return
                    if (!w.autoHideTitleBar && !w.audioImmersive3D)
                        return
                    customTitleBar.titleBarVisible = true
                    customTitleBar.hideTimer.stop()
                }

                onExited: {}
            }
        }
    }

    property var pageStack: pageStackLoader.item ? pageStackLoader.item : nullPageStack
    property var undertaleFight: undertaleFightLoader.item

    QtObject {
        id: nullMetadataPopupManager
        property var popup: null
        function updateMetadataList() {}
    }
    Loader {
        id: metadataPopupManagerLoader
        // Keep loaded while the app runs so metadata is fetched on track load even when the popup is closed.
        active: !!root.appWindow
        asynchronous: true
        sourceComponent: MetadataPopupManager {
            mainWindow: root.appWindow
            customTitleBar: customTitleBar
            pageStack: root.pageStack
        }
    }

    property var metadataPopupManager: metadataPopupManagerLoader.item ? metadataPopupManagerLoader.item : nullMetadataPopupManager
    property var metadataPopup: metadataPopupManager.popup

    ListenTogetherBridge {
        id: listenTogetherBridgeHost
        appWindow: appWin
        audioPlayer: (pageStackLoader.item && pageStackLoader.item.mediaViewerLoaders
                      && pageStackLoader.item.mediaViewerLoaders.audioPlayerLoader.item)
                     ? pageStackLoader.item.mediaViewerLoaders.audioPlayerLoader.item
                     : (appWin.audioPlayer || null)
    }
    property alias listenTogetherBridge: listenTogetherBridgeHost

    ListenTogetherPopup {
        id: listenTogetherPopup
        parent: root
        z: 500000
        webRTCManager: listenTogetherBridgeHost.manager
        titleBar: customTitleBar
        accentColor: appWin.accentColor
        foregroundColor: appWin.foregroundColor

        onOpened: appWin.showingListenTogether = true
        onClosed: appWin.showingListenTogether = false
    }

    Connections {
        target: appWin
        function onShowingListenTogetherChanged() {
            if (appWin.showingListenTogether && !listenTogetherPopup.opened)
                listenTogetherPopup.open()
            else if (!appWin.showingListenTogether && listenTogetherPopup.opened)
                listenTogetherPopup.close()
        }
    }

    AppShortcuts {
        window: appWin
        openDialog: openDialog
        openYoutubeDialog: function() {
            if (appWin && typeof appWin.openYoutubeUrlDialog === "function")
                appWin.openYoutubeUrlDialog()
        }
    }

    BassPulseManager {
        mainWindow: appWin
        isAudio: appWin.isAudio
        audioPlayerLoader: pageStack.mediaViewerLoaders.audioPlayerLoader
        accentColor: appWin.accentColor
        suppressMainWindowRaise: appWin.musicOverlayVisible
    }

    property alias windowBg: windowBackgroundRoot
    property alias _frameHelper: frameHelper
    property alias _customTitleBar: customTitleBar
}
