# Astral Plasma

> A sleek, fluid, and multi-theme modern desktop shell for **KDE Plasma 6 & KWin** and **Hyprland / Omarchy**, built with [Quickshell](https://quickshell.outfoxxed.me/), QtQuick, and a native **Rust daemon**.

[![KDE Plasma 6](https://img.shields.io/badge/KDE_Plasma-6.x-blue.svg?logo=kde)](https://kde.org/plasma-desktop/)
[![Hyprland](https://img.shields.io/badge/Hyprland-0.50%2B-00c8ff.svg)](https://hyprland.org/)
[![Omarchy](https://img.shields.io/badge/Omarchy-Hosted_Plugin-purple.svg)](https://omarchy.org/)
[![Powered by Quickshell](https://img.shields.io/badge/Powered_by-Quickshell-ff79c6.svg)](https://quickshell.outfoxxed.me/)
[![Backend: Rust](https://img.shields.io/badge/Backend-Rust-black.svg?logo=rust)](https://www.rust-lang.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

---

## 🌟 Overview & Inspiration

**Astral Plasma** is an extensible desktop shell engineered for **KDE Plasma 6 (KWin)**, **Hyprland**, and hosted **Omarchy** plugin environments.

The visual language is **highly inspired by [caelestia-dots/shell](https://github.com/caelestia-dots/shell)** — its seamless desktop frame, soft shadows, and fluid morphing popouts — while the architecture is a general-purpose, multi-theme shell framework: a Quickshell/QML frontend layered on top of a self-contained Rust daemon with a ports-and-adapters architecture.

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  QML Presentation (Quickshell)                              │
│  shell.qml · DesktopSessionFacade · UnifiedShell · Dock     │
│  dashboard/ · settings_gui/ · dock/ · services/ · theme/    │
└──────────────────────────┬──────────────────────────────────┘
                           │ Quickshell IPC · Unix Socket Stream
┌──────────────────────────▼──────────────────────────────────┐
│  Rust Daemon  (bin/astral-plasma, DDD layers)               │
│  domain/ (DesktopSessionSnapshot · Workspace · Window)      │
│  infrastructure/ (KWinAdapter · HyprlandAdapter · DBus)     │
│  window previews · metrics · wallpaper · shortcuts · doctor │
└─────────────────────────────────────────────────────────────┘
```

The daemon builds into a **single self-contained binary** (`bin/astral-plasma`) that embeds the entire QML theme bundle and Omarchy plugin assets, runs the shell, exposes a REST/Unix-socket API, and manages Plasma panels, Hyprland socket events, shortcuts, and system diagnostics.

---

## ✨ Features

### Unified Desktop Surface
- **Seamless outer frame**: full-screen boundary with rounded corners, soft shadows, zero gaps, and concentric inner fillets (`CornerFillet`).
- **Flush fused left dock + top bar**: `UnifiedDock` and `TopBar` share one `FusedPanel` surface with liquid-glass material and true compositor blur (`BackgroundEffect.blurRegion`, KWin blur radius tuned by `run.sh`).
- **Invisible exclusion zones** (`ExclusionZones`): 1px strips that reserve screen edges for KWin window tiling.
- **Wallpaper layer**: dynamic + static background layers with live preview, carousel picker, and Material You palette regeneration via [matugen](https://github.com/InioX/matugen).

### Left Dock
- **Launcher & workspaces**: quick launcher entry with animated workspace indicators and liquid asymmetric pill transitions (500ms/750ms decoupled edges).
- **Live taskbar** (`DockTaskbar`): running KWin windows, click-to-focus, scroll-capped (`DockScrollCapsule`) so it never pushes dock controls off-screen.
- **Active window tracker**: centered app name/icon with context menu.
- **System tray**: native `StatusNotifierItem` DBus integration with context menus (`TrayContextMenu`) and click-to-activate.
- **Stacked clock & status icons**: clock plus keyboard layout, network, Bluetooth, brightness, audio, and battery indicators (order/enabled via settings).
- **Fused bottom popouts**: `FusedBottomPopout` morphs out of the dock for Audio, Battery, Bluetooth, Brightness, Keyboard layout, Wi-Fi, tray menus, and app previews.

### Surfaces & Overlays
- **Central dashboard** (`CentralDropdown`): dropdown overlay with configurable tabs — **Dashboard** (weather, quick toggles, notifications), **Media**, **Performance** (system metrics), and **Workspaces**.
- **Command launcher** (`CommandLauncher`): bottom search/launch modal with keyboard navigation and an integrated **wallpaper carousel**.
- **Active apps overview** (`ActiveAppsOverview`): fullscreen overlay on bare `Meta` (KWin shortcut → daemon → shell IPC) showing **live window thumbnails** captured through KWin's `ScreenShot2` API, with double-buffered flicker-free updates.
- **Volume OSD**, **right-edge control rail**, **power confirmation dialog**, and **notification popups**.
- **Settings GUI** (`settings_gui/`): in-shell settings window with a Nexus hub and pages for Dock, Dashboard, Theme, Wallpaper & Style, Audio, Bluetooth, Network, Status icons, and System.

### Media
- **Multi-player MPRIS**: adapters for Spotify, NetEase Cloud Music, QQ Music, and a generic/universal fallback, with player switching.
- **Real-time visualizers**: PipeWire DSP spectrum via the daemon (`astral-plasma visualizer`) driving `radial`, `speaker`, and `heatmap` styles — energy is ground-truth PCM data, silence reads exactly `0.0`.
- **Audio stream arbitration**: per-app PipeWire stream matching for volume routing.

### Theming
- **Dynamic Material You / matugen** palette extraction from your KDE wallpaper, plus built-in presets (default `iris`) and light/dark modes.
- **Design tokens**: all motion uses the Material 3 Expressive beziers and durations from [`DESIGN.md`](DESIGN.md) / `theme/Theme.qml` — no hardcoded durations.

### Backend (Rust Daemon)
- DDD layout: `domain/` · `application/` · `infrastructure/` · `interfaces/`.
- Owns DBus integrations (KWin workspaces, Plasma panels, tray, MPRIS), system metrics parsing, window previews, wallpaper persistence, shortcut binding, systemd user-service management, and an interactive **dependency doctor**.
- Embedded QML bundle (`astral-plasma extract`), REST + Unix-socket API server (`astral-plasma serve`), and an event-driven watcher.

---

## 📋 Prerequisites

- **Desktop Environments Supported**:
  - **KDE Plasma 6** & KWin (Wayland or X11)
  - **Hyprland** (v0.50.0+ Wayland)
  - **Omarchy** (v4.0.x hosted plugin mode under `omarchy-shell`)
- **Runtime dependencies**:
  - [`quickshell`](https://quickshell.outfoxxed.me/) (v0.3.0+)
  - `qt6-base`, `qt6-declarative`, `qt6-svg` (Qt 6.6+)
  - `qdbus6` / `kwriteconfig6` (when running under KDE Plasma 6)
  - `pipewire` (audio & visualizer)
- **Build dependencies**:
  - Rust toolchain (`cargo`, stable) — builds the daemon
- **Optional**:
  - `fcitx5` / `fcitx5-remote` (IME switcher)
  - `power-profiles-daemon` / `powerprofilesctl` (power profiles)
  - `matugen` (dynamic wallpaper palette extraction)
  - `spectacle` (screenshots / visual verification)

> 💡 **Automated Dependency Doctor**: verify all dependencies, versions, and system readiness at any time:
> ```bash
> make doctor
> # or directly via the binary:
> ./bin/astral-plasma doctor
> # or machine-readable JSON:
> ./bin/astral-plasma doctor --json
> ```

---

## 🚀 Getting Started

### 1. Safe Dev Mode (recommended to test first)
Run the shell in isolation **without modifying your system's** Quickshell/Plasma configuration:

```bash
git clone https://github.com/gitawego/astral-plasma.git
cd astral-plasma
./run.sh
```

- Builds `bin/astral-plasma` on first run.
- Refuses to start a duplicate instance — if the shell is already running, `./run.sh` forwards to it over IPC.
- `./run.sh --launcher` opens the command launcher, `./run.sh --wallpaper` opens the wallpaper picker.
- Restores Plasma panels and shortcuts on exit; press `Ctrl+C` to stop safely.

### 2. Makefile workflow
```bash
make build      # Release build → bin/astral-plasma (single self-contained binary)
make run        # Build + run; auto-restores the Plasma top panel on exit
make stop       # Stop the shell and restore Plasma panels
make restore    # Restore the original KDE Plasma panels
make doctor     # Dependency / compatibility report
make test       # Full test suite: Rust unit tests + all QML suites
make clean      # Remove build artifacts
```

### 3. System installation
To install as your primary Quickshell configuration:

```bash
./install.sh
```

This will:
- Check dependencies and build the daemon.
- Back up any existing `~/.config/quickshell` and symlink this repository to it.
- Install desktop entries in `~/.local/share/applications`.
- Bind global shortcuts (with a snapshot of the previous state).
- Generate the initial color palette.

Launch anytime via `quickshell` (or the installed desktop entries).

### 4. Uninstall
```bash
./uninstall.sh
```
Zero-residue cleanup: stops the shell, removes the user service, restores the config backup, removes the KWin script package, unbinds shortcuts, and clears data/cache/state.

### 5. Automated Releases & Pre-built Binaries (x64 / ARM64)
Astral Plasma includes an automated multi-architecture release pipeline built on GitHub Actions:
- **Supported Architectures**: `x86_64` (Intel/AMD) and `aarch64` (ARM64 / Raspberry Pi / Asahi Linux).
- **Trigger via Local Project CLI**:
  ```bash
  # Interactive mode: proposes patch, minor, major, or custom version:
  ./scripts/release.sh

  # Or explicit flags / version:
  ./scripts/release.sh --patch
  ./scripts/release.sh --minor
  ./scripts/release.sh --major
  ./scripts/release.sh 0.2.0

  # Preview with dry-run:
  ./scripts/release.sh --dry-run
  ```
- **Trigger via GitHub Actions Web UI**:
  Go to the **Actions** tab -> **Release** -> **Run workflow**:
  - **Release type**: Select `patch` (default), `minor`, `major`, or `custom`.
  - **Custom version**: Enter version only if `custom` is selected.
  - The workflow automatically increments the version, updates `daemon/Cargo.toml`, commits with `[skip ci]`, creates the annotated git tag, compiles x64 & arm64 binaries, and publishes the GitHub Release.
- Releases automatically generate a formatted Conventional Commits changelog, compile stripped binaries for both architectures, calculate cryptographic checksums (`SHA256SUMS.txt`), and publish GitHub Releases with downloadable archives and standalone binaries.

---

## ⌨️ IPC & Shortcuts

All UI surfaces are scriptable through Quickshell IPC:

```bash
quickshell ipc -p <config-path> call <target> <function> [args...]
# e.g. (installed):
quickshell ipc -p ~/.config/quickshell call dashboard toggle
# e.g. (dev checkout):
quickshell ipc -p "$PWD" call launcher open apps
```

| Target | Functions | Purpose |
| :--- | :--- | :--- |
| `dashboard` | `toggle` `open` `close` `setTab(tab)` | Central dropdown dashboard |
| `media` | `playPause` `next` `previous` `cyclePlayer` `selectPlayer(bus)` `setVisualizer(style)` `toggleVisualizer` | MPRIS media & visualizer style |
| `launcher` | `toggle` `open(mode)` `close` `next` `prev` `pageUp` `pageDown` `select(idx)` | Bottom command launcher (`apps` / `wallpaper` modes) |
| `overview` | `toggle` `open` `close` | Active apps overview (live thumbnails) |
| `settings` | `toggle` `open(page)` `close` `setPage(page)` | In-shell settings GUI |
| `theme` | `toggle` `setMode(light\|dark)` `setPreset(name)` | Theme mode / preset |
| `popout` | `toggle(mode,y)` `open(mode,y)` `close` `showTray(id)` `previewApp(idx)` | Fused bottom popouts & tray/app previews |
| `wallpaper` | `set(path)` `preview(path)` `stopPreview()` `reload()` | Wallpaper engine |
| `power` | `logout` `reboot` `shutdown` `confirm` `cancel` | Power actions with confirmation dialog |
| `notification` | `show(...)` `post(summary,body)` `dismiss()` | Notification popups |
| `rightedge` | `toggle` `open` `close` | Right-edge control rail |
| `volumeosd` | `trigger()` | Volume OSD |
| `shell` | `quit()` | Exit the shell (Plasma panels auto-restore) |

### Helper scripts (`scripts/`)

| Action | Script |
| :--- | :--- |
| Toggle dashboard | `scripts/toggle_dashboard.sh` |
| Toggle settings | `scripts/toggle_settings.sh` |
| Toggle active apps overview | `scripts/toggle_overview.sh` (or bare `Meta`, bound by `bind_shortcuts.sh`) |
| Toggle command launcher | `scripts/toggle_launcher.sh` |
| Open wallpaper picker | `scripts/open_wallpaper.sh` |
| Generate wallpaper palette | `scripts/generate_palette.sh` |
| Bind / restore global shortcuts | `scripts/bind_shortcuts.sh` / `scripts/restore_shortcuts.sh` |

### Daemon CLI (`bin/astral-plasma`)

```
run                          Run the full self-contained shell
serve [--port <port>]        REST & Unix-socket API server
extract [target_dir]         Extract the embedded QML theme bundle
session snapshot             Query canonical DesktopSessionSnapshot JSON
omarchy <install|remove|status> Manage hosted Omarchy plugin package
plasma <disable|restore|status|watchdog>
systemd <status|install|remove>
settings [toggle|open|close] Control the Settings GUI via IPC
config write <path> <json>   Atomic configuration persistence
watch                        Event-driven background watcher
visualizer                   Stream real-time audio spectrum/energy JSON
metrics                      Print system metrics JSON
calendar <resolve|open>      Open the default calendar application
workspaces <cmd>             Virtual desktops: query / switch / ensure
preview <window_id>          Capture a live window thumbnail
desktop <install|cleanup>    Manage KWin authorization desktop entries
shortcuts <backup|bind|restore|status>
tray <cmd>                   System tray operations
doctor [--json]              Diagnose all system dependencies
```

---

## 🎨 Customization & Multi-Theming

Configuration lives in `config/` and `theme/`:

- **`config/settings.json`** — shipped defaults. Top-level sections:
  `dock` (width, entries, pinned apps, tray, status icons), `dashboard` (tabs, weather, avatars), `topBar`, `theme` (mode, preset, blur strength, corner radius, dynamic colors), `border`, `plasma` (panel/notification takeover), `debugMode`, `media` (visualizer style).
  Your live settings live in `~/.config/astral-plasma/settings.json` — the only file the shell writes (updated atomically via `astral-plasma config write`).
- **`theme/Theme.qml`** — typography scale, corner radii, borders, shadows, and all motion tokens (M3 Expressive beziers/durations).
- **`theme/Colors.qml`** — Material Design 3 color roles and dynamic palette mappings; plug in presets or wire new schemes here.

> 📖 **[DESIGN.md](DESIGN.md)** is the source of truth for visual design & motion physics, and **[docs/LESSONS.md](docs/LESSONS.md)** documents the deep engineering: liquid-glass materials, concave shoulder fillets, zero-overlap partitioning, and blur-region coverage.

---

## 🛠️ Development & Testing

```bash
make test        # Mandatory before declaring any change done
make test-rust   # Rust unit tests (daemon/tests/)
make test-qml    # Offscreen QML suites via tests/run_qml_tests.sh
```

- **Rust**: domain models, DBus parsing, metric/system parsers, resolvers, and adapters have unit coverage in `daemon/tests/`.
- **QML**: 70+ `tests/tst_*.qml` suites verify geometry (dock corners, fillets, popout borders), animation tokens, auto-close timers, blur extents, IPC wiring, and component boundaries — all headless via `tests/run_qml_tests.sh`.
- **TDD is mandatory**: write a reproducing `tst_*.qml` (or Rust) test first; root-cause fixes only, zero regressions. See [`AGENTS.md`](AGENTS.md) for the full contribution conventions.
- **Visual proof**: unit tests cannot judge translucency or aesthetics — verify UI changes with `spectacle -b -n -o /tmp/screen.png` against realistic content and inspect the result. See [`walkthrough.md`](walkthrough.md) for a worked example (active-apps overview).

---

## 📂 Repository Layout

```
astral-plasma/
├── shell.qml               # Quickshell entry: IPC handlers, per-screen scopes
├── Makefile                # build · run · stop · doctor · test
├── DESIGN.md               # Design system: motion tokens & layout rules
├── AGENTS.md               # Contribution conventions (TDD, architecture)
├── walkthrough.md          # Deep-dive: active apps overview
├── run.sh / install.sh / uninstall.sh
├── shell/                  # Core surfaces: UnifiedShell, UnifiedDock,
│   │                       # UnifiedFrame, TopBar host, CentralDropdown,
│   │                       # CommandLauncher, ActiveAppsOverview, VolumeOsd,
│   │                       # RightEdgeControl, WallpaperLayer, ExclusionZones
│   └── launcher/           # WallpaperCarousel
├── dock/                   # LeftDock, BarRepeater
│   ├── components/         # DockTaskbar, DockClock, DockTray, DockStatusIcons…
│   └── popouts/            # FusedBottomPopout, Audio/Battery/Bluetooth/…
├── dashboard/              # CentralDashboard + tabs (Dashboard, Media,
│   └── tabs/               # Performance, Workspaces)
├── settings_gui/           # SettingsWindow, NexusHub, pages/, controls/
├── components/             # CornerFillet, LiquidGlass*, MaterialIcon,
│                           # VinylPlayer, Heatmap*, LiveWindowThumbnail…
├── services/               # DBus/system services (KWinWorkspaces, WindowService,
│                           # MprisMedia, NetworkService, WallpaperEngine…)
├── notifications/ menus/ topbar/ shortcuts/
├── omarchy/                 # Omarchy hosted plugin package (manifest.json, Service.qml, Bar.qml)
├── theme/                  # Theme.qml (motion tokens), Colors.qml, assets/
├── config/                 # Config.qml, settings.json (shipped defaults)
├── kwin/                   # KWin shortcut script package (bare-Meta overview)
├── scripts/                # Palette, shortcuts, toggle helpers
├── daemon/                 # Rust backend (DDD)
│   ├── src/                # domain/ application/ infrastructure/ interfaces/
│   └── tests/              # Rust unit tests
├── tests/                  # QML offscreen suites (tst_*.qml) + runner
└── docs/LESSONS.md         # Liquid glass, fillets, zero-overlap engineering
```

---

## 📄 License & Credits

- The initial design language is highly inspired by the work of [caelestia-dots/shell](https://github.com/caelestia-dots/shell).
- Licensed under the [MIT License](LICENSE).
