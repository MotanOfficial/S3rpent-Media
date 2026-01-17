
# libvlc configuration
set(LIBVLC_INCLUDE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/libvlc/sdk/include")
set(LIBVLC_LIBRARY "${CMAKE_CURRENT_SOURCE_DIR}/libvlc/sdk/lib/libvlc.lib")
set(LIBVLCCORE_LIBRARY "${CMAKE_CURRENT_SOURCE_DIR}/libvlc/sdk/lib/libvlccore.lib")

if(EXISTS "${LIBVLC_INCLUDE_DIR}" AND EXISTS "${LIBVLC_LIBRARY}")
    message(STATUS "✅ libvlc found in project root")
    message(STATUS "  Include: ${LIBVLC_INCLUDE_DIR}")
    
    target_include_directories(apps3rp3nt_media PRIVATE ${LIBVLC_INCLUDE_DIR})
    target_link_libraries(apps3rp3nt_media PRIVATE ${LIBVLC_LIBRARY} ${LIBVLCCORE_LIBRARY})
    target_compile_definitions(apps3rp3nt_media PRIVATE HAS_LIBVLC=1)
    
    # Copy libvlc DLLs and plugins to build directory
    add_custom_command(TARGET apps3rp3nt_media POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
            "${CMAKE_CURRENT_SOURCE_DIR}/libvlc/libvlc.dll"
            "${CMAKE_CURRENT_SOURCE_DIR}/libvlc/libvlccore.dll"
            "$<TARGET_FILE_DIR:apps3rp3nt_media>"
        COMMAND ${CMAKE_COMMAND} -E copy_directory
            "${CMAKE_CURRENT_SOURCE_DIR}/libvlc/plugins"
            "$<TARGET_FILE_DIR:apps3rp3nt_media>/plugins"
        COMMENT "Copying libvlc DLLs and plugins to build directory"
    )
else()
    message(WARNING "⚠️ libvlc not found in project root (expected at libvlc/sdk)")
endif()
