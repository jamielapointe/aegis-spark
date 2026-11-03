"""Python ctypes FFI bindings for Aegis-SPARK Ada / C23 safety gate and mock MMIO."""

import ctypes
import functools
import platform
from enum import IntEnum
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
HALOS_DOF_COUNT = 6
HALOS_MAX_CMD_AGE_NS = 5_000_000
MAX_HARDWARE_TORQUE_NM = 500.0


class HalosStatus(IntEnum):
    """Halos safety gate status codes matching Halos_Safety_Gate.ads."""

    HALOS_OK = 0
    HALOS_ERR_NOT_ACTIVE = 1
    HALOS_ERR_STALE_HEARTBEAT = 2
    HALOS_ERR_NON_FINITE_INPUT = 3
    HALOS_ERR_TORQUE_LIMIT_EXCEEDED = 4


class HalosSafetyState(IntEnum):
    """Halos safety gate operational states matching Halos_Safety_Gate.ads."""

    HALOS_STATE_INIT = 0
    HALOS_STATE_ACTIVE = 1
    HALOS_STATE_FAULT_ESTOP = 2


class HalosJointCmd(ctypes.Structure):
    """Joint torque command packet matching struct halos_joint_cmd."""

    _fields_ = [
        ('timestamp_ns', ctypes.c_uint64),
        ('desired_torque_nm', ctypes.c_float * HALOS_DOF_COUNT),
    ]


class HalosSafetyEnvelope(ctypes.Structure):
    """Safety envelope and state matching struct halos_safety_envelope."""

    _fields_ = [
        ('max_abs_torque_nm', ctypes.c_float * HALOS_DOF_COUNT),
        ('state', ctypes.c_uint8),
    ]


SafeTorqueArray = ctypes.c_float * HALOS_DOF_COUNT
SafeVelocityArray = ctypes.c_float * HALOS_DOF_COUNT
SafePositionArray = ctypes.c_float * HALOS_DOF_COUNT

HALOS_WD_RESET_MAGIC = 0x57444752
HALOS_HSM_RESET_MAGIC = 0x48534D52
AEGIS_MAILBOX_MAGIC = 0x41454749534D4258
AEGIS_MAILBOX_VERSION = 1
AEGIS_MAILBOX_CAPACITY = 16


class HalosWatchdogState(IntEnum):
    """Watchdog states matching halos_watchdog.ads."""

    WD_DISABLED = 0
    WD_ARMED = 1
    WD_FAULT_EARLY = 2
    WD_FAULT_LATE = 3
    WD_FAULT_CLOCK = 4


class HalosWatchdogStatus(IntEnum):
    """Watchdog status codes matching halos_watchdog.ads."""

    WD_OK = 0
    WD_ERR_NOT_ARMED = 1
    WD_ERR_TOO_EARLY = 2
    WD_ERR_TOO_LATE = 3
    WD_ERR_TIME_REWIND = 4
    WD_ERR_INVALID_CONFIG = 5
    WD_ERR_INVALID_KEY = 6


class HalosWatchdogConfig(ctypes.Structure):
    """Watchdog timing configuration."""

    _fields_ = [
        ('min_interval_ns', ctypes.c_uint64),
        ('max_interval_ns', ctypes.c_uint64),
    ]


class HalosWatchdogDevice(ctypes.Structure):
    """Watchdog device instance."""

    _fields_ = [
        ('config', HalosWatchdogConfig),
        ('last_pet_ns', ctypes.c_uint64),
        ('pet_count', ctypes.c_uint64),
        ('state', ctypes.c_uint32),
        ('reserved_pad', ctypes.c_uint32),
    ]


class HalosHsmState(IntEnum):
    """Hierarchical safety state matching halos_hsm.ads."""

    HALOS_HSM_BOOT = 0
    HALOS_HSM_ACTIVE = 1
    HALOS_HSM_DEGRADED = 2
    HALOS_HSM_FAULT_ESTOP = 3


class HalosHsmEvent(IntEnum):
    """HSM lifecycle events matching halos_hsm.ads."""

    HALOS_EVENT_NONE = 0
    HALOS_EVENT_SELF_TEST_PASSED = 1
    HALOS_EVENT_SELF_TEST_FAILED = 2
    HALOS_EVENT_DEGRADE_REQUESTED = 3
    HALOS_EVENT_RECOVER_NOMINAL = 4
    HALOS_EVENT_FAULT_DETECTED = 5
    HALOS_EVENT_RESET_REQUESTED = 6


