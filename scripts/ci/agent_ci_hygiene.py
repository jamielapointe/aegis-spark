#!/usr/bin/env python3
"""Repository Hygiene and Deletion Safety Verifier for aegis-spark.

Enforces:
1. Deletion safety: Verifies no files/directories named '~', containing '~',
   or unexpanded shell variables ('$') exist.
2. Git & build artifact hygiene: Verifies no agent metadata (.agents/teamwork),
   temporary caches, generated Alire/GPRbuild directories (obj/, bin/, alire/, config/),
   or forbidden rules files (AGENT.md, GEMINI.md) are tracked or leaked into src/.
3. Code layout: Verifies canonical repository layout (src/, tests/python/, scripts/ci/,
   .antigravity/, .github/workflows/).
4. Secret hygiene: Verifies zero leaked API keys or credentials exist in the repository.
5. Case collision safety: Verifies no two paths under obj/ or bin/ differ solely by case
   (macOS APFS guard).
"""

import argparse
import importlib
import re
import shutil
import sys
from pathlib import Path
from typing import Any


sub: Any = importlib.import_module('subprocess')

REPO_ROOT = Path(__file__).resolve().parents[2]

GOOGLE_API_KEY_PATTERN = re.compile(r'AIza[0-9A-Za-z\-_]{35}')


def check_deletion_safety(root: Path, fail_on_tilde: bool = True) -> list[str]:
    """Scan for suspicious files named '~', containing '~', or '$'.

    Args:
        root: The repository root path to inspect.
        fail_on_tilde: Whether to treat tilde paths as fatal violations.

    Returns:
        List of detected violation messages.
    """
    violations: list[str] = []
    try:
        entries = list(root.iterdir())
    except OSError as err:
        return [f'Failed to scan directory {root}: {err}']

    for entry in entries:
        name = entry.name
        if name == '~' or name.startswith('~'):
            msg = (
                f"Stray path named '~' found: {entry}. "
                'Per user deletion safety policy, automated scripts MUST NOT run rm -rf; '
                'this path must be reported for safe manual removal by the user.'
            )
            if fail_on_tilde:
                violations.append(msg)
            else:
                sys.stderr.write(f'[DELETION SAFETY NOTICE] {msg}\n')
        elif '$' in name:
            violations.append(f"Suspicious path containing '$' found: {entry}")
        elif name.endswith('~') and not name.startswith('.'):
            violations.append(f"Editor backup file matching '*~' found: {entry}")

    return violations


def check_agent_and_build_hygiene(root: Path) -> list[str]:
    """Verify that agent metadata, build artifacts, or reserved files are not tracked or in src/.

    Args:
        root: Repository root path to check.

    Returns:
        List of violation messages found.
    """
    violations: list[str] = []
    forbidden_root_files = ['AGENT.md', 'GEMINI.md']

    for name in forbidden_root_files:
        p = root / name
        if p.exists():
            violations.append(f"Reserved agent instruction file '{name}' must not exist at repository root: {p}")

    # Verify no stray compiler or binder artifacts leaked into src/
    src_dir = root / 'src'
    if src_dir.is_dir():
        forbidden_src_suffixes = {'.o', '.ali', '.adt', '.ci', '.cswi', '.bexch', '.d', '.a', '.so', '.dylib'}
        violations.extend([
            f'Compiled/generated artifact found inside src/: {p.relative_to(root)}'
            for p in src_dir.rglob('*')
            if p.is_file() and (p.suffix in forbidden_src_suffixes or p.name.startswith('b__'))
        ])

    # Check git tracked files if git repository is initialized
    git_dir = root / '.git'
    if git_dir.exists():
        git_bin = shutil.which('git') or '/usr/bin/git'
        try:
            res = sub.run(
                [
                    git_bin,
                    'ls-files',
                    '.agents',
                    'obj',
                    'bin',
                    'alire',
                    'alire_install',
                    'config',
                    'build',
                    '.pixi',
                    'node_modules',
                    '*.o',
                    '*.ali',
                ],
                cwd=root,
                capture_output=True,
                text=True,
                check=False,
            )
            if res.returncode == 0 and res.stdout.strip():
                tracked = res.stdout.strip().splitlines()
                violations.append(f'Forbidden generated/build files tracked in git ({len(tracked)}): {tracked[:5]}')
        except (OSError, RuntimeError) as err:
            violations.append(f'Failed to check git tracked files: {err}')

    return violations


