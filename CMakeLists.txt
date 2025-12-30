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
    lyricstranslationclient.cpp
    lyricstranslationclient.h
    audiovisualizer.cpp
    audiovisualizer.h
    audioequalizer.cpp
    audioequalizer.h
    customaudioprocessor.cpp
    customaudioprocessor.h
    customaudioplayer.cpp
    customaudioplayer.h
    windowsmediasession.cpp
    windowsmediasession.h
    $<$<PLATFORM_ID:Windows>:windowsmediasession_windows.cpp>
    discordrpc.cpp
    discordrpc.h
    coverartclient.cpp
    coverartclient.h
    lastfmclient.cpp
    lastfmclient.h
    singleinstancemanager.cpp
    singleinstancemanager.h
    windowframehelper.cpp
    windowframehelper.h
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
        ImageThumbnailPopup.qml
        MarkdownViewer.qml
        AudioVisualizerView.qml
        BassPulseWindow.qml
        BassPulseManager.qml
        DebugConsole.qml
    TextViewer.qml
    PdfViewer.qml
        EmptyState.qml
        ToastNotification.qml
        InputHandlers.qml
        AppShortcuts.qml
        ImageNavigationArrows.qml
        OpenFileDialog.qml
        FileDialogManager.qml
        MetadataPopupManager.qml
        WindowInitializationManager.qml
        WindowResizeTimers.qml
        MediaViewerLoaders.qml
        MainContentArea.qml
        BadAppleEffect.qml
        FileTypeUtils.js
        MediaFormatUtils.js
        ImageNavigationUtils.js
        AudioUtils.js
        DebugUtils.js
        ViewManagementUtils.js
        MediaLoaderUtils.js
        ColorManagementUtils.js
        MediaUnloadUtils.js
        WindowLifecycleUtils.js
        WindowResizeUtils.js
        MediaChangeHandlerUtils.js
        MediaLoaderFunctions.js
        AudioProcessingFunctions.js
        WindowResizeFunctions.js
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
        badapple.frag
        badapple_procedural.frag
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
if(EXISTS "${CMAKE_SOURCE_DIR}/Bad Apple!!.mp3")
    add_custom_command(TARGET apps3rp3nt_media POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
            "${CMAKE_SOURCE_DIR}/Bad Apple!!.mp3"
            "${CMAKE_BINARY_DIR}/Bad Apple!!.mp3"
        COMMENT "Copying Bad Apple!!.mp3 to build directory"
    )
    message(STATUS "Bad Apple!!.mp3 will be copied to build directory")
else()
    message(WARNING "Bad Apple!!.mp3 not found - easter egg will not work")
endif()

if(EXISTS "${CMAKE_SOURCE_DIR}/badapple_frames.bin")
    add_custom_command(TARGET apps3rp3nt_media POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
            "${CMAKE_SOURCE_DIR}/badapple_frames.bin"
            "${CMAKE_BINARY_DIR}/badapple_frames.bin"
        COMMENT "Copying badapple_frames.bin to build directory"
    )
    message(STATUS "badapple_frames.bin will be copied to build directory")
else()
    message(WARNING "badapple_frames.bin not found - easter egg will not work")
endif()

# Copy icon files to build directory (for tray icon loading from file system)
if(EXISTS "${CMAKE_SOURCE_DIR}/icon.ico")
    add_custom_command(TARGET apps3rp3nt_media POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
            "${CMAKE_SOURCE_DIR}/icon.ico"
            "${CMAKE_BINARY_DIR}/icon.ico"
        COMMENT "Copying icon.ico to build directory"
    )
endif()
if(EXISTS "${CMAKE_SOURCE_DIR}/icon.png")
    add_custom_command(TARGET apps3rp3nt_media POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
            "${CMAKE_SOURCE_DIR}/icon.png"
            "${CMAKE_BINARY_DIR}/icon.png"
        COMMENT "Copying icon.png to build directory"
    )
endif()

# Install Bad Apple files for distribution
install(FILES "${CMAKE_SOURCE_DIR}/Bad Apple!!.mp3" DESTINATION ${CMAKE_INSTALL_BINDIR} OPTIONAL)
install(FILES "${CMAKE_SOURCE_DIR}/badapple_frames.bin" DESTINATION ${CMAKE_INSTALL_BINDIR} OPTIONAL)
