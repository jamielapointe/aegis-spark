/*
 * ARMv8-A Bare-Metal Startup Assembly for QEMU virt
 * Responsibilities:
 *  1. SMP secondary core parking
 *  2. Exception Level (EL2 -> EL1) transition if booted at EL2
 *  3. Enable FP/SIMD coprocessor in CPACR_EL1 (FPEN = 0b11)
 *  4. Stack Pointer initialization
 *  5. .bss segment zeroing
 *  6. Jump to Ada runtime main / scenario runner
 *  7. Clean shutdown via semihosting SYS_EXIT
 */

    .section .text.boot, "ax", %progbits
    .global _start
    .type _start, %function

_start:
    /* 1. Park secondary cores (Aff0 of MPIDR_EL1 != 0) */
    mrs     x0, mpidr_el1
    and     x0, x0, #0xFF
    cbz     x0, .Lcore0_entry

.Lpark_loop:
    wfe
    b       .Lpark_loop

.Lcore0_entry:
    /* 2. Check current Exception Level (CurrentEL[3:2]) */
    mrs     x0, CurrentEL
    lsr     x0, x0, #2
    cmp     x0, #2
    b.ne    .Linit_el1

    /* Drop from EL2 to EL1: set HCR_EL2.RW = 1 (AArch64 EL1) */
    mov     x1, #(1 << 31)
    msr     hcr_el2, x1

    /* Configure SPSR_EL2: Return to EL1h (0b0101) with DAIF masked (0x3c5) */
    mov     x1, #0x3c5
    msr     spsr_el2, x1

    /* Return address for eret into .Linit_el1 */
    adr     x1, .Linit_el1
    msr     elr_el2, x1
    eret

.Linit_el1:
    /* 3. Enable FPU / SIMD coprocessor in CPACR_EL1 (bits [21:20] = 0b11) */
    mov     x0, #(3 << 20)
    msr     cpacr_el1, x0
    isb

    /* 4. Set up stack pointer */
    ldr     x0, =_stack_top
    mov     sp, x0

    /* 5. Zero out .bss segment */
    ldr     x0, =__bss_start
    ldr     x1, =__bss_end

.Lbss_clear:
    cmp     x0, x1
    b.ge    .Lbss_done
    str     xzr, [x0], #8
    b       .Lbss_clear

.Lbss_done:
    /* Memory barrier before jumping to application code */
    dsb     sy
    isb

    /* 6. Branch to GNAT main (which elaborates packages and runs Ada main) */
    bl      main

    /* 7. Clean exit via semihosting */
    mov     w0, #0
    bl      qemu_exit

.Lterminate_hang:
    wfe
    b       .Lterminate_hang

    .size _start, . - _start
