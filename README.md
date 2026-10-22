# Aegis-SPARK (`aegis-spark`)

Formally verified **SPARK Ada 2022** and **ISO C23** real-time robotics safety kernel and command interceptor, modeled
on the **NVIDIA Halos** / **IGX Thor Functional Safety Island (FSI)** architecture, with **Python 3.14.7** (`pixi`) CI
and verification orchestration.

## Architecture Overview

- **Gold-Proved SPARK Ada 2022 Safety Gate (`src/halos_safety_gate.ads`, `src/halos_safety_gate.adb`)**:
  - Mathematically proves **Absence of Run-Time Errors (Silver AoRTE)** and **Functional Correctness (Gold contracts)**
    across all inputs using `gnatprove` (`cvc5`, `z3`, `altergo`).
  - Guarantees deterministic transitions to `State_Fault_Estop` and zeroed actuator torques across all 6 DOFs whenever
    an unarmed state, stale watchdog heartbeat ($> 5\text{ ms}$), clock rollback, non-finite IEEE-754 float (`NaN` /
    `Inf`), or torque envelope violation occurs.
  - Enforces `pragma Profile (Jorvik)` and zero dynamic heap/secondary-stack allocation (`gnat.adc`).
- **ISO C23 ABI Interop & Logging Boundary (`src/halos_c_logger.h`, `src/halos_c_logger.c`, `src/halos_logger.ads`)**:
  - Zero-copy C23 ABI interoperability (`Convention => C`) verified by compile-time `static_assert` layout checks and
    strict CERT C / MISRA C static analysis (`clang-tidy`).
  - Automatically runs `clang-tidy` on every `alr build` via Alire's `post-build` action hook
    (`scripts/ci/run_clang_tidy.py`), as well as via `pixi` tasks and `pre-commit`.
- **Cross-Platform Multi-Language Workflow (`pyproject.toml`, `alire.toml`, `aegis_spark.gpr`)**:
  - Portable across **Apple macOS (`osx-arm64`)**, **Ubuntu Linux (`x86_64`)**,
    **Embedded Linux (`aarch64` / Raspberry Pi 5)**, and **RISC-V (`riscv64` RVA23)**.

## Quick Start

### 1. Install Pixi Environment & Select Alire Toolchain

```bash
pixi install
alr toolchain --select gnat_native gprbuild
```

### 2. Build, Prove, and Run via Pixi Tasks

```bash
# Build Ada 2022 + C23 validation binary (automatically runs clang-tidy post-build)
pixi run build

# Run SPARK formal verification (Silver AoRTE + Gold Functional Contracts)
pixi run prove
pixi run prove-ci

# Run compiled safety kernel verification suite
pixi run run

# Run full test suite (SPARK proofs + Ada/C binary + Python pytest suite)
pixi run test

# Run complete CI & pre-commit quality gates
pixi run pre-commit
pixi run ci
```

## Repository Structure

```text
aegis-spark/
├── alire.toml                  # Alire crate manifest (with post-build clang-tidy hook)
├── aegis_spark.gpr             # GPRbuild multi-language (Ada 2022 + C23) project file
├── gnat.adc                    # High-integrity SPARK/Jorvik restriction pragmas
├── pyproject.toml              # Unified Pixi, Ruff, Mypy, Pytest, Coverage & Rumdl config
├── .clangd                     # clangd C23 language server configuration (synced with GPR)
├── .clang-format               # Google C/C++ formatting configuration
├── .clang-tidy                 # CERT C / MISRA C / Real-Time static analysis configuration
├── .pre-commit-config.yaml     # Multi-language pre-commit hooks
├── src/                        # SPARK Ada 2022 (.ads/.adb) and ISO C23 (.c/.h) sources
├── scripts/ci/                 # CI gates (clang-tidy, clang-format, SPARK contracts, hygiene)
└── tests/python/               # Pytest integration & CI verification suite
```
