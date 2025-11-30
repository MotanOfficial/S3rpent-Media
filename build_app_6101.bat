@echo off
setlocal

set "QT_ENV=C:\Qt\6.10.1\mingw_64\bin\qtenv2.bat"
set "CMAKE_CMD=C:\Qt\Tools\CMake_64\bin\cmake.exe"
set "PROJECT_DIR=C:\Users\Motan\Documents\s3rp3nt_media"
set "BUILD_DIR=C:/Users/Motan/Documents/s3rp3nt_media/build/Desktop_Qt_6_10_1_MinGW_64_bit-Debug"
set "DEPLOY_DIR=%BUILD_DIR%"
set "BINARY=%BUILD_DIR%\apps3rp3nt_media.exe"
set "WINDEPLOYQT=C:\Qt\6.10.1\mingw_64\bin\windeployqt.exe"

echo Setting up environment for Qt 6.10.1...
if exist "%QT_ENV%" (
    call "%QT_ENV%"
) else (
    echo Warning: Could not find %QT_ENV% to set up the Qt environment.
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
    echo Configuring project with CMake...
    "%CMAKE_CMD%" -S "%PROJECT_DIR%" -B "%BUILD_DIR%" -G "MinGW Makefiles" -DCMAKE_BUILD_TYPE=Debug -DCMAKE_PREFIX_PATH="C:/Qt/6.10.1/mingw_64"
    if %errorlevel% neq 0 (
        echo CMake configuration failed.
        goto :END
    )
)

echo.
echo Building Qt project with Qt 6.10.1...
"%CMAKE_CMD%" --build "%BUILD_DIR%" --target all

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
)

:END
echo.
pause
endlocal


