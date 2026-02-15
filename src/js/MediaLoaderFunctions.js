.pragma library

// MediaLoaderFunctions - Utility functions for loading and unloading media viewers

function loadImageViewer(params) {
    const { mediaViewerLoaders, logToDebugConsole, MediaLoaderUtils } = params
    
    logToDebugConsole("[Load] loadImageViewer() called", "info")
    if (!mediaViewerLoaders || !mediaViewerLoaders.viewerLoader) {
        logToDebugConsole("[Load] ERROR: mediaViewerLoaders.viewerLoader is not accessible", "error")
        return
    }
    MediaLoaderUtils.forceReloadLoader(mediaViewerLoaders.viewerLoader)
    logToDebugConsole("[Load] viewerLoader.active = " + mediaViewerLoaders.viewerLoader.active, "info")
}

function unloadImageViewer(params) {
    const { mediaViewerLoaders, MediaLoaderUtils } = params
    MediaLoaderUtils.unloadLoader(mediaViewerLoaders.viewerLoader)
}

function loadVideoPlayer(params) {
    const { mediaViewerLoaders, currentImage, logToDebugConsole, MediaLoaderUtils } = params
    
    logToDebugConsole("[Load] loadVideoPlayer() called, currentImage: " + currentImage, "info")
    if (!mediaViewerLoaders || !mediaViewerLoaders.videoPlayerLoader) {
        logToDebugConsole("[Load] ERROR: mediaViewerLoaders.videoPlayerLoader is not accessible", "error")
        return
    }
    logToDebugConsole("[Load] Before forceReloadLoader: active = " + mediaViewerLoaders.videoPlayerLoader.active, "info")
    MediaLoaderUtils.forceReloadLoader(mediaViewerLoaders.videoPlayerLoader)
    logToDebugConsole("[Load] After forceReloadLoader: active = " + mediaViewerLoaders.videoPlayerLoader.active, "info")
    logToDebugConsole("[Load] videoPlayerLoader.item: " + (mediaViewerLoaders.videoPlayerLoader.item ? "exists" : "null"), "info")
    if (mediaViewerLoaders.videoPlayerLoader.item) {
        logToDebugConsole("[Load] videoPlayerLoader.item.source: " + mediaViewerLoaders.videoPlayerLoader.item.source, "info")
    }
}

function unloadVideoPlayer(params) {
    const { mediaViewerLoaders, MediaLoaderUtils } = params
    MediaLoaderUtils.stopAndClearPlayer(mediaViewerLoaders.videoPlayerLoader.item)
    MediaLoaderUtils.unloadLoader(mediaViewerLoaders.videoPlayerLoader)
}

function loadAudioPlayer(params) {
    const { mediaViewerLoaders, window, logToDebugConsole, MediaLoaderUtils, Qt } = params
    
    // Prevent double-loading using a guard flag on the window object
    if (window._loadingAudioPlayer) {
        return
    }
    
    window._loadingAudioPlayer = true
    
    // CRITICAL: If loader is already active, we MUST deactivate it first to destroy the old component
    // This prevents the old AudioPlayer from still playing when we create a new one
    if (mediaViewerLoaders.audioPlayerLoader.active) {
        if (mediaViewerLoaders.audioPlayerLoader.item) {
            // Stop and clear the current player
            MediaLoaderUtils.stopAndClearPlayer(mediaViewerLoaders.audioPlayerLoader.item)
        }
        // Deactivate the loader to destroy the old component
        mediaViewerLoaders.audioPlayerLoader.active = false
        // Use Qt.callLater to ensure the old component is fully destroyed before creating new one
        Qt.callLater(function() {
            // Always reactivate - the guard prevents multiple calls to this function
            // But only if we're still in audio mode (safety check)
            if (window.isAudio && window.currentImage !== "") {
                logToDebugConsole("[Audio] Reactivating audio player loader after deactivation", "info")
                mediaViewerLoaders.audioPlayerLoader.active = true
            } else {
                logToDebugConsole("[Audio] Skipping audio player reactivation - not in audio mode", "warning")
            }
            // Clear guard after component is created
            Qt.callLater(function() {
                window._loadingAudioPlayer = false
            })
        })
    } else {
        // Loader is not active, just activate it
        // But only if we're still in audio mode (safety check)
        if (window.isAudio && window.currentImage !== "") {
            mediaViewerLoaders.audioPlayerLoader.active = true
        }
        // Clear guard after a short delay to allow component to initialize
        Qt.callLater(function() {
            window._loadingAudioPlayer = false
        })
    }
}

function unloadAudioPlayer(params) {
    const { mediaViewerLoaders, MediaLoaderUtils } = params
    MediaLoaderUtils.stopAndClearPlayer(mediaViewerLoaders.audioPlayerLoader.item)
    MediaLoaderUtils.unloadLoader(mediaViewerLoaders.audioPlayerLoader)
}

function loadMarkdownViewer(params) {
    const { mediaViewerLoaders, MediaLoaderUtils } = params
    MediaLoaderUtils.forceReloadLoader(mediaViewerLoaders.markdownViewerLoader)
}

function unloadMarkdownViewer(params) {
    const { mediaViewerLoaders, MediaLoaderUtils } = params
    MediaLoaderUtils.unloadLoader(mediaViewerLoaders.markdownViewerLoader)
}

function loadTextViewer(params) {
    const { mediaViewerLoaders, MediaLoaderUtils } = params
    MediaLoaderUtils.forceReloadLoader(mediaViewerLoaders.textViewerLoader)
}

function unloadTextViewer(params) {
    const { mediaViewerLoaders, MediaLoaderUtils } = params
    MediaLoaderUtils.unloadLoader(mediaViewerLoaders.textViewerLoader)
}

function loadPdfViewer(params) {
    const { mediaViewerLoaders, MediaLoaderUtils } = params
    MediaLoaderUtils.forceReloadLoader(mediaViewerLoaders.pdfViewerLoader)
}

function unloadPdfViewer(params) {
    const { mediaViewerLoaders, MediaLoaderUtils } = params
    MediaLoaderUtils.unloadLoader(mediaViewerLoaders.pdfViewerLoader)
}

function loadZipViewer(params) {
    const { mediaViewerLoaders, MediaLoaderUtils } = params
    MediaLoaderUtils.forceReloadLoader(mediaViewerLoaders.zipViewerLoader)
}

function unloadZipViewer(params) {
    const { mediaViewerLoaders, MediaLoaderUtils } = params
    MediaLoaderUtils.unloadLoader(mediaViewerLoaders.zipViewerLoader)
}

function loadModelViewer(params) {
    const { mediaViewerLoaders, MediaLoaderUtils } = params
    MediaLoaderUtils.forceReloadLoader(mediaViewerLoaders.modelViewerLoader)
}

function unloadModelViewer(params) {
    const { mediaViewerLoaders, MediaLoaderUtils } = params
    MediaLoaderUtils.unloadLoader(mediaViewerLoaders.modelViewerLoader)
}

function unloadAllViewers(params) {
    unloadImageViewer(params)
    unloadVideoPlayer(params)
    unloadAudioPlayer(params)
    unloadMarkdownViewer(params)
    unloadTextViewer(params)
    unloadPdfViewer(params)
    unloadZipViewer(params)
    unloadModelViewer(params)
}

