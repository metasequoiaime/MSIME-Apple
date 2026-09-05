cmake_minimum_required(VERSION 3.25)

set(CMAKE_OSX_DEPLOYMENT_TARGET "12.0" CACHE STRING "Minimum supported macOS version")
set(CMAKE_OSX_ARCHITECTURES "arm64;x86_64" CACHE STRING "macOS target architectures")

project(MetasequoiaImeApple VERSION 0.44.0 LANGUAGES CXX OBJCXX) # x-release-please-version

include(CTest)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

set(METASEQUOIA_MACOS_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/platforms/macos")

set(METASEQUOIA_SPARKLE_VERSION "2.9.6")
set(METASEQUOIA_SPARKLE_SHA256 "52bf9e88cdd972fc0c81501377a880e90d47031bd8ca5462488f843e2609e192")
set(METASEQUOIA_SPARKLE_URL
    "https://github.com/sparkle-project/Sparkle/releases/download/${METASEQUOIA_SPARKLE_VERSION}/Sparkle-${METASEQUOIA_SPARKLE_VERSION}.tar.xz")

set(METASEQUOIA_IME_BUILD_VOICE ON CACHE BOOL "" FORCE)
set(MSIME_VOICE_WHISPER ON CACHE BOOL "" FORCE)
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(GGML_NATIVE OFF CACHE BOOL "" FORCE)
# The pinned BLAS backend requires macOS 13.3; keep the supported macOS 12 floor.
# Metal and the CPU backend remain available for local Whisper.
set(GGML_BLAS OFF CACHE BOOL "" FORCE)
add_subdirectory(vendor/MetasequoiaImeEngine engine)
add_library(MetasequoiaAppleVoice STATIC
    ${METASEQUOIA_MACOS_ROOT}/src/VoiceInputService.mm
    ${METASEQUOIA_MACOS_ROOT}/src/VoiceSettings.mm)
target_compile_options(MetasequoiaAppleVoice PRIVATE -fobjc-arc -Wall -Wextra -Wpedantic -Werror)
target_link_libraries(MetasequoiaAppleVoice PUBLIC MetasequoiaIme::Voice MetasequoiaIme::VoiceCapture MetasequoiaIme::VoiceWhisper
    "-framework AppKit" "-framework AVFoundation" "-framework Security")

if(BUILD_TESTING)
    find_package(Python3 REQUIRED COMPONENTS Interpreter)
    find_library(APPKIT_FRAMEWORK AppKit REQUIRED)
    find_library(INPUT_METHOD_KIT_FRAMEWORK InputMethodKit REQUIRED)
    add_executable(MetasequoiaVoiceSettingsTests ${METASEQUOIA_MACOS_ROOT}/tests/VoiceSettingsTests.mm)
    target_compile_options(MetasequoiaVoiceSettingsTests PRIVATE -fobjc-arc -Wall -Wextra -Wpedantic -Werror)
    target_link_libraries(MetasequoiaVoiceSettingsTests PRIVATE "-framework AppKit" "-framework Security")
    add_test(NAME voice_settings COMMAND MetasequoiaVoiceSettingsTests)
    add_executable(MetasequoiaCandidateSelectionStateTests ${METASEQUOIA_MACOS_ROOT}/tests/CandidateSelectionStateTests.cpp)
    target_link_libraries(MetasequoiaCandidateSelectionStateTests PRIVATE MetasequoiaIme::Engine)
    target_compile_options(MetasequoiaCandidateSelectionStateTests PRIVATE -Wall -Wextra -Wpedantic -Werror)
    add_test(NAME candidate_selection_state COMMAND MetasequoiaCandidateSelectionStateTests)
    add_executable(MetasequoiaLocalInputModeTests ${METASEQUOIA_MACOS_ROOT}/tests/LocalInputModeTests.cpp)
    target_link_libraries(MetasequoiaLocalInputModeTests PRIVATE MetasequoiaIme::Engine)
    target_compile_options(MetasequoiaLocalInputModeTests PRIVATE -Wall -Wextra -Wpedantic -Werror)
    add_test(NAME local_input_modes COMMAND MetasequoiaLocalInputModeTests)
    add_executable(MetasequoiaAppleInputSessionAdapterTests
        platforms/ios/Tests/InputSessionAdapterTests.cpp
        shared/apple-bridge/InputSessionAdapter.cpp
        shared/apple-bridge/ShuangpinKeymap.cpp)
    target_include_directories(MetasequoiaAppleInputSessionAdapterTests PRIVATE shared/apple-bridge)
    target_link_libraries(MetasequoiaAppleInputSessionAdapterTests PRIVATE MetasequoiaIme::Engine)
    target_compile_options(MetasequoiaAppleInputSessionAdapterTests PRIVATE -Wall -Wextra -Wpedantic -Werror)
    add_test(NAME apple_input_session_adapter COMMAND MetasequoiaAppleInputSessionAdapterTests)
    add_executable(MetasequoiaInputControllerKeyRoutingTests ${METASEQUOIA_MACOS_ROOT}/tests/InputControllerKeyRoutingTests.mm)
    target_compile_options(MetasequoiaInputControllerKeyRoutingTests PRIVATE -fobjc-arc -Wall -Wextra -Wpedantic -Werror)
    target_link_libraries(MetasequoiaInputControllerKeyRoutingTests PRIVATE MetasequoiaIme::Engine ${APPKIT_FRAMEWORK} ${INPUT_METHOD_KIT_FRAMEWORK})
    add_test(NAME input_controller_key_routing COMMAND MetasequoiaInputControllerKeyRoutingTests)
    add_executable(MetasequoiaCandidatePanelTests ${METASEQUOIA_MACOS_ROOT}/tests/CandidatePanelTests.mm ${METASEQUOIA_MACOS_ROOT}/src/CandidatePanel.mm)
    target_compile_options(MetasequoiaCandidatePanelTests PRIVATE -fobjc-arc -Wall -Wextra -Wpedantic -Werror)
    target_link_libraries(MetasequoiaCandidatePanelTests PRIVATE ${APPKIT_FRAMEWORK} ${INPUT_METHOD_KIT_FRAMEWORK})
    add_test(NAME candidate_panel COMMAND MetasequoiaCandidatePanelTests)
    add_executable(MetasequoiaInputMenuTests ${METASEQUOIA_MACOS_ROOT}/tests/InputMenuTests.mm)
    target_compile_options(MetasequoiaInputMenuTests PRIVATE -fobjc-arc -Wall -Wextra -Wpedantic -Werror)
    target_link_libraries(MetasequoiaInputMenuTests PRIVATE ${APPKIT_FRAMEWORK})
    add_test(NAME input_menu COMMAND MetasequoiaInputMenuTests)
    add_executable(MetasequoiaChineseTextConversionTests ${METASEQUOIA_MACOS_ROOT}/tests/ChineseTextConversionTests.mm ${METASEQUOIA_MACOS_ROOT}/src/ChineseTextConversion.mm)
    target_compile_options(MetasequoiaChineseTextConversionTests PRIVATE -fobjc-arc -Wall -Wextra -Wpedantic -Werror)
    target_link_libraries(MetasequoiaChineseTextConversionTests PRIVATE ${APPKIT_FRAMEWORK})
    add_test(NAME chinese_text_conversion COMMAND MetasequoiaChineseTextConversionTests)
    add_executable(MetasequoiaFloatingToolbarPanelTests ${METASEQUOIA_MACOS_ROOT}/tests/FloatingToolbarPanelTests.mm ${METASEQUOIA_MACOS_ROOT}/src/FloatingToolbarPanel.mm)
    target_compile_options(MetasequoiaFloatingToolbarPanelTests PRIVATE -fobjc-arc -Wall -Wextra -Wpedantic -Werror)
    target_link_libraries(MetasequoiaFloatingToolbarPanelTests PRIVATE ${APPKIT_FRAMEWORK})
    add_test(NAME floating_toolbar_panel COMMAND MetasequoiaFloatingToolbarPanelTests)
    add_executable(MetasequoiaShuangpinKeymapPanelTests
        ${METASEQUOIA_MACOS_ROOT}/tests/ShuangpinKeymapPanelTests.mm
        ${METASEQUOIA_MACOS_ROOT}/src/ShuangpinKeymapPanel.mm)
    target_compile_options(MetasequoiaShuangpinKeymapPanelTests PRIVATE -fobjc-arc -Wall -Wextra -Wpedantic -Werror)
    target_link_libraries(MetasequoiaShuangpinKeymapPanelTests PRIVATE MetasequoiaIme::Engine ${APPKIT_FRAMEWORK})
    add_test(NAME shuangpin_keymap_panel COMMAND MetasequoiaShuangpinKeymapPanelTests)
    add_executable(MetasequoiaStringConversionTests ${METASEQUOIA_MACOS_ROOT}/tests/StringConversionTests.mm ${METASEQUOIA_MACOS_ROOT}/src/StringConversion.mm)
    target_compile_options(MetasequoiaStringConversionTests PRIVATE -fobjc-arc -Wall -Wextra -Wpedantic -Werror)
    target_link_libraries(MetasequoiaStringConversionTests PRIVATE ${APPKIT_FRAMEWORK})
    add_test(NAME string_conversion COMMAND MetasequoiaStringConversionTests)
    add_test(NAME release_automation COMMAND ${Python3_EXECUTABLE} ${METASEQUOIA_MACOS_ROOT}/tests/ReleaseAutomationTests.py)
    add_test(NAME release_configuration COMMAND ${Python3_EXECUTABLE} ${METASEQUOIA_MACOS_ROOT}/tests/ReleaseConfigurationTests.py)
    add_test(NAME product_lock COMMAND ${Python3_EXECUTABLE} ${METASEQUOIA_MACOS_ROOT}/tests/ProductLockTests.py)
    add_test(NAME uninstall_workflow COMMAND ${Python3_EXECUTABLE} ${METASEQUOIA_MACOS_ROOT}/tests/UninstallTests.py)
endif()

option(METASEQUOIA_IME_BUILD_INPUT_METHOD "Build the InputMethodKit bundle" ON)
set(METASEQUOIA_IME_DICTIONARY "${CMAKE_CURRENT_SOURCE_DIR}/vendor/MetasequoiaImeDict/out/msime.db" CACHE FILEPATH "Path to the generated msime.db dictionary")

if(METASEQUOIA_IME_BUILD_INPUT_METHOD)
    if(NOT APPLE)
        message(FATAL_ERROR "The InputMethodKit bundle can only be built on macOS.")
    endif()
    if(NOT EXISTS "${METASEQUOIA_IME_DICTIONARY}")
        message(FATAL_ERROR "Dictionary not found at ${METASEQUOIA_IME_DICTIONARY}. Run scripts/fetch_dictionary.py first.")
    endif()

    file(SHA256 "${METASEQUOIA_IME_DICTIONARY}" METASEQUOIA_IME_DICTIONARY_SHA256)
    find_library(APPKIT_FRAMEWORK AppKit REQUIRED)
    find_library(CARBON_FRAMEWORK Carbon REQUIRED)
    find_library(INPUT_METHOD_KIT_FRAMEWORK InputMethodKit REQUIRED)

    set(METASEQUOIA_SPARKLE_DOWNLOAD_DIRECTORY "${CMAKE_BINARY_DIR}/_deps")
    set(METASEQUOIA_SPARKLE_ARCHIVE
        "${METASEQUOIA_SPARKLE_DOWNLOAD_DIRECTORY}/Sparkle-${METASEQUOIA_SPARKLE_VERSION}.tar.xz")
    set(METASEQUOIA_SPARKLE_ROOT
        "${METASEQUOIA_SPARKLE_DOWNLOAD_DIRECTORY}/Sparkle-${METASEQUOIA_SPARKLE_VERSION}")
    set(METASEQUOIA_SPARKLE_FRAMEWORK "${METASEQUOIA_SPARKLE_ROOT}/Sparkle.framework")
    file(MAKE_DIRECTORY "${METASEQUOIA_SPARKLE_DOWNLOAD_DIRECTORY}")
    set(METASEQUOIA_SPARKLE_DOWNLOAD_REQUIRED TRUE)
    if(EXISTS "${METASEQUOIA_SPARKLE_ARCHIVE}")
        file(SHA256 "${METASEQUOIA_SPARKLE_ARCHIVE}" METASEQUOIA_SPARKLE_EXISTING_SHA256)
        if(METASEQUOIA_SPARKLE_EXISTING_SHA256 STREQUAL METASEQUOIA_SPARKLE_SHA256)
            set(METASEQUOIA_SPARKLE_DOWNLOAD_REQUIRED FALSE)
        endif()
    endif()
    if(METASEQUOIA_SPARKLE_DOWNLOAD_REQUIRED)
        file(DOWNLOAD "${METASEQUOIA_SPARKLE_URL}" "${METASEQUOIA_SPARKLE_ARCHIVE}"
            EXPECTED_HASH "SHA256=${METASEQUOIA_SPARKLE_SHA256}"
            TLS_VERIFY ON
            SHOW_PROGRESS)
    endif()
    if(NOT EXISTS "${METASEQUOIA_SPARKLE_FRAMEWORK}/Versions/B/Sparkle")
        file(MAKE_DIRECTORY "${METASEQUOIA_SPARKLE_ROOT}")
        file(ARCHIVE_EXTRACT INPUT "${METASEQUOIA_SPARKLE_ARCHIVE}"
            DESTINATION "${METASEQUOIA_SPARKLE_ROOT}")
    endif()
    if(NOT EXISTS "${METASEQUOIA_SPARKLE_FRAMEWORK}/Versions/B/Sparkle")
        message(FATAL_ERROR "Pinned Sparkle framework was not extracted successfully.")
    endif()
    add_library(MetasequoiaSparkle SHARED IMPORTED)
    set_target_properties(MetasequoiaSparkle PROPERTIES
        IMPORTED_LOCATION "${METASEQUOIA_SPARKLE_FRAMEWORK}/Versions/B/Sparkle"
        INTERFACE_COMPILE_OPTIONS "-F${METASEQUOIA_SPARKLE_ROOT}"
        INTERFACE_LINK_OPTIONS "-F${METASEQUOIA_SPARKLE_ROOT}")

    configure_file(${METASEQUOIA_MACOS_ROOT}/resources/Info.plist ${CMAKE_CURRENT_BINARY_DIR}/MetasequoiaIME-Info.plist @ONLY)

    set(METASEQUOIA_IME_LEGAL_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/Legal)
    file(MAKE_DIRECTORY ${METASEQUOIA_IME_LEGAL_DIRECTORY})
    configure_file(LICENSE ${METASEQUOIA_IME_LEGAL_DIRECTORY}/GPL-3.0.txt COPYONLY)
    configure_file(THIRD_PARTY_NOTICES.txt
        ${METASEQUOIA_IME_LEGAL_DIRECTORY}/THIRD_PARTY_NOTICES.txt COPYONLY)
    configure_file(vendor/MetasequoiaImeEngine/googlepinyinime-rev/LICENSE
        ${METASEQUOIA_IME_LEGAL_DIRECTORY}/Apache-2.0-googlepinyinime.txt COPYONLY)
    configure_file(vendor/MetasequoiaImeEngine/utfcpp/LICENSE
        ${METASEQUOIA_IME_LEGAL_DIRECTORY}/Boost-1.0.txt COPYONLY)
    configure_file(licenses/fmt-LICENSE ${METASEQUOIA_IME_LEGAL_DIRECTORY}/MIT-fmt.txt COPYONLY)
    configure_file(licenses/spdlog-LICENSE ${METASEQUOIA_IME_LEGAL_DIRECTORY}/MIT-spdlog.txt COPYONLY)
    configure_file(${METASEQUOIA_SPARKLE_ROOT}/LICENSE
        ${METASEQUOIA_IME_LEGAL_DIRECTORY}/Sparkle-LICENSE.txt COPYONLY)
    configure_file(licenses/nlohmann-json-LICENSE ${METASEQUOIA_IME_LEGAL_DIRECTORY}/MIT-nlohmann-json.txt COPYONLY)
    configure_file(vendor/MetasequoiaImeEngine/voice/third_party/miniaudio/LICENSE
        ${METASEQUOIA_IME_LEGAL_DIRECTORY}/miniaudio-LICENSE.txt COPYONLY)
    configure_file(vendor/MetasequoiaImeEngine/voice/third_party/whisper.cpp/LICENSE
        ${METASEQUOIA_IME_LEGAL_DIRECTORY}/MIT-whisper.txt COPYONLY)
    set(METASEQUOIA_IME_UNINSTALLER ${CMAKE_CURRENT_BINARY_DIR}/Uninstall.command)
    configure_file(${METASEQUOIA_MACOS_ROOT}/scripts/uninstall.sh ${METASEQUOIA_IME_UNINSTALLER} COPYONLY)

    set(METASEQUOIA_IME_ICONS ${METASEQUOIA_MACOS_ROOT}/resources/MetasequoiaIME.icns ${METASEQUOIA_MACOS_ROOT}/resources/MetasequoiaIMEMenuIcon.tiff)
    set(METASEQUOIA_IME_HELPCODES
        vendor/MetasequoiaImeEngine/helpcode/helpcodes/helpcode.txt
        vendor/MetasequoiaImeEngine/helpcode/helpcodes/zrm_helpcode_big_unique.txt
        vendor/MetasequoiaImeEngine/helpcode/helpcodes/shouyou2_0_helpcode.txt
        vendor/MetasequoiaImeEngine/helpcode/helpcodes/shouyouplus_helpcode.txt
        vendor/MetasequoiaImeEngine/helpcode/helpcodes/xiaohe_helpcode.txt)
    set(METASEQUOIA_IME_LOCALIZATIONS ${METASEQUOIA_MACOS_ROOT}/resources/en.lproj/InfoPlist.strings ${METASEQUOIA_MACOS_ROOT}/resources/zh-Hans.lproj/InfoPlist.strings)
    set(METASEQUOIA_IME_LEGAL_RESOURCES
        ${METASEQUOIA_IME_LEGAL_DIRECTORY}/GPL-3.0.txt
        ${METASEQUOIA_IME_LEGAL_DIRECTORY}/THIRD_PARTY_NOTICES.txt
        ${METASEQUOIA_IME_LEGAL_DIRECTORY}/Apache-2.0-googlepinyinime.txt
        ${METASEQUOIA_IME_LEGAL_DIRECTORY}/Boost-1.0.txt
        ${METASEQUOIA_IME_LEGAL_DIRECTORY}/MIT-fmt.txt
        ${METASEQUOIA_IME_LEGAL_DIRECTORY}/MIT-spdlog.txt
        ${METASEQUOIA_IME_LEGAL_DIRECTORY}/Sparkle-LICENSE.txt
        ${METASEQUOIA_IME_LEGAL_DIRECTORY}/MIT-nlohmann-json.txt
        ${METASEQUOIA_IME_LEGAL_DIRECTORY}/miniaudio-LICENSE.txt
        ${METASEQUOIA_IME_LEGAL_DIRECTORY}/MIT-whisper.txt)
    add_executable(MetasequoiaIME MACOSX_BUNDLE ${METASEQUOIA_MACOS_ROOT}/src/main.mm ${METASEQUOIA_MACOS_ROOT}/src/CandidatePanel.mm ${METASEQUOIA_MACOS_ROOT}/src/ChineseTextConversion.mm ${METASEQUOIA_MACOS_ROOT}/src/DictionaryInstaller.mm ${METASEQUOIA_MACOS_ROOT}/src/FloatingToolbarPanel.mm ${METASEQUOIA_MACOS_ROOT}/src/InputSourceRegistration.mm ${METASEQUOIA_MACOS_ROOT}/src/MetasequoiaInputController.mm ${METASEQUOIA_MACOS_ROOT}/src/PreferencesWindowController.mm ${METASEQUOIA_MACOS_ROOT}/src/ShuangpinKeymapPanel.mm ${METASEQUOIA_MACOS_ROOT}/src/StringConversion.mm ${METASEQUOIA_MACOS_ROOT}/src/UpdateController.mm ${METASEQUOIA_IME_DICTIONARY} ${METASEQUOIA_IME_ICONS} ${METASEQUOIA_IME_HELPCODES} ${METASEQUOIA_IME_LOCALIZATIONS} ${METASEQUOIA_IME_LEGAL_RESOURCES} ${METASEQUOIA_IME_UNINSTALLER})
    get_filename_component(dictionary_directory "${METASEQUOIA_IME_DICTIONARY}" DIRECTORY)
    if(EXISTS "${dictionary_directory}/dictionary-manifest.json")
        target_sources(MetasequoiaIME PRIVATE "${dictionary_directory}/dictionary-manifest.json")
        set_source_files_properties("${dictionary_directory}/dictionary-manifest.json"
            PROPERTIES MACOSX_PACKAGE_LOCATION Resources)
    endif()
    set_source_files_properties(${METASEQUOIA_IME_DICTIONARY} PROPERTIES MACOSX_PACKAGE_LOCATION Resources)
    set_source_files_properties(${METASEQUOIA_IME_ICONS} PROPERTIES MACOSX_PACKAGE_LOCATION Resources)
    set_source_files_properties(${METASEQUOIA_IME_HELPCODES}
        PROPERTIES MACOSX_PACKAGE_LOCATION Resources/helpcodes)
    set_source_files_properties(${METASEQUOIA_MACOS_ROOT}/resources/en.lproj/InfoPlist.strings PROPERTIES MACOSX_PACKAGE_LOCATION Resources/en.lproj)
    set_source_files_properties(${METASEQUOIA_MACOS_ROOT}/resources/zh-Hans.lproj/InfoPlist.strings PROPERTIES MACOSX_PACKAGE_LOCATION Resources/zh-Hans.lproj)
    set_source_files_properties(${METASEQUOIA_IME_LEGAL_RESOURCES}
        PROPERTIES MACOSX_PACKAGE_LOCATION Resources/Licenses)
    set_source_files_properties(${METASEQUOIA_IME_UNINSTALLER}
        PROPERTIES MACOSX_PACKAGE_LOCATION Resources HEADER_FILE_ONLY TRUE)
    set_target_properties(MetasequoiaIME PROPERTIES MACOSX_BUNDLE_INFO_PLIST ${CMAKE_CURRENT_BINARY_DIR}/MetasequoiaIME-Info.plist MACOSX_BUNDLE_BUNDLE_NAME "Metasequoia IME" MACOSX_BUNDLE_GUI_IDENTIFIER "com.houko.inputmethod.MetasequoiaIME" MACOSX_BUNDLE_SHORT_VERSION_STRING ${PROJECT_VERSION} MACOSX_BUNDLE_BUNDLE_VERSION ${PROJECT_VERSION} OUTPUT_NAME MetasequoiaIME BUILD_WITH_INSTALL_RPATH TRUE INSTALL_RPATH "@executable_path/../Frameworks")
    target_compile_options(MetasequoiaIME PRIVATE -fobjc-arc -Wall -Wextra -Wpedantic -Werror)
    target_link_libraries(MetasequoiaIME PRIVATE MetasequoiaAppleVoice MetasequoiaIme::Engine MetasequoiaSparkle ${APPKIT_FRAMEWORK} ${CARBON_FRAMEWORK} ${INPUT_METHOD_KIT_FRAMEWORK})
    add_custom_command(TARGET MetasequoiaIME POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E make_directory "$<TARGET_BUNDLE_DIR:MetasequoiaIME>/Contents/Frameworks"
        COMMAND /usr/bin/ditto "${METASEQUOIA_SPARKLE_FRAMEWORK}"
            "$<TARGET_BUNDLE_DIR:MetasequoiaIME>/Contents/Frameworks/Sparkle.framework"
        VERBATIM)
    add_custom_target(MetasequoiaIMESign ALL COMMAND /usr/bin/codesign --force --deep --sign - "$<TARGET_BUNDLE_DIR:MetasequoiaIME>" DEPENDS MetasequoiaIME VERBATIM)
    if(BUILD_TESTING)
        add_executable(MetasequoiaCandidatePaginationTests
            ${METASEQUOIA_MACOS_ROOT}/tests/CandidatePaginationTests.mm
            ${METASEQUOIA_MACOS_ROOT}/src/CandidatePanel.mm
            ${METASEQUOIA_MACOS_ROOT}/src/ChineseTextConversion.mm
            ${METASEQUOIA_MACOS_ROOT}/src/DictionaryInstaller.mm
            ${METASEQUOIA_MACOS_ROOT}/src/FloatingToolbarPanel.mm
            ${METASEQUOIA_MACOS_ROOT}/src/PreferencesWindowController.mm
            ${METASEQUOIA_MACOS_ROOT}/src/ShuangpinKeymapPanel.mm
            ${METASEQUOIA_MACOS_ROOT}/src/StringConversion.mm
            ${METASEQUOIA_MACOS_ROOT}/src/UpdateController.mm)
        target_compile_options(MetasequoiaCandidatePaginationTests PRIVATE -fobjc-arc -Wall -Wextra -Wpedantic -Werror)
        target_link_libraries(MetasequoiaCandidatePaginationTests PRIVATE MetasequoiaAppleVoice MetasequoiaIme::Engine MetasequoiaSparkle ${APPKIT_FRAMEWORK} ${CARBON_FRAMEWORK} ${INPUT_METHOD_KIT_FRAMEWORK})
        set_target_properties(MetasequoiaCandidatePaginationTests PROPERTIES BUILD_RPATH "${METASEQUOIA_SPARKLE_ROOT}")
        add_test(NAME candidate_pagination COMMAND MetasequoiaCandidatePaginationTests)
        add_executable(MetasequoiaDictionaryInstallerTests ${METASEQUOIA_MACOS_ROOT}/tests/DictionaryInstallerTests.mm ${METASEQUOIA_MACOS_ROOT}/src/DictionaryInstaller.mm)
        target_compile_options(MetasequoiaDictionaryInstallerTests PRIVATE -fobjc-arc -Wall -Wextra -Wpedantic -Werror)
        target_link_libraries(MetasequoiaDictionaryInstallerTests PRIVATE MetasequoiaIme::Engine ${APPKIT_FRAMEWORK})
        add_test(NAME dictionary_installer COMMAND MetasequoiaDictionaryInstallerTests)
        add_executable(MetasequoiaInputSourceRegistrationTests ${METASEQUOIA_MACOS_ROOT}/tests/InputSourceRegistrationTests.mm ${METASEQUOIA_MACOS_ROOT}/src/InputSourceRegistration.mm)
        target_compile_options(MetasequoiaInputSourceRegistrationTests PRIVATE -fobjc-arc -Wall -Wextra -Wpedantic -Werror)
        target_link_libraries(MetasequoiaInputSourceRegistrationTests PRIVATE ${APPKIT_FRAMEWORK} ${CARBON_FRAMEWORK})
        add_test(NAME input_source_registration COMMAND MetasequoiaInputSourceRegistrationTests)
        add_executable(MetasequoiaUpdateControllerTests ${METASEQUOIA_MACOS_ROOT}/tests/UpdateControllerTests.mm ${METASEQUOIA_MACOS_ROOT}/src/UpdateController.mm)
        target_compile_options(MetasequoiaUpdateControllerTests PRIVATE -fobjc-arc -Wall -Wextra -Wpedantic -Werror)
        target_link_libraries(MetasequoiaUpdateControllerTests PRIVATE MetasequoiaSparkle ${APPKIT_FRAMEWORK})
        set_target_properties(MetasequoiaUpdateControllerTests PROPERTIES BUILD_RPATH "${METASEQUOIA_SPARKLE_ROOT}")
        add_test(NAME update_controller COMMAND MetasequoiaUpdateControllerTests)
        add_executable(MetasequoiaPreferencesWindowTests ${METASEQUOIA_MACOS_ROOT}/tests/PreferencesWindowTests.mm ${METASEQUOIA_MACOS_ROOT}/src/PreferencesWindowController.mm ${METASEQUOIA_MACOS_ROOT}/src/DictionaryInstaller.mm ${METASEQUOIA_MACOS_ROOT}/src/UpdateController.mm)
        target_compile_options(MetasequoiaPreferencesWindowTests PRIVATE -fobjc-arc -Wall -Wextra -Wpedantic -Werror)
        target_link_libraries(MetasequoiaPreferencesWindowTests PRIVATE MetasequoiaIme::Engine MetasequoiaSparkle ${APPKIT_FRAMEWORK} ${INPUT_METHOD_KIT_FRAMEWORK})
        set_target_properties(MetasequoiaPreferencesWindowTests PROPERTIES BUILD_RPATH "${METASEQUOIA_SPARKLE_ROOT}")
        add_test(NAME preferences_window COMMAND MetasequoiaPreferencesWindowTests)
        add_test(NAME release_package COMMAND ${CMAKE_COMMAND} -E env
            "METASEQUOIA_DEVELOPMENT_BUNDLE=$<TARGET_BUNDLE_DIR:MetasequoiaIME>"
            ${Python3_EXECUTABLE} ${METASEQUOIA_MACOS_ROOT}/tests/ReleasePackageTests.py
            $<TARGET_BUNDLE_DIR:MetasequoiaIME>)
        set_tests_properties(release_package PROPERTIES TIMEOUT 240)
    endif()
endif()
