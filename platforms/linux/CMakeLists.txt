cmake_minimum_required(VERSION 3.25)
project(MSIMEClientLinux LANGUAGES CXX)
include(GNUInstallDirs)
configure_file(cmake/uninstall.cmake.in ${CMAKE_CURRENT_BINARY_DIR}/uninstall.cmake @ONLY)
add_custom_target(uninstall
  COMMAND "${CMAKE_COMMAND}" -P "${CMAKE_CURRENT_BINARY_DIR}/uninstall.cmake"
  COMMENT "Remove installed MSIME files while preserving runtime configuration")
include(CTest)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
find_package(PkgConfig REQUIRED)
pkg_check_modules(IBUS REQUIRED IMPORTED_TARGET ibus-1.0>=1.5.20)
pkg_check_modules(XKBCOMMON REQUIRED IMPORTED_TARGET xkbcommon)
pkg_check_modules(ICU REQUIRED IMPORTED_TARGET icu-i18n icu-uc)
find_package(nlohmann_json 3.11 REQUIRED)
# Optional on Wayland-only systems; the monitor retains bounded polling.
pkg_check_modules(X11_CLIPBOARD QUIET IMPORTED_TARGET x11 xfixes)
pkg_check_modules(X11_SURFACE QUIET IMPORTED_TARGET x11 xfixes)
pkg_check_modules(WAYLAND_CLIENT QUIET IMPORTED_TARGET wayland-client)
pkg_check_modules(WAYLAND_TEXT QUIET IMPORTED_TARGET pangocairo)
find_program(WAYLAND_SCANNER_EXECUTABLE wayland-scanner)
if(WAYLAND_CLIENT_FOUND AND WAYLAND_SCANNER_EXECUTABLE)
  enable_language(C)
  set(MSIME_WAYLAND_PROTOCOL_DIR "${CMAKE_CURRENT_BINARY_DIR}/wayland-protocols")
  set(MSIME_LAYER_SHELL_HEADER
      "${MSIME_WAYLAND_PROTOCOL_DIR}/wlr-layer-shell-unstable-v1-client-protocol.h")
  set(MSIME_LAYER_SHELL_CODE
      "${MSIME_WAYLAND_PROTOCOL_DIR}/wlr-layer-shell-unstable-v1-protocol.c")
  find_path(MSIME_XDG_SHELL_DIR NAMES xdg-shell.xml
            PATHS /usr/share/wayland-protocols/stable/xdg-shell
                  /usr/local/share/wayland-protocols/stable/xdg-shell)
  set(MSIME_XDG_SHELL_XML "${MSIME_XDG_SHELL_DIR}/xdg-shell.xml")
  set(MSIME_XDG_SHELL_HEADER
      "${MSIME_WAYLAND_PROTOCOL_DIR}/xdg-shell-client-protocol.h")
  set(MSIME_XDG_SHELL_CODE
      "${MSIME_WAYLAND_PROTOCOL_DIR}/xdg-shell-protocol.c")
  if(NOT EXISTS "${MSIME_XDG_SHELL_XML}")
    unset(MSIME_XDG_SHELL_XML)
  endif()
  add_custom_command(
    OUTPUT "${MSIME_LAYER_SHELL_HEADER}" "${MSIME_LAYER_SHELL_CODE}"
    COMMAND "${CMAKE_COMMAND}" -E make_directory "${MSIME_WAYLAND_PROTOCOL_DIR}"
    COMMAND "${WAYLAND_SCANNER_EXECUTABLE}" client-header
            "${CMAKE_CURRENT_SOURCE_DIR}/data/wayland/wlr-layer-shell-unstable-v1.xml"
            "${MSIME_LAYER_SHELL_HEADER}"
    COMMAND "${WAYLAND_SCANNER_EXECUTABLE}" private-code
            "${CMAKE_CURRENT_SOURCE_DIR}/data/wayland/wlr-layer-shell-unstable-v1.xml"
            "${MSIME_LAYER_SHELL_CODE}"
    DEPENDS data/wayland/wlr-layer-shell-unstable-v1.xml)
  if(MSIME_XDG_SHELL_XML)
    add_custom_command(
      OUTPUT "${MSIME_XDG_SHELL_HEADER}" "${MSIME_XDG_SHELL_CODE}"
      COMMAND "${CMAKE_COMMAND}" -E make_directory "${MSIME_WAYLAND_PROTOCOL_DIR}"
      COMMAND "${WAYLAND_SCANNER_EXECUTABLE}" client-header
              "${MSIME_XDG_SHELL_XML}" "${MSIME_XDG_SHELL_HEADER}"
      COMMAND "${WAYLAND_SCANNER_EXECUTABLE}" private-code
              "${MSIME_XDG_SHELL_XML}" "${MSIME_XDG_SHELL_CODE}"
      DEPENDS "${MSIME_XDG_SHELL_XML}")
  endif()
