cmake_minimum_required(VERSION 3.25)
project(MSIMEClientIOS LANGUAGES OBJCXX)

set(CMAKE_OBJCXX_STANDARD 17)
set(CMAKE_OSX_SYSROOT iphoneos CACHE STRING "iPhoneOS SDK used for syntax/build checks")
set(CMAKE_OSX_DEPLOYMENT_TARGET "16.0" CACHE STRING "Minimum iOS version")
set(MSIME_HOST_LIBRARY "${CMAKE_CURRENT_SOURCE_DIR}/../../target/ios/libmsime_host_api.a" CACHE FILEPATH "Rust host static library for iOS")

if(NOT EXISTS "${MSIME_HOST_LIBRARY}")
  message(FATAL_ERROR "Build msime-host-api for iOS first")
endif()

add_library(msime-ios-keyboard STATIC
  KeyboardViewController.mm
  ../../shared/apple/MSIMEClientSession.mm
  ../../shared/apple/TextClient.mm)
target_compile_options(msime-ios-keyboard PRIVATE -fobjc-arc -Wall -Wextra -Werror)
target_include_directories(msime-ios-keyboard PUBLIC ../../shared/apple ../../crates/host-api/include)
target_link_libraries(msime-ios-keyboard PUBLIC "${MSIME_HOST_LIBRARY}" "-framework Foundation" "-framework UIKit")
