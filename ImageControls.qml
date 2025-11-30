import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects

Item {
    id: imageControls

    property int currentIndex: 0
    property int totalImages: 0
    property real zoomFactor: 1.0
    property color accentColor: "#ffffff"
    property bool hasImages: totalImages > 0

    signal previousClicked()
    signal nextClicked()
    signal zoomInClicked()
    signal zoomOutClicked()
    signal fitToWindowClicked()
    signal actualSizeClicked()
    signal rotateLeftClicked()
    signal rotateRightClicked()

    Rectangle {
        anchors.fill: parent
        radius: 12
        color: Qt.rgba(0, 0, 0, 0.85)
        border.color: Qt.rgba(255, 255, 255, 0.15)
        border.width: 1

        RowLayout {
            anchors.fill: parent
            anchors.margins: 8
            spacing: 8

            // LEFT SIDE: Previous button
            Item {
                Layout.preferredWidth: 32
                Layout.preferredHeight: 32
                visible: hasImages

                Rectangle {
                    anchors.centerIn: parent
                    width: 32; height: 32
                    radius: 8
                    color: prevMouse.containsMouse && totalImages > 1
                           ? Qt.rgba(accentColor.r, accentColor.g, accentColor.b, 0.25)
                           : "transparent"
                    opacity: totalImages > 1 ? 1 : 0.3

                    Image {
                        id: prevIcon
                        anchors.centerIn: parent
                        width: 20; height: 20
                        source: "qrc:/qlementine/icons/16/navigation/chevron-left.svg"
                        sourceSize.width: 20
                        sourceSize.height: 20
                        fillMode: Image.PreserveAspectFit
                    }
                    ColorOverlay {
                        anchors.fill: prevIcon
                        source: prevIcon
                        color: "#ffffff"
                    }

                    MouseArea {
                        id: prevMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: totalImages > 1 ? Qt.PointingHandCursor : Qt.ArrowCursor
                        enabled: totalImages > 1
                        onClicked: previousClicked()
                    }
                }
            }

            // Image counter
            Text {
                Layout.preferredWidth: 60
                visible: hasImages
                color: "#ffffff"
                font.pixelSize: 12
                font.family: "Segoe UI"
                horizontalAlignment: Text.AlignHCenter
                text: (currentIndex + 1) + " / " + totalImages
                opacity: 0.8
            }

            // Next button
            Item {
                Layout.preferredWidth: 32
                Layout.preferredHeight: 32
                visible: hasImages

                Rectangle {
                    anchors.centerIn: parent
                    width: 32; height: 32
                    radius: 8
                    color: nextMouse.containsMouse && totalImages > 1
                           ? Qt.rgba(accentColor.r, accentColor.g, accentColor.b, 0.25)
                           : "transparent"
                    opacity: totalImages > 1 ? 1 : 0.3

                    Image {
                        id: nextIcon
                        anchors.centerIn: parent
                        width: 20; height: 20
                        source: "qrc:/qlementine/icons/16/navigation/chevron-right.svg"
                        sourceSize.width: 20
                        sourceSize.height: 20
                        fillMode: Image.PreserveAspectFit
                    }
                    ColorOverlay {
                        anchors.fill: nextIcon
                        source: nextIcon
                        color: "#ffffff"
                    }

                    MouseArea {
                        id: nextMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: totalImages > 1 ? Qt.PointingHandCursor : Qt.ArrowCursor
                        enabled: totalImages > 1
                        onClicked: nextClicked()
                    }
                }
            }

            // Separator
            Rectangle {
                Layout.preferredWidth: 1
                Layout.preferredHeight: 20
                color: Qt.rgba(255, 255, 255, 0.2)
                visible: hasImages
            }

            // Zoom out
            Item {
                Layout.preferredWidth: 32
                Layout.preferredHeight: 32

                Rectangle {
                    anchors.centerIn: parent
                    width: 32; height: 32
                    radius: 8
                    color: zoomOutMouse.containsMouse
                           ? Qt.rgba(accentColor.r, accentColor.g, accentColor.b, 0.25)
                           : "transparent"

                    Image {
                        id: zoomOutIcon
                        anchors.centerIn: parent
                        width: 20; height: 20
                        source: "qrc:/qlementine/icons/16/action/zoom-out.svg"
                        sourceSize.width: 20
                        sourceSize.height: 20
                        fillMode: Image.PreserveAspectFit
                    }
                    ColorOverlay {
                        anchors.fill: zoomOutIcon
                        source: zoomOutIcon
                        color: "#ffffff"
                    }

                    MouseArea {
                        id: zoomOutMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: zoomOutClicked()
                    }
                }
            }

            // Zoom level indicator
            Text {
                Layout.preferredWidth: 50
                color: "#ffffff"
                font.pixelSize: 11
                font.family: "Segoe UI"
                horizontalAlignment: Text.AlignHCenter
                text: (zoomFactor * 100).toFixed(0) + "%"
                opacity: 0.8
            }

            // Zoom in
            Item {
                Layout.preferredWidth: 32
                Layout.preferredHeight: 32

                Rectangle {
                    anchors.centerIn: parent
                    width: 32; height: 32
                    radius: 8
                    color: zoomInMouse.containsMouse
                           ? Qt.rgba(accentColor.r, accentColor.g, accentColor.b, 0.25)
                           : "transparent"

                    Image {
                        id: zoomInIcon
                        anchors.centerIn: parent
                        width: 20; height: 20
                        source: "qrc:/qlementine/icons/16/action/zoom-in.svg"
                        sourceSize.width: 20
                        sourceSize.height: 20
                        fillMode: Image.PreserveAspectFit
                    }
                    ColorOverlay {
                        anchors.fill: zoomInIcon
                        source: zoomInIcon
                        color: "#ffffff"
                    }

                    MouseArea {
                        id: zoomInMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: zoomInClicked()
                    }
                }
            }

            // Separator
            Rectangle {
                Layout.preferredWidth: 1
                Layout.preferredHeight: 20
                color: Qt.rgba(255, 255, 255, 0.2)
            }

            // Fit to window
            Item {
                Layout.preferredWidth: 32
                Layout.preferredHeight: 32

                Rectangle {
                    anchors.centerIn: parent
                    width: 32; height: 32
                    radius: 8
                    color: fitMouse.containsMouse
                           ? Qt.rgba(accentColor.r, accentColor.g, accentColor.b, 0.25)
                           : "transparent"

                    Image {
                        id: fitIcon
                        anchors.centerIn: parent
                        width: 20; height: 20
                        source: "qrc:/qlementine/icons/16/action/fullscreen.svg"
                        sourceSize.width: 20
                        sourceSize.height: 20
                        fillMode: Image.PreserveAspectFit
                    }
                    ColorOverlay {
                        anchors.fill: fitIcon
                        source: fitIcon
                        color: zoomFactor === 1.0 ? accentColor : "#ffffff"
                    }

                    MouseArea {
                        id: fitMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: fitToWindowClicked()
                    }

                    // Tooltip
                    ToolTip {
                        visible: fitMouse.containsMouse
                        text: "Fit to window"
                        delay: 500
                    }
                }
            }

            // 100% / Actual size
            Item {
                Layout.preferredWidth: 32
                Layout.preferredHeight: 32

                Rectangle {
                    anchors.centerIn: parent
                    width: 32; height: 32
                    radius: 8
                    color: actualMouse.containsMouse
                           ? Qt.rgba(accentColor.r, accentColor.g, accentColor.b, 0.25)
                           : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: "1:1"
                        color: "#ffffff"
                        font.pixelSize: 11
                        font.bold: true
                    }

                    MouseArea {
                        id: actualMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: actualSizeClicked()
                    }

                    // Tooltip
                    ToolTip {
                        visible: actualMouse.containsMouse
                        text: "Actual size (100%)"
                        delay: 500
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
                    anchors.centerIn: parent
                    width: 32; height: 32
                    radius: 8
                    color: rotateLeftMouse.containsMouse
                           ? Qt.rgba(accentColor.r, accentColor.g, accentColor.b, 0.25)
                           : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: "↺"
                        color: "#ffffff"
                        font.pixelSize: 18
                    }

                    MouseArea {
                        id: rotateLeftMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: rotateLeftClicked()
                    }
                }
            }

            // Rotate right
            Item {
                Layout.preferredWidth: 32
                Layout.preferredHeight: 32

                Rectangle {
                    anchors.centerIn: parent
                    width: 32; height: 32
                    radius: 8
                    color: rotateRightMouse.containsMouse
                           ? Qt.rgba(accentColor.r, accentColor.g, accentColor.b, 0.25)
                           : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: "↻"
                        color: "#ffffff"
                        font.pixelSize: 18
                    }

                    MouseArea {
                        id: rotateRightMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: rotateRightClicked()
                    }
                }
            }
        }
    }

    // Tooltip component
    component ToolTip: Rectangle {
        id: tooltip
        property string text: ""
        property int delay: 500
        
        width: tooltipText.width + 16
        height: tooltipText.height + 8
        radius: 4
        color: Qt.rgba(0, 0, 0, 0.9)
        border.color: Qt.rgba(255, 255, 255, 0.2)
        
        anchors.bottom: parent.top
        anchors.bottomMargin: 8
        anchors.horizontalCenter: parent.horizontalCenter
        
        opacity: visible ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 150 } }
        
        Text {
            id: tooltipText
            anchors.centerIn: parent
            text: tooltip.text
            color: "#ffffff"
            font.pixelSize: 11
        }
    }
}

