cmake_minimum_required(VERSION 3.16)



project(s3rpent_media VERSION 0.1 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 REQUIRED COMPONENTS Quick QuickControls2 Multimedia Network Widgets OpenGLWidgets ShaderTools LinguistTools Concurrent Gui GuiPrivate)
find_package(Qt6 QUIET COMPONENTS Pdf PdfQuick)
find_package(Qt6 QUIET COMPONENTS Quick3D Quick3DAssetUtils)
find_package(LibArchive CONFIG QUIET)
if(NOT LibArchive_FOUND)
    find_package(LibArchive QUIET)
endif()

# Note: FFmpeg is used via QProcess (subprocess) for audio decoding
# This handles HE-AAC correctly by ignoring broken MP4 timestamps
# FFmpeg executable must be in PATH
#
# For subtitle extraction, we use FFmpeg libraries (libavformat/libavcodec) for fast extraction
# If FFmpeg libraries are not found, the code will fall back to CLI-based extraction

# Try to find FFmpeg libraries (optional - for fast subtitle extraction and D3D11VA video decoding)
# Priority: 1. Custom build in project root (best for D3D11VA), 2. vcpkg package, 3. pkg-config (Linux/macOS), 4. Manual find (fallback)

set(FFMPEG_FOUND FALSE)

# Method 1: Try custom FFmpeg build in project root (highest priority - has proper D3D11VA support)
set(CUSTOM_FFMPEG_DIR "${CMAKE_SOURCE_DIR}/ffmpeg")
if(EXISTS "${CUSTOM_FFMPEG_DIR}/include/libavformat/avformat.h" AND EXISTS "${CUSTOM_FFMPEG_DIR}/lib/avformat.lib")
    set(FFMPEG_FOUND TRUE)
    set(FFMPEG_INCLUDE_DIR "${CUSTOM_FFMPEG_DIR}/include")
    set(FFMPEG_AVFORMAT_LIB "${CUSTOM_FFMPEG_DIR}/lib/avformat.lib")
    set(FFMPEG_AVCODEC_LIB "${CUSTOM_FFMPEG_DIR}/lib/avcodec.lib")
    set(FFMPEG_AVUTIL_LIB "${CUSTOM_FFMPEG_DIR}/lib/avutil.lib")
    set(FFMPEG_SWRESAMPLE_LIB "${CUSTOM_FFMPEG_DIR}/lib/swresample.lib")
    set(FFMPEG_SWSCALE_LIB "${CUSTOM_FFMPEG_DIR}/lib/swscale.lib")
    set(FFMPEG_AVFILTER_LIB "${CUSTOM_FFMPEG_DIR}/lib/avfilter.lib")
    set(FFMPEG_BIN_DIR "${CUSTOM_FFMPEG_DIR}/bin")
    message(STATUS "✅ FFmpeg libraries found via custom build - D3D11VA video decoding enabled")
    message(STATUS "  Using custom FFmpeg build from: ${CUSTOM_FFMPEG_DIR}")
    message(STATUS "  Include: ${FFMPEG_INCLUDE_DIR}")
    message(STATUS "  Libraries: ${FFMPEG_AVFORMAT_LIB} ${FFMPEG_AVCODEC_LIB} ${FFMPEG_AVUTIL_LIB} ${FFMPEG_SWRESAMPLE_LIB} ${FFMPEG_SWSCALE_LIB} ${FFMPEG_AVFILTER_LIB}")
