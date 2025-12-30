import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects

Popup {
    id: metadataPopup
    
    property var metadataList: []
    property color accentColor: "#121216"
    property color foregroundColor: "#f5f5f5"
    
    signal closeRequested()
    
    width: Math.min(350, parent.width - 80)
    height: Math.min(450, parent.height - 80)
    modal: false
    focus: true
    closePolicy: Popup.CloseOnEscape
    
    // Modern rounded container with shadow
    background: Rectangle {
        id: popupBackground
        radius: 20
        color: Qt.rgba(
            Qt.lighter(accentColor, 1.3).r,
            Qt.lighter(accentColor, 1.3).g,
            Qt.lighter(accentColor, 1.3).b,
            0.95
        )
        border.width: 0
        
        // Drop shadow for modern look
        layer.enabled: true
        layer.effect: DropShadow {
            transparentBorder: true
            horizontalOffset: 0
            verticalOffset: 4
            radius: 16
            samples: 32
            color: Qt.rgba(0, 0, 0, 0.25)
        }
        
        // Entrance animation
        scale: 0.9
        opacity: 0
        Behavior on scale {
            NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
        }
        Behavior on opacity {
            NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
        }
        Component.onCompleted: {
            scale = 1.0
            opacity = 1.0
        }
    }
    
    // Header with close button
    Rectangle {
        id: header
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
                text: qsTr("File Metadata")
                color: foregroundColor
                font.pixelSize: 20
                font.weight: Font.Medium
                font.letterSpacing: 0.5
            }
            
            // Close button
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
                        color: foregroundColor
                        opacity: 0.9
                    }
                }
                
                TapHandler {
                    id: closeButtonTap
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    acceptedButtons: Qt.LeftButton
                    gesturePolicy: TapHandler.ReleaseWithinBounds
                    onTapped: {
                        // Emit signal to close the popup - this ensures it only closes on release
                        metadataPopup.closeRequested()
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
    
    // Content area
    ScrollView {
        anchors.top: header.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.topMargin: 8
        anchors.leftMargin: 24
        anchors.rightMargin: 24
        anchors.bottomMargin: 24
        clip: true
        
        ColumnLayout {
            width: metadataPopup.width - 48
            spacing: 20
            
            Repeater {
                id: metadataRepeater
                model: metadataList
                
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    
                    // Label
                    Text {
                        Layout.fillWidth: true
                        text: modelData.label
                        color: Qt.lighter(foregroundColor, 1.4)
                        font.pixelSize: 11
                        font.weight: Font.Medium
                        font.letterSpacing: 0.5
                        opacity: 0.7
                    }
                    
                    // Value
                    Text {
                        Layout.fillWidth: true
                        text: modelData.value
                        color: foregroundColor
                        font.pixelSize: 14
                        font.weight: Font.Normal
                        wrapMode: Text.WordWrap
                        lineHeight: 1.4
                    }
                }
            }
        }
    }
}

