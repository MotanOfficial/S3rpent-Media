import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ApplicationWindow {
    id: debugWindow
    width: 600
    height: 400
    title: "Debug Console - s3rpent media"
    visible: true
    flags: Qt.Window | Qt.WindowTitleHint | Qt.WindowMinimizeButtonHint | Qt.WindowMaximizeButtonHint | Qt.WindowCloseButtonHint
    
    // Prevent this window from closing when main window closes
    // This window should stay open independently
    onClosing: function(close) {
        // Allow normal close - user can close it manually if needed
        // But it won't auto-close when main window closes
    }
    
    property var mainWindow: null
    
    // Log storage - use ListModel for proper QML binding
    ListModel {
        id: logEntriesModel
    }
    property int maxLogEntries: 1000
    
    // Memory tracking
    property real memoryUsageMB: 0.0
    property real previousMemoryMB: 0.0
    
    function addLog(message, type) {
        const timestamp = new Date().toLocaleTimeString()
        const entryType = type || "info"
        
        // Add to ListModel
        logEntriesModel.append({
            time: timestamp,
            message: message,
            type: entryType
        })
        
        // Keep only last maxLogEntries
        while (logEntriesModel.count > maxLogEntries) {
            logEntriesModel.remove(0)
        }
        
        // Update scroll position
        Qt.callLater(function() {
            logListView.positionViewAtEnd()
        })
    }
    
    function updateMemoryUsage() {
        if (typeof ColorUtils !== "undefined" && ColorUtils.getMemoryUsage) {
            memoryUsageMB = ColorUtils.getMemoryUsage()
        } else {
            // Fallback: try to get from process
            memoryUsageMB = 0.0
        }
    }
    
    function copyLogsToClipboard() {
        let logText = "=== Debug Console Logs ===\n"
        logText += "RAM Usage: " + memoryUsageMB.toFixed(2) + " MB\n"
        logText += "Total Entries: " + logEntriesModel.count + "\n\n"
        
        for (let i = 0; i < logEntriesModel.count; i++) {
            const entry = logEntriesModel.get(i)
            const typeLabel = entry.type === "error" ? "[ERROR]" : (entry.type === "warning" ? "[WARN]" : "[INFO]")
            logText += "[" + entry.time + "] " + typeLabel + " " + entry.message + "\n"
        }
        
        // Copy to clipboard using ColorUtils if available, otherwise try Qt.application.clipboard
        try {
            if (typeof ColorUtils !== "undefined" && ColorUtils.copyToClipboard) {
                ColorUtils.copyToClipboard(logText)
                addLog("Logs copied to clipboard (" + logEntriesModel.count + " entries)", "info")
            } else if (typeof Qt !== "undefined" && Qt.application && Qt.application.clipboard) {
                Qt.application.clipboard.text = logText
                addLog("Logs copied to clipboard (" + logEntriesModel.count + " entries)", "info")
            } else {
                addLog("ERROR: Clipboard not available - please add copyToClipboard to ColorUtils", "error")
            }
        } catch (e) {
            addLog("ERROR: Failed to copy to clipboard: " + e, "error")
        }
    }
    
    Timer {
        id: memoryUpdateTimer
        interval: 500  // Update every 500ms
        running: true
        repeat: true
        onTriggered: {
            previousMemoryMB = memoryUsageMB
            updateMemoryUsage()
        }
    }
    
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 8
        spacing: 8
        
        // Header with memory info
        RowLayout {
            Layout.fillWidth: true
            spacing: 16
            
            Text {
                text: "RAM Usage: " + memoryUsageMB.toFixed(2) + " MB"
                font.bold: true
                color: memoryUsageMB > previousMemoryMB ? "#ff6b6b" : (memoryUsageMB < previousMemoryMB ? "#51cf66" : "#ffffff")
            }
            
            Text {
                text: "Delta: " + (memoryUsageMB - previousMemoryMB >= 0 ? "+" : "") + (memoryUsageMB - previousMemoryMB).toFixed(2) + " MB"
                color: memoryUsageMB > previousMemoryMB ? "#ff6b6b" : (memoryUsageMB < previousMemoryMB ? "#51cf66" : "#ffffff")
            }
            
            Item { Layout.fillWidth: true }
            
            Button {
                text: "Copy Logs"
                onClicked: {
                    copyLogsToClipboard()
                }
            }
            
            Button {
                text: "Clear Logs"
                onClicked: {
                    logEntriesModel.clear()
                }
            }
        }
        
        // Log list
        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            
            ListView {
                id: logListView
                model: logEntriesModel
                delegate: Rectangle {
                    width: logListView.width
                    height: logText.height + 8
                    color: {
                        if (type === "error") return "#2d1b1b"
                        if (type === "warning") return "#2d2b1b"
                        return "#1b1b1b"
                    }
                    
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        spacing: 8
                        
                        Text {
                            text: "[" + time + "]"
                            color: "#888888"
                            font.pixelSize: 11
                        }
                        
                        Text {
                            id: logText
                            text: message
                            color: {
                                if (type === "error") return "#ff6b6b"
                                if (type === "warning") return "#ffd93d"
                                return "#ffffff"
                            }
                            font.pixelSize: 11
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                        }
                    }
                }
            }
        }
    }
    
    Component.onCompleted: {
        updateMemoryUsage()
        addLog("Debug console initialized", "info")
        
        // Notify main window that we're ready
        if (mainWindow && typeof mainWindow.logToDebugConsole === "function") {
            mainWindow.logToDebugConsole("[Debug] Console ready and connected", "info")
        }
    }
}

