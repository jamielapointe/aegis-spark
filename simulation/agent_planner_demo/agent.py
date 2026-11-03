"""Google Antigravity SDK untrusted AI trajectory planner agent.

Integrates with a local on-device / mock trajectory model requiring zero external
API keys or remote network calls, simulating the untrusted AI compute domain
(CCPLEX + GPU) that streams kinematic commands to the safety supervisor.
"""

from typing import Any

from google.antigravity import Agent
from google.antigravity import AgentBehavior
from google.antigravity import CapabilitiesConfig
from google.antigravity import LocalOpenAIAgentConfig

from simulation.agent_planner_demo.trajectory import TrajectoryCommand
from simulation.agent_planner_demo.trajectory import TrajectoryGenerator
from simulation.agent_planner_demo.trajectory import TrajectoryLimits
from simulation.agent_planner_demo.trajectory import TrajectoryMode


def plan_trajectory_waypoint(step: int, joint_count: int = 6) -> str:
    """Plans 6-DOF joint trajectory waypoints for robotic manipulator.

    Args:
        step: Monotonic trajectory sequence step index.
        joint_count: Number of robot manipulator degrees of freedom (default 6).

    Returns:
        Summary of the computed kinematic plan.
    """
    return (
        f'Step {step}: Computed nominal {joint_count}-DOF kinematic waypoint with '
        'smooth sine-wave profile within certified physical limits.'
    )


def inspect_safety_limits() -> str:
    """Returns certified safety envelope limits enforced by NVIDIA Halos FSI.

    Returns:
        Text representation of certified physical envelopes.
    """
    limits = TrajectoryLimits()
    return (
        f'Certified Envelope: Position <= {limits.max_position_rad:.2f} rad, '
        f'Velocity <= {limits.max_velocity_rad_s:.1f} rad/s, '
        f'Torque <= {limits.max_torque_nm:.1f} Nm, '
        f'Delta Jerk <= {limits.max_delta_torque_step_nm:.1f} Nm, '
        f'Watchdog Window = [{limits.wd_min_interval_ns / 1e6:.1f}ms, {limits.wd_max_interval_ns / 1e6:.1f}ms].'
    )


def inject_fault_test_pattern(fault_type: str, step: int) -> str:
    """Generates an adversarial out-of-envelope fault test pattern to verify safety gate clamping.

    Args:
        fault_type: Name of fault (torque, jerk, velocity, position, non_finite, stale_wd).
        step: Simulation step where the injection is scheduled.

    Returns:
        Description of synthesized adversarial vector.
    """
    return (
        f'Step {step}: Synthesized adversarial out-of-envelope perturbation: {fault_type} '
        'targeting safety gate deterministic clamping.'
    )


class LocalTrajectoryModel:
    """On-device mock foundation model for trajectory planning without external API keys."""

    def __init__(self, limits: TrajectoryLimits | None = None) -> None:
        """Initialize local trajectory model.

        Args:
            limits: Certified kinematic limits.
        """
        self._limits = limits or TrajectoryLimits()
        self._generator = TrajectoryGenerator(limits=self._limits)

    @property
    def current_timestamp_ns(self) -> int:
        """Current monotonic simulation timestamp."""
        return self._generator.current_timestamp_ns

    def generate_step(
        self,
        step: int,
        mode: TrajectoryMode = TrajectoryMode.NOMINAL,
    ) -> TrajectoryCommand:
        """Compute next 6-DOF joint command packet.

        Args:
            step: Monotonic step count.
            mode: Operational mode.

        Returns:
            Computed TrajectoryCommand.
        """
        return self._generator.generate_step(step, mode=mode)

    def reset(self, start_ns: int = 1_000_000) -> None:
        """Reset internal model state.

        Args:
            start_ns: Reset timestamp in nanoseconds.
        """
        self._generator.reset(start_ns=start_ns)


class TrajectoryPlannerAgent:
    """Google Antigravity SDK Agent for trajectory planning and fault injection."""

    def __init__(
        self,
        model_name: str = 'mock-trajectory-planner-v1',
        step_duration_ns: int = 1_000_000,
        start_ns: int = 1_000_000,
    ) -> None:
        """Initialize Antigravity planner agent with local on-device trajectory model.

        Args:
            model_name: Identifier for the local model.
            step_duration_ns: Step time increment in nanoseconds.
            start_ns: Simulation epoch start timestamp in nanoseconds.
        """
        self._model_name = model_name
        self._limits = TrajectoryLimits()
        self._generator = TrajectoryGenerator(
            step_duration_ns=step_duration_ns,
            start_ns=start_ns,
            limits=self._limits,
        )

        # Configure Google Antigravity Agent using LocalOpenAIAgentConfig with custom tools
        self._config = LocalOpenAIAgentConfig(
            model=model_name,
            base_url='http://127.0.0.1:0/v1',  # Local on-device dummy endpoint (no remote calls)
            capabilities=CapabilitiesConfig(
                agent_behavior=AgentBehavior.AUTONOMOUS,
                enable_subagents=False,
            ),
            tools=[
                plan_trajectory_waypoint,
                inspect_safety_limits,
                inject_fault_test_pattern,
            ],
        )
        self._agent = Agent(config=self._config)

    @property
    def model_name(self) -> str:
        """Name of the trajectory planning model."""
        return self._model_name

    @property
    def config(self) -> LocalOpenAIAgentConfig:
        """Google Antigravity SDK configuration."""
        return self._config

    @property
    def current_timestamp_ns(self) -> int:
        """Current monotonic simulation timestamp in nanoseconds."""
        return self._generator.current_timestamp_ns

    def generate_command(
        self,
        step: int,
        mode: TrajectoryMode = TrajectoryMode.NOMINAL,
    ) -> TrajectoryCommand:
        """Generate 6-DOF joint command for the current step.

        Args:
            step: Simulation step index.
            mode: Operational mode (nominal or specific adversarial attack).

        Returns:
            Constructed TrajectoryCommand ready for safety interception.
        """
        return self._generator.generate_step(step, mode=mode)

    def reset(self, start_ns: int = 1_000_000) -> None:
        """Reset the planner model to epoch.

        Args:
            start_ns: Reset timestamp in nanoseconds.
        """
        self._generator.reset(start_ns=start_ns)

    def describe_capabilities(self) -> dict[str, Any]:
        """Return metadata describing agent capabilities and safety parameters.

        Returns:
            Dictionary containing model configuration and physical limits.
        """
        return {
            'model': self._model_name,
            'offline_only': True,
            'external_api_keys_required': False,
            'dof': 6,
            'limits': {
                'max_position_rad': self._limits.max_position_rad,
                'max_velocity_rad_s': self._limits.max_velocity_rad_s,
                'max_torque_nm': self._limits.max_torque_nm,
                'max_delta_torque_step_nm': self._limits.max_delta_torque_step_nm,
                'wd_window_ms': [
                    self._limits.wd_min_interval_ns / 1e6,
                    self._limits.wd_max_interval_ns / 1e6,
                ],
            },
        }
