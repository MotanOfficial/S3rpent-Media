import QtQuick

/**
 * ToastNotification.qml
 * Reusable toast notification component
 */
Rectangle {
    id: root
    
    anchors.bottom: parent.bottom
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottomMargin: 32
    width: toastText.width + 32
    height: 40
    radius: 20
    color: toastError ? Qt.rgba(200, 50, 50, 0.9) : Qt.rgba(50, 150, 50, 0.9)
    opacity: 0
    visible: opacity > 0
    z: 100
    
    property bool toastError: false
    
    function show(message, isError) {
        toastText.text = message
        toastError = isError
        toastAnimation.restart()
    }
    
    Text {
        id: toastText
        anchors.centerIn: parent
        color: "#ffffff"
        font.pixelSize: 14
        font.family: "Segoe UI"
    }
    
    SequentialAnimation {
        id: toastAnimation
        NumberAnimation { target: root; property: "opacity"; to: 1; duration: 200 }
        PauseAnimation { duration: 2000 }
        NumberAnimation { target: root; property: "opacity"; to: 0; duration: 300 }
    }
}

