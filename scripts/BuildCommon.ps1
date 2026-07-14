# Shared helpers for S3rpent Media build scripts.

$script:AppReleasePrefix = "media"

function Normalize-PathForCompare {
    param([string]$PathValue)

    if ([string]::IsNullOrWhiteSpace($PathValue)) {
        return ""
    }

    $normalized = $PathValue.Replace('/', '\').Trim()
    try {
        $normalized = [System.IO.Path]::GetFullPath($normalized)
    } catch {}

    return $normalized.TrimEnd('\').ToLowerInvariant()
}

function Join-ReleaseObjectPath {
    param([string]$RelativePath)

    $normalized = $RelativePath.Trim().TrimStart('/').Replace('\', '/')
    if ([string]::IsNullOrWhiteSpace($normalized)) {
        return $script:AppReleasePrefix
    }
    if ($normalized.StartsWith("$($script:AppReleasePrefix)/")) {
        return $normalized
    }
    return "$($script:AppReleasePrefix)/$normalized"
}

function Initialize-MsvcEnvironment {
    $vcvarsPaths = @(
        "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat",
        "C:\Program Files\Microsoft Visual Studio\2022\Professional\VC\Auxiliary\Build\vcvars64.bat",
        "C:\Program Files\Microsoft Visual Studio\2022\Enterprise\VC\Auxiliary\Build\vcvars64.bat",
        "C:\Program Files\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat",
        "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat"
    )

    $vcvarsPath = $null
    foreach ($path in $vcvarsPaths) {
        if (Test-Path $path) {
            $vcvarsPath = $path
            break
        }
    }

    if (-not $vcvarsPath) {
        throw "Visual Studio 2022 with C++ tools not found."
    }

    $tempBatch = [System.IO.Path]::GetTempFileName() + ".bat"
    $tempOutput = [System.IO.Path]::GetTempFileName()
    Set-Content -Path $tempBatch -Value @"
@echo off
setlocal EnableDelayedExpansion
call "$vcvarsPath" >nul 2>&1
set > "$tempOutput"
"@
    & cmd.exe /c $tempBatch

    $vcvarsPathParts = @()
    $otherPathParts = @()
    if (Test-Path $tempOutput) {
        foreach ($line in Get-Content $tempOutput) {
            if ($line -match '^([^=]+)=(.*)$') {
                $name = $matches[1]
                $value = $matches[2]
                if ($name -eq "PATH") {
                    foreach ($part in ($value -split ';')) {
                        if ($part) { $vcvarsPathParts += $part }
                    }
                } else {
                    [Environment]::SetEnvironmentVariable($name, $value, "Process")
                }
            }
        }

        $currentPath = [Environment]::GetEnvironmentVariable("PATH", "Process")
        if ($currentPath) {
            foreach ($part in ($currentPath -split ';' | Where-Object { $_ })) {
                if ($part -notlike "*\18\*" -and $part -notlike "*\2019\*" -and $vcvarsPathParts -notcontains $part) {
                    $otherPathParts += $part
                }
            }
        }
        [Environment]::SetEnvironmentVariable("PATH", (($vcvarsPathParts + $otherPathParts) -join ';'), "Process")
        Remove-Item $tempOutput -ErrorAction SilentlyContinue
    }
    Remove-Item $tempBatch -ErrorAction SilentlyContinue

    return $vcvarsPath
}

function Initialize-QtEnvironment {
    param([string]$QtRoot = "C:\Qt\6.11.1\msvc2022_64")

    $qtEnv = Join-Path $QtRoot "bin\qtenv2.bat"
    if (-not (Test-Path $qtEnv)) {
        return
    }

    $qtBatch = [System.IO.Path]::GetTempFileName() + ".bat"
    $qtOutput = [System.IO.Path]::GetTempFileName()
    Set-Content -Path $qtBatch -Value "@echo off`ncall `"$qtEnv`" >nul 2>&1`nset > `"$qtOutput`""
    & cmd.exe /c $qtBatch
    if (Test-Path $qtOutput) {
        foreach ($line in Get-Content $qtOutput) {
            if ($line -match '^([^=]+)=(.*)$') {
                [Environment]::SetEnvironmentVariable($matches[1], $matches[2], "Process")
            }
        }
        Remove-Item $qtOutput -ErrorAction SilentlyContinue
    }
    Remove-Item $qtBatch -ErrorAction SilentlyContinue
}

function Resolve-InstallerFramework {
    $versions = @("4.10", "4.9", "4.8", "4.7", "4.6", "4.5")
    foreach ($version in $versions) {
        $root = "C:\Qt\Tools\QtInstallerFramework\$version"
        $binaryCreator = Join-Path $root "bin\binarycreator.exe"
        if (Test-Path $binaryCreator) {
            return @{
                Root = $root
                BinaryCreator = $binaryCreator
            }
        }
    }
    return $null
}

function Get-ProjectVersion {
    param([string]$ProjectDir)

    $cmakeFile = Join-Path $ProjectDir "CMakeLists.txt"
    if (-not (Test-Path $cmakeFile)) {
        return "0.1.0"
    }

    foreach ($line in Get-Content $cmakeFile) {
        if ($line -match 'project\s*\(\s*\S+\s+VERSION\s+([0-9]+(?:\.[0-9]+)*)\s*') {
            $version = $matches[1]
            if ($version -notmatch '\.[0-9]+\.[0-9]+$') {
                return "$version.0"
            }
            return $version
        }
    }

    return "0.1.0"
}

function Update-InstallerMetadata {
    param(
        [string]$ProjectDir,
        [string]$Version,
        [string]$PackageId = "com.s3rpent.media"
    )

    $configXml = Join-Path $ProjectDir "installer\config\config.xml"
    $packageXml = Join-Path $ProjectDir "installer\packages\$PackageId\meta\package.xml"
    $releaseDate = (Get-Date).ToString("yyyy-MM-dd")

    foreach ($path in @($configXml, $packageXml)) {
        if (-not (Test-Path $path)) {
            continue
        }
        $content = Get-Content $path -Raw
        $content = $content -replace '(<Version>)[^<]+(</Version>)', "`${1}$Version`${2}"
        if ($path -eq $packageXml) {
            $content = $content -replace '(<ReleaseDate>)[^<]+(</ReleaseDate>)', "`${1}$releaseDate`${2}"
        }
        Set-Content -Path $path -Value $content -NoNewline
    }
}

function Resolve-NinjaCommand {
    $candidates = @(
        "C:\Qt\Tools\Ninja\ninja.exe",
        "C:\Qt\Tools\CMake_64\bin\ninja.exe"
    )
    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) {
            return $candidate
        }
    }

    $ninjaInPath = (Get-Command ninja -ErrorAction SilentlyContinue).Source
    if ($ninjaInPath) {
        return $ninjaInPath
    }

    throw "Ninja not found."
}

function Invoke-External {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(ValueFromRemainingArguments = $true)][string[]]$ArgumentList
    )

    $proc = Start-Process -FilePath $FilePath -ArgumentList $ArgumentList -NoNewWindow -Wait -PassThru
    if ($proc.ExitCode -ne 0) {
        throw "Command failed ($($proc.ExitCode)): $FilePath $($ArgumentList -join ' ')"
    }
}

