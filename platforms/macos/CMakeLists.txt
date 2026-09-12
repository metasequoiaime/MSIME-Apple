cmake_minimum_required(VERSION 3.25)
set(CMAKE_OSX_DEPLOYMENT_TARGET "13.0" CACHE STRING "Minimum macOS version; match the Cargo build")
project(MSIMEClientMacOS LANGUAGES CXX OBJCXX)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_OBJCXX_STANDARD 17)
set(MSIME_HOST_LIBRARY "${CMAKE_CURRENT_SOURCE_DIR}/../../target/debug/libmsime_host_api.a" CACHE FILEPATH "Rust host static library for this architecture")
if(NOT EXISTS "${MSIME_HOST_LIBRARY}")
  message(FATAL_ERROR "Build msime-host-api with Cargo first")
endif()
find_package(SQLite3 REQUIRED)
if(TARGET SQLite3::SQLite3)
  set(SQLITE_TARGET SQLite3::SQLite3)
else()
  set(SQLITE_TARGET SQLite::SQLite3)
endif()
add_library(apple-client STATIC ../../shared/apple/MSIMEClientSession.mm ../../shared/apple/TextClient.mm)
target_compile_options(apple-client PRIVATE -fobjc-arc -Wall -Wextra -Werror)
target_include_directories(apple-client PUBLIC ../../shared/apple . ../../crates/host-api/include)
target_link_libraries(apple-client PUBLIC "${MSIME_HOST_LIBRARY}" ${SQLITE_TARGET} "-framework Foundation" "-framework Security")
add_executable(MSIMEClientInputMethod MACOSX_BUNDLE CloudFileTransfer.mm main.mm CloudClipboardWindowController.mm CloudClipboardClient.mm AccountSessionManager.mm AccountAuthClient.mm AccountWindowController.mm AccountKeychain.mm CloudDictionaryClient.mm PreferencesWindowController.mm VoiceInputService.mm VoiceSettings.mm VoiceProviderSettings.mm InputController.mm CandidatePanel.mm CandidateSkinAppearance.mm AppearancePreferences.mm CandidateSkin.cpp CandidateSkinPreviewView.mm SkinSettingsView.mm ChineseTextConversion.mm StringConversion.mm ShuangpinKeymapPanel.mm InputSourceRegistration.mm FloatingToolbarPanel.mm UpdateController.mm DictionaryWindowController.mm ClientDictionaryRuntime.mm DictionaryInstaller.mm)
target_sources(MSIMEClientInputMethod PRIVATE ScreenKeyboardPanel.mm)
target_link_libraries(MSIMEClientInputMethod PRIVATE "-framework CoreGraphics")
file(GLOB MSIME_BACKEND_SWIFT CONFIGURE_DEPENDS
  "${CMAKE_CURRENT_SOURCE_DIR}/../../shared/backend/*.swift"
  "${CMAKE_CURRENT_SOURCE_DIR}/../../shared/backend-ui/*.swift"
  "${CMAKE_CURRENT_SOURCE_DIR}/Backend*.swift")
set(MSIME_SWIFT_BACKEND_OUTPUT "${CMAKE_CURRENT_BINARY_DIR}/MSIMEBackend.dylib")
add_custom_command(OUTPUT "${MSIME_SWIFT_BACKEND_OUTPUT}"
  COMMAND "${CMAKE_CURRENT_SOURCE_DIR}/scripts/build_backend_swift.sh" "${MSIME_SWIFT_BACKEND_OUTPUT}"
  DEPENDS ${MSIME_BACKEND_SWIFT} "${CMAKE_CURRENT_SOURCE_DIR}/scripts/build_backend_swift.sh")
add_custom_target(macos-swift-backend DEPENDS "${MSIME_SWIFT_BACKEND_OUTPUT}")
add_dependencies(MSIMEClientInputMethod macos-swift-backend)
target_include_directories(MSIMEClientInputMethod PRIVATE ../../vendor/MSIME-Engine ../../vendor/MSIME-Engine/include)
target_compile_options(MSIMEClientInputMethod PRIVATE -fobjc-arc -Wall -Wextra -Werror)
target_link_libraries(MSIMEClientInputMethod PRIVATE apple-client "-framework AppKit" "-framework InputMethodKit" "-framework Carbon" "-framework AVFoundation" "-framework Speech")
set_target_properties(MSIMEClientInputMethod PROPERTIES MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_SOURCE_DIR}/Info.plist.in")
add_custom_command(TARGET MSIMEClientInputMethod POST_BUILD
  COMMAND "${CMAKE_COMMAND}" -E make_directory "$<TARGET_BUNDLE_DIR:MSIMEClientInputMethod>/Contents/Frameworks"
  COMMAND "${CMAKE_COMMAND}" -E copy_if_different "${MSIME_SWIFT_BACKEND_OUTPUT}" "$<TARGET_BUNDLE_DIR:MSIMEClientInputMethod>/Contents/Frameworks/MSIMEBackend.dylib")
