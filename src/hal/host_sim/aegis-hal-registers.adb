pragma Ada_2022;

package body Aegis.HAL.Registers
   with SPARK_Mode => On
is

   procedure Host_Sim_Set_Status (Status : Uart_Status_Reg) is
   begin
      SR_Reg := Status;
   end Host_Sim_Set_Status;

   procedure Host_Sim_Set_Tx_Empty (Tx_Empty : Boolean) is
      Current : Uart_Status_Reg := SR_Reg;
   begin
      Current.Tx_Empty := Tx_Empty;
      SR_Reg := Current;
   end Host_Sim_Set_Tx_Empty;

   function Host_Sim_Get_Last_Data return Unsigned_8 is
   begin
      return DR_Reg.Data;
   end Host_Sim_Get_Last_Data;

   function Host_Sim_Get_Last_Tx return Character is
   begin
      return Character'Val (DR_Reg.Data);
   end Host_Sim_Get_Last_Tx;

   procedure Host_Sim_Reset is
   begin
      DR_Reg := (Data => 0, Reserved => 0);
      SR_Reg :=
        (Tx_Empty => True,
         Rx_Full  => False,
         Busy     => False,
         Err_Ovr  => False,
         Reserved => 0);
      CR_Reg :=
        (Enable     => False,
         Tx_En      => False,
         Rx_En      => False,
         Reserved_1 => 0,
         Loopback   => False,
         Reserved_2 => 0);
      BAUD_Reg := 0;
   end Host_Sim_Reset;

end Aegis.HAL.Registers;
