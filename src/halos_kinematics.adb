pragma Ada_2022;

package body Halos_Kinematics
   with SPARK_Mode => On
is

   procedure Init
     (State : out Halos_Kinematic_State)
   is
   begin
      State :=
        (Last_Cmd =>
           (Timestamp_Ns => 0,
            Position_Rad => [others => 0.0],
            Velocity_Rad => [others => 0.0],
            Torque_Nm    => [others => 0.0]),
         Limits   =>
           (Max_Abs_Position_Rad  => [others => 3.14159265],
            Max_Abs_Velocity_Rad  => [others => 10.0],
            Max_Abs_Torque_Nm     => [others => 50.0],
            Max_Delta_Torque_Step => [others => 25.0]),
         HSM      =>
           (State            => State_Boot,
            Last_Fault_Code  => Fault_None,
            Transition_Count => 0));
   end Init;

   procedure Intercept_Kinematic_Cmd
     (State           : in out Halos_Kinematic_State;
      Cmd_In          :        Halos_Kinematic_Cmd;
      Safe_Torque_Out :    out Torque_Array;
      Safe_Vel_Out    :    out Velocity_Array;
      Status          :    out Halos_Hsm_Status)
   is
   begin
      Safe_Torque_Out := [others => 0.0];
      Safe_Vel_Out    := [others => 0.0];

      if State.HSM.State /= State_Active
        and then State.HSM.State /= State_Degraded
      then
         Status := HSM_Err_Invalid_Transition;
         return;
      end if;

      for I in Dof_Index loop
         pragma Warnings
           (GNATprove, Off,
            "attribute ""Valid"" is assumed to return True",
            Reason => "Defensive runtime check at C23/DMA boundary");
         if not Cmd_In.Position_Rad (I)'Valid
           or else not Cmd_In.Velocity_Rad (I)'Valid
           or else not Cmd_In.Torque_Nm (I)'Valid
         then
            State.HSM.State            := State_Fault_Estop;
            State.HSM.Last_Fault_Code  := Fault_Non_Finite_Input;
            State.HSM.Transition_Count := State.HSM.Transition_Count + 1;
            Safe_Torque_Out            := [others => 0.0];
            Safe_Vel_Out               := [others => 0.0];
            Status                     := HSM_Err_Invalid_Transition;
            return;
         end if;
         pragma Warnings
           (GNATprove, On,
            "attribute ""Valid"" is assumed to return True");

         if abs (Cmd_In.Position_Rad (I)) > State.Limits.Max_Abs_Position_Rad (I) then
            State.HSM.State            := State_Fault_Estop;
            State.HSM.Last_Fault_Code  := Fault_Kinematic_Position;
            State.HSM.Transition_Count := State.HSM.Transition_Count + 1;
            Safe_Torque_Out            := [others => 0.0];
            Safe_Vel_Out               := [others => 0.0];
            Status                     := HSM_Err_Invalid_Transition;
            return;
         end if;

         if abs (Cmd_In.Velocity_Rad (I)) > State.Limits.Max_Abs_Velocity_Rad (I) then
            State.HSM.State            := State_Fault_Estop;
            State.HSM.Last_Fault_Code  := Fault_Kinematic_Velocity;
            State.HSM.Transition_Count := State.HSM.Transition_Count + 1;
            Safe_Torque_Out            := [others => 0.0];
            Safe_Vel_Out               := [others => 0.0];
            Status                     := HSM_Err_Invalid_Transition;
            return;
         end if;

         if abs (Cmd_In.Torque_Nm (I)) > State.Limits.Max_Abs_Torque_Nm (I) then
            State.HSM.State            := State_Fault_Estop;
            State.HSM.Last_Fault_Code  := Fault_Kinematic_Torque;
            State.HSM.Transition_Count := State.HSM.Transition_Count + 1;
            Safe_Torque_Out            := [others => 0.0];
            Safe_Vel_Out               := [others => 0.0];
            Status                     := HSM_Err_Invalid_Transition;
            return;
         end if;

         if abs (Cmd_In.Torque_Nm (I) - State.Last_Cmd.Torque_Nm (I)) >
            State.Limits.Max_Delta_Torque_Step (I)
         then
            State.HSM.State            := State_Fault_Estop;
            State.HSM.Last_Fault_Code  := Fault_Kinematic_Jerk;
            State.HSM.Transition_Count := State.HSM.Transition_Count + 1;
            Safe_Torque_Out            := [others => 0.0];
            Safe_Vel_Out               := [others => 0.0];
            Status                     := HSM_Err_Invalid_Transition;
            return;
         end if;

         pragma Loop_Invariant
           ((State.HSM.State in State_Active | State_Degraded)
            and then State.HSM = State'Loop_Entry.HSM
            and then State.Limits = State'Loop_Entry.Limits
            and then State.Last_Cmd = State'Loop_Entry.Last_Cmd
            and then
            (for all K in Dof_Index'First .. I =>
               abs (Cmd_In.Position_Rad (K)) <= State.Limits.Max_Abs_Position_Rad (K)
               and then abs (Cmd_In.Velocity_Rad (K)) <= State.Limits.Max_Abs_Velocity_Rad (K)
               and then abs (Cmd_In.Torque_Nm (K)) <= State.Limits.Max_Abs_Torque_Nm (K)
               and then abs (Cmd_In.Torque_Nm (K) - State.Last_Cmd.Torque_Nm (K)) <=
                        State.Limits.Max_Delta_Torque_Step (K)));
      end loop;

      Safe_Torque_Out := Cmd_In.Torque_Nm;
      Safe_Vel_Out    := Cmd_In.Velocity_Rad;
      State.Last_Cmd  := Cmd_In;
      Status          := HSM_Ok;
   end Intercept_Kinematic_Cmd;

end Halos_Kinematics;
