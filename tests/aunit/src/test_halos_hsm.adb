with AUnit.Assertions; use AUnit.Assertions;
with Halos_HSM;        use Halos_HSM;
with Interfaces;       use Interfaces;

package body Test_Halos_HSM is

   overriding function Name (T : Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Halos.HSM.Lifecycle");
   end Name;

   overriding procedure Register_Tests (T : in out Test_Case) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine (T, Test_Boot_And_Self_Test'Access, "Test Boot State & Self-Test Pass");
      Register_Routine (T, Test_Self_Test_Failed'Access, "Test Self-Test Failure to Estop");
      Register_Routine
        (T, Test_Active_Degraded_Transitions'Access, "Test Active <-> Degraded Transitions");
      Register_Routine (T, Test_Fault_Estop_Latching'Access, "Test Fault Detection Latching");
      Register_Routine (T, Test_Illegal_Estop_Bypass'Access, "Test Illegal Estop Bypass Rejection");
      Register_Routine (T, Test_Authorized_Reset'Access, "Test Authorized Fault Reset Key");
   end Register_Tests;

   procedure Test_Boot_And_Self_Test (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      HSM    : Halos_HSM_Instance;
      Status : Halos_Hsm_Status;
   begin
      Init (HSM);
      Assert (HSM.State = State_Boot, "Initial state must be Boot");
      Assert (HSM.Last_Fault_Code = Fault_None, "Fault code must be None");
      Assert (HSM.Transition_Count = 0, "Transition count should be 0");

      --  Self-test passed transitions Boot -> Active
      Process_Event (HSM, Event_Self_Test_Passed, Fault_None, Status);
      Assert (Status = HSM_Ok, "Self-test pass should succeed");
      Assert (HSM.State = State_Active, "State must transition to Active");
      Assert (HSM.Transition_Count = 1, "Transition count should be 1");
   end Test_Boot_And_Self_Test;

   procedure Test_Self_Test_Failed (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      HSM    : Halos_HSM_Instance;
      Status : Halos_Hsm_Status;
   begin
      Init (HSM);
      Process_Event (HSM, Event_Self_Test_Failed, Fault_None, Status);
      Assert (Status = HSM_Ok, "Event processed");
      Assert (HSM.State = State_Fault_Estop, "Failed BIST must transition to Fault_Estop");
      Assert (HSM.Last_Fault_Code = Fault_Hardware_Bist, "Fault code must be BIST");
   end Test_Self_Test_Failed;

   procedure Test_Active_Degraded_Transitions (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      HSM    : Halos_HSM_Instance;
      Status : Halos_Hsm_Status;
   begin
      Init (HSM);
      Process_Event (HSM, Event_Self_Test_Passed, Fault_None, Status);
      Assert (HSM.State = State_Active, "Active state");

      --  Active -> Degraded
      Process_Event (HSM, Event_Degrade_Requested, Fault_None, Status);
      Assert (Status = HSM_Ok, "Degrade request should succeed");
      Assert (HSM.State = State_Degraded, "State should be Degraded");

      --  Degraded -> Active
      Process_Event (HSM, Event_Recover_Nominal, Fault_None, Status);
      Assert (Status = HSM_Ok, "Recover nominal should succeed");
      Assert (HSM.State = State_Active, "State should return to Active");
   end Test_Active_Degraded_Transitions;

   procedure Test_Fault_Estop_Latching (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      HSM    : Halos_HSM_Instance;
      Status : Halos_Hsm_Status;
   begin
      Init (HSM);
      Process_Event (HSM, Event_Self_Test_Passed, Fault_None, Status);

      --  Fault detected from Active
      Process_Event (HSM, Event_Fault_Detected, Fault_Kinematic_Torque, Status);
      Assert (Status = HSM_Ok, "Fault transition succeeded");
      Assert (HSM.State = State_Fault_Estop, "Must latch in Fault_Estop");
      Assert (HSM.Last_Fault_Code = Fault_Kinematic_Torque, "Fault code recorded");
   end Test_Fault_Estop_Latching;

   procedure Test_Illegal_Estop_Bypass (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      HSM    : Halos_HSM_Instance;
      Status : Halos_Hsm_Status;
   begin
      Init (HSM);
      Process_Event (HSM, Event_Fault_Detected, Fault_Watchdog_Timeout, Status);
      Assert (HSM.State = State_Fault_Estop, "In Estop");

      --  Attempt direct transition to Active
      Process_Event (HSM, Event_Self_Test_Passed, Fault_None, Status);
      Assert (Status = HSM_Err_Invalid_Transition, "Must reject direct transition from Estop");
      Assert (HSM.State = State_Fault_Estop, "Must remain in Estop");

      --  Attempt direct transition to Degraded
      Process_Event (HSM, Event_Degrade_Requested, Fault_None, Status);
      Assert (Status = HSM_Err_Invalid_Transition, "Must reject degrade from Estop");
      Assert (HSM.State = State_Fault_Estop, "Must remain in Estop");
   end Test_Illegal_Estop_Bypass;

   procedure Test_Authorized_Reset (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      HSM    : Halos_HSM_Instance;
      Status : Halos_Hsm_Status;
   begin
      Init (HSM);
      Process_Event (HSM, Event_Fault_Detected, Fault_Kinematic_Position, Status);
      Assert (HSM.State = State_Fault_Estop, "In Estop");

      --  Reset with wrong key
      Trigger_Reset (HSM, 16#CAFE_BABE#, Status);
      Assert (Status = HSM_Err_Invalid_Key, "Invalid key rejected");
      Assert (HSM.State = State_Fault_Estop, "Must remain in Estop");

      --  Reset with correct key 0x48534D52 ("HSMR")
      Trigger_Reset (HSM, Halos_Hsm_Reset_Magic, Status);
      Assert (Status = HSM_Ok, "Authorized reset accepted");
      Assert (HSM.State = State_Boot, "Must transition strictly to Boot");
      Assert (HSM.Last_Fault_Code = Fault_None, "Fault code cleared");
   end Test_Authorized_Reset;

end Test_Halos_HSM;
