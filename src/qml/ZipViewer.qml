import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import Qt5Compat.GraphicalEffects
import s3rpent_media 1.0 as S3rpentMedia

Item {
    id: zipViewer

    property url source: ""
    property color accentColor: "#1e1e1e"
    property color foregroundColor: "#f5f5f5"
    readonly property real uiScale: Math.max(0.72, Math.min(1.9, Math.min(width / 960.0, height / 720.0)))
    function s(px) { return Math.max(1, Math.round(px * uiScale)) }
    readonly property string displayFileName: {
        if (!source || source === "") return ""
        const raw = source.toString()
        const base = raw.split("/").pop() || raw
        try {
            return decodeURIComponent(base)
        } catch (e) {
            return base
        }
    }
    readonly property string displayPath: {
        if (!source || source === "") return ""
        const raw = source.toString().replace("file:///", "")
        try {
            return decodeURIComponent(raw)
        } catch (e) {
            return raw
        }
    }
    property alias archiveReader: archiveReaderObj
    property string extractionStatus: ""
    property bool extractionError: false
    property string currentFolder: ""
    property var visibleEntries: []
    property int colIconWidth: s(20)
    property int colSizeWidth: s(110)
    property int colPackedWidth: s(110)
    property int colModifiedWidth: s(150)
    property int colNameWidth: Math.max(s(180), entriesList.width - colIconWidth - colSizeWidth - colPackedWidth - colModifiedWidth - s(40))

    S3rpentMedia.ZipArchiveReader {
        id: archiveReaderObj
        source: zipViewer.source
    }
    S3rpentMedia.ExternalDragHelper {
        id: externalDragHelper
    }

    signal loaded()

    function formatBytes(bytes) {
        const b = Number(bytes || 0)
        if (b <= 0) return "0 B"
        const units = ["B", "KB", "MB", "GB", "TB"]
        let value = b
        let unit = 0
        while (value >= 1024 && unit < units.length - 1) {
            value /= 1024
            unit++
        }
        return (unit === 0 ? value.toFixed(0) : value.toFixed(2)) + " " + units[unit]
    }

    function formatSeconds(totalSeconds) {
        const t = Number(totalSeconds || 0)
        if (t < 0) return "--:--"
        const m = Math.floor(t / 60)
        const s = t % 60
        return m + ":" + (s < 10 ? "0" + s : s)
    }

    function formatDate(iso) {
        if (!iso || iso === "")
            return ""
        const dt = new Date(iso)
        if (isNaN(dt.getTime()))
            return iso
        const yy = dt.getFullYear()
        const mm = ("0" + (dt.getMonth() + 1)).slice(-2)
        const dd = ("0" + dt.getDate()).slice(-2)
        const hh = ("0" + dt.getHours()).slice(-2)
        const mi = ("0" + dt.getMinutes()).slice(-2)
        return yy + "-" + mm + "-" + dd + " " + hh + ":" + mi
    }

    function openFolder(path) {
        currentFolder = path
        rebuildVisibleEntries()
    }

    function goUpFolder() {
        if (currentFolder === "") return
        const parts = currentFolder.split("/")
        parts.pop()
        currentFolder = parts.join("/")
        rebuildVisibleEntries()
    }

    function rebuildVisibleEntries() {
        const entries = archiveReaderObj.entries || []
        const map = {}
        const list = []
        const prefix = currentFolder === "" ? "" : (currentFolder + "/")

        if (currentFolder !== "") {
            list.push({
                name: "..",
                displayName: "..",
                isDirectory: true,
                uncompressedSize: 0,
                packedSize: 0,
                modified: "",
                path: "__PARENT__",
                isParent: true
            })
        }

        for (let i = 0; i < entries.length; ++i) {
            const e = entries[i]
            const rawName = (e.name || "").replace(/\\/g, "/")
            const cleanName = rawName.endsWith("/") ? rawName.slice(0, -1) : rawName
            if (cleanName === "") continue
            if (prefix !== "" && !cleanName.startsWith(prefix)) continue

            const relative = prefix === "" ? cleanName : cleanName.slice(prefix.length)
            if (relative === "") continue

            const slashIdx = relative.indexOf("/")
            if (slashIdx >= 0) {
                const folderName = relative.slice(0, slashIdx)
                const folderPath = (prefix + folderName).replace(/\/$/, "")
                if (!map[folderPath]) {
                    map[folderPath] = {
                        name: folderName,
                        displayName: folderName,
                        isDirectory: true,
                        uncompressedSize: 0,
                        packedSize: 0,
                        modified: "",
                        path: folderPath
                    }
                    list.push(map[folderPath])
                }
                const us = Number(e.uncompressedSize || 0)
                const ps = Number((e.packedSize !== undefined ? e.packedSize : e.compressedSize) || 0)
                if (!isNaN(us)) map[folderPath].uncompressedSize += us
                if (!isNaN(ps) && ps > 0) map[folderPath].packedSize += ps
                if (e.modified && (!map[folderPath].modified || e.modified > map[folderPath].modified)) {
                    map[folderPath].modified = e.modified
                }
                continue
            }

            const pathKey = (prefix + relative).replace(/\/$/, "")
            if (map[pathKey]) continue
            const packed = Number((e.packedSize !== undefined ? e.packedSize : e.compressedSize) || 0)
            map[pathKey] = {
                name: relative,
                displayName: relative,
                isDirectory: !!e.isDirectory,
                uncompressedSize: Number(e.uncompressedSize || 0),
                packedSize: packed > 0 ? packed : 0,
                modified: e.modified || "",
                path: pathKey
            }
            list.push(map[pathKey])
        }

        list.sort(function(a, b) {
            if (a.isParent) return -1
            if (b.isParent) return 1
            if (a.isDirectory !== b.isDirectory) return a.isDirectory ? -1 : 1
            return a.displayName.toLowerCase().localeCompare(b.displayName.toLowerCase())
        })

        visibleEntries = list
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.18)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.06)
    }

    ColumnLayout {
        anchors.centerIn: parent
        width: Math.min(parent.width * 0.96, s(980))
        spacing: s(12)

        Label {
            Layout.fillWidth: true
            text: qsTr("ZIP Archive")
            color: zipViewer.foregroundColor
            font.pixelSize: s(28)
            font.bold: true
            horizontalAlignment: Text.AlignHCenter
        }

        Label {
            Layout.fillWidth: true
            text: zipViewer.displayFileName !== "" ? zipViewer.displayFileName : qsTr("No archive loaded")
            color: Qt.rgba(zipViewer.foregroundColor.r, zipViewer.foregroundColor.g, zipViewer.foregroundColor.b, 0.9)
            font.pixelSize: s(18)
            wrapMode: Text.WrapAnywhere
            horizontalAlignment: Text.AlignHCenter
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: pathLabel.implicitHeight + s(16)
            radius: s(10)
            color: Qt.rgba(0, 0, 0, 0.25)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.08)

            Label {
                id: pathLabel
                anchors.fill: parent
                anchors.margins: s(9)
                text: zipViewer.displayPath
                color: Qt.rgba(zipViewer.foregroundColor.r, zipViewer.foregroundColor.g, zipViewer.foregroundColor.b, 0.75)
                font.pixelSize: s(12)
                wrapMode: Text.WrapAnywhere
                verticalAlignment: Text.AlignVCenter
            }
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: s(18)

            Label {
                text: qsTr("Files: %1").arg(archiveReaderObj.fileCount)
                color: Qt.rgba(zipViewer.foregroundColor.r, zipViewer.foregroundColor.g, zipViewer.foregroundColor.b, 0.85)
                font.pixelSize: s(13)
            }
            Label {
                text: qsTr("Entries: %1").arg(archiveReaderObj.entries.length)
                color: Qt.rgba(zipViewer.foregroundColor.r, zipViewer.foregroundColor.g, zipViewer.foregroundColor.b, 0.85)
                font.pixelSize: s(13)
            }
            Label {
                text: qsTr("Uncompressed: %1 MB").arg((archiveReaderObj.totalUncompressedSize / (1024.0 * 1024.0)).toFixed(2))
                color: Qt.rgba(zipViewer.foregroundColor.r, zipViewer.foregroundColor.g, zipViewer.foregroundColor.b, 0.85)
                font.pixelSize: s(13)
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(s(420), Math.max(s(180), zipViewer.height * 0.46))
            radius: s(10)
            color: Qt.rgba(0, 0, 0, 0.24)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.08)

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: s(10)
                spacing: s(6)

                RowLayout {
                    Layout.fillWidth: true
                    spacing: s(8)

                    Label {
                        text: qsTr("Path:")
                        color: Qt.rgba(zipViewer.foregroundColor.r, zipViewer.foregroundColor.g, zipViewer.foregroundColor.b, 0.7)
                        font.pixelSize: s(12)
                    }
                    Label {
                        Layout.fillWidth: true
                        text: currentFolder === "" ? "/" : ("/" + currentFolder)
                        color: zipViewer.foregroundColor
                        font.pixelSize: s(12)
                        elide: Text.ElideMiddle
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: s(8)

                    Item {
                        Layout.preferredWidth: colIconWidth
                        Layout.preferredHeight: 1
                    }
                    Label {
                        Layout.preferredWidth: colNameWidth
                        text: qsTr("Name")
                        font.bold: true
                        font.pixelSize: s(12)
                        color: zipViewer.foregroundColor
                    }
                    Label {
                        Layout.preferredWidth: colSizeWidth
                        text: qsTr("Size")
                        font.bold: true
                        font.pixelSize: s(12)
                        horizontalAlignment: Text.AlignRight
                        color: zipViewer.foregroundColor
                    }
                    Label {
                        Layout.preferredWidth: colPackedWidth
                        text: qsTr("Packed Size")
                        font.bold: true
                        font.pixelSize: s(12)
                        horizontalAlignment: Text.AlignRight
                        color: zipViewer.foregroundColor
                    }
                    Label {
                        Layout.preferredWidth: colModifiedWidth
                        text: qsTr("Modified")
                        font.bold: true
                        font.pixelSize: s(12)
                        horizontalAlignment: Text.AlignRight
                        color: zipViewer.foregroundColor
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1
                    color: Qt.rgba(1, 1, 1, 0.12)
                }

                ScrollView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true

                    ListView {
                        id: entriesList
                        model: visibleEntries
                        spacing: s(3)

                        delegate: Rectangle {
                            required property var modelData
                            required property int index
                            property url dragUrl: ""
                            width: entriesList.width
                            height: s(28)
                            radius: s(6)
                            color: index % 2 === 0 ? Qt.rgba(1, 1, 1, 0.03) : "transparent"

                            TapHandler {
                                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                                onTapped: {
                                    if (!modelData.isDirectory) return
                                    if (modelData.isParent) {
                                        goUpFolder()
                                    } else {
                                        openFolder(modelData.path)
                                    }
                                }
                            }

                            DragHandler {
                                id: rowDragHandler
                                target: null
                                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                                onActiveChanged: {
                                    if (active) {
                                        if (modelData.isParent) {
                                            parent.dragUrl = ""
                                            return
                                        }
                                        const preparedUrl = archiveReaderObj.prepareEntryForExternalDrag(modelData.path, modelData.isDirectory)
                                        if (preparedUrl && preparedUrl.toString() !== "") {
                                            parent.dragUrl = preparedUrl
                                            externalDragHelper.startFileDrag(preparedUrl, modelData.displayName)
                                        } else {
                                            parent.dragUrl = ""
                                        }
                                    } else {
                                        parent.dragUrl = ""
                                    }
                                }
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: s(8)
                                anchors.rightMargin: s(8)
                                spacing: s(8)

                                Item {
                                    Layout.preferredWidth: colIconWidth
                                    Layout.preferredHeight: colIconWidth

                                    Image {
                                        id: rowIcon
                                        anchors.fill: parent
                                        source: modelData.isDirectory
                                                ? "qrc:/qlementine/icons/16/file/folder-open.svg"
                                                : "qrc:/qlementine/icons/16/file/file.svg"
                                        sourceSize.width: colIconWidth
                                        sourceSize.height: colIconWidth
                                        fillMode: Image.PreserveAspectFit
                                        smooth: true
                                        visible: false
                                    }
                                    ColorOverlay {
                                        anchors.fill: parent
                                        source: rowIcon
                                        color: "#ffffff"
                                    }
                                }
                                Label {
                                    Layout.preferredWidth: colNameWidth
                                    text: modelData.isDirectory && !modelData.isParent ? (modelData.displayName + "/") : modelData.displayName
                                    color: Qt.rgba(zipViewer.foregroundColor.r, zipViewer.foregroundColor.g, zipViewer.foregroundColor.b, modelData.isDirectory ? 0.72 : 0.92)
                                    font.pixelSize: s(11)
                                    elide: Text.ElideMiddle
                                }

                                Label {
                                    Layout.preferredWidth: colSizeWidth
                                    horizontalAlignment: Text.AlignRight
                                    text: modelData.isParent ? "" : formatBytes(modelData.uncompressedSize)
                                    color: Qt.rgba(zipViewer.foregroundColor.r, zipViewer.foregroundColor.g, zipViewer.foregroundColor.b, 0.78)
                                    font.pixelSize: s(11)
                                }

                                Label {
                                    Layout.preferredWidth: colPackedWidth
                                    horizontalAlignment: Text.AlignRight
                                    text: modelData.isParent ? "" : formatBytes(modelData.packedSize)
                                    color: Qt.rgba(zipViewer.foregroundColor.r, zipViewer.foregroundColor.g, zipViewer.foregroundColor.b, 0.78)
                                    font.pixelSize: s(11)
                                }

                                Label {
                                    Layout.preferredWidth: colModifiedWidth
                                    horizontalAlignment: Text.AlignRight
                                    text: modelData.isParent ? "" : formatDate(modelData.modified)
                                    color: Qt.rgba(zipViewer.foregroundColor.r, zipViewer.foregroundColor.g, zipViewer.foregroundColor.b, 0.78)
                                    font.pixelSize: s(11)
                                }
                            }
                        }

                        Label {
                            anchors.centerIn: parent
                            visible: archiveReaderObj.loaded && visibleEntries.length === 0
                            text: qsTr("Archive has no entries.")
                            color: Qt.rgba(zipViewer.foregroundColor.r, zipViewer.foregroundColor.g, zipViewer.foregroundColor.b, 0.7)
                            font.pixelSize: s(12)
                        }
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: s(84)
            radius: s(10)
            color: Qt.rgba(0, 0, 0, 0.2)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.08)

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: s(10)
                spacing: s(8)

                ProgressBar {
                    Layout.fillWidth: true
                    from: 0
                    to: 100
                    value: archiveReaderObj.progressPercent
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: s(12)

                    Label {
                        text: qsTr("Progress: %1%").arg(archiveReaderObj.progressPercent.toFixed(1))
                        color: zipViewer.foregroundColor
                        font.pixelSize: s(12)
                    }
                    Label {
                        text: qsTr("Done: %1 / %2").arg(zipViewer.formatBytes(archiveReaderObj.extractedBytes)).arg(zipViewer.formatBytes(archiveReaderObj.totalUncompressedSize))
                        color: Qt.rgba(zipViewer.foregroundColor.r, zipViewer.foregroundColor.g, zipViewer.foregroundColor.b, 0.85)
                        font.pixelSize: s(12)
                    }
                    Label {
                        text: qsTr("Speed: %1/s").arg(zipViewer.formatBytes(archiveReaderObj.speedBytesPerSecond))
                        color: Qt.rgba(zipViewer.foregroundColor.r, zipViewer.foregroundColor.g, zipViewer.foregroundColor.b, 0.85)
                        font.pixelSize: s(12)
                    }
                    Label {
                        text: qsTr("Elapsed: %1").arg(zipViewer.formatSeconds(archiveReaderObj.elapsedSeconds))
                        color: Qt.rgba(zipViewer.foregroundColor.r, zipViewer.foregroundColor.g, zipViewer.foregroundColor.b, 0.85)
                        font.pixelSize: s(12)
                    }
                    Label {
                        text: qsTr("ETA: %1").arg(archiveReaderObj.etaSeconds >= 0 ? zipViewer.formatSeconds(archiveReaderObj.etaSeconds) : "--:--")
                        color: Qt.rgba(zipViewer.foregroundColor.r, zipViewer.foregroundColor.g, zipViewer.foregroundColor.b, 0.85)
                        font.pixelSize: s(12)
                    }
                    Item { Layout.fillWidth: true }
                    Label {
                        text: qsTr("Extracted files: %1").arg(archiveReaderObj.extractedFiles)
                        color: Qt.rgba(zipViewer.foregroundColor.r, zipViewer.foregroundColor.g, zipViewer.foregroundColor.b, 0.85)
                        font.pixelSize: s(12)
                    }
                }
            }
        }

        Label {
            Layout.fillWidth: true
            visible: !archiveReaderObj.loaded && archiveReaderObj.errorString !== ""
            text: archiveReaderObj.errorString
            color: "#ff8080"
            font.pixelSize: s(13)
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
        }

        Label {
            Layout.fillWidth: true
            visible: extractionStatus !== ""
            text: extractionStatus
            color: extractionError ? "#ff8080" : Qt.rgba(zipViewer.foregroundColor.r, zipViewer.foregroundColor.g, zipViewer.foregroundColor.b, 0.85)
            font.pixelSize: s(13)
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: s(10)

            Button {
                text: qsTr("Open Externally")
                enabled: zipViewer.source !== ""
                onClicked: Qt.openUrlExternally(zipViewer.source)
            }

            Button {
                text: archiveReaderObj.extracting ? qsTr("Extracting...") : qsTr("Extract ZIP")
                enabled: zipViewer.source !== "" && archiveReaderObj.loaded && !archiveReaderObj.extracting
                onClicked: extractFolderDialog.open()
            }
        }
    }

    FolderDialog {
        id: extractFolderDialog
        title: qsTr("Select extraction destination")
        onAccepted: {
            extractionStatus = ""
            extractionError = false
            archiveReaderObj.extractAllTo(selectedFolder)
        }
    }

    onSourceChanged: {
        if (source !== "") {
            currentFolder = ""
            archiveReaderObj.reload()
        } else {
            currentFolder = ""
            visibleEntries = []
        }
    }

    Connections {
        target: archiveReaderObj
        function onLoadedChanged() {
            if (archiveReaderObj.loaded) {
                loaded()
            }
        }
        function onExtractionFinished(success, message) {
            extractionStatus = message
            extractionError = !success
        }
        function onEntriesChanged() {
            rebuildVisibleEntries()
        }
    }
}