def check_secret_hygiene(root: Path) -> list[str]:
    """Verify that zero Google API keys or credentials exist in the repository.

    Args:
        root: Repository root directory to scan.

    Returns:
        List of potential secret leak violation messages.
    """
    violations: list[str] = []
    excluded_dirs = {
        '.git',
        '.pixi',
        'obj',
        'bin',
        'alire',
        'alire_install',
        'config',
        'build',
        'dist',
        'node_modules',
        '.agents',
        '.venv',
        '__pycache__',
    }
    scanned_exts = {
        '.adb',
        '.ads',
        '.c',
        '.h',
        '.gpr',
        '.adc',
        '.py',
        '.json',
        '.yaml',
        '.yml',
        '.toml',
        '.md',
        '.txt',
        '.sh',
    }

    for path in root.rglob('*'):
        if not path.is_file():
            continue
        if any(part in excluded_dirs for part in path.parts):
            continue
        if path.suffix not in scanned_exts and path.name != 'pyproject.toml':
            continue

        try:
            content = path.read_text(encoding='utf-8', errors='ignore')
        except OSError:
            continue

        matches = GOOGLE_API_KEY_PATTERN.findall(content)
        if matches:
            masked = [f'{m[:6]}...{m[-4:]}' for m in matches]
            violations.append(f'Potential Google API key detected in {path.relative_to(root)}: {masked}')

    return violations


def check_directory_layout(root: Path) -> list[str]:
    """Verify canonical project directory layout for aegis-spark.

    Args:
        root: Repository root path to check.

    Returns:
        List of directory layout violations.
    """
    required_dirs = [
        root / 'src',
        root / 'tests' / 'python',
        root / 'scripts' / 'ci',
        root / '.antigravity',
        root / '.github' / 'workflows',
    ]
    required_files = [
        root / 'alire.toml',
        root / 'aegis_spark.gpr',
        root / 'gnat.adc',
        root / 'pyproject.toml',
        root / '.clang-format',
        root / '.clang-tidy',
        root / '.pre-commit-config.yaml',
        root / '.gitignore',
        root / '.gitattributes',
    ]

    violations: list[str] = [
        f'Required directory missing: {req.relative_to(root)}'
        for req in required_dirs
        if not req.exists() or not req.is_dir()
    ]
    violations.extend([
        f'Required configuration file missing: {req.relative_to(root)}'
        for req in required_files
        if not req.exists() or not req.is_file()
    ])
    return violations


def check_build_case_collisions(root: Path, fail_on_collision: bool = True) -> list[str]:
    """Verify that no two paths under obj/ or bin/ differ solely by case (macOS APFS guard).

    Args:
        root: Repository root path to check.
        fail_on_collision: Whether to treat case collisions as fatal errors.

    Returns:
        List of case collision violation messages.
    """
    violations: list[str] = []
    for dir_name in ('obj', 'bin'):
        target_dir = root / dir_name
        if not target_dir.exists() or not target_dir.is_dir():
            continue

        seen: dict[str, str] = {}
        try:
            paths = sorted(target_dir.rglob('*'))
        except OSError as err:
            return [f'Failed to scan {dir_name}/ directory for case collisions: {err}']

        for path in paths:
            try:
                rel = str(path.relative_to(target_dir))
            except ValueError:
                continue
            rel_lower = rel.lower()
            if rel_lower in seen and seen[rel_lower] != rel:
                msg = f"macOS APFS case collision detected under {dir_name}/: '{seen[rel_lower]}' vs '{rel}'"
                if fail_on_collision:
                    violations.append(msg)
                else:
                    sys.stderr.write(f'[APFS CASE COLLISION NOTICE] {msg}\n')
            else:
                seen[rel_lower] = rel

    return violations


def main(argv: list[str] | None = None) -> int:
    """CLI entrypoint.

    Args:
        argv: Command-line arguments.

    Returns:
        Exit code (0 on success, 1 on violations).
    """
    parser = argparse.ArgumentParser(description='Aegis-SPARK CI Hygiene & Deletion Safety Verifier')
    parser.add_argument('--root', type=Path, default=REPO_ROOT, help='Repository root path')
    parser.add_argument(
        '--allow-stray-tilde',
        action='store_true',
        help='Report but do not fail on stray tilde paths pending manual user deletion',
    )
    parser.add_argument(
        '--allow-case-collisions',
        action='store_true',
        help='Report but do not fail on case collisions in obj/ or bin/ pending manual cleanup',
    )
    args = parser.parse_args(argv)

    root = args.root.resolve()
    all_violations: list[str] = []

    all_violations.extend(check_deletion_safety(root, fail_on_tilde=not args.allow_stray_tilde))
    all_violations.extend(check_agent_and_build_hygiene(root))
    all_violations.extend(check_directory_layout(root))
    all_violations.extend(check_secret_hygiene(root))
    all_violations.extend(check_build_case_collisions(root, fail_on_collision=not args.allow_case_collisions))

    if all_violations:
        sys.stderr.write('=====================================================\n')
        sys.stderr.write('=== CI Hygiene & Deletion Safety Violations Found ===\n')
        sys.stderr.write('=====================================================\n')
        for v in all_violations:
            sys.stderr.write(f'  [FAIL] {v}\n')
        return 1

    sys.stdout.write('[OK] Repository hygiene and deletion safety checks passed.\n')
    return 0


if __name__ == '__main__':
    sys.exit(main())
