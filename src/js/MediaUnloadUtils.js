.pragma library

/**
 * MediaUnloadUtils.js
 * Utility functions for unloading media and cleanup operations
 */

/**
 * Unload media and perform cleanup
 * @param {Object} params - Parameters object containing:
 *   - window: Window object with properties to clear
 *   - unloadAllViewers: Function to unload all viewers
 *   - resetView: Function to reset view
 *   - useFallbackAccent: Function to use fallback accent
 *   - logToDebugConsole: Function to log messages
 *   - ColorUtils: ColorUtils object for memory operations
 * @returns {Object} Object with cleanup status
 */
function unloadMedia(params) {
    if (!params || !params.window) {
        return { success: false, error: "Invalid parameters" }
    }
    
    const window = params.window
    const unloadAllViewers = params.unloadAllViewers
    const resetView = params.resetView
    const useFallbackAccent = params.useFallbackAccent
    const logToDebugConsole = params.logToDebugConsole || function(msg, type) { console.log(msg) }
    const ColorUtils = params.ColorUtils
    
    // Track memory before unload
    let memBefore = 0.0
    if (ColorUtils && typeof ColorUtils.getMemoryUsage === "function") {
        memBefore = ColorUtils.getMemoryUsage()
        logToDebugConsole("[Unload] Memory before unload: " + memBefore.toFixed(2) + " MB", "info")
    }
    
    logToDebugConsole("[Unload] Starting media unload...", "info")
    
    // CRITICAL: Clear currentImage FIRST before anything else
    // This ensures all bound components (imageViewer, videoPlayer, audioPlayer) clear immediately
    window.currentImage = ""
    logToDebugConsole("[Unload] Cleared currentImage", "info")
    
    // Unload all viewers via Loaders to ensure proper cleanup
    try {
        if (unloadAllViewers) {
            unloadAllViewers()
            logToDebugConsole("[Unload] All viewers unloaded via Loaders", "info")
        }
    } catch (e) {
        logToDebugConsole("[Unload] ERROR in unloadAllViewers: " + e, "error")
    }
    
    logToDebugConsole("[Unload] Step: About to clear media properties", "info")
    // Clear all other media properties
    if (window.initialImage !== undefined) window.initialImage = ""
    if (window.directoryImages !== undefined) window.directoryImages = []
    if (window.currentImageIndex !== undefined) window.currentImageIndex = 0
    if (window.audioCoverArt !== undefined) window.audioCoverArt = ""
    if (window.audioFormatInfo !== undefined) window.audioFormatInfo = { sampleRate: 0, bitrate: 0 }
    logToDebugConsole("[Unload] Cleared media properties", "info")
    
    logToDebugConsole("[Unload] Step: About to reset view", "info")
    // Reset view
    if (resetView) {
        resetView()
        logToDebugConsole("[Unload] Step: Reset view complete", "info")
    }
    
    logToDebugConsole("[Unload] Step: About to reset accent color", "info")
    // Reset accent color to default (black)
    if (window.accentColor !== undefined) window.accentColor = Qt.rgba(0.07, 0.07, 0.09, 1.0)
    if (window.dynamicColoringEnabled !== undefined) window.dynamicColoringEnabled = true  // Re-enable for next load
    logToDebugConsole("[Unload] Reset accent color to default", "info")
    
    logToDebugConsole("[Unload] Step: About to hide controls", "info")
    // Hide controls
    if (window.showImageControls !== undefined) window.showImageControls = false
    if (window.showingSettings !== undefined) window.showingSettings = false
    if (window.showingMetadata !== undefined) window.showingMetadata = false
    logToDebugConsole("[Unload] Step: Controls hidden", "info")
    
    logToDebugConsole("[Unload] Step: About to clear Qt image cache", "info")
    // Clear Qt's image cache immediately (synchronous)
    try {
        if (ColorUtils && typeof ColorUtils.clearImageCache === "function") {
            ColorUtils.clearImageCache()
            logToDebugConsole("[Unload] Cleared Qt image cache", "info")
        } else {
            logToDebugConsole("[Unload] WARNING: ColorUtils.clearImageCache not available", "warning")
        }
    } catch (e) {
        logToDebugConsole("[Unload] ERROR in clearImageCache: " + e, "error")
    }
    
    logToDebugConsole("[Unload] Step: About to force garbage collection", "info")
    // Force QML garbage collection to release memory immediately
    try {
        if (typeof Qt !== "undefined" && Qt.callLater) {
            // Force GC by processing events and calling GC
            Qt.callLater(function() {
                // Give Qt a moment to process cleanup events
                Qt.callLater(function() {
                    // Now measure memory after GC has had time to run
                    logToDebugConsole("[Unload] Step: About to get memory after unload (after GC)", "info")
                    try {
                        if (ColorUtils && typeof ColorUtils.getMemoryUsage === "function") {
                            const memAfter = ColorUtils.getMemoryUsage()
                            const freed = memBefore - memAfter
                            logToDebugConsole("[Unload] Memory after unload: " + memAfter.toFixed(2) + " MB (freed: " + freed.toFixed(2) + " MB)", "info")
                        } else {
                            logToDebugConsole("[Unload] WARNING: ColorUtils.getMemoryUsage not available", "warning")
                        }
                    } catch (e) {
                        logToDebugConsole("[Unload] ERROR in getMemoryUsage: " + e, "error")
                    }
                }, 100)  // 100ms delay to allow GC to run
            })
        }
    } catch (e) {
        logToDebugConsole("[Unload] ERROR in GC delay: " + e, "error")
    }
    
    // Log memory immediately (before GC) for comparison
    try {
        if (ColorUtils && typeof ColorUtils.getMemoryUsage === "function") {
            const memAfterImmediate = ColorUtils.getMemoryUsage()
            const freedImmediate = memBefore - memAfterImmediate
            logToDebugConsole("[Unload] Memory immediately after unload (before GC): " + memAfterImmediate.toFixed(2) + " MB (freed: " + freedImmediate.toFixed(2) + " MB)", "info")
        }
    } catch (e) {
        // Ignore errors in immediate measurement
    }
    
    logToDebugConsole("[Unload] Media unload complete", "info")
    
    return { success: true, memBefore: memBefore }
}

