# Compile the shared Swift transport and native account window without requiring
# a generator with Swift language support (the release uses Unix Makefiles).
execute_process(COMMAND xcrun --find swiftc OUTPUT_VARIABLE MSIME_SWIFTC
    OUTPUT_STRIP_TRAILING_WHITESPACE COMMAND_ERROR_IS_FATAL ANY)
execute_process(COMMAND xcrun --sdk macosx --show-sdk-path OUTPUT_VARIABLE MSIME_SWIFT_SDK
    OUTPUT_STRIP_TRAILING_WHITESPACE COMMAND_ERROR_IS_FATAL ANY)
get_filename_component(MSIME_SWIFT_BIN "${MSIME_SWIFTC}" DIRECTORY)
set(MSIME_ACCOUNT_SOURCES
    "${CMAKE_CURRENT_SOURCE_DIR}/shared/backend/BackendAccountClient.swift"
    "${CMAKE_CURRENT_SOURCE_DIR}/shared/backend/BackendAccountSession.swift"
    "${CMAKE_CURRENT_SOURCE_DIR}/shared/backend/BackendClipboardClient.swift"
    "${CMAKE_CURRENT_SOURCE_DIR}/shared/backend/BackendPreferencesClient.swift"
    "${CMAKE_CURRENT_SOURCE_DIR}/shared/backend/BackendDictionaryClient.swift"
    "${CMAKE_CURRENT_SOURCE_DIR}/shared/backend/BackendCandidateClient.swift"
    "${CMAKE_CURRENT_SOURCE_DIR}/shared/backend/BackendSnapshotClient.swift"
    "${CMAKE_CURRENT_SOURCE_DIR}/shared/backend/BackendCommunityResourceClient.swift"
    "${METASEQUOIA_MACOS_ROOT}/src/BackendFileTransfer.swift"
    "${METASEQUOIA_MACOS_ROOT}/src/BackendSnapshotView.swift"
    "${METASEQUOIA_MACOS_ROOT}/src/BackendLocalSnapshot.swift"
    "${CMAKE_CURRENT_SOURCE_DIR}/shared/backend-ui/BackendInputModifiers.swift"
    "${CMAKE_CURRENT_SOURCE_DIR}/shared/backend-ui/CloudCandidatesView.swift"
    "${CMAKE_CURRENT_SOURCE_DIR}/shared/backend-ui/CloudDictionaryCatalogView.swift"
    "${CMAKE_CURRENT_SOURCE_DIR}/shared/backend-ui/CloudDictionaryEditor.swift"
    "${METASEQUOIA_MACOS_ROOT}/src/BackendDictionaryView.swift"
    "${METASEQUOIA_MACOS_ROOT}/src/BackendSettingsView.swift"
    "${METASEQUOIA_MACOS_ROOT}/src/BackendClipboardView.swift"
    "${METASEQUOIA_MACOS_ROOT}/src/BackendAccountWindow.swift")
set(MSIME_ACCOUNT_ARCHIVES)
foreach(architecture IN LISTS CMAKE_OSX_ARCHITECTURES)
    set(archive "${CMAKE_CURRENT_BINARY_DIR}/backend-account/${architecture}/libMSIMEBackendAccount.a")
    add_custom_command(OUTPUT "${archive}"
        COMMAND ${CMAKE_COMMAND} -E make_directory "${CMAKE_CURRENT_BINARY_DIR}/backend-account/${architecture}"
        COMMAND "${MSIME_SWIFTC}" -sdk "${MSIME_SWIFT_SDK}" -emit-library -static -O -module-name MSIMEBackendAccount
            -target "${architecture}-apple-macos${CMAKE_OSX_DEPLOYMENT_TARGET}"
            ${MSIME_ACCOUNT_SOURCES} -o "${archive}"
        DEPENDS ${MSIME_ACCOUNT_SOURCES} VERBATIM)
    list(APPEND MSIME_ACCOUNT_ARCHIVES "${archive}")
endforeach()
set(MSIME_ACCOUNT_LIBRARY "${CMAKE_CURRENT_BINARY_DIR}/backend-account/libMSIMEBackendAccount.a")
add_custom_command(OUTPUT "${MSIME_ACCOUNT_LIBRARY}"
    COMMAND xcrun lipo -create ${MSIME_ACCOUNT_ARCHIVES} -output "${MSIME_ACCOUNT_LIBRARY}"
    DEPENDS ${MSIME_ACCOUNT_ARCHIVES} VERBATIM)
add_custom_target(MSIMEBackendAccountBuild DEPENDS "${MSIME_ACCOUNT_LIBRARY}")
add_library(MSIMEBackendAccount STATIC IMPORTED GLOBAL)
set_target_properties(MSIMEBackendAccount PROPERTIES IMPORTED_LOCATION "${MSIME_ACCOUNT_LIBRARY}")
add_dependencies(MSIMEBackendAccount MSIMEBackendAccountBuild)
target_link_directories(MSIMEBackendAccount INTERFACE /usr/lib/swift "${MSIME_SWIFT_BIN}/../lib/swift/macosx")

if(BUILD_TESTING)
    set(MSIME_ACCOUNT_TEST "${CMAKE_CURRENT_BINARY_DIR}/backend-account/BackendAccountTests")
    add_custom_command(OUTPUT "${MSIME_ACCOUNT_TEST}"
        COMMAND ${CMAKE_COMMAND} -E make_directory "${CMAKE_CURRENT_BINARY_DIR}/backend-account"
        COMMAND "${MSIME_SWIFTC}" -sdk "${MSIME_SWIFT_SDK}" -parse-as-library
            -target "${CMAKE_HOST_SYSTEM_PROCESSOR}-apple-macos${CMAKE_OSX_DEPLOYMENT_TARGET}"
            ${MSIME_ACCOUNT_SOURCES} "${METASEQUOIA_MACOS_ROOT}/tests/BackendAccountTests.swift"
            -o "${MSIME_ACCOUNT_TEST}"
        DEPENDS ${MSIME_ACCOUNT_SOURCES} "${METASEQUOIA_MACOS_ROOT}/tests/BackendAccountTests.swift"
        VERBATIM)
    add_custom_target(MSIMEBackendAccountTestsBuild ALL DEPENDS "${MSIME_ACCOUNT_TEST}")
    add_test(NAME backend_account COMMAND "${MSIME_ACCOUNT_TEST}")
    set_tests_properties(backend_account PROPERTIES TIMEOUT 30)
endif()
