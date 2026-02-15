.pragma library

// WindowLifecycleUtils - Utility functions for window lifecycle management
// These functions contain the logic that was previously in Main.qml's lifecycle handlers

function handleWindowClosing(window, isMainWindow, currentImage, unloadMedia) {
    if (isMainWindow) {
        // Main window: minimize to tray
        // Prevent close FIRST - this is critical
        return {
            accepted: false,
            wasHiddenWithMedia: (currentImage !== ""),
            hideWindow: true,
            unloadAfterHide: true
        }
    } else {
        // Secondary window: WINDOW POOLING - hide instead of destroy
        // Prevent close - we want to hide, not destroy (window pooling)
        return {
            accepted: false,
            wasHiddenWithMedia: false,
            hideWindow: true,
            unloadBeforeHide: true
        }
    }
}

function handleWindowVisibleChanged(visible, wasHiddenWithMedia, unloadMedia) {
    if (visible && wasHiddenWithMedia) {
        // Window is being shown after being hidden with media
        // Clear any residual media immediately
        unloadMedia()
        return false  // Clear wasHiddenWithMedia flag
    }
    return wasHiddenWithMedia  // Keep current value
}

function handleComponentDestruction(isMainWindow, window, unloadAllViewers) {
    if (!isMainWindow) {
        // Final cleanup before destruction - clear all references
        window._isUnloading = true
        window.currentImage = ""
        window.initialImage = ""
        window.directoryImages = []
        window.currentImageIndex = 0
        window.audioCoverArt = ""
        window.audioFormatInfo = { sampleRate: 0, bitrate: 0 }
        
        // Clear all media components
        unloadAllViewers()
        
        // Clear Qt image cache one more time
        if (typeof ColorUtils !== "undefined" && ColorUtils.clearImageCache) {
            ColorUtils.clearImageCache()
        }
    }
}

function handleComponentCompleted(initialImage, window, logToDebugConsole, updateAccentColor, callLater) {
    // Test logging to verify debug console is working
    console.log("[App] Application started - Component.onCompleted")
    if (typeof logToDebugConsole === "function") {
        logToDebugConsole("[App] Application started", "info")
    }
    
    // Check debug console connection (it might be set later by main.cpp)
    if (typeof callLater === "function") {
        callLater(function() {
            if (window.debugConsole && typeof logToDebugConsole === "function") {
                logToDebugConsole("[App] Debug console connected", "info")
            } else {
                console.log("[App] WARNING: Debug console not connected yet (will be set by main.cpp)")
                // Try again after a short delay
                if (typeof callLater === "function") {
                    callLater(function() {
                        if (window.debugConsole && typeof logToDebugConsole === "function") {
                            logToDebugConsole("[App] Debug console connected (delayed)", "info")
                        } else {
                            console.log("[App] ERROR: Debug console still not connected")
                        }
                    }, 100)
                }
            }
        })
    }
    
    // CRITICAL: Do NOT load from initialImage here - loading happens ONLY via onCurrentImageChanged
    // This ensures windows can be reused properly (Component.onCompleted only runs once)
    // If initialImage was set, it will be copied to currentImage by C++ after window creation
    if (initialImage !== "") {
        // Only set currentImage if initialImage was provided (for first-time creation)
        // This triggers onCurrentImageChanged which handles the actual loading
        window.currentImage = initialImage
    } else {
        if (typeof updateAccentColor === "function") {
            updateAccentColor()
        }
    }
}

function resetForReuse(window, unloadAllViewers, logToDebugConsole) {
    if (typeof logToDebugConsole === "function") {
        logToDebugConsole("[QML] resetForReuse() called - resetting window state", "info")
    }
    
    // CRITICAL: Set unloading flag to prevent onCurrentImageChanged from loading
    // when C++ sets currentImage to empty (which happens before setting new image)
    window._isUnloading = true
    
    // CRITICAL: Unload all viewers via Loaders to destroy components
    // This ensures proper cleanup and allows recreation on next load
    unloadAllViewers()
    
    // Clear unloading flag AFTER unload is complete - next image load will work
    // This flag will be cleared when the new image is set (onCurrentImageChanged will handle it)
    
    // Reset media type flags
    window.isVideo = false
    window.isGif = false
    window.isAudio = false
    window.isMarkdown = false
    window.isText = false
    window.isPdf = false
    window.isZip = false
    window.isModel = false
    
    // Clear media properties
    window.directoryImages = []
    window.currentImageIndex = 0
    window.audioCoverArt = ""
    window.audioFormatInfo = { sampleRate: 0, bitrate: 0 }
    
    if (typeof logToDebugConsole === "function") {
        logToDebugConsole("[QML] resetForReuse() complete - window ready for new image", "info")
    }
}

