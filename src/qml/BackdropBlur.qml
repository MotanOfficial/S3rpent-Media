import QtQuick
import Qt5Compat.GraphicalEffects

// Blurred cover-art backdrop effect (like Apple Music, YouTube Music)
Item {
    id: backdropBlur
    
    property url imageSource: ""  // Cover art or image to blur
    property bool enabled: true
    property real blurRadius: 80  // Blur radius in pixels (increased for more blur)
    property real scaleFactor: 1.5  // Scale up factor (increased to cover more area)
    property real darkOverlay: 0.25  // Dark overlay opacity (reduced for less darkness)
    property real saturation: 0.8  // Saturation reduction (0.7-0.9 typical)
    
    property url _currentDisplayedSource: ""  // Track currently displayed image
    
    anchors.fill: parent
    visible: enabled && imageSource !== ""
    opacity: enabled && imageSource !== "" ? 1.0 : 0.0
    // No z value needed - window background property automatically puts it behind content
    
    // Smooth fade in/out when enabled/disabled or image changes
    Behavior on opacity {
        NumberAnimation {
            duration: 400
            easing.type: Easing.OutCubic
        }
    }
    
    // Track image source changes for cross-fade
    onImageSourceChanged: {
        if (imageSource !== "" && imageSource !== _currentDisplayedSource) {
            // Save currently displayed source to old image before switching
            // Only if we have a valid displayed source (not first load)
            if (_currentDisplayedSource !== "" && sourceImage.status === Image.Ready) {
                // Capture the current source before it changes
                var oldSource = sourceImage.source
                if (oldSource !== "" && oldSource !== imageSource) {
                    oldImage.source = oldSource
                    oldImage.opacity = 1.0
                }
            }
            // New image starts invisible until ready
            sourceImage.opacity = 0.0
        }
    }
    
    // Old image - stays visible while new one loads (for cross-fade)
    Image {
        id: oldImage
        width: parent.width * scaleFactor
        height: parent.height * scaleFactor
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        smooth: true
        visible: false  // Hidden, only used as source for blur
        opacity: 0.0
        
        Behavior on opacity {
            NumberAnimation {
                duration: 400
                easing.type: Easing.OutCubic
            }
        }
    }
    
    // New image - fades in when ready
    Image {
        id: sourceImage
        width: parent.width * scaleFactor
        height: parent.height * scaleFactor
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        source: backdropBlur.imageSource
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        smooth: true
        visible: false  // Hidden, only used as source for blur
        opacity: 0.0
        
        Behavior on opacity {
            NumberAnimation {
                duration: 400
                easing.type: Easing.OutCubic
            }
        }
        
        onStatusChanged: {
            if (status === Image.Ready && source !== "") {
                // New image ready - fade out old and fade in new
                if (oldImage.opacity > 0) {
                    oldImage.opacity = 0.0
                }
                opacity = 1.0
                // Update displayed source now that new image is ready
                backdropBlur._currentDisplayedSource = source
            } else if (status === Image.Loading && backdropBlur._currentDisplayedSource === "") {
                // First image loading - make sure we don't show black
                // Keep opacity at 0 until ready
                opacity = 0.0
            }
        }
        
        // Initialize on first load
        Component.onCompleted: {
            if (status === Image.Ready && source !== "") {
                opacity = 1.0
                backdropBlur._currentDisplayedSource = source
            }
        }
    }
    
    // Layer both images together for cross-fade effect
    Item {
        id: imageLayer
        anchors.fill: parent
        visible: false  // Hidden, only used as source for blur
        
        // Old image layer
        Image {
            id: oldImageLayer
            anchors.fill: parent
            source: oldImage.source
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            smooth: true
            opacity: oldImage.opacity
        }
        
        // New image layer
        Image {
            id: newImageLayer
            anchors.fill: parent
            source: sourceImage.source
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            smooth: true
            opacity: sourceImage.opacity
        }
    }
    
    // Apply Gaussian blur to the combined image layer
    FastBlur {
        id: blurEffect
        anchors.fill: parent
        source: imageLayer
        radius: backdropBlur.blurRadius
        transparentBorder: false
        
        // Smooth transition when blur radius changes
        Behavior on radius {
            NumberAnimation {
                duration: 300
                easing.type: Easing.OutCubic
            }
        }
    }
    
    // Dark overlay for better contrast
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, darkOverlay)
        z: 1  // Relative to backdropBlur parent
        border.width: 0
        border.color: "transparent"
        
        // Smooth transition when dark overlay opacity changes
        Behavior on color {
            ColorAnimation {
                duration: 300
                easing.type: Easing.OutCubic
            }
        }
    }
    
    // Optional: Subtle vertical gradient darkening (like Apple Music) - reduced opacity
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.0) }
            GradientStop { position: 0.5; color: Qt.rgba(0, 0, 0, 0.03) }
            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.08) }
        }
        z: 2  // Relative to backdropBlur parent
        border.width: 0
        border.color: "transparent"
    }
}

