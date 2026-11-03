"""Hypothesis property-based fuzzing suite verifying Aegis-SPARK safety kernel invariants."""

import math

from hypothesis import given
from hypothesis import settings
from hypothesis import strategies as st

from tests.python.aegis_ffi import HALOS_DOF_COUNT
from tests.python.aegis_ffi import HALOS_MAX_CMD_AGE_NS
from tests.python.aegis_ffi import MAX_HARDWARE_TORQUE_NM
from tests.python.aegis_ffi import HalosJointCmd
from tests.python.aegis_ffi import HalosSafetyEnvelope
from tests.python.aegis_ffi import HalosSafetyState
from tests.python.aegis_ffi import HalosStatus
from tests.python.aegis_ffi import get_mock_uart0_baud
from tests.python.aegis_ffi import get_mock_uart0_cr
from tests.python.aegis_ffi import get_mock_uart0_dr
from tests.python.aegis_ffi import get_mock_uart0_sr
from tests.python.aegis_ffi import intercept_joint_cmd
from tests.python.aegis_ffi import set_mock_uart0_baud
from tests.python.aegis_ffi import set_mock_uart0_cr
from tests.python.aegis_ffi import set_mock_uart0_dr
from tests.python.aegis_ffi import set_mock_uart0_sr


def create_envelope(
    state: HalosSafetyState = HalosSafetyState.HALOS_STATE_ACTIVE,
    limit: float = 100.0,
) -> HalosSafetyEnvelope:
    """Helper to instantiate HalosSafetyEnvelope with uniform limits.

    Args:
        state: Initial safety state.
        limit: Uniform torque limit per joint in Nm.

    Returns:
        Configured HalosSafetyEnvelope instance.
    """
    env = HalosSafetyEnvelope()
    env.state = int(state)
    for i in range(HALOS_DOF_COUNT):
        env.max_abs_torque_nm[i] = limit
    return env


def create_cmd(timestamp_ns: int, torques: list[float]) -> HalosJointCmd:
    """Helper to instantiate HalosJointCmd.

    Args:
        timestamp_ns: Nanosecond timestamp of command.
        torques: List of 6 joint torques.

    Returns:
        Configured HalosJointCmd instance.
    """
    cmd = HalosJointCmd()
    cmd.timestamp_ns = timestamp_ns
    for i in range(HALOS_DOF_COUNT):
        cmd.desired_torque_nm[i] = torques[i]
    return cmd


# Strategy generating arbitrary 6-DOF float arrays including NaN, +/-Inf, denormals
arbitrary_torques = st.lists(
    st.floats(allow_nan=True, allow_infinity=True, width=32),
    min_size=HALOS_DOF_COUNT,
    max_size=HALOS_DOF_COUNT,
)

# Strategy generating valid in-bounds torques
valid_torques = st.lists(
    st.floats(min_value=-100.0, max_value=100.0, allow_nan=False, allow_infinity=False, width=32),
    min_size=HALOS_DOF_COUNT,
    max_size=HALOS_DOF_COUNT,
)

# Strategy generating arbitrary 64-bit unsigned timestamps
timestamps = st.integers(min_value=0, max_value=2**64 - 1)


@settings(max_examples=200, deadline=None)
@given(
    torques=arbitrary_torques,
    cmd_ts=st.integers(min_value=1_000_000, max_value=100_000_000),
    now_delta_ns=st.integers(min_value=-10_000_000, max_value=20_000_000),
)
def test_invariant_1_zero_torque_on_error(
    torques: list[float],
    cmd_ts: int,
    now_delta_ns: int,
) -> None:
    """Invariant 1: Any fault condition strictly produces 0.0 Nm on all joints."""
    now_ns = max(0, cmd_ts + now_delta_ns)
    env = create_envelope(state=HalosSafetyState.HALOS_STATE_ACTIVE, limit=100.0)
    cmd = create_cmd(cmd_ts, torques)

    _updated_env, safe_torques, status = intercept_joint_cmd(env, cmd, now_ns)

    if status != HalosStatus.HALOS_OK:
        assert all(math.isclose(t, 0.0, abs_tol=1e-7) for t in safe_torques), (
            f'Expected zero torques on error status={status}, got {safe_torques}'
        )


