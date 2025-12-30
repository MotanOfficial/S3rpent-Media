import QtQuick

// Spotify-style multi-color gradient background component
Canvas {
    id: gradientCanvas
    
    property color accentColor: "#121216"
    property var paletteColors: []  // Array of colors for gradient
    property bool enabled: true
    
    anchors.fill: parent
    visible: enabled && paletteColors && paletteColors.length > 1
    z: -1  // Background layer
    opacity: 0.9  // More visible
    
    onPaint: {
        var ctx = getContext("2d")
        var w = width
        var h = height
        var maxSize = Math.max(w, h)
        var diagonal = Math.sqrt(w * w + h * h)  // Full diagonal to cover corners
        
        ctx.clearRect(0, 0, w, h)
        
        if (!paletteColors || paletteColors.length === 0) return
        
        // Use the actual accent color (from dominantColor() function) for the center gradient
        // This ensures we use the same logic as the normal dynamic color
        var dominantColor = Qt.color(accentColor)
        // Use minimal brightening to preserve the actual dominant color - just enough for visibility
        var dominantBrightened = Qt.lighter(dominantColor, 1.15)
        
        // Draw dominant color in center with large radius - most prominent
        var centerGradient = ctx.createRadialGradient(w * 0.5, h * 0.5, 0, w * 0.5, h * 0.5, diagonal * 0.7)
        centerGradient.addColorStop(0, Qt.rgba(dominantBrightened.r, dominantBrightened.g, dominantBrightened.b, 0.7))
        centerGradient.addColorStop(0.4, Qt.rgba(dominantBrightened.r, dominantBrightened.g, dominantBrightened.b, 0.5))
        centerGradient.addColorStop(0.7, Qt.rgba(dominantBrightened.r, dominantBrightened.g, dominantBrightened.b, 0.3))
        centerGradient.addColorStop(1, "transparent")
        ctx.fillStyle = centerGradient
        ctx.beginPath()
        ctx.arc(w * 0.5, h * 0.5, diagonal * 0.7, 0, 2 * Math.PI)
        ctx.fill()
        
        // Draw other colors in corners - less prominent
        var cornerPositions = [
            {x: 0, y: 0},           // Top-left corner
            {x: w, y: 0},           // Top-right corner
            {x: 0, y: h},           // Bottom-left corner
            {x: w, y: h}            // Bottom-right corner
        ]
        
        var cornerOpacities = [0.4, 0.4, 0.4, 0.4]  // Lower opacity for accent colors
        var cornerRadii = [diagonal * 0.5, diagonal * 0.5, diagonal * 0.5, diagonal * 0.5]
        
        // Use colors 1-4 for corners (skip 0 which is dominant, already used in center)
        for (var i = 0; i < cornerPositions.length && i + 1 < paletteColors.length; i++) {
            var pos = cornerPositions[i]
            var radius = cornerRadii[i]
            var color = Qt.color(paletteColors[i + 1])  // Skip first color (dominant)
            var brightened = Qt.lighter(color, 1.3)  // Less brightening to preserve actual colors
            
            // Create radial gradient for corner
            var gradient = ctx.createRadialGradient(pos.x, pos.y, 0, pos.x, pos.y, radius)
            gradient.addColorStop(0, Qt.rgba(brightened.r, brightened.g, brightened.b, cornerOpacities[i]))
            gradient.addColorStop(0.3, Qt.rgba(brightened.r, brightened.g, brightened.b, cornerOpacities[i] * 0.6))
            gradient.addColorStop(0.6, Qt.rgba(brightened.r, brightened.g, brightened.b, cornerOpacities[i] * 0.3))
            gradient.addColorStop(0.9, Qt.rgba(brightened.r, brightened.g, brightened.b, cornerOpacities[i] * 0.1))
            gradient.addColorStop(1, "transparent")
            
            ctx.fillStyle = gradient
            ctx.beginPath()
            ctx.arc(pos.x, pos.y, radius, 0, 2 * Math.PI)
            ctx.fill()
        }
    }
    
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onPaletteColorsChanged: {
        if (visible) {
            requestPaint()
        }
    }
    onAccentColorChanged: {
        if (visible) {
            requestPaint()
        }
    }
}

