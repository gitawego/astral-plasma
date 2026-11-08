# Astral App Platform Specification

> **Status**: proposal v5 for review. No implementation has started.
> **v5**: what happens when a platform update leaves an app outside the window —
> auto-update if a compatible version exists, otherwise disable with a warning
> (§8.5.4).
> **v4**: every app owns its version, including preinstalled ones; the core
> package ships baselines, not the version authority (§8.5).
> **v3**: app versioning and the platform compatibility rule (§8.5, A12, A21–A30).
> **Goal**: make Astral a **platform** — anyone can build an app against a stable
> SDK, package it, and install it in one step, without a checkout of this
> repository. Official apps keep the integrated glass experience; community apps
> run isolated and permission-scoped.
> **Related**: [`ARCHITECTURE.md`](ARCHITECTURE.md) (DDD layers),
> [`UPDATES.md`](UPDATES.md) (install/update ownership),
> [`../CONTEXT.md`](../CONTEXT.md) (ubiquitous language),
> [`../DESIGN.md`](../DESIGN.md) (design authority),
> [`HYPRLAND-OMARCHY-SPEC.md`](HYPRLAND-OMARCHY-SPEC.md) (profiles).

---

## 1. Goal and non-goals

### Goal

An app author with no Astral checkout can:

```bash
astral app new io.github.alice.clock --template surface
cd io.github.alice.clock
astral app dev .            # live, sandboxed, hot reload
astral app test .           # headless tests
astral app pack .           # builds io.github.alice.clock-0.1.0.astralapp
```

and a user can:

```bash
astral app install ./io.github.alice.clock-0.1.0.astralapp
astral app install io.github.alice.clock          # from a catalog
astral app remove io.github.alice.clock
```

The app appears in the launcher, runs with only the permissions it declared, can
be removed without touching the rest of the desktop, and never takes the shell
down when it crashes.

### Non-goals (this round)

- A hosted web storefront, payments, ratings, or remote analytics.
- Native plugins (`.so`) inside community packages. QML/JS only.
- Cross-process embedding of a community app's UI inside the dock, dashboard
  tabs, or settings pages (see §9.4 for why, and the future path).
- Running community apps without a sandbox.

---

## 2. Current state: why this is a refactor, not a plugin loader

| Symptom | Evidence today |
| :--- | :--- |
| One root wires every feature | `shell.qml` (536 lines) declares 18 `IpcHandler`s and instantiates every window. |
| One settings god-object | `config/Config.qml` is 1,741 lines; every feature setting lives in one singleton. |
| One visual monolith | `shell/UnifiedShell.qml` is 2,073 lines. |
| Hardcoded feature lists | `DashboardTabs.DEFAULT_TABS`; fixed settings page imports in `NexusHub.qml`. |
| One test bucket | 152 QML suites in a flat `tests/`; no per-app runner. |
| One install unit | `embedded_bundle.rs` extracts one tree; `install.json` names one owner for the whole product. |
| Entangled services | 35 services mix kernel ports, app infrastructure (MPRIS, downloads, DSH), and app state. |

A plugin loader on top of this would just move the coupling: apps would still
need `Config`, reach into `services/`, and be unable to load without the whole
tree. The kernel boundary is the prerequisite.

### Proven already (spikes, 2026-11-08)

- `qml6` resolves a fixed-depth relative directory import **and**
  `import Astral.Kernel 1.0` from `QML_IMPORT_PATH`.
- A `qmldir` entry may point into a subdirectory
  (`Pill 1.0 components/Pill.qml`), so one module can expose `theme/`,
  `components/`, `services/`.
- `quickshell -p <root>` loads `import Astral.Kernel 1.0` from
  `QML_IMPORT_PATH` (offscreen; live-Wayland proof is P0).

---

## 3. Platform principles

1. **One manifest, one package, one installer.** Official and community apps use
   the same `.astralapp` format and the same `astral app` lifecycle.
2. **Trust decides integration, not capability.** Official apps may run
   embedded; untrusted code never does. A community app is still first-class,
   just hosted.
3. **No silent capability.** Every side effect is a declared permission, shown
   at install, enforced at runtime.
4. **Stable surface.** Apps import `Astral.AppKit` only. `Astral.Kernel` is
   private. `kernelApi` has a level, a floor, and a deprecation window (§8.5).
5. **Local-first.** Any app installs from a file, offline. Catalogs are indexes,
   not a requirement.
6. **One command to running.** `app new` → `app dev` must work without reading a
   wiki.
7. **Removal is safe.** Removing or breaking an app never breaks the shell; a
   crashed hosted app is just a closed window.
8. **No native code in community packages.** No `.so`, no qmldir `plugin`
   entries. The verifier rejects them.
9. **Versions are owned, not decorative.** Every app owns its version,
   preinstalled ones included, and must satisfy the compatibility window of the
   shell that loads it (§8.5).

---

## 4. Vocabulary

Additions to `CONTEXT.md`:

- **App** — a versioned first- or third-party feature bundle with a manifest.
- **Official app** — built and signed by the Astral project; may run embedded.
- **Hosted app** — an app that runs in its own sandboxed process with
  `Astral.AppKit` and a broker connection.
- **Embedded app** — an official app loaded into the shell's QML tree.
- **AppKit** — the public, stable QML module for app authors.
- **Broker** — the daemon endpoint that mediates permissions for hosted apps.
- **Catalog** — a signed index of installable apps.
- **Package** — `.astralapp` archive: manifest, payload, signature.
- **Permission Grant** — user consent recorded per app and per permission set.
- **Kernel API** — the integer compatibility contract between apps and the
  running shell.
- **API Level** — `APP_API_LEVEL`: the highest `kernelApi` this build
  implements.
- **API Floor** — `APP_API_FLOOR`: the oldest `kernelApi` it still loads.
- **Preinstalled app** — an official app whose baseline payload ships in the
  core package. Independently versioned and updated like any other app; it does
  not share the platform version (§8.5.2).
- **Data Schema** — the integer layout version of an app's settings and data,
  recorded at install and refused when a build cannot read it.

Existing terms (`Install Method`, `Claim`, `ShellSurface`, `ActionResult`) keep
their meaning; a *ShellSurface* is what an embedded app may own, while a hosted
app owns ordinary compositor windows.

---

## 5. Decisions (locked by review)

| # | Decision | Choice |
| :--- | :--- | :--- |
| A1 | Unit of modularity | Apps with a manifest; kernel + official apps + community apps share one contract. |
| A2 | Shell composition | Kernel `AppHost` loads **embedded** apps from the registry; hosted apps are launched as their own process. |
| A3 | QML boundary | `Astral.Kernel` (private) and `Astral.AppKit` (public); apps never import kernel internals. |
| A4 | DDD per app | `domain/` (pure), `application/` (use cases), `infrastructure/` (adapters), `presentation/` (views), `interfaces/` (entry points). |
| A5 | Trust model | Official = signed and may run embedded; verified/community = hosted and sandboxed. |
| A6 | Community entry points | Standalone `surface` (toplevel / layer-shell) and `service` only. No tabs, settings pages, or shell IPC. |
| A7 | Sandbox | `bubblewrap` + `xdg-dbus-proxy`, no `$HOME`, no network by default, broker-only capability access. |
| A8 | Package format | `.astralapp` = tar.zst + `manifest.json` + detached minisign signature; no native plugins. |
| A9 | Install sources | Catalog id, local file, HTTPS URL, or `--git` dev link. |
| A10 | Distribution | Preinstalled official apps (baseline in the core package, updated from the catalog) + store official apps + community catalog. |
| A11 | App settings | App-owned namespace/file (`apps.<id>` for embedded, app config dir for hosted), schema in the manifest. |
| A12 | Compatibility | `kernelApi` level with an `APP_API_FLOOR`; install refuses anything outside the window with a typed reason and offers a platform update when the app is newer; a platform move is reconciled per A29, never crashed on. |
| A13 | Rust split | One crate now; context-first modules; optional crate split later. |
| A14 | Third-party apps | **Supported.** QML/JS only, sandboxed, permissioned, signed by the author and optionally reviewed by a catalog. |
| A15 | Catalog policy | Official catalog compiled in; community catalog is a signed index URL the user can add. |
| A16 | SDK | `astral app new/dev/test/lint/pack/install` + docs + example app; no repo checkout required. |
| A17 | CLI alias | Install `astral` as an alias of `astral-plasma` for the developer-facing commands. |
| A18 | Update consent | A new permission set or publisher key change requires re-consent; otherwise the update is refused. |
| A19 | Revocation | Catalog entries may be revoked; the host disables a revoked app and explains why. |
| A20 | Runtime isolation | Hosted apps use a per-app process; a crash closes the app, never the shell. |
| A21 | App version | **Every** app owns a `version`, preinstalled ones included; a fix ships as an app release without a platform release. |
| A22 | Preinstalled baseline | The core package carries a read-only baseline payload per preinstalled app. It seeds first boot and rollback; the installed copy stays authoritative. |
| A23 | Platform update | Reconciles per app: compatible → untouched; incompatible with a compatible newer version → auto-update; otherwise disable with a warning. Baseline copies seed first boot and are the core-app fallback. |
| A24 | Update acceptance | Forward only; same version with a different digest is refused; `--to` for an explicit target; auto-update on for official apps, opt-in for community. |
| A25 | Downgrade | Refused by default; `--allow-downgrade` requires a target whose `dataSchema` ≥ the recorded one, else `--reset-data` with its own consent. |
| A26 | Data compatibility | `dataSchema` integer in the manifest, recorded at install, re-checked at launch; a build that cannot read the recorded schema never runs. |
| A27 | Compatibility constants | One Rust constant pair generated into QML; drift fails CI; no semver range parser. |
| A28 | Core app failure | A core app that fails to load is reverted to its baseline, the failure is recorded, and the failed version is blocked instead of retried. |
| A29 | Compatibility failure | An app that no longer fits the window is auto-updated when a compatible version exists, otherwise disabled with a recorded reason and an actionable warning; never uninstalled, never half-loaded. |
| A30 | Forced-update consent | An auto-update may not add permissions; a candidate that does is not applied and the app disables instead. |

---

## 6. Target architecture

### 6.1 Tree

```
astral-plasma/
├── shell.qml                        # thin host: screens, AppHost, core IPC
├── modules/
│   └── Astral/
│       ├── AppKit/                  # PUBLIC SDK (module Astral.AppKit)
│       │   ├── qmldir
│       │   ├── Theme.qml            # facade over kernel theme
│       │   ├── Colors.qml
│       │   ├── AppWindow.qml        # glass toplevel
│       │   ├── LayerSurface.qml
│       │   ├── SettingsStore.qml    # app-owned settings file
│       │   └── Broker.qml           # capability client
│       ├── Kernel/                  # PRIVATE (module Astral.Kernel)
│       │   ├── qmldir               # generated, checked in
│       │   ├── theme/ components/ config/ services/
│       │   ├── host/                # AppRegistry, AppHost, SurfaceBroker, IntentBus
│       │   └── ports/               # ports, ActionResult, capability gate
│       └── Apps/                    # official embedded apps
│           ├── Dock/ Launcher/ Overview/ Dashboard/ Settings/
│           ├── Media/ Performance/ Workspaces/ Downloads/
│           └── Ai/ Assistant/
│               ├── manifest.json
│               ├── qmldir
│               ├── domain/ application/ infrastructure/ presentation/ interfaces/
│               ├── Standalone.qml
│               └── tests/
├── sdk/
│   ├── examples/hello/              # fixture used by platform tests
│   ├── templates/{surface,layer-surface,service}/
│   └── docs/                        # AppKit reference, authoring guide
├── daemon/src/
│   ├── kernel/                      # branding, ActionResult, events, clock
│   ├── contexts/
│   │   ├── desktop_session/ media/ downloads/ ai/ voice/
│   │   ├── apps/                    # catalog, registry, package, install, verify
│   │   └── broker/                  # permissions, grants, app-scoped API
│   └── interfaces/
├── catalog/
│   ├── catalog.json                 # official (compiled in)
│   └── apps/<Id>/manifest.json
└── tests/                           # kernel + contract suites
```

Module directories are PascalCase because QML URIs map to paths
(`Astral.Apps.Media` → `Astral/Apps/Media`). CLI ids are lowercase.

### 6.2 Import rules (enforced)

1. Kernel internals may use relative imports inside `Astral/Kernel/`.
2. Official embedded apps may import `Astral.Kernel` and `Astral.AppKit`.
3. Community apps may import **only** `Astral.AppKit`, `QtQuick`, and explicitly
   allowed Qt modules. The verifier/linter rejects anything else.
