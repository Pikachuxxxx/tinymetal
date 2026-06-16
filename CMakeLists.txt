cmake_minimum_required(VERSION 3.25)

include(FetchContent)

set(TINYMETAL_PLATFORM "macOS" CACHE STRING "Target platform: macOS or iOS")
set_property(CACHE TINYMETAL_PLATFORM PROPERTY STRINGS macOS iOS)

if(TINYMETAL_PLATFORM STREQUAL "iOS")
    set(CMAKE_SYSTEM_NAME iOS CACHE STRING "" FORCE)
endif()

project(TinyMetal LANGUAGES C OBJC)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_OBJC_STANDARD 11)
set(CMAKE_OBJC_STANDARD_REQUIRED ON)

if(NOT APPLE)
    message(FATAL_ERROR "TinyMetal only supports Apple platforms.")
endif()

if(NOT CMAKE_GENERATOR STREQUAL "Xcode")
    message(WARNING "This project is intended for the Xcode generator so the app bundle and Metal shader steps work cleanly.")
endif()

set(APP_NAME TinyMetal)
set(METAL_SOURCE ${CMAKE_CURRENT_SOURCE_DIR}/src/render/HelloTriangleShaders.metal)
set(COMMON_SOURCES
    src/render/TMRenderer.h
    src/render/TMRenderer.m
)

if(TINYMETAL_PLATFORM STREQUAL "iOS")
    set(PLATFORM_SOURCES
        src/ios/app/main.m
        src/ios/app/TMiOSAppDelegate.h
        src/ios/app/TMiOSAppDelegate.m
        src/ios/window/TMiOSMetalView.h
        src/ios/window/TMiOSMetalView.m
        src/ios/app/TMiOSSceneDelegate.h
        src/ios/app/TMiOSSceneDelegate.m
        src/ios/app/TMiOSViewController.h
        src/ios/app/TMiOSViewController.m
    )
    set(BUNDLE_PLIST ${CMAKE_CURRENT_BINARY_DIR}/Info-iOS.plist)
    configure_file(cmake/Info-iOS.plist.in ${BUNDLE_PLIST} @ONLY)
    set(METAL_SDK iphoneos)
    set(METALLIB_DESTINATION "$<TARGET_BUNDLE_DIR:${APP_NAME}>/default.metallib")
else()
    set(PLATFORM_SOURCES
        src/macos/app/main.m
        src/macos/app/TMMacAppDelegate.h
        src/macos/app/TMMacAppDelegate.m
        src/macos/window/TMMacMetalView.h
        src/macos/window/TMMacMetalView.m
    )
    set(BUNDLE_PLIST ${CMAKE_CURRENT_BINARY_DIR}/Info-macOS.plist)
    configure_file(cmake/Info-macOS.plist.in ${BUNDLE_PLIST} @ONLY)
    set(METAL_SDK macosx)
    set(METALLIB_DESTINATION "$<TARGET_BUNDLE_DIR:${APP_NAME}>/Contents/Resources/default.metallib")
endif()

add_executable(${APP_NAME} MACOSX_BUNDLE
    ${COMMON_SOURCES}
    ${PLATFORM_SOURCES}
)

target_include_directories(${APP_NAME} PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/src/render
    ${CMAKE_CURRENT_SOURCE_DIR}/src/macos/app
    ${CMAKE_CURRENT_SOURCE_DIR}/src/macos/window
    ${CMAKE_CURRENT_SOURCE_DIR}/src/ios/app
    ${CMAKE_CURRENT_SOURCE_DIR}/src/ios/window
)

set_target_properties(${APP_NAME} PROPERTIES
    MACOSX_BUNDLE_INFO_PLIST ${BUNDLE_PLIST}
    XCODE_ATTRIBUTE_CLANG_ENABLE_OBJC_ARC YES
    XCODE_ATTRIBUTE_PRODUCT_BUNDLE_IDENTIFIER com.example.tinymetal
)

