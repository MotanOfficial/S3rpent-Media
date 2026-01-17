import QtQuick
import s3rp3nt_media 1.0 as S3rp3ntMedia

// This component will only be loaded if MPVVideoPlayer type exists
// If it doesn't exist, the Loader will handle the error gracefully
// Note: This file will cause a parse error if MPVVideoPlayer doesn't exist
// The Loader in VideoPlayer.qml will catch this and disable itself
S3rp3ntMedia.MPVVideoPlayer {
    id: mpvPlayerInstance
    // source will be set by the Loader's onItemChanged
    
    Component.onCompleted: {
        // Set volume from videoPlayer after Settings has loaded
        // Access parent's videoPlayer through Loader's parent
        var vp = parent.parent ? parent.parent.videoPlayer : null
        if (vp) {
            volume = vp.volume
            console.log("[MPVVideoPlayer] onCompleted: Set volume to", volume)
        }
    }
    
    onDurationChanged: {
        if (duration > 0) {
            console.log("[MPV] Duration available:", duration, "ms")
            var vp = parent.parent ? parent.parent.videoPlayer : null
            if (vp) {
                // Ensure volume is synced after video is loaded
                if (Math.abs(volume - vp.volume) > 0.001) {
                    console.log("[MPV] Syncing volume:", vp.volume, "-> mpvPlayer")
                    volume = vp.volume
                }
                vp.durationAvailable()
                // Autoplay video when ready
                Qt.callLater(function() {
                    if (playbackState !== 1) { // Not already playing
                        console.log("[MPV] Autoplaying video")
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
            if (playbackState === 1) { // Playing
                vp.showControls = true
                if (vp.controlsHideTimer) {
                    vp.controlsHideTimer.start()
                }
            } else {
                vp.showControls = true
                if (vp.controlsHideTimer) {
                    vp.controlsHideTimer.stop()
                }
            }
        }
    }
    
    onHasAudioChanged: {
        // hasAudio property changed
    }
    
    onErrorOccurred: function(error, errorString) {
        console.error("[MPV] Error occurred:", error, errorString)
        var vp = parent.parent ? parent.parent.videoPlayer : null
        if (vp && vp.useLibmpv) {
            console.log("[MPV] Falling back to MediaPlayer")
            vp.videoSettings.videoBackend = "mediaplayer"
        }
    }
}

