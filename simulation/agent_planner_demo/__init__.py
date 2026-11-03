"""Aegis-SPARK Untrusted AI Trajectory Planner & Safety Supervisor Demonstration.

Package providing Google Antigravity SDK agent integration, 6-DOF trajectory
generation with adversarial fault injection, C23 ABI bridge to libaegis_spark,
and live Rich terminal telemetry.
"""

from simulation.agent_planner_demo.agent import LocalTrajectoryModel
from simulation.agent_planner_demo.agent import TrajectoryPlannerAgent
from simulation.agent_planner_demo.agent import inject_fault_test_pattern
from simulation.agent_planner_demo.agent import inspect_safety_limits
from simulation.agent_planner_demo.agent import plan_trajectory_waypoint
from simulation.agent_planner_demo.runner import SimulationConfig
from simulation.agent_planner_demo.runner import main
from simulation.agent_planner_demo.runner import run_simulation
from simulation.agent_planner_demo.safety_bridge import SafetyBridge
from simulation.agent_planner_demo.safety_bridge import SafetyInterceptionResult
from simulation.agent_planner_demo.telemetry import TelemetryDashboard
from simulation.agent_planner_demo.trajectory import TrajectoryCommand
from simulation.agent_planner_demo.trajectory import TrajectoryGenerator
from simulation.agent_planner_demo.trajectory import TrajectoryLimits
from simulation.agent_planner_demo.trajectory import TrajectoryMode


__all__ = [
    'LocalTrajectoryModel',
    'SafetyBridge',
    'SafetyInterceptionResult',
    'SimulationConfig',
    'TelemetryDashboard',
    'TrajectoryCommand',
    'TrajectoryGenerator',
    'TrajectoryLimits',
    'TrajectoryMode',
    'TrajectoryPlannerAgent',
    'inject_fault_test_pattern',
    'inspect_safety_limits',
    'main',
    'plan_trajectory_waypoint',
    'run_simulation',
]
