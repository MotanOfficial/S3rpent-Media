cmake_minimum_required(VERSION 3.16)

project(s3rp3nt_media VERSION 0.1 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 REQUIRED COMPONENTS Quick QuickControls2 Multimedia Network Widgets ShaderTools LinguistTools Concurrent)
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
    $<$<PLATFORM_ID:Windows>:resources/app.rc>
)

set(QML_FILES
        src/qml/Main.qml
        src/qml/ImageViewer.qml
        src/qml/VideoPlayer.qml
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

qt_add_qml_module(apps3rp3nt_media
    URI s3rp3nt_media
    QML_FILES ${QML_FILES}
    PREFIX src
)

# Add shader files using qt_add_shaders - shaders are automatically added to resources
qt_add_shaders(apps3rp3nt_media PRIVATE
    FILES
        resources/shaders/ambientgradient.vert
        resources/shaders/ambientgradient.frag
        resources/shaders/snow.frag
        resources/shaders/badapple.frag
        resources/shaders/badapple_procedural.frag
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

# Hide console window in Release mode (GUI app), show in Debug/RelWithDebInfo mode (for debugging)
# RelWithDebInfo (FastDebug) is treated like Debug - console app for debugging
if(CMAKE_BUILD_TYPE STREQUAL "Release" OR CMAKE_BUILD_TYPE STREQUAL "MinSizeRel")
    set_target_properties(apps3rp3nt_media PROPERTIES WIN32_EXECUTABLE TRUE)
    message(STATUS "Building as GUI application (no console)")
else()
    set_target_properties(apps3rp3nt_media PROPERTIES WIN32_EXECUTABLE FALSE)
    if(CMAKE_BUILD_TYPE STREQUAL "RelWithDebInfo")
        message(STATUS "Building as console application (FastDebug/RelWithDebInfo mode)")
    else()
        message(STATUS "Building as console application (debug mode)")
    endif()
endif()

target_link_libraries(apps3rp3nt_media
    PRIVATE Qt6::Quick Qt6::QuickControls2 Qt6::Multimedia Qt6::Network Qt6::Widgets Qt6::ShaderTools Qt6::Concurrent
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

# Windows-specific libraries for WASAPI audio loopback, memory info, Windows Media Session, and DWM
if(WIN32)
    target_link_libraries(apps3rp3nt_media PRIVATE
        ole32
        oleaut32
        uuid
        psapi
        dwmapi
    )
    # Additional libraries for Windows Media Session (WinRT) - MSVC only
    if(MSVC)
        target_link_libraries(apps3rp3nt_media PRIVATE
            runtimeobject
            shlwapi
            propsys
            coremessaging  # For CreateDispatcherQueueController
        )
        
        # RelWithDebInfo optimizations: Full optimization + debug symbols (FastDebug mode)
        # This makes RelWithDebInfo perform like Release but with debug symbols
        # Perfect for media apps that need smooth playback but also need debugging
        add_compile_options(
            $<$<CONFIG:RelWithDebInfo>:/Zi>     # Debug symbols (PDB)
            $<$<CONFIG:RelWithDebInfo>:/O2>     # Full optimization
            $<$<CONFIG:RelWithDebInfo>:/Ob2>    # Inline aggressively
            $<$<CONFIG:RelWithDebInfo>:/DNDEBUG> # Disable assertions
        )
        
        add_link_options(
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
    translations/s3rp3nt_media_ro.ts
)

qt_add_translations(apps3rp3nt_media TS_FILES ${TS_FILES})

include(GNUInstallDirs)
install(TARGETS apps3rp3nt_media
    BUNDLE DESTINATION .
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
)

# Copy Bad Apple files to build directory (for development)
# These files will be in the same directory as the executable
if(EXISTS "${CMAKE_SOURCE_DIR}/resources/media/Bad Apple!!.mp3")
    add_custom_command(TARGET apps3rp3nt_media POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
            "${CMAKE_SOURCE_DIR}/resources/media/Bad Apple!!.mp3"
            "$<TARGET_FILE_DIR:apps3rp3nt_media>/Bad Apple!!.mp3"
        COMMENT "Copying Bad Apple!!.mp3 to build directory"
    )
    message(STATUS "Bad Apple!!.mp3 will be copied to build directory")
else()
    message(WARNING "Bad Apple!!.mp3 not found - easter egg will not work")
endif()

if(EXISTS "${CMAKE_SOURCE_DIR}/resources/media/badapple_frames.bin")
    add_custom_command(TARGET apps3rp3nt_media POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
            "${CMAKE_SOURCE_DIR}/resources/media/badapple_frames.bin"
            "$<TARGET_FILE_DIR:apps3rp3nt_media>/badapple_frames.bin"
        COMMENT "Copying badapple_frames.bin to build directory"
    )
    message(STATUS "badapple_frames.bin will be copied to build directory")
else()
    message(WARNING "badapple_frames.bin not found - easter egg will not work")
endif()

# Copy icon files to build directory (for tray icon loading from file system)
if(EXISTS "${CMAKE_SOURCE_DIR}/resources/icons/icon.ico")
    add_custom_command(TARGET apps3rp3nt_media POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
            "${CMAKE_SOURCE_DIR}/resources/icons/icon.ico"
            "$<TARGET_FILE_DIR:apps3rp3nt_media>/icon.ico"
        COMMENT "Copying icon.ico to build directory"
    )
endif()
if(EXISTS "${CMAKE_SOURCE_DIR}/resources/icons/icon.png")
    add_custom_command(TARGET apps3rp3nt_media POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
            "${CMAKE_SOURCE_DIR}/resources/icons/icon.png"
            "$<TARGET_FILE_DIR:apps3rp3nt_media>/icon.png"
        COMMENT "Copying icon.png to build directory"
    )
endif()

# Install Bad Apple files for distribution
install(FILES "${CMAKE_SOURCE_DIR}/resources/media/Bad Apple!!.mp3" DESTINATION ${CMAKE_INSTALL_BINDIR} OPTIONAL)
install(FILES "${CMAKE_SOURCE_DIR}/resources/media/badapple_frames.bin" DESTINATION ${CMAKE_INSTALL_BINDIR} OPTIONAL)
