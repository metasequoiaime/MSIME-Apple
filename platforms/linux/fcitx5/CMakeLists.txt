cmake_minimum_required(VERSION 3.25)
project(MSIMEClientFcitx5 LANGUAGES CXX)
include(GNUInstallDirs)
include(CTest)
find_package(Fcitx5Core 5.0.20 REQUIRED)
find_package(nlohmann_json 3.11 REQUIRED)
set(MSIME_HOST_LIBRARY "${CMAKE_CURRENT_SOURCE_DIR}/../../../target/debug/libmsime_host_api.so" CACHE FILEPATH "Cargo-built Linux Host API")
if(NOT EXISTS "${MSIME_HOST_LIBRARY}")
  message(FATAL_ERROR "Build msime-host-api for Linux first")
endif()
set(MSIME_FCITX5_ADDON_DIR "${CMAKE_INSTALL_LIBDIR}/fcitx5" CACHE PATH "Fcitx5 addon directory")
add_library(msime-fcitx5 MODULE FcitxEngine.cpp)
target_compile_features(msime-fcitx5 PRIVATE cxx_std_17)
target_compile_options(msime-fcitx5 PRIVATE -Wall -Wextra -Werror)
target_include_directories(msime-fcitx5 PRIVATE ../../../crates/host-api/include)
target_link_libraries(msime-fcitx5 PRIVATE Fcitx5::Core nlohmann_json::nlohmann_json "${MSIME_HOST_LIBRARY}")
target_compile_definitions(msime-fcitx5 PRIVATE MSIME_SYSTEM_OPTIONS="${CMAKE_INSTALL_FULL_SYSCONFDIR}/msime-client/runtime-options.json")
file(RELATIVE_PATH MSIME_FCITX5_HOST_RELATIVE "${CMAKE_INSTALL_PREFIX}/${MSIME_FCITX5_ADDON_DIR}" "${CMAKE_INSTALL_FULL_LIBDIR}/msime-client")
set_target_properties(msime-fcitx5 PROPERTIES INSTALL_RPATH "$ORIGIN/${MSIME_FCITX5_HOST_RELATIVE}")
install(TARGETS msime-fcitx5 LIBRARY DESTINATION "${MSIME_FCITX5_ADDON_DIR}")
install(FILES "${MSIME_HOST_LIBRARY}" DESTINATION "${CMAKE_INSTALL_LIBDIR}/msime-client")
install(FILES msime.conf DESTINATION "${CMAKE_INSTALL_DATADIR}/fcitx5/addon")
install(FILES msime-inputmethod.conf DESTINATION "${CMAKE_INSTALL_DATADIR}/fcitx5/inputmethod" RENAME msime.conf)
if(BUILD_TESTING)
  add_executable(fcitx5-native-test tests/native.cpp)
  target_compile_features(fcitx5-native-test PRIVATE cxx_std_17)
  target_compile_options(fcitx5-native-test PRIVATE -Wall -Wextra -Werror)
  target_include_directories(fcitx5-native-test PRIVATE ../../../crates/host-api/include)
  target_link_libraries(fcitx5-native-test PRIVATE Fcitx5::Core nlohmann_json::nlohmann_json "${MSIME_HOST_LIBRARY}")
  set(MSIME_FCITX5_TEST_RESOURCES "" CACHE PATH "Verified resources directory for the native Fcitx5 test")
  if(MSIME_FCITX5_TEST_RESOURCES)
    add_test(NAME fcitx5-native-context
      COMMAND fcitx5-native-test "${MSIME_FCITX5_TEST_RESOURCES}")
    add_test(NAME fcitx5-native-ai
      COMMAND fcitx5-native-test "${MSIME_FCITX5_TEST_RESOURCES}" --ai)
    find_package(Python3 COMPONENTS Interpreter)
    find_program(DBUS_RUN_SESSION dbus-run-session)
    if(Python3_Interpreter_FOUND AND DBUS_RUN_SESSION)
      add_test(NAME fcitx5-daemon-frontend
        COMMAND "${DBUS_RUN_SESSION}" --
          "${Python3_EXECUTABLE}" "${CMAKE_CURRENT_SOURCE_DIR}/tests/daemon.py"
          "${MSIME_FCITX5_TEST_RESOURCES}" "${MSIME_HOST_LIBRARY}"
          "$<TARGET_FILE:msime-fcitx5>")
      find_program(XVFB_RUN xvfb-run)
      find_program(XDOTOOL xdotool)
      if(XVFB_RUN AND XDOTOOL)
        add_test(NAME fcitx5-gtk-editor
          COMMAND "${CMAKE_COMMAND}" -E env MSIME_TEST_GTK=1
            "${XVFB_RUN}" -a "${DBUS_RUN_SESSION}" --
            "${Python3_EXECUTABLE}" "${CMAKE_CURRENT_SOURCE_DIR}/tests/daemon.py"
            "${MSIME_FCITX5_TEST_RESOURCES}" "${MSIME_HOST_LIBRARY}"
            "$<TARGET_FILE:msime-fcitx5>")
        set_tests_properties(fcitx5-gtk-editor PROPERTIES TIMEOUT 90)
      endif()
    endif()
  endif()
endif()
