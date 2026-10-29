pragma Ada_2022;
with Interfaces;              use Interfaces;
with System;
with System.Storage_Elements; use System.Storage_Elements;

--  Proof-of-Concept: Memory-Mapped I/O (MMIO) Hardware Registers in SPARK Ada 2022
--
--  Demonstrates how safety-critical SPARK Ada 2022 accesses fixed hardware addresses
--  (e.g., UART0 at 0x4000_1000) without raw pointer casts, untyped bitmasks, or
--  unbounded spin loops.
--
--  NOTE ON RUNTIME EXECUTION:
--  Because 16#4000_1000# is a physical peripheral MMIO address, calling Uart0_Init or
--  Uart0_Putc directly inside a host OS process (macOS / Linux user space) would fault
--  on unmapped virtual memory unless run inside a hardware simulator/emulator (such as
--  QEMU or Renode) or on target bare-metal silicon. Using `with Import` on each register
--  prevents package elaboration from touching hardware memory at startup, enabling full
--  compilation (`alr build`) and formal verification (`alr gnatprove`) on any host.
package Uart0_Mmio
   with SPARK_Mode => On
is
   --  1. Strongly-typed peripheral base address & byte offsets
   Uart0_Base_Addr : constant Integer_Address := 16#4000_1000#;

   Dr_Offset   : constant Integer_Address := 16#00#;
   Sr_Offset   : constant Integer_Address := 16#04#;
   Cr_Offset   : constant Integer_Address := 16#08#;
   Baud_Offset : constant Integer_Address := 16#0C#;

   --  Exact-width modular types for reserved hardware bitfields
   type UInt4  is mod 2**4  with Size => 4;
   type UInt24 is mod 2**24 with Size => 24;
   type UInt28 is mod 2**28 with Size => 28;

   --  2. Hardware bitfield records (replaces error-prone C23 bitmask enums)
   --  0x00: Data Register (R/W) — 8-bit payload in bits 0..7, reserved 8..31
   type Uart_Data_Reg is record
      Data     : Unsigned_8 := 0;
      Reserved : UInt24     := 0;
   end record
      with Size        => 32,
           Object_Size => 32,
           Bit_Order   => System.Low_Order_First;

   for Uart_Data_Reg use record
      Data     at 0 range 0 .. 7;
      Reserved at 0 range 8 .. 31;
   end record;

   --  0x04: Status Register (Read-Only)
   type Uart_Status_Reg is record
      Tx_Empty : Boolean := False;
      Rx_Full  : Boolean := False;
      Busy     : Boolean := False;
      Err_Ovr  : Boolean := False;
      Reserved : UInt28  := 0;
   end record
      with Size        => 32,
           Object_Size => 32,
           Bit_Order   => System.Low_Order_First;

   for Uart_Status_Reg use record
      Tx_Empty at 0 range 0 .. 0;
      Rx_Full  at 0 range 1 .. 1;
      Busy     at 0 range 2 .. 2;
      Err_Ovr  at 0 range 3 .. 3;
      Reserved at 0 range 4 .. 31;
   end record;

   --  0x08: Control Register (R/W)
   type Uart_Ctrl_Reg is record
      Enable     : Boolean := False;
      Tx_En      : Boolean := False;
      Rx_En      : Boolean := False;
      Reserved_1 : UInt4   := 0;
      Loopback   : Boolean := False;
      Reserved_2 : UInt24  := 0;
   end record
      with Size        => 32,
           Object_Size => 32,
           Bit_Order   => System.Low_Order_First;

   for Uart_Ctrl_Reg use record
      Enable     at 0 range 0 .. 0;
      Tx_En      at 0 range 1 .. 1;
      Rx_En      at 0 range 2 .. 2;
      Reserved_1 at 0 range 3 .. 6;
      Loopback   at 0 range 7 .. 7;
      Reserved_2 at 0 range 8 .. 31;
   end record;

   --  3. Hardware register overlays with SPARK fine-grained volatility aspects
   pragma Warnings
     (GNATprove, Off,
      "[imprecise-address-specification]",
      Reason => "Disjoint hardware MMIO registers verified against SoC memory map");

   --  DR (0x4000_1000): Writing pushes a byte to the hardware TX FIFO
   DR_Reg : Uart_Data_Reg
      with Volatile,
           Async_Writers    => False,
           Async_Readers    => True,
           Effective_Reads  => False,
           Effective_Writes => True,
           Import,
           Address          => To_Address (Uart0_Base_Addr + Dr_Offset);

   --  SR (0x4000_1004): Hardware updates status flags asynchronously
   SR_Reg : Uart_Status_Reg
      with Volatile,
           Async_Writers    => True,
           Async_Readers    => False,
           Effective_Reads  => False,
           Effective_Writes => False,
           Import,
           Address          => To_Address (Uart0_Base_Addr + Sr_Offset);

   --  CR (0x4000_1008): Consecutive writes (disable then enable) are hardware-effective
   CR_Reg : Uart_Ctrl_Reg
      with Volatile,
           Async_Writers    => False,
           Async_Readers    => True,
           Effective_Reads  => False,
           Effective_Writes => True,
           Import,
           Address          => To_Address (Uart0_Base_Addr + Cr_Offset);

   --  BAUD (0x4000_100C): Baud Rate Divisor register
   BAUD_Reg : Unsigned_32
      with Volatile,
           Async_Writers    => False,
           Async_Readers    => True,
           Effective_Reads  => False,
           Effective_Writes => True,
           Import,
           Address          => To_Address (Uart0_Base_Addr + Baud_Offset);

   pragma Warnings (GNATprove, On, "[imprecise-address-specification]");

   --  4. Driver Subprograms with SPARK Flow & Functional Contracts

   --  Initialize UART0 with a non-zero baud divisor (requires target/emulated MMIO)
   procedure Uart0_Init (Baud_Divisor : Unsigned_32)
      with Global  => (Output => (CR_Reg, BAUD_Reg)),
           Depends => (CR_Reg   => null,
                       BAUD_Reg => Baud_Divisor),
           Pre     => Baud_Divisor > 0,
           Always_Terminates;

   --  Bounded polling limit for deterministic WCET and termination proof
   Max_Tx_Poll_Spins : constant Positive := 10_000;

   --  Safe bounded transmit (guarantees termination even if UART clock fails)
   procedure Uart0_Putc
     (Byte      :     Unsigned_8;
      Timed_Out : out Boolean)
      with Global  => (Input  => SR_Reg,
                       In_Out => DR_Reg),
           Depends => (Timed_Out => SR_Reg,
                       DR_Reg    => (DR_Reg, SR_Reg, Byte)),
           Always_Terminates;

end Uart0_Mmio;
