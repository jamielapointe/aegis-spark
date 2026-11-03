# Rule: Modern CMake 4.4.3+ Build Orchestration Standards

**Applies to**: `CMakeLists.txt`, `CMakePresets.json`, `cmake/*.cmake`  
**Skill Reference**: `/cmake-pro`

---

## 1. Core Principles & Version Requirements

1. **Minimum Version**:
   ```cmake
   cmake_minimum_required(VERSION 4.4.3)
   ```
2. **Target-Based CMake Only**:
   - Global commands (`include_directories`, `link_libraries`, `add_definitions`, `add_compile_options`) are strictly forbidden.
   - Always use target commands:
     - `target_include_directories(<target> <INTERFACE|PUBLIC|PRIVATE> ...)`
     - `target_link_libraries(<target> <INTERFACE|PUBLIC|PRIVATE> ...)`
     - `target_compile_features(<target> <INTERFACE|PUBLIC|PRIVATE> c_std_23)`
     - `target_compile_options(<target> <INTERFACE|PUBLIC|PRIVATE> ...)`

---

## 2. Modular Architecture (`cmake/`)

1. **Clean Root `CMakeLists.txt`**:
   - Keep root CMake declarative.
   - Delegate helper logic to `cmake/`:
     - `cmake/FindAlire.cmake`: Hybrid Alire 2.1+ crate discovery and GPRbuild static library integration.
     - `cmake/CompilerWarnings.cmake`: Strict warning sets per compiler.
     - `cmake/ProjectOptions.cmake`: Output dirs, position-independent code, IPO/LTO, compiler launchers.
     - `cmake/Sanitizers.cmake`: Dynamic ASan, UBSan, TSan configuration.
2. **Register Module Path**:
   ```cmake
   list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake")
   ```

---

## 3. CMakePresets.json (v10+ Schema) Workflows

1. **Sole User Interface**:
   - Agents and CI must invoke CMake exclusively through presets:
     ```bash
     cmake --workflow --preset host-sim-debug
     ```
2. **Standard Presets**:
   - `host-sim-debug`: Host SIL cyclic demo with ASan/UBSan.
   - `host-sim-asan`: Host SIL build with address and undefined behavior sanitizers.
   - `host-release`: Optimized Host SIL build.
3. **Out-of-Source Build Directories**:
   - Build trees reside in `${sourceDir}/build/${presetName}`.
4. **Native Compilation Database**:
   - Always configure `"CMAKE_EXPORT_COMPILE_COMMANDS": "ON"`.
   - Never write compilation databases to the repository root.

---

## 4. Code Formatting & Quality

1. **Gersemi Formatter**:
   - CMake files must be formatted using `gersemi` (indent 4, line length 100).
   - Verify formatting in CI:
     ```bash
     gersemi --check CMakeLists.txt cmake/*.cmake
     ```
2. **Naming Conventions**:
   - Commands: lowercase (`add_library`, `target_link_libraries`).
   - Keywords / Variables: UPPERCASE (`INTERFACE`, `PUBLIC`, `CMAKE_BUILD_TYPE`).
