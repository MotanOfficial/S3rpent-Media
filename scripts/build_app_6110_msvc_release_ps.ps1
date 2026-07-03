# PowerShell script to build RELEASE with MSVC
# This build type provides maximum performance with no debug symbols
# Perfect for distribution to end users

$ErrorActionPreference = "Stop"

$CMAKE_CMD = "C:\Qt\Tools\CMake_64\bin\cmake.exe"
$NINJA_CMD = "C:\Qt\Tools\Ninja\ninja.exe"
$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
$PROJECT_DIR = (Resolve-Path (Join-Path $SCRIPT_DIR "..")).Path
$DEFAULT_SHORT_BUILD_ROOT = "G:\b"
$DEFAULT_SHORT_BUILD_DIRNAME = "s3_rel"

# Windows cmd.exe has a strict ~8191 char command-line limit. Qt's qmlimportscanner/qmlcachegen
# can exceed it when build paths are long. Use a short build directory by default.
# You can override by setting env var S3_BUILD_DIR to a full path.
if ($env:S3_BUILD_DIR -and -not [string]::IsNullOrWhiteSpace($env:S3_BUILD_DIR)) {
    $BUILD_DIR = $env:S3_BUILD_DIR
} else {
    if (Test-Path $DEFAULT_SHORT_BUILD_ROOT) {
        $BUILD_DIR = Join-Path $DEFAULT_SHORT_BUILD_ROOT $DEFAULT_SHORT_BUILD_DIRNAME
    } else {
        $BUILD_DIR = Join-Path $PROJECT_DIR "build\rel"
    }
}
$BINARY = Join-Path $BUILD_DIR "apps3rpent_media.exe"
$APP_EXE_NAME = "apps3rpent_media.exe"
$WINDEPLOYQT = "C:\Qt\6.11.0\msvc2022_64\bin\windeployqt.exe"
$VCPKG_ROOT = "C:\vcpkg"
$VCPKG_EXE = "$VCPKG_ROOT\vcpkg.exe"
$VCPKG_TRIPLET = "x64-windows"
$GIT_CMD = "git"