function Get-SupabaseConfig {
    $configPath = Join-Path $PROJECT_DIR "src\cpp\supabase_config.h"
    if (-not (Test-Path $configPath)) {
        throw "supabase_config.h not found at $configPath"
    }

    $content = Get-Content $configPath -Raw
    if ($content -notmatch 'defaultProjectUrl\s*=\s*"([^"]+)"') {
        throw "Could not read defaultProjectUrl from supabase_config.h"
    }
    $projectUrl = $matches[1].TrimEnd('/')
    return @{
        ProjectUrl = $projectUrl
        Bucket = "app-releases"
    }
}

function Resolve-SupabaseServiceKey {
    param([hashtable]$Config)

    $key = $env:SUPABASE_SERVICE_KEY
    if (-not [string]::IsNullOrWhiteSpace($key)) {
        return $key
    }

    $envFile = Join-Path $PROJECT_DIR ".env"
    if (Test-Path $envFile) {
        foreach ($line in Get-Content $envFile) {
            if ($line -match '^SUPABASE_SERVICE_KEY=(.+)$') {
                return $matches[1].Trim().Trim('"', "'")
            }
        }
    }

    return $null
}

function Format-CMakePathArg {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Value
    )

    $normalized = $Value -replace '\\', '/'
    return ("-D{0}=`"{1}`"" -f $Name, $normalized)
}

function Ensure-VcpkgPackage {
    param(
        [string]$PackageName,
        [string]$Triplet = "x64-windows"
    )

    $vcpkgRoots = @()
    if ($env:VCPKG_ROOT) { $vcpkgRoots += $env:VCPKG_ROOT }
    $vcpkgRoots += "C:\vcpkg"
    if (Test-Path "G:\b") { $vcpkgRoots += "G:\b\vcpkg" }

    $vcpkgExe = $null
    foreach ($root in $vcpkgRoots) {
        $exe = Join-Path $root "vcpkg.exe"
        if (Test-Path $exe) {
            $vcpkgExe = $exe
            break
        }
    }

    if (-not $vcpkgExe) {
        Write-Warning "vcpkg not found; cannot ensure $PackageName"
        return
    }

    $installedDir = Join-Path (Split-Path $vcpkgExe -Parent) "installed\$Triplet"
    & $vcpkgExe "install", "$PackageName`:$Triplet", "--clean-after-build"
    if ($LASTEXITCODE -ne 0) {
        throw "vcpkg install $PackageName failed."
    }
}

