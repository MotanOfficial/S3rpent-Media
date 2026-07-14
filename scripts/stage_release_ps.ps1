# Stage a minimal runtime folder for distribution (no build artifacts).
param(
    [string]$BuildDir,
    [string]$StageDir,
    [string]$ProjectDir,
    [string]$AppExeName = "apps3rpent_media.exe",
    [string]$QtRoot = "C:\Qt\6.11.1\msvc2022_64"
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "BuildCommon.ps1")

if (-not $ProjectDir) {
    $ProjectDir = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
}
if (-not $BuildDir) {
    $BuildDir = if ($env:S3_BUILD_DIR) { $env:S3_BUILD_DIR } else { "G:\b\s3_rel_6111" }
}
if (-not $StageDir) {
    $StageDir = Join-Path $ProjectDir "dist\stage"
}

$sourceExe = Join-Path $BuildDir $AppExeName
$windeployqt = Join-Path $QtRoot "bin\windeployqt.exe"

if (-not (Test-Path $sourceExe)) {
    throw "Release binary not found: $sourceExe`nRun a release build first."
}
if (-not (Test-Path $windeployqt)) {
    throw "windeployqt not found: $windeployqt"
}

Write-Host "Staging runtime to: $StageDir" -ForegroundColor Cyan

if (Test-Path $StageDir) {
    Remove-Item $StageDir -Recurse -Force
}
New-Item -ItemType Directory -Path $StageDir | Out-Null

Copy-Item -Path $sourceExe -Destination (Join-Path $StageDir $AppExeName) -Force

# Copy companion executables present in the build directory
foreach ($extraName in @("yt-dlp.exe", "deno.exe")) {
    $extraSource = Join-Path $BuildDir $extraName
    if (Test-Path $extraSource) {
        Copy-Item -Path $extraSource -Destination (Join-Path $StageDir $extraName) -Force
    }
}

$stagedExe = Join-Path $StageDir $AppExeName
& $windeployqt @(
    "--release",
    "--qmldir", $ProjectDir,
    "--compiler-runtime",
    "--no-translations",
    "--no-opengl-sw",
    $stagedExe
)
if ($LASTEXITCODE -ne 0) {
    throw "windeployqt failed with exit code $LASTEXITCODE"
}

function Copy-MsvcRuntime {
    param([string]$Destination)

    $searchRoots = @(
        "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2022\*\VC\Redist\MSVC\*\x64\Microsoft.VC143.CRT",
        "${env:ProgramFiles}\Microsoft Visual Studio\2022\*\VC\Redist\MSVC\*\x64\Microsoft.VC143.CRT"
    )

    $crtDir = $null
    foreach ($pattern in $searchRoots) {
        $match = Get-ChildItem -Path $pattern -ErrorAction SilentlyContinue |
            Sort-Object FullName -Descending |
            Select-Object -First 1
        if ($match) {
            $crtDir = $match.FullName
            break
        }
    }

    if (-not $crtDir) {
        Write-Warning "MSVC CRT folder not found. vc_redist.x64.exe will install runtime during setup."
        return
    }

    foreach ($dll in @(
        "msvcp140.dll",
        "msvcp140_1.dll",
        "msvcp140_2.dll",
        "msvcp140_atomic_wait.dll",
        "vcruntime140.dll",
        "vcruntime140_1.dll",
        "concrt140.dll"
    )) {
        $src = Join-Path $crtDir $dll
        if (Test-Path $src) {
            Copy-Item $src (Join-Path $Destination $dll) -Force
        }
    }

    Write-Host "Copied MSVC runtime DLLs from $crtDir" -ForegroundColor DarkGray
}

Copy-MsvcRuntime -Destination $StageDir

# Copy OpenSSL runtime DLLs if present (for WebRTC P2P)
$openSslBin = Join-Path $BuildDir "libcrypto-3-x64.dll"
if (Test-Path $openSslBin) {
    Copy-Item $openSslBin (Join-Path $StageDir "libcrypto-3-x64.dll") -Force
    Copy-Item (Join-Path $BuildDir "libssl-3-x64.dll") (Join-Path $StageDir "libssl-3-x64.dll") -Force
    Write-Host "Copied OpenSSL runtime DLLs" -ForegroundColor DarkGray
}

