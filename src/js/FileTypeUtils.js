.pragma library

/**
 * FileTypeUtils.js
 * Utility functions for detecting file types based on URL/extension
 */

function normalizedPath(url) {
    if (!url || url === "")
        return ""
    let path = url.toString().toLowerCase()
    const queryIndex = path.indexOf("?")
    if (queryIndex >= 0)
        path = path.substring(0, queryIndex)
    const hashIndex = path.indexOf("#")
    if (hashIndex >= 0)
        path = path.substring(0, hashIndex)
    return path
}

function checkIfVideo(url) {
    const path = normalizedPath(url)
    if (path === "")
        return false
    // GIFs are images, not videos
    return path.endsWith(".mp4") || path.endsWith(".avi") || path.endsWith(".mov") ||
           path.endsWith(".mkv") || path.endsWith(".webm") || path.endsWith(".m4v") ||
           path.endsWith(".flv") || path.endsWith(".wmv") || path.endsWith(".mpg") ||
           path.endsWith(".mpeg") || path.endsWith(".3gp")
}

function checkIfGif(url) {
    const path = normalizedPath(url)
    if (path === "")
        return false
    return path.endsWith(".gif")
}

function checkIfAudio(url) {
    const path = normalizedPath(url)
    if (path === "")
        return false
    return path.endsWith(".mp3") || path.endsWith(".wav") || path.endsWith(".flac") ||
           path.endsWith(".ogg") || path.endsWith(".aac") || path.endsWith(".m4a") ||
           path.endsWith(".wma") || path.endsWith(".opus") || path.endsWith(".mp2") ||
           path.endsWith(".mp1") || path.endsWith(".amr") || path.endsWith(".3gp")
}

function checkIfMarkdown(url) {
    const path = normalizedPath(url)
    if (path === "")
        return false
    return path.endsWith(".md") || path.endsWith(".markdown") || path.endsWith(".mdown") ||
           path.endsWith(".mkd") || path.endsWith(".mkdn")
}

function checkIfText(url) {
    const path = normalizedPath(url)
    if (path === "")
        return false
    // Plain text
    if (path.endsWith(".txt") || path.endsWith(".log") || path.endsWith(".nfo"))
        return true
    // Config files
    if (path.endsWith(".ini") || path.endsWith(".cfg") || path.endsWith(".conf") ||
        path.endsWith(".env") || path.endsWith(".properties"))
        return true
    // Data formats
    if (path.endsWith(".json") || path.endsWith(".xml") || path.endsWith(".yaml") ||
        path.endsWith(".yml") || path.endsWith(".csv") || path.endsWith(".toml"))
        return true
    // Web development
    if (path.endsWith(".html") || path.endsWith(".htm") || path.endsWith(".css") ||
        path.endsWith(".scss") || path.endsWith(".sass") || path.endsWith(".less") ||
        path.endsWith(".js") || path.endsWith(".jsx") || path.endsWith(".ts") ||
        path.endsWith(".tsx") || path.endsWith(".vue") || path.endsWith(".svelte"))
        return true
    // C/C++
    if (path.endsWith(".c") || path.endsWith(".cpp") || path.endsWith(".cc") ||
        path.endsWith(".cxx") || path.endsWith(".h") || path.endsWith(".hpp") ||
        path.endsWith(".hxx") || path.endsWith(".hh"))
        return true
    // Qt/QML
    if (path.endsWith(".qml") || path.endsWith(".qrc") || path.endsWith(".pro") ||
        path.endsWith(".pri") || path.endsWith(".ui"))
        return true
    // Python
    if (path.endsWith(".py") || path.endsWith(".pyw") || path.endsWith(".pyx") ||
        path.endsWith(".pyi") || path.endsWith(".pyd"))
        return true
    // Java/Kotlin
    if (path.endsWith(".java") || path.endsWith(".kt") || path.endsWith(".kts") ||
        path.endsWith(".gradle"))
        return true
    // C#/F#
    if (path.endsWith(".cs") || path.endsWith(".fs") || path.endsWith(".csproj") ||
        path.endsWith(".sln"))
        return true
    // Ruby
    if (path.endsWith(".rb") || path.endsWith(".erb") || path.endsWith(".rake") ||
        path.endsWith(".gemspec"))
        return true
    // Go
    if (path.endsWith(".go") || path.endsWith(".mod") || path.endsWith(".sum"))
        return true
    // Rust
    if (path.endsWith(".rs") || path.endsWith(".toml"))
        return true
    // PHP
    if (path.endsWith(".php") || path.endsWith(".phtml"))
        return true
    // Shell/Scripts
    if (path.endsWith(".sh") || path.endsWith(".bash") || path.endsWith(".zsh") ||
        path.endsWith(".fish") || path.endsWith(".bat") || path.endsWith(".cmd") ||
        path.endsWith(".ps1") || path.endsWith(".psm1"))
        return true
    // SQL
    if (path.endsWith(".sql") || path.endsWith(".sqlite"))
        return true
    // Swift/Objective-C
    if (path.endsWith(".swift") || path.endsWith(".m") || path.endsWith(".mm"))
        return true
    // Lua
    if (path.endsWith(".lua"))
        return true
    // Perl
    if (path.endsWith(".pl") || path.endsWith(".pm"))
        return true
    // R
    if (path.endsWith(".r") || path.endsWith(".rmd"))
        return true
    // Scala
    if (path.endsWith(".scala") || path.endsWith(".sc"))
        return true
    // Dart
    if (path.endsWith(".dart"))
        return true
    // Assembly
    if (path.endsWith(".asm") || path.endsWith(".s"))
        return true
    // Makefiles and build
    if (path.endsWith(".mk") || path.endsWith(".cmake") || path.endsWith(".ninja") ||
        path.endsWith("makefile") || path.endsWith("cmakelists.txt"))
        return true
    // Docker
    if (path.endsWith(".dockerfile") || path.endsWith("dockerfile") ||
        path.endsWith(".dockerignore"))
        return true
    // Git
    if (path.endsWith(".gitignore") || path.endsWith(".gitattributes") ||
        path.endsWith(".gitmodules"))
        return true
    // Other
    if (path.endsWith(".diff") || path.endsWith(".patch") || path.endsWith(".rst") ||
        path.endsWith(".tex") || path.endsWith(".bib") || path.endsWith(".cls") ||
        path.endsWith(".sty"))
        return true
    return false
}

function checkIfPdf(url) {
    const path = normalizedPath(url)
    if (path === "")
        return false
    return path.endsWith(".pdf")
}

function checkIfZip(url) {
    const path = normalizedPath(url)
    if (path === "")
        return false
    return path.endsWith(".zip")
}

function checkIfModel(url) {
    const path = normalizedPath(url)
    if (path === "")
        return false
    return path.endsWith(".obj") || path.endsWith(".fbx") || path.endsWith(".glb") ||
           path.endsWith(".mtl") || path.endsWith(".blend")
}

