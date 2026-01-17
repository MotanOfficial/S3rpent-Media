import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtMultimedia

// Undertale-style fight page
// Easter egg: creates an Undertale battle interface
Item {
    id: undertaleFight
    
    property bool enabled: false
    property var appWindow: null  // Reference to main window for fullscreen
    property var titleBar: null  // Reference to titlebar to disable auto-hide
    
    // Fixed virtual resolution (Undertale-style: 640×480)
    property int virtualWidth: 640
    property int virtualHeight: 480
    
    // Fight phases (state-driven like Undertale)
    property string fightState: "dialogue"  // "dialogue", "targetSelect", "attackBar", "attack", "enemyTurn"
    
    // Menu navigation (0 = FIGHT, 1 = ACT, 2 = ITEM, 3 = MERCY)
    property int menuIndex: 0
    
    // Enemy data model
    property var enemies: [
        {
            name: "Napstablook",
            maxHp: 88,
            hp: 88
        }
    ]
    
    property int selectedEnemy: 0
    
    // Attack bar state variables
    property real attackCursorX: 0
    property bool attackMoving: false
    property bool attackStopped: false
    property int flashCount: 0  // Track flash animation frame count
    
    // Transition animation state properties
    property real transitionProgress: 0.0  // 0.0 to 1.0 during transition
    property bool inTransitionToAttack: false  // True during transition animation
    property bool soulReady: false  // True when soul has been positioned correctly and may be shown
    
    // Hit slash animation state
    property bool hitActive: false  // True when hit slash animation is playing
    property int hitFrame: 1  // Current frame of hit slash (1-6)
    
    // Dialogue typing system (Undertale-accurate)
    property string fullDialogueText: ""
    property string visibleDialogueText: ""
    property int dialogueIndex: 0
    property bool isTyping: false
    property bool soundFlip: false  // Alternates between two sound effects to prevent clipping
    
    anchors.fill: parent
    visible: enabled
    focus: enabled  // Enable keyboard focus when visible
    z: 10000  // High z-order to be on top of everything
    
    // Audio output for fight music (Qt 6 requirement)
    AudioOutput {
        id: musicOutput
        volume: 0.8
    }
    
    // Fight music (Qt 6 uses MediaPlayer with separate AudioOutput)
    MediaPlayer {
        id: fightMusic
        audioOutput: musicOutput
        loops: MediaPlayer.Infinite
        // Source will be set in startFight() using QRC path
    }
    
    // Text typing sound effect (low latency, Undertale-accurate)
    // Use two alternating SoundEffects to prevent clipping/overlap issues
    SoundEffect {
        id: textSound
        source: {
            if (typeof ColorUtils !== "undefined") {
                const appDir = ColorUtils.getAppDirectory()
                const normalizedDir = appDir.replace(/\\/g, "/")
                return "file:///" + normalizedDir + "/sprites/audio/SND_TXT2.wav"
            }
            return ""
        }
        volume: 0.6
    }
    
    // Alternate sound effect to prevent clipping when characters type rapidly
    SoundEffect {
        id: textSoundAlt
        source: textSound.source
        volume: 0.6
    }
    
    // Hit slash sound effect (plays when attack hits enemy)
    SoundEffect {
        id: hitSlashSound
        source: {
            if (typeof ColorUtils !== "undefined") {
                const appDir = ColorUtils.getAppDirectory()
                const normalizedDir = appDir.replace(/\\/g, "/")
                return "file:///" + normalizedDir + "/sprites/audio/snd_laz.wav"
            }
            return ""
        }
        volume: 0.8
    }
    
    // Dialogue typing timer (Undertale-accurate: ~30 chars/sec, longer pause on newlines)
    Timer {
        id: dialogueTimer
        interval: 33  // Default: ~30 chars/sec (Undertale-accurate)
        repeat: true
        running: isTyping
        
        onTriggered: {
            if (dialogueIndex >= fullDialogueText.length) {
                isTyping = false
                stop()
                return
            }
            
            const ch = fullDialogueText.charAt(dialogueIndex)
            visibleDialogueText += ch
            dialogueIndex++
            
            // Play sound only for visible characters (not spaces, newlines, or punctuation)
            // Undertale does not play sound for: spaces, newlines, . , ! ?
            if (!/[ \n.,!?]/.test(ch)) {
                // Alternate between two sound effects to prevent clipping
                (soundFlip ? textSound : textSoundAlt).play()
                soundFlip = !soundFlip
            }
            
            // Adjust speed for newline (Undertale pauses slightly longer on line breaks)
            if (ch === "\n") {
                interval = 120  // Slight pause on newline (~120ms)
            } else {
                interval = 33   // Normal character speed (~33ms)
            }
        }
    }
    
    // Attack bar movement timer (moves cursor across the bar)
    Timer {
        id: attackMoveTimer
        interval: 16  // ~60 FPS for smooth movement
        repeat: true
        running: fightState === "attackBar" && attackMoving && !attackStopped
        
        onTriggered: {
            attackCursorX += 6  // Move cursor 6 pixels per frame
            
            // MISS - cursor went off screen (check if cursor X exceeds bar width by cursor width)
            // Attack bar has fixed width of 575px
            const cursorWidth = attackCursor.implicitWidth > 0 ? attackCursor.implicitWidth : 16  // Fallback to 16px
            if (attackCursorX > 575 - cursorWidth) {
                stop()
                attackMoving = false
                showMiss()
            }
        }
    }
    
    // Attack cursor flash timer (for hit confirmation animation)
    Timer {
        id: flashTimer
        interval: 80  // Flash speed (Undertale-accurate)
        repeat: true
        running: false
        
        onTriggered: {
            if (attackCursor) {
                // Alternate between flash frame and normal frame
                if (flashCount % 2 === 0) {
                    attackCursor.cursorSprite = "attackbar_2.png"  // Flash frame
                } else {
                    attackCursor.cursorSprite = "attackbar_1.png"  // Normal frame
                }
            }
            
            flashCount++
            if (flashCount >= 6) {
                stop()
                flashCount = 0
                attackCursor.cursorSprite = "attackbar_1.png"  // Reset to normal
                resolveAttack()
            }
        }
    }
    
    // Miss popup timer (auto-hide after 1 second)
    Timer {
        id: missPopupTimer
        interval: 1000
        running: false
        repeat: false
        onTriggered: {
            missPopup.visible = false
        }
    }
    
    // Hit slash frame timer (advances through 6 frames of slash animation)
    Timer {
        id: hitFrameTimer
        interval: 92  // ~92ms per frame (6 frames × 92ms = 552ms, close to 551ms)
        repeat: true
        running: false
        
        onTriggered: {
            hitFrame++
            if (hitFrame > 6) {
                stop()
                startHitFadeOut()
            }
        }
    }
    
    // Hit slash fade-out animation (fades out after animation completes)
    NumberAnimation {
        id: hitFade
        target: hitSlash
        property: "opacity"
        from: 1.0
        to: 0.0
        duration: 200  // Fade out over 200ms
        
        onFinished: {
            hitActive = false
            hitSlash.opacity = 1.0  // Reset opacity for next hit
        }
    }
    
    // Transition animation from attack bar to fight phase (Undertale-accurate)
    PropertyAnimation {
        id: transitionAnimation
        target: undertaleFight
        property: "transitionProgress"
        from: 0
        to: 1
        duration: 800  // Even slower transition timing (smooth, Undertale-accurate)
        easing.type: Easing.InOutQuad  // Smooth ease in/out
        
        onStarted: {
            inTransitionToAttack = true
            transitionProgress = 0
            soulReady = false  // Hide soul during transition until positioned correctly
        }
        
        onFinished: {
            inTransitionToAttack = false
            fightState = "attack"
            
            // Re-center soul in the NEW (narrow) box after transition completes
            // This ensures the heart is perfectly centered in the 165px box, not the old 575px box
            // IMPORTANT: Position must be set BEFORE allowing visibility (prevents teleport artifact)
            if (soul && battleBox) {
                soul.posX = battleBox.borderThickness + battleBox.collisionPadding + 
                            (battleBox.playableWidth - soul.width) / 2
                soul.posY = battleBox.borderThickness + battleBox.collisionPadding + 
                            (battleBox.playableHeight - soul.height) / 2
            }
            
            soulReady = true  // NOW the soul may appear (position is correct)
        }
    }
    
    // Block all mouse input to underlying elements
    MouseArea {
        anchors.fill: parent
        enabled: undertaleFight.enabled
        acceptedButtons: Qt.AllButtons
        hoverEnabled: true
        // Accept all events to prevent them from reaching underlying elements
        onPressed: (mouse) => {
            mouse.accepted = true
        }
        onClicked: (mouse) => {
            mouse.accepted = true
        }
        onDoubleClicked: (mouse) => {
            mouse.accepted = true
        }
    }
    
    // Completely black background
    Rectangle {
        anchors.fill: parent
        color: "#000000"
    }
    
    // Undertale fight UI (scaled, fixed resolution)
    Item {
        id: scaler
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        
        // Integer scale factor (Undertale-style: only integer scaling)
        property int scaleFactor: Math.max(1, Math.floor(
            Math.min(
                parent.width / virtualWidth,
                parent.height / virtualHeight
            )
        ))
        
        // Adjust vertical position based on screen size
        // At 640×480, minimal offset; at fullscreen, move content lower significantly
        anchors.verticalCenterOffset: {
            // Calculate offset in actual screen pixels (parent coordinate system)
            // The offset needs to be more dramatic for fullscreen
            const heightRatio = parent.height / virtualHeight  // How many times larger than 480px
            const scaleFactor = Math.floor(Math.min(parent.width / virtualWidth, heightRatio))
            
            // Base offset at 640×480: minimal (0-10px)
            // At fullscreen (scaleFactor 2+): moderate offset (proportional to scale)
            if (scaleFactor <= 1) {
                return 10  // Small offset at base resolution
            } else {
                // For fullscreen, offset increases moderately
                // At 2x scale: ~80px, at 3x scale: ~120px, etc.
                return 40 * scaleFactor  // Moderate offset for fullscreen
            }
        }
        
        // Scaler size is virtual size - the Scale transform handles the scaling
        width: virtualWidth
        height: virtualHeight
        
        // Ensure pixel-perfect scaling (nearest-neighbor, no blur)
        // Scale from center so it stays centered
        transform: Scale {
            origin.x: virtualWidth / 2
            origin.y: virtualHeight / 2
            xScale: scaler.scaleFactor
            yScale: scaler.scaleFactor
        }
        
        // Disable filtering (nearest-neighbor)
        layer.enabled: true
        layer.smooth: false
        
        // The actual game canvas (fixed 640×480)
        Item {
            id: gameCanvas
            anchors.fill: parent  // Fill the scaler (which is virtualWidth × virtualHeight)
            width: virtualWidth
            height: virtualHeight
        
            // Napstablook sprite (idle animation at 5 FPS)
            // Positioned "on" the dialogue/fight box (overlapping, not above) - uses virtual pixel size
            // CRITICAL: Size in virtual pixels (640×480 space), NOT native image pixels
            // The scaler will handle integer scaling automatically
            Image {
                id: napstablook
                smooth: false
                mipmap: false
                fillMode: Image.PreserveAspectFit
                
                // Undertale-accurate virtual size (virtual pixels, not screen pixels)
                // Native sprite is 52×78, but Undertale displays it at 104×156 at base resolution (2x scale)
                // The scaler's Scale transform will automatically scale this further (2x at fullscreen = 208×312)
                width: 104  // Virtual pixels (640×480 space) - 2x the native sprite size
                height: 156  // Virtual pixels (640×480 space) - 2x the native sprite size
                
                anchors.horizontalCenter: gameCanvas.horizontalCenter
                // Position ghost "on" the box (overlapping the top edge, not above it)
                // Both dialogue and fight boxes are at same position
                y: {
                    // Box is at verticalCenter (240) + 40 offset = 280 center
                    // Box top: 280 - (box height/2) = 280 - 70 = 210
                    // Ghost should overlap the box (sit on top of it, not above it)
                    const boxCenter = 240 + 40  // 280
                    const boxTop = boxCenter - 70  // 210
                    // Use height property (virtual pixels) directly
                    // Move down 10px from previous position
                    return boxTop - height + 5 + 15  // Overlap by 5px + 5px down = 10px overlap
                }
                
                property int frame: 0
                
                source: {
                    if (typeof ColorUtils !== "undefined") {
                        const appDir = ColorUtils.getAppDirectory()
                        const normalizedDir = appDir.replace(/\\/g, "/")
                        return "file:///" + normalizedDir + "/sprites/napstablook_" + (frame + 1) + ".png"
                    }
                    return ""
                }
                
                visible: undertaleFight.enabled
                
                // Idle animation timer (5 FPS)
                Timer {
                    interval: 200  // 5 FPS (1000ms / 5 = 200ms)
                    running: undertaleFight.enabled
                    repeat: true
                    onTriggered: {
                        napstablook.frame = (napstablook.frame + 1) % 2
                    }
                }
            }
            
            // Hit slash animation (plays when attack hits enemy)
            // Positioned slightly above center of enemy, 6-frame animation, then fades out
            Image {
                id: hitSlash
                visible: hitActive
                opacity: 1.0  // Opacity is animated by hitFade NumberAnimation
                
                width: 52  // Double size: 26 × 2 = 52 virtual pixels
                height: 200  // Double size: 100 × 2 = 200 virtual pixels
                
                smooth: false
                mipmap: false
                
                // Position slash on enemy (Napstablook) - slightly higher than center
                anchors.horizontalCenter: napstablook.horizontalCenter
                anchors.verticalCenter: napstablook.verticalCenter
                anchors.verticalCenterOffset: -25  // Move up by 25 pixels (positioned a little higher than center)
                
                source: {
                    if (!hitActive) return ""
                    if (typeof ColorUtils !== "undefined") {
                        const appDir = ColorUtils.getAppDirectory()
                        const normalizedDir = appDir.replace(/\\/g, "/")
                        return "file:///" + normalizedDir + "/sprites/hit_" + hitFrame + ".png"
                    }
                    return ""
                }
            }
            
            // Shared battle box frame (ONE box that resizes - Undertale-accurate)
            // This is the ONLY rectangle that handles width animation
            // Visible during all fight phases (dialogue, targetSelect, attackBar, attack, transition)
            Rectangle {
                id: battleBox
                visible: fightState === "dialogue" || fightState === "targetSelect" || 
                         fightState === "attackBar" || fightState === "attack" || inTransitionToAttack
                anchors.horizontalCenter: gameCanvas.horizontalCenter
                anchors.verticalCenter: gameCanvas.verticalCenter
                anchors.verticalCenterOffset: 40
                
                height: 140
                width: {
                    // Transition state must override fightState (check first!)
                    if (inTransitionToAttack) {
                        // Animate from dialogue width (575) → fight width (165) during transition
                        return 575 - (575 - 165) * transitionProgress
                    }
                    if (fightState === "attack") {
                        return 165  // Narrow for attack phase
                    }
                    // dialogue / targetSelect / attackBar (all wide)
                    return 575
                }
                
                color: "#000000"
                border.color: "#ffffff"
                border.width: 5
                
                // Border thickness (used for collision calculations)
                property int borderThickness: border.width  // Always 5 pixels
                property int collisionPadding: 0
                
                // Calculate the inner playable area (size minus borders and padding)
                property int playableWidth: width - (2 * borderThickness) - (2 * collisionPadding)
                property int playableHeight: height - (2 * borderThickness) - (2 * collisionPadding)
            }
            
            // Dialogue text (visible during dialogue phase)
            // Positioned inside battleBox, no border (battleBox provides the frame)
            Item {
                id: dialogueBox
                visible: fightState === "dialogue"
                width: battleBox.width
                height: battleBox.height
                anchors.centerIn: battleBox
                
                Text {
                    id: dialogueText
                    text: visibleDialogueText  // Use visible text from typing system
                    wrapMode: Text.WordWrap
                    width: parent.width - 40
                    renderType: Text.NativeRendering
                    antialiasing: false
                    
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.margins: 20
                    
                    color: "#ffffff"
                    font.pixelSize: 26
                    font.family: {
                        // Try Determination Mono (loaded globally via QRC), fallback to monospace
                        const fontFamilies = ["Determination Mono", "DTM-Mono", "DTM Mono"]
                        for (let i = 0; i < fontFamilies.length; i++) {
                            if (Qt.fontFamilies().indexOf(fontFamilies[i]) !== -1) {
                                return fontFamilies[i]
                            }
                        }
                        return "monospace"
                    }
                }
            }
            
            // Enemy target selector (visible during targetSelect phase)
            // Positioned inside battleBox, no border (battleBox provides the frame)
            Item {
                id: enemySelect
                visible: fightState === "targetSelect"
                width: battleBox.width
                height: battleBox.height
                anchors.centerIn: battleBox
                
                // Enemy name
                Text {
                    text: enemies.length > selectedEnemy ? enemies[selectedEnemy].name : ""
                    x: 40
                    y: 30
                    font.pixelSize: 26
                    color: "#ffffff"
                    renderType: Text.NativeRendering
                    antialiasing: false
                    font.family: dialogueText.font.family
                }
                
                // HP bar background (red)
                Rectangle {
                    x: 40
                    y: 70
                    width: 200
                    height: 12
                    color: "#ff0000"
                }
                
                // HP bar foreground (green)
                Rectangle {
                    x: 40
                    y: 70
                    height: 12
                    width: {
                        if (enemies.length > selectedEnemy && enemies[selectedEnemy].maxHp > 0) {
                            return 200 * (enemies[selectedEnemy].hp / enemies[selectedEnemy].maxHp)
                        }
                        return 0
                    }
                    color: "#00ff00"
                }
                
                // Selector heart
                Image {
                    source: {
                        if (typeof ColorUtils !== "undefined") {
                            const appDir = ColorUtils.getAppDirectory()
                            const normalizedDir = appDir.replace(/\\/g, "/")
                            return "file:///" + normalizedDir + "/sprites/heart.png"
                        }
                        return ""
                    }
                    width: 16
                    height: 16
                    smooth: false
                    mipmap: false
                    x: 16
                    y: 32
                }
            }
            
            // Attack bar contents (visible during attackBar phase, fades out during transition)
            // Positioned inside battleBox, NO border/background (battleBox provides the frame)
            // Fades AND scales with box (Undertale-accurate - shrinks with the box frame)
            Item {
                id: attackBar
                visible: fightState === "attackBar" || inTransitionToAttack
                opacity: inTransitionToAttack ? (1.0 - transitionProgress) : 1.0
                width: 575  // Fixed logical width - cursor math stays in 575px space
                height: 140
                anchors.centerIn: battleBox
                
                // Scale transform: visually shrink with box, but keep logical space for cursor math
                // This is Undertale-accurate - attack bar graphic shrinks WITH the box
                transform: Scale {
                    origin.x: attackBar.width / 2
                    origin.y: attackBar.height / 2
                    xScale: inTransitionToAttack ? battleBox.width / 575 : 1.0
                    yScale: 1.0  // Only scale horizontally (width), not height
                }
                
                // Attack bar background image
                Image {
                    id: attackBarBg
                    source: {
                        if (typeof ColorUtils !== "undefined") {
                            const appDir = ColorUtils.getAppDirectory()
                            const normalizedDir = appDir.replace(/\\/g, "/")
                            return "file:///" + normalizedDir + "/sprites/attackbar.png"
                        }
                        return ""
                    }
                    anchors.centerIn: parent
                    smooth: false
                    mipmap: false
                }
                
                // Attack cursor (moving indicator) - source updates during flash animation
                Image {
                    id: attackCursor
                    property string cursorSprite: "attackbar_1.png"  // Default sprite, updates during flash
                    source: {
                        if (typeof ColorUtils !== "undefined") {
                            const appDir = ColorUtils.getAppDirectory()
                            const normalizedDir = appDir.replace(/\\/g, "/")
                            return "file:///" + normalizedDir + "/sprites/" + cursorSprite
                        }
                        return ""
                    }
                    smooth: false
                    mipmap: false
                    y: parent.height / 2 - height / 2
                    x: attackCursorX
                }
            }
            
            // Miss popup (shown when attack misses)
            Image {
                id: missPopup
                visible: false
                source: {
                    if (typeof ColorUtils !== "undefined") {
                        const appDir = ColorUtils.getAppDirectory()
                        const normalizedDir = appDir.replace(/\\/g, "/")
                        return "file:///" + normalizedDir + "/sprites/miss.png"
                    }
                    return ""
                }
                smooth: false
                mipmap: false
                anchors.horizontalCenter: napstablook.horizontalCenter
                y: napstablook.y - 20
            }
            
            // Soul (red heart sprite) - visible during attack phase, fades in during transition
            // Positioned inside battleBox (reuses the same frame)
            // Fade-in is delayed until near the end of transition (Undertale-accurate)
            // Visibility is gated on soulReady to prevent appearing before correct position is set
            Image {
                id: soul
                visible: soulReady  // Only visible when positioned correctly (prevents teleport artifact)
                opacity: {
                    if (!soulReady) return 0.0  // Invisible until ready
                    if (!inTransitionToAttack) return 1.0
                    // Delay fade-in until ~65% of transition (heart appears near end of shrink)
                    // This matches Undertale timing - heart fades in only after box has shrunk enough
                    const t = Math.max(0, transitionProgress - 0.65) / 0.35
                    return Math.min(1.0, t)
                }
                parent: battleBox  // Parent to battleBox for proper positioning
                source: {
                        // Load from sprites folder in app directory
                        if (typeof ColorUtils !== "undefined") {
                            const appDir = ColorUtils.getAppDirectory()
                            const normalizedDir = appDir.replace(/\\/g, "/")
                            return "file:///" + normalizedDir + "/sprites/heart.png"
                        }
                        // Fallback (shouldn't happen, but just in case)
                        return ""
                    }
                    smooth: false  // Nearest-neighbor (no blur)
                    mipmap: false  // No mipmaps (pixel-perfect)
                    width: 16
                    height: 16
                    
                    // TRUE position (float, never rounded - maintains sub-pixel precision)
                    property real posX: 0
                    property real posY: 0
                    
                    // Rendered position (rounded for pixel-perfect display only)
                    x: Math.round(posX)
                    y: Math.round(posY)
                    
                    // Movement speed: 120 pixels per second (Undertale-accurate)
                    // Undertale runs at 30 FPS with ~4 px/frame = 120 px/sec
                    property real speed: 120  // pixels per second
                    
                    // Clamp position to stay within playable area (inside the border)
                    // Works with float positions - no rounding here!
                    function clampPosition() {
                        const minX = battleBox.borderThickness + battleBox.collisionPadding
                        const maxX = battleBox.borderThickness + battleBox.collisionPadding + battleBox.playableWidth - width
                        const minY = battleBox.borderThickness + battleBox.collisionPadding
                        const maxY = battleBox.borderThickness + battleBox.collisionPadding + battleBox.playableHeight - height
                        
                        posX = Math.max(minX, Math.min(maxX, posX))
                        posY = Math.max(minY, Math.min(maxY, posY))
                    }
                }
            
        }
        
        // Status bar row - positioned under the dialogue/fighting rectangle
        // Layout: Left side has player name + level aligned with FIGHT button, center has HP info
        // Positioned below whichever box is visible (both boxes are at same position, just different widths)
        // Box bottom: 280 (center) + 70 (half height) = 350, status bar at 350 + 12 = 362
        Item {
            id: statusBar
            anchors.left: gameCanvas.left
            anchors.right: gameCanvas.right
            anchors.top: gameCanvas.top
            anchors.topMargin: {
                // Box is at verticalCenter (240) + 40 offset = 280 center
                // Box bottom: 280 + (box height/2) = 280 + 70 = 350
                // Status bar top: 350 + 12 (margin) = 362
                return 362
            }
            height: 24
            
            // Player name and level - positioned on the left, aligned with FIGHT button
            // Hardcoded: centered buttons are ~455px wide, so left edge is (width - 455) / 2 from left
            // For 640px width: (640 - 455) / 2 = 92.5px from left
            Text {
                id: playerNameLevel
                text: "MOTAN LV 1"
                renderType: Text.NativeRendering
                antialiasing: false
                font.family: {
                    // Try to find the Mars_Needs_Cunnilingus font (note: one 'n' in Cunnilingus)
                    const fontFamilies = ["Mars_Needs_Cunnilingus", "Mars Needs Cunnilingus", "MarsNeedsCunnilingus", "Mars Needs Cunninilingus"]
                    for (let i = 0; i < fontFamilies.length; i++) {
                        if (Qt.fontFamilies().indexOf(fontFamilies[i]) !== -1) {
                            return fontFamilies[i]
                        }
                    }
                    return "monospace"  // Fallback
                }
                font.pixelSize: 24
                color: "#ffffff"
                verticalAlignment: Text.AlignVCenter
                anchors.horizontalCenter: statusBar.horizontalCenter
                anchors.horizontalCenterOffset: -227.5  // Half of button row width (455/2) = 227.5px left from center
                height: parent.height
            }
            
            // HP info section - centered horizontally
            Row {
                id: hpSection
                anchors.horizontalCenter: statusBar.horizontalCenter
                spacing: 8
                height: parent.height
                
                // "HP" text
                Text {
                    id: hpLabel
                    text: "HP"
                    renderType: Text.NativeRendering
                    antialiasing: false
                    font.family: {
                        // Use UT HP Font for HP text only
                        const fontFamilies = ["UT HP Font", "UTHPFont", "UT-HP-Font", "ut-hp-font"]
                        for (let i = 0; i < fontFamilies.length; i++) {
                            if (Qt.fontFamilies().indexOf(fontFamilies[i]) !== -1) {
                                return fontFamilies[i]
                            }
                        }
                        return "monospace"
                    }
                    font.pixelSize: 10  // Smaller HP text
                    color: "#ffffff"
                    verticalAlignment: Text.AlignVCenter
                    height: parent.height
                }
                
                // Yellow health bar rectangle (slightly taller and wider)
                Rectangle {
                    id: healthBar
                    width: 22  // Slightly wider
                    height: 20  // Taller to center with text perfectly
                    color: "#ffff00"  // Yellow
                    y: (parent.height - height) / 2  // Center vertically within parent
                }
                
                // HP numbers "20 / 20"
                Text {
                    id: hpText
                    text: "20 / 20"
                    renderType: Text.NativeRendering
                    antialiasing: false
                    font.family: {
                        // Try to find the Mars_Needs_Cunnilingus font (note: one 'n' in Cunnilingus)
                        const fontFamilies = ["Mars_Needs_Cunnilingus", "Mars Needs Cunnilingus", "MarsNeedsCunnilingus", "Mars Needs Cunninilingus"]
                        for (let i = 0; i < fontFamilies.length; i++) {
                            if (Qt.fontFamilies().indexOf(fontFamilies[i]) !== -1) {
                                return fontFamilies[i]
                            }
                        }
                        return "monospace"
                    }
                    font.pixelSize: 24  // Bigger HP numbers
                    color: "#ffffff"
                    verticalAlignment: Text.AlignVCenter
                    height: parent.height
                }
            }
        }
        
        // Action buttons row (FIGHT, ACT, ITEM, MERCY) - positioned under status bar
        Row {
            id: actionButtons
            anchors.horizontalCenter: gameCanvas.horizontalCenter
            anchors.top: statusBar.bottom
            anchors.topMargin: 12  // Same distance as status bar from rectangle
            spacing: 45
            
            // FIGHT button (with highlight support)
            Image {
                id: fightButton
                source: {
                    if (typeof ColorUtils !== "undefined") {
                        const appDir = ColorUtils.getAppDirectory()
                        const normalizedDir = appDir.replace(/\\/g, "/")
                        const name = (menuIndex === 0 && fightState === "dialogue")
                            ? "fightbuttonhighlight.png"
                            : "fightbutton.png"
                        return "file:///" + normalizedDir + "/sprites/" + name
                    }
                    return ""
                }
                smooth: false  // Nearest-neighbor (no blur)
                mipmap: false  // No mipmaps (pixel-perfect)
            }
            
            // ACT button (with highlight support)
            Image {
                id: actButton
                source: {
                    if (typeof ColorUtils !== "undefined") {
                        const appDir = ColorUtils.getAppDirectory()
                        const normalizedDir = appDir.replace(/\\/g, "/")
                        const name = (menuIndex === 1 && fightState === "dialogue")
                            ? "actbuttonhighlight.png"
                            : "actbutton.png"
                        return "file:///" + normalizedDir + "/sprites/" + name
                    }
                    return ""
                }
                smooth: false  // Nearest-neighbor (no blur)
                mipmap: false  // No mipmaps (pixel-perfect)
            }
            
            // ITEM button (with highlight support)
            Image {
                id: itemButton
                source: {
                    if (typeof ColorUtils !== "undefined") {
                        const appDir = ColorUtils.getAppDirectory()
                        const normalizedDir = appDir.replace(/\\/g, "/")
                        const name = (menuIndex === 2 && fightState === "dialogue")
                            ? "itembuttonhighlight.png"
                            : "itembutton.png"
                        return "file:///" + normalizedDir + "/sprites/" + name
                    }
                    return ""
                }
                smooth: false  // Nearest-neighbor (no blur)
                mipmap: false  // No mipmaps (pixel-perfect)
            }
            
            // MERCY button (with highlight support)
            Image {
                id: mercyButton
                source: {
                    if (typeof ColorUtils !== "undefined") {
                        const appDir = ColorUtils.getAppDirectory()
                        const normalizedDir = appDir.replace(/\\/g, "/")
                        const name = (menuIndex === 3 && fightState === "dialogue")
                            ? "mercybuttonhighlight.png"
                            : "mercybutton.png"
                        return "file:///" + normalizedDir + "/sprites/" + name
                    }
                    return ""
                }
                smooth: false  // Nearest-neighbor (no blur)
                mipmap: false  // No mipmaps (pixel-perfect)
            }
        }
        
        // Menu heart selector (visible during dialogue/menu phase)
        // Positioned relative to action buttons (they're siblings of gameCanvas)
        Image {
            id: menuHeart
            visible: fightState === "dialogue"
            source: {
                if (typeof ColorUtils !== "undefined") {
                    const appDir = ColorUtils.getAppDirectory()
                    const normalizedDir = appDir.replace(/\\/g, "/")
                    return "file:///" + normalizedDir + "/sprites/heart.png"
                }
                return ""
            }
            smooth: false
            mipmap: false
            width: 16
            height: 16
            
            // Position inside the selected button (centered vertically, on the left side)
            // Don't use anchors for dynamic positioning - calculate y and x directly
            y: {
                if (actionButtons.children.length > menuIndex) {
                    const btn = actionButtons.children[menuIndex]
                    if (btn) {
                        // Center vertically within the button
                        return actionButtons.y + btn.y + (btn.height - height) / 2
                    }
                }
                return actionButtons.y + (actionButtons.height - height) / 2  // Fallback
            }
            
            // Calculate x position to be inside the selected button (on the left side, with padding)
            x: {
                if (actionButtons.children.length > menuIndex) {
                    const btn = actionButtons.children[menuIndex]
                    if (btn) {
                        // Position inside the button, on the left side (with some padding from left edge)
                        // The heart should be inside the button, not to the left of it
                        // Button images might have padding, so position about 8-10px from left edge of button
                        return actionButtons.x + btn.x + 10  // Inside button, 10px from left edge
                    }
                }
                return actionButtons.x + 10  // Fallback to first button position
            }
        }
    }
    
    // Key state tracking (real-time input, not event-based)
    property bool keyLeft: false
    property bool keyRight: false
    property bool keyUp: false
    property bool keyDown: false
    
    // Keyboard input: handle menu navigation and movement
    Keys.onPressed: (event) => {
        if (!enabled || event.isAutoRepeat) return
        
        // Block input during transition animation (Undertale ignores input during transitions)
        if (inTransitionToAttack) {
            event.accepted = true
            return
        }
        
        // Menu navigation (dialogue phase)
        if (fightState === "dialogue") {
            switch (event.key) {
            case Qt.Key_Left:
                // Only allow navigation when not typing
                if (!isTyping) {
                    menuIndex = (menuIndex + 3) % 4  // Wrap around (0→3, 3→2, etc.)
                }
                event.accepted = true
                return
            case Qt.Key_Right:
                // Only allow navigation when not typing
                if (!isTyping) {
                    menuIndex = (menuIndex + 1) % 4  // Wrap around (0→1, 3→0, etc.)
                }
                event.accepted = true
                return
            case Qt.Key_Z:
            case Qt.Key_Return:
            case Qt.Key_Enter:
                if (isTyping) {
                    // Instantly finish the line (Undertale skip-on-confirm)
                    visibleDialogueText = fullDialogueText
                    dialogueIndex = fullDialogueText.length
                    isTyping = false
                    dialogueTimer.stop()
                    // Return early to prevent sound spam and state fallthrough
                    event.accepted = true
                    return
                } else {
                    // Dialogue finished → allow menu interaction
                    if (menuIndex === 0) {
                        // FIGHT selected - switch to enemy target selector
                        fightState = "targetSelect"
                    }
                    // TODO: Handle ACT, ITEM, MERCY
                }
                event.accepted = true
                return
            }
        }
        
        // Enemy target selection (targetSelect phase)
        if (fightState === "targetSelect") {
            if (event.key === Qt.Key_Z || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                // Confirm enemy selection - start attack bar
                fightState = "attackBar"
                startAttackBar()
                event.accepted = true
                return
            }
            // TODO: Handle Left/Right to select between multiple enemies (if more than 1)
        }
        
        // Attack bar phase (stop bar on key press)
        if (fightState === "attackBar" && !attackStopped) {
            if (event.key === Qt.Key_Z || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                attackStopped = true
                attackMoveTimer.stop()
                flashAttackCursor()
                event.accepted = true
                return
            }
        }
        
        // Movement input (attack phase only)
        if (fightState === "attack") {
            switch (event.key) {
            case Qt.Key_Left:
            case Qt.Key_A:
                keyLeft = true
                break
            case Qt.Key_Right:
            case Qt.Key_D:
                keyRight = true
                break
            case Qt.Key_Up:
            case Qt.Key_W:
                keyUp = true
                break
            case Qt.Key_Down:
            case Qt.Key_S:
                keyDown = true
                break
            }
        }
        
        event.accepted = true
    }
    
    Keys.onReleased: (event) => {
        if (!enabled || event.isAutoRepeat) return
        
        // Only handle movement keys in attack phase
        if (fightState === "attack") {
            switch (event.key) {
            case Qt.Key_Left:
            case Qt.Key_A:
                keyLeft = false
                break
            case Qt.Key_Right:
            case Qt.Key_D:
                keyRight = false
                break
            case Qt.Key_Up:
            case Qt.Key_W:
                keyUp = false
                break
            case Qt.Key_Down:
            case Qt.Key_S:
                keyDown = false
                break
            }
        }
        
        event.accepted = true
    }
    
    // Delta-time tracking for frame-rate independent movement
    property double lastTime: 0
    
    // Frame-based movement timer with delta-time (Undertale-style: time-based movement)
    // Only runs during attack phase
    Timer {
        id: movementTimer
        interval: 1  // Fire as fast as possible (1ms minimum in QML)
        running: enabled && fightState === "attack"
        repeat: true
        onTriggered: {
            if (!enabled || fightState !== "attack") return
            
            // Calculate delta time (time since last frame in seconds)
            const now = Date.now()
            if (lastTime === 0) {
                lastTime = now
                return
            }
            
            const delta = (now - lastTime) / 1000.0  // Convert milliseconds to seconds
            lastTime = now
            
            // Skip if delta is too large (prevents jumps on lag spikes)
            if (delta > 0.1) {
                lastTime = now
                return
            }
            
            // Calculate movement direction based on key states
            let dx = 0
            let dy = 0
            
            if (keyLeft)  dx -= 1
            if (keyRight) dx += 1
            if (keyUp)    dy -= 1
            if (keyDown)  dy += 1
            
            // Normalize diagonal movement (prevents faster diagonal speed)
            // Uses exact value: 1/sqrt(2) = 0.70710678
            if (dx !== 0 && dy !== 0) {
                const length = Math.sqrt(dx * dx + dy * dy)
                dx /= length
                dy /= length
            }
            
            // Apply movement scaled by speed and delta time
            // Use float positions (posX/posY) - never round during movement!
            // This ensures both straight and diagonal movement are the same speed
            soul.posX += dx * soul.speed * delta
            soul.posY += dy * soul.speed * delta
            
            // Clamp to stay within playable area (works with floats, no rounding)
            soul.clampPosition()
        }
    }
    
    // Function to start the fight
    // Helper function to start dialogue typing (Undertale-accurate)
    function startDialogue(text) {
        fullDialogueText = text
        visibleDialogueText = ""
        dialogueIndex = 0
        isTyping = true
        soundFlip = false  // Reset sound flip state for new dialogue
        dialogueTimer.interval = 33  // Reset to default interval
        dialogueTimer.restart()
    }
    
    // Function to start the attack bar phase
    function startAttackBar() {
        attackCursorX = 0
        attackStopped = false
        attackMoving = true
        flashCount = 0  // Reset flash counter
        // Reset cursor to default sprite
        if (attackCursor) {
            attackCursor.cursorSprite = "attackbar_1.png"
        }
        attackMoveTimer.restart()
    }
    
    // Function to flash the attack cursor after stopping
    function flashAttackCursor() {
        if (!attackCursor) return
        flashCount = 0  // Reset flash counter
        flashTimer.start()  // Start flashing animation
    }
    
    // Function to play hit slash animation (6-frame animation on enemy)
    function playHitSlash() {
        hitActive = true
        hitFrame = 1
        hitSlash.opacity = 1.0
        hitSlashSound.play()  // Play hit slash sound effect
        hitFrameTimer.start()
    }
    
    // Function to start hit slash fade-out (called after 6 frames complete)
    function startHitFadeOut() {
        hitFade.start()
    }
    
    // Function to resolve attack damage calculation
    function resolveAttack() {
        if (!attackBar || enemies.length <= selectedEnemy) return
        
        const center = 575 / 2  // Attack bar fixed width (575px)
        const dist = Math.abs(attackCursorX - center)
        const dmg = Math.max(1, Math.round(20 - dist / 8))
        
        // Apply damage
        enemies[selectedEnemy].hp = Math.max(0, enemies[selectedEnemy].hp - dmg)
        
        // Play hit slash animation (visual feedback on enemy)
        // This runs simultaneously with the transition (does not block it)
        playHitSlash()
        
        // TODO: Show damage number popup
        
        // Start smooth transition animation to attack phase (Undertale-accurate)
        // Animation will fade out attack bar, shrink box, fade in heart
        // fightState will be set to "attack" after animation completes
        // Hit slash animation runs on top of this (exact Undertale behavior)
        transitionAnimation.start()
    }
    
    // Function to show miss popup
    function showMiss() {
        missPopup.visible = true
        missPopupTimer.start()  // Auto-hide after 1 second
        
        // Start smooth transition animation to attack phase (Undertale-accurate)
        // Animation will fade out attack bar, shrink box, fade in heart
        // fightState will be set to "attack" after animation completes
        transitionAnimation.start()
    }
    
    function startFight() {
        enabled = true
        // Reset fight state to dialogue
        fightState = "dialogue"
        menuIndex = 0
        // Reset transition state
        soulReady = false  // Soul not ready until positioned correctly
        inTransitionToAttack = false
        transitionProgress = 0
        // Reset hit animation state
        hitActive = false
        hitFrame = 1
        // Reset delta-time tracking
        lastTime = 0
        // Reset key states
        keyLeft = false
        keyRight = false
        keyUp = false
        keyDown = false
        // Reset soul position to center of playable area (accounting for border and padding)
        // Initialize float positions (no rounding - sub-pixel precision maintained)
        if (soul && battleBox) {
            soul.posX = battleBox.borderThickness + battleBox.collisionPadding + (battleBox.playableWidth - soul.width) / 2
            soul.posY = battleBox.borderThickness + battleBox.collisionPadding + (battleBox.playableHeight - soul.height) / 2
            // Visual position (x/y) will be rounded automatically via binding
        }
        // Disable titlebar auto-hide when fight is active
        if (titleBar) {
            titleBar.autoHideEnabled = false
            titleBar.titleBarVisible = false  // Force hide titlebar
        } else if (appWindow && appWindow.customTitleBar) {
            appWindow.customTitleBar.autoHideEnabled = false
            appWindow.customTitleBar.titleBarVisible = false  // Force hide titlebar
        }
        // Make window fullscreen
        if (appWindow) {
            appWindow.showFullScreen()
        }
        // Start fight music
        // Audio file is in sprites/audio/ folder (copied to build directory by CMake, see CMakeLists.txt line 819-830)
        if (typeof ColorUtils !== "undefined") {
            const appDir = ColorUtils.getAppDirectory()
            const normalizedDir = appDir.replace(/\\/g, "/")
            fightMusic.source = "file:///" + normalizedDir + "/sprites/audio/napstablook.ogg"
            fightMusic.play()
        }
        // Request focus for keyboard input
        forceActiveFocus()
        // Ensure timer starts
        if (!movementTimer.running) {
            movementTimer.start()
        }
        // Debug scale factor
        if (scaler) {
            console.log("[UndertaleFight] Scale factor:", scaler.scaleFactor, "Canvas size:", virtualWidth + "×" + virtualHeight)
        }
        console.log("[UndertaleFight] Fight started! Timer running:", movementTimer.running)
        // Start dialogue typing
        startDialogue("* Here comes Napstablook.")
    }
    
    // Function to stop the fight
    function stopFight() {
        enabled = false
        // Stop fight music
        fightMusic.stop()
        // Reset fight state
        fightState = "dialogue"
        menuIndex = 0
        // Reset delta-time tracking
        lastTime = 0
        // Reset key states
        keyLeft = false
        keyRight = false
        keyUp = false
        keyDown = false
        // Re-enable titlebar auto-hide when fight ends
        if (titleBar) {
            titleBar.autoHideEnabled = appWindow ? appWindow.autoHideTitleBar : true
        } else if (appWindow && appWindow.customTitleBar) {
            appWindow.customTitleBar.autoHideEnabled = appWindow.autoHideTitleBar
        }
        // Exit fullscreen
        if (appWindow) {
            appWindow.showNormal()
        }
        console.log("[UndertaleFight] Fight stopped!")
    }
}
