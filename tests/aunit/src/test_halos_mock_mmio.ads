with AUnit.Test_Cases;

package Test_Halos_Mock_Mmio is

   type Test_Case is new AUnit.Test_Cases.Test_Case with null record;

   overriding procedure Register_Tests (T : in out Test_Case);
   overriding function Name (T : Test_Case) return AUnit.Message_String;

   procedure Test_Mock_Mmio_Init
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   procedure Test_Mock_Mmio_Putc_Nominal
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   procedure Test_Mock_Mmio_Puts_Nominal
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   procedure Test_Mock_Mmio_Tx_Empty_Stall
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   procedure Test_Mock_Mmio_Reset
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   procedure Test_High_Volume_Throughput
     (T : in out AUnit.Test_Cases.Test_Case'Class);

end Test_Halos_Mock_Mmio;
