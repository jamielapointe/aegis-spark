# Aegis-SPARK — Antigravity Project Rules & Workflows

## 1. Core Architecture & Purpose

`aegis-spark` (`aegis_spark` Alire crate) is a formally verified, deterministic, zero-allocation robotics safety kernel
and command interceptor following the **NVIDIA Halos** / **IGX Thor Functional Safety Island (FSI)** architecture:

1. **Formally Verified SPARK Ada 2022 Core (`src/*.ads`, `src/*.adb`)**:
   - Proves **Absence of Run-Time Errors (AoRTE — Silver tier)** and **Functional Safety Invariants (Gold tier)** using
     `gnatprove` (`cvc5`, `z3`, `altergo`).
   - Enforces `pragma Profile (Jorvik)`, `pragma Partition_Elaboration_Policy (Sequential)`, and strict zero-heap /
     no-secondary-stack / no-recursion restrictions via `gnat.adc`.
2. **Deterministic ISO C23 Systems Boundary (`src/*.c`, `src/*.h`)**:
   - Zero-copy C23 ABI interoperability (`Convention => C`) with compile-time layout assertions (`static_assert`),
     `[[nodiscard]]` status codes, and strict CERT C / MISRA C static analysis (`clang-tidy`).
   - Because `gprbuild` compiles C code with `gnat_native` GCC 16.1 for Ada ABI compatibility and lacks a built-in
     `CMAKE_C_CLANG_TIDY` attribute, `scripts/ci/run_clang_tidy.py` is wired directly into `alire.toml` (`post-build`),
     `pixi` tasks, and `.pre-commit-config.yaml`.
3. **Python 3.14.7 CI, Tooling & Test Orchestration (`scripts/ci/`, `tests/python/`)**:
   - Managed via `pixi` (`pyproject.toml`) across macOS (`osx-arm64`) and Linux (`linux-64`, `linux-aarch64`).

## 2. Language, Build & Environment Rules

- **Cross-Platform Portability**:
  - Never commit `alire/` (including `alire/alire.lock`), `config/`, `obj/`, or `bin/`. `alire/alire.lock` pins
    host-specific binary tarballs (e.g., `aarch64-darwin` vs. `x86_64-linux` vs. `aarch64-linux`).
  - Never hardcode OS-specific paths (`/Users/...` or `/home/...`) inside `.gpr`, `alire.toml`, or scripts.
- **SPARK Ada 2022 (`/spark-pro`)**:
  - Every `.ads` and `.adb` file must begin with `pragma Ada_2022;` and declare an explicit `SPARK_Mode`.
  - Package specifications (`.ads`) must always use `SPARK_Mode => On`. Isolate `SPARK_Mode => Off` strictly to thin FFI
    package bodies (`.adb`).
  - Never silence failed proofs with unjustified `pragma Annotate (GNATprove, ...)`.
- **ISO C23 (`/c-pro`)**:
  - Enforce `-std=c23 -Wall -Wextra -Wpedantic -Werror` and `.clang-tidy` (`WarningsAsErrors: "*"`) with Google
    formatting (`.clang-format`).
- **Python 3.14.7 (`/python-pro`)**:
  - Use native PEP 649 deferred annotations (never `from __future__ import annotations`).
  - Follow Google Python Style Guide (`ruff` with single quotes and `convention = "google"`, `mypy --strict`).
  - Zero in-code suppressions (`# noqa`, `# ruff: ignore`, `# type: ignore`).

## 3. Standard Verification Workflow

Before committing any change, verify all local CI gates pass with exit code `0`:

```bash
pixi run pre-commit
pixi run ci
```