4. No app imports `Astral.Apps.<Other>`; cross-app work goes through `IntentBus`
   or the broker.
5. `domain/` has no `Quickshell`, `Config`, `Process`, `DBus`, or I/O imports.
6. No app writes another app's data directory or settings namespace.

`scripts/check_app_boundaries.py` enforces 1–6; `scripts/gen_qmldir.py`
generates module type lists and CI fails when they are stale.

### 6.3 DDD layers

| Layer | Contents | Must not |
| :--- | :--- | :--- |
| `domain/` | Policies, value objects, eligibility rules (e.g. `MediaElection.js`) | Import Quickshell, Config, I/O |
| `application/` | Use cases as QML singletons; depends on ports | Render, spawn processes |
| `infrastructure/` | Daemon/broker/DBus adapters | Leak protocol types upward |
| `presentation/` | Views, delegates, motion | Decide policy |
| `interfaces/` | Entry points, IPC, shortcuts, desktop entries | Be imported by domain |

Ports are named contracts plus contract tests (`tst_port_contracts.qml`). The
kernel's `ActionResult` (`applied`, `pending`, `unsupported`, `unavailable`,
`denied`, `invalid`, `stale`) is the return type everywhere.

### 6.4 Two runtimes, one contract

| | Embedded | Hosted |
| :--- | :--- | :--- |
| Who | Official apps | Verified/community apps |
| Process | Shell process | Own `quickshell` process |
| Entry points | Surface, tab, settings page, service, IPC | Surface (toplevel/layer-shell), service |
| Kernel access | `Astral.Kernel` + `Astral.AppKit` | `Astral.AppKit` only |
| Capabilities | In-process ports | Broker over Unix socket |
| Crash impact | Isolated by `AppHost` error handling | Just a closed window |
| Glass integration | Full | AppKit-styled windows |

This is why official apps keep the integrated experience and community apps can
still look like Astral without being trusted.

---

## 7. Trust, permissions, sandbox

### 7.1 Trust levels

| Trust | Signed by | Review | Entry points | Runtime |
| :--- | :--- | :--- | :--- | :--- |
| **official** | Astral release key | same repo | all | embedded (or hosted) |
| **verified** | author key | catalog maintainer | surface, service | hosted |
| **community** | author key (self-signed) | none | surface, service | hosted |
| **local-dev** | none | none | surface, service | hosted, `--dev` only |

Install UI always shows the trust level, publisher fingerprint, permissions, and
source. Community installs are one explicit extra confirmation, not a hidden
default.

### 7.2 Permission catalog

| Permission | Grants | Default |
| :--- | :--- | :--- |
| `session.read` | snapshot, windows, workspaces, outputs | ask |
| `session.control` | activate window, switch workspace, focus restore | ask |
| `media.read` / `media.control` | player list, metadata, play/pause/next | ask |
| `notifications.send` | post a notification | ask |
| `clipboard.read` / `clipboard.write` | clipboard access | off |
| `audio.read` | spectral/level data | off |
| `files.read:<path>` / `files.write:<path>` | one user-chosen directory per grant | off |
| `network` | network namespace enabled | off |
| `process.spawn` | run allowlisted helpers | off |
| `power` | lock, inhibit, suspend request | off |
| `secrets:<namespace>` | keyring entries under the app id | off |

Manifest permissions are a set; the install consent screen lists them in plain
language. The broker refuses undeclared calls with `denied`, and the UI shows
"this app tried to use X it did not declare" in the app's diagnostics.

### 7.3 Sandbox implementation

`astral app launch <id>` builds:

```bash
bwrap --unshare-all [--share-net] --die-with-parent --new-session \
  --ro-bind /usr /usr --ro-bind /lib /lib --ro-bind /lib64 /lib64 \
  --ro-bind /etc/ld.so.cache /etc/ld.so.cache \
  --ro-bind /etc/fonts /etc/fonts \
  --ro-bind /var/cache/fontconfig /var/cache/fontconfig \
  --ro-bind /etc/xdg /etc/xdg \
  --ro-bind /sys /sys \
  --ro-bind <package>/Astral/AppKit /sdk/Astral/AppKit \
  --ro-bind <palette-dir>/current-palette.json /run/astral/palette.json \
  --ro-bind <app>/payload /app \
  --bind   <app>/config /config \
  --bind   <app>/cache  /cache \
  --ro-bind $XDG_RUNTIME_DIR/$WAYLAND_DISPLAY /run/astral/wayland \
  --dev /dev --dev-bind /dev/dri /dev/dri \
  --proc /proc --tmpfs /dev/shm --tmpfs /tmp \
  --dir /run/astral \
  --bind   <broker-socket> /run/astral/broker.sock \
  --clearenv \
  --setenv HOME /run/astral/home --setenv XDG_RUNTIME_DIR /run/astral \
  --setenv WAYLAND_DISPLAY /run/astral/wayland \
  --setenv XDG_CONFIG_HOME /config --setenv XDG_CACHE_HOME /cache \
  --setenv QML_IMPORT_PATH /sdk --setenv LC_ALL C.UTF-8 \
  --setenv ASTRAL_APP_ID <id> --setenv ASTRAL_APP_TOKEN <one-shot> \
  quickshell -p /app
```

This is not a proposal: it is the command P0 ran on a live KWin/Wayland session
(Appendix C). Three mounts are load-bearing and were discovered by measuring,
not by reading man pages:

- **`/sys`** — without it, EGL fails (`ZINK: vkEnumeratePhysicalDevices failed`
  → `egl: failed to create dri2 screen`) and rendering falls back to software.
- **`/var/cache/fontconfig`** — without it the app's fresh `XDG_CACHE_HOME`
  makes fontconfig rebuild its cache: startup went from **121 ms to 569 ms**.
- **`/run/astral/wayland`** (absolute `WAYLAND_DISPLAY`) — the app never needs
  the host's `$XDG_RUNTIME_DIR` path exposed; `/run/user/<uid>` does not exist
  inside the sandbox.

The invariants:

- No `$HOME`, no session bus, no daemon binary path, no package kernel.
- The environment is scrubbed: `HOME`/`XDG_*` point at the app's own writable
  directories; the real home path never resolves.
- Only `Astral/AppKit` is readable, so `import Astral.Kernel` cannot resolve.
- The exported palette file is read-only, so AppKit theming matches the session
  without exposing settings or secrets.
- DBus is available only through `xdg-dbus-proxy` with a per-app name allowlist
  when the manifest asks for it.
- `--unshare-all` removes the network namespace by default; `--share-net` is
  added only with the `network` grant.
- The broker socket is created per launch under
  `$XDG_RUNTIME_DIR/astral/broker/<id>.sock`, mode `0600`, bound only into that
  app's sandbox. The token is one-shot and tied to the app id and launch.
- Install verifies once; launch re-verifies the manifest digest and the payload
  against the install record before exec.

### 7.4 Threat model — what this does and does not stop

**Stops**: reading the user's home, other apps' data, secrets; network access
without consent; talking to arbitrary session-bus services; loading native
plugins; replacing kernel files; surviving uninstall.

**Does not stop**: a malicious app drawing a deceptive window (it is its own
window), CPU/GPU exhaustion (resource limits are a later hardening step), or
abuse of a permission the user granted (the broker can rate-limit and audit,
but a granted capability is usable).

This is stated in the install UI so consent is honest.

### 7.5 Broker protocol

A Unix-socket JSON-RPC endpoint in `contexts/broker`:

```json
{ "jsonrpc": "2.0", "id": 1, "method": "media.playPause", "params": {} }
{ "jsonrpc": "2.0", "id": 1, "result": { "status": "applied" } }
```

- `hello` handshake: `{appId, token, api}`; the daemon validates the token it
  issued for the launch and loads the app's grants.
- One method namespace per permission; undeclared → `denied`, unavailable
  backend → `unavailable`, bad payload → `invalid`.
- Rate limits and an audit log (`~/.local/state/astral-plasma/apps/<id>/broker.log`)
  per app.
- Official embedded apps bypass the socket but use the same application-layer
  use cases, so behavior cannot diverge.

---

## 8. App contract

### 8.1 Manifest

```json
{
  "schema": 1,
  "id": "io.github.alice.clock",
  "name": "World Clock",
  "version": "1.4.2",
  "kernelApi": 1,
  "minQuickshell": "0.2.0",
  "dataSchema": 2,
  "publisher": { "name": "Alice", "key": "minisign:…" },
  "trust": "community",
  "runtime": "hosted",
  "entry": {
    "root": "shell.qml",
    "surface": { "type": "toplevel", "width": 420, "height": 320 }
  },
  "requires": { "capabilities": [], "qtModules": ["QtQuick.Controls"] },
  "permissions": ["session.read"],
  "settings": { "schema": "settings.schema.json", "defaults": "settings.defaults.json" }
}
```

Official apps add `"runtime": "embedded"` and may declare
`entry.dashboardTab`, `entry.settingsPage`, `entry.ipc`, `entry.shortcuts`.
Validation lives in one JSON Schema; Rust validates at install, QML at load, and
both share fixtures.

`version` is authored by **every** app, preinstalled ones included (§8.5.1);
the core package ships a baseline payload, not a version number shared across
apps. `minQuickshell` and `dataSchema` are optional; `kernelApi` is required.

### 8.2 Package format

```
io.github.alice.clock-0.1.0.astralapp   (tar.zst)
├── manifest.json
├── payload/
│   ├── shell.qml                       # ShellRoot; hosted apps only
│   ├── Main.qml
│   ├── qmldir
│   └── ...
└── manifest.json.minisig                (detached, signs manifest + payload digest)
```

A hosted payload root must contain `shell.qml`, because the launcher starts it
with `quickshell -p <payload>`. Embedded official apps have no `shell.qml`; their
`entry.surface` is a component the host instantiates.

Rules: HTTPS only for remote installs; size cap; SHA-256 verified before
extract; signature verified before activation; reject absolute paths, `..`,
symlinks escaping the payload, native plugins, and oversized payloads.

### 8.3 Settings and lifecycle

- `Astral.AppKit.SettingsStore` reads/writes the app's own settings file with
  schema defaults; embedded apps use `apps.<id>` in the main settings document.
- Optional hooks in `Main.qml`: `onAppInstalled`, `onAppEnabled`,
  `onAppDisabled`, `onAppUninstalled` (best-effort, never required for
  correctness).
- Uninstall keeps app data unless `--purge`; reinstall restores it.

### 8.4 Entry-point matrix

| Entry point | Official | Verified | Community |
| :--- | :--- | :--- | :--- |
| Toplevel surface | yes | yes | yes |
| Layer-shell surface | yes | yes | yes |
| Background service | yes | yes | yes |
| Dashboard tab | yes | no | no |
| Settings page | yes | no | no |
| Shell IPC target | yes | no | no |
| Desktop shortcut | yes | yes | yes |

Cross-process embedding is deliberately absent: an embedded tab is a QML item in
the shell's scene graph, and a hosted app is a separate Wayland client. Making
that seamless requires a compositor-embedding protocol; it is future work, not
a v1 promise.

### 8.5 Versioning and compatibility

Three numbers, three owners, one comparison function.

| Number | Owner | Answers | Lives in |
| :--- | :--- | :--- | :--- |
| `version` | the app | "which build is this?" | manifest, install record |
| `kernelApi` | the platform | "what does it need from me?" | manifest, `APP_API_LEVEL`/`APP_API_FLOOR` |
| `minQuickshell` | the Qt runtime | "is my QML engine new enough?" | manifest only |

The product version is not an app version. It stays where it is today:
`daemon/Cargo.toml` and the product `install.json`.

#### 8.5.1 Every app owns its version

Including preinstalled ones. A bug in `downloads` must be fixable without a
kernel release, so `downloads` has a version, a catalog entry, and a
`.astralapp` artifact like any other app. Being preinstalled says how it got
here, not what it is allowed to become.

- `version` is a required `MAJOR.MINOR.PATCH[-prerelease]` string, validated by
  the same `is_version` the release manifest already uses. It is the app's
  identity in the catalog, in the install record, and in every update decision.
- An app version and the platform version are unrelated numbers. `downloads
  0.4.1` on `astral-plasma 0.2.0` is normal; nothing is derived from anything.
- An app extracted from the current monolith gets `0.1.0` as its first
  independently versioned build. That is a declared baseline, not a
  reconstructed history — there is no changelog to invent.
- The version lives with the app (`modules/Astral/Apps/<App>/manifest.json`,
  `CHANGELOG.md`), so a fix is one app commit plus one catalog publish.

#### 8.5.2 Preinstalled baselines, not a shared version

