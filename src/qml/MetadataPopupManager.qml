import QtQuick
import QtQuick.Controls
import QtMultimedia

// MetadataPopupManager - Manages the metadata popup component
Item {
    id: metadataPopupManager
    
    required property Window mainWindow
    required property var customTitleBar
    required property var pageStack  // MainContentArea component (has id: pageStack in Main.qml)
    
    // Computed metadata list that updates when needed
    property var computedMetadataList: []
    
    // Timer to update metadata list during playback (for duration/time updates)
    property var _playbackUpdateTimer: null
    
    // Function to update metadata list
    function updateMetadataList() {
        if (metadataPopupManager.mainWindow.currentImage !== "") {
            // Access getMetadataList directly from the main window
            if (metadataPopupManager.mainWindow.getMetadataList && typeof metadataPopupManager.mainWindow.getMetadataList === "function") {
                try {
                    const result = metadataPopupManager.mainWindow.getMetadataList()
                    metadataPopupManager.computedMetadataList = result || []
                } catch (e) {
                    metadataPopupManager.computedMetadataList = []
                }
            } else {
                metadataPopupManager.computedMetadataList = []
            }
        } else {
            metadataPopupManager.computedMetadataList = []
        }
    }
    
    // Timer to debounce metadata updates when switching files
    // Longer interval to allow audio duration to load
    Timer {
        id: metadataUpdateTimer
        interval: 500  // Increased to 500ms to allow audio duration to load
        onTriggered: {
            if (metadataPopupManager.mainWindow.showingMetadata) {
                metadataPopupManager.updateMetadataList()
            } else {
            }
        }
    }
    
    // Update metadata list when popup becomes visible or current image changes
    Connections {
        target: metadataPopupManager.mainWindow
        function onShowingMetadataChanged() {
            
            // Start/stop playback update timer based on popup visibility
            if (metadataPopupManager._playbackUpdateTimer) {
                if (metadataPopupManager.mainWindow.showingMetadata && 
                    metadataPopupManager.mainWindow.isAudio &&
                    metadataPopupManager.audioPlayer) {
                    metadataPopupManager._playbackUpdateTimer.start()
                } else {
                    metadataPopupManager._playbackUpdateTimer.stop()
                    
                    // CRITICAL: When popup closes, force AudioPlayer UI refresh
                    // The AudioPlayer's mainContent is hidden when showingMetadata is true,
                    // so we need to refresh it when the popup closes to ensure UI renders
                    if (metadataPopupManager.mainWindow.isAudio && 
                        metadataPopupManager.audioPlayer) {
                        
                        // CRITICAL: When popup closes, the AudioPlayer's mainContent becomes visible
                        // The Text elements use bindings that might not re-evaluate when they become visible.
                        // We need to force the bindings to re-evaluate by triggering a property change.
                        Qt.callLater(function() {
                            if (metadataPopupManager.audioPlayer) {
                                // CRITICAL: First ensure showingMetadata is false so UI becomes visible
                                // The mainWindow.showingMetadata should already be false, but audioPlayer.showingMetadata
                                // might be out of sync, so we force it to match
                                const currentShowing = metadataPopupManager.audioPlayer.showingMetadata
                                
                                // Force showingMetadata to false to make UI visible
                                if (currentShowing) {
                                    metadataPopupManager.audioPlayer.showingMetadata = false
                                }
                                
                                // Force metadata refresh
                                if (typeof metadataPopupManager.audioPlayer.attemptMetadataRefresh === "function") {
                                    metadataPopupManager.audioPlayer.attemptMetadataRefresh("popup-closed")
                                }
                                
                                // Explicitly refresh display multiple times to ensure Text elements update
                                // The Text elements use bindings that might not re-evaluate immediately
                                function forceRefresh() {
                                    if (metadataPopupManager.audioPlayer && typeof metadataPopupManager.audioPlayer.refreshMetadataDisplay === "function") {
                                        metadataPopupManager.audioPlayer.refreshMetadataDisplay({ triggerLyrics: false })
                                    }
                                }
                                
                                // Immediate refresh
                                forceRefresh()
                                
                                // Refresh again after UI becomes visible
                                Qt.callLater(forceRefresh, 50)
                                
                                // One more refresh to ensure bindings have re-evaluated
                                Qt.callLater(forceRefresh, 150)
                            }
                        }, 10) // Reduced delay to make it faster
                    }
                }
            }
            
            if (metadataPopupManager.mainWindow.showingMetadata) {
                // For audio files, check if duration is already available
                if (metadataPopupManager.mainWindow.isAudio) {
                    // Check if duration is already available (audio might already be loaded)
                    if (metadataPopupManager.audioPlayer && metadataPopupManager.audioPlayer.duration > 0) {
                        Qt.callLater(function() {
                            metadataPopupManager.updateMetadataList()
                        })
                    } else {
                        // Duration not available yet - wait for onDurationAvailable signal
                    }
                } else {
                    // Use a longer delay when opening to allow media to load
                    metadataUpdateTimer.interval = 500
                    metadataUpdateTimer.restart()
                }
            }
        }
        function onCurrentImageChanged() {
            
            // Update metadata when current image changes, if popup is visible
            // Use a timer to debounce and ensure all properties are set (including duration and metadata)
            if (metadataPopupManager.mainWindow.showingMetadata) {
                // For audio files, don't use the timer - rely on signal-based updates (onDurationAvailable, onMetaDataChanged)
                // This prevents interference with audio loading
                if (metadataPopupManager.mainWindow.isAudio) {
                    // Don't clear metadata list - keep old data until new data arrives to prevent UI glitches
                    // The metadata will update when duration/metadata become available via Connections
                    // This prevents interference with AudioPlayer's metadata display
                } else {
                    // For non-audio files, use a short delay
                    metadataUpdateTimer.interval = 500
                    metadataUpdateTimer.restart()
                }
            } else {
            }
        }
    }
    
    // Listen to audio player changes via a property binding
    // This ensures metadata updates when duration and metadata (title, artist, cover art) become available
    // Use a computed property that updates reactively
    property var mediaViewerLoaders: (metadataPopupManager.pageStack && metadataPopupManager.pageStack.mediaViewerLoaders) ? metadataPopupManager.pageStack.mediaViewerLoaders : null
    property var audioPlayerLoader: (mediaViewerLoaders && mediaViewerLoaders.audioPlayerLoader) ? mediaViewerLoaders.audioPlayerLoader : null
    
    // Make audioPlayer reactive using a Binding component to track audioPlayerLoader.item changes
    property var audioPlayer: null
    
    Binding {
        target: metadataPopupManager
        property: "audioPlayer"
        value: (metadataPopupManager.audioPlayerLoader && metadataPopupManager.audioPlayerLoader.item) 
               ? metadataPopupManager.audioPlayerLoader.item 
               : null
    }
    
    // Log when audioPlayer changes (this is now handled in the Binding's onAudioPlayerChanged below)
    
    // Log when dependencies change
    onPageStackChanged: {
    }
    onMediaViewerLoadersChanged: {
        if (mediaViewerLoaders) {
        }
    }
    
    Connections {
        id: audioPlayerConnections
        target: metadataPopupManager.audioPlayer
        enabled: !!metadataPopupManager.audioPlayer
        
        Component.onCompleted: {
        }
        
        // Only listen to onDurationAvailable (fires once when duration is known)
        // NOT onDurationChanged (fires continuously during playback)
        function onDurationAvailable() {
            
            // When duration becomes available, ensure cover art is extracted and metadata is refreshed
            if (metadataPopupManager.mainWindow.isAudio &&
                metadataPopupManager.audioPlayer &&
                metadataPopupManager.audioPlayer.duration > 0) {
                
                // CRITICAL: When popup is open, explicitly trigger cover art extraction
                // This ensures the AudioPlayer's UI updates even when popup is open
                if (metadataPopupManager.mainWindow.showingMetadata) {
                    const win = metadataPopupManager.mainWindow
                    if (win && typeof win.extractAudioCoverArt === "function") {
                        Qt.callLater(function() {
                            if (win) win.extractAudioCoverArt()
                        })
                    }
                }
                
                // Update metadata popup if it's visible
                if (metadataPopupManager.mainWindow.showingMetadata) {
                    Qt.callLater(function() {
                        metadataPopupManager.updateMetadataList()
                    })
                } else {
                }
            } else {
            }
        }
    }
    
    // Also listen to the player's metadata changes (for title, artist, cover art)
    // Access the internal MediaPlayer through the audioPlayer
    Connections {
        id: mediaPlayerConnections
        target: (metadataPopupManager.audioPlayer && metadataPopupManager.audioPlayer.player) 
                ? metadataPopupManager.audioPlayer.player 
                : null
        enabled: !!(metadataPopupManager.audioPlayer && metadataPopupManager.audioPlayer.player)
        
        Component.onCompleted: {
        }
        
        function onMetaDataChanged() {
            
            if (metadataPopupManager.mainWindow.showingMetadata && 
                metadataPopupManager.mainWindow.isAudio) {
                // Update metadata when title/artist/cover art become available
                // Use a small delay to ensure metadata is fully loaded
                Qt.callLater(function() {
                    metadataPopupManager.updateMetadataList()
                })
            } else {
            }
        }
        // NOTE: We do NOT listen to onDurationChanged here because it fires continuously
        // during playback. Duration is obtained from metadata directly via getMetadataList()
    }
    
    // Log when audioPlayerLoader changes
    onAudioPlayerLoaderChanged: {
        if (audioPlayerLoader) {
        }
    }
    
    Connections {
        target: metadataPopupManager.audioPlayerLoader
        enabled: !!metadataPopupManager.audioPlayerLoader
        
        function onItemChanged() {
            
            // When audio player item changes, give it time to load metadata before updating
            if (metadataPopupManager.mainWindow.showingMetadata && 
                metadataPopupManager.mainWindow.isAudio) {
                // CRITICAL: When popup is open and audio player loads, we need to ensure cover art and metadata refresh
                // Use a timer to periodically check if duration is available and trigger updates
                
                // Set up a fallback mechanism: check periodically if duration is available
                // This ensures updates happen even if onDurationAvailable signal doesn't fire
                let checkCount = 0
                const maxChecks = 20 // Check for up to 2 seconds (20 * 100ms)
                const checkInterval = 100
                
                function checkAndUpdate() {
                    checkCount++
                    if (checkCount > maxChecks) {
                        return
                    }
                    
                    if (metadataPopupManager.audioPlayer && metadataPopupManager.audioPlayer.duration > 1000) {
                        // Duration is available and seems valid (> 1 second)
                        
                        // Explicitly trigger cover art extraction
                        const win = metadataPopupManager.mainWindow
                        if (win && typeof win.extractAudioCoverArt === "function") {
                            win.extractAudioCoverArt()
                        } else {
                        }
                        
                        // Trigger AudioPlayer metadata refresh
                        
                        if (metadataPopupManager.audioPlayer) {
                            // First, explicitly call refreshMetadataDisplay to force UI update
                            if (typeof metadataPopupManager.audioPlayer.refreshMetadataDisplay === "function") {
                                metadataPopupManager.audioPlayer.refreshMetadataDisplay({ triggerLyrics: false })
                            }
                            
                            // Then trigger the full metadata refresh
                            if (typeof metadataPopupManager.audioPlayer.attemptMetadataRefresh === "function") {
                                metadataPopupManager.audioPlayer.attemptMetadataRefresh("popup-open-fallback")
                                
                                // Force another refresh after a delay to ensure UI updates
                                Qt.callLater(function() {
                                    if (metadataPopupManager.audioPlayer && typeof metadataPopupManager.audioPlayer.refreshMetadataDisplay === "function") {
                                        metadataPopupManager.audioPlayer.refreshMetadataDisplay({ triggerLyrics: false })
                                    }
                                }, 200)
                            }
                            
                            // Check AudioPlayer properties after refresh
                            Qt.callLater(function() {
                                if (metadataPopupManager.audioPlayer) {
                                    
                                    // Check if refreshMetadataDisplay worked by checking metadataReady
                                    
                                    // Try to call getMetaString directly to see what it returns
                                    if (typeof metadataPopupManager.audioPlayer.getMetaString === "function") {
                                        const title = metadataPopupManager.audioPlayer.getMetaString(MediaMetaData.Title) || metadataPopupManager.audioPlayer.getMetaString("Title")
                                        const artist = metadataPopupManager.audioPlayer.getMetaString(MediaMetaData.ContributingArtist) || metadataPopupManager.audioPlayer.getMetaString("ContributingArtist") || metadataPopupManager.audioPlayer.getMetaString("Artist")
                                        
                                        // If metadata is available, force another refresh
                                        // Note: We don't change showingMetadata here - refreshMetadataDisplay() works even when UI is hidden
                                        // The Text elements will be updated, and when popup closes, the UI will already be correct
                                        if (title || artist) {
                                            Qt.callLater(function() {
                                                if (metadataPopupManager.audioPlayer && typeof metadataPopupManager.audioPlayer.refreshMetadataDisplay === "function") {
                                                    metadataPopupManager.audioPlayer.refreshMetadataDisplay({ triggerLyrics: false })
                                                }
                                            }, 100)
                                        }
                                    } else {
                                    }
                                    
                                    // Try to get title/artist from metadata
                                    if (metadataPopupManager.audioPlayer.player) {
                                        const metaData = metadataPopupManager.audioPlayer.player.metaData
                                        if (metaData) {
                                            try {
                                                const title = metaData.stringValue ? metaData.stringValue(MediaMetaData.Title) : null
                                                const artist = metaData.stringValue ? metaData.stringValue(MediaMetaData.ContributingArtist) : null
                                            } catch(e) {
                                            }
                                        }
                                    }
                                    
                                    // Also check customPlayer if it exists
                                    if (metadataPopupManager.audioPlayer.customPlayer) {
                                        if (metadataPopupManager.audioPlayer.customPlayer.metaData) {
                                            const customMeta = metadataPopupManager.audioPlayer.customPlayer.metaData
                                        }
                                    }
                                }
                            }, 300)
                        } else {
                        }
                        
                        // Update metadata popup
                        Qt.callLater(function() {
                            metadataPopupManager.updateMetadataList()
                        })
                        
                        // Stop checking once we've successfully updated
                        return
                    } else {
                        // Duration not ready yet, check again
                        Qt.callLater(function() {
                            checkAndUpdate()
                        }, checkInterval)
                    }
                }
                
                // Start checking after a short delay
                Qt.callLater(function() {
                    checkAndUpdate()
                }, checkInterval)
                
                // Store timer reference to avoid creating multiple timers
                if (!metadataPopupManager._playbackUpdateTimer) {
                    metadataPopupManager._playbackUpdateTimer = Qt.createQmlObject(
                        'import QtQuick; Timer { interval: 1000; repeat: true; running: false }', 
                        metadataPopupManager
                    )
                    metadataPopupManager._playbackUpdateTimer.triggered.connect(function() {
                        if (metadataPopupManager.audioPlayer) {
                        }
                        
                        if (metadataPopupManager.mainWindow.showingMetadata && 
                            metadataPopupManager.mainWindow.isAudio &&
                            metadataPopupManager.audioPlayer &&
                            metadataPopupManager.audioPlayer.duration > 0) {
                            // Update metadata list during playback to keep duration/time current
                            metadataPopupManager.updateMetadataList()
                        } else {
                            // Stop timer if popup is closed or not audio
                            metadataPopupManager._playbackUpdateTimer.stop()
                        }
                    })
                }
                
                // Start the timer after a delay to let everything initialize
                Qt.callLater(function() {
                    if (metadataPopupManager.mainWindow.showingMetadata && 
                        metadataPopupManager.mainWindow.isAudio &&
                        metadataPopupManager.audioPlayer) {
                        metadataPopupManager._playbackUpdateTimer.start()
                    }
                }, 500)
            } else {
            }
            
            // Force re-evaluation of audioPlayer property by triggering a change
            Qt.callLater(function() {
            })
        }
    }
    
    // Metadata popup
    MetadataPopup {
        id: metadataPopup
        parent: metadataPopupManager.mainWindow.contentItem
        // Top-left positioning with consistent spacing
        x: 12
        y: 12
        visible: metadataPopupManager.mainWindow.showingMetadata && 
                 metadataPopupManager.mainWindow.currentImage !== "" &&
                 !metadataPopupManager.mainWindow.showingSettings
        metadataList: metadataPopupManager.computedMetadataList
        accentColor: metadataPopupManager.mainWindow.accentColor
        foregroundColor: metadataPopupManager.mainWindow.foregroundColor
        onOpened: {
            // Update metadata when popup opens
            if (!metadataPopupManager.mainWindow.isAudio) {
                metadataPopupManager.updateMetadataList()
            } else {
                // For audio files, check if duration is already available
                if (metadataPopupManager.audioPlayer && metadataPopupManager.audioPlayer.duration > 0) {
                    Qt.callLater(function() {
                        metadataPopupManager.updateMetadataList()
                    })
                } else {
                }
            }
        }
        
        property bool closingViaButton: false
        
        onCloseRequested: {
            // Close the popup by setting showingMetadata to false
            // This ensures it only closes on release, not on press
            closingViaButton = true
            metadataPopupManager.mainWindow.showingMetadata = false
            Qt.callLater(function() {
                closingViaButton = false
            })
        }
        
        onVisibleChanged: {
            if (visible) {
                // Update metadata when popup becomes visible - use callLater to ensure it happens after visibility is set
                if (!metadataPopupManager.mainWindow.isAudio) {
                    Qt.callLater(function() {
                        metadataPopupManager.updateMetadataList()
                    })
                } else {
                    // For audio files, check if duration is already available
                    if (metadataPopupManager.audioPlayer && metadataPopupManager.audioPlayer.duration > 0) {
                        Qt.callLater(function() {
                            metadataPopupManager.updateMetadataList()
                        })
                    } else {
                    }
                }
            } else {
                // Only set showingMetadata to false if we're not closing via the button
                // This prevents the popup from reopening when the button is released
                if (!closingViaButton) {
                    metadataPopupManager.mainWindow.showingMetadata = false
                }
            }
        }
    }
    
    // Expose the popup for external access
    property alias popup: metadataPopup
    
    // Expose updateMetadataList function for external access (e.g., from MediaViewerLoaders)
    // This allows other components to trigger metadata updates
}

