pragma Ada_2022;
with Halos_Safety_Gate; use Halos_Safety_Gate;
with Interfaces;        use Interfaces;
with Interfaces.C;      use Interfaces.C;
with Uart0_Mmio;

procedure Aegis_Spark_Qemu
   with SPARK_Mode => On
is
   procedure C_Qemu_Exit (Status : Integer)
      with Import,
           Convention    => C,
           External_Name => "qemu_exit";

   Env : Halos_Safety_Envelope :=
     (Max_Abs_Torque_Nm => [others => 50.0],
      State             => State_Active);

   Valid_Cmd : constant Halos_Joint_Cmd :=
     (Timestamp_Ns      => 1_000_000,
      Desired_Torque_Nm => [others => 12.5]);

   Over_Torque_Cmd : constant Halos_Joint_Cmd :=
     (Timestamp_Ns      => 2_000_000,
      Desired_Torque_Nm => [0 => 75.0, others => 10.0]);

   Safe_Out  : Safe_Torque_Array;
   Status    : Halos_Status;
   Timed_Out : Boolean;
begin
   --  1. Initialize PL011 UART hardware at 115200 baud
   Uart0_Mmio.Uart0_Init (Baud_Divisor => 115_200);

   --  2. Emit boot telemetry
   Uart0_Mmio.Uart0_Puts
     (Str       => "[AEGIS_SPARK] Initializing bare-metal ARM64 safety supervisor" & ASCII.LF,
      Timed_Out => Timed_Out);

   Uart0_Mmio.Uart0_Puts
     (Str       => "HALOS_GATE: BOOT OK" & ASCII.LF,
      Timed_Out => Timed_Out);

   --  3. Execute nominal joint command (Self-Test pass)
   Intercept_Joint_Cmd
     (Env             => Env,
      Cmd_In          => Valid_Cmd,
      Now_Ns          => 2_000_000,
      Safe_Torque_Out => Safe_Out,
      Status          => Status);

   if Status = Halos_Ok and then Env.State = State_Active then
      Uart0_Mmio.Uart0_Puts
        (Str       => "HALOS_GATE: SELF-TEST PASS" & ASCII.LF,
         Timed_Out => Timed_Out);
   end if;

   --  4. Over-torque command triggering Fault_Estop latching
   Intercept_Joint_Cmd
     (Env             => Env,
      Cmd_In          => Over_Torque_Cmd,
      Now_Ns          => 2_500_000,
      Safe_Torque_Out => Safe_Out,
      Status          => Status);

   if Status = Halos_Err_Torque_Limit_Exceeded
     and then Env.State = State_Fault_Estop
   then
      Uart0_Mmio.Uart0_Puts
        (Str       => "HALOS_GATE: FAULT_ESTOP LATCHED" & ASCII.LF,
         Timed_Out => Timed_Out);
   end if;

   --  5. Subsequent command while in Fault_Estop (rejection verification)
   Intercept_Joint_Cmd
     (Env             => Env,
      Cmd_In          => Valid_Cmd,
      Now_Ns          => 3_000_000,
      Safe_Torque_Out => Safe_Out,
      Status          => Status);

   if Status = Halos_Err_Not_Active
     and then Env.State = State_Fault_Estop
   then
      Uart0_Mmio.Uart0_Puts
        (Str       => "HALOS_GATE: TELEMETRY OK" & ASCII.LF,
         Timed_Out => Timed_Out);
   end if;

   --  6. Terminate emulation cleanly via ARM semihosting SYS_EXIT
   C_Qemu_Exit (0);
end Aegis_Spark_Qemu;
