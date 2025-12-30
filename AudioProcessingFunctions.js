.pragma library

// AudioProcessingFunctions - Utility functions for audio processing (cover art extraction, format info)

function extractAudioCoverArt(params) {
    const { isAudio, currentImage, updateAccentColor, AudioUtils, ColorUtils, Qt, onCoverArtExtracted } = params
    
    if (!isAudio || !currentImage || currentImage === "") {
        if (onCoverArtExtracted) {
            onCoverArtExtracted("")
        }
        return
    }
    
    // Use C++ helper to extract cover art - call asynchronously to avoid blocking UI
    // Defer color extraction to after cover art is ready (non-blocking)
    if (typeof ColorUtils !== "undefined" && ColorUtils.extractCoverArt) {
        Qt.callLater(function() {
            const coverArtUrl = AudioUtils.extractAudioCoverArt(currentImage, ColorUtils.extractCoverArt)
            if (coverArtUrl && coverArtUrl !== "") {
                // Call the callback to set the cover art
                if (onCoverArtExtracted) {
                    onCoverArtExtracted(coverArtUrl)
                }
                // Update accent color from cover art (also deferred, non-blocking)
                Qt.callLater(function() {
                    if (updateAccentColor) {
                        updateAccentColor()
                    }
                })
            } else {
                if (onCoverArtExtracted) {
                    onCoverArtExtracted("")
                }
            }
        })
    } else {
        if (onCoverArtExtracted) {
            onCoverArtExtracted("")
        }
    }
}

function getAudioFormatInfo(params) {
    const { isAudio, currentImage, audioFormatInfo, audioPlayerLoader, showingMetadata, metadataPopup, getMetadataList, ColorUtils, AudioUtils, Qt } = params
    
    if (!isAudio || !currentImage || currentImage === "") {
        return { sampleRate: 0, bitrate: 0 }
    }
    
    // If duration not provided, try to get it from audioPlayer
    let durationMs = params.durationMs
    if (durationMs === undefined || durationMs === 0) {
        if (audioPlayerLoader && audioPlayerLoader.item && audioPlayerLoader.item.duration > 0) {
            durationMs = audioPlayerLoader.item.duration
        } else {
            // Still get sample rate even without duration (bitrate will be 0)
            durationMs = 0
        }
    }
    
    // Use C++ helper to get audio format info directly from the media file
    if (typeof ColorUtils !== "undefined" && ColorUtils.getAudioFormatInfo) {
        const formatInfo = AudioUtils.getAudioFormatInfo(currentImage, durationMs, ColorUtils.getAudioFormatInfo, audioFormatInfo)
        
        // Refresh metadata if popup is open
        if (showingMetadata && getMetadataList) {
            Qt.callLater(function() {
                if (metadataPopup) {
                    metadataPopup.metadataList = getMetadataList()
                }
            })
        }
        
        return formatInfo
    } else {
        return { sampleRate: 0, bitrate: 0 }
    }
}