endif()
if(X11_CLIPBOARD_FOUND)
  add_executable(msime-client-clipboard-watch-x11 clipboard_watch_x11.cpp)
  target_compile_options(msime-client-clipboard-watch-x11 PRIVATE -Wall -Wextra -Werror)
  target_link_libraries(msime-client-clipboard-watch-x11 PRIVATE PkgConfig::X11_CLIPBOARD)
  install(TARGETS msime-client-clipboard-watch-x11 RUNTIME DESTINATION "${CMAKE_INSTALL_BINDIR}" COMPONENT clipboard-watch)
  if(BUILD_TESTING)
    add_executable(msime-test-x11-string-owner tests/clipboard_x11_string_owner.cpp)
    target_compile_options(msime-test-x11-string-owner PRIVATE -Wall -Wextra -Werror)
    target_link_libraries(msime-test-x11-string-owner PRIVATE PkgConfig::X11_CLIPBOARD)
  endif()
endif()
option(MSIME_LINUX_VOICE "Build voice worker test" OFF)
set(MSIME_HOST_LIBRARY "${CMAKE_CURRENT_SOURCE_DIR}/../../target/debug/libmsime_host_api.so" CACHE FILEPATH "Cargo-built Linux host library")
set(MSIME_RUNTIME_OPTIONS_FILE "" CACHE FILEPATH "Prepared runtime options")
set(MSIME_DESKTOP_BINARY "" CACHE FILEPATH "Cargo-built Tauri desktop binary")
set(MSIME_HANDWRITING_MODEL "${CMAKE_CURRENT_SOURCE_DIR}/../../vendor/MSIME-Engine/handwriting/models/handwriting-zh_CN.model" CACHE FILEPATH "Trusted packaged handwriting model")
set(MSIME_EMOJI_RESOURCES "" CACHE PATH "Trusted packaged Engine Emoji resource directory")
set(MSIME_ENGINE_RESOURCES "" CACHE PATH "Trusted packaged Engine desktop resource directory")
if(NOT EXISTS "${MSIME_HOST_LIBRARY}")
  message(FATAL_ERROR "Build msime-host-api for Linux first")
endif()
add_library(msime-ibus-host STATIC
  ClientEngine.cpp DiagnosticLog.cpp ChineseTextConversion.cpp WaveOverlayIbusSurface.cpp
  WaveOverlaySurfaceFactory.cpp)
target_compile_options(msime-ibus-host PRIVATE -Wall -Wextra -Werror)
target_include_directories(msime-ibus-host PUBLIC . ../../crates/host-api/include)
target_link_libraries(msime-ibus-host PUBLIC PkgConfig::IBUS PkgConfig::XKBCOMMON PkgConfig::ICU nlohmann_json::nlohmann_json "${MSIME_HOST_LIBRARY}")
if(X11_SURFACE_FOUND)
  target_sources(msime-ibus-host PRIVATE WaveOverlayX11Surface.cpp)
  target_compile_definitions(msime-ibus-host PRIVATE MSIME_LINUX_HAS_X11_SURFACE)
  target_link_libraries(msime-ibus-host PUBLIC PkgConfig::X11_SURFACE)
