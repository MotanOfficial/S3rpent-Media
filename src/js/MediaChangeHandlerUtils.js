.pragma library

// MediaChangeHandlerUtils - Utility functions for handling media changes

function handleCurrentImageChanged(params) {
    const {
        currentImage,
        _isUnloading,
        matchMediaAspectRatio,
        _navigatingImages,
        mediaViewerLoaders,
        MediaLoaderUtils,
        MediaPlayer,
        Qt,
        // Callback functions
        checkIfVideo,
        checkIfGif,
        checkIfAudio,
        checkIfMarkdown,
        checkIfText,
        checkIfPdf,
        checkIfZip,
        checkIfModel,
        resetView,
        restoreDefaultWindowSize,
        loadVideoPlayer,
        loadAudioPlayer,
        loadMarkdownViewer,
        loadTextViewer,
        loadPdfViewer,
        loadZipViewer,
        loadModelViewer,
        loadImageViewer,
        unloadImageViewer,
        unloadVideoPlayer,
        unloadAudioPlayer,
        unloadMarkdownViewer,
        unloadTextViewer,
        unloadPdfViewer,
        unloadZipViewer,
        unloadModelViewer,
        useFallbackAccent,
        startLoadTimer,
        loadDirectoryImages,
        extractAudioCoverArt,
        getAudioFormatInfo,
        logToDebugConsole
    } = params
    
    const imageStr = currentImage.toString()
    
    // Result object to return what needs to be set
    const result = {
        shouldReturn: false,
        propertiesToSet: {},
        actionsToPerform: []
    }
    
    // If currentImage is empty, unload all viewers and return early
    // CRITICAL: Do NOT load any viewer when clearing - only unload
    if (currentImage === "") {
        // Unload all viewers (only if active to avoid unnecessary calls)
        if (mediaViewerLoaders.viewerLoader.active) {
            result.actionsToPerform.push(() => unloadImageViewer())
        }
        if (mediaViewerLoaders.videoPlayerLoader.active) {
            result.actionsToPerform.push(() => unloadVideoPlayer())
        }
        if (mediaViewerLoaders.audioPlayerLoader.active) {
            result.actionsToPerform.push(() => unloadAudioPlayer())
        }
        if (mediaViewerLoaders.markdownViewerLoader.active) {
            result.actionsToPerform.push(() => unloadMarkdownViewer())
        }
        if (mediaViewerLoaders.textViewerLoader.active) {
            result.actionsToPerform.push(() => unloadTextViewer())
        }
        if (mediaViewerLoaders.pdfViewerLoader.active) {
            result.actionsToPerform.push(() => unloadPdfViewer())
        }
        if (mediaViewerLoaders.zipViewerLoader.active) {
            result.actionsToPerform.push(() => unloadZipViewer())
        }
        if (mediaViewerLoaders.modelViewerLoader.active) {
            result.actionsToPerform.push(() => unloadModelViewer())
        }
        result.actionsToPerform.push(() => useFallbackAccent())
        result.actionsToPerform.push(() => logToDebugConsole("[Media] Cleared current image", "info"))
        result.shouldReturn = true
        return result
    }
    
    // If we're in the middle of unloading, handle appropriately
    // This prevents race conditions when unloadMedia() or resetForReuse() sets currentImage = ""
    if (_isUnloading) {
        // If currentImage is empty, we're actually unloading - skip load
        if (currentImage === "") {
            result.actionsToPerform.push(() => logToDebugConsole("[Media] Skipping load - unload in progress (empty URL)", "info"))
            result.shouldReturn = true
            return result
        }
        // If we have a valid URL, this means resetForReuse() set the flag,
        // and now C++ is setting a new image - clear the flag and continue loading
        result.actionsToPerform.push(() => logToDebugConsole("[Media] Clearing unloading flag - new media URL set after reset", "info"))
        result.propertiesToSet._isUnloading = false
        // Continue to load logic below (don't return)
    }
    
    // New image to load - reset view and detect type
    result.actionsToPerform.push(() => resetView())
    
    const isVideo = checkIfVideo(currentImage)
    const isGif = checkIfGif(currentImage)
    const isAudio = checkIfAudio(currentImage)
    const isMarkdown = checkIfMarkdown(currentImage)
    const isText = checkIfText(currentImage)
    const isPdf = checkIfPdf(currentImage)
    const isZip = checkIfZip(currentImage)
    const isModel = checkIfModel(currentImage)
    
    result.propertiesToSet.isVideo = isVideo
    result.propertiesToSet.isGif = isGif
    result.propertiesToSet.isAudio = isAudio
    result.propertiesToSet.isMarkdown = isMarkdown
    result.propertiesToSet.isText = isText
    result.propertiesToSet.isPdf = isPdf
    result.propertiesToSet.isZip = isZip
    result.propertiesToSet.isModel = isModel
    
    // Restore default window size when loading audio, text, or PDF (these have no visual dimensions to match)
    if ((isAudio || isText || isPdf || isZip || isModel) && matchMediaAspectRatio) {
        result.actionsToPerform.push(() => {
            Qt.callLater(function() {
                restoreDefaultWindowSize()
            })
        })
    }
    
    // CRITICAL: Clear unloading flag before loading (in case it was set by resetForReuse)
    result.propertiesToSet._isUnloading = false
    
    // CRITICAL: Stop previous video/audio before loading new media
    // This prevents audio from continuing to play when switching media
    if (mediaViewerLoaders.videoPlayerLoader.item && mediaViewerLoaders.videoPlayerLoader.item.source !== "") {
        result.actionsToPerform.push(() => {
            if (mediaViewerLoaders.videoPlayerLoader.item) {
                mediaViewerLoaders.videoPlayerLoader.item.stop()
            }
        })
    }
    if (mediaViewerLoaders.audioPlayerLoader.item && mediaViewerLoaders.audioPlayerLoader.item.source !== "") {
        result.actionsToPerform.push(() => {
            if (mediaViewerLoaders.audioPlayerLoader.item) {
                mediaViewerLoaders.audioPlayerLoader.item.stop()
            }
        })
    }
    
    // CRITICAL: Recreate the appropriate viewer via Loader to ensure proper scene graph rebinding
    // This fixes the issue where components don't reload after window hide/show
    if (isVideo) {
        result.actionsToPerform.push(() => loadVideoPlayer())
    } else if (isAudio) {
        // Use Qt.callLater to ensure video player is fully unloaded before loading audio player
        // This prevents both players from playing simultaneously
        result.actionsToPerform.push(() => {
            Qt.callLater(function() {
                loadAudioPlayer()
            })
        })
    } else if (isMarkdown) {
        result.actionsToPerform.push(() => loadMarkdownViewer())
    } else if (isText) {
        result.actionsToPerform.push(() => loadTextViewer())
    } else if (isPdf) {
        result.actionsToPerform.push(() => loadPdfViewer())
    } else if (isZip) {
        result.actionsToPerform.push(() => loadZipViewer())
    } else if (isModel) {
        result.actionsToPerform.push(() => loadModelViewer())
    } else {
        // Image (including GIF)
        result.actionsToPerform.push(() => loadImageViewer())
    }
    
    // Log image change
    const fileName = currentImage.toString().split("/").pop() || currentImage.toString()
    if (isVideo) {
        result.actionsToPerform.push(() => useFallbackAccent())
        result.actionsToPerform.push(() => startLoadTimer("Video"))
    } else if (isAudio) {
        // Audio keeps color until cover art is detected
        result.actionsToPerform.push(() => startLoadTimer("Audio"))
    } else if (isMarkdown) {
        result.actionsToPerform.push(() => useFallbackAccent())
        result.actionsToPerform.push(() => startLoadTimer("Markdown"))
    } else if (isText) {
        result.actionsToPerform.push(() => useFallbackAccent())
        result.actionsToPerform.push(() => startLoadTimer("Text"))
    } else if (isPdf) {
        result.actionsToPerform.push(() => useFallbackAccent())
        result.actionsToPerform.push(() => startLoadTimer("PDF"))
    } else if (isZip) {
        result.actionsToPerform.push(() => useFallbackAccent())
        result.actionsToPerform.push(() => startLoadTimer("ZIP"))
    } else if (isModel) {
        result.actionsToPerform.push(() => useFallbackAccent())
        result.actionsToPerform.push(() => startLoadTimer("Model"))
    } else {
        // Images: keep previous color until new one is detected (smooth transition)
        result.actionsToPerform.push(() => startLoadTimer(isGif ? "GIF" : "Image"))
    }
    
    if (!isVideo && !isAudio && !isMarkdown && !isText && !isPdf && !isZip && !isModel) {
        // Don't call updateAccentColor here - it's called async in onImageReady
        // Load all images from directory for navigation (only if not already navigating)
        if (!_navigatingImages) {
            result.actionsToPerform.push(() => loadDirectoryImages(currentImage))
            result.propertiesToSet.showImageControls = false  // Hide controls when loading new image
        }
    } else if (isVideo) {
        // Reset no audio flag when switching videos
        result.propertiesToSet.videoHasNoAudio = false
        // Stop audio if playing (video already stopped above)
        if (mediaViewerLoaders.audioPlayerLoader.item) {
            result.actionsToPerform.push(() => {
                mediaViewerLoaders.audioPlayerLoader.item.stop()
            })
        }
    } else if (isAudio) {
        // CRITICAL: Stop and completely unload video player before loading audio
        // This prevents the video's MediaPlayer from still playing audio while the audio player starts
        if (mediaViewerLoaders.videoPlayerLoader.item) {
            result.actionsToPerform.push(() => {
                MediaLoaderUtils.stopAndClearPlayer(mediaViewerLoaders.videoPlayerLoader.item)
            })
        }
        if (mediaViewerLoaders.videoPlayerLoader.active) {
            result.propertiesToSet.videoPlayerLoaderActive = false
        }
        // Note: loadAudioPlayer() will handle stopping/clearing/unloading the old audio player
        // Reset cover art and format info
        result.propertiesToSet.audioCoverArt = ""
        result.propertiesToSet.audioFormatInfo = { sampleRate: 0, bitrate: 0 }
        // Try to extract cover art immediately (might be available)
        result.actionsToPerform.push(() => {
            Qt.callLater(function() {
                extractAudioCoverArt()
                getAudioFormatInfo(0) // Get sample rate only
            })
        })
    } else if (isMarkdown || isText || isPdf || isZip || isModel) {
        // Video and audio already stopped above, no need to stop again
    }
    
    return result
}

