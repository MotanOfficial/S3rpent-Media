# 🎬 s3rpent media

A modern, feature-rich media viewer built with Qt 6, designed to provide a beautiful and immersive experience for viewing images, videos, audio files, documents, and more.

![Qt Version](https://img.shields.io/badge/Qt-6.8%2B-blue)
![Platform](https://img.shields.io/badge/Platform-Windows-lightgrey)
![License](https://img.shields.io/badge/License-GPL%20v3-blue)

## ✨ Features

### 🖼️ Universal Media Support

**Images**
- PNG, JPG, JPEG, BMP, GIF, WebP
- Animated GIF support with frame navigation
- Zoom, pan, and smooth navigation
- High-quality image rendering

**Videos**
- MP4, AVI, MOV, MKV, WebM, M4V, FLV, WMV, MPG, MPEG, 3GP
- Hardware-accelerated playback via Windows Media Foundation
- Full playback controls (play, pause, seek, volume)
- Resolution and codec information display

**Audio**
- MP3, WAV, FLAC, OGG, AAC, M4A, WMA, Opus, MP2, MP1, AMR
- Real-time audio visualizer with frequency analysis
- Beta: Real-time audio equalizer (10-band EQ)
- Automatic lyrics fetching from LRC Lib
- Lyrics translation support (via RapidAPI)
- Cover art extraction and display
- WASAPI loopback audio capture for visualizer

**Documents**
- PDF viewer with page navigation and zoom
- Text files with syntax highlighting
- Markdown rendering with full formatting
- Code files with language-specific highlighting
  - Web: HTML, CSS, JavaScript, TypeScript, Vue, Svelte, JSON
  - C/C++/Qt: C, C++, Headers, QML, QRC, PRO, PRI, UI
  - Python: .py, .pyw, .pyx, .pyi
  - Java/Kotlin: Java, Kotlin, Gradle
  - Other: Rust, Go, Ruby, PHP, Swift, C#, F#, Scala, Lua, Perl, R, Dart, Shell scripts, SQL
  - Config: INI, YAML, TOML, XML, Properties

### 🎨 Dynamic Visual Effects

**Dynamic Coloring**
- Automatically extracts dominant colors from media
- Adapts interface colors to match the current media
- Creates a cohesive, immersive viewing experience

**Background Effects** (requires dynamic coloring)
- **Gradient Background**: Spotify-style multi-color gradient extracted from cover art
- **Blurred Backdrop**: Apple Music/YouTube Music-style blurred and darkened background
- **Ambient Animated Gradient**: GPU-accelerated animated gradient with organic motion
- **Snow Effect**: Beautiful procedural shader-based snow effect with 6-arm snowflake SDF shapes, 3D rotation, and ground splashes

### 🎵 Advanced Audio Features

**Audio Visualizer**
- Real-time frequency spectrum analysis
- FFT-based frequency band visualization
- Bass amplitude detection
- Multiple visualization modes
- Windows WASAPI loopback support

**Lyrics Integration**
- Automatic lyrics fetching from [LRC Lib](https://lrclib.net)
- Synchronized lyrics display with current playback position
- Lyrics translation support (via RapidAPI)
- Local caching to minimize API requests
- Support for multiple target languages

**Audio Processing** (Beta)
- Real-time 10-band equalizer
- Custom audio processor with optimized performance
- Low-latency audio processing pipeline

### 🌍 Internationalization

- **English** (default)
- **Romanian** (Română)
- Full UI translation support
- Metadata labels translation
- Easy language switching in settings

### ⚙️ Settings & Customization

- File association management (set as default viewer)
- Appearance customization
- Audio processing options
- Lyrics translation configuration
- Language selection
- Persistent settings storage

### 📊 Metadata Display

Comprehensive metadata popup showing:
- File information (name, path, format, type)
- Media-specific metadata (duration, resolution, codec, bitrate)
- Audio metadata (title, artist, album, genre, year)
- Video metadata (frame rate, codec, tracks)
- Document metadata (pages, dimensions, status)

### 🎯 User Experience

- Drag & drop file support
- Keyboard shortcuts (Ctrl+O to open)
- System tray integration
- Single instance management
- Custom title bar with window controls
- Smooth animations and transitions
- Responsive UI design

## 🚀 Getting Started

### Prerequisites

- **Qt 6.8+** with the following components:
  - Qt Quick
  - Qt Quick Controls 2
  - Qt Multimedia
  - Qt Network
  - Qt Widgets
  - Qt ShaderTools
  - Qt LinguistTools
  - Qt PDF (optional, for PDF support)

- **CMake 3.16+**
- **C++17 compatible compiler**
- **FFmpeg** (in PATH, for audio decoding with HE-AAC support)

### Building from Source

1. **Clone the repository**
   ```bash
   git clone https://github.com/MotanOfficial/s3rpent_media.git
   cd s3rpent_media
   ```

2. **Configure with CMake**
   ```bash
   mkdir build
   cd build
   cmake .. -DCMAKE_PREFIX_PATH=/path/to/qt6
   ```

3. **Build**
   ```bash
   cmake --build . --config Release
   ```

4. **Run**
   ```bash
   ./apps3rpent_media
   ```

### Windows Build Scripts

The repository includes convenient build scripts:
- `build_app.bat` - Standard build
- `build_release.bat` - Release build
- `build_installer.bat` - Create installer package

## 📦 Installation

### Windows Installer

Download the latest installer from the [Releases](https://github.com/MotanOfficial/s3rpent_media/releases) page and run `S3rpent_Media_Setup.exe`.

### Manual Installation

1. Extract the application files to your desired location
2. Run `apps3rpent_media.exe`
3. (Optional) Set as default viewer via Settings → File Associations

## 🎮 Usage

### Opening Files

- **Drag & Drop**: Drag any supported file onto the window
- **File Dialog**: Press `Ctrl+O` or use the "Browse files" button
- **Command Line**: `apps3rpent_media.exe "path/to/file"`

### Controls

**Images**
- Mouse wheel: Zoom in/out
- Click & drag: Pan
- Double-click: Reset zoom

**Videos**
- Space: Play/Pause
- Arrow keys: Seek backward/forward
- Mouse wheel: Volume control
- Right-click: Context menu

**Audio**
- Space: Play/Pause
- Arrow keys: Seek backward/forward
- Mouse wheel: Volume control
- Click on visualizer: Toggle visualization modes

**PDFs**
- Mouse wheel: Scroll pages
- Ctrl + Mouse wheel: Zoom
- Arrow keys: Navigate pages

### Settings

Access settings via the gear icon in the title bar or press `Ctrl+,` (if implemented).

**Appearance**
- Toggle dynamic coloring
- Enable/disable background effects
- Adjust snow effect intensity

**Audio**
- Enable/disable beta audio processing
- Configure equalizer settings

**Lyrics**
- Enable lyrics translation
- Set RapidAPI key
- Select target language

**Language**
- Switch between English and Romanian

## 🛠️ Technical Details

### Architecture

- **Framework**: Qt 6.8+ (QML/C++)
- **Graphics**: OpenGL/GLSL shaders for effects
- **Audio**: Qt Multimedia + Custom audio processor
- **Video**: Windows Media Foundation (WMF)
- **PDF**: Qt PDF (optional)

### Performance

- GPU-accelerated shader effects
- Optimized audio processing pipeline
- Efficient memory management
- Lazy loading for large files

### Dependencies

- Qt 6.8+ (Quick, Multimedia, Network, Widgets, ShaderTools, LinguistTools)
- CMake 3.16+
- FFmpeg (for audio decoding)
- Windows SDK (for WMF video support)

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## 📝 License

This project is licensed under the GNU General Public License v3.0 (GPL v3) - see the [LICENSE](LICENSE) file for details.

**Important**: This is a copyleft license. If you modify or distribute this software, you must also license your changes under GPL v3 and make the source code available to users.

## 🙏 Acknowledgments

- [Qt Project](https://www.qt.io/) - Amazing cross-platform framework
- [LRC Lib](https://lrclib.net) - Lyrics database
- [qlementine-icons](https://github.com/oclero/qlementine-icons) - Beautiful icon set
- [RapidAPI](https://rapidapi.com) - Translation API service

## 📧 Contact

For issues, questions, or suggestions, please open an issue on GitHub.

---

**Made with ❤️ using Qt 6**