class HalosFaultCode(IntEnum):
    """HSM fault codes matching halos_hsm.ads."""

    HALOS_FAULT_NONE = 0
    HALOS_FAULT_WATCHDOG_TIMEOUT = 1
    HALOS_FAULT_WATCHDOG_EARLY_PET = 2
    HALOS_FAULT_WATCHDOG_CLOCK_REWIND = 3
    HALOS_FAULT_KINEMATIC_POSITION = 4
    HALOS_FAULT_KINEMATIC_VELOCITY = 5
    HALOS_FAULT_KINEMATIC_TORQUE = 6
    HALOS_FAULT_KINEMATIC_JERK = 7
    HALOS_FAULT_NON_FINITE_INPUT = 8
    HALOS_FAULT_HARDWARE_BIST = 9


class HalosHsmStatus(IntEnum):
    """HSM transition status codes matching halos_hsm.ads."""

    HALOS_HSM_OK = 0
    HALOS_HSM_ERR_INVALID_TRANSITION = 1
    HALOS_HSM_ERR_INVALID_KEY = 2
    HALOS_HSM_ERR_ALREADY_IN_STATE = 3


class HalosHsmInstance(ctypes.Structure):
    """HSM instance matching struct halos_hsm_instance."""

    _fields_ = [
        ('state', ctypes.c_uint32),
        ('last_fault_code', ctypes.c_uint32),
        ('transition_count', ctypes.c_uint64),
    ]


class HalosKinematicLimits(ctypes.Structure):
    """6-DOF kinematic envelope limits matching struct halos_kinematic_limits."""

    _fields_ = [
        ('max_abs_position_rad', ctypes.c_float * HALOS_DOF_COUNT),
        ('max_abs_velocity_rad', ctypes.c_float * HALOS_DOF_COUNT),
        ('max_abs_torque_nm', ctypes.c_float * HALOS_DOF_COUNT),
        ('max_delta_torque_step', ctypes.c_float * HALOS_DOF_COUNT),
    ]


class HalosKinematicCmd(ctypes.Structure):
    """6-DOF kinematic command matching struct halos_kinematic_cmd."""

    _fields_ = [
        ('timestamp_ns', ctypes.c_uint64),
        ('position_rad', ctypes.c_float * HALOS_DOF_COUNT),
        ('velocity_rad', ctypes.c_float * HALOS_DOF_COUNT),
        ('torque_nm', ctypes.c_float * HALOS_DOF_COUNT),
    ]


class HalosKinematicState(ctypes.Structure):
    """6-DOF kinematic supervisor state matching struct halos_kinematic_state."""

    _fields_ = [
        ('last_cmd', HalosKinematicCmd),
        ('limits', HalosKinematicLimits),
        ('hsm', HalosHsmInstance),
    ]


class HalosComposedGate(ctypes.Structure):
    """Composed safety gate integrating Watchdog, HSM, and Kinematics."""

    _fields_ = [
        ('watchdog', HalosWatchdogDevice),
        ('hsm', HalosHsmInstance),
        ('kinematics', HalosKinematicState),
    ]


class HalosMsgType(IntEnum):
    """Inter-VM mailbox message types."""

    HALOS_MSG_NONE = 0
    HALOS_MSG_TORQUE_CMD = 1
    HALOS_MSG_KINEMATIC_CMD = 2
    HALOS_MSG_HEARTBEAT_PET = 3
    HALOS_MSG_RESET_FAULT = 4
    HALOS_MSG_EMERGENCY_STOP = 5


class HalosMailboxStatus(IntEnum):
    """Inter-VM mailbox return status codes."""

    HALOS_MBX_OK = 0
    HALOS_MBX_ERR_EMPTY = 1
    HALOS_MBX_ERR_FULL = 2
    HALOS_MBX_ERR_NULL_PTR = 3
    HALOS_MBX_ERR_UNALIGNED = 4
    HALOS_MBX_ERR_CORRUPT_MAGIC = 5
    HALOS_MBX_ERR_VERSION_MISMATCH = 6
    HALOS_MBX_ERR_SEQ_GAP = 7
    HALOS_MBX_ERR_OVERRUN = 8
    HALOS_MBX_ERR_CRC_MISMATCH = 9
    HALOS_MBX_ERR_INVALID_PAYLOAD = 10
    HALOS_MBX_ERR_STALE_TIMESTAMP = 11
    HALOS_MBX_ERR_INVALID_MSG_TYPE = 12


