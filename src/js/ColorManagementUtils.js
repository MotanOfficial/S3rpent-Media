.pragma library

/**
 * ColorManagementUtils.js
 * Utility functions for color management and accent color extraction
 */

/**
 * Use fallback accent color
 * @param {Object} colorExtractor - Color extractor component
 * @returns {boolean} True if fallback was used
 */
function useFallbackAccent(colorExtractor) {
    if (colorExtractor && typeof colorExtractor.useFallbackAccent === "function") {
        colorExtractor.useFallbackAccent()
        return true
    }
    return false
}

/**
 * Update accent color from current media
 * @param {Object} colorExtractor - Color extractor component
 * @returns {boolean} True if accent color was updated
 */
function updateAccentColor(colorExtractor) {
    if (colorExtractor && typeof colorExtractor.updateAccentColor === "function") {
        colorExtractor.updateAccentColor()
        return true
    }
    return false
}

