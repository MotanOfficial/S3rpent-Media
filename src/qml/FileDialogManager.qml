import QtQuick
import QtQuick.Dialogs

// FileDialogManager - Manages the file selection dialog and its handlers
Item {
    id: fileDialogManager
    
    required property Window mainWindow
    required property var logToDebugConsole
    
    // File selection dialog
    OpenFileDialog {
        id: openDialog
        onFileSelected: function(fileUrl) {
            fileDialogManager.logToDebugConsole("[QML] FileDialog accepted, setting currentImage: " + fileUrl.toString(), "info")
            // Ensure window is visible when loading file
            if (!fileDialogManager.mainWindow.visible) {
                fileDialogManager.mainWindow.show()
                fileDialogManager.mainWindow.raise()
            }
            fileDialogManager.mainWindow.currentImage = fileUrl
        }
    }
    
    // Expose the dialog for external access
    property alias dialog: openDialog
}

