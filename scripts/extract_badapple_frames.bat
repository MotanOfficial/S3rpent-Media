@echo off
REM Extract Bad Apple frames using FFmpeg
REM This creates PNG frames, then you can run the Python script to convert to binary

set VIDEO_FILE=BadApple.mp4
set OUTPUT_DIR=badapple_frames
set FRAME_WIDTH=64
set FRAME_HEIGHT=48

if not exist "%VIDEO_FILE%" (
    echo Error: %VIDEO_FILE% not found!
    pause
    exit /b 1
)

echo Extracting frames from %VIDEO_FILE%...
echo This may take a few minutes...

if not exist "%OUTPUT_DIR%" mkdir "%OUTPUT_DIR%"

ffmpeg -i "%VIDEO_FILE%" -vf scale=%FRAME_WIDTH%:%FRAME_HEIGHT% -frames:v 6572 "%OUTPUT_DIR%\frame_%%04d.png"

if %ERRORLEVEL% EQU 0 (
    echo.
    echo Frame extraction complete!
    echo Frames saved to: %OUTPUT_DIR%\
    echo.
    echo Next step: Run extract_badapple_frames.py to convert to binary format
    echo (Requires Python with PIL/Pillow: pip install Pillow)
) else (
    echo.
    echo Error: FFmpeg extraction failed!
    echo Make sure FFmpeg is installed and in your PATH
)

pause