endif()
if(WAYLAND_CLIENT_FOUND AND WAYLAND_SCANNER_EXECUTABLE AND MSIME_XDG_SHELL_XML)
  target_sources(msime-ibus-host PRIVATE WaveOverlayWaylandSurface.cpp
                 "${MSIME_LAYER_SHELL_CODE}" ${MSIME_XDG_SHELL_CODE})
  target_include_directories(msime-ibus-host PRIVATE "${MSIME_WAYLAND_PROTOCOL_DIR}")
  target_compile_definitions(msime-ibus-host PRIVATE MSIME_LINUX_HAS_WAYLAND_SURFACE)
  target_link_libraries(msime-ibus-host PUBLIC PkgConfig::WAYLAND_CLIENT)
  if(WAYLAND_TEXT_FOUND)
    target_compile_definitions(msime-ibus-host PRIVATE MSIME_LINUX_WAYLAND_TEXT)
    target_link_libraries(msime-ibus-host PUBLIC PkgConfig::WAYLAND_TEXT)
  endif()
endif()
add_executable(msime-client-ibus main.cpp SystemTheme.cpp)
target_compile_options(msime-client-ibus PRIVATE -Wall -Wextra -Werror)
target_link_libraries(msime-client-ibus PRIVATE msime-ibus-host)
add_executable(msime-client-dictionary dictionary_request.cpp)
add_executable(msime-client-prepare prepare_host.cpp)
target_compile_options(msime-client-prepare PRIVATE -Wall -Wextra -Werror)
target_link_libraries(msime-client-prepare PRIVATE msime-ibus-host)
file(RELATIVE_PATH MSIME_INSTALLED_RESOURCE_RELATIVE_DIR
     "${CMAKE_INSTALL_FULL_BINDIR}"
     "${CMAKE_INSTALL_FULL_DATADIR}/msime-client/resources")
target_compile_definitions(msime-client-prepare PRIVATE
  MSIME_INSTALLED_RESOURCE_RELATIVE_DIR="${MSIME_INSTALLED_RESOURCE_RELATIVE_DIR}")
