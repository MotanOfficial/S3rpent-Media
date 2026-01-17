import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import QtQuick.Controls
import QtMultimedia
import Qt5Compat.GraphicalEffects

Item {
    id: audioControls
    clip: false  // Don't clip tooltips that extend outside

    property int position: 0
    property int duration: 0
    property real volume: 1.0
    property int playbackState: 0
    property bool seekable: false
    property color accentColor: "#ffffff"
    property bool muted: false
    property real pitch: 1.0
    property real tempo: 1.0
    property bool showEQ: false
    property var eqBands: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]  // 10-band EQ, values from -12 to +12 dB
    property bool eqEnabled: false  // EQ enabled state
    property bool loop: false  // Loop playback state
    
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

    signal playClicked()
    signal pauseClicked()
    signal seekRequested(real position)
    signal seekReleased()  // Emitted when user releases the progress bar
    signal volumeAdjusted(real volume)
    signal muteToggled(bool muted)
    signal loopClicked()
    signal moreClicked()
    signal pitchAdjusted(real pitch)
    signal tempoAdjusted(real tempo)
    signal eqBandChanged(int band, real value)
    signal eqToggled(bool enabled)

    // Helper function to get volume icon path based on volume level and muted state
    function getVolumeIconPath() {
        if (muted) return "qrc:/qlementine/icons/16/audio/speaker-mute.svg"
        if (volume === 0) return "qrc:/qlementine/icons/16/audio/speaker-0.svg"
        if (volume < 0.33) return "qrc:/qlementine/icons/16/audio/speaker-0.svg"
        if (volume < 0.66) return "qrc:/qlementine/icons/16/audio/speaker-1.svg"
        return "qrc:/qlementine/icons/16/audio/speaker-2.svg"
    }

    function formatTime(ms) {
        if (!ms || ms <= 0) return "0:00"
        const totalSeconds = Math.floor(ms / 1000)
        return Math.floor(totalSeconds / 60) + ":" +
               (totalSeconds % 60 < 10 ? "0" : "") + (totalSeconds % 60)
    }

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

            // Main controls row: [Play/Pause] [Volume] [Progress Bar] [Loop] [More]
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

                // LEFT SIDE: Play/Pause icon
                Item {
                    Layout.preferredWidth: 36
                    Layout.preferredHeight: 36
                    Layout.alignment: Qt.AlignVCenter

                    Rectangle {
                        id: playPauseButton
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
                            id: playPauseIcon
                            anchors.centerIn: parent
                            width: 18
                            height: 18
                            source: (playbackState === MediaPlayer.PlayingState || playbackState === 1)
                                   ? "qrc:/qlementine/icons/16/media/pause.svg"
                                   : "qrc:/qlementine/icons/16/media/play.svg"
                            sourceSize: Qt.size(18, 18)
                            visible: false
                        }
                        ColorOverlay {
                            anchors.fill: playPauseIcon
                            source: playPauseIcon
                            color: iconColor
                            opacity: 0.9
                        }

                        TapHandler {
                            id: playPauseTap
                            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                            acceptedButtons: Qt.LeftButton
                            
                            onTapped: (playbackState === MediaPlayer.PlayingState || playbackState === 1)
                                       ? pauseClicked()
                                       : playClicked()
                            onPressedChanged: playPauseButton.isPressed = pressed
                        }
                        
                        HoverHandler {
                            id: playPauseHover
                            cursorShape: Qt.PointingHandCursor
                            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                            onHoveredChanged: playPauseButton.isHovered = hovered
                        }
                    }
                }

                // Volume icon
                Item {
                    id: volumeIconContainer
                    Layout.preferredWidth: 36
                    Layout.preferredHeight: 36
                    Layout.alignment: Qt.AlignVCenter

                    property bool volumeHovered: false

                    Rectangle {
                        id: volumeButton
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
                            id: volumeIcon
                            anchors.centerIn: parent
                            width: 18
                            height: 18
                            source: getVolumeIconPath()
                            sourceSize: Qt.size(18, 18)
                            visible: false
                        }
                        ColorOverlay {
                            anchors.fill: volumeIcon
                            source: volumeIcon
                            color: iconColor
                            opacity: 0.9
                        }

                        TapHandler {
                            id: volumeButtonTap
                            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                            acceptedButtons: Qt.LeftButton
                            
                            onTapped: { muted=!muted; muteToggled(muted)}
                            onPressedChanged: volumeButton.isPressed = pressed
                        }
                        
                        HoverHandler {
                            id: volumeButtonHover
                            cursorShape: Qt.PointingHandCursor
                            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                            onHoveredChanged: {
                                volumeButton.isHovered = hovered
                                if (hovered) {
                                    volumeIconContainer.volumeHovered = true
                                } else {
                                // Small delay to allow moving to popup
                                volumeHoverTimer.restart()
                            }
                            }
                        }
                    }

                    Timer {
                        id: volumeHoverTimer
                        interval: 100
                        onTriggered: {
                            // Don't hide if slider is being dragged
                            if (!volumePopupHover.hovered && !volumeSliderArea.containsMouse && !volumeButtonHover.hovered && !volumeSliderArea.pressed) {
                                volumeIconContainer.volumeHovered = false
                            }
                        }
                    }

                    // Volume dropdown popup - positioned outside to avoid clipping
                    Rectangle {
                        id: volumePopup
                        parent: audioControls
                        width: 120
                        height: 50
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
                        visible: volumeIconContainer.volumeHovered
                        opacity: visible ? 1 : 0
                        scale: visible ? 1.0 : 0.8
                        z: 1000
                        
                        // Calculate position: RowLayout position + button Item position + button center
                        x: {
                            var buttonItem = volumeIconContainer
                            if (!buttonItem || !controlsRowLayout) return 0
                            // Get RowLayout's position in audioControls
                            var layoutX = controlsRowLayout.x
                            // Get button Item's x position in RowLayout
                            var itemX = buttonItem.x
                            // Center: layout x + item x + item width/2 - popup width/2
                            return layoutX + itemX + (buttonItem.width / 2) - (width / 2)
                        }
                        y: {
                            var buttonItem = volumeIconContainer
                            if (!buttonItem || !controlsRowLayout) return 0
                            // Get RowLayout's position in audioControls
                            var layoutY = controlsRowLayout.y
                            // Position above: layout y + item y - popup height - margin
                            return layoutY + buttonItem.y - height - 10
                        }
                        
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
                        
                        // Modern drop shadow using layer (like main background)
                        layer.enabled: true
                        layer.effect: DropShadow {
                            radius: 20
                            samples: 41
                            color: Qt.rgba(0, 0, 0, 0.5)
                            verticalOffset: 4
                            horizontalOffset: 0
                        }

                        // HoverHandler to keep popup visible when hovering over it
                        HoverHandler {
                            id: volumePopupHover
                            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                            onHoveredChanged: {
                                if (hovered) {
                                    volumeIconContainer.volumeHovered = true
                                } else {
                                // Small delay to allow moving back to button
                                volumeHoverTimer.restart()
                                }
                            }
                        }

                        // Volume slider (horizontal)
                        Item {
                            id: volumeSliderContainer
                            anchors.centerIn: parent
                            width: 100
                            height: 4

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width
                                height: parent.height
                                radius: 2
                                color: Qt.rgba(255,255,255,0.2)

                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width * volume
                                    height: parent.height
                                    radius: 2
                                    color: accentColor
                                    Behavior on width { NumberAnimation { duration: 100 } }
                                }
                            }

                            Rectangle {
                                id: volumeHandle
                                anchors.verticalCenter: parent.verticalCenter
                                width: 12; height: 12; radius: 6
                                color: accentColor
                                x: parent.width * volume - width/2
                                opacity: volumeSliderArea.containsMouse ? 1 : 0
                                Behavior on opacity { NumberAnimation{duration:150} }
                                Behavior on x { NumberAnimation { duration: 100 } }
                            }

                            MouseArea {
                                id: volumeSliderArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                z: 1  // Above the popup HoverHandler
                                propagateComposedEvents: true

                                onEntered: volumeIconContainer.volumeHovered = true
                                onExited: {
                                    // Only hide if not dragging
                                    if (!pressed) {
                                        volumeHoverTimer.restart()
                                    }
                                }

                                onPositionChanged: (mouse)=>{
                                    if (!pressed) return;
                                    // Keep popup visible while dragging
                                    volumeIconContainer.volumeHovered = true
                                    let v = Math.max(0, Math.min(1, mouse.x / parent.width))
                                    if (muted && v>0) { muted=false; muteToggled(false) }
                                    volumeAdjusted(v)
                                }
                                onReleased: {
                                    // Small delay after release to allow moving back
                                    volumeHoverTimer.restart()
                                }
                                onClicked: (mouse)=>{
                                    let v = Math.max(0, Math.min(1, mouse.x / parent.width))
                                    if (muted && v>0) { muted=false; muteToggled(false) }
                                    volumeAdjusted(v)
                                }
                            }
                        }
                    }
                }

                // CENTER: Progress bar
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 2

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        Layout.alignment: Qt.AlignVCenter

                        // current time
                        Text {
                            Layout.preferredWidth: 35
                            color: iconColor
                            font.pixelSize: 12
                            font.weight: Font.Medium
                            horizontalAlignment: Text.AlignRight
                            text: formatTime(position)
                            opacity: 0.9
                        }

                        // progress bar
                        Item {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 6

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width
                                height: 4
                                radius: 2
                                color: Qt.rgba(255,255,255,0.2)

                                Rectangle {
                                    width: duration > 0 ? parent.width * position / duration : 0
                                    height: parent.height
                                    radius: 2
                                    color: accentColor
                                    Behavior on width { NumberAnimation { duration: 100 } }
                                }
                            }

                            Rectangle {
                                id: handle
                                anchors.verticalCenter: parent.verticalCenter
                                width: 12; height: 12; radius: 6
                                color: accentColor
                                x: duration > 0 ? (parent.width * position / duration - width/2) : -100
                                opacity: progressArea.containsMouse ? 1 : 0
                                Behavior on opacity { NumberAnimation{duration:150} }
                            }

                            MouseArea {
                                id: progressArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor

                                onPressed: (mouse)=>{
                                    if (!seekable || duration<=0) return;
                                    const newPos = (mouse.x/parent.width)*duration
                                    seekRequested(Math.max(0, Math.min(newPos, duration)))
                                }

                                onPositionChanged: (mouse)=>{
                                    if (!pressed || !seekable || duration<=0) return;
                                    const newPos = (mouse.x/parent.width)*duration
                                    seekRequested(Math.max(0, Math.min(newPos, duration)))
                                }
                                
                                onReleased: {
                                    // Emit seekReleased when user releases the progress bar
                                    // This allows immediate commit of the seek (no timer delay)
                                    seekReleased()
                                }
                            }
                        }

                        // total time
                        Text {
                            Layout.preferredWidth: 35
                            color: iconColor
                            font.pixelSize: 12
                            font.weight: Font.Medium
                            horizontalAlignment: Text.AlignLeft
                            text: formatTime(duration)
                            opacity: 0.9
                        }
                    }
                }

                // RIGHT SIDE: Loop icon
                Item {
                    Layout.preferredWidth: 36
                    Layout.preferredHeight: 36
                    Layout.alignment: Qt.AlignVCenter

                    Rectangle {
                        id: loopButton
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
                            id: loopIcon
                            anchors.centerIn: parent
                            width: 18
                            height: 18
                            source: "qrc:/qlementine/icons/16/media/repeat.svg"
                            sourceSize: Qt.size(18, 18)
                            visible: false
                        }
                        ColorOverlay {
                            anchors.fill: loopIcon
                            source: loopIcon
                            color: loop ? accentColor : iconColor
                            opacity: 0.9
                        }

                        TapHandler {
                            id: loopTap
                            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                            acceptedButtons: Qt.LeftButton
                            
                            onTapped: loopClicked()
                            onPressedChanged: loopButton.isPressed = pressed
                        }
                        
                        HoverHandler {
                            id: loopHover
                            cursorShape: Qt.PointingHandCursor
                            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                            onHoveredChanged: loopButton.isHovered = hovered
                        }
                    }
                }

                // RIGHT SIDE: More icon (three dots)
                Item {
                    id: moreIconContainer
                    Layout.preferredWidth: 36
                    Layout.preferredHeight: 36
                    Layout.alignment: Qt.AlignVCenter

                    property bool moreHovered: false

                    Rectangle {
                        id: moreButton
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
                            id: moreIcon
                            anchors.centerIn: parent
                            width: 18
                            height: 18
                            source: "qrc:/qlementine/icons/16/navigation/menu-dots.svg"
                            sourceSize: Qt.size(18, 18)
                            visible: false
                        }
                        ColorOverlay {
                            anchors.fill: moreIcon
                            source: moreIcon
                            color: iconColor
                            opacity: 0.9
                        }

                        TapHandler {
                            id: moreTap
                            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                            acceptedButtons: Qt.LeftButton
                            
                            onTapped: moreClicked()
                            onPressedChanged: moreButton.isPressed = pressed
                        }
                        
                        HoverHandler {
                            id: moreHover
                            cursorShape: Qt.PointingHandCursor
                            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                            onHoveredChanged: {
                                moreButton.isHovered = hovered
                                if (hovered) {
                                    moreIconContainer.moreHovered = true
                                } else {
                                moreHoverTimer.restart()
                            }
                            }
                        }
                    }

                    Timer {
                        id: moreHoverTimer
                        interval: 100
                        onTriggered: {
                            if (!morePopupHover.hovered && !moreHover.hovered && 
                                !pitchSliderArea.containsMouse && !tempoSliderArea.containsMouse &&
                                !eqButtonHover.hovered &&
                                !pitchSliderArea.pressed && !tempoSliderArea.pressed) {
                                moreIconContainer.moreHovered = false
                            }
                        }
                    }

                    // More options dropdown popup - positioned outside to avoid clipping
                    Rectangle {
                        id: morePopup
                        parent: audioControls
                        width: 140
                        height: 120
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
                        visible: moreIconContainer.moreHovered
                        opacity: visible ? 1 : 0
                        scale: visible ? 1.0 : 0.8
                        z: 1000
                        
                        // Calculate position: RowLayout position + button Item position + button center
                        x: {
                            var buttonItem = moreIconContainer
                            if (!buttonItem || !controlsRowLayout) return 0
                            // Get RowLayout's position in audioControls
                            var layoutX = controlsRowLayout.x
                            // Get button Item's x position in RowLayout
                            var itemX = buttonItem.x
                            // Center: layout x + item x + item width/2 - popup width/2
                            return layoutX + itemX + (buttonItem.width / 2) - (width / 2)
                        }
                        y: {
                            var buttonItem = moreIconContainer
                            if (!buttonItem || !controlsRowLayout) return 0
                            // Get RowLayout's position in audioControls
                            var layoutY = controlsRowLayout.y
                            // Position above: layout y + item y - popup height - margin
                            return layoutY + buttonItem.y - height - 10
                        }
                        
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
                        
                        // Modern drop shadow using layer (like main background)
                        layer.enabled: true
                        layer.effect: DropShadow {
                            radius: 20
                            samples: 41
                            color: Qt.rgba(0, 0, 0, 0.5)
                            verticalOffset: 4
                            horizontalOffset: 0
                        }

                        // HoverHandler to keep popup visible when hovering over it
                        HoverHandler {
                            id: morePopupHover
                            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                            onHoveredChanged: {
                                if (hovered) {
                                    moreIconContainer.moreHovered = true
                                } else {
                                moreHoverTimer.restart()
                                }
                            }
                        }

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 12

                            // Pitch control
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 4

                                Text {
                                    Layout.fillWidth: true
                                    text: "Pitch: " + (pitch * 100).toFixed(0) + "%"
                                    color: iconColor
                                    font.pixelSize: 12
                                    font.weight: Font.Medium
                                    opacity: 0.9
                                }

                                Item {
                                    id: pitchSliderContainer
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 4

                                    Rectangle {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width
                                        height: parent.height
                                        radius: 2
                                        color: Qt.rgba(255, 255, 255, 0.2)

                                        Rectangle {
                                            anchors.left: parent.left
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: parent.width * ((pitch - 0.5) / 1.0)  // Map 0.5-1.5 to 0-1
                                            height: parent.height
                                            radius: 2
                                            color: accentColor
                                            Behavior on width { NumberAnimation { duration: 100 } }
                                        }
                                    }

                                    Rectangle {
                                        id: pitchHandle
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 12; height: 12; radius: 6
                                        color: accentColor
                                        x: parent.width * ((pitch - 0.5) / 1.0) - width/2
                                        opacity: pitchSliderArea.containsMouse ? 1 : 0
                                        Behavior on opacity { NumberAnimation { duration: 150 } }
                                        Behavior on x { NumberAnimation { duration: 100 } }
                                    }

                                    MouseArea {
                                        id: pitchSliderArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        z: 1
                                        propagateComposedEvents: true

                                        onEntered: moreIconContainer.moreHovered = true
                                        onExited: {
                                            if (!pressed) {
                                                moreHoverTimer.restart()
                                            }
                                        }

                                        onPositionChanged: (mouse)=>{
                                            if (!pressed) return;
                                            moreIconContainer.moreHovered = true
                                            let p = Math.max(0, Math.min(1, mouse.x / parent.width))
                                            // Map 0-1 to 0.5-1.5 (50% to 150%)
                                            let newPitch = 0.5 + p * 1.0
                                            pitch = newPitch
                                            pitchAdjusted(newPitch)
                                        }
                                        onReleased: {
                                            moreHoverTimer.restart()
                                        }
                                        onClicked: (mouse)=>{
                                            let p = Math.max(0, Math.min(1, mouse.x / parent.width))
                                            let newPitch = 0.5 + p * 1.0
                                            pitch = newPitch
                                            pitchAdjusted(newPitch)
                                        }
                                    }
                                }
                            }

                            // Tempo control
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 4

                                Text {
                                    Layout.fillWidth: true
                                    text: "Tempo: " + (tempo * 100).toFixed(0) + "%"
                                    color: iconColor
                                    font.pixelSize: 12
                                    font.weight: Font.Medium
                                    opacity: 0.9
                                }

                                Item {
                                    id: tempoSliderContainer
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 4

                                    Rectangle {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width
                                        height: parent.height
                                        radius: 2
                                        color: Qt.rgba(255, 255, 255, 0.2)

                                        Rectangle {
                                            anchors.left: parent.left
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: parent.width * ((tempo - 0.5) / 1.0)  // Map 0.5-1.5 to 0-1
                                            height: parent.height
                                            radius: 2
                                            color: accentColor
                                            Behavior on width { NumberAnimation { duration: 100 } }
                                        }
                                    }

                                    Rectangle {
                                        id: tempoHandle
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 12; height: 12; radius: 6
                                        color: accentColor
                                        x: parent.width * ((tempo - 0.5) / 1.0) - width/2
                                        opacity: tempoSliderArea.containsMouse ? 1 : 0
                                        Behavior on opacity { NumberAnimation { duration: 150 } }
                                        Behavior on x { NumberAnimation { duration: 100 } }
                                    }

                                    MouseArea {
                                        id: tempoSliderArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        z: 1
                                        propagateComposedEvents: true

                                        onEntered: moreIconContainer.moreHovered = true
                                        onExited: {
                                            if (!pressed) {
                                                moreHoverTimer.restart()
                                            }
                                        }

                                        onPositionChanged: (mouse)=>{
                                            if (!pressed) return;
                                            moreIconContainer.moreHovered = true
                                            let t = Math.max(0, Math.min(1, mouse.x / parent.width))
                                            // Map 0-1 to 0.5-1.5 (50% to 150%)
                                            let newTempo = 0.5 + t * 1.0
                                            tempo = newTempo
                                            tempoAdjusted(newTempo)
                                        }
                                        onReleased: {
                                            moreHoverTimer.restart()
                                        }
                                        onClicked: (mouse)=>{
                                            let t = Math.max(0, Math.min(1, mouse.x / parent.width))
                                            let newTempo = 0.5 + t * 1.0
                                            tempo = newTempo
                                            tempoAdjusted(newTempo)
                                        }
                                    }
                                }
                            }
                            
                            // EQ button
                            Rectangle {
                                id: eqButton
                                Layout.fillWidth: true
                                Layout.preferredHeight: 32
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
                                
                                scale: isPressed ? 0.95 : (isHovered ? 1.02 : 1.0)
                                
                                Text {
                                    anchors.centerIn: parent
                                    text: "Equalizer"
                                    color: iconColor
                                    font.pixelSize: 12
                                    font.weight: Font.Medium
                                    opacity: 0.9
                                }
                                
                                TapHandler {
                                    id: eqButtonTap
                                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                                    acceptedButtons: Qt.LeftButton
                                    
                                    onTapped: {
                                        showEQ = !showEQ
                                        eqToggled(showEQ)
                                    }
                                    onPressedChanged: eqButton.isPressed = pressed
                                }
                                
                                HoverHandler {
                                    id: eqButtonHover
                                    cursorShape: Qt.PointingHandCursor
                                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                                    onHoveredChanged: {
                                        eqButton.isHovered = hovered
                                        if (hovered) {
                                        moreIconContainer.moreHovered = true
                                        moreHoverTimer.stop()
                                        } else {
                                        moreHoverTimer.restart()
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    // EQ Popup (centered on screen) - styled like MetadataPopup
    Popup {
        id: eqPopup
        // Find the root window/item for proper sizing and centering
        property var rootWindow: {
            var item = audioControls.parent
            while (item && item.parent) {
                item = item.parent
            }
            return item
        }
        
        // Set parent to root window for proper centering
        parent: rootWindow
        
        width: Math.min(600, (rootWindow ? rootWindow.width - 80 : 600))
        height: Math.min(450, (rootWindow ? rootWindow.height - 80 : 450))
        modal: true
        focus: true
        closePolicy: Popup.CloseOnPressOutside | Popup.CloseOnEscape
        visible: showEQ
        
        // Center the popup properly relative to root window
        x: rootWindow ? Math.max(0, (rootWindow.width - width) / 2) : 0
        y: rootWindow ? Math.max(0, (rootWindow.height - height) / 2) : 0
        
        background: Rectangle {
            id: eqPopupBackground
            radius: 20
            // Use dynamic color like MetadataPopup (lighter for better visibility)
            color: Qt.rgba(
                Qt.lighter(accentColor, 1.3).r,
                Qt.lighter(accentColor, 1.3).g,
                Qt.lighter(accentColor, 1.3).b,
                0.95
            )
            border.width: 0
            
            // Modern drop shadow matching MetadataPopup style
            layer.enabled: true
            layer.effect: DropShadow {
                transparentBorder: true
                horizontalOffset: 0
                verticalOffset: 4
                radius: 16
                samples: 32
                color: Qt.rgba(0, 0, 0, 0.25)
            }
            
            // Entrance animation matching MetadataPopup
            scale: 0.9
            opacity: 0
            Behavior on scale {
                NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
            }
            Behavior on opacity {
                NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
            }
            Component.onCompleted: {
                if (eqPopup.visible) {
                    scale = 1.0
                    opacity = 1.0
                }
            }
        }
        
        // Update animation when popup becomes visible
        onVisibleChanged: {
            if (visible) {
                eqPopupBackground.scale = 1.0
                eqPopupBackground.opacity = 1.0
                // Sync EQ enabled state when popup opens
                // Signal will be emitted to parent to sync state
            } else {
                eqPopupBackground.scale = 0.9
                eqPopupBackground.opacity = 0.0
            }
        }
        
        onClosed: {
            showEQ = false
        }
        
        // Header with close button (styled like MetadataPopup)
        Rectangle {
            id: eqHeader
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 56
            color: "transparent"
            radius: 20
            clip: true
            
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 24
                anchors.rightMargin: 16
                spacing: 16
                
                Text {
                    Layout.fillWidth: true
                    text: "Equalizer"
                    color: iconColor
                    font.pixelSize: 20
                    font.weight: Font.Medium
                    font.letterSpacing: 0.5
                }
                
                // Close button (styled like MetadataPopup)
                Rectangle {
                    id: closeButton
                    Layout.preferredWidth: 32
                    Layout.preferredHeight: 32
            radius: 8
            property bool isPressed: false
                    color: closeButtonHover.hovered
                           ? (isPressed 
                              ? Qt.rgba(0.9, 0.2, 0.2, 0.3)
                              : Qt.rgba(0.9, 0.2, 0.2, 0.2))
                           : "transparent"
            
            Behavior on color {
                        ColorAnimation { duration: 150; easing.type: Easing.OutCubic }
            }
            Behavior on scale {
                NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
            }
            
                    property real scale: 1.0
                    transform: Scale { xScale: closeButton.scale; yScale: closeButton.scale }
            
                    Image {
                        id: closeIcon
                anchors.centerIn: parent
                        source: "qrc:/qlementine/icons/16/action/windows-close.svg"
                        sourceSize: Qt.size(16, 16)
                        ColorOverlay {
                            anchors.fill: closeIcon
                            source: closeIcon
                color: iconColor
                opacity: 0.9
                        }
            }
            
            TapHandler {
                id: closeButtonTap
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                acceptedButtons: Qt.LeftButton
                        gesturePolicy: TapHandler.ReleaseWithinBounds
                onTapped: {
                    showEQ = false
                    eqToggled(false)
                }
                        onPressedChanged: {
                            closeButton.isPressed = pressed
                            if (pressed) {
                                closeButton.scale = 0.9
                            } else {
                                closeButton.scale = closeButtonHover.hovered ? 1.05 : 1.0
                            }
                        }
                    }
            HoverHandler {
                id: closeButtonHover
                cursorShape: Qt.PointingHandCursor
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                        onHoveredChanged: {
                            if (hovered && !closeButton.isPressed) {
                                closeButton.scale = 1.05
                            } else if (!hovered && !closeButton.isPressed) {
                                closeButton.scale = 1.0
                            }
                        }
                    }
                }
            }
        }
        
        ColumnLayout {
            anchors.fill: parent
            anchors.topMargin: 56  // Account for header
            anchors.margins: 24
            spacing: 16
            
            // Enable/Disable Toggle (moved below header)
            RowLayout {
                Layout.fillWidth: true
                spacing: 16
                
                Item {
                    Layout.fillWidth: true
                }
                
                // Enable/Disable Toggle
                Rectangle {
                    id: eqToggleButton
                    Layout.preferredWidth: 80
                    Layout.preferredHeight: 32
                    radius: 16
                    property bool isHovered: false
                    property bool isPressed: false
                    
                    color: isPressed
                           ? pressedButtonColor
                           : (audioControls.eqEnabled 
                              ? accentColor 
                              : (isHovered ? hoverButtonColor : Qt.rgba(255, 255, 255, 0.2)))
                    border.color: Qt.rgba(255, 255, 255, 0.3)
                    border.width: 1
                    
                    Behavior on color {
                        ColorAnimation { duration: 200; easing.type: Easing.OutCubic }
                    }
                    Behavior on scale {
                        NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                    }
                    
                    scale: isPressed ? 0.95 : (isHovered ? 1.02 : 1.0)
                    
                    Text {
                        anchors.centerIn: parent
                        text: audioControls.eqEnabled ? "ON" : "OFF"
                        color: iconColor
                        font.pixelSize: 12
                        font.weight: Font.Bold
                        opacity: 0.9
                    }
                    
                    TapHandler {
                        id: eqToggleTap
                        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                        acceptedButtons: Qt.LeftButton
                        
                        onTapped: {
                            audioControls.eqEnabled = !audioControls.eqEnabled
                            eqToggled(audioControls.eqEnabled)
                        }
                        onPressedChanged: eqToggleButton.isPressed = pressed
                    }
                    
                    HoverHandler {
                        id: eqToggleHover
                        cursorShape: Qt.PointingHandCursor
                        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                        onHoveredChanged: eqToggleButton.isHovered = hovered
                    }
                }
                
                Item {
                    Layout.fillWidth: true
                }
            }
            
            // EQ bands
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 8
                
                Repeater {
                    model: 10
                    
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 8
                        
                        property int bandIndex: model.index
                        property var freqs: ["31", "62", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"]
                        
                        // Frequency label
                        Text {
                            Layout.fillWidth: true
                            text: freqs[bandIndex] + " Hz"
                            color: iconColor
                            font.pixelSize: 10
                            font.weight: Font.Medium
                            horizontalAlignment: Text.AlignHCenter
                            opacity: 0.9
                        }
                        
                        // Vertical slider
                        Item {
                            id: eqSliderItem
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            
                            property real currentBandValue: (eqBands && eqBands[bandIndex] !== undefined) ? eqBands[bandIndex] : 0
                            
                            Rectangle {
                                anchors.centerIn: parent
                                width: 4
                                height: parent.height - 40
                                radius: 2
                                color: Qt.rgba(255, 255, 255, 0.2)
                                
                                Rectangle {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: parent.width
                                    height: Math.abs(eqSliderItem.currentBandValue / 12.0) * parent.height
                                    anchors.verticalCenter: parent.verticalCenter
                                    radius: 2
                                    color: eqSliderItem.currentBandValue >= 0 ? accentColor : "#ff6b6b"
                                    y: eqSliderItem.currentBandValue >= 0 
                                       ? parent.height / 2 - height
                                       : parent.height / 2
                                }
                            }
                            
                            Rectangle {
                                id: eqHandle
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: 24
                                height: 8
                                radius: 4
                                color: accentColor
                                y: parent.height / 2 - (eqSliderItem.currentBandValue / 12.0) * (parent.height - 40) / 2 - height / 2
                                opacity: eqSliderArea.containsMouse ? 1 : 0.7
                                Behavior on opacity { NumberAnimation { duration: 150 } }
                                Behavior on y { NumberAnimation { duration: 100 } }
                            }
                            
                            MouseArea {
                                id: eqSliderArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                
                                onPositionChanged: (mouse)=>{
                                    if (!pressed) return
                                    // Map mouse Y position to -12 to +12 dB
                                    let normalizedY = 1.0 - (mouse.y / parent.height)  // Invert Y axis
                                    let dbValue = (normalizedY - 0.5) * 24.0  // Map 0-1 to -12 to +12
                                    dbValue = Math.max(-12, Math.min(12, dbValue))
                                    
                                    // Update EQ band
                                    let newBands = eqBands.slice()
                                    newBands[bandIndex] = dbValue
                                    eqBands = newBands
                                    eqBandChanged(bandIndex, dbValue)
                                }
                                
                                onClicked: (mouse)=>{
                                    let normalizedY = 1.0 - (mouse.y / parent.height)
                                    let dbValue = (normalizedY - 0.5) * 24.0
                                    dbValue = Math.max(-12, Math.min(12, dbValue))
                                    
                                    let newBands = eqBands.slice()
                                    newBands[bandIndex] = dbValue
                                    eqBands = newBands
                                    eqBandChanged(bandIndex, dbValue)
                                }
                            }
                            
                            // Value label
                            Text {
                                anchors.bottom: parent.bottom
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: {
                                    let val = eqSliderItem.currentBandValue
                                    return (val >= 0 ? "+" : "") + val.toFixed(0) + " dB"
                                }
                                color: iconColor
                                font.pixelSize: 9
                                font.weight: Font.Medium
                                opacity: 0.9
                            }
                        }
                    }
                }
            }
            
            // Reset button
            Rectangle {
                id: resetButton
                Layout.fillWidth: true
                Layout.preferredHeight: 36
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
                
                scale: isPressed ? 0.95 : (isHovered ? 1.02 : 1.0)
                
                Text {
                    anchors.centerIn: parent
                    text: "Reset"
                    color: iconColor
                    font.pixelSize: 12
                    font.weight: Font.Medium
                    opacity: 0.9
                }
                
                TapHandler {
                    id: resetButtonTap
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    acceptedButtons: Qt.LeftButton
                    
                    onTapped: {
                        eqBands = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
                        for (let i = 0; i < 10; i++) {
                            eqBandChanged(i, 0)
                        }
                    }
                    onPressedChanged: resetButton.isPressed = pressed
                }
                
                HoverHandler {
                    id: resetButtonHover
                    cursorShape: Qt.PointingHandCursor
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onHoveredChanged: resetButton.isHovered = hovered
                }
            }
        }
    }
}