else()
    # Method 2: Try vcpkg's FFmpeg package (fallback)
    find_package(FFMPEG QUIET)
    if(FFMPEG_FOUND)
        # vcpkg's FFMPEG package provides FFMPEG_INCLUDE_DIRS and FFMPEG_LIBRARIES
        if(DEFINED FFMPEG_INCLUDE_DIRS)
            set(FFMPEG_INCLUDE_DIR ${FFMPEG_INCLUDE_DIRS})
        endif()
        message(STATUS "✅ FFmpeg libraries found via vcpkg - fast subtitle extraction enabled")
        message(STATUS "  Using: FFMPEG::avformat, FFMPEG::avcodec, FFMPEG::avutil")
        message(STATUS "  ⚠️  Note: vcpkg FFmpeg may not have proper D3D11VA support")
        if(FFMPEG_INCLUDE_DIR)
            message(STATUS "  Include dir: ${FFMPEG_INCLUDE_DIR}")
        endif()
    else()
        # Method 3: Try pkg-config (Linux/macOS)
        find_package(PkgConfig QUIET)
        if(PKG_CONFIG_FOUND)
            pkg_check_modules(FFMPEG_PKG QUIET libavformat libavcodec libavutil)
            if(FFMPEG_PKG_FOUND)
                set(FFMPEG_FOUND TRUE)
                set(FFMPEG_INCLUDE_DIR ${FFMPEG_PKG_INCLUDE_DIRS})
                set(FFMPEG_AVFORMAT_LIB ${FFMPEG_PKG_LIBRARIES})
                set(FFMPEG_AVCODEC_LIB ${FFMPEG_PKG_LIBRARIES})
                set(FFMPEG_AVUTIL_LIB ${FFMPEG_PKG_LIBRARIES})
                message(STATUS "✅ FFmpeg libraries found via pkg-config - fast subtitle extraction enabled")
                message(STATUS "  Include: ${FFMPEG_INCLUDE_DIR}")
            endif()
        endif()
        
        # Method 4: Manual find (fallback)
        if(NOT FFMPEG_FOUND)
            find_path(FFMPEG_INCLUDE_DIR
                NAMES libavformat/avformat.h libavcodec/avcodec.h
                PATHS
                    /usr/include
                    /usr/local/include
                    "C:/ffmpeg/include"
                    "$ENV{FFMPEG_DIR}/include"
                    "$ENV{VCPKG_ROOT}/installed/x64-windows/include"
                    "$ENV{VCPKG_ROOT}/installed/x86-windows/include"
            )
            
            find_library(FFMPEG_AVFORMAT_LIB
                NAMES avformat
                PATHS
                    /usr/lib
                    /usr/local/lib
                    "C:/ffmpeg/lib"
                    "$ENV{FFMPEG_DIR}/lib"
                    "$ENV{VCPKG_ROOT}/installed/x64-windows/lib"
                    "$ENV{VCPKG_ROOT}/installed/x86-windows/lib"
            )
            
            find_library(FFMPEG_AVCODEC_LIB
                NAMES avcodec
                PATHS
                    /usr/lib
                    /usr/local/lib
                    "C:/ffmpeg/lib"
                    "$ENV{FFMPEG_DIR}/lib"
                    "$ENV{VCPKG_ROOT}/installed/x64-windows/lib"
                    "$ENV{VCPKG_ROOT}/installed/x86-windows/lib"
            )
            
            find_library(FFMPEG_AVUTIL_LIB
                NAMES avutil
                PATHS
                    /usr/lib
                    /usr/local/lib
                    "C:/ffmpeg/lib"
                    "$ENV{FFMPEG_DIR}/lib"
                    "$ENV{VCPKG_ROOT}/installed/x64-windows/lib"
                    "$ENV{VCPKG_ROOT}/installed/x86-windows/lib"
            )
            
            find_library(FFMPEG_SWRESAMPLE_LIB
                NAMES swresample
                PATHS
                    /usr/lib
                    /usr/local/lib
                    "C:/ffmpeg/lib"
                    "${CUSTOM_FFMPEG_DIR}/lib"
                    "$ENV{FFMPEG_DIR}/lib"
                    "$ENV{VCPKG_ROOT}/installed/x64-windows/lib"
                    "$ENV{VCPKG_ROOT}/installed/x86-windows/lib"
            )
            
            find_library(FFMPEG_SWSCALE_LIB
                NAMES swscale
                PATHS
                    /usr/lib
                    /usr/local/lib
                    "C:/ffmpeg/lib"
                    "${CUSTOM_FFMPEG_DIR}/lib"
                    "$ENV{FFMPEG_DIR}/lib"
                    "$ENV{VCPKG_ROOT}/installed/x64-windows/lib"
                    "$ENV{VCPKG_ROOT}/installed/x86-windows/lib"
            )
            
            find_library(FFMPEG_AVFILTER_LIB
                NAMES avfilter
                PATHS
                    /usr/lib
                    /usr/local/lib
                    "C:/ffmpeg/lib"
                    "${CUSTOM_FFMPEG_DIR}/lib"
                    "$ENV{FFMPEG_DIR}/lib"
                    "$ENV{VCPKG_ROOT}/installed/x64-windows/lib"
                    "$ENV{VCPKG_ROOT}/installed/x86-windows/lib"
            )
            
            if(FFMPEG_INCLUDE_DIR AND FFMPEG_AVFORMAT_LIB AND FFMPEG_AVCODEC_LIB AND FFMPEG_AVUTIL_LIB AND FFMPEG_SWRESAMPLE_LIB AND FFMPEG_SWSCALE_LIB AND FFMPEG_AVFILTER_LIB)
                set(FFMPEG_FOUND TRUE)
                message(STATUS "✅ FFmpeg libraries found manually - fast subtitle extraction enabled")
                message(STATUS "  Include: ${FFMPEG_INCLUDE_DIR}")
                message(STATUS "  Libraries: ${FFMPEG_AVFORMAT_LIB} ${FFMPEG_AVCODEC_LIB} ${FFMPEG_AVUTIL_LIB} ${FFMPEG_SWRESAMPLE_LIB} ${FFMPEG_SWSCALE_LIB} ${FFMPEG_AVFILTER_LIB}")
            endif()
        endif()
        
        if(NOT FFMPEG_FOUND)
            message(STATUS "⚠️  FFmpeg libraries not found - will use CLI-based subtitle extraction (slower)")
            message(STATUS "")
            message(STATUS "  To enable FAST subtitle extraction and D3D11VA video decoding:")
            message(STATUS "  • Use custom FFmpeg build in project root: ffmpeg/")
            message(STATUS "  • Windows: Install via vcpkg: vcpkg install ffmpeg")
            message(STATUS "  • Linux:   sudo apt install libavformat-dev libavcodec-dev libavutil-dev")
            message(STATUS "  • macOS:   brew install ffmpeg")
            message(STATUS "  • Manual:  Set FFMPEG_DIR environment variable or install to standard paths")
        endif()
    endif()
endif()

# Try to find libmpv (optional - for HDR video playback)
set(LIBMPV_FOUND FALSE)

# Method 1: Try pkg-config (Linux/macOS)
find_package(PkgConfig QUIET)
if(PKG_CONFIG_FOUND)
    pkg_check_modules(LIBMPV_PKG QUIET mpv)
    if(LIBMPV_PKG_FOUND)
        set(LIBMPV_FOUND TRUE)
        set(LIBMPV_INCLUDE_DIR ${LIBMPV_PKG_INCLUDE_DIRS})
        set(LIBMPV_LIBRARIES ${LIBMPV_PKG_LIBRARIES})
        message(STATUS "✅ libmpv found via pkg-config - HDR video playback enabled")
        message(STATUS "  Include: ${LIBMPV_INCLUDE_DIR}")
        message(STATUS "  Libraries: ${LIBMPV_LIBRARIES}")
    endif()
endif()

