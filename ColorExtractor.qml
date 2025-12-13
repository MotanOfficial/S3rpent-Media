import QtQuick

// Component for extracting colors from images and managing dynamic coloring
QtObject {
    id: colorExtractor
    
    // Input properties
    property bool dynamicColoringEnabled: true
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
    
    // Reset to fallback colors
    function useFallbackAccent() {
        if (!target) return
        target.accentColor = fallbackAccent
        target.foregroundColor = "#f5f5f5"
        target.paletteColors = []
    }
    
    // Main color extraction function
    function updateAccentColor() {
        if (!target) return
        
        if (!dynamicColoringEnabled) {
            useFallbackAccent()
            return
        }
        
        // For audio files, use cover art if available
        let imageSource = currentImage
        if (isAudio && audioCoverArt && audioCoverArt !== "") {
            imageSource = audioCoverArt
        }
        
        if (!imageSource || imageSource === "") {
            useFallbackAccent()
            return
        }
        if (typeof ColorUtils === "undefined" || !ColorUtils.dominantColor) {
            useFallbackAccent()
            return
        }
        
        // Extract multiple colors for gradient (Spotify-style)
        if (gradientBackgroundEnabled && typeof ColorUtils.extractPaletteColors === "function") {
            const colors = ColorUtils.extractPaletteColors(imageSource, 5)
            if (colors && colors.length > 0) {
                target.paletteColors = colors
                
                // Get dominant color using the same logic as normal dynamic color
                const dominant = ColorUtils.dominantColor(imageSource)
                if (dominant && dominant.a > 0) {
                    target.accentColor = dominant
                    const lum = luminance(dominant)
                    target.foregroundColor = lum > 0.65 ? "#050505" : "#f5f5f5"
                } else {
                    // Fallback to first palette color if dominantColor fails
                    var domColor = Qt.color(colors[0])
                    target.accentColor = domColor
                    const lum = luminance(domColor)
                    target.foregroundColor = lum > 0.65 ? "#050505" : "#f5f5f5"
                }
                return
            }
        }
        
        // Fallback to single color extraction
        const sampled = ColorUtils.dominantColor(imageSource)
        if (!sampled || sampled.a === 0) {
            useFallbackAccent()
        } else {
            target.accentColor = sampled
            target.paletteColors = [sampled]  // Single color as fallback
            const lum = luminance(sampled)
            target.foregroundColor = lum > 0.65 ? "#050505" : "#f5f5f5"
        }
    }
}


