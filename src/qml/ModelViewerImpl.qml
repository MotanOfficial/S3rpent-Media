import QtQuick
import QtQuick.Controls
import QtQuick3D
import QtQuick3D.AssetUtils

Item {
    id: modelViewerImpl

    property url source: ""
    property color accentColor: "#121216"
    property color foregroundColor: "#f5f5f5"

    signal loaded()
    signal loadError(string message)

    property real yaw: 0
    property real pitch: -12
    property real cameraDistance: 500
    property real zoomMinDistance: 0.1
    property real zoomMaxDistance: 50000
    property vector3d orbitTarget: Qt.vector3d(0, 0, 0)
    property vector3d modelCenterOffset: Qt.vector3d(0, 0, 0)
    property bool isLoaded: runtimeLoader.status === RuntimeLoader.Success
    property string statusMessage: {
        if (source === "")
            return qsTr("No model selected")
        if (runtimeLoader.status === RuntimeLoader.Success)
            return qsTr("Loaded")
        if (runtimeLoader.status === RuntimeLoader.Error) {
            if (sourcePathLower().endsWith(".fbx"))
                return qsTr("FBX runtime import is not available in this Qt build. Convert FBX to GLB/OBJ.")
            return runtimeLoader.errorString && runtimeLoader.errorString !== "" ? runtimeLoader.errorString : qsTr("Failed to load model")
        }
        if (runtimeLoader.status === RuntimeLoader.Empty)
            return qsTr("Waiting")
        return qsTr("Waiting")
    }
    property bool _loadedEmittedForCurrentSource: false
    property bool _errorEmittedForCurrentSource: false

    function clamp(value, minValue, maxValue) {
        return Math.max(minValue, Math.min(maxValue, value))
    }

    function sourcePathLower() {
        return source ? source.toString().toLowerCase() : ""
    }

    function safeSpan(maxValue, minValue) {
        const span = maxValue - minValue
        return span > 0 ? span : 0.001
    }

    function vectorLength(v) {
        return Math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
    }

    function normalizeVector(v) {
        const len = vectorLength(v)
        if (len <= 1e-8)
            return Qt.vector3d(0, 0, 0)
        return Qt.vector3d(v.x / len, v.y / len, v.z / len)
    }

    function crossProduct(a, b) {
        return Qt.vector3d(
            a.y * b.z - a.z * b.y,
            a.z * b.x - a.x * b.z,
            a.x * b.y - a.y * b.x
        )
    }

    function currentCameraPosition() {
        const yawRad = yaw * Math.PI / 180.0
        const pitchRad = pitch * Math.PI / 180.0

        const x = orbitTarget.x + Math.sin(yawRad) * Math.cos(pitchRad) * cameraDistance
        const y = orbitTarget.y - Math.sin(pitchRad) * cameraDistance
        const z = orbitTarget.z + Math.cos(yawRad) * Math.cos(pitchRad) * cameraDistance
        return Qt.vector3d(x, y, z)
    }

    function panByScreenDelta(dx, dy) {
        if (!runtimeLoader || runtimeLoader.status !== RuntimeLoader.Success)
            return

        const fovRad = (camera.fieldOfView > 1 ? camera.fieldOfView : 60) * Math.PI / 180.0
        const worldPerPixel = (2.0 * cameraDistance * Math.tan(fovRad * 0.5)) / Math.max(1, height)

        // Reversed pan direction (Blender-like feel requested by user).
        const moveX = -dx * worldPerPixel
        const moveY = dy * worldPerPixel

        // Build basis from current camera direction so pan follows exact current view plane.
        const camPos = currentCameraPosition()
        const forward = normalizeVector(Qt.vector3d(
            orbitTarget.x - camPos.x,
            orbitTarget.y - camPos.y,
            orbitTarget.z - camPos.z
        ))
        const worldUp = Qt.vector3d(0, 1, 0)
        let right = normalizeVector(crossProduct(forward, worldUp))
        if (vectorLength(right) <= 1e-8) {
            // Camera close to vertical: pick fallback up axis.
            right = normalizeVector(crossProduct(forward, Qt.vector3d(0, 0, 1)))
        }
        const up = normalizeVector(crossProduct(right, forward))

        orbitTarget = Qt.vector3d(
            orbitTarget.x + right.x * moveX + up.x * moveY,
            orbitTarget.y + right.y * moveX + up.y * moveY,
            orbitTarget.z + right.z * moveX + up.z * moveY
        )
    }

    function fitModelToView() {
        if (!runtimeLoader || runtimeLoader.status !== RuntimeLoader.Success)
            return

        const bounds = runtimeLoader.bounds
        if (!bounds || !bounds.minimum || !bounds.maximum)
            return

        const minV = bounds.minimum
        const maxV = bounds.maximum

        const centerX = (minV.x + maxV.x) * 0.5
        const centerY = (minV.y + maxV.y) * 0.5
        const centerZ = (minV.z + maxV.z) * 0.5
        modelCenterOffset = Qt.vector3d(-centerX, -centerY, -centerZ)
        runtimeLoader.position = modelCenterOffset
        orbitTarget = Qt.vector3d(0, 0, 0)

        const sizeX = safeSpan(maxV.x, minV.x)
        const sizeY = safeSpan(maxV.y, minV.y)
        const sizeZ = safeSpan(maxV.z, minV.z)
        const largestSize = Math.max(sizeX, Math.max(sizeY, sizeZ))
        const radius = Math.max(0.001, largestSize * 0.5)

        const verticalFov = (camera.fieldOfView > 1 ? camera.fieldOfView : 60) * Math.PI / 180.0
        const fitDistance = Math.max(0.5, (radius / Math.tan(verticalFov * 0.5)) * 2.2)

        zoomMinDistance = Math.max(0.01, fitDistance * 0.08)
        zoomMaxDistance = Math.max(10, fitDistance * 200.0)
        cameraDistance = fitDistance
    }

    onSourceChanged: {
        if (source === "") {
            return
        }
        // Reset view per model for predictable first frame.
        yaw = 0
        pitch = -12
        cameraDistance = 500
        zoomMinDistance = 0.1
        zoomMaxDistance = 50000
        orbitTarget = Qt.vector3d(0, 0, 0)
        modelCenterOffset = Qt.vector3d(0, 0, 0)
        _loadedEmittedForCurrentSource = false
        _errorEmittedForCurrentSource = false
    }

    View3D {
        id: sceneView
        anchors.fill: parent
        renderMode: View3D.Offscreen
        camera: camera

        environment: SceneEnvironment {
            clearColor: Qt.darker(modelViewerImpl.accentColor, 1.4)
            backgroundMode: SceneEnvironment.Color
            antialiasingMode: SceneEnvironment.MSAA
            antialiasingQuality: SceneEnvironment.High
        }

        Node {
            id: orbitPivot
            position: modelViewerImpl.orbitTarget
            eulerRotation.x: modelViewerImpl.pitch
            eulerRotation.y: modelViewerImpl.yaw

            PerspectiveCamera {
                id: camera
                position: Qt.vector3d(0, 0, modelViewerImpl.cameraDistance)
                clipNear: Math.max(0.001, modelViewerImpl.cameraDistance * 0.001)
                clipFar: 10000
            }
        }

        DirectionalLight {
            eulerRotation.x: -35
            eulerRotation.y: -35
            brightness: 1.15
        }

        DirectionalLight {
            eulerRotation.x: 45
            eulerRotation.y: 140
            brightness: 0.55
        }

        // World-space floor grid (editor style), centered at origin.
        Node {
            id: worldGrid
            y: 0
            property int halfCount: 30
            property real spacing: 20
            property real lineThickness: 0.003
            property real lineLength: (halfCount * 2 + 1) * spacing

            Repeater3D {
                model: worldGrid.halfCount * 2 + 1
                delegate: Model {
                    readonly property int idx: index - worldGrid.halfCount
                    source: "#Cube"
                    position: Qt.vector3d(idx * worldGrid.spacing, 0, 0)
                    scale: Qt.vector3d(worldGrid.lineThickness, worldGrid.lineThickness, worldGrid.lineLength)
                    materials: DefaultMaterial {
                        diffuseColor: idx === 0 ? "#5f79ff" : "#2f3340"
                        lighting: DefaultMaterial.NoLighting
                    }
                    receivesShadows: false
                    castsShadows: false
                }
            }

            Repeater3D {
                model: worldGrid.halfCount * 2 + 1
                delegate: Model {
                    readonly property int idx: index - worldGrid.halfCount
                    source: "#Cube"
                    position: Qt.vector3d(0, 0, idx * worldGrid.spacing)
                    scale: Qt.vector3d(worldGrid.lineLength, worldGrid.lineThickness, worldGrid.lineThickness)
                    materials: DefaultMaterial {
                        diffuseColor: idx === 0 ? "#ff6a6a" : "#2f3340"
                        lighting: DefaultMaterial.NoLighting
                    }
                    receivesShadows: false
                    castsShadows: false
                }
            }
        }

        RuntimeLoader {
            id: runtimeLoader
            source: modelViewerImpl.source
            onStatusChanged: {
                if (status === RuntimeLoader.Success && !modelViewerImpl._loadedEmittedForCurrentSource) {
                    modelViewerImpl._loadedEmittedForCurrentSource = true
                    modelViewerImpl.fitModelToView()
                    modelViewerImpl.loaded()
                } else if (status === RuntimeLoader.Error && !modelViewerImpl._errorEmittedForCurrentSource) {
                    modelViewerImpl._errorEmittedForCurrentSource = true
                    modelViewerImpl.loadError(modelViewerImpl.statusMessage)
                }
            }
            onBoundsChanged: {
                if (status === RuntimeLoader.Success) {
                    modelViewerImpl.fitModelToView()
                }
            }
        }
    }

    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: function(event) {
            const step = event.angleDelta && event.angleDelta.y !== 0 ? event.angleDelta.y : (event.pixelDelta ? event.pixelDelta.y * 8 : 0)
            if (step !== 0) {
                const ticks = step / 120.0
                const scale = Math.pow(0.9, ticks)
                modelViewerImpl.cameraDistance = modelViewerImpl.clamp(
                    modelViewerImpl.cameraDistance * scale,
                    modelViewerImpl.zoomMinDistance,
                    modelViewerImpl.zoomMaxDistance
                )
            }
        }
    }

    DragHandler {
        id: orbitDrag
        target: null
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad | PointerDevice.Stylus
        acceptedButtons: Qt.MiddleButton
        acceptedModifiers: Qt.NoModifier
        property real prevX: 0
        property real prevY: 0

        onActiveChanged: {
            prevX = translation.x
            prevY = translation.y
        }

        onTranslationChanged: {
            const dx = translation.x - prevX
            const dy = translation.y - prevY
            prevX = translation.x
            prevY = translation.y

            modelViewerImpl.yaw -= dx * 0.28
            modelViewerImpl.pitch = modelViewerImpl.clamp(modelViewerImpl.pitch - dy * 0.18, -89, 89)
        }
    }

    DragHandler {
        id: panDrag
        target: null
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad | PointerDevice.Stylus
        acceptedButtons: Qt.MiddleButton
        acceptedModifiers: Qt.ShiftModifier
        property real prevX: 0
        property real prevY: 0

        onActiveChanged: {
            prevX = translation.x
            prevY = translation.y
        }

        onTranslationChanged: {
            const dx = translation.x - prevX
            const dy = translation.y - prevY
            prevX = translation.x
            prevY = translation.y
            modelViewerImpl.panByScreenDelta(dx, dy)
        }
    }

    Rectangle {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.margins: 12
        radius: 8
        color: Qt.rgba(0, 0, 0, 0.45)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.16)
        implicitWidth: controlsLabel.implicitWidth + 20
        implicitHeight: controlsLabel.implicitHeight + 12

        Label {
            id: controlsLabel
            anchors.centerIn: parent
            text: qsTr("MMB: orbit   Shift+MMB: pan (reversed)   Scroll: zoom")
            color: modelViewerImpl.foregroundColor
            font.pixelSize: 12
        }
    }

    Rectangle {
        anchors.centerIn: parent
        visible: source !== "" && runtimeLoader.status === RuntimeLoader.Error
        color: Qt.rgba(0, 0, 0, 0.55)
        radius: 10
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.2)
        width: Math.min(parent.width * 0.9, 700)
        height: errorText.implicitHeight + 26

        Label {
            id: errorText
            anchors.centerIn: parent
            width: parent.width - 24
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
            text: qsTr("Could not load this model.\n") + modelViewerImpl.statusMessage
            color: modelViewerImpl.foregroundColor
        }
    }
}
