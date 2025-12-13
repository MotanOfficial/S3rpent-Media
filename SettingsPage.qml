import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects

Rectangle {
    id: settingsPage
    
    property color accentColor: "#121216"
    property color foregroundColor: "#f5f5f5"
    property bool dynamicColoringEnabled: true
    property bool gradientBackgroundEnabled: true
    property bool backdropBlurEnabled: false
    property bool ambientGradientEnabled: false
    property bool snowEffectEnabled: false
    property bool betaAudioProcessingEnabled: true
    
    signal backClicked()
    signal dynamicColoringToggled(bool enabled)
    signal gradientBackgroundToggled(bool enabled)
    signal backdropBlurToggled(bool enabled)
    signal ambientGradientToggled(bool enabled)
    signal snowEffectToggled(bool enabled)
    signal betaAudioProcessingToggled(bool enabled)
    
    color: Qt.darker(accentColor, 1.2)

    ScrollView {
        id: scrollView
        anchors.fill: parent
        anchors.margins: 0
        clip: true
        
        ScrollBar.vertical.policy: ScrollBar.AsNeeded
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        
        contentWidth: availableWidth
        contentHeight: contentItem.height
        
        Item {
            id: contentItem
            width: scrollView.availableWidth
            height: contentColumn.implicitHeight + 64  // Top and bottom margins
            
            ColumnLayout {
                id: contentColumn
                width: parent.width - 64  // Left and right margins
        spacing: 18
                anchors.top: parent.top
                anchors.topMargin: 32
                anchors.left: parent.left
                anchors.leftMargin: 32

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            Rectangle {
                id: backButton
                Layout.preferredWidth: 150
                Layout.preferredHeight: 36
                radius: 6
                color: backMouseArea.containsMouse ? Qt.lighter(accentColor, 1.4) : Qt.lighter(accentColor, 1.2)
                border.width: 1
                border.color: Qt.lighter(accentColor, 1.6)
                
                Behavior on color { ColorAnimation { duration: 150 } }
                
                Row {
                    anchors.centerIn: parent
                    spacing: 8
                    
                    Image {
                        id: backIcon
                        source: "qrc:/qlementine/icons/16/navigation/chevron-left.svg"
                        sourceSize: Qt.size(16, 16)
                        visible: false
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    ColorOverlay {
                        width: 16; height: 16
                        source: backIcon
                        color: foregroundColor
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    
                    Text {
                        text: qsTr("Back to viewer")
                        color: foregroundColor
                        font.pixelSize: 13
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
                
                MouseArea {
                    id: backMouseArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                onClicked: backClicked()
                }
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

        // File Associations Section
        Text {
            Layout.fillWidth: true
            text: qsTr("File Associations")
            font.pixelSize: 16
            font.bold: true
            color: foregroundColor
        }
        
        Text {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: qsTr("Set S3rp3nt Media as your default app for opening images and other media files.")
            color: Qt.lighter(foregroundColor, 1.3)
            font.pixelSize: 12
        }
        
        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            
            Rectangle {
                id: setDefaultButton
                Layout.preferredWidth: 240
                Layout.preferredHeight: 44
                radius: 8
                color: setDefaultMouseArea.containsMouse 
                       ? Qt.lighter(accentColor, 1.5) 
                       : Qt.lighter(accentColor, 1.3)
                border.width: 1
                border.color: Qt.lighter(accentColor, 1.8)
                
                Behavior on color { ColorAnimation { duration: 150 } }
                
                Row {
                    anchors.centerIn: parent
                    spacing: 10
                    
                    Image {
                        id: imageIcon
                        source: "qrc:/qlementine/icons/16/file/picture.svg"
                        sourceSize: Qt.size(18, 18)
                        visible: false
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    ColorOverlay {
                        width: 18; height: 18
                        source: imageIcon
                        color: foregroundColor
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    
                    Text {
                        text: qsTr("Set as Default for Images")
                        color: foregroundColor
                        font.pixelSize: 14
                        font.weight: Font.Medium
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
                
                MouseArea {
                    id: setDefaultMouseArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (typeof ColorUtils !== "undefined" && ColorUtils.registerAsDefaultImageViewer) {
                            ColorUtils.registerAsDefaultImageViewer()
                        }
                    }
                }
            }
            
            Rectangle {
                id: openSettingsButton
                Layout.preferredWidth: 160
                Layout.preferredHeight: 44
                radius: 8
                color: openSettingsMouseArea.containsMouse 
                       ? Qt.rgba(1, 1, 1, 0.15) 
                       : Qt.rgba(1, 1, 1, 0.08)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.2)
                
                Behavior on color { ColorAnimation { duration: 150 } }
                
                Row {
                    anchors.centerIn: parent
                    spacing: 8
                    
                    Image {
                        id: settingsIcon
                        source: "qrc:/qlementine/icons/16/action/external-link.svg"
                        sourceSize: Qt.size(14, 14)
                        visible: false
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    ColorOverlay {
                        width: 14; height: 14
                        source: settingsIcon
                        color: foregroundColor
                        opacity: 0.7
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    
                    Text {
                        text: qsTr("Windows Settings")
                        color: foregroundColor
                        font.pixelSize: 13
                        opacity: 0.8
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
                
                MouseArea {
                    id: openSettingsMouseArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (typeof ColorUtils !== "undefined" && ColorUtils.openDefaultAppsSettings) {
                            ColorUtils.openDefaultAppsSettings()
                        }
                    }
                }
            }
            
            Item { Layout.fillWidth: true }
        }
        
        Text {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: qsTr("This will register the app and open Windows Settings where you can select S3rp3nt Media as your default image viewer.")
            color: Qt.lighter(foregroundColor, 1.4)
            font.pixelSize: 11
            opacity: 0.8
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            Layout.topMargin: 12
            Layout.bottomMargin: 12
            color: Qt.darker(accentColor, 1.4)
            opacity: 0.6
        }

        // Appearance Section
        Text {
            Layout.fillWidth: true
            text: qsTr("Appearance")
            font.pixelSize: 16
            font.bold: true
            color: foregroundColor
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
            font.pixelSize: 12
        }

        CheckBox {
            text: qsTr("Enable gradient background")
            checked: gradientBackgroundEnabled
            enabled: dynamicColoringEnabled && !backdropBlurEnabled && !ambientGradientEnabled
            onToggled: gradientBackgroundToggled(checked)
            palette.text: foregroundColor
        }

        Text {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: qsTr("When enabled, creates a Spotify-style gradient background using multiple colors extracted from the cover image. Requires dynamic coloring to be enabled.")
            color: Qt.lighter(foregroundColor, 1.3)
            font.pixelSize: 12
            opacity: dynamicColoringEnabled ? 1.0 : 0.5
        }

        CheckBox {
            text: qsTr("Enable blurred backdrop background")
            checked: backdropBlurEnabled
            enabled: dynamicColoringEnabled && !gradientBackgroundEnabled && !ambientGradientEnabled
            onToggled: backdropBlurToggled(checked)
            palette.text: foregroundColor
        }

        Text {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: qsTr("When enabled, creates a blurred backdrop effect using the cover art or image (like Apple Music, YouTube Music). The image is scaled, blurred, and darkened for a rich ambient background. Requires dynamic coloring to be enabled.")
            color: Qt.lighter(foregroundColor, 1.3)
            font.pixelSize: 12
            opacity: dynamicColoringEnabled ? 1.0 : 0.5
        }

        CheckBox {
            text: qsTr("Enable ambient animated gradient")
            checked: ambientGradientEnabled
            enabled: dynamicColoringEnabled
            onToggled: ambientGradientToggled(checked)
            palette.text: foregroundColor
        }

        Text {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: qsTr("When enabled, creates a Spotify-style ambient animated gradient using GPU shaders. The gradient slowly animates with organic motion, creating a living, breathing background effect. Requires dynamic coloring to be enabled.")
            color: Qt.lighter(foregroundColor, 1.3)
            font.pixelSize: 12
            opacity: dynamicColoringEnabled ? 1.0 : 0.5
        }

        CheckBox {
            text: qsTr("Enable snow effect")
            checked: snowEffectEnabled
            enabled: true  // Snow can be enabled with any other effect
            onToggled: snowEffectToggled(checked)
            palette.text: foregroundColor
        }

        Text {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: qsTr("When enabled, creates a beautiful hybrid snow effect combining procedural shader-based background snow with particle-based foreground flakes. Perfect for winter vibes! This effect is independent of dynamic coloring.")
            color: Qt.lighter(foregroundColor, 1.3)
            font.pixelSize: 12
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
            }  // End ColumnLayout
        }  // End Item (contentItem)
    }  // End ScrollView
}

