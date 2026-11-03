# Aegis-SPARK — Agent Invariants & Architecture Guardrails

This document establishes the non-negotiable architectural invariants, safety standards, and development protocols for
all autonomous and human contributors to `aegis-spark`.

---

## 1. System Architecture: NVIDIA Halos on IGX Thor FSI Pattern

`aegis-spark` models the fundamental safety split of the **NVIDIA Halos** architecture on the **NVIDIA IGX Thor** SoC:

1. **Untrusted AI Compute Domain (CCPLEX + Blackwell GPU)**:
   - High-rate trajectory planners, foundation models (Isaac GR00T, VLA policies), and agent frameworks (Python 3.14,
     Antigravity SDK, ADK, C++23).
   - Cannot be formally certified to ASIL-D / SIL-3.
2. **Deterministic Safety Supervisor Domain (Functional Safety Island / FSI)**:
   - Physically isolated lockstep cores executing a **Gold-proved SPARK Ada 2022** safety kernel (`Halos_Safety_Gate`,
     `Halos_Watchdog`, `Halos_HSM`).
   - Enforces zero heap allocation, bounded execution loops, monotonic watchdogs, and fail-safe latching
     (`State_Fault_Estop`).
3. **Dual-Tier Hardware Abstraction Layer (HAL)**:
   - **Tier 1 (Host SIL)**: Sub-second native simulator using mock RAM registers on macOS (`osx-arm64`) and Linux
     (`linux-64`).
   - **Tier 2 (Target PIL)**: Bare-metal QEMU ARM64 (`-M virt`, PL011 UART @ `16#0900_0000#`) verifying real MMIO and
     boot determinism.

---

## 2. Non-Negotiable Core Invariants

### 2.1 SPARK Ada 2022 (`/spark-pro`)

- **Ada Standard**: Explicit `pragma Ada_2022;` on all Ada units.
- **Assurance Tiers**:
  - **Silver Baseline**: 100% Absence of Run-Time Errors (AoRTE) mathematically proved across all units.
  - **Gold Safety Gates**: 100% Functional safety contracts (`Pre`, `Post`, `Contract_Cases`, `Always_Terminates`)
    mathematically proved.
- **SPARK Mode**: Package specifications (`.ads`) must declare `SPARK_Mode => On`. `SPARK_Mode => Off` is strictly
  limited to thin FFI bodies (`.adb`).
- **Memory & Concurrency Model**: `pragma Profile (Jorvik)` and zero dynamic heap allocation via `gnat.adc`.
- See detailed rules: `.agents/rules/spark-safety.md`.

### 2.2 ISO C23 Leaf & ABI Boundary (`/c-pro`)

- **C Standard**: Pure ISO C23 (`-std=c23`, `__STDC_VERSION__ == 202311L`) compiled with LLVM Clang 23.1+ (Pixi) and
  Apple Clang 21.0+.
- **Language Modernisms**: `nullptr`, `static constexpr`, `static_assert`, `<stdckdint.h>`, `[[nodiscard]]`, `= {}` zero
  initialization.
- **Zero Heap**: `malloc`, `calloc`, and `free` are strictly forbidden on real-time and safety paths.
- **ABI Parity**: Every shared struct/enum must have compile-time layout parity verified via
  `static_assert(sizeof(...) == ...)` and `static_assert(alignof(...) == ...)`.
- See detailed rules: `.agents/rules/c23-abi.md`.

### 2.3 Modern CMake 4.4.3+ Build Orchestration (`/cmake-pro`)

- **Target-Based CMake**: Exclusively use target commands (`target_include_directories`, `target_link_libraries`,
  `target_compile_features`). Global commands (`include_directories`, `add_definitions`) are prohibited.
- **Presets Interface**: All configure, build, and test operations run through `CMakePresets.json` (schema v10+):
  `cmake --workflow --preset host-sim-debug`.
- **Compilation Database**: Exported natively out-of-source (`CMAKE_EXPORT_COMPILE_COMMANDS=ON`).
- **Code Style**: CMake files must be formatted with `gersemi` (indent 2, line length 100).
- See detailed rules: `.agents/rules/cmake.md`.

---

## 3. Collaboration & Lifecycle Protocol (`/github-flow-lifecycle`)

All modifications must follow the GitHub Flow lifecycle:

1. **GitHub Issue**: Every task must be linked to an open GitHub issue.
2. **Branch Isolation**: Work on a dedicated branch named `feat/<issue>-<slug>` or `fix/<issue>-<slug>`.
3. **Local Pre-Commit Verification**: Run `pixi run pre-commit` and `pixi run ci` locally before pushing.
4. **Pull Request**: Open a PR referencing the issue (`Closes #<issue>`) with reproducible verification logs.
5. **Remote CI Gate**: Remote GitHub Actions must pass on `ubuntu-latest`, `ubuntu-24.04-arm`, and `macos-latest` before
   merge.

---

## 4. Workspace Hygiene & Security Guardrails

- **Zero Hardcoded Paths**: Never commit machine-specific paths (`/Users/...`, `/Library/Developer/...`, `/home/...`).
- **Deletion Safety**: Never create files or folders named `~` or containing `~` or `$`. Automated scripts must not run
  unconstrained `rm -rf`.
- **Secret Hygiene**: Zero hardcoded credentials, tokens, or Google API keys (`AIza...`).
- **Agent Workspaces**: `.agents/teamwork/` is reserved for ephemeral agent coordination metadata and is gitignored.
  Permanent rules live in `AGENTS.md` and `.agents/rules/`.
