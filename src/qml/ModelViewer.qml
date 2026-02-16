import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import s3rpent_media 1.0 as S3rpentMedia

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

    readonly property bool isBlendSource: {
        const s = source.toString().toLowerCase()
        return s.indexOf(".blend") >= 0
    }
    property var modelPropertyOverrides: ({})
    property var blendVisibilityMap: ({})
    // Property -> { materials: [...], objects: [...] } from Blender driver analysis; use for data-driven material overrides.
    property var blendMaterialMap: ({})
    // When non-empty, resolvedSource is the base GLB and this holds { base: url, parts: { propName: url } } for instant toggles.
    property var resolvedModelParts: ({})

    signal loaded()
    signal loadError(string message)

    S3rpentMedia.ModelSourceResolver {
        id: modelSourceResolver
    }

    ListModel {
        id: blendPropertyDefs
        // Populated from blend's Properties bone when a .blend is converted (see onResolveFinished).
    }

    function resolveSourceForViewing() {
        if (!source || source === "") {
            resolvedSource = ""
            resolverError = ""
            return
        }
        resolvedSource = ""
        resolverError = ""
        if (isBlendSource && Object.keys(modelPropertyOverrides).length > 0)
            modelSourceResolver.resolveForViewingAsync(source, fullPropertyOverridesForResolve())
        else
            modelSourceResolver.resolveForViewingAsync(source)
    }

    function setPropertyAndResolve(name, value) {
        var o = {}
        for (var k in modelPropertyOverrides)
            o[k] = modelPropertyOverrides[k]
        o[name] = value
        modelPropertyOverrides = o
        if (!source || source === "") return

        var full = fullPropertyOverridesForResolve()

        // 1) Visibility props -> instant (split GLBs)
        var isVisibilityProp = isBlendSource && blendVisibilityMap && blendVisibilityMap.hasOwnProperty(name)
        if (isVisibilityProp && resolvedModelParts && resolvedModelParts.parts && Object.keys(resolvedModelParts.parts).length > 0) {
            if (modelLoader.item && typeof modelLoader.item.applyPropertyOverrides === 'function') {
                const updated = modelLoader.item.applyPropertyOverrides(full, blendVisibilityMap)
                if (updated > 0)
                    return
            }
            return
        }

        // 2) Material/driver props from matmap -> instant (no re-export). Skip when custom skin/clothes materials are used (CustomMaterial uniforms handle it).
        var isMaterialDrivenProp = isBlendSource && blendMaterialMap && blendMaterialMap.hasOwnProperty(name)
        if (isMaterialDrivenProp) {
            var useCustomSkin = resolvedModelParts && resolvedModelParts.skinMesh && resolvedModelParts.customMaterials && resolvedModelParts.customMaterials.skin
            if (useCustomSkin && (name === "Skin Roughness" || name === "Color Yellow/Black" || name === "Color Yellow Black")) {
                return
            }
            if (modelLoader.item && typeof modelLoader.item.applyBlendDrivenMaterialOverrides === 'function') {
                modelLoader.item.applyBlendDrivenMaterialOverrides(name, full[name])
                return
            }
            return
        }

        // 3) Otherwise -> re-export
        resolvedSource = ""
        resolverError = ""
        modelSourceResolver.resolveForViewingAsync(source, full)
    }

    function currentPropertyValue(name) {
        if (modelPropertyOverrides.hasOwnProperty(name))
            return modelPropertyOverrides[name]
        for (var i = 0; i < blendPropertyDefs.count; i++) {
            if (blendPropertyDefs.get(i).name === name)
                return blendPropertyDefs.get(i).defaultVal
        }
        return 0
    }

    // Full overrides for export: every discovered property with its current UI value, so changing one property doesn't reset the rest.
    function fullPropertyOverridesForResolve() {
        var full = {}
        for (var i = 0; i < blendPropertyDefs.count; i++) {
            var name = blendPropertyDefs.get(i).name
            if (name)
                full[name] = currentPropertyValue(name)
        }
        // Include any keys from modelPropertyOverrides not yet in blendPropertyDefs (e.g. before discovery)
        for (var k in modelPropertyOverrides)
            if (!full.hasOwnProperty(k))
                full[k] = modelPropertyOverrides[k]
        return full
    }

    Connections {
        target: modelSourceResolver
        function onResolveFinished(originalSource, newResolvedSource, error) {
            console.log("[ModelViewer] resolve finished:",
                        "original=", originalSource,
                        "resolved=", newResolvedSource,
                        "error=", error)
            resolverError = error
            if (newResolvedSource && newResolvedSource !== "") {
                resolvedSource = newResolvedSource
            } else if (resolverError !== "") {
                resolvedSource = ""
            } else {
                resolvedSource = modelViewer.source
            }
            if (modelViewer.isBlendSource && originalSource && originalSource.toString() !== "") {
                var discovered = modelSourceResolver.getDiscoveredBlendProperties(originalSource)
                blendPropertyDefs.clear()
                if (discovered && discovered.length > 0) {
                    for (var i = 0; i < discovered.length; i++) {
                        var p = discovered[i]
                        blendPropertyDefs.append({
                            name: p.name || "",
                            label: p.label || p.name || "",
                            type: (p.type === "float") ? "float" : "int",
                            defaultVal: typeof p.defaultVal === "number" ? p.defaultVal : 0,
                            minVal: typeof p.minVal === "number" ? p.minVal : 0,
                            maxVal: typeof p.maxVal === "number" ? p.maxVal : 1
                        })
                    }
                }
                blendVisibilityMap = modelSourceResolver.getBlendVisibilityMap(originalSource) || {}
                blendMaterialMap = modelSourceResolver.getBlendMaterialMap(originalSource) || {}
                console.log("[ModelViewer] matmap keys:", Object.keys(blendMaterialMap || {}).length,
                    "example Skin Roughness:", JSON.stringify((blendMaterialMap || {})["Skin Roughness"]))
                resolvedModelParts = modelSourceResolver.getResolvedModelParts(originalSource) || {}
            }
        }
    }

    onSourceChanged: {
        if (isBlendSource) {
            modelPropertyOverrides = {}
            blendVisibilityMap = {}
            blendMaterialMap = {}
            resolvedModelParts = {}
        }
        resolveSourceForViewing()
    }
    Component.onCompleted: resolveSourceForViewing()

    Loader {
        id: modelLoader
        anchors.fill: modelViewer.isBlendSource ? undefined : parent
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: modelViewer.isBlendSource ? propertiesPanel.left : parent.right
        asynchronous: true
        source: "ModelViewerImpl.qml"

        onStatusChanged: {
            if (status === Loader.Ready && item) {
                item.source = Qt.binding(function() { return modelViewer.resolvedSource })
                item.accentColor = Qt.binding(function() { return modelViewer.accentColor })
                item.foregroundColor = Qt.binding(function() { return modelViewer.foregroundColor })
                item.partSources = Qt.binding(function() { return (modelViewer.resolvedModelParts && modelViewer.resolvedModelParts.parts) ? modelViewer.resolvedModelParts.parts : {} })
                item.partVisibilityOverrides = Qt.binding(function() {
                    var o = {}
                    for (var i = 0; i < blendPropertyDefs.count; i++) {
                        var n = blendPropertyDefs.get(i).name
                        if (n) o[n] = modelViewer.currentPropertyValue(n)
                    }
                    for (var k in modelViewer.modelPropertyOverrides) o[k] = modelViewer.modelPropertyOverrides[k]
                    return o
                })
                item.partVisibilityMap = Qt.binding(function() { return modelViewer.blendVisibilityMap || {} })
                item.blendMaterialMap = Qt.binding(function() { return modelViewer.blendMaterialMap || {} })
                item.partBaseMeshNames = Qt.binding(function() {
                    var names = (modelViewer.resolvedModelParts && modelViewer.resolvedModelParts.baseMeshNames) ? modelViewer.resolvedModelParts.baseMeshNames : []
                    return (names && typeof names.length === 'number') ? names : []
                })
                item.partBodyMeshNames = Qt.binding(function() {
                    var names = (modelViewer.resolvedModelParts && modelViewer.resolvedModelParts.bodyMeshNames) ? modelViewer.resolvedModelParts.bodyMeshNames : []
                    return (names && typeof names.length === 'number') ? names : []
                })
                item.skinMeshUrl = Qt.binding(function() {
                    return (modelViewer.resolvedModelParts && modelViewer.resolvedModelParts.skinMesh) ? modelViewer.resolvedModelParts.skinMesh : ""
                })
                item.customMaterials = Qt.binding(function() { return modelViewer.resolvedModelParts && modelViewer.resolvedModelParts.customMaterials ? modelViewer.resolvedModelParts.customMaterials : {} })
                item.textureBaseUrl = Qt.binding(function() {
                    var base = (modelViewer.resolvedModelParts && modelViewer.resolvedModelParts.base) ? String(modelViewer.resolvedModelParts.base) : ""
                    if (!base) return ""
                    var idx = Math.max(base.lastIndexOf("/"), base.lastIndexOf("\\"))
                    return idx >= 0 ? base.substring(0, idx + 1) : base
                })
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

    Rectangle {
        id: propertiesPanel
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: 220
        visible: modelViewer.isBlendSource
        color: Qt.darker(modelViewer.accentColor, 1.15)
        border.width: 0
        border.color: Qt.rgba(1, 1, 1, 0.08)

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 6

            Label {
                text: qsTr("Properties")
                color: modelViewer.foregroundColor
                font.pixelSize: 13
                font.bold: true
                Layout.topMargin: 4
                Layout.bottomMargin: 4
            }

            ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                ScrollBar.vertical.policy: ScrollBar.AsNeeded

                ColumnLayout {
                    width: propertiesPanel.width - 24
                    spacing: 4

                    Repeater {
                        model: blendPropertyDefs
                        delegate: RowLayout {
                            spacing: 8
                            Layout.fillWidth: true
                            Label {
                                text: model.label
                                color: modelViewer.foregroundColor
                                font.pixelSize: 12
                                opacity: 0.95
                                Layout.minimumWidth: 90
                                Layout.maximumWidth: 100
                                elide: Text.ElideRight
                            }
                            SpinBox {
                                id: spin
                                from: model.type === "float" ? Math.round(model.minVal * 100) : model.minVal
                                to: model.type === "float" ? Math.round(model.maxVal * 100) : model.maxVal
                                value: model.type === "float"
                                    ? Math.round(modelViewer.currentPropertyValue(model.name) * 100)
                                    : Math.round(modelViewer.currentPropertyValue(model.name))
                                editable: true
                                stepSize: model.type === "float" ? 5 : 1
                                Layout.fillWidth: true
                                onValueModified: {
                                    const v = model.type === "float" ? spin.value / 100.0 : spin.value
                                    modelViewer.setPropertyAndResolve(model.name, v)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
