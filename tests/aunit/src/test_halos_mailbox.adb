with AUnit.Assertions; use AUnit.Assertions;
with Halos_Mailbox;    use Halos_Mailbox;
with Interfaces;       use Interfaces;
with Interfaces.C;     use Interfaces.C;

package body Test_Halos_Mailbox is

   overriding function Name (T : Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Halos.Mailbox.SPSC");
   end Name;

   overriding procedure Register_Tests (T : in out Test_Case) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine (T, Test_Empty_Channel_Pop'Access, "Test Empty Channel Pop Handling");
      Register_Routine
        (T, Test_Corrupt_Magic_Rejection'Access, "Test Corrupt Channel Magic Rejection");
      Register_Routine (T, Test_CRC32_Calculation'Access, "Test CRC32 Calculation Determinism");
      Register_Routine (T, Test_Valid_Push_And_Pop'Access, "Test Message Push and Pop Integrity");
      Register_Routine (T, Test_Sequence_Gap_Detection'Access, "Test Sequence Gap Detection");
      Register_Routine (T, Test_Stale_Timestamp_Rejection'Access, "Test Stale Timestamp Rejection");
   end Register_Tests;

   procedure Init_Test_Channel (Chan : out Aegis_Mailbox_Channel) is
   begin
      Chan :=
        (Config        =>
           (Magic      => Mailbox_Magic,
            Version    => 1,
            Capacity   => 16,
            Slot_Size  => 128,
            Channel_Id => 1,
            Reserved   => [others => 0]),
         Producer      =>
           (Tail        => 0,
            Cached_Head => 0,
            Push_Count  => 0,
            Full_Drops  => 0,
            Reserved    => [others => 0]),
         Consumer      =>
           (Head        => 0,
            Cached_Tail => 0,
            Pop_Count   => 0,
            Crc_Errors  => 0,
            Seq_Gaps    => 0,
            Reserved    => [others => 0]),
         Reserved_Line => [others => 0],
         Slots         =>
           [others =>
              (Header  =>
                 (Sequence_Id  => 0,
                  Timestamp_Ns => 0,
                  Msg_Type     => Msg_None,
                  Flags        => Mbx_Flag_None,
                  Crc32        => 0,
                  Reserved     => 0),
               Payload =>
                 (Position_Rad        => [others => 0.0],
                  Velocity_Rad_S      => [others => 0.0],
                  Torque_Nm           => [others => 0.0],
                  Acceleration_Rad_S2 => [others => 0.0]))]);
   end Init_Test_Channel;

   procedure Test_Empty_Channel_Pop (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Chan    : Aegis_Mailbox_Channel;
      Msg_Out : Halos_Mailbox_Msg;
      Status  : Halos_Mailbox_Status;
   begin
      Init_Test_Channel (Chan);
      Try_Pop (Chan, 1_000_000, Msg_Out, Status);
      Assert (Status = Mbx_Err_Empty, "Pop on empty channel should return Mbx_Err_Empty");
      Assert (Chan.Consumer.Pop_Count = 0, "Pop count should be 0");
   end Test_Empty_Channel_Pop;

   procedure Test_Corrupt_Magic_Rejection (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Chan    : Aegis_Mailbox_Channel;
      Msg_Out : Halos_Mailbox_Msg;
      Status  : Halos_Mailbox_Status;
   begin
      Init_Test_Channel (Chan);
      Chan.Config.Magic := 16#DEAD_BEEF_CAFE_0000#;
      Try_Pop (Chan, 1_000_000, Msg_Out, Status);
      Assert (Status = Mbx_Err_Corrupt_Magic, "Corrupt magic should be rejected");
   end Test_Corrupt_Magic_Rejection;

   procedure Test_CRC32_Calculation (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Payload : Halos_Trajectory_Payload :=
        (Position_Rad        => [others => 0.0],
         Velocity_Rad_S      => [others => 0.0],
         Torque_Nm           => [others => 0.0],
         Acceleration_Rad_S2 => [others => 0.0]);
      Crc1    : Unsigned_32;
      Crc2    : Unsigned_32;
   begin
      Crc1 := Calculate_Crc32 (Payload);
      Assert (Crc1 /= 0, "CRC32 should be non-zero");

      --  Determinism check
      Crc2 := Calculate_Crc32 (Payload);
      Assert (Crc1 = Crc2, "CRC32 calculation must be deterministic");

      --  Modification check
      Payload.Position_Rad (0) := 1.0;
      Crc2 := Calculate_Crc32 (Payload);
      Assert (Crc1 /= Crc2, "Modified payload must produce distinct CRC32");
   end Test_CRC32_Calculation;

   procedure Test_Valid_Push_And_Pop (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Chan    : Aegis_Mailbox_Channel;
      Msg_Out : Halos_Mailbox_Msg;
      Status  : Halos_Mailbox_Status;
      Payload : constant Halos_Trajectory_Payload :=
        (Position_Rad        => [others => 0.5],
         Velocity_Rad_S      => [others => 1.5],
         Torque_Nm           => [others => 12.0],
         Acceleration_Rad_S2 => [others => 0.0]);
   begin
      Init_Test_Channel (Chan);

      --  Simulate producer write
      Chan.Slots (0).Payload := Payload;
      Chan.Slots (0).Header  :=
        (Sequence_Id  => 0,
         Timestamp_Ns => 1_000_000,
         Msg_Type     => Msg_Kinematic_Cmd,
         Flags        => Mbx_Flag_Valid,
         Crc32        => Calculate_Crc32 (Payload),
         Reserved     => 0);
      Chan.Producer.Tail := 1;

      --  Consumer reads at +1 ms
      Try_Pop (Chan, 2_000_000, Msg_Out, Status);
      Assert (Status = Mbx_Ok, "Pop should succeed for valid message");
      Assert (Chan.Consumer.Head = 1, "Consumer head updated to 1");
      Assert (Chan.Consumer.Pop_Count = 1, "Pop count incremented");
      Assert (Msg_Out.Payload.Torque_Nm (0) = 12.0, "Torque payload verified");
   end Test_Valid_Push_And_Pop;

   procedure Test_Sequence_Gap_Detection (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Chan    : Aegis_Mailbox_Channel;
      Msg_Out : Halos_Mailbox_Msg;
      Status  : Halos_Mailbox_Status;
      Payload : constant Halos_Trajectory_Payload :=
        (Position_Rad        => [others => 0.0],
         Velocity_Rad_S      => [others => 0.0],
         Torque_Nm           => [others => 10.0],
         Acceleration_Rad_S2 => [others => 0.0]);
   begin
      Init_Test_Channel (Chan);

      --  Slot has sequence_id 5, but consumer expects 0
      Chan.Slots (0).Payload := Payload;
      Chan.Slots (0).Header  :=
        (Sequence_Id  => 5,
         Timestamp_Ns => 1_000_000,
         Msg_Type     => Msg_Torque_Cmd,
         Flags        => Mbx_Flag_Valid,
         Crc32        => Calculate_Crc32 (Payload),
         Reserved     => 0);
      Chan.Producer.Tail := 1;

      Try_Pop (Chan, 2_000_000, Msg_Out, Status);
      Assert (Status = Mbx_Err_Seq_Gap, "Sequence mismatch should return Mbx_Err_Seq_Gap");
      Assert (Chan.Consumer.Seq_Gaps = 1, "Sequence gap metric incremented");
   end Test_Sequence_Gap_Detection;

   procedure Test_Stale_Timestamp_Rejection (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Chan    : Aegis_Mailbox_Channel;
      Msg_Out : Halos_Mailbox_Msg;
      Status  : Halos_Mailbox_Status;
      Payload : constant Halos_Trajectory_Payload :=
        (Position_Rad        => [others => 0.0],
         Velocity_Rad_S      => [others => 0.0],
         Torque_Nm           => [others => 10.0],
         Acceleration_Rad_S2 => [others => 0.0]);
   begin
      Init_Test_Channel (Chan);

      --  Timestamp 1 ms, popped at 7 ms (> 5 ms stale deadline!)
      Chan.Slots (0).Payload := Payload;
      Chan.Slots (0).Header  :=
        (Sequence_Id  => 0,
         Timestamp_Ns => 1_000_000,
         Msg_Type     => Msg_Torque_Cmd,
         Flags        => Mbx_Flag_Valid,
         Crc32        => Calculate_Crc32 (Payload),
         Reserved     => 0);
      Chan.Producer.Tail := 1;

      Try_Pop (Chan, 7_000_000, Msg_Out, Status);
      Assert (Status = Mbx_Err_Stale_Timestamp, "Stale message should return error");
   end Test_Stale_Timestamp_Rejection;

end Test_Halos_Mailbox;