Preinstalled apps still ship **inside** the core package, and that copy has a
job: make the desktop work on first boot, and give every required surface a
factory copy to fall back to.

| Copy | Path | Role |
| :--- | :--- | :--- |
| baseline | `package/apps/<Id>/` | the release's known-good payload; read-only, never edited |
| installed | `apps/<Id>/` | the live app, at whatever version the user runs |

Each copy carries its own manifest, so the baseline's `version` is read from
`package/apps/<Id>/manifest.json` and compared with the install record — no
out-of-band version table to keep in sync.

The installed copy is authoritative. A platform update reconciles versions; it
does not overwrite:

| On platform update | Result |
| :--- | :--- |
| app missing | install the baseline |
| installed newer than baseline | keep the installed version; an upgrade never downgrades |
| installed older than baseline | apply the baseline through the verified update path, then re-check compatibility |
| app is pinned | keep it, and say so in the Apps page |

That table answers *which version exists*. Whether an app still fits the new
kernel's API window is a second question, answered in §8.5.4.

Core apps (`dock`, `launcher`, `overview`, `dashboard`, `settings`) are the
special case: they cannot be removed, and a broken one leaves no UI to fix it
from. They update with automatic rollback — if a core app fails to load, the
host promotes that app's baseline into `apps/<Id>/`, records the failure, and
blocks the failed version so it is not retried in a loop. The next platform
update may install a different, newer version.

Cost: one extra payload per preinstalled app on disk (hardlinked from the
package where the filesystem allows it). That is worth it — it is the only
rollback that still exists when the settings app is the thing that broke.

#### 8.5.3 The compatibility rule

```
compatible(app, host)  ⟺
      host.apiFloor ≤ app.kernelApi ≤ host.apiLevel
    ∧ ( app.minQuickshell is absent ∨ runningQuickshell ≥ app.minQuickshell )
```

- `APP_API_LEVEL` (highest API this build implements), `APP_API_FLOOR`
  (oldest API it still loads), and `API_LEVEL_HISTORY` (level → first platform
  release that introduced it, used to phrase warnings as platform versions) live
  in `daemon/src/kernel/app_api.rs`, generated into
  `modules/Astral/Kernel/Host/AppApi.js` by `scripts/gen_app_api.py`. A test
  reads both and asserts equality; CI fails when they drift.
- A manifest's `kernelApi` is the level the app was **built against**, i.e. its
  minimum. Authors never declare a maximum: only the host knows what it still
  supports.
- **Removals bump `apiLevel`; retirements bump `apiFloor`.** An addition changes
  neither, so a new release cannot break an app that already worked (§3.4).
- **No semver ranges.** `">=0.4 <1.0"` lets an author claim combinations they
  never ran, and a range parser would be a second, subtly different comparison
  implementation beside `domain/update.rs`. Floor/level expresses exactly one
  thing — which removals an app still needs — and reuses `version_gt` and
  `compare_versions`.

Failures are typed `ActionResult`s that carry the numbers:

| Situation | Result | What the user sees |
| :--- | :--- | :--- |
| `kernelApi > apiLevel`, install | `unsupported` | "Needs Astral API 2; this shell is API 1" + **Update Astral** (existing updater) |
| `kernelApi < apiFloor`, install | `unsupported` | "Built for API 0, retired" — the author must rebuild |
| `minQuickshell` unmet | `unavailable` | both versions, "update Quickshell" |
| installed app out of window after a platform update | `unsupported` at load | optional app: excluded + notice; core app: baseline restored, failed version blocked |
| hosted launch re-check | `stale` | window closes with the reason, shell unaffected |

The install-time ceiling is the common real case — an app built after the
user's platform — so it must offer the platform update, not a dead end. The
load-time case must never resolve a module it cannot satisfy: exclude it, or for
a core app restore the baseline. Never crash.

#### 8.5.4 When the platform moves

A platform update changes `apiFloor`/`apiLevel`, so an app that was fine can
stop fitting. The reconcile runs once per app at platform update **and** at
every boot — a kernel rollback (`package.prev`, UPDATES.md D6) makes apps newer
than the kernel, which is the same problem pointing the other way — and it
prefers keeping the app working over switching it off:

| State after the platform moved | Action |
| :--- | :--- |
| compatible | nothing |
| incompatible, a compatible newer version exists, permissions unchanged | **auto-update** to it; notice "updated to stay compatible" |
| incompatible, a compatible newer version exists but adds permissions | keep installed, **disable**: an update exists and needs review |
| incompatible, no compatible newer version | **disable** with the recorded reason |
| incompatible and pinned | the pin wins: **disable**, with "unpin and update" offered |
| incompatible, and only an older version is compatible | **disable** — downgrade stays opt-in (A25) |
| incompatible, a compatible newer version exists, but the app does not auto-update (community opt-out) | **disable** with a one-click **Update and enable** |
| core app (`dock`, `launcher`, `overview`, `dashboard`, `settings`) | the platform's baseline is compatible by construction → activate it; only a baseline that also fails the window disables it |

"Compatible newer version" means the newest version offered by the catalog — or
the baseline payload in `package/` — that satisfies the window, is strictly
newer than the installed one, and grants no permission the user has not already
approved. Permissions are not laundered through a forced update.

After a **kernel rollback** nothing newer is compatible, so the *only an older
version is compatible* row is the normal outcome: apps switch off with a warning
until the kernel moves forward again. That is why the warning has to be worth
reading.

Switching an app off is never silent and never destructive:

- the payload, data, settings, and grants all stay; only `enabled` flips;
- the verdict is recorded on the install record
  (`compat: { status, reason, requiredPlatform, runningPlatform, checkedAt }`),
  so `astral app list`, the Apps page, and the logs agree;
- one row per affected app in Settings → Apps: what it is, why it stopped,
  **Check for a compatible update**, **Unpin and update** where relevant, and
  **Remove**;
- the app is never half-loaded: an app outside the window is not imported at all.

The reason names a *platform version*, because that is what a person can act on:
*"Needs Astral 0.3.0 or newer (API 2); this is 0.2.0 (API 1)."*
`API_LEVEL_HISTORY` in `daemon/src/kernel/app_api.rs` maps each level to the
first platform release that introduced it, so that sentence is derived from the
same constants that enforce the rule (§8.5.3). No second source of truth, and no
author-supplied `minAstral` field that could drift.

#### 8.5.5 Update, pin, downgrade, rollback

| Operation | Rule |
| :--- | :--- |
| install | record `version`, `preinstalled`, `dataSchema`, digest, publisher key, `installedAt` |
| update (any official app) | accepted only if `version_gt(new, installed)`; preinstalled apps take the same path with a catalog artifact, no platform release |
| same version, new digest | `invalid`: an artifact's digest is its identity, so a republish needs a version bump |
| explicit target | `astral app update <id> --to <version>`, same checks |
| downgrade | refused by default; `--allow-downgrade` requires the target's `dataSchema` ≥ the recorded one, else `--reset-data` needs its own consent |
| pin | `astral app pin <id> [--to <version>]` freezes automatic updates for that app |
| auto-update | on for official apps, preinstalled and store alike (catalog-signed, trusted); off for community apps until the user opts in |
| rollback | `.prev/` restores the payload **and** the recorded version atomically; grants re-checked; the same `dataSchema` guard applies |
| core app failure | payload moved to `.prev/`, baseline activated, failed version recorded as blocked, notice in Apps page |
| reinstall after uninstall | the app's data dir keeps `dataSchema`, so reinstalling an older build is refused |

`dataSchema` is what makes a downgrade safe instead of lucky: it names the
layout of the settings and data that build writes. It is recorded on install and
re-checked at every launch, so a build that cannot read what is on disk is
refused *before* it writes anything — the failure that would otherwise corrupt
user data silently.

#### 8.5.6 Where it lives

`daemon/src/contexts/apps/version.rs` holds the policy as pure functions over
`Manifest`, `InstallRecord`, and `HostApi`, tested without a session. Rust owns
the only semver implementation in the repo; QML reads the resulting state from
the daemon and never re-implements a comparison.

---

## 9. Runtime

### 9.1 Embedded boot

1. `astral-plasma run` extracts the core package, reconciles each preinstalled
   baseline into `apps/<id>/` when that app is missing, and launches Quickshell
   with `QML_IMPORT_PATH = <package>:<apps-root>`, so every installed app
   resolves its module from its own directory (§8.5.2).
2. `AppRegistry` reads `apps.json`, validates manifests, resolves capabilities,
   and topologically sorts by `requires.apps`.
3. `AppHost` instantiates enabled apps behind `LazyLoader`s:
   screen-scoped surfaces, toplevel windows once, tab/page providers as
   metadata, service apps only when `keepLoaded`.
4. A failing app is recorded with its reason and excluded; a failing **core**
   app has its baseline promoted into `apps/<id>/` and that version blocked.
   Neither case can take down the shell.

### 9.2 Hosted launch

