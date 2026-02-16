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
    property bool useImportedCamera: true
    property var importedCameraNode: null
    property bool useImportedLights: false
    property int importedLightCount: 0
    readonly property bool hasImportedLights: importedLightCount > 0
    property var importedLightNodes: []
    property var animationControllers: []
    readonly property int animationControllerCount: animationControllers.length
    property bool animationsPlaying: false
    property bool animationLoop: false
    property real animationSpeed: 1.0
    property int _discoverRetryCount: 0
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
    property url _runtimeSource: ""
    // Split GLBs: base + one per visibility property; keys = property names, values = part GLB URLs.
    property var partSources: ({})
    // Current override values per property (0 = hide part, non-zero = show). Used for part loader visibility.
    property var partVisibilityOverrides: ({})
    // Property name -> list of mesh node names (from blend visibility map). Used to show only part meshes and hide base/body in part loaders.
    property var partVisibilityMap: ({})
    // Base mesh names (head, face, plane; not body) to hide in part loaders. From _parts.json baseMeshNames.
    property var partBaseMeshNames: []
    // Body mesh names: show only from first part loader; hide in part loaders 2..N to avoid duplicate. From _parts.json bodyMeshNames.
    property var partBodyMeshNames: []
    // Property -> { materials: [...], objects: [...] } from _matmap.json (Blender driver analysis). Use for data-driven material overrides (e.g. roughness only on listed materials/objects).
    property var blendMaterialMap: ({})
    property var _partLoaders: []  // [{ loader, propName }, ...] for re-applying visibility when overrides change
    // CustomMaterial path: skin mesh GLB + texture map so runtime is independent of RuntimeLoader material exposure.
    property url skinMeshUrl: ""
    property var customMaterials: ({})
    property string textureBaseUrl: ""

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

    function objectChildrenForTraversal(obj) {
        const out = []
        try {
            if (obj && obj.children && obj.children.length) {
                for (let i = 0; i < obj.children.length; i++)
                    out.push(obj.children[i])
            }
        } catch (e) {
        }
        try {
            if (obj && obj.data && obj.data.length) {
                for (let j = 0; j < obj.data.length; j++)
                    out.push(obj.data[j])
            }
        } catch (e2) {
        }
        return out
    }

    // Apply property visibility from map without re-loading the model (instant toggles).
    // Returns the number of node visibilities updated; 0 if no nodes could be matched (e.g. RuntimeLoader doesn't set objectName).
    function applyPropertyOverrides(overridesMap, visibilityMap) {
        if (!runtimeLoader || runtimeLoader.status !== RuntimeLoader.Success || !visibilityMap || typeof overridesMap !== 'object')
            return 0
        const nameToNode = {}
        const queue = objectChildrenForTraversal(runtimeLoader)
        const visited = []
        while (queue.length > 0) {
            const node = queue.shift()
            if (!node || visited.indexOf(node) >= 0)
                continue
            visited.push(node)
            // Qt RuntimeLoader may set objectName from glTF node name; some builds expose asset name differently.
            let name = (node.objectName !== undefined && node.objectName != null) ? String(node.objectName).trim() : ''
            if (!name && typeof node.name === 'string' && node.name)
                name = String(node.name).trim()
            if (name)
                nameToNode[name] = node
            const kids = objectChildrenForTraversal(node)
            for (let i = 0; i < kids.length; i++)
                queue.push(kids[i])
        }
        let updated = 0
        const mapEntryCount = Object.keys(visibilityMap).length
        for (const propName in visibilityMap) {
            let nodeNames = visibilityMap[propName]
            if (!nodeNames || (typeof nodeNames.length !== 'number'))
                continue
            const show = (overridesMap[propName] !== undefined && overridesMap[propName] !== 0)
            const len = nodeNames.length
            for (let n = 0; n < len; n++) {
                const node = nameToNode[String(nodeNames[n])]
                if (node && node.visible !== undefined) {
                    node.visible = show
                    updated++
                }
            }
        }
        if (mapEntryCount > 0 && updated === 0)
            console.log("[ModelViewer3D] Visibility overrides: no nodes matched (names in scene:", Object.keys(nameToNode).length, "- instant toggles need node names from loader)")
        return updated
    }

    // Part loaders export base+part meshes so body comes from parts; hide base (head/face/plane) and hide body in loaders 2..N.
    // Only set visibility on named nodes so we don't hide an unnamed root (which would hide the whole loader).
    function applyPartLoaderVisibility(loader, propName) {
        if (!loader || !partVisibilityMap || typeof partVisibilityMap !== 'object')
            return
        const partNodeNames = partVisibilityMap[propName]
        if (!partNodeNames || (typeof partNodeNames.length !== 'number'))
            return
        const showPart = (partVisibilityOverrides[propName] === undefined || partVisibilityOverrides[propName] !== 0)
        const partSet = {}
        for (let n = 0; n < partNodeNames.length; n++)
            partSet[String(partNodeNames[n])] = true
        const baseSet = {}
        const baseList = partBaseMeshNames
        if (baseList && (typeof baseList.length === 'number'))
            for (let b = 0; b < baseList.length; b++)
                baseSet[String(baseList[b])] = true
        // Body only from first part loader; hide body in part loaders 2..N to avoid duplicate.
        let partIndex = -1
        for (let i = 0; i < _partLoaders.length; i++) {
            if (_partLoaders[i].propName === propName) {
                partIndex = i
                break
            }
        }
        const bodySet = {}
        // Hide body in part loaders 2..N, or in all part loaders when using dedicated skin mesh (CustomMaterial).
        const hideBody = (partIndex > 0) || (skinMeshUrl && skinMeshUrl.toString() !== "")
        if (hideBody && partBodyMeshNames && (typeof partBodyMeshNames.length === 'number')) {
            for (let b = 0; b < partBodyMeshNames.length; b++)
                bodySet[String(partBodyMeshNames[b])] = true
        }
        const nameToNode = {}
        const queue = objectChildrenForTraversal(loader)
        const visited = []
        while (queue.length > 0) {
            const node = queue.shift()
            if (!node || visited.indexOf(node) >= 0)
                continue
            visited.push(node)
            let name = (node.objectName !== undefined && node.objectName != null) ? String(node.objectName).trim() : ''
            if (!name && typeof node.name === 'string' && node.name)
                name = String(node.name).trim()
            if (name)
                nameToNode[name] = node
            const kids = objectChildrenForTraversal(node)
            for (let i = 0; i < kids.length; i++)
                queue.push(kids[i])
        }
        for (const name in nameToNode) {
            const node = nameToNode[name]
            if (!node || node.visible === undefined)
                continue
            if (baseSet[name] || bodySet[name])
                node.visible = false
            else
                node.visible = partSet[name] ? showPart : false
        }
    }

    function registerPartLoader(loader, propName) {
        for (let i = 0; i < _partLoaders.length; i++) {
            if (_partLoaders[i].propName === propName) {
                _partLoaders[i].loader = loader
                return
            }
        }
        _partLoaders.push({ loader: loader, propName: propName })
    }

    // Apply skin CustomMaterial to all mesh nodes under loader (used when skin_mesh.glb is loaded).
    function applySkinCustomMaterial(loader) {
        const mat = skinMaterialLoader.item
        if (!mat || !loader) return
        const queue = objectChildrenForTraversal(loader)
        const visited = []
        while (queue.length > 0) {
            const n = queue.shift()
            if (!n || visited.indexOf(n) >= 0) continue
            visited.push(n)
            try {
                if ((n.materials !== undefined && Array.isArray(n.materials)) || (n.material !== undefined && n.material !== null)) {
                    n.materials = [mat]
                }
            } catch (e) {}
            const kids = objectChildrenForTraversal(n)
            for (let k = 0; k < kids.length; k++) queue.push(kids[k])
        }
    }

    function basename(u) {
        if (!u) return ""
        const s = String(u)
        const q = s.indexOf("?")
        const clean = q >= 0 ? s.slice(0, q) : s
        const slash = Math.max(clean.lastIndexOf("/"), clean.lastIndexOf("\\"))
        return slash >= 0 ? clean.slice(slash + 1) : clean
    }

    function dumpImportedMaterials(tag) {
        if (!runtimeLoader || runtimeLoader.status !== RuntimeLoader.Success) return
        let mats = []
        const queue = objectChildrenForTraversal(runtimeLoader)
        const visited = []
        const texPropNames = ["baseColorMap", "roughnessMap", "metalnessMap", "normalMap", "occlusionMap", "emissiveMap"]
        while (queue.length) {
            const n = queue.shift()
            if (!n || visited.indexOf(n) >= 0) continue
            visited.push(n)
            try {
                const arr = n.materials || (n.material ? [n.material] : [])
                for (let i = 0; i < arr.length; i++) {
                    const m = arr[i]
                    if (!m) continue
                    const mName = (m.objectName ? String(m.objectName) : "") || (m.name ? String(m.name) : "")
                    const rough = (m.roughness !== undefined) ? m.roughness : "no-roughness-prop"
                    const srcs = {}
                    for (let t = 0; t < texPropNames.length; t++) {
                        try {
                            const tex = m[texPropNames[t]]
                            if (tex && tex.source)
                                srcs[texPropNames[t]] = String(tex.source)
                        } catch(e) {}
                    }
                    mats.push({ mName: mName, rough: rough, textureSources: srcs })
                }
            } catch(e2) {}
            const kids = objectChildrenForTraversal(n)
            for (let k = 0; k < kids.length; k++) queue.push(kids[k])
        }
        console.log("[MatDump]", tag, "materials seen:", mats.length, JSON.stringify(mats.slice(0, 20)))
    }

    // Match materials by texture source basename only (exact, no substring). Don't touch materials with no visible texture source.
    function applyBlendDrivenMaterialOverridesByTextures(propName, propValue) {
        const entry = blendMaterialMap ? blendMaterialMap[propName] : null
        if (!entry) return
        const imgs = entry.images || []
        const imgSet = {}
        for (let i = 0; i < imgs.length; i++) {
            const k = String(imgs[i]).trim()
            if (k)
                imgSet[k.toLowerCase()] = true
        }
        const rough = Math.max(0.0, Math.min(1.0, Number(propValue)))
        const seen = []
        function seenBefore(mat) {
            if (!mat) return true
            if (seen.indexOf(mat) >= 0) return true
            seen.push(mat)
            return false
        }
        let updated = 0
        const texProps = ["baseColorMap", "roughnessMap", "metalnessMap", "normalMap", "occlusionMap", "emissiveMap"]
        function applyToRoot(rootObj) {
            if (!rootObj) return
            const queue = objectChildrenForTraversal(rootObj)
            const visited = []
            while (queue.length) {
                const n = queue.shift()
                if (!n || visited.indexOf(n) >= 0) continue
                visited.push(n)
                let mats = []
                try { if (n.materials && n.materials.length) mats = n.materials } catch(e) {}
                try { if (!mats.length && n.material) mats = [n.material] } catch(e2) {}
                for (let i = 0; i < mats.length; i++) {
                    const m = mats[i]
                    if (!m || m.roughness === undefined) continue
                    if (seenBefore(m)) continue
                    let sawAnyTexture = false
                    let hit = false
                    for (let t = 0; t < texProps.length; t++) {
                        try {
                            const tex = m[texProps[t]]
                            if (!tex || !tex.source) continue
                            const full = String(tex.source).trim()
                            if (!full) continue
                            sawAnyTexture = true
                            const b = basename(full).toLowerCase()
                            if (imgSet[b]) hit = true
                        } catch(e3) {}
                    }
                    if (!sawAnyTexture)
                        continue
                    if (!hit)
                        continue
                    m.roughness = rough
                    updated++
                }
                const kids = objectChildrenForTraversal(n)
                for (let k = 0; k < kids.length; k++) queue.push(kids[k])
            }
        }
        if (runtimeLoader && runtimeLoader.status === RuntimeLoader.Success)
            applyToRoot(runtimeLoader)
        for (let i = 0; i < _partLoaders.length; i++) {
            const p = _partLoaders[i] && _partLoaders[i].loader
            if (p && p.status === RuntimeLoader.Success)
                applyToRoot(p)
        }
        if (updated > 0)
            console.log("[Roughness]", propName, "updated materials:", updated, "value:", rough)
    }

    // Apply material overrides (e.g. roughness) to base + all part loaders using blendMaterialMap (data-driven).
    // Prefer texture-based matching (entry.images) when RuntimeLoader doesn't expose names.
    function applyBlendDrivenMaterialOverrides(propName, propValue) {
        if (!blendMaterialMap || typeof blendMaterialMap !== 'object')
            return
        const entry = blendMaterialMap[propName]
        if (!entry)
            return
        const imgs = entry.images || []
        if (imgs.length > 0) {
            applyBlendDrivenMaterialOverridesByTextures(propName, propValue)
            return
        }
        const mats = entry.materials || []
        const objs = entry.objects || []
        const matSet = {}
        for (let i = 0; i < mats.length; i++)
            matSet[String(mats[i])] = true
        const objSet = {}
        for (let i = 0; i < objs.length; i++)
            objSet[String(objs[i])] = true
        const rough = Math.max(0.0, Math.min(1.0, Number(propValue)))
        function nodeName(node) {
            let n = (node && node.objectName !== undefined && node.objectName != null) ? String(node.objectName).trim() : ''
            if (!n && node && typeof node.name === 'string' && node.name)
                n = String(node.name).trim()
            return n
        }
        function applyToRoot(rootObj) {
            if (!rootObj)
                return 0
            let updated = 0
            const queue = objectChildrenForTraversal(rootObj)
            const visited = []
            while (queue.length) {
                const node = queue.shift()
                if (!node || visited.indexOf(node) >= 0)
                    continue
                visited.push(node)
                const nName = nodeName(node)
                const isTargetObject = nName && objSet[nName] === true
                try {
                    if (node.materials && node.materials.length) {
                        for (let i = 0; i < node.materials.length; i++) {
                            const m = node.materials[i]
                            if (!m) continue
                            const mName = nodeName(m)
                            const isTargetMaterial = mName && matSet[mName] === true
                            if (isTargetObject || isTargetMaterial) {
                                if (m.roughness !== undefined) {
                                    m.roughness = rough
                                    updated++
                                }
                            }
                        }
                    }
                } catch (e) {}
                try {
                    if (node.material) {
                        const m = node.material
                        const mName = nodeName(m)
                        const isTargetMaterial = mName && matSet[mName] === true
                        if (isTargetObject || isTargetMaterial) {
                            if (m.roughness !== undefined) {
                                m.roughness = rough
                                updated++
                            }
                        }
                    }
                } catch (e2) {}
                const kids = objectChildrenForTraversal(node)
                for (let k = 0; k < kids.length; k++)
                    queue.push(kids[k])
            }
            return updated
        }
        if (runtimeLoader && runtimeLoader.status === RuntimeLoader.Success)
            applyToRoot(runtimeLoader)
        for (let i = 0; i < _partLoaders.length; i++) {
            const partEntry = _partLoaders[i]
            if (partEntry && partEntry.loader && partEntry.loader.status === RuntimeLoader.Success)
                applyToRoot(partEntry.loader)
        }
    }

    function applyAllMaterialDrivenOverridesFromCurrentState() {
        if (!blendMaterialMap || typeof blendMaterialMap !== 'object')
            return
        for (const k in partVisibilityOverrides) {
            if (blendMaterialMap[k] !== undefined)
                applyBlendDrivenMaterialOverrides(k, partVisibilityOverrides[k])
        }
    }

    function applyAllPartLoaderVisibilities() {
        for (let i = 0; i < _partLoaders.length; i++) {
            const entry = _partLoaders[i]
            if (entry.loader)
                applyPartLoaderVisibility(entry.loader, entry.propName)
        }
    }

    function isCameraObject(obj) {
        if (!obj)
            return false
        return typeof obj.clipNear !== "undefined" &&
               typeof obj.clipFar !== "undefined" &&
               typeof obj.position !== "undefined"
    }

    function isLightObject(obj) {
        if (!obj)
            return false
        return typeof obj.brightness !== "undefined" &&
               typeof obj.color !== "undefined"
    }

    function applyImportedLightState() {
        for (let i = 0; i < importedLightNodes.length; i++) {
            const light = importedLightNodes[i]
            if (!light)
                continue
            try {
                if (light.brightness > 2.5)
                    light.brightness = 2.5
                else if (light.brightness <= 0)
                    light.brightness = 0.2
            } catch (e) {
            }
            try {
                light.visible = useImportedLights
            } catch (e2) {
            }
        }
    }

    function isAnimationControllerObject(obj) {
        if (!obj)
            return false
        const hasRunning = typeof obj.running !== "undefined"
        const hasControlMethod = typeof obj.start === "function" ||
                                 typeof obj.stop === "function" ||
                                 typeof obj.restart === "function"
        const hasTiming = typeof obj.duration !== "undefined" || typeof obj.position !== "undefined"
        return hasRunning && (hasControlMethod || hasTiming)
    }

    function applyAnimationControlState() {
        for (let i = 0; i < animationControllers.length; i++) {
            const ctrl = animationControllers[i]
            if (!ctrl)
                continue
            try {
                if (typeof ctrl.loops !== "undefined")
                    ctrl.loops = animationLoop ? Animation.Infinite : 1
            } catch (e) {
            }
            try {
                if (typeof ctrl.playbackRate !== "undefined")
                    ctrl.playbackRate = animationSpeed
                else if (typeof ctrl.speed !== "undefined")
                    ctrl.speed = animationSpeed
            } catch (e2) {
            }
            try {
                ctrl.running = animationsPlaying
            } catch (e3) {
            }
            if (animationsPlaying) {
                try {
                    if (typeof ctrl.start === "function")
                        ctrl.start()
                    else if (typeof ctrl.restart === "function")
                        ctrl.restart()
                } catch (e4) {
                }
            } else {
                try {
                    if (typeof ctrl.stop === "function")
                        ctrl.stop()
                } catch (e5) {
                }
            }
        }
    }

    function applyImportedMaterialTweaks() {
        if (!runtimeLoader || runtimeLoader.status !== RuntimeLoader.Success)
            return

        let touchedMaterials = 0
        const queue = objectChildrenForTraversal(runtimeLoader)
        const visited = []
        while (queue.length > 0) {
            const node = queue.shift()
            if (!node || visited.indexOf(node) >= 0)
                continue
            visited.push(node)

            try {
                if (node.materials && node.materials.length) {
                    for (let i = 0; i < node.materials.length; i++) {
                        const mat = node.materials[i]
                        if (mat && typeof mat.cullMode !== "undefined") {
                            mat.cullMode = Material.NoCulling
                            touchedMaterials++
                        }
                    }
                }
            } catch (e) {
            }

            const kids = objectChildrenForTraversal(node)
            for (let j = 0; j < kids.length; j++)
                queue.push(kids[j])
        }
        if (touchedMaterials > 0) {
            console.log("[ModelViewer3D] Applied NoCulling to imported materials:", touchedMaterials)
        }
    }

    function discoverImportedSceneFeatures() {
        importedCameraNode = null
        importedLightCount = 0
        importedLightNodes = []
        animationControllers = []

        if (!runtimeLoader || runtimeLoader.status !== RuntimeLoader.Success)
            return

        const rootChildren = objectChildrenForTraversal(runtimeLoader)
        console.log("[ModelViewer3D] discoverImportedSceneFeatures() root child count:", rootChildren.length)
        const queue = rootChildren
        const visited = []
        while (queue.length > 0) {
            const node = queue.shift()
            if (!node || visited.indexOf(node) >= 0)
                continue
            visited.push(node)

            if (importedCameraNode === null && isCameraObject(node))
                importedCameraNode = node
            if (isLightObject(node)) {
                importedLightCount++
                importedLightNodes.push(node)
            }
            if (isAnimationControllerObject(node))
                animationControllers.push(node)

            const kids = objectChildrenForTraversal(node)
            for (let i = 0; i < kids.length; i++)
                queue.push(kids[i])
        }

        console.log("[ModelViewer3D] scene discovery result:",
                    "visited=", visited.length,
                    "camera=", importedCameraNode ? "yes" : "no",
                    "lights=", importedLightCount,
                    "animations=", animationControllers.length)
        applyImportedLightState()
        applyImportedMaterialTweaks()
        applyAnimationControlState()

        // Imported nodes may arrive after first frame; retry a few times if scene looks empty.
        if (!importedCameraNode && importedLightCount === 0 && animationControllers.length === 0 && _discoverRetryCount < 8) {
            _discoverRetryCount += 1
            discoverRetryTimer.restart()
        }
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
            _runtimeSource = ""
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
        importedCameraNode = null
        importedLightCount = 0
        importedLightNodes = []
        animationControllers = []
        _discoverRetryCount = 0
        _loadedEmittedForCurrentSource = false
        _errorEmittedForCurrentSource = false
        _partLoaders = []
        // Force RuntimeLoader to reload: clear then set so it picks up the new URL.
        _runtimeSource = ""
        Qt.callLater(function() { _runtimeSource = source })
    }

    onPartVisibilityOverridesChanged: applyAllPartLoaderVisibilities()

    onAnimationsPlayingChanged: applyAnimationControlState()
    onAnimationLoopChanged: applyAnimationControlState()
    onAnimationSpeedChanged: applyAnimationControlState()
    onUseImportedLightsChanged: applyImportedLightState()

    View3D {
        id: sceneView
        anchors.fill: parent
        renderMode: View3D.Offscreen
        camera: (modelViewerImpl.useImportedCamera && modelViewerImpl.importedCameraNode) ? modelViewerImpl.importedCameraNode : camera

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
            visible: !modelViewerImpl.hasImportedLights || !modelViewerImpl.useImportedLights
        }

        DirectionalLight {
            eulerRotation.x: 45
            eulerRotation.y: 140
            brightness: 0.55
            visible: !modelViewerImpl.hasImportedLights || !modelViewerImpl.useImportedLights
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
            source: modelViewerImpl._runtimeSource
            onStatusChanged: {
                console.log("[ModelViewer3D] RuntimeLoader status:", status, "error:", errorString)
                if (status === RuntimeLoader.Success && !modelViewerImpl._loadedEmittedForCurrentSource) {
                    modelViewerImpl._loadedEmittedForCurrentSource = true
                    modelViewerImpl.fitModelToView()
                    Qt.callLater(function() { modelViewerImpl.discoverImportedSceneFeatures() })
                    Qt.callLater(function() { modelViewerImpl.dumpImportedMaterials("base") })
                    Qt.callLater(function() { modelViewerImpl.applyAllMaterialDrivenOverridesFromCurrentState() })
                    modelViewerImpl.loaded()
                } else if (status === RuntimeLoader.Error && !modelViewerImpl._errorEmittedForCurrentSource) {
                    modelViewerImpl._errorEmittedForCurrentSource = true
                    modelViewerImpl.loadError(modelViewerImpl.statusMessage)
                }
            }
            onBoundsChanged: {
                if (status === RuntimeLoader.Success) {
                    modelViewerImpl.fitModelToView()
                    Qt.callLater(function() { modelViewerImpl.discoverImportedSceneFeatures() })
                }
            }
        }

        Repeater3D {
            model: partSources && typeof partSources === 'object' ? Object.keys(partSources) : []
            delegate: RuntimeLoader {
                id: partLoader
                source: partSources[modelData] || ""
                visible: (partVisibilityOverrides[modelData] === undefined || partVisibilityOverrides[modelData] !== 0)
                onStatusChanged: {
                    if (status === RuntimeLoader.Success) {
                        modelViewerImpl.registerPartLoader(partLoader, modelData)
                        modelViewerImpl.applyPartLoaderVisibility(partLoader, modelData)
                        Qt.callLater(function() { modelViewerImpl.applyAllMaterialDrivenOverridesFromCurrentState() })
                    }
                }
            }
        }

        RuntimeLoader {
            id: skinMeshLoader
            source: (modelViewerImpl.skinMeshUrl && modelViewerImpl.skinMeshUrl.toString() !== "") ? modelViewerImpl.skinMeshUrl : ""
            visible: source.toString() !== ""
            onStatusChanged: {
                if (status === RuntimeLoader.Success) {
                    Qt.callLater(function() { modelViewerImpl.applySkinCustomMaterial(skinMeshLoader) })
                    Qt.callLater(function() { modelViewerImpl.applyAllPartLoaderVisibilities() })
                }
            }
        }
    }

    Loader {
        id: skinMaterialLoader
        active: (modelViewerImpl.skinMeshUrl && modelViewerImpl.skinMeshUrl.toString() !== "")
                && modelViewerImpl.customMaterials
                && modelViewerImpl.customMaterials.skin
                && modelViewerImpl.customMaterials.skin.baseColorVariant0
                && modelViewerImpl.customMaterials.skin.baseColorVariant0.length > 0
        onItemChanged: {
            if (item && skinMeshLoader.status === RuntimeLoader.Success)
                Qt.callLater(function() { modelViewerImpl.applySkinCustomMaterial(skinMeshLoader) })
        }
        sourceComponent: Component {
            CustomMaterial {
                shadingMode: CustomMaterial.Shaded
                vertexShader: "shaders/skin_material.vert"
                fragmentShader: "shaders/skin_material.frag"
                property real u_roughness: (modelViewerImpl.partVisibilityOverrides["Skin Roughness"] !== undefined)
                    ? modelViewerImpl.partVisibilityOverrides["Skin Roughness"] : 0.5
                property real u_colorMix: (modelViewerImpl.partVisibilityOverrides["Color Yellow/Black"] !== undefined)
                    ? modelViewerImpl.partVisibilityOverrides["Color Yellow/Black"]
                    : (modelViewerImpl.partVisibilityOverrides["Color Yellow Black"] !== undefined)
                      ? modelViewerImpl.partVisibilityOverrides["Color Yellow Black"] : 0.0
                property TextureInput baseColorVariant0: TextureInput {
                    texture: Texture {
                        source: {
                            var base = modelViewerImpl.textureBaseUrl || ""
                            var skin = modelViewerImpl.customMaterials && modelViewerImpl.customMaterials.skin
                            var arr = skin && skin.baseColorVariant0
                            var name = (arr && arr[0]) ? arr[0] : ""
                            return (base && name) ? (base + name + ".png") : ""
                        }
                    }
                }
                property TextureInput baseColorVariant1: TextureInput {
                    texture: Texture {
                        source: {
                            var base = modelViewerImpl.textureBaseUrl || ""
                            var skin = modelViewerImpl.customMaterials && modelViewerImpl.customMaterials.skin
                            var arr = skin && skin.baseColorVariant1
                            var name = (arr && arr[0]) ? arr[0] : ""
                            return (base && name) ? (base + name + ".png") : ""
                        }
                    }
                }
            }
        }
    }

    Timer {
        id: discoverRetryTimer
        interval: 150
        repeat: false
        onTriggered: modelViewerImpl.discoverImportedSceneFeatures()
    }

    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        enabled: !(modelViewerImpl.useImportedCamera && modelViewerImpl.importedCameraNode)
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
        enabled: !(modelViewerImpl.useImportedCamera && modelViewerImpl.importedCameraNode)
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
        enabled: !(modelViewerImpl.useImportedCamera && modelViewerImpl.importedCameraNode)
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
            text: (modelViewerImpl.useImportedCamera && modelViewerImpl.importedCameraNode)
                ? qsTr("Imported camera active")
                : qsTr("MMB: orbit   Shift+MMB: pan (reversed)   Scroll: zoom")
            color: modelViewerImpl.foregroundColor
            font.pixelSize: 12
        }
    }

    Rectangle {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.leftMargin: 12
        anchors.topMargin: 56
        radius: 8
        color: Qt.rgba(0, 0, 0, 0.45)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.16)
        visible: modelViewerImpl.importedCameraNode !== null
        implicitWidth: cameraToggleRow.implicitWidth + 20
        implicitHeight: cameraToggleRow.implicitHeight + 12

        Row {
            id: cameraToggleRow
            anchors.centerIn: parent
            spacing: 8

            Label {
                text: qsTr("Camera")
                color: modelViewerImpl.foregroundColor
                font.pixelSize: 12
                anchors.verticalCenter: parent.verticalCenter
            }

            Button {
                text: modelViewerImpl.useImportedCamera ? qsTr("Imported") : qsTr("Orbit")
                onClicked: modelViewerImpl.useImportedCamera = !modelViewerImpl.useImportedCamera
            }
        }
    }

    Rectangle {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.leftMargin: 12
        anchors.topMargin: 100
        radius: 8
        color: Qt.rgba(0, 0, 0, 0.45)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.16)
        visible: modelViewerImpl.hasImportedLights
        implicitWidth: lightToggleRow.implicitWidth + 20
        implicitHeight: lightToggleRow.implicitHeight + 12

        Row {
            id: lightToggleRow
            anchors.centerIn: parent
            spacing: 8

            Label {
                text: qsTr("Lights")
                color: modelViewerImpl.foregroundColor
                font.pixelSize: 12
                anchors.verticalCenter: parent.verticalCenter
            }

            Button {
                text: modelViewerImpl.useImportedLights ? qsTr("Imported") : qsTr("Viewer")
                onClicked: modelViewerImpl.useImportedLights = !modelViewerImpl.useImportedLights
            }
        }
    }

    Rectangle {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 12
        radius: 8
        color: Qt.rgba(0, 0, 0, 0.45)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.16)
        visible: modelViewerImpl.animationControllerCount > 0
        implicitWidth: animationControlsCol.implicitWidth + 20
        implicitHeight: animationControlsCol.implicitHeight + 16

        Column {
            id: animationControlsCol
            anchors.centerIn: parent
            spacing: 6

            Label {
                text: qsTr("Animations: %1").arg(modelViewerImpl.animationControllerCount)
                color: modelViewerImpl.foregroundColor
                font.pixelSize: 12
            }

            Row {
                spacing: 8

                Button {
                    text: modelViewerImpl.animationsPlaying ? qsTr("Pause") : qsTr("Play")
                    onClicked: modelViewerImpl.animationsPlaying = !modelViewerImpl.animationsPlaying
                }

                CheckBox {
                    text: qsTr("Loop")
                    checked: modelViewerImpl.animationLoop
                    onToggled: modelViewerImpl.animationLoop = checked
                }
            }

            Row {
                spacing: 8

                Label {
                    text: qsTr("Speed")
                    color: modelViewerImpl.foregroundColor
                    font.pixelSize: 12
                    anchors.verticalCenter: parent.verticalCenter
                }

                Slider {
                    id: speedSlider
                    from: 0.1
                    to: 2.0
                    stepSize: 0.1
                    value: modelViewerImpl.animationSpeed
                    width: 120
                    onMoved: modelViewerImpl.animationSpeed = value
                }
            }
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
