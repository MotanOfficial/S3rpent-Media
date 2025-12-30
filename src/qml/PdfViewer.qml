import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: pdfViewer
    
    property url source: ""
    property color accentColor: "#121216"
    property color foregroundColor: "#f5f5f5"
    property int pageCount: pdfLoader.item ? pdfLoader.item.pageCount : 0
    property int currentPage: pdfLoader.item ? pdfLoader.item.currentPage : 1
    property real zoomLevel: pdfLoader.item ? pdfLoader.item.zoomLevel : 1.0
    property bool isLoaded: pdfLoader.item ? pdfLoader.item.isLoaded : false
    property bool pdfSupported: pdfLoader.status === Loader.Ready
    
    signal loaded()
    signal loadError(string message)
    
    Loader {
        id: pdfLoader
        anchors.fill: parent
        asynchronous: true
        source: "PdfViewerImpl.qml"
        
        onStatusChanged: {
            if (status === Loader.Ready && item) {
                item.source = Qt.binding(function() { return pdfViewer.source })
                item.accentColor = Qt.binding(function() { return pdfViewer.accentColor })
                item.foregroundColor = Qt.binding(function() { return pdfViewer.foregroundColor })
                item.loaded.connect(pdfViewer.loaded)
                item.loadError.connect(pdfViewer.loadError)
            } else if (status === Loader.Error) {
                console.log("[PDF] PDF module not available - PdfViewerImpl.qml not found")
            }
        }
    }
    
    // Fallback when PDF not supported
    Rectangle {
        anchors.fill: parent
        color: Qt.darker(pdfViewer.accentColor, 1.3)
        visible: pdfLoader.status === Loader.Error || (pdfLoader.status === Loader.Null && !pdfLoader.source)
        
        Column {
            anchors.centerIn: parent
            spacing: 20
            
            Text {
                text: "📄"
                font.pixelSize: 64
                anchors.horizontalCenter: parent.horizontalCenter
            }
            
            Text {
                text: "PDF Support Not Available"
                color: pdfViewer.foregroundColor
                font.pixelSize: 24
                font.bold: true
                anchors.horizontalCenter: parent.horizontalCenter
            }
            
            Rectangle {
                width: 400
                height: infoText.implicitHeight + 32
                color: Qt.rgba(0, 0, 0, 0.3)
                radius: 8
                anchors.horizontalCenter: parent.horizontalCenter
                
                Text {
                    id: infoText
                    anchors.centerIn: parent
                    width: parent.width - 32
                    text: "The Qt PDF module is not installed for your compiler.\n\n" +
                          "To enable PDF support, you need to:\n" +
                          "• Use Qt with MSVC compiler instead of MinGW, or\n" +
                          "• Install Qt PDF module via Qt Maintenance Tool\n\n" +
                          "Note: Qt PDF is not available for MinGW on Windows."
                    color: Qt.rgba(pdfViewer.foregroundColor.r, pdfViewer.foregroundColor.g, 
                                  pdfViewer.foregroundColor.b, 0.8)
                    font.pixelSize: 13
                    horizontalAlignment: Text.AlignLeft
                    wrapMode: Text.WordWrap
                    lineHeight: 1.4
                }
            }
        }
    }
    
    // Loading indicator
    Rectangle {
        anchors.fill: parent
        color: Qt.darker(pdfViewer.accentColor, 1.3)
        visible: pdfLoader.status === Loader.Loading
        
        Column {
            anchors.centerIn: parent
            spacing: 10
            
            BusyIndicator {
                anchors.horizontalCenter: parent.horizontalCenter
                running: true
                palette.dark: pdfViewer.foregroundColor
            }
            
            Text {
                text: "Loading PDF viewer..."
                color: pdfViewer.foregroundColor
                font.pixelSize: 14
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }
}