set(MSIME_OPTIONS_FILE "" CACHE FILEPATH "Optional development runtime configuration; never distribute this file")
if(MSIME_OPTIONS_FILE)
  target_sources(MSIMEClientInputMethod PRIVATE "${MSIME_OPTIONS_FILE}")
  set_source_files_properties("${MSIME_OPTIONS_FILE}" PROPERTIES MACOSX_PACKAGE_LOCATION Resources)
endif()
enable_testing()
include(ClipboardTests.cmake)
set(MSIME_EMOJI_HOME_TEST_SOURCES BackendEmojiSymbolGroups.swift BackendEmojiCatalog.swift BackendEmojiCatalogCursor.swift
  BackendEmojiAppearance.swift BackendEmojiScroll.swift BackendEmojiHomeHeading.swift BackendEmojiHome.swift BackendEmojiHomeNavigation.swift
  BackendEmojiKeyboard.swift BackendEmojiFlow.swift BackendEmojiGrid.swift BackendEmojiNavigation.swift tests/EmojiHomeTest.swift)
list(TRANSFORM MSIME_EMOJI_HOME_TEST_SOURCES PREPEND "${CMAKE_CURRENT_SOURCE_DIR}/")
add_custom_command(OUTPUT "${CMAKE_CURRENT_BINARY_DIR}/emoji-home-test"
  COMMAND "${MSIME_XCRUN}" swiftc -Onone
    -target "${CMAKE_HOST_SYSTEM_PROCESSOR}-apple-macosx${CMAKE_OSX_DEPLOYMENT_TARGET}"
    ${MSIME_EMOJI_HOME_TEST_SOURCES} -o "${CMAKE_CURRENT_BINARY_DIR}/emoji-home-test"
  DEPENDS ${MSIME_EMOJI_HOME_TEST_SOURCES} VERBATIM)
add_custom_target(emoji-home-test-build ALL DEPENDS "${CMAKE_CURRENT_BINARY_DIR}/emoji-home-test")
add_test(NAME emoji-home COMMAND "${CMAKE_CURRENT_BINARY_DIR}/emoji-home-test")
set_tests_properties(emoji-home PROPERTIES LABELS "emoji-local" TIMEOUT 30)
set(MSIME_EMOJI_FLOW_TEST_SOURCES BackendEmojiSymbolGroups.swift BackendEmojiCatalog.swift
  BackendEmojiAppearance.swift BackendEmojiFlow.swift tests/EmojiFlowTest.swift)
list(TRANSFORM MSIME_EMOJI_FLOW_TEST_SOURCES PREPEND "${CMAKE_CURRENT_SOURCE_DIR}/")
add_custom_command(OUTPUT "${CMAKE_CURRENT_BINARY_DIR}/emoji-flow-test"
  COMMAND "${MSIME_XCRUN}" swiftc -Onone
    -target "${CMAKE_HOST_SYSTEM_PROCESSOR}-apple-macosx${CMAKE_OSX_DEPLOYMENT_TARGET}"
    ${MSIME_EMOJI_FLOW_TEST_SOURCES} -o "${CMAKE_CURRENT_BINARY_DIR}/emoji-flow-test"
  DEPENDS ${MSIME_EMOJI_FLOW_TEST_SOURCES} VERBATIM)
add_custom_target(emoji-flow-test-build ALL DEPENDS "${CMAKE_CURRENT_BINARY_DIR}/emoji-flow-test")
add_test(NAME emoji-flow COMMAND "${CMAKE_CURRENT_BINARY_DIR}/emoji-flow-test")
set_tests_properties(emoji-flow PROPERTIES LABELS "emoji-local" TIMEOUT 30)
set(MSIME_EMOJI_GRID_TEST_SOURCES BackendEmojiSymbolGroups.swift BackendEmojiCatalog.swift
  BackendEmojiAppearance.swift BackendEmojiFlow.swift BackendEmojiGrid.swift
  BackendEmojiKeyboard.swift tests/EmojiGridTest.swift)
