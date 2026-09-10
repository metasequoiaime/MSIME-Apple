# Compile the shared Swift transport and native account window without requiring
# a generator with Swift language support (the release uses Unix Makefiles).
execute_process(COMMAND xcrun --find swiftc OUTPUT_VARIABLE MSIME_SWIFTC
    OUTPUT_STRIP_TRAILING_WHITESPACE COMMAND_ERROR_IS_FATAL ANY)
execute_process(COMMAND xcrun --sdk macosx --show-sdk-path OUTPUT_VARIABLE MSIME_SWIFT_SDK
    OUTPUT_STRIP_TRAILING_WHITESPACE COMMAND_ERROR_IS_FATAL ANY)
get_filename_component(MSIME_SWIFT_BIN "${MSIME_SWIFTC}" DIRECTORY)
set(MSIME_SERVICES_HEADER "${CMAKE_CURRENT_SOURCE_DIR}/shared/apple-bridge/AppServicesBridge.h")
set(MSIME_ACCOUNT_SOURCES
    "${METASEQUOIA_MACOS_ROOT}/src/SkinPackageRevision.swift"
    "${CMAKE_CURRENT_SOURCE_DIR}/shared/apple-services/AISkinService.swift"
    "${CMAKE_CURRENT_SOURCE_DIR}/shared/backend/BackendSkinArtworkClient.swift"
    "${METASEQUOIA_MACOS_ROOT}/src/AISkinGalleryView.swift"
    "${METASEQUOIA_MACOS_ROOT}/src/SkinArtwork.swift"
    "${METASEQUOIA_MACOS_ROOT}/src/SkinEditorWindow.swift"
    "${METASEQUOIA_MACOS_ROOT}/src/SkinPublicationView.swift"
    "${CMAKE_CURRENT_SOURCE_DIR}/shared/apple-models/CustomKeyboardSkinModel.swift"
    "${CMAKE_CURRENT_SOURCE_DIR}/shared/backend/BackendSkinCommunityClient.swift"
    "${METASEQUOIA_MACOS_ROOT}/src/CommunitySkinView.swift"
    "${METASEQUOIA_MACOS_ROOT}/src/SkinGenerationView.swift"
    "${CMAKE_CURRENT_SOURCE_DIR}/shared/apple-models/ClipboardHistoryStore.swift"
    "${METASEQUOIA_MACOS_ROOT}/src/ClipboardHistoryWindow.swift"
    "${METASEQUOIA_MACOS_ROOT}/src/ReplyTemplateStore.swift"
    "${METASEQUOIA_MACOS_ROOT}/src/CustomWritingSettings.swift"
    "${CMAKE_CURRENT_SOURCE_DIR}/shared/apple-services/CustomService.swift"
    "${METASEQUOIA_MACOS_ROOT}/src/NativeWritingWindow.swift"
    "${CMAKE_CURRENT_SOURCE_DIR}/shared/apple-models/WritingTask.swift"
    "${METASEQUOIA_MACOS_ROOT}/src/BackendWritingView.swift"
    "${METASEQUOIA_MACOS_ROOT}/src/DictionaryMutation.swift"
    "${CMAKE_CURRENT_SOURCE_DIR}/shared/apple-models/PersonalWord.swift"
    "${CMAKE_CURRENT_SOURCE_DIR}/shared/apple-models/PersonalDictionaryImport.swift"
    "${METASEQUOIA_MACOS_ROOT}/src/PersonalDictionaryWindow.swift"
    "${CMAKE_CURRENT_SOURCE_DIR}/shared/apple-models/TypingStatistics.swift"
    "${METASEQUOIA_MACOS_ROOT}/src/TypingStatisticsWindow.swift"
    "${CMAKE_CURRENT_SOURCE_DIR}/shared/backend/BackendAccountClient.swift"
    "${CMAKE_CURRENT_SOURCE_DIR}/shared/backend/BackendAccountSession.swift"
    "${CMAKE_CURRENT_SOURCE_DIR}/shared/backend/BackendClipboardClient.swift"
    "${CMAKE_CURRENT_SOURCE_DIR}/shared/backend/BackendPreferencesClient.swift"
    "${CMAKE_CURRENT_SOURCE_DIR}/shared/backend/BackendDictionaryClient.swift"
    "${CMAKE_CURRENT_SOURCE_DIR}/shared/backend/BackendCandidateClient.swift"
    "${CMAKE_CURRENT_SOURCE_DIR}/shared/backend/BackendChatClient.swift"
    "${METASEQUOIA_MACOS_ROOT}/src/BackendChatView.swift"
    "${CMAKE_CURRENT_SOURCE_DIR}/shared/backend/BackendSnapshotClient.swift"
    "${CMAKE_CURRENT_SOURCE_DIR}/shared/backend/BackendCommunityResourceClient.swift"
    "${METASEQUOIA_MACOS_ROOT}/src/BackendFileTransfer.swift"
    "${METASEQUOIA_MACOS_ROOT}/src/BackendSnapshotView.swift"
    "${METASEQUOIA_MACOS_ROOT}/src/BackendLocalSnapshot.swift"
    "${CMAKE_CURRENT_SOURCE_DIR}/shared/backend-ui/BackendInputModifiers.swift"
    "${CMAKE_CURRENT_SOURCE_DIR}/shared/backend-ui/CloudCandidatesView.swift"
    "${CMAKE_CURRENT_SOURCE_DIR}/shared/backend-ui/BackendCommunityResourcesView.swift"
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
            -target "${architecture}-apple-macos${CMAKE_OSX_DEPLOYMENT_TARGET}" -import-objc-header "${MSIME_SERVICES_HEADER}"
            ${MSIME_ACCOUNT_SOURCES} -o "${archive}"
        DEPENDS ${MSIME_ACCOUNT_SOURCES} "${MSIME_SERVICES_HEADER}" VERBATIM)
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
target_link_libraries(MSIMEBackendAccount INTERFACE MetasequoiaAppServicesBridge)
target_link_directories(MSIMEBackendAccount INTERFACE /usr/lib/swift "${MSIME_SWIFT_BIN}/../lib/swift/macosx")

