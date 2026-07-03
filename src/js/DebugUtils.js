.pragma library

/**
 * DebugUtils.js
 * Utility functions for debug logging and performance tracking
 */

function safeUrlString(url) {
    if (!url || url === "")
        return ""
    const s = url.toString()
    try {
        return decodeURIComponent(s)
    } catch (e) {
        return s
    }
}

function fileBasename(urlOrString) {
    const s = safeUrlString(urlOrString)
    if (!s)
        return ""
    const norm = s.replace(/\\/g, "/")
    const parts = norm.split("/")
    return parts[parts.length - 1] || norm
}

/**
 * Log a message to both console and debug console
 * @param {string} message - Message to log
 * @param {string} type - Log type (info, warning, error, etc.)
 * @param {Object} debugConsole - Reference to debug console object
 */
function logToDebugConsole(message, type, debugConsole) {
    // Keep console quiet when debug console is disabled.
    // Only forward messages if a debug console is actually connected.
    if (debugConsole) {
        try {
            if (typeof debugConsole.addLog === "function") {
                debugConsole.addLog(message, type || "info")
            }
        } catch (e) {
            // Ignore logging failures in production paths.
        }
    }
}

/**
 * Start a load timer for performance tracking
 * @param {string} typeLabel - Type of media being loaded (e.g., "Image", "Video")
 * @param {url} currentImage - Current image/media URL
 * @param {function} logToDebugConsoleFn - Optional (message, type) for in-app debug console
 * @returns {Object} Object with loadStartTime, pendingLoadSource, and pendingLoadType
 */
function startLoadTimer(typeLabel, currentImage, logToDebugConsoleFn, consoleEnabled) {
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
    const name = fileBasename(currentImage)
    const message = "[Load] Started " + pendingLoadType + (name ? " - " + name : "")
    
    if (consoleEnabled) {
        console.log(message)
    }
    if (typeof logToDebugConsoleFn === "function") {
        logToDebugConsoleFn(message, "info")
    }
    
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
 * @param {function} logToDebugConsoleFn - Optional (message, type) for in-app debug console
 * @returns {Object} Updated load timer data (with cleared values)
 */
function logLoadDuration(statusLabel, sourceUrl, loadTimerData, logToDebugConsoleFn, consoleEnabled) {
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
    const name = fileBasename(targetUrl)
    const message = "[Load] " + statusLabel + " in " + elapsed + " ms (" + loadTimerData.pendingLoadType + ")"
            + (name ? " - " + name : "")
    
    if (consoleEnabled) {
        console.log(message)
    }
    if (typeof logToDebugConsoleFn === "function") {
        logToDebugConsoleFn(message, "info")
    }
    
    // Return cleared timer data
    return {
        loadStartTime: 0,
        pendingLoadSource: "",
        pendingLoadType: ""
    }
}

