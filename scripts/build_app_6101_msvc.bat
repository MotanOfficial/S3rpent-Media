@echo off
setlocal

set "CMAKE_CMD=C:\Qt\Tools\CMake_64\bin\cmake.exe"
set "PROJECT_DIR=C:\Users\Motan\Documents\s3rp3nt_media"
set "BUILD_DIR=C:/Users/Motan/Documents/s3rp3nt_media/build/Desktop_Qt_6_10_1_MSVC_64_bit-Debug"
set "DEPLOY_DIR=%BUILD_DIR%"
set "BINARY=%BUILD_DIR%\apps3rp3nt_media.exe"
set "WINDEPLOYQT=C:\Qt\6.10.1\msvc2022_64\bin\windeployqt.exe"

REM Force Visual Studio 2022 activation - ALWAYS activate, never skip
echo Forcing Visual Studio 2022 with v143 toolset for Qt 6.10.1 compatibility...
set "VS2022_FOUND=0"

REM Try Visual Studio 2022 - prioritize Community edition
if exist "C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat" (
    call "C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat" -arch=x64 -host_arch=x64
    set "VS2022_FOUND=1"
) else if exist "C:\Program Files\Microsoft Visual Studio\2022\Professional\Common7\Tools\VsDevCmd.bat" (
    call "C:\Program Files\Microsoft Visual Studio\2022\Professional\Common7\Tools\VsDevCmd.bat" -arch=x64 -host_arch=x64
    set "VS2022_FOUND=1"
) else if exist "C:\Program Files\Microsoft Visual Studio\2022\Enterprise\Common7\Tools\VsDevCmd.bat" (
    call "C:\Program Files\Microsoft Visual Studio\2022\Enterprise\Common7\Tools\VsDevCmd.bat" -arch=x64 -host_arch=x64
    set "VS2022_FOUND=1"
) else if exist "C:\Program Files\Microsoft Visual Studio\2022\BuildTools\Common7\Tools\VsDevCmd.bat" (
    call "C:\Program Files\Microsoft Visual Studio\2022\BuildTools\Common7\Tools\VsDevCmd.bat" -arch=x64 -host_arch=x64
    set "VS2022_FOUND=1"
) else if exist "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\Common7\Tools\VsDevCmd.bat" (
    call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\Common7\Tools\VsDevCmd.bat" -arch=x64 -host_arch=x64
    set "VS2022_FOUND=1"
)

if "%VS2022_FOUND%"=="0" (
    echo.
    echo ERROR: Could not find Visual Studio 2022 installation.
    echo.
    echo Please install Visual Studio 2022 (Community edition is free)
    echo Download from: https://visualstudio.microsoft.com/downloads/
    echo Make sure to select "Desktop development with C++" during installation
    echo.
    pause
    exit /b 1
)

if errorlevel 1 (
    echo ERROR: Failed to initialize Visual Studio environment
    pause
    exit /b 1
)

echo MSVC environment initialized successfully.
echo Active compiler:
where cl
echo.
echo MSVC version:
cl 2>&1 | findstr /i "Version"

echo Setting up environment for Qt 6.10.1 with MSVC...
if exist "C:\Qt\6.10.1\msvc2022_64\bin\qtenv2.bat" (
    call "C:\Qt\6.10.1\msvc2022_64\bin\qtenv2.bat"
) else (
    echo Warning: Could not find Qt 6.10.1 MSVC environment script.
    echo Make sure Qt 6.10.1 MSVC version is installed.
)

REM Check for --clean argument
if "%1"=="--clean" (
    echo Cleaning build directory...
    if exist "%BUILD_DIR%" rmdir /s /q "%BUILD_DIR%"
)

REM Create build directory if it doesn't exist
if not exist "%BUILD_DIR%" (
    echo Creating build directory...
    mkdir "%BUILD_DIR%"
)

REM Configure with CMake if not already configured
if not exist "%BUILD_DIR%\CMakeCache.txt" (
    echo Configuring project with CMake (MSVC)...
    echo Using Visual Studio 17 2022 generator with v143 toolset for Qt 6.10.1 compatibility...
    "%CMAKE_CMD%" -S "%PROJECT_DIR%" -B "%BUILD_DIR%" -G "Visual Studio 17 2022" -A x64 -T v143 -DCMAKE_BUILD_TYPE=Debug -DCMAKE_PREFIX_PATH="C:/Qt/6.10.1/msvc2022_64"
    if %errorlevel% neq 0 (
        echo CMake configuration failed.
        goto :END
    )
)

echo.
echo Building Qt project with Qt 6.10.1 (MSVC)...
"%CMAKE_CMD%" --build "%BUILD_DIR%" --config Debug --target all

if %errorlevel% neq 0 (
    echo Build failed.
) else (
    echo Build succeeded.
    echo Running windeployqt...
    if not exist "%WINDEPLOYQT%" (
        echo Error: windeployqt.exe not found at %WINDEPLOYQT%.
        goto :END
    )
    if not exist "%BINARY%" (
        echo Error: Built binary not found at %BINARY%.
        goto :END
    )
    "%WINDEPLOYQT%" --qmldir "%PROJECT_DIR%" "%BINARY%"
    if %errorlevel% neq 0 (
        echo Deployment failed.
        goto :END
    )
    echo Deployment succeeded.
    echo.
    echo Full Windows Media Session integration is now enabled!
    echo - Custom metadata (title, artist, album, cover art) will be available
    echo - Keyboard play/pause controls will work
    echo - Windows apps like Wallpaper Engine can access the metadata
)

:END
echo.
pause
endlocal