target_compile_options(msime-client-dictionary PRIVATE -Wall -Wextra -Werror)
target_link_libraries(msime-client-dictionary PRIVATE msime-ibus-host)
add_executable(msime-client-cloud-dictionary cloud_dictionary_request.cpp)
target_compile_options(msime-client-cloud-dictionary PRIVATE -Wall -Wextra -Werror)
target_link_libraries(msime-client-cloud-dictionary PRIVATE msime-ibus-host)
add_executable(msime-client-cloud-clipboard cloud_clipboard_request.cpp)
target_compile_options(msime-client-cloud-clipboard PRIVATE -Wall -Wextra -Werror)
target_link_libraries(msime-client-cloud-clipboard PRIVATE msime-ibus-host)
add_executable(msime-client-online online_request.cpp)
target_compile_options(msime-client-online PRIVATE -Wall -Wextra -Werror)
target_link_libraries(msime-client-online PRIVATE msime-ibus-host)
add_executable(msime-client-translation translation_request.cpp)
target_compile_options(msime-client-translation PRIVATE -Wall -Wextra -Werror)
target_link_libraries(msime-client-translation PRIVATE msime-ibus-host)
add_executable(msime-client-clipboard clipboard_history.cpp)
target_compile_options(msime-client-clipboard PRIVATE -Wall -Wextra -Werror)
add_executable(msime-client-clipboard-capture clipboard_capture.cpp)
target_compile_options(msime-client-clipboard-capture PRIVATE -Wall -Wextra -Werror)
target_link_libraries(msime-client-clipboard-capture PRIVATE msime-ibus-host)
add_executable(msime-client-handwriting handwriting_request.cpp)
target_compile_options(msime-client-handwriting PRIVATE -Wall -Wextra -Werror)
target_link_libraries(msime-client-handwriting PRIVATE msime-ibus-host)
add_executable(msime-client-voice voice_request.cpp)
target_compile_options(msime-client-voice PRIVATE -Wall -Wextra -Werror)
target_link_libraries(msime-client-voice PRIVATE msime-ibus-host)
add_executable(msime-client-emoji emoji_request.cpp)
target_compile_options(msime-client-emoji PRIVATE -Wall -Wextra -Werror)
target_link_libraries(msime-client-emoji PRIVATE msime-ibus-host)
add_executable(ibus-engine-smoke tests/engine_smoke.cpp)
target_compile_options(ibus-engine-smoke PRIVATE -Wall -Wextra -Werror)
target_link_libraries(ibus-engine-smoke PRIVATE msime-ibus-host)
add_executable(linux-navigation-bindings-test tests/navigation_bindings.cpp)
target_compile_options(linux-navigation-bindings-test PRIVATE -Wall -Wextra -Werror)
target_include_directories(linux-navigation-bindings-test PRIVATE . ../../crates/host-api/include)
add_test(NAME linux-navigation-bindings COMMAND linux-navigation-bindings-test)
add_executable(linux-candidate-palette-test tests/candidate_palette.cpp)
target_compile_options(linux-candidate-palette-test PRIVATE -Wall -Wextra -Werror)
target_include_directories(linux-candidate-palette-test PRIVATE .)
add_test(NAME linux-candidate-palette COMMAND linux-candidate-palette-test)
add_executable(linux-candidate-action-policy-test tests/candidate_action_policy.cpp)
target_compile_options(linux-candidate-action-policy-test PRIVATE -Wall -Wextra -Werror)
target_include_directories(linux-candidate-action-policy-test PRIVATE .)
add_test(NAME linux-candidate-action-policy COMMAND linux-candidate-action-policy-test)
add_executable(linux-paired-punctuation-test tests/paired_punctuation.cpp)
target_compile_options(linux-paired-punctuation-test PRIVATE -Wall -Wextra -Werror)
target_include_directories(linux-paired-punctuation-test PRIVATE .)
add_test(NAME linux-paired-punctuation COMMAND linux-paired-punctuation-test)
add_executable(linux-prepare-paths-test tests/prepare_paths.cpp)
target_compile_options(linux-prepare-paths-test PRIVATE -Wall -Wextra -Werror)
target_include_directories(linux-prepare-paths-test PRIVATE .)
add_test(NAME linux-prepare-paths COMMAND linux-prepare-paths-test)
add_executable(linux-key-router-adapter-test tests/key_router_adapter.cpp)
target_compile_options(linux-key-router-adapter-test PRIVATE -Wall -Wextra -Werror)
target_include_directories(linux-key-router-adapter-test PRIVATE . ../../crates/host-api/include)
add_test(NAME linux-key-router-adapter COMMAND linux-key-router-adapter-test)
add_executable(linux-diagnostic-log-test tests/diagnostic_log.cpp)
target_compile_options(linux-diagnostic-log-test PRIVATE -Wall -Wextra -Werror)
target_include_directories(linux-diagnostic-log-test PRIVATE .)
target_sources(linux-diagnostic-log-test PRIVATE DiagnosticLog.cpp)
add_test(NAME linux-diagnostic-log COMMAND linux-diagnostic-log-test)
add_executable(linux-traditional-output-test tests/traditional_output.cpp ChineseTextConversion.cpp)
target_compile_options(linux-traditional-output-test PRIVATE -Wall -Wextra -Werror)
target_link_libraries(linux-traditional-output-test PRIVATE PkgConfig::ICU)
add_test(NAME linux-traditional-output COMMAND linux-traditional-output-test)
if(MSIME_LINUX_VOICE)
 add_executable(msime-voice-worker-test tests/voice_worker.cpp)
 target_compile_options(msime-voice-worker-test PRIVATE -Wall -Wextra -Werror)
 target_include_directories(msime-voice-worker-test PRIVATE .)
 add_test(NAME linux-voice-worker COMMAND msime-voice-worker-test)
endif()
configure_file(msime-client-preview.xml.in ${CMAKE_CURRENT_BINARY_DIR}/msime-client-preview.xml @ONLY)
install(TARGETS msime-client-ibus msime-client-dictionary msime-client-cloud-dictionary msime-client-cloud-clipboard msime-client-online msime-client-translation msime-client-clipboard
                msime-client-handwriting msime-client-voice msime-client-emoji msime-client-clipboard-capture msime-client-prepare
                RUNTIME DESTINATION "${CMAKE_INSTALL_BINDIR}")
if(MSIME_LINUX_VOICE)
 install(TARGETS msime-voice-worker-test RUNTIME DESTINATION "${CMAKE_INSTALL_BINDIR}")
