# cmake/CompilerWarnings.cmake

add_library(project_warnings INTERFACE)

set(
  CLANG_C_WARNINGS
  -Wall
  -Wextra
  -Wpedantic
  -Wstrict-prototypes
  -Wmissing-prototypes
  -Wmissing-declarations
  -Wold-style-definition
  -Wbad-function-cast
  -Wconversion
  -Wsign-conversion
  -Wdouble-promotion
  -Wcast-qual
  -Wcast-align
  -Wwrite-strings
  -Wformat=2
  -Wformat-security
  -Wnull-dereference
  -Wshadow
  -Wimplicit-fallthrough
  -Wvla
  -Wundef
  -Wswitch-enum
  -ftrivial-auto-var-init=zero
)

set(
  CLANG_CXX_WARNINGS
  -Wall
  -Wextra
  -Wpedantic
  -Wshadow
  -Wnon-virtual-dtor
  -Wold-style-cast
  -Wcast-align
  -Wunused
  -Woverloaded-virtual
  -Wconversion
  -Wsign-conversion
  -Wnull-dereference
  -Wdouble-promotion
  -Wformat=2
  -Wimplicit-fallthrough
)

option(WARNINGS_AS_ERRORS "Treat compiler warnings as errors" ON)
if(WARNINGS_AS_ERRORS)
  list(APPEND CLANG_C_WARNINGS -Werror)
  list(APPEND CLANG_CXX_WARNINGS -Werror)
endif()

target_compile_options(
  project_warnings
  INTERFACE
    $<$<COMPILE_LANGUAGE:C>:${CLANG_C_WARNINGS}>
    $<$<COMPILE_LANGUAGE:CXX>:${CLANG_CXX_WARNINGS}>
)
