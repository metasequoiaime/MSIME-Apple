cmake_minimum_required(VERSION 3.25)
project(MsimeEngineBridge LANGUAGES CXX)
set(BUILD_TESTING OFF CACHE BOOL "" FORCE)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
find_package(SQLite3 REQUIRED)
if(TARGET SQLite3::SQLite3)
    set(METASEQUOIA_SQLITE_TARGET SQLite3::SQLite3)
else()
    set(METASEQUOIA_SQLITE_TARGET SQLite::SQLite3)
endif()
add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../../../vendor/MSIME-Engine" engine)
option(MSIME_ENGINE_BRIDGE_HANDWRITING "Build the optional Engine handwriting recognizer" ON)
if(MSIME_ENGINE_BRIDGE_HANDWRITING)
    # The bridge links the engine statically. Without this the vendored zinnia
    # header resolves to __declspec(dllimport) on Windows and the archive cannot
    # be linked.
    target_compile_definitions(MetasequoiaHandwriting PUBLIC ZINNIA_STATIC_LIBRARY)
else()
    # Mobile hosts inject their platform recognizer and must not ship a second,
    # unreachable zinnia implementation just because the shared Engine exports one.
    set_target_properties(MetasequoiaHandwriting PROPERTIES EXCLUDE_FROM_ALL TRUE)
endif()
install(TARGETS MetasequoiaImeEngine ARCHIVE DESTINATION lib)
if(MSIME_ENGINE_BRIDGE_HANDWRITING AND TARGET MetasequoiaHandwriting)
    install(TARGETS MetasequoiaHandwriting ARCHIVE DESTINATION lib)
endif()
file(GENERATE OUTPUT "${CMAKE_CURRENT_BINARY_DIR}/sqlite-path.txt" CONTENT "$<TARGET_FILE:${METASEQUOIA_SQLITE_TARGET}>" )
