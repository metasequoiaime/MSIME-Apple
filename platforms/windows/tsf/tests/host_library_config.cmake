file(MAKE_DIRECTORY "${TEST_ROOT}")
file(WRITE "${TEST_ROOT}/fixture.lib" "linking is verified separately")
set(cases "" "relative.lib" "${TEST_ROOT}/missing.lib" "${TEST_ROOT}")
foreach(candidate IN LISTS cases)
  execute_process(COMMAND "${CMAKE_COMMAND}" "-DMSIME_HOST_LIBRARY=${candidate}"
    -P "${SOURCE_ROOT}/RequireHostLibrary.cmake"
    RESULT_VARIABLE result OUTPUT_VARIABLE output ERROR_VARIABLE error)
  if(result EQUAL 0 OR NOT error MATCHES "MSIME_HOST_LIBRARY must name")
    message(FATAL_ERROR "Invalid library path was not rejected with an actionable error")
  endif()
endforeach()
execute_process(COMMAND "${CMAKE_COMMAND}" "-DMSIME_HOST_LIBRARY=${TEST_ROOT}/fixture.lib"
  -P "${SOURCE_ROOT}/RequireHostLibrary.cmake" RESULT_VARIABLE result)
file(REMOVE "${TEST_ROOT}/fixture.lib")
if(NOT result EQUAL 0)
  message(FATAL_ERROR "Existing absolute file was rejected")
endif()
