# cmake/ProjectOptions.cmake

add_library(project_options INTERFACE)

# Compiler Launcher (ccache)
find_program(CCACHE_PROGRAM ccache)
if(CCACHE_PROGRAM)
  message(STATUS "Compiler launcher found: ${CCACHE_PROGRAM}")
  set(CMAKE_C_COMPILER_LAUNCHER "${CCACHE_PROGRAM}")
  set(CMAKE_CXX_COMPILER_LAUNCHER "${CCACHE_PROGRAM}")
endif()

# Position Independent Code
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# Output Directories
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin")
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/lib")
set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/lib")

# Interprocedural Optimization (LTO)
option(ENABLE_IPO "Enable Interprocedural Optimization (LTO)" OFF)
if(ENABLE_IPO)
  include(CheckIPOSupported)
  check_ipo_supported(RESULT ipo_supported OUTPUT ipo_error)
  if(ipo_supported)
    set(CMAKE_INTERPROCEDURAL_OPTIMIZATION ON)
    message(STATUS "Interprocedural Optimization (IPO/LTO) enabled")
  else()
    message(WARNING "IPO requested but not supported: ${ipo_error}")
  endif()
endif()
