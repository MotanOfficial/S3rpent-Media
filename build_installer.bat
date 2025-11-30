@echo off
setlocal EnableDelayedExpansion

REM ========================================
REM   S3rp3nt Media - Installer Builder
REM ========================================

set "PROJECT_DIR=C:\Users\Motan\Documents\s3rp3nt_media"
set "RELEASE_DIR=%PROJECT_DIR%\build\Release"
set "INSTALLER_DIR=%PROJECT_DIR%\installer"
set "PACKAGE_DATA=%INSTALLER_DIR%\packages\com.s3rp3nt.media\data"
set "OUTPUT_DIR=%PROJECT_DIR%\dist"

REM Qt Installer Framework path
set "IFW_DIR=C:\Qt\Tools\QtInstallerFramework\4.10"
set "BINARYCREATOR=%IFW_DIR%\bin\binarycreator.exe"

echo ========================================
echo   S3rp3nt Media - Installer Builder
echo ========================================
echo.

REM Check if Qt Installer Framework is installed
if not exist "%BINARYCREATOR%" (
    echo ERROR: Qt Installer Framework not found at:
    echo   %IFW_DIR%
    echo.
    echo Please install Qt Installer Framework via Qt Maintenance Tool:
    echo   1. Run Qt Maintenance Tool
    echo   2. Select "Add or remove components"
    echo   3. Under "Qt" ^> "Developer and Designer Tools"
    echo   4. Check "Qt Installer Framework 4.x"
    echo   5. Click "Next" and complete installation
    echo.
    echo Common IFW paths:
    echo   C:\Qt\Tools\QtInstallerFramework\4.8
    echo   C:\Qt\Tools\QtInstallerFramework\4.7
    echo   C:\Qt\Tools\QtInstallerFramework\4.6
    echo.
    
    REM Try to find IFW in common locations
    for %%v in (4.10 4.9 4.8 4.7 4.6 4.5) do (
        if exist "C:\Qt\Tools\QtInstallerFramework\%%v\bin\binarycreator.exe" (
            echo Found IFW version %%v
            set "IFW_DIR=C:\Qt\Tools\QtInstallerFramework\%%v"
            set "BINARYCREATOR=!IFW_DIR!\bin\binarycreator.exe"
            goto :FOUND_IFW
        )
    )
    
    echo Could not find Qt Installer Framework automatically.
    goto :END
)

:FOUND_IFW
echo Using Qt Installer Framework: %IFW_DIR%
echo.

REM Check if release build exists
if not exist "%RELEASE_DIR%\apps3rp3nt_media.exe" (
    echo ERROR: Release build not found!
    echo.
    echo Please run build_release.bat first to create the release build.
    echo Expected location: %RELEASE_DIR%\apps3rp3nt_media.exe
    goto :END
)

REM Create output directory
if not exist "%OUTPUT_DIR%" mkdir "%OUTPUT_DIR%"

REM Clean and recreate package data directory
echo Preparing package data...
if exist "%PACKAGE_DATA%" rmdir /s /q "%PACKAGE_DATA%"
mkdir "%PACKAGE_DATA%"

REM Copy release build to package data
echo Copying release files...
xcopy "%RELEASE_DIR%\*" "%PACKAGE_DATA%\" /E /I /Q /Y >nul

if !errorlevel! neq 0 (
    echo ERROR: Failed to copy release files.
    goto :END
)

REM Copy icon to package data
if exist "%PROJECT_DIR%\icon.ico" (
    copy /Y "%PROJECT_DIR%\icon.ico" "%PACKAGE_DATA%\" >nul
    echo Copied application icon
)

REM Count files copied
for /f %%a in ('dir /b /a-d "%PACKAGE_DATA%" 2^>nul ^| find /c /v ""') do set FILE_COUNT=%%a
echo Copied files to package data directory [%FILE_COUNT% files]
echo.

REM Create the installer
echo ========================================
echo   Creating Installer...
echo ========================================
echo.

set "INSTALLER_NAME=S3rp3nt_Media_Setup"
set "INSTALLER_PATH=%OUTPUT_DIR%\%INSTALLER_NAME%.exe"

REM Remove old installer if exists
if exist "%INSTALLER_PATH%" del /q "%INSTALLER_PATH%"

"%BINARYCREATOR%" -c "%INSTALLER_DIR%\config\config.xml" -p "%INSTALLER_DIR%\packages" "%INSTALLER_PATH%" --offline-only

if !errorlevel! neq 0 (
    echo.
    echo ERROR: Failed to create installer.
    goto :END
)

echo.
echo ========================================
echo   Installer Created Successfully!
echo ========================================
echo.
echo Installer location:
echo   %INSTALLER_PATH%
echo.

REM Show file size
for %%A in ("%INSTALLER_PATH%") do (
    set "SIZE=%%~zA"
    set /a "SIZE_MB=!SIZE! / 1048576"
    echo Installer size: !SIZE_MB! MB
)
echo.

:END
echo.
pause
endlocal

