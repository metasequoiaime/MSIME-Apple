cmake_minimum_required(VERSION 3.25)

project(MSIMEClientTsf LANGUAGES CXX)
enable_testing()
add_executable(msime-tsf-candidate-ownership-test tests/candidate_ownership.cpp)
target_compile_features(msime-tsf-candidate-ownership-test PRIVATE cxx_std_17)
add_test(NAME msime-tsf-candidate-ownership COMMAND msime-tsf-candidate-ownership-test)
add_executable(msime-tsf-preedit-caret-test tests/preedit_caret.cpp)
target_compile_features(msime-tsf-preedit-caret-test PRIVATE cxx_std_17)
add_test(NAME msime-tsf-preedit-caret COMMAND msime-tsf-preedit-caret-test)
find_package(nlohmann_json 3.11 REQUIRED)
add_executable(msime-tsf-engine-response-test tests/engine_response.cpp EngineResponse.cpp)
target_compile_features(msime-tsf-engine-response-test PRIVATE cxx_std_17)
target_include_directories(msime-tsf-engine-response-test PRIVATE ../../../crates/host-api/include)
target_link_libraries(msime-tsf-engine-response-test PRIVATE nlohmann_json::nlohmann_json)
add_test(NAME msime-tsf-engine-response COMMAND msime-tsf-engine-response-test)

# The TSF tip is an in-process DLL.  It is intentionally a separate target
# from the out-of-process Windows Server.
if(NOT WIN32)
  return()
endif()

add_library(msime-tsf SHARED
  Candidate/EnumTfCandidates.cpp Candidate/SearchCandidateProvider.cpp
  Candidate/TipCandidateList.cpp Candidate/TipCandidateString.cpp
  Compartment/Compartment.cpp
  Composition/Composition.cpp Composition/CompositionProcessorEngine.cpp
  Composition/EndComposition.cpp Composition/StartComposition.cpp
  DisplayAttribute/DisplayAttribute.cpp DisplayAttribute/DisplayAttributeInfo.cpp
  DisplayAttribute/DisplayAttributeProvider.cpp DisplayAttribute/EnumDisplayAttributeInfo.cpp
  Edit/EditSession.cpp Edit/GetTextExtentEditSession.cpp Edit/TextEditSink.cpp
  Global/Globals.cpp
  IME/ActiveLanguageProfileNotifySink.cpp IME/FunctionProviderSink.cpp
  IME/MetasequoiaIME.cpp IME/MetasequoiaIMEBaseStructure.cpp
  IPC/Ipc.cpp
  Key/KeyEventSink.cpp Key/KeyHandler.cpp Key/KeyHandlerEditSession.cpp
  Key/KeyStateCategory.cpp
  LanguageBar/LanguageBar.cpp
  Register/Register.cpp Register/RegKey.cpp
  Tf/TfInputProcessorProfile.cpp Tf/TfTextLayoutSink.cpp
  Thread/ThreadFocusSink.cpp Thread/ThreadMgrEventSink.cpp
  UI/CandidateSessionState.cpp UI/CandidateListUIPresenter.cpp
  Utils/CommonUtils.cpp Utils/FanyUtils.cpp
  DllMain.cpp Server.cpp
  EngineSessionAdapter.cpp EngineSessionAdapter.h EngineResponse.cpp
  HostOptionsPaths.cpp HostOptionsPaths.h
  IME/MetasequoiaIME.rc
)

find_package(fmt CONFIG REQUIRED)
find_path(UTF8CPP_INCLUDE_DIR NAMES utf8cpp/utf8.h REQUIRED)

target_include_directories(msime-tsf PRIVATE
  . Candidate Compartment Composition DisplayAttribute Edit FanyLog Global
  Header IME IPC Key LanguageBar Register Tf Thread UI Utils
  ../../../vendor/MSIME-Engine/contracts
  ${UTF8CPP_INCLUDE_DIR}
  ../../../crates/host-api/include
)
target_compile_features(msime-tsf PRIVATE cxx_std_17)
target_compile_definitions(msime-tsf PRIVATE UNICODE _UNICODE)
target_link_libraries(msime-tsf PRIVATE nlohmann_json::nlohmann_json fmt::fmt-header-only ole32 oleaut32 user32 advapi32 msctf)
set(MSIME_HOST_LIBRARY "" CACHE FILEPATH "Cargo-built msime-host library for the TSF DLL")
if(MSIME_HOST_LIBRARY)
  target_link_libraries(msime-tsf PRIVATE "${MSIME_HOST_LIBRARY}")
endif()
set_target_properties(msime-tsf PROPERTIES OUTPUT_NAME MetasequoiaImeTsf)
install(TARGETS msime-tsf
  RUNTIME DESTINATION bin
  LIBRARY DESTINATION lib
  ARCHIVE DESTINATION lib
)
if(MSVC)
  target_compile_options(msime-tsf PRIVATE /W4 /Zc:__cplusplus /Zc:threadSafeInit-)
  set_property(TARGET msime-tsf PROPERTY MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
endif()
