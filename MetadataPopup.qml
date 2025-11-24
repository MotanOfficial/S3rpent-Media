import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Popup {
    id: metadataPopup
    
    property var metadataList: []
    property color accentColor: "#121216"
    property color foregroundColor: "#f5f5f5"
    
    width: 400
    height: Math.min(500, parent.height - 20)
    modal: false
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    
    background: Rectangle {
        color: Qt.darker(accentColor, 1.2)
        border.color: Qt.darker(accentColor, 1.4)
        border.width: 1
        radius: 8
    }
    
    ScrollView {
        anchors.fill: parent
        anchors.margins: 12
        clip: true
        
        ColumnLayout {
            width: metadataPopup.width - 24
            spacing: 12
            
            RowLayout {
                Layout.fillWidth: true
                
                Text {
                    Layout.fillWidth: true
                    text: "File Metadata"
                    color: foregroundColor
                    font.pixelSize: 18
                    font.bold: true
                }
            }
            
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: Qt.darker(accentColor, 1.4)
                opacity: 0.6
            }
            
            Repeater {
                id: metadataRepeater
                model: metadataList
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    
                    Text {
                        Layout.fillWidth: true
                        text: modelData.label
                        color: Qt.lighter(foregroundColor, 1.3)
                        font.pixelSize: 11
                        font.bold: true
                    }
                    
                    Text {
                        Layout.fillWidth: true
                        text: modelData.value
                        color: foregroundColor
                        font.pixelSize: 13
                        wrapMode: Text.WordWrap
                    }
                }
            }
        }
    }
}

