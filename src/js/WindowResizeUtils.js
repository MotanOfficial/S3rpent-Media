.pragma library

// WindowResizeUtils - Utility functions for window resizing and aspect ratio management

function getScreenDimensions(window, Screen) {
    // Get the current screen that the window is on (not the total desktop across all monitors)
    // Try multiple methods to get the correct screen dimensions
    let screenAvailableWidth = Screen.desktopAvailableWidth
    let screenAvailableHeight = Screen.desktopAvailableHeight
    
    // Method 1: Try window.screen directly (most reliable)
    if (window.screen) {
        const screenGeo = window.screen.availableGeometry
        if (screenGeo && screenGeo.width > 0 && screenGeo.height > 0 && screenGeo.width < Screen.desktopAvailableWidth) {
            // Only use if it's smaller than desktop width (indicates individual monitor)
            screenAvailableWidth = screenGeo.width
            screenAvailableHeight = screenGeo.height
        } else {
            // Try geometry as fallback
            const screenGeo2 = window.screen.geometry
            if (screenGeo2 && screenGeo2.width > 0 && screenGeo2.height > 0 && screenGeo2.width < Screen.desktopAvailableWidth) {
                screenAvailableWidth = screenGeo2.width
                screenAvailableHeight = screenGeo2.height
            }
        }
    }
    
        // Method 2: If window.screen didn't work, try finding screen by position
        if (screenAvailableWidth >= Screen.desktopAvailableWidth) {
            if (Screen && Screen.screens && Screen.screens.length > 0) {
            const windowX = window.x
            const windowY = window.y
            const windowCenterX = windowX + window.width / 2
            const windowCenterY = windowY + window.height / 2
            
            for (let i = 0; i < Screen.screens.length; i++) {
                const screen = Screen.screens[i]
                if (screen && screen.geometry) {
                    const screenGeo = screen.geometry
                    
                    // Check if window center is within this screen's bounds (more reliable than top-left corner)
                    if (windowCenterX >= screenGeo.x && windowCenterX < screenGeo.x + screenGeo.width &&
                        windowCenterY >= screenGeo.y && windowCenterY < screenGeo.y + screenGeo.height) {
                        // Found the screen - use its availableGeometry
                        const availGeo = screen.availableGeometry
                        if (availGeo && availGeo.width > 0 && availGeo.height > 0) {
                            screenAvailableWidth = availGeo.width
                            screenAvailableHeight = availGeo.height
                            break
                        }
                    }
                }
            }
        }
    }
    
    // Method 3: Final fallback - if still using desktop width, use a heuristic based on window position
    // If window is on the left side of the desktop, assume it's on the first monitor
    if (screenAvailableWidth >= Screen.desktopAvailableWidth) {
        const windowX = window.x
        // Heuristic: if window is positioned in the left half of desktop, assume first monitor is ~1920px wide
        // This is a fallback for when screen detection completely fails
        if (windowX < Screen.desktopAvailableWidth / 2) {
            // Assume first monitor is standard 1920px (or use 60% of desktop width as conservative estimate)
            screenAvailableWidth = Math.min(1920, Math.floor(Screen.desktopAvailableWidth * 0.6))
            screenAvailableHeight = Screen.desktopAvailableHeight
        }
        // If window is on right side, we still use desktop width (might be second monitor)
    }
    
    return {
        width: screenAvailableWidth,
        height: screenAvailableHeight
    }
}

function getMediaDimensions(isVideo, isImageType, videoPlayerLoader, viewerLoader, logToDebugConsole) {
    let mediaWidth = 0
    let mediaHeight = 0
    
    // Get media dimensions
    if (isVideo && videoPlayerLoader && videoPlayerLoader.item) {
        if (videoPlayerLoader.item.implicitWidth > 0 && videoPlayerLoader.item.implicitHeight > 0) {
            mediaWidth = videoPlayerLoader.item.implicitWidth
            mediaHeight = videoPlayerLoader.item.implicitHeight
        }
    } else if (isImageType && viewerLoader) {
        if (viewerLoader.item) {
            // Check if image is ready (status === Image.Ready)
            const imageStatus = viewerLoader.item.status
            const isReady = (imageStatus === 2) // Image.Ready = 2
            
            // Use actual image dimensions (not sourceSize which is the requested size)
            // actualImageWidth/Height use implicitWidth/Height which give the real image dimensions
            if (viewerLoader.item.actualImageWidth > 0 && viewerLoader.item.actualImageHeight > 0) {
                mediaWidth = viewerLoader.item.actualImageWidth
                mediaHeight = viewerLoader.item.actualImageHeight
            } else if (viewerLoader.item.sourceWidth > 0 && viewerLoader.item.sourceHeight > 0) {
                // Fallback: Use sourceWidth/Height (may be requested size, not actual)
                mediaWidth = viewerLoader.item.sourceWidth
                mediaHeight = viewerLoader.item.sourceHeight
            } else if (viewerLoader.item.paintedWidth > 0 && viewerLoader.item.paintedHeight > 0) {
                // Final fallback: Use painted dimensions
                // Note: Painted dimensions are the displayed size, which may be affected by zoom/fit
                // But they should still give us a valid aspect ratio for window sizing
                mediaWidth = viewerLoader.item.paintedWidth
                mediaHeight = viewerLoader.item.paintedHeight
            }
        }
    }
    
    return {
        width: mediaWidth,
        height: mediaHeight
    }
}

