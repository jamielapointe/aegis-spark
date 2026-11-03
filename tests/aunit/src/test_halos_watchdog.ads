with AUnit.Test_Cases;

package Test_Halos_Watchdog is

   type Test_Case is new AUnit.Test_Cases.Test_Case with null record;

   overriding procedure Register_Tests (T : in out Test_Case);
   overriding function Name (T : Test_Case) return AUnit.Message_String;

   procedure Test_Arm_Config (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Nominal_Pet (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Early_Pet (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Late_Pet (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Clock_Rewind (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Deadline_Check (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Authorized_Reset (T : in out AUnit.Test_Cases.Test_Case'Class);

end Test_Halos_Watchdog;
