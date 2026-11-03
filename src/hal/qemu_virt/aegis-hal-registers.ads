pragma Ada_2022;
with Interfaces;              use Interfaces;
with System;
with System.Storage_Elements; use System.Storage_Elements;

package Aegis.HAL.Registers
   with SPARK_Mode => On
is
   Uart0_Base_Addr : constant Integer_Address := 16#0900_0000#;

   Dr_Offset   : constant Integer_Address := 16#00#;
   Sr_Offset   : constant Integer_Address := 16#04#;
   Cr_Offset   : constant Integer_Address := 16#08#;
   Baud_Offset : constant Integer_Address := 16#0C#;

   type UInt4  is mod 2**4  with Size => 4;
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

   SR_Reg : Uart_Status_Reg
      with Volatile,
           Async_Writers    => True,
           Async_Readers    => False,
           Effective_Reads  => False,
           Effective_Writes => False,
           Import,
           Address          => To_Address (Uart0_Base_Addr + Sr_Offset);

   CR_Reg : Uart_Ctrl_Reg
      with Volatile,
           Async_Writers    => False,
           Async_Readers    => True,
           Effective_Reads  => False,
           Effective_Writes => True,
           Import,
           Address          => To_Address (Uart0_Base_Addr + Cr_Offset);

   BAUD_Reg : Unsigned_32
      with Volatile,
           Async_Writers    => False,
           Async_Readers    => True,
           Effective_Reads  => False,
           Effective_Writes => True,
           Import,
           Address          => To_Address (Uart0_Base_Addr + Baud_Offset);

   pragma Warnings (GNATprove, On, "[imprecise-address-specification]");

end Aegis.HAL.Registers;
