.pragma library

/**
 * MediaFormatUtils.js
 * Utility functions for media format handling and metadata extraction
 */

/**
 * Format time in milliseconds to MM:SS format
 */
function formatTime(ms) {
    if (!ms || ms <= 0) return "0:00"
    const totalSeconds = Math.floor(ms / 1000)
    const minutes = Math.floor(totalSeconds / 60)
    const seconds = totalSeconds % 60
    return minutes + ":" + (seconds < 10 ? "0" : "") + seconds
}

/**
 * Get metadata list for a media file
 * @param {Object} params - Object containing all necessary parameters:
 *   - currentImage: url
 *   - isVideo: bool
 *   - isAudio: bool
 *   - isGif: bool
 *   - isMarkdown: bool
 *   - isText: bool
 *   - isPdf: bool
 *   - isZip: bool
 *   - isModel: bool
 *   - zoomFactor: real
 *   - videoPlayer: object (videoPlayerLoader.item)
 *   - audioPlayer: object (audioPlayerLoader.item)
 *   - imageViewer: object (viewerLoader.item)
 *   - markdownViewer: object (markdownViewerLoader.item)
 *   - textViewer: object (textViewerLoader.item)
 *   - pdfViewer: object (pdfViewerLoader.item)
 *   - zipViewer: object (zipViewerLoader.item)
 *   - modelViewer: object (modelViewerLoader.item)
 *   - audioFormatInfo: object ({ sampleRate, bitrate })
 *   - qsTr: function (translation function)
 *   - MediaMetaData: object (Qt MediaMetaData enum)
 */
