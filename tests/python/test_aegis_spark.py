"""Integration and verification tests for the Aegis-SPARK safety kernel and CI gates."""

import importlib
from pathlib import Path
from typing import Any

import pytest

from scripts.ci import agent_ci_hygiene
from scripts.ci import run_clang_format
from scripts.ci import run_clang_tidy
from scripts.ci import verify_spark_contracts


sub: Any = importlib.import_module('subprocess')

REPO_ROOT = Path(__file__).resolve().parents[2]


@pytest.mark.unit
def test_repository_hygiene_passes() -> None:
    """Verify that repository layout, deletion safety, and secret hygiene pass."""
    assert agent_ci_hygiene.main(['--root', str(REPO_ROOT)]) == 0


@pytest.mark.unit
def test_spark_contracts_hygiene_passes() -> None:
    """Verify that all Ada sources enforce Ada 2022 and SPARK_Mode hygiene."""
    assert verify_spark_contracts.main(['--root', str(REPO_ROOT)]) == 0


@pytest.mark.unit
def test_clang_format_and_tidy_pass() -> None:
    """Verify that C23 sources pass both clang-format and clang-tidy."""
    assert run_clang_format.main(['--root', str(REPO_ROOT), '--check']) == 0
    assert run_clang_tidy.main(['--root', str(REPO_ROOT)]) == 0


@pytest.mark.integration
def test_aegis_spark_binary_execution() -> None:
    """Verify that the compiled aegis_spark binary executes and enforces Gold safety invariants."""
    binary_path = REPO_ROOT / 'bin' / 'aegis_spark'
    assert binary_path.is_file(), f'Expected compiled binary at {binary_path}; run `pixi run build` first.'

    res = sub.run([str(binary_path)], cwd=REPO_ROOT, capture_output=True, text=True, check=False)
    assert res.returncode == 0, f'aegis_spark failed with stderr: {res.stderr}'

    output = res.stdout
    assert '[INFO] [AEGIS-SPARK] Starting Aegis-SPARK (Halos) Safety Gate Verification' in output
    assert '[INFO] [Step 1] now_ns=2000000 cmd_ts_ns=1000000 | status=HALOS_OK | env_state=STATE_ACTIVE' in output
    assert (
        '[WARN] [Step 2] now_ns=2500000 cmd_ts_ns=2000000 | '
        'status=HALOS_ERR_TORQUE_LIMIT_EXCEEDED | env_state=STATE_FAULT_ESTOP'
    ) in output
    assert (
        '[WARN] [Step 3] now_ns=3000000 cmd_ts_ns=1000000 | status=HALOS_ERR_NOT_ACTIVE | env_state=STATE_FAULT_ESTOP'
    ) in output
    assert 'safe_torque_nm = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]' in output
    assert '[INFO] [AEGIS-SPARK] All Gold-proved safety assertions and checks succeeded.' in output
