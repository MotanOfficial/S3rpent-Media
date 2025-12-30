.pragma library

/**
 * AudioUtils.js
 * Utility functions for audio processing and metadata extraction
 */

/**
 * Extract cover art from audio file
 * @param {url} audioUrl - URL of the audio file
 * @param {function} extractCoverArt - Function to extract cover art (from ColorUtils)
 * @returns {url} URL of the extracted cover art, or empty string if not found
 */
function extractAudioCoverArt(audioUrl, extractCoverArt) {
    if (!audioUrl || audioUrl === "" || !extractCoverArt) {
        return ""
    }
    
    try {
        const coverArtUrl = extractCoverArt(audioUrl)
        return (coverArtUrl && coverArtUrl !== "") ? coverArtUrl : ""
    } catch (e) {
        console.log("[AudioUtils] Error extracting cover art:", e)
        return ""
    }
}

/**
 * Get audio format information (sample rate, bitrate)
 * @param {url} audioUrl - URL of the audio file
 * @param {number} durationMs - Duration of the audio in milliseconds
 * @param {function} getAudioFormatInfo - Function to get format info (from ColorUtils)
 * @param {Object} existingInfo - Existing format info to merge with
 * @returns {Object} Object with sampleRate and bitrate properties
 */
function getAudioFormatInfo(audioUrl, durationMs, getAudioFormatInfo, existingInfo) {
    if (!audioUrl || audioUrl === "" || !getAudioFormatInfo) {
        return { sampleRate: 0, bitrate: 0 }
    }
    
    // If duration not provided, use 0 (will still get sample rate)
    if (durationMs === undefined || durationMs === null) {
        durationMs = 0
    }
    
    try {
        const formatInfo = getAudioFormatInfo(audioUrl, durationMs)
        if (formatInfo) {
            // Merge with existing info to preserve values
            return {
                sampleRate: formatInfo.sampleRate || (existingInfo ? existingInfo.sampleRate : 0) || 0,
                bitrate: formatInfo.bitrate || (existingInfo ? existingInfo.bitrate : 0) || 0
            }
        } else {
            // Return existing info or default
            return existingInfo || { sampleRate: 0, bitrate: 0 }
        }
    } catch (e) {
        console.log("[AudioUtils] Error getting format info:", e)
        return existingInfo || { sampleRate: 0, bitrate: 0 }
    }
}

