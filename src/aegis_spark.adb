pragma Ada_2022;
with Halos_Logger;      use Halos_Logger;
with Halos_Safety_Gate; use Halos_Safety_Gate;
with Interfaces;        use Interfaces;
with Interfaces.C;      use Interfaces.C;

procedure Aegis_Spark
   with SPARK_Mode => On
is
   Env : Halos_Safety_Envelope :=
     (Max_Abs_Torque_Nm => [others => 50.0],
      State             => State_Active);

   Valid_Cmd : constant Halos_Joint_Cmd :=
     (Timestamp_Ns      => 1_000_000,
      Desired_Torque_Nm => [others => 12.5]);

   Over_Torque_Cmd : constant Halos_Joint_Cmd :=
     (Timestamp_Ns      => 2_000_000,
      Desired_Torque_Nm => [0 => 75.0, others => 10.0]);

   Safe_Out : Safe_Torque_Array;
   Status   : Halos_Status;
begin
   Log_Suite_Header;

   --  1. Nominal command within watchdog deadline and torque envelope
   Intercept_Joint_Cmd
     (Env             => Env,
      Cmd_In          => Valid_Cmd,
      Now_Ns          => 2_000_000,
      Safe_Torque_Out => Safe_Out,
      Status          => Status);
   pragma Assert (Status = Halos_Ok);
   pragma Assert (Env.State = State_Active);
   Log_Intercept_Step
     (Step_Id  => 1,
      Now_Ns   => 2_000_000,
      Cmd_In   => Valid_Cmd,
      Env      => Env,
      Safe_Out => Safe_Out,
      Status   => Status);

   --  2. Command exceeding torque envelope triggers Fault_Estop & zero torque
   Intercept_Joint_Cmd
     (Env             => Env,
      Cmd_In          => Over_Torque_Cmd,
      Now_Ns          => 2_500_000,
      Safe_Torque_Out => Safe_Out,
      Status          => Status);
   pragma Assert (Status /= Halos_Ok);
   pragma Assert (Env.State = State_Fault_Estop);
   pragma Assert (for all I in Dof_Index => Safe_Out (I) = 0.0);
   Log_Intercept_Step
     (Step_Id  => 2,
      Now_Ns   => 2_500_000,
      Cmd_In   => Over_Torque_Cmd,
      Env      => Env,
      Safe_Out => Safe_Out,
      Status   => Status);

   --  3. Subsequent valid command stays rejected while latched in Fault_Estop
   Intercept_Joint_Cmd
     (Env             => Env,
      Cmd_In          => Valid_Cmd,
      Now_Ns          => 3_000_000,
      Safe_Torque_Out => Safe_Out,
      Status          => Status);
   pragma Assert (Status /= Halos_Ok);
   pragma Assert (Env.State = State_Fault_Estop);
   pragma Assert (for all I in Dof_Index => Safe_Out (I) = 0.0);
   Log_Intercept_Step
     (Step_Id  => 3,
      Now_Ns   => 3_000_000,
      Cmd_In   => Valid_Cmd,
      Env      => Env,
      Safe_Out => Safe_Out,
      Status   => Status);

   Log_Suite_Footer;
end Aegis_Spark;
