pragma Ada_2022;
with Interfaces; use Interfaces;
with System;

package Aegis.HAL.Registers
   with SPARK_Mode => On
is
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
      Tx_Empty : Boolean := True;  --  Default ready for transmit in host simulation
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

   --  Aligned in-RAM mock registers (Host SIL)
   DR_Reg : Uart_Data_Reg := (Data => 0, Reserved => 0)
      with Volatile,
           Async_Writers    => False,
           Async_Readers    => True,
           Effective_Reads  => False,
           Effective_Writes => True,
           Export,
           Convention       => C,
           External_Name    => "aegis_mock_uart0_dr";

   SR_Reg : Uart_Status_Reg :=
     (Tx_Empty => True,
      Rx_Full  => False,
      Busy     => False,
      Err_Ovr  => False,
      Reserved => 0)
      with Volatile,
           Async_Writers    => True,
           Async_Readers    => False,
           Effective_Reads  => False,
           Effective_Writes => False,
           Export,
           Convention       => C,
           External_Name    => "aegis_mock_uart0_sr";

   FR_Reg : Uart_Status_Reg renames SR_Reg;

   CR_Reg : Uart_Ctrl_Reg :=
     (Enable     => False,
      Tx_En      => False,
      Rx_En      => False,
      Reserved_1 => 0,
      Loopback   => False,
      Reserved_2 => 0)
      with Volatile,
           Async_Writers    => False,
           Async_Readers    => True,
           Effective_Reads  => False,
           Effective_Writes => True,
           Export,
           Convention       => C,
           External_Name    => "aegis_mock_uart0_cr";

   BAUD_Reg : Unsigned_32 := 0
      with Volatile,
           Async_Writers    => False,
           Async_Readers    => True,
           Effective_Reads  => False,
           Effective_Writes => True,
           Export,
           Convention       => C,
           External_Name    => "aegis_mock_uart0_baud";

   --  Host Simulation Ingress/Egress APIs for AUnit, GTest, and Python
   procedure Host_Sim_Set_Status (Status : Uart_Status_Reg)
      with Global  => (Output => SR_Reg),
           Depends => (SR_Reg => Status),
           Always_Terminates;

   procedure Host_Sim_Set_Tx_Empty (Tx_Empty : Boolean)
      with Global  => (In_Out => SR_Reg),
           Depends => (SR_Reg => (SR_Reg, Tx_Empty)),
           Always_Terminates;

   function Host_Sim_Get_Last_Data return Unsigned_8
      with Global  => (Input => DR_Reg),
           Depends => (Host_Sim_Get_Last_Data'Result => DR_Reg);

   function Host_Sim_Get_Last_Tx return Character
      with Global  => (Input => DR_Reg),
           Depends => (Host_Sim_Get_Last_Tx'Result => DR_Reg);

   procedure Host_Sim_Reset
      with Global  => (Output => (DR_Reg, SR_Reg, CR_Reg, BAUD_Reg)),
           Depends => ((DR_Reg, SR_Reg, CR_Reg, BAUD_Reg) => null),
           Always_Terminates;

end Aegis.HAL.Registers;
