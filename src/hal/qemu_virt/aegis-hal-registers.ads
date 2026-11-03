pragma Ada_2022;
with Interfaces;              use Interfaces;
with System;
with System.Storage_Elements; use System.Storage_Elements;

package Aegis.HAL.Registers
   with SPARK_Mode => On
is
   Uart0_Base_Addr : constant Integer_Address := 16#0900_0000#;

   Dr_Offset    : constant Integer_Address := 16#000#;
   Fr_Offset    : constant Integer_Address := 16#018#;
   Sr_Offset    : constant Integer_Address := 16#018#;
   Ibrd_Offset  : constant Integer_Address := 16#024#;
   Fbrd_Offset  : constant Integer_Address := 16#028#;
   Lcr_H_Offset : constant Integer_Address := 16#02C#;
   Cr_Offset    : constant Integer_Address := 16#030#;
   Baud_Offset  : constant Integer_Address := 16#024#;

   type UInt2  is mod 2**2  with Size => 2;
   type UInt3  is mod 2**3  with Size => 3;
   type UInt4  is mod 2**4  with Size => 4;
   type UInt6  is mod 2**6  with Size => 6;
   type UInt22 is mod 2**22 with Size => 22;
   type UInt24 is mod 2**24 with Size => 24;
   type UInt28 is mod 2**28 with Size => 28;

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

   type Uart_Status_Reg is record
      Reserved_Low  : UInt3   := 0;      --  bits 0..2 (CTS, DSR, DCD)
      Busy          : Boolean := False;  --  bit 3 (BUSY)
      Rx_Empty      : Boolean := True;   --  bit 4 (RXFE)
      Tx_Full       : Boolean := False;  --  bit 5 (TXFF)
      Rx_Full       : Boolean := False;  --  bit 6 (RXFF)
      Tx_Empty      : Boolean := True;   --  bit 7 (TXFE)
      Reserved_High : UInt24  := 0;      --  bits 8..31
   end record
      with Size        => 32,
           Object_Size => 32,
           Bit_Order   => System.Low_Order_First;

   for Uart_Status_Reg use record
      Reserved_Low  at 0 range 0 .. 2;
      Busy          at 0 range 3 .. 3;
      Rx_Empty      at 0 range 4 .. 4;
      Tx_Full       at 0 range 5 .. 5;
      Rx_Full       at 0 range 6 .. 6;
      Tx_Empty      at 0 range 7 .. 7;
      Reserved_High at 0 range 8 .. 31;
   end record;

   type Uart_Ctrl_Reg is record
      Enable     : Boolean := False;  --  bit 0 (UARTEN)
      Reserved_1 : UInt6   := 0;      --  bits 1..6
      Loopback   : Boolean := False;  --  bit 7 (LBE)
      Tx_En      : Boolean := False;  --  bit 8 (TXE)
      Rx_En      : Boolean := False;  --  bit 9 (RXE)
      Reserved_2 : UInt22  := 0;      --  bits 10..31
   end record
      with Size        => 32,
           Object_Size => 32,
           Bit_Order   => System.Low_Order_First;

   for Uart_Ctrl_Reg use record
      Enable     at 0 range 0 .. 0;
      Reserved_1 at 0 range 1 .. 6;
      Loopback   at 0 range 7 .. 7;
      Tx_En      at 0 range 8 .. 8;
      Rx_En      at 0 range 9 .. 9;
      Reserved_2 at 0 range 10 .. 31;
   end record;

   type Uart_Line_Ctrl_Reg is record
      Brk      : Boolean := False;  --  bit 0
      Pen      : Boolean := False;  --  bit 1
      Eps      : Boolean := False;  --  bit 2
      Stp2     : Boolean := False;  --  bit 3
      Fen      : Boolean := True;   --  bit 4 (FIFO enable)
      Wlen     : UInt2   := 3;      --  bits 5..6 (0b11 = 8 bits)
      Sps      : Boolean := False;  --  bit 7
      Reserved : UInt24  := 0;      --  bits 8..31
   end record
      with Size        => 32,
           Object_Size => 32,
           Bit_Order   => System.Low_Order_First;

   for Uart_Line_Ctrl_Reg use record
      Brk      at 0 range 0 .. 0;
      Pen      at 0 range 1 .. 1;
      Eps      at 0 range 2 .. 2;
      Stp2     at 0 range 3 .. 3;
      Fen      at 0 range 4 .. 4;
      Wlen     at 0 range 5 .. 6;
      Sps      at 0 range 7 .. 7;
      Reserved at 0 range 8 .. 31;
   end record;

   pragma Warnings
     (GNATprove, Off,
      "[imprecise-address-specification]",
      Reason => "Disjoint hardware MMIO registers verified against SoC memory map");

   DR_Reg : Uart_Data_Reg
      with Volatile,
           Async_Writers    => False,
           Async_Readers    => True,
           Effective_Reads  => False,
           Effective_Writes => True,
           Import,
           Address          => To_Address (Uart0_Base_Addr + Dr_Offset);

   FR_Reg : Uart_Status_Reg
      with Volatile,
           Async_Writers    => True,
           Async_Readers    => False,
           Effective_Reads  => False,
           Effective_Writes => False,
           Import,
           Address          => To_Address (Uart0_Base_Addr + Fr_Offset);

   SR_Reg : Uart_Status_Reg renames FR_Reg;

   IBRD_Reg : Unsigned_32
      with Volatile,
           Async_Writers    => False,
           Async_Readers    => True,
           Effective_Reads  => False,
           Effective_Writes => True,
           Import,
           Address          => To_Address (Uart0_Base_Addr + Ibrd_Offset);

   FBRD_Reg : Unsigned_32
      with Volatile,
           Async_Writers    => False,
           Async_Readers    => True,
           Effective_Reads  => False,
           Effective_Writes => True,
           Import,
           Address          => To_Address (Uart0_Base_Addr + Fbrd_Offset);

   LCR_H_Reg : Uart_Line_Ctrl_Reg
      with Volatile,
           Async_Writers    => False,
           Async_Readers    => True,
           Effective_Reads  => False,
           Effective_Writes => True,
           Import,
           Address          => To_Address (Uart0_Base_Addr + Lcr_H_Offset);

   CR_Reg : Uart_Ctrl_Reg
      with Volatile,
           Async_Writers    => False,
           Async_Readers    => True,
           Effective_Reads  => False,
           Effective_Writes => True,
           Import,
           Address          => To_Address (Uart0_Base_Addr + Cr_Offset);

   BAUD_Reg : Unsigned_32 renames IBRD_Reg;

   pragma Warnings (GNATprove, On, "[imprecise-address-specification]");

end Aegis.HAL.Registers;
