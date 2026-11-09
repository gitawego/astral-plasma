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
6. Every intent an app requests in the shell (`intents.request("x")`) must have a handler
   registered in `shell.qml`. An unregistered intent is silently dropped — the same shape of
   bug as an undeclared port member, and it shipped once: a careless rename turned
   `media.visualizerStyle` into `shellState.mediaVisualizerStyle` and the visualiser style
   button stopped responding without a single error.
7. Every property an app reads from an injected port (`shellState`, `media`, `session`,
   `workspaces`, `metrics`) must exist on that port. A typo or a renamed property reads as
   `undefined`, and `undefined` is falsy, so the app silently takes the "nothing is
   happening" branch: the media tab shipped with `media.isPlaying` on a port that only had
   `status`, and the transport glyph and the audio visualiser were dead for days while
   every test passed (spec C.31).

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
#: Any mention of the settings singleton. `typeof Config !== "undefined"` is the dangerous
#: shape: an app never imports Config, so the guard is permanently false and the value it
#: was protecting silently becomes a default (or `undefined`). That shipped as a dead
#: visualiser-style button, default download settings, and an "always private" AI panel.
CONFIG_ANY = re.compile(r"(?<![A-Za-z0-9_.])Config(?![A-Za-z0-9_])")

FORBIDDEN_DIRS = {"Kernel/config", "Kernel/services"}

HOST = pathlib.Path("modules/Astral/Kernel/Host")
#: Port module -> the injection property an app receives it as.
PORTS = {
    "ShellState.qml": "shellState",
    "MediaPort.qml": "media",
    "SessionPort.qml": "session",
    "WorkspacesPort.qml": "workspaces",
    # The shell injects its live metrics service, not `MetricsPort` (which exists for
    # hosts that do not have one). Check the type apps actually receive.
    "services/SystemService.qml": "metrics",
}
#: Members inherited from QML's own objects/arrays; never declared by a port.
BUILTIN_MEMBERS = {
    "length", "map", "filter", "forEach", "slice", "indexOf", "includes", "push", "join",
    "concat", "sort", "find", "some", "every", "reduce", "keys", "values", "hasOwnProperty",
}
PROPERTY = re.compile(r"^\s*(?:readonly\s+)?property\s+[A-Za-z0-9_<>:]+\s+([A-Za-z0-9_]+)")
FUNCTION = re.compile(r"^\s*function\s+([A-Za-z0-9_]+)")
SIGNAL = re.compile(r"^\s*signal\s+([A-Za-z0-9_]+)")


INTENT_REQUEST = re.compile(r'intents\.request\(\s*"([^"]+)"')
INTENT_HANDLER = re.compile(r'intents\.register\(\s*"([^"]+)"')


def check_intents(app_dir: pathlib.Path, shell_file: pathlib.Path) -> list[str]:
    """Flag intents an app requests that the shell never registers."""
    problems: list[str] = []
    try:
        handled = set(INTENT_HANDLER.findall(shell_file.read_text(encoding="utf-8")))
    except OSError:
        return problems
    for file in sorted(app_dir.rglob("*")):
        if file.suffix not in {".qml", ".js"}:
            continue
        try:
            text = file.read_text(encoding="utf-8")
        except OSError:
            continue
        for number, line in enumerate(text.splitlines(), start=1):
            if line.lstrip().startswith("//"):
                continue
            for intent in INTENT_REQUEST.findall(line):
                if intent in handled:
                    continue
                problems.append(
                    f"{file}:{number}: requests the intent '{intent}', which shell.qml never "
                    f"registers (the click does nothing and reports nothing)"
                )
    return problems


def port_members(path: pathlib.Path) -> set[str]:
    """The members a port declares: properties, functions and signals."""
    members: set[str] = set()
    try:
        text = path.read_text(encoding="utf-8")
    except OSError:
        return members
    for line in text.splitlines():
        for pattern in (PROPERTY, FUNCTION, SIGNAL):
            match = pattern.match(line)
            if match:
                members.add(match.group(1))
    return members


STATE_INSTANCE = re.compile(r"ShellState\s*\{([\s\S]*?)\n    \}")


def check_state_populated(state_file: pathlib.Path, shell_file: pathlib.Path) -> list[str]:
    """Flag `ShellState` properties the shell never populates.

    A member that exists but is never assigned is the mirror image of the bug in spec
    C.31: the app reads a real property that is always at its default, so every surface
    shows the fallback while nothing reports a problem.
    """
    try:
        state_text = state_file.read_text(encoding="utf-8")
        shell_text = shell_file.read_text(encoding="utf-8")
    except OSError:
        return []
    match = STATE_INSTANCE.search(shell_text)
    if not match:
        return [f"{shell_file}: no `ShellState {{ }}` instance found"]
    assigned = set(re.findall(r"^\s*([A-Za-z_][A-Za-z0-9_]*)\s*:", match.group(1), re.M))
    problems = []
    for line in state_text.splitlines():
        prop = PROPERTY.match(line)
        if not prop:
            continue
        name = prop.group(1)
        if name in assigned:
            continue
        problems.append(
            f"{state_file}: `{name}` is declared but never populated in {shell_file} "
            f"(every app reads its default)"
        )
    return problems


def check_port_members(path: pathlib.Path, app_dir: pathlib.Path) -> list[str]:
    """Flag app reads of port members the port does not declare."""
    problems: list[str] = []
    usage = re.compile(
        r"\b(?:root\.)?(" + "|".join(PORTS.values()) + r")\.([A-Za-z_][A-Za-z0-9_]*)"
    )
    def port_path(module: str) -> pathlib.Path:
        # `ShellState.qml` sits in Host/, `services/SystemService.qml` one level up.
        candidate = HOST / module
        return candidate if candidate.is_file() else HOST.parent / module

    declared = {name: port_members(port_path(module)) for module, name in PORTS.items()}
    for file in sorted(app_dir.rglob("*")):
        if file.suffix not in {".qml", ".js"}:
            continue
        try:
            text = file.read_text(encoding="utf-8")
        except OSError:
            continue
        for number, line in enumerate(text.splitlines(), start=1):
            if line.lstrip().startswith("//"):
                continue
            # Blank out string literals: `intents.request("media.visualizerStyle")` names an
            # intent, it does not read a port member.
            code = re.sub(r'"[^"]*"', '""', line)
            for port, member in usage.findall(code):
                if member in BUILTIN_MEMBERS:
                    continue
                if member in declared[port]:
                    continue
                problems.append(
                    f"{file}:{number}: reads {port}.{member}, which {port} does not declare "
                    f"(it is `undefined`, and every dependent branch silently takes the "
                    f"'nothing is happening' path)"
                )
    return problems


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
        code = re.sub(r'"[^"]*"', '""', line)
        if not line.lstrip().startswith("//") and CONFIG_ANY.search(code) and not CONFIG_USE.search(code):
            problems.append(
                f"{path}:{number}: references Config, which an app does not have - "
                f"`typeof Config` is always false; read the injected port instead"
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
        problems.extend(check_port_members(app_dir, app_dir))
        problems.extend(check_intents(app_dir, pathlib.Path("shell.qml")))

    problems.extend(check_state_populated(HOST / "ShellState.qml", pathlib.Path("shell.qml")))

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