class HalosTrajectoryPayload(ctypes.Structure):
    """Mailbox 6-DOF trajectory payload (96 bytes)."""

    _fields_ = [
        ('position_rad', ctypes.c_float * HALOS_DOF_COUNT),
        ('velocity_rad_s', ctypes.c_float * HALOS_DOF_COUNT),
        ('torque_nm', ctypes.c_float * HALOS_DOF_COUNT),
        ('acceleration_rad_s2', ctypes.c_float * HALOS_DOF_COUNT),
    ]


class HalosMailboxHeader(ctypes.Structure):
    """Mailbox slot header (32 bytes)."""

    _fields_ = [
        ('sequence_id', ctypes.c_uint64),
        ('timestamp_ns', ctypes.c_uint64),
        ('msg_type', ctypes.c_uint32),
        ('flags', ctypes.c_uint32),
        ('crc32', ctypes.c_uint32),
        ('reserved', ctypes.c_uint32),
    ]


class HalosMailboxMsg(ctypes.Structure):
    """Mailbox message slot (128 bytes)."""

    _fields_ = [
        ('header', HalosMailboxHeader),
        ('payload', HalosTrajectoryPayload),
    ]


class AegisMailboxConfig(ctypes.Structure):
    """Mailbox configuration header (64 bytes)."""

    _fields_ = [
        ('magic', ctypes.c_uint64),
        ('version', ctypes.c_uint32),
        ('capacity', ctypes.c_uint32),
        ('slot_size', ctypes.c_uint32),
        ('channel_id', ctypes.c_uint32),
        ('reserved', ctypes.c_uint8 * 40),
    ]


class AegisMailboxProducer(ctypes.Structure):
    """Mailbox producer cache line (64 bytes)."""

    _fields_ = [
        ('tail', ctypes.c_uint64),
        ('cached_head', ctypes.c_uint64),
        ('push_count', ctypes.c_uint64),
        ('full_drops', ctypes.c_uint64),
        ('reserved', ctypes.c_uint8 * 32),
    ]


class AegisMailboxConsumer(ctypes.Structure):
    """Mailbox consumer cache line (64 bytes)."""

    _fields_ = [
        ('head', ctypes.c_uint64),
        ('cached_tail', ctypes.c_uint64),
        ('pop_count', ctypes.c_uint64),
        ('crc_errors', ctypes.c_uint64),
        ('seq_gaps', ctypes.c_uint64),
        ('reserved', ctypes.c_uint8 * 24),
    ]


class AegisMailboxChannel(ctypes.Structure):
    """SPSC inter-VM channel (2304 bytes, 64-byte aligned)."""

    _fields_ = [
        ('config', AegisMailboxConfig),
        ('producer', AegisMailboxProducer),
        ('consumer', AegisMailboxConsumer),
        ('reserved_line', ctypes.c_uint8 * 64),
        ('slots', HalosMailboxMsg * AEGIS_MAILBOX_CAPACITY),
    ]


class AegisUartDataReg(ctypes.Structure):
    """Mock UART Data Register bitfield matching struct aegis_uart_data_reg."""

    _fields_ = [
        ('data', ctypes.c_uint32, 8),
        ('reserved', ctypes.c_uint32, 24),
    ]


class AegisUartStatusReg(ctypes.Structure):
    """Mock UART Status Register bitfield matching struct aegis_uart_status_reg."""

    _fields_ = [
        ('tx_empty', ctypes.c_uint32, 1),
        ('rx_full', ctypes.c_uint32, 1),
        ('busy', ctypes.c_uint32, 1),
        ('err_ovr', ctypes.c_uint32, 1),
        ('reserved', ctypes.c_uint32, 28),
    ]


class AegisUartCtrlReg(ctypes.Structure):
    """Mock UART Control Register bitfield matching struct aegis_uart_ctrl_reg."""

    _fields_ = [
        ('enable', ctypes.c_uint32, 1),
        ('tx_en', ctypes.c_uint32, 1),
        ('rx_en', ctypes.c_uint32, 1),
        ('reserved_1', ctypes.c_uint32, 4),
        ('loopback', ctypes.c_uint32, 1),
        ('reserved_2', ctypes.c_uint32, 24),
    ]


