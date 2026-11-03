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

# Dual-Tier HAL Target Hardware Mode (host_sim, qemu_virt, igx_thor)
set(
  AEGIS_TARGET_MODE
  "host_sim"
  CACHE STRING
  "Target hardware execution mode (host_sim, qemu_virt, igx_thor)"
)

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
  set(AEGIS_SPARK_AUNIT_BINARY "${CMAKE_CURRENT_SOURCE_DIR}/bin/aunit_runner")

  add_custom_command(
    OUTPUT "${AEGIS_SPARK_LIB_ARCHIVE}" "${AEGIS_SPARK_DEMO_BINARY}"
    COMMAND
      "${Alire_EXECUTABLE}" --non-interactive exec -- gprbuild -P aegis_spark_lib.gpr
      -XAEGIS_TARGET_MODE=${AEGIS_TARGET_MODE}
    COMMAND
      "${Alire_EXECUTABLE}" --non-interactive exec -- gprbuild -P aegis_spark.gpr
      -XAEGIS_TARGET_MODE=${AEGIS_TARGET_MODE}
    WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
    DEPENDS
      "${CMAKE_CURRENT_SOURCE_DIR}/src/aegis.ads"
      "${CMAKE_CURRENT_SOURCE_DIR}/src/aegis-hal.ads"
      "${CMAKE_CURRENT_SOURCE_DIR}/src/hal/host_sim/aegis-hal-registers.ads"
      "${CMAKE_CURRENT_SOURCE_DIR}/src/hal/host_sim/aegis-hal-registers.adb"
      "${CMAKE_CURRENT_SOURCE_DIR}/src/hal/qemu_virt/aegis-hal-registers.ads"
      "${CMAKE_CURRENT_SOURCE_DIR}/src/hal/igx_thor/aegis-hal-registers.ads"
      "${CMAKE_CURRENT_SOURCE_DIR}/src/halos_safety_gate.ads"
      "${CMAKE_CURRENT_SOURCE_DIR}/src/halos_safety_gate.adb"
      "${CMAKE_CURRENT_SOURCE_DIR}/src/halos_watchdog.ads"
      "${CMAKE_CURRENT_SOURCE_DIR}/src/halos_watchdog.adb"
      "${CMAKE_CURRENT_SOURCE_DIR}/src/halos_hsm.ads"
      "${CMAKE_CURRENT_SOURCE_DIR}/src/halos_hsm.adb"
      "${CMAKE_CURRENT_SOURCE_DIR}/src/halos_kinematics.ads"
      "${CMAKE_CURRENT_SOURCE_DIR}/src/halos_kinematics.adb"
      "${CMAKE_CURRENT_SOURCE_DIR}/src/halos_mailbox.ads"
      "${CMAKE_CURRENT_SOURCE_DIR}/src/halos_mailbox.adb"
      "${CMAKE_CURRENT_SOURCE_DIR}/src/halos_mailbox.h"
      "${CMAKE_CURRENT_SOURCE_DIR}/src/halos_mailbox.c"
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
    COMMENT "Building SPARK Ada 2022 standalone static library and host demo via Alire / GPRbuild"
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

  # AUnit Native Test Runner (Host SIL only)
  if(AEGIS_TARGET_MODE STREQUAL "host_sim")
    add_custom_command(
      OUTPUT "${AEGIS_SPARK_AUNIT_BINARY}"
      COMMAND
        "${Alire_EXECUTABLE}" --non-interactive exec -- gprbuild -P
        tests/aunit/aegis_spark_tests.gpr -XAEGIS_TARGET_MODE=${AEGIS_TARGET_MODE}
      WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
      DEPENDS
        "${AEGIS_SPARK_LIB_ARCHIVE}"
        "${CMAKE_CURRENT_SOURCE_DIR}/tests/aunit/aegis_spark_tests.gpr"
        "${CMAKE_CURRENT_SOURCE_DIR}/tests/aunit/gnat_test.adc"
        "${CMAKE_CURRENT_SOURCE_DIR}/tests/aunit/src/aunit_runner.adb"
        "${CMAKE_CURRENT_SOURCE_DIR}/tests/aunit/src/aegis_spark_suite.ads"
        "${CMAKE_CURRENT_SOURCE_DIR}/tests/aunit/src/aegis_spark_suite.adb"
        "${CMAKE_CURRENT_SOURCE_DIR}/tests/aunit/src/test_halos_safety_gate.ads"
        "${CMAKE_CURRENT_SOURCE_DIR}/tests/aunit/src/test_halos_safety_gate.adb"
        "${CMAKE_CURRENT_SOURCE_DIR}/tests/aunit/src/test_halos_mock_mmio.ads"
        "${CMAKE_CURRENT_SOURCE_DIR}/tests/aunit/src/test_halos_mock_mmio.adb"
      COMMENT "Building AUnit native test runner via Alire / GPRbuild"
    )

    add_custom_target(aegis_spark_aunit ALL DEPENDS "${AEGIS_SPARK_AUNIT_BINARY}")
    add_dependencies(aegis_spark_aunit aegis_spark_core)
  endif()
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

add_library(
  halos_mailbox
  STATIC
  "${CMAKE_CURRENT_SOURCE_DIR}/src/halos_mailbox.c"
  "${CMAKE_CURRENT_SOURCE_DIR}/src/halos_mailbox.h"
)

target_include_directories(
  halos_mailbox
  PUBLIC "$<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/src>" "$<INSTALL_INTERFACE:include>"
)

target_link_libraries(halos_mailbox PRIVATE project_options project_warnings project_sanitizers)

# -----------------------------------------------------------------------------
# Shared Library Packaging for Python FFI (libaegis_spark.dylib / .so)
# -----------------------------------------------------------------------------
if(Alire_FOUND AND AEGIS_TARGET_MODE STREQUAL "host_sim")
  add_library(
    aegis_spark_shared
    SHARED
    "${CMAKE_CURRENT_SOURCE_DIR}/src/aegis_spark_ffi.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/src/aegis_spark.h"
  )

  target_include_directories(
    aegis_spark_shared
    PUBLIC "$<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/src>" "$<INSTALL_INTERFACE:include>"
  )

  target_link_libraries(
    aegis_spark_shared
    PRIVATE
      "$<LINK_LIBRARY:WHOLE_ARCHIVE,AegisSpark::aegis_spark>"
      "$<LINK_LIBRARY:WHOLE_ARCHIVE,halos_mailbox>"
      "${Alire_GNAT_RUNTIME_LIBRARY}"
      project_options
      project_warnings
  )

  set_target_properties(
    aegis_spark_shared
    PROPERTIES OUTPUT_NAME "aegis_spark" LIBRARY_OUTPUT_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/lib"
  )
endif()

# -----------------------------------------------------------------------------
# Google Test C23/C++23 Suite (Host SIL & Fault Injection)
# -----------------------------------------------------------------------------
if(Alire_FOUND AND AEGIS_TARGET_MODE STREQUAL "host_sim")
  find_package(GTest REQUIRED)

  add_executable(
    aegis_spark_gtest
    "${CMAKE_CURRENT_SOURCE_DIR}/tests/gtest/test_c23_abi.cpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/tests/gtest/test_fault_injection.cpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/tests/gtest/test_mailbox_spsc.cpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/tests/gtest/test_mock_mmio.cpp"
  )

  target_include_directories(aegis_spark_gtest PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/src")

  target_link_libraries(
    aegis_spark_gtest
    PRIVATE
      GTest::gtest_main
      AegisSpark::aegis_spark
      halos_mailbox
      "${Alire_GNAT_RUNTIME_LIBRARY}"
      project_options
      project_warnings
      project_sanitizers
  )
endif()

# -----------------------------------------------------------------------------
# Testing Orchestration (CTest)
# -----------------------------------------------------------------------------
include(CTest)
if(BUILD_TESTING)
  enable_testing()

  if(Alire_FOUND AND AEGIS_TARGET_MODE STREQUAL "host_sim")
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

    add_test(
      NAME aunit_test_suite
      COMMAND "${AEGIS_SPARK_AUNIT_BINARY}"
      WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
    )

    add_test(
      NAME gtest_suite
      COMMAND aegis_spark_gtest
      WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
    )
  endif()

  if(AEGIS_TARGET_MODE STREQUAL "host_sim")
    find_program(PIXI_EXECUTABLE NAMES pixi)
    if(PIXI_EXECUTABLE)
      add_test(
        NAME python_test_suite
        COMMAND "${PIXI_EXECUTABLE}" run test-python
        WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
      )
      set_tests_properties(python_test_suite PROPERTIES ENVIRONMENT "AEGIS_INSIDE_CTEST=1")
    endif()
  endif()

  find_program(QEMU_AARCH64_EXECUTABLE NAMES qemu-system-aarch64)
  find_package(Python3 COMPONENTS Interpreter)
  set(AEGIS_SPARK_QEMU_ELF "${CMAKE_CURRENT_SOURCE_DIR}/bin/aegis_spark_qemu.elf")

  if(Alire_FOUND)
    add_custom_command(
      OUTPUT "${AEGIS_SPARK_QEMU_ELF}"
      COMMAND "${Alire_EXECUTABLE}" --non-interactive exec -- gprbuild -P rts/rts.gpr
      COMMAND "${Alire_EXECUTABLE}" --non-interactive build
      WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/target/qemu-virt-aarch64"
      DEPENDS
        "${CMAKE_CURRENT_SOURCE_DIR}/target/qemu-virt-aarch64/boot.S"
        "${CMAKE_CURRENT_SOURCE_DIR}/target/qemu-virt-aarch64/virt.ld"
        "${CMAKE_CURRENT_SOURCE_DIR}/target/qemu-virt-aarch64/src/aegis_spark_qemu.adb"
        "${CMAKE_CURRENT_SOURCE_DIR}/target/qemu-virt-aarch64/src/qemu_exit.c"
        "${CMAKE_CURRENT_SOURCE_DIR}/target/qemu-virt-aarch64/src/qemu_exit.h"
        "${CMAKE_CURRENT_SOURCE_DIR}/target/qemu-virt-aarch64/src/last_chance.c"
        "${CMAKE_CURRENT_SOURCE_DIR}/target/qemu-virt-aarch64/aegis_spark_qemu.gpr"
        "${CMAKE_CURRENT_SOURCE_DIR}/src/hal/qemu_virt/aegis-hal-registers.ads"
        "${CMAKE_CURRENT_SOURCE_DIR}/src/uart0_mmio.ads"
        "${CMAKE_CURRENT_SOURCE_DIR}/src/uart0_mmio.adb"
        "${CMAKE_CURRENT_SOURCE_DIR}/src/halos_safety_gate.ads"
        "${CMAKE_CURRENT_SOURCE_DIR}/src/halos_safety_gate.adb"
      COMMENT "Building bare-metal ARM64 QEMU ELF image via Alire / GPRbuild"
    )

    add_custom_target(aegis_spark_qemu_image ALL DEPENDS "${AEGIS_SPARK_QEMU_ELF}")
  endif()

  if(Python3_Interpreter_FOUND)
    set(QEMU_SMOKE_ARGS "--elf" "${AEGIS_SPARK_QEMU_ELF}")
    if(NOT QEMU_AARCH64_EXECUTABLE)
      list(APPEND QEMU_SMOKE_ARGS "--allow-skip")
    endif()
    add_test(
      NAME qemu_smoke
      COMMAND
        "${Python3_EXECUTABLE}" "${CMAKE_CURRENT_SOURCE_DIR}/scripts/ci/run_qemu_smoke.py"
        ${QEMU_SMOKE_ARGS}
      WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
    )
    set_tests_properties(qemu_smoke PROPERTIES TIMEOUT 15)
  endif()
endif()
