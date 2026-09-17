# AGENTS.md

> Guidelines, architecture map, and development conventions for AI coding assistants working in **Astral Plasma / Caelestia KDE**.

---

## 1. Project Overview

**Astral Plasma** is a high-performance, fluid, and expressive desktop shell for **KDE Plasma 6 & KWin** (Wayland / X11), built with [Quickshell](https://quickshell.outfoxxed.me/) and Qt 6 QML.

The design language is adapted from upstream [caelestia-dots/shell](https://github.com/caelestia-dots/shell), featuring a seamless outer screen frame, an organic capsule dock, fluid Material 3 Expressive motion physics, and wallpaper-driven dynamic palettes.

---

## 2. Design System Authority

> [!IMPORTANT]
> **[DESIGN.md](DESIGN.md) is the authoritative source of truth for all visual and motion design.**
> Before modifying or creating any UI components, animations, popouts, or layouts, consult [DESIGN.md](DESIGN.md).
>
> - **Motion Tokens**: All animations MUST use the Material 3 Expressive bezier curves and durations defined in [`DESIGN.md`](DESIGN.md) and [`theme/Theme.qml`](theme/Theme.qml). Hardcoded durations, linear easing, or generic quadratic transitions are forbidden for spatial UI changes.
> - **Centering & Proportions**: Icons and text badges must be strictly centered within their parent bounding boxes (`anchors.centerIn: parent`).
> - **Asymmetric Liquid Physics**: Multi-state indicator transitions (such as workspace pills) must decouple leading and trailing edge durations (500ms / 750ms) as specified in `DESIGN.md`.

---

## 3. Mandatory Test-Driven Development (TDD) & Zero Regressions

> [!CAUTION]
> **CRITICAL MANDATORY RULE: For each modification, you must make sure no regression, so TDD is mandatory.**
> Fixing one issue or adding a feature must NEVER break another existing feature. Every bug fix, refactor, or modification MUST follow strict TDD discipline:
>
> 1. **No Monkey Patching - Root Cause First**:
>    - You must NEVER monkey patch an issue (e.g. hardcoding string checks for specific modes, adding arbitrary pixel offsets, or applying superficial band-aids).
>    - Always investigate deeply to find the true root cause, understand the design architecture (including references like `caelestia-dots/shell`), and implement a clean, proper, and permanent solution.
> 2. **Zero Regressions Guarantee**:
>    - Never consider any task complete without running `make test` and ensuring 100% pass rate across all suites.
>    - For every modification, identify potential regression points (borders, fillets, overlapping panels, auto-hide timers, popout geometries) and verify them with automated tests.
> 3. **Write or Update Tests First**:
>    - For every bug reported, write a reproducing unit test in `tests/tst_*.qml` (for QML/shell behavior) or `daemon/tests/` (for backend/Rust logic) before or alongside the fix.
> 4. **Automated Verification**:
>    - Run `make test` on every change. It runs both the Rust test suite and all QML test suites.
>    - All tests must pass with 0 failures before completing any work.
> 5. **Test Scope Coverage**:
>    - **Backend (Rust Daemon)**: Domain models, DBus error filtering, system metrics parsing, and process resolvers must have full unit test coverage.
>    - **Frontend (QML)**: Geometry calculations, non-overlapping borders, corner fillets, auto-close timers, and component boundaries must have dedicated offscreen QML test suites (`tests/tst_*.qml`).

---

## 4. Absolute Architectural Integrity: Data-Driven, Built-In, No Content Fabrication

> [!IMPORTANT]
> **MANDATORY CORE PRINCIPLES**:
> 1. **Generic, Edge-Case Resilient & Purely Data/Config-Driven**:
>    - All solutions must be architectural, generic, and driven entirely by dynamic system state, audio data, and configuration.
>    - Avoid ad-hoc monkey patches, hardcoded player identities, brittle boolean flipping, or arbitrary pixel offsets.
> 2. **High-Performance & Built-In Primitives**:
>    - Audio visualizers, canvas renders, and animations must be exceptionally performant.
>    - Use built-in Qt Quick primitives, GPU-accelerated items (`Canvas`, `ShaderEffect`, `PropertyAnimation`), and native system facilities rather than CPU-heavy polling loops or uncoordinated subprocesses.
> 3. **NEVER Fabricate or Hard-Code Content**:
>    - You must NEVER fabricate, fake, or synthesize content (e.g. generating synthetic beats with hardcoded 124 BPM math, generating fake audio frequency bands, or guessing playback state with isolated booleans).
>    - Every visualizer frame, beat pulse, and playback status must reflect physical ground-truth (actual PCM audio streaming through PipeWire, DSP spectral flux, and live MPRIS signals). When audio is silent, energy and beats must be purely and cleanly 0.0.

---

## 5. Repository Map

```
caelestia-kde/
├── Makefile                  # Build, test, and run automation (make test, make build, make run)
├── AGENTS.md                 # Agent instructions & development conventions (this file)
├── DESIGN.md                 # Design system specification, motion tokens & layout rules
├── README.md                 # Public documentation and setup guide
├── daemon/                   # High-performance native Rust daemon (DDD architecture)
│   ├── src/                  # Domain, Infrastructure, Application, Interfaces
│   └── tests/                # Rust unit tests (make test-rust)
├── tests/                    # QML & integration test suites (make test-qml)
│   ├── tst_top_drawer_autoclose.qml
│   ├── tst_top_drawer_fidelity.qml
│   ├── tst_dock_corners_geometry.qml
│   └── run_tests.py
├── shell.qml                 # Quickshell entry point loader
├── shell/
│   └── UnifiedShell.qml      # Core unified desktop surface (frame, dock, dashboard, popouts)
├── dock/
│   ├── components/           # Dock modules (ActiveWindow, Launcher, Workspaces, Status, Tray)
│   └── popouts/              # Morphing dock popouts (Audio, Battery, Bluetooth, Network, Fused)
├── dashboard/
│   ├── CentralDashboard.qml  # Fullscreen / overlay dropdown dashboard
│   └── tabs/                 # Dashboard tabs (Media, Performance, Workspaces)
├── components/               # Common primitives (CornerFillet, MaterialIcon, LevelBar, Card, PacmanIcon)
├── services/                 # DBus & system integration (KWinWorkspaces, WindowService, Network)
├── theme/
│   ├── Theme.qml             # Motion tokens, bezier curves, sizing constants, typography
│   └── Colors.qml            # Material Design 3 color roles & dynamic palette mappings
├── config/
│   ├── Config.qml            # Reactive configuration singleton
│   └── settings.json         # User preferences and geometry overrides
└── scripts/
    ├── generate_palette.sh   # Wallpaper-based Material You color extraction via matugen
    ├── toggle_dashboard.sh   # DBus IPC script to trigger dashboard dropdown
    └── toggle_settings.sh    # DBus IPC script to open settings
```

---

## 6. Development & Verification Workflow

### 6.1. Commands (Use Makefile)
Always use `make` commands:
```bash
make test         # MANDATORY: Runs both Rust unit tests and all QML test suites
make build        # Compiles release Rust daemon (bin/caelestia-daemon)
make test-rust    # Runs Rust unit tests
make test-qml     # Runs QML offscreen test suites
make run          # Runs shell with daemon
```

### 5.2. Hot Reloading & Diagnostics
Quickshell automatically reloads upon file changes. Monitor the console output or active daemon log for:
- QML syntax or parse errors (`ERROR: Failed to load configuration`).
- Anchor cycles or undefined binding loops.
- DBus service warnings.

### 5.3. Visual Verification
Because Wayland desktop shells cannot be inspected through headless DOM tools, verify all UI changes visually using Spectacle and ImageMagick:
```bash
spectacle -b -n -o /tmp/screen.png && magick /tmp/screen.png -crop 120x1600+0+0 /tmp/dock_crop.png
```
Inspect the resulting image using `view_file` to verify alignment, centering, and contrast.

---

## 7. QML Coding Standards & Best Practices

1. **Explicit Sizing & No Circular Anchors**:
   - Never combine `anchors.fill: parent` with an item whose parent's `implicitHeight` depends on its children.
   - Use `implicitWidth` and `implicitHeight` on custom components.
2. **Bounded Scrolling**:
   - Any dynamic list whose item count depends on user state (e.g. running application windows) MUST be wrapped in a `Flickable` and height-clamped to prevent pushing fixed dock controls off-screen on smaller displays.
3. **Dual-Text Cross-Fading**:
   - For labels that update reactively (such as the active window title), use alternating double `Text` items (`titleText1` / `titleText2`) with opacity cross-fading rather than instant text jumps.
4. **Resilient Icon Resolution**:
   - Always chain app icons: check for raw desktop file / URI path -> query `Quickshell.iconPath()` -> fallback to a Material Symbols icon via `MaterialIcon`.
