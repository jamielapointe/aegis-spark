"""Integration and verification tests for the Aegis-SPARK safety kernel and CI gates."""

import importlib
import shutil
from pathlib import Path
from typing import Any

import pytest

from scripts.ci import agent_ci_hygiene
from scripts.ci import run_clang_format
from scripts.ci import run_clang_tidy
from scripts.ci import verify_spark_contracts
from scripts.ci import verify_static_stack


sub: Any = importlib.import_module('subprocess')

REPO_ROOT = Path(__file__).resolve().parents[2]


@pytest.mark.unit
def test_repository_hygiene_passes() -> None:
    """Verify that repository layout, deletion safety, and secret hygiene pass."""
    assert agent_ci_hygiene.main(['--root', str(REPO_ROOT)]) == 0


@pytest.mark.unit
def test_gitignore_and_agentic_hygiene_enforcement(tmp_path: Path) -> None:
    """Verify that .gitignore ignores agentic scratch paths and tracks canonical rules."""
    git_bin = shutil.which('git') or '/usr/bin/git'
    ignored_paths = [
        '.agents/teamwork/state.json',
        '.gemini/settings.json',
        '.antigravity/rules.md',
        '.als-alire',
        'TEST_INFRA.md',
        'TEST_READY.md',
        'ORIGINAL_REQUEST.md',
        'PROJECT.md',
        'AGENT.md',
        'GEMINI.md',
        'CLAUDE.md',
        '.claude/settings.json',
        '.cursor/rules',
        '.windsurf/rules',
        '.aider.chat.history.md',
    ]
    for rel_path in ignored_paths:
        res = sub.run(
            [git_bin, 'check-ignore', '-q', rel_path],
            cwd=REPO_ROOT,
            check=False,
        )
        assert res.returncode == 0, f'Expected {rel_path} to be ignored by .gitignore'

    tracked_paths = [
        'AGENTS.md',
        '.agents/rules/c23-abi.md',
        '.agents/rules/cmake.md',
        '.agents/rules/spark-safety.md',
    ]
    for rel_path in tracked_paths:
        res = sub.run(
            [git_bin, 'check-ignore', '-q', rel_path],
            cwd=REPO_ROOT,
            check=False,
        )
        assert res.returncode != 0, f'Expected {rel_path} NOT to be ignored by .gitignore'

    # Verify check_agent_and_build_hygiene catches forbidden root scratch files and legacy dirs
    (tmp_path / 'TEST_INFRA.md').write_text('# scratch\n', encoding='utf-8')
    (tmp_path / 'PROJECT.md').write_text('# project\n', encoding='utf-8')
    (tmp_path / '.antigravity').mkdir()
    violations = agent_ci_hygiene.check_agent_and_build_hygiene(tmp_path)
    assert any('TEST_INFRA.md' in v for v in violations)
    assert any('PROJECT.md' in v for v in violations)
    assert any('.antigravity' in v for v in violations)


@pytest.mark.unit
def test_spark_contracts_hygiene_passes() -> None:
    """Verify that all Ada sources enforce Ada 2022 and SPARK_Mode hygiene."""
    assert verify_spark_contracts.main(['--root', str(REPO_ROOT)]) == 0


@pytest.mark.unit
def test_static_stack_and_zero_dynamic_allocation() -> None:
    """Verify that all SPARK subprograms have bounded stack usage and zero dynamic heap allocation."""
    assert verify_static_stack.main(['--root', str(REPO_ROOT)]) == 0


@pytest.mark.unit
def test_uart0_mmio_proof_of_concept_sources() -> None:
    """Verify that the SPARK Ada 2022 UART0 MMIO register and Dual-Tier HAL are present and well-formed."""
    ads_path = REPO_ROOT / 'src' / 'uart0_mmio.ads'
    adb_path = REPO_ROOT / 'src' / 'uart0_mmio.adb'
    assert ads_path.is_file()
    assert adb_path.is_file()

    ads_content = ads_path.read_text(encoding='utf-8')
    assert 'Aegis.HAL.Registers' in ads_content
    assert 'DR_Reg' in ads_content
    assert 'SR_Reg' in ads_content
    assert 'CR_Reg' in ads_content
    assert 'BAUD_Reg' in ads_content

    # Verify Dual-Tier HAL register backends
    host_sim_ads = REPO_ROOT / 'src' / 'hal' / 'host_sim' / 'aegis-hal-registers.ads'
    qemu_ads = REPO_ROOT / 'src' / 'hal' / 'qemu_virt' / 'aegis-hal-registers.ads'
    thor_ads = REPO_ROOT / 'src' / 'hal' / 'igx_thor' / 'aegis-hal-registers.ads'
    assert host_sim_ads.is_file()
    assert qemu_ads.is_file()
    assert thor_ads.is_file()

    thor_content = thor_ads.read_text(encoding='utf-8')
    assert '16#4000_1000#' in thor_content
    assert 'Async_Writers' in thor_content
    assert 'Async_Readers' in thor_content
    assert 'Effective_Writes' in thor_content
    assert 'To_Address' in thor_content

    qemu_content = qemu_ads.read_text(encoding='utf-8')
    assert '16#0900_0000#' in qemu_content


