import QtQuick

Item {
    id: windowBackground
    
    property color accentColor: "#121216"
    property bool dynamicColoringEnabled: true
    
    anchors.fill: parent

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(15 / 255, 17 / 255, 26 / 255, 0.98)
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.45)
    }

    Rectangle {
        anchors.fill: parent
        border.width: 0
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.0) }
            GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.0) }
            GradientStop {
                position: 1.0
                color: dynamicColoringEnabled
                       ? Qt.rgba(accentColor.r, accentColor.g, accentColor.b, 0.16)
                       : Qt.rgba(0.75, 0.8, 0.95, 0.18)
            }
        }
        rotation: 180
    }

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.0) }
            GradientStop { position: 0.8; color: Qt.rgba(1, 1, 1, 0.0) }
            GradientStop {
                position: 1.0
                color: dynamicColoringEnabled
                       ? Qt.rgba(Qt.lighter(accentColor, 1.5).r,
                                 Qt.lighter(accentColor, 1.5).g,
                                 Qt.lighter(accentColor, 1.5).b,
                                 0.22)
                       : Qt.rgba(0.9, 0.95, 1.0, 0.2)
            }
        }
        rotation: 45
        opacity: 0.6
    }

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.0) }
            GradientStop { position: 0.7; color: Qt.rgba(1, 1, 1, 0.0) }
            GradientStop {
                position: 1.0
                color: dynamicColoringEnabled
                       ? Qt.rgba(Qt.darker(accentColor, 1.35).r,
                                 Qt.darker(accentColor, 1.35).g,
                                 Qt.darker(accentColor, 1.35).b,
                                 0.18)
                       : Qt.rgba(0.75, 0.8, 0.9, 0.18)
            }
        }
        rotation: -35
        opacity: 0.4
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(255, 255, 255, dynamicColoringEnabled ? 0.03 : 0.04)
    }
}