# Copy non-Qt third-party DLLs from build directory (vcpkg, FFmpeg, libvlc)
$extraDlls = @(
    "archive.dll",
    "datachannel.dll",
    "juice.dll",
    "avcodec-61.dll",
    "avfilter-10.dll",
    "avformat-61.dll",
    "avutil-59.dll",
    "swresample-5.dll",
    "swscale-8.dll",
    "postproc-58.dll",
    "libvlc.dll",
    "libvlccore.dll"
)
foreach ($dll in $extraDlls) {
    $src = Join-Path $BuildDir $dll
    if (Test-Path $src) {
        Copy-Item $src (Join-Path $StageDir $dll) -Force
    }
}

# Copy libvlc plugins/ directory
$pluginsSrc = Join-Path $BuildDir "plugins"
if (Test-Path $pluginsSrc) {
    Copy-Item $pluginsSrc (Join-Path $StageDir "plugins") -Recurse -Force
    Write-Host "Copied libvlc plugins/ directory" -ForegroundColor DarkGray
}

function Remove-IfExists {
    param([string]$Path)
    if (Test-Path $Path) {
        Remove-Item $Path -Recurse -Force
    }
}

# Drop unused Qt Quick Controls style packs (app uses Basic via QQuickStyle).
$controlsDir = Join-Path $StageDir "qml\QtQuick\Controls"
foreach ($style in @("Fusion", "Material", "Imagine", "Universal", "FluentWinUI3", "Windows")) {
    Remove-IfExists (Join-Path $controlsDir $style)
}

# Drop plugin categories this app does not use.
$pluginsDir = Join-Path $StageDir "plugins"
foreach ($plugin in @(
    "assetimporters", "canbus", "designer", "geoservices", "generic",
    "playlistformats", "position", "qmllint",
    "qmltooling", "sceneparsers", "sensors", "sqldrivers", "texttospeech",
    "virtualkeyboard", "qmlls"
)) {
    Remove-IfExists (Join-Path $pluginsDir $plugin)
}

Remove-IfExists (Join-Path $StageDir "qmltooling")

# Remove root DLLs for QML styles we do not ship (Basic only).
foreach ($dll in @(
    "Qt6QuickControls2Imagine.dll",
    "Qt6QuickControls2ImagineStyleImpl.dll",
    "Qt6QuickControls2Material.dll",
    "Qt6QuickControls2MaterialStyleImpl.dll",
    "Qt6QuickControls2Universal.dll",
    "Qt6QuickControls2UniversalStyleImpl.dll",
    "Qt6QuickControls2Fusion.dll",
    "Qt6QuickControls2FusionStyleImpl.dll",
    "Qt6QuickControls2FluentWinUI3StyleImpl.dll",
    "Qt6QuickControls2WindowsStyleImpl.dll"
)) {
    $path = Join-Path $StageDir $dll
    if (Test-Path $path) { Remove-Item $path -Force }
}

# Remove modules this app does not use at runtime.
foreach ($dll in @(
    "Qt6Pdf.dll",
    "Qt6Lottie.dll",
    "Qt6LottieVectorImageGenerator.dll",
    "Qt6Quick3DUtils.dll",
    "Qt6QuickVectorImageGenerator.dll",
    "Qt6VirtualKeyboard.dll",
    "dxcompiler.dll",
    "dxil.dll"
)) {
    $path = Join-Path $StageDir $dll
    if (Test-Path $path) { Remove-Item $path -Force }
}

Remove-IfExists (Join-Path $StageDir "qml\QtQuick\VirtualKeyboard")
Remove-IfExists (Join-Path $StageDir "qml\QtQuick\Pdf")
Remove-IfExists (Join-Path $StageDir "qml\QtQuick\VectorImage")
Remove-IfExists (Join-Path $StageDir "qml\QtQuick\Timeline")

$iconIco = Join-Path $ProjectDir "resources\icons\icon.ico"
if (Test-Path $iconIco) {
    Copy-Item $iconIco (Join-Path $StageDir "icon.ico") -Force
}

# Remove stray build artifacts if any were copied.
Get-ChildItem -Path $StageDir -Recurse -Include @(
    "*.pdb", "*.lib", "*.exp", "*.ilk", "*.obj", "CMakeCache.txt", "build.ninja", ".ninja_log"
) -File -ErrorAction SilentlyContinue | Remove-Item -Force

$fileCount = (Get-ChildItem -Path $StageDir -Recurse -File).Count
$sizeMb = [math]::Round(((Get-ChildItem -Path $StageDir -Recurse -File | Measure-Object -Property Length -Sum).Sum / 1MB), 1)

Write-Host "Staged $fileCount files ($sizeMb MB)" -ForegroundColor Green
Write-Host $StageDir