list(TRANSFORM MSIME_EMOJI_GRID_TEST_SOURCES PREPEND "${CMAKE_CURRENT_SOURCE_DIR}/")
add_custom_command(OUTPUT "${CMAKE_CURRENT_BINARY_DIR}/emoji-grid-test"
  COMMAND "${MSIME_XCRUN}" swiftc -Onone
    -target "${CMAKE_HOST_SYSTEM_PROCESSOR}-apple-macosx${CMAKE_OSX_DEPLOYMENT_TARGET}"
    ${MSIME_EMOJI_GRID_TEST_SOURCES} -o "${CMAKE_CURRENT_BINARY_DIR}/emoji-grid-test"
  DEPENDS ${MSIME_EMOJI_GRID_TEST_SOURCES} VERBATIM)
add_custom_target(emoji-grid-test-build ALL DEPENDS "${CMAKE_CURRENT_BINARY_DIR}/emoji-grid-test")
add_test(NAME emoji-grid COMMAND "${CMAKE_CURRENT_BINARY_DIR}/emoji-grid-test")
set_tests_properties(emoji-grid PROPERTIES LABELS "emoji-local" TIMEOUT 30)
set(MSIME_EMOJI_SCROLL_TEST_SOURCES BackendEmojiScroll.swift tests/EmojiScrollTest.swift)
list(TRANSFORM MSIME_EMOJI_SCROLL_TEST_SOURCES PREPEND "${CMAKE_CURRENT_SOURCE_DIR}/")
add_custom_command(OUTPUT "${CMAKE_CURRENT_BINARY_DIR}/emoji-scroll-test"
  COMMAND "${MSIME_XCRUN}" swiftc -Onone
    -target "${CMAKE_HOST_SYSTEM_PROCESSOR}-apple-macosx${CMAKE_OSX_DEPLOYMENT_TARGET}"
    ${MSIME_EMOJI_SCROLL_TEST_SOURCES} -o "${CMAKE_CURRENT_BINARY_DIR}/emoji-scroll-test"
  DEPENDS ${MSIME_EMOJI_SCROLL_TEST_SOURCES} VERBATIM)
add_custom_target(emoji-scroll-test-build ALL DEPENDS "${CMAKE_CURRENT_BINARY_DIR}/emoji-scroll-test")
add_test(NAME emoji-scroll COMMAND "${CMAKE_CURRENT_BINARY_DIR}/emoji-scroll-test")
set_tests_properties(emoji-scroll PROPERTIES LABELS "emoji-local" TIMEOUT 30)
set(MSIME_EMOJI_SEARCH_TEST_SOURCES BackendEmojiAppearance.swift BackendEmojiSearchField.swift tests/EmojiSearchChromeTest.swift)
list(TRANSFORM MSIME_EMOJI_SEARCH_TEST_SOURCES PREPEND "${CMAKE_CURRENT_SOURCE_DIR}/")
add_custom_command(OUTPUT "${CMAKE_CURRENT_BINARY_DIR}/emoji-search-test"
  COMMAND "${MSIME_XCRUN}" swiftc -Onone
    -target "${CMAKE_HOST_SYSTEM_PROCESSOR}-apple-macosx${CMAKE_OSX_DEPLOYMENT_TARGET}"
    ${MSIME_EMOJI_SEARCH_TEST_SOURCES} -o "${CMAKE_CURRENT_BINARY_DIR}/emoji-search-test"
  DEPENDS ${MSIME_EMOJI_SEARCH_TEST_SOURCES} VERBATIM)
add_custom_target(emoji-search-test-build ALL DEPENDS "${CMAKE_CURRENT_BINARY_DIR}/emoji-search-test")
add_test(NAME emoji-search COMMAND "${CMAKE_CURRENT_BINARY_DIR}/emoji-search-test")
set_tests_properties(emoji-search PROPERTIES LABELS "emoji-local" TIMEOUT 30)
set(MSIME_EMOJI_TOAST_TEST_SOURCES BackendEmojiAppearance.swift BackendEmojiToast.swift tests/EmojiToastTest.swift)
list(TRANSFORM MSIME_EMOJI_TOAST_TEST_SOURCES PREPEND "${CMAKE_CURRENT_SOURCE_DIR}/")
add_custom_command(OUTPUT "${CMAKE_CURRENT_BINARY_DIR}/emoji-toast-test"
  COMMAND "${MSIME_XCRUN}" swiftc -Onone
    -target "${CMAKE_HOST_SYSTEM_PROCESSOR}-apple-macosx${CMAKE_OSX_DEPLOYMENT_TARGET}"
    ${MSIME_EMOJI_TOAST_TEST_SOURCES} -o "${CMAKE_CURRENT_BINARY_DIR}/emoji-toast-test"
  DEPENDS ${MSIME_EMOJI_TOAST_TEST_SOURCES} VERBATIM)