function ConvertTo-LatestManifestJson {
    param(
        [string]$LatestVersion,
        [string]$ReleaseNotes,
        [string]$PublishedAt,
        [array]$Patches,
        [hashtable]$FullRelease,
        [hashtable]$AndroidRelease = $null
    )

    $obj = [ordered]@{
        latest_version = $LatestVersion
        release_notes = $ReleaseNotes
        published_at = $PublishedAt
        patches = $Patches
        full_release = $FullRelease
    }

    if ($null -ne $AndroidRelease) {
        $obj.android_release = $AndroidRelease
    }

    return ($obj | ConvertTo-Json -Depth 10)
}

function Write-Utf8NoBomFile {
    param([string]$Path, [string]$Text)

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        $bytes = $bytes[3..($bytes.Length - 1)]
    }
    [System.IO.File]::WriteAllBytes($Path, $bytes)
}

function Upload-StorageObject {
    param(
        [string]$ProjectUrl,
        [string]$ServiceKey,
        [string]$Bucket,
        [string]$ObjectPath,
        [string]$LocalPath,
        [string]$ContentType = "application/octet-stream"
    )

    $normalizedPath = $ObjectPath.TrimStart('/')
    $uri = "$ProjectUrl/storage/v1/object/$Bucket/$normalizedPath"
    $bytes = [System.IO.File]::ReadAllBytes($LocalPath)

    $headers = @{
        Authorization = "Bearer $ServiceKey"
        apikey = $ServiceKey
        "x-upsert" = "true"
    }

    Invoke-RestMethod -Method Put -Uri $uri -Headers $headers -ContentType $ContentType -Body $bytes | Out-Null
    Write-Host "  uploaded $normalizedPath" -ForegroundColor DarkGray
}

function Upload-TextObject {
    param(
        [string]$ProjectUrl,
        [string]$ServiceKey,
        [string]$Bucket,
        [string]$ObjectPath,
        [string]$Text,
        [string]$ContentType = "application/json"
    )

    $tempFile = [System.IO.Path]::GetTempFileName()
    try {
        Set-Content -Path $tempFile -Value $Text -Encoding UTF8
        Upload-StorageObject -ProjectUrl $ProjectUrl -ServiceKey $ServiceKey -Bucket $Bucket `
            -ObjectPath $ObjectPath -LocalPath $tempFile -ContentType $ContentType
    } finally {
        Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
    }
}

function Normalize-Version {
    param([string]$Version)
    $parts = @($Version.Trim().Split('.') | Where-Object { $_ -ne "" })
    while ($parts.Count -lt 3) { $parts += "0" }
    return ($parts[0..2] -join '.')
}

function Compare-Versions {
    param([string]$Left, [string]$Right)
    $leftParts = @(Normalize-Version $Left).Split('.') | ForEach-Object { [int]$_ }
    $rightParts = @(Normalize-Version $Right).Split('.') | ForEach-Object { [int]$_ }
    for ($i = 0; $i -lt 3; $i++) {
        if ($leftParts[$i] -lt $rightParts[$i]) { return -1 }
        if ($leftParts[$i] -gt $rightParts[$i]) { return 1 }
    }
    return 0
}
