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

# CMakeLists.txt resolves the version before the IBus host is compiled, because the host reports the same version at startup.
set(CPACK_PACKAGE_VERSION "${MSIME_LINUX_VERSION}")
set(CPACK_PACKAGE_NAME "msime-client")
set(CPACK_PACKAGE_VENDOR "Metasequoia IME")
set(CPACK_PACKAGE_CONTACT "Metasequoia IME <metasequoiaime@gmail.com>")
set(CPACK_PACKAGE_DESCRIPTION_SUMMARY "MSIME Linux IBus host and desktop tools (Fcitx5 addon available)")
set(CPACK_PACKAGE_HOMEPAGE_URL "https://github.com/metasequoiaime/msime")
set(CPACK_RESOURCE_FILE_LICENSE "${CMAKE_CURRENT_SOURCE_DIR}/../../LICENSE")
set(CPACK_GENERATOR "TGZ")
set(CPACK_SET_DESTDIR ON)
set(CPACK_PACKAGE_RELOCATABLE FALSE)
set(CPACK_PACKAGE_FILE_NAME "${CPACK_PACKAGE_NAME}-${CPACK_PACKAGE_VERSION}-linux-${CMAKE_SYSTEM_PROCESSOR}")
set(CPACK_DEBIAN_FILE_NAME DEB-DEFAULT)
set(CPACK_DEBIAN_PACKAGE_SECTION "utils")
set(CPACK_DEBIAN_PACKAGE_PRIORITY "optional")
set(CPACK_DEBIAN_PACKAGE_DEPENDS "ibus (>= 1.5.20), python3 (>= 3.9)")
if(MSIME_ENABLE_FCITX5)
  string(APPEND CPACK_DEBIAN_PACKAGE_DEPENDS ", fcitx5 (>= 5.0.20)")
endif()
# Voice runtime: Doubao streaming needs the websockets sync client from 15.0 on, recording needs one of parec, pw-cat or arecord. Recommends rather than Depends, because the voice service starts without them and only the requests that need them fail.
set(CPACK_DEBIAN_PACKAGE_RECOMMENDS "python3-websockets (>= 15), pulseaudio-utils | pipewire-bin | alsa-utils")
set(CPACK_DEBIAN_PACKAGE_SHLIBDEPS ON)
get_filename_component(MSIME_HOST_LIBRARY_DIR "${MSIME_HOST_LIBRARY}" DIRECTORY)
# libsherpa-onnx-c-api.so needs libonnxruntime.so, which ships beside it in the same private directory rather than coming from a Debian package.
set(CPACK_DEBIAN_PACKAGE_SHLIBDEPS_PRIVATE_DIRS "${MSIME_HOST_LIBRARY_DIR};${MSIME_VOICE_RUNTIME_DIR}")
# prerm stops and disables the user units of logged-in users on removal and postinst restarts running services after an upgrade; CMakeLists.txt configures both from the unit list the CMake uninstall uses.
# The clipboard XDG autostart entry is the package's one file under /etc (a /usr prefix puts MSIME_XDG_AUTOSTART_DIR there), and Debian policy requires /etc files to be conffiles so an administrator who edits or deletes it keeps that change across upgrades. CPack's DEB generator marks nothing by itself; the list travels as a control file like the maintainer scripts.
file(CONFIGURE OUTPUT "${CMAKE_CURRENT_BINARY_DIR}/debian/conffiles"
     CONTENT "${MSIME_XDG_AUTOSTART_DIR}/msime-client-clipboard.desktop\n")
set(CPACK_DEBIAN_PACKAGE_CONTROL_EXTRA "${CMAKE_CURRENT_BINARY_DIR}/debian/prerm;${CMAKE_CURRENT_BINARY_DIR}/debian/postinst;${CMAKE_CURRENT_BINARY_DIR}/debian/conffiles")
set(CPACK_DEBIAN_PACKAGE_CONTROL_STRICT_PERMISSION ON)

# The license (as copyright) and the third-party notices are installed by CMakeLists.txt for every install; configuration already failed there if any of them was missing.
install(FILES "${CMAKE_CURRENT_SOURCE_DIR}/README.md"
        DESTINATION "${CMAKE_INSTALL_DATADIR}/doc/msime-client" RENAME README.md)
include(CPack)
