import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import s3rpent_media

Item {
    id: root
    implicitWidth: 360
    implicitHeight: contentColumn.implicitHeight

    property var webRTCManager: null
    property color foregroundColor: "#f5f5f5"
    property color accentColor: "#121216"

    signal createSessionRequested()
    signal joinSessionRequested(string code)
    signal leaveSessionRequested()

    readonly property bool isConnected: webRTCManager && webRTCManager.isConnected
    readonly property bool hasSession: webRTCManager && webRTCManager.sessionId !== ""
    readonly property string sessionCode: hasSession ? webRTCManager.sessionId : ""

    property int _mode: 0 // 0 = host, 1 = join
    property bool _advancedOpen: false

    function buildSignalingUrl(hostPort) {
        var s = hostPort.trim()
        if (s === "") return ""
        if (s.startsWith("http://") || s.startsWith("https://")) return s
        return "http://" + s + "/api/signal"
    }

    function applyServerUrl(fieldText) {
        if (webRTCManager && fieldText !== "")
            webRTCManager.signalingServerUrl = buildSignalingUrl(fieldText)
    }

    function copySessionCode() {
        if (!hasSession) return
        const code = sessionCode.toUpperCase()
        if (typeof ColorUtils !== "undefined" && ColorUtils.copyToClipboard) {
            ColorUtils.copyToClipboard(code)
            toast.show(qsTr("Code copied"))
        } else if (typeof Qt !== "undefined" && Qt.application && Qt.application.clipboard) {
            Qt.application.clipboard.text = code
            toast.show(qsTr("Code copied"))
        } else {
            console.log("[ListenTogether] Session code:", code)
            toast.show(qsTr("Code: %1").arg(code))
        }
    }

    ColumnLayout {
        id: contentColumn
        width: parent.width
        spacing: 16

        Text {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: isConnected
                  ? qsTr("You're listening together — play, pause, seek, and song changes stay in sync.")
                  : qsTr("Start a room or join with a friend's code to listen in sync.")
            font.pixelSize: 13
            color: Qt.rgba(foregroundColor.r, foregroundColor.g, foregroundColor.b, 0.7)
            lineHeight: 1.35
        }

        // Status pill
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: statusRow.implicitHeight + 20
            radius: 12
            color: isConnected
                   ? Qt.rgba(0.3, 0.85, 0.45, 0.12)
                   : (hasSession
                      ? Qt.rgba(0.55, 0.45, 0.95, 0.12)
                      : Qt.rgba(foregroundColor.r, foregroundColor.g, foregroundColor.b, 0.06))
            border.width: 1
            border.color: isConnected
                          ? Qt.rgba(0.3, 0.85, 0.45, 0.35)
                          : (hasSession
                             ? Qt.rgba(0.55, 0.45, 0.95, 0.35)
                             : Qt.rgba(foregroundColor.r, foregroundColor.g, foregroundColor.b, 0.1))

            RowLayout {
                id: statusRow
                anchors.fill: parent
                anchors.margins: 12
                spacing: 10

                Rectangle {
                    Layout.preferredWidth: 8
                    Layout.preferredHeight: 8
                    radius: 4
                    color: isConnected ? "#6ee7a0" : (hasSession ? "#a78bfa" : "#f87171")

                    SequentialAnimation on opacity {
                        running: !isConnected
                        loops: Animation.Infinite
                        PropertyAnimation { to: 0.35; duration: 600 }
                        PropertyAnimation { to: 1.0; duration: 600 }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: {
                        if (!webRTCManager)
                            return qsTr("Listen Together is unavailable")
                        if (isConnected)
                            return qsTr("Connected")
                        if (hasSession)
                            return qsTr("Room open — waiting for your friend")
                        return qsTr("Not in a room")
                    }
                    color: foregroundColor
                    font.pixelSize: 13
                    font.weight: Font.Medium
                }
            }
        }

        // Sync progress
        Rectangle {
            Layout.fillWidth: true
            visible: syncStatusText.text !== ""
            implicitHeight: visible ? syncColumn.implicitHeight + 20 : 0
            radius: 12
            color: Qt.rgba(0.4, 0.7, 0.96, 0.1)
            border.color: Qt.rgba(0.4, 0.7, 0.96, 0.28)
            border.width: 1

            ColumnLayout {
                id: syncColumn
                anchors.fill: parent
                anchors.margins: 12
                spacing: 8

                Text {
                    id: syncStatusText
                    Layout.fillWidth: true
                    text: {
                        if (!webRTCManager)
                            return ""
                        if (webRTCManager.isHost && webRTCManager.streamPreparing)
                            return qsTr("Optimizing track for transfer…")
                        if (!webRTCManager.isConnected)
                            return ""
                        if (webRTCManager.syncStatus === "" || webRTCManager.syncStatus === "idle")
                            return ""
                        return webRTCManager.syncStatusLabel
                    }
                    color: "#b3e5fc"
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                }

                ProgressBar {
                    Layout.fillWidth: true
                    visible: webRTCManager && webRTCManager.syncStatus === "receiving"
                    from: 0
                    to: 1
                    value: webRTCManager ? webRTCManager.streamReceiveProgress : 0
                }
            }
        }

        // Session code (host / connected)
        Rectangle {
            Layout.fillWidth: true
            visible: hasSession
            implicitHeight: visible ? codeColumn.implicitHeight + 24 : 0
            radius: 14
            color: Qt.rgba(foregroundColor.r, foregroundColor.g, foregroundColor.b, 0.05)
            border.color: Qt.rgba(foregroundColor.r, foregroundColor.g, foregroundColor.b, 0.12)
            border.width: 1

            ColumnLayout {
                id: codeColumn
                anchors.fill: parent
                anchors.margins: 16
                spacing: 10

                Text {
                    Layout.fillWidth: true
                    text: isConnected
                          ? qsTr("Room code")
                          : qsTr("Share this code with your friend")
                    font.pixelSize: 12
                    color: Qt.rgba(foregroundColor.r, foregroundColor.g, foregroundColor.b, 0.65)
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Text {
                        Layout.fillWidth: true
                        text: sessionCode.toUpperCase()
                        font.pixelSize: 26
                        font.weight: Font.Bold
                        font.letterSpacing: 4
                        color: foregroundColor
                    }

                    Rectangle {
                        Layout.preferredWidth: 36
                        Layout.preferredHeight: 36
                        radius: 10
                        color: copyTap.pressed
                               ? Qt.rgba(foregroundColor.r, foregroundColor.g, foregroundColor.b, 0.2)
                               : (copyHover.hovered
                                  ? Qt.rgba(foregroundColor.r, foregroundColor.g, foregroundColor.b, 0.14)
                                  : Qt.rgba(foregroundColor.r, foregroundColor.g, foregroundColor.b, 0.08))

                        Image {
                            id: copyIcon
                            anchors.centerIn: parent
                            source: "qrc:/qlementine/icons/16/action/copy.svg"
                            sourceSize: Qt.size(16, 16)
                            visible: false
                        }
                        ColorOverlay {
                            anchors.fill: copyIcon
                            source: copyIcon
                            color: foregroundColor
                        }

                        HoverHandler { id: copyHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler {
                            id: copyTap
                            onTapped: root.copySessionCode()
                        }
                    }
                }
            }
        }

        // Host: compress lossless tracks before sending to friend
        Rectangle {
            Layout.fillWidth: true
            visible: webRTCManager && webRTCManager.isHost && hasSession
            implicitHeight: visible ? compressRow.implicitHeight + 24 : 0
            radius: 12
            color: Qt.rgba(foregroundColor.r, foregroundColor.g, foregroundColor.b, 0.05)
            border.color: Qt.rgba(foregroundColor.r, foregroundColor.g, foregroundColor.b, 0.1)
            border.width: 1

            RowLayout {
                id: compressRow
                anchors.fill: parent
                anchors.margins: 14
                spacing: 12

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    Text {
                        Layout.fillWidth: true
                        text: qsTr("Faster transfers")
                        font.pixelSize: 13
                        font.weight: Font.Medium
                        color: foregroundColor
                    }

                    Text {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: qsTr("Convert FLAC/WAV to MP3 before sending. You still play the original — sync and artwork stay the same.")
                        font.pixelSize: 11
                        color: Qt.rgba(foregroundColor.r, foregroundColor.g, foregroundColor.b, 0.55)
                        lineHeight: 1.3
                    }
                }

                Switch {
                    checked: webRTCManager ? webRTCManager.compressStreamsForPeer : true
                    onToggled: {
                        if (webRTCManager)
                            webRTCManager.compressStreamsForPeer = checked
                    }
                }
            }
        }

        // Host / Join picker (only when not in a session)
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            visible: !hasSession

            Repeater {
                model: [
                    { id: 0, label: qsTr("Start a room"), icon: "qrc:/qlementine/icons/16/action/group.svg" },
                    { id: 1, label: qsTr("Join a room"), icon: "qrc:/qlementine/icons/16/misc/link.svg" }
                ]

                delegate: Rectangle {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredHeight: 40
                    radius: 10
                    color: root._mode === modelData.id
                           ? Qt.rgba(0.55, 0.45, 0.95, 0.28)
                           : Qt.rgba(foregroundColor.r, foregroundColor.g, foregroundColor.b, 0.06)
                    border.width: 1
                    border.color: root._mode === modelData.id
                                  ? Qt.rgba(0.65, 0.55, 1.0, 0.45)
                                  : Qt.rgba(foregroundColor.r, foregroundColor.g, foregroundColor.b, 0.1)

                    Row {
                        anchors.centerIn: parent
                        spacing: 8

                        Item {
                            width: 14
                            height: 14
                            anchors.verticalCenter: parent.verticalCenter
                            Image {
                                id: modeIconImage
                                anchors.fill: parent
                                source: modelData.icon
                                sourceSize: Qt.size(14, 14)
                                visible: false
                            }
                            ColorOverlay {
                                anchors.fill: parent
                                source: modeIconImage
                                color: foregroundColor
                                opacity: root._mode === modelData.id ? 1.0 : 0.75
                            }
                        }

                        Text {
                            text: modelData.label
                            font.pixelSize: 12
                            font.weight: root._mode === modelData.id ? Font.DemiBold : Font.Normal
                            color: foregroundColor
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    TapHandler {
                        onTapped: root._mode = modelData.id
                    }
                }
            }
        }

        // Host action
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 44
            radius: 12
            visible: !hasSession && _mode === 0
            color: hostTap.pressed
                   ? Qt.rgba(0.55, 0.45, 0.95, 0.45)
                   : (hostHover.hovered ? Qt.rgba(0.55, 0.45, 0.95, 0.38) : Qt.rgba(0.55, 0.45, 0.95, 0.32))
            opacity: webRTCManager ? 1.0 : 0.45

            RowLayout {
                anchors.centerIn: parent
                spacing: 8

                Image {
                    id: hostIcon
                    source: "qrc:/qlementine/icons/16/action/group.svg"
                    sourceSize: Qt.size(16, 16)
                    visible: false
                }
                ColorOverlay {
                    source: hostIcon
                    width: 16
                    height: 16
                    color: "#ffffff"
                }

                Text {
                    text: qsTr("Create room")
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                    color: "#ffffff"
                }
            }

            HoverHandler { id: hostHover; cursorShape: Qt.PointingHandCursor }
            TapHandler {
                id: hostTap
                enabled: !!webRTCManager
                onTapped: {
                    applyServerUrl(serverUrlField.text)
                    createSessionRequested()
                }
            }
        }

        // Join form
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 10
            visible: !hasSession && _mode === 1

            Text {
                Layout.fillWidth: true
                text: qsTr("Enter the code your friend shared")
                font.pixelSize: 12
                color: Qt.rgba(foregroundColor.r, foregroundColor.g, foregroundColor.b, 0.65)
            }

            TextField {
                id: joinCodeField
                Layout.fillWidth: true
                placeholderText: qsTr("e.g. EBAF1E1F")
                font.pixelSize: 15
                font.letterSpacing: 2
                maximumLength: 8
                horizontalAlignment: Text.AlignHCenter
                onTextChanged: text = text.toUpperCase().replace(/[^A-Z0-9]/g, "")
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 44
                radius: 12
                opacity: (webRTCManager && joinCodeField.text.length >= 4) ? 1.0 : 0.45
                color: joinTap.pressed
                       ? Qt.rgba(0.55, 0.45, 0.95, 0.45)
                       : (joinHover.hovered ? Qt.rgba(0.55, 0.45, 0.95, 0.38) : Qt.rgba(0.55, 0.45, 0.95, 0.32))

                Text {
                    anchors.centerIn: parent
                    text: qsTr("Join room")
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                    color: "#ffffff"
                }

                HoverHandler { id: joinHover; cursorShape: Qt.PointingHandCursor }
                TapHandler {
                    id: joinTap
                    enabled: webRTCManager && joinCodeField.text.length >= 4
                    onTapped: {
                        applyServerUrl(serverUrlField.text)
                        joinSessionRequested(joinCodeField.text)
                    }
                }
            }
        }

        // Leave
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 40
            radius: 10
            visible: hasSession
            color: leaveTap.pressed
                   ? Qt.rgba(0.9, 0.3, 0.3, 0.22)
                   : (leaveHover.hovered ? Qt.rgba(0.9, 0.3, 0.3, 0.16) : Qt.rgba(foregroundColor.r, foregroundColor.g, foregroundColor.b, 0.06))
            border.width: 1
            border.color: Qt.rgba(0.9, 0.3, 0.3, leaveHover.hovered ? 0.45 : 0.25)

            Text {
                anchors.centerIn: parent
                text: qsTr("Leave room")
                font.pixelSize: 13
                font.weight: Font.Medium
                color: leaveHover.hovered ? "#ff8a8a" : Qt.rgba(foregroundColor.r, foregroundColor.g, foregroundColor.b, 0.85)
            }

            HoverHandler { id: leaveHover; cursorShape: Qt.PointingHandCursor }
            TapHandler {
                id: leaveTap
                onTapped: leaveSessionRequested()
            }
        }

        // Advanced connection settings
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: advColumn.implicitHeight + 16
            radius: 12
            color: Qt.rgba(foregroundColor.r, foregroundColor.g, foregroundColor.b, 0.05)
            border.color: Qt.rgba(foregroundColor.r, foregroundColor.g, foregroundColor.b, 0.1)
            border.width: 1

            ColumnLayout {
                id: advColumn
                anchors.fill: parent
                anchors.margins: 8
                spacing: 8

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 32
                    radius: 8
                    color: advTap.pressed
                           ? Qt.rgba(foregroundColor.r, foregroundColor.g, foregroundColor.b, 0.1)
                           : (advHover.hovered ? Qt.rgba(foregroundColor.r, foregroundColor.g, foregroundColor.b, 0.07)
                                               : "transparent")

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 4
                        anchors.rightMargin: 4
                        spacing: 6

                        Text {
                            Layout.fillWidth: true
                            text: qsTr("Connection settings")
                            font.pixelSize: 11
                            color: Qt.rgba(foregroundColor.r, foregroundColor.g, foregroundColor.b, 0.5)
                        }

                        Item {
                            Layout.preferredWidth: 12
                            Layout.preferredHeight: 12
                            rotation: root._advancedOpen ? 180 : 0
                            Behavior on rotation { NumberAnimation { duration: 150 } }

                            Image {
                                id: chevronIcon
                                anchors.fill: parent
                                source: "qrc:/qlementine/icons/16/navigation/chevron-down.svg"
                                sourceSize: Qt.size(12, 12)
                                visible: false
                            }
                            ColorOverlay {
                                anchors.fill: parent
                                source: chevronIcon
                                color: Qt.rgba(foregroundColor.r, foregroundColor.g, foregroundColor.b, 0.45)
                            }
                        }
                    }

                    HoverHandler { id: advHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler {
                        id: advTap
                        onTapped: root._advancedOpen = !root._advancedOpen
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    visible: root._advancedOpen

                    Text {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: qsTr("Only change this if you and your friend use a custom server. For local testing, use localhost:3847.")
                        font.pixelSize: 11
                        color: Qt.rgba(foregroundColor.r, foregroundColor.g, foregroundColor.b, 0.45)
                        lineHeight: 1.3
                    }

                    TextField {
                        id: serverUrlField
                        Layout.fillWidth: true
                        placeholderText: "localhost:3847"
                        text: "localhost:3847"
                        font.pixelSize: 12
                    }
                }
            }
        }
    }

    Rectangle {
        id: toast
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: -8
        width: Math.max(120, toastLabel.implicitWidth + 28)
        height: 34
        radius: 17
        color: Qt.rgba(0.2, 0.75, 0.45, 0.95)
        visible: opacity > 0
        opacity: 0
        z: 10

        Text {
            id: toastLabel
            anchors.centerIn: parent
            font.pixelSize: 12
            font.weight: Font.Medium
            color: "#ffffff"
        }

        Behavior on opacity { NumberAnimation { duration: 200 } }

        function show(message) {
            toastLabel.text = message
            opacity = 1.0
            hideTimer.restart()
        }

        Timer {
            id: hideTimer
            interval: 1800
            onTriggered: toast.opacity = 0
        }
    }
}
