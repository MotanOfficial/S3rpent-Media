# PowerShell script to build FASTDEBUG (RelWithDebInfo) with MSVC
# This build type provides Release performance with debug symbols for profiling
# Perfect for media apps that need smooth playback but also need debugging

$ErrorActionPreference = "Stop"

$CMAKE_CMD = "C:\Qt\Tools\CMake_64\bin\cmake.exe"
$PROJECT_DIR = "C:\Users\Motan\Documents\s3rp3nt_media"
$BUILD_DIR = "C:\Users\Motan\Documents\s3rp3nt_media\build\Desktop_Qt_6_10_1_MSVC_64_bit-FastDebug"
$BINARY = "$BUILD_DIR\RelWithDebInfo\apps3rp3nt_media.exe"
$WINDEPLOYQT = "C:\Qt\6.10.1\msvc2022_64\bin\windeployqt.exe"
$VCPKG_ROOT = "C:\vcpkg"
$VCPKG_EXE = "$VCPKG_ROOT\vcpkg.exe"
$VCPKG_TRIPLET = "x64-windows"

Write-Host "Setting up MSVC environment for FASTDEBUG build (RelWithDebInfo)..." -ForegroundColor Cyan
Write-Host "This build provides Release performance with debug symbols" -ForegroundColor Yellow

# Find and run vcvars64.bat
# Only use Visual Studio 2022 with v143 toolset for Qt 6.10.1 compatibility
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
Write-Host "Using Visual Studio 2022 with v143 toolset for Qt 6.10.1 compatibility" -ForegroundColor Cyan

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
Write-Host "Setting up Qt 6.10.1 with MSVC..." -ForegroundColor Cyan
$qtEnv = "C:\Qt\6.10.1\msvc2022_64\bin\qtenv2.bat"
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
    Write-Host "ERROR: vcpkg not found at $VCPKG_EXE" -ForegroundColor Red
    Write-Host "Install vcpkg or update script path before building." -ForegroundColor Yellow
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

# Configure with CMake
if (-not (Test-Path "$BUILD_DIR\CMakeCache.txt")) {
    Write-Host "Configuring project with CMake (MSVC) for FASTDEBUG (RelWithDebInfo)..." -ForegroundColor Cyan
    
    # Always use Visual Studio 17 2022 generator with v143 toolset for Qt 6.10.1 compatibility
    $vsGenerator = "Visual Studio 17 2022"
    $toolset = "v143"
    
    Write-Host "Using generator: $vsGenerator with toolset: $toolset" -ForegroundColor Cyan
    
    $cmakeArgs = @(
        "-S", $PROJECT_DIR,
        "-B", $BUILD_DIR,
        "-G", $vsGenerator,
        "-A", "x64",
        "-T", $toolset,
        "-DCMAKE_BUILD_TYPE=RelWithDebInfo",
        "-DCMAKE_PREFIX_PATH=C:/Qt/6.10.1/msvc2022_64",
        "-DCMAKE_TOOLCHAIN_FILE=C:/vcpkg/scripts/buildsystems/vcpkg.cmake"
    )
    & $CMAKE_CMD $cmakeArgs
    if ($LASTEXITCODE -ne 0) {
        Write-Host "CMake configuration failed." -ForegroundColor Red
        exit 1
    }
}

# Build
Write-Host "`nBuilding Qt project with Qt 6.10.1 (MSVC) - FASTDEBUG (RelWithDebInfo)..." -ForegroundColor Cyan
Write-Host "This build will have Release performance with debug symbols" -ForegroundColor Yellow
$buildArgs = @(
    "--build", $BUILD_DIR,
    "--config", "RelWithDebInfo"
)
& $CMAKE_CMD $buildArgs

if ($LASTEXITCODE -ne 0) {
    Write-Host "Build failed." -ForegroundColor Red
    exit 1
}

Write-Host "Build succeeded!" -ForegroundColor Green

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
Write-Host "FASTDEBUG build and deployment succeeded!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host "Binary location: $BINARY" -ForegroundColor Cyan
Write-Host "Build type: RelWithDebInfo (Release performance + debug symbols)" -ForegroundColor White
Write-Host "`nBenefits:" -ForegroundColor Yellow
Write-Host "  - Full Release optimizations (O2, aggressive inlining)" -ForegroundColor White
Write-Host "  - Debug symbols (PDB) for stack traces and profiling" -ForegroundColor White
Write-Host "  - Release CRT (no Debug CRT overhead)" -ForegroundColor White
Write-Host "  - Perfect for media apps that need smooth playback + debugging" -ForegroundColor White

