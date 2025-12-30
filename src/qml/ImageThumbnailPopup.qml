import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects

/**
 * ImageThumbnailPopup.qml
 * Scrollable thumbnail popup showing current image and surrounding thumbnails
 */
Rectangle {
    id: thumbnailPopup
    
    property int currentIndex: 0
    property var directoryImages: []
    property color accentColor: "#ffffff"
    property var imageControlsHideTimer: null  // Reference to the hide timer
    
    signal thumbnailClicked(int index)
    
    width: 500
    height: 140
    radius: 12
    color: Qt.rgba(0, 0, 0, 0.95)
    border.color: Qt.rgba(255, 255, 255, 0.2)
    border.width: 1
    
    property bool shouldBeVisible: false
    
    opacity: shouldBeVisible ? 1 : 0
    visible: opacity > 0  // Keep visible during fade-out animation
    
    Behavior on opacity { 
        NumberAnimation { 
            duration: 300
            easing.type: Easing.OutCubic 
        } 
    }
    
    // Drop shadow
    DropShadow {
        anchors.fill: thumbnailPopup
        source: thumbnailPopup
        radius: 20
        samples: 41
        color: Qt.rgba(0, 0, 0, 0.5)
        verticalOffset: 4
        horizontalOffset: 0
    }
    
    // Property to expose hover state for timer control
    property bool isHovered: false
    
    // MouseArea to capture wheel events and prevent propagation
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        hoverEnabled: true
        propagateComposedEvents: false
        
        onEntered: {
            thumbnailPopup.isHovered = true
            // Stop the hide timer when mouse enters popup
            if (thumbnailPopup.imageControlsHideTimer) {
                thumbnailPopup.imageControlsHideTimer.stop()
            }
        }
        
        onExited: {
            thumbnailPopup.isHovered = false
            // Restart the hide timer when mouse leaves popup
            if (thumbnailPopup.imageControlsHideTimer) {
                thumbnailPopup.imageControlsHideTimer.restart()
            }
        }
        
        onPressed: function(mouse) {
            mouse.accepted = true  // Stop propagation to overlay
        }
        onReleased: function(mouse) {
            mouse.accepted = true  // Stop propagation to overlay
        }
        onClicked: function(mouse) {
            mouse.accepted = true  // Stop propagation to overlay
        }
        
        onWheel: function(wheel) {
            // Handle horizontal scrolling in the thumbnail list
            var delta = 0
            if (wheel.angleDelta.x !== 0) {
                delta = wheel.angleDelta.x
            } else if (wheel.angleDelta.y !== 0) {
                // Convert vertical scroll to horizontal
                delta = -wheel.angleDelta.y
            }
            
            if (delta !== 0) {
                // Wait for contentWidth to be calculated
                Qt.callLater(function() {
                    // Calculate max scroll position
                    var maxScroll = Math.max(0, thumbnailList.contentWidth - thumbnailList.width)
                    
                    // Only scroll if there's content to scroll
                    if (maxScroll > 0) {
                        // Scroll by adjusting contentX
                        var scrollAmount = delta * 0.5  // Adjust scroll speed
                        var newX = thumbnailList.contentX + scrollAmount
                        
                        // Clamp to valid range (no overscroll to prevent bugs)
                        thumbnailList.contentX = Math.max(0, Math.min(maxScroll, newX))
                    }
                })
            }
            
            wheel.accepted = true  // CRITICAL: Prevent propagation to main image
        }
        
        // Scrollable list of thumbnails
        ListView {
            id: thumbnailList
            anchors.fill: parent
            anchors.margins: 12
            orientation: ListView.Horizontal
            spacing: 8
            snapMode: ListView.NoSnap  // Remove snap to allow smooth scrolling
            clip: true
            interactive: true  // Enable user interaction
            flickableDirection: Flickable.HorizontalFlick
            
            // Ensure contentWidth is properly calculated
            contentWidth: {
                var totalWidth = 0
                for (var i = 0; i < directoryImages.length; i++) {
                    totalWidth += (i === thumbnailPopup.currentIndex ? 120 : 80) + (i > 0 ? 8 : 0)  // width + spacing
                }
                return totalWidth
            }
            
            model: directoryImages.length
            
            // Center on current index when popup opens
            onCurrentIndexChanged: {
                if (visible && currentIndex >= 0 && currentIndex < directoryImages.length) {
                    Qt.callLater(function() {
                        thumbnailList.positionViewAtIndex(currentIndex, ListView.Center)
                    })
                }
            }
            
            Component.onCompleted: {
                if (currentIndex >= 0 && currentIndex < directoryImages.length) {
                    Qt.callLater(function() {
                        thumbnailList.positionViewAtIndex(currentIndex, ListView.Center)
                    })
                }
            }
            
            delegate: Item {
            width: (index === thumbnailPopup.currentIndex) ? 120 : 80
            height: thumbnailList.height
            
            property bool isCurrent: index === thumbnailPopup.currentIndex
            
            Rectangle {
                anchors.fill: parent
                anchors.margins: isCurrent ? 0 : 2
                radius: isCurrent ? 8 : 6
                color: isCurrent 
                       ? Qt.rgba(1, 1, 1, 0.15)
                       : Qt.rgba(1, 1, 1, 0.1)
                border.color: isCurrent
                              ? Qt.rgba(accentColor.r, accentColor.g, accentColor.b, 0.5)
                              : Qt.rgba(255, 255, 255, 0.15)
                border.width: isCurrent ? 2 : 1
                
                Behavior on width {
                    NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                }
                
                Image {
                    id: thumbnailImage
                    anchors.fill: parent
                    anchors.margins: isCurrent ? 4 : 3
                    source: index >= 0 && index < directoryImages.length 
                            ? directoryImages[index] : ""
                    sourceSize.width: isCurrent ? 240 : 160
                    sourceSize.height: isCurrent ? 240 : 160
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    cache: false
                    visible: status === Image.Ready
                    
                    // Loading indicator
                    Rectangle {
                        anchors.fill: parent
                        color: Qt.rgba(0, 0, 0, 0.3)
                        visible: thumbnailImage.status === Image.Loading
                        
                        Text {
                            anchors.centerIn: parent
                            text: "..."
                            color: "#ffffff"
                            font.pixelSize: isCurrent ? 10 : 8
                            opacity: 0.6
                        }
                    }
                    
                    // Error indicator
                    Text {
                        anchors.centerIn: parent
                        text: "✕"
                        color: "#ff4444"
                        font.pixelSize: isCurrent ? 24 : 16
                        visible: thumbnailImage.status === Image.Error
                    }
                }
                
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (index >= 0 && index < directoryImages.length) {
                            thumbnailPopup.thumbnailClicked(index)
                        }
                    }
                    
                    // Hover effect
                    Rectangle {
                        anchors.fill: parent
                        color: Qt.rgba(accentColor.r, accentColor.g, accentColor.b, 0.2)
                        opacity: parent.containsMouse ? 1 : 0
                        radius: parent.parent.radius
                        Behavior on opacity { NumberAnimation { duration: 150 } }
                    }
                }
            }
            }
        }
    }
    
    // Scroll indicators (fade in/out at edges)
    Rectangle {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: 20
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.8) }
            GradientStop { position: 1.0; color: "transparent" }
        }
        visible: thumbnailList.contentX > 0
        opacity: visible ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 200 } }
    }
    
    Rectangle {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: 20
        gradient: Gradient {
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.8) }
        }
        visible: thumbnailList.contentX < (thumbnailList.contentWidth - thumbnailList.width)
        opacity: visible ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 200 } }
    }
    
    // Function to show the popup
    function show() {
        shouldBeVisible = true
        Qt.callLater(function() {
            if (currentIndex >= 0 && currentIndex < directoryImages.length) {
                thumbnailList.positionViewAtIndex(currentIndex, ListView.Center)
            }
        })
    }
    
    // Function to hide the popup
    function hide() {
        shouldBeVisible = false
    }
}
