# Upload delta patch / full release manifests and files to Supabase Storage.
param(
    [Parameter(Mandatory = $true)]
    [string]$ToVersion,
    [string]$FromVersion,
    [string]$PatchDir,
    [string]$ReleaseDir,
    [string]$ReleaseNotes = "",
    [switch]$SkipLatestJson
)

$ErrorActionPreference = "Stop"

$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
$PROJECT_DIR = (Resolve-Path (Join-Path $SCRIPT_DIR "..")).Path

. (Join-Path $SCRIPT_DIR "BuildCommon.ps1")

$config = Get-SupabaseConfig
$serviceKey = Resolve-SupabaseServiceKey -Config $config
if ([string]::IsNullOrWhiteSpace($serviceKey)) {
    throw "Set SUPABASE_SERVICE_KEY in environment or .env"
}

$toVersionNorm = Normalize-Version $ToVersion
$fromVersionNorm = if ($FromVersion) { Normalize-Version $FromVersion } else { $null }

if (-not $PatchDir) {
    if ($fromVersionNorm) {
        $PatchDir = Join-Path $PROJECT_DIR "dist\patches\$fromVersionNorm-$toVersionNorm"
    }
}
if (-not $ReleaseDir) {
    $ReleaseDir = Join-Path $PROJECT_DIR "dist\releases\$toVersionNorm"
}

$releaseManifestPath = Join-Path $ReleaseDir "manifest.json"
if (-not (Test-Path $releaseManifestPath)) {
    throw "Release manifest not found: $releaseManifestPath"
}

$releaseManifest = Get-Content $releaseManifestPath -Raw | ConvertFrom-Json

Write-Host "Publishing app update $toVersionNorm to Supabase Storage" -ForegroundColor Cyan

# Upload full release files
foreach ($file in $releaseManifest.files) {
    $localPath = Join-Path $ReleaseDir ("files\" + ($file.path -replace '/', '\'))
    if (-not (Test-Path $localPath)) {
        throw "Missing release file: $localPath"
    }
    Upload-StorageObject -ProjectUrl $config.ProjectUrl -ServiceKey $serviceKey `
        -Bucket $config.Bucket -ObjectPath (Join-ReleaseObjectPath $file.storage_path) -LocalPath $localPath
}

Upload-TextObject -ProjectUrl $config.ProjectUrl -ServiceKey $serviceKey -Bucket $config.Bucket `
    -ObjectPath (Join-ReleaseObjectPath "releases/$toVersionNorm/manifest.json") `
    -Text (Get-Content $releaseManifestPath -Raw)

$patchManifest = $null
if ($PatchDir -and (Test-Path $PatchDir)) {
    $patchManifestPath = Join-Path $PatchDir "manifest.json"
    if (-not (Test-Path $patchManifestPath)) {
        throw "Patch manifest not found: $patchManifestPath"
    }
    $patchManifest = Get-Content $patchManifestPath -Raw | ConvertFrom-Json

    foreach ($file in $patchManifest.files) {
        $localPath = Join-Path $PatchDir ("files\" + ($file.path -replace '/', '\'))
        if (-not (Test-Path $localPath)) {
            throw "Missing patch file: $localPath"
        }
        Upload-StorageObject -ProjectUrl $config.ProjectUrl -ServiceKey $serviceKey `
            -Bucket $config.Bucket -ObjectPath (Join-ReleaseObjectPath $file.storage_path) -LocalPath $localPath
    }

    Upload-TextObject -ProjectUrl $config.ProjectUrl -ServiceKey $serviceKey -Bucket $config.Bucket `
        -ObjectPath (Join-ReleaseObjectPath "patches/$fromVersionNorm-$toVersionNorm/manifest.json") `
        -Text (Get-Content $patchManifestPath -Raw)
}

if (-not $SkipLatestJson) {
    $latestPath = Join-Path $PROJECT_DIR "dist\latest.json"
    $notes = if ($ReleaseNotes) { $ReleaseNotes } else { "Release $toVersionNorm" }
    $publishedAt = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    $fullRelease = @{
        version = $toVersionNorm
        manifest_path = (Join-ReleaseObjectPath "releases/$toVersionNorm/manifest.json")
    }

    $patches = @()
if ($null -ne $patchManifest) {
            $existingLatest = $null
        $existingUrl = "$($config.ProjectUrl)/storage/v1/object/public/$($config.Bucket)/$(Join-ReleaseObjectPath 'latest.json')"
        try {
            $existingLatest = Invoke-RestMethod -Uri $existingUrl -Method Get
        } catch {}

        $existingPatches = @()
        if ($null -ne $existingLatest -and $null -ne $existingLatest.patches) {
            $existingPatches = @($existingLatest.patches)
        }

        $newManifestPath = (Join-ReleaseObjectPath "patches/$fromVersionNorm-$toVersionNorm/manifest.json")
        $merged = New-Object System.Collections.Generic.List[object]
        foreach ($patch in $existingPatches) {
            if ($null -eq $patch) { continue }
            $pFrom = Normalize-Version ([string]$patch.from)
            $pTo = Normalize-Version ([string]$patch.to)
            $pPath = [string]$patch.manifest_path
            if ([string]::IsNullOrWhiteSpace($pPath)) { continue }
            if ($pFrom -eq $fromVersionNorm -and $pTo -eq $toVersionNorm) { continue }
            if ($pFrom -eq $fromVersionNorm) { continue }
            $merged.Add([ordered]@{
                from = $pFrom
                to = $pTo
                manifest_path = $pPath
            })
        }
        $merged.Add([ordered]@{
            from = $fromVersionNorm
            to = $toVersionNorm
            manifest_path = $newManifestPath
        })
        $patches = @($merged | Sort-Object {
            $parts = (Normalize-Version $_.from).Split('.') | ForEach-Object { [int]$_ }
            ($parts[0] * 1000000) + ($parts[1] * 1000) + $parts[2]
        })
    }

    # Write latest.json locally and upload
    $latestJson = ConvertTo-LatestManifestJson `
        -LatestVersion $toVersionNorm `
        -ReleaseNotes $notes `
        -PublishedAt $publishedAt `
        -Patches $patches `
        -FullRelease $fullRelease

    Write-Utf8NoBomFile -Path $latestPath -Text $latestJson
    Upload-TextObject -ProjectUrl $config.ProjectUrl -ServiceKey $serviceKey -Bucket $config.Bucket `
        -ObjectPath (Join-ReleaseObjectPath "latest.json") -Text $latestJson
}

Write-Host ""
Write-Host "Update published successfully." -ForegroundColor Green
Write-Host "Public latest.json: $($config.ProjectUrl)/storage/v1/object/public/app-releases/$(Join-ReleaseObjectPath 'latest.json')"
