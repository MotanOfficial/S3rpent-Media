import QtMultimedia
import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import QtCore

ApplicationWindow {
    id: window
    width: 960
    height: 720
    minimumWidth: 640
    minimumHeight: 480
    visible: true
    title: qsTr("s3rp3nt media · Media Viewer")
    flags: Qt.Window | Qt.CustomizeWindowHint | Qt.WindowMinimizeButtonHint
            | Qt.WindowMaximizeButtonHint | Qt.WindowCloseButtonHint
    background: WindowBackground {
        accentColor: window.accentColor
        dynamicColoringEnabled: window.dynamicColoringEnabled
    }

    property url initialImage: ""
    property url currentImage: ""
    property bool isVideo: false
    property bool isGif: false
    property bool isAudio: false
    property bool isMarkdown: false
    property bool isText: false
    property bool isPdf: false
    property real zoomFactor: 1.0
    property real panX: 0
    property real panY: 0
    property bool dropActive: false
    property bool showingSettings: false
    property bool showingMetadata: false
    property real videoVolume: 1.0
    property real audioVolume: 1.0
    
    Settings {
        id: videoSettings
        category: "video"
        property alias volume: window.videoVolume
    }
    
    Settings {
        id: audioSettings
        category: "audio"
        property alias volume: window.audioVolume
    }
    property url audioCoverArt: ""
    property var audioFormatInfo: ({ sampleRate: 0, bitrate: 0 })
    property int lastAudioDuration: 0  // Track last duration to prevent infinite loops
    readonly property color fallbackAccent: "#121216"
    property color accentColor: fallbackAccent
    property color foregroundColor: "#f5f5f5"
    
    // Smooth transitions for dynamic accent color
    Behavior on accentColor { ColorAnimation { duration: 300; easing.type: Easing.OutCubic } }
    Behavior on foregroundColor { ColorAnimation { duration: 300; easing.type: Easing.OutCubic } }
    
    property bool dynamicColoringEnabled: true
    property bool betaAudioProcessingEnabled: true
    property real loadStartTime: 0
    property url pendingLoadSource: ""
    property string pendingLoadType: ""
    
    // Image navigation properties
    property var directoryImages: []
    property int currentImageIndex: 0
    property bool isImageType: !isVideo && !isAudio && !isMarkdown && !isText && !isPdf && currentImage.toString() !== ""
    property bool _navigatingImages: false  // Flag to prevent re-scanning during navigation
    property bool showImageControls: false  // Toggle for image controls visibility

    function adjustZoom(delta) {
        if (currentImage === "" || isVideo || isAudio || isMarkdown || isText || isPdf)
            return;
        imageViewer.adjustZoom(delta);
    }
    
    // Image navigation functions
    function loadDirectoryImages(imageUrl) {
        if (!imageUrl || imageUrl === "" || typeof ColorUtils === "undefined" || !ColorUtils.getImagesInDirectory)
            return
        
        const images = ColorUtils.getImagesInDirectory(imageUrl)
        if (images && images.length > 0) {
            directoryImages = images
            // Find current image index
            const currentPath = imageUrl.toString()
            for (let i = 0; i < images.length; i++) {
                if (images[i].toString() === currentPath) {
                    currentImageIndex = i
                    break
                }
            }
        } else {
            directoryImages = [imageUrl]
            currentImageIndex = 0
        }
    }
    
    function navigateToImage(index) {
        if (directoryImages.length === 0) return
        
        // Wrap around navigation
        if (index < 0) index = directoryImages.length - 1
        if (index >= directoryImages.length) index = 0
        
        currentImageIndex = index
        _navigatingImages = true  // Prevent re-scanning directory
        currentImage = directoryImages[index]
        _navigatingImages = false
    }
    
    function nextImage() {
        navigateToImage(currentImageIndex + 1)
    }
    
    function previousImage() {
        navigateToImage(currentImageIndex - 1)
    }

    function resetView() {
        if (!isVideo && !isAudio && !isMarkdown && !isText && !isPdf) {
            imageViewer.resetView()
        }
    }

    function clampPan() {
        if (window.currentImage === "") {
            panX = 0
            panY = 0
            return
        }

        if (window.isVideo || window.isMarkdown || window.isText || window.isPdf) {
            // Videos, markdown, text, and PDF don't need pan clamping
                panX = 0
                panY = 0
                return
        } else if (!window.isAudio) {
            // For images, use the imageViewer component
            imageViewer.clampPan()
        }
    }

    function luminance(color) {
        if (!color)
            return 0
        return 0.2126 * color.r + 0.7152 * color.g + 0.0722 * color.b
    }

    function useFallbackAccent() {
        accentColor = fallbackAccent
        foregroundColor = "#f5f5f5"
    }

    function updateAccentColor() {
        if (!dynamicColoringEnabled) {
            useFallbackAccent()
            return
        }
        
        // For audio files, use cover art if available
        let imageSource = currentImage
        if (isAudio && audioCoverArt && audioCoverArt !== "") {
            imageSource = audioCoverArt
        }
        
        if (!imageSource || imageSource === "") {
            useFallbackAccent()
            return
        }
        if (typeof ColorUtils === "undefined" || !ColorUtils.dominantColor) {
            useFallbackAccent()
            return
        }
        const sampled = ColorUtils.dominantColor(imageSource)
        if (!sampled || sampled.a === 0) {
            useFallbackAccent()
        } else {
            accentColor = sampled
            const lum = luminance(sampled)
            foregroundColor = lum > 0.65 ? "#050505" : "#f5f5f5"
        }
    }

    function checkIfVideo(url) {
        if (!url || url === "")
            return false
        const path = url.toString().toLowerCase()
        // GIFs are images, not videos
        return path.endsWith(".mp4") || path.endsWith(".avi") || path.endsWith(".mov") ||
               path.endsWith(".mkv") || path.endsWith(".webm") || path.endsWith(".m4v") ||
               path.endsWith(".flv") || path.endsWith(".wmv") || path.endsWith(".mpg") ||
               path.endsWith(".mpeg") || path.endsWith(".3gp")
    }
    
    function checkIfGif(url) {
        if (!url || url === "")
            return false
        const path = url.toString().toLowerCase()
        return path.endsWith(".gif")
    }
    
    function checkIfAudio(url) {
        if (!url || url === "")
            return false
        const path = url.toString().toLowerCase()
        return path.endsWith(".mp3") || path.endsWith(".wav") || path.endsWith(".flac") ||
               path.endsWith(".ogg") || path.endsWith(".aac") || path.endsWith(".m4a") ||
               path.endsWith(".wma") || path.endsWith(".opus") || path.endsWith(".mp2") ||
               path.endsWith(".mp1") || path.endsWith(".amr") || path.endsWith(".3gp")
    }
    
    function checkIfMarkdown(url) {
        if (!url || url === "")
            return false
        const path = url.toString().toLowerCase()
        return path.endsWith(".md") || path.endsWith(".markdown") || path.endsWith(".mdown") ||
               path.endsWith(".mkd") || path.endsWith(".mkdn")
    }
    
    function checkIfText(url) {
        if (!url || url === "")
            return false
        const path = url.toString().toLowerCase()
        // Plain text
        if (path.endsWith(".txt") || path.endsWith(".log") || path.endsWith(".nfo"))
            return true
        // Config files
        if (path.endsWith(".ini") || path.endsWith(".cfg") || path.endsWith(".conf") ||
            path.endsWith(".env") || path.endsWith(".properties"))
            return true
        // Data formats
        if (path.endsWith(".json") || path.endsWith(".xml") || path.endsWith(".yaml") ||
            path.endsWith(".yml") || path.endsWith(".csv") || path.endsWith(".toml"))
            return true
        // Web development
        if (path.endsWith(".html") || path.endsWith(".htm") || path.endsWith(".css") ||
            path.endsWith(".scss") || path.endsWith(".sass") || path.endsWith(".less") ||
            path.endsWith(".js") || path.endsWith(".jsx") || path.endsWith(".ts") ||
            path.endsWith(".tsx") || path.endsWith(".vue") || path.endsWith(".svelte"))
            return true
        // C/C++
        if (path.endsWith(".c") || path.endsWith(".cpp") || path.endsWith(".cc") ||
            path.endsWith(".cxx") || path.endsWith(".h") || path.endsWith(".hpp") ||
            path.endsWith(".hxx") || path.endsWith(".hh"))
            return true
        // Qt/QML
        if (path.endsWith(".qml") || path.endsWith(".qrc") || path.endsWith(".pro") ||
            path.endsWith(".pri") || path.endsWith(".ui"))
            return true
        // Python
        if (path.endsWith(".py") || path.endsWith(".pyw") || path.endsWith(".pyx") ||
            path.endsWith(".pyi") || path.endsWith(".pyd"))
            return true
        // Java/Kotlin
        if (path.endsWith(".java") || path.endsWith(".kt") || path.endsWith(".kts") ||
            path.endsWith(".gradle"))
            return true
        // C#/F#
        if (path.endsWith(".cs") || path.endsWith(".fs") || path.endsWith(".csproj") ||
            path.endsWith(".sln"))
            return true
        // Ruby
        if (path.endsWith(".rb") || path.endsWith(".erb") || path.endsWith(".rake") ||
            path.endsWith(".gemspec"))
            return true
        // Go
        if (path.endsWith(".go") || path.endsWith(".mod") || path.endsWith(".sum"))
            return true
        // Rust
        if (path.endsWith(".rs") || path.endsWith(".toml"))
            return true
        // PHP
        if (path.endsWith(".php") || path.endsWith(".phtml"))
            return true
        // Shell/Scripts
        if (path.endsWith(".sh") || path.endsWith(".bash") || path.endsWith(".zsh") ||
            path.endsWith(".fish") || path.endsWith(".bat") || path.endsWith(".cmd") ||
            path.endsWith(".ps1") || path.endsWith(".psm1"))
            return true
        // SQL
        if (path.endsWith(".sql") || path.endsWith(".sqlite"))
            return true
        // Swift/Objective-C
        if (path.endsWith(".swift") || path.endsWith(".m") || path.endsWith(".mm"))
            return true
        // Lua
        if (path.endsWith(".lua"))
            return true
        // Perl
        if (path.endsWith(".pl") || path.endsWith(".pm"))
            return true
        // R
        if (path.endsWith(".r") || path.endsWith(".rmd"))
            return true
        // Scala
        if (path.endsWith(".scala") || path.endsWith(".sc"))
            return true
        // Dart
        if (path.endsWith(".dart"))
            return true
        // Assembly
        if (path.endsWith(".asm") || path.endsWith(".s"))
            return true
        // Makefiles and build
        if (path.endsWith(".mk") || path.endsWith(".cmake") || path.endsWith(".ninja") ||
            path.endsWith("makefile") || path.endsWith("cmakelists.txt"))
            return true
        // Docker
        if (path.endsWith(".dockerfile") || path.endsWith("dockerfile") ||
            path.endsWith(".dockerignore"))
            return true
        // Git
        if (path.endsWith(".gitignore") || path.endsWith(".gitattributes") ||
            path.endsWith(".gitmodules"))
            return true
        // Other
        if (path.endsWith(".diff") || path.endsWith(".patch") || path.endsWith(".rst") ||
            path.endsWith(".tex") || path.endsWith(".bib") || path.endsWith(".cls") ||
            path.endsWith(".sty"))
            return true
        return false
    }
    
    function checkIfPdf(url) {
        if (!url || url === "")
            return false
        const path = url.toString().toLowerCase()
        return path.endsWith(".pdf")
    }
    
    function formatTime(ms) {
        if (!ms || ms <= 0) return "0:00"
        const totalSeconds = Math.floor(ms / 1000)
        const minutes = Math.floor(totalSeconds / 60)
        const seconds = totalSeconds % 60
        return minutes + ":" + (seconds < 10 ? "0" : "") + seconds
    }
    
    function extractAudioCoverArt() {
        if (!isAudio || !currentImage || currentImage === "") {
            audioCoverArt = ""
            return
        }
        
        // Use C++ helper to extract cover art (runs in background to avoid UI freeze)
        // The C++ function is still synchronous but we call it asynchronously via Qt.callLater
        if (typeof ColorUtils !== "undefined" && ColorUtils.extractCoverArt) {
            const coverArtUrl = ColorUtils.extractCoverArt(currentImage)
            if (coverArtUrl && coverArtUrl !== "") {
                audioCoverArt = coverArtUrl
                // Update accent color from cover art
                Qt.callLater(function() {
                    updateAccentColor()
                })
            } else {
                audioCoverArt = ""
            }
        } else {
            audioCoverArt = ""
        }
    }
    
    function getAudioFormatInfo(durationMs) {
        if (!isAudio || !currentImage || currentImage === "") {
            audioFormatInfo = { sampleRate: 0, bitrate: 0 }
            return
        }
        // If duration not provided, try to get it from audioPlayer
        if (durationMs === undefined || durationMs === 0) {
            if (audioPlayer && audioPlayer.duration > 0) {
                durationMs = audioPlayer.duration
                console.log("[Audio] Using duration from audioPlayer:", durationMs, "ms")
            } else {
                // Still get sample rate even without duration (bitrate will be 0)
                durationMs = 0
                console.log("[Audio] getAudioFormatInfo called without duration, will get sample rate only")
            }
        }
        
        // Use C++ helper to get audio format info directly from the media file
        if (typeof ColorUtils !== "undefined" && ColorUtils.getAudioFormatInfo) {
            console.log("[Audio] Calling getAudioFormatInfo with durationMs:", durationMs)
            const formatInfo = ColorUtils.getAudioFormatInfo(currentImage, durationMs)
            if (formatInfo) {
                console.log("[Audio] Format info received:", JSON.stringify(formatInfo), "durationMs:", durationMs)
                // Merge with existing to preserve values
                const newInfo = {
                    sampleRate: formatInfo.sampleRate || audioFormatInfo.sampleRate || 0,
                    bitrate: formatInfo.bitrate || audioFormatInfo.bitrate || 0
                }
                audioFormatInfo = newInfo
                console.log("[Audio] Updated audioFormatInfo:", JSON.stringify(audioFormatInfo))
                // Refresh metadata if popup is open
                if (showingMetadata) {
                    Qt.callLater(function() {
                        if (metadataPopup) {
                            metadataPopup.metadataList = getMetadataList()
                        }
                    })
                }
            } else {
                console.log("[Audio] Format info is null/undefined")
                if (!audioFormatInfo || (audioFormatInfo.sampleRate === 0 && audioFormatInfo.bitrate === 0)) {
                    audioFormatInfo = { sampleRate: 0, bitrate: 0 }
                }
            }
        } else {
            console.log("[Audio] ColorUtils.getAudioFormatInfo not available")
            audioFormatInfo = { sampleRate: 0, bitrate: 0 }
        }
    }

    function startLoadTimer(typeLabel) {
        if (!currentImage || currentImage === "") {
            loadStartTime = 0
            pendingLoadSource = ""
            pendingLoadType = ""
            return
        }
        loadStartTime = Date.now()
        pendingLoadSource = currentImage
        pendingLoadType = typeLabel || "Unknown"
        console.log("[Load] Started", pendingLoadType, "for", decodeURIComponent(currentImage.toString()))
    }

    function logLoadDuration(statusLabel, sourceUrl) {
        if (!loadStartTime)
            return
        const targetUrl = sourceUrl || currentImage
        if (pendingLoadSource && pendingLoadSource !== "" && targetUrl && targetUrl !== "" &&
                pendingLoadSource.toString() !== targetUrl.toString()) {
            return
        }
        const elapsed = Date.now() - loadStartTime
        console.log("[Load]", statusLabel, "in", elapsed, "ms (" + pendingLoadType + ")")
        loadStartTime = 0
        pendingLoadSource = ""
        pendingLoadType = ""
    }

    onCurrentImageChanged: {
        resetView()
        isVideo = checkIfVideo(currentImage)
        isGif = checkIfGif(currentImage)
        isAudio = checkIfAudio(currentImage)
        isMarkdown = checkIfMarkdown(currentImage)
        isText = checkIfText(currentImage)
        isPdf = checkIfPdf(currentImage)
        if (currentImage === "") {
            useFallbackAccent()
            startLoadTimer("")
            return
        }
        if (isVideo) {
            useFallbackAccent()
            startLoadTimer("Video")
        } else if (isAudio) {
            // Audio keeps color until cover art is detected
            startLoadTimer("Audio")
        } else if (isMarkdown) {
            useFallbackAccent()
            startLoadTimer("Markdown")
        } else if (isText) {
            useFallbackAccent()
            startLoadTimer("Text")
        } else if (isPdf) {
            useFallbackAccent()
            startLoadTimer("PDF")
        } else {
            // Images: keep previous color until new one is detected (smooth transition)
            startLoadTimer(isGif ? "GIF" : "Image")
        }
        if (!isVideo && !isAudio && !isMarkdown && !isText && !isPdf) {
            // Don't call updateAccentColor here - it's called async in onImageReady
            // Load all images from directory for navigation (only if not already navigating)
            if (!_navigatingImages) {
                loadDirectoryImages(currentImage)
                showImageControls = false  // Hide controls when loading new image
            }
        } else if (isVideo) {
            // Stop audio if playing
            audioPlayer.stop()
        } else if (isAudio) {
            // Stop video if playing
            videoPlayer.stop()
            // Reset cover art and format info
            audioCoverArt = ""
            audioFormatInfo = { sampleRate: 0, bitrate: 0 }
            // Try to extract cover art immediately (might be available)
            Qt.callLater(function() {
                extractAudioCoverArt()
                getAudioFormatInfo(0) // Get sample rate only
            })
        } else if (isMarkdown || isText || isPdf) {
            // Stop video and audio if they have a source and are playing
            if (videoPlayer && videoPlayer.source !== "") {
                const state = videoPlayer.playbackState
                if (state !== undefined && (state === MediaPlayer.PlayingState || state === MediaPlayer.PausedState || (typeof state === 'number' && state > 0))) {
                    videoPlayer.stop()
                }
            }
            if (audioPlayer && audioPlayer.source !== "") {
                const state = audioPlayer.playbackState
                if (state !== undefined && (state === MediaPlayer.PlayingState || state === MediaPlayer.PausedState || (typeof state === 'number' && state > 0))) {
                    audioPlayer.stop()
                }
            }
        }
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

    header: TitleBar {
        id: customTitleBar
        windowTitle: window.title
        currentFilePath: window.currentImage
        accentColor: window.accentColor
        foregroundColor: window.foregroundColor
        hasMedia: window.currentImage !== ""
        window: window
        
        onMetadataClicked: window.showingMetadata = !window.showingMetadata
        onSettingsClicked: window.showingSettings = !window.showingSettings
        onMinimizeClicked: window.showMinimized()
        onMaximizeClicked: {
                            if (window.visibility === Window.Maximized)
                                window.showNormal()
                            else
                                window.showMaximized()
                        }
        onCloseClicked: Qt.quit()
        onWindowMoveRequested: window.startSystemMove()
    }

    // Metadata popup
    MetadataPopup {
        id: metadataPopup
        parent: window.contentItem
        x: customTitleBar.x + 4
        y: customTitleBar.height + 4
        visible: window.showingMetadata && window.currentImage !== ""
        metadataList: window.getMetadataList()
        accentColor: window.accentColor
        foregroundColor: window.foregroundColor
        onVisibleChanged: {
            if (!visible) {
                window.showingMetadata = false
            }
        }
    }
    
    function getMetadataList() {
        if (window.currentImage === "") return []
        
        const path = window.currentImage.toString().replace("file:///", "")
        const decodedPath = decodeURIComponent(path)
        const list = []
        
        // File name
        const fileName = decodedPath.split(/[/\\]/).pop()
        list.push({ label: "File Name", value: fileName })
        
        // File path (truncated if too long)
        const displayPath = decodedPath.length > 60 ? "..." + decodedPath.slice(-57) : decodedPath
        list.push({ label: "File Path", value: displayPath })
        
        // File extension
        const extension = fileName.split('.').pop().toUpperCase()
        list.push({ label: "File Format", value: extension })
        
        // File type
        if (window.isVideo) {
            list.push({ label: "Media Type", value: "Video" })
            
            // Duration
            if (videoPlayer.duration > 0) {
                list.push({ label: "Duration", value: formatTime(videoPlayer.duration) })
            }
            
            // Get resolution from implicit size (always available)
            if (videoPlayer.implicitWidth > 0 && videoPlayer.implicitHeight > 0) {
                list.push({ label: "Resolution", value: Math.round(videoPlayer.implicitWidth) + " × " + Math.round(videoPlayer.implicitHeight) + " px" })
            }
            
            // Try to get metadata - Qt 6 metadata access
            const metaData = videoPlayer.metaData
            if (metaData) {
                // Helper to safely get metadata
                const getMeta = function(key) {
                    try {
                        // Try stringValue method first (Qt 6 way)
                        if (typeof metaData.stringValue === 'function') {
                            const result = metaData.stringValue(key)
                            if (result !== undefined && result !== null && result !== "") {
                                return result
                            }
                        }
                        // Try direct property access
                        if (metaData[key] !== undefined && metaData[key] !== null) {
                            return metaData[key]
                        }
                    } catch(e) {
                        // Ignore errors
                    }
                    return null
                }
                
                // Video codec
                const videoCodec = getMeta(MediaMetaData.VideoCodec) || getMeta("VideoCodec")
                if (videoCodec) {
                    list.push({ label: "Video Codec", value: String(videoCodec) })
                }
                
                // Video bitrate
                const videoBitrate = getMeta(MediaMetaData.VideoBitRate) || getMeta("VideoBitRate")
                if (videoBitrate) {
                    const bitrate = parseInt(videoBitrate)
                    if (!isNaN(bitrate) && bitrate > 0) {
                        const bitrateStr = bitrate >= 1000000 
                            ? (bitrate / 1000000).toFixed(2) + " Mbps"
                            : (bitrate >= 1000 ? (bitrate / 1000).toFixed(0) + " kbps" : bitrate + " bps")
                        list.push({ label: "Video Bitrate", value: bitrateStr })
                    }
                }
                
                // Frame rate
                const frameRate = getMeta(MediaMetaData.FrameRate) || getMeta("FrameRate")
                if (frameRate) {
                    const rate = parseFloat(frameRate)
                    if (!isNaN(rate) && rate > 0) {
                        list.push({ label: "Frame Rate", value: rate.toFixed(2) + " fps" })
                    }
                }
                
                // Audio codec
                const audioCodec = getMeta(MediaMetaData.AudioCodec) || getMeta("AudioCodec")
                if (audioCodec) {
                    list.push({ label: "Audio Codec", value: String(audioCodec) })
                }
                
                // Audio bitrate
                const audioBitrate = getMeta(MediaMetaData.AudioBitRate) || getMeta("AudioBitRate")
                if (audioBitrate) {
                    const bitrate = parseInt(audioBitrate)
                    if (!isNaN(bitrate) && bitrate > 0) {
                        const bitrateStr = bitrate >= 1000000 
                            ? (bitrate / 1000000).toFixed(2) + " Mbps"
                            : (bitrate >= 1000 ? (bitrate / 1000).toFixed(0) + " kbps" : bitrate + " bps")
                        list.push({ label: "Audio Bitrate", value: bitrateStr })
                    }
                }
                
                // Sample rate
                const sampleRate = getMeta(MediaMetaData.SampleRate) || getMeta("SampleRate")
                if (sampleRate) {
                    const rate = parseInt(sampleRate)
                    if (!isNaN(rate) && rate > 0) {
                        list.push({ label: "Sample Rate", value: rate + " Hz" })
                    }
                }
                
                // Channel count
                const channelCount = getMeta(MediaMetaData.ChannelCount) || getMeta("ChannelCount")
                if (channelCount) {
                    const channels = parseInt(channelCount)
                    if (!isNaN(channels) && channels > 0) {
                        const channelStr = channels === 1 ? "Mono" : (channels === 2 ? "Stereo" : channels + " channels")
                        list.push({ label: "Audio Channels", value: channelStr })
                    }
                }
            }
            
            // Tracks
            list.push({ label: "Video Track", value: videoPlayer.hasVideo ? "Yes" : "No" })
            list.push({ label: "Audio Track", value: videoPlayer.hasAudio ? "Yes" : "No" })
            
            // Playback info
            if (videoPlayer.playbackRate !== undefined && videoPlayer.playbackRate !== 1.0) {
                list.push({ label: "Playback Rate", value: videoPlayer.playbackRate.toFixed(2) + "x" })
            }
            if (videoPlayer.playbackState !== undefined) {
                const states = ["Stopped", "Playing", "Paused"]
                list.push({ label: "Playback State", value: states[videoPlayer.playbackState] || "Unknown" })
            }
        } else if (window.isAudio) {
            list.push({ label: "Media Type", value: "Audio" })
            
            // Duration
            if (audioPlayer.duration > 0) {
                list.push({ label: "Duration", value: formatTime(audioPlayer.duration) })
            }
            
            // Try to get metadata
            const metaData = audioPlayer.metaData
            if (metaData) {
                const getMeta = function(key) {
                    try {
                        if (typeof metaData.stringValue === 'function') {
                            const result = metaData.stringValue(key)
                            if (result !== undefined && result !== null && result !== "") {
                                return result
                            }
                        }
                        if (metaData[key] !== undefined && metaData[key] !== null) {
                            return metaData[key]
                        }
                    } catch(e) {
                        // Ignore errors
                    }
                    return null
                }
                
                // Audio codec
                const audioCodec = getMeta(MediaMetaData.AudioCodec) || getMeta("AudioCodec")
                if (audioCodec) {
                    list.push({ label: "Audio Codec", value: String(audioCodec) })
                }
                
                // Sample rate - get from C++ helper (FFmpeg directly)
                if (window.audioFormatInfo && window.audioFormatInfo.sampleRate > 0) {
                    list.push({ label: "Sample Rate", value: window.audioFormatInfo.sampleRate.toLocaleString() + " Hz" })
                } else {
                    // Fallback to metadata
                    const sampleRate = getMeta(MediaMetaData.SampleRate) || getMeta("SampleRate")
                    if (sampleRate) {
                        const rate = parseInt(sampleRate)
                        if (!isNaN(rate) && rate > 0) {
                            list.push({ label: "Sample Rate", value: rate + " Hz" })
                        }
                    }
                }
                
                // Audio bitrate - get from C++ helper (FFmpeg directly)
                if (window.audioFormatInfo && window.audioFormatInfo.bitrate > 0) {
                    const bitrate = window.audioFormatInfo.bitrate
                    const bitrateStr = bitrate >= 1000000 
                        ? (bitrate / 1000000).toFixed(2) + " Mbps"
                        : (bitrate >= 1000 ? (bitrate / 1000).toFixed(0) + " kbps" : bitrate + " bps")
                    list.push({ label: "Bitrate", value: bitrateStr })
                } else {
                    // Fallback to metadata
                const audioBitrate = getMeta(MediaMetaData.AudioBitRate) || getMeta("AudioBitRate")
                if (audioBitrate) {
                    const bitrate = parseInt(audioBitrate)
                    if (!isNaN(bitrate) && bitrate > 0) {
                        const bitrateStr = bitrate >= 1000000 
                            ? (bitrate / 1000000).toFixed(2) + " Mbps"
                            : (bitrate >= 1000 ? (bitrate / 1000).toFixed(0) + " kbps" : bitrate + " bps")
                        list.push({ label: "Bitrate", value: bitrateStr })
                    }
                    }
                }
                
                // Channel count
                const channelCount = getMeta(MediaMetaData.ChannelCount) || getMeta("ChannelCount")
                if (channelCount) {
                    const channels = parseInt(channelCount)
                    if (!isNaN(channels) && channels > 0) {
                        const channelStr = channels === 1 ? "Mono" : (channels === 2 ? "Stereo" : channels + " channels")
                        list.push({ label: "Channels", value: channelStr })
                    }
                }
                
                // Title
                const title = getMeta(MediaMetaData.Title) || getMeta("Title")
                if (title) {
                    list.push({ label: "Title", value: String(title) })
                }
                
                // Contributing Artists
                const contributingArtists = getMeta(MediaMetaData.ContributingArtist) || getMeta("ContributingArtist") || getMeta("Artist")
                if (contributingArtists) {
                    list.push({ label: "Contributing Artists", value: String(contributingArtists) })
                }
                
                // Album Artist
                const albumArtist = getMeta(MediaMetaData.AlbumArtist) || getMeta("AlbumArtist")
                if (albumArtist) {
                    list.push({ label: "Album Artist", value: String(albumArtist) })
                }
                
                // Album
                const album = getMeta(MediaMetaData.AlbumTitle) || getMeta("AlbumTitle") || getMeta("Album")
                if (album) {
                    list.push({ label: "Album", value: String(album) })
                }
                
                // Track Number (#)
                const trackNumber = getMeta(MediaMetaData.TrackNumber) || getMeta("TrackNumber")
                if (trackNumber) {
                    const track = parseInt(trackNumber)
                    if (!isNaN(track) && track > 0) {
                        list.push({ label: "#", value: String(track) })
                    } else {
                        list.push({ label: "#", value: String(trackNumber) })
                    }
                }
                
                // Genre
                const genre = getMeta(MediaMetaData.Genre) || getMeta("Genre")
                if (genre) {
                    list.push({ label: "Genre", value: String(genre) })
                }
                
                // Year
                const year = getMeta(MediaMetaData.Year) || getMeta("Year") || getMeta(MediaMetaData.Date) || getMeta("Date")
                if (year) {
                    // Try to extract year from date if it's a full date
                    let yearValue = String(year)
                    const yearMatch = yearValue.match(/\b(19|20)\d{2}\b/)
                    if (yearMatch) {
                        yearValue = yearMatch[0]
                    }
                    list.push({ label: "Year", value: yearValue })
                }
                
                // Date Released
                const dateReleased = getMeta(MediaMetaData.Date) || getMeta("Date")
                if (dateReleased && dateReleased !== year) {
                    list.push({ label: "Date Released", value: String(dateReleased) })
                }
                
                // Encoded By
                const encodedBy = getMeta(MediaMetaData.Encoder) || getMeta("Encoder") || getMeta("EncodedBy")
                if (encodedBy) {
                    list.push({ label: "Encoded By", value: String(encodedBy) })
                }
                
                // Copyright
                const copyright = getMeta(MediaMetaData.Copyright) || getMeta("Copyright")
                if (copyright) {
                    list.push({ label: "Copyright", value: String(copyright) })
                }
            }
            
            // Playback info
            if (audioPlayer.playbackState !== undefined) {
                const states = ["Stopped", "Playing", "Paused"]
                list.push({ label: "Playback State", value: states[audioPlayer.playbackState] || "Unknown" })
            }
        } else if (window.isGif) {
            list.push({ label: "Media Type", value: "Animated GIF" })
            if (imageViewer.paintedWidth > 0 && imageViewer.paintedHeight > 0) {
                list.push({ label: "Dimensions", value: imageViewer.paintedWidth + " × " + imageViewer.paintedHeight + " px" })
            }
            if (imageViewer.frameCount > 0) {
                list.push({ label: "Frame Count", value: imageViewer.frameCount })
            }
            if (imageViewer.currentFrame !== undefined) {
                list.push({ label: "Current Frame", value: imageViewer.currentFrame + 1 })
            }
        } else if (window.isMarkdown) {
            list.push({ label: "Media Type", value: "Markdown" })
            if (markdownViewer.content) {
                const lineCount = markdownViewer.content.split('\n').length
                const charCount = markdownViewer.content.length
                list.push({ label: "Lines", value: lineCount })
                list.push({ label: "Characters", value: charCount.toLocaleString() })
            }
        } else if (window.isText) {
            list.push({ label: "Media Type", value: "Text" })
            if (textViewer.lineCount > 0) {
                list.push({ label: "Lines", value: textViewer.lineCount.toLocaleString() })
                list.push({ label: "Characters", value: textViewer.characterCount.toLocaleString() })
                list.push({ label: "Status", value: textViewer.modified ? "Modified" : "Saved" })
            }
        } else if (window.isPdf) {
            list.push({ label: "Media Type", value: "PDF Document" })
            if (pdfViewer.isLoaded) {
                list.push({ label: "Pages", value: pdfViewer.pageCount.toLocaleString() })
                list.push({ label: "Current Page", value: pdfViewer.currentPage + " / " + pdfViewer.pageCount })
                list.push({ label: "Zoom", value: Math.round(pdfViewer.zoomLevel * 100) + "%" })
            }
        } else {
            list.push({ label: "Media Type", value: "Image" })
            if (imageViewer.paintedWidth > 0 && imageViewer.paintedHeight > 0) {
                list.push({ label: "Dimensions", value: imageViewer.paintedWidth + " × " + imageViewer.paintedHeight + " px" })
            }
            if (imageViewer.status !== undefined) {
                const statuses = ["Null", "Ready", "Loading", "Error"]
                list.push({ label: "Status", value: statuses[imageViewer.status] || "Unknown" })
            }
        }
        
        // View info (only for visual media, excluding PDF which has its own zoom in metadata)
        if (!window.isAudio && !window.isMarkdown && !window.isText && !window.isPdf) {
            list.push({ label: "Zoom Level", value: (window.zoomFactor * 100).toFixed(1) + "%" })
        }
        
        return list
    }

    StackLayout {
        id: pageStack
        anchors.fill: parent
        currentIndex: window.showingSettings ? 1 : 0

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            Rectangle {
                id: viewer
                anchors.fill: parent
                color: Qt.darker(window.accentColor, 1.15)
                clip: true
                focus: true
                property int padding: 0

                WheelHandler {
                    id: wheel
                    target: null
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onWheel: function(event) {
                        const delta = event.angleDelta && event.angleDelta.y !== 0
                                      ? event.angleDelta.y
                                      : (event.pixelDelta ? event.pixelDelta.y * 8 : 0)
                        if (delta !== 0)
                            window.adjustZoom(delta)
                    }
                    enabled: window.currentImage.toString() !== "" && !window.isVideo && !window.isAudio && !window.isMarkdown && !window.isText && !window.isPdf
                }

                TapHandler {
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    gesturePolicy: TapHandler.ReleaseWithinBounds
                    onDoubleTapped: window.resetView()
                    onTapped: {
                        // Toggle image controls on single tap
                        if (window.isImageType && window.currentImage.toString() !== "") {
                            window.showImageControls = !window.showImageControls
                            if (window.showImageControls) {
                                imageControlsHideTimer.restart()
                            }
                        }
                    }
                    enabled: window.currentImage.toString() !== "" && !window.isVideo
                }
                
                TapHandler {
                    id: videoTapHandler
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    gesturePolicy: TapHandler.ReleaseWithinBounds
                    onTapped: {
                        if (window.isVideo && window.currentImage !== "") {
                            // Toggle play/pause based on playbackState
                            const wasPlaying = videoPlayer.playbackState === MediaPlayer.PlayingState
                            if (wasPlaying) {
                                videoPlayer.pause()
                            } else {
                                videoPlayer.play()
                            }
                        }
                    }
                    enabled: window.currentImage !== "" && window.isVideo
                }

                DragHandler {
                    id: drag
                    property real prevX: 0
                    property real prevY: 0
                    target: null
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad | PointerDevice.Stylus
                    enabled: window.currentImage.toString() !== "" && !window.isVideo && !window.isAudio && !window.isMarkdown && !window.isText && !window.isPdf
                    onActiveChanged: {
                        prevX = translation.x
                        prevY = translation.y
                    }
                    onTranslationChanged: {
                        const factor = imageViewer.zoomFactor === 0 ? 1 : imageViewer.zoomFactor
                        imageViewer.panX += (translation.x - prevX) / factor
                        imageViewer.panY += (translation.y - prevY) / factor
                        prevX = translation.x
                        prevY = translation.y
                        imageViewer.clampPan()
                    }
                }

                DropArea {
                    anchors.fill: parent
                    keys: [ "text/uri-list" ]
                    onEntered: window.dropActive = true
                    onExited: window.dropActive = false
                    onDropped: function(drop) {
                        window.dropActive = false
                        if (drop.hasUrls && drop.urls.length > 0) {
                            window.currentImage = drop.urls[0]
                            drop.acceptProposedAction()
                        }
                    }
                }
                
                // Empty state placeholder
                Column {
                    id: emptyStatePlaceholder
                    anchors.centerIn: parent
                    spacing: 20
                    visible: window.currentImage.toString() === "" && !window.showingSettings
                    opacity: visible ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                    
                    // Icon container with subtle glow
                    Rectangle {
                        width: 120
                        height: 120
                        radius: 60
                        color: Qt.rgba(1, 1, 1, 0.05)
                        border.width: 2
                        border.color: Qt.rgba(1, 1, 1, 0.1)
                        anchors.horizontalCenter: parent.horizontalCenter
                        
                        // Decorative ring
                        Rectangle {
                            anchors.centerIn: parent
                            width: 100
                            height: 100
                            radius: 50
                            color: "transparent"
                            border.width: 1
                            border.color: Qt.rgba(1, 1, 1, 0.08)
                        }
                        
                        Text {
                            anchors.centerIn: parent
                            text: "📁"
                            font.pixelSize: 48
                            opacity: 0.7
                        }
                    }
                    
                    // Main text
                    Text {
                        text: "No media loaded"
                        font.pixelSize: 24
                        font.weight: Font.Medium
                        font.family: "Segoe UI"
                        color: Qt.rgba(1, 1, 1, 0.8)
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                    
                    // Subtitle
                    Text {
                        text: "Drag & drop a file here to get started"
                        font.pixelSize: 14
                        font.family: "Segoe UI"
                        color: Qt.rgba(1, 1, 1, 0.5)
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                    
                    // Or divider
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 12
                        
                        Rectangle {
                            width: 40
                            height: 1
                            color: Qt.rgba(1, 1, 1, 0.2)
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        
                        Text {
                            text: "or"
                            font.pixelSize: 12
                            font.family: "Segoe UI"
                            color: Qt.rgba(1, 1, 1, 0.4)
                        }
                        
                        Rectangle {
                            width: 40
                            height: 1
                            color: Qt.rgba(1, 1, 1, 0.2)
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                    
                    // Open file button
                    Rectangle {
                        width: 160
                        height: 40
                        radius: 20
                        color: openFileMouseArea.containsMouse ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(1, 1, 1, 0.1)
                        border.width: 1
                        border.color: Qt.rgba(1, 1, 1, 0.2)
                        anchors.horizontalCenter: parent.horizontalCenter
                        
                        Behavior on color { ColorAnimation { duration: 150 } }
                        
                        Row {
                            anchors.centerIn: parent
                            spacing: 8
                            
                            Text {
                                text: "📂"
                                font.pixelSize: 16
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            
                            Text {
                                text: "Browse files"
                                font.pixelSize: 14
                                font.family: "Segoe UI"
                                font.weight: Font.Medium
                                color: Qt.rgba(1, 1, 1, 0.9)
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                        
                        MouseArea {
                            id: openFileMouseArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: openDialog.open()
                        }
                    }
                    
                    // Supported formats hint
                    Text {
                        text: "Images • Videos • Audio • Documents"
                        font.pixelSize: 11
                        font.family: "Segoe UI"
                        color: Qt.rgba(1, 1, 1, 0.3)
                        anchors.horizontalCenter: parent.horizontalCenter
                        topPadding: 8
                    }
                }

                // Image viewer component
                ImageViewer {
                    id: imageViewer
                        anchors.fill: parent
                    source: (!window.isVideo && !window.isAudio && !window.isMarkdown && !window.isText && !window.isPdf && window.currentImage !== "") ? window.currentImage : ""
                    isGif: window.isGif
                    zoomFactor: window.zoomFactor
                    panX: window.panX
                    panY: window.panY
                    accentColor: window.accentColor
                    visible: !window.isVideo && !window.isAudio && !window.isMarkdown && !window.isText && !window.isPdf && window.currentImage !== ""
                    
                    onImageReady: {
                        // Log duration FIRST so image appears immediately
                        window.logLoadDuration(window.isGif ? "GIF ready" : "Image ready", imageViewer.source)
                        // Then update accent color after a short delay (doesn't block image display)
                        accentColorTimer.restart()
                    }
                    
                    Timer {
                        id: accentColorTimer
                        interval: 50  // Small delay to let image render first
                        onTriggered: window.updateAccentColor()
                    }
                    
                    onPaintedSizeChanged: {
                            window.clampPan()
                        }
                    
                    Binding {
                        target: window
                        property: "zoomFactor"
                        value: imageViewer.zoomFactor
                        when: !window.isVideo && !window.isAudio && !window.isMarkdown && !window.isText && !window.isPdf
                    }
                    
                    Binding {
                        target: window
                        property: "panX"
                        value: imageViewer.panX
                        when: !window.isVideo && !window.isAudio && !window.isMarkdown && !window.isText && !window.isPdf
                    }
                    
                    Binding {
                        target: window
                        property: "panY"
                        value: imageViewer.panY
                        when: !window.isVideo && !window.isAudio && !window.isMarkdown && !window.isText && !window.isPdf
                    }
                }
                
                // Image controls bar
                ImageControls {
                    id: imageControls
                    anchors.bottom: parent.bottom
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottomMargin: 24
                    width: Math.min(500, parent.width - 48)
                    height: 48
                    visible: window.isImageType && window.showImageControls && window.currentImage.toString() !== "" && !window.showingSettings && !window.showingMetadata
                    z: 50
                    
                    currentIndex: window.currentImageIndex
                    totalImages: window.directoryImages.length
                    zoomFactor: window.zoomFactor
                    accentColor: window.accentColor
                    
                    onPreviousClicked: {
                        window.previousImage()
                        imageControlsHideTimer.restart()
                    }
                    onNextClicked: {
                        window.nextImage()
                        imageControlsHideTimer.restart()
                    }
                    onZoomInClicked: {
                        window.adjustZoom(100)
                        imageControlsHideTimer.restart()
                    }
                    onZoomOutClicked: {
                        window.adjustZoom(-100)
                        imageControlsHideTimer.restart()
                    }
                    onFitToWindowClicked: {
                        imageViewer.fitToWindow()
                        imageControlsHideTimer.restart()
                    }
                    onActualSizeClicked: {
                        imageViewer.actualSize()
                        imageControlsHideTimer.restart()
                    }
                    onRotateLeftClicked: {
                        imageViewer.rotateLeft()
                        imageControlsHideTimer.restart()
                    }
                    onRotateRightClicked: {
                        imageViewer.rotateRight()
                        imageControlsHideTimer.restart()
                    }
                    
                    // Fade in/out animation
                    opacity: visible ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 200 } }
                }
                
                // Auto-hide timer for image controls
                Timer {
                    id: imageControlsHideTimer
                    interval: 3000
                    onTriggered: window.showImageControls = false
                }
                
                // Pre-load next image for faster navigation
                Image {
                    id: preloadNext
                    visible: false
                    asynchronous: true
                    cache: true
                    source: {
                        if (!window.isImageType || window.directoryImages.length <= 1) return ""
                        const nextIndex = (window.currentImageIndex + 1) % window.directoryImages.length
                        return window.directoryImages[nextIndex] || ""
                    }
                }
                
                // Pre-load previous image for faster navigation
                Image {
                    id: preloadPrev
                    visible: false
                    asynchronous: true
                    cache: true
                    source: {
                        if (!window.isImageType || window.directoryImages.length <= 1) return ""
                        const prevIndex = (window.currentImageIndex - 1 + window.directoryImages.length) % window.directoryImages.length
                        return window.directoryImages[prevIndex] || ""
                    }
                }
                
                // Left navigation arrow
                Rectangle {
                    id: leftArrow
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 12
                    width: 32
                    height: 48
                    radius: 8
                    color: leftArrowMouse.containsMouse 
                           ? Qt.rgba(0, 0, 0, 0.7) 
                           : Qt.rgba(0, 0, 0, 0.4)
                    visible: window.isImageType && window.showImageControls && window.currentImage.toString() !== "" && window.directoryImages.length > 1 && !window.showingSettings && !window.showingMetadata
                    opacity: leftArrowMouse.containsMouse ? 1 : 0.5
                    z: 50
                    
                    Behavior on color { ColorAnimation { duration: 150 } }
                    Behavior on opacity { NumberAnimation { duration: 150 } }
                    
                    Text {
                        anchors.centerIn: parent
                        text: "‹"
                        color: "#ffffff"
                        font.pixelSize: 24
                        font.bold: true
                    }
                    
                    MouseArea {
                        id: leftArrowMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            window.previousImage()
                            imageControlsHideTimer.restart()
                        }
                    }
                }
                
                // Right navigation arrow
                Rectangle {
                    id: rightArrow
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.rightMargin: 12
                    width: 32
                    height: 48
                    radius: 8
                    color: rightArrowMouse.containsMouse 
                           ? Qt.rgba(0, 0, 0, 0.7) 
                           : Qt.rgba(0, 0, 0, 0.4)
                    visible: window.isImageType && window.showImageControls && window.currentImage.toString() !== "" && window.directoryImages.length > 1 && !window.showingSettings && !window.showingMetadata
                    opacity: rightArrowMouse.containsMouse ? 1 : 0.5
                    z: 50
                    
                    Behavior on color { ColorAnimation { duration: 150 } }
                    Behavior on opacity { NumberAnimation { duration: 150 } }
                    
                    Text {
                        anchors.centerIn: parent
                        text: "›"
                        color: "#ffffff"
                        font.pixelSize: 24
                        font.bold: true
                    }
                    
                    MouseArea {
                        id: rightArrowMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            window.nextImage()
                            imageControlsHideTimer.restart()
                        }
                    }
                }

                // Video player component
                VideoPlayer {
                    id: videoPlayer
                    anchors.fill: parent
                    source: window.isVideo ? window.currentImage : ""
                    volume: window.videoVolume
                    showControls: true
                    accentColor: window.accentColor
                    foregroundColor: window.foregroundColor
                    visible: window.isVideo && window.currentImage !== ""
                    
                    onDurationAvailable: {
                            if (videoPlayer.duration > 0) {
                                console.log("[Video] Duration available:", videoPlayer.duration, "ms")
                                window.logLoadDuration("Video ready", videoPlayer.source)
                                if (window.showingMetadata) {
                                    Qt.callLater(function() {
                                        if (metadataPopup) {
                                            metadataPopup.metadataList = window.getMetadataList()
                                        }
                                    })
                            }
                        }
                    }
                    
                    Binding {
                        target: window
                        property: "videoVolume"
                        value: videoPlayer.volume
                    }
                }
                // Audio player component
                AudioPlayer {
                    id: audioPlayer
                            anchors.fill: parent
                    source: window.isAudio ? window.currentImage : ""
                    volume: window.audioVolume
                    showControls: true
                    coverArt: window.audioCoverArt
                    accentColor: window.accentColor
                    foregroundColor: window.foregroundColor
                    showingMetadata: window.showingMetadata
                    visible: window.isAudio && window.currentImage !== ""
                    betaAudioProcessingEnabled: window.betaAudioProcessingEnabled
                    
                    onDurationAvailable: {
                        if (audioPlayer.duration > 0) {
                            console.log("[Audio] Duration available:", audioPlayer.duration, "ms")
                            // Debounce: Only update if duration changed significantly
                            // This prevents infinite loops from rapid duration updates
                            const lastDuration = window.lastAudioDuration || 0
                            if (Math.abs(audioPlayer.duration - lastDuration) > 100) {
                                window.lastAudioDuration = audioPlayer.duration
                                window.logLoadDuration("Audio ready", audioPlayer.source)
                                // Get format info with the actual duration (async to avoid blocking)
                                Qt.callLater(function() {
                                    window.getAudioFormatInfo(audioPlayer.duration)
                                })
                                // Extract cover art when duration is available (metadata should be ready)
                                window.extractAudioCoverArt()
                                // Always refresh metadata list when duration is available
                                Qt.callLater(function() {
                                    if (metadataPopup) {
                                        metadataPopup.metadataList = window.getMetadataList()
                                    }
                                })
                            }
                        }
                    }
                    
                    Connections {
                        target: window
                        function onAudioCoverArtChanged() {
                            // Cover art is already bound via coverArt: window.audioCoverArt
                            // Just update accent color when cover art changes
                            if (window.audioCoverArt !== "") {
                                Qt.callLater(function() {
                                    window.updateAccentColor()
                                })
                            }
                        }
                    }
                    
                    Binding {
                        target: window
                        property: "audioVolume"
                        value: audioPlayer.volume
                    }
                }
                
                // Markdown viewer component
                MarkdownViewer {
                    id: markdownViewer
                    anchors.fill: parent
                    source: window.isMarkdown ? window.currentImage : ""
                    accentColor: window.accentColor
                    foregroundColor: window.foregroundColor
                    visible: window.isMarkdown && window.currentImage !== ""
                }

                Connections {
                    target: markdownViewer
                    function onContentChanged() {
                        if (window.isMarkdown && markdownViewer.content !== "" && markdownViewer.source !== "") {
                            window.logLoadDuration("Markdown ready", markdownViewer.source)
                        }
                    }
                }
                
                // Text viewer component
                TextViewer {
                    id: textViewer
                    anchors.fill: parent
                    source: window.isText ? window.currentImage : ""
                    accentColor: window.accentColor
                    foregroundColor: window.foregroundColor
                    visible: window.isText && window.currentImage !== ""
                    
                    onSaved: {
                        saveToast.show("File saved successfully", false)
                    }
                    
                    onSaveError: function(message) {
                        saveToast.show(message, true)
                    }
                }

                Connections {
                    target: textViewer
                    function onContentLoaded() {
                        if (window.isText && textViewer.content !== "" && textViewer.source !== "") {
                            window.logLoadDuration("Text ready", textViewer.source)
                        }
                    }
                }
                
                // PDF viewer component
                PdfViewer {
                    id: pdfViewer
                    anchors.fill: parent
                    source: window.isPdf ? window.currentImage : ""
                    accentColor: window.accentColor
                    foregroundColor: window.foregroundColor
                    visible: window.isPdf && window.currentImage !== ""
                    
                    onLoaded: {
                        window.logLoadDuration("PDF ready", pdfViewer.source)
                        if (window.showingMetadata) {
                            Qt.callLater(function() {
                                if (metadataPopup) {
                                    metadataPopup.metadataList = window.getMetadataList()
                                }
                            })
                        }
                    }
                }
                
                // Save toast notification
                Rectangle {
                    id: saveToast
                    anchors.bottom: parent.bottom
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottomMargin: 32
                    width: toastText.width + 32
                    height: 40
                    radius: 20
                    color: toastError ? Qt.rgba(200, 50, 50, 0.9) : Qt.rgba(50, 150, 50, 0.9)
                    opacity: 0
                    visible: opacity > 0
                    z: 100
                    
                    property bool toastError: false
                    
                    function show(message, isError) {
                        toastText.text = message
                        toastError = isError
                        toastAnimation.restart()
                    }
                    
                    Text {
                        id: toastText
                        anchors.centerIn: parent
                        color: "#ffffff"
                        font.pixelSize: 14
                        font.family: "Segoe UI"
                    }
                    
                    SequentialAnimation {
                        id: toastAnimation
                        NumberAnimation { target: saveToast; property: "opacity"; to: 1; duration: 200 }
                        PauseAnimation { duration: 2000 }
                        NumberAnimation { target: saveToast; property: "opacity"; to: 0; duration: 300 }
                    }
                }

                Rectangle {
                    anchors.fill: parent
                    color: Qt.rgba(window.accentColor.r, window.accentColor.g, window.accentColor.b, 0.25)
                    visible: window.dropActive
                    border.color: Qt.rgba(window.accentColor.r, window.accentColor.g, window.accentColor.b, 0.5)
                    border.width: 2
                }

                Text {
                    anchors.centerIn: parent
                    visible: window.currentImage === ""
                    color: window.dropActive ? "#050505" : window.foregroundColor
                    font.pixelSize: 22
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: window.dropActive ? qsTr("Drop media to open") : qsTr("Drag & drop media\nor press Ctrl+O")
                }
            }
        }

        SettingsPage {
            id: settingsPage
            Layout.fillWidth: true
            Layout.fillHeight: true
            accentColor: window.accentColor
            foregroundColor: window.foregroundColor
            dynamicColoringEnabled: window.dynamicColoringEnabled
            
            onBackClicked: window.showingSettings = false
            onDynamicColoringToggled: function(enabled) {
                window.dynamicColoringEnabled = enabled
                        window.updateAccentColor()
                    }
        }
    }

    FileDialog {
        id: openDialog
        title: qsTr("Select media")
        fileMode: FileDialog.OpenFile
        nameFilters: [
            qsTr("All Supported (*.png *.jpg *.jpeg *.bmp *.gif *.webp *.mp4 *.avi *.mov *.mkv *.webm *.m4v *.mp3 *.wav *.flac *.ogg *.aac *.m4a *.wma *.opus *.md *.markdown *.txt *.log *.json *.xml *.yaml *.yml *.csv *.html *.css *.js *.ts *.cpp *.c *.h *.hpp *.py *.java *.qml *.rs *.go *.rb *.php *.sh *.sql *.pdf)"),
            qsTr("Images (*.png *.jpg *.jpeg *.bmp *.gif *.webp)"),
            qsTr("Videos (*.mp4 *.avi *.mov *.mkv *.webm *.m4v *.flv *.wmv *.mpg *.mpeg *.3gp)"),
            qsTr("Audio (*.mp3 *.wav *.flac *.ogg *.aac *.m4a *.wma *.opus *.mp2 *.mp1 *.amr)"),
            qsTr("PDF Documents (*.pdf)"),
            qsTr("Markdown (*.md *.markdown *.mdown *.mkd *.mkdn)"),
            qsTr("Code - Web (*.html *.htm *.css *.scss *.sass *.less *.js *.jsx *.ts *.tsx *.vue *.svelte *.json)"),
            qsTr("Code - C/C++/Qt (*.c *.cpp *.cc *.cxx *.h *.hpp *.hxx *.qml *.qrc *.pro *.pri *.ui)"),
            qsTr("Code - Python (*.py *.pyw *.pyx *.pyi)"),
            qsTr("Code - Java/Kotlin (*.java *.kt *.kts *.gradle)"),
            qsTr("Code - Other (*.rs *.go *.rb *.php *.swift *.cs *.fs *.scala *.lua *.pl *.r *.dart *.sh *.bat *.ps1 *.sql)"),
            qsTr("Config (*.ini *.cfg *.conf *.env *.yaml *.yml *.toml *.xml *.properties)"),
            qsTr("Text (*.txt *.log *.nfo *.csv *.diff *.patch)"),
            qsTr("All files (*)")
        ]
        onAccepted: window.currentImage = selectedFile
    }

    Shortcut {
        sequences: [ StandardKey.Open ]
        onActivated: openDialog.open()
    }
    
    // Image navigation shortcuts
    Shortcut {
        sequence: "Left"
        enabled: window.isImageType && window.directoryImages.length > 1
        onActivated: window.previousImage()
    }
    
    Shortcut {
        sequence: "Right"
        enabled: window.isImageType && window.directoryImages.length > 1
        onActivated: window.nextImage()
    }
    
    Shortcut {
        sequence: "Home"
        enabled: window.isImageType && window.directoryImages.length > 1
        onActivated: window.navigateToImage(0)
    }
    
    Shortcut {
        sequence: "End"
        enabled: window.isImageType && window.directoryImages.length > 1
        onActivated: window.navigateToImage(window.directoryImages.length - 1)
    }

    Component.onCompleted: {
        if (initialImage !== "")
            currentImage = initialImage
        else
            updateAccentColor()
    }
}