endif()
install(PROGRAMS msime-client-ibus-launcher msime-client-online-provider msime-client-voice-provider msime-client-provider-session DESTINATION "${CMAKE_INSTALL_BINDIR}")
install(PROGRAMS msime-client-clipboard-monitor DESTINATION "${CMAKE_INSTALL_BINDIR}")
set(MSIME_SYSTEMD_USER_UNIT_DIR "${CMAKE_INSTALL_DATADIR}/systemd/user" CACHE PATH "systemd user unit installation directory")
foreach(MSIME_PROVIDER online voice clipboard)
  configure_file(data/msime-client-${MSIME_PROVIDER}.service.in
                 ${CMAKE_CURRENT_BINARY_DIR}/msime-client-${MSIME_PROVIDER}.service @ONLY)
  install(FILES ${CMAKE_CURRENT_BINARY_DIR}/msime-client-${MSIME_PROVIDER}.service
          DESTINATION "${MSIME_SYSTEMD_USER_UNIT_DIR}")
endforeach()
install(FILES msime_voice_doubao.py msime_provider_runtime.py DESTINATION "${CMAKE_INSTALL_BINDIR}")
install(FILES requirements-voice.txt DESTINATION "${CMAKE_INSTALL_DATADIR}/msime-client")
file(RELATIVE_PATH MSIME_VOICE_CUE_RELATIVE "${CMAKE_INSTALL_FULL_BINDIR}"
     "${CMAKE_INSTALL_FULL_DATADIR}/msime-client/voice")
configure_file(msime_voice_paths.py.in msime_voice_paths.py @ONLY)
install(FILES "${CMAKE_CURRENT_BINARY_DIR}/msime_voice_paths.py" DESTINATION "${CMAKE_INSTALL_BINDIR}")
install(FILES data/voice/start.pcm data/voice/end.pcm data/voice/SOURCE.md
        DESTINATION "${CMAKE_INSTALL_DATADIR}/msime-client/voice")
if(MSIME_HANDWRITING_MODEL AND EXISTS "${MSIME_HANDWRITING_MODEL}")
  install(FILES "${MSIME_HANDWRITING_MODEL}" DESTINATION "${CMAKE_INSTALL_DATADIR}/msime-client/handwriting"
          RENAME handwriting-zh_CN.model)
  get_filename_component(MSIME_HANDWRITING_MODEL_DIR "${MSIME_HANDWRITING_MODEL}" DIRECTORY)
  foreach(MSIME_HANDWRITING_NOTICE HandwritingModel-LICENSE.txt provenance.json)
    if(EXISTS "${MSIME_HANDWRITING_MODEL_DIR}/${MSIME_HANDWRITING_NOTICE}")
      install(FILES "${MSIME_HANDWRITING_MODEL_DIR}/${MSIME_HANDWRITING_NOTICE}"
              DESTINATION "${CMAKE_INSTALL_DATADIR}/msime-client/handwriting")
    endif()
  endforeach()
endif()
if(MSIME_EMOJI_RESOURCES)
  if(NOT IS_DIRECTORY "${MSIME_EMOJI_RESOURCES}")
    message(FATAL_ERROR "MSIME_EMOJI_RESOURCES is not a directory: ${MSIME_EMOJI_RESOURCES}")
  endif()
  install(DIRECTORY "${MSIME_EMOJI_RESOURCES}/"
          DESTINATION "${CMAKE_INSTALL_DATADIR}/msime-client/emoji")
