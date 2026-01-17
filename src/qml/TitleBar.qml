import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects

Item {
    id: titleBarContainer
    
    // Separate visual height from layout height
    // Visual: the actual titlebar rectangle height
    property int barHeight: 50
    // Layout: the container's effective height (controls layout space)
    property int layoutHeight: titleBarVisible ? barHeight : 0
    // Hot zone height for cursor detection (extends beyond barHeight for easier triggering)
    property int hotZoneHeight: 60
    
    // Bind container height to layout height - this makes the layout collapse when hidden
    height: layoutHeight
    
    // Animate height changes for smooth layout transitions
    Behavior on height {
        NumberAnimation {
            duration: 200
            easing.type: Easing.OutCubic
        }
    }
    
    property string windowTitle: ""
    property string currentFilePath: ""
    property color accentColor: "#121216"
    property color foregroundColor: "#f5f5f5"
    property bool hasMedia: false
    property var window: null
    property var frameHelper: null  // FrameHelper reference for immediate titleBarVisible updates
    property bool autoHideEnabled: false
    property bool isHovered: false  // Expose hover state for external access
    
    // Expose hideTimer for external access
    property alias hideTimer: hideTimer
    
    // Expose right controls width for hit-testing
    property alias rightControlsHitWidth: titleBarLayout.rightControlsHitWidth
    
    signal metadataClicked()
    signal settingsClicked()
    signal minimizeClicked()
    signal maximizeClicked()
    signal closeClicked()
    
    // State for auto-hide functionality
    property bool titleBarVisible: true  // Default to visible, will be controlled by auto-hide logic
    
    // CRITICAL: Immediately update C++ property when QML property changes
    // This ensures the hit-test (running on Windows message thread) sees the update immediately
    onTitleBarVisibleChanged: {
        if (frameHelper) {
            console.log("[TitleBar] titleBarVisible changed to:", titleBarVisible, "- updating C++ property immediately")
            frameHelper.titleBarVisible = titleBarVisible
        }
    }
    
    // POSITION-BASED DETECTION - Removed in favor of permanent hot zone in Main.qml
    // The hot zone detection is now handled by a permanent top-edge Item that never collapses
    // This allows the titlebar to fully collapse while still detecting cursor at the top
    
    // Timer to hide titlebar after a delay when cursor leaves hot zone
    // The hot zone detection is handled by the permanent hot zone in Main.qml
    // This timer just hides the titlebar after the delay
    Timer {
        id: hideTimer
        interval: 500  // Hide after 0.5 seconds of cursor outside hot zone
        running: false
        onTriggered: {
            if (autoHideEnabled) {
                console.log("[TitleBar] Hide timer triggered - hiding titlebar")
                titleBarVisible = false
            } else {
                console.log("[TitleBar] Hide timer triggered but auto-hide disabled")
            }
        }
    }
    
    // Hover detection for the titlebar itself - covers the entire titlebar area
    // This needs to be on the Rectangle, not the container
    
    // Update visibility when auto-hide is toggled
    onAutoHideEnabledChanged: {
        console.log("[TitleBar] autoHideEnabled changed to:", autoHideEnabled)
        if (!autoHideEnabled) {
            console.log("[TitleBar] Auto-hide disabled - showing titlebar")
            titleBarVisible = true  // Always visible when disabled
            hideTimer.stop()
        } else {
            console.log("[TitleBar] Auto-hide enabled")
            // When enabled, show initially, then start hide timer
            titleBarVisible = true
            // Start hide timer after a short delay to allow user to move cursor to top
            Qt.callLater(function() {
                hideTimer.restart()
            })
        }
    }
    
    Rectangle {
        id: titleBar
        anchors.left: parent.left
        anchors.right: parent.right
        y: titleBarVisible ? 0 : -barHeight  // Slide up when hidden
        height: barHeight  // Visual height of the titlebar
        z: 0
        color: Qt.rgba(
            Qt.lighter(accentColor, 1.3).r,
            Qt.lighter(accentColor, 1.3).g,
            Qt.lighter(accentColor, 1.3).b,
            0.85
        )
        
        // HoverHandler removed - cannot coexist with HTCAPTION drag zone
        // Hiding is now driven by position detection in Main.qml's global MouseArea
        
        // Smooth animation for auto-hide
        Behavior on y {
            NumberAnimation {
                duration: 200
                easing.type: Easing.OutCubic
            }
        }
    
    // Subtle shadow at the bottom instead of border
    layer.enabled: true
    layer.effect: DropShadow {
        transparentBorder: true
        horizontalOffset: 0
        verticalOffset: 2
        radius: 8
        samples: 16
        color: Qt.rgba(0, 0, 0, 0.15)
    }

        // DragHandler to start Windows drag when user presses and moves
        // This allows QML to own hover/click while Windows handles drag on demand
        DragHandler {
            id: dragHandler
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            target: null  // We don't move QML items, we move the window
            enabled: window && window.visibility !== Window.FullScreen  // Disable dragging in fullscreen
            
            onActiveChanged: {
                if (active && frameHelper) {
                    // Don't allow dragging when in fullscreen mode (double-check)
                    if (window && window.visibility === Window.FullScreen) {
                        return
                    }
                    // User started dragging - tell Windows to take over
                    frameHelper.startSystemMove()
                }
            }
        }

    TapHandler {
        acceptedButtons: Qt.LeftButton
        gesturePolicy: TapHandler.ReleaseWithinBounds
        onDoubleTapped: maximizeClicked()
    }

    RowLayout {
        id: titleBarLayout
        anchors.fill: parent
        anchors.leftMargin: 16
        anchors.rightMargin: 12
        spacing: 16
        // Layouts don't need to be disabled - they're not interactive by default
        // Removing enabled: false fixes hover detection across the entire width
        
        // Expose the actual width of the right-side controls for hit-testing
        // This includes all buttons + spacing + right margin
        property int rightControlsWidth: rightControls.implicitWidth > 0 ? rightControls.implicitWidth : rightControls.width
        property int rightControlsHitWidth: rightControlsWidth + 24  // 12px right margin + 12px safety padding

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: parent.height
            // Items don't need to be disabled - they're not interactive by default

        ColumnLayout {
                anchors.fill: parent
            spacing: 2
                // Layouts don't need to be disabled

            Text {
                text: windowTitle
                color: foregroundColor
                font.pixelSize: 14
                font.weight: Font.Medium
                font.letterSpacing: 0.2
                opacity: 0.95
            }

            Text {
                Layout.fillWidth: true
                text: currentFilePath === ""
                      ? qsTr("Drag & drop an image")
                      : decodeURIComponent(currentFilePath.toString().replace("file:///", ""))
                elide: Text.ElideMiddle
                color: foregroundColor
                font.pixelSize: 11
                opacity: 0.7
            }
            }
            
        }

        RowLayout {
            id: rightControls
            spacing: 6
            Layout.alignment: Qt.AlignVCenter

            Rectangle {
                id: metadataButton
                Layout.preferredWidth: 36
                Layout.preferredHeight: 36
                radius: 8
                property bool hovered: false  // Local hover state for visual feedback
                color: metadataTap.pressed
                       ? Qt.rgba(foregroundColor.r, foregroundColor.g, foregroundColor.b, 0.2)
                       : (hovered
                          ? Qt.rgba(foregroundColor.r, foregroundColor.g, foregroundColor.b, 0.12)
                          : Qt.rgba(foregroundColor.r, foregroundColor.g, foregroundColor.b, 0.05))
                visible: hasMedia
                
                Behavior on color {
                    ColorAnimation { duration: 150; easing.type: Easing.OutCubic }
                }
                
                Behavior on scale {
                    NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                }
                
                scale: metadataTap.pressed ? 0.95 : (hovered ? 1.05 : 1.0)
                
                Image {
                    id: metadataIcon
                    anchors.centerIn: parent
                    source: "qrc:/qlementine/icons/16/misc/info.svg"
                    sourceSize: Qt.size(18, 18)
                    visible: false
                }
                ColorOverlay {
                    anchors.fill: metadataIcon
                    source: metadataIcon
                    color: foregroundColor
                    opacity: metadataButton.hovered ? 1.0 : 0.8
                    
                    Behavior on opacity {
                        NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                    }
                }
                TapHandler {
                    id: metadataTap
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    acceptedButtons: Qt.LeftButton
                    gesturePolicy: TapHandler.ReleaseWithinBounds
                    onTapped: metadataClicked()
                    onDoubleTapped: {
                        // Prevent double-tap from propagating to title bar
                        // Just handle it as a single tap
                        metadataClicked()
                    }
                }
                // MouseArea for cursor and visual feedback - does NOT own hover
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.NoButton  // Don't intercept clicks
                    cursorShape: Qt.PointingHand
                    onEntered: metadataButton.hovered = true
                    onExited: metadataButton.hovered = false
                }
            }

            Rectangle {
                id: settingsButton
                Layout.preferredWidth: 36
                Layout.preferredHeight: 36
                radius: 8
                property bool hovered: false  // Local hover state for visual feedback
                color: settingsTap.pressed
                       ? Qt.rgba(foregroundColor.r, foregroundColor.g, foregroundColor.b, 0.2)
                       : (hovered
                          ? Qt.rgba(foregroundColor.r, foregroundColor.g, foregroundColor.b, 0.12)
                          : Qt.rgba(foregroundColor.r, foregroundColor.g, foregroundColor.b, 0.05))
                
                Behavior on color {
                    ColorAnimation { duration: 150; easing.type: Easing.OutCubic }
                }
                
                Behavior on scale {
                    NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                }
                
                scale: settingsTap.pressed ? 0.95 : (hovered ? 1.05 : 1.0)
                
                Image {
                    id: settingsIcon
                    anchors.centerIn: parent
                    source: "qrc:/qlementine/icons/16/navigation/settings.svg"
                    sourceSize: Qt.size(18, 18)
                    visible: false
                }
                ColorOverlay {
                    anchors.fill: settingsIcon
                    source: settingsIcon
                    color: foregroundColor
                    opacity: settingsButton.hovered ? 1.0 : 0.8
                    
                    Behavior on opacity {
                        NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                    }
                }
                TapHandler {
                    id: settingsTap
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    acceptedButtons: Qt.LeftButton
                    gesturePolicy: TapHandler.ReleaseWithinBounds
                    onTapped: settingsClicked()
                    onDoubleTapped: {
                        // Prevent double-tap from propagating to title bar
                        // Just handle it as a single tap
                        settingsClicked()
                    }
                }
                // MouseArea for cursor and visual feedback - does NOT own hover
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.NoButton  // Don't intercept clicks
                    cursorShape: Qt.PointingHand
                    onEntered: settingsButton.hovered = true
                    onExited: settingsButton.hovered = false
                }
            }

            Rectangle {
                id: minimizeButton
                Layout.preferredWidth: 40
                Layout.preferredHeight: 36
                radius: 8
                property bool hovered: false  // Local hover state for visual feedback
                color: minimizeTap.pressed
                       ? Qt.rgba(foregroundColor.r, foregroundColor.g, foregroundColor.b, 0.2)
                       : (hovered
                          ? Qt.rgba(foregroundColor.r, foregroundColor.g, foregroundColor.b, 0.12)
                          : Qt.rgba(foregroundColor.r, foregroundColor.g, foregroundColor.b, 0.05))
                
                Behavior on color {
                    ColorAnimation { duration: 150; easing.type: Easing.OutCubic }
                }
                
                Behavior on scale {
                    NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                }
                
                scale: minimizeTap.pressed ? 0.95 : (hovered ? 1.05 : 1.0)
                
                Image {
                    id: minimizeIcon
                    anchors.centerIn: parent
                    source: "qrc:/qlementine/icons/16/action/windows-minimize.svg"
                    sourceSize: Qt.size(18, 18)
                    visible: false
                }
                ColorOverlay {
                    anchors.fill: minimizeIcon
                    source: minimizeIcon
                    color: foregroundColor
                    opacity: minimizeButton.hovered ? 1.0 : 0.8
                    
                    Behavior on opacity {
                        NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                    }
                }
                TapHandler {
                    id: minimizeTap
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    acceptedButtons: Qt.LeftButton
                    onTapped: minimizeClicked()
                }
                // MouseArea for cursor and visual feedback - does NOT own hover
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.NoButton  // Don't intercept clicks
                    cursorShape: Qt.PointingHand
                    onEntered: minimizeButton.hovered = true
                    onExited: minimizeButton.hovered = false
                }
            }

            Rectangle {
                id: maximizeButton
                Layout.preferredWidth: 40
                Layout.preferredHeight: 36
                radius: 8
                property bool hovered: false  // Local hover state for visual feedback
                color: maximizeTap.pressed
                       ? Qt.rgba(foregroundColor.r, foregroundColor.g, foregroundColor.b, 0.2)
                       : (hovered
                          ? Qt.rgba(foregroundColor.r, foregroundColor.g, foregroundColor.b, 0.12)
                          : Qt.rgba(foregroundColor.r, foregroundColor.g, foregroundColor.b, 0.05))
                
                property bool isMaximized: window ? window.visibility === Window.Maximized : false
                
                Behavior on color {
                    ColorAnimation { duration: 150; easing.type: Easing.OutCubic }
                }
                
                Behavior on scale {
                    NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                }
                
                scale: maximizeTap.pressed ? 0.95 : (hovered ? 1.05 : 1.0)
                
                Image {
                    id: maximizeIconImg
                    anchors.centerIn: parent
                    source: maximizeButton.isMaximized 
                            ? "qrc:/qlementine/icons/16/action/windows-unmaximize.svg"
                            : "qrc:/qlementine/icons/16/action/windows-maximize.svg"
                    sourceSize: Qt.size(18, 18)
                    visible: false
                }
                ColorOverlay {
                    id: maximizeIcon
                    anchors.fill: maximizeIconImg
                    source: maximizeIconImg
                    color: foregroundColor
                    opacity: maximizeButton.hovered ? 1.0 : 0.8
                    
                    Behavior on opacity {
                        NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                    }
                }
                TapHandler {
                    id: maximizeTap
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    acceptedButtons: Qt.LeftButton
                    onTapped: maximizeClicked()
                }
                // MouseArea for cursor and visual feedback - does NOT own hover
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.NoButton  // Don't intercept clicks
                    cursorShape: Qt.PointingHand
                    onEntered: maximizeButton.hovered = true
                    onExited: maximizeButton.hovered = false
                }
            }

            Rectangle {
                id: closeButton
                Layout.preferredWidth: 40
                Layout.preferredHeight: 36
                radius: 8
                property bool hovered: false  // Local hover state for visual feedback
                color: closeTap.pressed
                       ? Qt.rgba(0.9, 0.3, 0.3, 0.3)
                       : (hovered
                          ? Qt.rgba(0.9, 0.3, 0.3, 0.2)
                          : Qt.rgba(foregroundColor.r, foregroundColor.g, foregroundColor.b, 0.05))
                
                Behavior on color {
                    ColorAnimation { duration: 150; easing.type: Easing.OutCubic }
                }
                
                Behavior on scale {
                    NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                }
                
                scale: closeTap.pressed ? 0.95 : (hovered ? 1.05 : 1.0)
                
                Image {
                    id: closeIcon
                    anchors.centerIn: parent
                    source: "qrc:/qlementine/icons/16/action/windows-close.svg"
                    sourceSize: Qt.size(18, 18)
                    visible: false
                }
                ColorOverlay {
                    anchors.fill: closeIcon
                    source: closeIcon
                    color: closeButton.hovered ? "#ff4444" : foregroundColor
                    opacity: closeButton.hovered ? 1.0 : 0.8
                    
                    Behavior on color {
                        ColorAnimation { duration: 150; easing.type: Easing.OutCubic }
                    }
                    
                    Behavior on opacity {
                        NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                    }
                }
                TapHandler {
                    id: closeTap
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    acceptedButtons: Qt.LeftButton
                    onTapped: closeClicked()
                }
                // MouseArea for cursor and visual feedback - does NOT own hover
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.NoButton  // Don't intercept clicks
                    cursorShape: Qt.PointingHand
                    onEntered: closeButton.hovered = true
                    onExited: closeButton.hovered = false
                }
            }
            }  // Close buttons RowLayout
        }  // Close main RowLayout
    }  // Close Rectangle
    
    // Hover detection architecture:
    // - ONE central HoverHandler on titleBarContainer (owns hover for entire subtree)
    // - Fixed reveal strip at top (for when titlebar is hidden)
    // - Button MouseAreas provide cursor/visual feedback only (do NOT own hover)
    // - No competing HoverHandlers that fragment hover ownership
}  // Close Item

