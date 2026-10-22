#!/usr/bin/env python3
"""SPARK Ada 2022 Contract and Formal Verification Hygiene Gate.

Enforces:
1. Every Ada specification (.ads) and body (.adb) under src/ explicitly declares
   'pragma Ada_2022;' and 'SPARK_Mode => On' (or 'SPARK_Mode => Off' strictly
   isolated to thin FFI package bodies, never package specifications).
2. No unjustified 'pragma Annotate (GNATprove, ...)' suppressions exist in src/.
3. If gnatprove report artifacts exist under obj/*/gnatprove/gnatprove.out,
   verifies zero unproved Verification Conditions (VCs).
"""

import argparse
import re
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]

SPARK_MODE_ON_PATTERN = re.compile(r'\bSPARK_Mode\s*=>\s*On\b|\bpragma\s+SPARK_Mode\s*\(\s*On\s*\)')
SPARK_MODE_OFF_PATTERN = re.compile(r'\bSPARK_Mode\s*=>\s*Off\b|\bpragma\s+SPARK_Mode\s*\(\s*Off\s*\)')
ANNOTATE_PATTERN = re.compile(r'pragma\s+Annotate\s*\(\s*GNATprove\b(.*?)\)\s*;', re.DOTALL)


def check_ada_sources(root: Path) -> list[str]:
    """Inspect all Ada specifications and bodies in src/ for SPARK_Mode and Ada_2022 compliance.

    Args:
        root: Repository root directory.

    Returns:
        List of violation messages.
    """
    violations: list[str] = []
    src_dir = root / 'src'
    if not src_dir.is_dir():
        return [f'Missing src/ directory at {src_dir}']

    ada_files = sorted([*src_dir.rglob('*.ads'), *src_dir.rglob('*.adb')])
    if not ada_files:
        return ['No Ada (.ads/.adb) source files found in src/']

    for ada_file in ada_files:
        rel_path = ada_file.relative_to(root)
        content = ada_file.read_text(encoding='utf-8')

        if 'pragma Ada_2022;' not in content:
            violations.append(f'{rel_path}: Missing explicit "pragma Ada_2022;" header.')

        has_on = bool(SPARK_MODE_ON_PATTERN.search(content))
        has_off = bool(SPARK_MODE_OFF_PATTERN.search(content))

        if not has_on and not has_off:
            violations.append(f'{rel_path}: Missing explicit SPARK_Mode aspect or pragma.')

        if ada_file.suffix == '.ads' and has_off:
            violations.append(
                f'{rel_path}: Package specifications (.ads) must have SPARK_Mode => On; '
                'isolate SPARK_Mode => Off strictly to thin FFI package bodies (.adb).'
            )

        for match in ANNOTATE_PATTERN.finditer(content):
            inner_args = match.group(1)
            if inner_args.count(',') < 3:
                violations.append(
                    f'{rel_path}: pragma Annotate (GNATprove, ...) must include an explicit '
                    '4th safety justification string argument.'
                )

    return violations


def check_gnatprove_reports(root: Path) -> list[str]:
    """Inspect existing gnatprove.out reports under obj/ for unproved checks.

    Args:
        root: Repository root directory.

    Returns:
        List of unproved check violations if any reports exist and contain failures.
    """
    violations: list[str] = []
    obj_dir = root / 'obj'
    if not obj_dir.is_dir():
        return violations

    reports = sorted(obj_dir.glob('*/gnatprove/gnatprove.out'))
    for report in reports:
        rel_report = report.relative_to(root)
        text = report.read_text(encoding='utf-8')
        for line in text.splitlines():
            stripped = line.strip()
            if stripped.startswith('Total'):
                cols = stripped.split()
                if cols and cols[-1] != '.':
                    violations.append(f'{rel_report}: Contains {cols[-1]} unproved SPARK Verification Condition(s).')

    return violations


def main(argv: list[str] | None = None) -> int:
    """CLI entrypoint for SPARK contract and proof hygiene verification.

    Args:
        argv: Command-line arguments.

    Returns:
        Exit code (0 on success, 1 on violations).
    """
    parser = argparse.ArgumentParser(description='Verify SPARK Ada 2022 source and proof hygiene.')
    parser.add_argument('--root', type=Path, default=REPO_ROOT, help='Repository root path')
    args = parser.parse_args(argv)

    root = args.root.resolve()
    violations = [*check_ada_sources(root), *check_gnatprove_reports(root)]
    if violations:
        sys.stderr.write('[FAIL] SPARK Ada 2022 hygiene violations detected:\n')
        for v in violations:
            sys.stderr.write(f'  - {v}\n')
        return 1

    sys.stdout.write('[OK] SPARK Ada 2022 source contracts and proof hygiene verified.\n')
    return 0


if __name__ == '__main__':
    sys.exit(main())
