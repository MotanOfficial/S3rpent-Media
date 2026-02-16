import QtQuick
import s3rpent_media 1.0 as S3rpentMedia

// D3D11-based MPV Video Player Component
// This component uses D3D11 renderer instead of OpenGL
// Only loaded if MPVVideoPlayerD3D11 type exists
S3rpentMedia.MPVVideoPlayerD3D11 {
    id: mpvPlayerInstanceD3D11
    // source will be set by the Loader's onItemChanged
    
    Component.onCompleted: {
        // Set volume from videoPlayer after Settings has loaded
        // Access parent's videoPlayer through Loader's parent
        var vp = parent.parent ? parent.parent.videoPlayer : null
        if (vp) {
            volume = vp.volume
            console.log("[MPVVideoPlayerD3D11] onCompleted: Set volume to", volume)
        }
    }
    
    onDurationChanged: {
        if (duration > 0) {
            console.log("[MPV D3D11] Duration available:", duration, "ms")
            var vp = parent.parent ? parent.parent.videoPlayer : null
            if (vp) {
                // Ensure volume is synced after video is loaded
                if (Math.abs(volume - vp.volume) > 0.001) {
                    console.log("[MPV D3D11] Syncing volume:", vp.volume, "-> mpvPlayer")
                    volume = vp.volume
                }
                vp.durationAvailable()
                // Autoplay video when ready
                Qt.callLater(function() {
                    if (playbackState !== 1) { // Not already playing
                        console.log("[MPV D3D11] Autoplaying video")
                        play()
                    }
                })
            }
        }
    }
    
    onPlaybackStateChanged: {
        var vp = parent.parent ? parent.parent.videoPlayer : null
        if (vp) {
            vp.playbackStateUpdated()
        }
    }
    
    onPositionChanged: {
        var vp = parent.parent ? parent.parent.videoPlayer : null
        if (vp) {
            vp.position = position
        }
    }
    
    onErrorOccurred: {
        console.error("[MPV D3D11] Error:", error, errorString)
    }
}