def locate_shared_library() -> Path:
    """Locate libaegis_spark shared library across lib/ and build/ directories.

    Returns:
        Path to the discovered shared library binary.

    Raises:
        FileNotFoundError: If the shared library cannot be found in any candidate path.
    """
    ext = '.dylib' if platform.system() == 'Darwin' else '.so'
    name = f'libaegis_spark{ext}'

    candidates = [
        REPO_ROOT / 'lib' / name,
        REPO_ROOT / 'build' / 'host-sim-debug' / 'lib' / name,
        REPO_ROOT / 'build' / 'lib' / name,
    ]

    for candidate in candidates:
        if candidate.is_file():
            return candidate

    msg = (
        f'Could not locate {name} in candidate paths: {[str(c) for c in candidates]}. '
        'Run `cmake --workflow --preset host-sim-debug` to build the shared library target.'
    )
    raise FileNotFoundError(msg)


@functools.cache
def get_lib() -> ctypes.CDLL:
    """Load libaegis_spark shared library and initialize SPARK runtime.

    Returns:
        Loaded ctypes.CDLL instance.
    """
    lib_path = locate_shared_library()
    lib = ctypes.CDLL(str(lib_path))

    # Initialize Ada library elaboration if available
    if hasattr(lib, 'aegis_sparkinit'):
        lib.aegis_sparkinit.argtypes = []
        lib.aegis_sparkinit.restype = None
        lib.aegis_sparkinit()

    # Configure halos_spark_intercept_joint_cmd signature
    lib.halos_spark_intercept_joint_cmd.argtypes = [
        ctypes.POINTER(HalosSafetyEnvelope),
        ctypes.POINTER(HalosJointCmd),
        ctypes.c_uint64,
        ctypes.POINTER(SafeTorqueArray),
        ctypes.POINTER(ctypes.c_int32),
    ]
    lib.halos_spark_intercept_joint_cmd.restype = None

    # Phase 4 Watchdog
    lib.halos_watchdog_init.argtypes = [ctypes.POINTER(HalosWatchdogDevice)]
    lib.halos_watchdog_init.restype = None

    lib.halos_watchdog_arm.argtypes = [
        ctypes.POINTER(HalosWatchdogDevice),
        ctypes.POINTER(HalosWatchdogConfig),
        ctypes.c_uint64,
        ctypes.POINTER(ctypes.c_int32),
    ]
    lib.halos_watchdog_arm.restype = None

    lib.halos_watchdog_pet.argtypes = [
        ctypes.POINTER(HalosWatchdogDevice),
        ctypes.c_uint64,
        ctypes.POINTER(ctypes.c_int32),
    ]
    lib.halos_watchdog_pet.restype = None

    lib.halos_watchdog_check_deadline.argtypes = [
        ctypes.POINTER(HalosWatchdogDevice),
        ctypes.c_uint64,
        ctypes.POINTER(ctypes.c_int32),
    ]
    lib.halos_watchdog_check_deadline.restype = None

    lib.halos_watchdog_reset.argtypes = [
        ctypes.POINTER(HalosWatchdogDevice),
        ctypes.c_uint32,
        ctypes.c_uint64,
        ctypes.POINTER(ctypes.c_int32),
    ]
    lib.halos_watchdog_reset.restype = None

    # Phase 4 HSM
    lib.halos_hsm_init.argtypes = [ctypes.POINTER(HalosHsmInstance)]
    lib.halos_hsm_init.restype = None

    lib.halos_hsm_process_event.argtypes = [
        ctypes.POINTER(HalosHsmInstance),
        ctypes.c_uint32,
        ctypes.c_uint32,
        ctypes.POINTER(ctypes.c_int32),
    ]
    lib.halos_hsm_process_event.restype = None

    lib.halos_hsm_trigger_reset.argtypes = [
        ctypes.POINTER(HalosHsmInstance),
        ctypes.c_uint32,
        ctypes.POINTER(ctypes.c_int32),
    ]
    lib.halos_hsm_trigger_reset.restype = None

    # Phase 4 Kinematics
    lib.halos_kinematics_init.argtypes = [ctypes.POINTER(HalosKinematicState)]
    lib.halos_kinematics_init.restype = None

    lib.halos_kinematics_intercept_cmd.argtypes = [
        ctypes.POINTER(HalosKinematicState),
        ctypes.POINTER(HalosKinematicCmd),
        ctypes.POINTER(SafeTorqueArray),
        ctypes.POINTER(SafeVelocityArray),
        ctypes.POINTER(ctypes.c_int32),
    ]
    lib.halos_kinematics_intercept_cmd.restype = None

    # Phase 4 Composed Gate
    lib.halos_composed_gate_init.argtypes = [
        ctypes.POINTER(HalosComposedGate),
        ctypes.c_uint64,
    ]
    lib.halos_composed_gate_init.restype = None

    lib.halos_composed_gate_intercept_cmd.argtypes = [
        ctypes.POINTER(HalosComposedGate),
        ctypes.POINTER(HalosKinematicCmd),
        ctypes.c_uint64,
        ctypes.POINTER(SafeTorqueArray),
        ctypes.POINTER(SafeVelocityArray),
        ctypes.POINTER(ctypes.c_int32),
    ]
    lib.halos_composed_gate_intercept_cmd.restype = None

    # Phase 4 Mailbox
    lib.aegis_mailbox_init.argtypes = [
        ctypes.POINTER(AegisMailboxChannel),
        ctypes.c_uint32,
    ]
    lib.aegis_mailbox_init.restype = ctypes.c_int32

    lib.aegis_mailbox_try_push.argtypes = [
        ctypes.POINTER(AegisMailboxChannel),
        ctypes.c_uint32,
        ctypes.c_uint32,
        ctypes.c_uint64,
        ctypes.POINTER(HalosTrajectoryPayload),
    ]
    lib.aegis_mailbox_try_push.restype = ctypes.c_int32

    lib.aegis_mailbox_try_pop.argtypes = [
        ctypes.POINTER(AegisMailboxChannel),
        ctypes.c_uint64,
        ctypes.POINTER(HalosMailboxMsg),
    ]
    lib.aegis_mailbox_try_pop.restype = ctypes.c_int32

    lib.aegis_mailbox_crc32.argtypes = [ctypes.POINTER(HalosTrajectoryPayload)]
    lib.aegis_mailbox_crc32.restype = ctypes.c_uint32

    return lib


