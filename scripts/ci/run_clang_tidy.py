#!/usr/bin/env python3
"""Clang-Tidy static analyzer and compile_commands.json generator for aegis-spark.

Because GPRbuild (.gpr) does not provide a native CMAKE_EXPORT_COMPILE_COMMANDS or
CMAKE_C_CLANG_TIDY attribute (and passes -I flags via temporary deleted GCC -specs
files), this script parses `aegis_spark.gpr` as the single source of truth to:
1. Extract `Source_Dirs` and `Default_Switches ("C")` directly from `aegis_spark.gpr`.
2. Verify that `.clangd` is 100% synchronized with `aegis_spark.gpr`.
3. Generate `compile_commands.json` at the repository root for `clangd` and `clang-tidy`.
4. Execute LLVM `clang-tidy -p <root>` across all C23 translation units and headers.
"""

import argparse
import importlib
import json
import os
import platform
import re
import shutil
import sys
from pathlib import Path
from typing import Any


sub: Any = importlib.import_module('subprocess')

REPO_ROOT = Path(__file__).resolve().parents[2]

DEFAULT_C_SWITCHES: tuple[str, ...] = (
    '-std=c23',
    '-O3',
    '-g',
    '-Wall',
    '-Wextra',
    '-Wpedantic',
    '-Werror',
    '-Wstrict-prototypes',
    '-Wmissing-prototypes',
    '-Wmissing-declarations',
    '-Wold-style-definition',
    '-Wbad-function-cast',
    '-Wconversion',
    '-Wsign-conversion',
    '-Wdouble-promotion',
    '-Wcast-qual',
    '-Wcast-align',
    '-Wwrite-strings',
    '-Wformat=2',
    '-Wformat-security',
    '-Wnull-dereference',
    '-Wshadow',
    '-Wimplicit-fallthrough',
    '-Wvla',
    '-Wundef',
    '-Wswitch-enum',
    '-ftrivial-auto-var-init=zero',
)


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


def extract_gpr_c_config(root: Path) -> tuple[list[str], list[str], str]:
    """Parse `aegis_spark.gpr` and `config/aegis_spark_config.gpr` for C compilation settings.

    Args:
        root: Repository root directory containing `aegis_spark.gpr`.

    Returns:
        Tuple of `(source_dirs, c_switches, build_profile)`.
    """
    gpr_path = root / 'aegis_spark.gpr'
    source_dirs: list[str] = ['src/', 'config/']
    c_switches: list[str] = list(DEFAULT_C_SWITCHES)
    build_profile = 'validation'

    if gpr_path.is_file():
        gpr_text = gpr_path.read_text(encoding='utf-8')
        src_match = re.search(
            r'for\s+Source_Dirs\s+use\s*\(([^)]+)\)',
            gpr_text,
            re.IGNORECASE | re.DOTALL,
        )
        if src_match:
            parsed_dirs = re.findall(r'"([^"]+)"', src_match.group(1))
            if parsed_dirs:
                source_dirs = parsed_dirs

        c_match = re.search(
            r'for\s+Default_Switches\s*\(\s*"C"\s*\)\s+use\s*\(([^)]+)\)',
            gpr_text,
            re.IGNORECASE | re.DOTALL,
        )
        if c_match:
            parsed_switches = re.findall(r'"([^"]+)"', c_match.group(1))
            if parsed_switches:
                c_switches = parsed_switches

    config_gpr_path = root / 'config' / 'aegis_spark_config.gpr'
    if config_gpr_path.is_file():
        cfg_text = config_gpr_path.read_text(encoding='utf-8')
        prof_match = re.search(
            r'Build_Profile\s*:\s*Build_Profile_Kind\s*:=\s*"([^"]+)"',
            cfg_text,
            re.IGNORECASE,
        )
        if prof_match:
            build_profile = prof_match.group(1)

    return source_dirs, c_switches, build_profile


