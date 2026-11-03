/*
 * QEMU ARM64 (virt) Bare-Metal Linker Script
 * Memory Base: 0x4000_0000 (DRAM start)
 * Load Origin: 0x4008_0000 (Offset 512KB to avoid QEMU Device Tree Blob collision)
 * UART0: 0x0900_0000 (ARM PrimeCell PL011)
 */

ENTRY(_start)

MEMORY
{
    RAM (rwx) : ORIGIN = 0x40080000, LENGTH = 128M
}

SECTIONS
{
    .text.boot : {
        KEEP(*(.text.boot))
    } > RAM

    .text : ALIGN(8) {
        *(.text .text.*)
    } > RAM

    .rodata : ALIGN(8) {
        *(.rodata .rodata.*)
    } > RAM

    .data : ALIGN(8) {
        *(.data .data.*)
    } > RAM

    .bss (NOLOAD) : ALIGN(16) {
        __bss_start = .;
        *(.bss .bss.*)
        *(COMMON)
        __bss_end = .;
    } > RAM

    .stack (NOLOAD) : ALIGN(16) {
        . += 0x10000; /* 64 KB kernel stack */
        _stack_top = .;
        __stack_top = .;
    } > RAM

    /DISCARD/ : {
        *(.eh_frame)
        *(.eh_frame_hdr)
        *(.note*)
        *(.comment)
    }
}
