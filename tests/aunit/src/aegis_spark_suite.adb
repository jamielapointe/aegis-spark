with Test_Halos_Safety_Gate;
with Test_Halos_Mock_Mmio;
with Test_Halos_Watchdog;
with Test_Halos_HSM;
with Test_Halos_Kinematics;
with Test_Halos_Mailbox;

package body Aegis_Spark_Suite is

   Gate_Tests       : aliased Test_Halos_Safety_Gate.Test_Case;
   Mmio_Tests       : aliased Test_Halos_Mock_Mmio.Test_Case;
   Watchdog_Tests   : aliased Test_Halos_Watchdog.Test_Case;
   Hsm_Tests        : aliased Test_Halos_HSM.Test_Case;
   Kinematics_Tests : aliased Test_Halos_Kinematics.Test_Case;
   Mailbox_Tests    : aliased Test_Halos_Mailbox.Test_Case;

   function Suite return AUnit.Test_Suites.Access_Test_Suite is
      Result : constant AUnit.Test_Suites.Access_Test_Suite :=
        AUnit.Test_Suites.New_Suite;
   begin
      Result.Add_Test (Gate_Tests'Access);
      Result.Add_Test (Mmio_Tests'Access);
      Result.Add_Test (Watchdog_Tests'Access);
      Result.Add_Test (Hsm_Tests'Access);
      Result.Add_Test (Kinematics_Tests'Access);
      Result.Add_Test (Mailbox_Tests'Access);
      return Result;
   end Suite;

end Aegis_Spark_Suite;
