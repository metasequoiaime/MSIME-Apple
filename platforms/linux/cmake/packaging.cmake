# Packaging is explicit and consumes the same installed files as CMake install.
# Never put a prepared user's runtime options into a redistributable package.
if(NOT CMAKE_SYSTEM_NAME STREQUAL "Linux")
  message(FATAL_ERROR "MSIME packaging requires a Linux build")
endif()
if(NOT CMAKE_INSTALL_PREFIX STREQUAL "/usr")
  message(FATAL_ERROR "Configure distributable Linux packages with CMAKE_INSTALL_PREFIX=/usr")
endif()
if(MSIME_RUNTIME_OPTIONS_FILE)
  message(FATAL_ERROR "Packaged builds must not include prepared runtime options; leave MSIME_RUNTIME_OPTIONS_FILE empty")
endif()
if(MSIME_LINUX_VOICE)
  message(FATAL_ERROR "Disable MSIME_LINUX_VOICE for packaging; it installs a development test executable")
endif()

# Use the desktop product's existing version; packaging has no separate version
# sequence. CMake's JSON reader avoids depending on Python during configuration.
file(READ "${CMAKE_CURRENT_SOURCE_DIR}/../../apps/desktop/src-tauri/tauri.conf.json" MSIME_DESKTOP_METADATA)
string(JSON CPACK_PACKAGE_VERSION GET "${MSIME_DESKTOP_METADATA}" version)
set(CPACK_PACKAGE_NAME "msime-client")
set(CPACK_PACKAGE_VENDOR "Metasequoia IME")
set(CPACK_PACKAGE_CONTACT "Metasequoia IME <metasequoiaime@gmail.com>")
set(CPACK_PACKAGE_DESCRIPTION_SUMMARY "MSIME Linux IBus host and desktop tools")
set(CPACK_PACKAGE_HOMEPAGE_URL "https://github.com/metasequoiaime/MSIME-Client")
set(CPACK_RESOURCE_FILE_LICENSE "${CMAKE_CURRENT_SOURCE_DIR}/../../LICENSE")
set(CPACK_GENERATOR "TGZ")
set(CPACK_SET_DESTDIR ON)
set(CPACK_PACKAGE_RELOCATABLE FALSE)
set(CPACK_PACKAGE_FILE_NAME "${CPACK_PACKAGE_NAME}-${CPACK_PACKAGE_VERSION}-linux-${CMAKE_SYSTEM_PROCESSOR}")
set(CPACK_DEBIAN_FILE_NAME DEB-DEFAULT)
set(CPACK_DEBIAN_PACKAGE_SECTION "utils")
set(CPACK_DEBIAN_PACKAGE_PRIORITY "optional")
set(CPACK_DEBIAN_PACKAGE_DEPENDS "ibus (>= 1.5.20), python3 (>= 3.9)")
set(CPACK_DEBIAN_PACKAGE_SHLIBDEPS ON)
get_filename_component(MSIME_HOST_LIBRARY_DIR "${MSIME_HOST_LIBRARY}" DIRECTORY)
set(CPACK_DEBIAN_PACKAGE_SHLIBDEPS_PRIVATE_DIRS "${MSIME_HOST_LIBRARY_DIR}")

install(FILES "${CMAKE_CURRENT_SOURCE_DIR}/../../LICENSE"
        DESTINATION "${CMAKE_INSTALL_DATADIR}/doc/msime-client" RENAME copyright)
install(FILES "${CMAKE_CURRENT_SOURCE_DIR}/README.md"
        DESTINATION "${CMAKE_INSTALL_DATADIR}/doc/msime-client" RENAME README.md)
include(CPack)
