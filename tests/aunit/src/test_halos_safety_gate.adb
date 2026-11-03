with AUnit.Assertions; use AUnit.Assertions;
with Halos_Safety_Gate; use Halos_Safety_Gate;
with Interfaces;        use Interfaces;
with Interfaces.C;      use Interfaces.C;

package body Test_Halos_Safety_Gate is

   overriding procedure Register_Tests (T : in out Test_Case) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T, Test_Nominal_Command'Access,
         "Test Nominal Command Pass-Through");
      Register_Routine
        (T, Test_Watchdog_Stale_Heartbeat'Access,
         "Test Watchdog Stale Heartbeat");
      Register_Routine
        (T, Test_Future_Timestamp'Access,
         "Test Future Timestamp Rejection");
      Register_Routine
        (T, Test_Torque_Limit_Exceeded'Access,
         "Test Torque Limit Exceeded Rejection");
      Register_Routine
        (T, Test_Boundary_Conditions'Access,
         "Test Exact Envelope Boundary Conditions");
      Register_Routine
        (T, Test_Fault_Estop_Latching'Access,
         "Test Fault E-Stop Latching Persistence");
      Register_Routine
        (T, Test_Inactive_State_Rejection'Access,
         "Test Inactive State Command Rejection");
   end Register_Tests;

   overriding function Name (T : Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Halos Safety Gate Unit Tests");
   end Name;

   procedure Test_Nominal_Command
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Env : Halos_Safety_Envelope :=
        (Max_Abs_Torque_Nm => [others => 50.0],
         State             => State_Active);
      Cmd : constant Halos_Joint_Cmd :=
        (Timestamp_Ns      => 1_000_000,
         Desired_Torque_Nm => [others => 25.0]);
      Safe_Out : Safe_Torque_Array;
      Status   : Halos_Status;
   begin
      Intercept_Joint_Cmd
        (Env             => Env,
         Cmd_In          => Cmd,
         Now_Ns          => 2_000_000,
         Safe_Torque_Out => Safe_Out,
         Status          => Status);

      Assert (Status = Halos_Ok,
              "Expected Halos_Ok on nominal command");
      Assert (Env.State = State_Active,
              "Expected Env.State to remain State_Active");
      for I in Dof_Index loop
         Assert (Safe_Out (I) = 25.0,
                 "Expected Safe_Torque_Out to match desired torque");
      end loop;
   end Test_Nominal_Command;

   procedure Test_Watchdog_Stale_Heartbeat
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Env : Halos_Safety_Envelope :=
        (Max_Abs_Torque_Nm => [others => 50.0],
         State             => State_Active);
      --  Age = 6 ms > 5 ms watchdog limit
      Cmd : constant Halos_Joint_Cmd :=
        (Timestamp_Ns      => 1_000_000,
         Desired_Torque_Nm => [others => 10.0]);
      Safe_Out : Safe_Torque_Array;
      Status   : Halos_Status;
   begin
      Intercept_Joint_Cmd
        (Env             => Env,
         Cmd_In          => Cmd,
         Now_Ns          => 7_000_000,
         Safe_Torque_Out => Safe_Out,
         Status          => Status);

      Assert (Status = Halos_Err_Stale_Heartbeat,
              "Expected Halos_Err_Stale_Heartbeat");
      Assert (Env.State = State_Fault_Estop,
              "Expected transition to State_Fault_Estop");
      for I in Dof_Index loop
         Assert (Safe_Out (I) = 0.0,
                 "Expected zero torque on watchdog failure");
      end loop;
   end Test_Watchdog_Stale_Heartbeat;

   procedure Test_Future_Timestamp
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Env : Halos_Safety_Envelope :=
        (Max_Abs_Torque_Nm => [others => 50.0],
         State             => State_Active);
      --  Timestamp is in the future: Cmd_Time > Now_Ns
      Cmd : constant Halos_Joint_Cmd :=
        (Timestamp_Ns      => 3_000_000,
         Desired_Torque_Nm => [others => 10.0]);
      Safe_Out : Safe_Torque_Array;
      Status   : Halos_Status;
   begin
      Intercept_Joint_Cmd
        (Env             => Env,
         Cmd_In          => Cmd,
         Now_Ns          => 2_000_000,
         Safe_Torque_Out => Safe_Out,
         Status          => Status);

      Assert (Status = Halos_Err_Stale_Heartbeat,
              "Expected Halos_Err_Stale_Heartbeat on future timestamp");
      Assert (Env.State = State_Fault_Estop,
              "Expected transition to State_Fault_Estop");
      for I in Dof_Index loop
         Assert (Safe_Out (I) = 0.0,
                 "Expected zero torque on clock rewind/future timestamp");
      end loop;
   end Test_Future_Timestamp;

   procedure Test_Torque_Limit_Exceeded
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Env : Halos_Safety_Envelope :=
        (Max_Abs_Torque_Nm => [others => 50.0],
         State             => State_Active);
      --  Joint 0 exceeds limit (75.0 > 50.0)
      Cmd : constant Halos_Joint_Cmd :=
        (Timestamp_Ns      => 1_000_000,
         Desired_Torque_Nm => [0 => 75.0, others => 10.0]);
      Safe_Out : Safe_Torque_Array;
      Status   : Halos_Status;
   begin
      Intercept_Joint_Cmd
        (Env             => Env,
         Cmd_In          => Cmd,
         Now_Ns          => 2_000_000,
         Safe_Torque_Out => Safe_Out,
         Status          => Status);

      Assert (Status = Halos_Err_Torque_Limit_Exceeded,
              "Expected Halos_Err_Torque_Limit_Exceeded");
      Assert (Env.State = State_Fault_Estop,
              "Expected transition to State_Fault_Estop");
      for I in Dof_Index loop
         Assert (Safe_Out (I) = 0.0,
                 "Expected all joints zeroed on torque violation");
      end loop;
   end Test_Torque_Limit_Exceeded;

   procedure Test_Boundary_Conditions
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Env : Halos_Safety_Envelope :=
        (Max_Abs_Torque_Nm => [others => 50.0],
         State             => State_Active);
      --  Exactly at boundary: 50.0 and -50.0
      Cmd : constant Halos_Joint_Cmd :=
        (Timestamp_Ns      => 1_000_000,
         Desired_Torque_Nm => [0 => 50.0, 1 => -50.0, others => 0.0]);
      Safe_Out : Safe_Torque_Array;
      Status   : Halos_Status;
   begin
      Intercept_Joint_Cmd
        (Env             => Env,
         Cmd_In          => Cmd,
         Now_Ns          => 2_000_000,
         Safe_Torque_Out => Safe_Out,
         Status          => Status);

      Assert (Status = Halos_Ok,
              "Expected Halos_Ok on exact boundary values");
      Assert (Env.State = State_Active,
              "Expected State_Active on boundary values");
      Assert (Safe_Out (0) = 50.0, "Joint 0 should be 50.0");
      Assert (Safe_Out (1) = -50.0, "Joint 1 should be -50.0");
   end Test_Boundary_Conditions;

   procedure Test_Fault_Estop_Latching
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Env : Halos_Safety_Envelope :=
        (Max_Abs_Torque_Nm => [others => 50.0],
         State             => State_Active);
      Bad_Cmd : constant Halos_Joint_Cmd :=
        (Timestamp_Ns      => 1_000_000,
         Desired_Torque_Nm => [others => 100.0]);
      Good_Cmd : constant Halos_Joint_Cmd :=
        (Timestamp_Ns      => 2_500_000,
         Desired_Torque_Nm => [others => 10.0]);
      Safe_Out : Safe_Torque_Array;
      Status   : Halos_Status;
   begin
      --  First command triggers fault
      Intercept_Joint_Cmd
        (Env             => Env,
         Cmd_In          => Bad_Cmd,
         Now_Ns          => 2_000_000,
         Safe_Torque_Out => Safe_Out,
         Status          => Status);
      Assert (Env.State = State_Fault_Estop,
              "Must latch to State_Fault_Estop");

      --  Subsequent valid command must remain rejected
      Intercept_Joint_Cmd
        (Env             => Env,
         Cmd_In          => Good_Cmd,
         Now_Ns          => 3_000_000,
         Safe_Torque_Out => Safe_Out,
         Status          => Status);

      Assert (Status = Halos_Err_Not_Active,
              "Expected Halos_Err_Not_Active while latched in fault");
      Assert (Env.State = State_Fault_Estop,
              "State must remain State_Fault_Estop");
      for I in Dof_Index loop
         Assert (Safe_Out (I) = 0.0, "Safe torque must remain zero");
      end loop;
   end Test_Fault_Estop_Latching;

   procedure Test_Inactive_State_Rejection
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Env : Halos_Safety_Envelope :=
        (Max_Abs_Torque_Nm => [others => 50.0],
         State             => State_Init);
      Cmd : constant Halos_Joint_Cmd :=
        (Timestamp_Ns      => 1_000_000,
         Desired_Torque_Nm => [others => 10.0]);
      Safe_Out : Safe_Torque_Array;
      Status   : Halos_Status;
   begin
      Intercept_Joint_Cmd
        (Env             => Env,
         Cmd_In          => Cmd,
         Now_Ns          => 2_000_000,
         Safe_Torque_Out => Safe_Out,
         Status          => Status);

      Assert (Status = Halos_Err_Not_Active,
              "Commands in State_Init must be rejected");
      Assert (Env.State = State_Init, "State should remain State_Init");
      for I in Dof_Index loop
         Assert (Safe_Out (I) = 0.0,
                 "Safe torque must be zero in State_Init");
      end loop;
   end Test_Inactive_State_Rejection;

end Test_Halos_Safety_Gate;