function Normalize-PathForCompare {
    param([string]$PathValue)

    if ([string]::IsNullOrWhiteSpace($PathValue)) {
        return ""
    }

    $normalized = $PathValue.Replace('/', '\').Trim()
    try {
        $normalized = [System.IO.Path]::GetFullPath($normalized)
    } catch {
        # Keep the best-effort normalized value when full resolution fails.
    }

    return $normalized.TrimEnd('\').ToLowerInvariant()
}

Write-Host "Setting up MSVC environment for RELEASE build..." -ForegroundColor Cyan
Write-Host "This build provides maximum performance for distribution" -ForegroundColor Yellow

# Find and run vcvars64.bat
# Use Visual Studio 2022 with v143 toolset.
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
    Write-Host "ERROR: Could not find Visual Studio 2022 installation." -ForegroundColor Red
    Write-Host "Please install Visual Studio 2022 with 'Desktop development with C++'" -ForegroundColor Yellow
    exit 1
}

Write-Host "Found Visual Studio 2022 at: $vcvarsPath" -ForegroundColor Green
Write-Host "Using Visual Studio 2022 with v143 toolset" -ForegroundColor Cyan

# Clear existing MSVC environment variables to avoid conflicts
# This ensures we use the compiler from the vcvars64.bat we just found
# Remove conflicting VS paths based on which VS we're using
$msvcVars = @("VCINSTALLDIR", "VCToolsInstallDir", "VSCMD_ARG_app_plat", "VSCMD_ARG_TGT_ARCH",
              "INCLUDE", "LIB", "LIBPATH", "PATH", "WindowsSdkDir", "WindowsSDKVersion")
foreach ($var in $msvcVars) {
    $currentValue = [Environment]::GetEnvironmentVariable($var, "Process")
    if ($currentValue) {
        $newValue = $currentValue
        if ($var -eq "PATH") {
            # Remove conflicting VS paths based on which VS we're using
            $pathParts = $currentValue -split ';'
            $filteredParts = @()
            foreach ($part in $pathParts) {
                if ($part) {
                    $shouldKeep = $true
                    # Using VS 2022 - remove VS 2025 (18) and VS 2019 paths
                    if ($part -like "*\18\*" -or $part -like "*\2019\*") {
                        $shouldKeep = $false
                    }
                    if ($shouldKeep) {
                        $filteredParts += $part
                    }
                }
            }
            $newValue = $filteredParts -join ';'
        } else {
            # For other variables, remove conflicting VS paths
            # Using VS 2022 - remove VS 2025 (18) and VS 2019 paths
            $newValue = ($currentValue -split ';' | Where-Object { $_ -and $_ -notlike "*\18\*" -and $_ -notlike "*\2019\*" }) -join ';'
        }

        if ($newValue -ne $currentValue) {
            [Environment]::SetEnvironmentVariable($var, $newValue, "Process")
        }
    }
}

# Run vcvars64.bat and capture environment variables
$tempBatch = [System.IO.Path]::GetTempFileName() + ".bat"
$tempOutput = [System.IO.Path]::GetTempFileName()

# Create a batch file that runs vcvars64.bat and exports all environment variables
# Use /V:ON to enable delayed expansion and ensure proper variable handling
$batchContent = @"
@echo off
setlocal EnableDelayedExpansion
call "$vcvarsPath" >nul 2>&1
set > "$tempOutput"
"@

Set-Content -Path $tempBatch -Value $batchContent
& cmd.exe /c $tempBatch

# Read the environment variables and apply them
# Special handling for PATH to ensure vcvars64.bat paths come first
$vcvarsPathParts = @()
$otherPathParts = @()
if (Test-Path $tempOutput) {
    $envVars = Get-Content $tempOutput
    foreach ($line in $envVars) {
        if ($line -match '^([^=]+)=(.*)$') {
            $name = $matches[1]
            $value = $matches[2]

            # Special handling for PATH - collect paths from vcvars64.bat first
            if ($name -eq "PATH") {
                $pathParts = $value -split ';'
                foreach ($part in $pathParts) {
                    if ($part) {
                        $vcvarsPathParts += $part
                    }
                }
            } else {
                # Apply all variables (we allow VS 2025 now)
                [Environment]::SetEnvironmentVariable($name, $value, "Process")
            }
        }
    }

    # Set PATH with vcvars64.bat paths FIRST, then existing paths (excluding conflicting VS paths)
    $currentPath = [Environment]::GetEnvironmentVariable("PATH", "Process")
    if ($currentPath) {
        $currentPathParts = ($currentPath -split ';' | Where-Object { $_ })
        foreach ($part in $currentPathParts) {
            # Skip paths that conflict with VS 2022
            # Using VS 2022 - skip VS 2025 (18) and VS 2019 paths
            $shouldSkip = $false
            if ($part -like "*\18\*" -or $part -like "*\2019\*") {
                $shouldSkip = $true
            }

            if (-not $shouldSkip -and $vcvarsPathParts -notcontains $part) {
                $otherPathParts += $part
            }
        }
    }

    # Combine: vcvars64.bat paths first, then other paths
    $newPathParts = $vcvarsPathParts + $otherPathParts
    $newPath = $newPathParts -join ';'
    [Environment]::SetEnvironmentVariable("PATH", $newPath, "Process")

    Remove-Item $tempOutput -ErrorAction SilentlyContinue
}
Remove-Item $tempBatch -ErrorAction SilentlyContinue

# Verify we're using the correct compiler
$clPath = (Get-Command cl -ErrorAction SilentlyContinue).Source
if (-not $clPath) {
    Write-Host "ERROR: cl.exe is not available after setting up MSVC environment." -ForegroundColor Red
    Write-Host "Try running from Visual Studio Developer Command Prompt instead." -ForegroundColor Yellow
    exit 1
}

Write-Host "MSVC environment set up successfully. Compiler: $clPath" -ForegroundColor Green
Write-Host "MSVC version:" -ForegroundColor Cyan
try {
    $versionOutput = & cl 2>&1 | Select-String -Pattern "Version"
    if ($versionOutput) {
        Write-Host $versionOutput -ForegroundColor White
    }
} catch {
    Write-Host "Could not determine compiler version" -ForegroundColor Yellow
}

# Set up Qt environment
Write-Host "Setting up Qt 6.11.0 with MSVC..." -ForegroundColor Cyan
$qtEnv = "C:\Qt\6.11.0\msvc2022_64\bin\qtenv2.bat"
if (Test-Path $qtEnv) {
    $qtBatch = [System.IO.Path]::GetTempFileName() + ".bat"
    $qtOutput = [System.IO.Path]::GetTempFileName()
    $qtBatchContent = @"
@echo off
call "$qtEnv" >nul 2>&1
set > "$qtOutput"
"@
    Set-Content -Path $qtBatch -Value $qtBatchContent
    & cmd.exe /c $qtBatch
    if (Test-Path $qtOutput) {
        $qtEnvVars = Get-Content $qtOutput
        foreach ($line in $qtEnvVars) {
            if ($line -match '^([^=]+)=(.*)$') {
                $name = $matches[1]
                $value = $matches[2]
                [Environment]::SetEnvironmentVariable($name, $value, "Process")
            }
        }
        Remove-Item $qtOutput -ErrorAction SilentlyContinue
    }
    Remove-Item $qtBatch -ErrorAction SilentlyContinue
}

# Ensure libarchive is available for ZIP extraction backend
Write-Host "Ensuring libarchive is installed via vcpkg..." -ForegroundColor Cyan
if (-not (Test-Path $VCPKG_EXE)) {
    Write-Host "vcpkg not found. Bootstrapping at $VCPKG_ROOT ..." -ForegroundColor Yellow

    $gitInPath = Get-Command $GIT_CMD -ErrorAction SilentlyContinue
    if (-not $gitInPath) {
        Write-Host "ERROR: git is required to auto-install vcpkg, but was not found in PATH." -ForegroundColor Red
        Write-Host "Install Git for Windows or install vcpkg manually, then rerun." -ForegroundColor Yellow
        exit 1
    }

    if (-not (Test-Path $VCPKG_ROOT)) {
        New-Item -ItemType Directory -Path $VCPKG_ROOT -Force | Out-Null
    }

    $vcpkgGitDir = Join-Path $VCPKG_ROOT ".git"
    if (-not (Test-Path $vcpkgGitDir)) {
        & $GIT_CMD clone "https://github.com/microsoft/vcpkg.git" $VCPKG_ROOT
        if ($LASTEXITCODE -ne 0) {
            Write-Host "ERROR: Failed to clone vcpkg repository." -ForegroundColor Red
            exit 1
        }
    } else {
        Write-Host "Existing vcpkg repo detected; skipping clone." -ForegroundColor DarkYellow
    }

    $bootstrapBat = Join-Path $VCPKG_ROOT "bootstrap-vcpkg.bat"
    if (-not (Test-Path $bootstrapBat)) {
        Write-Host "ERROR: bootstrap-vcpkg.bat not found in $VCPKG_ROOT" -ForegroundColor Red
        exit 1
    }

    & cmd.exe /c $bootstrapBat
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: Failed to bootstrap vcpkg." -ForegroundColor Red
        exit 1
    }
}
if (-not (Test-Path $VCPKG_EXE)) {
    Write-Host "ERROR: vcpkg.exe still not found at $VCPKG_EXE after bootstrap." -ForegroundColor Red
    exit 1
}
& $VCPKG_EXE @("install", "libarchive:$VCPKG_TRIPLET")
if ($LASTEXITCODE -ne 0) {
    Write-Host "Failed to install libarchive via vcpkg." -ForegroundColor Red
    exit 1
}

