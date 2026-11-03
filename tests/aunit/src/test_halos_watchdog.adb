with AUnit.Assertions; use AUnit.Assertions;
with Halos_Watchdog;   use Halos_Watchdog;
with Interfaces;       use Interfaces;

package body Test_Halos_Watchdog is

   overriding function Name (T : Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Halos.Watchdog.Windowed");
   end Name;

   overriding procedure Register_Tests (T : in out Test_Case) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine (T, Test_Arm_Config'Access, "Test Arm & Config Validation");
      Register_Routine (T, Test_Nominal_Pet'Access, "Test Nominal Pet in Window");
      Register_Routine (T, Test_Early_Pet'Access, "Test Early Pet Fault Detection");
      Register_Routine (T, Test_Late_Pet'Access, "Test Late Pet Fault Detection");
      Register_Routine (T, Test_Clock_Rewind'Access, "Test Clock Rewind Detection");
      Register_Routine (T, Test_Deadline_Check'Access, "Test Deadline Check Expiration");
      Register_Routine (T, Test_Authorized_Reset'Access, "Test Password Reset Authorization");
   end Register_Tests;

   procedure Test_Arm_Config (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      WD     : Halos_Watchdog_Device;
      Status : Halos_Watchdog_Status;
      Valid_Cfg : constant Halos_Watchdog_Config :=
        (Min_Interval_Ns => 500_000,
         Max_Interval_Ns => 5_000_000);
      Invalid_Cfg : constant Halos_Watchdog_Config :=
        (Min_Interval_Ns => 6_000_000,
         Max_Interval_Ns => 5_000_000);
   begin
      Init (WD);
      Assert (WD.State = WD_Disabled, "Initial state should be disabled");

      Arm (WD, Invalid_Cfg, 1_000_000, Status);
      Assert (Status = WD_Err_Invalid_Config, "Arm should reject min > max");
      Assert (WD.State = WD_Disabled, "State should remain disabled");

      Arm (WD, Valid_Cfg, 1_000_000, Status);
      Assert (Status = WD_Ok, "Arm should accept valid config");
      Assert (WD.State = WD_Armed, "State should be armed");
      Assert (WD.Last_Pet_Ns = 1_000_000, "Start timestamp recorded");
   end Test_Arm_Config;

   procedure Test_Nominal_Pet (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      WD     : Halos_Watchdog_Device;
      Status : Halos_Watchdog_Status;
      Cfg    : constant Halos_Watchdog_Config :=
        (Min_Interval_Ns => 500_000,
         Max_Interval_Ns => 5_000_000);
   begin
      Init (WD);
      Arm (WD, Cfg, 1_000_000, Status);

      --  Pet at +1.0 ms (inside [0.5 ms, 5.0 ms])
      Pet (WD, 2_000_000, Status);
      Assert (Status = WD_Ok, "Nominal pet should succeed");
      Assert (WD.State = WD_Armed, "Watchdog should remain armed");
      Assert (WD.Pet_Count = 1, "Pet count incremented");
      Assert (WD.Last_Pet_Ns = 2_000_000, "Last pet timestamp updated");

      --  Pet at +2.0 ms
      Pet (WD, 4_000_000, Status);
      Assert (Status = WD_Ok, "Second nominal pet should succeed");
      Assert (WD.Pet_Count = 2, "Pet count should be 2");
   end Test_Nominal_Pet;

   procedure Test_Early_Pet (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      WD     : Halos_Watchdog_Device;
      Status : Halos_Watchdog_Status;
      Cfg    : constant Halos_Watchdog_Config :=
        (Min_Interval_Ns => 500_000,
         Max_Interval_Ns => 5_000_000);
   begin
      Init (WD);
      Arm (WD, Cfg, 1_000_000, Status);

      --  Pet at +0.1 ms (too early! 100_000 < 500_000)
      Pet (WD, 1_100_000, Status);
      Assert (Status = WD_Err_Too_Early, "Early pet should return error");
      Assert (WD.State = WD_Fault_Early, "State should latch early fault");

      --  Subsequent pet should stay rejected
      Pet (WD, 2_000_000, Status);
      Assert (Status = WD_Err_Not_Armed, "Subsequent pet should fail while in fault");
   end Test_Early_Pet;

   procedure Test_Late_Pet (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      WD     : Halos_Watchdog_Device;
      Status : Halos_Watchdog_Status;
      Cfg    : constant Halos_Watchdog_Config :=
        (Min_Interval_Ns => 500_000,
         Max_Interval_Ns => 5_000_000);
   begin
      Init (WD);
      Arm (WD, Cfg, 1_000_000, Status);

      --  Pet at +6.0 ms (too late! 6_000_000 > 5_000_000)
      Pet (WD, 7_000_000, Status);
      Assert (Status = WD_Err_Too_Late, "Late pet should return timeout");
      Assert (WD.State = WD_Fault_Late, "State should latch late fault");
   end Test_Late_Pet;

   procedure Test_Clock_Rewind (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      WD     : Halos_Watchdog_Device;
      Status : Halos_Watchdog_Status;
      Cfg    : constant Halos_Watchdog_Config :=
        (Min_Interval_Ns => 500_000,
         Max_Interval_Ns => 5_000_000);
   begin
      Init (WD);
      Arm (WD, Cfg, 2_000_000, Status);

      --  Pet at earlier timestamp (clock rewind)
      Pet (WD, 1_000_000, Status);
      Assert (Status = WD_Err_Time_Rewind, "Rewind should return error");
      Assert (WD.State = WD_Fault_Clock, "State should latch clock fault");
   end Test_Clock_Rewind;

   procedure Test_Deadline_Check (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      WD     : Halos_Watchdog_Device;
      Status : Halos_Watchdog_Status;
      Cfg    : constant Halos_Watchdog_Config :=
        (Min_Interval_Ns => 500_000,
         Max_Interval_Ns => 5_000_000);
   begin
      Init (WD);
      Arm (WD, Cfg, 1_000_000, Status);

      --  Check at +2.0 ms (within window)
      Check_Deadline (WD, 3_000_000, Status);
      Assert (Status = WD_Ok, "Deadline check within window should be OK");
      Assert (WD.State = WD_Armed, "Should remain armed");

      --  Check at +7.0 ms (deadline missed!)
      Check_Deadline (WD, 8_000_000, Status);
      Assert (Status = WD_Err_Too_Late, "Missed deadline should be detected");
      Assert (WD.State = WD_Fault_Late, "Should latch fault late");
   end Test_Deadline_Check;

   procedure Test_Authorized_Reset (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      WD     : Halos_Watchdog_Device;
      Status : Halos_Watchdog_Status;
      Cfg    : constant Halos_Watchdog_Config :=
        (Min_Interval_Ns => 500_000,
         Max_Interval_Ns => 5_000_000);
   begin
      Init (WD);
      Arm (WD, Cfg, 1_000_000, Status);
      Pet (WD, 7_000_000, Status);
      Assert (WD.State = WD_Fault_Late, "Watchdog should be in fault");

      --  Attempt reset with invalid magic key
      Reset (WD, 16#1234_5678#, 8_000_000, Status);
      Assert (Status = WD_Err_Invalid_Key, "Invalid key should be rejected");
      Assert (WD.State = WD_Fault_Late, "Watchdog must remain in fault");

      --  Reset with correct key 0x57444752 ("WDGR")
      Reset (WD, Halos_Wd_Reset_Magic, 8_000_000, Status);
      Assert (Status = WD_Ok, "Authorized reset must succeed");
      Assert (WD.State = WD_Armed, "Watchdog returned to armed");
      Assert (WD.Last_Pet_Ns = 8_000_000, "Timestamp reset to now");
   end Test_Authorized_Reset;

end Test_Halos_Watchdog;
