#!/usr/bin/env python3
"""Static Stack Analysis and Zero Dynamic Allocation Verification Gate.

Enforces:
1. Every subprogram in the SPARK Ada 2022 safety kernel has bounded static stack
   usage (<= max_frame_bytes, default 4096 bytes per subprogram frame).
2. Strict zero dynamic heap allocation under `pragma Profile (Jorvik)`: verifies
   that zero dynamic objects and zero dynamic stack frames exist in GCC callgraph
   (`.ci`) artifacts.
"""

import argparse
import re
import sys
from dataclasses import dataclass
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_MAX_FRAME_BYTES = 4096

NODE_PATTERN = re.compile(r'node:\s*\{\s*title:\s*"([^"]+)"\s+label:\s*"([^"]+)".*?\}')
STATIC_STACK_PATTERN = re.compile(r'(\d+)\s+bytes\s+\(static\)')
DYNAMIC_STACK_PATTERN = re.compile(r'(\d+)\s+bytes\s+\(dynamic\)')
DYNAMIC_OBJECTS_PATTERN = re.compile(r'(\d+)\s+dynamic objects')


@dataclass(frozen=True)
class SubprogramStackInfo:
    """Represents stack usage and dynamic allocation metrics for a subprogram node."""

    file_path: Path
    title: str
    subprogram_name: str
    source_location: str
    static_bytes: int | None
    dynamic_bytes: int | None
    dynamic_objects: int | None


def parse_ci_file(ci_file: Path) -> list[SubprogramStackInfo]:
    """Parse a GCC callgraph (.ci) artifact into structured subprogram metrics.

    Args:
        ci_file: Path to the .ci callgraph file.

    Returns:
        List of parsed SubprogramStackInfo entries.
    """
    results: list[SubprogramStackInfo] = []
    content = ci_file.read_text(encoding='utf-8')

    for line in content.splitlines():
        match = NODE_PATTERN.search(line)
        if not match:
            continue

        title, label = match.group(1), match.group(2)
        parts = label.split('\\n')
        subprogram_name = parts[0] if parts else title
        source_loc = parts[1] if len(parts) > 1 else 'unknown'

        static_match = STATIC_STACK_PATTERN.search(label)
        dynamic_match = DYNAMIC_STACK_PATTERN.search(label)
        objects_match = DYNAMIC_OBJECTS_PATTERN.search(label)

        static_bytes = int(static_match.group(1)) if static_match else None
        dynamic_bytes = int(dynamic_match.group(1)) if dynamic_match else None
        dynamic_objects = int(objects_match.group(1)) if objects_match else None

        results.append(
            SubprogramStackInfo(
                file_path=ci_file,
                title=title,
                subprogram_name=subprogram_name,
                source_location=source_loc,
                static_bytes=static_bytes,
                dynamic_bytes=dynamic_bytes,
                dynamic_objects=dynamic_objects,
            )
        )

    return results


def _locate_ci_files(root: Path, ci_dir: Path | None) -> list[Path]:
    """Discover .ci callgraph files in the designated or standard build directory.

    Args:
        root: Repository root path.
        ci_dir: Optional specific directory.

    Returns:
        Sorted list of matching .ci file paths.
    """
    if ci_dir is not None:
        return sorted(ci_dir.glob('*.ci'))

    candidates = [
        root / 'obj' / 'validation' / 'lib',
        root / 'obj' / 'validation',
        root / 'obj' / 'release',
        root / 'obj',
    ]
    for cand in candidates:
        if cand.is_dir():
            matches = sorted(cand.glob('*.ci'))
            if matches:
                return matches

    return []


def _validate_node(node: SubprogramStackInfo, root: Path, max_frame_bytes: int) -> list[str]:
    """Validate a single subprogram node for stack and dynamic allocation rules.

    Args:
        node: Parsed subprogram stack metrics.
        root: Repository root directory.
        max_frame_bytes: Maximum permitted stack frame size in bytes.

    Returns:
        List of violation strings.
    """
    violations: list[str] = []
    rel_path = node.file_path.relative_to(root)

    if node.dynamic_objects is not None and node.dynamic_objects > 0:
        violations.append(
            f'{rel_path}: Subprogram "{node.subprogram_name}" ({node.title}) at {node.source_location} '
            f'has {node.dynamic_objects} dynamic objects (heap allocation violates pragma Profile (Jorvik)).'
        )

    if node.dynamic_bytes is not None and node.dynamic_bytes > 0:
        violations.append(
            f'{rel_path}: Subprogram "{node.subprogram_name}" ({node.title}) at {node.source_location} '
            f'uses {node.dynamic_bytes} dynamic stack bytes (unbounded/variable stack frame).'
        )

    if node.static_bytes is not None and node.static_bytes > max_frame_bytes:
        violations.append(
            f'{rel_path}: Subprogram "{node.subprogram_name}" ({node.title}) at {node.source_location} '
            f'exceeds static stack limit: {node.static_bytes} bytes > {max_frame_bytes} bytes limit.'
        )

    return violations


