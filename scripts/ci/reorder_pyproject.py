#!/usr/bin/env python3
"""Deterministic formatter and sorter for pyproject.toml."""

import argparse
import json
import string
import sys
import tomllib
from pathlib import Path
from typing import Any


def toml_dump_value(v: object, indent: int = 0) -> str:
    """Serialize a Python value into formatted TOML syntax.

    Args:
        v: Python object to serialize.
        indent: Current indentation depth.

    Returns:
        Formatted TOML string representation.

    Raises:
        TypeError: If an unsupported type is encountered.
    """
    if isinstance(v, bool):
        return 'true' if v else 'false'
    if isinstance(v, (int, float)):
        return str(v)
    if isinstance(v, str):
        return json.dumps(v)
    if isinstance(v, dict):
        items = ', '.join(f'{get_key_str(k)} = {toml_dump_value(val)}' for k, val in sorted(v.items()))
        return f'{{ {items} }}'
    if isinstance(v, list):
        if not v:
            return '[]'
        ind = '    ' * indent
        inner_ind = '    ' * (indent + 1)
        if any(isinstance(i, dict) for i in v):
            items = ',\n'.join(f'{inner_ind}{toml_dump_value(i, indent + 1)}' for i in v)
        else:
            try:
                unique_v = sorted(set(v))
            except TypeError:
                unique_v = v
            items = ',\n'.join(f'{inner_ind}{toml_dump_value(i, indent + 1)}' for i in unique_v)
        return f'[\n{items},\n{ind}]'
    raise TypeError(f'Unsupported type {type(v)}')


def is_bare_key(k: str) -> bool:
    """Check whether a TOML key requires quotes.

    Args:
        k: Candidate key string.

    Returns:
        True if the key does not require quotes, False otherwise.
    """
    if not k:
        return False
    valid = set(string.ascii_letters + string.digits + '-_')
    return all(c in valid for c in k)


def get_key_str(k: str) -> str:
    """Return a bare or JSON-quoted string representation of a TOML key.

    Args:
        k: Key string.

    Returns:
        Formatted bare or quoted key.
    """
    return k if is_bare_key(k) else json.dumps(k)


def has_scalars(d: dict[str, Any]) -> bool:
    """Check whether a dictionary contains any scalar values or simple lists.

    Args:
        d: TOML section dictionary.

    Returns:
        True if any scalar values or simple lists exist in the dictionary.
    """
    return any(
        not isinstance(v, (dict, list)) or (isinstance(v, list) and (not v or not isinstance(v[0], dict)))
        for v in d.values()
    )


def dump_toml_dict(d: dict[str, Any], out: list[str], prefix: str = '') -> None:
    """Recursively dump a dictionary as formatted TOML lines.

    Args:
        d: Dictionary to format.
        out: Output string accumulator list.
        prefix: Current TOML key path prefix.
    """
    for k in sorted(d.keys()):
        v = d[k]
        if isinstance(v, dict):
            continue
        if isinstance(v, list) and v and isinstance(v[0], dict):
            continue
        out.append(f'{get_key_str(k)} = {toml_dump_value(v)}')

    for k in sorted(d.keys()):
        v = d[k]
        if isinstance(v, dict):
            if has_scalars(v):
                out.append(f'\n[{prefix}{get_key_str(k)}]')
            dump_toml_dict(v, out, prefix + get_key_str(k) + '.')
        elif isinstance(v, list) and v and isinstance(v[0], dict):
            for item in sorted(v, key=str):
                if isinstance(item, dict):
                    out.append(f'\n[[{prefix}{get_key_str(k)}]]')
                    dump_toml_dict(item, out, prefix + get_key_str(k) + '.')


def _format_pyproject_dict(data: dict[str, Any]) -> str:
    """Format parsed pyproject TOML data into canonical string.

    Args:
        data: Parsed TOML dictionary.

    Returns:
        Canonical formatted TOML text.
    """
    out: list[str] = []
    order = ['project', 'dependency-groups', 'build-system', 'tool']
    for k in order:
        if k in data and k != 'tool':
            if k != order[0]:
                out.append('')
            if isinstance(data[k], dict):
                if has_scalars(data[k]):
                    out.append(f'[{get_key_str(k)}]')
                dump_toml_dict(data[k], out, get_key_str(k) + '.')
            else:
                out.append(f'{get_key_str(k)} = {toml_dump_value(data[k])}')

    if 'tool' in data:
        tool_order = ['pixi', 'ruff', 'mypy', 'pytest', 'coverage', 'rumdl']
        for tk in tool_order:
            if tk in data['tool']:
                if has_scalars(data['tool'][tk]):
                    out.append(f'\n[tool.{get_key_str(tk)}]')
                dump_toml_dict(data['tool'][tk], out, f'tool.{get_key_str(tk)}.')

        for tk in sorted(data['tool'].keys()):
            if tk not in tool_order:
                if has_scalars(data['tool'][tk]):
                    out.append(f'\n[tool.{get_key_str(tk)}]')
                dump_toml_dict(data['tool'][tk], out, f'tool.{get_key_str(tk)}.')

    return '\n'.join(out) + '\n'


def _reorder_single_file(file_path: Path, check: bool) -> bool:
    """Process a single pyproject.toml file.

    Args:
        file_path: Path to target file.
        check: Whether to verify without writing.

    Returns:
        True if formatting is clean, False if errors or changes occurred.
    """
    try:
        with file_path.open('rb') as f:
            original_content = f.read().decode('utf-8')
            f.seek(0)
            data = tomllib.load(f)
    except (OSError, tomllib.TOMLDecodeError) as e:
        sys.stderr.write(f'Error reading {file_path}: {e}\n')
        return False

    new_content = _format_pyproject_dict(data)
    if original_content != new_content:
        if check:
            sys.stderr.write(f'{file_path} is not sorted correctly. Run without --check to fix.\n')
            return False
        with file_path.open('w', encoding='utf-8') as f:
            f.write(new_content)
        sys.stdout.write(f'Reordered and sorted {file_path}\n')
        return False
    return True


def main(argv: list[str] | None = None) -> int:
    """CLI entrypoint to check or format pyproject.toml files.

    Args:
        argv: Command-line arguments.

    Returns:
        0 on success, 1 on format mismatches or errors.
    """
    parser = argparse.ArgumentParser(description='Sort pyproject.toml in a predictable, diff-friendly way.')
    parser.add_argument('filenames', nargs='+', help='Paths to the pyproject.toml files')
    parser.add_argument(
        '--check',
        action='store_true',
        help='Check if formatting is correct without modifying the file',
    )
    args = parser.parse_args(argv)

    exit_code = 0
    for filename in args.filenames:
        if not _reorder_single_file(Path(filename), args.check):
            exit_code = 1

    return exit_code


if __name__ == '__main__':
    sys.exit(main())
