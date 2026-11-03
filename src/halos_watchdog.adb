pragma Ada_2022;

package body Halos_Watchdog
   with SPARK_Mode => On
is

   procedure Init
     (WD : out Halos_Watchdog_Device)
   is
   begin
      WD :=
        (Config       =>
           (Min_Interval_Ns => Halos_Wd_Min_Interval_Ns,
            Max_Interval_Ns => Halos_Wd_Max_Deadline_Ns),
         Last_Pet_Ns  => 0,
         Pet_Count    => 0,
         State        => WD_Disabled,
         Reserved_Pad => 0);
   end Init;

   procedure Arm
     (WD       : in out Halos_Watchdog_Device;
      Config   :        Halos_Watchdog_Config;
      Start_Ns :        Unsigned_64;
      Status   :    out Halos_Watchdog_Status)
   is
   begin
      if not Valid_Config (Config) then
         Status := WD_Err_Invalid_Config;
         return;
      end if;

      WD.Config       := Config;
      WD.Last_Pet_Ns  := Start_Ns;
      WD.Pet_Count    := 0;
      WD.State        := WD_Armed;
      WD.Reserved_Pad := 0;
      Status          := WD_Ok;
   end Arm;

   procedure Pet
     (WD     : in out Halos_Watchdog_Device;
      Now_Ns :        Unsigned_64;
      Status :    out Halos_Watchdog_Status)
   is
   begin
      if WD.State /= WD_Armed then
         Status := WD_Err_Not_Armed;
         return;
      end if;

      if Now_Ns < WD.Last_Pet_Ns then
         WD.State := WD_Fault_Clock;
         Status   := WD_Err_Time_Rewind;
         return;
      end if;

      declare
         Elapsed : constant Unsigned_64 := Now_Ns - WD.Last_Pet_Ns;
      begin
         if Elapsed < WD.Config.Min_Interval_Ns then
            WD.State := WD_Fault_Early;
            Status   := WD_Err_Too_Early;
            return;
         elsif Elapsed > WD.Config.Max_Interval_Ns then
            WD.State := WD_Fault_Late;
            Status   := WD_Err_Too_Late;
            return;
         end if;
      end;

      WD.Last_Pet_Ns := Now_Ns;
      WD.Pet_Count   := WD.Pet_Count + 1;
      Status         := WD_Ok;
   end Pet;

   procedure Check_Deadline
     (WD     : in out Halos_Watchdog_Device;
      Now_Ns :        Unsigned_64;
      Status :    out Halos_Watchdog_Status)
   is
   begin
      if WD.State /= WD_Armed then
         Status := WD_Err_Not_Armed;
         return;
      end if;

      if Now_Ns < WD.Last_Pet_Ns then
         WD.State := WD_Fault_Clock;
         Status   := WD_Err_Time_Rewind;
         return;
      end if;

      if (Now_Ns - WD.Last_Pet_Ns) > WD.Config.Max_Interval_Ns then
         WD.State := WD_Fault_Late;
         Status   := WD_Err_Too_Late;
         return;
      end if;

      Status := WD_Ok;
   end Check_Deadline;

   procedure Reset
     (WD        : in out Halos_Watchdog_Device;
      Reset_Key :        Unsigned_32;
      Now_Ns    :        Unsigned_64;
      Status    :    out Halos_Watchdog_Status)
   is
   begin
      if Reset_Key /= Halos_Wd_Reset_Magic then
         Status := WD_Err_Invalid_Key;
         return;
      end if;

      WD.Last_Pet_Ns  := Now_Ns;
      WD.Pet_Count    := 0;
      WD.State        := WD_Armed;
      WD.Reserved_Pad := 0;
      Status          := WD_Ok;
   end Reset;

end Halos_Watchdog;
