import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import QtQuick.Controls
import QtMultimedia
import Qt5Compat.GraphicalEffects

Item {
    id: audioControls

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

    signal playClicked()
    signal pauseClicked()
    signal seekRequested(real position)
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
        radius: 12
        color: Qt.rgba(0, 0, 0, 0.85)
        border.color: Qt.rgba(255, 255, 255, 0.15)
        border.width: 1

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 8
            spacing: 2

            // Main controls row: [Play/Pause] [Volume] [Progress Bar] [Loop] [More]
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 32
                spacing: 8

                // LEFT SIDE: Play/Pause icon
                Item {
                    Layout.preferredWidth: 32
                    Layout.preferredHeight: 32

                    Rectangle {
                        id: playPauseButton
                        anchors.centerIn: parent
                        width: 32; height: 32
                        radius: 8
                        color: playPauseMouse.containsMouse
                               ? Qt.rgba(accentColor.r, accentColor.g, accentColor.b, 0.25)
                               : "transparent"

                        Image {
                            id: playPauseIcon
                            anchors.centerIn: parent
                            width: 20; height: 20
                            source: playbackState === MediaPlayer.PlayingState
                                   ? "qrc:/qlementine/icons/16/media/pause.svg"
                                   : "qrc:/qlementine/icons/16/media/play.svg"
                            sourceSize.width: 20
                            sourceSize.height: 20
                            fillMode: Image.PreserveAspectFit
                        }
                        ColorOverlay {
                            anchors.fill: playPauseIcon
                            source: playPauseIcon
                            color: "#ffffff"
                        }

                        MouseArea {
                            id: playPauseMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: playbackState === MediaPlayer.PlayingState
                                       ? pauseClicked()
                                       : playClicked()
                        }
                    }
                }

                // Volume icon
                Item {
                    id: volumeIconContainer
                    Layout.preferredWidth: 32
                    Layout.preferredHeight: 32

                    property bool volumeHovered: false

                    Rectangle {
                        id: volumeButton
                        anchors.centerIn: parent
                        width: 32; height: 32
                        radius: 8
                        color: volumeIconContainer.volumeHovered
                               ? Qt.rgba(accentColor.r, accentColor.g, accentColor.b, 0.25)
                               : "transparent"

                        Image {
                            id: volumeIcon
                            anchors.centerIn: parent
                            width: 20; height: 20
                            source: getVolumeIconPath()
                            sourceSize.width: 20
                            sourceSize.height: 20
                            fillMode: Image.PreserveAspectFit
                        }
                        ColorOverlay {
                            anchors.fill: volumeIcon
                            source: volumeIcon
                            color: "#ffffff"
                        }

                        MouseArea {
                            id: volumeButtonMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: volumeIconContainer.volumeHovered = true
                            onExited: {
                                // Small delay to allow moving to popup
                                volumeHoverTimer.restart()
                            }
                            onClicked: { muted=!muted; muteToggled(muted)} 
                        }
                    }

                    Timer {
                        id: volumeHoverTimer
                        interval: 100
                        onTriggered: {
                            // Don't hide if slider is being dragged
                            if (!volumePopupMouse.containsMouse && !volumeSliderArea.containsMouse && !volumeButtonMouse.containsMouse && !volumeSliderArea.pressed) {
                                volumeIconContainer.volumeHovered = false
                            }
                        }
                    }

                    // Volume dropdown popup
                    Rectangle {
                        id: volumePopup
                        anchors.bottom: parent.top
                        anchors.bottomMargin: 8
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 120
                        height: 50
                        radius: 8
                        color: Qt.rgba(0, 0, 0, 0.9)
                        border.color: Qt.rgba(255, 255, 255, 0.2)
                        border.width: 1
                        visible: volumeIconContainer.volumeHovered
                        opacity: visible ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 150 } }

                        // MouseArea to keep popup visible when hovering over it (covers entire popup including slider)
                        MouseArea {
                            id: volumePopupMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            propagateComposedEvents: true
                            acceptedButtons: Qt.NoButton  // Don't intercept clicks, let slider handle them
                            onEntered: volumeIconContainer.volumeHovered = true
                            onExited: {
                                // Small delay to allow moving back to button
                                volumeHoverTimer.restart()
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
                                z: 1  // Above the popup MouseArea
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
                    spacing: 2

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        Layout.alignment: Qt.AlignVCenter

                        // current time
                        Text {
                            Layout.preferredWidth: 35
                            color: "#ffffff"
                            font.pixelSize: 11
                            horizontalAlignment: Text.AlignRight
                            text: formatTime(position)
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
                            }
                        }

                        // total time
                        Text {
                            Layout.preferredWidth: 35
                            color: "#ffffff"
                            font.pixelSize: 11
                            horizontalAlignment: Text.AlignLeft
                            text: formatTime(duration)
                        }
                    }
                }

                // RIGHT SIDE: Loop icon
                Item {
                    Layout.preferredWidth: 32
                    Layout.preferredHeight: 32

                    Rectangle {
                        anchors.centerIn: parent
                        width: 32; height: 32
                        radius: 8
                        color: loopMouse.containsMouse
                               ? Qt.rgba(accentColor.r, accentColor.g, accentColor.b, 0.25)
                               : "transparent"

                        Image {
                            id: loopIcon
                            anchors.centerIn: parent
                            width: 20; height: 20
                            source: "qrc:/qlementine/icons/16/media/repeat.svg"
                            sourceSize.width: 20
                            sourceSize.height: 20
                            fillMode: Image.PreserveAspectFit
                        }
                        ColorOverlay {
                            anchors.fill: loopIcon
                            source: loopIcon
                            color: loop ? accentColor : "#ffffff"
                        }

                        MouseArea {
                            id: loopMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: loopClicked()
                        }
                    }
                }

                // RIGHT SIDE: More icon (three dots)
                Item {
                    id: moreIconContainer
                    Layout.preferredWidth: 32
                    Layout.preferredHeight: 32

                    property bool moreHovered: false

                    Rectangle {
                        anchors.centerIn: parent
                        width: 32; height: 32
                        radius: 8
                        color: moreIconContainer.moreHovered
                               ? Qt.rgba(accentColor.r, accentColor.g, accentColor.b, 0.25)
                               : "transparent"

                        Image {
                            id: moreIcon
                            anchors.centerIn: parent
                            width: 20; height: 20
                            source: "qrc:/qlementine/icons/16/navigation/menu-dots.svg"
                            sourceSize.width: 20
                            sourceSize.height: 20
                            fillMode: Image.PreserveAspectFit
                        }
                        ColorOverlay {
                            anchors.fill: moreIcon
                            source: moreIcon
                            color: "#ffffff"
                        }

                        MouseArea {
                            id: moreMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: moreIconContainer.moreHovered = true
                            onExited: {
                                moreHoverTimer.restart()
                            }
                            onClicked: moreClicked()
                        }
                    }

                    Timer {
                        id: moreHoverTimer
                        interval: 100
                        onTriggered: {
                            if (!morePopupMouse.containsMouse && !moreMouse.containsMouse && 
                                !pitchSliderArea.containsMouse && !tempoSliderArea.containsMouse &&
                                !eqButtonMouse.containsMouse &&
                                !pitchSliderArea.pressed && !tempoSliderArea.pressed) {
                                moreIconContainer.moreHovered = false
                            }
                        }
                    }

                    // More options dropdown popup
                    Rectangle {
                        id: morePopup
                        anchors.bottom: parent.top
                        anchors.bottomMargin: 8
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 140
                        height: 120
                        radius: 8
                        color: Qt.rgba(0, 0, 0, 0.9)
                        border.color: Qt.rgba(255, 255, 255, 0.2)
                        border.width: 1
                        visible: moreIconContainer.moreHovered
                        opacity: visible ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 150 } }

                        // MouseArea to keep popup visible when hovering over it
                        MouseArea {
                            id: morePopupMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            propagateComposedEvents: true
                            acceptedButtons: Qt.NoButton
                            onEntered: moreIconContainer.moreHovered = true
                            onExited: {
                                moreHoverTimer.restart()
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
                                    color: "#ffffff"
                                    font.pixelSize: 11
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
                                    color: "#ffffff"
                                    font.pixelSize: 11
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
                                Layout.fillWidth: true
                                Layout.preferredHeight: 32
                                radius: 6
                                color: eqButtonMouse.containsMouse 
                                       ? Qt.rgba(accentColor.r, accentColor.g, accentColor.b, 0.25)
                                       : "transparent"
                                
                                Text {
                                    anchors.centerIn: parent
                                    text: "Equalizer"
                                    color: "#ffffff"
                                    font.pixelSize: 11
                                }
                                
                                MouseArea {
                                    id: eqButtonMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    z: 1
                                    propagateComposedEvents: true
                                    
                                    onEntered: {
                                        moreIconContainer.moreHovered = true
                                        moreHoverTimer.stop()
                                    }
                                    onExited: {
                                        moreHoverTimer.restart()
                                    }
                                    onClicked: {
                                        showEQ = !showEQ
                                        eqToggled(showEQ)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    // EQ Popup (centered on screen)
    Popup {
        id: eqPopup
        parent: audioControls.parent
        anchors.centerIn: parent
        width: 600
        height: 400
        modal: true
        closePolicy: Popup.CloseOnPressOutside | Popup.CloseOnEscape
        visible: showEQ
        
        background: Rectangle {
            radius: 16
            color: Qt.rgba(0, 0, 0, 0.95)
            border.color: Qt.rgba(255, 255, 255, 0.2)
            border.width: 2
        }
        
        onVisibleChanged: {
            if (visible) {
                // Sync EQ enabled state when popup opens
                // Signal will be emitted to parent to sync state
            }
        }
        
        onClosed: {
            showEQ = false
        }
        
        // Close button
        Rectangle {
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: 12
            width: 32
            height: 32
            radius: 16
            color: closeButtonMouse.containsMouse 
                   ? Qt.rgba(accentColor.r, accentColor.g, accentColor.b, 0.3)
                   : Qt.rgba(255, 255, 255, 0.1)
            
            Text {
                anchors.centerIn: parent
                text: "×"
                color: "#ffffff"
                font.pixelSize: 24
                font.bold: true
            }
            
            MouseArea {
                id: closeButtonMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    showEQ = false
                    eqToggled(false)
                }
            }
        }
        
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 24
            spacing: 16
            
            // Title and Enable Toggle
            RowLayout {
                Layout.fillWidth: true
                spacing: 16
                
                Text {
                    Layout.fillWidth: true
                    text: "Equalizer"
                    color: "#ffffff"
                    font.pixelSize: 24
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                }
                
                // Enable/Disable Toggle
                Rectangle {
                    id: eqToggleButton
                    Layout.preferredWidth: 80
                    Layout.preferredHeight: 32
                    radius: 16
                    color: audioControls.eqEnabled ? accentColor : Qt.rgba(255, 255, 255, 0.2)
                    border.color: Qt.rgba(255, 255, 255, 0.3)
                    border.width: 1
                    
                    Text {
                        anchors.centerIn: parent
                        text: audioControls.eqEnabled ? "ON" : "OFF"
                        color: "#ffffff"
                        font.pixelSize: 12
                        font.bold: true
                    }
                    
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            audioControls.eqEnabled = !audioControls.eqEnabled
                            eqToggled(audioControls.eqEnabled)
                        }
                    }
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
                            color: "#ffffff"
                            font.pixelSize: 10
                            horizontalAlignment: Text.AlignHCenter
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
                                color: "#ffffff"
                                font.pixelSize: 9
                            }
                        }
                    }
                }
            }
            
            // Reset button
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 36
                radius: 8
                color: resetButtonMouse.containsMouse 
                       ? Qt.rgba(accentColor.r, accentColor.g, accentColor.b, 0.3)
                       : Qt.rgba(255, 255, 255, 0.1)
                
                Text {
                    anchors.centerIn: parent
                    text: "Reset"
                    color: "#ffffff"
                    font.pixelSize: 12
                }
                
                MouseArea {
                    id: resetButtonMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        eqBands = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
                        for (let i = 0; i < 10; i++) {
                            eqBandChanged(i, 0)
                        }
                    }
                }
            }
        }
    }
}
