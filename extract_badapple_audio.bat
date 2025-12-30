@echo off
REM Extract audio from BadApple.mp4 to badapple_audio.mp3 at 20%% quality
REM Requires FFmpeg to be in PATH

if not exist "BadApple.mp4" (
    echo Error: BadApple.mp4 not found in current directory
    echo Please place BadApple.mp4 in the same folder as this script
    pause
    exit /b 1
)

echo Extracting audio from BadApple.mp4...
ffmpeg -i "BadApple.mp4" -vn -acodec libmp3lame -ab 128k -ar 44100 -ac 2 "badapple_audio.mp3"

if %ERRORLEVEL% EQU 0 (
    echo.
    echo Success! Audio extracted to: badapple_audio.mp3
    echo Place this file in the same directory as the executable.
) else (
    echo.
    echo Error: Audio extraction failed
    echo Make sure FFmpeg is installed and in your PATH
)

pause