def intercept_joint_cmd(
    env: HalosSafetyEnvelope,
    cmd: HalosJointCmd,
    now_ns: int,
) -> tuple[HalosSafetyEnvelope, list[float], HalosStatus]:
    """Execute the Gold-proved SPARK safety gate command interceptor.

    Args:
        env: The safety envelope (modified in-place by interceptor).
        cmd: The desired joint command.
        now_ns: The current monotonic timestamp in nanoseconds.

    Returns:
        Tuple of (updated_env, safe_torques, status).
    """
    lib = get_lib()
    safe_out = SafeTorqueArray()
    status_c = ctypes.c_int32(99)

    lib.halos_spark_intercept_joint_cmd(
        ctypes.byref(env),
        ctypes.byref(cmd),
        ctypes.c_uint64(now_ns),
        ctypes.byref(safe_out),
        ctypes.byref(status_c),
    )

    return env, [float(x) for x in safe_out], HalosStatus(status_c.value)


def get_mock_uart0_dr() -> int:
    """Read value of mock UART0 Data Register.

    Returns:
        32-bit register value as an integer.
    """
    lib = get_lib()
    ptr = ctypes.c_uint32.in_dll(lib, 'aegis_mock_uart0_dr')
    return int(ptr.value)


def set_mock_uart0_dr(value: int) -> None:
    """Write value to mock UART0 Data Register.

    Args:
        value: 32-bit integer value to write.
    """
    lib = get_lib()
    ptr = ctypes.c_uint32.in_dll(lib, 'aegis_mock_uart0_dr')
    ptr.value = value


def get_mock_uart0_sr() -> int:
    """Read value of mock UART0 Status Register.

    Returns:
        32-bit register value as an integer.
    """
    lib = get_lib()
    ptr = ctypes.c_uint32.in_dll(lib, 'aegis_mock_uart0_sr')
    return int(ptr.value)


