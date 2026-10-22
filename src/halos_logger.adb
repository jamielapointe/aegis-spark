pragma Ada_2022;

package body Halos_Logger
   with SPARK_Mode => Off
is

   procedure C_Log_Suite_Header
      with Import        => True,
           Convention    => C,
           External_Name => "halos_c_log_suite_header";

   procedure C_Log_Intercept_Step
     (Step_Id  : Unsigned_32;
      Now_Ns   : Unsigned_64;
      Cmd_In   : Halos_Joint_Cmd;
      Env      : Halos_Safety_Envelope;
      Safe_Out : Safe_Torque_Array;
      Status   : Halos_Status)
      with Import        => True,
           Convention    => C,
           External_Name => "halos_c_log_intercept_step";

   procedure C_Log_Suite_Footer
      with Import        => True,
           Convention    => C,
           External_Name => "halos_c_log_suite_footer";

   procedure Log_Suite_Header is
   begin
      C_Log_Suite_Header;
   end Log_Suite_Header;

   procedure Log_Intercept_Step
     (Step_Id  : Log_Step_Id;
      Now_Ns   : Unsigned_64;
      Cmd_In   : Halos_Joint_Cmd;
      Env      : Halos_Safety_Envelope;
      Safe_Out : Safe_Torque_Array;
      Status   : Halos_Status)
   is
   begin
      C_Log_Intercept_Step
        (Step_Id  => Unsigned_32 (Step_Id),
         Now_Ns   => Now_Ns,
         Cmd_In   => Cmd_In,
         Env      => Env,
         Safe_Out => Safe_Out,
         Status   => Status);
   end Log_Intercept_Step;

   procedure Log_Suite_Footer is
   begin
      C_Log_Suite_Footer;
   end Log_Suite_Footer;

end Halos_Logger;
