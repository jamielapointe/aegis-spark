with AUnit; use type AUnit.Status;
with AUnit.Reporter.Text;
with AUnit.Run;
with Ada.Command_Line;
with Aegis_Spark_Suite;

procedure Aunit_Runner is
   function Run is new
     AUnit.Run.Test_Runner_With_Status (Aegis_Spark_Suite.Suite);
   Reporter : AUnit.Reporter.Text.Text_Reporter;
   Status   : AUnit.Status;
begin
   Status := Run (Reporter);
   if Status /= AUnit.Success then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Aunit_Runner;
