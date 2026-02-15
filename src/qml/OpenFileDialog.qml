import QtQuick
import QtQuick.Dialogs

// OpenFileDialog component - encapsulates the file selection dialog with all supported file filters
FileDialog {
    id: openFileDialog
    
    title: qsTr("Select media")
    fileMode: FileDialog.OpenFile
    
    nameFilters: [
        qsTr("All Supported (*.png *.jpg *.jpeg *.bmp *.gif *.webp *.mp4 *.avi *.mov *.mkv *.webm *.m4v *.mp3 *.wav *.flac *.ogg *.aac *.m4a *.wma *.opus *.md *.markdown *.txt *.log *.json *.xml *.yaml *.yml *.csv *.html *.css *.js *.ts *.cpp *.c *.h *.hpp *.py *.java *.qml *.rs *.go *.rb *.php *.sh *.sql *.pdf *.zip *.obj *.fbx *.glb *.mtl *.blend)"),
        qsTr("Images (*.png *.jpg *.jpeg *.bmp *.gif *.webp)"),
        qsTr("Videos (*.mp4 *.avi *.mov *.mkv *.webm *.m4v *.flv *.wmv *.mpg *.mpeg *.3gp)"),
        qsTr("Audio (*.mp3 *.wav *.flac *.ogg *.aac *.m4a *.wma *.opus *.mp2 *.mp1 *.amr)"),
        qsTr("PDF Documents (*.pdf)"),
        qsTr("Archives (*.zip)"),
        qsTr("3D Models (*.obj *.fbx *.glb *.mtl *.blend)"),
        qsTr("Markdown (*.md *.markdown *.mdown *.mkd *.mkdn)"),
        qsTr("Code - Web (*.html *.htm *.css *.scss *.sass *.less *.js *.jsx *.ts *.tsx *.vue *.svelte *.json)"),
        qsTr("Code - C/C++/Qt (*.c *.cpp *.cc *.cxx *.h *.hpp *.hxx *.qml *.qrc *.pro *.pri *.ui)"),
        qsTr("Code - Python (*.py *.pyw *.pyx *.pyi)"),
        qsTr("Code - Java/Kotlin (*.java *.kt *.kts *.gradle)"),
        qsTr("Code - Other (*.rs *.go *.rb *.php *.swift *.cs *.fs *.scala *.lua *.pl *.r *.dart *.sh *.bat *.ps1 *.sql)"),
        qsTr("Config (*.ini *.cfg *.conf *.env *.yaml *.yml *.toml *.xml *.properties)"),
        qsTr("Text (*.txt *.log *.nfo *.csv *.diff *.patch)"),
        qsTr("All files (*)")
    ]
    
    // Signal emitted when a file is selected
    signal fileSelected(url fileUrl)
    
    onAccepted: {
        fileSelected(selectedFile)
    }
}

