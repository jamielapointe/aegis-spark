# Aegis-SPARK (`aegis-spark`)

[![Continuous Integration][ci-badge]][ci]
[![License: MIT][license-badge]][license]
[![SPARK Ada 2022: Gold Proof][spark-badge]][spark]
[![ISO C23][c23-badge]][c23]
[![C++23][cpp23-badge]][cpp23]
[![Python 3.14][python-badge]][python]
[![CMake 4.4.3+][cmake-badge]][cmake]
[![Alire 2.1+][alire-badge]][alire]
[![Pixi][pixi-badge]][pixi]
[![clang-tidy: CERT C | MISRA][clang-tidy-badge]][clang-tidy]
[![Code style: clang-format (Google)][clang-format-badge]][clang-format]
[![Ruff][ruff-badge]][ruff]
[![mypy: strict][mypy-badge]][mypy]
[![Platforms][platforms-badge]][ci]
[![pre-commit][pre-commit-badge]][pre-commit]
[![Renovate][renovate-badge]][renovate]

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
- **SPARK Ada 2022 MMIO Hardware Register Proof-of-Concept (`src/uart0_mmio.ads`, `src/uart0_mmio.adb`)**:
  - Demonstrates safe Memory-Mapped I/O (MMIO) register access at fixed peripheral addresses (`16#4000_1000#`) using
    record representation clauses (`Size => 32`), `Volatile` / `Import` overlays, fine-grained SPARK volatility aspects
    (`Async_Writers`, `Async_Readers`, `Effective_Reads`, `Effective_Writes`), and bounded polling
    (`Always_Terminates`).
  - Compiled by `gprbuild` and formally proven by `gnatprove` (`--level=4`); runtime execution of MMIO reads/writes
    requires bare-metal silicon or hardware simulation/emulation (e.g., QEMU or Renode).
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

[ci]: https://github.com/jamielapointe/aegis-spark/actions/workflows/ci.yml
[ci-badge]: https://github.com/jamielapointe/aegis-spark/actions/workflows/ci.yml/badge.svg?branch=main
[license]: LICENSE
[license-badge]: https://img.shields.io/github/license/jamielapointe/aegis-spark
[spark]: https://docs.adacore.com/spark2014-docs/html/ug/
[spark-badge]: https://img.shields.io/badge/SPARK%20Ada%202022-Gold%20Proof-02569B?logo=ada&logoColor=white
[c23]: https://en.cppreference.com/w/c/23
[c23-badge]: https://img.shields.io/badge/C-23-A8B9CC?logo=c&logoColor=white
[cpp23]: https://en.cppreference.com/w/cpp/23
[cpp23-badge]: https://img.shields.io/badge/C%2B%2B-23-00599C?logo=c%2B%2B&logoColor=white
[python]: https://docs.python.org/3.14/
[python-badge]: https://img.shields.io/badge/Python-3.14-3776AB?logo=python&logoColor=white
[cmake]: https://cmake.org
[cmake-badge]: https://img.shields.io/badge/CMake-4.4.3%2B-064F8C?logo=cmake&logoColor=white
[alire]: https://alire.ada.dev
[alire-badge]: https://img.shields.io/badge/Alire-2.1%2B-02569B
[pixi]: https://pixi.sh
[pixi-badge]: https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/prefix-dev/pixi/main/assets/badge/v0.json
[clang-tidy]: https://clang.llvm.org/extra/clang-tidy/
[clang-tidy-badge]: https://img.shields.io/badge/clang--tidy-CERT%20C%20%7C%20MISRA-262D3A?logo=llvm&logoColor=white
[clang-format]: https://clang.llvm.org/docs/ClangFormat.html
[clang-format-badge]: https://img.shields.io/badge/clang--format-Google-262D3A?logo=llvm&logoColor=white
[ruff]: https://github.com/astral-sh/ruff
[ruff-badge]: https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/astral-sh/ruff/main/assets/badge/v2.json
[mypy]: https://mypy-lang.org
[mypy-badge]: https://img.shields.io/badge/mypy-strict-2A6DB2?logo=python&logoColor=white
[platforms-badge]: https://img.shields.io/badge/platforms-linux--64%20%7C%20linux--aarch64%20%7C%20osx--arm64%20%7C%20qemu--arm64-lightgrey
[pre-commit]: https://github.com/pre-commit/pre-commit
[pre-commit-badge]: https://img.shields.io/badge/pre--commit-enabled-brightgreen?logo=pre-commit
[renovate]: https://docs.renovatebot.com/
[renovate-badge]: https://img.shields.io/badge/renovate-enabled-brightgreen?logo=renovate
