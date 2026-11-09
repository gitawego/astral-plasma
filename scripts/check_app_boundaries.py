#!/usr/bin/env python3
"""Enforce the app boundary: what an app may import.

Spec section 6.2. The short version, and the reason this exists at all: an app that
imports `Kernel/config` gets its **own** singleton instance (spec C.9), so every
read is a stale copy - and an app that imports `Kernel/services` or another app can
reach past the host contract entirely. Neither is a style issue; both produce
surfaces that render with the wrong state or bypass the intent bus.

Rules for `modules/Astral/Apps/**`:

1. `Kernel/config` is forbidden for **every** app — use the injected `shellState`
   and `intents`. A `typeof` guard does not help: the stale copy is the problem.
2. `Kernel/services` is forbidden for **non-official** apps, which may only use
   `Astral.AppKit`. Official embedded apps are trusted (`spec 7.1`) and may use
   the kernel's ports, because that is how a session surface reads windows.
3. Another app's directory is forbidden — cross-app work goes through intents.
4. `Astral.Kernel` (the module URI) is forbidden; `Astral.AppKit` is the public SDK.
5. Direct `Config.` reads are forbidden, including behind `typeof` guards.

Allowed: Qt*, Quickshell*, `Astral.AppKit`, `Kernel/theme`, `Kernel/components`
(design primitives), and anything inside the app's own directory.

Usage:
    check_app_boundaries.py            # report violations, exit 1 if any
    check_app_boundaries.py --verbose  # also print the files it checked
    check_app_boundaries.py --app Media  # only one app (the CI matrix runs one per job)
"""

from __future__ import annotations

import json
import pathlib
import re
import sys

APPS = pathlib.Path("modules/Astral/Apps")
IMPORT = re.compile(r'^\s*import\s+"(?P<path>[^"]+)"')
CONFIG_USE = re.compile(r"\bConfig\.[A-Za-z0-9_]+")

FORBIDDEN_DIRS = {"Kernel/config", "Kernel/services"}


def apps() -> list[pathlib.Path]:
    if not APPS.is_dir():
        return []
    return sorted(p for p in APPS.glob("*") if p.is_dir() and (p / "manifest.json").is_file())


def is_official(app_dir: pathlib.Path) -> bool:
    try:
        data = json.loads((app_dir / "manifest.json").read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return False
    return data.get("trust") == "official"


def check_file(path: pathlib.Path, app_dir: pathlib.Path, official: bool) -> list[str]:
    problems: list[str] = []
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        match = IMPORT.match(line)
        if match:
            target = match.group("path")
            normalised = target.replace("\\", "/")
            if "Astral.Kernel" in normalised:
                problems.append(f"{path}:{number}: imports the private kernel module ({target})")
            if "Kernel/config" in normalised:
                problems.append(
                    f"{path}:{number}: imports {target} - use the injected shellState"
                )
            if "Kernel/services" in normalised and not official:
                problems.append(
                    f"{path}:{number}: a non-official app may not import {target} "
                    f"(Astral.AppKit only)"
                )
            # Another app: any path that leaves this app for a sibling.
            if "Apps/" in normalised and f"Apps/{app_dir.name}" not in normalised:
                problems.append(
                    f"{path}:{number}: imports another app ({target}) - use an intent"
                )
        for usage in CONFIG_USE.findall(line):
            problems.append(
                f"{path}:{number}: reads {usage} directly - a Loader-loaded app gets its own "
                f"singleton copy; use shellState/ints"
            )
    return problems


def main(argv: list[str]) -> int:
    verbose = "--verbose" in argv
    checked = 0
    problems: list[str] = []

    app_dirs = apps()
    if "--app" in argv:
        wanted = argv[argv.index("--app") + 1]
        app_dirs = [d for d in app_dirs if d.name == wanted]
        if not app_dirs:
            print(f"no app named '{wanted}' in {APPS}", file=sys.stderr)
            return 1
    for app_dir in app_dirs:
        for path in sorted(app_dir.rglob("*")):
            if path.suffix not in {".qml", ".js"}:
                continue
            checked += 1
            problems.extend(check_file(path, app_dir, is_official(app_dir)))

    for problem in problems:
        print(problem, file=sys.stderr)

    if verbose:
        print(f"checked {checked} file(s) in {len(app_dirs)} app(s)")

    if problems:
        print(
            f"\n{len(problems)} boundary violation(s). See docs/APPS-PLATFORM-SPEC.md section 6.2.",
            file=sys.stderr,
        )
        return 1
    if verbose:
        print("app boundaries: clean")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
