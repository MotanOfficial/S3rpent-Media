import QtQuick 2.15
import s3rpent_media 1.0 as S3rpentMedia

Item {
    id: root
    property var player: null
    property real videoRotation: 0
    property bool rendererVisible: true

    S3rpentMedia.MPVVideoItem {
        id: mpvVideoDisplayOpenGL
        player: root.player
        anchors.fill: parent
        visible: root.rendererVisible
        enabled: true
        z: 1

        Component.onCompleted: {
            console.log("[MPVVideoItem] Component created, player:", player)
            console.log("[MPVVideoItem] Size:", width, "x", height)
            console.log("[MPVVideoItem] Using QQuickFramebufferObject-based renderer (Qt Quick native)")
        }

        onPlayerChanged: {
            console.log("[MPVVideoItem] Player changed")
        }

        transform: Rotation {
            origin.x: mpvVideoDisplayOpenGL.width / 2
            origin.y: mpvVideoDisplayOpenGL.height / 2
            angle: root.videoRotation
        }
    }
}