endif()
if(MSIME_ENGINE_RESOURCES)
  if(NOT IS_DIRECTORY "${MSIME_ENGINE_RESOURCES}")
    message(FATAL_ERROR "MSIME_ENGINE_RESOURCES is not a directory: ${MSIME_ENGINE_RESOURCES}")
  endif()
  file(READ "${CMAKE_CURRENT_SOURCE_DIR}/../../resources/desktop-dictionary.lock.json"
       MSIME_ENGINE_RESOURCE_LOCK)
  string(JSON MSIME_ENGINE_RESOURCE_COUNT LENGTH "${MSIME_ENGINE_RESOURCE_LOCK}" artifacts)
  math(EXPR MSIME_ENGINE_RESOURCE_LAST "${MSIME_ENGINE_RESOURCE_COUNT} - 1")
  foreach(MSIME_ENGINE_RESOURCE_INDEX RANGE 0 ${MSIME_ENGINE_RESOURCE_LAST})
    string(JSON MSIME_ENGINE_RESOURCE_NAME GET "${MSIME_ENGINE_RESOURCE_LOCK}"
           artifacts ${MSIME_ENGINE_RESOURCE_INDEX} name)
    set(MSIME_ENGINE_RESOURCE_FILE "${MSIME_ENGINE_RESOURCES}/${MSIME_ENGINE_RESOURCE_NAME}")
    if(NOT EXISTS "${MSIME_ENGINE_RESOURCE_FILE}" OR
       IS_DIRECTORY "${MSIME_ENGINE_RESOURCE_FILE}" OR
       IS_SYMLINK "${MSIME_ENGINE_RESOURCE_FILE}")
      message(FATAL_ERROR "Missing Engine resource ${MSIME_ENGINE_RESOURCE_NAME} in ${MSIME_ENGINE_RESOURCES}")
    endif()
    string(JSON MSIME_ENGINE_RESOURCE_SIZE GET "${MSIME_ENGINE_RESOURCE_LOCK}"
           artifacts ${MSIME_ENGINE_RESOURCE_INDEX} size)
    string(JSON MSIME_ENGINE_RESOURCE_SHA256 GET "${MSIME_ENGINE_RESOURCE_LOCK}"
           artifacts ${MSIME_ENGINE_RESOURCE_INDEX} sha256)
    file(SIZE "${MSIME_ENGINE_RESOURCE_FILE}" MSIME_ENGINE_RESOURCE_ACTUAL_SIZE)
    file(SHA256 "${MSIME_ENGINE_RESOURCE_FILE}" MSIME_ENGINE_RESOURCE_ACTUAL_SHA256)
    if(NOT MSIME_ENGINE_RESOURCE_ACTUAL_SIZE STREQUAL MSIME_ENGINE_RESOURCE_SIZE OR
       NOT MSIME_ENGINE_RESOURCE_ACTUAL_SHA256 STREQUAL MSIME_ENGINE_RESOURCE_SHA256)
      message(FATAL_ERROR
        "Engine resource ${MSIME_ENGINE_RESOURCE_NAME} does not match the reviewed lock")
    endif()
    install(FILES "${MSIME_ENGINE_RESOURCE_FILE}"
            DESTINATION "${CMAKE_INSTALL_DATADIR}/msime-client/resources")
  endforeach()
  # Keep the reviewed lock beside the installed bundle as provenance metadata;
  # it is not copied into the runtime directory because the Engine verifier
  # requires that directory to contain exactly the pinned artifacts.
  install(FILES "${CMAKE_CURRENT_SOURCE_DIR}/../../resources/desktop-dictionary.lock.json"
          DESTINATION "${CMAKE_INSTALL_DATADIR}/msime-client")
endif()
if(MSIME_DESKTOP_BINARY)
  if(NOT EXISTS "${MSIME_DESKTOP_BINARY}")
    message(FATAL_ERROR "MSIME_DESKTOP_BINARY does not exist: ${MSIME_DESKTOP_BINARY}")
  endif()
  # Quote the configured path as one POSIX shell word, including apostrophes.
  string(REPLACE "'" "'\\''" MSIME_SETTINGS_SYSTEM_CONFIG
         "${CMAKE_INSTALL_FULL_SYSCONFDIR}/msime-client/runtime-options.json")
  configure_file(msime-client-settings.in ${CMAKE_CURRENT_BINARY_DIR}/msime-client-settings @ONLY)
  configure_file(data/msime-client.desktop.in ${CMAKE_CURRENT_BINARY_DIR}/msime-client.desktop @ONLY)
  install(PROGRAMS "${MSIME_DESKTOP_BINARY}" DESTINATION "${CMAKE_INSTALL_BINDIR}" RENAME msime-client-desktop)
  install(PROGRAMS ${CMAKE_CURRENT_BINARY_DIR}/msime-client-settings DESTINATION "${CMAKE_INSTALL_BINDIR}")
  install(FILES ${CMAKE_CURRENT_BINARY_DIR}/msime-client.desktop DESTINATION "${CMAKE_INSTALL_DATADIR}/applications")
