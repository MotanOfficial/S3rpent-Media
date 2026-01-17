# libmpv Setup Guide for Windows

## Installation Steps

### 1. Download libmpv (Recommended Sources)

**🥇 Best Option: GitHub Releases (includes dev files)**

1. **shinchiro builds** (Recommended):
   - Visit: https://github.com/shinchiro/mpv-winbuild-cmake/releases
   - Download the latest `mpv-dev-x86_64-*.7z` or `mpv-dev-x86_64-*.zip` file
   - These builds include all development files (headers, libs, DLLs)

2. **zhongfly builds** (Alternative):
   - Visit: https://github.com/zhongfly/mpv-winbuild/releases
   - Download the latest `mpv-dev-x86_64-*.7z` or `mpv-dev-x86_64-*.zip` file

3. **First-party CI builds** (Latest commit, may be unstable):
   - Visit: https://nightly.link/mpv-player/mpv/workflows/build/master
   - Download the Windows build artifact

**🥈 Alternative: Package Managers**

- **Scoop**: `scoop install mpv` (may need to extract dev files separately)
- **Chocolatey**: `choco install mpvio` (may need to extract dev files separately)

**🥉 Legacy: SourceForge**

- Visit: https://sourceforge.net/projects/mpv-player-windows/files/libmpv/
- Download the latest `mpv-dev-x86_64-YYYYMMDD.7z` file

### 2. Install to Standard Location

Extract the contents to `C:\mpv\` so you have:
```
C:\mpv\
├── include\
│   └── mpv\
│       ├── client.h
│       ├── render_gl.h
│       └── ...
├── lib\
│   ├── mpv-2.dll
│   └── mpv.lib (or mpv-2.lib)
└── bin\
    └── mpv-2.dll (copy of DLL)
```

### 3. Set Environment Variable (Optional but Recommended)

Set the `MPV_DIR` environment variable to point to the installation:

**PowerShell (Current Session):**
```powershell
$env:MPV_DIR = "C:\mpv"
[System.Environment]::SetEnvironmentVariable("MPV_DIR", "C:\mpv", "User")
```

**Or manually:**
1. Open System Properties → Environment Variables
2. Add new User variable:
   - Name: `MPV_DIR`
   - Value: `C:\mpv`

### 4. Verify Installation

After installation, CMake should automatically detect libmpv when you rebuild the project.

Check the CMake output for:
```
✅ libmpv found manually - HDR video playback enabled
  Include: C:\mpv\include
  Libraries: C:\mpv\lib\mpv.lib
```

### 5. Copy DLL to Build Directory

After building, copy `mpv-2.dll` from `C:\mpv\lib\` to your build output directory:
- `build/Desktop_Qt_6_10_1_MSVC_64_bit-FastDebug/RelWithDebInfo/`

Or add `C:\mpv\lib` to your system PATH.

## Alternative: Manual CMake Configuration

If CMake doesn't auto-detect, you can manually specify the paths in CMakeLists.txt or via CMake GUI:

```cmake
set(LIBMPV_INCLUDE_DIR "C:/mpv/include")
set(LIBMPV_LIBRARIES "C:/mpv/lib/mpv.lib")
set(LIBMPV_FOUND TRUE)
```

## Troubleshooting

### CMake can't find libmpv
- Verify `C:\mpv\include\mpv\client.h` exists
- Verify `C:\mpv\lib\mpv.lib` (or `mpv-2.lib`) exists
- Set `MPV_DIR` environment variable
- Manually set paths in CMakeLists.txt

### Runtime Error: "mpv-2.dll not found"
- Copy `mpv-2.dll` to your build output directory
- Or add `C:\mpv\lib` to system PATH
- Or place DLL next to your executable

### Linker Errors
- Ensure you're using the correct architecture (x64 for 64-bit builds)
- Verify the `.lib` file matches your compiler (MSVC vs MinGW)

## Notes

- libmpv is not available via vcpkg on Windows
- Precompiled builds are provided by the mpv project
- The DLL must be accessible at runtime (PATH or same directory as executable)

