import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: settingsPage
    
    property color accentColor: "#121216"
    property color foregroundColor: "#f5f5f5"
    property bool dynamicColoringEnabled: true
    property bool betaAudioProcessingEnabled: true
    
    signal backClicked()
    signal dynamicColoringToggled(bool enabled)
    signal betaAudioProcessingToggled(bool enabled)
    
    color: Qt.darker(accentColor, 1.2)

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 32
        spacing: 18

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            Button {
                text: qsTr("Back to viewer")
                Layout.preferredWidth: 150
                onClicked: backClicked()
            }

            Label {
                Layout.fillWidth: true
                text: qsTr("Settings")
                font.pixelSize: 20
                font.bold: true
                color: foregroundColor
                horizontalAlignment: Text.AlignRight
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: Qt.darker(accentColor, 1.4)
            opacity: 0.6
        }

        CheckBox {
            text: qsTr("Enable dynamic coloring")
            checked: dynamicColoringEnabled
            onToggled: dynamicColoringToggled(checked)
            palette.text: foregroundColor
        }

        Text {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: qsTr("When enabled, the viewer adapts the interface colors to the dominant tones of the current media.")
            color: Qt.lighter(foregroundColor, 1.3)
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            Layout.topMargin: 12
            Layout.bottomMargin: 12
            color: Qt.darker(accentColor, 1.4)
            opacity: 0.6
        }

        Text {
            Layout.fillWidth: true
            text: qsTr("Beta Features")
            font.pixelSize: 16
            font.bold: true
            color: foregroundColor
        }

        CheckBox {
            text: qsTr("Enable beta audio processing (Real EQ)")
            checked: betaAudioProcessingEnabled
            onToggled: betaAudioProcessingToggled(checked)
            palette.text: foregroundColor
        }

        Text {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: qsTr("⚠️ BETA: Enables real-time audio equalizer processing. This feature is experimental and may impact performance. Requires restart to take effect.")
            color: Qt.lighter(foregroundColor, 1.3)
            font.pixelSize: 11
        }

        Item { Layout.fillHeight: true }
    }
}