endif()
if(MSIME_RUNTIME_OPTIONS_FILE)
 install(FILES "${MSIME_RUNTIME_OPTIONS_FILE}" DESTINATION "${CMAKE_INSTALL_SYSCONFDIR}/msime-client" RENAME runtime-options.json)
endif()
install(FILES ${CMAKE_CURRENT_BINARY_DIR}/msime-client-preview.xml DESTINATION "${CMAKE_INSTALL_DATADIR}/ibus/component")
install(FILES "${MSIME_HOST_LIBRARY}" DESTINATION "${CMAKE_INSTALL_LIBDIR}/msime-client")
file(RELATIVE_PATH MSIME_HOST_LIBRARY_RELATIVE_DIR
  "${CMAKE_INSTALL_FULL_BINDIR}" "${CMAKE_INSTALL_FULL_LIBDIR}/msime-client")
set_target_properties(msime-client-ibus msime-client-dictionary msime-client-cloud-dictionary msime-client-cloud-clipboard msime-client-online msime-client-translation msime-client-handwriting
                      msime-client-voice msime-client-emoji msime-client-clipboard-capture msime-client-prepare PROPERTIES
  INSTALL_RPATH "$ORIGIN/${MSIME_HOST_LIBRARY_RELATIVE_DIR}")

add_executable(linux-native-compose-test tests/native_compose.cpp)
add_executable(linux-wave-overlay-model-test
  tests/wave_overlay_model.cpp WaveOverlayIbusSurface.cpp
  WaveOverlaySurfaceFactory.cpp)
target_compile_features(linux-wave-overlay-model-test PRIVATE cxx_std_17)
target_compile_options(linux-wave-overlay-model-test PRIVATE -Wall -Wextra -Werror)
target_link_libraries(linux-wave-overlay-model-test PRIVATE PkgConfig::IBUS)
if(X11_SURFACE_FOUND)
  target_sources(linux-wave-overlay-model-test PRIVATE WaveOverlayX11Surface.cpp)
  target_compile_definitions(linux-wave-overlay-model-test PRIVATE MSIME_LINUX_HAS_X11_SURFACE)
  target_link_libraries(linux-wave-overlay-model-test PRIVATE PkgConfig::X11_SURFACE)
endif()
if(WAYLAND_CLIENT_FOUND AND WAYLAND_SCANNER_EXECUTABLE AND MSIME_XDG_SHELL_XML)
  target_sources(linux-wave-overlay-model-test PRIVATE
                 WaveOverlayWaylandSurface.cpp "${MSIME_LAYER_SHELL_CODE}"
                 ${MSIME_XDG_SHELL_CODE})
  target_include_directories(linux-wave-overlay-model-test PRIVATE
                             "${MSIME_WAYLAND_PROTOCOL_DIR}")
  target_compile_definitions(linux-wave-overlay-model-test PRIVATE
                             MSIME_LINUX_HAS_WAYLAND_SURFACE)
  target_link_libraries(linux-wave-overlay-model-test PRIVATE
                        PkgConfig::WAYLAND_CLIENT)
  if(WAYLAND_TEXT_FOUND)
    target_compile_definitions(linux-wave-overlay-model-test PRIVATE
                               MSIME_LINUX_WAYLAND_TEXT)
    target_link_libraries(linux-wave-overlay-model-test PRIVATE
                          PkgConfig::WAYLAND_TEXT)
  endif()
endif()
add_test(NAME linux-wave-overlay-model COMMAND linux-wave-overlay-model-test)
target_compile_options(linux-native-compose-test PRIVATE -Wall -Wextra -Werror)
target_include_directories(linux-native-compose-test PRIVATE .)
target_link_libraries(linux-native-compose-test PRIVATE PkgConfig::XKBCOMMON)
add_test(NAME linux-native-compose COMMAND linux-native-compose-test
  "${CMAKE_CURRENT_SOURCE_DIR}/tests/compose.fixture")

option(MSIME_ENABLE_PACKAGING "Enable Linux TGZ and Debian package generation" OFF)
if(MSIME_ENABLE_PACKAGING)
  include(cmake/packaging.cmake)
endif()
