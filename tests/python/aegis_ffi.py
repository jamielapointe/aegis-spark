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
