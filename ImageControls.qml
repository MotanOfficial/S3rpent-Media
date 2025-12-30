import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects

Item {
    id: imageControls
    clip: false  // Don't clip tooltips that extend outside

    property int currentIndex: 0
    property int totalImages: 0
    property real zoomFactor: 1.0
    property color accentColor: "#ffffff"
    property bool hasImages: totalImages > 0
    property var directoryImages: []  // Array of image URLs
    property var imageControlsHideTimer: null  // Reference to the hide timer from parent
    readonly property bool thumbnailPopupVisible: thumbnailPopup.shouldBeVisible
    
    // Calculate if background is light or dark to determine icon color
    readonly property color backgroundColor: Qt.rgba(
        Qt.lighter(accentColor, 1.1).r,
        Qt.lighter(accentColor, 1.1).g,
        Qt.lighter(accentColor, 1.1).b,
        0.85
    )
    readonly property real backgroundLuminance: (0.299 * backgroundColor.r + 0.587 * backgroundColor.g + 0.114 * backgroundColor.b)
    readonly property color iconColor: backgroundLuminance > 0.5 ? "#000000" : "#ffffff"
    // Pressed button color - use contrasting color for visibility
    readonly property color pressedButtonColor: backgroundLuminance > 0.5 
        ? Qt.rgba(0, 0, 0, 0.15)  // Dark overlay on light background
        : Qt.rgba(255, 255, 255, 0.2)  // Light overlay on dark background
    // Hover button color - subtle but visible
    readonly property color hoverButtonColor: backgroundLuminance > 0.5 
        ? Qt.rgba(0, 0, 0, 0.08)  // Subtle dark overlay on light background
        : Qt.rgba(255, 255, 255, 0.12)  // Subtle light overlay on dark background

    signal previousClicked()
    signal nextClicked()
    signal zoomInClicked()
    signal zoomOutClicked()
    signal fitToWindowClicked()
    signal actualSizeClicked()
    signal rotateLeftClicked()
    signal rotateRightClicked()
    signal thumbnailNavigationRequested(int index)  // Signal when thumbnail is clicked

    Rectangle {
        anchors.fill: parent
        radius: 20
        // Use subtle colored background - less intense than settings
        color: Qt.rgba(
            Qt.lighter(accentColor, 1.1).r,
            Qt.lighter(accentColor, 1.1).g,
            Qt.lighter(accentColor, 1.1).b,
            0.85
        )
        border.color: Qt.rgba(255, 255, 255, 0.2)
        border.width: 1
        clip: false  // Don't clip tooltips that extend outside
        
        // TapHandler to stop event propagation to InputHandlers
        TapHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            gesturePolicy: TapHandler.ReleaseWithinBounds
            onTapped: {
                // Stop propagation - don't toggle controls when clicking on them
            }
        }
        
        // Modern drop shadow using layer (like settings page)
        layer.enabled: true
        layer.effect: DropShadow {
            radius: 20
            samples: 41
            color: Qt.rgba(0, 0, 0, 0.5)
            verticalOffset: 4
            horizontalOffset: 0
        }

        RowLayout {
            id: controlsRowLayout
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            anchors.topMargin: 10
            anchors.bottomMargin: 14
            spacing: 8
            z: 1
            clip: false  // Don't clip tooltips

            // LEFT SIDE: Previous button
            Item {
                Layout.preferredWidth: 36
                Layout.preferredHeight: 36
                visible: hasImages

                Rectangle {
                    id: prevButton
                    anchors.fill: parent
                    radius: 8
                    property bool isHovered: false
                    property bool isPressed: false
                    
                    color: isPressed
                           ? pressedButtonColor
                           : (isHovered && totalImages > 1
                              ? hoverButtonColor
                              : "transparent")
                    opacity: totalImages > 1 ? 1 : 0.3
                    
                    Behavior on color {
                        ColorAnimation { duration: 200; easing.type: Easing.OutCubic }
                    }
                    Behavior on scale {
                        NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                    }
                    
                    scale: isPressed ? 0.9 : (isHovered ? 1.05 : 1.0)

                    Image {
                        id: prevIcon
                        anchors.centerIn: parent
                        width: 18
                        height: 18
                        source: "qrc:/qlementine/icons/16/navigation/chevron-left.svg"
                        sourceSize: Qt.size(18, 18)
                        visible: false
                    }
                    ColorOverlay {
                        anchors.fill: prevIcon
                        source: prevIcon
                        color: iconColor
                        opacity: 0.9
                    }

                    TapHandler {
                        id: prevTap
                        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                        acceptedButtons: Qt.LeftButton
                        enabled: totalImages > 1
                        
                        onTapped: previousClicked()
                        onPressedChanged: prevButton.isPressed = pressed
                    }
                    
                    HoverHandler {
                        id: prevHover
                        cursorShape: totalImages > 1 ? Qt.PointingHandCursor : Qt.ArrowCursor
                        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                        onHoveredChanged: prevButton.isHovered = hovered
                    }
                }
            }

            // Image counter (clickable to show thumbnails)
            Item {
                Layout.preferredWidth: 60
                Layout.preferredHeight: 32
                visible: hasImages
                z: 1
                
                Rectangle {
                    id: counterButton
                    anchors.fill: parent
                    radius: 10
                    property bool isHovered: false
                    property bool isPressed: false
                    
                    color: isPressed
                           ? pressedButtonColor
                           : (isHovered
                              ? hoverButtonColor
                              : "transparent")
                    
                    Behavior on color {
                        ColorAnimation { duration: 200; easing.type: Easing.OutCubic }
                    }
                    Behavior on scale {
                        NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                    }
                    
                    scale: isPressed ? 0.95 : (isHovered ? 1.02 : 1.0)
                    
                    Text {
                        id: counterText
                        anchors.centerIn: parent
                        width: parent.width
                        color: iconColor
                        font.pixelSize: 13
                font.family: "Segoe UI"
                        font.weight: Font.Medium
                horizontalAlignment: Text.AlignHCenter
                text: (currentIndex + 1) + " / " + totalImages
                        opacity: counterButton.isHovered ? 1.0 : 0.9
                        
                        Behavior on color {
                            ColorAnimation { duration: 200; easing.type: Easing.OutCubic }
                        }
                        Behavior on opacity {
                            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                        }
                    }
                    
                    TapHandler {
                        id: counterTap
                        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                        acceptedButtons: Qt.LeftButton
                        
                        onTapped: {
                            if (thumbnailPopup.visible) {
                                thumbnailPopup.hide()
                            } else {
                                thumbnailPopup.show()
                            }
                        }
                        onPressedChanged: counterButton.isPressed = pressed
                    }
                    
                    HoverHandler {
                        id: counterHover
                        cursorShape: Qt.PointingHandCursor
                        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                        onHoveredChanged: counterButton.isHovered = hovered
                    }
                }
            }

            // Next button
            Item {
                Layout.preferredWidth: 32
                Layout.preferredHeight: 32
                visible: hasImages

                Rectangle {
                    id: nextButton
                    anchors.fill: parent
                    radius: 8
                    property bool isHovered: false
                    property bool isPressed: false
                    
                    color: isPressed
                           ? pressedButtonColor
                           : (isHovered && totalImages > 1
                              ? hoverButtonColor
                              : "transparent")
                    opacity: totalImages > 1 ? 1 : 0.3
                    
                    Behavior on color {
                        ColorAnimation { duration: 200; easing.type: Easing.OutCubic }
                    }
                    Behavior on scale {
                        NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                    }
                    
                    scale: isPressed ? 0.9 : (isHovered ? 1.05 : 1.0)

                    Image {
                        id: nextIcon
                        anchors.centerIn: parent
                        width: 18
                        height: 18
                        source: "qrc:/qlementine/icons/16/navigation/chevron-right.svg"
                        sourceSize: Qt.size(18, 18)
                        visible: false
                    }
                    ColorOverlay {
                        anchors.fill: nextIcon
                        source: nextIcon
                        color: iconColor
                        opacity: 0.9
                    }

                    TapHandler {
                        id: nextTap
                        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                        acceptedButtons: Qt.LeftButton
                        enabled: totalImages > 1
                        
                        onTapped: nextClicked()
                        onPressedChanged: nextButton.isPressed = pressed
                    }
                    
                    HoverHandler {
                        id: nextHover
                        cursorShape: totalImages > 1 ? Qt.PointingHandCursor : Qt.ArrowCursor
                        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                        onHoveredChanged: nextButton.isHovered = hovered
                    }
                }
            }

            // Separator
            Rectangle {
                Layout.preferredWidth: 1
                Layout.preferredHeight: 24
                color: Qt.rgba(255, 255, 255, 0.15)
                visible: hasImages
            }

            // Zoom out
            Item {
                Layout.preferredWidth: 32
                Layout.preferredHeight: 32

                Rectangle {
                    id: zoomOutButton
                    anchors.fill: parent
                    radius: 8
                    property bool isHovered: false
                    property bool isPressed: false
                    
                    color: isPressed
                           ? pressedButtonColor
                           : (isHovered
                              ? hoverButtonColor
                              : "transparent")
                    
                    Behavior on color {
                        ColorAnimation { duration: 200; easing.type: Easing.OutCubic }
                    }
                    Behavior on scale {
                        NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                    }
                    
                    scale: isPressed ? 0.9 : (isHovered ? 1.05 : 1.0)

                    Image {
                        id: zoomOutIcon
                        anchors.centerIn: parent
                        width: 18
                        height: 18
                        source: "qrc:/qlementine/icons/16/action/zoom-out.svg"
                        sourceSize: Qt.size(18, 18)
                        visible: false
                    }
                    ColorOverlay {
                        anchors.fill: zoomOutIcon
                        source: zoomOutIcon
                        color: iconColor
                        opacity: 0.9
                    }

                    TapHandler {
                        id: zoomOutTap
                        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                        acceptedButtons: Qt.LeftButton
                        
                        onTapped: zoomOutClicked()
                        onPressedChanged: zoomOutButton.isPressed = pressed
                    }
                    
                    HoverHandler {
                        id: zoomOutHover
                        cursorShape: Qt.PointingHandCursor
                        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                        onHoveredChanged: zoomOutButton.isHovered = hovered
                    }
                }
            }

            // Zoom level indicator
            Text {
                Layout.preferredWidth: 55
                color: iconColor
                font.pixelSize: 12
                font.family: "Segoe UI"
                font.weight: Font.Medium
                horizontalAlignment: Text.AlignHCenter
                text: (zoomFactor * 100).toFixed(0) + "%"
                opacity: 0.9
            }

            // Zoom in
            Item {
                Layout.preferredWidth: 32
                Layout.preferredHeight: 32

                Rectangle {
                    id: zoomInButton
                    anchors.fill: parent
                    radius: 8
                    property bool isHovered: false
                    property bool isPressed: false
                    
                    color: isPressed
                           ? pressedButtonColor
                           : (isHovered
                              ? hoverButtonColor
                              : "transparent")
                    
                    Behavior on color {
                        ColorAnimation { duration: 200; easing.type: Easing.OutCubic }
                    }
                    Behavior on scale {
                        NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                    }
                    
                    scale: isPressed ? 0.9 : (isHovered ? 1.05 : 1.0)

                    Image {
                        id: zoomInIcon
                        anchors.centerIn: parent
                        width: 18
                        height: 18
                        source: "qrc:/qlementine/icons/16/action/zoom-in.svg"
                        sourceSize: Qt.size(18, 18)
                        visible: false
                    }
                    ColorOverlay {
                        anchors.fill: zoomInIcon
                        source: zoomInIcon
                        color: iconColor
                        opacity: 0.9
                    }

                    TapHandler {
                        id: zoomInTap
                        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                        acceptedButtons: Qt.LeftButton
                        
                        onTapped: zoomInClicked()
                        onPressedChanged: zoomInButton.isPressed = pressed
                    }
                    
                    HoverHandler {
                        id: zoomInHover
                        cursorShape: Qt.PointingHandCursor
                        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                        onHoveredChanged: zoomInButton.isHovered = hovered
                    }
                }
            }

            // Separator
            Rectangle {
                Layout.preferredWidth: 1
                Layout.preferredHeight: 24
                color: Qt.rgba(255, 255, 255, 0.15)
            }

            // Fit to window
            Item {
                Layout.preferredWidth: 32
                Layout.preferredHeight: 32

                Rectangle {
                    id: fitButton
                    anchors.fill: parent
                    radius: 8
                    property bool isHovered: false
                    property bool isPressed: false
                    
                    color: isPressed
                           ? pressedButtonColor
                           : (isHovered
                              ? hoverButtonColor
                              : "transparent")
                    
                    Behavior on color {
                        ColorAnimation { duration: 200; easing.type: Easing.OutCubic }
                    }
                    Behavior on scale {
                        NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                    }
                    
                    scale: isPressed ? 0.9 : (isHovered ? 1.05 : 1.0)

                    Image {
                        id: fitIcon
                        anchors.centerIn: parent
                        width: 18
                        height: 18
                        source: "qrc:/qlementine/icons/16/action/fullscreen.svg"
                        sourceSize: Qt.size(18, 18)
                        visible: false
                    }
                    ColorOverlay {
                        anchors.fill: fitIcon
                        source: fitIcon
                        color: iconColor
                        opacity: zoomFactor === 1.0 ? 1.0 : 0.9
                        
                        Behavior on color {
                            ColorAnimation { duration: 200; easing.type: Easing.OutCubic }
                        }
                    }

                    TapHandler {
                        id: fitTap
                        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                        acceptedButtons: Qt.LeftButton
                        
                        onTapped: fitToWindowClicked()
                        onPressedChanged: fitButton.isPressed = pressed
                    }
                    
                    HoverHandler {
                        id: fitHover
                        cursorShape: Qt.PointingHandCursor
                        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                        onHoveredChanged: fitButton.isHovered = hovered
                    }
                }
                
                // Tooltip for fit button - positioned using button Item's actual position
                Rectangle {
                    id: fitTooltip
                    parent: imageControls
                    width: fitTooltipText.width + 20
                    height: fitTooltipText.height + 12
                    radius: 10
                    // Use the same dynamic color as the controls bar
                    color: Qt.rgba(
                        Qt.lighter(accentColor, 1.1).r,
                        Qt.lighter(accentColor, 1.1).g,
                        Qt.lighter(accentColor, 1.1).b,
                        0.95
                    )
                    border.color: Qt.rgba(255, 255, 255, 0.2)
                    border.width: 1
                    visible: fitHover.hovered
                    z: 1000
                    
                    // Calculate position: RowLayout position + button Item position + button center
                    x: {
                        var buttonItem = fitButton.parent
                        if (!buttonItem || !controlsRowLayout) return 0
                        // Get RowLayout's position in imageControls
                        var layoutX = controlsRowLayout.x
                        // Get button Item's x position in RowLayout (it's the accumulated x from previous items)
                        var itemX = buttonItem.x
                        // Center: layout x + item x + item width/2 - tooltip width/2
                        return layoutX + itemX + (buttonItem.width / 2) - (width / 2)
                    }
                    y: {
                        var buttonItem = fitButton.parent
                        if (!buttonItem || !controlsRowLayout) return 0
                        // Get RowLayout's position in imageControls
                        var layoutY = controlsRowLayout.y
                        // Position above: layout y + item y - tooltip height - margin
                        return layoutY + buttonItem.y - height - 10
                    }
                    
                    // Smooth animations
                    opacity: visible ? 1 : 0
                    scale: visible ? 1.0 : 0.8
                    
                    Behavior on opacity { 
                        NumberAnimation { 
                            duration: 250
                            easing.type: Easing.OutCubic 
                        } 
                    }
                    Behavior on scale {
                        NumberAnimation {
                            duration: 250
                            easing.type: Easing.OutCubic
                        }
                    }
                    
                    DropShadow {
                        anchors.fill: fitTooltip
                        source: fitTooltip
                        radius: 20
                        samples: 41
                        color: Qt.rgba(0, 0, 0, 0.5)
                        verticalOffset: 4
                        horizontalOffset: 0
                    }
                    
                    Text {
                        id: fitTooltipText
                        anchors.centerIn: parent
                        text: "Fit to window"
                        // Use dynamic icon color based on background luminance
                        color: iconColor
                        font.pixelSize: 12
                        font.family: "Segoe UI"
                        font.weight: Font.Medium
                        opacity: 0.9
                    }
                }
            }

            // 100% / Actual size
            Item {
                Layout.preferredWidth: 32
                Layout.preferredHeight: 32

                Rectangle {
                    id: actualButton
                    anchors.fill: parent
                    radius: 8
                    property bool isHovered: false
                    property bool isPressed: false
                    
                    color: isPressed
                           ? pressedButtonColor
                           : (isHovered
                              ? hoverButtonColor
                              : "transparent")
                    
                    Behavior on color {
                        ColorAnimation { duration: 200; easing.type: Easing.OutCubic }
                    }
                    Behavior on scale {
                        NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                    }
                    
                    scale: isPressed ? 0.9 : (isHovered ? 1.05 : 1.0)

                    Text {
                        anchors.centerIn: parent
                        text: "1:1"
                        color: iconColor
                        font.pixelSize: 11
                        font.weight: Font.Bold
                        font.family: "Segoe UI"
                        opacity: 0.9
                    }

                    TapHandler {
                        id: actualTap
                        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                        acceptedButtons: Qt.LeftButton
                        
                        onTapped: actualSizeClicked()
                        onPressedChanged: actualButton.isPressed = pressed
                    }
                    
                    HoverHandler {
                        id: actualHover
                        cursorShape: Qt.PointingHandCursor
                        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                        onHoveredChanged: actualButton.isHovered = hovered
                    }
                }
                
                // Tooltip for actual size button - positioned using button Item's actual position
                Rectangle {
                    id: actualTooltip
                    parent: imageControls
                    width: actualTooltipText.width + 20
                    height: actualTooltipText.height + 12
                    radius: 10
                    // Use the same dynamic color as the controls bar
                    color: Qt.rgba(
                        Qt.lighter(accentColor, 1.1).r,
                        Qt.lighter(accentColor, 1.1).g,
                        Qt.lighter(accentColor, 1.1).b,
                        0.95
                    )
                    border.color: Qt.rgba(255, 255, 255, 0.2)
                    border.width: 1
                    visible: actualHover.hovered
                    z: 1000
                    
                    // Calculate position: RowLayout position + button Item position + button center
                    x: {
                        var buttonItem = actualButton.parent
                        if (!buttonItem || !controlsRowLayout) return 0
                        // Get RowLayout's position in imageControls
                        var layoutX = controlsRowLayout.x
                        // Get button Item's x position in RowLayout (it's the accumulated x from previous items)
                        var itemX = buttonItem.x
                        // Center: layout x + item x + item width/2 - tooltip width/2
                        return layoutX + itemX + (buttonItem.width / 2) - (width / 2)
                    }
                    y: {
                        var buttonItem = actualButton.parent
                        if (!buttonItem || !controlsRowLayout) return 0
                        // Get RowLayout's position in imageControls
                        var layoutY = controlsRowLayout.y
                        // Position above: layout y + item y - tooltip height - margin
                        return layoutY + buttonItem.y - height - 10
                    }
                    
                    // Smooth animations
                    opacity: visible ? 1 : 0
                    scale: visible ? 1.0 : 0.8
                    
                    Behavior on opacity { 
                        NumberAnimation { 
                            duration: 250
                            easing.type: Easing.OutCubic 
                        } 
                    }
                    Behavior on scale {
                        NumberAnimation {
                            duration: 250
                            easing.type: Easing.OutCubic
                        }
                    }
                    
                    DropShadow {
                        anchors.fill: actualTooltip
                        source: actualTooltip
                        radius: 20
                        samples: 41
                        color: Qt.rgba(0, 0, 0, 0.5)
                        verticalOffset: 4
                        horizontalOffset: 0
                    }
                    
                    Text {
                        id: actualTooltipText
                        anchors.centerIn: parent
                        text: "Actual size (100%)"
                        // Use dynamic icon color based on background luminance
                        color: iconColor
                        font.pixelSize: 12
                        font.family: "Segoe UI"
                        font.weight: Font.Medium
                        opacity: 0.9
                    }
                }
            }

            // Spacer
            Item {
                Layout.fillWidth: true
            }

            // Rotate left
            Item {
                Layout.preferredWidth: 32
                Layout.preferredHeight: 32

                Rectangle {
                    id: rotateLeftButton
                    anchors.fill: parent
                    radius: 8
                    property bool isHovered: false
                    property bool isPressed: false
                    
                    color: isPressed
                           ? pressedButtonColor
                           : (isHovered
                              ? hoverButtonColor
                              : "transparent")
                    
                    Behavior on color {
                        ColorAnimation { duration: 200; easing.type: Easing.OutCubic }
                    }
                    Behavior on scale {
                        NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                    }
                    
                    scale: isPressed ? 0.9 : (isHovered ? 1.05 : 1.0)

                    Text {
                        anchors.centerIn: parent
                        text: "↺"
                        color: iconColor
                        font.pixelSize: 18
                        font.family: "Segoe UI"
                        opacity: 0.9
                    }

                    TapHandler {
                        id: rotateLeftTap
                        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                        acceptedButtons: Qt.LeftButton
                        
                        onTapped: rotateLeftClicked()
                        onPressedChanged: rotateLeftButton.isPressed = pressed
                    }
                    
                    HoverHandler {
                        id: rotateLeftHover
                        cursorShape: Qt.PointingHandCursor
                        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                        onHoveredChanged: rotateLeftButton.isHovered = hovered
                    }
                }
            }

            // Rotate right
            Item {
                Layout.preferredWidth: 32
                Layout.preferredHeight: 32

                Rectangle {
                    id: rotateRightButton
                    anchors.fill: parent
                    radius: 8
                    property bool isHovered: false
                    property bool isPressed: false
                    
                    color: isPressed
                           ? pressedButtonColor
                           : (isHovered
                              ? hoverButtonColor
                              : "transparent")
                    
                    Behavior on color {
                        ColorAnimation { duration: 200; easing.type: Easing.OutCubic }
                    }
                    Behavior on scale {
                        NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                    }
                    
                    scale: isPressed ? 0.9 : (isHovered ? 1.05 : 1.0)

                    Text {
                        anchors.centerIn: parent
                        text: "↻"
                        color: iconColor
                        font.pixelSize: 18
                        font.family: "Segoe UI"
                        opacity: 0.9
                    }

                    TapHandler {
                        id: rotateRightTap
                        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                        acceptedButtons: Qt.LeftButton
                        
                        onTapped: rotateRightClicked()
                        onPressedChanged: rotateRightButton.isPressed = pressed
                    }
                    
                    HoverHandler {
                        id: rotateRightHover
                        cursorShape: Qt.PointingHandCursor
                        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                        onHoveredChanged: rotateRightButton.isHovered = hovered
                    }
                }
            }
        }
    }

    // Thumbnail popup - positioned above the counter
    ImageThumbnailPopup {
        id: thumbnailPopup
        anchors.bottom: parent.top
        anchors.bottomMargin: 8
        anchors.horizontalCenter: parent.horizontalCenter
        currentIndex: imageControls.currentIndex
        directoryImages: imageControls.directoryImages
        accentColor: imageControls.accentColor
        imageControlsHideTimer: imageControls.imageControlsHideTimer
        z: 200  // Higher z-order to ensure it captures events
        
        onThumbnailClicked: function(index) {
            thumbnailNavigationRequested(index)
            hide()
        }
    }
    
    // Function to hide thumbnail popup (exposed for external use)
    function hideThumbnailPopup() {
        thumbnailPopup.hide()
    }
    
}
