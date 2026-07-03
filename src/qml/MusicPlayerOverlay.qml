import QtMultimedia
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects

/**
 * Uiverse.io / Vosoone "main-music-card" — QML port; times/progress/transport bound to AudioPlayer.
 */
Item {
    id: root
    width: parent.width

    implicitWidth: mainMusicCard.width
    implicitHeight: mainMusicCard.height

    property color accentColor: "#0072ff"
    property color foregroundColor: "#ffffff"
    property bool overlayActive: false
    property var appWindow: null
    property var audioPlayer: null
    property bool lyricsEnabled: true
    property bool lowQualityWhileDragging: false
    property real frozenProgress: 0
    property int frozenPosition: 0
    property int frozenDuration: 0
    property int frozenPlaybackState: MediaPlayer.StoppedState
    property var frozenBands: []
    property url frozenCoverUrl: ""
    property string frozenTitle: ""
    property string frozenArtist: ""

    signal closed()

    /// Decoupled tick tokens prevent exponential re-evaluation cascades through
    /// the QML binding engine. Each tick token only drives the properties it
    /// genuinely needs — position, state, and chrome ticks are independent.
    property int _posTick: 0
    property int _stateTick: 0
    property int _chromeTick: 0

    Timer {
        interval: 250
        running: root.overlayActive && !root.lowQualityWhileDragging
        repeat: true
        onTriggered: root._posTick++
    }
    Timer {
        interval: 500
        running: root.overlayActive && !root.lowQualityWhileDragging
        repeat: true
        onTriggered: root._stateTick++
    }
    Timer {
        interval: 1000
        running: root.overlayActive && !root.lowQualityWhileDragging
        repeat: true
        onTriggered: root._chromeTick++
    }

    onLowQualityWhileDraggingChanged: {
        if (lowQualityWhileDragging) {
            frozenProgress = _progress
            frozenPosition = audioPlayer ? audioPlayer.position : 0
            frozenDuration = audioPlayer ? audioPlayer.duration : 0
            frozenPlaybackState = _playbackState
            frozenBands = _bands
            frozenCoverUrl = _coverUrl
            frozenTitle = _titleText()
            frozenArtist = _artistText()
        }
    }

    function _formatTime(ms) {
        if (ms === undefined || ms < 0)
            return "0:00"
        const totalSec = Math.floor(ms / 1000)
        const h = Math.floor(totalSec / 3600)
        const m = Math.floor((totalSec % 3600) / 60)
        const s = totalSec % 60
        if (h > 0)
            return h + ":" + (m < 10 ? "0" : "") + m + ":" + (s < 10 ? "0" : "") + s
        return m + ":" + (s < 10 ? "0" : "") + s
    }

    function _fileNameFromSource(u) {
        if (!u || u === "")
            return ""
        const s = u.toString()
        const last = s.lastIndexOf("/")
        let name = last >= 0 ? s.substring(last + 1) : s
        const lastB = name.lastIndexOf("\\")
        if (lastB >= 0)
            name = name.substring(lastB + 1)
        const q = name.indexOf("?")
        return q >= 0 ? name.substring(0, q) : name
    }

    function _displayNameForUrl(u) {
        const s = _fileNameFromSource(u)
        return s && s.length > 0 ? s : (u ? ("" + u) : "")
    }

    function _volumeIconPath() {
        if (!audioPlayer)
            return "qrc:/qlementine/icons/16/audio/speaker-2.svg"
        const v = Math.max(0, Math.min(1, audioPlayer.volume || 0))
        if (v <= 0.001) return "qrc:/qlementine/icons/16/audio/speaker-mute.svg"
        if (v < 0.33) return "qrc:/qlementine/icons/16/audio/speaker-0.svg"
        if (v < 0.66) return "qrc:/qlementine/icons/16/audio/speaker-1.svg"
        return "qrc:/qlementine/icons/16/audio/speaker-2.svg"
    }

    function _queueThumbForUrl(u) {
        if (audioPlayer && typeof audioPlayer.queueThumbFor === "function") {
            const t = audioPlayer.queueThumbFor(u)
            if (t && t.toString && t.toString() !== "")
                return t
        }
        return ""
    }

    function _titleText() {
        const _t = _stateTick
        if (!audioPlayer || !audioPlayer.source || audioPlayer.source === "")
            return "Glow"
        if (typeof audioPlayer.getMetaString === "function") {
            const t = audioPlayer.getMetaString(MediaMetaData.Title) || audioPlayer.getMetaString("Title")
            if (t)
                return t
        }
        return _fileNameFromSource(audioPlayer.source) || "Glow"
    }

    function _artistText() {
        const _t = _stateTick
        if (!audioPlayer || !audioPlayer.source || audioPlayer.source === "")
            return "Echo"
        if (typeof audioPlayer.getMetaString === "function") {
            const a = audioPlayer.getMetaString(MediaMetaData.ContributingArtist)
                || audioPlayer.getMetaString("ContributingArtist")
                || audioPlayer.getMetaString("Artist")
            if (a)
                return a
        }
        return "Echo"
    }

    readonly property url _coverUrl: {
        const _t = _stateTick
        if (audioPlayer && audioPlayer.coverArt && audioPlayer.coverArt.toString && audioPlayer.coverArt.toString() !== "")
            return audioPlayer.coverArt
        if (appWindow && appWindow.audioCoverArt && appWindow.audioCoverArt.toString && appWindow.audioCoverArt.toString() !== "")
            return appWindow.audioCoverArt
        return ""
    }

    readonly property real _dpr: {
        if (Qt.application && Qt.application.primaryScreen && Qt.application.primaryScreen.devicePixelRatio)
            return Qt.application.primaryScreen.devicePixelRatio
        return 1
    }

    readonly property real _progress: {
        const _t = _posTick
        if (!audioPlayer || audioPlayer.duration <= 0)
            return 0
        return Math.min(1, Math.max(0, audioPlayer.position / audioPlayer.duration))
    }

    readonly property int _playbackState: {
        const _t = _stateTick
        if (!audioPlayer)
            return MediaPlayer.StoppedState
        return audioPlayer.playbackState !== undefined ? audioPlayer.playbackState : MediaPlayer.StoppedState
    }

    readonly property bool _playing: _playbackState === MediaPlayer.PlayingState
    readonly property url _displayCoverUrl: root.lowQualityWhileDragging ? root.frozenCoverUrl : root._coverUrl
    readonly property string _displayTitle: root.lowQualityWhileDragging ? root.frozenTitle : _titleText()
    readonly property string _displayArtist: root.lowQualityWhileDragging ? root.frozenArtist : _artistText()
    readonly property real _displayProgress: root.lowQualityWhileDragging ? root.frozenProgress : root._progress
    readonly property int _displayPosition: root.lowQualityWhileDragging ? root.frozenPosition : (audioPlayer ? audioPlayer.position : 0)
    readonly property int _displayDuration: root.lowQualityWhileDragging ? root.frozenDuration : (audioPlayer ? audioPlayer.duration : 0)
    readonly property int _displayPlaybackState: root.lowQualityWhileDragging ? root.frozenPlaybackState : root._playbackState
    readonly property var _displayBands: root.lowQualityWhileDragging ? root.frozenBands : root._bands

    readonly property real _amp: {
        const _t = _posTick
        if (!audioPlayer || !audioPlayer.analyzer)
            return 0
        const a = audioPlayer.analyzer.overallAmplitude
        if (a === undefined || a === null)
            return 0
        return Math.min(1, Math.max(0, a * 2.0))
    }

    readonly property var _bands: {
        const _t = _posTick
        if (!audioPlayer || !audioPlayer.analyzer)
            return []
        const b = audioPlayer.analyzer.frequencyBands
        return b ? b : []
    }

    function _bandForBar(i, barCount) {
        const b = root._bands
        if (!b || b.length === 0)
            return 0
        const count = Math.max(1, barCount || 8)
        const idx = Math.min(b.length - 1, Math.max(0, Math.round(i * (b.length - 1) / Math.max(1, count - 1))))
        const v = Number(b[idx])
        if (!isFinite(v))
            return 0
        return Math.min(1, Math.max(0, v * 6.0))
    }

    readonly property string _svgSkipBack: '<svg xmlns="http://www.w3.org/2000/svg" width="22" height="22" fill="#ffffff" viewBox="0 0 16 16"><path d="M.5 3.5A.5.5 0 0 0 0 4v8a.5.5 0 0 0 1 0V8.753l6.267 3.636c.54.313 1.233-.066 1.233-.697v-2.94l6.267 3.636c.54.314 1.233-.065 1.233-.696V4.308c0-.63-.693-1.01-1.233-.696L8.5 7.248v-2.94c0-.63-.692-1.01-1.233-.696L1 7.248V4a.5.5 0 0 0-.5-.5"/></svg>'
    readonly property string _svgSkipFwd: '<svg xmlns="http://www.w3.org/2000/svg" width="22" height="22" fill="#ffffff" viewBox="0 0 16 16"><path d="M15.5 3.5a.5.5 0 0 1 .5.5v8a.5.5 0 0 1-1 0V8.753l-6.267 3.636c-.54.313-1.233-.066-1.233-.697v-2.94l-6.267 3.636C.693 12.703 0 12.324 0 11.693V4.308c0-.63.693-1.01 1.233-.696L7.5 7.248v-2.94c0-.63.693-1.01 1.233-.696L15 7.248V4a.5.5 0 0 1 .5-.5"/></svg>'
    readonly property string _svgPlay: '<svg xmlns="http://www.w3.org/2000/svg" width="30" height="30" fill="#ffffff" viewBox="0 0 16 16"><path d="M11.596 8.697l-6.363 3.692c-.54.314-1.233-.065-1.233-.696V4.308c0-.63.693-1.01 1.233-.696l6.363 3.692a.802.802 0 0 1 0 1.393"/></svg>'
    readonly property string _svgPause: '<svg xmlns="http://www.w3.org/2000/svg" width="30" height="30" fill="#ffffff" viewBox="0 0 16 16"><path d="M5.5 3.5A1.5 1.5 0 0 1 7 5v6a1.5 1.5 0 0 1-3 0V5a1.5 1.5 0 0 1 1.5-1.5m5 0A1.5 1.5 0 0 1 12 5v6a1.5 1.5 0 0 1-3 0V5a1.5 1.5 0 0 1 1.5-1.5"/></svg>'
    readonly property string _svgRadar: '<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" fill="#ffffff" viewBox="0 0 16 16"><path d="M6.634 1.135A7 7 0 0 1 15 8a.5.5 0 0 1-1 0 6 6 0 1 0-6.5 5.98v-1.005A5 5 0 1 1 13 8a.5.5 0 0 1-1 0 4 4 0 1 0-4.5 3.969v-1.011A2.999 2.999 0 1 1 11 8a.5.5 0 0 1-1 0 2 2 0 1 0-2.5 1.936v-1.07a1 1 0 1 1 1 0V15.5a.5.5 0 0 1-1 0v-.518a7 7 0 0 1-.866-13.847"/></svg>'

    function _svgUrl(svg) {
        return "data:image/svg+xml;charset=utf-8," + encodeURIComponent(svg)
    }

    Rectangle {
        id: mainMusicCard
        width: Math.min(420, parent.width)
        height: contentCol.implicitHeight + 36
        anchors.horizontalCenter: parent.horizontalCenter
        radius: 35
        color: root.accentColor
        border.width: 0
        Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutCubic } }
        Behavior on height { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

        layer.enabled: !root.lowQualityWhileDragging
        layer.effect: DropShadow {
            transparentBorder: true
            horizontalOffset: 0
            verticalOffset: 8
            radius: 20
            samples: 32
            color: Qt.rgba(0, 0, 0, 0.4)
        }

        ColumnLayout {
            id: contentCol
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: 18
            }
            spacing: 14

            RowLayout {
                id: trackInfo
                Layout.fillWidth: true
                spacing: 12

                Item {
                    id: albumArt
                    Layout.preferredWidth: 64
                    Layout.preferredHeight: 64
                    Layout.minimumWidth: 64
                    Layout.minimumHeight: 64

                    Image {
                        id: coverImg
                        anchors.fill: parent
                        visible: root._displayCoverUrl.toString() !== ""
                        source: root._displayCoverUrl
                        sourceSize.width: Math.max(1, Math.round(width * root._dpr))
                        sourceSize.height: Math.max(1, Math.round(height * root._dpr))
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        smooth: true

                        layer.enabled: !root.lowQualityWhileDragging
                        layer.effect: OpacityMask {
                            maskSource: Rectangle {
                                width: coverImg.width
                                height: coverImg.height
                                radius: 16
                            }
                        }
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: 16
                        color: "transparent"
                        layer.enabled: !root.lowQualityWhileDragging
                        layer.effect: DropShadow {
                            transparentBorder: true
                            horizontalOffset: 0
                            verticalOffset: 4
                            radius: 10
                            samples: 16
                            color: Qt.rgba(0, 0, 0, 0.5)
                        }
                    }
                    Rectangle {
                        anchors.fill: parent
                        radius: 16
                        visible: root._displayCoverUrl.toString() === ""
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: "#ff9a9e" }
                            GradientStop { position: 1.0; color: "#fad0c4" }
                        }
                        layer.enabled: !root.lowQualityWhileDragging
                        layer.effect: DropShadow {
                            transparentBorder: true
                            horizontalOffset: 0
                            verticalOffset: 4
                            radius: 10
                            samples: 16
                            color: Qt.rgba(0, 0, 0, 0.5)
                        }
                    }
                }

                ColumnLayout {
                    id: trackDetails
                    Layout.fillWidth: true
                    spacing: 2
                    Layout.minimumWidth: 0

                    Label {
                        text: root._displayTitle
                        font.pixelSize: Math.round(1.3 * 13)
                        font.weight: Font.DemiBold
                        font.family: Qt.application.font.family
                        color: root.foregroundColor
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        Layout.fillWidth: true
                    }
                    Label {
                        text: root._displayArtist
                        font.pixelSize: Math.round(0.9 * 13)
                        font.family: Qt.application.font.family
                        color: Qt.rgba(root.foregroundColor.r, root.foregroundColor.g, root.foregroundColor.b, 0.75)
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        Layout.fillWidth: true
                    }
                }

                RowLayout {
                    id: volumeBars
                    spacing: 2
                    Layout.preferredWidth: 38
                    Layout.preferredHeight: 32
                    Layout.alignment: Qt.AlignBottom

                    Repeater {
                        model: 8
                        Item {
                            width: 3
                            height: volumeBars.height

                            Rectangle {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                radius: 2
                                gradient: Gradient {
                                    GradientStop { position: 0.0; color: Qt.darker(root.accentColor, 1.4) }
                                    GradientStop { position: 1.0; color: Qt.lighter(root.accentColor, 1.8) }
                                }
                                height: {
                                    if (!root._playing || root.lowQualityWhileDragging)
                                        return 6
                                    const bands = root._displayBands
                                    if (!bands || bands.length === 0)
                                        return 6
                                    const idx = Math.min(bands.length - 1, Math.max(0, Math.round(index * (bands.length - 1) / 7)))
                                    const v = Math.min(1, Math.max(0, Number(bands[idx]) * 6.0))
                                    return 6 + 20 * v
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    width: 34
                    height: 34
                    radius: 17
                    color: favMa.pressed ? Qt.rgba(1, 1, 1, 0.15) : (favMa.containsMouse ? Qt.rgba(1, 1, 1, 0.10) : "transparent")
                    Layout.alignment: Qt.AlignVCenter

                    Text {
                        anchors.centerIn: parent
                        text: (appWindow && typeof appWindow.isCurrentFavorite === "function" && appWindow.isCurrentFavorite()) ? "♥" : "♡"
                        font.family: Qt.application.font.family
                        font.pixelSize: 16
                        color: root.foregroundColor
                        opacity: (appWindow && appWindow.currentImage && appWindow.currentImage !== "") ? 1.0 : 0.45
                    }
                    MouseArea {
                        id: favMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        enabled: appWindow && typeof appWindow.toggleFavoriteCurrent === "function" && appWindow.currentImage && appWindow.currentImage !== ""
                        onClicked: appWindow.toggleFavoriteCurrent()
                    }
                }
            }

            Item {
                id: lyricsSection
                Layout.fillWidth: true
                readonly property bool _hasLyrics: root.lyricsEnabled && audioPlayer && audioPlayer.hasLyrics
                readonly property real _targetH: _hasLyrics ? lyricsBox.height : 0
                Layout.preferredHeight: _targetH
                Layout.minimumHeight: _targetH
                height: _targetH
                clip: true
                Behavior on Layout.preferredHeight { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                Behavior on height { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                opacity: _hasLyrics ? 1 : 0

                Rectangle {
                    id: lyricsBox
                    width: parent.width
                    height: 92
                    radius: 16
                    color: Qt.rgba(0, 0, 0, 0.18)
                    border.width: 1
                    border.color: Qt.rgba(root.foregroundColor.r, root.foregroundColor.g, root.foregroundColor.b, 0.18)

                    readonly property int _curIdx: {
                        if (!audioPlayer) return -1
                        const lines = audioPlayer.lyricLines
                        if (!lines || lines.length === 0) return -1
                        const idx = audioPlayer.currentLyricIndex
                        if (idx === undefined || idx === null || idx < 0 || idx >= lines.length) return 0
                        return idx
                    }

                    function _lineText(v) {
                        if (v === undefined || v === null) return ""
                        if (typeof v === "string") return v
                        if (typeof v === "object") return String(v.text || v.lyric || v.line || "")
                        return String(v)
                    }

                    function scrollToCurrent() {
                        const idx = _curIdx
                        if (idx < 0) return
                        const doScroll = function() {
                            if (!lyricsRepeater || typeof lyricsRepeater.itemAt !== "function") return
                            const item = lyricsRepeater.itemAt(idx)
                            if (!item) return
                            const target = item.y - ((lyricsFlickable.height - item.height) * 0.5)
                            const maxY = Math.max(0, lyricsFlickable.contentHeight - lyricsFlickable.height)
                            lyricsFlickable.contentY = Math.min(Math.max(0, target), maxY)
                        }
                        Qt.callLater(function() {
                            doScroll()
                            Qt.callLater(doScroll)
                        })
                    }

                    Connections {
                        target: audioPlayer
                        function onCurrentLyricIndexChanged() { lyricsBox.scrollToCurrent() }
                        function onLyricLinesChanged() { lyricsBox.scrollToCurrent() }
                    }

                    Flickable {
                        id: lyricsFlickable
                        anchors.fill: parent
                        anchors.margins: 10
                        clip: true
                        interactive: false
                        contentWidth: width
                        contentHeight: lyricsColumn.implicitHeight
                        onHeightChanged: lyricsBox.scrollToCurrent()
                        onContentHeightChanged: lyricsBox.scrollToCurrent()

                        Behavior on contentY {
                            NumberAnimation { duration: 600; easing.type: Easing.OutCubic }
                        }

                        Column {
                            id: lyricsColumn
                            width: lyricsFlickable.width
                            spacing: 10

                            Item { width: 1; height: Math.floor(lyricsFlickable.height * 0.5) }

                            Repeater {
                                id: lyricsRepeater
                                model: audioPlayer ? audioPlayer.lyricLines : []
                                Text {
                                    width: lyricsColumn.width
                                    text: lyricsBox._lineText(modelData)
                                    wrapMode: Text.WordWrap
                                    elide: Text.ElideRight
                                    maximumLineCount: 2
                                    font.family: Qt.application.font.family
                                    font.pixelSize: index === lyricsBox._curIdx ? 15 : 12
                                    font.weight: index === lyricsBox._curIdx ? Font.DemiBold : Font.Normal
                                    color: index === lyricsBox._curIdx
                                           ? root.foregroundColor
                                           : Qt.rgba(root.foregroundColor.r, root.foregroundColor.g, root.foregroundColor.b, 0.68)
                                    opacity: index === lyricsBox._curIdx ? 1.0 : 0.55

                                    Behavior on font.pixelSize { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                                    Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                                }
                            }

                            Item { width: 1; height: Math.floor(lyricsFlickable.height * 0.5) }
                        }
                    }
                }

                scale: visible ? 1.0 : 0.98
                transformOrigin: Item.Top
                Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutBack } }
            }

            ColumnLayout {
                id: playbackControls
                Layout.fillWidth: true
                spacing: 8

                RowLayout {
                    id: timeInfo
                    Layout.fillWidth: true
                    Label {
                        text: _formatTime(root._displayPosition)
                        font.pixelSize: Math.round(0.8 * 13)
                        font.family: Qt.application.font.family
                        color: Qt.rgba(root.foregroundColor.r, root.foregroundColor.g, root.foregroundColor.b, 0.55)
                    }
                    Item { Layout.fillWidth: true }
                    Label {
                        text: {
                            if (root._displayDuration <= 0)
                                return "0:00"
                            const rem = Math.max(0, root._displayDuration - root._displayPosition)
                            return "-" + _formatTime(rem)
                        }
                        font.pixelSize: Math.round(0.8 * 13)
                        font.family: Qt.application.font.family
                        color: Qt.rgba(root.foregroundColor.r, root.foregroundColor.g, root.foregroundColor.b, 0.55)
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Item {
                        id: volControl
                        Layout.preferredWidth: volumeBarHost.visible ? 112 : 24
                        Layout.preferredHeight: 24
                        z: 20
                        property bool volumeHovered: false
                        readonly property bool volumeExpanded: volumeHovered || volumeBarArea.containsMouse || volumeBarArea.pressed
                        Behavior on Layout.preferredWidth { NumberAnimation { duration: 170; easing.type: Easing.OutCubic } }

                        Rectangle {
                            id: volumeButton
                            width: 24
                            height: 24
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            radius: 8
                            property bool isPressed: false
                            color: isPressed
                                   ? Qt.rgba(root.foregroundColor.r, root.foregroundColor.g, root.foregroundColor.b, 0.16)
                                   : (volumeButtonMa.containsMouse || volControl.volumeExpanded
                                      ? Qt.rgba(root.foregroundColor.r, root.foregroundColor.g, root.foregroundColor.b, 0.10)
                                      : "transparent")
                            Behavior on color { ColorAnimation { duration: 200; easing.type: Easing.OutCubic } }
                            Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                            scale: isPressed ? 0.9 : (volumeButtonMa.containsMouse ? 1.05 : 1.0)

                            Image {
                                id: volumeIcon
                                anchors.centerIn: parent
                                width: 14
                                height: 14
                                source: _volumeIconPath()
                                sourceSize: Qt.size(14, 14)
                                visible: false
                            }
                            ColorOverlay {
                                anchors.fill: volumeIcon
                                source: volumeIcon
                                color: {
                                    const v = (audioPlayer && audioPlayer.volume !== undefined) ? Math.max(0, Math.min(1, audioPlayer.volume)) : 1
                                    if (v <= 0.001)
                                        return Qt.rgba(root.foregroundColor.r, root.foregroundColor.g, root.foregroundColor.b, 0.7)
                                    return (volControl.volumeExpanded || volumeButtonMa.containsMouse) ? Qt.lighter(root.accentColor, 1.25) : root.foregroundColor
                                }
                                opacity: 0.9
                            }

                            MouseArea {
                                id: volumeButtonMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onEntered: volControl.volumeHovered = true
                                onExited: volCollapseTimer.restart()
                                onPressed: volumeButton.isPressed = true
                                onReleased: volumeButton.isPressed = false
                                onClicked: {
                                    if (audioPlayer && typeof audioPlayer.toggleMute === "function")
                                        audioPlayer.toggleMute()
                                }
                            }
                        }

                        Timer {
                            id: volCollapseTimer
                            interval: 320
                            repeat: false
                            onTriggered: volControl.volumeHovered = false
                        }

                        Item {
                            id: volumeBarHost
                            anchors.left: volumeButton.right
                            anchors.leftMargin: 6
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            height: 14
                            visible: volControl.volumeExpanded
                            opacity: visible ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width
                                height: 4
                                radius: 2
                                color: Qt.rgba(root.foregroundColor.r, root.foregroundColor.g, root.foregroundColor.b, 0.12)
                            }

                            Rectangle {
                                width: parent.width * ((audioPlayer && audioPlayer.volume !== undefined) ? Math.max(0, Math.min(1, audioPlayer.volume)) : 0)
                                height: 4
                                radius: 2
                                anchors.verticalCenter: parent.verticalCenter
                                gradient: Gradient {
                                    orientation: Gradient.Horizontal
                                    GradientStop { position: 0.0; color: Qt.lighter(root.accentColor, 1.6) }
                                    GradientStop { position: 1.0; color: root.accentColor }
                                }
                                Behavior on width { NumberAnimation { duration: 100 } }
                            }

                            Rectangle {
                                id: volumeHandle
                                width: 9
                                height: 9
                                radius: 4.5
                                anchors.verticalCenter: parent.verticalCenter
                                x: Math.max(0, Math.min(parent.width - width, parent.width * ((audioPlayer && audioPlayer.volume !== undefined) ? Math.max(0, Math.min(1, audioPlayer.volume)) : 0) - width / 2))
                                color: root.foregroundColor
                                opacity: volumeBarArea.containsMouse || volumeBarArea.pressed ? 1 : 0.9
                                Behavior on opacity { NumberAnimation { duration: 120 } }
                            }

                            MouseArea {
                                id: volumeBarArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                enabled: audioPlayer && typeof audioPlayer.setOutputVolume === "function"

                                function setFromMouse(mouse) {
                                    if (!audioPlayer || parent.width <= 0) return
                                    const v = Math.max(0, Math.min(1, mouse.x / parent.width))
                                    audioPlayer.setOutputVolume(v)
                                }

                                onEntered: {
                                    volControl.volumeHovered = true
                                    volCollapseTimer.stop()
                                }
                                onExited: {
                                    if (!pressed && !volumeButtonMa.containsMouse)
                                        volCollapseTimer.restart()
                                }
                                onPressed: function(mouse) {
                                    volControl.volumeHovered = true
                                    volCollapseTimer.stop()
                                    setFromMouse(mouse)
                                }
                                onPositionChanged: function(mouse) {
                                    if (!pressed) return
                                    setFromMouse(mouse)
                                }
                                onReleased: {
                                    if (!containsMouse && !volumeButtonMa.containsMouse)
                                        volCollapseTimer.restart()
                                }
                                onClicked: function(mouse) { setFromMouse(mouse) }
                            }
                        }
                    }

                    Item {
                        id: progressBarHost
                        Layout.fillWidth: true
                        Layout.preferredHeight: 14

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width
                            height: 4
                            radius: 2
                            color: Qt.rgba(root.foregroundColor.r, root.foregroundColor.g, root.foregroundColor.b, 0.12)
                        }
                        Rectangle {
                            id: progressFill
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width * root._displayProgress
                            height: 4
                            radius: 2
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0.0; color: Qt.lighter(root.accentColor, 1.6) }
                                GradientStop { position: 1.0; color: root.accentColor }
                            }
                        }
                        Rectangle {
                            id: progressHandle
                            width: 9
                            height: 9
                            radius: 4.5
                            color: root.foregroundColor
                            x: Math.max(0, Math.min(parent.width - width, parent.width * root._displayProgress - width / 2))
                            anchors.verticalCenter: parent.verticalCenter
                            z: 2
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            enabled: audioPlayer && audioPlayer.seekable && audioPlayer.duration > 0
                            function setFromMouse(mouse) {
                                if (!audioPlayer || progressBarHost.width <= 0) return
                                const ratio = Math.min(1, Math.max(0, mouse.x / progressBarHost.width))
                                if (typeof audioPlayer.seekToPosition === "function")
                                    audioPlayer.seekToPosition(ratio * audioPlayer.duration)
                            }
                            onPressed: function(mouse) { setFromMouse(mouse) }
                            onPositionChanged: function(mouse) {
                                if (!pressed) return
                                setFromMouse(mouse)
                            }
                            onClicked: function(mouse) { setFromMouse(mouse) }
                        }
                    }
                }

                Item {
                    Layout.fillWidth: true
                    readonly property bool _hasQueue: false
                    visible: _hasQueue
                    readonly property real _targetH: _hasQueue ? upNextCol.implicitHeight : 0
                    Layout.preferredHeight: _targetH
                    Layout.minimumHeight: _targetH
                    height: _targetH
                    clip: true
                    Behavior on Layout.preferredHeight { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                    Behavior on height { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                    opacity: _hasQueue ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                    Column {
                        id: upNextCol
                        width: parent.width
                        spacing: 6
                    }
                }

                RowLayout {
                    id: buttonRow
                    Layout.fillWidth: true
                    spacing: 12

                    Item {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        implicitHeight: 52

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 20
                            Layout.minimumWidth: 0

                            Rectangle {
                                width: 52
                                height: 52
                                radius: 26
                                color: backMa.pressed ? Qt.rgba(1, 1, 1, 0.15) : (backMa.containsMouse ? Qt.rgba(1, 1, 1, 0.1) : "transparent")
                                Image {
                                    anchors.centerIn: parent
                                    width: 22
                                    height: 22
                                    source: _svgUrl(_svgSkipBack)
                                    smooth: true
                                }
                                MouseArea {
                                    id: backMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    enabled: appWindow && typeof appWindow.previousImage === "function"
                                    opacity: enabled ? 1 : 0.35
                                    onClicked: {
                                        if (appWindow && typeof appWindow.previousImage === "function")
                                            appWindow.previousImage()
                                    }
                                }
                            }

                            Rectangle {
                                width: 52
                                height: 52
                                radius: 26
                                color: playMa.pressed ? Qt.rgba(1, 1, 1, 0.15) : (playMa.containsMouse ? Qt.rgba(1, 1, 1, 0.1) : "transparent")
                                Image {
                                    anchors.centerIn: parent
                                    width: 30
                                    height: 30
                                    source: {
                                        const _ = root._stateTick
                                        return _svgUrl(root._displayPlaybackState === MediaPlayer.PlayingState ? _svgPause : _svgPlay)
                                    }
                                    smooth: true
                                }
                                MouseArea {
                                    id: playMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    enabled: audioPlayer && audioPlayer.source && audioPlayer.source !== ""
                                    onClicked: {
                                        if (!audioPlayer)
                                            return
                                        if (root._playing) {
                                            if (typeof audioPlayer.pause === "function")
                                                audioPlayer.pause()
                                        } else {
                                            if (typeof audioPlayer.play === "function")
                                                audioPlayer.play()
                                        }
                                    }
                                }
                            }

                            Rectangle {
                                width: 52
                                height: 52
                                radius: 26
                                color: nextMa.pressed ? Qt.rgba(1, 1, 1, 0.15) : (nextMa.containsMouse ? Qt.rgba(1, 1, 1, 0.1) : "transparent")
                                Image {
                                    anchors.centerIn: parent
                                    width: 22
                                    height: 22
                                    source: _svgUrl(_svgSkipFwd)
                                    smooth: true
                                }
                                MouseArea {
                                    id: nextMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    enabled: appWindow && typeof appWindow.nextImage === "function"
                                    opacity: enabled ? 1 : 0.35
                                    onClicked: {
                                        if (appWindow && typeof appWindow.nextImage === "function")
                                            appWindow.nextImage()
                                    }
                                }
                            }
                        }
                    }

                    RowLayout {
                        spacing: 8

                        Rectangle {
                            width: 44
                            height: 44
                            radius: 22
                            readonly property bool _active: appWindow && appWindow.queueShuffle
                            color: shuffleMa.pressed
                                   ? Qt.rgba(1, 1, 1, 0.15)
                                   : ((shuffleMa.containsMouse || _active)
                                      ? Qt.rgba(1, 1, 1, _active ? 0.16 : 0.10)
                                      : "transparent")
                            Image {
                                id: shuffleIcon
                                anchors.centerIn: parent
                                width: 17
                                height: 17
                                source: "qrc:/qlementine/icons/16/media/shuffle.svg"
                                sourceSize: Qt.size(17, 17)
                                visible: false
                            }
                            ColorOverlay {
                                anchors.fill: shuffleIcon
                                source: shuffleIcon
                                color: parent._active ? Qt.lighter(root.accentColor, 1.25) : root.foregroundColor
                                opacity: parent._active ? 1.0 : 0.85
                            }
                            MouseArea {
                                id: shuffleMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                enabled: appWindow !== null && appWindow.queueShuffle !== undefined
                                onClicked: {
                                    if (appWindow && appWindow.queueShuffle !== undefined) {
                                        appWindow.queueShuffle = !appWindow.queueShuffle
                                        if (appWindow.queueShuffle && typeof appWindow.shuffleQueueNow === "function")
                                            appWindow.shuffleQueueNow()
                                    }
                                }
                            }
                        }

                        Rectangle {
                            width: 44
                            height: 44
                            radius: 22
                            readonly property string _mode: (appWindow && appWindow.queueRepeatMode) ? appWindow.queueRepeatMode : "off"
                            readonly property bool _active: _mode !== "off"
                            color: repeatMa.pressed
                                   ? Qt.rgba(1, 1, 1, 0.15)
                                   : ((repeatMa.containsMouse || _active)
                                      ? Qt.rgba(1, 1, 1, _active ? 0.16 : 0.10)
                                      : "transparent")
                            Image {
                                id: repeatIcon
                                anchors.centerIn: parent
                                width: 17
                                height: 17
                                source: "qrc:/qlementine/icons/16/media/repeat.svg"
                                sourceSize: Qt.size(17, 17)
                                visible: false
                            }
                            ColorOverlay {
                                anchors.fill: repeatIcon
                                source: repeatIcon
                                color: parent._active ? Qt.lighter(root.accentColor, 1.25) : root.foregroundColor
                                opacity: parent._active ? 1.0 : 0.85
                            }
                            Text {
                                visible: parent._mode === "one"
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                anchors.rightMargin: 9
                                anchors.bottomMargin: 7
                                text: "1"
                                font.family: Qt.application.font.family
                                font.pixelSize: 9
                                font.bold: true
                                color: Qt.lighter(root.accentColor, 1.35)
                            }
                            MouseArea {
                                id: repeatMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                enabled: appWindow !== null && appWindow.queueRepeatMode !== undefined
                                onClicked: {
                                    if (!appWindow || appWindow.queueRepeatMode === undefined)
                                        return
                                    if (appWindow.queueRepeatMode === "off")
                                        appWindow.queueRepeatMode = "all"
                                    else if (appWindow.queueRepeatMode === "all")
                                        appWindow.queueRepeatMode = "one"
                                    else
                                        appWindow.queueRepeatMode = "off"
                                    if (audioPlayer && typeof audioPlayer.setLoopEnabled === "function")
                                        audioPlayer.setLoopEnabled(appWindow.queueRepeatMode !== "off")
                                }
                            }
                        }

                        Rectangle {
                            width: 44
                            height: 44
                            radius: 22
                            color: radarMa.pressed ? Qt.rgba(1, 1, 1, 0.15) : (radarMa.containsMouse ? Qt.rgba(1, 1, 1, 0.1) : "transparent")
                            Text {
                                anchors.centerIn: parent
                                text: "LYR"
                                font.family: Qt.application.font.family
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                                color: root.foregroundColor
                                opacity: root.lyricsEnabled ? 1.0 : 0.55
                            }
                            MouseArea {
                                id: radarMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.lyricsEnabled = !root.lyricsEnabled
                            }
                        }
                    }
                }

                Item {
                    Layout.fillWidth: true
                    readonly property bool _hasQueue: appWindow && appWindow.playbackQueue && appWindow.playbackQueue.length > 0
                    visible: _hasQueue
                    readonly property real _targetH: _hasQueue ? upNextColAfter.implicitHeight : 0
                    Layout.preferredHeight: _targetH
                    Layout.minimumHeight: _targetH
                    height: _targetH
                    clip: true
                    Behavior on Layout.preferredHeight { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                    Behavior on height { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                    opacity: _hasQueue ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                    Column {
                        id: upNextColAfter
                        width: parent.width
                        spacing: 6

                        Text {
                            text: "Up next"
                            font.family: Qt.application.font.family
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                            color: Qt.rgba(root.foregroundColor.r, root.foregroundColor.g, root.foregroundColor.b, 0.7)
                        }

                        Flow {
                            width: parent.width
                            spacing: 8
                            flow: Flow.LeftToRight
                            layoutDirection: Qt.LeftToRight

                            Repeater {
                                model: (appWindow && appWindow.playbackQueue) ? appWindow.playbackQueue.slice(0, 3) : []
                                Rectangle {
                                    height: 26
                                    radius: 13
                                    color: Qt.rgba(0, 0, 0, 0.18)
                                    border.width: 1
                                    border.color: Qt.rgba(root.foregroundColor.r, root.foregroundColor.g, root.foregroundColor.b, 0.14)
                                    width: Math.min(upNextColAfter.width, Math.max(110, chipTextAfter.implicitWidth + 44))

                                    Rectangle {
                                        id: chipThumbAfter
                                        width: 18
                                        height: 18
                                        radius: 6
                                        anchors.left: parent.left
                                        anchors.leftMargin: 6
                                        anchors.verticalCenter: parent.verticalCenter
                                        color: Qt.rgba(0, 0, 0, 0.18)
                                        clip: true
                                        Image {
                                            anchors.fill: parent
                                            source: {
                                                const _ = root._chromeTick
                                                return _queueThumbForUrl(modelData)
                                            }
                                            visible: source && source !== ""
                                            fillMode: Image.PreserveAspectCrop
                                            asynchronous: true
                                            smooth: true
                                            layer.enabled: !root.lowQualityWhileDragging
                                            layer.effect: OpacityMask {
                                                maskSource: Rectangle {
                                                    width: chipThumbAfter.width
                                                    height: chipThumbAfter.height
                                                    radius: chipThumbAfter.radius
                                                }
                                            }
                                        }
                                    }

                                    Text {
                                        id: chipTextAfter
                                        anchors.left: chipThumbAfter.right
                                        anchors.leftMargin: 6
                                        anchors.right: parent.right
                                        anchors.rightMargin: 10
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: _displayNameForUrl(modelData)
                                        font.family: Qt.application.font.family
                                        font.pixelSize: 11
                                        color: Qt.rgba(root.foregroundColor.r, root.foregroundColor.g, root.foregroundColor.b, 0.9)
                                        elide: Text.ElideRight
                                        horizontalAlignment: Text.AlignLeft
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (appWindow && typeof appWindow.skipToQueueIndex === "function")
                                                appWindow.skipToQueueIndex(index)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Item {
                    Layout.fillWidth: true
                    readonly property bool _hasFav: appWindow && appWindow.favoriteItems && appWindow.favoriteItems.length > 0
                    visible: _hasFav
                    readonly property real _targetH: _hasFav ? likedCol.implicitHeight : 0
                    Layout.preferredHeight: _targetH
                    Layout.minimumHeight: _targetH
                    height: _targetH
                    clip: true
                    Behavior on Layout.preferredHeight { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                    Behavior on height { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                    opacity: _hasFav ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                    Column {
                        id: likedCol
                        width: parent.width
                        spacing: 6

                        Text {
                            text: "Liked"
                            font.family: Qt.application.font.family
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                            color: Qt.rgba(root.foregroundColor.r, root.foregroundColor.g, root.foregroundColor.b, 0.7)
                        }

                        Flow {
                            width: parent.width
                            spacing: 8
                            flow: Flow.LeftToRight
                            layoutDirection: Qt.LeftToRight

                            Repeater {
                                model: (appWindow && appWindow.favoriteItems) ? appWindow.favoriteItems.slice(0, 8) : []
                                Rectangle {
                                    height: 26
                                    radius: 13
                                    color: Qt.rgba(0, 0, 0, 0.18)
                                    border.width: 1
                                    border.color: Qt.rgba(root.foregroundColor.r, root.foregroundColor.g, root.foregroundColor.b, 0.14)
                                    width: Math.min(likedCol.width, Math.max(110, likedChipText.implicitWidth + 44))

                                    Rectangle {
                                        id: likedChipThumb
                                        width: 18
                                        height: 18
                                        radius: 6
                                        anchors.left: parent.left
                                        anchors.leftMargin: 6
                                        anchors.verticalCenter: parent.verticalCenter
                                        color: Qt.rgba(0, 0, 0, 0.18)
                                        clip: true
                                        Image {
                                            id: likedChipImg
                                            anchors.fill: parent
                                            source: {
                                                const _ = root._chromeTick
                                                return modelData && modelData.indexOf("http") !== 0 ? _queueThumbForUrl(modelData) : ""
                                            }
                                            visible: source !== undefined && source !== null && source.toString() !== ""
                                            fillMode: Image.PreserveAspectCrop
                                            asynchronous: true
                                            smooth: true
                                            layer.enabled: !root.lowQualityWhileDragging
                                            layer.effect: OpacityMask {
                                                maskSource: Rectangle {
                                                    width: likedChipThumb.width
                                                    height: likedChipThumb.height
                                                    radius: likedChipThumb.radius
                                                }
                                            }
                                        }
                                        Text {
                                            anchors.centerIn: parent
                                            visible: !likedChipImg.visible
                                            text: "♥"
                                            font.pixelSize: 10
                                            color: root.foregroundColor
                                            opacity: 0.85
                                        }
                                    }

                                    Text {
                                        id: likedChipText
                                        anchors.left: likedChipThumb.right
                                        anchors.leftMargin: 6
                                        anchors.right: parent.right
                                        anchors.rightMargin: 10
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: {
                                            const u = modelData ? ("" + modelData) : ""
                                            if (u.indexOf("youtube.com") >= 0 || u.indexOf("youtu.be") >= 0)
                                                return "YouTube"
                                            return _displayNameForUrl(modelData)
                                        }
                                        font.family: Qt.application.font.family
                                        font.pixelSize: 11
                                        color: Qt.rgba(root.foregroundColor.r, root.foregroundColor.g, root.foregroundColor.b, 0.9)
                                        elide: Text.ElideRight
                                        horizontalAlignment: Text.AlignLeft
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (appWindow && typeof appWindow.playFavoriteEntry === "function")
                                                appWindow.playFavoriteEntry(modelData)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        Rectangle {
            parent: mainMusicCard
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: 10
            width: 32
            height: 32
            radius: 16
            color: closeMa.containsMouse ? Qt.rgba(255, 255, 255, 0.12) : "transparent"
            z: 100
            Text {
                anchors.centerIn: parent
                text: "\u00D7"
                color: root.foregroundColor
                font.pixelSize: 18
            }
            MouseArea {
                id: closeMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.closed()
            }
        }
    }
}