def set_mock_uart0_sr(value: int) -> None:
    """Write value to mock UART0 Status Register.

    Args:
        value: 32-bit integer value to write.
    """
    lib = get_lib()
    ptr = ctypes.c_uint32.in_dll(lib, 'aegis_mock_uart0_sr')
    ptr.value = value


def get_mock_uart0_cr() -> int:
    """Read value of mock UART0 Control Register.

    Returns:
        32-bit register value as an integer.
    """
    lib = get_lib()
    ptr = ctypes.c_uint32.in_dll(lib, 'aegis_mock_uart0_cr')
    return int(ptr.value)


def set_mock_uart0_cr(value: int) -> None:
    """Write value to mock UART0 Control Register.

    Args:
        value: 32-bit integer value to write.
    """
    lib = get_lib()
    ptr = ctypes.c_uint32.in_dll(lib, 'aegis_mock_uart0_cr')
    ptr.value = value


def get_mock_uart0_baud() -> int:
    """Read value of mock UART0 Baud Divisor Register.

    Returns:
        32-bit register value as an integer.
    """
    lib = get_lib()
    ptr = ctypes.c_uint32.in_dll(lib, 'aegis_mock_uart0_baud')
    return int(ptr.value)


def set_mock_uart0_baud(value: int) -> None:
    """Write value to mock UART0 Baud Divisor Register.

    Args:
        value: 32-bit integer value to write.
    """
    lib = get_lib()
    ptr = ctypes.c_uint32.in_dll(lib, 'aegis_mock_uart0_baud')
    ptr.value = value


def get_mock_uart0_dr_reg() -> AegisUartDataReg:
    """Read mock UART0 Data Register as structured bitfields.

    Returns:
        AegisUartDataReg overlay on in-RAM mock register.
    """
    lib = get_lib()
    return AegisUartDataReg.in_dll(lib, 'aegis_mock_uart0_dr')


def get_mock_uart0_sr_reg() -> AegisUartStatusReg:
    """Read mock UART0 Status Register as structured bitfields.

    Returns:
        AegisUartStatusReg overlay on in-RAM mock register.
    """
    lib = get_lib()
    return AegisUartStatusReg.in_dll(lib, 'aegis_mock_uart0_sr')


def get_mock_uart0_cr_reg() -> AegisUartCtrlReg:
    """Read mock UART0 Control Register as structured bitfields.

    Returns:
        AegisUartCtrlReg overlay on in-RAM mock register.
    """
    lib = get_lib()
    return AegisUartCtrlReg.in_dll(lib, 'aegis_mock_uart0_cr')


def watchdog_create(
    min_ns: int = 500_000,
    max_ns: int = 5_000_000,
    start_ns: int = 1_000_000,
) -> tuple[HalosWatchdogDevice, HalosWatchdogStatus]:
    """Create and arm a Halos watchdog device.

    Args:
        min_ns: Minimum pet interval in nanoseconds.
        max_ns: Maximum pet deadline in nanoseconds.
        start_ns: Initial timestamp in nanoseconds.

    Returns:
        Tuple of (configured device instance, arming status).
    """
    lib = get_lib()
    wd = HalosWatchdogDevice()
    lib.halos_watchdog_init(ctypes.byref(wd))

    cfg = HalosWatchdogConfig(min_interval_ns=min_ns, max_interval_ns=max_ns)
    status = ctypes.c_int32(0)
    lib.halos_watchdog_arm(ctypes.byref(wd), ctypes.byref(cfg), ctypes.c_uint64(start_ns), ctypes.byref(status))
    return wd, HalosWatchdogStatus(status.value)


def watchdog_pet(wd: HalosWatchdogDevice, now_ns: int) -> HalosWatchdogStatus:
    """Pet the watchdog.

    Args:
        wd: Watchdog device instance.
        now_ns: Current timestamp in nanoseconds.

    Returns:
        Watchdog status code resulting from pet operation.
    """
    lib = get_lib()
    status = ctypes.c_int32(0)
    lib.halos_watchdog_pet(ctypes.byref(wd), ctypes.c_uint64(now_ns), ctypes.byref(status))
    return HalosWatchdogStatus(status.value)


