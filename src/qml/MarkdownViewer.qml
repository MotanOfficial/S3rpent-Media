import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: markdownViewer
    
    property url source: ""
    property color accentColor: "#121216"
    property color foregroundColor: "#f5f5f5"
    property string content: ""
    property string renderedContent: ""
    property var contentSegments: []
    
    function parseMarkdown(markdown) {
        if (!markdown) return []
        
        const segments = []
        const codeBlockRegex = /```(\w+)?\n?([\s\S]*?)```/g
        let lastIndex = 0
        let match
        
        // Find all code blocks
        const codeBlocks = []
        while ((match = codeBlockRegex.exec(markdown)) !== null) {
            codeBlocks.push({
                start: match.index,
                end: match.index + match[0].length,
                lang: match[1] || "",
                code: match[2].trim()
            })
        }
        
        // Split content into text and code segments
        let currentIndex = 0
        for (let i = 0; i < codeBlocks.length; i++) {
            const block = codeBlocks[i]
            
            // Add text before code block
            if (block.start > currentIndex) {
                const text = markdown.substring(currentIndex, block.start)
                if (text.trim()) {
                    segments.push({ type: "text", content: text })
                }
            }
            
            // Add code block
            segments.push({ type: "code", content: block.code, lang: block.lang })
            
            currentIndex = block.end
        }
        
        // Add remaining text
        if (currentIndex < markdown.length) {
            const text = markdown.substring(currentIndex)
            if (text.trim()) {
                segments.push({ type: "text", content: text })
            }
        }
        
        // If no code blocks found, return single text segment
        if (codeBlocks.length === 0) {
            segments.push({ type: "text", content: markdown })
        }
        
        return segments
    }
    
    function markdownToHtml(markdown) {
        if (!markdown) return ""
        
        let html = markdown
        
        // Escape HTML entities first (but preserve existing HTML)
        // Only escape if not already in HTML tags
        html = html.replace(/&(?![a-zA-Z]+;)/g, "&amp;")
        
        // Code blocks (triple backticks) - process first to avoid processing content
        html = html.replace(/```(\w+)?\n?([\s\S]*?)```/g, function(match, lang, code) {
            const escaped = code.trim()
                .replace(/&/g, "&amp;")
                .replace(/</g, "&lt;")
                .replace(/>/g, "&gt;")
            return "<pre><code>" + escaped + "</code></pre>"
        })
        
        // Inline code (single backticks) - process before other formatting
        html = html.replace(/`([^`\n]+)`/g, function(match, code) {
            const escaped = code
                .replace(/&/g, "&amp;")
                .replace(/</g, "&lt;")
                .replace(/>/g, "&gt;")
            return "<code>" + escaped + "</code>"
        })
        
        // Headers (must be on their own line)
        html = html.replace(/^### (.*)$/gim, "<h3>$1</h3>")
        html = html.replace(/^## (.*)$/gim, "<h2>$1</h2>")
        html = html.replace(/^# (.*)$/gim, "<h1>$1</h1>")
        
        // Bold (must come before italic to avoid conflicts)
        html = html.replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>")
        html = html.replace(/__([^_]+)__/g, "<strong>$1</strong>")
        
        // Italic (avoid matching bold)
        html = html.replace(/(?<!\*)\*([^*]+)\*(?!\*)/g, "<em>$1</em>")
        html = html.replace(/(?<!_)_([^_]+)_(?!_)/g, "<em>$1</em>")
        
        // Links [text](url)
        html = html.replace(/\[([^\]]+)\]\(([^)]+)\)/g, '<a href="$2">$1</a>')
        
        // Horizontal rules
        html = html.replace(/^---$/gim, "<hr />")
        html = html.replace(/^\*\*\*$/gim, "<hr />")
        
        // Blockquotes
        html = html.replace(/^> (.+)$/gim, "<blockquote>$1</blockquote>")
        
        // Lists - process line by line
        const lines = html.split('\n')
        let inList = false
        let result = []
        
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i]
            const listMatch = line.match(/^[\*\-\+] (.+)$/) || line.match(/^\d+\. (.+)$/)
            
            if (listMatch) {
                if (!inList) {
                    result.push("<ul>")
                    inList = true
                }
                result.push("<li>" + listMatch[1] + "</li>")
            } else {
                if (inList) {
                    result.push("</ul>")
                    inList = false
                }
                if (line.trim() !== "") {
                    result.push(line)
                }
            }
        }
        if (inList) {
            result.push("</ul>")
        }
        
        html = result.join('\n')
        
        // Convert double newlines to paragraph breaks
        html = html.split(/\n\n+/).map(function(para) {
            para = para.trim()
            if (!para) return ""
            // Don't wrap if already a block element
            if (para.match(/^<(h[1-6]|ul|ol|pre|blockquote|hr)/)) {
                return para
            }
            return "<p>" + para + "</p>"
        }).join('\n')
        
        // Convert single newlines to <br>
        html = html.replace(/\n/g, "<br />")
        
        return html
    }
    
    function loadContent() {
        if (source === "" || typeof ColorUtils === "undefined" || !ColorUtils.readTextFile) {
            content = ""
            renderedContent = ""
            return
        }
        
        const fileContent = ColorUtils.readTextFile(source)
        if (fileContent) {
            content = fileContent
            contentSegments = parseMarkdown(fileContent)
            renderedContent = markdownToHtml(fileContent)
        } else {
            content = ""
            contentSegments = []
            renderedContent = ""
        }
    }
    
    onSourceChanged: {
        loadContent()
    }
    
    Component.onCompleted: {
        loadContent()
    }
    
    Rectangle {
        anchors.fill: parent
        color: Qt.darker(accentColor, 1.15)
        
        ScrollView {
            id: scrollView
            anchors.fill: parent
            anchors.margins: 24
            clip: true
            
            ScrollBar.vertical.policy: ScrollBar.AsNeeded
            ScrollBar.horizontal.policy: ScrollBar.AsNeeded
            
            Column {
                id: contentColumn
                width: scrollView.width - (scrollView.ScrollBar.vertical.visible ? scrollView.ScrollBar.vertical.width : 0)
                spacing: 12
                
                Repeater {
                    model: markdownViewer.contentSegments
                    
                    delegate: Loader {
                        width: contentColumn.width
                        sourceComponent: modelData.type === "code" ? codeBlockComponent : textBlockComponent
                        
                        property var segmentData: modelData
                    }
                }
            }
        }
        
        Component {
            id: textBlockComponent
            
            Text {
                id: textBlock
                width: contentColumn.width
                text: {
                    const loader = textBlock.parent
                    if (loader && loader.segmentData) {
                        return markdownToHtml(loader.segmentData.content)
                    }
                    return ""
                }
                color: foregroundColor
                font.pixelSize: 15
                font.family: "-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif"
                wrapMode: Text.Wrap
                textFormat: Text.RichText
                linkColor: foregroundColor
                onLinkActivated: function(link) {
                    Qt.openUrlExternally(link)
                }
            }
        }
        
        Component {
            id: codeBlockComponent
            
            Rectangle {
                id: codeBlockRect
                width: contentColumn.width
                height: Math.max(codeText.implicitHeight + 16, 60)
                color: Qt.rgba(128, 128, 128, 0.15)
                border.color: Qt.rgba(128, 128, 128, 0.3)
                border.width: 1
                radius: 6
                
                ScrollView {
                    id: codeScrollView
                    anchors.fill: parent
                    anchors.margins: 8
                    clip: true
                    ScrollBar.horizontal.policy: ScrollBar.AsNeeded
                    ScrollBar.vertical.policy: ScrollBar.AsNeeded
                    
                    TextEdit {
                        id: codeText
                        width: Math.max(codeScrollView.width - (codeScrollView.ScrollBar.vertical.visible ? codeScrollView.ScrollBar.vertical.width : 0), implicitWidth)
                        text: {
                            const loader = codeBlockRect.parent
                            if (loader && loader.segmentData) {
                                const code = loader.segmentData.content
                                return code
                                    .replace(/&/g, "&amp;")
                                    .replace(/</g, "&lt;")
                                    .replace(/>/g, "&gt;")
                            }
                            return ""
                        }
                        color: foregroundColor
                        font.pixelSize: 13
                        font.family: "Consolas, 'Courier New', monospace"
                        wrapMode: TextEdit.NoWrap
                        readOnly: true
                        selectByMouse: true
                    }
                }
            }
        }
        
        // Empty state
        Text {
            anchors.centerIn: parent
            visible: markdownViewer.content === ""
            color: foregroundColor
            font.pixelSize: 18
            opacity: 0.6
            text: qsTr("No content to display")
        }
    }
}