function getMetadataList(params) {
    if (!params || !params.currentImage || params.currentImage === "") return []
    
    const path = params.currentImage.toString().replace("file:///", "")
    const decodedPath = decodeURIComponent(path)
    const list = []
    const qsTr = params.qsTr || function(s) { return s }
    
    // File name
    const fileName = decodedPath.split(/[/\\]/).pop()
    list.push({ label: qsTr("File Name"), value: fileName })
    
    // File path (truncated if too long)
    const displayPath = decodedPath.length > 60 ? "..." + decodedPath.slice(-57) : decodedPath
    list.push({ label: qsTr("File Path"), value: displayPath })
    
    // File extension
    const extension = fileName.split('.').pop().toUpperCase()
    list.push({ label: qsTr("File Format"), value: extension })
    
    // Helper function to safely get metadata
    function getMeta(metaData, key) {
        if (!metaData) return null
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
    
    // File type
    if (params.isVideo) {
        list.push({ label: qsTr("Media Type"), value: qsTr("Video") })
        
        // Duration
        if (params.videoPlayer && params.videoPlayer.duration > 0) {
            list.push({ label: qsTr("Duration"), value: formatTime(params.videoPlayer.duration) })
        }
        
        // Get resolution from implicit size (always available)
        if (params.videoPlayer && params.videoPlayer.implicitWidth > 0 && params.videoPlayer.implicitHeight > 0) {
            list.push({ label: qsTr("Resolution"), value: Math.round(params.videoPlayer.implicitWidth) + " × " + Math.round(params.videoPlayer.implicitHeight) + " px" })
        }
        
        // Try to get metadata - Qt 6 metadata access
        const metaData = params.videoPlayer ? params.videoPlayer.metaData : null
        if (metaData) {
            const MediaMetaData = params.MediaMetaData || {}
            
            // Video codec
            const videoCodec = getMeta(metaData, MediaMetaData.VideoCodec) || getMeta(metaData, "VideoCodec")
            if (videoCodec) {
                list.push({ label: qsTr("Video Codec"), value: String(videoCodec) })
            }
            
            // Video bitrate
            const videoBitrate = getMeta(metaData, MediaMetaData.VideoBitRate) || getMeta(metaData, "VideoBitRate")
            if (videoBitrate) {
                const bitrate = parseInt(videoBitrate)
                if (!isNaN(bitrate) && bitrate > 0) {
                    const bitrateStr = bitrate >= 1000000 
                        ? (bitrate / 1000000).toFixed(2) + " Mbps"
                        : (bitrate >= 1000 ? (bitrate / 1000).toFixed(0) + " kbps" : bitrate + " bps")
                    list.push({ label: qsTr("Video Bitrate"), value: bitrateStr })
                }
            }
            
            // Frame rate
            const frameRate = getMeta(metaData, MediaMetaData.FrameRate) || getMeta(metaData, "FrameRate")
            if (frameRate) {
                const rate = parseFloat(frameRate)
                if (!isNaN(rate) && rate > 0) {
                    list.push({ label: qsTr("Frame Rate"), value: rate.toFixed(2) + " fps" })
                }
            }
            
            // Audio codec
            const audioCodec = getMeta(metaData, MediaMetaData.AudioCodec) || getMeta(metaData, "AudioCodec")
            if (audioCodec) {
                list.push({ label: qsTr("Audio Codec"), value: String(audioCodec) })
            }
            
            // Audio bitrate
            const audioBitrate = getMeta(metaData, MediaMetaData.AudioBitRate) || getMeta(metaData, "AudioBitRate")
            if (audioBitrate) {
                const bitrate = parseInt(audioBitrate)
                if (!isNaN(bitrate) && bitrate > 0) {
                    const bitrateStr = bitrate >= 1000000 
                        ? (bitrate / 1000000).toFixed(2) + " Mbps"
                        : (bitrate >= 1000 ? (bitrate / 1000).toFixed(0) + " kbps" : bitrate + " bps")
                    list.push({ label: qsTr("Audio Bitrate"), value: bitrateStr })
                }
            }
            
            // Sample rate
            const sampleRate = getMeta(metaData, MediaMetaData.SampleRate) || getMeta(metaData, "SampleRate")
            if (sampleRate) {
                const rate = parseInt(sampleRate)
                if (!isNaN(rate) && rate > 0) {
                    list.push({ label: qsTr("Sample Rate"), value: rate + " Hz" })
                }
            }
            
            // Channel count
            const channelCount = getMeta(metaData, MediaMetaData.ChannelCount) || getMeta(metaData, "ChannelCount")
            if (channelCount) {
                const channels = parseInt(channelCount)
                if (!isNaN(channels) && channels > 0) {
                    const channelStr = channels === 1 ? qsTr("Mono") : (channels === 2 ? qsTr("Stereo") : channels + " " + qsTr("channels"))
                    list.push({ label: qsTr("Audio Channels"), value: channelStr })
                }
            }
        }
        
        // Tracks
        if (params.videoPlayer) {
            list.push({ label: qsTr("Video Track"), value: params.videoPlayer.hasVideo ? qsTr("Yes") : qsTr("No") })
            list.push({ label: qsTr("Audio Track"), value: params.videoPlayer.hasAudio ? qsTr("Yes") : qsTr("No") })
            
            // Playback info
            if (params.videoPlayer.playbackRate !== undefined && params.videoPlayer.playbackRate !== 1.0) {
                list.push({ label: qsTr("Playback Rate"), value: params.videoPlayer.playbackRate.toFixed(2) + "x" })
            }
            if (params.videoPlayer.playbackState !== undefined) {
                const states = [qsTr("Stopped"), qsTr("Playing"), qsTr("Paused")]
                list.push({ label: qsTr("Playback State"), value: states[params.videoPlayer.playbackState] || qsTr("Unknown") })
            }
        }
    } else if (params.isAudio) {
        list.push({ label: qsTr("Media Type"), value: qsTr("Audio") })
        
        // Duration - try to get from C++ helper first (instant), fallback to audioPlayer
        let duration = 0
        if (params.ColorUtils && typeof params.ColorUtils.getAudioDuration === "function") {
            try {
                const instantDuration = params.ColorUtils.getAudioDuration(params.currentImage)
                if (instantDuration > 0) {
                    duration = instantDuration
                }
            } catch (e) {
                // Ignore errors, fall back to audioPlayer
            }
        }
        
        // Fallback to audioPlayer duration if C++ helper didn't work
        if (duration === 0 && params.audioPlayer && params.audioPlayer.duration > 0) {
            duration = params.audioPlayer.duration
        }
        
        if (duration > 0) {
            list.push({ label: qsTr("Duration"), value: formatTime(duration) })
        }
        
        // Try to get metadata
        const metaData = params.audioPlayer ? params.audioPlayer.metaData : null
        if (metaData) {
            const MediaMetaData = params.MediaMetaData || {}
            
            // Audio codec
            const audioCodec = getMeta(metaData, MediaMetaData.AudioCodec) || getMeta(metaData, "AudioCodec")
            if (audioCodec) {
                list.push({ label: qsTr("Audio Codec"), value: String(audioCodec) })
            }
            
            // Sample rate - get from C++ helper (FFmpeg directly)
            if (params.audioFormatInfo && params.audioFormatInfo.sampleRate > 0) {
                list.push({ label: qsTr("Sample Rate"), value: params.audioFormatInfo.sampleRate.toLocaleString() + " Hz" })
            } else {
                // Fallback to metadata
                const sampleRate = getMeta(metaData, MediaMetaData.SampleRate) || getMeta(metaData, "SampleRate")
                if (sampleRate) {
                    const rate = parseInt(sampleRate)
                    if (!isNaN(rate) && rate > 0) {
                        list.push({ label: qsTr("Sample Rate"), value: rate + " Hz" })
                    }
                }
            }
            
            // Audio bitrate - get from C++ helper (FFmpeg directly)
            if (params.audioFormatInfo && params.audioFormatInfo.bitrate > 0) {
                const bitrate = params.audioFormatInfo.bitrate
                const bitrateStr = bitrate >= 1000000 
                    ? (bitrate / 1000000).toFixed(2) + " Mbps"
                    : (bitrate >= 1000 ? (bitrate / 1000).toFixed(0) + " kbps" : bitrate + " bps")
                list.push({ label: qsTr("Bitrate"), value: bitrateStr })
            } else {
                // Fallback to metadata
                const audioBitrate = getMeta(metaData, MediaMetaData.AudioBitRate) || getMeta(metaData, "AudioBitRate")
                if (audioBitrate) {
                    const bitrate = parseInt(audioBitrate)
                    if (!isNaN(bitrate) && bitrate > 0) {
                        const bitrateStr = bitrate >= 1000000 
                            ? (bitrate / 1000000).toFixed(2) + " Mbps"
                            : (bitrate >= 1000 ? (bitrate / 1000).toFixed(0) + " kbps" : bitrate + " bps")
                        list.push({ label: qsTr("Bitrate"), value: bitrateStr })
                    }
                }
            }
            
            // Channel count
            const channelCount = getMeta(metaData, MediaMetaData.ChannelCount) || getMeta(metaData, "ChannelCount")
            if (channelCount) {
                const channels = parseInt(channelCount)
                if (!isNaN(channels) && channels > 0) {
                    const channelStr = channels === 1 ? qsTr("Mono") : (channels === 2 ? qsTr("Stereo") : channels + " " + qsTr("channels"))
                    list.push({ label: qsTr("Channels"), value: channelStr })
                }
            }
            
            // Title
            const title = getMeta(metaData, MediaMetaData.Title) || getMeta(metaData, "Title")
            if (title) {
                list.push({ label: qsTr("Title"), value: String(title) })
            }
            
            // Contributing Artists
            const contributingArtists = getMeta(metaData, MediaMetaData.ContributingArtist) || getMeta(metaData, "ContributingArtist") || getMeta(metaData, "Artist")
            if (contributingArtists) {
                list.push({ label: qsTr("Contributing Artists"), value: String(contributingArtists) })
            }
            
            // Album Artist
            const albumArtist = getMeta(metaData, MediaMetaData.AlbumArtist) || getMeta(metaData, "AlbumArtist")
            if (albumArtist) {
                list.push({ label: qsTr("Album Artist"), value: String(albumArtist) })
            }
            
            // Album
            const album = getMeta(metaData, MediaMetaData.AlbumTitle) || getMeta(metaData, "AlbumTitle") || getMeta(metaData, "Album")
            if (album) {
                list.push({ label: qsTr("Album"), value: String(album) })
            }
            
            // Track Number (#)
            const trackNumber = getMeta(metaData, MediaMetaData.TrackNumber) || getMeta(metaData, "TrackNumber")
            if (trackNumber) {
                const track = parseInt(trackNumber)
                if (!isNaN(track) && track > 0) {
                    list.push({ label: "#", value: String(track) })
                } else {
                    list.push({ label: "#", value: String(trackNumber) })
                }
            }
            
            // Genre
            const genre = getMeta(metaData, MediaMetaData.Genre) || getMeta(metaData, "Genre")
            if (genre) {
                list.push({ label: qsTr("Genre"), value: String(genre) })
            }
            
            // Year
            const year = getMeta(metaData, MediaMetaData.Year) || getMeta(metaData, "Year") || getMeta(metaData, MediaMetaData.Date) || getMeta(metaData, "Date")
            if (year) {
                // Try to extract year from date if it's a full date
                let yearValue = String(year)
                const yearMatch = yearValue.match(/\b(19|20)\d{2}\b/)
                if (yearMatch) {
                    yearValue = yearMatch[0]
                }
                list.push({ label: qsTr("Year"), value: yearValue })
            }
            
            // Date Released
            const dateReleased = getMeta(metaData, MediaMetaData.Date) || getMeta(metaData, "Date")
            if (dateReleased && dateReleased !== year) {
                list.push({ label: qsTr("Date Released"), value: String(dateReleased) })
            }
            
            // Encoded By
            const encodedBy = getMeta(metaData, MediaMetaData.Encoder) || getMeta(metaData, "Encoder") || getMeta(metaData, "EncodedBy")
            if (encodedBy) {
                list.push({ label: qsTr("Encoded By"), value: String(encodedBy) })
            }
            
            // Copyright
            const copyright = getMeta(metaData, MediaMetaData.Copyright) || getMeta(metaData, "Copyright")
            if (copyright) {
                list.push({ label: qsTr("Copyright"), value: String(copyright) })
            }
        }
        
        // Playback info
        if (params.audioPlayer && params.audioPlayer.playbackState !== undefined) {
            const states = [qsTr("Stopped"), qsTr("Playing"), qsTr("Paused")]
            list.push({ label: qsTr("Playback State"), value: states[params.audioPlayer.playbackState] || qsTr("Unknown") })
        }
    } else if (params.isGif) {
        list.push({ label: qsTr("Media Type"), value: qsTr("Animated GIF") })
        if (params.imageViewer && params.imageViewer.paintedWidth > 0 && params.imageViewer.paintedHeight > 0) {
            list.push({ label: qsTr("Dimensions"), value: params.imageViewer.paintedWidth + " × " + params.imageViewer.paintedHeight + " px" })
        }
        if (params.imageViewer && params.imageViewer.frameCount > 0) {
            list.push({ label: qsTr("Frame Count"), value: params.imageViewer.frameCount })
        }
        if (params.imageViewer && params.imageViewer.currentFrame !== undefined) {
            list.push({ label: qsTr("Current Frame"), value: params.imageViewer.currentFrame + 1 })
        }
    } else if (params.isMarkdown) {
        list.push({ label: qsTr("Media Type"), value: qsTr("Markdown") })
        if (params.markdownViewer && params.markdownViewer.content) {
            const lineCount = params.markdownViewer.content.split('\n').length
            const charCount = params.markdownViewer.content.length
            list.push({ label: qsTr("Lines"), value: lineCount })
            list.push({ label: qsTr("Characters"), value: charCount.toLocaleString() })
        }
    } else if (params.isText) {
        list.push({ label: qsTr("Media Type"), value: qsTr("Text") })
        if (params.textViewer && params.textViewer.lineCount > 0) {
            list.push({ label: qsTr("Lines"), value: params.textViewer.lineCount.toLocaleString() })
            list.push({ label: qsTr("Characters"), value: params.textViewer.characterCount.toLocaleString() })
            list.push({ label: qsTr("Status"), value: params.textViewer.modified ? qsTr("Modified") : qsTr("Saved") })
        }
    } else if (params.isPdf) {
        list.push({ label: qsTr("Media Type"), value: qsTr("PDF Document") })
        if (params.pdfViewer && params.pdfViewer.isLoaded) {
            list.push({ label: qsTr("Pages"), value: params.pdfViewer.pageCount.toLocaleString() })
            list.push({ label: qsTr("Current Page"), value: params.pdfViewer.currentPage + " / " + params.pdfViewer.pageCount })
            list.push({ label: qsTr("Zoom"), value: Math.round(params.pdfViewer.zoomLevel * 100) + "%" })
        }
    } else if (params.isZip) {
        list.push({ label: qsTr("Media Type"), value: qsTr("ZIP Archive") })
        if (params.zipViewer && params.zipViewer.displayFileName) {
            list.push({ label: qsTr("Archive"), value: params.zipViewer.displayFileName })
        }
        if (params.zipViewer && params.zipViewer.archiveReader) {
            list.push({ label: qsTr("Entries"), value: params.zipViewer.archiveReader.entries.length.toLocaleString() })
            list.push({ label: qsTr("Files"), value: params.zipViewer.archiveReader.fileCount.toLocaleString() })
            const total = params.zipViewer.archiveReader.totalUncompressedSize
            const totalMb = (total / (1024 * 1024)).toFixed(2)
            list.push({ label: qsTr("Uncompressed Size"), value: totalMb + " MB" })
            if (!params.zipViewer.archiveReader.loaded && params.zipViewer.archiveReader.errorString) {
                list.push({ label: qsTr("Status"), value: params.zipViewer.archiveReader.errorString })
            }
        }
    } else if (params.isModel) {
        list.push({ label: qsTr("Media Type"), value: qsTr("3D Model") })
        if (params.modelViewer) {
            list.push({ label: qsTr("Format Support"), value: params.modelViewer.modelSupported ? qsTr("Available") : qsTr("Unavailable") })
            if (params.modelViewer.modelSupported) {
                list.push({ label: qsTr("Load State"), value: params.modelViewer.modelLoaded ? qsTr("Loaded") : qsTr("Not Loaded") })
            }
            if (params.modelViewer.statusMessage) {
                list.push({ label: qsTr("Status"), value: params.modelViewer.statusMessage })
            }
        }
    } else {
        list.push({ label: qsTr("Media Type"), value: qsTr("Image") })
        if (params.imageViewer && params.imageViewer.paintedWidth > 0 && params.imageViewer.paintedHeight > 0) {
            list.push({ label: qsTr("Dimensions"), value: params.imageViewer.paintedWidth + " × " + params.imageViewer.paintedHeight + " px" })
        }
        if (params.imageViewer && params.imageViewer.status !== undefined) {
            const statuses = [qsTr("Null"), qsTr("Ready"), qsTr("Loading"), qsTr("Error")]
            list.push({ label: qsTr("Status"), value: statuses[params.imageViewer.status] || qsTr("Unknown") })
        }
    }
    
    // View info (only for visual media, excluding PDF which has its own zoom in metadata)
    if (!params.isAudio && !params.isMarkdown && !params.isText && !params.isPdf && !params.isZip && !params.isModel) {
        list.push({ label: qsTr("Zoom Level"), value: (params.zoomFactor * 100).toFixed(1) + "%" })
    }
    
    return list
}

