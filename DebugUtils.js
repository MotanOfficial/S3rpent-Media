.pragma library

/**
 * DebugUtils.js
 * Utility functions for debug logging and performance tracking
 */

/**
 * Log a message to both console and debug console
 * @param {string} message - Message to log
 * @param {string} type - Log type (info, warning, error, etc.)
 * @param {Object} debugConsole - Reference to debug console object
 */
function logToDebugConsole(message, type, debugConsole) {
    // Always log to regular console first
    console.log(message)
    
    // Try to log to debug console if available
    if (debugConsole) {
        try {
            if (typeof debugConsole.addLog === "function") {
                debugConsole.addLog(message, type || "info")
            } else {
                console.log("[Debug] debugConsole.addLog not available")
            }
        } catch (e) {
            console.log("[Debug] Error logging to console:", e)
        }
    } else {
        console.log("[Debug] debugConsole is null")
    }
}

/**
 * Start a load timer for performance tracking
 * @param {string} typeLabel - Type of media being loaded (e.g., "Image", "Video")
 * @param {url} currentImage - Current image/media URL
 * @returns {Object} Object with loadStartTime, pendingLoadSource, and pendingLoadType
 */
function startLoadTimer(typeLabel, currentImage) {
    if (!currentImage || currentImage === "") {
        return {
            loadStartTime: 0,
            pendingLoadSource: "",
            pendingLoadType: ""
        }
    }
    
    const loadStartTime = Date.now()
    const pendingLoadSource = currentImage
    const pendingLoadType = typeLabel || "Unknown"
    const message = "[Load] Started " + pendingLoadType + " for " + decodeURIComponent(currentImage.toString())
    
    return {
        loadStartTime: loadStartTime,
        pendingLoadSource: pendingLoadSource,
        pendingLoadType: pendingLoadType,
        message: message
    }
}

/**
 * Log the duration of a load operation
 * @param {string} statusLabel - Status label (e.g., "Image ready", "Video ready")
 * @param {url} sourceUrl - Source URL that was loaded
 * @param {Object} loadTimerData - Object from startLoadTimer with loadStartTime, pendingLoadSource, pendingLoadType
 * @param {function} logToDebugConsole - Function to log to debug console
 * @returns {Object} Updated load timer data (with cleared values)
 */
function logLoadDuration(statusLabel, sourceUrl, loadTimerData, logToDebugConsole) {
    if (!loadTimerData || !loadTimerData.loadStartTime) {
        return loadTimerData || { loadStartTime: 0, pendingLoadSource: "", pendingLoadType: "" }
    }
    
    const targetUrl = sourceUrl || loadTimerData.pendingLoadSource
    if (loadTimerData.pendingLoadSource && loadTimerData.pendingLoadSource !== "" && targetUrl && targetUrl !== "" &&
            loadTimerData.pendingLoadSource.toString() !== targetUrl.toString()) {
        // Source changed, don't log
        return loadTimerData
    }
    
    const elapsed = Date.now() - loadTimerData.loadStartTime
    const message = "[Load] " + statusLabel + " in " + elapsed + " ms (" + loadTimerData.pendingLoadType + ")"
    
    if (logToDebugConsole) {
        logToDebugConsole(message, "info")
    } else {
        console.log(message)
    }
    
    // Return cleared timer data
    return {
        loadStartTime: 0,
        pendingLoadSource: "",
        pendingLoadType: ""
    }
}

