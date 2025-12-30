.pragma library

// WindowResizeFunctions - Utility functions for window resizing operations

function restoreDefaultWindowSize(params) {
    const { window, isResizing, defaultWidth, defaultHeight, lastResizeWidth, lastResizeHeight, logToDebugConsole, Qt, Window } = params
    
    if (isResizing || window.visibility === Window.Maximized || window.visibility === Window.FullScreen) {
        return
    }
    
    // Set the isResizing flag (caller should handle this)
    params.onResizingChanged(true)
    
    // Restore to default size
    window.width = defaultWidth
    window.height = defaultHeight
    
    // Update last resize dimensions (caller should handle this)
    params.onLastResizeChanged(defaultWidth, defaultHeight)
    
    logToDebugConsole("[Window] Restored to default size: " + defaultWidth + "×" + defaultHeight, "info")
    
    // Reset flag after a short delay
    Qt.callLater(function() {
        params.onResizingChanged(false)
    })
}

function resizeToMediaAspectRatio(params) {
    const { window, matchMediaAspectRatio, currentImage, isResizing, isVideo, isImageType, 
            videoPlayerLoader, viewerLoader, customTitleBar, lastResizeWidth, lastResizeHeight,
            logToDebugConsole, Qt, Screen, Window, WindowResizeUtils } = params
    
    // Don't resize if disabled, no media, already resizing
    if (!matchMediaAspectRatio) {
        return
    }
    if (currentImage === "" || isResizing) {
        return
    }
    
    // Check if window is actually maximized by checking if it takes up the full screen
    // Sometimes visibility can be incorrectly reported, so we also check window size
    const isActuallyMaximized = (window.visibility === Window.Maximized) && 
                                (window.width >= Screen.desktopAvailableWidth * 0.95 && 
                                 window.height >= Screen.desktopAvailableHeight * 0.95)
    const isFullScreen = (window.visibility === Window.FullScreen)
    
    if (isActuallyMaximized || isFullScreen) {
        window.showNormal()
        // Wait a bit for window to restore, then resize
        Qt.callLater(function() {
            resizeToMediaAspectRatio(params)
        }, 100)
        return
    }
    
    // Set the isResizing flag (caller should handle this)
    params.onResizingChanged(true)
    
    const result = WindowResizeUtils.resizeToMediaAspectRatio(
        window, matchMediaAspectRatio, currentImage, false, window.visibility, isVideo, isImageType,
        videoPlayerLoader, viewerLoader, customTitleBar, lastResizeWidth, lastResizeHeight,
        logToDebugConsole, Qt.callLater, Screen
    )
    
    if (result) {
        // Update last resize dimensions (caller should handle this)
        params.onLastResizeChanged(result.newWidth, result.newHeight)
    }
    
    // Reset flag after a short delay to allow window to resize
    Qt.callLater(function() {
        params.onResizingChanged(false)
    })
}

