import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects

Popup {
    id: root
    modal: false
    focus: true
    padding: 0
    closePolicy: Popup.CloseOnEscape

    property var webRTCManager: null
    property var titleBar: null
    property color accentColor: "#121216"
    property color foregroundColor: "#f5f5f5"

    width: Math.min(400, parent ? parent.width - 24 : 400)
    implicitHeight: innerColumn.implicitHeight + 40

    function reposition() {
        if (!parent || !titleBar)
            return
        const margin = 12
        x = Math.max(margin, parent.width - width - margin)
        y = titleBar.height + 6
    }

    onOpened: reposition()
    Connections {
        target: parent
        function onWidthChanged() { if (root.opened) root.reposition() }
    }

    background: Rectangle {
        radius: 18
        color: Qt.rgba(
            Qt.lighter(accentColor, 1.15).r,
            Qt.lighter(accentColor, 1.15).g,
            Qt.lighter(accentColor, 1.15).b,
            0.97
        )
        border.width: 1
        border.color: Qt.rgba(foregroundColor.r, foregroundColor.g, foregroundColor.b, 0.12)

        layer.enabled: true
        layer.effect: DropShadow {
            transparentBorder: true
            horizontalOffset: 0
            verticalOffset: 10
            radius: 28
            samples: 32
            color: Qt.rgba(0, 0, 0, 0.38)
        }
    }

    ColumnLayout {
        id: innerColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: 20
        anchors.rightMargin: 20
        anchors.topMargin: 20
        anchors.bottomMargin: 20
        spacing: 16

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            Rectangle {
                Layout.preferredWidth: 36
                Layout.preferredHeight: 36
                radius: 10
                color: Qt.rgba(0.55, 0.45, 0.95, 0.22)

                Image {
                    id: headerIcon
                    anchors.centerIn: parent
                    source: "qrc:/qlementine/icons/16/hardware/headphones.svg"
                    sourceSize: Qt.size(18, 18)
                    visible: false
                }
                ColorOverlay {
                    anchors.fill: headerIcon
                    source: headerIcon
                    color: foregroundColor
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                Text {
                    text: qsTr("Listen Together")
                    font.pixelSize: 17
                    font.weight: Font.Bold
                    color: foregroundColor
                }

                Text {
                    visible: webRTCManager && webRTCManager.isConnected
                    text: qsTr("In sync")
                    font.pixelSize: 11
                    font.weight: Font.Medium
                    color: "#6ee7a0"
                }
            }

            Rectangle {
                Layout.preferredWidth: 32
                Layout.preferredHeight: 32
                radius: 8
                color: closeTap.pressed
                       ? Qt.rgba(foregroundColor.r, foregroundColor.g, foregroundColor.b, 0.18)
                       : (closeHover.hovered
                          ? Qt.rgba(foregroundColor.r, foregroundColor.g, foregroundColor.b, 0.12)
                          : Qt.rgba(foregroundColor.r, foregroundColor.g, foregroundColor.b, 0.05))

                Image {
                    id: closeIcon
                    anchors.centerIn: parent
                    source: "qrc:/qlementine/icons/16/action/windows-close.svg"
                    sourceSize: Qt.size(14, 14)
                    visible: false
                }
                ColorOverlay {
                    anchors.fill: closeIcon
                    source: closeIcon
                    color: closeHover.hovered ? "#ff6b6b" : foregroundColor
                }

                HoverHandler { id: closeHover; cursorShape: Qt.PointingHandCursor }
                TapHandler {
                    id: closeTap
                    onTapped: root.close()
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: Qt.rgba(foregroundColor.r, foregroundColor.g, foregroundColor.b, 0.1)
        }

        ListenTogetherControl {
            id: control
            Layout.fillWidth: true
            webRTCManager: root.webRTCManager
            foregroundColor: root.foregroundColor
            accentColor: root.accentColor

            onCreateSessionRequested: {
                if (webRTCManager)
                    webRTCManager.createSession()
            }
            onJoinSessionRequested: function(code) {
                if (webRTCManager)
                    webRTCManager.joinSession(code)
            }
            onLeaveSessionRequested: {
                if (webRTCManager)
                    webRTCManager.leaveSession()
            }
        }
    }
}
