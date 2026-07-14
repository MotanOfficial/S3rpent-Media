import QtQuick

// Native Qt Quick 3D audio visualizer (Mineradio-style recreation).
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

    readonly property bool handlesOwnInput: backendLoader.item
                                            ? backendLoader.item.handlesOwnInput
                                            : false

    signal sceneInteracted()

    function applyPointerDrag(dx, dy, middleButton, shiftHeld) {
        if (backendLoader.item && backendLoader.item.applyPointerDrag)
            backendLoader.item.applyPointerDrag(dx, dy, middleButton, shiftHeld)
    }

    function applyWheelZoom(angleDeltaY) {
        if (backendLoader.item && backendLoader.item.applyWheelZoom)
            backendLoader.item.applyWheelZoom(angleDeltaY)
    }

    function resetSceneView() {
        if (backendLoader.item && backendLoader.item.resetSceneView)
            backendLoader.item.resetSceneView()
    }

    readonly property bool useQuick3D: typeof quick3DAvailable !== "undefined" && quick3DAvailable

    Loader {
        id: backendLoader
        anchors.fill: parent
        sourceComponent: root.useQuick3D ? quick3dBackend : shaderBackend

        onStatusChanged: {
            if (status === Loader.Error && root.useQuick3D) {
                console.warn("[Audio3D] Qt Quick 3D backend failed — shader fallback")
                sourceComponent = shaderBackend
            }
        }
    }

    Component {
        id: quick3dBackend

        Audio3DVisualizerQuick3D {
            anchors.fill: parent
            audioAnalyzer: root.audioAnalyzer
            active: root.active
            visualizerColor: root.visualizerColor
            coverArtUrl: root.coverArtUrl
            mineradioPreset: root.mineradioPreset
            songTitle: root.songTitle
            songArtist: root.songArtist
            immersiveMode: root.immersiveMode
            onSceneInteracted: root.sceneInteracted()
        }
    }

    Component {
        id: shaderBackend

        Audio3DVisualizerNative {
            anchors.fill: parent
            audioAnalyzer: root.audioAnalyzer
            active: root.active
            visualizerColor: root.visualizerColor
            coverArtUrl: root.coverArtUrl
            mineradioPreset: root.mineradioPreset
            songTitle: root.songTitle
            songArtist: root.songArtist
            immersiveMode: root.immersiveMode
            onSceneInteracted: root.sceneInteracted()
        }
    }
}
