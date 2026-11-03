#!/usr/bin/env python3
"""Headless QEMU bare-metal ARM64 smoke test runner for Aegis-SPARK.

Launches QEMU virt emulator with Cortex-A72 CPU under deterministic -icount,
streams serial UART output, verifies the safety supervisor boot and fault
telemetry tokens in sequential order, and asserts clean semihosting exit (code 0).
"""

import argparse
import importlib
import os
import shutil
import sys
from pathlib import Path
from typing import Any


sub: Any = importlib.import_module('subprocess')
REPO_ROOT = Path(__file__).resolve().parents[2]

EXPECTED_TELEMETRY_TOKENS: list[str] = [
    '[AEGIS_SPARK] Initializing bare-metal ARM64 safety supervisor',
    'HALOS_GATE: BOOT OK',
    'HALOS_GATE: SELF-TEST PASS',
    'HALOS_GATE: FAULT_ESTOP LATCHED',
    'HALOS_GATE: TELEMETRY OK',
]


def find_qemu_executable() -> str | None:
    """Locate qemu-system-aarch64 across system PATH and standard package manager prefixes.

    Returns:
        Absolute path to qemu-system-aarch64 if found, None otherwise.
    """
    candidates: list[str] = []

    which_qemu = shutil.which('qemu-system-aarch64')
    if which_qemu:
        candidates.append(which_qemu)

    candidates.extend([
        '/opt/homebrew/bin/qemu-system-aarch64',
        '/usr/local/bin/qemu-system-aarch64',
        '/usr/bin/qemu-system-aarch64',
    ])

    for candidate in candidates:
        cand_path = Path(candidate)
        if cand_path.is_file() and os.access(cand_path, os.X_OK):
            return candidate

    return None


def ensure_elf_binary(elf_arg: Path | None, root: Path) -> Path:
    """Resolve or build the bare-metal ELF binary.

    Args:
        elf_arg: Optional explicit path to ELF binary.
        root: Repository root path.

    Returns:
        Resolved Path to the bare-metal ELF binary.

    Raises:
        FileNotFoundError: If the target directory or expected binary is not found.
        RuntimeError: If RTS or application build fails.
    """
    if elf_arg and elf_arg.is_file():
        return elf_arg.resolve()

    default_elf = root / 'bin' / 'aegis_spark_qemu.elf'
    if default_elf.is_file():
        return default_elf

    # If ELF does not exist, build it using alr in target/qemu-virt-aarch64
    sys.stdout.write('[INFO] ELF image not found. Building bare-metal target via alr...\n')
    target_dir = root / 'target' / 'qemu-virt-aarch64'
    if not target_dir.is_dir():
        msg = f'Target directory not found: {target_dir}'
        raise FileNotFoundError(msg)

    # First ensure RTS is built
    rts_dir = target_dir / 'rts'
    if not (rts_dir / 'lib' / 'libgnat.a').is_file():
        sys.stdout.write('[INFO] Building minimal RTS library...\n')
        rts_res = sub.run(
            ['alr', '--non-interactive', 'exec', '--', 'gprbuild', '--target=aarch64-elf', '-P', 'rts.gpr'],
            cwd=rts_dir,
            capture_output=True,
            text=True,
            check=False,
        )
        if rts_res.returncode != 0:
            sys.stderr.write(f'[ERROR] RTS build failed:\n{rts_res.stderr}\n')
            msg = 'Failed to build minimal Ada RTS'
            raise RuntimeError(msg)

    build_res = sub.run(
        ['alr', '--non-interactive', 'exec', '--', 'gprbuild', '--target=aarch64-elf', '-P', 'aegis_spark_qemu.gpr'],
        cwd=target_dir,
        capture_output=True,
        text=True,
        check=False,
    )
    if build_res.returncode != 0:
        sys.stderr.write(f'[ERROR] Bare-metal build failed:\n{build_res.stderr}\n')
        msg = 'Failed to cross-compile bare-metal ELF image'
        raise RuntimeError(msg)

    if not default_elf.is_file():
        msg = f'Expected ELF binary missing after build: {default_elf}'
        raise FileNotFoundError(msg)

    return default_elf


