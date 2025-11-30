import QtQuick
import QtQuick.Layouts

Item {
    id: imageViewer
    
    property url source: ""
    property bool isGif: false
    property real zoomFactor: 1.0
    property real panX: 0
    property real panY: 0
    property int rotation: 0  // Rotation in degrees (0, 90, 180, 270)
    property color accentColor: "#121216"
    
    signal imageReady()
    signal paintedSizeChanged()
    
    
    function adjustZoom(delta) {
        if (source === "")
            return;
        const factor = Math.pow(1.0015, delta);
        zoomFactor = Math.max(0.1, Math.min(zoomFactor * factor, 10.0));
        clampPan();
    }
    
    function resetView() {
        zoomFactor = 1.0
        panX = 0
        panY = 0
        rotation = 0
    }
    
    function fitToWindow() {
        // When rotated 90 or 270 degrees, we need to adjust zoom to account for aspect ratio swap
        if (rotation === 90 || rotation === 270) {
            // Calculate the zoom needed to fit the rotated image
            const imgW = paintedWidth
            const imgH = paintedHeight
            const containerW = mediaContainer.width
            const containerH = mediaContainer.height
            
            if (imgW > 0 && imgH > 0 && containerW > 0 && containerH > 0) {
                // After 90/270 rotation, width becomes height and vice versa
                // We need to scale so the rotated image fits
                const rotatedFitW = containerW / imgH  // rotated width (original height) fits container width
                const rotatedFitH = containerH / imgW  // rotated height (original width) fits container height
                const scaleFactor = Math.min(rotatedFitW, rotatedFitH)
                
                // The base zoom (1.0) already fits the unrotated image, so we adjust
                const baseFitW = containerW / imgW
                const baseFitH = containerH / imgH
                const baseScale = Math.min(baseFitW, baseFitH)
                
                zoomFactor = scaleFactor / baseScale
            } else {
                zoomFactor = 1.0
            }
        } else {
            zoomFactor = 1.0
        }
        panX = 0
        panY = 0
        clampPan()
    }
    
    function actualSize() {
        // Calculate zoom needed to show image at 100% (1 image pixel = 1 screen pixel)
        if (source === "" || paintedWidth === 0 || sourceWidth === 0)
            return
        
        // At zoomFactor 1.0, paintedWidth is the fitted size
        // We want sourceWidth to equal the displayed size
        const actualZoom = sourceWidth / paintedWidth
        zoomFactor = Math.max(0.1, Math.min(actualZoom, 10.0))
        panX = 0
        panY = 0
        clampPan()
    }
    
    function rotateLeft() {
        rotation = (rotation - 90 + 360) % 360
        fitToWindow()
    }
    
    function rotateRight() {
        rotation = (rotation + 90) % 360
        fitToWindow()
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
            },
            Rotation {
                origin.x: mediaContainer.width / 2
                origin.y: mediaContainer.height / 2
                angle: imageViewer.rotation
            }
        ]
        
        Image {
            id: photo
            anchors.fill: parent
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            cache: true  // Enable caching for faster re-loads
            smooth: true
            mipmap: true  // Enable mipmapping for better scaled image quality
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
            cache: true  // Enable caching for faster re-loads
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
    property int sourceWidth: isGif ? animatedGif.sourceSize.width : photo.sourceSize.width
    property int sourceHeight: isGif ? animatedGif.sourceSize.height : photo.sourceSize.height
    property int frameCount: isGif ? animatedGif.frameCount : 0
    property int currentFrame: isGif ? animatedGif.currentFrame : 0
    property int status: isGif ? animatedGif.status : photo.status
}

