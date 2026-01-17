# FFmpeg Library Setup Guide

This guide explains how to install FFmpeg libraries for **fast subtitle extraction** in s3rp3nt_media.

## Why FFmpeg Libraries?

Using FFmpeg libraries (instead of CLI) provides:
- **100x faster** subtitle extraction (uses container index, no linear scan)
- **No external process** overhead
- **Direct seeking** to subtitle packets
- **Instant extraction** even for 20GB+ files

## Installation Methods

### 🪟 Windows (Recommended: vcpkg)

#### Step 1: Install vcpkg

```bat
git clone https://github.com/microsoft/vcpkg.git
cd vcpkg
.\bootstrap-vcpkg.bat
```

#### Step 2: Install FFmpeg

```bat
.\vcpkg install ffmpeg
```

#### Step 3: Configure CMake with vcpkg

When configuring your CMake build, point to vcpkg:

```bat
cmake -DCMAKE_TOOLCHAIN_FILE=C:/path/to/vcpkg/scripts/buildsystems/vcpkg.cmake ..
```

Or set the environment variable:
```bat
set CMAKE_TOOLCHAIN_FILE=C:/path/to/vcpkg/scripts/buildsystems/vcpkg.cmake
```

**That's it!** CMake will automatically find and link FFmpeg.

---

### 🐧 Linux

#### Debian / Ubuntu

```bash
sudo apt install libavformat-dev libavcodec-dev libavutil-dev
```

#### Fedora

```bash
sudo dnf install ffmpeg-devel
```

#### Arch Linux

```bash
sudo pacman -S ffmpeg
```

CMake will find them automatically via pkg-config.

---

### 🍎 macOS

```bash
brew install ffmpeg
```

CMake will find them automatically via pkg-config.

---

### Manual Installation (All Platforms)

If you have FFmpeg installed manually:

1. Set the `FFMPEG_DIR` environment variable to point to your FFmpeg installation:
   ```bat
   set FFMPEG_DIR=C:/ffmpeg
   ```

2. Or install to standard paths:
   - Windows: `C:/ffmpeg/include` and `C:/ffmpeg/lib`
   - Linux: `/usr/include` and `/usr/lib`
   - macOS: `/usr/local/include` and `/usr/local/lib`

---

## Verifying Installation

After building, check the CMake output:

```
✅ FFmpeg libraries found via vcpkg - fast subtitle extraction enabled
```

If you see:
```
⚠️  FFmpeg libraries not found - will use CLI-based subtitle extraction (slower)
```

Then FFmpeg libraries are not available, and the app will fall back to CLI extraction (slower but still works).

---

## Runtime Deployment (Windows)

If using vcpkg, you need to copy FFmpeg DLLs next to your `.exe`:

Required DLLs:
- `avformat-*.dll`
- `avcodec-*.dll`
- `avutil-*.dll`

Location: `vcpkg/installed/x64-windows/bin/` (or `x86-windows/bin/` for 32-bit)

You can use vcpkg's `vcpkg integrate install` to automatically copy DLLs, or manually copy them.

---

## Performance Comparison

| Method | 20GB File Extraction Time |
|--------|---------------------------|
| FFmpeg CLI | 2+ minutes |
| FFmpeg Libraries | **< 1 second** |

The difference is **dramatic** for large files!

---

## Troubleshooting

### "FFmpeg libraries not found"

1. **Windows**: Make sure vcpkg toolchain is set: `-DCMAKE_TOOLCHAIN_FILE=...`
2. **Linux/macOS**: Install dev packages (not just runtime)
3. **Manual**: Check `FFMPEG_DIR` environment variable

### "Cannot find avformat.h"

- Check include paths in CMake output
- Verify headers are in `include/libavformat/` directory

### Link errors

- Make sure all three libraries are found: `avformat`, `avcodec`, `avutil`
- On Windows, ensure DLLs are in PATH or next to executable

---

## Fallback Behavior

If FFmpeg libraries are **not** found, the app will:
- ✅ Still work perfectly
- ✅ Use CLI-based extraction (slower)
- ✅ Cache results (instant on subsequent loads)

So the app works either way - libraries just make it **much faster**!

