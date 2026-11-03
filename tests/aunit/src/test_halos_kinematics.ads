with AUnit.Test_Cases;

package Test_Halos_Kinematics is

   type Test_Case is new AUnit.Test_Cases.Test_Case with null record;

   overriding procedure Register_Tests (T : in out Test_Case);
   overriding function Name (T : Test_Case) return AUnit.Message_String;

   procedure Test_Nominal_Kinematic_Pass (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Position_Limit_Exceeded (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Velocity_Limit_Exceeded (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Torque_Limit_Exceeded (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Jerk_Step_Delta_Exceeded (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Zero_Torque_Fail_Safe_Latch (T : in out AUnit.Test_Cases.Test_Case'Class);

end Test_Halos_Kinematics;
