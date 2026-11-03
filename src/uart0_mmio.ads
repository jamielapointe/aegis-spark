pragma Ada_2022;
with Interfaces; use Interfaces;
with Aegis.HAL.Registers;

--  Proof-of-Concept: Memory-Mapped I/O (MMIO) Hardware Registers in SPARK Ada 2022
--
--  Demonstrates how safety-critical SPARK Ada 2022 accesses hardware registers
--  through the Aegis.HAL.Registers abstraction without raw pointer casts,
--  untyped bitmasks, or unbounded spin loops.
package Uart0_Mmio
   with SPARK_Mode => On
is
   --  Exact-width modular types for reserved hardware bitfields
   subtype UInt4  is Aegis.HAL.Registers.UInt4;
   subtype UInt24 is Aegis.HAL.Registers.UInt24;
   subtype UInt28 is Aegis.HAL.Registers.UInt28;

   --  Hardware bitfield records
   subtype Uart_Data_Reg   is Aegis.HAL.Registers.Uart_Data_Reg;
   subtype Uart_Status_Reg is Aegis.HAL.Registers.Uart_Status_Reg;
   subtype Uart_Ctrl_Reg   is Aegis.HAL.Registers.Uart_Ctrl_Reg;

   --  Hardware register overlays re-exported from scenario HAL
   DR_Reg   : Uart_Data_Reg   renames Aegis.HAL.Registers.DR_Reg;
   SR_Reg   : Uart_Status_Reg renames Aegis.HAL.Registers.SR_Reg;
   CR_Reg   : Uart_Ctrl_Reg   renames Aegis.HAL.Registers.CR_Reg;
   BAUD_Reg : Unsigned_32     renames Aegis.HAL.Registers.BAUD_Reg;

   --  Driver Subprograms with SPARK Flow & Functional Contracts

   --  Initialize UART0 with a non-zero baud divisor
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
