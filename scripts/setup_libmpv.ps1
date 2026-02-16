# libmpv Setup Script for Windows
# This script helps set up libmpv for the s3rpent_media project

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "libmpv Setup Script" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$mpvDir = "C:\mpv"

# Check if libmpv is already installed
if (Test-Path "$mpvDir\include\mpv\client.h") {
    Write-Host "✅ libmpv appears to be already installed at $mpvDir" -ForegroundColor Green
    Write-Host ""
    Write-Host "Include directory: $mpvDir\include" -ForegroundColor Yellow
    Write-Host "Library directory: $mpvDir\lib" -ForegroundColor Yellow
    
    # Check for DLL
    $dllPath = Get-ChildItem -Path "$mpvDir\lib" -Filter "*.dll" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($dllPath) {
        Write-Host "✅ Found DLL: $($dllPath.FullName)" -ForegroundColor Green
    } else {
        Write-Host "⚠️  Warning: No DLL found in $mpvDir\lib" -ForegroundColor Yellow
    }
    
    # Check for LIB
    $libPath = Get-ChildItem -Path "$mpvDir\lib" -Filter "*.lib" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($libPath) {
        Write-Host "✅ Found LIB: $($libPath.FullName)" -ForegroundColor Green
    } else {
        Write-Host "⚠️  Warning: No LIB file found in $mpvDir\lib" -ForegroundColor Yellow
    }
    
    Write-Host ""
    Write-Host "If libmpv is properly installed, CMake should detect it automatically." -ForegroundColor Cyan
    Write-Host "Rebuild your project to verify." -ForegroundColor Cyan
    exit 0
}

Write-Host "libmpv is not installed yet." -ForegroundColor Yellow
Write-Host ""
Write-Host "📥 Recommended Download Sources (in order of preference):" -ForegroundColor Cyan
Write-Host ""
Write-Host "1. 🥇 GitHub Releases (Recommended - includes dev files):" -ForegroundColor Green
Write-Host "   • shinchiro builds: https://github.com/shinchiro/mpv-winbuild-cmake/releases" -ForegroundColor White
Write-Host "   • zhongfly builds: https://github.com/zhongfly/mpv-winbuild/releases" -ForegroundColor White
Write-Host "   Look for: mpv-dev-x86_64-*.7z or mpv-dev-x86_64-*.zip" -ForegroundColor Gray
Write-Host ""
Write-Host "2. 🥈 First-party CI builds (latest commit):" -ForegroundColor Yellow
Write-Host "   https://nightly.link/mpv-player/mpv/workflows/build/master" -ForegroundColor White
Write-Host ""
Write-Host "3. 🥉 Package Managers:" -ForegroundColor Yellow
Write-Host "   • Scoop: scoop install mpv" -ForegroundColor White
Write-Host "   • Chocolatey: choco install mpvio" -ForegroundColor White
Write-Host "   (Note: May need to extract dev files separately)" -ForegroundColor Gray
Write-Host ""
Write-Host "4. Legacy SourceForge:" -ForegroundColor Yellow
Write-Host "   https://sourceforge.net/projects/mpv-player-windows/files/libmpv/" -ForegroundColor White
Write-Host ""

# Create directory if it doesn't exist
if (-not (Test-Path $mpvDir)) {
    Write-Host "Creating directory: $mpvDir" -ForegroundColor Yellow
    New-Item -ItemType Directory -Path $mpvDir | Out-Null
    Write-Host "✅ Directory created" -ForegroundColor Green
}

Write-Host "Expected structure after extraction:" -ForegroundColor Cyan
Write-Host "  $mpvDir\" -ForegroundColor Gray
Write-Host "  ├── include\" -ForegroundColor Gray
Write-Host "  │   └── mpv\" -ForegroundColor Gray
Write-Host "  │       ├── client.h" -ForegroundColor Gray
Write-Host "  │       ├── render_gl.h" -ForegroundColor Gray
Write-Host "  │       └── qthelper.hpp" -ForegroundColor Gray
Write-Host "  └── lib\" -ForegroundColor Gray
Write-Host "      ├── mpv-2.dll (or mpv.dll)" -ForegroundColor Gray
Write-Host "      └── mpv.lib (or mpv-2.lib)" -ForegroundColor Gray
Write-Host ""

