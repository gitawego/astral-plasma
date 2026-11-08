#!/usr/bin/env python3
"""Generate `modules/Astral/Apps/index.json` from the shipped app directories.

`shell.qml` must not name a feature and QML cannot list a directory, so the set of
bundled apps is data: one generated index, checked in, verified by CI (`--check`).
"""

from __future__ import annotations

import json
import pathlib
import sys

APPS_DIR = pathlib.Path("modules/Astral/Apps")
INDEX = APPS_DIR / "index.json"


def discover() -> list[dict[str, str]]:
    apps: list[dict[str, str]] = []
    for entry in sorted(APPS_DIR.iterdir()):
        manifest = entry / "manifest.json"
        if not entry.is_dir() or not manifest.is_file():
            continue
        apps.append({"dir": entry.name, "id": json.loads(manifest.read_text())["id"]})
    return apps


def main(argv: list[str]) -> int:
    content = json.dumps({"schema": 1, "apps": discover()}, indent=2) + "\n"
    if "--check" in argv:
        current = INDEX.read_text(encoding="utf-8") if INDEX.exists() else ""
        if current != content:
            print(f"error: {INDEX} is stale; run scripts/gen_apps_index.py", file=sys.stderr)
            return 1
        return 0
    INDEX.write_text(content, encoding="utf-8")
    print(f"{INDEX}: wrote {len(discover())} apps")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
