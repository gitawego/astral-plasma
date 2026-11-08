#!/usr/bin/env python3
"""Generate a QML module `qmldir` from a directory tree.

QML module URIs map onto paths (`Astral.Kernel` -> `Astral/Kernel`), and a
`qmldir` type entry may point into a subdirectory (`Pill 1.0 components/Pill.qml`).
That is what lets one module expose `theme/`, `components/`, `services/` and
`config/` without inventing a module per folder.

Usage:
    gen_qmldir.py modules/Astral/Kernel       # write Astral/Kernel/qmldir
    gen_qmldir.py modules/Astral/Kernel --check
    gen_qmldir.py modules/Astral/Kernel --module Astral.Kernel --check

`--check` exits 1 when the file on disk is stale, so CI fails instead of a
runtime "Type ... is not a type" at boot.

Two failure modes it refuses instead of writing something that half-works:

* two files that flatten to the same type name (`a/Panel.qml` and
  `b/Panel.qml`) — QML would silently pick one;
* a file whose type name is not a valid QML identifier.

Singletons are emitted with the `singleton` keyword: a file with
`pragma Singleton` that is registered as a plain type fails at runtime with
"Singleton is not a type" on first use.
"""

from __future__ import annotations

import argparse
import pathlib
import re
import sys

SINGLETON_RE = re.compile(r"^\s*pragma\s+Singleton\b", re.MULTILINE)
IDENT_RE = re.compile(r"^[A-Z][A-Za-z0-9_]*$")


def scan(module_dir: pathlib.Path) -> tuple[list[str], list[str]]:
    """Return (type lines, problems) for every .qml file under module_dir."""
    types: dict[str, pathlib.Path] = {}
    lines: list[str] = []
    problems: list[str] = []

    for path in sorted(module_dir.rglob("*.qml")):
        rel = path.relative_to(module_dir)
        name = path.stem
        if not IDENT_RE.match(name):
            problems.append(f"{rel}: '{name}' is not a valid QML type name")
            continue
        if name in types:
            problems.append(
                f"duplicate type name '{name}': {types[name]} and {rel} "
                f"(QML would silently pick one)"
            )
            continue
        types[name] = rel
        text = path.read_text(encoding="utf-8", errors="replace")
        prefix = "singleton " if SINGLETON_RE.search(text) else ""
        lines.append(f"{prefix}{name} 1.0 {rel.as_posix()}")

    return sorted(lines), problems


def render(module: str, lines: list[str]) -> str:
    return "\n".join([f"module {module}", *lines, ""])


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("module_dir", type=pathlib.Path)
    ap.add_argument("--module", help="module URI (default: derived from path)")
    ap.add_argument(
        "--check",
        action="store_true",
        help="exit 1 if the qmldir on disk does not match the tree",
    )
    args = ap.parse_args(argv)

    module_dir: pathlib.Path = args.module_dir
    if not module_dir.is_dir():
        print(f"error: {module_dir} is not a directory", file=sys.stderr)
        return 2

    lines, problems = scan(module_dir)
    if problems:
        for problem in problems:
            print(f"error: {problem}", file=sys.stderr)
        return 2

    module = args.module
    if module is None:
        parts = module_dir.resolve().parts
        # `Astral/Kernel` -> `Astral.Kernel`; keep the two deepest segments that
        # start above the module dir, which is the only portable guess.
        module = ".".join(parts[-2:])

    content = render(module, lines)
    target = module_dir / "qmldir"

    if args.check:
        current = target.read_text(encoding="utf-8") if target.exists() else ""
        if current != content:
            print(
                f"error: {target} is stale; run scripts/gen_qmldir.py {module_dir}",
                file=sys.stderr,
            )
            return 1
        print(f"{target}: up to date ({len(lines)} types)")
        return 0

    target.write_text(content, encoding="utf-8")
    print(f"{target}: wrote {len(lines)} types")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
