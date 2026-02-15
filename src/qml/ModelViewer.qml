import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import s3rp3nt_media 1.0 as S3rp3ntMedia

Item {
    id: modelViewer

    property url source: ""
    property color accentColor: "#121216"
    property color foregroundColor: "#f5f5f5"
    property url resolvedSource: ""
    property string resolverError: ""
    property bool modelSupported: modelLoader.status === Loader.Ready
    property bool modelLoaded: modelLoader.item ? modelLoader.item.isLoaded : false
    property string statusMessage: {
        if (resolverError !== "")
            return resolverError
        if (!modelSupported)
            return qsTr("Qt Quick3D module is not available")
        if (modelLoader.item && modelLoader.item.statusMessage)
            return modelLoader.item.statusMessage
        return qsTr("Ready")
    }

    signal loaded()
    signal loadError(string message)

    S3rp3ntMedia.ModelSourceResolver {
        id: modelSourceResolver
    }

    function resolveSourceForViewing() {
        if (!source || source === "") {
            resolvedSource = ""
            resolverError = ""
            return
        }
        // Resolve asynchronously to avoid blocking the UI thread.
        resolvedSource = ""
        resolverError = ""
        modelSourceResolver.resolveForViewingAsync(source)
    }

    Connections {
        target: modelSourceResolver
        function onResolveFinished(originalSource, newResolvedSource, error) {
            resolverError = error
            if (newResolvedSource && newResolvedSource !== "") {
                resolvedSource = newResolvedSource
            } else if (resolverError !== "") {
                resolvedSource = ""
            } else {
                resolvedSource = modelViewer.source
            }
        }
    }

    onSourceChanged: resolveSourceForViewing()
    Component.onCompleted: resolveSourceForViewing()

    Loader {
        id: modelLoader
        anchors.fill: parent
        asynchronous: true
        source: "ModelViewerImpl.qml"

        onStatusChanged: {
            if (status === Loader.Ready && item) {
                item.source = Qt.binding(function() { return modelViewer.resolvedSource })
                item.accentColor = Qt.binding(function() { return modelViewer.accentColor })
                item.foregroundColor = Qt.binding(function() { return modelViewer.foregroundColor })
                item.loaded.connect(modelViewer.loaded)
                item.loadError.connect(modelViewer.loadError)
            } else if (status === Loader.Error) {
                console.log("[ModelViewer] Quick3D not available - ModelViewerImpl.qml not found")
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.darker(modelViewer.accentColor, 1.25)
        visible: modelLoader.status === Loader.Error || (modelLoader.status === Loader.Null && !modelLoader.source)

        ColumnLayout {
            anchors.centerIn: parent
            spacing: 12

            Label {
                text: qsTr("3D Model Support Not Available")
                color: modelViewer.foregroundColor
                font.pixelSize: 24
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
                Layout.alignment: Qt.AlignHCenter
            }

            Label {
                text: qsTr("Install Qt Quick 3D for your current kit to open OBJ/FBX/GLB models (plus MTL-linked OBJ and BLEND via conversion).")
                color: Qt.rgba(modelViewer.foregroundColor.r, modelViewer.foregroundColor.g, modelViewer.foregroundColor.b, 0.82)
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
                Layout.preferredWidth: 520
                Layout.alignment: Qt.AlignHCenter
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.darker(modelViewer.accentColor, 1.25)
        visible: modelLoader.status === Loader.Loading || modelSourceResolver.resolving

        ColumnLayout {
            anchors.centerIn: parent
            spacing: 10

            BusyIndicator {
                running: true
                Layout.alignment: Qt.AlignHCenter
            }

            Label {
                text: modelSourceResolver.resolving ? qsTr("Converting model...") : qsTr("Loading 3D viewer...")
                color: modelViewer.foregroundColor
                font.pixelSize: 14
                Layout.alignment: Qt.AlignHCenter
            }
        }
    }
}