if(TINYMETAL_PLATFORM STREQUAL "iOS")
    set_target_properties(${APP_NAME} PROPERTIES
        XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED NO
        XCODE_ATTRIBUTE_IPHONEOS_DEPLOYMENT_TARGET 16.0
        XCODE_ATTRIBUTE_TARGETED_DEVICE_FAMILY "1,2"
    )
    target_link_libraries(${APP_NAME} PRIVATE
        "-framework Foundation"
        "-framework UIKit"
        "-framework QuartzCore"
        "-framework Metal"
    )
else()
    set_target_properties(${APP_NAME} PROPERTIES
        XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED NO
        XCODE_ATTRIBUTE_MACOSX_DEPLOYMENT_TARGET 13.0
    )
    target_link_libraries(${APP_NAME} PRIVATE
        "-framework Foundation"
        "-framework AppKit"
        "-framework QuartzCore"
        "-framework Metal"
    )
endif()

set(METAL_AIR ${CMAKE_CURRENT_BINARY_DIR}/HelloTriangleShaders.air)
set(METAL_LIBRARY ${CMAKE_CURRENT_BINARY_DIR}/default.metallib)

add_custom_command(
    OUTPUT ${METAL_LIBRARY}
    COMMAND xcrun -sdk ${METAL_SDK} metal -c ${METAL_SOURCE} -o ${METAL_AIR}
    COMMAND xcrun -sdk ${METAL_SDK} metallib ${METAL_AIR} -o ${METAL_LIBRARY}
    DEPENDS ${METAL_SOURCE}
    VERBATIM
)

add_custom_target(${APP_NAME}Shaders DEPENDS ${METAL_LIBRARY})
add_dependencies(${APP_NAME} ${APP_NAME}Shaders)

# Easy command to compile shaders
add_custom_target(compileshaders DEPENDS ${APP_NAME}Shaders)

add_custom_command(
    TARGET ${APP_NAME}
    POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy ${METAL_LIBRARY} ${METALLIB_DESTINATION}
    VERBATIM
)

if(NOT TINYMETAL_PLATFORM STREQUAL "iOS")
    enable_language(CXX)
    set(CMAKE_CXX_STANDARD 17)
    set(CMAKE_CXX_STANDARD_REQUIRED ON)

    FetchContent_Declare(
        meshoptimizer
        GIT_REPOSITORY https://github.com/zeux/meshoptimizer.git
        GIT_TAG v0.25
    )

    set(MESHOPT_BUILD_DEMO OFF CACHE BOOL "" FORCE)
    set(MESHOPT_BUILD_GLTFPACK OFF CACHE BOOL "" FORCE)
    set(MESHOPT_INSTALL OFF CACHE BOOL "" FORCE)
    FetchContent_MakeAvailable(meshoptimizer)

    FetchContent_Declare(
        tinyobjloader
        GIT_REPOSITORY https://github.com/syoyo/tinyobjloader.git
        GIT_TAG v1.0.6
    )
    FetchContent_MakeAvailable(tinyobjloader)

    FetchContent_Declare(
        glm
        GIT_REPOSITORY https://github.com/g-truc/glm.git
        GIT_TAG 1.0.1
    )
    FetchContent_MakeAvailable(glm)

    add_executable(tiny-mesh-tool
        tools/tiny_mesh_tool.cpp
    )

    target_link_libraries(tiny-mesh-tool PRIVATE meshoptimizer tinyobjloader glm::glm)

    # Easy command to run the main application
    add_custom_target(run
        COMMAND open $<TARGET_BUNDLE_DIR:${APP_NAME}>
        DEPENDS ${APP_NAME}
        COMMENT "Running ${APP_NAME}..."
    )

    # Easy command to run the tool
    add_custom_target(run-tool
        COMMAND $<TARGET_FILE:tiny-mesh-tool>
        DEPENDS tiny-mesh-tool
        COMMENT "Running tiny-mesh-tool..."
    )

    # Easy command to run CI verification (compiles shaders, builds app, and runs tool)
    add_custom_target(ci
        COMMAND $<TARGET_FILE:tiny-mesh-tool>
        DEPENDS ${APP_NAME} compileshaders tiny-mesh-tool
        COMMENT "Running CI verification..."
    )
endif()
