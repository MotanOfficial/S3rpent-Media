import QtQuick
import QtMultimedia
import s3rpent_media 1.0 as S3rpentMedia

/**
 * Video-only overlay card matching MusicPlayerOverlay's shape.
 * Displays muted video and syncs it to the app audio player's position.
 */
Item {
    id: root
    width: parent ? parent.width : 420

    implicitWidth: mainCard.width
    implicitHeight: mainCard.height

    property color accentColor: "#0072ff"
    property color foregroundColor: "#ffffff"
    property bool overlayActive: false
    property var appWindow: null
    property var audioPlayer: null
    property url videoSource: ""
    // If true, this overlay becomes an audio+video popup player.
    // If false, it stays video-only and muted (useful when main app audio is playing).
    property bool playAudio: false

    signal closed()

    // Use the custom FFmpeg backend (same as VideoPlayer.qml's "ffmpeg" backend).
    // Audio comes from the main app player; this video renderer is muted by design.
    S3rpentMedia.FFmpegVideoPlayer {
        id: videoPlayer
        logTag: "MusicOverlay"
        source: (root._hasVideoUrl && root.overlayActive) ? root.videoSource : ""
        volume: root.playAudio
            ? ((root.appWindow && root.appWindow.videoVolume !== undefined) ? root.appWindow.videoVolume : 1.0)
            : 0.0
        audioEnabled: root.playAudio
        useYtDlpPipe: true
        ytDlpMaxHeight: (root.appWindow && root.appWindow.musicVideoMaxHeight !== undefined)
            ? root.appWindow.musicVideoMaxHeight
            : 0

        onErrorOccurred: function(error, errorString) {
            const msg = (errorString !== undefined && errorString !== null) ? String(errorString) : ""
            console.warn("[MusicVideoOverlay][FFmpeg] Video error:", error, msg)
        }
    }

    // FFmpeg backend needs the QQuickWindow to initialize RHI/D3D11 resources.
    onWindowChanged: {
        if (root.window && videoPlayer) {
            videoPlayer.window = root.window
        }
    }

    readonly property bool _hasVideoUrl: {
        const u = root.videoSource
        if (!u)
            return false
        const s = u.toString ? u.toString() : String(u)
        return s.length > 0
    }

    // Frequent seeks cause visible stutter; only correct large drift and throttle hard seeks.
    property int _lastVideoSeekWallMs: 0

    function _syncToAudio(force) {
        if (!audioPlayer || !videoPlayer || !root._hasVideoUrl)
            return
        // yt-dlp pipe streams often have duration=0 and are not seekable; avoid spam-seeking,
        // which causes looping/restarts and stutter.
        if (!videoPlayer.seekable || videoPlayer.duration <= 0)
            return
        const ap = audioPlayer.position !== undefined ? audioPlayer.position : 0
        const vp = videoPlayer.position
        const drift = Math.abs(vp - ap)
        const now = Date.now()
        if (force) {
            if (drift > 80) {
                root._lastVideoSeekWallMs = now
                videoPlayer.seek(ap)
            }
            return
        }
        if (drift < 2800)
            return
        if ((now - root._lastVideoSeekWallMs) < 3200 && drift < 8000)
            return
        root._lastVideoSeekWallMs = now
        videoPlayer.seek(ap)
    }

    function _tryPlayVideo() {
        if (!root.overlayActive || !root._hasVideoUrl)
            return
        if (!audioPlayer)
            return
        const ps = audioPlayer.playbackState !== undefined ? audioPlayer.playbackState : MediaPlayer.StoppedState
        if (ps === MediaPlayer.PlayingState) {
            root._syncToAudio(true)
            videoPlayer.play()
        } else if (ps === MediaPlayer.PausedState) {
            root._syncToAudio(true)
            videoPlayer.pause()
        } else {
            videoPlayer.stop()
        }
    }

    Timer {
        interval: 900
        repeat: true
        running: root.overlayActive && root._hasVideoUrl && audioPlayer
                && audioPlayer.playbackState === MediaPlayer.PlayingState
        onTriggered: root._syncToAudio(false)
    }

    onOverlayActiveChanged: {
        if (!overlayActive) {
            videoPlayer.stop()
            return
        }
        Qt.callLater(root._tryPlayVideo)
    }

    onVideoSourceChanged: {
        if (!root.overlayActive)
            return
        Qt.callLater(root._tryPlayVideo)
    }

    onAudioPlayerChanged: {
        if (root.overlayActive && root._hasVideoUrl)
            Qt.callLater(root._tryPlayVideo)
    }

    Connections {
        target: videoPlayer
        function onDurationChanged() {
            if (!root.overlayActive || !root._hasVideoUrl)
                return
            if (videoPlayer.duration > 0) {
                Qt.callLater(root._tryPlayVideo)
            }
        }
    }

    Connections {
        target: audioPlayer
        enabled: !!audioPlayer
        function onPlaybackStateChanged() {
            if (!root.overlayActive || !root._hasVideoUrl)
                return
            if (audioPlayer.playbackState === MediaPlayer.PlayingState) {
                root._syncToAudio(true)
                videoPlayer.play()
            } else if (audioPlayer.playbackState === MediaPlayer.PausedState) {
                videoPlayer.pause()
            } else if (audioPlayer.playbackState === MediaPlayer.StoppedState) {
                videoPlayer.stop()
            }
        }
    }

    Rectangle {
        id: mainCard
        width: Math.min(420, parent ? parent.width : 420)
        height: 280
        anchors.horizontalCenter: parent ? parent.horizontalCenter : undefined
        radius: 35
        color: root.accentColor
        border.width: 0

        // Soft shadow without layer.effect (keeps VideoOutput in normal scene graph).
        Rectangle {
            z: -1
            anchors.fill: parent
            anchors.topMargin: 5
            radius: parent.radius
            color: Qt.rgba(0, 0, 0, 0.28)
        }

        // inner rounded viewport
        Rectangle {
            id: viewport
            anchors.fill: parent
            anchors.margins: 18
            radius: 22
            color: Qt.rgba(0, 0, 0, 0.18)
            border.width: 1
            border.color: Qt.rgba(root.foregroundColor.r, root.foregroundColor.g, root.foregroundColor.b, 0.16)
            clip: true

            VideoOutput {
                id: videoOut
                anchors.fill: parent
                visible: root._hasVideoUrl && String(videoPlayer.source) !== ""
                fillMode: VideoOutput.PreserveAspectCrop

                Component.onCompleted: {
                    if (videoPlayer && videoOut.videoSink) {
                        videoPlayer.videoSink = videoOut.videoSink
                    }
                }
            }

            // Fallback if no video is available
            Item {
                anchors.fill: parent
                visible: !root._hasVideoUrl || String(videoPlayer.source) === ""
                Text {
                    anchors.centerIn: parent
                    text: "No video"
                    color: root.foregroundColor
                    opacity: 0.85
                    font.pixelSize: 18
                }
            }
        }

        // Close button (top-right inside the card)
        Rectangle {
            width: 34
            height: 34
            radius: 17
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.topMargin: 10
            anchors.rightMargin: 10
            color: closeMa.pressed ? Qt.rgba(1, 1, 1, 0.15) : (closeMa.containsMouse ? Qt.rgba(1, 1, 1, 0.10) : "transparent")

            Text {
                anchors.centerIn: parent
                text: "✕"
                color: root.foregroundColor
                font.pixelSize: 16
            }

            MouseArea {
                id: closeMa
                anchors.fill: parent
                hoverEnabled: true
                onClicked: root.closed()
            }
        }
    }
}

