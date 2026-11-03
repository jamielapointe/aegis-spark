with AUnit.Test_Cases;

package Test_Halos_Safety_Gate is

   type Test_Case is new AUnit.Test_Cases.Test_Case with null record;

   overriding procedure Register_Tests (T : in out Test_Case);
   overriding function Name (T : Test_Case) return AUnit.Message_String;

   procedure Test_Nominal_Command
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   procedure Test_Watchdog_Stale_Heartbeat
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   procedure Test_Future_Timestamp
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   procedure Test_Torque_Limit_Exceeded
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   procedure Test_Boundary_Conditions
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   procedure Test_Fault_Estop_Latching
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   procedure Test_Inactive_State_Rejection
     (T : in out AUnit.Test_Cases.Test_Case'Class);

end Test_Halos_Safety_Gate;
