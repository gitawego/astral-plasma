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
  `modules/Astral/Kernel/host/AppApi.js` by `scripts/gen_app_api.py`. A test
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
- `modules/Astral/Kernel/host/AppHostPolicy.js` — the host's decisions as pure
  functions: who loads, why the rest do not (`disabled`, `blocked`,
  `incompatible`, `unresolvedDependency`, `invalid`), dependency-ordered and
  deterministic. No app is named anywhere.
- `astral app list [--json]`, `enable`, `disable` — real, reading and writing the
  same registry the host will; every other `astral app` subcommand names the
  phase it lands in instead of silently doing nothing.
- `sdk/examples/hello/` + `daemon/tests/test_app_contract.rs`: the example an
  author copies is validated by the same code that validates an install, so the
  authoring side cannot drift from the enforcement side.

Still open in P2:

- `AppHost.qml` itself (instantiate the plan behind `LazyLoader`s) and
  `SurfaceBroker`/`IntentBus`; then moving `overview` out as the first embedded
  app — the point at which the host stops being a library and starts replacing
  `shell.qml` wiring.
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

### P3 — SDK v0 + first reference app: downloads (L)

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
