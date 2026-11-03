# cmake/Sanitizers.cmake

include(CheckCSourceCompiles)
include(CMakePushCheckState)

add_library(project_sanitizers INTERFACE)

option(ENABLE_SANITIZER_ADDRESS "Enable AddressSanitizer (ASan)" OFF)
option(ENABLE_SANITIZER_UNDEFINED "Enable UndefinedBehaviorSanitizer (UBSan)" OFF)

if(CMAKE_C_COMPILER_ID MATCHES ".*Clang|GNU")
  set(SANITIZER_FLAGS "")

  if(ENABLE_SANITIZER_ADDRESS)
    list(APPEND SANITIZER_FLAGS "-fsanitize=address" "-fno-omit-frame-pointer")
  endif()

  if(ENABLE_SANITIZER_UNDEFINED)
    list(APPEND SANITIZER_FLAGS "-fsanitize=undefined")
  endif()

  if(SANITIZER_FLAGS)
    cmake_push_check_state()
    set(CMAKE_REQUIRED_FLAGS "${SANITIZER_FLAGS}")
    set(CMAKE_REQUIRED_LINK_OPTIONS "${SANITIZER_FLAGS}")
    check_c_source_compiles("int main(void) { return 0; }" COMPILER_SUPPORTS_SANITIZERS)
    cmake_pop_check_state()

    if(COMPILER_SUPPORTS_SANITIZERS)
      target_compile_options(project_sanitizers INTERFACE ${SANITIZER_FLAGS})
      target_link_options(project_sanitizers INTERFACE ${SANITIZER_FLAGS})
      message(STATUS "Sanitizers enabled: ${SANITIZER_FLAGS}")
    else()
      message(
        FATAL_ERROR
        "Requested sanitizers are not supported by the current compiler: ${SANITIZER_FLAGS}"
      )
    endif()
  endif()
endif()
