"""Automated test suite verifying the untrusted AI trajectory planner and SPARK safety supervisor."""

import io
import math

import pytest

from simulation.agent_planner_demo.agent import TrajectoryPlannerAgent
from simulation.agent_planner_demo.agent import inject_fault_test_pattern
from simulation.agent_planner_demo.agent import inspect_safety_limits
from simulation.agent_planner_demo.agent import plan_trajectory_waypoint
from simulation.agent_planner_demo.runner import SimulationConfig
from simulation.agent_planner_demo.runner import main
from simulation.agent_planner_demo.runner import run_simulation
from simulation.agent_planner_demo.safety_bridge import SafetyBridge
from simulation.agent_planner_demo.telemetry import TelemetryDashboard
from simulation.agent_planner_demo.trajectory import TrajectoryGenerator
from simulation.agent_planner_demo.trajectory import TrajectoryMode
from tests.python.aegis_ffi import HALOS_DOF_COUNT
from tests.python.aegis_ffi import HALOS_HSM_RESET_MAGIC
from tests.python.aegis_ffi import HalosFaultCode
from tests.python.aegis_ffi import HalosHsmState
from tests.python.aegis_ffi import HalosHsmStatus


@pytest.mark.unit
def test_antigravity_agent_initialization_and_metadata() -> None:
    """Verify that TrajectoryPlannerAgent initializes offline without external API keys."""
    agent = TrajectoryPlannerAgent()
    assert agent.model_name == 'mock-trajectory-planner-v1'

    caps = agent.describe_capabilities()
    assert caps['offline_only'] is True
    assert caps['external_api_keys_required'] is False
    assert caps['dof'] == HALOS_DOF_COUNT
    assert math.isclose(caps['limits']['max_torque_nm'], 50.0)

    # Verify custom tools
    wp_str = plan_trajectory_waypoint(1, 6)
    assert 'Step 1' in wp_str
    assert '6-DOF' in wp_str

    limits_str = inspect_safety_limits()
    assert '50.0 Nm' in limits_str
    assert '[0.5ms, 5.0ms]' in limits_str

    fault_str = inject_fault_test_pattern('torque', 10)
    assert 'Step 10' in fault_str
    assert 'torque' in fault_str


@pytest.mark.unit
def test_nominal_trajectory_streaming_passes_safely() -> None:
    """Verify that nominal 6-DOF trajectory commands pass through the SPARK safety gate untouched."""
    agent = TrajectoryPlannerAgent(start_ns=1_000_000)
    bridge = SafetyBridge(start_ns=1_000_000)

    for step in range(25):
        cmd = agent.generate_command(step=step, mode=TrajectoryMode.NOMINAL)
        res = bridge.intercept(cmd)

        assert res.is_safe is True
        assert res.status == HalosHsmStatus.HALOS_HSM_OK
        assert res.hsm_state == HalosHsmState.HALOS_HSM_ACTIVE
        assert res.last_fault_code == HalosFaultCode.HALOS_FAULT_NONE

        for i in range(HALOS_DOF_COUNT):
            assert math.isclose(res.safe_torque_nm[i], cmd.torque_nm[i], abs_tol=1e-5)
            assert math.isclose(res.safe_velocity_rad[i], cmd.velocity_rad[i], abs_tol=1e-5)


@pytest.mark.unit
def test_adversarial_overtorque_injection_clamped_to_zero() -> None:
    """Verify that out-of-envelope torques (>50.0 Nm) are clamped strictly to 0.0 Nm in Fault_Estop."""
    agent = TrajectoryPlannerAgent(start_ns=1_000_000)
    bridge = SafetyBridge(start_ns=1_000_000)

    # Step 0: Nominal
    cmd_nom = agent.generate_command(step=0, mode=TrajectoryMode.NOMINAL)
    res_nom = bridge.intercept(cmd_nom)
    assert res_nom.is_safe is True

    # Step 1: Over-torque spike (+75.0 Nm on Joint 0)
    cmd_fault = agent.generate_command(step=1, mode=TrajectoryMode.ADVERSARIAL_TORQUE)
    assert cmd_fault.torque_nm[0] > 50.0

    res_fault = bridge.intercept(cmd_fault)
    assert res_fault.is_safe is False
    assert res_fault.status != HalosHsmStatus.HALOS_HSM_OK
    assert res_fault.hsm_state == HalosHsmState.HALOS_HSM_FAULT_ESTOP
    assert res_fault.last_fault_code == HalosFaultCode.HALOS_FAULT_KINEMATIC_TORQUE

    # Invariant 1: All safe torques and velocities must be strictly 0.0
    for i in range(HALOS_DOF_COUNT):
        assert math.isclose(res_fault.safe_torque_nm[i], 0.0, abs_tol=1e-7)
        assert math.isclose(res_fault.safe_velocity_rad[i], 0.0, abs_tol=1e-7)


