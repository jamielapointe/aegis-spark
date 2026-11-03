# Rule: SPARK Ada 2022 Formal Verification & Safety Standards

**Applies to**: `src/*.ads`, `src/*.adb`, `kernel/**`, `hal/**`, `drivers/**`, `config/*.gpr`, `gnat.adc`  
**Skill Reference**: `/spark-pro`

---

## 1. Language Standard & Pragma Rules

1. **Ada 2022 Enforced**: Every `.ads` and `.adb` must begin with:
   ```ada
   pragma Ada_2022;
   ```
2. **Explicit SPARK Mode**:
   - Every package specification (`.ads`) must declare `with SPARK_Mode => On;` or `pragma SPARK_Mode (On);`.
   - `SPARK_Mode => Off` is permitted **only** in thin FFI package bodies (`.adb`) interfacing directly with C23 functions or raw assembly.
3. **No Unchecked Conversions Without Rationale**:
   - `Unchecked_Conversion` is forbidden on verified safety types.
   - Any raw memory overlay must be isolated behind an explicit representation clause and justified with a safety comment.

---

## 2. Formal Verification Tiers (`gnatprove` 16.1+)

All code must pass `gnatprove` with zero unproved VCs and zero warnings:

```bash
alr gnatprove --mode=all --level=4 --prover=cvc5,z3,altergo --warnings=error
```

1. **Silver Baseline (AoRTE)**:
   - Prove Absence of Run-Time Errors across 100% of units: no buffer overflows, no divide-by-zero, no numeric overflow, no uninitialized reads.
2. **Gold Tier (Functional Safety Invariants)**:
   - Enforce complete contracts (`Pre`, `Post`, `Contract_Cases`, `Type_Invariant`, `Always_Terminates`).
   - Safety monitors must prove fail-safe latching:
     ```ada
     Contract_Cases =>
       (State = State_Fault_Estop =>
          State = State_Fault_Estop and
          (for all J in Dof_Index => Safe_Torque (J) = 0.0),
        others => ...);
     ```
3. **Loop Verification**:
   - Every loop modifying state or performing search must declare `pragma Loop_Invariant` and `pragma Loop_Variant (Increases/Decreases => ...)`.
4. **Annotation Discipline**:
   - Never silence a proof failure with `pragma Annotate (GNATprove, False_Positive/Intentional, ...)`.
   - Any allowed hardware annotation must provide a 4th argument explaining the physical safety rationale.

---

## 3. Deterministic Memory & Concurrency (`gnat.adc`)

1. **Jorvik Profile**:
   ```ada
   pragma Profile (Jorvik);
   pragma Partition_Elaboration_Policy (Sequential);
   ```
2. **Zero Heap Allocation**:
   ```ada
   pragma Restrictions (No_Allocators);
   pragma Restrictions (No_Implicit_Heap_Allocations);
   pragma Restrictions (No_Secondary_Stack);
   pragma Restrictions (No_Recursion);
   ```
3. **Bounded Types on Hot Paths**:
   - Functions must not return unconstrained types (`String`, `array (Positive range <>)`).
   - Use fixed-size constrained arrays or `out` parameters.

---

## 4. Hardware MMIO & Volatile Modeling

1. **Record Representation Clauses**:
   - Map registers using exact bit-level representation clauses (`at 0 range 0 .. 31;`).
2. **Fine-Grained SPARK Volatility**:
   - Status/Sensor registers: `Async_Writers => True`
   - Command/TX registers: `Async_Readers => True`
   - Read-side-effect FIFOs: `Effective_Reads => True`
   - Action-triggering writes: `Effective_Writes => True`

---

## 5. C23 ABI Boundary Ingress

- External C callers are untrusted by `gnatprove`.
- Every subprogram with `Convention => C` must validate all input fields with `'Valid` before delegating to the Gold-proved SPARK kernel:
  ```ada
  if not Raw_Cmd.Timestamp_Ns'Valid or not Raw_Cmd.Torque'Valid then
     Status := HALOS_ERR_NON_FINITE_INPUT;
     return;
  end if;
  ```