# Method 2: Manual find (fallback)
if(NOT LIBMPV_FOUND)
    find_path(LIBMPV_INCLUDE_DIR
        NAMES mpv/client.h
        PATHS
            /usr/include
            /usr/local/include
            "C:/mpv/include"
            "C:/Program Files/mpv/include"
            "$ENV{MPV_DIR}/include"
            "$ENV{VCPKG_ROOT}/installed/x64-windows/include"
            "$ENV{VCPKG_ROOT}/installed/x64-windows-static/include"
    )
    
    find_library(LIBMPV_LIBRARIES
        NAMES mpv mpv-2 mpv2 libmpv libmpv-2
        PATHS
            /usr/lib
            /usr/local/lib
            "C:/mpv/lib"
            "C:/mpv"
            "C:/Program Files/mpv/lib"
            "$ENV{MPV_DIR}/lib"
            "$ENV{MPV_DIR}"
            "$ENV{VCPKG_ROOT}/installed/x64-windows/lib"
            "$ENV{VCPKG_ROOT}/installed/x64-windows-static/lib"
    )
    
    # If .lib not found, try the generated one
    if(NOT LIBMPV_LIBRARIES AND EXISTS "C:/mpv/lib/libmpv-2.lib")
        set(LIBMPV_LIBRARIES "C:/mpv/lib/libmpv-2.lib")
        message(STATUS "  Using generated import library")
    endif()
    
    if(LIBMPV_INCLUDE_DIR AND LIBMPV_LIBRARIES)
        set(LIBMPV_FOUND TRUE)
        message(STATUS "✅ libmpv found manually - HDR video playback enabled")
        message(STATUS "  Include: ${LIBMPV_INCLUDE_DIR}")
        message(STATUS "  Libraries: ${LIBMPV_LIBRARIES}")
    endif()
endif()

if(NOT LIBMPV_FOUND)
    message(STATUS "⚠️  libmpv not found - HDR video playback will be disabled")
    message(STATUS "")
    message(STATUS "  To enable HDR video playback:")
    message(STATUS "  • Linux:   sudo apt install libmpv-dev")
    message(STATUS "  • macOS:   brew install mpv")
    message(STATUS "  • Windows: Install via vcpkg: vcpkg install mpv")
    message(STATUS "  • Manual:  Set MPV_DIR environment variable or install to standard paths")
endif()

# Fetch qlementine-icons library
include(FetchContent)
FetchContent_Declare(qlementine-icons 
    GIT_REPOSITORY "https://github.com/oclero/qlementine-icons.git"
    GIT_TAG master
)
FetchContent_MakeAvailable(qlementine-icons)

# JUCE integration disabled - requires Direct2D headers not available with MinGW
# The optimized custom audio processor provides excellent performance

qt_standard_project_setup(REQUIRES 6.8)

qt_add_executable(apps3rpent_media
    src/cpp/main.cpp
    src/cpp/colorutils.cpp
    src/cpp/colorutils.h
    src/cpp/windowmanager.cpp
    src/cpp/windowmanager.h
    src/cpp/wmfvideoplayer.cpp
    src/cpp/wmfvideoplayer.h
    src/cpp/wmfvideoplayer_playback.cpp
    src/cpp/wmfvideoplayer_helpers.cpp
    src/cpp/wmfvideoplayer_helpers.h
    src/cpp/lrclibclient.cpp
    src/cpp/lrclibclient.h
    src/cpp/lyricstranslationclient.cpp
    src/cpp/lyricstranslationclient.h
    src/cpp/audiovisualizer.cpp
    src/cpp/audiovisualizer.h
    src/cpp/audioequalizer.cpp
    src/cpp/audioequalizer.h
    src/cpp/customaudioprocessor.cpp
    src/cpp/customaudioprocessor.h
    src/cpp/customaudioplayer.cpp
    src/cpp/customaudioplayer.h
    src/cpp/windowsmediasession.cpp
    src/cpp/windowsmediasession.h
    $<$<PLATFORM_ID:Windows>:src/cpp/windowsmediasession_windows.cpp>
    src/cpp/discordrpc.cpp
    src/cpp/discordrpc.h
    src/cpp/coverartclient.cpp
    src/cpp/coverartclient.h
    src/cpp/lastfmclient.cpp
    src/cpp/lastfmclient.h
    src/cpp/singleinstancemanager.cpp
    src/cpp/singleinstancemanager.h
    src/cpp/windowframehelper.cpp
    src/cpp/windowframehelper.h
    src/cpp/subtitleformatter.cpp
    src/cpp/subtitleformatter.h
    src/cpp/mediaplayerwrapper.cpp
    src/cpp/mediaplayerwrapper.h
    src/cpp/embeddedsubtitleextractor.cpp
    src/cpp/embeddedsubtitleextractor.h
    src/cpp/ziparchivereader.cpp
    src/cpp/ziparchivereader.h
    src/cpp/externaldraghelper.cpp
    src/cpp/externaldraghelper.h
    src/cpp/modelsourceresolver.cpp
    src/cpp/modelsourceresolver.h
    $<$<BOOL:${FFMPEG_FOUND}>:src/cpp/ffmpegsubtitleextractor.cpp>
    $<$<BOOL:${FFMPEG_FOUND}>:src/cpp/ffmpegsubtitleextractor.h>
    $<$<BOOL:${FFMPEG_FOUND}>:src/cpp/ffmpegvideoplayer.cpp>
    $<$<BOOL:${FFMPEG_FOUND}>:src/cpp/ffmpegvideoplayer.h>
    $<$<BOOL:${FFMPEG_FOUND}>:src/cpp/ffmpegvideorenderer.cpp>
    $<$<BOOL:${FFMPEG_FOUND}>:src/cpp/ffmpegvideorenderer.h>
    src/cpp/vlcvideoplayer.cpp
    src/cpp/vlcvideoplayer.h
    src/cpp/vlcvideoitem.cpp
    src/cpp/vlcvideoitem.h
    $<$<BOOL:${LIBMPV_FOUND}>:src/cpp/mpvvideoplayer.cpp>
    $<$<BOOL:${LIBMPV_FOUND}>:src/cpp/mpvvideoplayer.h>
    $<$<BOOL:${LIBMPV_FOUND}>:src/cpp/mpvglwidget.cpp>
    $<$<BOOL:${LIBMPV_FOUND}>:src/cpp/mpvglwidget.h>
    # TEMPORARILY DISABLED: Widget-based mpv embedding (testing white border issue)
    # $<$<BOOL:${LIBMPV_FOUND}>:src/cpp/mpvqmlcontainer.cpp>
    # $<$<BOOL:${LIBMPV_FOUND}>:src/cpp/mpvqmlcontainer.h>
    # $<$<BOOL:${LIBMPV_FOUND}>:src/cpp/mpvqmlitem.cpp>
    # $<$<BOOL:${LIBMPV_FOUND}>:src/cpp/mpvqmlitem.h>
    $<$<PLATFORM_ID:Windows>:resources/app.rc>
)

