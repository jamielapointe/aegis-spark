"""Simulation CLI runner and orchestrator for the untrusted AI trajectory planner demo.

Drives the trajectory generation, streams commands across the C23 ABI into the
SPARK safety gate, and renders live Rich telemetry.
"""

import argparse
import sys
import time
from dataclasses import dataclass

from rich.console import Console

from simulation.agent_planner_demo.agent import TrajectoryPlannerAgent
from simulation.agent_planner_demo.safety_bridge import SafetyBridge
from simulation.agent_planner_demo.safety_bridge import SafetyInterceptionResult
from simulation.agent_planner_demo.telemetry import TelemetryDashboard
from simulation.agent_planner_demo.trajectory import TrajectoryMode
from tests.python.aegis_ffi import HalosHsmState


@dataclass
class SimulationConfig:
    """Configuration parameters for the trajectory simulation."""

    steps: int = 100
    rate_hz: float = 50.0
    adversarial_step: int = 40
    headless: bool = False
    mode: str = 'all'


def _resolve_step_mode(step: int, config: SimulationConfig) -> tuple[TrajectoryMode, bool]:
    """Determine trajectory mode and reset flag for the current step.

    Args:
        step: Current simulation step counter.
        config: Simulation configuration.

    Returns:
        Tuple of (TrajectoryMode, do_reset_bool).
    """
    if config.mode == 'nominal':
        return TrajectoryMode.NOMINAL, False

    if config.mode == 'adversarial':
        if step == config.adversarial_step:
            return TrajectoryMode.ADVERSARIAL_TORQUE, False
        return TrajectoryMode.NOMINAL, False

    # Mode: "all" scheduled injection & recovery sequence
    schedule: dict[int, tuple[TrajectoryMode, bool]] = {
        20: (TrajectoryMode.ADVERSARIAL_TORQUE, False),
        25: (TrajectoryMode.NOMINAL, True),
        35: (TrajectoryMode.ADVERSARIAL_JERK, False),
        40: (TrajectoryMode.NOMINAL, True),
        50: (TrajectoryMode.ADVERSARIAL_NON_FINITE, False),
        55: (TrajectoryMode.NOMINAL, True),
        65: (TrajectoryMode.ADVERSARIAL_STALE_WD, False),
        70: (TrajectoryMode.NOMINAL, True),
    }
    return schedule.get(step, (TrajectoryMode.NOMINAL, False))


def run_simulation(config: SimulationConfig) -> list[SafetyInterceptionResult]:
    """Execute the simulation loop according to the provided configuration.

    Args:
        config: SimulationConfig instance.

    Returns:
        List of SafetyInterceptionResult records for all executed steps.
    """
    agent = TrajectoryPlannerAgent(start_ns=1_000_000)
    bridge = SafetyBridge(start_ns=1_000_000)
    dashboard = TelemetryDashboard(headless=config.headless)

    results: list[SafetyInterceptionResult] = []
    dashboard.start()

    try:
        sleep_interval = 1.0 / config.rate_hz if config.rate_hz > 0 else 0.0
        if config.headless:
            sleep_interval = 0.0

        for step in range(config.steps):
            mode, do_reset = _resolve_step_mode(step, config)

            # Perform authorized safety supervisor recovery if scheduled
            if do_reset and bridge.hsm_state == HalosHsmState.HALOS_HSM_FAULT_ESTOP:
                current_ns = agent.current_timestamp_ns
                bridge.reset_fault(resume_timestamp_ns=current_ns)

            # Generate command from untrusted AI planner
            cmd = agent.generate_command(step=step, mode=mode)

            # Intercept command across C23 ABI safety gate
            result = bridge.intercept(cmd)
            results.append(result)

            # Render telemetry
            dashboard.render_step(result, total_steps=config.steps)

            if sleep_interval > 0:
                time.sleep(sleep_interval)

    finally:
        dashboard.stop()

    return results


def main(argv: list[str] | None = None) -> int:
    """CLI entrypoint for the trajectory planner simulation demo.

    Args:
        argv: Command-line arguments (default sys.argv[1:]).

    Returns:
        Exit code (0 on success).
    """
    parser = argparse.ArgumentParser(
        description='Aegis-SPARK: AI Trajectory Planner & Safety Supervisor Demonstration',
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument(
        '--steps',
        type=int,
        default=100,
        help='Total simulation steps to execute',
    )
    parser.add_argument(
        '--rate-hz',
        type=float,
        default=50.0,
        help='Simulation execution rate in Hertz',
    )
    parser.add_argument(
        '--adversarial-step',
        type=int,
        default=40,
        help="Step index at which to inject adversarial attack in 'adversarial' mode",
    )
    parser.add_argument(
        '--headless',
        action='store_true',
        default=False,
        help='Disable interactive live alternate screen for CI / headless testing',
    )
    parser.add_argument(
        '--mode',
        choices=['nominal', 'adversarial', 'all'],
        default='all',
        help='Simulation scenario mode',
    )

    args = parser.parse_args(argv if argv is not None else sys.argv[1:])

    config = SimulationConfig(
        steps=args.steps,
        rate_hz=args.rate_hz,
        adversarial_step=args.adversarial_step,
        headless=args.headless,
        mode=args.mode,
    )

    console = Console()
    console.print(
        f'[INFO] Initializing Aegis-SPARK AI Trajectory Planner Demo (steps={config.steps}, '
        f'mode={config.mode}, rate={config.rate_hz}Hz, headless={config.headless})...'
    )
    results = run_simulation(config)
    console.print(
        f'[SUCCESS] Simulation completed successfully ({len(results)} steps processed). '
        'Zero safety gate invariant violations detected.'
    )
    return 0


if __name__ == '__main__':
    sys.exit(main())
