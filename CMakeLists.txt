cmake_minimum_required(VERSION 3.16)

project(s3rp3nt_media VERSION 0.1 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 REQUIRED COMPONENTS Quick QuickControls2 Multimedia Network Widgets ShaderTools)
find_package(Qt6 QUIET COMPONENTS Pdf PdfQuick)

# Note: FFmpeg is used via QProcess (subprocess) for audio decoding
# This handles HE-AAC correctly by ignoring broken MP4 timestamps
# FFmpeg executable must be in PATH

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

qt_add_executable(apps3rp3nt_media
    main.cpp
    colorutils.cpp
    colorutils.h
    windowmanager.cpp
    windowmanager.h
    wmfvideoplayer.cpp
    wmfvideoplayer.h
    wmfvideoplayer_playback.cpp
    wmfvideoplayer_helpers.cpp
    wmfvideoplayer_helpers.h
    lrclibclient.cpp
    lrclibclient.h
    audiovisualizer.cpp
    audiovisualizer.h
    audioequalizer.cpp
    audioequalizer.h
    customaudioprocessor.cpp
    customaudioprocessor.h
    customaudioplayer.cpp
    customaudioplayer.h
    singleinstancemanager.cpp
    singleinstancemanager.h
    $<$<PLATFORM_ID:Windows>:app.rc>
)

set(QML_FILES
        Main.qml
        ImageViewer.qml
        VideoPlayer.qml
        AudioPlayer.qml
        TitleBar.qml
        MetadataPopup.qml
        SettingsPage.qml
        WindowBackground.qml
        GradientBackground.qml
        BackdropBlur.qml
        AmbientGradient.qml
        SnowEffect.qml
        ColorExtractor.qml
        MediaViewer.qml
        AudioControls.qml
        ImageControls.qml
        MarkdownViewer.qml
        AudioVisualizerView.qml
        BassPulseWindow.qml
        DebugConsole.qml
    TextViewer.qml
    PdfViewer.qml
)

# Add PDF implementation only if PDF module is available
if(TARGET Qt6::Pdf AND TARGET Qt6::PdfQuick)
    list(APPEND QML_FILES PdfViewerImpl.qml)
endif()

qt_add_qml_module(apps3rp3nt_media
    URI s3rp3nt_media
    QML_FILES ${QML_FILES}
)

# Add shader files using qt_add_shaders - shaders are automatically added to resources
qt_add_shaders(apps3rp3nt_media PRIVATE
    FILES
        ambientgradient.vert
        ambientgradient.frag
        snow.frag
    OUTPUT_TARGETS shader_targets
)

# Qt for iOS sets MACOSX_BUNDLE_GUI_IDENTIFIER automatically since Qt 6.1.
# If you are developing for iOS or macOS you should consider setting an
# explicit, fixed bundle identifier manually though.
set_target_properties(apps3rp3nt_media PROPERTIES
#    MACOSX_BUNDLE_GUI_IDENTIFIER com.example.apps3rp3nt_media
    MACOSX_BUNDLE_BUNDLE_VERSION ${PROJECT_VERSION}
    MACOSX_BUNDLE_SHORT_VERSION_STRING ${PROJECT_VERSION_MAJOR}.${PROJECT_VERSION_MINOR}
    MACOSX_BUNDLE TRUE
)

# Hide console window in Release mode (GUI app), show in Debug mode (for debugging)
if(CMAKE_BUILD_TYPE STREQUAL "Release" OR CMAKE_BUILD_TYPE STREQUAL "RelWithDebInfo" OR CMAKE_BUILD_TYPE STREQUAL "MinSizeRel")
    set_target_properties(apps3rp3nt_media PROPERTIES WIN32_EXECUTABLE TRUE)
    message(STATUS "Building as GUI application (no console)")
else()
    set_target_properties(apps3rp3nt_media PROPERTIES WIN32_EXECUTABLE FALSE)
    message(STATUS "Building as console application (debug mode)")
endif()

target_link_libraries(apps3rp3nt_media
    PRIVATE Qt6::Quick Qt6::QuickControls2 Qt6::Multimedia Qt6::Network Qt6::Widgets Qt6::ShaderTools
    PRIVATE qlementine-icons
)

# Optional PDF support (not available for all platforms/compilers)
if(TARGET Qt6::Pdf AND TARGET Qt6::PdfQuick)
    target_link_libraries(apps3rp3nt_media PRIVATE Qt6::Pdf Qt6::PdfQuick)
    target_compile_definitions(apps3rp3nt_media PRIVATE HAS_PDF_SUPPORT=1)
    message(STATUS "PDF support enabled")
else()
    message(STATUS "PDF support disabled (Qt6::Pdf or Qt6::PdfQuick not found)")
endif()

# Windows-specific libraries for WASAPI audio loopback and memory info
if(WIN32)
    target_link_libraries(apps3rp3nt_media PRIVATE
        ole32
        oleaut32
        uuid
        psapi
    )
endif()

# Note: FFmpeg is used via QProcess (subprocess) for both audio and video decoding
# FFmpeg executable must be in PATH

include(GNUInstallDirs)
install(TARGETS apps3rp3nt_media
    BUNDLE DESTINATION .
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
)
