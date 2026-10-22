pragma Ada_2022;
with Halos_Safety_Gate; use Halos_Safety_Gate;
with Interfaces;        use Interfaces;

package Halos_Logger
   with SPARK_Mode => On
is
   type Log_Step_Id is new Unsigned_32 range 1 .. 1_000;

   procedure Log_Suite_Header
      with Global => null,
           Always_Terminates;

   procedure Log_Intercept_Step
     (Step_Id  : Log_Step_Id;
      Now_Ns   : Unsigned_64;
      Cmd_In   : Halos_Joint_Cmd;
      Env      : Halos_Safety_Envelope;
      Safe_Out : Safe_Torque_Array;
      Status   : Halos_Status)
      with Global => null,
           Always_Terminates;

   procedure Log_Suite_Footer
      with Global => null,
           Always_Terminates;

end Halos_Logger;
