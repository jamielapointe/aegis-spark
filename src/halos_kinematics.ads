pragma Ada_2022;
with Interfaces;   use Interfaces;
with Interfaces.C; use Interfaces.C;
with Halos_HSM;    use Halos_HSM;

package Halos_Kinematics
   with SPARK_Mode => On
is
   Halos_Dof_Count : constant := 6;
   type Dof_Index is range 0 .. Halos_Dof_Count - 1;

   --  Constrained finite subtypes statically excluding NaN and +/-Inf
   subtype Position_Scalar is C_float range -6.283185307 .. 6.283185307;
   subtype Velocity_Scalar is C_float range -50.0 .. 50.0;
   subtype Torque_Scalar   is C_float range -500.0 .. 500.0;

   --  Non-negative limit subtypes
   subtype Non_Neg_Position is C_float range 0.0 .. 6.283185307;
   subtype Non_Neg_Velocity is C_float range 0.0 .. 50.0;
   subtype Non_Neg_Torque   is C_float range 0.0 .. 500.0;
   subtype Non_Neg_Jerk     is C_float range 0.0 .. 500.0;

   type Position_Array is array (Dof_Index) of Position_Scalar
      with Convention => C;
   type Velocity_Array is array (Dof_Index) of Velocity_Scalar
      with Convention => C;
   type Torque_Array   is array (Dof_Index) of Torque_Scalar
      with Convention => C;

   type Position_Limit_Array is array (Dof_Index) of Non_Neg_Position
      with Convention => C;
   type Velocity_Limit_Array is array (Dof_Index) of Non_Neg_Velocity
      with Convention => C;
   type Torque_Limit_Array   is array (Dof_Index) of Non_Neg_Torque
      with Convention => C;
   type Jerk_Limit_Array     is array (Dof_Index) of Non_Neg_Jerk
      with Convention => C;

   type Halos_Kinematic_Limits is record
      Max_Abs_Position_Rad  : Position_Limit_Array;
      Max_Abs_Velocity_Rad  : Velocity_Limit_Array;
      Max_Abs_Torque_Nm     : Torque_Limit_Array;
      Max_Delta_Torque_Step : Jerk_Limit_Array;
   end record
      with Convention => C, Size => 768, Alignment => 4;

   for Halos_Kinematic_Limits use record
      Max_Abs_Position_Rad  at 0  range 0 .. 191;
      Max_Abs_Velocity_Rad  at 24 range 0 .. 191;
      Max_Abs_Torque_Nm     at 48 range 0 .. 191;
      Max_Delta_Torque_Step at 72 range 0 .. 191;
   end record;

   type Halos_Kinematic_Cmd is record
      Timestamp_Ns : Unsigned_64;
      Position_Rad : Position_Array;
      Velocity_Rad : Velocity_Array;
      Torque_Nm    : Torque_Array;
   end record
      with Convention => C, Size => 640, Alignment => 8;

   for Halos_Kinematic_Cmd use record
      Timestamp_Ns at 0  range 0 .. 63;
      Position_Rad at 8  range 0 .. 191;
      Velocity_Rad at 32 range 0 .. 191;
      Torque_Nm    at 56 range 0 .. 191;
   end record;

   type Halos_Kinematic_State is record
      Last_Cmd : Halos_Kinematic_Cmd;
      Limits   : Halos_Kinematic_Limits;
      HSM      : Halos_HSM.Halos_HSM_Instance;
   end record
      with Convention => C, Size => 1536, Alignment => 8;

   for Halos_Kinematic_State use record
      Last_Cmd at 0   range 0 .. 639;
      Limits   at 80  range 0 .. 767;
      HSM      at 176 range 0 .. 127;
   end record;

   function Is_Zero_Torque (T : Torque_Array) return Boolean is
     (for all I in Dof_Index => T (I) = 0.0);

   function Is_Zero_Velocity (V : Velocity_Array) return Boolean is
     (for all I in Dof_Index => V (I) = 0.0);

   function Within_Kinematic_Envelope
     (Cmd    : Halos_Kinematic_Cmd;
      Last   : Halos_Kinematic_Cmd;
      Limits : Halos_Kinematic_Limits) return Boolean
   is
     (for all I in Dof_Index =>
        abs (Cmd.Position_Rad (I)) <= Limits.Max_Abs_Position_Rad (I)
        and then abs (Cmd.Velocity_Rad (I)) <= Limits.Max_Abs_Velocity_Rad (I)
        and then abs (Cmd.Torque_Nm (I)) <= Limits.Max_Abs_Torque_Nm (I)
        and then abs (Cmd.Torque_Nm (I) - Last.Torque_Nm (I)) <= Limits.Max_Delta_Torque_Step (I))
      with Ghost;

   procedure Init
     (State : out Halos_Kinematic_State)
      with Export        => True,
           Convention    => C,
           External_Name => "halos_kinematics_init",
           Global        => null,
           Always_Terminates,
           Post          =>
             State.HSM.State = State_Boot
             and then State.HSM.Last_Fault_Code = Fault_None
             and then State.HSM.Transition_Count = 0;

   procedure Intercept_Kinematic_Cmd
     (State           : in out Halos_Kinematic_State;
      Cmd_In          :        Halos_Kinematic_Cmd;
      Safe_Torque_Out :    out Torque_Array;
      Safe_Vel_Out    :    out Velocity_Array;
      Status          :    out Halos_Hsm_Status)
      with Export        => True,
           Convention    => C,
           External_Name => "halos_kinematics_intercept_cmd",
           Global        => null,
           Always_Terminates,
           Post          =>
             (State.Limits = State'Old.Limits)
             and then
             (if Status = HSM_Ok then
                State.HSM.State in State_Active | State_Degraded
                and then State'Old.HSM.State in State_Active | State_Degraded
                and then Within_Kinematic_Envelope (Cmd_In, State'Old.Last_Cmd, State.Limits)
                and then Safe_Torque_Out = Cmd_In.Torque_Nm
                and then Safe_Vel_Out = Cmd_In.Velocity_Rad
                and then State.Last_Cmd = Cmd_In
              else
                Is_Zero_Torque (Safe_Torque_Out)
                and then Is_Zero_Velocity (Safe_Vel_Out)
                and then (if State'Old.HSM.State in State_Active | State_Degraded then
                            State.HSM.State = State_Fault_Estop
                          else
                            State.HSM.State = State'Old.HSM.State));

end Halos_Kinematics;