def verify_static_stack(
    root: Path,
    ci_dir: Path | None = None,
    max_frame_bytes: int = DEFAULT_MAX_FRAME_BYTES,
    verbose: bool = False,
) -> tuple[int, list[str]]:
    """Verify bounded static stack frames and zero dynamic objects across all .ci files.

    Args:
        root: Repository root directory.
        ci_dir: Optional specific directory to search for .ci files.
        max_frame_bytes: Maximum permitted stack frame size per function in bytes.
        verbose: Whether to print detailed subprogram metrics.

    Returns:
        A tuple of (exit_code, violations_list).
    """
    ci_files = _locate_ci_files(root, ci_dir)
    if not ci_files:
        return 1, ['No GCC callgraph (.ci) files found. Ensure the project is built with -fcallgraph-info=su,da.']

    all_nodes: list[SubprogramStackInfo] = []
    for ci_file in ci_files:
        all_nodes.extend(parse_ci_file(ci_file))

    metrics_nodes = [node for node in all_nodes if node.static_bytes is not None or node.dynamic_objects is not None]
    if not metrics_nodes:
        return 1, ['No nodes with stack or dynamic object information found in .ci files.']

    violations: list[str] = []
    max_observed_stack = 0
    max_observed_node: SubprogramStackInfo | None = None

    for node in metrics_nodes:
        violations.extend(_validate_node(node, root, max_frame_bytes))
        if node.static_bytes is not None and node.static_bytes > max_observed_stack:
            max_observed_stack = node.static_bytes
            max_observed_node = node

        if verbose:
            rel = node.file_path.relative_to(root).name
            sys.stdout.write(
                f'  [{rel}] {node.subprogram_name:<30} static={node.static_bytes or 0:>5} B, '
                f'dyn_objs={node.dynamic_objects or 0} ({node.source_location})\n'
            )

    if violations:
        return 1, violations

    name = f'"{max_observed_node.subprogram_name}"' if max_observed_node else 'none'
    sys.stdout.write(
        f'[OK] Static stack analysis passed: {len(metrics_nodes)} subprograms in {len(ci_files)} .ci file(s).\n'
        f'     Max static stack frame: {max_observed_stack} B in {name} (limit: {max_frame_bytes} B).\n'
        f'     Dynamic objects: 0 across all units (strict Jorvik compliance verified).\n'
    )
    return 0, []


def main(argv: list[str] | None = None) -> int:
    """CLI entrypoint for static stack analysis and Jorvik zero-heap verification.

    Args:
        argv: Command-line arguments.

    Returns:
        Exit code (0 on success, 1 on violations).
    """
    parser = argparse.ArgumentParser(
        description='Verify bounded static stack frames and zero dynamic heap allocation via GCC callgraph (.ci) files.'
    )
    parser.add_argument('--root', type=Path, default=REPO_ROOT, help='Repository root path')
    parser.add_argument('--ci-dir', type=Path, default=None, help='Directory containing .ci files to scan')
    parser.add_argument(
        '--max-frame-bytes',
        type=int,
        default=DEFAULT_MAX_FRAME_BYTES,
        help=f'Maximum allowed static stack frame in bytes per subprogram (default: {DEFAULT_MAX_FRAME_BYTES})',
    )
    parser.add_argument('--verbose', action='store_true', help='Print detailed per-subprogram stack usage')

    args = parser.parse_args(argv)
    code, violations = verify_static_stack(
        root=args.root.resolve(),
        ci_dir=args.ci_dir.resolve() if args.ci_dir else None,
        max_frame_bytes=args.max_frame_bytes,
        verbose=args.verbose,
    )

    if code != 0:
        sys.stderr.write('[FAIL] Static stack and heap verification violations detected:\n')
        for v in violations:
            sys.stderr.write(f'  - {v}\n')
        return code

    return 0


if __name__ == '__main__':
    sys.exit(main())