@pytest.mark.unit
def test_adversarial_excessive_jerk_clamped_to_zero() -> None:
    """Verify that excessive step torque jumps (>25.0 Nm) are clamped strictly to 0.0 Nm."""
    agent = TrajectoryPlannerAgent(start_ns=1_000_000)
    bridge = SafetyBridge(start_ns=1_000_000)

    # Step 0: Nominal
    cmd_nom = agent.generate_command(step=0, mode=TrajectoryMode.NOMINAL)
    bridge.intercept(cmd_nom)

    # Step 1: Jerk violation (+35.0 Nm jump on Joint 0)
    cmd_jerk = agent.generate_command(step=1, mode=TrajectoryMode.ADVERSARIAL_JERK)
    res_jerk = bridge.intercept(cmd_jerk)

    assert res_jerk.is_safe is False
    assert res_jerk.hsm_state == HalosHsmState.HALOS_HSM_FAULT_ESTOP
    assert res_jerk.last_fault_code == HalosFaultCode.HALOS_FAULT_KINEMATIC_JERK
    for i in range(HALOS_DOF_COUNT):
        assert math.isclose(res_jerk.safe_torque_nm[i], 0.0, abs_tol=1e-7)


@pytest.mark.unit
def test_adversarial_non_finite_nan_injection_clamped_to_zero() -> None:
    """Verify that IEEE-754 NaN inputs are caught at C23 ABI boundary and clamped to 0.0 Nm."""
    agent = TrajectoryPlannerAgent(start_ns=1_000_000)
    bridge = SafetyBridge(start_ns=1_000_000)

    cmd_nan = agent.generate_command(step=0, mode=TrajectoryMode.ADVERSARIAL_NON_FINITE)
    assert math.isnan(cmd_nan.torque_nm[0])

    res_nan = bridge.intercept(cmd_nan)
    assert res_nan.is_safe is False
    assert res_nan.hsm_state == HalosHsmState.HALOS_HSM_FAULT_ESTOP
    assert res_nan.last_fault_code == HalosFaultCode.HALOS_FAULT_NON_FINITE_INPUT
    for i in range(HALOS_DOF_COUNT):
        assert math.isclose(res_nan.safe_torque_nm[i], 0.0, abs_tol=1e-7)


@pytest.mark.unit
def test_watchdog_timeout_and_fault_latching() -> None:
    """Verify watchdog window timeout (>5.0ms) transitions to Fault_Estop and latches immutably."""
    agent = TrajectoryPlannerAgent(start_ns=1_000_000)
    bridge = SafetyBridge(start_ns=1_000_000)

    # Step 0: Nominal
    bridge.intercept(agent.generate_command(step=0, mode=TrajectoryMode.NOMINAL))

    # Step 1: Watchdog timeout (10 ms jump since last pet > 5 ms limit)
    cmd_wd = agent.generate_command(step=1, mode=TrajectoryMode.ADVERSARIAL_STALE_WD)
    res_wd = bridge.intercept(cmd_wd)

    assert res_wd.is_safe is False
    assert res_wd.hsm_state == HalosHsmState.HALOS_HSM_FAULT_ESTOP
    assert res_wd.last_fault_code == HalosFaultCode.HALOS_FAULT_WATCHDOG_TIMEOUT

    # Safety Invariant 2 (Fault Latch Immutability): Subsequent nominal commands remain blocked
    for step in range(2, 6):
        cmd_subsequent = agent.generate_command(step=step, mode=TrajectoryMode.NOMINAL)
        res_sub = bridge.intercept(cmd_subsequent)
        assert res_sub.is_safe is False
        assert res_sub.hsm_state == HalosHsmState.HALOS_HSM_FAULT_ESTOP
        for i in range(HALOS_DOF_COUNT):
            assert math.isclose(res_sub.safe_torque_nm[i], 0.0, abs_tol=1e-7)


