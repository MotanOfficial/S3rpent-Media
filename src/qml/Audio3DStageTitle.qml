import QtQuick
import Qt5Compat.GraphicalEffects

// Floating perspective title + artist with sparkle particles (Mineradio-style stage text).
Item {
    id: root

    property string songTitle: ""
    property string songArtist: ""
    property color tintColor: "#f5f5f5"
    property bool active: true
    property real bass: 0
    property real mid: 0
    property real treble: 0
    property real beat: 0
    property real energy: 0
    property real stageTime: 0

    visible: active && songTitle !== ""
    opacity: active ? 1.0 : 0.0

    Behavior on opacity {
        NumberAnimation { duration: 500; easing.type: Easing.OutCubic }
    }

    readonly property real _titleSize: Math.max(26, Math.min(58, width * 0.052))
    readonly property real _artistSize: Math.max(14, Math.min(26, width * 0.026))
    readonly property real _floatY: Math.sin(stageTime * 0.62) * (6 + bass * 10)
    readonly property real _tiltX: -16 - bass * 5 - beat * 2
    readonly property real _scalePulse: 1.0 + beat * 0.05 + energy * 0.02

    Item {
        id: titleStage
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: -parent.height * 0.04 + root._floatY
        width: titleBlock.width
        height: titleBlock.height + 36

        transform: [
            Scale {
                origin.x: titleStage.width * 0.5
                origin.y: titleStage.height
                xScale: root._scalePulse
                yScale: root._scalePulse
            },
            Rotation {
                origin.x: titleStage.width * 0.5
                origin.y: titleStage.height
                axis.x: 1
                angle: root._tiltX
            }
        ]

        // Soft bloom behind the text block
        Rectangle {
            anchors.centerIn: titleBlock
            width: titleBlock.width * 1.2
            height: titleBlock.height * 1.4
            radius: Math.min(width, height) * 0.5
            color: Qt.rgba(tintColor.r, tintColor.g, tintColor.b, 0.04 + beat * 0.06)
            visible: beat > 0.05
            layer.enabled: true
            layer.effect: GaussianBlur {
                radius: 28 + beat * 18
                samples: 16
            }
        }

        // Sparkle particles around the title (subtle — main field is in the shader)
        Repeater {
            model: 28
            delegate: Item {
                readonly property real seed: index * 0.61803398875
                readonly property real orbit: 0.42 + (index % 7) * 0.08
                readonly property real angle: seed * 19.3 + stageTime * (0.28 + (index % 5) * 0.04)
                readonly property real rx: titleBlock.width * (0.52 + bass * 0.12) + (index % 4) * 6
                readonly property real ry: titleBlock.height * (0.38 + mid * 0.10) + (index % 3) * 5

                x: titleStage.width * 0.5 + Math.cos(angle) * rx * orbit - width * 0.5
                y: titleStage.height * 0.48 + Math.sin(angle) * ry * orbit - height * 0.5

                width: 2 + beat * 3.5 + (index % 9 === 0 ? treble * 2 : 0)
                height: width

                Rectangle {
                    anchors.fill: parent
                    radius: width * 0.5
                    color: Qt.lighter(tintColor, 1.15 + beat * 0.2)
                    opacity: 0.06 + beat * 0.28 + (index % 6 === 0 ? energy * 0.15 : 0)
                }
            }
        }

        Column {
            id: titleBlock
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Math.max(6, root._titleSize * 0.18)
            width: Math.min(root.width * 0.82, titleLabel.implicitWidth)

            Text {
                id: titleLabel
                width: parent.width
                text: songTitle
                color: tintColor
                font.pixelSize: root._titleSize
                font.bold: true
                font.letterSpacing: 1.4
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
                layer.enabled: true
                layer.effect: Glow {
                    radius: 10 + beat * 14
                    samples: 20
                    color: Qt.rgba(tintColor.r, tintColor.g, tintColor.b, 0.45 + beat * 0.25)
                }
            }

            Text {
                width: parent.width
                text: songArtist
                color: Qt.rgba(tintColor.r, tintColor.g, tintColor.b, 0.72 + mid * 0.12)
                font.pixelSize: root._artistSize
                font.letterSpacing: 0.8
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                maximumLineCount: 1
                elide: Text.ElideRight
                layer.enabled: true
                layer.effect: Glow {
                    radius: 6 + beat * 8
                    samples: 14
                    color: Qt.rgba(tintColor.r, tintColor.g, tintColor.b, 0.22)
                }
            }
        }
    }
}