# MSVC: Apply all RelWithDebInfo flags to target to prevent C1041 PDB lock errors
# This MUST be done via target_compile_options, not add_compile_options,
# because Qt's target properties override global compile options and Qt-generated
# sources (MOC, QML cache, RCC) won't inherit /FS from add_compile_options()
if (MSVC)
    target_compile_options(apps3rpent_media PRIVATE
        $<$<CONFIG:RelWithDebInfo>:/O2>     # Full optimization
        $<$<CONFIG:RelWithDebInfo>:/Ob2>     # Inline aggressively
        $<$<CONFIG:RelWithDebInfo>:/DNDEBUG> # Disable assertions
        $<$<CONFIG:RelWithDebInfo>:/Z7>      # Embed debug info in .obj files (no shared PDB, no locks)
        # Alternative if you need PDB files: use /Zi + /FS instead of /Z7
        # $<$<CONFIG:RelWithDebInfo>:/Zi>    # Debug symbols (PDB)
        # $<$<CONFIG:RelWithDebInfo>:/FS>    # REQUIRED with /Zi: Serialize PDB writes
    )
    
    if (CMAKE_GENERATOR MATCHES "Visual Studio")
        set_target_properties(apps3rpent_media PROPERTIES
            MSVC_DEBUG_INFORMATION_FORMAT Embedded  # Matches /Z7
        )
    endif()
endif()

set(QML_FILES
        src/qml/Main.qml
        src/qml/ImageViewer.qml
        src/qml/VideoPlayer.qml
        src/qml/MPVVideoPlayerComponent.qml
        src/qml/MPVVideoPlayerComponentD3D11.qml
        src/qml/AudioPlayer.qml
        src/qml/TitleBar.qml
        src/qml/MetadataPopup.qml
        src/qml/SettingsPage.qml
        src/qml/WindowBackground.qml
        src/qml/GradientBackground.qml
        src/qml/BackdropBlur.qml
        src/qml/AmbientGradient.qml
        src/qml/SnowEffect.qml
        src/qml/ColorExtractor.qml
        src/qml/MediaViewer.qml
        src/qml/AudioControls.qml
        src/qml/ImageControls.qml
        src/qml/ImageThumbnailPopup.qml
        src/qml/MarkdownViewer.qml
        src/qml/AudioVisualizerView.qml
        src/qml/BassPulseWindow.qml
        src/qml/BassPulseManager.qml
        src/qml/DebugConsole.qml
        src/qml/TextViewer.qml
        src/qml/PdfViewer.qml
        src/qml/ZipViewer.qml
        src/qml/ModelViewer.qml
        src/qml/EmptyState.qml
        src/qml/ToastNotification.qml
        src/qml/InputHandlers.qml
        src/qml/AppShortcuts.qml
        src/qml/ImageNavigationArrows.qml
        src/qml/OpenFileDialog.qml
        src/qml/FileDialogManager.qml
        src/qml/MetadataPopupManager.qml
        src/qml/WindowInitializationManager.qml
        src/qml/WindowResizeTimers.qml
        src/qml/MediaViewerLoaders.qml
        src/qml/MainContentArea.qml
        src/qml/BadAppleEffect.qml
        src/qml/UndertaleFight.qml
        src/js/FileTypeUtils.js
        src/js/MediaFormatUtils.js
        src/js/ImageNavigationUtils.js
        src/js/AudioUtils.js
        src/js/DebugUtils.js
        src/js/ViewManagementUtils.js
        src/js/MediaLoaderUtils.js
        src/js/ColorManagementUtils.js
        src/js/MediaUnloadUtils.js
        src/js/WindowLifecycleUtils.js
        src/js/WindowResizeUtils.js
        src/js/MediaChangeHandlerUtils.js
        src/js/MediaLoaderFunctions.js
        src/js/AudioProcessingFunctions.js
        src/js/WindowResizeFunctions.js
)

# Add PDF implementation only if PDF module is available
if(TARGET Qt6::Pdf AND TARGET Qt6::PdfQuick)
    list(APPEND QML_FILES src/qml/PdfViewerImpl.qml)
endif()

# Add 3D model viewer implementation only if Quick3D is available
if(TARGET Qt6::Quick3D)
    list(APPEND QML_FILES src/qml/ModelViewerImpl.qml)
endif()

qt_add_qml_module(apps3rpent_media
    URI s3rpent_media
    QML_FILES ${QML_FILES}
    PREFIX src
)

# Add shader files using qt_add_shaders
# Attach directly to apps3rpent_media (same target that owns the QML module)
# Shaders will be accessible at qrc:/resources/shaders/...
qt_add_shaders(apps3rpent_media
    PREFIX /resources/shaders
    FILES
        resources/shaders/ambientgradient.vert
        resources/shaders/ambientgradient.frag
        resources/shaders/snow.frag
        resources/shaders/badapple.frag
        resources/shaders/badapple_procedural.frag
        resources/shaders/mpv_video.vert
        resources/shaders/mpv_video.frag
        resources/shaders/ffmpeg_video.vert
        resources/shaders/ffmpeg_video.frag
)

