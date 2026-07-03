@echo off
setlocal EnableDelayedExpansion

REM ============================================================================
REM S3rpent Media - Release Build Wrapper
REM ============================================================================
REM This batch file calls the PowerShell build script which uses:
REM   - Qt 6.11.0 with MSVC 2022
REM   - Ninja generator for faster builds
REM   - vcpkg for libarchive dependency
REM   - Auto-detected project directory
REM ============================================================================

set "SCRIPT_DIR=%~dp0"
set "PS_SCRIPT=%SCRIPT_DIR%build_app_6110_msvc_release_ps.ps1"

echo ========================================
echo   S3rpent Media - Release Build
echo ========================================
echo.
echo This will build using MSVC + Qt 6.11.0
echo.

REM Check if PowerShell script exists
if not exist "%PS_SCRIPT%" (
    echo Error: PowerShell script not found at:
    echo   %PS_SCRIPT%
    echo.
    echo Please ensure build_app_6110_msvc_release_ps.ps1 exists in the scripts folder.
    goto :END
)

REM Check for G:\b directory
if exist "G:\b\" (
    echo Build directory: G:\b\s3_rel (short path)
) else (
    echo Build directory: project_dir\build\rel (G:\b not found)
)
echo.

REM Parse arguments
set "CLEAN_ARG="
if "%~1"=="--clean" (
    set "CLEAN_ARG=-clean"
    echo Clean build requested.
    echo.
)

REM Run PowerShell script with execution policy bypass
echo Starting PowerShell build script...
echo.
powershell.exe -ExecutionPolicy Bypass -File "%PS_SCRIPT%" %CLEAN_ARG%

if !errorlevel! neq 0 (
    echo.
    echo Build script failed with error code !errorlevel!.
    goto :END
)

echo.
echo ========================================
echo   Build wrapper completed!
echo ========================================

:END
echo.
pause
endlocal
