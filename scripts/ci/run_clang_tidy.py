#!/usr/bin/env python3
"""Clang-Tidy static analyzer runner for C23 sources in aegis-spark.

Because GPRbuild (.gpr) does not provide a native CMAKE_C_CLANG_TIDY co-compiler
attribute (and compiles C sources with GNAT's GCC 16.1 for Ada ABI compatibility),
this script executes LLVM clang-tidy across all C23 translation units and headers
in src/. It is invoked automatically by Alire post-build actions, Pixi tasks,
pre-commit hooks, and GitHub Actions CI.
"""

import argparse
import importlib
import os
import platform
import shutil
import sys
from pathlib import Path
from typing import Any


sub: Any = importlib.import_module('subprocess')

REPO_ROOT = Path(__file__).resolve().parents[2]


def find_clang_tidy() -> str | None:
    """Locate the clang-tidy executable across Pixi, Homebrew LLVM, and system PATH.

    Returns:
        Absolute path to the clang-tidy binary if found, otherwise None.
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


def get_macos_sdk_path() -> str | None:
    """Resolve the active macOS SDK sysroot path via xcrun when running on Darwin.

    Returns:
        The SDK path string on macOS if available, otherwise None.
    """
    if platform.system() != 'Darwin':
        return None
    xcrun_bin = shutil.which('xcrun') or '/usr/bin/xcrun'
    if not Path(xcrun_bin).is_file():
        return None
    res = sub.run(
        [xcrun_bin, '--show-sdk-path'],
        capture_output=True,
        text=True,
        check=False,
    )
    if res.returncode == 0 and res.stdout.strip():
        return str(res.stdout).strip()
    return None


def collect_c_sources(root: Path) -> list[Path]:
    """Discover all C source files under src/.

    Args:
        root: Repository root directory.

    Returns:
        Sorted list of .c source paths.
    """
    src_dir = root / 'src'
    if not src_dir.is_dir():
        return []
    return sorted(src_dir.rglob('*.c'))


def run_clang_tidy(root: Path, extra_args: list[str] | None = None) -> int:
    """Execute clang-tidy with strict C23 flags on all C translation units in src/.

    Args:
        root: Repository root directory.
        extra_args: Optional additional arguments to pass to clang-tidy.

    Returns:
        Exit code (0 on clean static analysis, non-zero on warnings/errors).
    """
    clang_tidy_bin = find_clang_tidy()
    if not clang_tidy_bin:
        sys.stderr.write('[ERROR] clang-tidy executable not found on PATH or standard LLVM locations.\n')
        return 1

    c_files = collect_c_sources(root)
    if not c_files:
        sys.stdout.write('[INFO] No C source files found under src/; skipping clang-tidy.\n')
        return 0

    compiler_flags: list[str] = [
        '-std=c23',
        '-Wall',
        '-Wextra',
        '-Wpedantic',
        f'-I{root / "src"}',
    ]
    config_dir = root / 'config'
    if config_dir.is_dir():
        compiler_flags.append(f'-I{config_dir}')

    sdk_path = get_macos_sdk_path()
    if sdk_path:
        compiler_flags.extend(['-isysroot', sdk_path])

    cmd: list[str] = [
        clang_tidy_bin,
        f'--config-file={root / ".clang-tidy"}',
        '--warnings-as-errors=*',
        '--header-filter=^.*(src|include)/.*',
        '--quiet',
    ]
    if extra_args:
        cmd.extend(extra_args)
    cmd.extend(str(p) for p in c_files)
    cmd.append('--')
    cmd.extend(compiler_flags)

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
    """CLI entrypoint for clang-tidy verification.

    Args:
        argv: Command-line arguments.

    Returns:
        Exit status code (0 for success, non-zero for failure).
    """
    parser = argparse.ArgumentParser(description='Run clang-tidy static analysis on C23 sources.')
    parser.add_argument('--root', type=Path, default=REPO_ROOT, help='Repository root path')
    args, unknown = parser.parse_known_args(argv)
    # Filter out standalone filenames passed by pre-commit if any, since we scan all src/*.c units
    extra = [arg for arg in unknown if arg.startswith('-')]
    return run_clang_tidy(args.root.resolve(), extra_args=extra)


if __name__ == '__main__':
    sys.exit(main())
