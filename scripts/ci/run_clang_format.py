#!/usr/bin/env python3
"""Clang-Format checker and formatter for C23 sources and headers in aegis-spark."""

import argparse
import importlib
import os
import shutil
import sys
from pathlib import Path
from typing import Any


sub: Any = importlib.import_module('subprocess')

REPO_ROOT = Path(__file__).resolve().parents[2]


def find_clang_format() -> str | None:
    """Locate the clang-format executable across Pixi, Homebrew LLVM, and system PATH.

    Returns:
        Absolute path to the clang-format binary if found, otherwise None.
    """
    conda_prefix = os.environ.get('CONDA_PREFIX')
    candidates: list[str] = []
    if conda_prefix:
        candidates.append(str(Path(conda_prefix) / 'bin' / 'clang-format'))
    candidates.append(str(REPO_ROOT / '.pixi' / 'envs' / 'default' / 'bin' / 'clang-format'))

    which_fmt = shutil.which('clang-format')
    if which_fmt:
        candidates.append(which_fmt)

    candidates.extend([
        '/opt/homebrew/opt/llvm/bin/clang-format',
        '/opt/homebrew/bin/clang-format',
        '/usr/local/opt/llvm/bin/clang-format',
        '/usr/bin/clang-format',
    ])

    for candidate in candidates:
        if Path(candidate).is_file() and os.access(candidate, os.X_OK):
            return candidate
    return None


def collect_c_files(root: Path) -> list[Path]:
    """Collect all .c and .h files in src/.

    Args:
        root: Repository root directory.

    Returns:
        Sorted list of .c and .h file paths under src/.
    """
    src_dir = root / 'src'
    if not src_dir.is_dir():
        return []
    return sorted([*src_dir.rglob('*.c'), *src_dir.rglob('*.h')])


def run_clang_format(root: Path, check_only: bool = False) -> int:
    """Run clang-format across all C23 files in src/.

    Args:
        root: Repository root directory.
        check_only: If True, run with --dry-run --Werror instead of formatting in-place.

    Returns:
        Exit status code (0 on success, non-zero on failure).
    """
    clang_format_bin = find_clang_format()
    if not clang_format_bin:
        sys.stderr.write('[ERROR] clang-format executable not found on PATH.\n')
        return 1

    files = collect_c_files(root)
    if not files:
        sys.stdout.write('[INFO] No C source or header files found under src/.\n')
        return 0

    cmd: list[str] = [clang_format_bin, f'--style=file:{root / ".clang-format"}']
    if check_only:
        cmd.extend(['--dry-run', '--Werror'])
    else:
        cmd.append('-i')
    cmd.extend(str(f) for f in files)

    res = sub.run(cmd, cwd=root, capture_output=True, text=True, check=False)
    if res.returncode != 0:
        sys.stderr.write('[FAIL] clang-format check failed:\n')
        if res.stdout:
            sys.stderr.write(res.stdout)
        if res.stderr:
            sys.stderr.write(res.stderr)
        return int(res.returncode)

    mode_str = 'verified' if check_only else 'formatted'
    sys.stdout.write(f'[OK] clang-format {mode_str} {len(files)} C23 file(s).\n')
    return 0


def main(argv: list[str] | None = None) -> int:
    """CLI entrypoint for clang-format runner.

    Args:
        argv: Command-line arguments.

    Returns:
        Exit code (0 on success, non-zero on error).
    """
    parser = argparse.ArgumentParser(description='Run clang-format on C23 sources and headers.')
    parser.add_argument('--root', type=Path, default=REPO_ROOT, help='Repository root path')
    parser.add_argument('--check', action='store_true', help='Check formatting without modifying files')
    args = parser.parse_args(argv)
    return run_clang_format(args.root.resolve(), check_only=args.check)


if __name__ == '__main__':
    sys.exit(main())
