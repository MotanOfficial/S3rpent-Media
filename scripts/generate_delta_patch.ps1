# Generate delta patch manifest + files between two staged releases.
param(
    [string]$FromStage,
    [string]$ToStage,
    [string]$FromVersion,
    [string]$ToVersion,
    [string]$ReleaseNotes = "",
    [string]$OutputDir
)

$ErrorActionPreference = "Stop"

$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
$PROJECT_DIR = (Resolve-Path (Join-Path $SCRIPT_DIR "..")).Path

. (Join-Path $SCRIPT_DIR "BuildCommon.ps1")

$fromVersionNorm = Normalize-Version $FromVersion
$toVersionNorm = Normalize-Version $ToVersion

if (-not $FromStage) { $FromStage = Join-Path $PROJECT_DIR "dist\stage-$fromVersionNorm" }
if (-not $ToStage) { $ToStage = Join-Path $PROJECT_DIR "dist\stage" }
if (-not $OutputDir) { $OutputDir = Join-Path $PROJECT_DIR "dist\patches\$fromVersionNorm-$toVersionNorm" }

if (-not (Test-Path $FromStage)) { throw "From stage not found: $FromStage" }
if (-not (Test-Path $ToStage)) { throw "To stage not found: $ToStage" }

Write-Host "Generating delta patch $fromVersionNorm -> $toVersionNorm" -ForegroundColor Cyan

if (Test-Path $OutputDir) { Remove-Item $OutputDir -Recurse -Force }
New-Item -ItemType Directory -Path (Join-Path $OutputDir "files") | Out-Null

function Get-RelativePaths {
    param([string]$RootDir)
    Get-ChildItem $RootDir -Recurse -File | ForEach-Object {
        $_.FullName.Substring($RootDir.Length).TrimStart('\').Replace('\', '/')
    } | Sort-Object
}

$fromFiles = @{}
foreach ($path in (Get-RelativePaths $FromStage)) {
    $fullPath = Join-Path $FromStage ($path -replace '/', '\')
    $fromFiles[$path] = @{
        Path = $path
        Size = (Get-Item $fullPath).Length
        Hash = (Get-FileHash $fullPath -Algorithm SHA256).Hash
    }
}

$toFiles = @{}
foreach ($path in (Get-RelativePaths $ToStage)) {
    $fullPath = Join-Path $ToStage ($path -replace '/', '\')
    $toFiles[$path] = @{
        Path = $path
        Size = (Get-Item $fullPath).Length
        Hash = (Get-FileHash $fullPath -Algorithm SHA256).Hash
        Modified = $true
    }
}

$changedFiles = @()
$addedFiles = @()
$removedFiles = @()
$unchangedFiles = @()

foreach ($path in $toFiles.Keys) {
    if ($fromFiles.ContainsKey($path)) {
        if ($toFiles[$path].Hash -ne $fromFiles[$path].Hash) {
            $changedFiles += $path
        } else {
            $unchangedFiles += $path
        }
    } else {
        $addedFiles += $path
    }
}

foreach ($path in $fromFiles.Keys) {
    if (-not $toFiles.ContainsKey($path)) {
        $removedFiles += $path
    }
}

$patchFileEntries = @()

foreach ($path in $addedFiles + $changedFiles) {
    $srcPath = Join-Path $ToStage ($path -replace '/', '\')
    $destPath = Join-Path $OutputDir "files" ($path -replace '/', '\')
    $destDir = Split-Path $destPath -Parent
    if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir | Out-Null }
    Copy-Item $srcPath $destPath -Force

    $fileInfo = $toFiles[$path]
    $patchFileEntries += [ordered]@{
        path = $path
        size = $fileInfo.Size
        sha256 = $fileInfo.Hash.ToLower()
        storage_path = "patches/$fromVersionNorm-$toVersionNorm/files/$path"
    }
}

$manifest = [ordered]@{
    from_version = $fromVersionNorm
    to_version = $toVersionNorm
    release_notes = if ($ReleaseNotes) { $ReleaseNotes } else { "Update to $toVersionNorm" }
    files = $patchFileEntries
    added = $addedFiles.Count
    changed = $changedFiles.Count
    removed = $removedFiles.Count
    unchanged = $unchangedFiles.Count
}

$manifestPath = Join-Path $OutputDir "manifest.json"
$manifest | ConvertTo-Json -Depth 10 | Set-Content $manifestPath -Encoding UTF8

$patchSize = (Get-ChildItem $OutputDir -Recurse -File | Measure-Object -Property Length -Sum).Sum

Write-Host "Delta patch generated:" -ForegroundColor Green
Write-Host "  $fromVersionNorm -> $toVersionNorm"
Write-Host "  Total files: $($patchFileEntries.Count) (added: $($addedFiles.Count), changed: $($changedFiles.Count), removed: $($removedFiles.Count))"
Write-Host "  Unchanged (skipped): $($unchangedFiles.Count)"
Write-Host "  Patch size: $([math]::Round($patchSize / 1MB, 1)) MB"
Write-Host "  Output: $OutputDir"
