import QtQuick
import QtQuick.Controls

/**
 * ImageNavigationArrows.qml
 * Image navigation arrows and preloaders component
 */
Item {
    id: navigationArrows
    
    // Properties to bind to (passed from parent)
    property var appWindow: null
    property var imageControlsHideTimer: null
    
    // Pre-load next image for faster navigation
    Image {
        id: preloadNext
        visible: false
        asynchronous: true
        cache: true
        source: {
            if (!navigationArrows.appWindow || !navigationArrows.appWindow.isImageType || navigationArrows.appWindow.directoryImages.length <= 1) return ""
            const nextIndex = (navigationArrows.appWindow.currentImageIndex + 1) % navigationArrows.appWindow.directoryImages.length
            return navigationArrows.appWindow.directoryImages[nextIndex] || ""
        }
    }
    
    // Pre-load previous image for faster navigation
    Image {
        id: preloadPrev
        visible: false
        asynchronous: true
        cache: true
        source: {
            if (!navigationArrows.appWindow || !navigationArrows.appWindow.isImageType || navigationArrows.appWindow.directoryImages.length <= 1) return ""
            const prevIndex = (navigationArrows.appWindow.currentImageIndex - 1 + navigationArrows.appWindow.directoryImages.length) % navigationArrows.appWindow.directoryImages.length
            return navigationArrows.appWindow.directoryImages[prevIndex] || ""
        }
    }
    
    // Left navigation arrow
    Rectangle {
        id: leftArrow
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: 12
        width: 32
        height: 48
        radius: 8
        color: leftArrowMouse.containsMouse 
               ? Qt.rgba(0, 0, 0, 0.7) 
               : Qt.rgba(0, 0, 0, 0.4)
        visible: navigationArrows.appWindow ? (navigationArrows.appWindow.isImageType && navigationArrows.appWindow.showImageControls && navigationArrows.appWindow.currentImage.toString() !== "" && navigationArrows.appWindow.directoryImages.length > 1 && !navigationArrows.appWindow.showingSettings && !navigationArrows.appWindow.showingMetadata) : false
        opacity: leftArrowMouse.containsMouse ? 1 : 0.5
        z: 50
        
        Behavior on color { ColorAnimation { duration: 150 } }
        Behavior on opacity { NumberAnimation { duration: 150 } }
        
        Text {
            anchors.centerIn: parent
            text: "‹"
            color: "#ffffff"
            font.pixelSize: 24
            font.bold: true
        }
        
        MouseArea {
            id: leftArrowMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (navigationArrows.appWindow) {
                    navigationArrows.appWindow.previousImage()
                    if (navigationArrows.imageControlsHideTimer) {
                        navigationArrows.imageControlsHideTimer.restart()
                    }
                }
            }
        }
    }
    
    // Right navigation arrow
    Rectangle {
        id: rightArrow
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.rightMargin: 12
        width: 32
        height: 48
        radius: 8
        color: rightArrowMouse.containsMouse 
               ? Qt.rgba(0, 0, 0, 0.7) 
               : Qt.rgba(0, 0, 0, 0.4)
        visible: navigationArrows.appWindow ? (navigationArrows.appWindow.isImageType && navigationArrows.appWindow.showImageControls && navigationArrows.appWindow.currentImage.toString() !== "" && navigationArrows.appWindow.directoryImages.length > 1 && !navigationArrows.appWindow.showingSettings && !navigationArrows.appWindow.showingMetadata) : false
        opacity: rightArrowMouse.containsMouse ? 1 : 0.5
        z: 50
        
        Behavior on color { ColorAnimation { duration: 150 } }
        Behavior on opacity { NumberAnimation { duration: 150 } }
        
        Text {
            anchors.centerIn: parent
            text: "›"
            color: "#ffffff"
            font.pixelSize: 24
            font.bold: true
        }
        
        MouseArea {
            id: rightArrowMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (navigationArrows.appWindow) {
                    navigationArrows.appWindow.nextImage()
                    if (navigationArrows.imageControlsHideTimer) {
                        navigationArrows.imageControlsHideTimer.restart()
                    }
                }
            }
        }
    }
}