# Add font files to resources
# Note: qt_add_shaders() automatically handles shader .qsb files - DO NOT manually add them
qt_add_resources(apps3rpent_media PRIVATE
    PREFIX /fonts
    FILES
        resources/fonts/goodly-regular.otf
        resources/fonts/goodly-bold.otf
        resources/fonts/goodly-semibold.otf
        resources/fonts/goodly-medium.otf
        resources/fonts/goodly-light.otf
        resources/fonts/goodly-extralight.otf
        resources/fonts/ut-hp-font.otf
        resources/fonts/DTM-Mono.otf
        resources/fonts/DTM-Sans.otf
        resources/fonts/Mars_Needs_Cunnilingus.ttf
)

# Qt for iOS sets MACOSX_BUNDLE_GUI_IDENTIFIER automatically since Qt 6.1.
# If you are developing for iOS or macOS you should consider setting an
# explicit, fixed bundle identifier manually though.
set_target_properties(apps3rpent_media PROPERTIES
#    MACOSX_BUNDLE_GUI_IDENTIFIER com.example.apps3rpent_media
    MACOSX_BUNDLE_BUNDLE_VERSION ${PROJECT_VERSION}
    MACOSX_BUNDLE_SHORT_VERSION_STRING ${PROJECT_VERSION_MAJOR}.${PROJECT_VERSION_MINOR}
    MACOSX_BUNDLE TRUE
)

# Hide console window in Release mode (GUI app), show in Debug/RelWithDebInfo mode (for debugging)
# RelWithDebInfo (FastDebug) is treated like Debug - console app for debugging
if(CMAKE_BUILD_TYPE STREQUAL "Release" OR CMAKE_BUILD_TYPE STREQUAL "MinSizeRel")
    set_target_properties(apps3rpent_media PROPERTIES WIN32_EXECUTABLE TRUE)
    message(STATUS "Building as GUI application (no console)")
else()
    set_target_properties(apps3rpent_media PROPERTIES WIN32_EXECUTABLE FALSE)
    if(CMAKE_BUILD_TYPE STREQUAL "RelWithDebInfo")
        message(STATUS "Building as console application (FastDebug/RelWithDebInfo mode)")
    else()
        message(STATUS "Building as console application (debug mode)")
    endif()
endif()

target_link_libraries(apps3rpent_media
    PRIVATE Qt6::Quick Qt6::QuickControls2 Qt6::Multimedia Qt6::Network Qt6::Widgets Qt6::OpenGLWidgets Qt6::ShaderTools Qt6::Concurrent
    PRIVATE Qt6::Gui
    PRIVATE Qt6::GuiPrivate
    PRIVATE qlementine-icons
)

if(TARGET Qt6::Quick3D)
    target_link_libraries(apps3rpent_media PRIVATE Qt6::Quick3D)
    if(TARGET Qt6::Quick3DAssetUtils)
        target_link_libraries(apps3rpent_media PRIVATE Qt6::Quick3DAssetUtils)
    endif()
    target_compile_definitions(apps3rpent_media PRIVATE HAS_MODEL3D_SUPPORT=1)
    message(STATUS "3D model support enabled (Qt6::Quick3D found)")
else()
    message(STATUS "3D model support disabled (Qt6::Quick3D not found)")
endif()

if(LibArchive_FOUND)
    if(TARGET LibArchive::LibArchive)
        target_link_libraries(apps3rpent_media PRIVATE LibArchive::LibArchive)
    elseif(TARGET libarchive::libarchive)
        target_link_libraries(apps3rpent_media PRIVATE libarchive::libarchive)
    elseif(TARGET archive)
        target_link_libraries(apps3rpent_media PRIVATE archive)
    elseif(LibArchive_LIBRARIES)
        target_link_libraries(apps3rpent_media PRIVATE ${LibArchive_LIBRARIES})
    endif()
    if(LibArchive_INCLUDE_DIRS)
        target_include_directories(apps3rpent_media PRIVATE ${LibArchive_INCLUDE_DIRS})
    endif()
    target_compile_definitions(apps3rpent_media PRIVATE HAS_LIBARCHIVE=1)
    message(STATUS "ZIP extraction/listing: libarchive enabled")
else()
    message(STATUS "ZIP extraction/listing: libarchive not found, using external/fallback extractors")
endif()

# ---- Qt private headers (QRhi) ----
# Required for: #include <QtGui/private/qrhi_p.h>
# On Windows, Qt does NOT export private include paths properly in INTERFACE_INCLUDE_DIRECTORIES.
# We must add the versioned QtGui include directories manually.
# Note: We need TWO include roots:
#   1) include/QtGui/6.10.1 - for <QtGui/private/qrhi_p.h> (resolves to include/QtGui/6.10.1/QtGui/private/qrhi_p.h)
#   2) include/QtGui/6.10.1/QtGui - for <rhi/qrhi.h> (included by qrhi_p.h, resolves to include/QtGui/6.10.1/QtGui/rhi/qrhi.h)

set(QT_ROOT "C:/Qt/6.10.1/msvc2022_64")

set(QT_PRIVATE_QTGUI_VERSIONED_DIR
    "${QT_ROOT}/include/QtGui/6.10.1"
)

set(QT_PRIVATE_QTGUI_FULL_DIR
    "${QT_ROOT}/include/QtGui/6.10.1/QtGui"
)

if (
    EXISTS "${QT_PRIVATE_QTGUI_FULL_DIR}/private/qrhi_p.h"
    AND EXISTS "${QT_PRIVATE_QTGUI_FULL_DIR}/rhi/qrhi.h"
)
    target_include_directories(apps3rpent_media PRIVATE
        "${QT_PRIVATE_QTGUI_VERSIONED_DIR}"
        "${QT_PRIVATE_QTGUI_FULL_DIR}"
    )

    message(STATUS "Using Qt QRhi headers")
    message(STATUS "  QtGui versioned include: ${QT_PRIVATE_QTGUI_VERSIONED_DIR}")
    message(STATUS "  QtGui full include: ${QT_PRIVATE_QTGUI_FULL_DIR}")
