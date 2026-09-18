# Local-only synthetic/isolated clipboard tests. Never launch the input method.
find_program(MSIME_XCRUN xcrun REQUIRED)
add_custom_target(macos-clipboard-tests)

function(msime_clipboard_swift_test name entry)
  set(sources "${CMAKE_CURRENT_SOURCE_DIR}/${entry}")
  foreach(source IN LISTS ARGN)
    list(APPEND sources "${CMAKE_CURRENT_SOURCE_DIR}/${source}")
  endforeach()
  set(executable "${CMAKE_CURRENT_BINARY_DIR}/${name}-test")
  add_custom_command(OUTPUT "${executable}"
    COMMAND "${MSIME_XCRUN}" swiftc -Onone
      -target "${CMAKE_HOST_SYSTEM_PROCESSOR}-apple-macosx${CMAKE_OSX_DEPLOYMENT_TARGET}"
      ${sources} -o "${executable}"
    DEPENDS ${sources} "${CMAKE_CURRENT_SOURCE_DIR}/ClipboardTests.cmake"
    VERBATIM)
  add_custom_target(${name}-build ALL DEPENDS "${executable}")
  add_dependencies(macos-clipboard-tests ${name}-build)
  add_test(NAME ${name} COMMAND "${executable}")
  set_tests_properties(${name} PROPERTIES LABELS "clipboard-local" TIMEOUT 30)
endfunction()

set(clipboard_catalog_sources src/BackendClipboardTextLimits.swift src/BackendEmojiSymbolGroups.swift src/BackendEmojiCatalog.swift
  src/BackendEmojiClipboardHistory.swift)
set(clipboard_monitor_sources ${clipboard_catalog_sources} src/BackendClipboardCapture.swift
  src/BackendClipboardMonitor.swift)
set(clipboard_row_sources src/BackendEmojiAppearance.swift src/BackendEmojiClipboardRow.swift
  src/BackendEmojiClipboardTooltip.swift)

msime_clipboard_swift_test(clipboard-history-adapter tests/EmojiClipboardHistoryTest.swift
  ${clipboard_catalog_sources})
msime_clipboard_swift_test(clipboard-history-observation tests/EmojiClipboardObservationTest.swift
  ${clipboard_catalog_sources})
msime_clipboard_swift_test(clipboard-capture tests/ClipboardCaptureTest.swift src/BackendClipboardCapture.swift src/BackendClipboardTextLimits.swift)
msime_clipboard_swift_test(clipboard-monitor tests/ClipboardMonitorTest.swift ${clipboard_monitor_sources})
msime_clipboard_swift_test(clipboard-service tests/ClipboardServiceTest.swift
  ${clipboard_monitor_sources} src/BackendClipboardService.swift)
msime_clipboard_swift_test(clipboard-preview tests/EmojiClipboardPreviewTest.swift ${clipboard_row_sources})
msime_clipboard_swift_test(clipboard-tooltip tests/EmojiClipboardTooltipTest.swift ${clipboard_row_sources})
msime_clipboard_swift_test(clipboard-window-close tests/EmojiWindowCloseTest.swift src/BackendEmojiWindowController.swift)
msime_clipboard_swift_test(clipboard-copy-recents tests/EmojiRecentsTest.swift
  src/BackendEmojiSymbolGroups.swift src/BackendEmojiCatalog.swift src/BackendEmojiRecents.swift)

add_executable(clipboard-preferences-test tests/ClipboardPreferencesTest.mm)
target_compile_options(clipboard-preferences-test PRIVATE -fobjc-arc -Wall -Wextra -Werror -UNDEBUG)
target_link_libraries(clipboard-preferences-test PRIVATE "-framework Foundation")
add_dependencies(macos-clipboard-tests clipboard-preferences-test)
add_test(NAME clipboard-preferences COMMAND clipboard-preferences-test)
set_tests_properties(clipboard-preferences PROPERTIES LABELS "clipboard-local" TIMEOUT 30)
