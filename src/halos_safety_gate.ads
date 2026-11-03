pragma Ada_2022;
with Interfaces;       use Interfaces;
with Interfaces.C;     use Interfaces.C;
with Halos_Watchdog;   use Halos_Watchdog;
with Halos_HSM;        use Halos_HSM;
with Halos_Kinematics; use Halos_Kinematics;

package Halos_Safety_Gate
   with SPARK_Mode => On
is
   Halos_Dof_Count      : constant := 6;
   Halos_Max_Cmd_Age_Ns : constant Unsigned_64 := 5_000_000; --  5 ms watchdog

   type Dof_Index is range 0 .. Halos_Dof_Count - 1;

   --  Constrained finite torque subtype (statically excludes NaN and +/-Inf)
   Max_Hardware_Torque_Nm : constant := 500.0;
   subtype Safe_Torque_Scalar is
      C_float range -Max_Hardware_Torque_Nm .. Max_Hardware_Torque_Nm;
   subtype Non_Negative_Torque is
      C_float range 0.0 .. Max_Hardware_Torque_Nm;

   type Safe_Torque_Array is array (Dof_Index) of Safe_Torque_Scalar
      with Convention => C;

   type Torque_Limit_Array is array (Dof_Index) of Non_Negative_Torque
      with Convention => C;

   type Halos_Status is
     (Halos_Ok,
      Halos_Err_Not_Active,
      Halos_Err_Stale_Heartbeat,
      Halos_Err_Non_Finite_Input,
      Halos_Err_Torque_Limit_Exceeded)
      with Convention => C, Size => 32;

   for Halos_Status use
     (Halos_Ok                        => 0,
      Halos_Err_Not_Active            => 1,
      Halos_Err_Stale_Heartbeat       => 2,
      Halos_Err_Non_Finite_Input      => 3,
      Halos_Err_Torque_Limit_Exceeded => 4);

   pragma Warnings (Off, "the size of enums in C is implementation-defined");
   type Halos_Safety_State is
     (State_Init,
      State_Active,
      State_Fault_Estop)
      with Convention => C, Size => 8;
   pragma Warnings (On, "the size of enums in C is implementation-defined");

   for Halos_Safety_State use
     (State_Init        => 0,
      State_Active      => 1,
      State_Fault_Estop => 2);

   type Halos_Joint_Cmd is record
      Timestamp_Ns      : Unsigned_64;
      Desired_Torque_Nm : Safe_Torque_Array;
   end record
      with Convention => C;

   type Halos_Safety_Envelope is record
      Max_Abs_Torque_Nm : Torque_Limit_Array;
      State             : Halos_Safety_State;
   end record
      with Convention => C;

   --  Composed Safety Gate integrating Watchdog, HSM, and Kinematics (Phase 4)
   type Halos_Composed_Gate is record
      Watchdog   : Halos_Watchdog.Halos_Watchdog_Device;
      HSM        : Halos_HSM.Halos_HSM_Instance;
      Kinematics : Halos_Kinematics.Halos_Kinematic_State;
   end record
      with Convention => C;

   --  Ghost helper predicates for readable Gold-level contracts
   function Is_Zero_Torque (T : Safe_Torque_Array) return Boolean is
     (for all I in Dof_Index => T (I) = 0.0)
      with Ghost;

   function Heartbeat_Is_Fresh
     (Cmd_Time_Ns : Unsigned_64;
      Now_Ns      : Unsigned_64) return Boolean
   is
     (Now_Ns >= Cmd_Time_Ns
      and then Now_Ns - Cmd_Time_Ns <= Halos_Max_Cmd_Age_Ns)
      with Ghost;

   function Torques_Within_Envelope
     (Desired : Safe_Torque_Array;
      Limits  : Torque_Limit_Array) return Boolean
   is
     (for all I in Dof_Index => abs (Desired (I)) <= Limits (I))
      with Ghost;

   --  Gold-proved legacy safety command interceptor exported to C23 / C++23
   procedure Intercept_Joint_Cmd
     (Env             : in out Halos_Safety_Envelope;
      Cmd_In          :        Halos_Joint_Cmd;
      Now_Ns          :        Unsigned_64;
      Safe_Torque_Out :    out Safe_Torque_Array;
      Status          :    out Halos_Status)
      with Export        => True,
           Convention    => C,
           External_Name => "halos_spark_intercept_joint_cmd",
           Global        => null,
           Always_Terminates,
           Post          =>
             (Env.Max_Abs_Torque_Nm = Env'Old.Max_Abs_Torque_Nm)
             and then
             (if Status = Halos_Ok then
                Env.State = State_Active
                and then Env'Old.State = State_Active
                and then Heartbeat_Is_Fresh (Cmd_In.Timestamp_Ns, Now_Ns)
                and then Safe_Torque_Out = Cmd_In.Desired_Torque_Nm
                and then Torques_Within_Envelope
                           (Safe_Torque_Out, Env.Max_Abs_Torque_Nm)
              else
                Is_Zero_Torque (Safe_Torque_Out)
                and then (if Env'Old.State = State_Active then
                            Env.State = State_Fault_Estop
                          else
                            Env.State = Env'Old.State));

   --  Composed Phase 4 Gate Initialization
   procedure Init_Composed_Gate
     (Gate     : out Halos_Composed_Gate;
      Start_Ns :     Unsigned_64)
      with Export        => True,
           Convention    => C,
           External_Name => "halos_composed_gate_init",
           Global        => null,
           Always_Terminates,
           Post          =>
             Gate.Watchdog.State = WD_Armed
             and then Gate.HSM.State = State_Boot
             and then Gate.Kinematics.HSM.State = State_Boot;

   --  Composed Phase 4 Command Interceptor
   procedure Intercept_Composed_Cmd
     (Gate            : in out Halos_Composed_Gate;
      Cmd_In          :        Halos_Kinematics.Halos_Kinematic_Cmd;
      Now_Ns          :        Unsigned_64;
      Safe_Torque_Out :    out Halos_Kinematics.Torque_Array;
      Safe_Vel_Out    :    out Halos_Kinematics.Velocity_Array;
      Status          :    out Halos_HSM.Halos_Hsm_Status)
      with Export        => True,
           Convention    => C,
           External_Name => "halos_composed_gate_intercept_cmd",
           Global        => null,
           Always_Terminates,
           Post          =>
             (if Status = HSM_Ok then
                Gate.HSM.State in State_Active | State_Degraded
                and then Safe_Torque_Out = Cmd_In.Torque_Nm
                and then Safe_Vel_Out = Cmd_In.Velocity_Rad
              else
                Halos_Kinematics.Is_Zero_Torque (Safe_Torque_Out)
                and then Halos_Kinematics.Is_Zero_Velocity (Safe_Vel_Out));

end Halos_Safety_Gate;
