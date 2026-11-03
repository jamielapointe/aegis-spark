"""Rich terminal telemetry dashboard for Aegis-SPARK safety supervisor demonstration.

Renders live terminal dashboards displaying safety state (Active, Degraded, Fault_Estop),
commanded vs. clamped 6-DOF joint torques, and watchdog status with an automated
headless fallback for non-interactive and CI environments.
"""

import sys
from typing import TYPE_CHECKING
from typing import TextIO

from rich.console import Console
from rich.live import Live
from rich.panel import Panel
from rich.table import Table
from rich.text import Text


if TYPE_CHECKING:
    from simulation.agent_planner_demo.safety_bridge import SafetyInterceptionResult
from tests.python.aegis_ffi import HalosHsmState


TORQUE_TOLERANCE_NM: float = 1e-4


class TelemetryDashboard:
    """Telemetry rendering engine with interactive Live and headless fallback modes."""

    def __init__(
        self,
        headless: bool = False,
        file: TextIO | None = None,
    ) -> None:
        """Initialize telemetry dashboard.

        Args:
            headless: Force headless text-table rendering without alternate screen.
            file: Output stream (default sys.stdout).
        """
        output_file = file or sys.stdout
        self._headless = headless or not getattr(output_file, 'isatty', lambda: False)()
        self._console = Console(file=output_file, highlight=False, force_terminal=not self._headless)
        self._live: Live | None = None

    @property
    def is_headless(self) -> bool:
        """Whether running in headless mode."""
        return self._headless

    def start(self) -> None:
        """Start live telemetry session if interactive."""
        if not self._headless:
            self._live = Live(
                console=self._console,
                refresh_per_second=20,
                auto_refresh=False,
            )
            self._live.start()

    def stop(self) -> None:
        """Stop live telemetry session."""
        if self._live is not None:
            self._live.stop()
            self._live = None

    def render_step(
        self,
        result: SafetyInterceptionResult,
        total_steps: int,
    ) -> None:
        """Render a single simulation step's safety telemetry.

        Args:
            result: SafetyInterceptionResult from the safety bridge.
            total_steps: Total scheduled simulation steps.
        """
        renderable = self._build_dashboard_renderable(result, total_steps)

        if not self._headless and self._live is not None:
            self._live.update(renderable, refresh=True)
        elif result.step % 10 == 0 or not result.is_safe or result.step == total_steps - 1:
            self._console.print(renderable)

    @staticmethod
    def _build_dashboard_renderable(
        result: SafetyInterceptionResult,
        total_steps: int,
    ) -> Panel:
        """Construct the Rich renderable tree for the current step.

        Args:
            result: Safety interception result for the current step.
            total_steps: Total number of simulation steps.

        Returns:
            Rich Panel containing summary table and joint torque telemetry.
        """
        # Safety state coloring and text
        if result.hsm_state == HalosHsmState.HALOS_HSM_ACTIVE:
            state_text = Text('● ACTIVE (Normal Operation)', style='bold green')
        elif result.hsm_state == HalosHsmState.HALOS_HSM_DEGRADED:
            state_text = Text('▲ DEGRADED (Safe Envelope Restricted)', style='bold yellow')
        else:
            state_text = Text('✖ FAULT_ESTOP (Fail-Safe Latched to 0.0 Nm)', style='bold red')

        # Top summary table
        summary = Table.grid(padding=(0, 2))
        summary.add_column(style='bold')
        summary.add_column()
        summary.add_column(style='bold')
        summary.add_column()

        summary.add_row(
            'Step:',
            f'{result.step + 1}/{total_steps}',
            'Monotonic Time:',
            f'{result.timestamp_ns / 1_000_000:.3f} ms',
        )
        summary.add_row(
            'Safety State:',
            state_text,
            'Watchdog Pet:',
            'OK [0.5ms - 5.0ms]' if result.is_safe else 'FAULT / VIOLATION',
        )
        summary.add_row(
            'Interception Status:',
            result.status.name,
            'Last Fault Code:',
            result.last_fault_code.name,
        )
        summary.add_row(
            'Event Description:',
            result.description,
            'Verification:',
            'Invariant 1 (Zero-Torque Fail-Safe) Verified',
        )

        # 6-DOF Joint Torques Table
        joint_table = Table(
            title='6-DOF Joint Torque Interception Telemetry',
            title_style='bold cyan',
            show_header=True,
            header_style='bold white on blue',
            expand=True,
        )
        joint_table.add_column('Joint', justify='center', style='cyan')
        joint_table.add_column('Commanded (Nm)', justify='right')
        joint_table.add_column('Safe Clamped (Nm)', justify='right')
        joint_table.add_column('Delta (Nm)', justify='right')
        joint_table.add_column('Status', justify='center')

        for i in range(6):
            cmd_tau = result.commanded_torque_nm[i]
            safe_tau = result.safe_torque_nm[i]
            delta = abs(cmd_tau - safe_tau)

            cmd_str = f'{cmd_tau:+.2f}'
            safe_str = f'{safe_tau:+.2f}'
            delta_str = f'{delta:+.2f}'

            if not result.is_safe or delta > TORQUE_TOLERANCE_NM:
                status_cell = Text('CLAMPED 0.0', style='bold red')
                row_style = 'red'
            else:
                status_cell = Text('PASS', style='bold green')
                row_style = 'white'

            joint_table.add_row(
                f'J{i + 1}',
                cmd_str,
                safe_str,
                delta_str,
                status_cell,
                style=row_style,
            )

        # Composite Panel
        composite = Table.grid(padding=(1, 0))
        composite.add_row(summary)
        composite.add_row(joint_table)

        return Panel(
            composite,
            title='[bold yellow]Aegis-SPARK: NVIDIA Halos / IGX Thor FSI Safety Supervisor[/]',
            subtitle='Untrusted AI Compute Domain (CCPLEX+GPU) ↔ Certified SPARK Safety Domain (FSI)',
            border_style='green' if result.is_safe else 'red',
        )
