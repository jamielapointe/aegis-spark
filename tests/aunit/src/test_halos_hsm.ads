with AUnit.Test_Cases;

package Test_Halos_HSM is

   type Test_Case is new AUnit.Test_Cases.Test_Case with null record;

   overriding procedure Register_Tests (T : in out Test_Case);
   overriding function Name (T : Test_Case) return AUnit.Message_String;

   procedure Test_Boot_And_Self_Test (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Self_Test_Failed (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Active_Degraded_Transitions (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Fault_Estop_Latching (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Illegal_Estop_Bypass (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Authorized_Reset (T : in out AUnit.Test_Cases.Test_Case'Class);

end Test_Halos_HSM;