@pytest.mark.unit
def test_safety_bridge_authorized_recovery() -> None:
    """Verify authorized reset transitions from Fault_Estop back to Active state."""
    agent = TrajectoryPlannerAgent(start_ns=1_000_000)
    bridge = SafetyBridge(start_ns=1_000_000)

    # Trigger fault
    cmd_fault = agent.generate_command(step=0, mode=TrajectoryMode.ADVERSARIAL_TORQUE)
    res_fault = bridge.intercept(cmd_fault)
    assert res_fault.is_safe is False
    fault_state = bridge.hsm_state
    assert fault_state == HalosHsmState.HALOS_HSM_FAULT_ESTOP

    # Reset with valid magic key and current timestamp
    recovered = bridge.reset_fault(resume_timestamp_ns=agent.current_timestamp_ns)
    assert recovered is True
    active_state = bridge.hsm_state
    assert active_state == HalosHsmState.HALOS_HSM_ACTIVE

    # Post-reset command should stream normally
    cmd_post = agent.generate_command(step=1, mode=TrajectoryMode.NOMINAL)
    res_post = bridge.intercept(cmd_post)
    assert res_post.is_safe is True
    post_state = bridge.hsm_state
    assert post_state == HalosHsmState.HALOS_HSM_ACTIVE


@pytest.mark.unit
def test_safety_bridge_reset_fault_rejected_when_active() -> None:
    """Verify that resetting while in Active state is rejected without mutating state."""
    bridge = SafetyBridge(start_ns=1_000_000)
    assert bridge.hsm_state == HalosHsmState.HALOS_HSM_ACTIVE
    initial_transitions = bridge.transition_count

    # Attempt reset while in ACTIVE state (illegal state transition)
    rejected = bridge.reset_fault(resume_timestamp_ns=2_000_000)
    assert rejected is False
    assert bridge.hsm_state == HalosHsmState.HALOS_HSM_ACTIVE
    assert bridge.transition_count == initial_transitions

    # Attempt reset with explicit magic key while in ACTIVE state
    rejected_magic = bridge.reset_fault(
        resume_timestamp_ns=3_000_000,
        reset_key=HALOS_HSM_RESET_MAGIC,
    )
    assert rejected_magic is False
    assert bridge.hsm_state == HalosHsmState.HALOS_HSM_ACTIVE
    assert bridge.transition_count == initial_transitions


