import QtQuick
import QtCore

// WindowResizeTimers component - manages timers for window resizing operations
Item {
    id: resizeTimers
    
    // Target window
    required property var window
    
    // Properties from window
    property bool matchMediaAspectRatio: false
    property url currentImage: ""
    property bool isVideo: false
    property var videoPlayerLoader: null
    
    // Timer to debounce aspect ratio resizing (prevents infinite loops)
    Timer {
        id: resizeAspectTimer
        interval: 100  // Wait 100ms after last size change
        onTriggered: {
            if (resizeTimers.matchMediaAspectRatio && resizeTimers.currentImage !== "" && 
                resizeTimers.window.visibility !== Window.Maximized && 
                resizeTimers.window.visibility !== Window.FullScreen) {
                if (resizeTimers.window.resizeToMediaAspectRatio) {
                    resizeTimers.window.resizeToMediaAspectRatio()
                }
            }
        }
    }
    
    // Timer to retry getting video dimensions (for videos that load dimensions slowly)
    Timer {
        id: videoDimensionRetryTimer
        interval: 500  // Wait 500ms for video dimensions to become available
        repeat: false
        onTriggered: {
            if (resizeTimers.matchMediaAspectRatio && resizeTimers.isVideo && 
                resizeTimers.currentImage !== "" && 
                resizeTimers.window.visibility !== Window.Maximized && 
                resizeTimers.window.visibility !== Window.FullScreen &&
                resizeTimers.videoPlayerLoader && resizeTimers.videoPlayerLoader.item && 
                resizeTimers.videoPlayerLoader.item.implicitWidth > 0 && 
                resizeTimers.videoPlayerLoader.item.implicitHeight > 0) {
                resizeAspectTimer.restart()
            }
        }
    }
    
    // Timer to throttle clampPan during resize to avoid lag
    Timer {
        id: clampPanTimer
        interval: 16  // ~60fps
        onTriggered: {
            if (resizeTimers.window.clampPan) {
                resizeTimers.window.clampPan()
            }
        }
    }
    
    // Expose timers to parent
    property alias resizeAspectTimer: resizeAspectTimer
    property alias videoDimensionRetryTimer: videoDimensionRetryTimer
    property alias clampPanTimer: clampPanTimer
    
    // Connect to window size changes
    Connections {
        target: resizeTimers.window
        function onWidthChanged() {
            if (!clampPanTimer.running) {
                clampPanTimer.start()
            }
        }
        function onHeightChanged() {
            if (!clampPanTimer.running) {
                clampPanTimer.start()
            }
        }
    }
}