@pytest.mark.unit
def test_clang_format_and_tidy_pass() -> None:
    """Verify that C23 sources pass both clang-format and clang-tidy."""
    assert run_clang_format.main(['--root', str(REPO_ROOT), '--check']) == 0
    assert run_clang_tidy.main(['--root', str(REPO_ROOT)]) == 0


@pytest.mark.unit
def test_native_cmake_compilation_database_and_clangd() -> None:
    """Verify that CMake generates native compile_commands.json without regex scraping."""
    import json

    # Verify that the obsolete root compile_commands.json is eliminated
    root_cdb = REPO_ROOT / 'compile_commands.json'
    assert not root_cdb.exists(), 'compile_commands.json must not exist at repository root'

    # Verify locate_or_generate_compilation_database finds or creates the preset database
    cdb_dir = run_clang_tidy.locate_or_generate_compilation_database(REPO_ROOT)
    assert cdb_dir is not None
    cdb_path = cdb_dir / 'compile_commands.json'
    assert cdb_path.is_file()

    entries = json.loads(cdb_path.read_text(encoding='utf-8'))
    assert len(entries) >= 1
    found_halos_logger = False
    for entry in entries:
        if 'halos_c_logger.c' in entry.get('file', ''):
            found_halos_logger = True
            cmd = entry.get('command', '')
            assert '-Wall' in cmd
            assert '-Wextra' in cmd
            assert '-Wpedantic' in cmd
            assert '-ftrivial-auto-var-init=zero' in cmd
            assert '-I' in cmd
    assert found_halos_logger, 'halos_c_logger.c entry missing from compile_commands.json'

    # Verify .clangd points to the CMake compilation database
    clangd_path = REPO_ROOT / '.clangd'
    assert clangd_path.is_file()
    clangd_content = clangd_path.read_text(encoding='utf-8')
    assert 'CompilationDatabase: build/host-sim-debug' in clangd_content


@pytest.mark.unit
def test_standalone_static_library_packaging() -> None:
    """Verify that aegis_spark_lib.gpr configures a standalone static library."""
    lib_gpr = REPO_ROOT / 'aegis_spark_lib.gpr'
    demo_gpr = REPO_ROOT / 'aegis_spark.gpr'
    assert lib_gpr.is_file()
    assert demo_gpr.is_file()

    lib_content = lib_gpr.read_text(encoding='utf-8')
    assert 'for Library_Name use "aegis_spark"' in lib_content
    assert 'for Library_Kind use "static"' in lib_content
    assert '"Halos_Safety_Gate"' in lib_content
    assert '"Halos_Logger"' in lib_content
    assert '"Uart0_Mmio"' in lib_content
    assert '"Aegis.HAL.Registers"' in lib_content
    assert 'for Library_Auto_Init use "True"' in lib_content

    demo_content = demo_gpr.read_text(encoding='utf-8')
    assert 'with "aegis_spark_lib.gpr"' in demo_content
    assert '-B/Library/Developer' not in demo_content


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


@pytest.mark.integration
@pytest.mark.timeout(120)
def test_cmake_workflow_preset_execution() -> None:
    """Verify that CMake workflow preset host-sim-debug configures, builds, and tests."""
    import os

    if os.environ.get('AEGIS_INSIDE_CTEST') == '1':
        pytest.skip('Skipping nested cmake workflow invocation inside CTest runner')

    cmake_bin = run_clang_tidy.find_cmake()
    assert cmake_bin is not None, 'cmake executable must be available on PATH'

    res = sub.run(
        [cmake_bin, '--workflow', '--preset', 'host-sim-debug'],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        check=False,
        timeout=120,
    )
    assert res.returncode == 0, f'cmake --workflow --preset host-sim-debug failed:\n{res.stdout}\n{res.stderr}'

    static_lib = REPO_ROOT / 'lib' / 'libaegis_spark.a'
    c_logger_lib = REPO_ROOT / 'build' / 'host-sim-debug' / 'lib' / 'libhalos_c_logger.a'
    assert static_lib.is_file(), f'libaegis_spark.a missing at {static_lib}'
    assert c_logger_lib.is_file(), f'libhalos_c_logger.a missing at {c_logger_lib}'
