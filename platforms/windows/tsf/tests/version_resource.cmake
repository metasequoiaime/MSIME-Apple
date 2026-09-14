file(READ "${SOURCE_ROOT}/../../../Cargo.toml" workspace_manifest)
string(REGEX MATCH
  "\\[workspace\\.package\\][ \t\r\n]+version[ \t]*=[ \t]*\"([0-9]+)\\.([0-9]+)\\.([0-9]+)\""
  workspace_version_match "${workspace_manifest}")
if(NOT workspace_version_match)
  message(FATAL_ERROR "workspace package version missing or unsupported")
endif()
set(expected_version "${CMAKE_MATCH_1}.${CMAKE_MATCH_2}.${CMAKE_MATCH_3}.0")
set(expected_version_commas "${CMAKE_MATCH_1},${CMAKE_MATCH_2},${CMAKE_MATCH_3},0")

file(READ "${SOURCE_ROOT}/Header/resource.h" resource_header)
if(NOT resource_header MATCHES "#define[ \t]+VS_VERSION_INFO[ \t]+1")
  message(FATAL_ERROR "TSF resource does not use the standard version identifier")
endif()
if(resource_header MATCHES "IDR_VERSION2")
  message(FATAL_ERROR "legacy TSF version identifier remains")
endif()

file(READ "${SOURCE_ROOT}/IME/MetasequoiaIME.rc" version_resource)
foreach(kind IN ITEMS FILEVERSION PRODUCTVERSION)
  string(REGEX MATCH
    "${kind}[ \t]+([0-9]+),([0-9]+),([0-9]+),([0-9]+)"
    numeric_version_match "${version_resource}")
  if(NOT numeric_version_match)
    message(FATAL_ERROR "${kind} numeric resource is missing")
  endif()
  set(actual_version_commas
    "${CMAKE_MATCH_1},${CMAKE_MATCH_2},${CMAKE_MATCH_3},${CMAKE_MATCH_4}")
  if(NOT actual_version_commas STREQUAL expected_version_commas)
    message(FATAL_ERROR
      "${kind} ${actual_version_commas} does not match workspace ${expected_version_commas}")
  endif()
endforeach()

foreach(field IN ITEMS FileVersion ProductVersion)
  string(FIND "${version_resource}"
    "VALUE \"${field}\", \"${expected_version}\"" field_position)
  if(field_position EQUAL -1)
    message(FATAL_ERROR "${field} does not match workspace ${expected_version}")
  endif()
endforeach()

foreach(field IN ITEMS InternalName OriginalFilename)
  string(FIND "${version_resource}"
    "VALUE \"${field}\", \"MetasequoiaImeTsf.dll\"" field_position)
  if(field_position EQUAL -1)
    message(FATAL_ERROR "${field} does not match the TSF DLL output name")
  endif()
endforeach()