function calculateWindowSize(mediaWidth, mediaHeight, screenDimensions, titleBarHeight, minWidth, minHeight) {
    // Use current screen available size (accounts for taskbar) and leave some margin
    // Subtract title bar height from max height since we'll add it later
    const maxContentWidth = Math.floor(screenDimensions.width * 0.90)
    const maxContentHeight = Math.floor(screenDimensions.height * 0.90) - titleBarHeight
    const maxWidth = maxContentWidth
    const maxHeight = maxContentHeight
    
    // If we have valid dimensions, calculate window size
    if (mediaWidth > 0 && mediaHeight > 0) {
        const aspectRatio = mediaWidth / mediaHeight
        
        // Start with a reasonable base size (prefer larger dimension)
        let baseSize = 800  // Base content area size
        let newWidth = 0
        let newHeight = 0
        
        // Calculate size based on aspect ratio
        if (aspectRatio > 1) {
            // Landscape: use width as base
            newWidth = Math.min(Math.max(minWidth, baseSize), maxWidth)
            newHeight = Math.round(newWidth / aspectRatio)
            // Ensure height is within bounds
            if (newHeight > maxHeight) {
                newHeight = maxHeight
                newWidth = Math.round(newHeight * aspectRatio)
            } else if (newHeight < minHeight) {
                newHeight = minHeight
                newWidth = Math.round(newHeight * aspectRatio)
            }
        } else {
            // Portrait: use height as base
            newHeight = Math.min(Math.max(minHeight, baseSize), maxHeight)
            newWidth = Math.round(newHeight * aspectRatio)
            // Ensure width is within bounds
            if (newWidth > maxWidth) {
                newWidth = maxWidth
                newHeight = Math.round(newWidth / aspectRatio)
            } else if (newWidth < minWidth) {
                newWidth = minWidth
                newHeight = Math.round(newWidth / aspectRatio)
            }
        }
        
        // Ensure minimum sizes
        newWidth = Math.max(minWidth, newWidth)
        newHeight = Math.max(minHeight, newHeight)
        
        // Final bounds check - ensure content area doesn't exceed available screen (accounting for title bar)
        if (newWidth > maxWidth) {
            newWidth = maxWidth
            newHeight = Math.round(newWidth / aspectRatio)
        }
        if (newHeight > maxHeight) {
            newHeight = maxHeight
            newWidth = Math.round(newHeight * aspectRatio)
            // Re-check width after adjusting height
            if (newWidth > maxWidth) {
                newWidth = maxWidth
                newHeight = Math.round(newWidth / aspectRatio)
            }
        }
        
        // Calculate total window height (content + title bar)
        const totalHeight = newHeight + titleBarHeight
        
        // Final safety check: ensure total window height doesn't exceed available screen
        const maxTotalHeight = Math.floor(screenDimensions.height * 0.90)
        if (totalHeight > maxTotalHeight) {
            // Recalculate to fit within total available height
            const adjustedContentHeight = maxTotalHeight - titleBarHeight
            if (adjustedContentHeight >= minHeight) {
                newHeight = adjustedContentHeight
                newWidth = Math.round(newHeight * aspectRatio)
                // Ensure width is still within bounds
                if (newWidth > maxWidth) {
                    newWidth = maxWidth
                    newHeight = Math.round(newWidth / aspectRatio)
                }
            }
        }
        
        return {
            width: newWidth,
            height: newHeight,
            totalHeight: newHeight + titleBarHeight
        }
    }
    
    return null
}

function resizeToMediaAspectRatio(window, matchMediaAspectRatio, currentImage, isResizing, windowVisibility, isVideo, isImageType, 
                                   videoPlayerLoader, viewerLoader, customTitleBar, lastResizeWidth, lastResizeHeight,
                                   logToDebugConsole, callLater, Screen) {
    // Don't resize if disabled, no media, already resizing
    // Note: We don't check for maximized/fullscreen here - that's handled in Main.qml
    // because visibility can be incorrectly reported
    if (!matchMediaAspectRatio || currentImage === "" || isResizing) {
        return false
    }
    
    if (!customTitleBar || !Screen) {
        return false
    }
    
    const titleBarHeight = customTitleBar.height
    const minWidth = 640
    const minHeight = 480
    
    // Get screen dimensions
    const screenDimensions = getScreenDimensions(window, Screen)
    
    // Get media dimensions
    const mediaDims = getMediaDimensions(isVideo, isImageType, videoPlayerLoader, viewerLoader, logToDebugConsole)
    
    // If no media dimensions available, can't resize
    if (mediaDims.width === 0 || mediaDims.height === 0) {
        return false
    }
    
    // Calculate window size
    const size = calculateWindowSize(mediaDims.width, mediaDims.height, screenDimensions, titleBarHeight, minWidth, minHeight)
    
    if (size) {
        // Only resize if dimensions actually changed (prevent loops)
        if (size.width !== lastResizeWidth || size.totalHeight !== lastResizeHeight) {
            // Apply new size (add title bar height to total window height)
            window.width = size.width
            window.height = size.totalHeight
            
            return {
                newWidth: size.width,
                newHeight: size.totalHeight
            }
        }
    }
    
    return null
}