# Handle --clean argument
if ($args -contains "--clean") {
    Write-Host "Cleaning build directory..." -ForegroundColor Yellow
    if (Test-Path $BUILD_DIR) {
        Remove-Item $BUILD_DIR -Recurse -Force
    }
}

# Create build directory
if (-not (Test-Path $BUILD_DIR)) {
    New-Item -ItemType Directory -Path $BUILD_DIR | Out-Null
}

# Validate CMake cache and clean if it points to a different source/build tree
$cachePath = Join-Path $BUILD_DIR "CMakeCache.txt"
if (Test-Path $cachePath) {
    $cacheLines = Get-Content $cachePath
    $cacheBuildDir = ($cacheLines | Select-String '^CMAKE_CACHEFILE_DIR:INTERNAL=(.*)$' | ForEach-Object { $_.Matches[0].Groups[1].Value } | Select-Object -First 1)
    $cacheSourceDir = ($cacheLines | Select-String '^CMAKE_HOME_DIRECTORY:INTERNAL=(.*)$' | ForEach-Object { $_.Matches[0].Groups[1].Value } | Select-Object -First 1)

    $normalizedExpectedBuildDir = Normalize-PathForCompare $BUILD_DIR
    $normalizedExpectedSourceDir = Normalize-PathForCompare $PROJECT_DIR
    $normalizedCacheBuildDir = Normalize-PathForCompare $cacheBuildDir
    $normalizedCacheSourceDir = Normalize-PathForCompare $cacheSourceDir

    if (($normalizedCacheBuildDir -and $normalizedCacheBuildDir -ne $normalizedExpectedBuildDir) -or
        ($normalizedCacheSourceDir -and $normalizedCacheSourceDir -ne $normalizedExpectedSourceDir)) {
        Write-Host "Detected stale CMake cache from a different path. Recreating build directory..." -ForegroundColor Yellow
        Write-Host "  Cached build dir : $cacheBuildDir" -ForegroundColor DarkYellow
        Write-Host "  Expected build dir: $BUILD_DIR" -ForegroundColor DarkYellow
        Write-Host "  Cached source dir : $cacheSourceDir" -ForegroundColor DarkYellow
        Write-Host "  Expected source dir: $PROJECT_DIR" -ForegroundColor DarkYellow

        Remove-Item $BUILD_DIR -Recurse -Force
        New-Item -ItemType Directory -Path $BUILD_DIR | Out-Null
    }
}

