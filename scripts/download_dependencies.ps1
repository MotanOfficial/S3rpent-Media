#!/usr/bin/env pwsh
#Requires -Version 5.1
<#
.SYNOPSIS
    Downloads yt-dlp.exe and deno.exe to the project root directory.
.DESCRIPTION
    This script downloads the latest yt-dlp.exe from GitHub releases and
    deno v2.7.11 for Windows x64. Files are placed in the project root.
#>

param(
    [string]$ProjectRoot = $PSScriptRoot,
    [switch]$Force
)

$ErrorActionPreference = "Stop"

# URLs for downloads
$YtDlpUrl = "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe"
$DenoUrl = "https://github.com/denoland/deno/releases/download/v2.7.11/deno-x86_64-pc-windows-msvc.zip"

# Target paths
$YtDlpPath = Join-Path $ProjectRoot "yt-dlp.exe"
$DenoZipPath = Join-Path $ProjectRoot "deno.zip"
$DenoExePath = Join-Path $ProjectRoot "deno.exe"

function Write-Info {
    param([string]$Message)
    Write-Host "[Download] $Message" -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Message)
    Write-Host "[Download] $Message" -ForegroundColor Green
}

function Write-Warn {
    param([string]$Message)
    Write-Host "[Download] $Message" -ForegroundColor Yellow
}

function Invoke-DownloadFile {
    param(
        [string]$Url,
        [string]$OutFile,
        [string]$Description
    )

    if ((Test-Path $OutFile) -and -not $Force) {
        Write-Warn "$Description already exists at $OutFile. Use -Force to re-download."
        return
    }

    Write-Info "Downloading $Description from $Url..."

    try {
        # Use Invoke-WebRequest for download
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing
        $ProgressPreference = 'Continue'
        Write-Success "$Description downloaded successfully to $OutFile"
    }
    catch {
        Write-Error "Failed to download $Description : $_"
        exit 1
    }
}

function Install-Deno {
    param(
        [string]$ZipPath,
        [string]$TargetPath
    )

    if ((Test-Path $TargetPath) -and -not $Force) {
        Write-Warn "deno.exe already exists. Use -Force to re-extract."
        # Clean up zip if it exists
        if (Test-Path $ZipPath) {
            Remove-Item $ZipPath -Force
        }
        return
    }

    Write-Info "Extracting deno.exe from archive..."

    try {
        # Extract deno.exe from the zip
        Expand-Archive -Path $ZipPath -DestinationPath $ProjectRoot -Force

        # The zip contains deno.exe directly
        if (Test-Path $TargetPath) {
            Write-Success "deno.exe extracted successfully to $TargetPath"
        } else {
            # Try to find deno.exe if it's in a subdirectory
            $found = Get-ChildItem -Path $ProjectRoot -Name "deno.exe" -Recurse | Select-Object -First 1
            if ($found) {
                $fullPath = Join-Path $ProjectRoot $found
                Move-Item $fullPath $TargetPath -Force
                Write-Success "deno.exe extracted and moved to $TargetPath"
            } else {
                throw "deno.exe not found in extracted archive"
            }
        }
    }
    catch {
        Write-Error "Failed to extract deno.exe: $_"
        exit 1
    }
    finally {
        # Clean up zip file
        if (Test-Path $ZipPath) {
            Remove-Item $ZipPath -Force
            Write-Info "Cleaned up temporary zip file"
        }
    }
}

# Main execution
Write-Info "Starting download of yt-dlp.exe and deno.exe..."
Write-Info "Project root: $ProjectRoot"

# Download yt-dlp.exe
Invoke-DownloadFile -Url $YtDlpUrl -OutFile $YtDlpPath -Description "yt-dlp.exe"

# Download and extract deno
Invoke-DownloadFile -Url $DenoUrl -OutFile $DenoZipPath -Description "deno.zip"
Install-Deno -ZipPath $DenoZipPath -TargetPath $DenoExePath

Write-Success "All downloads completed successfully!"
Write-Host ""
Write-Host "Files in project root:" -ForegroundColor White
Get-ChildItem -Path $ProjectRoot -Name "*.exe" | ForEach-Object {
    $path = Join-Path $ProjectRoot $_
    $size = (Get-Item $path).Length
    $sizeStr = if ($size -gt 1MB) {
        "{0:N1} MB" -f ($size / 1MB)
    } else {
        "{0:N1} KB" -f ($size / 1KB)
    }
    Write-Host "  - $_ ($sizeStr)" -ForegroundColor Gray
}
