with Test_Halos_Safety_Gate;
with Test_Halos_Mock_Mmio;

package body Aegis_Spark_Suite is

   Gate_Tests : aliased Test_Halos_Safety_Gate.Test_Case;
   Mmio_Tests : aliased Test_Halos_Mock_Mmio.Test_Case;

   function Suite return AUnit.Test_Suites.Access_Test_Suite is
      Result : constant AUnit.Test_Suites.Access_Test_Suite :=
        AUnit.Test_Suites.New_Suite;
   begin
      Result.Add_Test (Gate_Tests'Access);
      Result.Add_Test (Mmio_Tests'Access);
      return Result;
   end Suite;

end Aegis_Spark_Suite;