else()
    message(FATAL_ERROR
        "Qt QRhi headers not found:\n"
        "  ${QT_PRIVATE_QTGUI_FULL_DIR}/private/qrhi_p.h\n"
        "  ${QT_PRIVATE_QTGUI_FULL_DIR}/rhi/qrhi.h"
    )
endif()

# Optional PDF support (not available for all platforms/compilers)
if(TARGET Qt6::Pdf AND TARGET Qt6::PdfQuick)
    target_link_libraries(apps3rpent_media PRIVATE Qt6::Pdf Qt6::PdfQuick)
    target_compile_definitions(apps3rpent_media PRIVATE HAS_PDF_SUPPORT=1)
    message(STATUS "PDF support enabled")
else()
    message(STATUS "PDF support disabled (Qt6::Pdf or Qt6::PdfQuick not found)")
endif()

# Link FFmpeg libraries if found (for fast subtitle extraction and D3D11VA video decoding)
if(FFMPEG_FOUND)
    # CRITICAL: Set include directories FIRST and with highest priority
    # This ensures we compile against the correct FFmpeg headers (custom build)
    # Must come before any other includes to avoid header conflicts
    if(FFMPEG_INCLUDE_DIR)
        target_include_directories(apps3rpent_media PRIVATE 
            ${FFMPEG_INCLUDE_DIR}  # Custom FFmpeg headers (highest priority)
        )
        message(STATUS "  FFmpeg include directory set: ${FFMPEG_INCLUDE_DIR}")
    elseif(DEFINED FFMPEG_INCLUDE_DIRS)
        target_include_directories(apps3rpent_media PRIVATE ${FFMPEG_INCLUDE_DIRS})
        message(STATUS "  FFmpeg include directories set: ${FFMPEG_INCLUDE_DIRS}")
    endif()
    
    # Add CUDA include directory (required for CUVID support on NVIDIA GPUs)
    # FFmpeg's hwcontext_cuda.h requires cuda.h
    if(WIN32)
        set(CUDA_INCLUDE_FOUND FALSE)
        
        # Try common CUDA installation paths (check multiple versions)
        set(CUDA_INCLUDE_PATHS
            "C:/Program Files/NVIDIA GPU Computing Toolkit/CUDA/v13.1/include"
            "C:/Program Files/NVIDIA GPU Computing Toolkit/CUDA/v13.0/include"
            "C:/Program Files/NVIDIA GPU Computing Toolkit/CUDA/v12.6/include"
            "C:/Program Files/NVIDIA GPU Computing Toolkit/CUDA/v12.5/include"
            "C:/Program Files/NVIDIA GPU Computing Toolkit/CUDA/v12.4/include"
            "C:/Program Files/NVIDIA GPU Computing Toolkit/CUDA/v12.3/include"
            "C:/Program Files/NVIDIA GPU Computing Toolkit/CUDA/v12.2/include"
            "C:/Program Files/NVIDIA GPU Computing Toolkit/CUDA/v12.1/include"
            "C:/Program Files/NVIDIA GPU Computing Toolkit/CUDA/v12.0/include"
            "$ENV{CUDA_PATH_V13_1}/include"
            "$ENV{CUDA_PATH_V13_0}/include"
            "$ENV{CUDA_PATH_V12_6}/include"
            "$ENV{CUDA_PATH_V12_5}/include"
            "$ENV{CUDA_PATH_V12_4}/include"
            "$ENV{CUDA_PATH_V12_3}/include"
            "$ENV{CUDA_PATH}/include"
        )
        
        foreach(CUDA_INCLUDE_PATH ${CUDA_INCLUDE_PATHS})
            if(EXISTS "${CUDA_INCLUDE_PATH}/cuda.h")
                target_include_directories(apps3rpent_media PRIVATE "${CUDA_INCLUDE_PATH}")
                message(STATUS "  CUDA include directory found: ${CUDA_INCLUDE_PATH}")
                set(CUDA_INCLUDE_FOUND TRUE)
                break()
            endif()
        endforeach()
        
        # Warn if CUDA not found
        if(NOT CUDA_INCLUDE_FOUND)
            message(WARNING "  CUDA include directory not found - CUVID support may not compile")
            message(WARNING "    Install CUDA Toolkit or set CUDA_PATH environment variable")
            message(WARNING "    Expected path: C:/Program Files/NVIDIA GPU Computing Toolkit/CUDA/v*/include")
        endif()
    endif()
    
    # Custom FFmpeg build (highest priority - has proper D3D11VA support)
    # NOTE: For gpl-shared FFmpeg (MinGW DLLs), we still need to link .lib files (import libraries)
    # The .lib files are import libraries that tell the linker where to find symbols in the DLLs
    # The actual code is in the DLLs, which are copied to the build directory
    if(DEFINED FFMPEG_BIN_DIR)
        # Link to import libraries (required for MSVC to resolve symbols)
        # These are import libraries, not static libraries - code is in DLLs
        target_link_libraries(apps3rpent_media PRIVATE 
            ${FFMPEG_AVFORMAT_LIB} 
            ${FFMPEG_AVCODEC_LIB} 
            ${FFMPEG_AVUTIL_LIB}
            ${FFMPEG_SWRESAMPLE_LIB}
            ${FFMPEG_SWSCALE_LIB}
            ${FFMPEG_AVFILTER_LIB}
        )
        message(STATUS "  Linked via custom FFmpeg import libraries (DLLs will be runtime-loaded)")
        
        # Copy FFmpeg DLLs to build directory (Windows only)
        if(WIN32)
            set(FFMPEG_DLLS
                "${FFMPEG_BIN_DIR}/avcodec-61.dll"
                "${FFMPEG_BIN_DIR}/avformat-61.dll"
                "${FFMPEG_BIN_DIR}/avutil-59.dll"
                "${FFMPEG_BIN_DIR}/swresample-5.dll"
                "${FFMPEG_BIN_DIR}/swscale-8.dll"
                "${FFMPEG_BIN_DIR}/avfilter-10.dll"
                "${FFMPEG_BIN_DIR}/postproc-58.dll"
            )
            foreach(DLL ${FFMPEG_DLLS})
                if(EXISTS ${DLL})
                    get_filename_component(DLL_NAME ${DLL} NAME)
                    add_custom_command(TARGET apps3rpent_media POST_BUILD
                        COMMAND ${CMAKE_COMMAND} -E copy_if_different
                        ${DLL}
                        $<TARGET_FILE_DIR:apps3rpent_media>/${DLL_NAME}
                        COMMENT "Copying ${DLL_NAME} to build directory"
                    )
                endif()
            endforeach()
            message(STATUS "  Will copy FFmpeg DLLs to build directory")
        endif()
    # vcpkg FFmpeg build
    elseif(TARGET FFMPEG::avformat)
        target_link_libraries(apps3rpent_media PRIVATE 
            FFMPEG::avformat 
            FFMPEG::avcodec 
            FFMPEG::avutil
            FFMPEG::swresample
            FFMPEG::swscale
            FFMPEG::avfilter
        )
        message(STATUS "  Linked via vcpkg imported targets")
        # Add library directories for vcpkg
        if(EXISTS "C:/vcpkg/installed/x64-windows/lib")
            target_link_directories(apps3rpent_media PRIVATE "C:/vcpkg/installed/x64-windows/lib")
        elseif(DEFINED FFMPEG_LIBRARY_DIRS)
            target_link_directories(apps3rpent_media PRIVATE ${FFMPEG_LIBRARY_DIRS})
        endif()
    elseif(EXISTS "C:/vcpkg/installed/x64-windows/lib/avformat.lib")
        # Use full paths from vcpkg (most reliable)
        target_link_libraries(apps3rpent_media PRIVATE 
            "C:/vcpkg/installed/x64-windows/lib/avformat.lib"
            "C:/vcpkg/installed/x64-windows/lib/avcodec.lib"
            "C:/vcpkg/installed/x64-windows/lib/avutil.lib"
            "C:/vcpkg/installed/x64-windows/lib/swresample.lib"
            "C:/vcpkg/installed/x64-windows/lib/swscale.lib"
            "C:/vcpkg/installed/x64-windows/lib/avfilter.lib"
        )
        message(STATUS "  Linked via vcpkg library paths (full paths)")
        target_link_directories(apps3rpent_media PRIVATE "C:/vcpkg/installed/x64-windows/lib")
    elseif(DEFINED FFMPEG_LIBRARIES)
        # Use vcpkg's FFMPEG_LIBRARIES if available
        target_link_libraries(apps3rpent_media PRIVATE ${FFMPEG_LIBRARIES})
        message(STATUS "  Linked via vcpkg FFMPEG_LIBRARIES")
        if(DEFINED FFMPEG_LIBRARY_DIRS)
            target_link_directories(apps3rpent_media PRIVATE ${FFMPEG_LIBRARY_DIRS})
        endif()
    else()
        # Manual linking (pkg-config or manual find)
        if(FFMPEG_PKG_FOUND)
            target_link_libraries(apps3rpent_media PRIVATE ${FFMPEG_PKG_LIBRARIES})
            target_compile_options(apps3rpent_media PRIVATE ${FFMPEG_PKG_CFLAGS_OTHER})
        else()
            target_link_libraries(apps3rpent_media PRIVATE 
                ${FFMPEG_AVFORMAT_LIB} 
                ${FFMPEG_AVCODEC_LIB} 
                ${FFMPEG_AVUTIL_LIB}
                ${FFMPEG_SWRESAMPLE_LIB}
                ${FFMPEG_SWSCALE_LIB}
                ${FFMPEG_AVFILTER_LIB}
            )
        endif()
        message(STATUS "  Linked manually")
    endif()
    target_compile_definitions(apps3rpent_media PRIVATE HAS_FFMPEG_LIBS=1)