add_custom_target(emoji-toast-test-build ALL DEPENDS "${CMAKE_CURRENT_BINARY_DIR}/emoji-toast-test")
add_test(NAME emoji-toast COMMAND "${CMAKE_CURRENT_BINARY_DIR}/emoji-toast-test")
set_tests_properties(emoji-toast PROPERTIES LABELS "emoji-local" TIMEOUT 30)
set(MSIME_EMOJI_TABS_TEST_SOURCES BackendEmojiAppearance.swift BackendEmojiNavigation.swift
  BackendEmojiMainTabs.swift tests/EmojiMainTabsTest.swift)
list(TRANSFORM MSIME_EMOJI_TABS_TEST_SOURCES PREPEND "${CMAKE_CURRENT_SOURCE_DIR}/")
add_custom_command(OUTPUT "${CMAKE_CURRENT_BINARY_DIR}/emoji-main-tabs-test"
  COMMAND "${MSIME_XCRUN}" swiftc -Onone
    -target "${CMAKE_HOST_SYSTEM_PROCESSOR}-apple-macosx${CMAKE_OSX_DEPLOYMENT_TARGET}"
    ${MSIME_EMOJI_TABS_TEST_SOURCES} -o "${CMAKE_CURRENT_BINARY_DIR}/emoji-main-tabs-test"
  DEPENDS ${MSIME_EMOJI_TABS_TEST_SOURCES} VERBATIM)
add_custom_target(emoji-main-tabs-test-build ALL DEPENDS "${CMAKE_CURRENT_BINARY_DIR}/emoji-main-tabs-test")
add_test(NAME emoji-main-tabs COMMAND "${CMAKE_CURRENT_BINARY_DIR}/emoji-main-tabs-test")
set_tests_properties(emoji-main-tabs PROPERTIES LABELS "emoji-local" TIMEOUT 30)
set(MSIME_EMOJI_CATEGORY_TEST_SOURCES BackendEmojiAppearance.swift BackendEmojiNavigation.swift
  BackendEmojiSymbolGroups.swift BackendEmojiCategoryTabs.swift tests/EmojiCategoryTabsTest.swift)
list(TRANSFORM MSIME_EMOJI_CATEGORY_TEST_SOURCES PREPEND "${CMAKE_CURRENT_SOURCE_DIR}/")
add_custom_command(OUTPUT "${CMAKE_CURRENT_BINARY_DIR}/emoji-category-tabs-test"
  COMMAND "${MSIME_XCRUN}" swiftc -Onone
    -target "${CMAKE_HOST_SYSTEM_PROCESSOR}-apple-macosx${CMAKE_OSX_DEPLOYMENT_TARGET}"
    ${MSIME_EMOJI_CATEGORY_TEST_SOURCES} -o "${CMAKE_CURRENT_BINARY_DIR}/emoji-category-tabs-test"
  DEPENDS ${MSIME_EMOJI_CATEGORY_TEST_SOURCES} VERBATIM)
add_custom_target(emoji-category-tabs-test-build ALL DEPENDS "${CMAKE_CURRENT_BINARY_DIR}/emoji-category-tabs-test")
add_test(NAME emoji-category-tabs COMMAND "${CMAKE_CURRENT_BINARY_DIR}/emoji-category-tabs-test")
set_tests_properties(emoji-category-tabs PROPERTIES LABELS "emoji-local" TIMEOUT 30)
set(MSIME_EMOJI_SECTIONS_TEST_SOURCES BackendEmojiAppearance.swift BackendEmojiSymbolGroups.swift
  BackendEmojiCatalog.swift BackendEmojiFlow.swift BackendEmojiGrid.swift BackendEmojiKeyboard.swift
  BackendEmojiSymbolSections.swift tests/EmojiSymbolSectionsTest.swift)
list(TRANSFORM MSIME_EMOJI_SECTIONS_TEST_SOURCES PREPEND "${CMAKE_CURRENT_SOURCE_DIR}/")
add_custom_command(OUTPUT "${CMAKE_CURRENT_BINARY_DIR}/emoji-symbol-sections-test"
  COMMAND "${MSIME_XCRUN}" swiftc -Onone
    -target "${CMAKE_HOST_SYSTEM_PROCESSOR}-apple-macosx${CMAKE_OSX_DEPLOYMENT_TARGET}"
    ${MSIME_EMOJI_SECTIONS_TEST_SOURCES} -o "${CMAKE_CURRENT_BINARY_DIR}/emoji-symbol-sections-test"
  DEPENDS ${MSIME_EMOJI_SECTIONS_TEST_SOURCES} VERBATIM)
