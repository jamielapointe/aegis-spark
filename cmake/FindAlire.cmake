# cmake/FindAlire.cmake
#[=======================================================================[.rst:
FindAlire
---------

Finds the Alire package manager (`alr`) for Ada 2022 and SPARK projects.

Imported Targets
^^^^^^^^^^^^^^^^

``Alire::alr``
  The Alire executable.

Result Variables
^^^^^^^^^^^^^^^^

``Alire_FOUND``
  True if `alr` was found on the system.
``Alire_EXECUTABLE``
  The absolute path to the `alr` executable.
``Alire_VERSION``
  The version of `alr` found (e.g. 2.1.1).
#]=======================================================================]

find_program(
  Alire_EXECUTABLE
  NAMES alr
  HINTS "$ENV{HOME}/.local/bin" "/opt/homebrew/bin" "/usr/local/bin"
  DOC "Alire package manager for Ada 2022 and SPARK"
)

if(Alire_EXECUTABLE)
  execute_process(
    COMMAND "${Alire_EXECUTABLE}" --version
    OUTPUT_VARIABLE _alr_version_raw
    ERROR_QUIET
    OUTPUT_STRIP_TRAILING_WHITESPACE
  )

  if(_alr_version_raw MATCHES "alr[ ]+([0-9]+\\.[0-9]+\\.[0-9]+)")
    set(Alire_VERSION "${CMAKE_MATCH_1}")
  endif()
endif()

include(FindPackageHandleStandardArgs)
find_package_handle_standard_args(Alire REQUIRED_VARS Alire_EXECUTABLE VERSION_VAR Alire_VERSION)

if(Alire_FOUND AND NOT TARGET Alire::alr)
  add_executable(Alire::alr IMPORTED GLOBAL)
  set_target_properties(Alire::alr PROPERTIES IMPORTED_LOCATION "${Alire_EXECUTABLE}")
endif()
