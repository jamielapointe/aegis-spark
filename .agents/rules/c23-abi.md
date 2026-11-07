# Rule: ISO C23 Systems & Zero-Copy ABI Standards

- **Applies to**: `src/*.c`, `src/*.h`, `kernel/include/**`, `hal/**`, `drivers/**`, `simulation/**`
- **Skill Reference**: `/c-pro`

---

## 1. ISO C23 Standard Compliance

1. **Standard & Compilers**:
   - Compile strictly with `-std=c23` (`__STDC_VERSION__ == 202311L`).
   - Target LLVM Clang 23.1+ (Pixi) and Apple Clang 21.0+ (macOS).
2. **Mandatory Modern C23 Features**:
   - Use `nullptr` for all pointer initialization and null checks (never `NULL` or `0`).
   - Use `static constexpr` for compile-time constants (internal linkage).
   - Use `static_assert` directly (native keyword; do not include `<assert.h>`).
   - Use `<stdckdint.h>` for all arithmetic subject to overflow (`ckd_add`, `ckd_mul`).
   - Use deterministic universal zero-initialization: `struct halos_cmd cmd = {};`.
   - Mark all status-returning functions with `[[nodiscard]]`.
   - Specify explicit fixed underlying types for enums: `enum halos_status : int32_t`.

---

## 2. Real-Time Determinism & Safety Invariants

1. **Zero Dynamic Allocation**:
   - `malloc`, `calloc`, `realloc`, and `free` are strictly forbidden on real-time, sensor, and safety paths
     (`cppcoreguidelines-no-malloc`).
   - Pre-allocate all memory statically during system initialization.
2. **Bounded Stack & WCET**:
   - Recursion is strictly prohibited (`misc-no-recursion`).
   - Variable-Length Arrays (VLAs) and `alloca()` are forbidden (`-Wvla -Werror=vla`).
   - All loops on real-time paths must have statically verifiable bounds.
3. **Lock-Free Concurrency & Cache Alignment**:
   - Align shared atomic structures to cache lines: `alignas(64)`.
   - Use explicit C11/C23 `<stdatomic.h>` memory orderings (`memory_order_acquire`, `memory_order_release`).
   - Never use `volatile` for synchronization (use `volatile` exclusively for MMIO registers).

---

## 3. SPARK Ada ABI Interoperability (`Convention => C`)

1. **Compile-Time Layout Verification**:
   - Every C struct shared with SPARK Ada must verify its size and field offsets:

     ```c
     static_assert(sizeof(struct halos_joint_cmd) == 32, "ABI layout mismatch with SPARK");
     static_assert(offsetof(struct halos_joint_cmd, timestamp_ns) == 0, "Offset mismatch");
     ```

2. **Header Guards & C++ Interoperability**:
   - All headers must use `#pragma once` and include `extern "C"` guards:

     ```c
     #pragma once
     #ifdef __cplusplus
     extern "C" {
     #endif
     ...
     #ifdef __cplusplus
     }
     #endif
     ```

---

## 4. Code Formatting & Static Analysis

1. **Formatting**: Google C++ Style via `.clang-format`:

   ```bash
   pixi run clang-format-check
   ```

2. **Static Analysis**: Zero warnings under `.clang-tidy` (`WarningsAsErrors: "*"`):
   - Enforces CERT C, MISRA C, `misc-include-cleaner`, and `misc-no-recursion`.