add_custom_target(emoji-symbol-sections-test-build ALL DEPENDS "${CMAKE_CURRENT_BINARY_DIR}/emoji-symbol-sections-test")
add_test(NAME emoji-symbol-sections COMMAND "${CMAKE_CURRENT_BINARY_DIR}/emoji-symbol-sections-test")
set_tests_properties(emoji-symbol-sections PROPERTIES LABELS "emoji-local" TIMEOUT 30)
set(MSIME_EMOJI_CURSOR_TEST_SOURCES BackendEmojiSymbolGroups.swift BackendEmojiCatalog.swift
  BackendEmojiCatalogCursor.swift tests/EmojiCatalogCursorTest.swift)
list(TRANSFORM MSIME_EMOJI_CURSOR_TEST_SOURCES PREPEND "${CMAKE_CURRENT_SOURCE_DIR}/")
add_custom_command(OUTPUT "${CMAKE_CURRENT_BINARY_DIR}/emoji-catalog-cursor-test"
  COMMAND "${MSIME_XCRUN}" swiftc -Onone
    -target "${CMAKE_HOST_SYSTEM_PROCESSOR}-apple-macosx${CMAKE_OSX_DEPLOYMENT_TARGET}"
    ${MSIME_EMOJI_CURSOR_TEST_SOURCES} -o "${CMAKE_CURRENT_BINARY_DIR}/emoji-catalog-cursor-test"
  DEPENDS ${MSIME_EMOJI_CURSOR_TEST_SOURCES} VERBATIM)
