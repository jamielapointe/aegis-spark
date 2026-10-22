pragma Ada_2022;

package body Halos_Safety_Gate
   with SPARK_Mode => On
is

   procedure Intercept_Joint_Cmd
     (Env             : in out Halos_Safety_Envelope;
      Cmd_In          :        Halos_Joint_Cmd;
      Now_Ns          :        Unsigned_64;
      Safe_Torque_Out :    out Safe_Torque_Array;
      Status          :    out Halos_Status)
   is
   begin
      Safe_Torque_Out := [others => 0.0];

      if Env.State /= State_Active then
         Status := Halos_Err_Not_Active;
         return;
      end if;

      if Now_Ns < Cmd_In.Timestamp_Ns
        or else (Now_Ns - Cmd_In.Timestamp_Ns) > Halos_Max_Cmd_Age_Ns
      then
         Env.State := State_Fault_Estop;
         Status    := Halos_Err_Stale_Heartbeat;
         return;
      end if;

      for I in Dof_Index loop
         --  'Valid checks IEEE-754 finiteness and [-500.0 .. 500.0] bounds at runtime
         pragma Warnings
           (GNATprove, Off,
            "attribute ""Valid"" is assumed to return True",
            Reason => "Defensive runtime check at C23/DMA FFI boundary");
         if not Cmd_In.Desired_Torque_Nm (I)'Valid then
            Env.State       := State_Fault_Estop;
            Safe_Torque_Out := [others => 0.0];
            Status          := Halos_Err_Non_Finite_Input;
            return;
         end if;
         pragma Warnings
           (GNATprove, On,
            "attribute ""Valid"" is assumed to return True");

         declare
            Req : constant Safe_Torque_Scalar := Cmd_In.Desired_Torque_Nm (I);
         begin
            if abs (Req) > Env.Max_Abs_Torque_Nm (I) then
               Env.State       := State_Fault_Estop;
               Safe_Torque_Out := [others => 0.0];
               Status          := Halos_Err_Torque_Limit_Exceeded;
               return;
            end if;

            Safe_Torque_Out (I) := Req;
         end;

         pragma Loop_Invariant
           (Env.State = State_Active
            and then Env.Max_Abs_Torque_Nm = Env'Loop_Entry.Max_Abs_Torque_Nm
            and then
            (for all K in Dof_Index'First .. I =>
               Safe_Torque_Out (K) = Cmd_In.Desired_Torque_Nm (K)
               and then abs (Safe_Torque_Out (K)) <= Env.Max_Abs_Torque_Nm (K)));
      end loop;

      Status := Halos_Ok;
   end Intercept_Joint_Cmd;

end Halos_Safety_Gate;
