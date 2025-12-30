import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: textViewer
    
    property url source: ""
    property color accentColor: "#121216"
    property color foregroundColor: "#f5f5f5"
    property string content: ""
    property int lineCount: 0
    property int characterCount: 0
    property bool modified: false
    property bool wordWrap: true
    property real lineHeight: 21
    
    // Chunking for data management
    property int charsPerChunk: 8000
    property var chunkData: []  // {start, end} for character positions
    property var modifiedChunks: ({})
    property int visibleChunkStart: 0
    property int visibleChunkEnd: 0
    property bool useCharBasedChunking: false
    
    // Merged display
    property string visibleText: ""
    property int visibleTextStartChunk: -1
    property int visibleTextEndChunk: -1
    
    property real gutterWidth: wordWrap ? 0 : Math.max(50, (String(lineCount).length * 10) + 20)
    property real fixedContentHeight: 0  // Set once when wordWrap is ON
    property real maxLineWidth: 0  // Longest line width for horizontal scroll
    
    signal saved()
    signal saveError(string message)
    signal contentLoaded()
    
    // Recalculate height when word wrap changes or width changes significantly
    onWordWrapChanged: recalculateContentHeight()
    onWidthChanged: {
        if (width > 0 && characterCount > 0) {
            recalculateContentHeight()
        }
        // Reload content if width wasn't available on initial load
        if (width > 0 && source !== "" && content === "" && !_pendingReload) {
            _pendingReload = true
            Qt.callLater(function() {
                _pendingReload = false
                loadContent()
            })
        }
    }
    
    property bool _pendingReload: false
    
    function recalculateContentHeight() {
        if (characterCount === 0) return
        
        const availableWidth = Math.max(400, width - gutterWidth - 40)
        const charsPerLine = Math.max(40, Math.floor(availableWidth / 8.5))
        const estimatedWrappedLines = Math.ceil(characterCount / charsPerLine)
        const effectiveLines = wordWrap ? Math.max(lineCount, estimatedWrappedLines) : lineCount
        fixedContentHeight = effectiveLines * lineHeight + 50
    }
    
    function loadContent() {
        if (source === "" || typeof ColorUtils === "undefined" || !ColorUtils.readTextFile) {
            content = ""
            chunkData = []
            modifiedChunks = {}
            lineCount = 0
            characterCount = 0
            modified = false
            visibleText = ""
            return
        }
        
        const fileContent = ColorUtils.readTextFile(source)
        if (fileContent !== null && fileContent !== undefined && fileContent.length > 0) {
            content = fileContent
            characterCount = fileContent.length
            const lines = fileContent.split('\n')
            lineCount = lines.length
            
            // Check for very long lines and calculate max width
            let maxLineLength = 0
            for (let i = 0; i < lines.length; i++) {
                if (lines[i].length > maxLineLength) {
                    maxLineLength = lines[i].length
                }
            }
            
            // Estimate max line width in pixels (approx 8px per char for monospace)
            maxLineWidth = maxLineLength * 8.5
            
            // Use character chunking for large files or long lines
            if (characterCount > 20000 || maxLineLength > 5000) {
                wordWrap = true
                useCharBasedChunking = true
                createCharacterChunks(fileContent)
            } else {
                useCharBasedChunking = false
                // Single chunk for small files
                chunkData = [{ start: 0, end: characterCount }]
            }
            
            modifiedChunks = {}
            modified = false
            
            // Calculate content height
            // For word-wrapped long lines, estimate based on characters and width
            const availableWidth = Math.max(400, textViewer.width - gutterWidth - 40)  // Assume minimum width
            const charsPerLine = Math.max(40, Math.floor(availableWidth / 8.5))
            const estimatedWrappedLines = Math.ceil(characterCount / charsPerLine)
            
            // Use max of actual lines or estimated wrapped lines
            const effectiveLines = wordWrap ? Math.max(lineCount, estimatedWrappedLines) : lineCount
            fixedContentHeight = effectiveLines * lineHeight + 50
            
            // Initial visible range - reset tracking to force refresh
            visibleChunkStart = 0
            visibleChunkEnd = Math.min(2, chunkData.length - 1)
            visibleTextStartChunk = -1  // Force updateVisibleText to actually update
            visibleTextEndChunk = -1
            updateVisibleText()
            
            contentLoaded()
        } else {
            content = ""
            chunkData = []
            modifiedChunks = {}
            lineCount = 0
            characterCount = 0
            modified = false
            visibleText = ""
            fixedContentHeight = 0
            maxLineWidth = 0
        }
    }
    
    function createCharacterChunks(text) {
        const chunks = []
        let pos = 0
        
        while (pos < text.length) {
            let endPos = Math.min(pos + charsPerChunk, text.length)
            
            // Try to break at word boundary
            if (endPos < text.length) {
                const searchStart = Math.max(endPos - 500, pos)
                for (let j = endPos; j >= searchStart; j--) {
                    const ch = text[j]
                    if (ch === ' ' || ch === '\t' || ch === '\n') {
                        endPos = j + 1
                        break
                    }
                }
            }
            
            chunks.push({ start: pos, end: endPos })
            pos = endPos
        }
        
        chunkData = chunks
    }
    
    function getChunkText(chunkIndex) {
        if (chunkIndex < 0 || chunkIndex >= chunkData.length) return ""
        if (chunkIndex in modifiedChunks) return modifiedChunks[chunkIndex]
        const chunk = chunkData[chunkIndex]
        return content.substring(chunk.start, chunk.end)
    }
    
    function getMergedText(startChunk, endChunk) {
        let merged = ""
        for (let i = startChunk; i <= endChunk; i++) {
            merged += getChunkText(i)
        }
        return merged
    }
    
    function updateVisibleText() {
        // Only update if visible range changed
        if (visibleTextStartChunk === visibleChunkStart && visibleTextEndChunk === visibleChunkEnd) {
            return
        }
        
        visibleTextStartChunk = visibleChunkStart
        visibleTextEndChunk = visibleChunkEnd
        visibleText = getMergedText(visibleChunkStart, visibleChunkEnd)
        
    }
    
    function getVisibleStartLine() {
        // For single-line files, always line 0 (displayed as 1)
        if (lineCount <= 1) return 0
        
        // Count actual newlines in chunks before visible start
        let linesBefore = 0
        for (let i = 0; i < visibleChunkStart; i++) {
            const chunkText = getChunkText(i)
            // Count newline characters, not split length
            const newlines = (chunkText.match(/\n/g) || []).length
            linesBefore += newlines
        }
        return linesBefore
    }
    
    function getVisibleStartY() {
        // For word-wrapped long-line content, use character percentage
        if (wordWrap && lineCount < 100 && chunkData.length > 0) {
            const charsBefore = visibleChunkStart > 0 ? chunkData[visibleChunkStart].start : 0
            const charPercent = characterCount > 0 ? charsBefore / characterCount : 0
            return charPercent * (fixedContentHeight - 50)
        }
        // For normal content, use line-based position
        return getVisibleStartLine() * lineHeight
    }
    
    function getVisibleStartX() {
        // For horizontal scrolling in single-line content (no word wrap)
        if (!wordWrap && lineCount < 10 && chunkData.length > 0 && visibleChunkStart > 0) {
            const charsBefore = chunkData[visibleChunkStart].start
            // Estimate X position based on characters (approx 8.5px per char)
            return charsBefore * 8.5
        }
        return 0
    }
    
    function getChunkYPosition(chunkIndex) {
        // For single-line files, Y is always 0
        if (lineCount <= 1) return 0
        
        // Calculate Y based on newlines before this chunk
        let linesBefore = 0
        for (let i = 0; i < chunkIndex && i < chunkData.length; i++) {
            const chunkText = getChunkText(i)
            const newlines = (chunkText.match(/\n/g) || []).length
            linesBefore += newlines
        }
        return linesBefore * lineHeight
    }
    
    function updateVisibleChunks() {
        const scrollY = contentFlickable.contentY
        const scrollX = contentFlickable.contentX
        const viewHeight = contentFlickable.height
        const viewWidth = contentFlickable.width
        const numChunks = chunkData.length
        
        if (numChunks === 0) return
        
        // For word-wrapped content, use scroll percentage to determine visible chunks
        if (wordWrap && lineCount < 100) {
            // For wrapped long-line content, use scroll position percentage
            const scrollPercent = fixedContentHeight > viewHeight ? 
                scrollY / (fixedContentHeight - viewHeight) : 0
            const endScrollPercent = fixedContentHeight > viewHeight ?
                (scrollY + viewHeight) / fixedContentHeight : 1
            
            const startChunk = Math.floor(scrollPercent * numChunks)
            const endChunk = Math.min(numChunks - 1, Math.ceil(endScrollPercent * numChunks))
            
            // Add buffer chunks
            const newStart = Math.max(0, startChunk - 1)
            const newEnd = Math.min(numChunks - 1, endChunk + 2)
            
            if (newStart !== visibleChunkStart || newEnd !== visibleChunkEnd) {
                visibleChunkStart = newStart
                visibleChunkEnd = newEnd
                updateVisibleText()
            }
            return
        }
        
        // For horizontal scrolling in single-line content (no word wrap)
        if (!wordWrap && lineCount < 10 && maxLineWidth > viewWidth) {
            // Use horizontal scroll position to determine visible chunks
            const scrollPercent = maxLineWidth > viewWidth ? 
                scrollX / (maxLineWidth - viewWidth + 40) : 0
            const endScrollPercent = maxLineWidth > viewWidth ?
                (scrollX + viewWidth) / maxLineWidth : 1
            
            const startChunk = Math.max(0, Math.floor(scrollPercent * numChunks) - 1)
            const endChunk = Math.min(numChunks - 1, Math.ceil(endScrollPercent * numChunks) + 1)
            
            // Add buffer chunks
            const newStart = Math.max(0, startChunk - 1)
            const newEnd = Math.min(numChunks - 1, endChunk + 2)
            
            if (newStart !== visibleChunkStart || newEnd !== visibleChunkEnd) {
                visibleChunkStart = newStart
                visibleChunkEnd = newEnd
                updateVisibleText()
            }
            return
        }
        
        // Calculate which line is at the top of the view
        const topLine = Math.max(0, Math.floor(scrollY / lineHeight))
        const bottomLine = Math.min(lineCount - 1, Math.ceil((scrollY + viewHeight) / lineHeight))
        
        // Find which chunks contain these lines
        let currentLineCount = 0
        let startChunk = 0
        let endChunk = numChunks - 1
        let foundStart = false
        
        for (let i = 0; i < numChunks; i++) {
            const chunkLines = getChunkText(i).split('\n').length
            
            // Find first chunk that contains topLine
            if (!foundStart && currentLineCount + chunkLines > topLine) {
                startChunk = i
                foundStart = true
            }
            
            // Find last chunk that contains bottomLine
            if (currentLineCount + chunkLines > bottomLine) {
                endChunk = i
                break
            }
            
            currentLineCount += chunkLines
        }
        
        // Ensure we always include the last chunk if we're near the end
        const totalLines = lineCount
        if (bottomLine >= totalLines - 10) {  // Within 10 lines of end
            endChunk = numChunks - 1
        }
        
        // Add buffer chunks
        const newStart = Math.max(0, startChunk - 1)
        const newEnd = Math.min(numChunks - 1, endChunk + 1)
        
        if (newStart !== visibleChunkStart || newEnd !== visibleChunkEnd) {
            visibleChunkStart = newStart
            visibleChunkEnd = newEnd
            updateVisibleText()
        }
    }
    
    function applyEdits(newText) {
        // Split the edited text back into chunks
        if (chunkData.length <= 1) {
            // Single chunk - simple case
            if (newText !== content) {
                modifiedChunks[0] = newText
                modified = true
            }
            return
        }
        
        // For merged chunks, we need to redistribute the text
        // Simple approach: put all edited text into first visible chunk, clear others
        const totalOriginalLength = getMergedText(visibleChunkStart, visibleChunkEnd).length
        
        if (newText !== getMergedText(visibleChunkStart, visibleChunkEnd)) {
            // Text changed - redistribute across visible chunks
            let pos = 0
            for (let i = visibleChunkStart; i <= visibleChunkEnd; i++) {
                const originalLen = getChunkText(i).length
                const proportion = originalLen / totalOriginalLength
                const newLen = Math.round(newText.length * proportion)
                
                if (i === visibleChunkEnd) {
                    // Last chunk gets remainder
                    modifiedChunks[i] = newText.substring(pos)
                } else {
                    modifiedChunks[i] = newText.substring(pos, pos + newLen)
                    pos += newLen
                }
            }
            modified = true
        }
    }
    
    function getFullContent() {
        let result = ""
        for (let i = 0; i < chunkData.length; i++) {
            result += getChunkText(i)
        }
        return result
    }
    
    function save() {
        if (source === "" || typeof ColorUtils === "undefined" || !ColorUtils.writeTextFile) {
            saveError("Cannot save: no file loaded or save not available")
            return false
        }
        
        const fullContent = getFullContent()
        const success = ColorUtils.writeTextFile(source, fullContent)
        if (success) {
            content = fullContent
            characterCount = fullContent.length
            const lines = fullContent.split('\n')
            lineCount = lines.length
            
            // Recalculate max line width
            let maxLen = 0
            for (let i = 0; i < lines.length; i++) {
                if (lines[i].length > maxLen) maxLen = lines[i].length
            }
            maxLineWidth = maxLen * 8.5
            
            // Update fixed content height
            const availableWidth = Math.max(400, textViewer.width - gutterWidth - 40)
            const charsPerLine = Math.max(40, Math.floor(availableWidth / 8.5))
            const estimatedWrappedLines = Math.ceil(characterCount / charsPerLine)
            const effectiveLines = wordWrap ? Math.max(lineCount, estimatedWrappedLines) : lineCount
            fixedContentHeight = effectiveLines * lineHeight + 50
            
            // Recreate chunks
            if (useCharBasedChunking) {
                createCharacterChunks(fullContent)
            } else {
                chunkData = [{ start: 0, end: characterCount }]
            }
            
            modifiedChunks = {}
            modified = false
            visibleTextStartChunk = -1  // Force refresh
            updateVisibleText()
            saved()
            return true
        } else {
            saveError("Failed to save file")
            return false
        }
    }
    
    onSourceChanged: {
        if (width > 0) {
            loadContent()
        }
    }
    
    onVisibleChanged: {
        // Reload when becoming visible if content wasn't loaded
        if (visible && width > 0 && source !== "" && content === "") {
            loadContent()
        }
    }
    
    Component.onCompleted: {
        if (width > 0) {
            loadContent()
        }
    }
    
    Rectangle {
        anchors.fill: parent
        color: Qt.darker(accentColor, 1.15)
        
        // Top toolbar
        Rectangle {
            id: toolbar
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 16
            anchors.bottomMargin: 0
            height: 32
            color: Qt.rgba(0, 0, 0, 0.2)
            radius: 4
            z: 10
            
            Row {
                anchors.left: parent.left
                anchors.leftMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                spacing: 12
                
                Row {
                    spacing: 6
                    anchors.verticalCenter: parent.verticalCenter
                    
                    Rectangle {
                        width: 36
                        height: 20
                        radius: 10
                        color: textViewer.wordWrap ? Qt.rgba(100, 200, 100, 0.6) : Qt.rgba(100, 100, 100, 0.4)
                        anchors.verticalCenter: parent.verticalCenter
                        
                        Rectangle {
                            width: 16
                            height: 16
                            radius: 8
                            color: "#ffffff"
                            anchors.verticalCenter: parent.verticalCenter
                            x: textViewer.wordWrap ? 18 : 2
                            Behavior on x { NumberAnimation { duration: 150 } }
                        }
                        
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: textViewer.wordWrap = !textViewer.wordWrap
                        }
                    }
                    
                    Text {
                        text: "Word Wrap"
                        color: foregroundColor
                        font.pixelSize: 12
                        font.family: "Segoe UI"
                        anchors.verticalCenter: parent.verticalCenter
                        opacity: 0.8
                    }
                }
                
                Rectangle {
                    width: 1
                    height: 16
                    color: Qt.rgba(foregroundColor.r, foregroundColor.g, foregroundColor.b, 0.2)
                    anchors.verticalCenter: parent.verticalCenter
                }
                
                Text {
                    text: textViewer.lineCount.toLocaleString() + " lines · " + textViewer.characterCount.toLocaleString() + " chars"
                    color: foregroundColor
                    font.pixelSize: 11
                    font.family: "Segoe UI"
                    anchors.verticalCenter: parent.verticalCenter
                    opacity: 0.6
                }
            }
            
            Row {
                anchors.right: parent.right
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8
                visible: textViewer.modified
                
                Rectangle {
                    width: 8
                    height: 8
                    radius: 4
                    color: "#ffcc00"
                    anchors.verticalCenter: parent.verticalCenter
                }
                
                Text {
                    text: "Modified · Ctrl+S"
                    color: "#ffcc00"
                    font.pixelSize: 11
                    font.family: "Segoe UI"
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
        
        // Content area
        Row {
            anchors.fill: parent
            anchors.margins: 16
            anchors.topMargin: 56
            spacing: 0
            
            // Line number gutter (only when word wrap OFF)
            Rectangle {
                id: gutter
                width: textViewer.gutterWidth
                height: parent.height
                visible: !textViewer.wordWrap
                color: Qt.rgba(0, 0, 0, 0.2)
                clip: true
                
                // Line numbers - positioned to match visible text
                TextEdit {
                    id: lineNumberEdit
                    width: gutter.width - 8
                    
                    // Position synced with the merged text in content area
                    y: mergedTextEdit.y - contentFlickable.contentY
                    
                    readOnly: true
                    selectByMouse: false
                    activeFocusOnPress: false
                    
                    color: Qt.rgba(foregroundColor.r, foregroundColor.g, foregroundColor.b, 0.4)
                    font.pixelSize: 14
                    font.family: "Consolas"
                    horizontalAlignment: Text.AlignRight
                    
                    topPadding: mergedTextEdit.topPadding
                    bottomPadding: mergedTextEdit.bottomPadding
                    
                    // Generate line numbers text
                    text: {
                        // For single-line files, always show line 1
                        if (textViewer.lineCount <= 1) return "1"
                        
                        // Count actual newlines in chunks before visible start
                        let linesBefore = 0
                        for (let i = 0; i < textViewer.visibleChunkStart; i++) {
                            const chunkText = textViewer.getChunkText(i)
                            const newlines = (chunkText.match(/\n/g) || []).length
                            linesBefore += newlines
                        }
                        
                        const visibleLines = textViewer.visibleText.split('\n').length
                        const numbers = []
                        for (let i = 0; i < visibleLines; i++) {
                            numbers.push(linesBefore + i + 1)
                        }
                        return numbers.join('\n')
                    }
                }
            }
            
            Flickable {
                id: contentFlickable
                width: parent.width - gutter.width
                height: parent.height
                // Horizontal scroll when word wrap is OFF (only if content actually overflows)
                contentWidth: textViewer.wordWrap ? width : (textViewer.maxLineWidth > width - 20 ? textViewer.maxLineWidth + 40 : width)
                // Use fixed height OR the actual rendered height from TextEdit
                contentHeight: Math.max(height, textViewer.fixedContentHeight)
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                
                onContentYChanged: textViewer.updateVisibleChunks()
                onContentXChanged: if (!textViewer.wordWrap) textViewer.updateVisibleChunks()
                
                ScrollBar.vertical: ScrollBar {
                    id: verticalScrollBar
                    // Hide vertical scrollbar for single-line files when word wrap is off
                    policy: (!textViewer.wordWrap && textViewer.lineCount <= 1) ? ScrollBar.AlwaysOff : ScrollBar.AsNeeded
                    
                    contentItem: Rectangle {
                        implicitWidth: 8
                        radius: 4
                        color: verticalScrollBar.pressed 
                            ? Qt.rgba(foregroundColor.r, foregroundColor.g, foregroundColor.b, 0.7)
                            : verticalScrollBar.hovered 
                                ? Qt.rgba(foregroundColor.r, foregroundColor.g, foregroundColor.b, 0.5)
                                : Qt.rgba(foregroundColor.r, foregroundColor.g, foregroundColor.b, 0.3)
                        
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }
                    
                    background: Rectangle {
                        implicitWidth: 12
                        radius: 6
                        color: Qt.rgba(0, 0, 0, 0.1)
                    }
                }
                
                ScrollBar.horizontal: ScrollBar {
                    id: horizontalScrollBar
                    // Only show when word wrap is off AND content actually overflows
                    policy: (textViewer.wordWrap || contentFlickable.contentWidth <= contentFlickable.width) ? ScrollBar.AlwaysOff : ScrollBar.AsNeeded
                    
                    contentItem: Rectangle {
                        implicitHeight: 8
                        radius: 4
                        color: horizontalScrollBar.pressed 
                            ? Qt.rgba(foregroundColor.r, foregroundColor.g, foregroundColor.b, 0.7)
                            : horizontalScrollBar.hovered 
                                ? Qt.rgba(foregroundColor.r, foregroundColor.g, foregroundColor.b, 0.5)
                                : Qt.rgba(foregroundColor.r, foregroundColor.g, foregroundColor.b, 0.3)
                        
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }
                    
                    background: Rectangle {
                        implicitHeight: 12
                        radius: 6
                        color: Qt.rgba(0, 0, 0, 0.1)
                    }
                }
                
                // Single merged TextEdit for all visible chunks
                TextEdit {
                    id: mergedTextEdit
                    
                    // Position based on content before visible chunk
                    x: textViewer.getVisibleStartX()
                    y: textViewer.getVisibleStartY()
                    // When word wrap is ON, limit to flickable width. When OFF, match content width
                    width: textViewer.wordWrap ? contentFlickable.width - 20 : contentFlickable.contentWidth
                    
                    text: textViewer.visibleText
                    color: foregroundColor
                    font.pixelSize: 14
                    font.family: "Consolas"
                    wrapMode: textViewer.wordWrap ? TextEdit.Wrap : TextEdit.NoWrap
                    textFormat: TextEdit.PlainText
                    selectByMouse: true
                    selectionColor: Qt.rgba(foregroundColor.r, foregroundColor.g, foregroundColor.b, 0.3)
                    selectedTextColor: foregroundColor
                    
                    leftPadding: 8
                    topPadding: 4
                    bottomPadding: 4
                    
                    // Track content height for word-wrapped mode
                    onImplicitHeightChanged: {
                        if (textViewer.wordWrap && implicitHeight > 0) {
                            // Update fixed height based on actual wrapped height
                            const startLineY = textViewer.getVisibleStartLine() * textViewer.lineHeight
                            const estimatedTotalHeight = startLineY + implicitHeight + 50
                            if (estimatedTotalHeight > textViewer.fixedContentHeight) {
                                textViewer.fixedContentHeight = estimatedTotalHeight
                            }
                        }
                    }
                    
                    property bool updating: false
                    
                    onTextChanged: {
                        if (!updating && text !== textViewer.visibleText) {
                            textViewer.applyEdits(text)
                        }
                    }
                    
                    Keys.onTabPressed: {
                        insert(cursorPosition, "    ")
                    }
                    
                    cursorDelegate: Rectangle {
                        width: 2
                        color: foregroundColor
                        visible: mergedTextEdit.activeFocus
                        
                        SequentialAnimation on opacity {
                            running: mergedTextEdit.activeFocus
                            loops: Animation.Infinite
                            NumberAnimation { to: 0; duration: 500 }
                            NumberAnimation { to: 1; duration: 500 }
                        }
                }
            }
        }  // End Flickable
        }  // End Row
        
        // Empty state
        Text {
            anchors.centerIn: parent
            visible: textViewer.content === "" && textViewer.source === ""
            color: foregroundColor
            font.pixelSize: 18
            opacity: 0.6
            text: qsTr("No content to display")
        }
    }
    
    // Update text when visibleText changes (from scrolling)
    onVisibleTextChanged: {
        mergedTextEdit.updating = true
        mergedTextEdit.text = visibleText
        mergedTextEdit.updating = false
    }
    
    Shortcut {
        sequences: [StandardKey.Save]
        enabled: textViewer.visible && textViewer.modified
        onActivated: textViewer.save()
    }
}
