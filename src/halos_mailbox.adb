pragma Ada_2022;
with Ada.Unchecked_Conversion;

package body Halos_Mailbox
   with SPARK_Mode => On
is

   function Calculate_Crc32 (Payload : Halos_Trajectory_Payload) return Unsigned_32 is
      type U32_Words is array (1 .. 24) of Unsigned_32;
      function To_Words is new Ada.Unchecked_Conversion
        (Source => Halos_Trajectory_Payload, Target => U32_Words);

      Words : constant U32_Words := To_Words (Payload);
      Crc   : Unsigned_32 := 16#FFFF_FFFF#;
      Byte  : Unsigned_32;
   begin
      for I in 1 .. 24 loop
         for B in Natural range 0 .. 3 loop
            Byte := Shift_Right (Words (I), B * 8) and 16#FF#;
            Crc  := Crc xor Byte;
            for Bit in 1 .. 8 loop
               if (Crc and 1) /= 0 then
                  Crc := Shift_Right (Crc, 1) xor 16#EDB8_8320#;
               else
                  Crc := Shift_Right (Crc, 1);
               end if;
            end loop;
         end loop;
      end loop;
      return Crc xor 16#FFFF_FFFF#;
   end Calculate_Crc32;

   function Validate_Payload_Floats (Payload : Halos_Trajectory_Payload) return Boolean is
   begin
      for I in Dof_Index loop
         pragma Warnings
           (GNATprove, Off,
            "attribute ""Valid"" is assumed to return True",
            Reason => "Defensive runtime validation at FFI boundary");
         if not Payload.Position_Rad (I)'Valid
           or else not Payload.Velocity_Rad_S (I)'Valid
           or else not Payload.Torque_Nm (I)'Valid
           or else not Payload.Acceleration_Rad_S2 (I)'Valid
         then
            return False;
         end if;
         pragma Warnings
           (GNATprove, On,
            "attribute ""Valid"" is assumed to return True");
      end loop;
      return True;
   end Validate_Payload_Floats;

   procedure Try_Pop
     (Chan    : in out Aegis_Mailbox_Channel;
      Now_Ns  :        Unsigned_64;
      Msg_Out :    out Halos_Mailbox_Msg;
      Status  :    out Halos_Mailbox_Status)
   is
      Local_Head : Unsigned_64;
      Local_Tail : Unsigned_64;
      Slot_Idx   : Slot_Index;
      Local_Msg  : Halos_Mailbox_Msg;
   begin
      Msg_Out :=
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
            Acceleration_Rad_S2 => [others => 0.0]));

      if Chan.Config.Magic /= Mailbox_Magic then
         Status := Mbx_Err_Corrupt_Magic;
         return;
      end if;

      if Chan.Config.Version /= 1 then
         Status := Mbx_Err_Version_Mismatch;
         return;
      end if;

      Local_Head := Unsigned_64 (Chan.Consumer.Head);

      if Local_Head = Chan.Consumer.Cached_Tail then
         Local_Tail := Unsigned_64 (Chan.Producer.Tail);
         Chan.Consumer.Cached_Tail := Local_Tail;
         if Local_Head = Local_Tail then
            Status := Mbx_Err_Empty;
            return;
         end if;
      end if;

      Slot_Idx  := Slot_Index (Local_Head and (Mailbox_Capacity - 1));
      Local_Msg := Chan.Slots (Slot_Idx);

      if Local_Msg.Header.Sequence_Id /= Local_Head then
         Chan.Consumer.Seq_Gaps := Chan.Consumer.Seq_Gaps + 1;
         Status := Mbx_Err_Seq_Gap;
         return;
      end if;

      if (Local_Msg.Header.Flags and Mbx_Flag_Valid) = 0 then
         Status := Mbx_Err_Invalid_Payload;
         return;
      end if;

      if Calculate_Crc32 (Local_Msg.Payload) /= Local_Msg.Header.Crc32 then
         Chan.Consumer.Crc_Errors := Chan.Consumer.Crc_Errors + 1;
         Status := Mbx_Err_Crc_Mismatch;
         return;
      end if;

      if Now_Ns < Local_Msg.Header.Timestamp_Ns
        or else (Now_Ns - Local_Msg.Header.Timestamp_Ns) > 5_000_000
      then
         Status := Mbx_Err_Stale_Timestamp;
         return;
      end if;

      if not Validate_Payload_Floats (Local_Msg.Payload) then
         Status := Mbx_Err_Invalid_Payload;
         return;
      end if;

      Chan.Consumer.Head      := Local_Head + 1;
      Chan.Consumer.Pop_Count := Chan.Consumer.Pop_Count + 1;
      Msg_Out                 := Local_Msg;
      Status                  := Mbx_Ok;
   end Try_Pop;

end Halos_Mailbox;
