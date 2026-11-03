pragma Ada_2022;
with Interfaces;   use Interfaces;
with Interfaces.C; use Interfaces.C;

package Halos_Mailbox
   with SPARK_Mode => On
is
   Mailbox_Capacity  : constant := 16;
   Mailbox_Slot_Size : constant := 128;
   Mailbox_Magic     : constant Unsigned_64 := 16#4145_4749_534D_4258#; --  ASCII "AEGISMBX"
   Halos_Dof_Count   : constant := 6;

   type Dof_Index is range 0 .. Halos_Dof_Count - 1;

   type Halos_Msg_Type is
     (Msg_None,
      Msg_Torque_Cmd,
      Msg_Kinematic_Cmd,
      Msg_Heartbeat_Pet,
      Msg_Reset_Fault,
      Msg_Emergency_Stop)
      with Convention => C, Size => 32;

   for Halos_Msg_Type use
     (Msg_None           => 0,
      Msg_Torque_Cmd     => 1,
      Msg_Kinematic_Cmd  => 2,
      Msg_Heartbeat_Pet  => 3,
      Msg_Reset_Fault    => 4,
      Msg_Emergency_Stop => 5);

   type Halos_Mailbox_Status is
     (Mbx_Ok,
      Mbx_Err_Empty,
      Mbx_Err_Full,
      Mbx_Err_Null_Ptr,
      Mbx_Err_Unaligned,
      Mbx_Err_Corrupt_Magic,
      Mbx_Err_Version_Mismatch,
      Mbx_Err_Seq_Gap,
      Mbx_Err_Overrun,
      Mbx_Err_Crc_Mismatch,
      Mbx_Err_Invalid_Payload,
      Mbx_Err_Stale_Timestamp,
      Mbx_Err_Invalid_Msg_Type)
      with Convention => C, Size => 32;

   for Halos_Mailbox_Status use
     (Mbx_Ok                   => 0,
      Mbx_Err_Empty            => 1,
      Mbx_Err_Full             => 2,
      Mbx_Err_Null_Ptr         => 3,
      Mbx_Err_Unaligned        => 4,
      Mbx_Err_Corrupt_Magic    => 5,
      Mbx_Err_Version_Mismatch => 6,
      Mbx_Err_Seq_Gap          => 7,
      Mbx_Err_Overrun          => 8,
      Mbx_Err_Crc_Mismatch     => 9,
      Mbx_Err_Invalid_Payload  => 10,
      Mbx_Err_Stale_Timestamp  => 11,
      Mbx_Err_Invalid_Msg_Type => 12);

   Mbx_Flag_None     : constant Unsigned_32 := 0;
   Mbx_Flag_Valid    : constant Unsigned_32 := 1;
   Mbx_Flag_Ack_Req  : constant Unsigned_32 := 2;
   Mbx_Flag_Degraded : constant Unsigned_32 := 4;
   Mbx_Flag_Estop    : constant Unsigned_32 := 8;

   type Halos_Mailbox_Header is record
      Sequence_Id  : Unsigned_64;
      Timestamp_Ns : Unsigned_64;
      Msg_Type     : Halos_Msg_Type;
      Flags        : Unsigned_32;
      Crc32        : Unsigned_32;
      Reserved     : Unsigned_32;
   end record
      with Convention => C, Size => 256, Alignment => 8;

   for Halos_Mailbox_Header use record
      Sequence_Id  at 0  range 0 .. 63;
      Timestamp_Ns at 8  range 0 .. 63;
      Msg_Type     at 16 range 0 .. 31;
      Flags        at 20 range 0 .. 31;
      Crc32        at 24 range 0 .. 31;
      Reserved     at 28 range 0 .. 31;
   end record;

   subtype Position_Scalar is C_float range -6.283185307 .. 6.283185307;
   subtype Velocity_Scalar is C_float range -50.0 .. 50.0;
   subtype Torque_Scalar is C_float range -500.0 .. 500.0;
   subtype Acceleration_Scalar is C_float range -500.0 .. 500.0;

   type Position_Array is array (Dof_Index) of Position_Scalar with Convention => C;
   type Velocity_Array is array (Dof_Index) of Velocity_Scalar with Convention => C;
   type Torque_Array is array (Dof_Index) of Torque_Scalar with Convention => C;
   type Acceleration_Array is array (Dof_Index) of Acceleration_Scalar with Convention => C;

   type Halos_Trajectory_Payload is record
      Position_Rad        : Position_Array;
      Velocity_Rad_S      : Velocity_Array;
      Torque_Nm           : Torque_Array;
      Acceleration_Rad_S2 : Acceleration_Array;
   end record
      with Convention => C, Size => 768, Alignment => 4;

   for Halos_Trajectory_Payload use record
      Position_Rad        at 0  range 0 .. 191;
      Velocity_Rad_S      at 24 range 0 .. 191;
      Torque_Nm           at 48 range 0 .. 191;
      Acceleration_Rad_S2 at 72 range 0 .. 191;
   end record;

   type Halos_Mailbox_Msg is record
      Header  : Halos_Mailbox_Header;
      Payload : Halos_Trajectory_Payload;
   end record
      with Convention => C, Size => 1024, Alignment => 8;

   for Halos_Mailbox_Msg use record
      Header  at 0  range 0 .. 255;
      Payload at 32 range 0 .. 767;
   end record;

   type Padding_40 is array (1 .. 40) of Unsigned_8 with Convention => C;
   type Padding_32 is array (1 .. 32) of Unsigned_8 with Convention => C;
   type Padding_24 is array (1 .. 24) of Unsigned_8 with Convention => C;
   type Padding_64 is array (1 .. 64) of Unsigned_8 with Convention => C;

   type Aegis_Mailbox_Config is record
      Magic      : Unsigned_64;
      Version    : Unsigned_32;
      Capacity   : Unsigned_32;
      Slot_Size  : Unsigned_32;
      Channel_Id : Unsigned_32;
      Reserved   : Padding_40;
   end record
      with Convention => C, Size => 512, Alignment => 64;

   for Aegis_Mailbox_Config use record
      Magic      at 0  range 0 .. 63;
      Version    at 8  range 0 .. 31;
      Capacity   at 12 range 0 .. 31;
      Slot_Size  at 16 range 0 .. 31;
      Channel_Id at 20 range 0 .. 31;
      Reserved   at 24 range 0 .. 319;
   end record;

   subtype Atomic_U64 is Unsigned_64;

   type Aegis_Mailbox_Producer is record
      Tail        : Atomic_U64;
      Cached_Head : Unsigned_64;
      Push_Count  : Unsigned_64;
      Full_Drops  : Unsigned_64;
      Reserved    : Padding_32;
   end record
      with Convention => C, Size => 512, Alignment => 64;

   for Aegis_Mailbox_Producer use record
      Tail        at 0  range 0 .. 63;
      Cached_Head at 8  range 0 .. 63;
      Push_Count  at 16 range 0 .. 63;
      Full_Drops  at 24 range 0 .. 63;
      Reserved    at 32 range 0 .. 255;
   end record;

   type Aegis_Mailbox_Consumer is record
      Head        : Atomic_U64;
      Cached_Tail : Unsigned_64;
      Pop_Count   : Unsigned_64;
      Crc_Errors  : Unsigned_64;
      Seq_Gaps    : Unsigned_64;
      Reserved    : Padding_24;
   end record
      with Convention => C, Size => 512, Alignment => 64;

   for Aegis_Mailbox_Consumer use record
      Head        at 0  range 0 .. 63;
      Cached_Tail at 8  range 0 .. 63;
      Pop_Count   at 16 range 0 .. 63;
      Crc_Errors  at 24 range 0 .. 63;
      Seq_Gaps    at 32 range 0 .. 63;
      Reserved    at 40 range 0 .. 191;
   end record;

   type Slot_Index is range 0 .. Mailbox_Capacity - 1;
   type Slot_Array is array (Slot_Index) of Halos_Mailbox_Msg with Convention => C;

   type Aegis_Mailbox_Channel is record
      Config        : Aegis_Mailbox_Config;
      Producer      : Aegis_Mailbox_Producer;
      Consumer      : Aegis_Mailbox_Consumer;
      Reserved_Line : Padding_64;
      Slots         : Slot_Array;
   end record
      with Convention => C, Size => 18432, Alignment => 64;

   for Aegis_Mailbox_Channel use record
      Config        at 0   range 0 .. 511;
      Producer      at 64  range 0 .. 511;
      Consumer      at 128 range 0 .. 511;
      Reserved_Line at 192 range 0 .. 511;
      Slots         at 256 range 0 .. 16383;
   end record;

   function Calculate_Crc32 (Payload : Halos_Trajectory_Payload) return Unsigned_32
      with Global => null;

   function Validate_Payload_Floats (Payload : Halos_Trajectory_Payload) return Boolean
      with Global => null;

   --  Consumer Pop Operation (Gold-proved)
   procedure Try_Pop
     (Chan    : in out Aegis_Mailbox_Channel;
      Now_Ns  :        Unsigned_64;
      Msg_Out :    out Halos_Mailbox_Msg;
      Status  :    out Halos_Mailbox_Status)
      with Export        => True,
           Convention    => C,
           External_Name => "halos_mailbox_try_pop",
           Global        => null,
           Always_Terminates;

end Halos_Mailbox;
