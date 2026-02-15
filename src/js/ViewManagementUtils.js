.pragma library

/**
 * ViewManagementUtils.js
 * Utility functions for view management (zoom, pan, reset, etc.)
 */

/**
 * Adjust zoom level for image viewer
 * @param {number} delta - Zoom delta (positive = zoom in, negative = zoom out)
 * @param {Object} viewerItem - Reference to the image viewer component
 * @param {boolean} hasMedia - Whether there is media loaded
 * @param {boolean} isVideo - Whether current media is video
 * @param {boolean} isAudio - Whether current media is audio
 * @param {boolean} isMarkdown - Whether current media is markdown
 * @param {boolean} isText - Whether current media is text
 * @param {boolean} isPdf - Whether current media is PDF
 * @param {boolean} isZip - Whether current media is ZIP
 * @param {boolean} isModel - Whether current media is 3D model
 * @returns {boolean} True if zoom was adjusted, false otherwise
 */
function adjustZoom(delta, viewerItem, hasMedia, isVideo, isAudio, isMarkdown, isText, isPdf, isZip, isModel) {
    if (!hasMedia || isVideo || isAudio || isMarkdown || isText || isPdf || isZip || isModel) {
        return false
    }
    if (viewerItem && typeof viewerItem.adjustZoom === "function") {
        viewerItem.adjustZoom(delta)
        return true
    }
    return false
}

/**
 * Reset view (zoom and pan) for image viewer
 * @param {Object} viewerItem - Reference to the image viewer component
 * @param {boolean} isVideo - Whether current media is video
 * @param {boolean} isAudio - Whether current media is audio
 * @param {boolean} isMarkdown - Whether current media is markdown
 * @param {boolean} isText - Whether current media is text
 * @param {boolean} isPdf - Whether current media is PDF
 * @param {boolean} isZip - Whether current media is ZIP
 * @param {boolean} isModel - Whether current media is 3D model
 * @returns {boolean} True if view was reset, false otherwise
 */
function resetView(viewerItem, isVideo, isAudio, isMarkdown, isText, isPdf, isZip, isModel) {
    if (isVideo || isAudio || isMarkdown || isText || isPdf || isZip || isModel) {
        return false
    }
    if (viewerItem && typeof viewerItem.resetView === "function") {
        viewerItem.resetView()
        return true
    }
    return false
}

/**
 * Clamp pan values to keep image within bounds
 * @param {Object} viewerItem - Reference to the image viewer component
 * @param {boolean} hasMedia - Whether there is media loaded
 * @param {boolean} isVideo - Whether current media is video
 * @param {boolean} isAudio - Whether current media is audio
 * @param {boolean} isMarkdown - Whether current media is markdown
 * @param {boolean} isText - Whether current media is text
 * @param {boolean} isPdf - Whether current media is PDF
 * @param {boolean} isZip - Whether current media is ZIP
 * @param {boolean} isModel - Whether current media is 3D model
 * @param {Object} window - Window object to set panX/panY to 0 if needed
 * @returns {boolean} True if pan was clamped, false otherwise
 */
function clampPan(viewerItem, hasMedia, isVideo, isAudio, isMarkdown, isText, isPdf, isZip, isModel, window) {
    if (!hasMedia) {
        if (window) {
            window.panX = 0
            window.panY = 0
        }
        return false
    }

    if (isVideo || isMarkdown || isText || isPdf || isZip || isModel) {
        // Videos, markdown, text, PDF, ZIP, and models don't need pan clamping here
        if (window) {
            window.panX = 0
            window.panY = 0
        }
        return false
    } else if (!isAudio) {
        // For images, use the imageViewer component
        if (viewerItem && typeof viewerItem.clampPan === "function") {
            viewerItem.clampPan()
            return true
        }
    }
    return false
}

/**
 * Load a file by setting it as current image
 * @param {url} fileUrl - URL of the file to load
 * @param {Object} window - Window object to set currentImage
 * @returns {boolean} True if file was loaded, false otherwise
 */
function loadFile(fileUrl, window) {
    if (fileUrl && fileUrl !== "" && window) {
        window.currentImage = fileUrl
        return true
    }
    return false
}

