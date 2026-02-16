import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import QtCore

Rectangle {
    id: settingsPage
    
    property var appWindow: null  // Reference to main window for blur
    property var mediaViewerItem: null  // Reference to media viewer for blur capture
    property bool showingSettings: false  // Track when settings is actually shown
    property color accentColor: "#121216"
    property color foregroundColor: "#f5f5f5"
    property bool dynamicColoringEnabled: true
    property bool gradientBackgroundEnabled: true
    property bool backdropBlurEnabled: false
    property bool ambientGradientEnabled: false
    property bool snowEffectEnabled: false
    property bool badAppleEffectEnabled: false
    property bool betaAudioProcessingEnabled: true
    property bool lyricsTranslationEnabled: false
    property string lyricsTranslationApiKey: ""
    property string lyricsTranslationTargetLanguage: "en"
    property string appLanguage: "en"
    property bool imageInterpolationMode: true
    property bool dynamicResolutionEnabled: true
    property bool matchMediaAspectRatio: false
    property bool autoHideTitleBar: false
    property bool discordRPCEnabled: true
    property string coverArtSource: "coverartarchive"  // "coverartarchive" or "lastfm"
    property string lastFMApiKey: ""
    property bool debugConsoleEnabled: false
    
    signal backClicked()
    signal dynamicColoringToggled(bool enabled)
    signal gradientBackgroundToggled(bool enabled)
    signal backdropBlurToggled(bool enabled)
    signal ambientGradientToggled(bool enabled)
    signal snowEffectToggled(bool enabled)
    signal badAppleEffectToggled(bool enabled)
    signal badAppleEasterEggClicked()
    signal undertaleEasterEggClicked()
    signal betaAudioProcessingToggled(bool enabled)
    signal lyricsTranslationToggled(bool enabled)
    signal lyricsTranslationApiKeyEdited(string apiKey)
    signal lyricsTranslationTargetLanguageEdited(string language)
    signal appLanguageEdited(string language)
    signal imageInterpolationModeSelected(bool smooth)
    signal dynamicResolutionToggled(bool enabled)
    signal matchMediaAspectRatioToggled(bool enabled)
    signal autoHideTitleBarToggled(bool enabled)
    signal discordRPCToggled(bool enabled)
    signal coverArtSourceSelected(string source)
    signal lastFMApiKeyEdited(string apiKey)
    signal debugConsoleToggled(bool enabled)
    
    // Modern popup container
    Layout.fillWidth: true
    Layout.fillHeight: true
    color: "transparent"  // Transparent to allow blur to show through

    // Capture the media viewer for blur effect
    ShaderEffectSource {
        id: backgroundSource
        anchors.fill: parent
        sourceItem: {
            // Prefer media viewer, fallback to window background
            if (mediaViewerItem) {
                return mediaViewerItem
            }
            return (appWindow && appWindow.background) ? appWindow.background : null
        }
        live: true  // Update live so it captures the current media viewer state
        hideSource: false  // Don't hide source - we want the original visible behind the blur
        visible: false
        z: -2  // Behind blur and overlay
        
        // Debug logging
        onSourceItemChanged: {
            console.log("[SettingsBlur] ShaderEffectSource sourceItem changed:", sourceItem ? "set" : "null", "mediaViewerItem:", mediaViewerItem ? "set" : "null")
            if (sourceItem) {
                scheduleUpdate()
            }
        }
        
        // Force update when component becomes visible
        Component.onCompleted: {
            if (sourceItem) {
                scheduleUpdate()
                console.log("[SettingsBlur] ShaderEffectSource initialized, sourceItem:", sourceItem)
            } else {
                console.log("[SettingsBlur] ShaderEffectSource initialized, but sourceItem is null. appWindow:", appWindow ? "set" : "null")
            }
        }
    }
    
    // Blurred background with smooth animation
    FastBlur {
        id: blurEffect
        anchors.fill: parent
        source: backgroundSource
        radius: blurActive ? 50 : 0  // Increased blur radius even more for better visibility
        visible: blurActive && backgroundSource.sourceItem !== null
        z: -1  // Behind overlay but above source
        
        // Smooth blur animation
        Behavior on radius {
            NumberAnimation { duration: 400; easing.type: Easing.OutCubic }
        }
        
        // Also animate opacity for smoother effect
        opacity: blurActive ? 1.0 : 0.0
        Behavior on opacity {
            NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
        }
    }
    
    // Dark overlay on top of blur (very light so blur is clearly visible)
            Rectangle {
        id: darkOverlay
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.15)  // Very light overlay so blur is clearly visible
        z: 0  // Above blur
        
        // Fade in animation for overlay
        opacity: 0
        Behavior on opacity {
            NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
        }
    }
    
    // Property to track if blur should be active - only when settings is actually shown
    property bool blurActive: false
    
    // Debug: log when mediaViewerItem changes
    onMediaViewerItemChanged: {
        console.log("[SettingsBlur] mediaViewerItem changed:", mediaViewerItem ? "set" : "null")
    }
    
    // Animate blur and overlay when settings is shown/hidden
    onShowingSettingsChanged: {
        console.log("[SettingsBlur] showingSettings changed to:", showingSettings, "mediaViewerItem:", mediaViewerItem ? "set" : "null")
        if (showingSettings) {
            // Settings is opening - capture media viewer for blur (it's now always visible!)
            if (mediaViewerItem) {
                backgroundSource.sourceItem = mediaViewerItem
                backgroundSource.scheduleUpdate()
                console.log("[SettingsBlur] Captured media viewer for blur")
            } else if (appWindow && appWindow.background) {
                // Fallback to window background
                backgroundSource.sourceItem = appWindow.background
                backgroundSource.scheduleUpdate()
                console.log("[SettingsBlur] Using window background for blur (fallback)")
            }
            
            Qt.callLater(function() {
                blurActive = true
                darkOverlay.opacity = 1
            })
        } else {
            // Settings is closing - animate blur out
            console.log("[SettingsBlur] Settings closing, animating blur out")
            blurActive = false
            darkOverlay.opacity = 0
        }
    }
    
    // Initialize - start with everything hidden
    Component.onCompleted: {
        blurActive = false
        darkOverlay.opacity = 0
        console.log("[SettingsBlur] Component initialized, blurActive:", blurActive)
    }
    
    // Update blur when appWindow becomes available (if settings is already shown)
    onAppWindowChanged: {
        if (appWindow && appWindow.background && showingSettings) {
            Qt.callLater(function() {
                console.log("[SettingsBlur] appWindow changed, updating blur")
                backgroundSource.scheduleUpdate()
                blurActive = true
            })
        }
    }
    
    // Main settings container (must be above blur and overlay)
        Rectangle {
        id: settingsContainer
        anchors.centerIn: parent
        width: Math.min(900, parent.width - 80)
        height: Math.min(700, parent.height - 80)
        radius: 20
        z: 1  // Above blur and overlay
        color: Qt.rgba(
            Qt.lighter(accentColor, 1.3).r,
            Qt.lighter(accentColor, 1.3).g,
            Qt.lighter(accentColor, 1.3).b,
            0.95
        )
        
        // Entrance animation
        scale: 0.9
        opacity: 0
        Behavior on scale {
            NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
        }
        Behavior on opacity {
            NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
        }
        Component.onCompleted: {
            scale = 1.0
            opacity = 1.0
        }
        
        // Subtle shadow
        layer.enabled: true
        layer.effect: DropShadow {
            transparentBorder: true
            horizontalOffset: 0
            verticalOffset: 8
            radius: 24
            samples: 32
            color: Qt.rgba(0, 0, 0, 0.3)
        }
        
        RowLayout {
            anchors.fill: parent
            anchors.margins: 0
            spacing: 0
            
            // Left sidebar
            Rectangle {
                id: sidebar
                Layout.preferredWidth: 220
                Layout.fillHeight: true
                color: Qt.rgba(0, 0, 0, 0.2)
                radius: 20
            
            ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 8
                    
                    // Header
        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            
            Rectangle {
                            width: 32
                            height: 32
                radius: 8
                            color: Qt.rgba(foregroundColor.r, foregroundColor.g, foregroundColor.b, 0.1)
                    
                    Image {
                                id: settingsHeaderIcon
                                anchors.centerIn: parent
                                source: "qrc:/qlementine/icons/16/navigation/settings.svg"
                        sourceSize: Qt.size(18, 18)
                        visible: false
                    }
                    ColorOverlay {
                                anchors.fill: settingsHeaderIcon
                                source: settingsHeaderIcon
                        color: foregroundColor
                            }
                    }
                    
                    Text {
                            text: qsTr("Settings")
                            font.pixelSize: 18
                            font.weight: Font.Bold
                        color: foregroundColor
            Layout.fillWidth: true
        }
            
            Rectangle {
                            width: 36
                            height: 36
                radius: 8
                            color: closeTap.pressed
                                   ? Qt.rgba(0.9, 0.3, 0.3, 0.3)
                                   : (closeHover.hovered
                                      ? Qt.rgba(0.9, 0.3, 0.3, 0.2)
                                      : Qt.rgba(foregroundColor.r, foregroundColor.g, foregroundColor.b, 0.05))
                            
                            Behavior on color {
                                ColorAnimation { duration: 150; easing.type: Easing.OutCubic }
                            }
                            
                            Behavior on scale {
                                NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                }
                
                            scale: closeTap.pressed ? 0.95 : (closeHover.hovered ? 1.05 : 1.0)
                    
                    Image {
                                id: closeIcon
                                anchors.centerIn: parent
                                source: "qrc:/qlementine/icons/16/action/windows-close.svg"
                        sourceSize: Qt.size(18, 18)
                        visible: false
                    }
                    ColorOverlay {
                                anchors.fill: closeIcon
                                source: closeIcon
                                color: closeHover.hovered ? "#ff4444" : foregroundColor
                                opacity: closeHover.hovered ? 1.0 : 0.8
                                
                                Behavior on color {
                                    ColorAnimation { duration: 150; easing.type: Easing.OutCubic }
                                }
                                
                                Behavior on opacity {
                                    NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                                }
                            }
                            
                            HoverHandler {
                                id: closeHover
                    cursorShape: Qt.PointingHandCursor
                                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                            }
                            
                            TapHandler {
                                id: closeTap
                                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                                acceptedButtons: Qt.LeftButton
                                onTapped: backClicked()
                    }
                }
            }
            
            Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
                        color: Qt.rgba(1, 1, 1, 0.1)
                        Layout.topMargin: 8
                        Layout.bottomMargin: 8
                    }
                    
                    // Navigation items
                    Repeater {
                        model: [
                            { id: "appearance", name: qsTr("Appearance"), icon: "qrc:/qlementine/icons/16/misc/pen.svg" },
                            { id: "display", name: qsTr("Display"), icon: "qrc:/qlementine/icons/16/hardware/screen.svg" },
                            { id: "video", name: qsTr("Video"), icon: "qrc:/qlementine/icons/16/hardware/screen.svg" },
                            { id: "audio", name: qsTr("Audio"), icon: "qrc:/qlementine/icons/16/hardware/speaker.svg" },
                            { id: "translation", name: qsTr("Translation"), icon: "qrc:/qlementine/icons/16/misc/info.svg" },
                            { id: "general", name: qsTr("General"), icon: "qrc:/qlementine/icons/16/navigation/settings.svg" },
                            { id: "discord", name: qsTr("Discord"), icon: "qrc:/qlementine/icons/16/misc/info.svg" }
                        ]
                        
                        Rectangle {
            Layout.fillWidth: true
                Layout.preferredHeight: 44
                            radius: 10
                            color: currentSection === modelData.id 
                                   ? Qt.rgba(foregroundColor.r, foregroundColor.g, foregroundColor.b, 0.15)
                                   : (navHover.hovered ? Qt.rgba(1, 1, 1, 0.08) : "transparent")
                
                            // Smooth animations
                            Behavior on color {
                                ColorAnimation { duration: 200; easing.type: Easing.OutCubic }
                            }
                            
                            Behavior on scale {
                                NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                            }
                            
                            scale: navHover.hovered ? 1.02 : 1.0
                            
                            // Active indicator animation
            Rectangle {
                                anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                                width: 3
                                height: currentSection === modelData.id ? parent.height * 0.6 : 0
                                radius: 2
                                color: foregroundColor
                                opacity: currentSection === modelData.id ? 0.8 : 0
                                
                                Behavior on height {
                                    NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                                }
                                Behavior on opacity {
                                    NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                                }
                            }
                            
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                spacing: 12
                    
                    Image {
                                    id: navIcon
                                    source: modelData.icon
                        sourceSize: Qt.size(18, 18)
                                    visible: false  // Image must be invisible for ColorOverlay to work
                    }
                    ColorOverlay {
                                    width: 18
                                    height: 18
                                    source: navIcon
                        color: foregroundColor
                                    opacity: currentSection === modelData.id ? 1.0 : 0.7
                                    visible: modelData.icon !== ""
                                    
                                    Behavior on opacity {
                                        NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                                    }
                    }
                    
                    Text {
                                    text: modelData.name
                        font.pixelSize: 14
                                    font.weight: currentSection === modelData.id ? Font.Medium : Font.Normal
                        color: foregroundColor
                                    opacity: currentSection === modelData.id ? 1.0 : 0.8
                                    Layout.fillWidth: true
                                    
                                    Behavior on opacity {
                                        NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                                    }
                    }
                }
                
                            HoverHandler {
                                id: navHover
                    cursorShape: Qt.PointingHandCursor
                        }
                            
                            TapHandler {
                                onTapped: currentSection = modelData.id
                    }
                }
            }
            
                    Item { Layout.fillHeight: true }
                }
        }
        
            // Right content area
            ScrollView {
                id: contentScrollView
            Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                
                ScrollBar.vertical.policy: ScrollBar.AsNeeded
                
                contentWidth: availableWidth
                contentHeight: contentColumn.implicitHeight
                
                ColumnLayout {
                    id: contentColumn
                    width: contentScrollView.availableWidth
                    spacing: 0
                    
                    // Content based on selected section with fade animation
                    Loader {
                        id: contentLoader
                        Layout.fillWidth: true
                        Layout.topMargin: 24
                        Layout.leftMargin: 32
                        Layout.rightMargin: 32
                        Layout.bottomMargin: 24
                        sourceComponent: {
                            switch(currentSection) {
                                case "appearance": return appearanceContent
                                case "display": return displayContent
                                case "video": return videoContent
                                case "audio": return audioContent
                                case "translation": return translationContent
                                case "general": return generalContent
                                case "discord": return discordContent
                                default: return appearanceContent
                            }
                        }
                        
                        // Fade animation when section changes
                        opacity: 1
                        
                        Behavior on opacity {
                            NumberAnimation { duration: 250; easing.type: Easing.InOutCubic }
                        }
                        
                        onSourceComponentChanged: {
                            opacity = 0
                            Qt.callLater(function() {
                                opacity = 1
                            })
                        }
                    }
                }
            }
        }
    }
    
    // Current section
    property string currentSection: "appearance"
    
    // Modern toggle switch component
    component ModernToggle: RowLayout {
        property bool checked: false
        property string label: ""
        property string description: ""
        property bool enabled: true
        
        signal toggled(bool checked)
        
        spacing: 16
            Layout.fillWidth: true
        Layout.topMargin: 20
        
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            
            Text {
                text: label
                font.pixelSize: 15
                font.weight: Font.Medium
                color: foregroundColor
                opacity: parent.parent.enabled ? 1.0 : 0.5
            }
            
        Text {
                text: description
                font.pixelSize: 12
            color: foregroundColor
                opacity: 0.7
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
                visible: description !== ""
            }
        }
        
        Rectangle {
            Layout.preferredWidth: 52
            Layout.preferredHeight: 32
            radius: 16
            color: checked 
                   ? (toggleHover.hovered ? Qt.lighter("#4CAF50", 1.1) : "#4CAF50")
                   : (toggleHover.hovered ? Qt.rgba(1, 1, 1, 0.2) : Qt.rgba(1, 1, 1, 0.1))
            enabled: parent.enabled
            
            Behavior on color {
                ColorAnimation { duration: 250; easing.type: Easing.OutCubic }
            }
            
            Behavior on scale {
                NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
            }
            
            scale: toggleTap.pressed ? 0.95 : 1.0
            
            Rectangle {
                width: 24
                height: 24
                radius: 12
                anchors.verticalCenter: parent.verticalCenter
                x: checked ? parent.width - width - 4 : 4
                color: "#FFFFFF"
                
                // Subtle shadow for the toggle circle
                layer.enabled: true
                layer.effect: DropShadow {
                    transparentBorder: true
                    horizontalOffset: 0
                    verticalOffset: 2
                    radius: 4
                    samples: 8
                    color: Qt.rgba(0, 0, 0, 0.15)
                }
                
                Behavior on x {
                    NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
                }
                
                Behavior on scale {
                    NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                }
                
                scale: toggleTap.pressed ? 0.9 : (checked ? 1.05 : 1.0)
            }
            
            HoverHandler {
                id: toggleHover
                cursorShape: Qt.PointingHandCursor
            }
            
            TapHandler {
                id: toggleTap
                enabled: parent.parent.enabled
                onTapped: {
                    parent.parent.checked = !parent.parent.checked
                    parent.parent.toggled(parent.parent.checked)
                }
            }
        }
    }
    
    // Modern button component
    component ModernButton: Rectangle {
        property string label: ""
        property string icon: ""
        property bool primary: false
        
        signal clicked()
        
        Layout.preferredHeight: 44
            Layout.fillWidth: true
        radius: 12
        color: primary
               ? (buttonTap.pressed ? Qt.darker(Qt.lighter(accentColor, 1.3), 1.1) : (buttonHover.hovered ? Qt.lighter(accentColor, 1.4) : Qt.lighter(accentColor, 1.3)))
               : (buttonTap.pressed ? Qt.rgba(1, 1, 1, 0.2) : (buttonHover.hovered ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(1, 1, 1, 0.08)))
        
        border.width: primary ? 0 : 1
        border.color: Qt.rgba(1, 1, 1, 0.1)
        
        // Smooth animations
        Behavior on color {
            ColorAnimation { duration: 200; easing.type: Easing.OutCubic }
        }
        
        Behavior on scale {
            NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
        }
        
        Behavior on border.color {
            ColorAnimation { duration: 200; easing.type: Easing.OutCubic }
        }
        
        scale: buttonTap.pressed ? 0.97 : (buttonHover.hovered ? 1.02 : 1.0)
        
        // Subtle shadow for primary buttons
        layer.enabled: primary
        layer.effect: DropShadow {
            transparentBorder: true
            horizontalOffset: 0
            verticalOffset: buttonHover.hovered ? 4 : 2
            radius: buttonHover.hovered ? 12 : 8
            samples: 16
            color: Qt.rgba(0, 0, 0, buttonHover.hovered ? 0.3 : 0.2)
            
            Behavior on verticalOffset {
                NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
            }
            Behavior on radius {
                NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
            }
            Behavior on color {
                ColorAnimation { duration: 200; easing.type: Easing.OutCubic }
            }
        }
        
        Item {
                anchors.centerIn: parent
            width: buttonRow.implicitWidth
            height: buttonRow.implicitHeight
            
            property string buttonLabel: parent.label
            property string buttonIcon: parent.icon
            
            Row {
                id: buttonRow
                spacing: 10
                
                Item {
                    width: 18
                    height: 18
                
                Image {
                        id: buttonIconImage
                        anchors.fill: parent
                        source: parent.parent.parent.buttonIcon
                    sourceSize: Qt.size(18, 18)
                    visible: false
                }
                ColorOverlay {
                        anchors.fill: buttonIconImage
                        source: buttonIconImage
                    color: foregroundColor
                        visible: parent.parent.parent.buttonIcon !== ""
                    }
                }
                
                Text {
                    text: parent.parent.parent.buttonLabel || ""
                    font.pixelSize: 14
                    font.weight: Font.Medium
                    color: foregroundColor
                }
                }
            }
            
        HoverHandler {
            id: buttonHover
                cursorShape: Qt.PointingHandCursor
        }
        
        TapHandler {
            id: buttonTap
            onTapped: {
                parent.clicked()
                // Subtle ripple effect
                rippleAnimation.start()
            }
        }
        
        // Ripple effect on click
        Rectangle {
            id: ripple
            anchors.centerIn: parent
            width: 0
            height: 0
            radius: width / 2
            color: Qt.rgba(1, 1, 1, 0.2)
            opacity: 0
            
            SequentialAnimation {
                id: rippleAnimation
                ParallelAnimation {
                    NumberAnimation {
                        target: ripple
                        property: "width"
                        from: 0
                        to: parent.width * 2
                        duration: 400
                        easing.type: Easing.OutCubic
                    }
                    NumberAnimation {
                        target: ripple
                        property: "height"
                        from: 0
                        to: parent.width * 2
                        duration: 400
                        easing.type: Easing.OutCubic
                    }
                    NumberAnimation {
                        target: ripple
                        property: "opacity"
                        from: 0.3
                        to: 0
                        duration: 400
                        easing.type: Easing.OutCubic
                    }
                }
                ScriptAction {
                    script: {
                        ripple.width = 0
                        ripple.height = 0
                        ripple.opacity = 0
            }
        }
            }
        }
    }
    
    // Section content components
    Component {
        id: appearanceContent
        
        ColumnLayout {
            spacing: 0
            width: parent.width

        Text {
                text: qsTr("Appearance")
                font.pixelSize: 24
                font.weight: Font.Bold
                color: foregroundColor
                Layout.bottomMargin: 8
        }

        Text {
                text: qsTr("Customize the visual appearance and effects")
                font.pixelSize: 13
            color: foregroundColor
                opacity: 0.7
                Layout.bottomMargin: 24
            }
            
            ModernToggle {
                label: qsTr("Dynamic Coloring")
                description: qsTr("Adapts the interface colors to the dominant tones of the current media")
                checked: dynamicColoringEnabled
                onToggled: (checked) => dynamicColoringToggled(checked)
            }
            
            ModernToggle {
                label: qsTr("Gradient Background")
                description: qsTr("Creates a Spotify-style gradient background using colors from the cover image")
                checked: gradientBackgroundEnabled
                enabled: dynamicColoringEnabled && !backdropBlurEnabled && !ambientGradientEnabled
                onToggled: (checked) => gradientBackgroundToggled(checked)
            }
            
            ModernToggle {
                label: qsTr("Blurred Backdrop")
                description: qsTr("Creates a blurred backdrop effect using the cover art or image (like Apple Music)")
                checked: backdropBlurEnabled
                enabled: dynamicColoringEnabled && !gradientBackgroundEnabled && !ambientGradientEnabled
                onToggled: (checked) => backdropBlurToggled(checked)
            }
            
            ModernToggle {
                label: qsTr("Ambient Animated Gradient")
                description: qsTr("Creates a Spotify-style ambient animated gradient with organic motion")
                checked: ambientGradientEnabled
                enabled: dynamicColoringEnabled
                onToggled: (checked) => ambientGradientToggled(checked)
            }
            
            ModernToggle {
                label: qsTr("Snow Effect")
                description: qsTr("Creates a beautiful hybrid snow effect with procedural shaders and particles")
                checked: snowEffectEnabled
                onToggled: (checked) => snowEffectToggled(checked)
            }
            
            ModernToggle {
                label: qsTr("Auto-Hide Titlebar")
                description: qsTr("Automatically hides the titlebar when not hovering over it, similar to Windows 11")
                checked: autoHideTitleBar
                onToggled: (checked) => autoHideTitleBarToggled(checked)
            }
            
            ModernButton {
                label: qsTr("🎵 Play Bad Apple!! Easter Egg")
                icon: "qrc:/qlementine/icons/16/media/play.svg"
                primary: true
                Layout.topMargin: 24
                onClicked: badAppleEasterEggClicked()
            }
                
                Text {
                text: qsTr("🎁 Easter Egg: Play the iconic Bad Apple!! shadow animation")
                font.pixelSize: 12
                color: foregroundColor
                opacity: 0.6
                Layout.topMargin: 8
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }
            
            ModernButton {
                label: qsTr("⚔️ Start Undertale Fight Easter Egg")
                icon: "qrc:/qlementine/icons/16/media/play.svg"
                primary: true
                Layout.topMargin: 24
                onClicked: undertaleEasterEggClicked()
            }
                
                Text {
                text: qsTr("🎁 Easter Egg: Experience an Undertale-style battle")
                font.pixelSize: 12
                color: foregroundColor
                opacity: 0.6
                Layout.topMargin: 8
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }
        }
    }
    
    Component {
        id: displayContent
        
        ColumnLayout {
            spacing: 0
            width: parent.width
            
            Text {
                text: qsTr("Display")
                font.pixelSize: 24
                font.weight: Font.Bold
                    color: foregroundColor
                Layout.bottomMargin: 8
            }
            
            Text {
                text: qsTr("Configure image rendering and display options")
                font.pixelSize: 13
                color: foregroundColor
                opacity: 0.7
                Layout.bottomMargin: 24
            }
            
            Text {
                text: qsTr("Image Interpolation")
                font.pixelSize: 15
                font.weight: Font.Medium
                color: foregroundColor
                Layout.topMargin: 20
                Layout.bottomMargin: 8
            }
            
            Rectangle {
                id: interpolationSelector
                Layout.fillWidth: true
                Layout.preferredHeight: 44
                radius: 12
                color: Qt.rgba(1, 1, 1, 0.08)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.15)
                
                RowLayout {
                        anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    
                    Text {
                        text: imageInterpolationMode ? qsTr("Smooth (Antialiased)") : qsTr("Nearest Neighbor (Pixelated)")
                        font.pixelSize: 14
                        color: foregroundColor
                        Layout.fillWidth: true
                    }
                    
                    Image {
                        id: chevronIcon
                        source: "qrc:/qlementine/icons/16/navigation/chevron-down.svg"
                        sourceSize: Qt.size(16, 16)
                        visible: false
                    }
                    ColorOverlay {
                        width: 16
                        height: 16
                        source: chevronIcon
                        color: foregroundColor
                        opacity: 0.6
                    }
                }
                
                TapHandler {
                    onTapped: interpolationPopup.open()
                }
            }
            
            Text {
                text: qsTr("Select how images are rendered when scaled. Smooth mode provides antialiased, high-quality rendering.")
                font.pixelSize: 12
                color: foregroundColor
                opacity: 0.7
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
                Layout.topMargin: 8
            }
            
            ModernToggle {
                label: qsTr("Dynamic Resolution Adjustment")
                description: qsTr("Decodes images at a resolution matching the zoom level, reducing memory usage at 100% zoom")
                checked: dynamicResolutionEnabled
                onToggled: (checked) => dynamicResolutionToggled(checked)
            }
            
            ModernToggle {
                label: qsTr("Match Window Aspect Ratio")
                description: qsTr("Automatically resizes the window to match the aspect ratio of loaded media")
                checked: matchMediaAspectRatio
                onToggled: (checked) => matchMediaAspectRatioToggled(checked)
            }
            
            Popup {
                id: interpolationPopup
                x: 0
                y: interpolationSelector.height + 2
                width: interpolationSelector.width
                height: 88  // 2 items * 44px each
                modal: true
                closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
                parent: interpolationSelector
                
                padding: 0
                topPadding: 0
                bottomPadding: 0
                leftPadding: 0
                rightPadding: 0
                
                // Entrance and exit animations
                enter: Transition {
                    NumberAnimation { property: "opacity"; from: 0.0; to: 1.0; duration: 200; easing.type: Easing.OutCubic }
                    NumberAnimation { property: "scale"; from: 0.95; to: 1.0; duration: 200; easing.type: Easing.OutCubic }
                }
                
                exit: Transition {
                    NumberAnimation { property: "opacity"; from: 1.0; to: 0.0; duration: 200; easing.type: Easing.InCubic }
                    NumberAnimation { property: "scale"; from: 1.0; to: 0.95; duration: 200; easing.type: Easing.InCubic }
                }
                
                background: Rectangle {
                    color: Qt.rgba(
                        Qt.lighter(accentColor, 1.3).r,
                        Qt.lighter(accentColor, 1.3).g,
                        Qt.lighter(accentColor, 1.3).b,
                        0.98
                    )
                    border.color: Qt.rgba(1, 1, 1, 0.15)
                    border.width: 1
                    radius: 12
                    
                    // Shadow
                    layer.enabled: true
                    layer.effect: DropShadow {
                        transparentBorder: true
                        horizontalOffset: 0
                        verticalOffset: 4
                        radius: 16
                        samples: 32
                        color: Qt.rgba(0, 0, 0, 0.3)
                    }
                }
                
                contentItem: Column {
                    spacing: 0
                    clip: true
                    width: interpolationPopup.width
                    anchors.fill: parent
                    
                    Repeater {
                        model: [
                            { value: true, name: qsTr("Smooth (Antialiased)") },
                            { value: false, name: qsTr("Nearest Neighbor (Pixelated)") }
                        ]
                        
                        Rectangle {
                            width: parent.width
                            height: 44
                            radius: 0
                            topLeftRadius: index === 0 ? 11 : 0
                            topRightRadius: index === 0 ? 11 : 0
                            bottomLeftRadius: index === 1 ? 11 : 0
                            bottomRightRadius: index === 1 ? 11 : 0
                            color: popupItemHover.hovered ? Qt.rgba(1, 1, 1, 0.12) : "transparent"
                            
                            Behavior on color {
                                ColorAnimation { duration: 150; easing.type: Easing.OutCubic }
                            }
                        
                        Text {
                            anchors.left: parent.left
                                anchors.leftMargin: 16
                                anchors.right: parent.right
                                anchors.rightMargin: 16
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.name
                            color: foregroundColor
                            font.pixelSize: 14
                                font.weight: imageInterpolationMode === modelData.value ? Font.Medium : Font.Normal
                                opacity: imageInterpolationMode === modelData.value ? 1.0 : 0.8
                                elide: Text.ElideRight
                            }
                            
                            HoverHandler {
                                id: popupItemHover
                            cursorShape: Qt.PointingHandCursor
                            }
                            
                            TapHandler {
                                onTapped: {
                                imageInterpolationModeSelected(modelData.value)
                                    interpolationPopup.close()
                            }
                        }
                    }
                }
            }
        }
        }
    }
    
    Component {
        id: videoContent
        
        ColumnLayout {
            spacing: 0
            width: parent.width
            
            // Helper property to determine if libmpv is selected
            readonly property bool isLibmpvSelected: {
                var backend = videoPlayerSettings.videoBackend || (videoPlayerSettings.useWMF ? "wmf" : "mediaplayer")
                return backend === "libmpv"
            }
            
            Text {
                text: qsTr("Video")
                font.pixelSize: 24
                font.weight: Font.Bold
                color: foregroundColor
                Layout.bottomMargin: 8
            }
            
            Text {
                text: qsTr("Configure video playback and player options")
                font.pixelSize: 13
                color: foregroundColor
                opacity: 0.7
                Layout.bottomMargin: 24
            }
            
            Text {
                text: qsTr("Video Player")
                font.pixelSize: 15
                font.weight: Font.Medium
                color: foregroundColor
                Layout.topMargin: 20
                Layout.bottomMargin: 8
            }
            
            Settings {
                id: videoPlayerSettings
                category: "video"
                property bool useWMF: false  // Legacy: kept for backward compatibility
                property string videoBackend: "mediaplayer"  // "mediaplayer", "wmf", or "libmpv"
                property string subtitleEngine: "external"  // "embedded" or "external"
                property string mpvRendererMode: "opengl"  // "opengl" or "d3d11" (only applies when videoBackend is "libmpv")
                
                // Ensure settings are synced when mpvRendererMode changes
                onMpvRendererModeChanged: {
                    console.log("[Settings] mpvRendererMode changed to:", mpvRendererMode)
                    sync()
                }
            }
            
            Rectangle {
                id: playerSelector
                Layout.fillWidth: true
                Layout.preferredHeight: 44
                radius: 12
                color: Qt.rgba(1, 1, 1, 0.08)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.15)
                
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    
                    Text {
                        text: {
                            var backend = videoPlayerSettings.videoBackend || (videoPlayerSettings.useWMF ? "wmf" : "mediaplayer")
                            if (backend === "libvlc") return qsTr("VLC (libvlc)")
                            if (backend === "libmpv") return qsTr("libmpv")
                            if (backend === "wmf") return qsTr("WMF (Windows Media Foundation)")
                            if (backend === "ffmpeg") return qsTr("FFmpeg (D3D11)")
                            return qsTr("MediaPlayer (Qt Multimedia)")
                        }
                        font.pixelSize: 14
                        color: foregroundColor
                        Layout.fillWidth: true
                    }
                    
                    Image {
                        id: playerChevronIcon
                        source: "qrc:/qlementine/icons/16/navigation/chevron-down.svg"
                        sourceSize: Qt.size(16, 16)
                        visible: false
                    }
                    ColorOverlay {
                        width: 16
                        height: 16
                        source: playerChevronIcon
                        color: foregroundColor
                        opacity: 0.6
                    }
                }
                
                TapHandler {
                    onTapped: playerPopup.open()
                }
            }
            
            Text {
                text: {
                    var backend = videoPlayerSettings.videoBackend || (videoPlayerSettings.useWMF ? "wmf" : "mediaplayer")
                    if (backend === "libvlc") {
                        return qsTr("VLC provides excellent format support and stability, similar to the standalone VLC player. Requires restart to take effect.")
                    } else if (backend === "libmpv") {
                        return qsTr("libmpv provides full HDR10/Dolby Vision support, proper tone mapping, BT.2020 color space conversion, and GPU-accelerated output. Best for HDR content. Requires restart to take effect.")
                    } else if (backend === "wmf") {
                        return qsTr("WMF provides better hardware acceleration and handles problematic videos better, but does not support audio/subtitle track selection. Requires restart to take effect.")
                    } else if (backend === "ffmpeg") {
                        return qsTr("FFmpeg with D3D11VA provides modern GPU-accelerated HDR playback, zero-copy rendering, and proper HDR10/Dolby Vision support. Best for 4K HDR content. Requires restart to take effect.")
                    } else {
                        return qsTr("MediaPlayer supports audio and subtitle track selection, but may have issues with some video formats and limited HDR support. Requires restart to take effect.")
                    }
                }
                font.pixelSize: 12
                color: foregroundColor
                opacity: 0.7
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
                Layout.topMargin: 8
            }
            
            Popup {
                id: playerPopup
                x: 0
                y: playerSelector.height + 2
                width: playerSelector.width
                height: Math.min(300, playerList.height + 16)
                modal: true
                closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
                
                background: Rectangle {
                    radius: 12
                    color: Qt.rgba(0.1, 0.1, 0.1, 0.95)
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.15)
                    
                    layer.enabled: true
                    layer.effect: DropShadow {
                        transparentBorder: true
                        horizontalOffset: 0
                        verticalOffset: 4
                        radius: 16
                        samples: 32
                        color: Qt.rgba(0, 0, 0, 0.5)
                    }
                }
                
                Column {
                    id: playerList
                    width: parent.width
                    spacing: 4
                    padding: 8
                    
                    Repeater {
                        model: [
                            { value: "mediaplayer", label: qsTr("MediaPlayer (Qt Multimedia)"), description: qsTr("Supports track selection, basic HDR") },
                            { value: "wmf", label: qsTr("WMF (Windows Media Foundation)"), description: qsTr("Better hardware acceleration, Windows only") },
                            { value: "libvlc", label: qsTr("VLC (libvlc)"), description: qsTr("Excellent format support, reliable playback") },
                            { value: "libmpv", label: qsTr("libmpv"), description: qsTr("Full HDR10/Dolby Vision support, proper tone mapping, GPU-accelerated (⚠️ May not work on Qt 6 Windows - use WMF instead)") },
                            { value: "ffmpeg", label: qsTr("FFmpeg (D3D11)"), description: qsTr("Modern GPU-accelerated HDR playback with D3D11VA, best for 4K HDR content") }
                        ]
                        
                        Rectangle {
                            width: playerList.width - 16
                            height: 52
                            radius: 8
                            color: playerItemMouseArea.containsMouse ? Qt.rgba(1, 1, 1, 0.1) : "transparent"
                            
                            // Check both new and legacy settings for backward compatibility
                            property bool isSelected: {
                                var backend = videoPlayerSettings.videoBackend || (videoPlayerSettings.useWMF ? "wmf" : "mediaplayer")
                                return backend === modelData.value
                            }
                            
                            MouseArea {
                                id: playerItemMouseArea
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: {
                                    videoPlayerSettings.videoBackend = modelData.value
                                    // Update legacy setting for backward compatibility
                                    if (modelData.value === "wmf") {
                                        videoPlayerSettings.useWMF = true
                                    } else if (modelData.value === "mediaplayer") {
                                        videoPlayerSettings.useWMF = false
                                    }
                                    playerPopup.close()
                                }
                            }
                            
                            Column {
                                anchors.left: parent.left
                                anchors.leftMargin: 12
                                anchors.right: parent.right
                                anchors.rightMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 4
                                
                                Text {
                                    text: modelData.label
                                    font.pixelSize: 14
                                    font.weight: isSelected ? Font.Medium : Font.Normal
                                    color: foregroundColor
                                }
                                
                                Text {
                                    text: modelData.description
                                    font.pixelSize: 12
                                    color: foregroundColor
                                    opacity: 0.7
                                }
                            }
                            
                            Rectangle {
                                anchors.right: parent.right
                                anchors.rightMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                                width: 20
                                height: 20
                                radius: 10
                                color: isSelected ? "#4CAF50" : "transparent"
                                border.width: isSelected ? 0 : 2
                                border.color: Qt.rgba(1, 1, 1, 0.3)
                                
                                Text {
                                    anchors.centerIn: parent
                                    text: "✓"
                                    font.pixelSize: 14
                                    color: "white"
                                    visible: isSelected
                                }
                            }
                        }
                    }
                }
            }
            
            Text {
                text: qsTr("Subtitle Engine")
                font.pixelSize: 15
                font.weight: Font.Medium
                color: foregroundColor
                Layout.topMargin: 32
                Layout.bottomMargin: 8
            }
            
            Rectangle {
                id: subtitleEngineSelector
                Layout.fillWidth: true
                Layout.preferredHeight: 44
                radius: 12
                color: Qt.rgba(1, 1, 1, 0.08)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.15)
                
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    
                    Text {
                        text: videoPlayerSettings.subtitleEngine === "embedded" 
                            ? qsTr("Embedded (from video file)") 
                            : qsTr("External (imported files)")
                        font.pixelSize: 14
                        color: foregroundColor
                        Layout.fillWidth: true
                    }
                    
                    Image {
                        id: subtitleEngineChevronIcon
                        source: "qrc:/qlementine/icons/16/navigation/chevron-down.svg"
                        sourceSize: Qt.size(16, 16)
                        visible: false
                    }
                    ColorOverlay {
                        width: 16
                        height: 16
                        source: subtitleEngineChevronIcon
                        color: foregroundColor
                        opacity: 0.6
                    }
                }
                
                TapHandler {
                    onTapped: subtitleEnginePopup.open()
                }
            }
            
            Text {
                text: videoPlayerSettings.subtitleEngine === "embedded"
                    ? qsTr("Uses subtitles embedded in the video file. Select tracks from the video context menu.")
                    : qsTr("Uses external subtitle files imported via the video context menu. Supports SRT, ASS, SSA formats.")
                font.pixelSize: 12
                color: foregroundColor
                opacity: 0.7
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
                Layout.topMargin: 8
            }
            
            Popup {
                id: subtitleEnginePopup
                x: 0
                y: subtitleEngineSelector.height + 2
                width: subtitleEngineSelector.width
                height: Math.min(200, subtitleEngineList.height + 16)
                modal: true
                closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
                parent: subtitleEngineSelector
                
                background: Rectangle {
                    radius: 12
                    color: Qt.rgba(0.1, 0.1, 0.1, 0.95)
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.15)
                    
                    layer.enabled: true
                    layer.effect: DropShadow {
                        transparentBorder: true
                        horizontalOffset: 0
                        verticalOffset: 4
                        radius: 16
                        samples: 32
                        color: Qt.rgba(0, 0, 0, 0.5)
                    }
                }
                
                contentItem: Column {
                    id: subtitleEngineList
                    width: subtitleEnginePopup.width
                    spacing: 4
                    padding: 8
                    
                    Repeater {
                        model: [
                            { value: "external", label: qsTr("External (imported files)"), description: qsTr("SRT, ASS, SSA support") },
                            { value: "embedded", label: qsTr("Embedded (from video)"), description: qsTr("Uses video file subtitles") }
                        ]
                        
                        Rectangle {
                            width: subtitleEngineList.width - 16
                            height: 52
                            radius: 8
                            color: subtitleEngineItemMouseArea.containsMouse ? Qt.rgba(1, 1, 1, 0.1) : "transparent"
                            
                            property bool isSelected: videoPlayerSettings.subtitleEngine === modelData.value
                            
                            MouseArea {
                                id: subtitleEngineItemMouseArea
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: {
                                    videoPlayerSettings.subtitleEngine = modelData.value
                                    subtitleEnginePopup.close()
                                }
                            }
                            
                            Column {
                                anchors.left: parent.left
                                anchors.leftMargin: 12
                                anchors.right: parent.right
                                anchors.rightMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 4
                                
                                Text {
                                    text: modelData.label
                                    font.pixelSize: 14
                                    font.weight: isSelected ? Font.Medium : Font.Normal
                                    color: foregroundColor
                                }
                                
                                Text {
                                    text: modelData.description
                                    font.pixelSize: 12
                                    color: foregroundColor
                                    opacity: 0.7
                                }
                            }
                            
                            Rectangle {
                                anchors.right: parent.right
                                anchors.rightMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                                width: 20
                                height: 20
                                radius: 10
                                color: isSelected ? "#4CAF50" : "transparent"
                                border.width: isSelected ? 0 : 2
                                border.color: Qt.rgba(1, 1, 1, 0.3)
                                
                                Text {
                                    anchors.centerIn: parent
                                    text: "✓"
                                    font.pixelSize: 14
                                    color: "white"
                                    visible: isSelected
                                }
                            }
                        }
                    }
                }
            }
            
            // MPV Renderer Mode (only shown when libmpv is selected)
            Text {
                text: qsTr("MPV Renderer Mode")
                font.pixelSize: 15
                font.weight: Font.Medium
                color: foregroundColor
                Layout.topMargin: 32
                Layout.bottomMargin: 8
                visible: {
                    var backend = videoPlayerSettings.videoBackend || (videoPlayerSettings.useWMF ? "wmf" : "mediaplayer")
                    return backend === "libmpv"
                }
            }
            
            Rectangle {
                id: rendererModeSelector
                Layout.fillWidth: true
                Layout.preferredHeight: 44
                radius: 12
                color: Qt.rgba(1, 1, 1, 0.08)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.15)
                visible: {
                    var backend = videoPlayerSettings.videoBackend || (videoPlayerSettings.useWMF ? "wmf" : "mediaplayer")
                    return backend === "libmpv"
                }
                
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    
                    Text {
                        text: videoPlayerSettings.mpvRendererMode === "d3d11"
                            ? qsTr("D3D11 (Recommended for Windows)")
                            : qsTr("OpenGL (Legacy)")
                        font.pixelSize: 14
                        color: foregroundColor
                        Layout.fillWidth: true
                    }
                    
                    Image {
                        id: rendererModeChevronIcon
                        source: "qrc:/qlementine/icons/16/navigation/chevron-down.svg"
                        sourceSize: Qt.size(16, 16)
                        visible: false
                    }
                    ColorOverlay {
                        width: 16
                        height: 16
                        source: rendererModeChevronIcon
                        color: foregroundColor
                        opacity: 0.6
                    }
                }
                
                TapHandler {
                    onTapped: rendererModePopup.open()
                }
            }
            
            Text {
                text: {
                    if (videoPlayerSettings.mpvRendererMode === "d3d11") {
                        return qsTr("D3D11 renderer uses native DirectX 11 for rendering. Provides better Windows integration, no white artifacts, proper maximize/snap support, and native HDR. This is the recommended mode for Windows. Requires restart to take effect.")
                    } else {
                        return qsTr("OpenGL renderer uses OpenGL for rendering. May have issues with frameless windows, white artifacts on maximize, and broken Aero Snap on Windows. Use D3D11 mode instead for better Windows compatibility. Requires restart to take effect.")
                    }
                }
                font.pixelSize: 12
                color: foregroundColor
                opacity: 0.7
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
                Layout.topMargin: 8
                visible: {
                    var backend = videoPlayerSettings.videoBackend || (videoPlayerSettings.useWMF ? "wmf" : "mediaplayer")
                    return backend === "libmpv"
                }
            }
            
            Popup {
                id: rendererModePopup
                x: 0
                y: rendererModeSelector.height + 2
                width: rendererModeSelector.width
                height: Math.min(200, rendererModeList.height + 16)
                modal: true
                closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
                parent: rendererModeSelector
                
                background: Rectangle {
                    radius: 12
                    color: Qt.rgba(0.1, 0.1, 0.1, 0.95)
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.15)
                    
                    layer.enabled: true
                    layer.effect: DropShadow {
                        transparentBorder: true
                        horizontalOffset: 0
                        verticalOffset: 4
                        radius: 16
                        samples: 32
                        color: Qt.rgba(0, 0, 0, 0.5)
                    }
                }
                
                contentItem: Column {
                    id: rendererModeList
                    width: rendererModePopup.width
                    spacing: 4
                    padding: 8
                    
                    Repeater {
                        model: [
                            { value: "d3d11", label: qsTr("D3D11 (Recommended for Windows)"), description: qsTr("Native DirectX 11, better Windows integration") },
                            { value: "opengl", label: qsTr("OpenGL (Legacy)"), description: qsTr("OpenGL renderer, may have Windows issues") }
                        ]
                        
                        Rectangle {
                            width: rendererModePopup.width - 16
                            height: 52
                            radius: 8
                            color: rendererModeItemMouseArea.containsMouse ? Qt.rgba(1, 1, 1, 0.1) : "transparent"
                            
                            property bool isSelected: videoPlayerSettings.mpvRendererMode === modelData.value
                            
                            MouseArea {
                                id: rendererModeItemMouseArea
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: {
                                    console.log("[Settings] Changing mpvRendererMode from", videoPlayerSettings.mpvRendererMode, "to", modelData.value)
                                    videoPlayerSettings.mpvRendererMode = modelData.value
                                    console.log("[Settings] mpvRendererMode is now:", videoPlayerSettings.mpvRendererMode)
                                    // Force sync to ensure setting is saved immediately
                                    videoPlayerSettings.sync()
                                    console.log("[Settings] Settings synced to disk")
                                    rendererModePopup.close()
                                }
                            }
                            
                            RowLayout {
                                anchors.left: parent.left
                                anchors.leftMargin: 12
                                anchors.right: parent.right
                                anchors.rightMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 12
                                
                                Column {
                                    Layout.fillWidth: true
                                    spacing: 4
                                    
                                    Text {
                                        text: modelData.label
                                        font.pixelSize: 14
                                        font.weight: isSelected ? Font.Medium : Font.Normal
                                        color: foregroundColor
                                        elide: Text.ElideRight
                                    }
                                    
                                    Text {
                                        text: modelData.description
                                        font.pixelSize: 12
                                        color: foregroundColor
                                        opacity: 0.7
                                        wrapMode: Text.WordWrap
                                        Layout.fillWidth: true
                                    }
                                }
                                
                                Rectangle {
                                    Layout.preferredWidth: 20
                                    Layout.preferredHeight: 20
                                    radius: 10
                                    color: isSelected ? "#4CAF50" : "transparent"
                                    border.width: isSelected ? 0 : 2
                                    border.color: Qt.rgba(1, 1, 1, 0.3)
                                    
                                    Text {
                                        anchors.centerIn: parent
                                        text: "✓"
                                        font.pixelSize: 14
                                        color: "white"
                                        visible: isSelected
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    Component {
        id: audioContent
        
        ColumnLayout {
            spacing: 0
            width: parent.width

        Text {
                text: qsTr("Audio")
                font.pixelSize: 24
                font.weight: Font.Bold
                color: foregroundColor
                Layout.bottomMargin: 8
        }

        Text {
                text: qsTr("Configure audio processing and playback options")
                font.pixelSize: 13
            color: foregroundColor
                opacity: 0.7
                Layout.bottomMargin: 24
        }

            ModernToggle {
                label: qsTr("Beta Audio Processing (Real EQ)")
                description: qsTr("⚠️ BETA: Enables real-time audio equalizer processing. Experimental feature. Requires restart.")
            checked: betaAudioProcessingEnabled
                onToggled: (checked) => betaAudioProcessingToggled(checked)
            }
        }
    }
    
    Component {
        id: translationContent
        
        ColumnLayout {
            spacing: 0
            width: parent.width

        Text {
                text: qsTr("Translation")
                font.pixelSize: 24
                font.weight: Font.Bold
                color: foregroundColor
                Layout.bottomMargin: 8
        }

        Text {
                text: qsTr("Configure lyrics translation settings")
                font.pixelSize: 13
            color: foregroundColor
                opacity: 0.7
                Layout.bottomMargin: 24
        }

            ModernToggle {
                label: qsTr("Enable Lyrics Translation")
                description: qsTr("Automatically translates lyrics to the target language. Translations are cached locally.")
            checked: lyricsTranslationEnabled
                onToggled: (checked) => lyricsTranslationToggled(checked)
        }

        Text {
            text: qsTr("Translation API Key")
                font.pixelSize: 15
                font.weight: Font.Medium
            color: foregroundColor
            opacity: lyricsTranslationEnabled ? 1.0 : 0.5
                Layout.topMargin: 24
                Layout.bottomMargin: 8
        }

        TextField {
            Layout.fillWidth: true
                Layout.preferredHeight: 44
            text: lyricsTranslationApiKey
            placeholderText: qsTr("Enter your RapidAPI key")
            enabled: lyricsTranslationEnabled
            echoMode: TextInput.Password
            onTextChanged: if (lyricsTranslationEnabled) lyricsTranslationApiKeyEdited(text)
                font.pixelSize: 14
                
            background: Rectangle {
                    color: Qt.rgba(1, 1, 1, 0.08)
                    border.color: Qt.rgba(1, 1, 1, 0.15)
                border.width: 1
                    radius: 12
            }
                
                color: foregroundColor
        }

        Text {
                text: qsTr("Get your RapidAPI key at https://rapidapi.com")
                font.pixelSize: 12
                color: foregroundColor
                opacity: lyricsTranslationEnabled ? 0.6 : 0.3
                Layout.topMargin: 8
        }

        Text {
            text: qsTr("Target Language")
                font.pixelSize: 15
                font.weight: Font.Medium
            color: foregroundColor
            opacity: lyricsTranslationEnabled ? 1.0 : 0.5
                Layout.topMargin: 24
                Layout.bottomMargin: 8
        }

        Rectangle {
            id: languageSelector
            Layout.fillWidth: true
                Layout.preferredHeight: 44
                radius: 12
                color: lyricsTranslationEnabled ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(1, 1, 1, 0.04)
            border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.15)
            enabled: lyricsTranslationEnabled
            
            property var languageModel: (function() {
                var languages = [
                    { code: "af", name: "Afrikaans" },
                    { code: "sq", name: "Albanian" },
                    { code: "am", name: "Amharic" },
                    { code: "ar", name: "Arabic" },
                    { code: "hy", name: "Armenian" },
                    { code: "az", name: "Azerbaijani" },
                    { code: "eu", name: "Basque" },
                    { code: "be", name: "Belarusian" },
                    { code: "bn", name: "Bengali" },
                    { code: "bs", name: "Bosnian" },
                    { code: "bg", name: "Bulgarian" },
                    { code: "ca", name: "Catalan" },
                    { code: "zh", name: "Chinese" },
                    { code: "hr", name: "Croatian" },
                    { code: "cs", name: "Czech" },
                    { code: "da", name: "Danish" },
                    { code: "nl", name: "Dutch" },
                { code: "en", name: "English" },
                    { code: "et", name: "Estonian" },
                    { code: "fa", name: "Persian" },
                    { code: "tl", name: "Filipino" },
                    { code: "fi", name: "Finnish" },
                { code: "fr", name: "French" },
                    { code: "gl", name: "Galician" },
                    { code: "ka", name: "Georgian" },
                { code: "de", name: "German" },
                    { code: "el", name: "Greek" },
                    { code: "gu", name: "Gujarati" },
                    { code: "he", name: "Hebrew" },
                    { code: "hi", name: "Hindi" },
                    { code: "hu", name: "Hungarian" },
                    { code: "is", name: "Icelandic" },
                    { code: "id", name: "Indonesian" },
                    { code: "ga", name: "Irish" },
                { code: "it", name: "Italian" },
                { code: "ja", name: "Japanese" },
                    { code: "kn", name: "Kannada" },
                    { code: "kk", name: "Kazakh" },
                    { code: "km", name: "Khmer" },
                { code: "ko", name: "Korean" },
                    { code: "ky", name: "Kyrgyz" },
                    { code: "lo", name: "Lao" },
                    { code: "lv", name: "Latvian" },
                    { code: "lt", name: "Lithuanian" },
                    { code: "mk", name: "Macedonian" },
                    { code: "ms", name: "Malay" },
                    { code: "ml", name: "Malayalam" },
                    { code: "mt", name: "Maltese" },
                    { code: "mn", name: "Mongolian" },
                    { code: "my", name: "Myanmar" },
                    { code: "ne", name: "Nepali" },
                { code: "no", name: "Norwegian" },
                    { code: "pa", name: "Punjabi" },
                    { code: "pl", name: "Polish" },
                    { code: "pt", name: "Portuguese" },
                { code: "ro", name: "Romanian" },
                    { code: "ru", name: "Russian" },
                    { code: "sr", name: "Serbian" },
                    { code: "si", name: "Sinhala" },
                    { code: "sk", name: "Slovak" },
                    { code: "sl", name: "Slovenian" },
                    { code: "es", name: "Spanish" },
                    { code: "sw", name: "Swahili" },
                    { code: "sv", name: "Swedish" },
                    { code: "tg", name: "Tajik" },
                    { code: "ta", name: "Tamil" },
                    { code: "te", name: "Telugu" },
                { code: "th", name: "Thai" },
                    { code: "tr", name: "Turkish" },
                    { code: "uk", name: "Ukrainian" },
                    { code: "ur", name: "Urdu" },
                    { code: "uz", name: "Uzbek" },
                { code: "vi", name: "Vietnamese" },
                    { code: "cy", name: "Welsh" },
                    { code: "xh", name: "Xhosa" },
                    { code: "zu", name: "Zulu" }
                ];
                // Sort alphabetically by name
                languages.sort(function(a, b) {
                    return a.name.localeCompare(b.name);
                });
                return languages;
            })()
            
            property string currentLanguageName: {
                for (let i = 0; i < languageModel.length; i++) {
                    if (languageModel[i].code === lyricsTranslationTargetLanguage) {
                        return languageModel[i].name + " (" + languageModel[i].code + ")"
                    }
                }
                return "English (en)"
            }
            
                RowLayout {
                anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                
                Text {
                        text: parent.parent.currentLanguageName
                    font.pixelSize: 14
                        color: foregroundColor
                        opacity: lyricsTranslationEnabled ? 1.0 : 0.5
                        Layout.fillWidth: true
                }
                    
                    Image {
                        id: langChevron
                        source: "qrc:/qlementine/icons/16/navigation/chevron-down.svg"
                        sourceSize: Qt.size(16, 16)
                        visible: false
                    }
                    ColorOverlay {
                        width: 16
                        height: 16
                        source: langChevron
                        color: foregroundColor
                        opacity: 0.6
                }
            }
            
                TapHandler {
                enabled: lyricsTranslationEnabled
                    onTapped: languagePopup.open()
            }
            
            Popup {
                id: languagePopup
                x: 0
                y: parent.height + 2
                width: parent.width
                    height: Math.min(300, languagePopup.languageModel.length * 44)
                modal: true
                closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
                    parent: languageSelector
                    
                    padding: 0
                    topPadding: 0
                    bottomPadding: 0
                    leftPadding: 0
                    rightPadding: 0
                
                    property var languageModel: parent.languageModel
                
                    // Entrance and exit animations
                    enter: Transition {
                        NumberAnimation { property: "opacity"; from: 0.0; to: 1.0; duration: 200; easing.type: Easing.OutCubic }
                        NumberAnimation { property: "scale"; from: 0.95; to: 1.0; duration: 200; easing.type: Easing.OutCubic }
                    }
                    
                    exit: Transition {
                        NumberAnimation { property: "opacity"; from: 1.0; to: 0.0; duration: 200; easing.type: Easing.InCubic }
                        NumberAnimation { property: "scale"; from: 1.0; to: 0.95; duration: 200; easing.type: Easing.InCubic }
                }
                
                background: Rectangle {
                        color: Qt.rgba(
                            Qt.lighter(accentColor, 1.3).r,
                            Qt.lighter(accentColor, 1.3).g,
                            Qt.lighter(accentColor, 1.3).b,
                            0.98
                        )
                        border.color: Qt.rgba(1, 1, 1, 0.15)
                    border.width: 1
                        radius: 12
                        
                        // Shadow
                        layer.enabled: true
                        layer.effect: DropShadow {
                            transparentBorder: true
                            horizontalOffset: 0
                            verticalOffset: 4
                            radius: 16
                            samples: 32
                            color: Qt.rgba(0, 0, 0, 0.3)
                        }
                }
                
                contentItem: ListView {
                    clip: true
                        width: languagePopup.width
                        height: languagePopup.height
                        anchors.fill: parent
                        model: languagePopup.languageModel
                        ScrollBar.vertical: ScrollBar {
                            policy: ScrollBar.AsNeeded
                        }
                    
                    delegate: Rectangle {
                            width: ListView.view.width
                            height: 44
                            radius: 0
                            topLeftRadius: index === 0 ? 11 : 0
                            topRightRadius: index === 0 ? 11 : 0
                            bottomLeftRadius: index === languagePopup.languageModel.length - 1 ? 11 : 0
                            bottomRightRadius: index === languagePopup.languageModel.length - 1 ? 11 : 0
                            color: langItemHover.hovered ? Qt.rgba(1, 1, 1, 0.12) : "transparent"
                            
                            Behavior on color {
                                ColorAnimation { duration: 150; easing.type: Easing.OutCubic }
                            }
                        
                        Text {
                            anchors.left: parent.left
                                anchors.leftMargin: 16
                                anchors.right: parent.right
                                anchors.rightMargin: 16
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.name + " (" + modelData.code + ")"
                            color: foregroundColor
                            font.pixelSize: 14
                                font.weight: lyricsTranslationTargetLanguage === modelData.code ? Font.Medium : Font.Normal
                                opacity: lyricsTranslationTargetLanguage === modelData.code ? 1.0 : 0.8
                                elide: Text.ElideRight
                            }
                            
                            HoverHandler {
                                id: langItemHover
                            cursorShape: Qt.PointingHandCursor
                            }
                            
                            TapHandler {
                                onTapped: {
                                lyricsTranslationTargetLanguageEdited(modelData.code)
                                languagePopup.close()
                                }
                            }
                            }
                        }
                    }
                }
            }
        }
    
    Component {
        id: generalContent
        
        ColumnLayout {
            spacing: 0
            width: parent.width

        Text {
                text: qsTr("General")
                font.pixelSize: 24
                font.weight: Font.Bold
                color: foregroundColor
                Layout.bottomMargin: 8
            }
            
            Text {
                text: qsTr("General application settings")
                font.pixelSize: 13
                color: foregroundColor
                opacity: 0.7
                Layout.bottomMargin: 24
        }

        Text {
            text: qsTr("App Language")
                font.pixelSize: 15
                font.weight: Font.Medium
            color: foregroundColor
                Layout.topMargin: 20
                Layout.bottomMargin: 8
        }

        Rectangle {
            id: appLanguageSelector
            Layout.fillWidth: true
                Layout.preferredHeight: 44
                radius: 12
                color: Qt.rgba(1, 1, 1, 0.08)
            border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.15)
            
            property var languageModel: [
                { code: "en", name: "English" },
                { code: "ro", name: "Română" }
            ]
            
            property string currentLanguageName: {
                for (let i = 0; i < languageModel.length; i++) {
                    if (languageModel[i].code === appLanguage) {
                        return languageModel[i].name + " (" + languageModel[i].code + ")"
                    }
                }
                return "English (en)"
            }
            
                RowLayout {
                anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                
                Text {
                        text: parent.parent.currentLanguageName
                    font.pixelSize: 14
                        color: foregroundColor
                        Layout.fillWidth: true
                }
                    
                    Image {
                        id: appLangChevron
                        source: "qrc:/qlementine/icons/16/navigation/chevron-down.svg"
                        sourceSize: Qt.size(16, 16)
                        visible: false
                    }
                    ColorOverlay {
                        width: 16
                        height: 16
                        source: appLangChevron
                        color: foregroundColor
                        opacity: 0.6
                }
            }
            
                TapHandler {
                    onTapped: appLanguagePopup.open()
            }
            
            Popup {
                id: appLanguagePopup
                x: 0
                    y: appLanguageSelector.height + 2
                    width: appLanguageSelector.width
                    height: appLanguagePopup.languageModel.length * 44
                modal: true
                closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
                    parent: appLanguageSelector
                    
                    padding: 0
                    topPadding: 0
                    bottomPadding: 0
                    leftPadding: 0
                    rightPadding: 0
                    
                    property var languageModel: appLanguageSelector.languageModel
                    
                    // Entrance and exit animations
                    enter: Transition {
                        NumberAnimation { property: "opacity"; from: 0.0; to: 1.0; duration: 200; easing.type: Easing.OutCubic }
                        NumberAnimation { property: "scale"; from: 0.95; to: 1.0; duration: 200; easing.type: Easing.OutCubic }
                    }
                    
                    exit: Transition {
                        NumberAnimation { property: "opacity"; from: 1.0; to: 0.0; duration: 200; easing.type: Easing.InCubic }
                        NumberAnimation { property: "scale"; from: 1.0; to: 0.95; duration: 200; easing.type: Easing.InCubic }
                }
                
                background: Rectangle {
                        color: Qt.rgba(
                            Qt.lighter(accentColor, 1.3).r,
                            Qt.lighter(accentColor, 1.3).g,
                            Qt.lighter(accentColor, 1.3).b,
                            0.98
                        )
                        border.color: Qt.rgba(1, 1, 1, 0.15)
                    border.width: 1
                        radius: 12
                        
                        // Shadow
                        layer.enabled: true
                        layer.effect: DropShadow {
                            transparentBorder: true
                            horizontalOffset: 0
                            verticalOffset: 4
                            radius: 16
                            samples: 32
                            color: Qt.rgba(0, 0, 0, 0.3)
                        }
                }
                
                    contentItem: Column {
                        spacing: 0
                    clip: true
                        width: appLanguagePopup.width
                        anchors.fill: parent
                        
                        Repeater {
                            model: appLanguagePopup.languageModel
                            
                            Rectangle {
                                width: parent.width
                                height: 44
                                radius: 0
                                topLeftRadius: index === 0 ? 11 : 0
                                topRightRadius: index === 0 ? 11 : 0
                                bottomLeftRadius: index === appLanguagePopup.languageModel.length - 1 ? 11 : 0
                                bottomRightRadius: index === appLanguagePopup.languageModel.length - 1 ? 11 : 0
                                color: appLangItemHover.hovered ? Qt.rgba(1, 1, 1, 0.12) : "transparent"
                                
                                Behavior on color {
                                    ColorAnimation { duration: 150; easing.type: Easing.OutCubic }
                                }
                        
                        Text {
                            anchors.left: parent.left
                                    anchors.leftMargin: 16
                                    anchors.right: parent.right
                                    anchors.rightMargin: 16
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.name + " (" + modelData.code + ")"
                            color: foregroundColor
                            font.pixelSize: 14
                                    font.weight: appLanguage === modelData.code ? Font.Medium : Font.Normal
                                    opacity: appLanguage === modelData.code ? 1.0 : 0.8
                                    elide: Text.ElideRight
                        }
                        
                                HoverHandler {
                                    id: appLangItemHover
                            cursorShape: Qt.PointingHandCursor
                                }
                                
                                TapHandler {
                                    onTapped: {
                                appLanguageEdited(modelData.code)
                                appLanguagePopup.close()
                                    }
                            }
                        }
                    }
                }
            }
        }

            ModernToggle {
                label: qsTr("Enable Debug Console")
                description: qsTr("Show a debug console window with logging information and memory usage. Requires application restart to take effect.")
                checked: debugConsoleEnabled
                onToggled: (checked) => debugConsoleToggled(checked)
                Layout.topMargin: 24
            }

            Text {
                text: qsTr("File Associations")
                font.pixelSize: 15
                font.weight: Font.Medium
                color: foregroundColor
                Layout.topMargin: 32
                Layout.bottomMargin: 8
            }
            
            ModernButton {
                label: qsTr("Set as Default for Images")
                icon: "qrc:/qlementine/icons/16/file/picture.svg"
                primary: true
                onClicked: {
                    if (typeof ColorUtils !== "undefined" && ColorUtils.registerAsDefaultImageViewer) {
                        ColorUtils.registerAsDefaultImageViewer()
                    }
                }
            }
            
            ModernButton {
                label: qsTr("Open Windows Settings")
                icon: "qrc:/qlementine/icons/16/action/external-link.svg"
                Layout.topMargin: 12
                onClicked: {
                    if (typeof ColorUtils !== "undefined" && ColorUtils.openDefaultAppsSettings) {
                        ColorUtils.openDefaultAppsSettings()
                    }
                }
            }
            
            Text {
                text: qsTr("Register the app and open Windows Settings to select S3rpent Media as your default image viewer")
                font.pixelSize: 12
                color: foregroundColor
                opacity: 0.6
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
                Layout.topMargin: 12
            }
        }
    }
    
    Component {
        id: discordContent
        
        ColumnLayout {
            spacing: 0
            width: parent.width

            Text {
                text: qsTr("Discord Rich Presence")
                font.pixelSize: 24
                font.weight: Font.Bold
                color: foregroundColor
                Layout.bottomMargin: 8
            }
            
            Text {
                text: qsTr("Configure Discord Rich Presence settings")
                font.pixelSize: 13
                color: foregroundColor
                opacity: 0.7
                Layout.bottomMargin: 24
            }

            ModernToggle {
                label: qsTr("Enable Discord Rich Presence")
                description: qsTr("Display currently playing track information in Discord. Cover art is automatically fetched from the selected API.")
                checked: discordRPCEnabled
                onToggled: (checked) => discordRPCToggled(checked)
            }
            
            Text {
                text: qsTr("Cover Art Source")
                font.pixelSize: 15
                font.weight: Font.Medium
                color: foregroundColor
                Layout.topMargin: 24
                Layout.bottomMargin: 8
            }
            
            Rectangle {
                id: coverArtSourceSelector
                Layout.fillWidth: true
                Layout.preferredHeight: 44
                radius: 12
                color: Qt.rgba(1, 1, 1, 0.08)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.15)
                
                property var sourceModel: [
                    { value: "coverartarchive", name: qsTr("Cover Art Archive") },
                    { value: "lastfm", name: qsTr("Last.fm") }
                ]
                
                property string currentSourceName: {
                    for (let i = 0; i < sourceModel.length; i++) {
                        if (sourceModel[i].value === coverArtSource) {
                            return sourceModel[i].name
                        }
                    }
                    return "Cover Art Archive"
                }
                
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    
                    Text {
                        text: parent.parent.currentSourceName
                        font.pixelSize: 14
                        color: foregroundColor
                        Layout.fillWidth: true
                    }
                    
                    Image {
                        id: coverArtChevron
                        source: "qrc:/qlementine/icons/16/navigation/chevron-down.svg"
                        sourceSize: Qt.size(16, 16)
                        visible: false
                    }
                    ColorOverlay {
                        width: 16
                        height: 16
                        source: coverArtChevron
                        color: foregroundColor
                        opacity: 0.6
                    }
                }
                
                TapHandler {
                    onTapped: coverArtSourcePopup.open()
                }
                
                Popup {
                    id: coverArtSourcePopup
                    x: 0
                    y: coverArtSourceSelector.height + 2
                    width: coverArtSourceSelector.width
                    height: coverArtSourceSelector.sourceModel.length * 44
                    modal: true
                    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
                    parent: coverArtSourceSelector
                    
                    padding: 0
                    topPadding: 0
                    bottomPadding: 0
                    leftPadding: 0
                    rightPadding: 0
                    
                    property var sourceModel: coverArtSourceSelector.sourceModel
                    
                    enter: Transition {
                        NumberAnimation { property: "opacity"; from: 0.0; to: 1.0; duration: 200; easing.type: Easing.OutCubic }
                        NumberAnimation { property: "scale"; from: 0.95; to: 1.0; duration: 200; easing.type: Easing.OutCubic }
                    }
                    
                    exit: Transition {
                        NumberAnimation { property: "opacity"; from: 1.0; to: 0.0; duration: 200; easing.type: Easing.InCubic }
                        NumberAnimation { property: "scale"; from: 1.0; to: 0.95; duration: 200; easing.type: Easing.InCubic }
                    }
                    
                    background: Rectangle {
                        color: Qt.rgba(
                            Qt.lighter(accentColor, 1.3).r,
                            Qt.lighter(accentColor, 1.3).g,
                            Qt.lighter(accentColor, 1.3).b,
                            0.98
                        )
                        border.color: Qt.rgba(1, 1, 1, 0.15)
                        border.width: 1
                        radius: 12
                        
                        layer.enabled: true
                        layer.effect: DropShadow {
                            transparentBorder: true
                            horizontalOffset: 0
                            verticalOffset: 4
                            radius: 16
                            samples: 32
                            color: Qt.rgba(0, 0, 0, 0.3)
                        }
                    }
                    
                    contentItem: Column {
                        spacing: 0
                        clip: true
                        width: coverArtSourcePopup.width
                        anchors.fill: parent
                        
                        Repeater {
                            model: coverArtSourcePopup.sourceModel
                            
                            Rectangle {
                                width: parent.width
                                height: 44
                                radius: 0
                                topLeftRadius: index === 0 ? 11 : 0
                                topRightRadius: index === 0 ? 11 : 0
                                bottomLeftRadius: index === 1 ? 11 : 0
                                bottomRightRadius: index === 1 ? 11 : 0
                                color: coverArtItemHover.hovered ? Qt.rgba(1, 1, 1, 0.12) : "transparent"
                                
                                Behavior on color {
                                    ColorAnimation { duration: 150; easing.type: Easing.OutCubic }
                                }
                            
                                Text {
                                    anchors.left: parent.left
                                    anchors.leftMargin: 16
                                    anchors.right: parent.right
                                    anchors.rightMargin: 16
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.name
                                    color: foregroundColor
                                    font.pixelSize: 14
                                    font.weight: coverArtSource === modelData.value ? Font.Medium : Font.Normal
                                    opacity: coverArtSource === modelData.value ? 1.0 : 0.8
                                    elide: Text.ElideRight
                                }
                                
                                HoverHandler {
                                    id: coverArtItemHover
                                    cursorShape: Qt.PointingHandCursor
                                }
                                
                                TapHandler {
                                    onTapped: {
                                        coverArtSourceSelected(modelData.value)
                                        coverArtSourcePopup.close()
                                    }
                                }
                            }
                        }
                    }
                }
            }
            
            Text {
                text: qsTr("Select the API to use for fetching album cover art. Cover Art Archive uses MusicBrainz data, while Last.fm provides its own database.")
                font.pixelSize: 12
                color: foregroundColor
                opacity: 0.7
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
                Layout.topMargin: 8
            }
            
            Text {
                text: qsTr("Last.fm API Key")
                font.pixelSize: 15
                font.weight: Font.Medium
                color: foregroundColor
                opacity: coverArtSource === "lastfm" ? 1.0 : 0.5
                Layout.topMargin: 24
                Layout.bottomMargin: 8
            }

            TextField {
                Layout.fillWidth: true
                Layout.preferredHeight: 44
                text: lastFMApiKey
                placeholderText: qsTr("Enter your Last.fm API key (optional)")
                enabled: coverArtSource === "lastfm"
                onTextChanged: if (coverArtSource === "lastfm") lastFMApiKeyEdited(text)
                font.pixelSize: 14
                
                background: Rectangle {
                    color: Qt.rgba(1, 1, 1, 0.08)
                    border.color: Qt.rgba(1, 1, 1, 0.15)
                    border.width: 1
                    radius: 12
                }
                
                color: foregroundColor
            }

            Text {
                text: qsTr("Get your Last.fm API key at https://www.last.fm/api/account/create")
                font.pixelSize: 12
                color: foregroundColor
                opacity: coverArtSource === "lastfm" ? 0.6 : 0.3
                Layout.topMargin: 8
            }
            
            Text {
                text: qsTr("Discord Rich Presence will show:")
                font.pixelSize: 15
                font.weight: Font.Medium
                color: foregroundColor
                Layout.topMargin: 24
                Layout.bottomMargin: 12
            }
            
            ColumnLayout {
                spacing: 8
                Layout.fillWidth: true
                
                RowLayout {
                    spacing: 12
                    Layout.fillWidth: true
                    
                    Rectangle {
                        width: 6
                        height: 6
                        radius: 3
                        color: foregroundColor
                        opacity: 0.7
                    }
                    
                    Text {
                        text: qsTr("Track title and artist name")
                        font.pixelSize: 13
                        color: foregroundColor
                        opacity: 0.8
                        Layout.fillWidth: true
                    }
                }
                
                RowLayout {
                    spacing: 12
                    Layout.fillWidth: true
                    
                    Rectangle {
                        width: 6
                        height: 6
                        radius: 3
                        color: foregroundColor
                        opacity: 0.7
                    }
                    
                    Text {
                        text: qsTr("Playback position and duration")
                        font.pixelSize: 13
                        color: foregroundColor
                        opacity: 0.8
                        Layout.fillWidth: true
                    }
                }
                
                RowLayout {
                    spacing: 12
                    Layout.fillWidth: true
                    
                    Rectangle {
                        width: 6
                        height: 6
                        radius: 3
                        color: foregroundColor
                        opacity: 0.7
                    }
                    
                    Text {
                        text: qsTr("Album cover art (automatically fetched)")
                        font.pixelSize: 13
                        color: foregroundColor
                        opacity: 0.8
                        Layout.fillWidth: true
                    }
                }
                
                RowLayout {
                    spacing: 12
                    Layout.fillWidth: true
                    
                    Rectangle {
                        width: 6
                        height: 6
                        radius: 3
                        color: foregroundColor
                        opacity: 0.7
                    }
                    
                    Text {
                        text: qsTr("Playback state (playing/paused)")
                        font.pixelSize: 13
                        color: foregroundColor
                        opacity: 0.8
                        Layout.fillWidth: true
                    }
                }
            }
        }
    }
    
    // Close on overlay click
    TapHandler {
        function handleTap(point) {
            const globalPos = settingsContainer.mapToItem(settingsPage, 0, 0)
            if (point.position.x < globalPos.x || 
                point.position.x > globalPos.x + settingsContainer.width ||
                point.position.y < globalPos.y || 
                point.position.y > globalPos.y + settingsContainer.height) {
                backClicked()
            }
        }
        onTapped: (eventPoint) => handleTap(eventPoint)
    }
}
