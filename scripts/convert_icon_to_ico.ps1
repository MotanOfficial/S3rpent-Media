# Build multi-size icon.ico from resources/icons/icon.png
$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectDir = (Resolve-Path (Join-Path $scriptDir "..")).Path
$pngPath = Join-Path $projectDir "resources\icons\icon.png"
$icoPath = Join-Path $projectDir "resources\icons\icon.ico"
$installerIco = Join-Path $projectDir "installer\config\icon.ico"
$installerLogo = Join-Path $projectDir "installer\config\logo.png"

if (-not (Test-Path $pngPath)) {
    throw "Missing $pngPath"
}

if (Get-Command magick -ErrorAction SilentlyContinue) {
    & magick $pngPath -define icon:auto-resize=256,128,64,48,32,24,16 $icoPath
    & magick $pngPath -resize 64x64 $installerLogo
} else {
    python -c @"
from PIL import Image
from pathlib import Path
src = Image.open(Path(r'$pngPath')).convert('RGBA')
src.save(
    Path(r'$icoPath'),
    format='ICO',
    sizes=[(256, 256), (128, 128), (64, 64), (48, 48), (32, 32), (24, 24), (16, 16)],
)
Image.open(Path(r'$pngPath')).convert('RGBA').resize((64, 64), Image.Resampling.LANCZOS).save(
    Path(r'$installerLogo')
)
"@
}

Copy-Item $icoPath $installerIco -Force
$sizeKb = [math]::Round((Get-Item $icoPath).Length / 1KB, 1)
if ($sizeKb -lt 10) {
    throw "icon.ico looks too small ($sizeKb KB) - multi-size ICO generation failed."
}
Write-Host "Created $icoPath ($sizeKb KB)"
Write-Host "Installer logo: $installerLogo (64x64)"
