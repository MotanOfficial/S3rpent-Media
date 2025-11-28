cmake_minimum_required(VERSION 3.16)

project(s3rp3nt_media VERSION 0.1 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 REQUIRED COMPONENTS Quick QuickControls2 Multimedia Network)

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
)

qt_add_qml_module(apps3rp3nt_media
    URI s3rp3nt_media
    QML_FILES
        Main.qml
        ImageViewer.qml
        VideoPlayer.qml
        AudioPlayer.qml
        TitleBar.qml
        MetadataPopup.qml
        SettingsPage.qml
        WindowBackground.qml
        MediaViewer.qml
        AudioControls.qml
        MarkdownViewer.qml
        AudioVisualizerView.qml
        TextViewer.qml
)

# Qt for iOS sets MACOSX_BUNDLE_GUI_IDENTIFIER automatically since Qt 6.1.
# If you are developing for iOS or macOS you should consider setting an
# explicit, fixed bundle identifier manually though.
set_target_properties(apps3rp3nt_media PROPERTIES
#    MACOSX_BUNDLE_GUI_IDENTIFIER com.example.apps3rp3nt_media
    MACOSX_BUNDLE_BUNDLE_VERSION ${PROJECT_VERSION}
    MACOSX_BUNDLE_SHORT_VERSION_STRING ${PROJECT_VERSION_MAJOR}.${PROJECT_VERSION_MINOR}
    MACOSX_BUNDLE TRUE
    WIN32_EXECUTABLE FALSE
)

target_link_libraries(apps3rp3nt_media
    PRIVATE Qt6::Quick Qt6::QuickControls2 Qt6::Multimedia Qt6::Network
    PRIVATE qlementine-icons
)

# Windows-specific libraries for WASAPI audio loopback
if(WIN32)
    target_link_libraries(apps3rp3nt_media PRIVATE
        ole32
        oleaut32
        uuid
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