def watchdog_check_deadline(wd: HalosWatchdogDevice, now_ns: int) -> HalosWatchdogStatus:
    """Check if watchdog deadline has expired.

    Args:
        wd: Watchdog device instance.
        now_ns: Current timestamp in nanoseconds.

    Returns:
        Watchdog status code.
    """
    lib = get_lib()
    status = ctypes.c_int32(0)
    lib.halos_watchdog_check_deadline(ctypes.byref(wd), ctypes.c_uint64(now_ns), ctypes.byref(status))
    return HalosWatchdogStatus(status.value)


def watchdog_reset(wd: HalosWatchdogDevice, key: int, now_ns: int) -> HalosWatchdogStatus:
    """Reset tripped watchdog with authorization token.

    Args:
        wd: Watchdog device instance.
        key: 32-bit authorization token.
        now_ns: Current timestamp in nanoseconds.

    Returns:
        Watchdog status code.
    """
    lib = get_lib()
    status = ctypes.c_int32(0)
    lib.halos_watchdog_reset(ctypes.byref(wd), ctypes.c_uint32(key), ctypes.c_uint64(now_ns), ctypes.byref(status))
    return HalosWatchdogStatus(status.value)


def hsm_create() -> HalosHsmInstance:
    """Create initialized HSM instance in State_Boot.

    Returns:
        Initialized HalosHsmInstance.
    """
    lib = get_lib()
    hsm = HalosHsmInstance()
    lib.halos_hsm_init(ctypes.byref(hsm))
    return hsm


def hsm_process_event(
    hsm: HalosHsmInstance,
    event: HalosHsmEvent,
    fault: HalosFaultCode = HalosFaultCode.HALOS_FAULT_NONE,
) -> HalosHsmStatus:
    """Process lifecycle event in HSM.

    Args:
        hsm: HSM instance.
        event: Lifecycle event to process.
        fault: Associated fault code if any.

    Returns:
        HSM transition status code.
    """
    lib = get_lib()
    status = ctypes.c_int32(0)
    lib.halos_hsm_process_event(
        ctypes.byref(hsm),
        ctypes.c_uint32(int(event)),
        ctypes.c_uint32(int(fault)),
        ctypes.byref(status),
    )
    return HalosHsmStatus(status.value)


def hsm_reset(hsm: HalosHsmInstance, key: int) -> HalosHsmStatus:
    """Reset HSM from Fault_Estop with auth key.

    Args:
        hsm: HSM instance.
        key: 32-bit authorization key.

    Returns:
        HSM reset status code.
    """
    lib = get_lib()
    status = ctypes.c_int32(0)
    lib.halos_hsm_trigger_reset(ctypes.byref(hsm), ctypes.c_uint32(key), ctypes.byref(status))
    return HalosHsmStatus(status.value)


def kinematics_create(
    pos_limit: float = 3.14,
    vel_limit: float = 10.0,
    torque_limit: float = 100.0,
    jerk_limit: float = 50.0,
) -> HalosKinematicState:
    """Create initialized 6-DOF kinematic supervisor state.

    Args:
        pos_limit: Max absolute position limit in radians.
        vel_limit: Max absolute velocity limit in rad/s.
        torque_limit: Max absolute torque limit in Nm.
        jerk_limit: Max single-step delta torque in Nm.

    Returns:
        Initialized HalosKinematicState.
    """
    lib = get_lib()
    state = HalosKinematicState()
    lib.halos_kinematics_init(ctypes.byref(state))
    for i in range(HALOS_DOF_COUNT):
        state.limits.max_abs_position_rad[i] = pos_limit
        state.limits.max_abs_velocity_rad[i] = vel_limit
        state.limits.max_abs_torque_nm[i] = torque_limit
        state.limits.max_delta_torque_step[i] = jerk_limit
    return state


def kinematics_intercept(
    state: HalosKinematicState, cmd: HalosKinematicCmd
) -> tuple[list[float], list[float], HalosHsmStatus]:
    """Execute 6-DOF kinematic interceptor.

    Args:
        state: Supervisor state instance.
        cmd: Incoming joint command.

    Returns:
        Tuple of (safe_torques, safe_velocities, status).
    """
    lib = get_lib()
    safe_tau = SafeTorqueArray()
    safe_vel = SafeVelocityArray()
    status = ctypes.c_int32(0)
    lib.halos_kinematics_intercept_cmd(
        ctypes.byref(state),
        ctypes.byref(cmd),
        ctypes.byref(safe_tau),
        ctypes.byref(safe_vel),
        ctypes.byref(status),
    )
    return [float(x) for x in safe_tau], [float(x) for x in safe_vel], HalosHsmStatus(status.value)