# Check if user has downloaded and extracted
Write-Host "Have you already downloaded and extracted libmpv to $mpvDir? (Y/N)" -ForegroundColor Cyan
$response = Read-Host

if ($response -eq "Y" -or $response -eq "y") {
    # Verify installation
    if (Test-Path "$mpvDir\include\mpv\client.h") {
        Write-Host "✅ libmpv installation verified!" -ForegroundColor Green
        
        # Check for required files
        $hasClientH = Test-Path "$mpvDir\include\mpv\client.h"
        $hasRenderGlH = Test-Path "$mpvDir\include\mpv\render_gl.h"
        $hasDll = (Get-ChildItem -Path "$mpvDir\lib" -Filter "*.dll" -ErrorAction SilentlyContinue).Count -gt 0
        $hasLib = (Get-ChildItem -Path "$mpvDir\lib" -Filter "*.lib" -ErrorAction SilentlyContinue).Count -gt 0
        
        Write-Host ""
        Write-Host "File check:" -ForegroundColor Cyan
        Write-Host "  client.h: $(if ($hasClientH) { '✅' } else { '❌' })" -ForegroundColor $(if ($hasClientH) { 'Green' } else { 'Red' })
        Write-Host "  render_gl.h: $(if ($hasRenderGlH) { '✅' } else { '❌' })" -ForegroundColor $(if ($hasRenderGlH) { 'Green' } else { 'Red' })
        Write-Host "  DLL: $(if ($hasDll) { '✅' } else { '❌' })" -ForegroundColor $(if ($hasDll) { 'Green' } else { 'Red' })
        Write-Host "  LIB: $(if ($hasLib) { '✅' } else { '❌' })" -ForegroundColor $(if ($hasLib) { 'Green' } else { 'Red' })
        
        if ($hasClientH -and $hasDll -and $hasLib) {
            # Set environment variable
            Write-Host ""
            Write-Host "Setting MPV_DIR environment variable..." -ForegroundColor Yellow
            [System.Environment]::SetEnvironmentVariable("MPV_DIR", $mpvDir, "User")
            $env:MPV_DIR = $mpvDir
            Write-Host "✅ MPV_DIR set to: $mpvDir" -ForegroundColor Green
            
            Write-Host ""
            Write-Host "✅ Setup complete!" -ForegroundColor Green
            Write-Host ""
            Write-Host "Next steps:" -ForegroundColor Cyan
            Write-Host "1. Rebuild your project with CMake" -ForegroundColor White
            Write-Host "2. Copy the DLL to your build output directory:" -ForegroundColor White
            $dllFiles = Get-ChildItem -Path "$mpvDir\lib" -Filter "*.dll" -ErrorAction SilentlyContinue
            if ($dllFiles) {
                Write-Host "   Copy: $($dllFiles[0].FullName)" -ForegroundColor Gray
                Write-Host "   To: build/Desktop_Qt_6_10_1_MSVC_64_bit-FastDebug/RelWithDebInfo/" -ForegroundColor Gray
            }
            Write-Host "   (or add $mpvDir\lib to your system PATH)" -ForegroundColor White
        } else {
            Write-Host ""
            Write-Host "⚠️  Some required files are missing. Please check the extraction." -ForegroundColor Yellow
        }
    } else {
        Write-Host "❌ Installation not found. Please extract libmpv to $mpvDir" -ForegroundColor Red
        Write-Host "   Expected: $mpvDir\include\mpv\client.h" -ForegroundColor Red
    }
} else {
    Write-Host ""
    Write-Host "Please download libmpv from one of the sources above, then run this script again." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Quick links:" -ForegroundColor Cyan
    Write-Host "  • shinchiro: https://github.com/shinchiro/mpv-winbuild-cmake/releases" -ForegroundColor White
    Write-Host "  • zhongfly: https://github.com/zhongfly/mpv-winbuild/releases" -ForegroundColor White
}

Write-Host ""
Write-Host "Press any key to exit..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
