# Astral AppKit — the SDK

Everything an app may use is in `Astral.AppKit`: `AppWindow` for the surface, `Colors`,
`Theme`, `Motion` for the design system, `AppApi` for the compatibility level, and
`AppPalette` for wallpaper-derived tokens. Nothing else is importable — the sandbox mounts
only this directory, so an `import Astral.Kernel…` fails at load with a message naming the
module.

The contract is generated and enforced:
[`docs/APPKIT-API.md`](../docs/APPKIT-API.md) lists every frozen member, the level history,
the deprecation table, and the floor-bump procedure.

## Start

```bash
astral-plasma app new io.github.you.thing --template surface          # a window
astral-plasma app new io.github.you.panel --template layer-surface    # a panel
astral-plasma app new io.github.you.worker --template service         # no surface
astral-plasma app dev io.github.you.thing --sandbox                   # run it fenced
astral-plasma app test io.github.you.thing                            # its QML suite
astral-plasma app lint io.github.you.thing                            # the rules below
astral-plasma app pack io.github.you.thing --out dist
```

Two examples ship with the SDK: [`examples/hello`](examples/hello) (a window) and
[`examples/tide`](examples/tide) (an anchored panel). `daemon/tests/test_sdk_examples.rs`
packs and installs both on every run, so they cannot rot.

## What an app declares

`manifest.json` is the whole interface with the platform:

| Field | Meaning |
| --- | --- |
| `id` | reverse-DNS, unique, immutable |
| `version` | semver; a permission change is at least a minor bump |
| `kernelApi` | the AppKit level the app was built against |
| `minQuickshell` | optional; the oldest Quickshell the app runs on |
| `runtime` | `hosted` (sandboxed, default) or `embedded` (official only) |
| `trust` | `official`, `community`, or `partner` |
| `entry.surface` | `toplevel` (needs width/height) or `layer-shell` (anchored) |
| `permissions` | a closed list; anything else is a validation error |
| `requires.capabilities` / `qtModules` | declared prerequisites, checked at install |

## Permissions

Declaring a permission is **asking**; the user granting it at install is **consent**. The
broker reads the registry, never your manifest, so editing a manifest after install changes
nothing.

| Permission | Allows |
| --- | --- |
| `windows.read` | `session.windows` |
| `windows.control` | `session.activate`, `session.close` |
| `workspaces.read` | `workspaces.list` |
| `workspaces.control` | `workspaces.switch` |
| `media.read` | `media.state` |
| `notifications.post` | `notifications.post` |
| `network` | a shared network namespace |
| `files.read` / `files.write` | the app's own config and cache directories |

In the sandbox an app has: no `$HOME` of yours, no session runtime directory, no network
unless granted, no kernel sources, and a private writable `HOME`, `XDG_CONFIG_HOME` and
`XDG_CACHE_HOME` that persist between runs.

Requests go over one Unix socket, `$ASTRAL_BROKER`, and every one is rate limited and
audited:

```json
{"id": 1, "method": "session.windows", "token": "<ASTRAL_APP_TOKEN>"}
```

```json
{"id": 1, "status": "applied", "value": [...]}
```

`status` is `applied`, `denied` (permission not granted), `unsupported` (no such method),
`stale` (rate limited), `unavailable` (granted, but this shell cannot serve it), or
`invalid`. A refusal names what was missing.

## Author checklist

1. `astral-plasma app lint` is clean — no `Astral.Kernel`, no `Config.` reads, no sibling app
   imports.
2. `astral-plasma app test` passes; the suite runs offscreen, without your desktop.
3. Nothing is fabricated: no fake timers, no placeholder data, no simulated telemetry. If a
   value is not available, show that it is not available.
4. Every animation uses `Motion` tokens; no hardcoded durations or linear easing.
5. Text contrast holds against `Colors.surface` in both light and dark palettes.
6. The app declares only the permissions it actually uses, and degrades to a visible hint
   when one is refused.
7. `kernelApi` matches the level the app was tested against, and `docs/APPKIT-API.md` shows
   no deprecated member in use.
8. `version` and the changelog entry are updated together.

## Compatibility

An app whose `kernelApi` is outside `[floor, level]` does not load. On a platform update the
shell auto-updates an app to a compatible version when one exists, and otherwise disables it
with a recorded, actionable reason. Nothing is uninstalled behind your back.