@pytest.mark.unit
def test_safety_bridge_reset_fault_rejected_with_invalid_key() -> None:
    """Verify that resetting Fault_Estop with an invalid token is rejected and latches state."""
    agent = TrajectoryPlannerAgent(start_ns=1_000_000)
    bridge = SafetyBridge(start_ns=1_000_000)

    # Induce fault via adversarial torque
    cmd_fault = agent.generate_command(step=0, mode=TrajectoryMode.ADVERSARIAL_TORQUE)
    res_fault = bridge.intercept(cmd_fault)
    assert res_fault.is_safe is False
    fault_state = bridge.hsm_state
    assert fault_state == HalosHsmState.HALOS_HSM_FAULT_ESTOP
    fault1_code = bridge.last_fault_code
    assert fault1_code == HalosFaultCode.HALOS_FAULT_KINEMATIC_TORQUE
    fault_transitions = bridge.transition_count

    # Negative test 1: Arbitrary invalid key
    res_bad1 = bridge.reset_fault(
        resume_timestamp_ns=agent.current_timestamp_ns,
        reset_key=0xDEADBEEF,
    )
    assert res_bad1 is False
    bad1_state = bridge.hsm_state
    assert bad1_state == HalosHsmState.HALOS_HSM_FAULT_ESTOP
    bad1_fault = bridge.last_fault_code
    assert bad1_fault == HalosFaultCode.HALOS_FAULT_KINEMATIC_TORQUE
    assert bridge.transition_count == fault_transitions

    # Negative test 2: Zero key
    res_bad2 = bridge.reset_fault(
        resume_timestamp_ns=agent.current_timestamp_ns,
        reset_key=0,
    )
    assert res_bad2 is False
    bad2_state = bridge.hsm_state
    assert bad2_state == HalosHsmState.HALOS_HSM_FAULT_ESTOP
    assert bridge.transition_count == fault_transitions

    # Safety Invariant 2: Commands remain clamped to 0.0 Nm under failed reset
    cmd_subsequent = agent.generate_command(step=1, mode=TrajectoryMode.NOMINAL)
    res_sub = bridge.intercept(cmd_subsequent)
    assert res_sub.is_safe is False
    assert res_sub.hsm_state == HalosHsmState.HALOS_HSM_FAULT_ESTOP
    for i in range(HALOS_DOF_COUNT):
        assert math.isclose(res_sub.safe_torque_nm[i], 0.0, abs_tol=1e-7)

    # Positive recovery: Authorized magic key successfully resets the latch
    res_good = bridge.reset_fault(
        resume_timestamp_ns=agent.current_timestamp_ns,
        reset_key=HALOS_HSM_RESET_MAGIC,
    )
    assert res_good is True
    active_state = bridge.hsm_state
    assert active_state == HalosHsmState.HALOS_HSM_ACTIVE
    last_fault = bridge.last_fault_code
    assert last_fault == HalosFaultCode.HALOS_FAULT_NONE

    # Post-recovery commands pass through nominally
    cmd_post = agent.generate_command(step=2, mode=TrajectoryMode.NOMINAL)
    res_post = bridge.intercept(cmd_post)
    assert res_post.is_safe is True


@pytest.mark.unit
def test_headless_telemetry_rendering() -> None:
    """Verify headless telemetry rendering to a string stream without TTY alternate screen."""
    buf = io.StringIO()
    dashboard = TelemetryDashboard(headless=True, file=buf)
    assert dashboard.is_headless is True

    dashboard.start()
    generator = TrajectoryGenerator(start_ns=1_000_000)
    bridge = SafetyBridge(start_ns=1_000_000)

    # Render step 0 (multiple of 10)
    cmd = generator.generate_step(0, mode=TrajectoryMode.NOMINAL)
    res = bridge.intercept(cmd)
    dashboard.render_step(res, total_steps=10)

    # Render fault step
    cmd_fault = generator.generate_step(1, mode=TrajectoryMode.ADVERSARIAL_TORQUE)
    res_fault = bridge.intercept(cmd_fault)
    dashboard.render_step(res_fault, total_steps=10)
    dashboard.stop()

    output = buf.getvalue()
    assert 'Aegis-SPARK: NVIDIA Halos / IGX Thor FSI Safety Supervisor' in output
    assert 'ACTIVE' in output
    assert 'FAULT_ESTOP' in output
    assert 'CLAMPED 0.0' in output


@pytest.mark.unit
def test_cli_runner_execution() -> None:
    """Verify full CLI simulation execution across nominal, adversarial, and all scenarios."""
    # Test nominal
    cfg_nom = SimulationConfig(steps=15, rate_hz=0.0, headless=True, mode='nominal')
    results_nom = run_simulation(cfg_nom)
    assert len(results_nom) == 15
    assert all(r.is_safe for r in results_nom)

    # Test adversarial
    cfg_adv = SimulationConfig(steps=25, rate_hz=0.0, adversarial_step=10, headless=True, mode='adversarial')
    results_adv = run_simulation(cfg_adv)
    assert len(results_adv) == 25
    assert all(results_adv[i].is_safe for i in range(10))
    assert all(not results_adv[i].is_safe for i in range(10, 25))

    # Test main entrypoint
    assert main(['--steps', '10', '--headless', '--mode', 'nominal']) == 0
