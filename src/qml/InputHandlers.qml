import QtQuick
import QtMultimedia

/**
 * InputHandlers.qml
 * Reusable input handlers for media viewer (wheel, tap, drag, drop)
 */
Item {
    id: inputHandlers
    
    // Properties
    property url currentImage: ""
    property bool isVideo: false
    property bool isAudio: false
    property bool isMarkdown: false
    property bool isText: false
    property bool isPdf: false
    property bool isImageType: false
    property bool showImageControls: false
    property var videoPlayerLoader: null
    property var viewerLoader: null
    property var imageControls: null  // Reference to ImageControls to check tap bounds
    
    // Signals
    signal adjustZoomRequested(real delta)
    signal resetViewRequested()
    signal toggleImageControls()
    signal toggleVideoPlayback()
    signal fileDropped(url fileUrl)
    signal dropActiveChanged(bool active)
    
    // Functions (removed - not needed, using signals instead)
    
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
        enabled: currentImage.toString() !== "" && !isVideo && !isAudio && !isMarkdown && !isText && !isPdf
    }

    TapHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        gesturePolicy: TapHandler.ReleaseWithinBounds
        onDoubleTapped: resetViewRequested()
        onTapped: function(event) {
            // Don't toggle if clicking on image controls
            if (imageControls && imageControls.visible) {
                const point = event.position
                const controlsPoint = imageControls.mapFromItem(inputHandlers, point.x, point.y)
                if (controlsPoint.x >= 0 && controlsPoint.x <= imageControls.width &&
                    controlsPoint.y >= 0 && controlsPoint.y <= imageControls.height) {
                    // Click is within image controls, don't toggle
                    return
                }
            }
            // Toggle image controls on single tap
            if (isImageType && currentImage.toString() !== "") {
                toggleImageControls()
            }
        }
        enabled: currentImage.toString() !== "" && !isVideo
    }
    
    TapHandler {
        id: videoTapHandler
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        gesturePolicy: TapHandler.ReleaseWithinBounds
        onTapped: {
            if (isVideo && currentImage !== "") {
                toggleVideoPlayback()
            }
        }
        enabled: currentImage !== "" && isVideo
    }

    DragHandler {
        id: drag
        property real prevX: 0
        property real prevY: 0
        target: null
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad | PointerDevice.Stylus
        enabled: currentImage.toString() !== "" && !isVideo && !isAudio && !isMarkdown && !isText && !isPdf
        onActiveChanged: {
            prevX = translation.x
            prevY = translation.y
        }
        onTranslationChanged: {
            if (viewerLoader && viewerLoader.item) {
                const imageViewer = viewerLoader.item
                const factor = imageViewer.zoomFactor === 0 ? 1 : imageViewer.zoomFactor
                imageViewer.panX += (translation.x - prevX) / factor
                imageViewer.panY += (translation.y - prevY) / factor
                prevX = translation.x
                prevY = translation.y
                imageViewer.clampPan()
            }
        }
    }

    DropArea {
        anchors.fill: parent
        keys: [ "text/uri-list" ]
        onEntered: dropActiveChanged(true)
        onExited: dropActiveChanged(false)
        onDropped: function(drop) {
            dropActiveChanged(false)
            if (drop.hasUrls && drop.urls.length > 0) {
                const fileUrl = drop.urls[0]
                fileDropped(fileUrl)
            }
        }
    }
}

