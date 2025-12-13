import QtQuick

// Pure shader-based snow effect (Spotify/Apple Music style)
Item {
    id: snowEffect
    
    property bool enabled: true
    property real effectOpacity: 0.9
    property color snowColor: "white"
    
    anchors.fill: parent
    visible: enabled
    
    // Use property binding for opacity
    opacity: enabled ? effectOpacity : 0.0
    
    // Smooth fade in/out
    Behavior on opacity {
        NumberAnimation {
            duration: 600
            easing.type: Easing.OutCubic
        }
    }
    
    // Time property for animation
    property real time: 0.0
    
    ShaderEffect {
        anchors.fill: parent
        
        property real u_time: snowEffect.time
        property real u_intensity: snowEffect.effectOpacity
        property vector2d u_resolution: Qt.vector2d(width, height)
        property color u_color: snowEffect.snowColor
        
        fragmentShader: Qt.resolvedUrl("qrc:/snow.frag.qsb")
    }
    
    // Drive time (cheap, stable, infinite loop)
    NumberAnimation on time {
        from: 0
        to: 100000
        duration: 100000000
        loops: Animation.Infinite
        running: snowEffect.enabled && snowEffect.opacity > 0
    }
}
