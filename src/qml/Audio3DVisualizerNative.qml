import QtQuick

// Native GPU recreation of Mineradio SILK / TUNNEL / ORBIT presets.
Item {
    id: root

    property var audioAnalyzer: null
    property bool active: false
    property color visualizerColor: "#ffffff"
    property url coverArtUrl: ""
    property int mineradioPreset: 0
    property string songTitle: ""
    property string songArtist: ""
    property bool immersiveMode: false

    property real _orbitYaw: 0.0
    property real _orbitPitch: 0.0
    property real _orbitZoom: 0.0
    property real _panX: 0.0
    property real _panY: 0.0

    property real _gestureRotX: 0.0
    property real _gestureRotY: 0.0

    readonly property bool handlesOwnInput: false

    signal sceneInteracted()

    function applyPointerDrag(dx, dy, middleButton, shiftHeld) {
        const w = width > 0 ? width : 1
        const h = height > 0 ? height : 1
        if (shiftHeld || middleButton) {
            root._panX = Math.max(-1.4, Math.min(1.4, root._panX + dx / w * 1.35))
            root._panY = Math.max(-1.0, Math.min(1.0, root._panY - dy / h * 1.35))
        } else {
            root._orbitYaw -= dx / w * 5.5
            root._orbitPitch = Math.max(-1.15, Math.min(1.15, root._orbitPitch + dy / h * 3.8))
        }
        sceneInteracted()
    }

    function applyWheelZoom(angleDeltaY) {
        root._orbitZoom = Math.max(-1.6, Math.min(2.8, root._orbitZoom - angleDeltaY * 0.0009))
        sceneInteracted()
    }

    function resetSceneView() {
        root._orbitYaw = 0
        root._orbitPitch = 0
        root._orbitZoom = 0
        root._panX = 0
        root._panY = 0
        root._gestureRotX = 0
        root._gestureRotY = 0
        sceneInteracted()
    }

    property real _time: 0.0
    property real _bass: 0.0
    property real _mid: 0.0
    property real _treble: 0.0
    property real _beat: 0.0
    property real _energy: 0.0

    // Always-bound 1×1 fallback so ShaderEffect never gets a null texture provider.
    ShaderEffectSource {
        id: fallbackCoverSource
        width: 1
        height: 1
        sourceItem: fallbackCoverRect
        hideSource: true
        live: false
    }

    Rectangle {
        id: fallbackCoverRect
        visible: false
        width: 1
        height: 1
        color: "#6048b8"
    }

    NumberAnimation on _time {
        from: 0
        to: 100000
        duration: 100000000
        loops: Animation.Infinite
        running: active
    }

    Image {
        id: coverImage
        visible: false
        asynchronous: true
        source: coverArtUrl
        smooth: true
        mipmap: true
    }

    ShaderEffectSource {
        id: coverSource
        sourceItem: coverImage
        visible: false
        hideSource: true
        live: true
        smooth: true
    }

    readonly property bool _hasCover: coverImage.status === Image.Ready && coverArtUrl.toString() !== ""

    ShaderEffect {
        id: effect
        anchors.fill: parent

        property real u_time: root._time
        property vector2d u_resolution: Qt.vector2d(Math.max(1, width), Math.max(1, height))
        property real u_bass: root._bass
        property real u_mid: root._mid
        property real u_treble: root._treble
        property real u_beat: root._beat
        property real u_energy: root._energy
        property real u_preset: Math.max(0, Math.min(2, root.mineradioPreset))
        property real u_intensity: 1.15
        property real u_hasCover: root._hasCover ? 1.0 : 0.0
        property real u_orbitYaw: root._orbitYaw
        property real u_orbitPitch: root._orbitPitch
        property real u_orbitZoom: root._orbitZoom
        property vector2d u_pan: Qt.vector2d(root._panX, root._panY)
        property real u_gestureRotX: root._gestureRotX * Math.PI / 180.0
        property real u_gestureRotY: root._gestureRotY * Math.PI / 180.0
        property color u_tint: root.visualizerColor
        property var u_coverTexture: root._hasCover ? coverSource : fallbackCoverSource

        vertexShader: Qt.resolvedUrl("qrc:/resources/shaders/audio3d.vert.qsb")
        fragmentShader: Qt.resolvedUrl("qrc:/resources/shaders/audio3d.frag.qsb")

        opacity: active ? 1.0 : 0.0
        visible: opacity > 0.001

        Behavior on opacity {
            NumberAnimation { duration: 400; easing.type: Easing.OutCubic }
        }

        onStatusChanged: {
            if (status === ShaderEffect.Error)
                console.warn("[Audio3D] Shader error:", log)
        }
    }

    // Drag to orbit, wheel to zoom, middle-drag to pan (Mineradio-style scene navigation)
    MouseArea {
        id: sceneInput
        anchors.fill: parent
        z: 3
        enabled: root.immersiveMode
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton

        property real _lastX: 0
        property real _lastY: 0
        property bool _dragging: false
        property int _dragButton: Qt.NoButton

        onPositionChanged: root.sceneInteracted()

        onPressed: (mouse) => {
            _dragging = true
            _dragButton = mouse.button
            _lastX = mouse.x
            _lastY = mouse.y
        }

        onReleased: {
            _dragging = false
            _dragButton = Qt.NoButton
        }

        onCanceled: {
            _dragging = false
            _dragButton = Qt.NoButton
        }

        onMouseXChanged: sceneInput.applyDrag()
        onMouseYChanged: sceneInput.applyDrag()

        function applyDrag() {
            if (!_dragging || width <= 0 || height <= 0)
                return
            const dx = (mouseX - _lastX) / width
            const dy = (mouseY - _lastY) / height
            _lastX = mouseX
            _lastY = mouseY
            if (_dragButton === Qt.LeftButton) {
                root._orbitYaw += dx * 5.5
                root._orbitPitch = Math.max(-1.15, Math.min(1.15, root._orbitPitch + dy * 3.8))
            } else if (_dragButton === Qt.MiddleButton) {
                root._panX = Math.max(-1.4, Math.min(1.4, root._panX + dx * 1.35))
                root._panY = Math.max(-1.0, Math.min(1.0, root._panY + dy * 1.35))
            }
            root.sceneInteracted()
        }

        onWheel: (wheel) => {
            root._orbitZoom = Math.max(-1.6, Math.min(2.8, root._orbitZoom - wheel.angleDelta.y * 0.0009))
            root.sceneInteracted()
        }

        onDoubleClicked: {
            root.resetSceneView()
        }
    }

    Audio3DStageTitle {
        id: stageTitle
        anchors.fill: parent
        z: 2
        active: root.immersiveMode && root.songTitle !== ""
        songTitle: root.songTitle
        songArtist: root.songArtist
        tintColor: root.visualizerColor
        bass: root._bass
        mid: root._mid
        treble: root._treble
        beat: root._beat
        energy: root._energy
        stageTime: root._time
    }

    function bandValue(bands, index) {
        if (!bands || index < 0 || index >= bands.length)
            return 0
        const v = bands[index]
        return (typeof v === "number") ? v : 0
    }

    function sumBands(bands, from, to) {
        let sum = 0
        let count = 0
        for (let i = from; i <= to && i < bands.length; ++i) {
            sum += bandValue(bands, i)
            ++count
        }
        return count > 0 ? (sum / count) : 0
    }

    function smoothToward(current, target, attack, release) {
        const k = target > current ? attack : release
        return current + (target - current) * k
    }

    Timer {
        interval: 33
        running: root.active
        repeat: true
        onTriggered: root.sampleAudio()
    }

    function sampleAudio() {
        if (!audioAnalyzer) {
            root._bass = smoothToward(root._bass, 0, 0.08, 0.14)
            root._mid = smoothToward(root._mid, 0, 0.08, 0.14)
            root._treble = smoothToward(root._treble, 0, 0.08, 0.14)
            root._beat = smoothToward(root._beat, 0, 0.2, 0.25)
            root._energy = smoothToward(root._energy, 0, 0.08, 0.14)
            return
        }

        const bands = audioAnalyzer.frequencyBands || []
        const bassT = Math.min(1, sumBands(bands, 0, 3) * 1.15)
        const midT = Math.min(1, sumBands(bands, 4, 18) * 1.05)
        const trebleT = Math.min(1, sumBands(bands, 19, 31) * 1.1)
        const energyT = Math.min(1, (audioAnalyzer.overallAmplitude || 0) * 2.2)
        const beatT = Math.min(1, (audioAnalyzer.bassAmplitude || 0) * 2.5)

        root._bass = smoothToward(root._bass, bassT, 0.28, 0.075)
        root._mid = smoothToward(root._mid, midT, 0.18, 0.060)
        root._treble = smoothToward(root._treble, trebleT, 0.18, 0.055)
        root._energy = smoothToward(root._energy, energyT, 0.16, 0.055)
        root._beat = smoothToward(root._beat, beatT, 0.35, 0.20)
    }
}