`astral app launch <id>` (also the generated desktop entry's `Exec`):

1. verify the install record and payload digest;
2. create the per-launch token and broker socket;
3. build the `bwrap` command from the granted permissions;
4. exec `quickshell -p <app>/payload` with only `Astral.AppKit` on the import
   path;
5. revoke the token and close the socket when the process exits.

The app appears in the dock/launcher through a namespaced desktop entry
(`org.astralplasma.app.<id>.desktop`) installed with the app, so no new
launcher integration is needed.

### 9.3 Intent bus and missing apps

```qml
IntentBus.request("downloads.open", {})
// { status: "unavailable", reason: "app-not-installed", app: "downloads" }
```

The UI renders an install card (Apps page deep link). Installed-but-disabled
returns `denied` with the reason. Tests assert the typed result, not a dead
button.

### 9.4 Surfaces, tabs, pages, IPC

- `entry.surface` declares type, screen, layer, anchor, focus policy, size.
  `shell.qml` keeps only the screen scope.
- Dashboard tabs and settings pages are projections of installed **official**
  apps' manifests, replacing `DEFAULT_TABS` and the fixed page imports.
- Existing `IpcHandler`s move into their app's `interfaces/ipc/`; `shell.qml`
  keeps only `shell` (quit) and host-level commands.
- Uninstalled app ⇒ no IPC target; CLI returns typed `unavailable`.

### 9.5 Settings ownership

Kernel `Config` keeps session/theme/dock/host keys only. Embedded apps own
`apps.<id>`; hosted apps own their config dir. The Apps page edits permissions
and per-app settings through the daemon, the only writer of grants.

---

## 10. SDK and developer experience

### 10.1 Commands

| Command | Result |
| :--- | :--- |
| `astral app new <id> [--template surface\|layer-surface\|service]` | manifest, `shell.qml` + `Main.qml`, `qmldir`, tests, README, `.astral/` dev config |
| `astral app dev .` | sandboxed live host with hot reload; uses the installed Astral package as SDK |
| `astral app test .` | `qml6` offscreen suites + manifest/boundary/permission lint |
| `astral app lint .` | manifest schema and version fields, AppKit-only imports, hardcoded colors, QML warnings |
| `astral app pack .` | `.astralapp` + SHA-256 + optional minisign signature; artifact named with the version |
| `astral app install <file\|url\|id>` | verify, compatibility, consent, stage, activate |
| `astral app update [<id>] [--to <version>]` | forward-only by default; `--allow-downgrade` behind the `dataSchema` guard |
| `astral app pin <id> [--to <version>]` / `astral app unpin <id>` | freeze or resume automatic updates for one app |
| `astral app rollback <id>` | reactivate `.prev/` payload and its recorded version |
| `astral app list` | installed apps with version, `kernelApi`, preinstalled flag, pin, blocked versions |
| `astral app publish .` | prints catalog entry JSON + submission steps (no auto-publish) |

`astral` is installed as an alias of `astral-plasma` (A17). `app dev` works from
any directory because the SDK is the installed package, not a repo checkout.

### 10.2 Templates

- `surface` — a toplevel `Astral.AppKit.AppWindow` with theme tokens.
- `layer-surface` — a panel/capsule with anchor and exclusive-zone options.
- `service` — a background app with a settings schema and broker usage.

Each template ships a passing test suite and a README that explains permissions.

### 10.3 Public API discipline

- `Astral.AppKit` is the only supported import; its types are documented in
  `sdk/docs/appkit.md` and covered by contract tests.
- `Astral.Kernel` is private; official apps may use it, community packages
  cannot see it inside the sandbox.
- `kernelApi` starts at `1`. Breaking AppKit changes bump it; the host supports
  the current and previous integer for one release cycle, then removes the old
  one with a changelog entry. Additive changes do not bump it.
- `astral app lint` warns on deprecated types with the replacement and the
  removal release.

### 10.4 Design consistency

Apps use AppKit theme tokens; `lint` rejects raw hex colors and raw motion
durations in `presentation/` (the same rule the shell follows). AppKit.Theme
reads the palette file `ThemeExportService` already publishes
(`current-palette.json`, `agent-theme.env`), so a hosted app matches the current
wallpaper palette without importing kernel internals. The result: community apps
look like Astral without copying the design system.

---

## 11. Distribution

### 11.0 Distribution classes

| Class | Apps | Delivery | Version | Runtime |
| :--- | :--- | :--- | :--- | :--- |
| **Preinstalled official** | `dock`, `launcher`, `overview`, `dashboard`, `settings`, `media`, `performance`, `workspaces`, `downloads`, `ai`, `assistant` | baseline in the core package, then the official catalog | own semver | embedded |
| **Store official** | `dsh-web`, `voice`, `skills`, future heavy features | official catalog only | own semver | embedded or hosted, per manifest; trusted, so embedded is allowed |
| **Community** | anything with a reverse-DNS id | author-signed `.astralapp` from a community catalog, file, or URL | own semver | hosted only |

Distribution class decides whether an app arrives preinstalled, whether it can
be removed, and which trust level it runs at. It does **not** decide how it is
versioned: a preinstalled app is updated exactly like a store app, from the
official catalog, because shipping a `downloads` fix must not require a
platform release (§8.5.1).

Core apps (`dock`, `launcher`, `overview`, `dashboard`, `settings`) cannot be
removed: without them there is no desktop, or no way to install an app again.
First boot installs every preinstalled baseline; "optional" only applies to a
fresh install.

### 11.1 Layout

```
~/.local/share/astral-plasma/
├── bin/astral-plasma
├── package/                      # core bundle: kernel + one baseline payload per
│                                 # preinstalled app (read-only factory copies)
├── install.json                  # product owner (kernel release)
├── apps.json                     # app registry (daemon-owned)
├── apps/<id>/
│   ├── manifest.json
│   ├── payload/
│   ├── install.json              # app record: version, preinstalled, dataSchema,
│   │                             # digest, trust, publisher key, grants, pin,
│   │                             # blocked versions
│   ├── config/ cache/            # bound into the sandbox
│   └── .prev/                    # one previous payload + its version, for rollback
└── catalogs/<name>.json          # cached catalog indexes
```

`apps.json` lists installed apps with their enabled state and version; the
per-app `install.json` mirrors `InstallRecord` (version, preinstalled flag,
data schema, digest, trust, publisher key, grants, pin, blocked versions,
installed_at). One writer: the daemon.

Two copies of a preinstalled app exist on disk on purpose: the baseline in
`package/` is the factory rollback that still works when the broken app is the
settings page, and `apps/<id>/` is what actually runs (§8.5.2). Preinstalled
baselines are hardlinked from `package/` where the filesystem supports it.

### 11.2 Catalogs

- **Official catalog** compiled into the binary, signed by the release key;
  works offline.
- **Community catalog** is a signed index URL the user adds
  (`astral app catalog add <url>`); the public key is pinned on first add and
  shown on updates.
- Catalog entry: id, version, kernelApi, minQuickshell, dataSchema, trust,
  preinstalled, permissions, size, digest, artifact URL, publisher key,
  `revoked` flag.
- The official catalog carries preinstalled apps too, so a `downloads` or
  `settings` fix reaches users as a catalog publish, not a platform release.
- A catalog entry whose `kernelApi` is above the running `APP_API_LEVEL` is not
  offered as an update at all — no "update available" that then refuses to
  install (§8.5.3).
- A revoked app is disabled at next launch with the reason; no silent deletion.

### 11.3 Install / update / remove

| Operation | Rules |
| :--- | :--- |
| install (preinstalled) | extract baseline into `apps/<id>/`, record version, enable; no download |
| install (store official / community) | fetch, verify digest, verify signature, check the compatibility window, consent permissions, stage, atomic rename, record last |
| update | forward-only version check plus the same checks; **new permissions or a changed publisher key require fresh consent**, otherwise refused; applies to preinstalled apps too, so an app fix ships without a platform release |
| remove | refuse if an installed app depends on it; `--cascade`; keep data unless `--purge`; remove desktop entry, shortcuts, grants, and broker token |
| disable | registry only; files stay; fast and safe |
| platform update | swaps the kernel in `package/`; every installed app is then reconciled by §8.5.4 — auto-update when a compatible version exists, otherwise disable with a warning; core apps fall back to their baseline; blocked core versions are not retried |
| rollback | restores `.prev/` payload **and** its recorded version; grants re-checked; `dataSchema` guard applies |

Crash safety: staging in `apps/.staging/<id>`, activation by rename, registry
written last, orphan staging cleaned by the next reconcile.

### 11.4 Consent UI

Settings → Apps shows installed and available apps with trust badge, publisher
fingerprint, version, size, permissions, dependencies, and enable/remove.
Preinstalled apps are listed in the same list with a "preinstalled" marker and
their own version — not merged into the platform version — so a `downloads`
fix is visible on its own row. Installing a community app shows a one-screen
explanation of what the sandbox does and does not protect (§7.4). Permission or
`dataSchema` changes on update are shown as a diff, and an app that is
incompatible with the running platform shows the derived platform floor, the
reason, and the actions from §8.5.4 — never a dead install button (§8.5.3). A
reconcile that had to switch an app off surfaces as one warning row per app, not
a modal.

---

## 12. Daemon contexts

```
daemon/src/
├── kernel/                 branding, ActionResult, DomainEvent, ports primitives, clock
├── contexts/
│   ├── desktop_session/    snapshot, windows, workspaces, focus, profiles
│   ├── media/ downloads/ ai/ assistant/ voice/
│   ├── apps/               catalog, package, registry, install, uninstall, verify,
│   │                       version (compatibility, upgrade/downgrade policy,
│   │                       baseline reconcile)
│   │                       ports: CatalogPort, PackageStorePort, RegistryPort,
│   │                              ArtifactVerifierPort, AppLifecyclePort,
│   │                              HostApiPort
│   └── broker/             permission model, grants, app-scoped JSON-RPC
│                           ports: GrantStorePort, BrokerTransportPort, AuditPort
└── interfaces/             cli.rs, api_server.rs
```

- Contexts may import `kernel` only; no cross-context domain imports.
- `apps` and `broker` are separate bounded contexts: packaging is not
  permission enforcement.
- The existing Unix API server grows app-scoped methods rather than a second
  server, so transport and authentication have one implementation.
- `contexts/apps/version.rs` owns version and compatibility policy as pure
  functions over `Manifest`, `InstallRecord`, and `HostApi`; it calls
  `domain::update::{is_version, version_gt, compare_versions}`. The repo keeps
  one semver implementation, not two.
- `cargo test --test test_app_*` / `test_broker_*` already gives per-context
  testability; a crate split is P7 if build time justifies it.

---

## 13. Testing

| Level | Proves | Where |
| :--- | :--- | :--- |
| App unit | Policy/use cases without a session | `apps/.../tests/`, `sdk/examples/hello/tests/` |
| Port contract | Every adapter implements its port | `tests/tst_port_contracts.qml` |
| Manifest | Schema valid, entry files exist, permissions known, `version` semver, `dataSchema` present | `tests/tst_app_manifests.qml` + Rust |
| Boundary | No cross-app imports; domain purity; community imports AppKit only | `scripts/check_app_boundaries.py` |
| Host wiring | Ordering, disabled app, broken app isolation, IPC collision | `tests/tst_app_host.qml` |
| Install | digest/signature/tamper, id collision, downgrade, permission diff, uninstall cascade/purge, crash-safe registry | `daemon/tests/test_app_*.rs` |
| Version | every app has a valid version; forward-only update; same-version republish refused; `dataSchema` downgrade guard; `--to`; pin | `daemon/tests/test_app_version_*.rs` |
| Compatibility | `kernelApi` above level / below floor refused with a typed reason; `minQuickshell` floor; out-of-window app excluded at boot, core app reverted to baseline; QML↔Rust constant equality | `daemon/tests/test_app_compat_*.rs` + `tests/tst_app_host.qml` |
| Baseline reconcile | missing app installed, newer kept, older baselined, pinned untouched, failed core version blocked, no rollback loop | `daemon/tests/test_app_baseline_*.rs` |
| Platform move | compatible untouched; incompatible + compatible update auto-updates; a candidate that adds permissions does not; no candidate disables with the recorded reason; pin wins; only-an-older-version-compatible disables; core app takes the baseline; kernel rollback disables but never uninstalls | `daemon/tests/test_app_reconcile_*.rs` + `tests/tst_app_compat_notice.qml` |
| Broker | handshake, token reuse, undeclared permission denial, rate limit, audit | `daemon/tests/test_broker_*.rs` |
| Sandbox | command construction, no-home/no-net assertions, native-plugin rejection | `daemon/tests/test_sandbox_*.rs` + CI |
| SDK | `new → dev → test → pack → install → launch → remove` on the fixture app | `tests/platform_e2e.sh` |
| Regression | Existing suites | `make test` |

Commands:

```bash
make test                      # rust + kernel/contract QML + every app suite + boundary
make test-app APP=media        # one app
make test-apps                 # all official app suites
make app-run APP=media         # embedded minimal host
make platform-e2e              # fixture app through the full lifecycle
```

Every phase also needs AGENTS §7 proof: screenshots of affected surfaces with
real content, plus a full-shell capture after install/remove.

---

## 14. Phases

Each phase is a separate change set; `make test` green at every gate.

### P0 — Spikes and baseline (S)

- Live-Wayland proof that Quickshell loads an external `Astral.AppKit` app.
- `bwrap` + `quickshell -p` spike: Wayland socket, DRI, fonts, broker socket,
  no-home, no-net. Measure startup.
- Cold-start cost: 0 vs N embedded apps.
- Record suite count and `make test` duration.

**Result (2026-11-08, live KWin/Wayland)**: the hosted hello app renders as a
real layer-shell window with `Astral.AppKit` only; an embedded surface renders
through a `Loader` the same way. Inside the sandbox `$HOME` does not resolve,
`/run/user/<uid>` does not exist, DNS fails, `import Astral.Kernel` fails, and a
`Quickshell.Io.Socket` reaches a bind-mounted broker socket whose JSON line
arrives intact. Startup medians (5 runs): bare 136 ms, sandboxed 569 ms,
sandboxed with `/var/cache/fontconfig` bound **121 ms** — the sandbox costs
nothing once the shared font cache is visible. 11 metadata-only loaders cost
+1 ms; 11 active stub modules +29 ms. Full log: Appendix C.

**Gate**: spike notes; a hello app runs embedded and hosted on the live session;
baseline recorded.

### P1 — Kernel extraction, no behavior change (L)

- Move `theme/`, `components/`, kernel `config/`, kernel `services/` under
  `modules/Astral/Kernel/`; rewrite every path reference; **`qmldir` deferred to
  P2** (see the finding below). Done: 217 files rewritten, 474 path references,
  0 behaviour change.
- **Mechanism proven before the move** (scratch module, 80 kernel files, 74
  relative imports collapsed into one `import Astral.Kernel 1.0`, `qmldir`
  generated): `Theme`/`Colors` singletons and `CornerFillet` resolve through the
  full `theme → components → services → motion → Config` chain with no errors.
  The generator is `scripts/gen_qmldir.py` (`--check` for CI; refuses duplicate
  flattened type names).
- **One real seam, found by that run**: `config/Config.qml` imports
  `dashboard/tabs/DashboardTabs.js`, i.e. the kernel reaching into an app. P1
  keeps it as a relative path into `dashboard/` (behaviour-identical); P4
  replaces `DEFAULT_TABS` with the registry projection (§9.4).
- **Module URI is a P2 change, not a P1 move**, proven the hard way: importing a
  `qmldir` module **eagerly compiles its singleton entries**, and the kernel's
  singletons (`Theme`, `Colors`, `Config`, 26 services) import `Quickshell`.
  Plain `qml6` — the test runner — has no Quickshell plugin, so `import
  Astral.Kernel 1.0` fails every suite. P1 therefore rewrites paths only
  (semantics preserved); the module URI lands in P2 where the shell
  (`quickshell`, which has the plugin built in) owns `QML_IMPORT_PATH`, and the
  kernel's Quickshell-dependent singletons can be split behind ports first.

**P1 result**: `make test` green — 153 QML suites, 988 Rust tests. Live proof on
the running session: zero load errors, dock + dashboard (7 tabs, weather,
calendar, power) + settings (real wallpaper thumbnail, wallpaper-derived accent
palette) all render. Not verified: a before/after pixel diff; the claim is
"loads and renders its real content", not "pixel-identical".
- Add `Astral.AppKit` facades for the public surface.
- Move branding/ports/events to `daemon/src/kernel/` with shims.
- Boundary linter in audit-only mode.

**Gate**: `make test` 100%; visually identical dock/dashboard/settings; no
behavior change.

### P2 — Contract, host, registry (M) — **partially done**

Landed:

- `daemon/src/domain/app_manifest.rs` — manifest schema + validation, with every
  refusal naming the field (`entry.root` escape, unknown permission, a community
  app claiming `embedded`, a hosted app whose root is not `shell.qml`, …).
- `daemon/src/domain/app_compat.rs` — the API window (`APP_API_LEVEL`,
  `APP_API_FLOOR`, `API_LEVEL_HISTORY` so warnings can say "needs Astral 0.2.0"),
  reusing `domain::update::{is_version, version_gt}` rather than a second semver.
- `daemon/src/domain/app_reconcile.rs` — install/update admission (forward only,
  republished digest refused, downgrade behind the `dataSchema` guard) and the
  platform-move table from §8.5.4 as pure functions.
- `daemon/src/application/app_service.rs` — `apps.json` registry (schema,
  duplicate-id refusal, missing file = empty registry) and the bridge into policy.
- `application/app_service.rs` writer — `apps.json` is written to
  `apps.json.tmp`, `sync_all`ed, renamed, and the directory synced: a crash
  leaves the previous registry intact, a registry a reader would refuse is never
  persisted, and a *corrupt* existing file is never silently clobbered. Plus
  `upsert`, `set_enabled`, `remove`, and `block_version` (capped at 32, so a
  broken catalog cannot grow it without bound).
- `modules/Astral/Kernel/Host/AppHostPolicy.js` — the host's decisions as pure
  functions: who loads, why the rest do not (`disabled`, `blocked`,
  `incompatible`, `unresolvedDependency`, `invalid`), dependency-ordered and
  deterministic. No app is named anywhere.
- `astral app list [--json]`, `enable`, `disable` — real, reading and writing the
  same registry the host will; every other `astral app` subcommand names the
  phase it lands in instead of silently doing nothing.
- `sdk/examples/hello/` + `daemon/tests/test_app_contract.rs`: the example an
  author copies is validated by the same code that validates an install, so the
  authoring side cannot drift from the enforcement side.

Also landed: the host itself.

- `modules/Astral/Kernel/Host/` is the `Astral.Kernel.Host` module:
  `AppManifest.js` (load-time manifest validation), `AppHostPolicy.js` (pure
  plan), `AppHost.qml` (Loaders + on-demand `activate(id)` + failure reporting),
  `AppRegistry.qml` (reads `apps.json` and each manifest, merges registry state).
- The host instantiates **nothing at boot**: `activate(id)` is a call, so startup
  does not grow with the installed app count (P0: 11 inactive apps +1 ms, 11
  instantiated +65 ms).
- A corrupt manifest, a missing payload, and QML that does not compile all become
  one skipped row with a reason; none of them can throw into the shell.
- Hosted apps are skipped by `AppHost` with state `hosted` — they are a separate
  process, not an item in this scene graph.
- The manifest contract is checked from both sides against shared fixtures
  (`tests/fixtures/apps/` + `index.json` + `expect.json`): Rust in
  `test_app_manifest_fixtures.rs`, QML in `tst_app_manifest_validation.qml`.

Now landed: the pipeline a migrated surface needs.

| Piece | What it does |
| :--- | :--- |
| `Host/IntentBus.qml` | named intents → typed `ActionResult`; unsupported/denied/invalid are answers, and a throwing handler is contained |
| `Host/ShellState.qml` | a read model with **no kernel imports**; the shell binds its values, so an app sees the live instance |
| `AppHost.state` / `.intents` / `.eager` | injection point: `property var shellState`, `property var intents`; `eager` activates boot surfaces |
| `scripts/check_app_boundaries.py` | CI gate: apps may not import `Kernel/config`, another app, or the kernel module; non-official apps are limited to `Astral.AppKit`. `make test` runs it |
| `Host/qmldir` | `Astral.Kernel.Host` as a module; `run.sh` exports `QML_IMPORT_PATH` |

**The overview is now an app** (`modules/Astral/Apps/Overview/`, loaded from
`apps/index.json` through `AppHost` with `eager`). `shell.qml` no longer names it:
the root keeps `ShellState`/`SessionPort`/`IntentBus` and the host.

| Surface reads | Was | Now |
| :--- | :--- | :--- |
| open/closed | `Config.overviewVisible` | `shellState.overviewVisible` (injected) |
| windows | `WindowService.windows` | `session.windows` (injected port) |
| thumbnails | `WindowService.overviewThumbnails` | `session.overviewThumbnails` |
| activate / close / launch | `WindowService.*` | `session.*` |
| close, launcher, exit | `Config.*` | `intents.request(...)` |

Verified live: the surface opens on `overview toggle`, and with a window in the
port it renders a card (`Probe Window` in the grid). Its grid is empty on this dev
box because the shell's own `WindowService` is empty without a claimed session —
the same data the pre-migration surface read, so no behaviour is lost. Four suites
that pinned the old hops were moved to the new ones rather than re-pinned to a path.

Still open in P2 — with the remaining blocker named precisely:

- **The port layer, before any migration.** Two attempts to move the overview
  through the host proved that *every* kernel singleton is per-instance for a
  Loader-loaded component: `Config` first (C.9), then `WindowService` — the
  migrated surface opened with an empty preview grid because its `WindowService`
  had no windows (C.10). So an embedded app cannot read window state through an
  import either; it needs a **session port** (windows, thumbnails, activation)
  injected the way `ShellState` is. That is P4 work, not wiring.
- `SurfaceBroker` for cross-app intents, and then `overview` and the rest.
- The `Astral.Kernel 1.0` module URI (needs the Quickshell-dependent singletons
  split behind ports first — Appendix C.6).

Original scope:

- Manifest schema (including `version`, `kernelApi`, `dataSchema`), catalog
  skeleton, `AppRegistry`, `AppHost`, `SurfaceBroker`, `IntentBus`,
  `CapabilityGate`.
- `APP_API_LEVEL`/`APP_API_FLOOR` in Rust with the generated QML mirror; the
  loader refuses an app outside the window with a typed reason.
- `apps.json` reader; read-only `astral app list/available`.
- App settings namespaces; `Config` gains no app keys.
- Move `overview` as the reference embedded app.

**Gate**: reference app enabled/disabled/corrupt-manifest all boot safely; an
app declaring `kernelApi: 99` is refused with a reason that names both levels;
registry/host tests green.

### P3 — SDK v0 + first reference app: downloads (L) — **AppKit landed**

`Astral.AppKit` exists and a real app loads through it:

| Type | What it is |
| :--- | :--- |
| `AppApi` | level/floor + level→release history; constants pinned to the daemon by test |
| `AppPalette` | reads the host's exported palette (`current-palette.json`) with `FileView`; internal |
| `Colors`, `Theme` | the public roles, radii, and typeface, resolved from that palette with Material 3 fallbacks |
| `Motion` | the design constants, pinned to `theme/Theme.qml` by test |
| `AppWindow` | the glass toplevel: self-contained, no kernel import |

The sandbox rule decided the architecture: a hosted app mounts `Astral/AppKit` and
nothing else, so AppKit cannot import the kernel — it *reads the palette the kernel
already exports*, and `ThemeExportService` now also publishes `radius_*` and
`font_family` so an archetype change reaches apps without a rebuild.

Verified: `daemon/tests/test_appkit.rs` (7 tests — constants drift, motion drift,
palette keys, qmldir completeness, no kernel import, and a live `quickshell` load
that asserts the app painted with *the palette file's* radius and typeface), plus
`sdk/examples/hello` rendering on the running session.

The SDK verbs are real (P3, partial):

| Command | What it does |
| :--- | :--- |
| `astral app new <id> [--template surface\|layer-surface\|service] [--dir .]` | writes `manifest.json`, `shell.qml`, `README.md`, `tests/`; refuses a non-empty target |
| `astral app lint <dir>` | manifest + entry file + import boundary + `Config.` scan; names file and line |
| `astral app pack <dir>` | `.astralapp` (POSIX ustar, uncompressed) + SHA-256 + file count; refuses what would not install |
| `astral app test <dir>` | lint, then the `tests/tst_*.qml` suites under `qml6` |

`.astralapp` is a hand-written ustar writer/reader with no archive dependency, so
packing works offline; zstd compression and minisign signing stay P5 (a codec
dependency, and a private key the daemon must not own). `Bundle::validate` refuses
absolute/escaping paths, symlinks, native libraries, a missing manifest, and a
manifest whose `entry.root` is not in the archive — the last one is what makes a
truncated bundle fail at install rather than at launch.

Every template is **load-verified**: `daemon/tests/test_app_sdk_templates.rs`
creates each one, lints it, packs it, and starts it under a real `quickshell`.

`astral app dev <dir>` runs the app for its author: `--print-command` shows what
would run (used by tests), the plain mode runs it on the session, and `--sandbox`
builds the P0 `bwrap` mount set (`/sys`, the shared font cache, a private runtime
dir) — with a clear refusal when bubblewrap is missing. Lint runs first, so an app
that would not install never starts.

**Install and remove landed with it** (P5's front half):

| Verb | Rules |
| :--- | :--- |
| `astral app install <file>` | verify → stage → activate by rename → **record last**; refuses an incompatible API level, a republished artifact, and a downgrade the data layout cannot survive |
| update | a permission **widening** update is refused unless `--accept-permissions`, and the new grants are recorded |
| `astral app remove <id> [--purge]` | deletes the payload and the record; keeps app data unless `--purge` |

Update keeps one previous payload in `.prev/` for rollback. Ten unit tests cover the
lifecycle, and the CLI was driven end to end: `pack → install → list → install again
(up to date) → remove`.

**Catalog (P5, local half)**: `domain/app_catalog.rs` validates a signed index
(schema, ids, versions, sha256 digests, duplicate ids, `revoked`); a catalog that
declares a `publisherKey` must carry a `.minisig` beside it, verified through the
same `minisign` path the release manifest uses, and a local catalog without a key
loads as *unsigned* rather than pretending otherwise.

`astral app install <id> --catalog <path>` resolves the entry, refuses a revoked id,
fetches the artifact beside the catalog, **verifies its SHA-256 against the entry**
(the digest is the contract; the signature only authenticates the index), then runs
the ordinary install pipeline — so compatibility, permissions, downgrade and staging
rules are identical to a file install. `astral app available --catalog <path>` lists
what may be offered.

**Ports (P4 groundwork)**: three injected models now exist, so the migrations that
need them are mechanical rather than investigative:

| Port | What a surface reads | Why it is injected |
| :--- | :--- | :--- |
| `ShellState` | shell-owned state (overview/launcher/dashboard open, daemon path, icon resolution) | an imported `Config` is a stale copy (C.9) |
| `SessionPort` | windows, installed apps, thumbnails, activate/close/launch | same, and it has no windows at all (C.10) |
| `MediaPort` | now-playing: track, artwork, status, players, seek | same; idle is *empty*, never a fabricated track |
| `WorkspacesPort` | desktops, current desktop, switch/create/remove/refresh, move a window | desktops are a different concern from windows, so they are a different port |

`MediaPort` is filled by the shell from `MprisMedia`, clamps seeks, and turns every
operation into a stated failure when the shell cannot do it.

`AppHost.mount(appId, parentItem)` embeds an app's item in a host-owned surface (a
dashboard pane) without the pane owning the app's code, and mounts the same instance
twice rather than duplicating it. `tst_app_host` also asserts that every
`featureHost.<name>` used in `shell.qml` exists on the host — a scripted edit once
dropped `itemFor` while the shell still called it, and nothing failed until that IPC
ran.

**Dashboard tabs are offered by apps** (`AppHost.tabProviders`): a manifest declares
`entry.dashboardTab`, and the host answers "which app provides this tab?" from the
*plan*, so a disabled or incompatible app offers nothing. `CentralDashboard` still
contains its old `switch` while the tabs are migrated one at a time; the provider
lookup is what replaces it. `SessionPort` also carries the workspace list and
`moveWindowToWorkspace`, which a workspace surface needs for grouping.

**The Apps page exists** (Settings → Apps): every installed app with its name, version,
API level, state (Enabled / Disabled / Incompatible and the reason) and two actions —
enable/disable (registry, reversible) and remove (payload + record, data kept). It renders
`astral-plasma app list --json` through `AppsService`; it keeps no copy of the truth and
patches nothing optimistically. A failed action shows the daemon's own sentence.

Bundled apps appear because the registry is reconciled on every `run` and on `app list`:
each shipped manifest with no record is recorded as installed (`preinstalled`, enabled,
digest of its payload). Existing records are never overwritten — version, pin, grants and
blocked versions are the user's state — and a record written before the registry carried
names gets one filled in.

Also fixed while wiring it: `run.sh` refreshed `bin/astral-plasma` only when the file was
*missing*, so a stale copy silently ran every daemon command and made new subcommands look
unimplemented. It now copies whichever build (release or debug) is newest.

Still open in P3/P5: remote artifact transport and the official inline catalog, zstd +
minisign *signing*, and the remaining app migrations.

- `astral app new/dev/test/lint/pack` using the installed package as SDK.
- Templates and `sdk/examples/hello`.
- `new` stamps `version` and `kernelApi` from the installed SDK; `lint` refuses
  a `kernelApi` newer than the SDK's own and a missing `dataSchema`; `pack`
  writes the version into the artifact name.
- Migrate `downloads` end to end (domain, infra, window, tab, settings page,
  IPC, shortcut) as the official reference, starting at `0.1.0`.
- `Standalone.qml`, per-app tests, `make app-run APP=downloads`.

**Gate**: a new app can be created outside the repo, run, tested, packed, and
installed locally; the downloads install→use→disable→remove cycle is proven
live; existing downloads tests moved and green.

### P4 — Migrate official apps (L, per app)

1. `media`, `performance`, `workspaces`;
2. `dashboard` (tabs from registry);
3. `settings` (pages from registry + Apps page);
4. `ai`, `assistant`;
5. `dock`, `launcher`, `overview` (core).

Definition of done per app: manifest with its own `version`, `kernelApi`, and
`dataSchema`; baseline in the core package; boundaries; standalone; tests;
install/enable/disable/remove; live proof; no edit to `shell.qml`.

**Gate**: `shell.qml` names no feature; old directories deleted; every app has a
suite and a version; `astral app list` shows eleven independently versioned
preinstalled apps.

### P5 — Packages, catalogs, install UX (M)

- `.astralapp` pack/verify, minisign, staging/rollback, permission records.
- Version fields in the install record; forward-only update, `--to`, pin,
  `--allow-downgrade` behind the `dataSchema` guard; `.prev` restores the
  version; blocked versions after a core-app failure.
- Official catalog in the binary, including preinstalled apps, so an app fix is
  a catalog publish; community catalog add/update.
- Install from file/URL/id; desktop entries; Apps page (per-app versions);
  consent UI.
- Migrations: legacy installs get a registry with every preinstalled app
  recorded at `0.1.0`, plus its baseline extracted from the core package.
- Platform-update reconcile per §8.5.4: auto-update when a compatible version
  exists, disable with a recorded reason otherwise, core apps fall back to the
  baseline; the warning row and its actions in Apps page.
- Platform update preserves app versions, applies only newer baselines, and
  honours pins; revocation and permission-diff behavior.
- Community-trust packages are **refused** until P6 ships the sandbox; P5
  installs official and verified (embedded) apps only.

**Gate**: install an official store app from a file and from the catalog;
tampered package refused; a preinstalled app updates from the catalog without a
platform release; a platform update does not downgrade a newer app; an
incompatible app with a compatible update updates itself, one without is
disabled with a warning and keeps its data; a downgrade that would corrupt data
is refused; uninstall leaves no desktop entry, token, or grant; a community
package is refused with the sandbox reason.

### P6 — Hosted runtime and sandbox (L)

- `broker` context: grants, handshake, methods, audit, rate limits.
- `bwrap` + `xdg-dbus-proxy` launcher; permission→mount/namespace mapping.
- Community catalog, trust badges, consent copy, diagnostics.
- `app publish` output and submission docs.

**Gate**: community fixture app cannot read `$HOME`, open the network without
`network`, import `Astral.Kernel`, load a `.so`, or call an undeclared method;
granting a permission makes exactly that operation work; crash leaves the shell
running.

### P7 — Platform hardening (M, optional)

- Remove shims; API freeze report; deprecation policy tests.
- `docs/APPKIT-API.md` level history, deprecation table, and the floor-bump
  procedure; app release checklist (version bump, changelog, catalog entry).
- CI matrix per app/catalog; cached `qml6`; `platform-e2e` on PRs touching the
  platform.
- `sdk/docs` site source, examples, app-author checklist, `CONTEXT.md` and
  `ARCHITECTURE.md` updates.
- Optional crate split if build time justifies it.

---

## 15. Risks

| Risk | Mitigation |
| :--- | :--- |
| Kernel extraction breaks 152 suites (source-path XHR reads) | Dedicated codemod commit; linter fails on stale paths; screenshot diff gate. |
| `Config` coupling is deeper than expected | Appendix A triage; no new app keys in `Config`; app namespaces from P2. |
| Community QML is malware | Sandbox + permissions + no native plugins + consent; threat model stated honestly. |
| Sandbox breaks legitimate apps | Tiered permissions, diagnostics, `app dev` uses the same sandbox; allowlisted mounts documented. |
| Cross-process embedding expectations | Entry-point matrix (§8.4) is explicit; tabs/pages are official-only. |
| App update silently gains power | Permission-diff consent; publisher key change requires re-consent. |
| An independently updated core app breaks the desktop (no settings page left to fix it from) | Baseline payload in `package/`, automatic revert on load failure, failed version blocked, one-click `rollback` (§8.5.2). |
| App version and platform version get conflated in UI or support | Every row shows the app's own version and a `kernelApi` badge; the platform version appears once, on the about row; a compat failure names both numbers. |
| Preinstalled app updates ship without the platform's checks | Same artifact format, same signature, same staging and consent path; only the delivery channel differs. |
| Compat failure is swallowed as "app disappeared" | Disable keeps payload, data, and grants; reason recorded and shown with the derived platform floor; nothing is uninstalled silently. |
| Forced auto-update smuggles in new permissions | A candidate must grant ⊆ approved; otherwise the app disables and the update waits for review (A30). |
| Downgrade corrupts app data | `dataSchema` recorded at install and re-checked at launch; older builds refused (§8.5.5). |
| Republished artifact under one version | Digest is identity; same version + new digest is refused and needs a version bump. |
| Installer corrupts the desktop | Staging + atomic rename + registry last; crash-point tests; `.prev` rollback. |
| Existing features disappear | Migration records every shipped feature as a preinstalled app at its baseline version; catalog regression test. |
| Startup cost of many apps | `LazyLoader`, provider metadata only, P0 measurement, per-app disable. |
| API churn frustrates authors | AppKit-only public module, `kernelApi`, one-release deprecation window, lint warnings. |
| Two writers for app state | Daemon owns registry/packages/grants; QML writes settings through it. |

---

## 16. Open decisions (small)

1. **Community apps are surface/service only** (no dashboard tabs or settings
   pages). Confirm this is acceptable for v1; the alternative is an embedding
   protocol later.
2. **Catalog ownership**: one official catalog plus user-added community
   catalogs, with no central review requirement for install (trust badges +
   sandbox). Confirm, or require review for "verified" listing.
3. **Sandbox dependency**: `bubblewrap` + `xdg-dbus-proxy` as hard dependencies
   for community apps. On a machine without them, community installs are
   refused; official apps keep working.
4. **Automatic updates**: recommended on for official apps (release-key signed,
   catalog-signed), including preinstalled ones; community apps stay opt-in.
   Confirm, or require a first-launch consent for app updates in general.
5. **Platform update applies newer baselines automatically**: recommended yes
   when the app is compatible and not pinned, with a notice and a one-click
   `rollback`; otherwise skipped silently.
6. **`--to` in v1**: recommended yes for `update --to` against catalog-archived
   versions; arbitrary offline downgrades stay out of v1, with `.prev` rollback
   as the only backward path.
7. **Pinned apps on a platform move**: recommended that the pin wins and the
   app disables with an "unpin and update" action, rather than the platform
   overriding an explicit user instruction.

---

## Appendix A — Service triage

| Current service | Target owner |
| :--- | :--- |
| `DesktopSessionFacade`, `WindowService`, `KWinWorkspaces` | kernel `desktop_session` |
| `NotificationService` | kernel (session-critical) |
| `AudioStreams`, `PipewireAudio`, `BluetoothService`, `NetworkService`, `BrightnessService`, `PowerService`, `InputMethodService`, `ClipboardService` | kernel system ports |
| `AudioVisualizer`, `MprisMedia`, `MediaElection.js` | `media` app |
| `DownloadService` | `downloads` app |
| `AiActivityService`, `AiTokenService` | `ai` app |
| `AssistantService` | `assistant` app |
| `DshWebService`, `DshAuth.js`, `DshWebLogic.js` | `dsh-web` app (store) |
| `VoiceEventCodec` | `voice` app (store) |
| `SystemService` | kernel metrics port; `performance` renders |
| `WallpaperEngine`, `ThemeExportService` | kernel |
| `ClockZoneService` | kernel clock |
| `DebugService`, `Log`, `Logging.js` | kernel |
| `PreviewAppState.js` | `overview` app |
| `WeatherService` | future `weather` app |

## Appendix B — Current → target

| Current | Target |
| :--- | :--- |
| `shell.qml` `IpcHandler`s | app `interfaces/ipc/` |
| `shell.qml` window instances | `AppHost` + manifest `entry.surface` |
| `DashboardTabs.DEFAULT_TABS` | registry projection |
| `NexusHub` fixed imports | registry projection |
| `Config.settings.<feature>` | `apps.<id>` / app config dir |
| Flat `tests/tst_*.qml` | kernel/contracts in `tests/`; app suites beside apps |
| `embedded_bundle.rs` one tree | kernel + one baseline payload per preinstalled app; store/community apps outside the package |
| `install.json` | `install.json` + per-app `install.json` (version, `dataSchema`, pin, blocked) + `apps.json` |
| Product version everywhere | Product version on the platform; per-app versions in each manifest and install record |

## Appendix C — Spike log (2026-11-08)

Environment: Quickshell 0.3.2, Qt 6, live KWin/Wayland session (`wayland-1`,
`/run/user/1000`), `/dev/dri` present, `bwrap` and `xdg-dbus-proxy` installed,
`minisign` CLI **absent**. Spikes ran from `/tmp/astral-p0` (deliberately not
committed; the reusable parts become P6 code and `sdk/examples/hello` in P3).

### C.1 Claims

| Claim | Result |
| :--- | :--- |
| `qml6` loads `import Astral.Kernel 1.0` from `QML_IMPORT_PATH` | **Pass** |
| A `qmldir` type may point into a subdirectory (`Pill 1.0 components/Pill.qml`) | **Pass** |
| `quickshell -p` loads an external module from `QML_IMPORT_PATH` (offscreen) | **Pass** |
| A hosted app renders on the **live** session with only `Astral/AppKit` bound | **Pass** — layer-shell window over the running desktop, `APP_READY` |
| `$HOME` and the session runtime dir are invisible | **Pass** — `$HOME` does not resolve; `/run/user/1000` does not exist |
| No network | **Pass** — `curl` cannot resolve, `getent hosts` empty |
| Hosted app reaches a broker socket bound into the sandbox and its request arrives intact | **Pass** — `Quickshell.Io.Socket` → host server, JSON line with the per-launch token received verbatim; the host's reply was not parsed (no concrete `DataStreamParser` chosen yet) |
| An embedded surface renders on the live session through a `Loader` | **Pass** — `PanelWindow` glass card over the desktop, `HOST_READY` once |
| `import Astral.Kernel` inside the sandbox | **Pass** — `module "Astral.Kernel" is not installed` |
| EGL/DRI works without binding `/sys` | **Fail** — `ZINK … failed`, `egl: failed to create dri2 screen`, software fallback |
| Wayland socket reachable without exposing `$XDG_RUNTIME_DIR` | **Pass** — absolute `WAYLAND_DISPLAY=/run/astral/wayland` |
| `minisign` CLI present | **Missing** — verify in-process with the `minisign-verify` crate |

### C.2 Measurements

Medians of 5 runs, `Date.now()`-style wall clock from `exec` to the app's
`Component.onCompleted`, polling the log every 5 ms.

| Scenario | Median |
| :--- | :--- |
| Hosted app, no sandbox, live Wayland | 136 ms |
| Hosted app, `bwrap`, live Wayland, no font cache mount | 569 ms |
| Hosted app, `bwrap`, live Wayland, `/var/cache/fontconfig` bound | **121 ms** |
| Embedded host, kernel only (offscreen) | 36 ms |
| Embedded host, 11 metadata-only app loaders | 37 ms |
| Embedded host, 11 active stub modules | 65 ms |

Conclusions the plan now depends on:

- The sandbox costs **nothing measurable** once the shared fontconfig cache is
  visible; the 448 ms gap is fontconfig rebuilding a cache into a fresh
  `XDG_CACHE_HOME`, not `bwrap`.
- `LazyLoader` metadata-only registration is free (+1 ms for 11 apps), which is
  what §9.1 relies on: startup does not scale with installed app count, only
  with apps that actually instantiate a surface.
- Stub modules (±2.6 ms each) are a floor, not a prediction. P4 must measure the
  real `dock`/`dashboard` after migration and compare against this 65 ms row.

### C.3 Regression baseline

`make test` on this commit: **53 s**, **153 QML suites**, **988 Rust tests**,
exit 0. Every phase gate compares against these numbers; a change that doubles
any of them needs a stated reason.

### C.4 Things that did not survive contact

- **`$HOME` was still `HOME=/home/hlu`** in the first offscreen spike: the path
  did not resolve, but the variable leaked. The launcher must `--clearenv` and
  set `HOME` explicitly, which the measured command above now does.
- **Locale**: a cleared environment makes Qt warn and switch to `C.UTF-8`;
  setting `LC_ALL=C.UTF-8` keeps logs clean and string collation predictable.
- **`/etc/machine-id`** was bound in the first attempt and turned out to be
  unnecessary for a Wayland client; it is gone from the mount list (verified by
  re-running the same sandbox and app without it).
- **`Quickshell.Io.Socket` does not connect on `path` alone** — `connected` must
  be set (or re-set) to open it; a server that closes after one reply reports
  `PeerClosedError` (1) on the app side, so the broker must keep the connection
  open for the app's lifetime.

### C.5 P1 mechanism spike (same day)

| Claim | Result |
| :--- | :--- |
| A generated `qmldir` with subdirectory paths resolves singleton + component types | **Pass** — 80 types, `KERNEL_MODULE_OK surface=#141218 radius=24` |
| Collapsing `import "../theme"` / `"../services"` into `import Astral.Kernel 1.0` keeps the dependency graph intact | **Pass** — 74 imports collapsed, no behaviour change in the probe |
| Duplicate flattened type names are detected before they silently collide | **Pass** — `a/Panel.qml` + `b/Panel.qml` refused with exit 2 |
| Kernel can be moved without touching app-layer code | **No** — `Config.qml` → `dashboard/tabs/DashboardTabs.js` must move into the kernel first |

Diagnostic note for the migration: a single missing script reports as a chain of
~10 `Type … unavailable` lines. Only the deepest `caused by` is the cause; the
rest are callers. The codemod review must read the last line, not the first.

### C.6 P1 migration (same day)

The kernel moved to `modules/Astral/Kernel/{theme,components,config,services}`.
The move itself is `git mv`; the work is that every relative path in the tree was
written against the old location.

| Quantity | Count |
| :--- | :--- |
| Files whose imports/strings changed | 217 |
| Path references rewritten | 474 |
| Source-text assertions relaxed to path shape | 4 |
| `import qs.<dir>` dialect occurrences | 11 (3 files) |
| QML suites / Rust tests after the move | 153 / 988, all green |

Findings that changed the plan:

1. **Two path dialects, not one.** Besides `import "../theme"`, three files used
   `import qs.theme` — Quickshell resolves a `qs.` prefix against the shell root,
   so those imports silently pointed at `<root>/theme` and broke the moment the
   directory moved. A codemod that only knows `../` reports success and leaves
   the shell unloadable; the live run is what caught it (`module "qs.services"
   is not installed`).
2. **A module `qmldir` is not a rename.** Importing a module compiles its
   singleton entries eagerly; the kernel's singletons import `Quickshell`; the
   `qml6` test runner has no Quickshell plugin. So `import Astral.Kernel 1.0`
   turns every suite red even though the same code loads fine under
   `quickshell`. P1 keeps semantics identical (relative paths) and the module URI
   moves to P2.
3. **Suites pin source text, not behaviour.** Four suites asserted the literal
   `"../theme/..."` inside other files. They were re-pinned to the *shape* of the
   reference (`theme/assets/icons/` + `.svg`, `[^"]*services/PreviewAppState.js`)
   so the next move does not rewrite them again.

### C.7 AppKit (same day)

| Claim | Result |
| :--- | :--- |
| `import Astral.AppKit 1.0` resolves from `QML_IMPORT_PATH` and renders a window | **Pass** — layer-shell window on the live session |
| A hosted app reads the host palette without kernel access | **Pass** — `radius=12`, `font=Test Sans` from the test's palette file |
| `AppKit` compiles with no kernel import | **Pass** — asserted per file |
| Drift between AppKit constants and the daemon/kernel | **Caught by tests** — `AppApi` vs `domain::app_compat`, `Motion` vs `theme/Theme.qml` |
| `QtObject` accepts an unnamed child | **Fail** — no default property; the reader is a named `FileView` property |
| `FileView.data()` returns the parsed JSON | **No** — returns `{}` for a flat `.json`; `text()` + `JSON.parse` is what works |

Three findings worth keeping:

1. **`Palette` is already a QML type.** Naming the internal singleton `Palette`
   shadowed `QtQuick`'s own type and surfaced as `Property 'color' … is not a
   function`. It is now `AppPalette`, and internal singletons avoid names QML
   already uses.
2. **A sandbox has no kernel.** The first attempt forwarded the kernel's theme
   through a relative import, which cannot work once only `Astral/AppKit` is
   mounted — and it silently produced `undefined` colours instead of failing.
   Palette-file-driven AppKit is the only version that survives the sandbox.
3. **Theme data has to travel with the palette.** Radii and the typeface were
   kernel-only, so a hosted app would have rendered with the shell's *default*
   shape and type. `ThemeExportService` now exports them, and a test asserts every
   key AppKit reads exists in the exported payload.

### C.8 AppHost (same day)

| Claim | Result |
| :--- | :--- |
| Registry → host → instantiated app, live | **Pass** — `PLAN loaded=[io.github.fixture.embedded]` then `EMBEDDED_APP_LOADED` |
| A corrupt manifest beside good ones | **Pass** — one `invalid` row, the other apps still plan and load |
| A payload whose QML does not compile | **Pass** — `appFailed`, `activate` returns null, caller continues |
| A missing payload | **Pass** — reported once, not once per status change |
| Nothing instantiated at boot | **Pass** — `loader.active === false` for every planned app |
| QML module name matches the directory | **Fail first** — `Astral.Kernel.Host` needs `Host/`, not `host/`; the directory was renamed to match the module (spec §6.1: PascalCase) |

Two design notes that came out of building it:

1. **`activate(id)` is the API, not `active: true` on a Repeater.** A host that
   instantiates at boot pays the whole cost immediately; an explicit call lets a
   screen, tab, or tray request decide when. The tests assert the `active === false`
   state, so this cannot silently regress into eager loading.
2. **Failure reporting is deduplicated by id.** A `Loader` reports its error twice
   (status change and the activation that observes it), which would surface as two
   warnings for one broken app.

### C.9 Shell rewiring attempt: reverted, with the reason (same day)

Attempted: move `shell/ActiveAppsOverview.qml` into
`modules/Astral/Apps/Overview/` with a manifest and load it through `AppHost`
(`modules/Astral/Apps/index.json` generated by a new `scripts/gen_apps_index.py`).

It did not work, and the failure is the useful part:

| Observation | Meaning |
| :--- | :--- |
| `AppHost.activate(...)` → `status=1 item=true`, `app loaded` | the host, the index, the manifest, and the Loader are correct |
| `IPC overview toggle` → `was false` / `now true` | the shell's handler and `Config` work |
| The app's own per-tick log stayed `Config.overviewVisible=false` | **the app has a different `Config` singleton instance** |

A component loaded through a `Loader` gets its own singleton instance for a
directory import, so a migrated surface silently reads stale settings. Nothing
about that is fixable with a relative path: it needs the shell to *pass* state
(IntentBus) and the app to read settings through a port.

Reverted: `shell.qml`, the surface, and the three suites it touched are back to
their committed state; `modules/Astral/Apps/` and the index generator were
removed. The host library stays — it is tested, and it is what the migration will
use once the bus exists. The packaging fix that came out of it (ship `modules/`
as one tree so a package contains AppKit and the host) was kept, because without
it an installed shell has no SDK.

### C.10 Second migration attempt: the pipeline works, the port does not exist yet

With `IntentBus`, `ShellState`, and injection in place, the overview was migrated
again: it loaded as an app, opened on `overview toggle`, and was driven by the
injected state.

| Observation | Meaning |
| :--- | :--- |
| `AppHost.activate(...)` → `app loaded`, zero load errors | the module, registry, manifest and injection all work |
| `overview tick: state=true visible=false` → after `overview toggle` the surface opens | the injected state is the live instance (the C.9 bug is gone) |
| The surface renders with an **empty preview grid** ("No windows") | its `WindowService` — imported from `Kernel/services` — is a different instance with no windows |

That is the same defect one layer down: **every kernel singleton is per-instance
for a Loader-loaded component**, so a session port has to be injected too, exactly
like `ShellState`. A window list is not a setting; it is a data model with signals,
so the port is a real object (`windows`, `refreshThumbnails()`, `activate(id)`), not
a value.

Reverted again: the surface is back under `shell/`, driven by `Config` and the
shell's own `WindowService`. Kept: the intent bus, the read model, injection,
`eager`, the module `qmldir`, the `QML_IMPORT_PATH` plumbing in `run.sh`, and the
boundary linter wired into `make test`.

Conclusion: the app platform's remaining blocker is the **port layer** (§6.3, §9.5),
not the host. Migrating an embedded app means first exposing what it reads — windows
today, media and downloads next — as injected ports.

### C.11 Overview migration (third attempt, successful)

| Claim | Result |
| :--- | :--- |
| The app loads from `apps/index.json` through the host | **Pass** — zero load errors, `eager` activation |
| Injected state drives visibility | **Pass** — `open=true` after `overview toggle` |
| Injected windows reach the UI | **Pass** — a probe window renders as a card in the grid |
| `shell.qml` names no feature | **Pass** — asserted by `test_apps_bundled::shell_qml_names_no_feature` |
| The app imports no kernel singleton | **Pass** — `check_app_boundaries.py`: 0 `Config.`/`WindowService.` uses |
| Window grid is populated on a dev box | **No** — the shell's own `WindowService.windows` is empty without a claimed session; identical data before and after the migration |

Two things this migration cost, both now encoded:

1. **A second `Component.onCompleted` in `shell.qml` breaks a contract test.**
   `the_shell_claims_its_shortcuts_on_every_start` splits the file on the first
   occurrence, so registering intents inside the `IntentBus` declaration made the
   test inspect the wrong block. Intent handlers now live in the root's single
   completion block, next to the rest of the startup wiring.
2. **Testing the port path needs a probe, not a daemon.** With no claimed session
   the grid is legitimately empty, which cannot distinguish "migration broken" from
   "no windows". The verification that settled it was a single stub window bound to
   `SessionPort.windows` in a dev run: a card appeared, then the stub was removed.

### C.12 Post-mortem: the kernel move silently disconnected the daemon

**Symptom** (user, live session): no taskbar app icons, no window previews, no
system tray. The shell looked alive; nothing errored.

**Cause**: twelve services computed the daemon path from *their own directory*:

```qml
readonly property string serviceDir: Qt.resolvedUrl(".")...
readonly property string daemonBin: root.serviceDir + "/../bin/astral-plasma"
```

That was correct while `services/` sat at the repository root. P1 moved it to
`modules/Astral/Kernel/services/`, so the path became
`<repo>/modules/Astral/Kernel/bin/astral-plasma` — a directory that does not exist.
Every `Process` call then failed with a warning the shell never surfaced, taking
windows, tray, previews, clipboard, network, downloads and metrics with it.

**Why the suites missed it**: 153 QML suites and 1000+ Rust tests were green. Nothing
asserted *where the shell thinks the daemon is*. Every test used fixtures, sources,
or data structures; the one path that matters at runtime was never resolved.

**Fix**: `modules/Astral/Kernel/config/Paths.qml` owns the layout —
`daemonBin`, `root`, `scriptsDir` — resolved from its own position
(`../../../..`), with `ASTRAL_PLASMA_DAEMON` as an override. `Config.daemonBin`
delegates to it; the twelve services ask it. No service computes a path again.

**Guard**: `daemon/tests/test_runtime_paths.rs` (4 tests, no display needed) fails
when a kernel file derives the daemon from its own directory, when `Config` computes
a second path, when any `daemonBin` property does not delegate, and when the
resolved binary is not a file at the depth `Paths` claims.

**Also observed and explained**: "a second background out of sync during
animation" was two `quickshell` instances running at once (the debugging restarts
left duplicates), each drawing its own frame and dock a few frames apart. One
instance now.

**Lesson for the remaining phases**: a file move is a *runtime* change for every
path-relative lookup, not only for imports. Any phase that relocates a directory
needs a resolved-path assertion before it is called done.

### C.13 Finding: two import spellings duplicate kernel singletons

Three tab migrations (`workspaces`, `media`, `performance`) were written, worked in
isolation, and then **reverted** — and the reason is the most useful result of the
attempt:

* a migrated app imports the kernel as `../../Kernel/...` (relative to its own depth);
* the unmigrated dashboard tab imports it as `../../modules/Astral/Kernel/...`.

Two spellings of the same directory are **two registrations** of every singleton in
it. When one document contains both (a suite instantiating the app *and* the tab), the
second registration can come up un-instantiated, and a name like `MprisMedia` resolves
to it: `Cannot read property 'length' of undefined` at a line that had worked for
months.

Consequences, now a P4 prerequisite rather than a note:

1. **Apps must reach the design primitives through one module** (`Astral.AppKit`), not
   by relative `Kernel/*` paths, so every app shares one spelling and one registration.
   `AppKit` therefore has to expose what a tab actually uses (`LiquidGlassCard`,
   `MaterialIcon`, `LevelBar`, `GlassPill`, …), not only Theme/Colors/AppWindow.
2. **A lint rule must enforce it**: an app file may import `Astral.AppKit` and Qt, and
   nothing from `Kernel/*`. `check_app_boundaries.py` already forbids `Kernel/config` and
   `Kernel/services`; it must forbid `Kernel/theme` and `Kernel/components` for apps too.

Until both land, tabs stay where they are. What *did* stay from the attempt: the host
ordering fix, `AppHost.mount`, `tabProviders`, the `loaderCount` notification fix, and
the `SessionPort`/`MediaPort`/`WorkspacesPort`/`MetricsPort` + intent wiring — all
tested, all green (`make test`: 1109 Rust tests, 164 QML suites).

### C.14 Finding: AppKit cannot be imported by the qml6 suites yet

With the boundary narrowed (apps import `Astral.AppKit` only, C.13), the workspaces
migration was retried and the *suite* failed:

```
modules/Astral/AppKit/AppPalette.qml:4:1: module "Quickshell" plugin
"quickshell-coreplugin" not found
```

Two known facts collide: importing a **module** compiles its singleton entries eagerly
(C.6), and `AppPalette` reads the host palette with `Quickshell.env`/`FileView` (C.7).
`qml6` — the test runner — has no Quickshell plugin, so `import Astral.AppKit 1.0`
fails in every suite that loads a migrated app, even though the same import works in the
shell and in a hosted app.

The fix is to make **AppKit's singletons IO-free**:

* `Theme`, `Colors`, `Motion`, `AppApi` hold values only (they already do, except the
  palette read);
* the palette read becomes a *type* (`PaletteLoader`) that `AppWindow` — or the app's
  own root — instantiates once and hands to the singletons via setters, so eager
  singleton compilation touches no Quickshell API;
* a suite then sees the Material defaults, which is what a layout test asserts against
  anyway; the shell and hosted apps see the real palette.

Reverted again for now: the workspaces tab stays in `dashboard/tabs/`, the tree is green
(1109 Rust tests, 164 QML suites), and the AppKit primitives + lint rule + harness
`QML_IMPORT_PATH` from C.13 are committed and in place.

### C.16 Finding: an AppKit component must not subclass a kernel component

Reported from the live desktop: the migrated workspaces surface rendered with **light
grey cards and washed-out text on a dark shell** — the theme was not respected.

Cause: `AppKit/GlassCard.qml` was `LiquidGlassCard {}`, i.e. a subclass of a kernel
component. Subclassing drags the kernel implementation's *own* imports with it, and inside
the `Astral.AppKit` module those resolve to a **second registration** of the kernel
`Colors`/`Theme` singletons. That copy has no palette (the shell populated the first
registration), so every colour falls back to Material defaults: light cards, pale text,
no accent.

Reverted: the AppKit primitives, the app migrations that used them, and the lint rule that
forced apps onto AppKit. The desktop is correct again (dark glass, accent pill, readable
chips), `make test` exit 0 — 1109 Rust tests, 164 QML suites.

The rule this settles, and it matches §6.4 rather than contradicting it:

| Runtime | What it renders with |
| :--- | :--- |
| **Embedded (official)** | the kernel: one registration, the shell's palette, the archetype's radii |
| **Hosted (community)** | `Astral.AppKit`: its own tokens, read from the exported palette file, because the kernel is not mounted |

So official apps keep importing `Kernel/theme` + `Kernel/components` (that is why the
earlier migrations were theme-correct), and AppKit is for hosted apps — where there is no
kernel to conflict with. An AppKit that *is* usable by embedded apps needs its primitives
implemented against AppKit's own tokens, which remains future work, not a prerequisite.

What this leaves: the tab migrations themselves were green and themed on kernel imports;
they will be re-applied that way. C.13's duplicate-registration problem applies to
**services inside suites**, not to colours in production — narrowed accordingly.

### C.17 The blocker P4 actually has: the theme does not cross the app boundary

Three app migrations were built, verified green, and each rendered **wrong on screen**:
light grey cards on a dark shell. The pattern is consistent and now fully characterised:

| Where the app's primitives come from | Result |
| :--- | :--- |
| kernel `Kernel/theme` + `Kernel/components`, imported by the app's own path | duplicate `Colors`; its `Config` does not have the shell's runtime theme state → light fallbacks |
| `Astral.AppKit`, subclassing kernel components | the subclass drags the kernel registration into the module → same duplicate, same result |
| the shell's own surfaces (unmigrated) | correct: dark glass, accent, archetype radii |

So this is not an import-path preference: **theme state lives in the shell's `Config`
singleton instance**, and no import can share it. Until the theme is *delivered to* the
app, every migration is a visual regression — and a green suite proves nothing about it
(which is exactly what happened three times).

Two designs that would work, in order of preference:

1. **Palette file as the single source of truth for apps.** `ThemeExportService` already
   writes `current-palette.json` (primary, surface, on_surface, outline, radii, font,
   mode). An app's primitives read that file, so a duplicate `Colors` resolves the *same*
   values the shell publishes. This needs no kernel change, works for hosted apps too
   (already the AppKit plan), and is testable by writing a palette and asserting pixels.
2. **Inject the theme**: the shell hands an app a `theme` object (colours, radii, motion)
   and the app renders primitives parameterised by it. More invasive — the primitives must
   accept tokens rather than read singletons — but it removes the file dependency.

Nothing is migrated today: `modules/Astral/Apps/` is empty apart from a generated
`index.json`, the overview is a shell surface again, and `make test` is green (1109 Rust
tests, 164 QML suites). What remains tested and usable for the migration phase: the
manifest contract, compatibility window, registry + writer, `AppHost` (plan, mount,
injection, tab providers), `IntentBus`, `ShellState`, and the
`Session`/`Media`/`Workspaces`/`Metrics` ports.

### C.18 The theme bridge: declare the app's component in the shell document

C.17 left one question: how does a migrated app get the shell's theme at all? A probe
answered it by measurement, not by reading code:

| How the app is loaded | `Colors.isDarkMode` / `Colors.surface` in the app |
| :--- | :--- |
| `Loader.source = <app>/Main.qml` (registry-driven) | `undefined` / `undefined` — its kernel singletons fail to instantiate |
| `Component { App {} }` declared in `shell.qml` | `true` / `#141218` — identical to the shell |

A component compiled in the shell's document resolves its imports in the shell's *context*,
so the app shares the shell's kernel registration — and therefore its palette, its archetype
and its radii. That is the bridge, and it needs no new API for themes.

`AppHost.components` carries the map (`appId -> Component`); the Loader prefers a declared
component and falls back to `source:` otherwise. `shell.qml` therefore declares one
`Component` per migrated app — a *component map*, not a `switch` over features: the plan,
enable/disable, dependency order, compatibility and injection all still come from the
registry.

Verified live: the **workspaces** tab renders dark glass with the accent pill, its 7-window
badge and readable chips, the **media** tab renders the player's idle state ("No Media
Playing · NetEase Cloud Music (Wine)"), transport, progress and artwork, and the
**performance** tab renders live telemetry (CPU 11%, memory 40%, GPU 33%, speed, temperature,
processes) — all hosted in their dashboard panes, zero load errors, `make test` 1109 Rust
tests + 164 QML suites. and the **AI** tab renders live quota data (98% cache hit, per-provider remaining limits,
three connected accounts). and **downloads** renders its manager (segments, "1 finished", add-sheet, empty state) — five
apps are migrated; the pattern is mechanical now. `DownloadsWindow` instantiates the same
shell-declared component, so the drawer and the window share one implementation and one
registration.

The trade-off is explicit: `shell.qml` names each migrated app once, in a component
declaration. That is the price of sharing one kernel registration, and it is smaller than
the alternative (duplicating the shell's theme state into every app).

### C.19 Disabling an app must reach the plan, and the gap must explain itself

Two defects were found by driving the Apps page's own actions end to end:

1. **The host ignored the registry.** `AppRegistry`'s bundled mode synthesised
   `enabled: true` for every shipped app without reading `apps.json`, so *Disable* changed
   the file and nothing else — the app kept loading. It now merges the daemon's records
   (enabled, pinned, blocked) over the bundled index, with `Paths.dataDir` supplying the
   registry path.
2. **A disabled app left a blank rectangle.** A dashboard pane whose app is not in the plan
   now renders `AppUnavailableHint` with the host's own reason — `AppHost.tabStatus(tabId)`
   answers `{ id, available, reason }` for the app that *declares* the tab, even when that
   app is skipped. Verified: "Workspaces is not available / disabled in the registry; its
   files stay on disk".

Re-enabling restores the tab on the next start, so the round trip is: enabled → mounted and
themed, disabled → excluded with a reason, re-enabled → back.

### C.20 The assistant: one context object instead of three properties

The assistant is thirteen files (window, drawer, five components) that all needed the same
three ports. Threading them individually would have meant a property on each. Instead the app
owns `AssistantContext` (a QtQuick-only singleton in its own directory) that the window fills
from what the host injected:

```
AssistantContext.assistant   the shell's live assistant service
AssistantContext.shellState  visibility, settings it renders
AssistantContext.intents     settings navigation, close, minimize, sessions
```

A singleton living inside an app directory is compiled when the app is, in the same
registration (C.18), so it shares the shell's kernel singletons.

Two classes of leftovers had to be removed, and both are worth remembering:

* `typeof Config !== "undefined" ? … : false` guards became *always false* once the app lost
  its Config import — **the window never opened**, with no error. Guards on a name the app
  cannot see are not defensive, they are broken.
* `Config.openSettings("ai")` → an intent rewrite left `{ page: "ai");` in two places (the
  substitution ate a parenthesis). The app failed to parse; the suites caught it, the linter
  would not have.

Verified live: the Copilot window opens with its session list, provider/model row
(`OpenCode Go · mimo-v2.6-flash`) and quick actions, in the shell palette.

### C.21 The dashboard is an app: one host, seven-ish ports

`shell/CentralDropdown.qml`, `dashboard/tabs/DashboardTab.qml` and the tab policy
(`DashboardTabs.js`) moved into `modules/Astral/Apps/Dashboard/`. The app takes **one**
injected property — the host — and derives everything else from it (`state`, `intents`,
`session`, `media`, `metrics`), so the shell does not thread eight ports through
`UnifiedShell`.

The tab panes now mount their apps through tolerant helpers (`hostTabStatus`, `mountTab`): a
host that cannot mount apps (a suite stub, or a shell without the platform) yields an empty
pane with a reason instead of a `TypeError`. That tolerance is what let thirteen suites
survive the move without a stub on every one of them.

`dashboard/CentralDashboard.qml` was **deleted**: nothing instantiated it, and it duplicated
the dropdown's job with a second tab switch — the kind of dead surface that makes two
behaviours look tested.

Verified live: the dashboard opens with its six tabs, weather card, system info row
(`CachyOS Linux · KDE Plasma 6 …`), clock and calendar, themed.