if(BUILD_TESTING)
    set(MSIME_ACCOUNT_TEST "${CMAKE_CURRENT_BINARY_DIR}/backend-account/BackendAccountTests")
    add_custom_command(OUTPUT "${MSIME_ACCOUNT_TEST}"
        COMMAND ${CMAKE_COMMAND} -E make_directory "${CMAKE_CURRENT_BINARY_DIR}/backend-account"
        COMMAND "${MSIME_SWIFTC}" -sdk "${MSIME_SWIFT_SDK}" -parse-as-library
            -target "${CMAKE_HOST_SYSTEM_PROCESSOR}-apple-macos${CMAKE_OSX_DEPLOYMENT_TARGET}" -import-objc-header "${MSIME_SERVICES_HEADER}"
            ${MSIME_ACCOUNT_SOURCES} "${METASEQUOIA_MACOS_ROOT}/tests/BackendAccountTests.swift"
            "$<TARGET_FILE:MetasequoiaAppServicesBridge>" "$<TARGET_FILE:MetasequoiaImeVoice>" -lc++
            -o "${MSIME_ACCOUNT_TEST}"
        DEPENDS ${MSIME_ACCOUNT_SOURCES} "${METASEQUOIA_MACOS_ROOT}/tests/BackendAccountTests.swift"
            "${MSIME_SERVICES_HEADER}" MetasequoiaAppServicesBridge MetasequoiaImeVoice
        VERBATIM)
    add_custom_target(MSIMEBackendAccountTestsBuild ALL DEPENDS "${MSIME_ACCOUNT_TEST}")
    add_test(NAME backend_account COMMAND "${MSIME_ACCOUNT_TEST}")
    set_tests_properties(backend_account PROPERTIES TIMEOUT 30)
endif()
