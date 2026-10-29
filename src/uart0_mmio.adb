pragma Ada_2022;

--  Proof-of-Concept implementation for UART0 MMIO register access in SPARK Ada 2022.
--  Note: Do not invoke Uart0_Init or Uart0_Putc on a host OS without hardware emulation
--  (e.g., QEMU/Renode) mapping physical peripheral address 16#4000_1000#.
package body Uart0_Mmio
   with SPARK_Mode => On
is

   procedure Uart0_Init (Baud_Divisor : Unsigned_32) is
   begin
      --  Disable peripheral before configuring (compiles to a single 32-bit zero store)
      CR_Reg :=
        (Enable     => False,
         Tx_En      => False,
         Rx_En      => False,
         Reserved_1 => 0,
         Loopback   => False,
         Reserved_2 => 0);

      BAUD_Reg := Baud_Divisor;

      --  Enable UART with TX and RX active (compiles to a single 32-bit immediate store)
      CR_Reg :=
        (Enable     => True,
         Tx_En      => True,
         Rx_En      => True,
         Reserved_1 => 0,
         Loopback   => False,
         Reserved_2 => 0);
   end Uart0_Init;

   procedure Uart0_Putc
     (Byte      :     Unsigned_8;
      Timed_Out : out Boolean)
   is
      Current_Status : Uart_Status_Reg;
   begin
      for Spin in 1 .. Max_Tx_Poll_Spins loop
         --  Volatile read with Async_Writers must be captured into a local variable
         Current_Status := SR_Reg;

         if Current_Status.Tx_Empty then
            DR_Reg    := (Data => Byte, Reserved => 0);
            Timed_Out := False;
            return;
         end if;
      end loop;

      Timed_Out := True;
   end Uart0_Putc;

end Uart0_Mmio;
