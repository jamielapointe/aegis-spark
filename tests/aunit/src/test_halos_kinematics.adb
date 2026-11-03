with AUnit.Assertions; use AUnit.Assertions;
with Halos_Kinematics; use Halos_Kinematics;
with Halos_HSM;        use Halos_HSM;
with Interfaces.C;     use Interfaces.C;

package body Test_Halos_Kinematics is

   overriding function Name (T : Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Halos.Kinematics.6DOF");
   end Name;

   overriding procedure Register_Tests (T : in out Test_Case) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T, Test_Nominal_Kinematic_Pass'Access, "Test Nominal Kinematic Command Pass");
      Register_Routine
        (T, Test_Position_Limit_Exceeded'Access, "Test Position Bound Violation Latching");
      Register_Routine
        (T, Test_Velocity_Limit_Exceeded'Access, "Test Velocity Bound Violation Latching");
      Register_Routine
        (T, Test_Torque_Limit_Exceeded'Access, "Test Torque Bound Violation Latching");
      Register_Routine
        (T, Test_Jerk_Step_Delta_Exceeded'Access, "Test Jerk Step Delta Violation Latching");
      Register_Routine
        (T, Test_Zero_Torque_Fail_Safe_Latch'Access, "Test Fail-Safe Zero Clamping on Violation");
   end Register_Tests;

   procedure Test_Nominal_Kinematic_Pass (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      State    : Halos_Kinematic_State;
      Cmd      : Halos_Kinematic_Cmd;
      Safe_Tau : Torque_Array;
      Safe_Vel : Velocity_Array;
      Status   : Halos_Hsm_Status;
   begin
      Init (State);
      State.HSM.State := State_Active;

      Cmd :=
        (Timestamp_Ns => 1_000_000,
         Position_Rad => [others => 1.0],
         Velocity_Rad => [others => 2.0],
         Torque_Nm    => [others => 10.0]);

      Intercept_Kinematic_Cmd (State, Cmd, Safe_Tau, Safe_Vel, Status);
      Assert (Status = HSM_Ok, "Nominal command should pass");
      Assert (State.HSM.State = State_Active, "State should remain Active");
      Assert (Safe_Tau (0) = 10.0, "Torque output should match command");
      Assert (Safe_Vel (0) = 2.0, "Velocity output should match command");
   end Test_Nominal_Kinematic_Pass;

   procedure Test_Position_Limit_Exceeded (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      State    : Halos_Kinematic_State;
      Cmd      : Halos_Kinematic_Cmd;
      Safe_Tau : Torque_Array;
      Safe_Vel : Velocity_Array;
      Status   : Halos_Hsm_Status;
   begin
      Init (State);
      State.HSM.State := State_Active;
      State.Limits.Max_Abs_Position_Rad := [others => 3.14159265];

      --  Exceed position on joint 2 (4.0 > 3.14159)
      Cmd :=
        (Timestamp_Ns => 1_000_000,
         Position_Rad => [2 => 4.0, others => 0.0],
         Velocity_Rad => [others => 1.0],
         Torque_Nm    => [others => 5.0]);

      Intercept_Kinematic_Cmd (State, Cmd, Safe_Tau, Safe_Vel, Status);
      Assert (Status /= HSM_Ok, "Out of bounds position should fail");
      Assert (State.HSM.State = State_Fault_Estop, "Must latch in Fault_Estop");
      Assert (State.HSM.Last_Fault_Code = Fault_Kinematic_Position, "Fault code position");
      Assert (Is_Zero_Torque (Safe_Tau), "All joints must be clamped to zero torque");
   end Test_Position_Limit_Exceeded;

   procedure Test_Velocity_Limit_Exceeded (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      State    : Halos_Kinematic_State;
      Cmd      : Halos_Kinematic_Cmd;
      Safe_Tau : Torque_Array;
      Safe_Vel : Velocity_Array;
      Status   : Halos_Hsm_Status;
   begin
      Init (State);
      State.HSM.State := State_Active;
      State.Limits.Max_Abs_Velocity_Rad := [others => 10.0];

      --  Exceed velocity on joint 5 (15.0 > 10.0)
      Cmd :=
        (Timestamp_Ns => 1_000_000,
         Position_Rad => [others => 0.0],
         Velocity_Rad => [5 => 15.0, others => 1.0],
         Torque_Nm    => [others => 5.0]);

      Intercept_Kinematic_Cmd (State, Cmd, Safe_Tau, Safe_Vel, Status);
      Assert (Status /= HSM_Ok, "Out of bounds velocity should fail");
      Assert (State.HSM.State = State_Fault_Estop, "Must latch in Fault_Estop");
      Assert (State.HSM.Last_Fault_Code = Fault_Kinematic_Velocity, "Fault code velocity");
      Assert (Is_Zero_Torque (Safe_Tau), "All joints clamped to 0.0");
   end Test_Velocity_Limit_Exceeded;

   procedure Test_Torque_Limit_Exceeded (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      State    : Halos_Kinematic_State;
      Cmd      : Halos_Kinematic_Cmd;
      Safe_Tau : Torque_Array;
      Safe_Vel : Velocity_Array;
      Status   : Halos_Hsm_Status;
   begin
      Init (State);
      State.HSM.State := State_Active;
      State.Limits.Max_Abs_Torque_Nm := [others => 50.0];

      --  Exceed torque on joint 0 (75.0 > 50.0)
      Cmd :=
        (Timestamp_Ns => 1_000_000,
         Position_Rad => [others => 0.0],
         Velocity_Rad => [others => 1.0],
         Torque_Nm    => [0 => 75.0, others => 10.0]);

      Intercept_Kinematic_Cmd (State, Cmd, Safe_Tau, Safe_Vel, Status);
      Assert (Status /= HSM_Ok, "Over torque should fail");
      Assert (State.HSM.State = State_Fault_Estop, "Must latch in Fault_Estop");
      Assert (State.HSM.Last_Fault_Code = Fault_Kinematic_Torque, "Fault code torque");
      Assert (Is_Zero_Torque (Safe_Tau), "All joints clamped to 0.0");
   end Test_Torque_Limit_Exceeded;

   procedure Test_Jerk_Step_Delta_Exceeded (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      State    : Halos_Kinematic_State;
      Cmd1     : Halos_Kinematic_Cmd;
      Cmd2     : Halos_Kinematic_Cmd;
      Safe_Tau : Torque_Array;
      Safe_Vel : Velocity_Array;
      Status   : Halos_Hsm_Status;
   begin
      Init (State);
      State.HSM.State := State_Active;
      State.Limits.Max_Delta_Torque_Step := [others => 20.0];

      --  First command at 10.0 Nm
      Cmd1 :=
        (Timestamp_Ns => 1_000_000,
         Position_Rad => [others => 0.0],
         Velocity_Rad => [others => 1.0],
         Torque_Nm    => [others => 10.0]);

      Intercept_Kinematic_Cmd (State, Cmd1, Safe_Tau, Safe_Vel, Status);
      Assert (Status = HSM_Ok, "First step ok");

      --  Second command jumps torque by 35.0 Nm (45.0 - 10.0 = 35.0 > 20.0 max step jerk!)
      Cmd2 :=
        (Timestamp_Ns => 2_000_000,
         Position_Rad => [others => 0.0],
         Velocity_Rad => [others => 1.0],
         Torque_Nm    => [3 => 45.0, others => 10.0]);

      Intercept_Kinematic_Cmd (State, Cmd2, Safe_Tau, Safe_Vel, Status);
      Assert (Status /= HSM_Ok, "Jerk jump should be rejected");
      Assert (State.HSM.State = State_Fault_Estop, "Must latch in Fault_Estop");
      Assert (State.HSM.Last_Fault_Code = Fault_Kinematic_Jerk, "Fault code jerk");
      Assert (Is_Zero_Torque (Safe_Tau), "All joints clamped to 0.0");
   end Test_Jerk_Step_Delta_Exceeded;

   procedure Test_Zero_Torque_Fail_Safe_Latch (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      State    : Halos_Kinematic_State;
      Cmd      : Halos_Kinematic_Cmd;
      Safe_Tau : Torque_Array;
      Safe_Vel : Velocity_Array;
      Status   : Halos_Hsm_Status;
   begin
      Init (State);
      State.HSM.State := State_Fault_Estop;

      Cmd :=
        (Timestamp_Ns => 1_000_000,
         Position_Rad => [others => 0.0],
         Velocity_Rad => [others => 0.0],
         Torque_Nm    => [others => 10.0]);

      Intercept_Kinematic_Cmd (State, Cmd, Safe_Tau, Safe_Vel, Status);
      Assert (Status /= HSM_Ok, "Commands rejected in Estop");
      Assert (Is_Zero_Torque (Safe_Tau), "Safe torque must be zero in Estop");
      Assert (Is_Zero_Velocity (Safe_Vel), "Safe vel must be zero in Estop");
   end Test_Zero_Torque_Fail_Safe_Latch;

end Test_Halos_Kinematics;
