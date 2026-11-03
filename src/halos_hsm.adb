pragma Ada_2022;

package body Halos_HSM
   with SPARK_Mode => On
is

   procedure Init
     (HSM : out Halos_HSM_Instance)
   is
   begin
      HSM :=
        (State            => State_Boot,
         Last_Fault_Code  => Fault_None,
         Transition_Count => 0);
   end Init;

   procedure Process_Event
     (HSM        : in out Halos_HSM_Instance;
      Event      :        Halos_Hsm_Event;
      Fault_Code :        Halos_Fault_Code;
      Status     :    out Halos_Hsm_Status)
   is
   begin
      if Event = Event_Fault_Detected and then HSM.State /= State_Fault_Estop then
         HSM.State            := State_Fault_Estop;
         HSM.Last_Fault_Code  := Fault_Code;
         HSM.Transition_Count := HSM.Transition_Count + 1;
         Status               := HSM_Ok;
         return;
      end if;

      case HSM.State is
         when State_Boot =>
            if Event = Event_Self_Test_Passed then
               HSM.State            := State_Active;
               HSM.Last_Fault_Code  := Fault_None;
               HSM.Transition_Count := HSM.Transition_Count + 1;
               Status               := HSM_Ok;
            elsif Event = Event_Self_Test_Failed then
               HSM.State            := State_Fault_Estop;
               HSM.Last_Fault_Code  := Fault_Hardware_Bist;
               HSM.Transition_Count := HSM.Transition_Count + 1;
               Status               := HSM_Ok;
            else
               Status := HSM_Err_Invalid_Transition;
            end if;

         when State_Active =>
            if Event = Event_Degrade_Requested then
               HSM.State            := State_Degraded;
               HSM.Transition_Count := HSM.Transition_Count + 1;
               Status               := HSM_Ok;
            else
               Status := HSM_Err_Invalid_Transition;
            end if;

         when State_Degraded =>
            if Event = Event_Recover_Nominal then
               HSM.State            := State_Active;
               HSM.Transition_Count := HSM.Transition_Count + 1;
               Status               := HSM_Ok;
            else
               Status := HSM_Err_Invalid_Transition;
            end if;

         when State_Fault_Estop =>
            Status := HSM_Err_Invalid_Transition;
      end case;
   end Process_Event;

   procedure Trigger_Reset
     (HSM       : in out Halos_HSM_Instance;
      Reset_Key :        Unsigned_32;
      Status    :    out Halos_Hsm_Status)
   is
   begin
      if HSM.State /= State_Fault_Estop then
         Status := HSM_Err_Invalid_Transition;
         return;
      end if;

      if Reset_Key /= Halos_Hsm_Reset_Magic then
         Status := HSM_Err_Invalid_Key;
         return;
      end if;

      HSM.State            := State_Boot;
      HSM.Last_Fault_Code  := Fault_None;
      HSM.Transition_Count := HSM.Transition_Count + 1;
      Status               := HSM_Ok;
   end Trigger_Reset;

end Halos_HSM;