# Configure with CMake (always run to keep cache/settings in sync)
Write-Host "Configuring project with CMake + Ninja (MSVC) for RELEASE..." -ForegroundColor Cyan

# Prefer Qt-provided Ninja, but fall back to Ninja in PATH.
if (-not (Test-Path $NINJA_CMD)) {
    $ninjaInPath = (Get-Command ninja -ErrorAction SilentlyContinue).Source
    if ($ninjaInPath) {
        $NINJA_CMD = $ninjaInPath
    } else {
        Write-Host "ERROR: Ninja not found at $NINJA_CMD and not found in PATH." -ForegroundColor Red
        Write-Host "Install Qt Ninja tool or add ninja.exe to PATH." -ForegroundColor Yellow
        exit 1
    }
}
Write-Host "Using generator: Ninja" -ForegroundColor Cyan
Write-Host "Using Ninja executable: $NINJA_CMD" -ForegroundColor Cyan

$cmakeArgs = @(
    "-S", $PROJECT_DIR,
    "-B", $BUILD_DIR,
    "-G", "Ninja",
    "-DCMAKE_MAKE_PROGRAM=$NINJA_CMD",
    "-DCMAKE_C_COMPILER=cl.exe",
    "-DCMAKE_CXX_COMPILER=cl.exe",
    "-DCMAKE_BUILD_TYPE=Release",
    "-DCMAKE_PREFIX_PATH=C:/Qt/6.11.0/msvc2022_64",
    "-DCMAKE_TOOLCHAIN_FILE=C:/vcpkg/scripts/buildsystems/vcpkg.cmake"
)
& $CMAKE_CMD $cmakeArgs
if ($LASTEXITCODE -ne 0) {
    Write-Host "CMake configuration failed." -ForegroundColor Red
    exit 1
}

# Build
Write-Host "`nBuilding Qt project with Qt 6.11.0 (MSVC) - RELEASE..." -ForegroundColor Cyan
Write-Host "This build will have maximum performance optimizations" -ForegroundColor Yellow

# Qt qmlimportscanner runs via cmd + qt_setup_tool_path.bat; huge PATH breaks cmd's 8191-char limit.
# Trim PATH before building so those cmd invocations don't exceed the limit.
. (Join-Path $SCRIPT_DIR "PathLimit.ps1")
Limit-PathForQtCmdBatch

$buildArgs = @(
    "--build", $BUILD_DIR
)
& $CMAKE_CMD $buildArgs

if ($LASTEXITCODE -ne 0) {
    Write-Host "Build failed." -ForegroundColor Red
    exit 1
}

Write-Host "Build succeeded!" -ForegroundColor Green

# Resolve the built binary path after build
$expectedBinary = Join-Path $BUILD_DIR $APP_EXE_NAME
if (Test-Path $expectedBinary) {
    $BINARY = $expectedBinary
} else {
    $candidateBinaries = @(Get-ChildItem -Path $BUILD_DIR -Filter "app*.exe" -File -Recurse -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
    if ($candidateBinaries.Count -gt 0) {
        $BINARY = $candidateBinaries[0].FullName
        Write-Host "Expected binary name not found; using detected binary: $BINARY" -ForegroundColor Yellow
    }
}

# Deploy
Write-Host "Running windeployqt..." -ForegroundColor Cyan
if (-not (Test-Path $WINDEPLOYQT)) {
    Write-Host "Error: windeployqt.exe not found at $WINDEPLOYQT" -ForegroundColor Red
    exit 1
}
if (-not (Test-Path $BINARY)) {
    Write-Host "Error: Built binary not found at $BINARY" -ForegroundColor Red
    exit 1
}

& $WINDEPLOYQT --qmldir $PROJECT_DIR --release $BINARY

if ($LASTEXITCODE -ne 0) {
    Write-Host "Deployment failed." -ForegroundColor Red
    exit 1
}

Write-Host "`n========================================" -ForegroundColor Green
Write-Host "RELEASE build and deployment succeeded!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host "Binary location: $BINARY" -ForegroundColor Cyan
Write-Host "Build type: Release (maximum performance)" -ForegroundColor White
Write-Host "`nFeatures:" -ForegroundColor Yellow
Write-Host "  - Full Release optimizations (O2/Ox, aggressive inlining)" -ForegroundColor White
Write-Host "  - No debug symbols (smaller binary size)" -ForegroundColor White
Write-Host "  - Release CRT (no debug overhead)" -ForegroundColor White
Write-Host "  - Ready for distribution to end users" -ForegroundColor White