add_custom_target(emoji-catalog-cursor-test-build ALL DEPENDS "${CMAKE_CURRENT_BINARY_DIR}/emoji-catalog-cursor-test")
add_test(NAME emoji-catalog-cursor COMMAND "${CMAKE_CURRENT_BINARY_DIR}/emoji-catalog-cursor-test")
set_tests_properties(emoji-catalog-cursor PROPERTIES LABELS "emoji-local" TIMEOUT 30)
add_executable(screen-keyboard-panel-test tests/ScreenKeyboardPanelTest.mm ScreenKeyboardPanel.mm)
target_compile_options(screen-keyboard-panel-test PRIVATE -fobjc-arc -Wall -Wextra -Werror -UNDEBUG)
target_link_libraries(screen-keyboard-panel-test PRIVATE "-framework AppKit" "-framework CoreGraphics" "-framework Carbon")
add_test(NAME screen-keyboard-panel COMMAND screen-keyboard-panel-test)
add_executable(preference-snapshot-merge-test tests/PreferenceSnapshotMergeTest.mm)
target_compile_options(preference-snapshot-merge-test PRIVATE -fobjc-arc -Wall -Wextra -Werror -UNDEBUG)
target_link_libraries(preference-snapshot-merge-test PRIVATE "-framework Foundation")
add_test(NAME preference-snapshot-merge COMMAND preference-snapshot-merge-test)
add_executable(preference-save-state-test tests/PreferenceSaveStateTest.cpp)
target_compile_options(preference-save-state-test PRIVATE -Wall -Wextra -Werror -UNDEBUG)
add_test(NAME preference-save-state COMMAND preference-save-state-test)
add_executable(preference-load-state-test tests/PreferenceLoadStateTest.cpp)
target_compile_options(preference-load-state-test PRIVATE -Wall -Wextra -Werror -UNDEBUG)
add_test(NAME preference-load-state COMMAND preference-load-state-test)
add_executable(toolbar-visibility-preferences-test tests/ToolbarVisibilityPreferencesTest.mm AppearancePreferences.mm CandidateSkin.cpp CandidateSkinPreviewView.mm SkinSettingsView.mm PreferencesWindowController.mm CandidateSkinAppearance.mm)
target_compile_options(toolbar-visibility-preferences-test PRIVATE -fobjc-arc -Wall -Wextra -Werror -UNDEBUG)
target_link_libraries(toolbar-visibility-preferences-test PRIVATE "-framework AppKit")
add_test(NAME toolbar-visibility-preferences COMMAND toolbar-visibility-preferences-test)
add_executable(cloud-appearance-settings-test tests/CloudAppearanceSettingsTest.mm CandidateSkin.cpp)
target_compile_options(cloud-appearance-settings-test PRIVATE -fobjc-arc -Wall -Wextra -Werror -UNDEBUG)
target_link_libraries(cloud-appearance-settings-test PRIVATE "-framework Foundation")
add_test(NAME cloud-appearance-settings COMMAND cloud-appearance-settings-test)
add_executable(cloud-clipboard-selection-test tests/CloudClipboardSelectionTest.mm CloudClipboardWindowController.mm)
target_compile_options(cloud-clipboard-selection-test PRIVATE -fobjc-arc -Wall -Wextra -Werror -UNDEBUG)
target_link_libraries(cloud-clipboard-selection-test PRIVATE "-framework AppKit")
add_test(NAME cloud-clipboard-selection COMMAND cloud-clipboard-selection-test)
add_executable(cloud-clipboard-deletion-test tests/CloudClipboardDeletionTest.mm CloudClipboardClient.mm)
target_compile_options(cloud-clipboard-deletion-test PRIVATE -fobjc-arc -Wall -Wextra -Werror -UNDEBUG)
target_link_libraries(cloud-clipboard-deletion-test PRIVATE "-framework Foundation")
add_test(NAME cloud-clipboard-deletion COMMAND cloud-clipboard-deletion-test)
add_executable(backend-account-entry-test tests/BackendAccountEntryTest.mm)
target_compile_options(backend-account-entry-test PRIVATE -fobjc-arc -Wall -Wextra -Werror -UNDEBUG)
target_link_libraries(backend-account-entry-test PRIVATE "-framework Foundation")
add_test(NAME backend-account-entry COMMAND backend-account-entry-test)
add_executable(backend-selection-observation-test tests/BackendSelectionObservationTest.mm)
target_compile_options(backend-selection-observation-test PRIVATE -fobjc-arc -Wall -Wextra -Werror -UNDEBUG)
target_link_libraries(backend-selection-observation-test PRIVATE "-framework Foundation")
add_test(NAME backend-selection-observation COMMAND backend-selection-observation-test)
add_executable(tool-text-return-test tests/ToolTextReturnTest.mm)
target_compile_options(tool-text-return-test PRIVATE -fobjc-arc -Wall -Wextra -Werror -UNDEBUG)
target_link_libraries(tool-text-return-test PRIVATE "-framework Foundation")
add_test(NAME tool-text-return COMMAND tool-text-return-test)
add_executable(tool-application-activation-test tests/ToolApplicationActivationTest.mm)
target_compile_options(tool-application-activation-test PRIVATE -fobjc-arc -Wall -Wextra -Werror -UNDEBUG)
target_link_libraries(tool-application-activation-test PRIVATE "-framework AppKit")
add_test(NAME tool-application-activation COMMAND tool-application-activation-test)
add_executable(backend-library-load-test tests/BackendLibraryLoadTest.mm)
target_compile_options(backend-library-load-test PRIVATE -fobjc-arc -Wall -Wextra -Werror -UNDEBUG)
target_link_libraries(backend-library-load-test PRIVATE "-framework Foundation")
add_dependencies(backend-library-load-test MSIMEClientInputMethod)
add_test(NAME backend-library-load COMMAND backend-library-load-test "$<TARGET_BUNDLE_DIR:MSIMEClientInputMethod>/Contents/Frameworks/MSIMEBackend.dylib")
set(MSIME_SPARKLE_ROOT "" CACHE PATH "Directory containing the pinned Sparkle.framework (Apple reference: 2.9.6)")
if(NOT MSIME_SPARKLE_ROOT)
  message(FATAL_ERROR "UpdateController requires Sparkle 2.9.6. Set MSIME_SPARKLE_ROOT to the directory containing Sparkle.framework; see platforms/macos/README.md.")
endif()
if(MSIME_SPARKLE_ROOT)
  # Do not reuse a framework cached for a different root on reconfiguration.
  unset(MSIME_SPARKLE_FRAMEWORK CACHE)
  find_library(MSIME_SPARKLE_FRAMEWORK Sparkle PATHS "${MSIME_SPARKLE_ROOT}" NO_DEFAULT_PATH REQUIRED)
  execute_process(COMMAND /usr/libexec/PlistBuddy -c Print:CFBundleShortVersionString
    "${MSIME_SPARKLE_FRAMEWORK}/Resources/Info.plist"
    OUTPUT_VARIABLE MSIME_SPARKLE_VERSION OUTPUT_STRIP_TRAILING_WHITESPACE
    ERROR_QUIET RESULT_VARIABLE MSIME_SPARKLE_VERSION_RESULT)
  if(NOT MSIME_SPARKLE_VERSION_RESULT EQUAL 0 OR NOT MSIME_SPARKLE_VERSION STREQUAL "2.9.6")
    message(FATAL_ERROR "MSIME_SPARKLE_ROOT must contain Sparkle 2.9.6; found '${MSIME_SPARKLE_VERSION}'.")
  endif()
  target_compile_options(MSIMEClientInputMethod PRIVATE "-F${MSIME_SPARKLE_ROOT}")
  target_link_libraries(MSIMEClientInputMethod PRIVATE "${MSIME_SPARKLE_FRAMEWORK}")
  set_property(TARGET MSIMEClientInputMethod APPEND PROPERTY BUILD_RPATH "@executable_path/../Frameworks")
  add_custom_command(TARGET MSIMEClientInputMethod POST_BUILD
    COMMAND "${CMAKE_COMMAND}" -E copy_directory "${MSIME_SPARKLE_FRAMEWORK}"
      "$<TARGET_BUNDLE_DIR:MSIMEClientInputMethod>/Contents/Frameworks/Sparkle.framework")
