import QtQuick
import QtQuick.Layouts

Item {
    id: mediaViewer
    
    property url currentImage: ""
    property bool isVideo: false
    property bool isGif: false
    property bool isAudio: false
    property bool dropActive: false
    property color accentColor: "#121216"
    property color foregroundColor: "#f5f5f5"
    property real zoomFactor: 1.0
    property real panX: 0
    property real panY: 0
    
    signal fileDropped(url fileUrl)
    signal adjustZoomRequested(real delta)
    signal resetViewRequested()
    
    Rectangle {
        id: viewer
        anchors.fill: parent
        color: Qt.darker(accentColor, 1.15)
        clip: true
        focus: true
        property int padding: 0

        WheelHandler {
            id: wheel
            target: null
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: function(event) {
                const delta = event.angleDelta && event.angleDelta.y !== 0
                              ? event.angleDelta.y
                              : (event.pixelDelta ? event.pixelDelta.y * 8 : 0)
                if (delta !== 0)
                    adjustZoomRequested(delta)
            }
            enabled: currentImage !== "" && !isVideo && !isAudio
        }

        TapHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            gesturePolicy: TapHandler.ReleaseWithinBounds
            onDoubleTapped: resetViewRequested()
            enabled: currentImage !== "" && !isVideo
        }

        DragHandler {
            id: drag
            property real prevX: 0
            property real prevY: 0
            target: null
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad | PointerDevice.Stylus
            enabled: currentImage !== "" && !isVideo && !isAudio
            onActiveChanged: {
                prevX = translation.x
                prevY = translation.y
            }
            onTranslationChanged: {
                // This will be handled by the parent
                prevX = translation.x
                prevY = translation.y
            }
        }

        DropArea {
            anchors.fill: parent
            keys: [ "text/uri-list" ]
            onEntered: dropActive = true
            onExited: dropActive = false
            onDropped: function(drop) {
                dropActive = false
                if (drop.hasUrls && drop.urls.length > 0) {
                    fileDropped(drop.urls[0])
                    drop.acceptProposedAction()
                }
            }
        }

        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(accentColor.r, accentColor.g, accentColor.b, 0.25)
            visible: dropActive
            border.color: Qt.rgba(accentColor.r, accentColor.g, accentColor.b, 0.5)
            border.width: 2
        }

        Text {
            anchors.centerIn: parent
            visible: currentImage === ""
            color: dropActive ? "#050505" : foregroundColor
            font.pixelSize: 22
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: dropActive ? qsTr("Drop media to open") : qsTr("Drag & drop media\nor press Ctrl+O")
        }
    }
}

