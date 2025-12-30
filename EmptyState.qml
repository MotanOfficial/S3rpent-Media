import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects

/**
 * EmptyState.qml
 * Modern empty state placeholder shown when no media is loaded
 */
Column {
    id: root
    
    anchors.centerIn: parent
    spacing: 32
    
    property bool showingSettings: false
    signal openFileRequested()
    
    // Access to appWindow for colors
    property var appWindow: null
    
    opacity: visible ? 1 : 0
    scale: visible ? 1 : 0.95
    z: 1  // Ensure it's above other content
    
    // Entrance animation
    Behavior on opacity { 
        NumberAnimation { 
            duration: 400
            easing.type: Easing.OutCubic 
        } 
    }
    Behavior on scale { 
        NumberAnimation { 
            duration: 400
            easing.type: Easing.OutCubic 
        } 
    }
    
    // Icon container with modern design
    Item {
        id: iconContainer
        width: 140
        height: 140
        anchors.horizontalCenter: parent.horizontalCenter
        
        // Animated glow effect
        Rectangle {
            id: glowCircle
            anchors.centerIn: parent
            width: parent.width
            height: parent.height
            radius: width / 2
            color: "transparent"
            border.width: 2
            border.color: Qt.rgba(1, 1, 1, 0.15)
            opacity: 0.6
            
            SequentialAnimation on opacity {
                running: root.visible
                loops: Animation.Infinite
                NumberAnimation {
                    to: 0.3
                    duration: 2000
                    easing.type: Easing.InOutSine
                }
                NumberAnimation {
                    to: 0.6
                    duration: 2000
                    easing.type: Easing.InOutSine
                }
            }
        }
        
        // Main icon background
        Rectangle {
            id: iconBackground
            anchors.centerIn: parent
            width: 120
            height: 120
            radius: 60
            color: Qt.rgba(1, 1, 1, 0.08)
            border.width: 1.5
            border.color: Qt.rgba(1, 1, 1, 0.12)
            
            // Drop shadow
            DropShadow {
                anchors.fill: iconBackground
                source: iconBackground
                radius: 20
                samples: 41
                color: Qt.rgba(0, 0, 0, 0.3)
                verticalOffset: 4
                horizontalOffset: 0
            }
            
            // Icon
            Image {
                id: folderIcon
                anchors.centerIn: parent
                source: "qrc:/qlementine/icons/32/file/folder-open.svg"
                sourceSize: Qt.size(64, 64)
                opacity: 0.85
                
                ColorOverlay {
                    anchors.fill: folderIcon
                    source: folderIcon
                    color: Qt.rgba(1, 1, 1, 0.9)
                }
            }
        }
        
        // Scale animation on hover
        HoverHandler {
            id: iconHover
            cursorShape: Qt.PointingHandCursor
            onHoveredChanged: {
                if (hovered) {
                    iconScaleAnimation.to = 1.1
                } else {
                    iconScaleAnimation.to = 1.0
                }
            }
        }
        
        property real iconScale: 1.0
        transform: Scale { 
            xScale: iconContainer.iconScale
            yScale: iconContainer.iconScale
        }
        
        NumberAnimation {
            id: iconScaleAnimation
            target: iconContainer
            property: "iconScale"
            duration: 200
            easing.type: Easing.OutCubic
        }
    }
    
    // Text content
    Column {
        id: textContent
        spacing: 12
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(400, parent.parent.width - 80)
        
        // Main title
        Text {
            text: qsTr("No media loaded")
            font.pixelSize: 32
            font.weight: Font.Bold
            font.family: "Segoe UI"
            color: Qt.rgba(1, 1, 1, 0.95)
            anchors.horizontalCenter: parent.horizontalCenter
            horizontalAlignment: Text.AlignHCenter
        }
        
        // Subtitle
        Text {
            text: qsTr("Drag & drop a file here or click the button below to browse")
            font.pixelSize: 15
            font.family: "Segoe UI"
            color: Qt.rgba(1, 1, 1, 0.6)
            anchors.horizontalCenter: parent.horizontalCenter
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            width: parent.width
        }
    }
    
    // Or divider
    Row {
        id: dividerRow
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 16
        opacity: 0.4
        
        Rectangle {
            width: 50
            height: 1
            color: Qt.rgba(1, 1, 1, 0.25)
            anchors.verticalCenter: parent.verticalCenter
        }
        
        Text {
            text: qsTr("or")
            font.pixelSize: 13
            font.family: "Segoe UI"
            color: Qt.rgba(1, 1, 1, 0.5)
            anchors.verticalCenter: parent.verticalCenter
        }
        
        Rectangle {
            width: 50
            height: 1
            color: Qt.rgba(1, 1, 1, 0.25)
            anchors.verticalCenter: parent.verticalCenter
        }
    }
    
    // Modern open file button
    Rectangle {
        id: openFileButton
        width: 200
        height: 48
        radius: 24
        anchors.horizontalCenter: parent.horizontalCenter
        
        property bool isHovered: false
        property bool isPressed: false
        
        color: isPressed 
               ? Qt.rgba(1, 1, 1, 0.2)
               : (isHovered 
                  ? Qt.rgba(1, 1, 1, 0.15)
                  : Qt.rgba(1, 1, 1, 0.1))
        border.width: 1.5
        border.color: isHovered 
                      ? Qt.rgba(1, 1, 1, 0.3)
                      : Qt.rgba(1, 1, 1, 0.2)
        
        // Drop shadow
        DropShadow {
            anchors.fill: openFileButton
            source: openFileButton
            radius: openFileButton.isHovered ? 16 : 8
            samples: openFileButton.isHovered ? 33 : 17
            color: Qt.rgba(0, 0, 0, openFileButton.isHovered ? 0.4 : 0.25)
            verticalOffset: openFileButton.isHovered ? 6 : 3
            horizontalOffset: 0
        }
        
        // Smooth transitions
        Behavior on color { 
            ColorAnimation { 
                duration: 200
                easing.type: Easing.OutCubic 
            } 
        }
        Behavior on border.color { 
            ColorAnimation { 
                duration: 200
                easing.type: Easing.OutCubic 
            } 
        }
        Behavior on scale { 
            NumberAnimation { 
                duration: 200
                easing.type: Easing.OutCubic 
            } 
        }
        
        property real buttonScale: 1.0
        transform: Scale { 
            xScale: openFileButton.buttonScale
            yScale: openFileButton.buttonScale
        }
        
        // Button content
        Row {
            anchors.centerIn: parent
            spacing: 10
            
            Image {
                id: browseIcon
                anchors.verticalCenter: parent.verticalCenter
                source: "qrc:/qlementine/icons/16/file/folder-open.svg"
                sourceSize: Qt.size(20, 20)
                
                ColorOverlay {
                    anchors.fill: browseIcon
                    source: browseIcon
                    color: Qt.rgba(1, 1, 1, 0.95)
                }
            }
            
            Text {
                text: qsTr("Browse files")
                font.pixelSize: 15
                font.family: "Segoe UI"
                font.weight: Font.Medium
                color: Qt.rgba(1, 1, 1, 0.95)
                anchors.verticalCenter: parent.verticalCenter
            }
        }
        
        // Interaction handlers
        TapHandler {
            id: openFileTap
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            acceptedButtons: Qt.LeftButton
            gesturePolicy: TapHandler.ReleaseWithinBounds
            
            onTapped: root.openFileRequested()
            
            onPressedChanged: {
                openFileButton.isPressed = pressed
                if (pressed) {
                    buttonScaleAnimation.to = 0.95
                } else {
                    buttonScaleAnimation.to = openFileButton.isHovered ? 1.05 : 1.0
                }
            }
        }
        
        HoverHandler {
            id: openFileHover
            cursorShape: Qt.PointingHandCursor
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            
            onHoveredChanged: {
                openFileButton.isHovered = hovered
                if (!openFileButton.isPressed) {
                    buttonScaleAnimation.to = hovered ? 1.05 : 1.0
                }
            }
        }
        
        NumberAnimation {
            id: buttonScaleAnimation
            target: openFileButton
            property: "buttonScale"
            duration: 200
            easing.type: Easing.OutCubic
        }
    }
    
    // Supported formats hint
    Text {
        text: qsTr("Images • Videos • Audio • Documents")
        font.pixelSize: 12
        font.family: "Segoe UI"
        color: Qt.rgba(1, 1, 1, 0.35)
        anchors.horizontalCenter: parent.horizontalCenter
        topPadding: 16
    }
}
