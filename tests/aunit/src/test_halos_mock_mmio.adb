with AUnit.Assertions; use AUnit.Assertions;
with Aegis.HAL.Registers;
with Interfaces;        use Interfaces;
with Uart0_Mmio;

package body Test_Halos_Mock_Mmio is

   overriding procedure Register_Tests (T : in out Test_Case) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T, Test_Mock_Mmio_Init'Access,
         "Test Mock MMIO UART Initialization");
      Register_Routine
        (T, Test_Mock_Mmio_Putc_Nominal'Access,
         "Test Mock MMIO Nominal Byte Transmit");
      Register_Routine
        (T, Test_Mock_Mmio_Tx_Empty_Stall'Access,
         "Test Mock MMIO TX Empty Stall Timeout");
      Register_Routine
        (T, Test_Mock_Mmio_Reset'Access,
         "Test Mock MMIO Register Reset");
      Register_Routine
        (T, Test_High_Volume_Throughput'Access,
         "Test High Volume Mock MMIO (No SIGSEGV)");
   end Register_Tests;

   overriding function Name (T : Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Halos Mock MMIO Registers Unit Tests");
   end Name;

   procedure Test_Mock_Mmio_Init
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Aegis.HAL.Registers.Host_Sim_Reset;
      Uart0_Mmio.Uart0_Init (Baud_Divisor => 115_200);

      Assert (Uart0_Mmio.CR_Reg.Enable,
              "CR_Reg.Enable should be True after init");
      Assert (Uart0_Mmio.CR_Reg.Tx_En,
              "CR_Reg.Tx_En should be True after init");
      Assert (Uart0_Mmio.CR_Reg.Rx_En,
              "CR_Reg.Rx_En should be True after init");
      Assert (Uart0_Mmio.BAUD_Reg = 115_200,
              "BAUD_Reg should match configured divisor");
   end Test_Mock_Mmio_Init;

   procedure Test_Mock_Mmio_Putc_Nominal
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Timed_Out : Boolean;
   begin
      Aegis.HAL.Registers.Host_Sim_Reset;
      Uart0_Mmio.Uart0_Init (Baud_Divisor => 115_200);

      Uart0_Mmio.Uart0_Putc (Byte => Character'Pos ('Z'),
                             Timed_Out => Timed_Out);

      Assert (not Timed_Out,
              "Transmit should not time out under nominal mock status");
      Assert (Aegis.HAL.Registers.Host_Sim_Get_Last_Data = Character'Pos ('Z'),
              "DR_Reg should hold 'Z' byte");
      Assert (Aegis.HAL.Registers.Host_Sim_Get_Last_Tx = 'Z',
              "Host_Sim_Get_Last_Tx should return 'Z'");
   end Test_Mock_Mmio_Putc_Nominal;

   procedure Test_Mock_Mmio_Tx_Empty_Stall
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Timed_Out : Boolean;
   begin
      Aegis.HAL.Registers.Host_Sim_Reset;
      Uart0_Mmio.Uart0_Init (Baud_Divisor => 115_200);

      --  Inject hardware stall: simulate FIFO full / TX not empty
      Aegis.HAL.Registers.Host_Sim_Set_Tx_Empty (False);

      Uart0_Mmio.Uart0_Putc (Byte => Character'Pos ('!'),
                             Timed_Out => Timed_Out);

      Assert (Timed_Out,
              "Transmit should time out when Tx_Empty is held False");
   end Test_Mock_Mmio_Tx_Empty_Stall;

   procedure Test_Mock_Mmio_Reset
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Uart0_Mmio.Uart0_Init (Baud_Divisor => 9600);
      Aegis.HAL.Registers.Host_Sim_Reset;

      Assert (not Uart0_Mmio.CR_Reg.Enable,
              "CR_Reg should be disabled after reset");
      Assert (Uart0_Mmio.SR_Reg.Tx_Empty,
              "SR_Reg.Tx_Empty should be True after reset");
      Assert (Uart0_Mmio.BAUD_Reg = 0,
              "BAUD_Reg should be zeroed after reset");
      Assert (Aegis.HAL.Registers.Host_Sim_Get_Last_Data = 0,
              "DR_Reg should be 0 after reset");
   end Test_Mock_Mmio_Reset;

   procedure Test_High_Volume_Throughput
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Timed_Out : Boolean;
   begin
      Aegis.HAL.Registers.Host_Sim_Reset;
      Uart0_Mmio.Uart0_Init (Baud_Divisor => 115_200);

      for I in 1 .. 10_000 loop
         Uart0_Mmio.Uart0_Putc (Byte => Unsigned_8 (I mod 256),
                                Timed_Out => Timed_Out);
         Assert (not Timed_Out, "High-volume transmit must not time out");
      end loop;

      Assert (Aegis.HAL.Registers.Host_Sim_Get_Last_Data =
                Unsigned_8 (10_000 mod 256),
              "Last transmitted byte should match 10000 mod 256");
   end Test_High_Volume_Throughput;

end Test_Halos_Mock_Mmio;