endif()
add_executable(candidate-skin-test tests/CandidateSkinTest.cpp CandidateSkin.cpp)
target_include_directories(candidate-skin-test PRIVATE .)
target_compile_options(candidate-skin-test PRIVATE -Wall -Wextra -Werror -UNDEBUG)
add_test(NAME candidate-skin COMMAND candidate-skin-test)
add_executable(external-skin-test tests/ExternalSkinTest.cpp CandidateSkin.cpp)
target_include_directories(external-skin-test PRIVATE .)
target_compile_options(external-skin-test PRIVATE -Wall -Wextra -Werror -UNDEBUG)
add_test(NAME external-skin COMMAND external-skin-test)
add_executable(text-client-test tests/TextClientTest.mm)
target_compile_options(text-client-test PRIVATE -fobjc-arc -Wall -Wextra -Werror -UNDEBUG)
target_link_libraries(text-client-test PRIVATE apple-client)
add_test(NAME text-client COMMAND text-client-test)
add_executable(string-conversion-test tests/StringConversionTest.mm StringConversion.mm)
target_compile_options(string-conversion-test PRIVATE -fobjc-arc -Wall -Wextra -Werror)
target_link_libraries(string-conversion-test PRIVATE "-framework Foundation")
add_test(NAME string-conversion COMMAND string-conversion-test)
add_executable(chinese-text-conversion-test tests/ChineseTextConversionTest.mm ChineseTextConversion.mm)
target_compile_options(chinese-text-conversion-test PRIVATE -fobjc-arc -Wall -Wextra -Werror -UNDEBUG)
target_link_libraries(chinese-text-conversion-test PRIVATE "-framework Foundation")
add_test(NAME chinese-text-conversion COMMAND chinese-text-conversion-test)
add_executable(session-smoke-test ../../shared/apple/tests/session_smoke.mm)
target_compile_options(session-smoke-test PRIVATE -fobjc-arc -Wall -Wextra -Werror -UNDEBUG)
target_include_directories(session-smoke-test PRIVATE ../../shared/apple ../../crates/host-api/include)
target_link_libraries(session-smoke-test PRIVATE apple-client "-framework Foundation")
add_test(NAME session-smoke COMMAND session-smoke-test)
add_executable(shortcut-test tests/ShortcutTest.mm AppearancePreferences.mm CandidateSkin.cpp CandidateSkinPreviewView.mm SkinSettingsView.mm ChineseTextConversion.mm ShuangpinKeymapPanel.mm InputSourceRegistration.mm FloatingToolbarPanel.mm UpdateController.mm DictionaryWindowController.mm ClientDictionaryRuntime.mm)
target_include_directories(shortcut-test PRIVATE ../../vendor/MSIME-Engine ../../vendor/MSIME-Engine/include)
target_compile_options(shortcut-test PRIVATE -fobjc-arc -Wall -Wextra -Werror -UNDEBUG)
target_link_libraries(shortcut-test PRIVATE apple-client "-framework AppKit" "-framework InputMethodKit" "-framework Carbon")
add_test(NAME shortcut COMMAND shortcut-test)
add_executable(candidate-panel-test tests/CandidatePanelTests.mm CandidatePanel.mm CandidateSkinAppearance.mm CandidateSkin.cpp)
target_compile_options(candidate-panel-test PRIVATE -fobjc-arc -Wall -Wextra -Werror)
target_link_libraries(candidate-panel-test PRIVATE apple-client "-framework AppKit" "-framework InputMethodKit")
add_test(NAME candidate-panel COMMAND candidate-panel-test)
add_executable(candidate-pagination-test tests/CandidatePaginationTest.cpp)
target_include_directories(candidate-pagination-test PRIVATE .)
target_compile_options(candidate-pagination-test PRIVATE -Wall -Wextra -Werror -UNDEBUG)
add_test(NAME candidate-pagination COMMAND candidate-pagination-test)
# The current client host uses the host-api adapter. DictionaryRuntime.mm is
# the retained Apple snapshot adapter for MetasequoiaInputController, not this host.
add_executable(dictionary-runtime-test tests/DictionaryRuntimeTest.mm ClientDictionaryRuntime.mm)
target_compile_options(dictionary-runtime-test PRIVATE -fobjc-arc -Wall -Wextra -Werror -UNDEBUG)
target_include_directories(dictionary-runtime-test PRIVATE ../../shared/apple ../../crates/host-api/include)
target_link_libraries(dictionary-runtime-test PRIVATE apple-client "-framework Foundation")
add_test(NAME dictionary-runtime COMMAND dictionary-runtime-test)
add_executable(skin-preview-test tests/SkinPreviewTest.mm AppearancePreferences.mm CandidateSkin.cpp CandidateSkinPreviewView.mm SkinSettingsView.mm ChineseTextConversion.mm)
target_include_directories(skin-preview-test PRIVATE .)
target_compile_options(skin-preview-test PRIVATE -fobjc-arc -Wall -Wextra -Werror -UNDEBUG)
target_link_libraries(skin-preview-test PRIVATE "-framework AppKit")
add_test(NAME skin-preview COMMAND skin-preview-test)
add_executable(skin-settings-test tests/SkinSettingsTest.mm AppearancePreferences.mm CandidateSkin.cpp CandidateSkinPreviewView.mm SkinSettingsView.mm ChineseTextConversion.mm)
target_include_directories(skin-settings-test PRIVATE .)
target_compile_options(skin-settings-test PRIVATE -fobjc-arc -Wall -Wextra -Werror -UNDEBUG)
target_link_libraries(skin-settings-test PRIVATE "-framework AppKit")
add_test(NAME skin-settings COMMAND skin-settings-test)
add_executable(apple-stored-preferences-test tests/AppleStoredPreferencesTest.mm)
target_compile_options(apple-stored-preferences-test PRIVATE -fobjc-arc -Wall -Wextra -Werror -UNDEBUG)
target_link_libraries(apple-stored-preferences-test PRIVATE "-framework Foundation")
add_test(NAME apple-stored-preferences COMMAND apple-stored-preferences-test)
add_executable(floating-toolbar-panel-test tests/FloatingToolbarPanelTest.mm FloatingToolbarPanel.mm CandidateSkinAppearance.mm CandidateSkin.cpp)
target_include_directories(floating-toolbar-panel-test PRIVATE ../../vendor/MSIME-Engine/include)
target_compile_options(floating-toolbar-panel-test PRIVATE -fobjc-arc -Wall -Wextra -Werror -UNDEBUG)
target_link_libraries(floating-toolbar-panel-test PRIVATE "-framework AppKit")
add_test(NAME floating-toolbar-panel COMMAND floating-toolbar-panel-test)
add_executable(input-source-registration-test tests/InputSourceRegistrationTests.mm InputSourceRegistration.mm)
target_compile_options(input-source-registration-test PRIVATE -fobjc-arc -Wall -Wextra -Werror -UNDEBUG)
target_link_libraries(input-source-registration-test PRIVATE "-framework Carbon" "-framework Foundation")
add_test(NAME input-source-registration COMMAND input-source-registration-test)
add_executable(local-input-mode-test tests/LocalInputModeTests.cpp)
target_include_directories(local-input-mode-test PRIVATE ../../vendor/MSIME-Engine/include)
target_compile_options(local-input-mode-test PRIVATE -Wall -Wextra -Werror -UNDEBUG)
target_link_libraries(local-input-mode-test PRIVATE apple-client)
add_test(NAME local-input-mode COMMAND local-input-mode-test)
add_executable(frequency-adjustment-preference-test tests/FrequencyAdjustmentPreferenceTests.cpp)
target_include_directories(frequency-adjustment-preference-test PRIVATE ../../vendor/MSIME-Engine/include)
target_compile_options(frequency-adjustment-preference-test PRIVATE -Wall -Wextra -Werror -UNDEBUG)
add_test(NAME frequency-adjustment-preference COMMAND frequency-adjustment-preference-test)
add_executable(candidate-selection-state-test tests/CandidateSelectionStateTests.cpp)
target_include_directories(candidate-selection-state-test PRIVATE . ../../vendor/MSIME-Engine/include)
target_compile_options(candidate-selection-state-test PRIVATE -Wall -Wextra -Werror -UNDEBUG)
target_link_libraries(candidate-selection-state-test PRIVATE "-framework Foundation")
add_test(NAME candidate-selection-state COMMAND candidate-selection-state-test)