def verify_clangd_config_sync(root: Path, c_switches: list[str]) -> list[str]:
    """Verify that `.clangd` CompileFlags.Add matches `aegis_spark.gpr` Default_Switches("C").

    Args:
        root: Repository root directory.
        c_switches: Authoritative C compiler switches extracted from `aegis_spark.gpr`.

    Returns:
        List of synchronization error messages (empty if synchronized).
    """
    clangd_path = root / '.clangd'
    if not clangd_path.is_file():
        return []

    lines = clangd_path.read_text(encoding='utf-8').splitlines()
    in_add_block = False
    added_flags: list[str] = []

    for raw_line in lines:
        stripped = raw_line.strip()
        if not stripped or stripped.startswith('#'):
            continue
        if stripped.startswith('Add:'):
            in_add_block = True
            continue
        if in_add_block:
            if stripped.startswith('- '):
                added_flags.append(stripped.removeprefix('- ').strip())
            else:
                in_add_block = False

    expected_flags = ['-xc', *c_switches]
    if added_flags != expected_flags:
        return [
            f'.clangd CompileFlags.Add is out of sync with aegis_spark.gpr Default_Switches("C"). '
            f'Expected {expected_flags}, found {added_flags}.'
        ]
    return []


def write_compile_commands(
    root: Path,
    c_files: list[Path],
    source_dirs: list[str],
    c_switches: list[str],
    build_profile: str,
) -> Path:
    """Write `compile_commands.json` at the repository root using GPRbuild C settings.

    Args:
        root: Repository root directory.
        c_files: List of C translation unit paths.
        source_dirs: Source directories extracted from `aegis_spark.gpr`.
        c_switches: C compiler flags extracted from `aegis_spark.gpr`.
        build_profile: Active Alire/GPRbuild build profile name.

    Returns:
        Path to the generated `compile_commands.json` file.
    """
    include_flags: list[str] = []
    for rel_dir in source_dirs:
        abs_dir = (root / rel_dir).resolve()
        include_flags.append(f'-I{abs_dir}')

    sdk_path = get_macos_sdk_path()
    sysroot_flags = ['-isysroot', sdk_path] if sdk_path else []
    obj_dir = (root / 'obj' / build_profile).resolve()

    entries: list[dict[str, Any]] = []
    for c_file in c_files:
        resolved_c = c_file.resolve()
        obj_file = obj_dir / f'{resolved_c.stem}.o'
        arguments: list[str] = [
            'clang',
            '-xc',
            *c_switches,
            *include_flags,
            *sysroot_flags,
            '-c',
            str(resolved_c),
            '-o',
            str(obj_file),
        ]
        entries.append({
            'directory': str(root.resolve()),
            'file': str(resolved_c),
            'arguments': arguments,
        })

    cdb_path = root / 'compile_commands.json'
    cdb_path.write_text(json.dumps(entries, indent=2) + '\n', encoding='utf-8')
    return cdb_path


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
    """Generate `compile_commands.json` from `aegis_spark.gpr` and run `clang-tidy`.

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

    source_dirs, c_switches, build_profile = extract_gpr_c_config(root)
    sync_errors = verify_clangd_config_sync(root, c_switches)
    if sync_errors:
        for err in sync_errors:
            sys.stderr.write(f'[FAIL] {err}\n')
        return 1

    write_compile_commands(root, c_files, source_dirs, c_switches, build_profile)

    cmd: list[str] = [
        clang_tidy_bin,
        f'--config-file={root / ".clang-tidy"}',
        '--warnings-as-errors=*',
        '--header-filter=^.*(src|include)/.*',
        '--quiet',
        '-p',
        str(root),
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
    """CLI entrypoint for clang-tidy verification and compilation database generation.

    Args:
        argv: Command-line arguments.

    Returns:
        Exit status code (0 for success, non-zero for failure).
    """
    parser = argparse.ArgumentParser(
        description='Generate compile_commands.json from aegis_spark.gpr and run clang-tidy on C23 sources.'
    )
    parser.add_argument('--root', type=Path, default=REPO_ROOT, help='Repository root path')
    args, unknown = parser.parse_known_args(argv)
    extra = [arg for arg in unknown if arg.startswith('-')]
    return run_clang_tidy(args.root.resolve(), extra_args=extra)


if __name__ == '__main__':
    sys.exit(main())
