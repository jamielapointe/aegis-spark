"""6-DOF robot trajectory generation and adversarial injection module.

Generates nominal joint trajectories within certified physical limits and
synthesizes out-of-envelope adversarial attacks to test deterministic clamping
and fail-safe latching by the SPARK safety gate.
"""

import math
from dataclasses import dataclass
from enum import StrEnum


class TrajectoryMode(StrEnum):
    """Trajectory generation and attack mode."""

    NOMINAL = 'nominal'
    ADVERSARIAL_TORQUE = 'adversarial_torque'
    ADVERSARIAL_JERK = 'adversarial_jerk'
    ADVERSARIAL_VELOCITY = 'adversarial_velocity'
    ADVERSARIAL_POSITION = 'adversarial_position'
    ADVERSARIAL_NON_FINITE = 'adversarial_non_finite'
    ADVERSARIAL_STALE_WD = 'adversarial_stale_wd'
    ALL = 'all'


@dataclass(frozen=True)
class TrajectoryLimits:
    """Certified kinematic and watchdog envelope limits."""

    max_position_rad: float = 3.14159265
    max_velocity_rad_s: float = 10.0
    max_torque_nm: float = 50.0
    max_delta_torque_step_nm: float = 25.0
    wd_min_interval_ns: int = 500_000  # 0.5 ms
    wd_max_interval_ns: int = 5_000_000  # 5.0 ms


@dataclass
class TrajectoryCommand:
    """6-DOF commanded waypoint from untrusted AI planner."""

    step: int
    timestamp_ns: int
    position_rad: list[float]
    velocity_rad: list[float]
    torque_nm: list[float]
    mode: TrajectoryMode
    description: str


class TrajectoryGenerator:
    """Generator for nominal 6-DOF trajectory streaming and adversarial fault injection."""

    def __init__(
        self,
        step_duration_ns: int = 1_000_000,
        start_ns: int = 1_000_000,
        limits: TrajectoryLimits | None = None,
    ) -> None:
        """Initialize trajectory generator.

        Args:
            step_duration_ns: Nominal elapsed time per step (default 1 ms, inside WD window).
            start_ns: Initial simulation timestamp in nanoseconds.
            limits: Envelope limits configuration.
        """
        self._step_duration_ns = step_duration_ns
        self._current_ns = start_ns
        self._limits = limits or TrajectoryLimits()
        self._last_torques: list[float] = [0.0] * 6

    @property
    def current_timestamp_ns(self) -> int:
        """Current monotonic simulation timestamp."""
        return self._current_ns

    def reset(self, start_ns: int = 1_000_000) -> None:
        """Reset internal generator state to boot initial conditions.

        Args:
            start_ns: Reset timestamp in nanoseconds.
        """
        self._current_ns = start_ns
        self._last_torques = [0.0] * 6

    def generate_step(
        self,
        step: int,
        mode: TrajectoryMode = TrajectoryMode.NOMINAL,
    ) -> TrajectoryCommand:
        """Generate joint commands for the specified simulation step.

        Args:
            step: Simulation step counter (0-indexed).
            mode: Mode of operation for this step.

        Returns:
            Constructed TrajectoryCommand packet.
        """
        # Determine time increment based on watchdog attack or nominal timing
        if mode == TrajectoryMode.ADVERSARIAL_STALE_WD:
            # Inject timestamp jump > 5.0 ms (10 ms)
            self._current_ns += 10_000_000
            desc = 'Adversarial: Watchdog timeout (>5.0ms elapsed since last pet)'
        else:
            self._current_ns += self._step_duration_ns
            desc = 'Nominal 6-DOF smooth trajectory'

        t_sec = step * (self._step_duration_ns / 1_000_000_000.0)

        # Baseline nominal smooth sinusoidal kinematics
        pos: list[float] = []
        vel: list[float] = []
        tau: list[float] = []

        for i in range(6):
            freq = 0.5 + 0.1 * i
            pos_amp = 0.5 + 0.1 * i  # max 1.0 rad <= 3.14 rad
            vel_amp = 1.0 + 0.4 * i  # max 3.0 rad/s <= 10.0 rad/s
            tau_amp = 20.0 + 3.0 * i  # max 35.0 Nm <= 50.0 Nm

            p = pos_amp * math.sin(2.0 * math.pi * freq * t_sec)
            v = vel_amp * math.cos(2.0 * math.pi * freq * t_sec)
            t = tau_amp * math.sin(2.0 * math.pi * freq * t_sec)

            pos.append(p)
            vel.append(v)
            tau.append(t)

        # Inject adversarial violations based on requested mode
        if mode == TrajectoryMode.ADVERSARIAL_TORQUE:
            # Spike Joint 0 to 75.0 Nm (> 50.0 Nm limit)
            tau[0] = 75.0
            desc = 'Adversarial: Over-torque spike (+75.0 Nm on Joint 0 > 50.0 Nm limit)'

        elif mode == TrajectoryMode.ADVERSARIAL_JERK:
            # Sudden step change of +35.0 Nm above last commanded torque (> 25.0 Nm delta limit)
            tau[0] = self._last_torques[0] + 35.0
            desc = 'Adversarial: Excessive step jerk (+35.0 Nm delta on Joint 0 > 25.0 Nm limit)'

        elif mode == TrajectoryMode.ADVERSARIAL_VELOCITY:
            # Velocity violation on Joint 1 (> 10.0 rad/s limit)
            vel[1] = 16.0
            desc = 'Adversarial: Over-velocity (+16.0 rad/s on Joint 1 > 10.0 rad/s limit)'

        elif mode == TrajectoryMode.ADVERSARIAL_POSITION:
            # Position envelope breach on Joint 2 (> 3.14 rad limit)
            pos[2] = 4.5
            desc = 'Adversarial: Position envelope breach (+4.5 rad on Joint 2 > 3.14 rad limit)'

        elif mode == TrajectoryMode.ADVERSARIAL_NON_FINITE:
            # IEEE-754 NaN injection on Joint 0
            tau[0] = float('nan')
            desc = 'Adversarial: Non-finite IEEE-754 NaN injection on Joint 0'

        # Update last torques if finite
        self._last_torques = [t if math.isfinite(t) else 0.0 for t in tau]

        return TrajectoryCommand(
            step=step,
            timestamp_ns=self._current_ns,
            position_rad=pos,
            velocity_rad=vel,
            torque_nm=tau,
            mode=mode,
            description=desc,
        )
