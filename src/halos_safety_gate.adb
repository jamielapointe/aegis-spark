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

   procedure Init_Composed_Gate
     (Gate     : out Halos_Composed_Gate;
      Start_Ns :     Unsigned_64)
   is
      Wd_Cfg : constant Halos_Watchdog.Halos_Watchdog_Config :=
        (Min_Interval_Ns => Halos_Wd_Min_Interval_Ns,
         Max_Interval_Ns => Halos_Wd_Max_Deadline_Ns);
      Wd_Status : Halos_Watchdog.Halos_Watchdog_Status;
   begin
      Halos_Watchdog.Init (Gate.Watchdog);
      Halos_Watchdog.Arm (Gate.Watchdog, Wd_Cfg, Start_Ns, Wd_Status);
      if Wd_Status /= Halos_Watchdog.WD_Ok then
         Gate.Watchdog.State := Halos_Watchdog.WD_Fault_Clock;
      end if;
      Halos_HSM.Init (Gate.HSM);
      Halos_Kinematics.Init (Gate.Kinematics);
   end Init_Composed_Gate;

   procedure Intercept_Composed_Cmd
     (Gate            : in out Halos_Composed_Gate;
      Cmd_In          :        Halos_Kinematics.Halos_Kinematic_Cmd;
      Now_Ns          :        Unsigned_64;
      Safe_Torque_Out :    out Halos_Kinematics.Torque_Array;
      Safe_Vel_Out    :    out Halos_Kinematics.Velocity_Array;
      Status          :    out Halos_HSM.Halos_Hsm_Status)
   is
      Wd_Status  : Halos_Watchdog.Halos_Watchdog_Status;
      Hsm_Status : Halos_HSM.Halos_Hsm_Status;
   begin
      Safe_Torque_Out := [others => 0.0];
      Safe_Vel_Out    := [others => 0.0];

      --  1. Evaluate windowed watchdog supervision
      Halos_Watchdog.Pet (Gate.Watchdog, Now_Ns, Wd_Status);
      if Wd_Status /= Halos_Watchdog.WD_Ok then
         declare
            Fault : Halos_HSM.Halos_Fault_Code;
         begin
            case Wd_Status is
               when Halos_Watchdog.WD_Err_Too_Early =>
                  Fault := Halos_HSM.Fault_Watchdog_Early_Pet;
               when Halos_Watchdog.WD_Err_Too_Late =>
                  Fault := Halos_HSM.Fault_Watchdog_Timeout;
               when Halos_Watchdog.WD_Err_Time_Rewind =>
                  Fault := Halos_HSM.Fault_Watchdog_Clock_Rewind;
               when others =>
                  Fault := Halos_HSM.Fault_Watchdog_Timeout;
            end case;

            Halos_HSM.Process_Event
              (HSM        => Gate.HSM,
               Event      => Halos_HSM.Event_Fault_Detected,
               Fault_Code => Fault,
               Status     => Hsm_Status);
            Gate.Kinematics.HSM := Gate.HSM;
            if Hsm_Status = Halos_HSM.HSM_Ok then
               Status := Halos_HSM.HSM_Err_Invalid_Transition;
            else
               Status := Hsm_Status;
            end if;
            return;
         end;
      end if;

      --  2. Evaluate 6-DOF kinematic envelope
      Gate.Kinematics.HSM := Gate.HSM;
      Halos_Kinematics.Intercept_Kinematic_Cmd
        (State           => Gate.Kinematics,
         Cmd_In          => Cmd_In,
         Safe_Torque_Out => Safe_Torque_Out,
         Safe_Vel_Out    => Safe_Vel_Out,
         Status          => Status);
      Gate.HSM := Gate.Kinematics.HSM;
   end Intercept_Composed_Cmd;

end Halos_Safety_Gate;
