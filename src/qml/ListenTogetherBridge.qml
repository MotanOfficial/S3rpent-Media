import QtMultimedia
import QtQuick
import s3rpent_media

/**
 * App-level Listen Together session — survives when no audio is loaded.
 * AudioPlayer receives manager via webRTCManager property for playback sync.
 */
Item {
    id: bridge
    visible: false
    width: 0
    height: 0

    property var audioPlayer: null
    property var appWindow: null
    property string _clientStreamPath: ""
    property bool _hostWantedPlay: false
    property bool _waitingForClientSync: false
    property bool _clientCatchUpSync: false
    property bool _pendingSyncStart: false
    property bool _pendingSyncPlay: false
    property int _pendingSyncPosition: 0
    property bool _pendingSyncPlayHint: false
    property int _streamEpoch: 0
    property int _streamEpochAtReceive: -1
    property bool _awaitingStreamComplete: false
    readonly property alias manager: webRTCManager

    onAudioPlayerChanged: {
        if (_pendingSyncStart && _hasPlayer())
            syncPlayRetryTimer.restart()
    }

    function _clearWebRtcMetadata() {
        if (!_hasPlayer())
            return
        audioPlayer.webRTCTitle = ""
        audioPlayer.webRTCArtist = ""
        audioPlayer.webRTCAlbum = ""
        if (typeof audioPlayer.resetCoverArtFetchCache === "function")
            audioPlayer.resetCoverArtFetchCache()
        if (typeof audioPlayer.refreshMetadataDisplay === "function")
            audioPlayer.refreshMetadataDisplay({ triggerLyrics: false })
        _clearAppWindowCoverArt()
    }

    function _clearAppWindowCoverArt() {
        if (!appWindow)
            return
        appWindow.audioCoverArt = ""
        Qt.callLater(function() {
            if (appWindow)
                appWindow.updateAccentColor()
        })
    }

    function _refreshAppWindowCoverArt() {
        if (!appWindow)
            return
        const m = webRTCManager
        const hostCover = m.currentCoverUrl ? m.currentCoverUrl.toString() : ""
        if (hostCover !== "" && hostCover.indexOf("file:") !== 0) {
            appWindow.audioCoverArt = hostCover
            if (_hasPlayer() && hostCover.indexOf("data:") === 0)
                audioPlayer.coverArt = hostCover
            Qt.callLater(function() {
                if (appWindow)
                    appWindow.updateAccentColor()
            })
            return
        }
        if (appWindow.isAudio && appWindow.currentImage && appWindow.currentImage !== "") {
            const src = _sourceStr()
            if (!webRTCManager.isHost && src.indexOf("s3rpent_stream_") >= 0)
                return
            Qt.callLater(function() {
                if (appWindow)
                    appWindow.extractAudioCoverArt()
            })
        }
    }

    function _applyStreamMetadata() {
        if (!_hasPlayer())
            return
        const m = webRTCManager
        audioPlayer.webRTCTitle = m.currentTitle || ""
        audioPlayer.webRTCArtist = m.currentArtist || ""
        audioPlayer.webRTCAlbum = m.currentAlbum || ""
        if (m.streamDuration > 0) {
            audioPlayer._lastEmittedDuration = 0
            audioPlayer.instantDuration = m.streamDuration
        }
        const cover = m.currentCoverUrl ? m.currentCoverUrl.toString() : ""
        if (cover !== "" && cover.indexOf("file:") !== 0)
            audioPlayer.coverArt = cover
        _refreshAppWindowCoverArt()
        if (typeof audioPlayer.refreshMetadataDisplay === "function")
            audioPlayer.refreshMetadataDisplay({ triggerLyrics: false })
    }

    function _reapplyHostStreamDuration() {
        if (!_hasPlayer() || webRTCManager.isHost || webRTCManager.streamDuration <= 0)
            return
        const src = _sourceStr()
        if (src.indexOf("s3rpent_stream_") < 0)
            return
        audioPlayer._lastEmittedDuration = webRTCManager.streamDuration
        audioPlayer.instantDuration = webRTCManager.streamDuration
    }

    function _resolvePlayer() {
        if (audioPlayer)
            return audioPlayer
        if (appWindow && appWindow.audioPlayer)
            return appWindow.audioPlayer
        return null
    }

    function _hasPlayer() {
        const p = _resolvePlayer()
        return p !== null && p !== undefined
    }

    function _sourceStr() {
        const p = _resolvePlayer()
        if (p && p.source)
            return p.source.toString()
        if (appWindow && appWindow.currentImage && appWindow.currentImage !== "")
            return appWindow.currentImage.toString()
        return ""
    }

    function _normalizeSourceUrl(source) {
        if (!source || source === "")
            return ""
        if (source.indexOf("://") >= 0)
            return source
        return "file:///" + String(source).replace(/\\/g, "/")
    }

    function _isDecoderReady() {
        const p = _resolvePlayer()
        if (!p || _sourceStr() === "")
            return false
        return p._playerDuration > 0
    }

    function _syncManagerFromPlayer() {
        const p = _resolvePlayer()
        if (p) {
            webRTCManager.playbackPosition = p.currentPosition
            webRTCManager.isPlaying = p.currentPlaybackState === MediaPlayer.PlayingState
                    || p.listenTogetherWantsPlayback
            webRTCManager.syncMetadataToWebRTC()
        }
        const src = _sourceStr()
        if (src !== "")
            webRTCManager.currentSource = src
    }

    function _hostPlaybackIntent() {
        if (webRTCManager.hostWantedPlayback)
            return true
        const p = _resolvePlayer()
        if (!p)
            return webRTCManager.isPlaying
        return p.listenTogetherWantsPlayback
                || p.currentPlaybackState === MediaPlayer.PlayingState
                || p.currentPlaybackState !== MediaPlayer.PausedState
    }

    function _notifySyncReadyWhenDecoderReady() {
        if (!_isDecoderReady()) {
            syncReadyWaitTimer.restart()
            return
        }
        syncReadyWaitTimer.stop()
        webRTCManager.notifyClientSyncReady()
    }

    function _startSyncedPlayback(position, play) {
        let effectivePlay = play
        if (!effectivePlay && bridge._pendingSyncPlayHint)
            effectivePlay = true
        webRTCManager._syncing = true
        webRTCManager.syncStatus = effectivePlay ? "starting" : "loading"
        _pendingSyncPosition = position
        _pendingSyncPlay = effectivePlay
        _pendingSyncStart = true
        syncPlayRetryTimer.interval = 100
        syncPlayRetryTimer.restart()
        syncTimer.restart()
    }

    function _loadRemoteSource(source, isPlaying) {
        const url = _normalizeSourceUrl(source)
        if (url === "")
            return
        if (appWindow)
            appWindow.currentImage = url
        if (_hasPlayer()) {
            if (url === _sourceStr())
                return
            audioPlayer.source = url
            if (isPlaying)
                audioPlayer.play()
            else
                audioPlayer.pause()
            return
        }
        if (!appWindow)
            return
        webRTCManager._pendingPlayState = isPlaying
    }

    WebRTCListenTogetherManager {
        id: webRTCManager

        property bool _syncing: false
        property bool _pendingPlayState: false
        property bool _streamComplete: false

        property string syncStatus: "idle"
        readonly property string syncStatusLabel: {
            switch (syncStatus) {
            case "receiving":
                return qsTr("Downloading track… %1%").arg(Math.round(streamReceiveProgress * 100))
            case "loading":
                return qsTr("Loading track…")
            case "waiting_peer":
                return qsTr("Waiting for friend to receive track…")
            case "starting":
                return qsTr("Starting playback together…")
            case "synced":
                return qsTr("In sync")
            default:
                return ""
            }
        }

        onConnectionStateChanged: {
            if (!isConnected) {
                syncStatus = "idle"
                hostMetadataPushTimer.stop()
                syncReadyWaitTimer.stop()
            }
        }

        onStreamReceiveProgressChanged: {
            if (!isHost && syncStatus === "receiving")
                syncStatus = "receiving"
        }

        onRemotePlayRequested: {
            _syncing = true
            if (!_hasPlayer() || _sourceStr() === "") {
                _pendingPlayState = true
            } else {
                audioPlayer.play()
            }
            syncTimer.restart()
        }

        onRemotePauseRequested: {
            _syncing = true
            if (!_hasPlayer() || _sourceStr() === "") {
                _pendingPlayState = false
            } else {
                audioPlayer.pause()
            }
            syncTimer.restart()
        }

        onRemoteSeekRequested: function(position) {
            _syncing = true
            if (_hasPlayer() && _sourceStr() !== "" && (_streamComplete || webRTCManager.isHost)) {
                audioPlayer.seekToPosition(position)
            }
            syncTimer.restart()
        }

        onRemoteTrackChanged: function(source, isPlaying) {
            if (source !== "" && source === _sourceStr())
                return
            _syncing = true
            _streamComplete = false
            if (source === "") {
                if (!isHost) {
                    bridge._streamEpoch++
                    bridge._awaitingStreamComplete = false
                    bridge._clientStreamPath = ""
                    syncReadyWaitTimer.stop()
                    syncStatus = "receiving"
                }
                if (_hasPlayer()) {
                    audioPlayer.stop()
                    audioPlayer.source = ""
                }
                _pendingPlayState = false
                bridge._clearWebRtcMetadata()
            } else {
                _loadRemoteSource(source, isPlaying)
            }
            syncTimer.interval = 3000
            syncTimer.restart()
        }

        onMetadataUpdated: {
            const m = webRTCManager
            if (!m.isHost && m.currentTitle === "" && m.currentArtist === "" && m.currentAlbum === ""
                    && (syncStatus === "receiving" || syncStatus === "loading"))
                return
            bridge._applyStreamMetadata()
            Qt.callLater(function() { bridge._reapplyHostStreamDuration() })
        }

        onHostPauseForSync: function(wantedPlay) {
            _syncing = true
            syncStatus = "waiting_peer"
            bridge._clientCatchUpSync = false
            bridge._hostWantedPlay = wantedPlay
            bridge._waitingForClientSync = true
            _lastSentTitle = ""
            _lastSentArtist = ""
            _lastSentAlbum = ""
            _lastSentCoverUrl = ""
            _lastSentDuration = 0
            hostMetadataPushTimer.start()
            if (_hasPlayer())
                audioPlayer.pause()
            syncTimer.restart()
        }

        onHostStateSyncRequested: {
            bridge._syncManagerFromPlayer()
            webRTCManager.publishFullStateToPeer()
        }

        onClientCatchUpStarted: {
            bridge._clientCatchUpSync = true
            bridge._syncManagerFromPlayer()
        }

        onClientSyncReady: {
            if (!webRTCManager.isHost)
                return

            bridge._syncManagerFromPlayer()
            const p = bridge._resolvePlayer()
            const pos = p ? p.currentPosition : webRTCManager.playbackPosition
            const play = bridge._hostPlaybackIntent()

            if (bridge._waitingForClientSync) {
                syncStatus = "starting"
                bridge._waitingForClientSync = false
                const play = bridge._hostWantedPlay || bridge._hostPlaybackIntent()
                webRTCManager.beginSyncedPlayback(0, true, play)
            } else if (bridge._clientCatchUpSync || webRTCManager.currentSource !== "") {
                bridge._clientCatchUpSync = false
                webRTCManager.beginSyncedPlayback(pos, false, play)
                syncStatus = "synced"
                syncedHideTimer.restart()
            }
        }

        onSyncStartRequested: function(position, play) {
            if (!webRTCManager.isHost) {
                if (bridge._awaitingStreamComplete || syncStatus === "receiving")
                    return
                if (_sourceStr() === "" || !_streamComplete)
                    return
            }
            bridge._startSyncedPlayback(position, play)
        }

        onFullStateReceived: function(state) {
            let hasValidMetadata = false

            if (state.title !== undefined && state.title !== "")
                webRTCManager.currentTitle = state.title
            if (state.artist !== undefined && state.artist !== "")
                webRTCManager.currentArtist = state.artist
            if (state.album !== undefined && state.album !== "")
                webRTCManager.currentAlbum = state.album
            if (state.coverUrl !== undefined && state.coverUrl !== "")
                webRTCManager.currentCoverUrl = state.coverUrl
            if (state.streamDuration !== undefined && state.streamDuration > 0)
                webRTCManager.streamDuration = state.streamDuration

            if (_hasPlayer()) {
                if (state.title !== undefined && state.title !== "") {
                    audioPlayer.webRTCTitle = state.title
                    hasValidMetadata = true
                }
                if (state.artist !== undefined && state.artist !== "") {
                    audioPlayer.webRTCArtist = state.artist
                    hasValidMetadata = true
                }
                if (state.album !== undefined && state.album !== "") {
                    audioPlayer.webRTCAlbum = state.album
                    hasValidMetadata = true
                }
                if (state.coverUrl !== undefined && state.coverUrl !== "") {
                    audioPlayer.coverArt = state.coverUrl
                    hasValidMetadata = true
                }
                if (state.streamDuration !== undefined && state.streamDuration > 0) {
                    const newDur = state.streamDuration
                    if (Math.abs(newDur - audioPlayer.instantDuration) > 500) {
                        audioPlayer._lastEmittedDuration = 0
                        audioPlayer.instantDuration = newDur
                    }
                    hasValidMetadata = true
                }
            }

            _syncing = true
            _streamComplete = false

            if (state.isLocalFile) {
                if (!isHost)
                    syncStatus = "receiving"
                if (state.position !== undefined && state.position > 0)
                    bridge._pendingSyncPosition = state.position
                if (state.isPlaying !== undefined)
                    bridge._pendingSyncPlayHint = state.isPlaying
                if (_hasPlayer()) {
                    audioPlayer.stop()
                    audioPlayer.source = ""
                }
                _pendingPlayState = false
            } else if (state.source !== undefined && state.source !== "" && state.source !== _sourceStr()) {
                _loadRemoteSource(state.source, false)
            }

            if (!state.isLocalFile) {
                const joinPos = state.position !== undefined ? state.position : 0
                const joinPlay = state.isPlaying === true
                if (joinPos > 0) {
                    bridge._startSyncedPlayback(joinPos, joinPlay)
                } else if (_hasPlayer()) {
                    if (joinPlay)
                        audioPlayer.play()
                    else
                        audioPlayer.pause()
                } else if (state.source) {
                    _loadRemoteSource(state.source, joinPlay)
                }
            }

            syncTimer.interval = 3000
            syncTimer.restart()
        }

        property string _lastSentTitle: ""
        property string _lastSentArtist: ""
        property string _lastSentAlbum: ""
        property string _lastSentCoverUrl: ""
        property int _lastSentDuration: 0

        function syncMetadataToWebRTC() {
            if (!_hasPlayer() || _sourceStr() === "")
                return

            const title = audioPlayer.getMetaString(MediaMetaData.Title) || audioPlayer.getMetaString("Title") || ""
            const artist = audioPlayer.getMetaString(MediaMetaData.ContributingArtist)
                || audioPlayer.getMetaString("ContributingArtist")
                || audioPlayer.getMetaString("Artist") || ""
            const album = audioPlayer.getMetaString(MediaMetaData.AlbumTitle)
                || audioPlayer.getMetaString("AlbumTitle")
                || audioPlayer.getMetaString("Album") || ""
            const cover = audioPlayer.coverArt ? audioPlayer.coverArt.toString() : ""
            const dur = audioPlayer.duration

            const hasValidMetadata = title !== "" || artist !== "" || album !== "" || dur > 0
            if (!hasValidMetadata)
                return

            if (title !== _lastSentTitle || artist !== _lastSentArtist
                    || album !== _lastSentAlbum || cover !== _lastSentCoverUrl
                    || dur !== _lastSentDuration) {
                if (webRTCManager.currentTitle !== title) webRTCManager.currentTitle = title
                if (webRTCManager.currentArtist !== artist) webRTCManager.currentArtist = artist
                if (webRTCManager.currentAlbum !== album) webRTCManager.currentAlbum = album
                if (webRTCManager.currentCoverUrl !== cover) webRTCManager.currentCoverUrl = cover
                if (webRTCManager.streamDuration !== dur) webRTCManager.streamDuration = dur
                _lastSentTitle = title
                _lastSentArtist = artist
                _lastSentAlbum = album
                _lastSentCoverUrl = cover
                _lastSentDuration = dur
                if (webRTCManager.isHost && webRTCManager.isConnected)
                    webRTCManager.broadcastMetadata()
            }
        }

        onAudioStreamReady: function(filePath, mimeType) {
            _syncing = true
            if (!webRTCManager.isHost) {
                bridge._clientStreamPath = filePath
                bridge._streamEpochAtReceive = bridge._streamEpoch
                bridge._awaitingStreamComplete = true
                syncStatus = "receiving"
            }
            syncTimer.restart()
        }

        onAudioStreamComplete: {
            if (webRTCManager.isHost)
                return
            if (!bridge._awaitingStreamComplete)
                return
            if (bridge._streamEpochAtReceive !== bridge._streamEpoch)
                return
            if (bridge._clientStreamPath === "")
                return

            _streamComplete = true
            bridge._awaitingStreamComplete = false
            _syncing = true
            syncStatus = "loading"
            bridge._applyStreamMetadata()
            _loadRemoteSource("file:///" + bridge._clientStreamPath, false)
            bridge._clientStreamPath = ""
            bridge._refreshAppWindowCoverArt()
            Qt.callLater(function() { bridge._reapplyHostStreamDuration() })
            bridge._notifySyncReadyWhenDecoderReady()
            syncTimer.restart()
        }
    }

    Timer {
        id: hostStatePushTimer
        interval: 200
        repeat: true
        running: webRTCManager.isHost && webRTCManager.isConnected
        onTriggered: bridge._syncManagerFromPlayer()
    }

    Timer {
        id: hostMetadataPushTimer
        interval: 400
        repeat: true
        running: false
        onTriggered: {
            if (!webRTCManager.isHost || !webRTCManager.isConnected || !_hasPlayer() || _sourceStr() === "") {
                stop()
                return
            }
            webRTCManager.syncMetadataToWebRTC()
        }
    }

    Timer {
        id: metadataSyncTimer
        interval: 2000
        running: webRTCManager.isConnected && webRTCManager.isHost
                 && _hasPlayer() && _sourceStr() !== ""
        repeat: true
        onTriggered: webRTCManager.syncMetadataToWebRTC()
    }

    Timer {
        id: syncTimer
        interval: 1500
        onTriggered: {
            webRTCManager._syncing = false
            if (interval !== 1500)
                interval = 1500
        }
    }

    Timer {
        id: syncReadyWaitTimer
        interval: 50
        repeat: true
        onTriggered: bridge._notifySyncReadyWhenDecoderReady()
    }

    Timer {
        id: syncPlayRetryTimer
        interval: 100
        repeat: true
        onTriggered: {
            if (!_pendingSyncStart)
                stop()

            if (!_hasPlayer() || _sourceStr() === "")
                return

            if (!bridge._isDecoderReady())
                return

            const p = bridge._resolvePlayer()
            if (!p)
                return

            const targetPos = bridge._pendingSyncPosition
            const play = bridge._pendingSyncPlay
            const canSeek = p.seekable && p.duration > 0

            if (targetPos > 0 && canSeek) {
                const drift = Math.abs(p.currentPosition - targetPos)
                if (drift > 1500 || p.currentPlaybackState === MediaPlayer.StoppedState)
                    p.seekToPosition(targetPos)
            }

            if (play) {
                if (p.currentPlaybackState !== MediaPlayer.PlayingState)
                    p.play()
            } else {
                p.pause()
            }

            if (play && p.currentPlaybackState !== MediaPlayer.PlayingState)
                return

            if (targetPos > 0 && canSeek && Math.abs(p.currentPosition - targetPos) > 2500)
                return

            bridge._pendingSyncPosition = 0
            bridge._pendingSyncPlay = false
            bridge._pendingSyncStart = false
            stop()
            bridge._pendingSyncPlayHint = false

            webRTCManager.syncStatus = "synced"
            syncedHideTimer.restart()
            syncTimer.restart()
        }
    }

    Timer {
        id: syncedHideTimer
        interval: 2500
        onTriggered: {
            if (webRTCManager.syncStatus === "synced")
                webRTCManager.syncStatus = "idle"
        }
    }

    Timer {
        id: clientMetadataCheckTimer
        interval: 100
        running: false
        repeat: true
        onTriggered: {
            if (!_hasPlayer())
                return
            const title = audioPlayer.getMetaString(MediaMetaData.Title) || audioPlayer.getMetaString("Title") || ""
            const artist = audioPlayer.getMetaString(MediaMetaData.ContributingArtist)
                || audioPlayer.getMetaString("ContributingArtist")
                || audioPlayer.getMetaString("Artist") || ""
            const dur = audioPlayer.duration

            if ((title !== "" || artist !== "" || dur > 0) && webRTCManager._pendingPlayState) {
                audioPlayer.play()
                webRTCManager._pendingPlayState = false
                stop()
            }
        }
    }

    Connections {
        target: audioPlayer
        function onSourceChanged() {
            if (!_hasPlayer() || _sourceStr() === "")
                return
            if (bridge._pendingSyncStart) {
                syncPlayRetryTimer.restart()
                return
            }
            if (webRTCManager._pendingPlayState) {
                Qt.callLater(function() {
                    if (_hasPlayer() && webRTCManager._pendingPlayState) {
                        audioPlayer.play()
                        webRTCManager._pendingPlayState = false
                    }
                })
            }
        }
    }
}
