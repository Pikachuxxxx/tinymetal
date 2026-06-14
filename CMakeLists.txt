cmake_minimum_required(VERSION 3.25)

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
set(METAL_SOURCE ${CMAKE_CURRENT_SOURCE_DIR}/src/shared/TMShaders.metal)
set(COMMON_SOURCES
    src/shared/TMRenderer.h
    src/shared/TMRenderer.m
)

if(TINYMETAL_PLATFORM STREQUAL "iOS")
    set(PLATFORM_SOURCES
        src/ios/main.m
        src/ios/TMiOSAppDelegate.h
        src/ios/TMiOSAppDelegate.m
        src/ios/TMiOSMetalView.h
        src/ios/TMiOSMetalView.m
        src/ios/TMiOSSceneDelegate.h
        src/ios/TMiOSSceneDelegate.m
        src/ios/TMiOSViewController.h
        src/ios/TMiOSViewController.m
    )
    set(BUNDLE_PLIST ${CMAKE_CURRENT_BINARY_DIR}/Info-iOS.plist)
    configure_file(cmake/Info-iOS.plist.in ${BUNDLE_PLIST} @ONLY)
    set(METAL_SDK iphoneos)
    set(METALLIB_DESTINATION "$<TARGET_BUNDLE_DIR:${APP_NAME}>/default.metallib")
else()
    set(PLATFORM_SOURCES
        src/macos/main.m
        src/macos/TMMacAppDelegate.h
        src/macos/TMMacAppDelegate.m
        src/macos/TMMacMetalView.h
        src/macos/TMMacMetalView.m
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
    ${CMAKE_CURRENT_SOURCE_DIR}/src/shared
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

set(METAL_AIR ${CMAKE_CURRENT_BINARY_DIR}/TMShaders.air)
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

add_custom_command(
    TARGET ${APP_NAME}
    POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy ${METAL_LIBRARY} ${METALLIB_DESTINATION}
    VERBATIM
)
