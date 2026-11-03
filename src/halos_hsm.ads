pragma Ada_2022;
with Interfaces; use Interfaces;

package Halos_HSM
   with SPARK_Mode => On
is
   Halos_Hsm_Reset_Magic : constant Unsigned_32 := 16#4853_4D52#; --  ASCII "HSMR"

   type Halos_Hsm_State is
     (State_Boot,
      State_Active,
      State_Degraded,
      State_Fault_Estop)
      with Convention => C, Size => 32;

   for Halos_Hsm_State use
     (State_Boot        => 0,
      State_Active      => 1,
      State_Degraded    => 2,
      State_Fault_Estop => 3);

   type Halos_Hsm_Event is
     (Event_None,
      Event_Self_Test_Passed,
      Event_Self_Test_Failed,
      Event_Degrade_Requested,
      Event_Recover_Nominal,
      Event_Fault_Detected,
      Event_Reset_Requested)
      with Convention => C, Size => 32;

   for Halos_Hsm_Event use
     (Event_None              => 0,
      Event_Self_Test_Passed  => 1,
      Event_Self_Test_Failed  => 2,
      Event_Degrade_Requested => 3,
      Event_Recover_Nominal   => 4,
      Event_Fault_Detected    => 5,
      Event_Reset_Requested   => 6);

   type Halos_Fault_Code is
     (Fault_None,
      Fault_Watchdog_Timeout,
      Fault_Watchdog_Early_Pet,
      Fault_Watchdog_Clock_Rewind,
      Fault_Kinematic_Position,
      Fault_Kinematic_Velocity,
      Fault_Kinematic_Torque,
      Fault_Kinematic_Jerk,
      Fault_Non_Finite_Input,
      Fault_Hardware_Bist)
      with Convention => C, Size => 32;

   for Halos_Fault_Code use
     (Fault_None                  => 0,
      Fault_Watchdog_Timeout      => 1,
      Fault_Watchdog_Early_Pet    => 2,
      Fault_Watchdog_Clock_Rewind => 3,
      Fault_Kinematic_Position    => 4,
      Fault_Kinematic_Velocity    => 5,
      Fault_Kinematic_Torque      => 6,
      Fault_Kinematic_Jerk        => 7,
      Fault_Non_Finite_Input      => 8,
      Fault_Hardware_Bist         => 9);

   type Halos_Hsm_Status is
     (HSM_Ok,
      HSM_Err_Invalid_Transition,
      HSM_Err_Invalid_Key,
      HSM_Err_Already_In_State)
      with Convention => C, Size => 32;

   for Halos_Hsm_Status use
     (HSM_Ok                     => 0,
      HSM_Err_Invalid_Transition => 1,
      HSM_Err_Invalid_Key        => 2,
      HSM_Err_Already_In_State   => 3);

   type Halos_HSM_Instance is record
      State            : Halos_Hsm_State;
      Last_Fault_Code  : Halos_Fault_Code;
      Transition_Count : Unsigned_64;
   end record
      with Convention => C, Size => 128, Alignment => 8;

   for Halos_HSM_Instance use record
      State            at 0 range 0 .. 31;
      Last_Fault_Code  at 4 range 0 .. 31;
      Transition_Count at 8 range 0 .. 63;
   end record;

   procedure Init
     (HSM : out Halos_HSM_Instance)
      with Export        => True,
           Convention    => C,
           External_Name => "halos_hsm_init",
           Global        => null,
           Always_Terminates,
           Post          =>
             HSM.State = State_Boot
             and then HSM.Last_Fault_Code = Fault_None
             and then HSM.Transition_Count = 0;

   procedure Process_Event
     (HSM        : in out Halos_HSM_Instance;
      Event      :        Halos_Hsm_Event;
      Fault_Code :        Halos_Fault_Code;
      Status     :    out Halos_Hsm_Status)
      with Export        => True,
           Convention    => C,
           External_Name => "halos_hsm_process_event",
           Global        => null,
           Always_Terminates,
           Contract_Cases =>
             (Event = Event_Fault_Detected and then HSM.State /= State_Fault_Estop =>
                HSM.State = State_Fault_Estop
                and then HSM.Last_Fault_Code = Fault_Code
                and then HSM.Transition_Count = HSM'Old.Transition_Count + 1
                and then Status = HSM_Ok,

              (HSM.State = State_Boot and then Event = Event_Self_Test_Passed) =>
                HSM.State = State_Active
                and then HSM.Last_Fault_Code = Fault_None
                and then HSM.Transition_Count = HSM'Old.Transition_Count + 1
                and then Status = HSM_Ok,

              (HSM.State = State_Boot and then Event = Event_Self_Test_Failed) =>
                HSM.State = State_Fault_Estop
                and then HSM.Last_Fault_Code = Fault_Hardware_Bist
                and then HSM.Transition_Count = HSM'Old.Transition_Count + 1
                and then Status = HSM_Ok,

              (HSM.State = State_Active and then Event = Event_Degrade_Requested) =>
                HSM.State = State_Degraded
                and then HSM.Last_Fault_Code = HSM'Old.Last_Fault_Code
                and then HSM.Transition_Count = HSM'Old.Transition_Count + 1
                and then Status = HSM_Ok,

              (HSM.State = State_Degraded and then Event = Event_Recover_Nominal) =>
                HSM.State = State_Active
                and then HSM.Last_Fault_Code = HSM'Old.Last_Fault_Code
                and then HSM.Transition_Count = HSM'Old.Transition_Count + 1
                and then Status = HSM_Ok,

              HSM.State = State_Fault_Estop =>
                HSM = HSM'Old
                and then Status = HSM_Err_Invalid_Transition,

              others =>
                HSM = HSM'Old
                and then Status = HSM_Err_Invalid_Transition);

   procedure Trigger_Reset
     (HSM       : in out Halos_HSM_Instance;
      Reset_Key :        Unsigned_32;
      Status    :    out Halos_Hsm_Status)
      with Export        => True,
           Convention    => C,
           External_Name => "halos_hsm_trigger_reset",
           Global        => null,
           Always_Terminates,
           Contract_Cases =>
             (HSM.State = State_Fault_Estop and then Reset_Key = Halos_Hsm_Reset_Magic =>
                HSM.State = State_Boot
                and then HSM.Last_Fault_Code = Fault_None
                and then HSM.Transition_Count = HSM'Old.Transition_Count + 1
                and then Status = HSM_Ok,

              HSM.State = State_Fault_Estop and then Reset_Key /= Halos_Hsm_Reset_Magic =>
                HSM = HSM'Old
                and then Status = HSM_Err_Invalid_Key,

              others =>
                HSM = HSM'Old
                and then Status = HSM_Err_Invalid_Transition);

end Halos_HSM;
