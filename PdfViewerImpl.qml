import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Pdf

Item {
    id: pdfViewerImpl
    
    property url source: ""
    property color accentColor: "#121216"
    property color foregroundColor: "#f5f5f5"
    property int pageCount: pdfDocument.pageCount
    property int currentPage: pdfView.currentPage + 1  // 1-indexed for display
    property real zoomLevel: 1.0
    property bool isLoaded: pdfDocument.status === PdfDocument.Ready
    
    signal loaded()
    signal loadError(string message)
    
    // Custom button component to avoid native style warnings
    component PdfButton: Rectangle {
        id: btn
        property string label: ""
        property bool btnEnabled: true
        signal clicked()
        
        implicitWidth: 32
        implicitHeight: 28
        radius: 4
        color: !btnEnabled ? Qt.darker(pdfViewerImpl.accentColor, 1.1) :
               mouseArea.pressed ? Qt.lighter(pdfViewerImpl.accentColor, 1.3) :
               mouseArea.containsMouse ? Qt.lighter(pdfViewerImpl.accentColor, 1.2) :
               Qt.lighter(pdfViewerImpl.accentColor, 1.1)
        opacity: btnEnabled ? 1.0 : 0.5
        
        Text {
            anchors.centerIn: parent
            text: btn.label
            color: pdfViewerImpl.foregroundColor
            font.pixelSize: 14
        }
        
        MouseArea {
            id: mouseArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: btn.btnEnabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: if (btn.btnEnabled) btn.clicked()
        }
    }
    
    PdfDocument {
        id: pdfDocument
        source: pdfViewerImpl.source
        
        onStatusChanged: function() {
            if (pdfDocument.status === PdfDocument.Ready) {
                console.log("[PDF] Loaded:", pdfDocument.pageCount, "pages")
                pdfViewerImpl.loaded()
            } else if (pdfDocument.status === PdfDocument.Error) {
                console.log("[PDF] Error loading document")
                pdfViewerImpl.loadError("Failed to load PDF document")
            }
        }
    }
    
    // Toolbar
    Rectangle {
        id: toolbar
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 44
        color: Qt.rgba(pdfViewerImpl.accentColor.r * 0.8, 
                       pdfViewerImpl.accentColor.g * 0.8, 
                       pdfViewerImpl.accentColor.b * 0.8, 0.95)
        z: 1
        
        RowLayout {
            anchors.fill: parent
            anchors.margins: 8
            spacing: 12
            
            // Page navigation
            RowLayout {
                spacing: 6
                
                PdfButton {
                    label: "◀"
                    btnEnabled: pdfView.currentPage > 0
                    onClicked: pdfView.goToPage(pdfView.currentPage - 1)
                }
                
                Text {
                    text: pdfViewerImpl.isLoaded ? 
                          (pdfViewerImpl.currentPage + " / " + pdfViewerImpl.pageCount) : 
                          "Loading..."
                    color: pdfViewerImpl.foregroundColor
                    font.pixelSize: 13
                    font.family: "Consolas"
                }
                
                PdfButton {
                    label: "▶"
                    btnEnabled: pdfView.currentPage < pdfDocument.pageCount - 1
                    onClicked: pdfView.goToPage(pdfView.currentPage + 1)
                }
            }
            
            // Separator
            Rectangle {
                width: 1
                height: 24
                color: Qt.rgba(pdfViewerImpl.foregroundColor.r, pdfViewerImpl.foregroundColor.g, 
                              pdfViewerImpl.foregroundColor.b, 0.3)
            }
            
            // Zoom controls
            RowLayout {
                spacing: 6
                
                PdfButton {
                    label: "−"
                    onClicked: pdfViewerImpl.zoomLevel = Math.max(0.25, pdfViewerImpl.zoomLevel - 0.25)
                    
                    Text {
                        anchors.centerIn: parent
                        text: "−"
                        color: pdfViewerImpl.foregroundColor
                        font.pixelSize: 18
                        font.bold: true
                    }
                }
                
                Text {
                    text: Math.round(pdfViewerImpl.zoomLevel * 100) + "%"
                    color: pdfViewerImpl.foregroundColor
                    font.pixelSize: 13
                    font.family: "Consolas"
                    Layout.minimumWidth: 50
                    horizontalAlignment: Text.AlignHCenter
                }
                
                PdfButton {
                    label: "+"
                    onClicked: pdfViewerImpl.zoomLevel = Math.min(4.0, pdfViewerImpl.zoomLevel + 0.25)
                    
                    Text {
                        anchors.centerIn: parent
                        text: "+"
                        color: pdfViewerImpl.foregroundColor
                        font.pixelSize: 18
                        font.bold: true
                    }
                }
                
                PdfButton {
                    implicitWidth: 40
                    label: "Fit"
                    onClicked: pdfViewerImpl.zoomLevel = 1.0
                    
                    Text {
                        anchors.centerIn: parent
                        text: "Fit"
                        color: pdfViewerImpl.foregroundColor
                        font.pixelSize: 12
                    }
                }
            }
            
            Item { Layout.fillWidth: true }
        }
    }
    
    // PDF content
    Rectangle {
        id: contentArea
        anchors.top: toolbar.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        color: Qt.darker(pdfViewerImpl.accentColor, 1.3)
        
        PdfMultiPageView {
            id: pdfView
            anchors.fill: parent
            anchors.margins: 8
            document: pdfDocument
            
            // Apply zoom
            renderScale: pdfViewerImpl.zoomLevel
        }
        
        // Loading indicator
        Rectangle {
            anchors.centerIn: parent
            width: 200
            height: 80
            color: Qt.rgba(0, 0, 0, 0.7)
            radius: 8
            visible: pdfDocument.status === PdfDocument.Loading
            
            Column {
                anchors.centerIn: parent
                spacing: 10
                
                BusyIndicator {
                    anchors.horizontalCenter: parent.horizontalCenter
                    running: true
                    palette.dark: pdfViewerImpl.foregroundColor
                }
                
                Text {
                    text: "Loading PDF..."
                    color: pdfViewerImpl.foregroundColor
                    font.pixelSize: 14
                }
            }
        }
        
        // Error indicator
        Rectangle {
            anchors.centerIn: parent
            width: 300
            height: 100
            color: Qt.rgba(0.3, 0, 0, 0.8)
            radius: 8
            visible: pdfDocument.status === PdfDocument.Error
            
            Column {
                anchors.centerIn: parent
                spacing: 10
                
                Text {
                    text: "⚠️"
                    font.pixelSize: 32
                    anchors.horizontalCenter: parent.horizontalCenter
                }
                
                Text {
                    text: "Failed to load PDF"
                    color: "#ff6b6b"
                    font.pixelSize: 14
                    font.bold: true
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }
        }
    }
    
    // Keyboard shortcuts
    Shortcut {
        sequences: [StandardKey.ZoomIn]
        onActivated: pdfViewerImpl.zoomLevel = Math.min(4.0, pdfViewerImpl.zoomLevel + 0.25)
    }
    
    Shortcut {
        sequences: [StandardKey.ZoomOut]
        onActivated: pdfViewerImpl.zoomLevel = Math.max(0.25, pdfViewerImpl.zoomLevel - 0.25)
    }
    
    Shortcut {
        sequence: "Home"
        onActivated: pdfView.goToPage(0)
    }
    
    Shortcut {
        sequence: "End"
        onActivated: pdfView.goToPage(pdfDocument.pageCount - 1)
    }
    
    Shortcut {
        sequence: "PgUp"
        onActivated: if (pdfView.currentPage > 0) pdfView.goToPage(pdfView.currentPage - 1)
    }
    
    Shortcut {
        sequence: "PgDown"
        onActivated: if (pdfView.currentPage < pdfDocument.pageCount - 1) pdfView.goToPage(pdfView.currentPage + 1)
    }
}
