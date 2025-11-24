import QtQuick
import QtQuick.Layouts

Rectangle {
    id: titleBar
    
    property string windowTitle: ""
    property string currentFilePath: ""
    property color accentColor: "#121216"
    property color foregroundColor: "#f5f5f5"
    property bool hasMedia: false
    property var window: null
    
    signal metadataClicked()
    signal settingsClicked()
    signal minimizeClicked()
    signal maximizeClicked()
    signal closeClicked()
    signal windowMoveRequested()
    
    height: 44
    color: Qt.lighter(accentColor, 1.25)
    border.color: Qt.darker(accentColor, 1.05)

    DragHandler {
        target: null
        acceptedButtons: Qt.LeftButton
        onActiveChanged: if (active) windowMoveRequested()
    }

    TapHandler {
        acceptedButtons: Qt.LeftButton
        gesturePolicy: TapHandler.ReleaseWithinBounds
        onDoubleTapped: maximizeClicked()
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 8
        spacing: 12

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            Text {
                text: windowTitle
                color: foregroundColor
                font.pixelSize: 16
                font.bold: true
            }

            Text {
                Layout.fillWidth: true
                text: currentFilePath === ""
                      ? qsTr("Drag & drop an image")
                      : decodeURIComponent(currentFilePath.toString().replace("file:///", ""))
                elide: Text.ElideMiddle
                color: Qt.lighter(foregroundColor, 1.2)
                font.pixelSize: 12
            }
        }

        RowLayout {
            spacing: 4

            Rectangle {
                id: metadataButton
                Layout.preferredWidth: 40
                Layout.preferredHeight: 32
                radius: 4
                color: metadataTap.pressed
                       ? Qt.darker(accentColor, 1.4)
                       : (metadataHover.hovered
                          ? Qt.darker(accentColor, 1.2)
                          : Qt.darker(accentColor, 1.05))
                border.color: Qt.darker(accentColor,
                                         metadataHover.hovered ? 1.3 : 1.1)
                visible: hasMedia
                Behavior on color { ColorAnimation { duration: 120 } }
                Behavior on border.color { ColorAnimation { duration: 120 } }
                Text {
                    anchors.centerIn: parent
                    text: "\u2139"
                    color: foregroundColor
                    font.pixelSize: 18
                }
                TapHandler {
                    id: metadataTap
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    acceptedButtons: Qt.LeftButton
                    onTapped: metadataClicked()
                }
                HoverHandler {
                    id: metadataHover
                    cursorShape: Qt.PointingHand
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                }
            }

            Rectangle {
                id: settingsButton
                Layout.preferredWidth: 40
                Layout.preferredHeight: 32
                radius: 4
                color: settingsTap.pressed
                       ? Qt.darker(accentColor, 1.4)
                       : (settingsHover.hovered
                          ? Qt.darker(accentColor, 1.2)
                          : Qt.darker(accentColor, 1.05))
                border.color: Qt.darker(accentColor,
                                         settingsHover.hovered ? 1.3 : 1.1)
                Behavior on color { ColorAnimation { duration: 120 } }
                Behavior on border.color { ColorAnimation { duration: 120 } }
                Text {
                    anchors.centerIn: parent
                    text: "\u2699"
                    color: foregroundColor
                    font.pixelSize: 18
                }
                TapHandler {
                    id: settingsTap
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    acceptedButtons: Qt.LeftButton
                    onTapped: settingsClicked()
                }
                HoverHandler {
                    id: settingsHover
                    cursorShape: Qt.PointingHand
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                }
            }

            Rectangle {
                id: minimizeButton
                Layout.preferredWidth: 44
                Layout.preferredHeight: 32
                radius: 4
                color: minimizeTap.pressed
                       ? Qt.darker(accentColor, 1.5)
                       : (minimizeHover.hovered
                          ? Qt.darker(accentColor, 1.35)
                          : Qt.darker(accentColor, 1.15))
                border.color: Qt.darker(accentColor,
                                         minimizeHover.hovered ? 1.45 : 1.2)
                Behavior on color { ColorAnimation { duration: 120 } }
                Behavior on border.color { ColorAnimation { duration: 120 } }
                Text {
                    anchors.centerIn: parent
                    text: "\u2212"
                    color: foregroundColor
                    font.pixelSize: 18
                }
                TapHandler {
                    id: minimizeTap
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    acceptedButtons: Qt.LeftButton
                    onTapped: minimizeClicked()
                }
                HoverHandler {
                    id: minimizeHover
                    cursorShape: Qt.PointingHand
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                }
            }

            Rectangle {
                id: maximizeButton
                Layout.preferredWidth: 44
                Layout.preferredHeight: 32
                radius: 4
                color: maximizeTap.pressed
                       ? Qt.darker(accentColor, 1.5)
                       : (maximizeHover.hovered
                          ? Qt.darker(accentColor, 1.35)
                          : Qt.darker(accentColor, 1.15))
                border.color: Qt.darker(accentColor,
                                         maximizeHover.hovered ? 1.45 : 1.2)
                Behavior on color { ColorAnimation { duration: 120 } }
                Behavior on border.color { ColorAnimation { duration: 120 } }
                
                property bool isMaximized: window ? window.visibility === Window.Maximized : false
                
                Text {
                    id: maximizeIcon
                    anchors.centerIn: parent
                    text: maximizeButton.isMaximized ? "\u2750" : "\u25A1"
                    color: foregroundColor
                    font.pixelSize: 16
                }
                TapHandler {
                    id: maximizeTap
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    acceptedButtons: Qt.LeftButton
                    onTapped: maximizeClicked()
                }
                HoverHandler {
                    id: maximizeHover
                    cursorShape: Qt.PointingHand
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                }
            }

            Rectangle {
                id: closeButton
                Layout.preferredWidth: 48
                Layout.preferredHeight: 32
                radius: 4
                color: closeTap.pressed
                       ? Qt.darker(accentColor, 1.7)
                       : (closeHover.hovered
                          ? Qt.darker(accentColor, 1.45)
                          : Qt.darker(accentColor, 1.2))
                border.color: Qt.darker(accentColor,
                                         closeHover.hovered ? 1.55 : 1.25)
                Behavior on color { ColorAnimation { duration: 120 } }
                Behavior on border.color { ColorAnimation { duration: 120 } }
                Text {
                    anchors.centerIn: parent
                    text: "\u00D7"
                    color: foregroundColor
                    font.pixelSize: 18
                }
                TapHandler {
                    id: closeTap
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    acceptedButtons: Qt.LeftButton
                    onTapped: closeClicked()
                }
                HoverHandler {
                    id: closeHover
                    cursorShape: Qt.PointingHand
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                }
            }
        }
    }
}