endif()

# Link libmpv if found (for HDR video playback)
if(LIBMPV_FOUND)
    if(LIBMPV_INCLUDE_DIR)
        target_include_directories(apps3rpent_media PRIVATE ${LIBMPV_INCLUDE_DIR})
    endif()
    
    # Add library directories for vcpkg
    if(EXISTS "C:/vcpkg/installed/x64-windows/lib")
        target_link_directories(apps3rpent_media PRIVATE "C:/vcpkg/installed/x64-windows/lib")
    endif()
    
    # Link libmpv
    if(LIBMPV_PKG_FOUND)
        target_link_libraries(apps3rpent_media PRIVATE ${LIBMPV_PKG_LIBRARIES})
        target_compile_options(apps3rpent_media PRIVATE ${LIBMPV_PKG_CFLAGS_OTHER})
        message(STATUS "  Linked libmpv via pkg-config")
    else()
        target_link_libraries(apps3rpent_media PRIVATE ${LIBMPV_LIBRARIES})
        message(STATUS "  Linked libmpv manually")
    endif()
    
    target_compile_definitions(apps3rpent_media PRIVATE HAS_LIBMPV=1)
    message(STATUS "✅ libmpv linked - HDR video playback enabled")
    
    # Copy libmpv DLL to build directory (Windows only)
    if(WIN32)
        # Find the DLL
        if(EXISTS "C:/mpv/libmpv-2.dll")
            add_custom_command(TARGET apps3rpent_media POST_BUILD
                COMMAND ${CMAKE_COMMAND} -E copy_if_different
                "C:/mpv/libmpv-2.dll"
                $<TARGET_FILE_DIR:apps3rpent_media>
                COMMENT "Copying libmpv-2.dll to build directory"
            )
            message(STATUS "  Will copy libmpv-2.dll to build directory")
        elseif(EXISTS "C:/mpv/libmpv.dll")
            add_custom_command(TARGET apps3rpent_media POST_BUILD
                COMMAND ${CMAKE_COMMAND} -E copy_if_different
                "C:/mpv/libmpv.dll"
                $<TARGET_FILE_DIR:apps3rpent_media>
                COMMENT "Copying libmpv.dll to build directory"
            )
            message(STATUS "  Will copy libmpv.dll to build directory")
        endif()
    endif()