@settings(max_examples=100, deadline=None)
@given(
    fault_torques=arbitrary_torques,
    nominal_torques=valid_torques,
    cmd_ts=st.integers(min_value=1_000_000, max_value=100_000_000),
)
def test_invariant_2_fault_latch_immutability(
    fault_torques: list[float],
    nominal_torques: list[float],
    cmd_ts: int,
) -> None:
    """Invariant 2: Once in FAULT_ESTOP, subsequent commands are permanently rejected."""
    # Step 1: Force a fault latch using fault_torques if active, or pre-latched state
    env = create_envelope(state=HalosSafetyState.HALOS_STATE_ACTIVE, limit=100.0)
    cmd_fault = create_cmd(cmd_ts, fault_torques)
    stale_ns = cmd_ts + 10_000_000  # Stale heartbeat forces FAULT_ESTOP
    env_latched, _, _ = intercept_joint_cmd(env, cmd_fault, stale_ns)
    assert env_latched.state == HalosSafetyState.HALOS_STATE_FAULT_ESTOP

    # Step 2: Send completely fresh, valid nominal command to the latched safety gate
    now_ns = cmd_ts + 1_000_000
    cmd_nominal = create_cmd(cmd_ts, nominal_torques)
    updated_env, safe_torques, status = intercept_joint_cmd(env_latched, cmd_nominal, now_ns)

    assert status == HalosStatus.HALOS_ERR_NOT_ACTIVE
    assert updated_env.state == HalosSafetyState.HALOS_STATE_FAULT_ESTOP
    assert all(math.isclose(t, 0.0, abs_tol=1e-7) for t in safe_torques)


@settings(max_examples=100, deadline=None)
@given(
    torques=valid_torques,
    cmd_ts=st.integers(min_value=1_000_000, max_value=100_000_000),
    latency_ns=st.integers(min_value=0, max_value=HALOS_MAX_CMD_AGE_NS),
)
def test_invariant_3_strict_limits_on_success(
    torques: list[float],
    cmd_ts: int,
    latency_ns: int,
) -> None:
    """Invariant 3: On success, safe torques match input and stay strictly within limits."""
    now_ns = cmd_ts + latency_ns
    env = create_envelope(state=HalosSafetyState.HALOS_STATE_ACTIVE, limit=100.0)
    cmd = create_cmd(cmd_ts, torques)

    updated_env, safe_torques, status = intercept_joint_cmd(env, cmd, now_ns)

    if status == HalosStatus.HALOS_OK:
        assert updated_env.state == HalosSafetyState.HALOS_STATE_ACTIVE
        for i in range(HALOS_DOF_COUNT):
            assert abs(safe_torques[i]) <= env.max_abs_torque_nm[i]
            assert abs(safe_torques[i]) <= MAX_HARDWARE_TORQUE_NM
            assert math.isclose(safe_torques[i], torques[i], rel_tol=1e-5, abs_tol=1e-5)


@settings(max_examples=100, deadline=None)
@given(
    torques=arbitrary_torques,
    cmd_ts=timestamps,
    now_ns=timestamps,
)
def test_invariant_4_zero_unhandled_crashes(
    torques: list[float],
    cmd_ts: int,
    now_ns: int,
) -> None:
    """Invariant 4: The safety gate never panics, segfaults, or aborts on arbitrary inputs."""
    env = create_envelope(state=HalosSafetyState.HALOS_STATE_ACTIVE, limit=100.0)
    cmd = create_cmd(cmd_ts, torques)

    _updated_env, safe_torques, status = intercept_joint_cmd(env, cmd, now_ns)
    assert isinstance(status, HalosStatus)
    assert len(safe_torques) == HALOS_DOF_COUNT


@settings(max_examples=100, deadline=None)
@given(
    torques=valid_torques,
    cmd_ts=st.integers(min_value=10_000_000, max_value=100_000_000),
    invalid_delta=st.one_of(
        st.integers(min_value=-50_000_000, max_value=-1),  # clock rewind
        st.integers(min_value=HALOS_MAX_CMD_AGE_NS + 1, max_value=20_000_000),  # stale
    ),
)
def test_invariant_5_monotonic_timestamps_and_freshness(
    torques: list[float],
    cmd_ts: int,
    invalid_delta: int,
) -> None:
    """Invariant 5: Clock rewind or stale heartbeat is rejected and latches FAULT_ESTOP."""
    now_ns = max(0, cmd_ts + invalid_delta)
    env = create_envelope(state=HalosSafetyState.HALOS_STATE_ACTIVE, limit=100.0)
    cmd = create_cmd(cmd_ts, torques)

    updated_env, safe_torques, status = intercept_joint_cmd(env, cmd, now_ns)

    assert status == HalosStatus.HALOS_ERR_STALE_HEARTBEAT
    assert updated_env.state == HalosSafetyState.HALOS_STATE_FAULT_ESTOP
    assert all(math.isclose(t, 0.0, abs_tol=1e-7) for t in safe_torques)


def test_mock_mmio_registers_python_access() -> None:
    """Verify that Python ctypes can read and write in-RAM mock MMIO registers without SIGSEGV."""
    set_mock_uart0_dr(0x42)
    assert get_mock_uart0_dr() & 0xFF == 0x42

    set_mock_uart0_sr(0x05)
    assert get_mock_uart0_sr() & 0x0F == 0x05

    set_mock_uart0_cr(0x83)
    assert get_mock_uart0_cr() & 0xFF == 0x83

    set_mock_uart0_baud(115200)
    assert get_mock_uart0_baud() == 115200
