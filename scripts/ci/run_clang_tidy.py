#!/usr/bin/env python3
"""Clang-Tidy static analyzer using CMake native compile_commands.json.

Retires the legacy regex scraper: CMake 4.4.3+ exports compile_commands.json natively.
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


def find_clang_tidy() -> str | None:
    """Locate the clang-tidy executable across Pixi, Homebrew LLVM, and system PATH.

    Returns:
        Absolute path to the executable if found, None otherwise.
    """
    conda_prefix = os.environ.get('CONDA_PREFIX')
    candidates: list[str] = []
    if conda_prefix:
        candidates.append(str(Path(conda_prefix) / 'bin' / 'clang-tidy'))
    candidates.append(str(REPO_ROOT / '.pixi' / 'envs' / 'default' / 'bin' / 'clang-tidy'))

    which_tidy = shutil.which('clang-tidy')
    if which_tidy:
        candidates.append(which_tidy)

    candidates.extend([
        '/opt/homebrew/opt/llvm/bin/clang-tidy',
        '/opt/homebrew/bin/clang-tidy',
        '/usr/local/opt/llvm/bin/clang-tidy',
        '/usr/bin/clang-tidy',
    ])

    for candidate in candidates:
        if Path(candidate).is_file() and os.access(candidate, os.X_OK):
            return candidate
    return None


def locate_or_generate_compilation_database(root: Path) -> Path | None:
    """Find native compile_commands.json or generate it via CMake preset host-sim-debug.

    Args:
        root: Repository root path.

    Returns:
        Directory path containing compile_commands.json, or None if unavailable.
    """
    candidates = [
        root / 'build' / 'host-sim-debug' / 'compile_commands.json',
        root / 'build' / 'compile_commands.json',
        root / 'compile_commands.json',
    ]
    for cdb in candidates:
        if cdb.is_file():
            return cdb.parent

    # If missing, invoke cmake --preset host-sim-debug to generate it natively
    cmake_bin = shutil.which('cmake')
    if cmake_bin:
        res = sub.run(
            [cmake_bin, '--preset', 'host-sim-debug'],
            cwd=root,
            capture_output=True,
            text=True,
            check=False,
        )
        if res.returncode == 0:
            target_cdb = root / 'build' / 'host-sim-debug' / 'compile_commands.json'
            if target_cdb.is_file():
                return target_cdb.parent

    return None


def collect_c_sources(root: Path) -> list[Path]:
    """Discover all C source files under src/.

    Args:
        root: Repository root path.

    Returns:
        Sorted list of discovered C source file paths.
    """
    src_dir = root / 'src'
    if not src_dir.is_dir():
        return []
    return sorted(src_dir.rglob('*.c'))


def run_clang_tidy(root: Path, extra_args: list[str] | None = None) -> int:
    """Execute LLVM clang-tidy against the native compilation database.

    Args:
        root: Repository root path.
        extra_args: Optional additional command-line arguments to pass to clang-tidy.

    Returns:
        Exit code (0 on success, non-zero on failure).
    """
    clang_tidy_bin = find_clang_tidy()
    if not clang_tidy_bin:
        sys.stderr.write('[ERROR] clang-tidy executable not found on PATH or standard LLVM locations.\n')
        return 1

    c_files = collect_c_sources(root)
    if not c_files:
        sys.stdout.write('[INFO] No C source files found under src/; skipping clang-tidy.\n')
        return 0

    cdb_dir = locate_or_generate_compilation_database(root)
    if not cdb_dir:
        sys.stderr.write(
            '[ERROR] Native compile_commands.json not found and could not be '
            'generated via CMake preset host-sim-debug.\n'
        )
        return 1

    cmd: list[str] = [
        clang_tidy_bin,
        f'--config-file={root / ".clang-tidy"}',
        '--warnings-as-errors=*',
        '--header-filter=^.*(src|include)/.*',
        '--quiet',
        '-p',
        str(cdb_dir),
    ]
    if extra_args:
        cmd.extend(extra_args)
    cmd.extend(str(p) for p in c_files)

    res = sub.run(cmd, cwd=root, capture_output=True, text=True, check=False)
    if res.returncode != 0:
        sys.stderr.write('[FAIL] clang-tidy static analysis reported issues:\n')
        if res.stdout:
            sys.stderr.write(res.stdout)
        if res.stderr:
            sys.stderr.write(res.stderr)
        return int(res.returncode)

    rel_files = ', '.join(str(p.relative_to(root)) for p in c_files)
    sys.stdout.write(f'[OK] clang-tidy C23 static analysis passed ({len(c_files)} unit(s): {rel_files}).\n')
    return 0


def main(argv: list[str] | None = None) -> int:
    """CLI entrypoint.

    Args:
        argv: Optional command-line arguments.

    Returns:
        Exit code (0 on success, non-zero on failure).
    """
    parser = argparse.ArgumentParser(
        description='Run clang-tidy on C23 sources using native CMake compilation database.'
    )
    parser.add_argument('--root', type=Path, default=REPO_ROOT, help='Repository root path')
    args, unknown = parser.parse_known_args(argv)
    extra = [arg for arg in unknown if arg.startswith('-')]
    return run_clang_tidy(args.root.resolve(), extra_args=extra)


if __name__ == '__main__':
    sys.exit(main())