endif()

# Windows-specific libraries for WASAPI audio loopback, memory info, Windows Media Session, and DWM
if(WIN32)
    target_link_libraries(apps3rpent_media PRIVATE
        ole32
        oleaut32
        uuid
        psapi
        dwmapi
    )
    # Additional libraries for Windows Media Session (WinRT) - MSVC only
    if(MSVC)
        target_link_libraries(apps3rpent_media PRIVATE
            runtimeobject
            shlwapi
            propsys
            coremessaging  # For CreateDispatcherQueueController
        )
        
        # RelWithDebInfo optimizations: Full optimization + debug symbols (FastDebug mode)
        # This makes RelWithDebInfo perform like Release but with debug symbols
        # Perfect for media apps that need smooth playback but also need debugging
        # NOTE: All compile options are now set via target_compile_options() above
        # to ensure they apply to Qt-generated sources (MOC, QML cache, RCC)
        
        add_link_options(
            $<$<CONFIG:RelWithDebInfo>:/INCREMENTAL:NO>  # Disable incremental linking (prevents link.exe crashes with large static libs + debug info)
            $<$<CONFIG:RelWithDebInfo>:/DEBUG>   # Generate PDB
            $<$<CONFIG:RelWithDebInfo>:/OPT:REF> # Remove unused code
            $<$<CONFIG:RelWithDebInfo>:/OPT:ICF> # Fold identical functions
        )
        
        message(STATUS "MSVC RelWithDebInfo optimizations enabled (FastDebug mode)")
    endif()
endif()

# Note: FFmpeg is used via QProcess (subprocess) for both audio and video decoding
# FFmpeg executable must be in PATH

# Translation files
set(TS_FILES
    translations/s3rpent_media_ro.ts
)

qt_add_translations(apps3rpent_media TS_FILES ${TS_FILES})

include(GNUInstallDirs)
install(TARGETS apps3rpent_media
    BUNDLE DESTINATION .
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
)

# Copy Bad Apple files to build directory (for development)
# These files will be in the same directory as the executable
if(EXISTS "${CMAKE_SOURCE_DIR}/resources/media/Bad Apple!!.mp3")
    add_custom_command(TARGET apps3rpent_media POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
            "${CMAKE_SOURCE_DIR}/resources/media/Bad Apple!!.mp3"
            "$<TARGET_FILE_DIR:apps3rpent_media>/Bad Apple!!.mp3"
        COMMENT "Copying Bad Apple!!.mp3 to build directory"
    )
    message(STATUS "Bad Apple!!.mp3 will be copied to build directory")
else()
    message(WARNING "Bad Apple!!.mp3 not found - easter egg will not work")
endif()

if(EXISTS "${CMAKE_SOURCE_DIR}/resources/media/badapple_frames.bin")
    add_custom_command(TARGET apps3rpent_media POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
            "${CMAKE_SOURCE_DIR}/resources/media/badapple_frames.bin"
            "$<TARGET_FILE_DIR:apps3rpent_media>/badapple_frames.bin"
        COMMENT "Copying badapple_frames.bin to build directory"
    )
    message(STATUS "badapple_frames.bin will be copied to build directory")
else()
    message(WARNING "badapple_frames.bin not found - easter egg will not work")
endif()

# Copy icon files to build directory (for tray icon loading from file system)
if(EXISTS "${CMAKE_SOURCE_DIR}/resources/icons/icon.ico")
    add_custom_command(TARGET apps3rpent_media POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
            "${CMAKE_SOURCE_DIR}/resources/icons/icon.ico"
            "$<TARGET_FILE_DIR:apps3rpent_media>/icon.ico"
        COMMENT "Copying icon.ico to build directory"
    )
endif()
if(EXISTS "${CMAKE_SOURCE_DIR}/resources/icons/icon.png")
    add_custom_command(TARGET apps3rpent_media POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
            "${CMAKE_SOURCE_DIR}/resources/icons/icon.png"
            "$<TARGET_FILE_DIR:apps3rpent_media>/icon.png"
        COMMENT "Copying icon.png to build directory"
    )
endif()

# Copy sprites folder to build directory (for Undertale fight easter egg)
if(EXISTS "${CMAKE_SOURCE_DIR}/sprites")
    add_custom_command(TARGET apps3rpent_media POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_directory
            "${CMAKE_SOURCE_DIR}/sprites"
            "$<TARGET_FILE_DIR:apps3rpent_media>/sprites"
        COMMENT "Copying sprites folder to build directory"
    )
    message(STATUS "sprites folder will be copied to build directory")
else()
    message(WARNING "sprites folder not found - Undertale fight easter egg will not work")
endif()

# Install Bad Apple files for distribution
install(FILES "${CMAKE_SOURCE_DIR}/resources/media/Bad Apple!!.mp3" DESTINATION ${CMAKE_INSTALL_BINDIR} OPTIONAL)
install(FILES "${CMAKE_SOURCE_DIR}/resources/media/badapple_frames.bin" DESTINATION ${CMAKE_INSTALL_BINDIR} OPTIONAL)

# Install sprites folder for distribution
install(DIRECTORY "${CMAKE_SOURCE_DIR}/sprites" DESTINATION ${CMAKE_INSTALL_BINDIR} OPTIONAL)

# Include libvlc configuration
include(cmake_libvlc.cmake)

