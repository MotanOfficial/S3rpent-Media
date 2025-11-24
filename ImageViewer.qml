import QtQuick
import QtQuick.Layouts

Item {
    id: imageViewer
    
    property url source: ""
    property bool isGif: false
    property real zoomFactor: 1.0
    property real panX: 0
    property real panY: 0
    property color accentColor: "#121216"
    
    signal imageReady()
    signal paintedSizeChanged()
    
    function adjustZoom(delta) {
        if (source === "")
            return;
        const factor = Math.pow(1.0015, delta);
        zoomFactor = Math.max(0.25, Math.min(zoomFactor * factor, 8.0));
        clampPan();
    }
    
    function resetView() {
        zoomFactor = 1.0
        panX = 0
        panY = 0
    }
    
    function clampPan() {
        if (source === "") {
            panX = 0
            panY = 0
            return
        }
        
        const imageSource = isGif ? animatedGif : photo
        if (imageSource.paintedWidth === 0 || imageSource.paintedHeight === 0) {
            panX = 0
            panY = 0
            return
        }
        
        const contentW = imageSource.paintedWidth
        const contentH = imageSource.paintedHeight
        const viewportW = mediaContainer.width
        const viewportH = mediaContainer.height
        const scaledW = contentW * zoomFactor
        const scaledH = contentH * zoomFactor
        
        const limitX = Math.max(0, (scaledW - viewportW) / 2)
        const limitY = Math.max(0, (scaledH - viewportH) / 2)
        
        panX = limitX === 0 ? 0 : Math.max(-limitX, Math.min(panX, limitX))
        panY = limitY === 0 ? 0 : Math.max(-limitY, Math.min(panY, limitY))
    }
    
    // Throttle clampPan during resize to avoid lag
    Timer {
        id: clampPanTimer
        interval: 16  // ~60fps
        onTriggered: clampPan()
    }
    
    onWidthChanged: {
        if (!clampPanTimer.running) {
            clampPanTimer.start()
        }
    }
    onHeightChanged: {
        if (!clampPanTimer.running) {
            clampPanTimer.start()
        }
    }
    
    Item {
        id: mediaContainer
        anchors.centerIn: parent
        width: Math.max(0, parent.width)
        height: Math.max(0, parent.height)
        visible: imageViewer.source !== ""
        transform: [
            Translate { x: panX; y: panY },
            Scale {
                origin.x: width / 2
                origin.y: height / 2
                xScale: zoomFactor
                yScale: zoomFactor
            }
        ]
        
        Image {
            id: photo
            anchors.fill: parent
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            cache: false
            smooth: true
            visible: !imageViewer.isGif && imageViewer.source !== ""
            source: (!imageViewer.isGif && imageViewer.source !== "") ? imageViewer.source : ""
            onStatusChanged: {
                if (status === Image.Ready) {
                    imageReady()
                    clampPan()
                }
            }
            onPaintedWidthChanged: {
                clampPan()
                paintedSizeChanged()
            }
            onPaintedHeightChanged: {
                clampPan()
                paintedSizeChanged()
            }
        }
        
        AnimatedImage {
            id: animatedGif
            anchors.fill: parent
            fillMode: AnimatedImage.PreserveAspectFit
            asynchronous: true
            cache: false
            smooth: true
            visible: imageViewer.isGif && imageViewer.source !== ""
            source: (imageViewer.isGif && imageViewer.source !== "") ? imageViewer.source : ""
            playing: true
            onStatusChanged: {
                if (status === AnimatedImage.Ready) {
                    imageReady()
                    clampPan()
                }
            }
            onPaintedWidthChanged: {
                clampPan()
                paintedSizeChanged()
            }
            onPaintedHeightChanged: {
                clampPan()
                paintedSizeChanged()
            }
        }
    }
    
    // Expose image properties for metadata
    property int paintedWidth: isGif ? animatedGif.paintedWidth : photo.paintedWidth
    property int paintedHeight: isGif ? animatedGif.paintedHeight : photo.paintedHeight
    property int frameCount: isGif ? animatedGif.frameCount : 0
    property int currentFrame: isGif ? animatedGif.currentFrame : 0
    property int status: isGif ? animatedGif.status : photo.status
}

