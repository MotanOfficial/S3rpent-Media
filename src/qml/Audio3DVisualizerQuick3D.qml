import QtQuick
import QtQuick3D
import s3rpent_media

// Pure Qt Quick 3D scene — cover particle field, star shell, in-scene title.
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

    readonly property bool handlesOwnInput: true

    signal sceneInteracted()

    property real cameraDistance: 14.0
    property real cameraYaw: 0
    property real cameraPitch: -10
    property real cameraPanX: 0
    property real cameraPanY: 0

    readonly property real cameraDistanceMin: 5.0
    readonly property real cameraDistanceMax: 72.0
    // 2D Text under a Node uses pixels — scale down to world units (~4.8 plane).
    readonly property real titleWorldScale: 0.0055

    property real _time: 0.0
    property real _bass: 0.0
    property real _mid: 0.0
    property real _treble: 0.0
    property real _beat: 0.0
    property real _energy: 0.0

    Image {
        id: coverProbe
        visible: false
        asynchronous: true
        cache: false
        source: root.coverArtUrl.toString() !== "" ? root.coverArtUrl : ""
    }

    readonly property bool _hasCover: coverArtUrl.toString() !== ""
                                    && coverProbe.status === Image.Ready

    opacity: active ? 1.0 : 0.0
    visible: opacity > 0.001

    Behavior on opacity {
        NumberAnimation { duration: 400; easing.type: Easing.OutCubic }
    }

    NumberAnimation on _time {
        from: 0
        to: 100000
        duration: 100000000
        loops: Animation.Infinite
        running: active
    }

    View3D {
        id: sceneView
        anchors.fill: parent
        enabled: false
        renderMode: View3D.Offscreen
        camera: sceneCamera

        environment: SceneEnvironment {
            backgroundMode: SceneEnvironment.Color
            clearColor: "#020208"
            antialiasingMode: SceneEnvironment.NoAA
        }

        // Blender-style orbit: rotate pivot, camera sits on +Z.
        Node {
            id: cameraRig
            eulerRotation.x: root.cameraPitch
            eulerRotation.y: root.cameraYaw

            PerspectiveCamera {
                id: sceneCamera
                position: Qt.vector3d(root.cameraPanX, root.cameraPanY, root.cameraDistance)
                clipNear: 0.12
                clipFar: 420
                fieldOfView: 48
            }
        }

        // Soft fill so shaded particles are visible even without strong emissive.
        DirectionalLight {
            eulerRotation.x: -35
            eulerRotation.y: 25
            brightness: 0.35
            ambientColor: Qt.rgba(0.08, 0.09, 0.14, 1.0)
        }

        AudioStarfieldGeometry {
            id: starGeometry
            starCount: 3200
        }

        Model {
            geometry: starGeometry
            castsShadows: false
            receivesShadows: false
            materials: [
                CustomMaterial {
                    shadingMode: CustomMaterial.Shaded
                    cullMode: Material.NoCulling
                    vertexShader: "shaders/audio3d_stars.vert"
                    fragmentShader: "shaders/audio3d_stars.frag"
                    property real u_time: root._time
                    property real u_starHalf: 0.16
                }
            ]
        }

        AudioCoverParticleGeometry {
            id: particleGeometryBloom
            gridResolution: 80
        }

        AudioCoverParticleGeometry {
            id: particleGeometryMain
            gridResolution: 80
        }

        Node {
            id: particleRoot

            Model {
                geometry: particleGeometryBloom
                castsShadows: false
                receivesShadows: false
                materials: [
                    CustomMaterial {
                        shadingMode: CustomMaterial.Shaded
                        cullMode: Material.NoCulling
                        depthDrawMode: Material.NeverDepthDraw
                        opacity: 0.45 + root._beat * 0.3
                        vertexShader: "shaders/audio3d_particles.vert"
                        fragmentShader: "shaders/audio3d_particles.frag"
                        property real u_time: root._time
                        property real u_bass: root._bass
                        property real u_mid: root._mid
                        property real u_treble: root._treble
                        property real u_beat: root._beat
                        property real u_energy: root._energy
                        property real u_preset: root.mineradioPreset
                        property real u_planeSize: 4.8
                        property real u_intensity: 1.2
                        property real u_hasCover: root._hasCover ? 1.0 : 0.0
                        property color u_tint: root.visualizerColor
                        property real u_particleAlpha: 0.5 + root._beat * 0.35
                        property TextureInput coverMap: TextureInput {
                            texture: Texture {
                                source: root.coverArtUrl
                                mipFilter: Texture.Linear
                            }
                        }
                    }
                ]
            }

            Model {
                geometry: particleGeometryMain
                castsShadows: false
                receivesShadows: false
                materials: [
                    CustomMaterial {
                        shadingMode: CustomMaterial.Shaded
                        cullMode: Material.NoCulling
                        vertexShader: "shaders/audio3d_particles.vert"
                        fragmentShader: "shaders/audio3d_particles.frag"
                        property real u_time: root._time
                        property real u_bass: root._bass
                        property real u_mid: root._mid
                        property real u_treble: root._treble
                        property real u_beat: root._beat
                        property real u_energy: root._energy
                        property real u_preset: root.mineradioPreset
                        property real u_planeSize: 4.8
                        property real u_intensity: 1.2
                        property real u_hasCover: root._hasCover ? 1.0 : 0.0
                        property color u_tint: root.visualizerColor
                        property real u_particleAlpha: 1.0
                        property TextureInput coverMap: TextureInput {
                            texture: Texture {
                                source: root.coverArtUrl
                                mipFilter: Texture.Linear
                            }
                        }
                    }
                ]
            }
        }

        // Title lives in the 3D scene — moves with camera orbit like everything else.
        Node {
            id: titleNode
            position: Qt.vector3d(0, 0.1 + root._bass * 0.08, 0.35)
            scale: Qt.vector3d(root.titleWorldScale, root.titleWorldScale, root.titleWorldScale)
            eulerRotation.x: -12 - root._bass * 10 - root._beat * 4
            eulerRotation.y: Math.sin(root._time * 0.35) * root._mid * 3.0
            visible: root.immersiveMode && root.songTitle !== ""

            Column {
                width: 640
                spacing: 8
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter

                Text {
                    width: parent.width
                    text: root.songTitle
                    color: root.visualizerColor
                    font.pixelSize: 42
                    font.bold: true
                    font.letterSpacing: 1.2
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    style: Text.Outline
                    styleColor: "#66000000"
                }

                Text {
                    width: parent.width
                    text: root.songArtist
                    color: Qt.rgba(root.visualizerColor.r, root.visualizerColor.g,
                                   root.visualizerColor.b, 0.78 + root._mid * 0.12)
                    font.pixelSize: 22
                    font.letterSpacing: 0.6
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    maximumLineCount: 1
                    elide: Text.ElideRight
                }
            }
        }
    }

    MouseArea {
        id: sceneInput
        anchors.fill: parent
        z: 10
        enabled: root.active
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        hoverEnabled: true
        preventStealing: true

        property real _lastX: 0
        property real _lastY: 0

        onPressed: (mouse) => {
            _lastX = mouse.x
            _lastY = mouse.y
            sceneInteracted()
        }

        onPositionChanged: (mouse) => {
            if (!pressed)
                return
            const dx = mouse.x - _lastX
            const dy = mouse.y - _lastY
            _lastX = mouse.x
            _lastY = mouse.y
            const shift = (mouse.modifiers & Qt.ShiftModifier) !== 0
            const middle = (mouse.buttons & Qt.MiddleButton) !== 0
            root.applyPointerDrag(dx, dy, middle, shift)
        }

        onWheel: (wheel) => {
            root.applyWheelZoom(wheel.angleDelta.y)
            wheel.accepted = true
        }

        onDoubleClicked: root.resetSceneView()
    }

    function applyPointerDrag(dx, dy, middleButton, shiftHeld) {
        if (shiftHeld || middleButton) {
            cameraPanX += dx * 0.006
            cameraPanY -= dy * 0.006
        } else {
            cameraYaw -= dx * 0.4
            cameraPitch = Math.max(-80, Math.min(80, cameraPitch + dy * 0.4))
        }
        sceneInteracted()
    }

    function applyWheelZoom(angleDeltaY) {
        if (!angleDeltaY)
            return
        cameraDistance = Math.max(root.cameraDistanceMin, Math.min(root.cameraDistanceMax,
            cameraDistance * Math.pow(0.88, angleDeltaY / 120.0)))
        sceneInteracted()
    }

    function resetSceneView() {
        cameraDistance = 14.0
        cameraYaw = 0
        cameraPitch = -10
        cameraPanX = 0
        cameraPanY = 0
        sceneInteracted()
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
