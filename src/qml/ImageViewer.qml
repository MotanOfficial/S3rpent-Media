import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import "../js/FileTypeUtils.js" as FileTypeUtils

Item {
    id: imageViewer
    
    property var windowRef: null  // Window reference for accessing window properties
    property var resizeTimersRef: null  // Resize timers reference
    property url source: ""
    property bool isGif: false
    property real zoomFactor: 1.0
    property real panX: 0
    property real panY: 0
    rotation: 0  // Rotation in degrees (0, 90, 180, 270)
    property color accentColor: "#121216"
    property bool imageInterpolationMode: true  // true = smooth/antialiased, false = nearest neighbor
    property bool dynamicResolutionEnabled: true  // Dynamic resolution adjustment based on zoom level
    
    signal imageReady()
    signal paintedSizeChanged()
    
    // Throttled sourceSize to prevent excessive reloading
    property size computedSourceSize: Qt.size(0, 0)
    property real lastZoomFactor: 1.0
    property size lastContainerSize: Qt.size(0, 0)
    property bool photoBufferActive: false  // Tracks which photo image is active for double-buffering
    property bool lastDynamicResolutionEnabled: dynamicResolutionEnabled  // Track previous setting state
    property bool _isInitialSourceLoad: false  // Flag to prevent onDynamicResolutionEnabledChanged from interfering during initial load
    property int originalSourceWidth: 0  // Store original full-resolution source width for 1:1 zoom calculation
    property int originalSourceHeight: 0  // Store original full-resolution source height
    
    // Longest edge cap for dynamic decode (avoids multi‑GB pixmaps on huge images)
    readonly property int maxDecodeEdge: 8192
    
    function isGifUrl(u) {
        if (!u || u === "")
            return false
        const s = u.toString().toLowerCase()
        return s.endsWith(".gif") || s.indexOf(".gif?") >= 0
    }
    
    function computeDynamicDecodeSize() {
        if (mediaContainer.width <= 0 || mediaContainer.height <= 0)
            return Qt.size(0, 0)
        const padding = 1.2
        let dpr = 1.0
        if (windowRef && windowRef.screen)
            dpr = windowRef.screen.devicePixelRatio
        let tw = Math.ceil(mediaContainer.width * zoomFactor * padding * dpr)
        let th = Math.ceil(mediaContainer.height * zoomFactor * padding * dpr)
        const maxEdge = maxDecodeEdge
        const longest = Math.max(tw, th)
        if (longest > maxEdge) {
            const scale = maxEdge / longest
            tw = Math.ceil(tw * scale)
            th = Math.ceil(th * scale)
        }
        return Qt.size(tw, th)
    }
    
    property url prefetchNextSource: {
        const w = windowRef
        if (!w || !w.directoryImages || w.directoryImages.length <= 1)
            return ""
        const idx = w.currentImageIndex
        const len = w.directoryImages.length
        const nextIdx = (idx + 1) % len
        const url = w.directoryImages[nextIdx]
        if (url === w.currentImage)
            return ""
        return url
    }
    property url prefetchPrevSource: {
        const w = windowRef
        if (!w || !w.directoryImages || w.directoryImages.length <= 1)
            return ""
        const idx = w.currentImageIndex
        const len = w.directoryImages.length
        const prevIdx = (idx - 1 + len) % len
        const url = w.directoryImages[prevIdx]
        if (url === w.currentImage)
            return ""
        return url
    }
    
    // Timer to debounce sourceSize updates
    Timer {
        id: sourceSizeUpdateTimer
        interval: 150  // Short debounce: faster response while still batching resize bursts
        onTriggered: updateSourceSize()
    }
    
    function startBufferedReload(targetSize) {
        if (source === "" || isGif) {
            return
        }
        // Load into the non-active image to keep the currently visible one on screen
        const target = photoBufferActive ? photo : photoBuffer
        const finalSize = (targetSize !== undefined && targetSize.width > 0 && targetSize.height > 0) ? targetSize : undefined
        target.loadingForSwap = true
        target.visible = true
        // If targetSize is undefined or has zero dimensions, use undefined for full resolution
        target.sourceSize = finalSize
        target.source = source
    }

    function updateSourceSize() {
        if (source === "" || isGif) {
            return
        }
        
        let sizeToUse = undefined  // undefined means full resolution
        
        if (dynamicResolutionEnabled) {
            if (mediaContainer.width === 0 || mediaContainer.height === 0) {
                // Container size not ready yet, schedule update when it becomes available
                if (!sourceSizeUpdateTimer.running) {
                    sourceSizeUpdateTimer.start()
                }
                return
            }
            
            // Calculate the effective display size (container size * zoomFactor)
            const ds = computeDynamicDecodeSize()
            sizeToUse = Qt.size(ds.width, ds.height)
        }
        
        // When disabled, sizeToUse is undefined (full resolution)
        // When enabled, sizeToUse is a specific size
        // We need to check if we should update based on the setting change or size change
        
        const wasEnabled = computedSourceSize.width > 0 && computedSourceSize.height > 0
        const nowEnabled = sizeToUse !== undefined && sizeToUse.width > 0 && sizeToUse.height > 0
        
        // Check if the setting actually changed (using tracked property)
        const settingChanged = lastDynamicResolutionEnabled !== dynamicResolutionEnabled
        
        // If the setting changed (enabled <-> disabled), always update
        // This handles the case when setting is toggled on an already-loaded image
        if (settingChanged) {
            // Force update - don't check size changes
            computedSourceSize = (sizeToUse !== undefined) ? sizeToUse : Qt.size(0, 0)
            lastZoomFactor = zoomFactor
            lastContainerSize = Qt.size(mediaContainer.width, mediaContainer.height)
            // Reload image in background buffer for smooth swap
            startBufferedReload(sizeToUse)
            return
        }
        
        // If enabled, check if size changed significantly (more than 5% difference)
        let sizeChanged = false
        if (nowEnabled && wasEnabled) {
            sizeChanged = Math.abs(sizeToUse.width - computedSourceSize.width) / Math.max(1, computedSourceSize.width) > 0.05 ||
                           Math.abs(sizeToUse.height - computedSourceSize.height) / Math.max(1, computedSourceSize.height) > 0.05
        } else if (nowEnabled && !wasEnabled) {
            // Just enabled, always update
            sizeChanged = true
        } else if (!nowEnabled && wasEnabled) {
            // Just disabled, always update to full resolution
            sizeChanged = true
        } else if (!nowEnabled && !wasEnabled && computedSourceSize.width === 0) {
            // First load with disabled setting, update to ensure full resolution
            sizeChanged = true
        }
        
        if (!sizeChanged && computedSourceSize.width !== 0) {
            lastZoomFactor = zoomFactor
            lastContainerSize = Qt.size(mediaContainer.width, mediaContainer.height)
            return
        }
        
        // Update computedSourceSize (use Qt.size(0, 0) as marker for disabled/full resolution)
        computedSourceSize = (sizeToUse !== undefined) ? sizeToUse : Qt.size(0, 0)
        lastZoomFactor = zoomFactor
        lastContainerSize = Qt.size(mediaContainer.width, mediaContainer.height)
        
        // Reload image in background buffer for smooth swap
        // Pass undefined for full resolution when disabled
        startBufferedReload(sizeToUse)
    }
    
        // Update sourceSize when zoomFactor changes significantly
        onZoomFactorChanged: {
            // Only update if zoom changed by more than 10%
            const zoomChange = Math.abs(zoomFactor - lastZoomFactor) / Math.max(0.1, lastZoomFactor)
            if (zoomChange > 0.1 || computedSourceSize.width === 0) {
                if (!sourceSizeUpdateTimer.running) {
                    sourceSizeUpdateTimer.start()
                }
            }
        }
    
    // Update sourceSize when container size changes (but debounced)
    onDynamicResolutionEnabledChanged: {
        // Skip if we're in the middle of an initial source load - onSourceChanged will handle it
        if (_isInitialSourceLoad) {
            lastDynamicResolutionEnabled = dynamicResolutionEnabled
            return
        }
        
        // Only process if we have a source and it's not a GIF
        // Also skip if source was just cleared (empty string means we're unloading)
        if (source !== "" && !isGif && source.toString() !== "") {
            // Check if setting actually changed (not just initial load)
            const settingActuallyChanged = lastDynamicResolutionEnabled !== dynamicResolutionEnabled
            
            // Check if image is already loaded (not during initial load)
            const imageAlreadyLoaded = photo.status === Image.Ready || photoBuffer.status === Image.Ready

            if (settingActuallyChanged && imageAlreadyLoaded) {
                // Only reload if image is already loaded (not during initial load)
                // Calculate the new size based on current setting
                let newSize = undefined
                if (dynamicResolutionEnabled) {
                    if (mediaContainer.width > 0 && mediaContainer.height > 0) {
                        const ds = computeDynamicDecodeSize()
                        newSize = Qt.size(ds.width, ds.height)
                    }
                }
                // If disabled, newSize remains undefined (full resolution)
                
                // Update computedSourceSize - the binding will update sourceSize automatically
                computedSourceSize = (newSize !== undefined) ? newSize : Qt.size(0, 0)

                // Store current state
                const currentSource = source
                
                // Clear both sources to force reload with new sourceSize
                photo.source = ""
                photoBuffer.source = ""

                // Wait for next frame, then reload
                // This ensures Qt recognizes it as a new load with new sourceSize
                Qt.callLater(function() {
                    Qt.callLater(function() {
                        if (source === currentSource && source !== "") {
                            // Reload using buffered reload system
                            startBufferedReload(newSize)
                        }
                    })
                })
                
                lastZoomFactor = zoomFactor
                lastContainerSize = Qt.size(mediaContainer.width, mediaContainer.height)
            } else if (settingActuallyChanged && !imageAlreadyLoaded) {
                // Setting changed during initial load - don't set sourceSize here
                // Let onSourceChanged handle it to avoid double loading
                // Just update computedSourceSize for tracking, but don't touch photo.sourceSize
                let newSize = undefined
                if (dynamicResolutionEnabled) {
                    if (mediaContainer.width > 0 && mediaContainer.height > 0) {
                        const ds = computeDynamicDecodeSize()
                        newSize = Qt.size(ds.width, ds.height)
                    }
                }
                computedSourceSize = (newSize !== undefined) ? newSize : Qt.size(0, 0)
                // Don't set photo.sourceSize here - onSourceChanged will handle it
            }

            // Update the tracked state
            lastDynamicResolutionEnabled = dynamicResolutionEnabled
        } else {
            // Update tracked state even if no source
            lastDynamicResolutionEnabled = dynamicResolutionEnabled
        }
    }
    
    
    function adjustZoom(delta) {
        if (source === "")
            return;
        const factor = Math.pow(1.0015, delta);
        zoomFactor = Math.max(0.1, Math.min(zoomFactor * factor, 10.0));
        clampPan();
    }
    
    function resetView() {
        zoomFactor = 1.0
        panX = 0
        panY = 0
        rotation = 0
    }
    
    function clearSource() {
        // Make components invisible FIRST to prevent any rendering
        photo.visible = false
        photoBuffer.visible = false
        animatedGif.visible = false
        animatedGif.playing = false
        
        // Clear the source property - this will trigger bound components to clear
        source = ""
        
        // Explicitly clear the internal image components immediately (synchronous)
        // This ensures memory is released before window closes
        photo.source = ""
        photoBuffer.source = ""
        animatedGif.source = ""
        
        // Reset computed source size
        computedSourceSize = Qt.size(0, 0)
        lastZoomFactor = 1.0
        lastContainerSize = Qt.size(0, 0)
        photoBufferActive = false
        
        // Note: status is read-only, so we can't set it directly
        // Clearing the source should be enough to release resources
    }
    
    // Initialize sourceSize when source changes
    onSourceChanged: {
        // Reset original source dimensions when source changes
        originalSourceWidth = 0
        originalSourceHeight = 0
        
        if (source === "") {
            // Clear Image sources when source is cleared
            photo.source = ""
            photoBuffer.source = ""
            return
        }
        
        if (source !== "") {
            // Set flag to prevent onDynamicResolutionEnabledChanged from interfering
            _isInitialSourceLoad = true
            
            // CRITICAL: Set sourceSize BEFORE setting source to prevent double loading
            // The Image's source was previously bound, but now we set it manually after sourceSize
            const newSource = source
            
            // IMPORTANT: Set computedSourceSize BEFORE anything else
            // Reset computedSourceSize first
            computedSourceSize = Qt.size(0, 0)
            
            // Update tracked setting state for initial load
            lastDynamicResolutionEnabled = dynamicResolutionEnabled
            
            // Set initial sourceSize immediately based on current setting
            let initialSourceSize = undefined
            if (dynamicResolutionEnabled) {
                // If container size is available, calculate size immediately
                if (mediaContainer.width > 0 && mediaContainer.height > 0) {
                    const ds = computeDynamicDecodeSize()
                    initialSourceSize = Qt.size(ds.width, ds.height)
                    computedSourceSize = initialSourceSize
                } else {
                    // Container size not ready, set to undefined temporarily
                    computedSourceSize = Qt.size(0, 0)
                    initialSourceSize = undefined
                }
            } else {
                // Disabled: always use full resolution (undefined)
                computedSourceSize = Qt.size(0, 0)  // Marker for disabled
                initialSourceSize = undefined
            }
            
            // Set sourceSize directly on both images BEFORE restoring source
            // CRITICAL: Must explicitly set to undefined (not Qt.size(0,0)) for full resolution
            if (initialSourceSize !== undefined) {
                photo.sourceSize = initialSourceSize
                photoBuffer.sourceSize = initialSourceSize
            } else {
                // Explicitly set to undefined for full resolution
                photo.sourceSize = undefined
                photoBuffer.sourceSize = undefined
            }
            
            // Now restore the source - Image will load with correct sourceSize from the start
            // Use Qt.callLater to ensure sourceSize is fully set before source is restored
            Qt.callLater(function() {
                if (imageViewer.source === newSource && newSource !== "") {
                    photo.source = newSource
                    photoBuffer.source = newSource
                }
            })
            
            // Now set other properties after sourceSize is ready
            // Reset tracking variables
            lastZoomFactor = zoomFactor
            lastContainerSize = Qt.size(mediaContainer.width, mediaContainer.height)
            photoBufferActive = false
            photo.visible = true
            photoBuffer.visible = false
            
            // Clear flag after a delay to allow initial load to complete
            Qt.callLater(function() {
                _isInitialSourceLoad = false
                
                if (source !== "") {
                    // Only call updateSourceSize if we need to (container size changed or enabled state changed)
                    // When disabled, we've already set sourceSize to undefined, so no need to reload
                    // When enabled, updateSourceSize will check if size needs to change
                    if (dynamicResolutionEnabled) {
                        // Enabled: might need to recalculate if container size wasn't ready
                    updateSourceSize()
                    }
                    // If disabled, sourceSize is already undefined, no need to call updateSourceSize
                    
                    // Ensure the primary photo is used first
                    photo.visible = true
                    photoBuffer.visible = false
                    photo.loadingForSwap = false
                    photoBuffer.loadingForSwap = false
                    photoBufferActive = false
                }
            })
        } else {
            computedSourceSize = Qt.size(0, 0)
            lastZoomFactor = 1.0
            lastContainerSize = Qt.size(0, 0)
            photoBufferActive = false
            photo.visible = false
            photoBuffer.visible = false
        }
    }
    
    function fitToWindow() {
        // When rotated 90 or 270 degrees, we need to adjust zoom to account for aspect ratio swap
        if (rotation === 90 || rotation === 270) {
            // Calculate the zoom needed to fit the rotated image
            const imgW = paintedWidth
            const imgH = paintedHeight
            const containerW = mediaContainer.width
            const containerH = mediaContainer.height
            
            if (imgW > 0 && imgH > 0 && containerW > 0 && containerH > 0) {
                // After 90/270 rotation, width becomes height and vice versa
                // We need to scale so the rotated image fits
                const rotatedFitW = containerW / imgH  // rotated width (original height) fits container width
                const rotatedFitH = containerH / imgW  // rotated height (original width) fits container height
                const scaleFactor = Math.min(rotatedFitW, rotatedFitH)
                
                // The base zoom (1.0) already fits the unrotated image, so we adjust
                const baseFitW = containerW / imgW
                const baseFitH = containerH / imgH
                const baseScale = Math.min(baseFitW, baseFitH)
                
                zoomFactor = scaleFactor / baseScale
            } else {
                zoomFactor = 1.0
            }
        } else {
            zoomFactor = 1.0
        }
        panX = 0
        panY = 0
        clampPan()
    }
    
    function actualSize() {
        // Calculate zoom needed to show image at 100% (1 image pixel = 1 screen pixel)
        if (source === "" || paintedWidth === 0)
            return
        
        // Use stored original source width, or get it from the image if not stored yet
        let origWidth = originalSourceWidth
        if (origWidth === 0) {
            const imageSource = isGif ? animatedGif : (photoBufferActive ? photoBuffer : photo)
            origWidth = imageSource.implicitWidth > 0 ? imageSource.implicitWidth : imageSource.sourceSize.width
            if (origWidth > 0) {
                originalSourceWidth = origWidth
            }
        }
        
        if (origWidth === 0)
            return
        
        // paintedWidth is the base fitted width (not affected by zoomFactor)
        // At 100% zoom, we want: displayedWidth = originalSourceWidth
        // displayedWidth = paintedWidth * zoomFactor
        // So: paintedWidth * zoomFactor = originalSourceWidth
        // Therefore: zoomFactor = originalSourceWidth / paintedWidth
        const actualZoom = origWidth / paintedWidth
        zoomFactor = Math.max(0.1, Math.min(actualZoom, 10.0))
        panX = 0
        panY = 0
        clampPan()
    }
    
    function rotateLeft() {
        rotation = (rotation - 90 + 360) % 360
        fitToWindow()
    }
    
    function rotateRight() {
        rotation = (rotation + 90) % 360
        fitToWindow()
    }
    
    function clampPan() {
        if (source === "") {
            panX = 0
            panY = 0
            return
        }
        
        const imageSource = isGif
                             ? animatedGif
                             : (photoBufferActive ? photoBuffer : photo)
        if (imageSource.paintedWidth === 0 || imageSource.paintedHeight === 0) {
            panX = 0
            panY = 0
            return
        }
        
        const contentW = imageSource.paintedWidth
        const contentH = imageSource.paintedHeight
        const viewportW = mediaContainer.width
        const viewportH = mediaContainer.height
        const scaledW = contentW * zoomFactor
        const scaledH = contentH * zoomFactor
        
        const limitX = Math.max(0, (scaledW - viewportW) / 2)
        const limitY = Math.max(0, (scaledH - viewportH) / 2)
        
        panX = limitX === 0 ? 0 : Math.max(-limitX, Math.min(panX, limitX))
        panY = limitY === 0 ? 0 : Math.max(-limitY, Math.min(panY, limitY))
    }
    
    // Throttle clampPan during resize to avoid lag
    Timer {
        id: clampPanTimer
        interval: 16  // ~60fps
        onTriggered: clampPan()
    }
    
    onWidthChanged: {
        if (!clampPanTimer.running) {
            clampPanTimer.start()
        }
    }
    onHeightChanged: {
        if (!clampPanTimer.running) {
            clampPanTimer.start()
        }
    }
    
    Item {
        id: mediaContainer
        anchors.centerIn: parent
        width: Math.max(0, parent.width)
        height: Math.max(0, parent.height)
        visible: imageViewer.source !== ""
        
        // Debounce container size changes to prevent excessive reloading
        onWidthChanged: {
            // If dynamic resolution is enabled and we have a source, update when container size becomes available
            if (imageViewer.dynamicResolutionEnabled && imageViewer.source !== "" && width > 0 && height > 0) {
                if (imageViewer.sourceSizeUpdateTimer && !imageViewer.sourceSizeUpdateTimer.running) {
                imageViewer.sourceSizeUpdateTimer.start()
                }
            }
        }
        onHeightChanged: {
            // If dynamic resolution is enabled and we have a source, update when container size becomes available
            if (imageViewer.dynamicResolutionEnabled && imageViewer.source !== "" && width > 0 && height > 0) {
                if (imageViewer.sourceSizeUpdateTimer && !imageViewer.sourceSizeUpdateTimer.running) {
                imageViewer.sourceSizeUpdateTimer.start()
                }
            }
        }
        
        transform: [
            Translate { x: panX; y: panY },
            Scale {
                origin.x: width / 2
                origin.y: height / 2
                xScale: zoomFactor
                yScale: zoomFactor
            },
            Rotation {
                origin.x: mediaContainer.width / 2
                origin.y: mediaContainer.height / 2
                angle: imageViewer.rotation
            }
        ]
        
        // Double-buffered static image for smooth sourceSize changes
        Image {
            id: photo
            anchors.fill: parent
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            cache: true  // Qt image cache: speeds repeat loads / prefetch; cleared when source is cleared
            smooth: imageViewer.imageInterpolationMode  // Use interpolation mode setting
            mipmap: false  // Disable mipmapping to reduce memory usage
            visible: !imageViewer.isGif && imageViewer.source !== "" && !imageViewer.photoBufferActive
            // source is set manually in onSourceChanged AFTER sourceSize is set to prevent double loading
            property bool loadingForSwap: false
            
            onStatusChanged: {
                if (status === Image.Ready) {
                    // Store original source dimensions (implicitWidth/Height give us the actual image size)
                    if (imageViewer.originalSourceWidth === 0 || imageViewer.originalSourceHeight === 0) {
                        imageViewer.originalSourceWidth = implicitWidth > 0 ? implicitWidth : (sourceSize.width > 0 ? sourceSize.width : 0)
                        imageViewer.originalSourceHeight = implicitHeight > 0 ? implicitHeight : (sourceSize.height > 0 ? sourceSize.height : 0)
                    }
                    if (loadingForSwap) {
                        imageViewer.photoBufferActive = false
                        loadingForSwap = false
                        photoBuffer.visible = false
                        imageReady()
                        clampPan()
                    } else {
                        imageReady()
                        clampPan()
                    }
                }
            }
            onPaintedWidthChanged: {
                clampPan()
                paintedSizeChanged()
            }
            onPaintedHeightChanged: {
                clampPan()
                paintedSizeChanged()
            }
        }
        
        Image {
            id: photoBuffer
            anchors.fill: parent
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            cache: true  // Qt image cache: speeds repeat loads / prefetch; cleared when source is cleared
            smooth: imageViewer.imageInterpolationMode  // Use interpolation mode setting
            mipmap: false  // Disable mipmapping to reduce memory usage
            visible: !imageViewer.isGif && imageViewer.source !== "" && imageViewer.photoBufferActive
            // source is set manually in onSourceChanged AFTER sourceSize is set to prevent double loading
            property bool loadingForSwap: false
            
            onStatusChanged: {
                if (status === Image.Ready) {
                    // Store original source dimensions (implicitWidth/Height give us the actual image size)
                    if (imageViewer.originalSourceWidth === 0 || imageViewer.originalSourceHeight === 0) {
                        imageViewer.originalSourceWidth = implicitWidth > 0 ? implicitWidth : (sourceSize.width > 0 ? sourceSize.width : 0)
                        imageViewer.originalSourceHeight = implicitHeight > 0 ? implicitHeight : (sourceSize.height > 0 ? sourceSize.height : 0)
                    }
                    if (loadingForSwap) {
                        imageViewer.photoBufferActive = true
                        loadingForSwap = false
                        photo.visible = false
                        imageReady()
                        clampPan()
                    } else {
                        imageReady()
                        clampPan()
                    }
                }
            }
            onPaintedWidthChanged: {
                clampPan()
                paintedSizeChanged()
            }
            onPaintedHeightChanged: {
                clampPan()
                paintedSizeChanged()
            }
        }
        
        AnimatedImage {
            id: animatedGif
            anchors.fill: parent
            fillMode: AnimatedImage.PreserveAspectFit
            asynchronous: true
            cache: false  // Disable caching to allow proper memory release
            smooth: imageViewer.imageInterpolationMode  // Use interpolation mode setting
            sourceSize: {
                // Use computedSourceSize if it has valid dimensions, otherwise undefined (full resolution)
                if (imageViewer.computedSourceSize.width > 0 && imageViewer.computedSourceSize.height > 0) {
                    return imageViewer.computedSourceSize
                }
                return undefined  // Full resolution when disabled or not calculated yet
            }
            visible: imageViewer.isGif && imageViewer.source !== ""
            source: (imageViewer.isGif && imageViewer.source !== "") ? imageViewer.source : ""
            playing: imageViewer.isGif && imageViewer.source !== ""
            
            // Force release when source is cleared
            onSourceChanged: {
                if (source === "") {
                    // Force immediate cleanup
                    playing = false
                    // Note: status is read-only, so we can't set it directly
                    // Clearing source and stopping playback is sufficient to release resources
                }
            }
            onStatusChanged: {
                if (status === AnimatedImage.Ready) {
                    imageReady()
                    clampPan()
                }
            }
            onPaintedWidthChanged: {
                clampPan()
                paintedSizeChanged()
            }
            onPaintedHeightChanged: {
                clampPan()
                paintedSizeChanged()
            }
        }
    }
    
    // Prefetch next/prev still images into Qt's image cache (wrap matches Main.qml navigation)
    Item {
        width: 1
        height: 1
        visible: false
        Image {
            id: prefetchNextImage
            anchors.fill: parent
            asynchronous: true
            cache: true
            smooth: false
            mipmap: false
            fillMode: Image.PreserveAspectFit
            property url effectiveSource: {
                if (imageViewer.source === "" || imageViewer.isGif)
                    return ""
                const u = imageViewer.prefetchNextSource
                if (!u || u === "" || u === imageViewer.source)
                    return ""
                if (imageViewer.isGifUrl(u))
                    return ""
                if (!FileTypeUtils.checkIfImage(u))
                    return ""
                return u
            }
            source: effectiveSource
            sourceSize: {
                if (!imageViewer.dynamicResolutionEnabled)
                    return undefined
                if (imageViewer.computedSourceSize.width > 0 && imageViewer.computedSourceSize.height > 0)
                    return imageViewer.computedSourceSize
                return undefined
            }
        }
        Image {
            id: prefetchPrevImage
            anchors.fill: parent
            asynchronous: true
            cache: true
            smooth: false
            mipmap: false
            fillMode: Image.PreserveAspectFit
            property url effectiveSource: {
                if (imageViewer.source === "" || imageViewer.isGif)
                    return ""
                const u = imageViewer.prefetchPrevSource
                if (!u || u === "" || u === imageViewer.source)
                    return ""
                if (imageViewer.isGifUrl(u))
                    return ""
                if (!FileTypeUtils.checkIfImage(u))
                    return ""
                if (u === imageViewer.prefetchNextSource && u !== "")
                    return ""
                return u
            }
            source: effectiveSource
            sourceSize: {
                if (!imageViewer.dynamicResolutionEnabled)
                    return undefined
                if (imageViewer.computedSourceSize.width > 0 && imageViewer.computedSourceSize.height > 0)
                    return imageViewer.computedSourceSize
                return undefined
            }
        }
    }
    
    // Expose image properties for metadata
    property int paintedWidth: isGif ? animatedGif.paintedWidth : (photoBufferActive ? photoBuffer.paintedWidth : photo.paintedWidth)
    property int paintedHeight: isGif ? animatedGif.paintedHeight : (photoBufferActive ? photoBuffer.paintedHeight : photo.paintedHeight)
    property int sourceWidth: isGif ? animatedGif.sourceSize.width : (photoBufferActive ? photoBuffer.sourceSize.width : photo.sourceSize.width)
    property int sourceHeight: isGif ? animatedGif.sourceSize.height : (photoBufferActive ? photoBuffer.sourceSize.height : photo.sourceSize.height)
    // Actual image dimensions (not the requested sourceSize) - use for aspect ratio calculations
    // Prefer originalSourceWidth/Height (stored from implicitWidth/Height), fallback to implicitWidth/Height, then sourceSize
    property int actualImageWidth: isGif 
        ? (animatedGif.implicitWidth > 0 ? animatedGif.implicitWidth : animatedGif.sourceSize.width)
        : (originalSourceWidth > 0 
            ? originalSourceWidth 
            : (photoBufferActive 
                ? (photoBuffer.implicitWidth > 0 ? photoBuffer.implicitWidth : photoBuffer.sourceSize.width)
                : (photo.implicitWidth > 0 ? photo.implicitWidth : photo.sourceSize.width)))
    property int actualImageHeight: isGif 
        ? (animatedGif.implicitHeight > 0 ? animatedGif.implicitHeight : animatedGif.sourceSize.height)
        : (originalSourceHeight > 0 
            ? originalSourceHeight 
            : (photoBufferActive 
                ? (photoBuffer.implicitHeight > 0 ? photoBuffer.implicitHeight : photoBuffer.sourceSize.height)
                : (photo.implicitHeight > 0 ? photo.implicitHeight : photo.sourceSize.height)))
    property int frameCount: isGif ? animatedGif.frameCount : 0
    property int currentFrame: isGif ? animatedGif.currentFrame : 0
    property int status: isGif ? animatedGif.status : (photoBufferActive ? photoBuffer.status : photo.status)
}

