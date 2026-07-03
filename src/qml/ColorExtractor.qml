import QtQuick

// Component for extracting colors from images and managing dynamic coloring
QtObject {
    id: colorExtractor
    
    // Input properties
    property bool dynamicColoringEnabled: true
    property bool windowsAccentColorEnabled: false
    property bool gradientBackgroundEnabled: true
    property url currentImage: ""
    property bool isAudio: false
    property url audioCoverArt: ""
    property color fallbackAccent: "#121216"
    
    // Output properties (these will be set on the target object)
    property var target: null  // The object to set properties on (e.g., window)
    
    // Helper function to calculate luminance
    function luminance(color) {
        if (!color)
            return 0
        return 0.2126 * color.r + 0.7152 * color.g + 0.0722 * color.b
    }

    function applyForegroundForAccent(accent) {
        if (!target || !accent)
            return
        const lum = luminance(accent)
        target.foregroundColor = lum > 0.65 ? "#050505" : "#f5f5f5"
    }

    function applyWindowsAccent() {
        if (!target || typeof ColorUtils === "undefined" || !ColorUtils.windowsAccentColor)
            return false
        const accent = ColorUtils.windowsAccentColor()
        if (!accent || accent.a === 0)
            return false
        target.accentColor = accent
        applyForegroundForAccent(accent)
        return true
    }

    function mediaImageSource() {
        if (isAudio && audioCoverArt && audioCoverArt !== "")
            return audioCoverArt
        return currentImage
    }
    
    // Reset to fallback colors
    function useFallbackAccent() {
        if (!target) return
        if (windowsAccentColorEnabled && applyWindowsAccent()) {
            target.paletteColors = [target.accentColor]
            return
        }
        target.accentColor = fallbackAccent
        target.foregroundColor = "#f5f5f5"
        target.paletteColors = []
    }
    
    // Main color extraction function
    function updateAccentColor() {
        if (!target) return

        if (windowsAccentColorEnabled) {
            if (!applyWindowsAccent()) {
                useFallbackAccent()
                return
            }
            if (!dynamicColoringEnabled) {
                target.paletteColors = [target.accentColor]
                return
            }
        } else if (!dynamicColoringEnabled) {
            useFallbackAccent()
            return
        }
        
        // For audio files, use cover art if available
        const imageSource = mediaImageSource()
        
        if (!imageSource || imageSource === "") {
            if (windowsAccentColorEnabled)
                target.paletteColors = [target.accentColor]
            else
                useFallbackAccent()
            return
        }
        if (typeof ColorUtils === "undefined" || !ColorUtils.dominantColor) {
            if (windowsAccentColorEnabled)
                target.paletteColors = [target.accentColor]
            else
                useFallbackAccent()
            return
        }
        
        // Extract multiple colors for gradient (Spotify-style)
        if (gradientBackgroundEnabled && typeof ColorUtils.extractPaletteColors === "function") {
            const colors = ColorUtils.extractPaletteColors(imageSource, 5)
            if (colors && colors.length > 0) {
                target.paletteColors = colors
                
                if (!windowsAccentColorEnabled) {
                    // Get dominant color using the same logic as normal dynamic color
                    const dominant = ColorUtils.dominantColor(imageSource)
                    if (dominant && dominant.a > 0) {
                        target.accentColor = dominant
                        applyForegroundForAccent(dominant)
                    } else {
                        // Fallback to first palette color if dominantColor fails
                        var domColor = Qt.color(colors[0])
                        target.accentColor = domColor
                        applyForegroundForAccent(domColor)
                    }
                }
                return
            }
        }
        
        // Fallback to single color extraction
        const sampled = ColorUtils.dominantColor(imageSource)
        if (!sampled || sampled.a === 0) {
            if (windowsAccentColorEnabled)
                target.paletteColors = [target.accentColor]
            else
                useFallbackAccent()
        } else {
            if (!windowsAccentColorEnabled) {
                target.accentColor = sampled
                applyForegroundForAccent(sampled)
            }
            target.paletteColors = windowsAccentColorEnabled ? [target.accentColor] : [sampled]
        }
    }
}

