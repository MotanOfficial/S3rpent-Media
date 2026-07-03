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
    
    function refreshAudioPlayerMetadata(reason) {
        if (!metadataPopupManager.mainWindow.isAudio || !metadataPopupManager.audioPlayer)
            return
        if (typeof metadataPopupManager.audioPlayer.attemptMetadataRefresh === "function")
            metadataPopupManager.audioPlayer.attemptMetadataRefresh(reason || "metadata-manager")
        else if (typeof metadataPopupManager.audioPlayer.refreshMetadataDisplay === "function")
            metadataPopupManager.audioPlayer.refreshMetadataDisplay({ triggerLyrics: false })
        updateMetadataList()
    }

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
            metadataPopupManager.updateMetadataList()
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
            if (!metadataPopupManager.mainWindow.isAudio) {
                metadataUpdateTimer.interval = 500
                metadataUpdateTimer.restart()
            } else if (metadataPopupManager.audioPlayer) {
                metadataPopupManager.refreshAudioPlayerMetadata("track-changed")
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
            if (!metadataPopupManager.mainWindow.isAudio
                    || !metadataPopupManager.audioPlayer
                    || metadataPopupManager.audioPlayer.duration <= 0) {
                return
            }
            Qt.callLater(function() {
                metadataPopupManager.refreshAudioPlayerMetadata("duration-available")
            })
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
            if (!metadataPopupManager.mainWindow.isAudio)
                return
            Qt.callLater(function() {
                metadataPopupManager.refreshAudioPlayerMetadata("player-metadata")
            })
        }
        // NOTE: We do NOT listen to onDurationChanged here because it fires continuously
        // during playback. Duration is obtained from metadata directly via getMetadataList()
    }

    Connections {
        target: (metadataPopupManager.audioPlayer && metadataPopupManager.audioPlayer.customPlayer)
                ? metadataPopupManager.audioPlayer.customPlayer
                : null
        enabled: !!(metadataPopupManager.audioPlayer && metadataPopupManager.audioPlayer.customPlayer)

        function onMetaDataChanged() {
            if (!metadataPopupManager.mainWindow.isAudio)
                return
            Qt.callLater(function() {
                metadataPopupManager.refreshAudioPlayerMetadata("custom-metadata")
            })
        }
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
            if (!metadataPopupManager.mainWindow.isAudio)
                return

            // Poll until duration/metadata are ready (onDurationAvailable can miss if the player was already loaded).
            let checkCount = 0
            const maxChecks = 20
            const checkInterval = 100

            function checkAndUpdate() {
                checkCount++
                if (checkCount > maxChecks)
                    return

                const ap = metadataPopupManager.audioPlayer
                if (ap && ap.duration > 1000) {
                    metadataPopupManager.refreshAudioPlayerMetadata("audio-player-ready")
                    return
                }
                Qt.callLater(checkAndUpdate, checkInterval)
            }

            Qt.callLater(checkAndUpdate, checkInterval)

            if (!metadataPopupManager._playbackUpdateTimer) {
                metadataPopupManager._playbackUpdateTimer = Qt.createQmlObject(
                    'import QtQuick; Timer { interval: 1000; repeat: true; running: false }',
                    metadataPopupManager
                )
                metadataPopupManager._playbackUpdateTimer.triggered.connect(function() {
                    if (metadataPopupManager.mainWindow.showingMetadata
                            && metadataPopupManager.mainWindow.isAudio
                            && metadataPopupManager.audioPlayer
                            && metadataPopupManager.audioPlayer.duration > 0) {
                        metadataPopupManager.updateMetadataList()
                    } else {
                        metadataPopupManager._playbackUpdateTimer.stop()
                    }
                })
            }
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
        
        onCloseRequested: {
            // Close the popup by setting showingMetadata to false
            // This ensures it only closes on release, not on press
            const w = metadataPopupManager.mainWindow
            w._metadataClosingViaButton = true
            w.showingMetadata = false
            Qt.callLater(function() {
                if (w)
                    w._metadataClosingViaButton = false
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
                if (!metadataPopupManager.mainWindow._metadataClosingViaButton) {
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

