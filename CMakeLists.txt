cmake_minimum_required(VERSION 4.4.3)

project(
  AegisSpark
  VERSION 0.1.0
  DESCRIPTION
    "Formally verified SPARK Ada 2022 & ISO C23 robotics safety platform (NVIDIA Halos pattern)"
  LANGUAGES C CXX
)

set(CMAKE_C_STANDARD 23)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_C_EXTENSIONS OFF)

set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# Export compilation database for LSP (clangd) and clang-tidy
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# Register modular cmake/ directory
list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake")

# Include modular components
include(ProjectOptions)
include(CompilerWarnings)
include(Sanitizers)
find_package(Alire)

# -----------------------------------------------------------------------------
# SPARK Ada 2022 Core Packaging via Alire / GPRbuild
# -----------------------------------------------------------------------------
if(Alire_FOUND)
  set(AEGIS_SPARK_LIB_ARCHIVE "${CMAKE_CURRENT_SOURCE_DIR}/lib/libaegis_spark.a")
  set(AEGIS_SPARK_DEMO_BINARY "${CMAKE_CURRENT_SOURCE_DIR}/bin/aegis_spark")

  add_custom_command(
    OUTPUT "${AEGIS_SPARK_LIB_ARCHIVE}" "${AEGIS_SPARK_DEMO_BINARY}"
    COMMAND "${Alire_EXECUTABLE}" --non-interactive build --validation
    WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
    DEPENDS
      "${CMAKE_CURRENT_SOURCE_DIR}/src/halos_safety_gate.ads"
      "${CMAKE_CURRENT_SOURCE_DIR}/src/halos_safety_gate.adb"
      "${CMAKE_CURRENT_SOURCE_DIR}/src/halos_logger.ads"
      "${CMAKE_CURRENT_SOURCE_DIR}/src/halos_logger.adb"
      "${CMAKE_CURRENT_SOURCE_DIR}/src/halos_c_logger.h"
      "${CMAKE_CURRENT_SOURCE_DIR}/src/halos_c_logger.c"
      "${CMAKE_CURRENT_SOURCE_DIR}/src/uart0_mmio.ads"
      "${CMAKE_CURRENT_SOURCE_DIR}/src/uart0_mmio.adb"
      "${CMAKE_CURRENT_SOURCE_DIR}/src/aegis_spark.adb"
      "${CMAKE_CURRENT_SOURCE_DIR}/aegis_spark_lib.gpr"
      "${CMAKE_CURRENT_SOURCE_DIR}/aegis_spark.gpr"
      "${CMAKE_CURRENT_SOURCE_DIR}/gnat.adc"
    COMMENT "Building SPARK Ada 2022 standalone static library and host demo via Alire"
  )

  add_custom_target(
    aegis_spark_core
    ALL
    DEPENDS "${AEGIS_SPARK_LIB_ARCHIVE}" "${AEGIS_SPARK_DEMO_BINARY}"
  )

  # Imported target for libaegis_spark.a
  add_library(AegisSpark::aegis_spark STATIC IMPORTED GLOBAL)
  set_target_properties(
    AegisSpark::aegis_spark
    PROPERTIES
      IMPORTED_LOCATION "${AEGIS_SPARK_LIB_ARCHIVE}"
      INTERFACE_INCLUDE_DIRECTORIES "${CMAKE_CURRENT_SOURCE_DIR}/src"
  )
  add_dependencies(AegisSpark::aegis_spark aegis_spark_core)
else()
  message(STATUS "Alire (alr) not found; skipping SPARK Ada targets")
endif()

# -----------------------------------------------------------------------------
# ISO C23 Translation Units (Generates Native compile_commands.json entries)
# -----------------------------------------------------------------------------
add_library(
  halos_c_logger
  STATIC
  "${CMAKE_CURRENT_SOURCE_DIR}/src/halos_c_logger.c"
  "${CMAKE_CURRENT_SOURCE_DIR}/src/halos_c_logger.h"
)

target_include_directories(
  halos_c_logger
  PUBLIC "$<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/src>" "$<INSTALL_INTERFACE:include>"
)

target_link_libraries(halos_c_logger PRIVATE project_options project_warnings project_sanitizers)

# -----------------------------------------------------------------------------
# Testing Orchestration (CTest)
# -----------------------------------------------------------------------------
include(CTest)
if(BUILD_TESTING)
  enable_testing()

  if(Alire_FOUND)
    add_test(
      NAME host_demo_verification
      COMMAND "${AEGIS_SPARK_DEMO_BINARY}"
      WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
    )

    add_test(
      NAME spark_formal_proof
      COMMAND "${Alire_EXECUTABLE}" --non-interactive gnatprove --level=2 -j0
      WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
    )
  endif()

  find_program(PIXI_EXECUTABLE NAMES pixi)
  if(PIXI_EXECUTABLE)
    add_test(
      NAME python_test_suite
      COMMAND "${PIXI_EXECUTABLE}" run test-python -m "unit"
      WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
    )
  endif()
endif()
