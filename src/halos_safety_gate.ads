pragma Ada_2022;
with Interfaces;   use Interfaces;
with Interfaces.C; use Interfaces.C;

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

   --  Gold-proved safety command interceptor exported to C23 / C++23
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
             ((Status = Halos_Ok) =
                (Env'Old.State = State_Active
                 and then Heartbeat_Is_Fresh (Cmd_In.Timestamp_Ns, Now_Ns)
                 and then Torques_Within_Envelope
                            (Cmd_In.Desired_Torque_Nm, Env.Max_Abs_Torque_Nm)))
             and then
             (if Status = Halos_Ok then
                Env.State = State_Active
                and then Safe_Torque_Out = Cmd_In.Desired_Torque_Nm
                and then Torques_Within_Envelope
                           (Safe_Torque_Out, Env.Max_Abs_Torque_Nm)
              else
                Is_Zero_Torque (Safe_Torque_Out)
                and then (if Env'Old.State = State_Active then
                            Env.State = State_Fault_Estop
                          else
                            Env.State = Env'Old.State));

end Halos_Safety_Gate;
