pragma Ada_2022;
with Interfaces; use Interfaces;

package Halos_Watchdog
   with SPARK_Mode => On
is
   Halos_Wd_Min_Interval_Ns : constant Unsigned_64 := 500_000;   --  0.5 ms
   Halos_Wd_Max_Deadline_Ns : constant Unsigned_64 := 5_000_000; --  5.0 ms
   Halos_Wd_Reset_Magic     : constant Unsigned_32 := 16#5744_4752#; --  ASCII "WDGR"

   type Halos_Watchdog_State is
     (WD_Disabled,
      WD_Armed,
      WD_Fault_Early,
      WD_Fault_Late,
      WD_Fault_Clock)
      with Convention => C, Size => 32;

   for Halos_Watchdog_State use
     (WD_Disabled    => 0,
      WD_Armed       => 1,
      WD_Fault_Early => 2,
      WD_Fault_Late  => 3,
      WD_Fault_Clock => 4);

   type Halos_Watchdog_Status is
     (WD_Ok,
      WD_Err_Not_Armed,
      WD_Err_Too_Early,
      WD_Err_Too_Late,
      WD_Err_Time_Rewind,
      WD_Err_Invalid_Config,
      WD_Err_Invalid_Key)
      with Convention => C, Size => 32;

   for Halos_Watchdog_Status use
     (WD_Ok                 => 0,
      WD_Err_Not_Armed      => 1,
      WD_Err_Too_Early      => 2,
      WD_Err_Too_Late       => 3,
      WD_Err_Time_Rewind    => 4,
      WD_Err_Invalid_Config => 5,
      WD_Err_Invalid_Key    => 6);

   type Halos_Watchdog_Config is record
      Min_Interval_Ns : Unsigned_64;
      Max_Interval_Ns : Unsigned_64;
   end record
      with Convention => C, Size => 128, Alignment => 8;

   for Halos_Watchdog_Config use record
      Min_Interval_Ns at 0 range 0 .. 63;
      Max_Interval_Ns at 8 range 0 .. 63;
   end record;

   type Halos_Watchdog_Device is record
      Config       : Halos_Watchdog_Config;
      Last_Pet_Ns  : Unsigned_64;
      Pet_Count    : Unsigned_64;
      State        : Halos_Watchdog_State;
      Reserved_Pad : Unsigned_32;
   end record
      with Convention => C, Size => 320, Alignment => 8;

   for Halos_Watchdog_Device use record
      Config       at 0  range 0 .. 127;
      Last_Pet_Ns  at 16 range 0 .. 63;
      Pet_Count    at 24 range 0 .. 63;
      State        at 32 range 0 .. 31;
      Reserved_Pad at 36 range 0 .. 31;
   end record;

   function Valid_Config (Cfg : Halos_Watchdog_Config) return Boolean is
     (Cfg.Min_Interval_Ns < Cfg.Max_Interval_Ns
      and then Cfg.Max_Interval_Ns <= Halos_Wd_Max_Deadline_Ns);

   function In_Fault (WD : Halos_Watchdog_Device) return Boolean is
     (WD.State in WD_Fault_Early | WD_Fault_Late | WD_Fault_Clock)
      with Ghost;

   procedure Init
     (WD : out Halos_Watchdog_Device)
      with Export        => True,
           Convention    => C,
           External_Name => "halos_watchdog_init",
           Global        => null,
           Always_Terminates,
           Post          =>
             WD.State = WD_Disabled
             and then WD.Last_Pet_Ns = 0
             and then WD.Pet_Count = 0
             and then WD.Reserved_Pad = 0
             and then WD.Config.Min_Interval_Ns = Halos_Wd_Min_Interval_Ns
             and then WD.Config.Max_Interval_Ns = Halos_Wd_Max_Deadline_Ns;

   procedure Arm
     (WD       : in out Halos_Watchdog_Device;
      Config   :        Halos_Watchdog_Config;
      Start_Ns :        Unsigned_64;
      Status   :    out Halos_Watchdog_Status)
      with Export        => True,
           Convention    => C,
           External_Name => "halos_watchdog_arm",
           Global        => null,
           Always_Terminates,
           Contract_Cases =>
             (Valid_Config (Config) =>
                WD.State = WD_Armed
                and then WD.Config = Config
                and then WD.Last_Pet_Ns = Start_Ns
                and then WD.Pet_Count = 0
                and then WD.Reserved_Pad = 0
                and then Status = WD_Ok,
              others =>
                WD = WD'Old
                and then Status = WD_Err_Invalid_Config);

   procedure Pet
     (WD     : in out Halos_Watchdog_Device;
      Now_Ns :        Unsigned_64;
      Status :    out Halos_Watchdog_Status)
      with Export        => True,
           Convention    => C,
           External_Name => "halos_watchdog_pet",
           Global        => null,
           Always_Terminates,
           Contract_Cases =>
             (WD.State /= WD_Armed =>
                Status = WD_Err_Not_Armed
                and then WD = WD'Old,

              WD.State = WD_Armed and then Now_Ns < WD.Last_Pet_Ns =>
                Status = WD_Err_Time_Rewind
                and then WD.State = WD_Fault_Clock
                and then WD.Config = WD'Old.Config
                and then WD.Last_Pet_Ns = WD'Old.Last_Pet_Ns
                and then WD.Pet_Count = WD'Old.Pet_Count
                and then WD.Reserved_Pad = WD'Old.Reserved_Pad,

              WD.State = WD_Armed
              and then Now_Ns >= WD.Last_Pet_Ns
              and then (Now_Ns - WD.Last_Pet_Ns) < WD.Config.Min_Interval_Ns =>
                Status = WD_Err_Too_Early
                and then WD.State = WD_Fault_Early
                and then WD.Config = WD'Old.Config
                and then WD.Last_Pet_Ns = WD'Old.Last_Pet_Ns
                and then WD.Pet_Count = WD'Old.Pet_Count
                and then WD.Reserved_Pad = WD'Old.Reserved_Pad,

              WD.State = WD_Armed
              and then Now_Ns >= WD.Last_Pet_Ns
              and then (Now_Ns - WD.Last_Pet_Ns) >= WD.Config.Min_Interval_Ns
              and then (Now_Ns - WD.Last_Pet_Ns) > WD.Config.Max_Interval_Ns =>
                Status = WD_Err_Too_Late
                and then WD.State = WD_Fault_Late
                and then WD.Config = WD'Old.Config
                and then WD.Last_Pet_Ns = WD'Old.Last_Pet_Ns
                and then WD.Pet_Count = WD'Old.Pet_Count
                and then WD.Reserved_Pad = WD'Old.Reserved_Pad,

              others =>
                Status = WD_Ok
                and then WD.State = WD_Armed
                and then WD.Config = WD'Old.Config
                and then WD.Last_Pet_Ns = Now_Ns
                and then WD.Pet_Count = WD'Old.Pet_Count + 1
                and then WD.Reserved_Pad = WD'Old.Reserved_Pad);

   procedure Check_Deadline
     (WD     : in out Halos_Watchdog_Device;
      Now_Ns :        Unsigned_64;
      Status :    out Halos_Watchdog_Status)
      with Export        => True,
           Convention    => C,
           External_Name => "halos_watchdog_check_deadline",
           Global        => null,
           Always_Terminates,
           Contract_Cases =>
             (WD.State /= WD_Armed =>
                Status = WD_Err_Not_Armed
                and then WD = WD'Old,

              WD.State = WD_Armed and then Now_Ns < WD.Last_Pet_Ns =>
                Status = WD_Err_Time_Rewind
                and then WD.State = WD_Fault_Clock
                and then WD.Config = WD'Old.Config
                and then WD.Last_Pet_Ns = WD'Old.Last_Pet_Ns
                and then WD.Pet_Count = WD'Old.Pet_Count
                and then WD.Reserved_Pad = WD'Old.Reserved_Pad,

              WD.State = WD_Armed
              and then Now_Ns >= WD.Last_Pet_Ns
              and then (Now_Ns - WD.Last_Pet_Ns) > WD.Config.Max_Interval_Ns =>
                Status = WD_Err_Too_Late
                and then WD.State = WD_Fault_Late
                and then WD.Config = WD'Old.Config
                and then WD.Last_Pet_Ns = WD'Old.Last_Pet_Ns
                and then WD.Pet_Count = WD'Old.Pet_Count
                and then WD.Reserved_Pad = WD'Old.Reserved_Pad,

              others =>
                Status = WD_Ok
                and then WD = WD'Old);

   procedure Reset
     (WD        : in out Halos_Watchdog_Device;
      Reset_Key :        Unsigned_32;
      Now_Ns    :        Unsigned_64;
      Status    :    out Halos_Watchdog_Status)
      with Export        => True,
           Convention    => C,
           External_Name => "halos_watchdog_reset",
           Global        => null,
           Always_Terminates,
           Contract_Cases =>
             (Reset_Key = Halos_Wd_Reset_Magic =>
                WD.State = WD_Armed
                and then WD.Config = WD'Old.Config
                and then WD.Last_Pet_Ns = Now_Ns
                and then WD.Pet_Count = 0
                and then WD.Reserved_Pad = 0
                and then Status = WD_Ok,
              others =>
                WD = WD'Old
                and then Status = WD_Err_Invalid_Key);

end Halos_Watchdog;