def composed_gate_create(start_ns: int = 1_000_000) -> HalosComposedGate:
    """Create initialized composed safety gate.

    Args:
        start_ns: Initial boot timestamp in nanoseconds.

    Returns:
        Initialized HalosComposedGate.
    """
    lib = get_lib()
    gate = HalosComposedGate()
    lib.halos_composed_gate_init(ctypes.byref(gate), ctypes.c_uint64(start_ns))
    return gate


def composed_gate_intercept(
    gate: HalosComposedGate, cmd: HalosKinematicCmd, now_ns: int
) -> tuple[list[float], list[float], HalosHsmStatus]:
    """Execute composed safety gate interceptor.

    Args:
        gate: Composed gate instance.
        cmd: Incoming joint command.
        now_ns: Current timestamp in nanoseconds.

    Returns:
        Tuple of (safe_torques, safe_velocities, status).
    """
    lib = get_lib()
    safe_tau = SafeTorqueArray()
    safe_vel = SafeVelocityArray()
    status = ctypes.c_int32(0)
    lib.halos_composed_gate_intercept_cmd(
        ctypes.byref(gate),
        ctypes.byref(cmd),
        ctypes.c_uint64(now_ns),
        ctypes.byref(safe_tau),
        ctypes.byref(safe_vel),
        ctypes.byref(status),
    )
    return [float(x) for x in safe_tau], [float(x) for x in safe_vel], HalosHsmStatus(status.value)


def mailbox_create(channel_id: int = 1) -> tuple[AegisMailboxChannel, HalosMailboxStatus]:
    """Create initialized inter-VM SPSC mailbox with guaranteed 64-byte alignment.

    Args:
        channel_id: Unique 32-bit channel identifier.

    Returns:
        Tuple of (channel instance, status).
    """
    lib = get_lib()
    buf = (ctypes.c_uint8 * (ctypes.sizeof(AegisMailboxChannel) + 64))()
    addr = ctypes.addressof(buf)
    offset = (64 - (addr % 64)) % 64
    chan = AegisMailboxChannel.from_address(addr + offset)
    chan._backing_buf = buf
    rc = lib.aegis_mailbox_init(ctypes.byref(chan), ctypes.c_uint32(channel_id))
    return chan, HalosMailboxStatus(rc)


def mailbox_push(
    chan: AegisMailboxChannel,
    msg_type: HalosMsgType,
    flags: int,
    now_ns: int,
    payload: HalosTrajectoryPayload,
) -> HalosMailboxStatus:
    """Push message to SPSC mailbox.

    Args:
        chan: Mailbox channel instance.
        msg_type: Message type identifier.
        flags: 32-bit flags.
        now_ns: Current timestamp in nanoseconds.
        payload: Trajectory payload.

    Returns:
        Mailbox push status.
    """
    lib = get_lib()
    rc = lib.aegis_mailbox_try_push(
        ctypes.byref(chan),
        ctypes.c_uint32(int(msg_type)),
        ctypes.c_uint32(flags),
        ctypes.c_uint64(now_ns),
        ctypes.byref(payload),
    )
    return HalosMailboxStatus(rc)


def mailbox_pop(chan: AegisMailboxChannel, now_ns: int) -> tuple[HalosMailboxMsg, HalosMailboxStatus]:
    """Pop message from SPSC mailbox.

    Args:
        chan: Mailbox channel instance.
        now_ns: Current timestamp in nanoseconds.

    Returns:
        Tuple of (popped message, status).
    """
    lib = get_lib()
    msg = HalosMailboxMsg()
    rc = lib.aegis_mailbox_try_pop(ctypes.byref(chan), ctypes.c_uint64(now_ns), ctypes.byref(msg))
    return msg, HalosMailboxStatus(rc)


def mailbox_crc(payload: HalosTrajectoryPayload) -> int:
    """Calculate CRC-32 of trajectory payload.

    Args:
        payload: Trajectory payload instance.

    Returns:
        32-bit unsigned CRC value.
    """
    lib = get_lib()
    return int(lib.aegis_mailbox_crc32(ctypes.byref(payload)))