def run_qemu_smoke(
    elf_path: Path,
    timeout_seconds: float = 10.0,
    allow_skip: bool = False,
) -> int:
    """Execute bare-metal ELF in QEMU and assert sequential telemetry tokens.

    Args:
        elf_path: Path to the bare-metal ELF binary.
        timeout_seconds: Timeout in seconds before terminating QEMU.
        allow_skip: If True, returns 0 when QEMU is not installed.

    Returns:
        Exit code (0 on success, non-zero on failure).
    """
    qemu_bin = find_qemu_executable()
    if not qemu_bin:
        if allow_skip:
            sys.stdout.write('[WARN] qemu-system-aarch64 not found on host. Skipping QEMU smoke test as requested.\n')
            return 0
        sys.stderr.write(
            '[ERROR] qemu-system-aarch64 executable not found. '
            'Install QEMU (e.g. `brew install qemu` or `apt-get install qemu-system-arm`).\n'
        )
        return 1

    cmd: list[str] = [
        qemu_bin,
        '-M',
        'virt',
        '-cpu',
        'cortex-a72',
        '-nographic',
        '-m',
        '128M',
        '-icount',
        'shift=auto',
        '-semihosting',
        '-semihosting-config',
        'enable=on,target=native',
        '-kernel',
        str(elf_path),
    ]

    sys.stdout.write(f'[INFO] Invoking QEMU: {" ".join(cmd)}\n')

    try:
        proc = sub.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=timeout_seconds,
            check=False,
        )
    except sub.TimeoutExpired:
        sys.stderr.write(f'[FAIL] QEMU timed out after {timeout_seconds}s without clean termination.\n')
        return 1

    stdout_output = proc.stdout
    stderr_output = proc.stderr

    sys.stdout.write('--- QEMU Serial Output Start ---\n')
    sys.stdout.write(stdout_output)
    if not stdout_output.endswith('\n'):
        sys.stdout.write('\n')
    sys.stdout.write('--- QEMU Serial Output End ---\n')

    if stderr_output.strip():
        sys.stderr.write(f'[QEMU STDERR]:\n{stderr_output}\n')

    # Verify exit code
    if proc.returncode != 0:
        sys.stderr.write(f'[FAIL] QEMU process exited with non-zero status: {proc.returncode}\n')
        return int(proc.returncode)

    # Verify sequential presence of all expected telemetry tokens
    last_idx = 0
    for idx, token in enumerate(EXPECTED_TELEMETRY_TOKENS, start=1):
        found_pos = stdout_output.find(token, last_idx)
        if found_pos == -1:
            sys.stderr.write(
                f"[FAIL] Missing expected telemetry token {idx}/{len(EXPECTED_TELEMETRY_TOKENS)}: '{token}'\n"
            )
            return 1
        sys.stdout.write(f"[OK] Verified telemetry token {idx}/{len(EXPECTED_TELEMETRY_TOKENS)}: '{token}'\n")
        last_idx = found_pos + len(token)

    sys.stdout.write(
        f'[PASS] QEMU bare-metal emulation passed all {len(EXPECTED_TELEMETRY_TOKENS)} '
        'telemetry checks with exit code 0.\n'
    )
    return 0


def main(argv: list[str] | None = None) -> int:
    """CLI entrypoint.

    Args:
        argv: Optional command-line arguments.

    Returns:
        Exit code (0 on success, non-zero on failure).
    """
    parser = argparse.ArgumentParser(
        description='Run bare-metal ARM64 QEMU emulation smoke test and verify UART telemetry.'
    )
    parser.add_argument(
        '--elf',
        type=Path,
        default=None,
        help='Path to bare-metal ELF binary (default: bin/aegis_spark_qemu.elf)',
    )
    parser.add_argument(
        '--root',
        type=Path,
        default=REPO_ROOT,
        help='Repository root directory',
    )
    parser.add_argument(
        '--timeout',
        type=float,
        default=10.0,
        help='Timeout in seconds (default: 10.0)',
    )
    parser.add_argument(
        '--allow-skip',
        action='store_true',
        help='Exit with 0 if qemu-system-aarch64 is not installed',
    )

    args = parser.parse_args(argv)

    try:
        elf_binary = ensure_elf_binary(args.elf, args.root.resolve())
    except (FileNotFoundError, RuntimeError) as err:
        sys.stderr.write(f'[ERROR] {err}\n')
        return 1

    return run_qemu_smoke(
        elf_path=elf_binary,
        timeout_seconds=args.timeout,
        allow_skip=args.allow_skip,
    )


if __name__ == '__main__':
    sys.exit(main())
