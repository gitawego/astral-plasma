# Astral Plasma — Architecture & Engineering Specification

> Comprehensive architectural reference, design patterns, domain models, and system interactions for **Astral Plasma**.

---

## 1. Executive Summary & Design Vision

**Astral Plasma** is a high-performance, fluid, and multi-compositor desktop shell built with [Quickshell](https://quickshell.outfoxxed.me/) (Qt 6 QML) and a native **Rust daemon**. 

Originally engineered for **KDE Plasma 6 & KWin**, the shell has evolved into a **compositor-neutral desktop environment engine** supporting **Hyprland** and hosted **Omarchy 4.0.x** plugin integration through a strict **Ports-and-Adapters (Hexagonal)** and **Domain-Driven Design (DDD)** architecture.

The design language adapts upstream aesthetic principles from [caelestia-dots/shell](https://github.com/caelestia-dots/shell)—including seamless screen framing, liquid-glass materials, organic concave shoulder fillets, and Material 3 Expressive motion physics—while delivering an extensible, production-grade Linux desktop shell.

---

## 2. High-Level Architecture Overview

Astral Plasma adheres strictly to **Domain-Driven Design (DDD)** and the **Dependency Rule** (all source code dependencies point inwards towards the Domain). Low-level compositor details and protocol objects never cross boundary layers into domain models or UI presentation components.

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                             PRESENTATION LAYER (QML)                            │
│  shell.qml · UnifiedShell · UnifiedDock · CentralDashboard · Popouts · Overlays │
│                                        │                                        │
│                        DesktopSessionFacade (QML Singleton)                     │
└────────────────────────────────────────┬────────────────────────────────────────┘
                                         │ Quickshell IPC / CLI / Unix Sockets
┌────────────────────────────────────────▼────────────────────────────────────────┐
│                             INTERFACES LAYER (Rust)                             │
│  CLI (bin/astral-plasma) · REST API Server · Unix Socket Event Stream (watch)   │
└────────────────────────────────────────┬────────────────────────────────────────┘
                                         │ Calls Application Use Cases
┌────────────────────────────────────────▼────────────────────────────────────────┐
│                             APPLICATION LAYER (Rust)                            │
│  DesktopSessionCoordinator · WindowControlUseCase · WorkspaceControlUseCase     │
│  PlasmaControlUseCase · ShortcutControlUseCase · WineMprisService · Lifecycle   │
└───────────────────┬─────────────────────────────────────────┬───────────────────┘
                    │ Depends on Domain Ports                 │ Emits Domain Events
┌───────────────────▼─────────────────────────────────────────▼───────────────────┐
│                               DOMAIN LAYER (Rust)                               │
│  Entities & Value Objects: DesktopSessionSnapshot · Output · Workspace · Window │
│  Capability · UserIntent · ActionResult · DesktopEvent · WineMediaInfo          │
│  Domain Ports: DesktopSessionPort · WindowManagerPort · WorkspacePort           │
│  OutputPort · FocusPort · PreviewPort · CompositorEffectsPort · TrayPort        │
└───────────────────────────────────▲─────────────────────────────────────────────┘
                                    │ Implemented By Adapters
┌───────────────────────────────────┴─────────────────────────────────────────────┐
│                            INFRASTRUCTURE LAYER (Rust)                          │
│  DesktopFactory (dynamic & config-driven session / compositor detection)        │
│  KWinAdapter (KWin D-Bus, KWin Scripting, ScreenShot2, Plasma Panel Watchdog)   │
│  HyprlandAdapter (Direct UNIX Domain Sockets: .socket.sock & .socket2.sock)     │
│  ProcMetricsAdapter · TrayAdapter · PipeWire Audio DSP · EmbeddedBundle         │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## 3. Layer Responsibilities & Strict Boundaries

### 3.1. Domain Layer (`daemon/src/domain/`)

The Domain layer is the authoritative core of the desktop shell. It contains enterprise business rules, canonical entities, value objects, and domain ports.

**Crucial Invariant:** The Domain layer has **zero dependencies** on external frameworks, I/O libraries, compositor protocols, or other daemon layers (`application/`, `infrastructure/`, `interfaces/`).

Key components:
- **Canonical Ubiquitous Models** (`domain/model.rs`):
  - `DesktopSessionSnapshot`: Immutable, versioned state projection representing displays, workspaces, windows, capabilities, and connection status.
  - `Output`: Display geometry, scale factor, refresh rate, and focus state.
  - `Workspace`: Canonical desktop index, display association, and active status.
  - `Window`: External application window identity, titles, icons, and layout state (`maximized`, `minimized`, `fullscreen`, `floating`).
  - `Capability`: Dynamically queried feature support (`workspaceSwitch`, `backgroundBlur`, `windowPreview`, `globalShortcuts`, `focusRestore`).
  - `UserIntent`: Typed intent request (`focus-workspace`, `activate-window`, `toggle-surface`).
  - `ActionResult`: Typed execution result (`applied`, `pending`, `unsupported`, `unavailable`, `stale`).
  - `DesktopEvent`: Canonical facts emitted during session transitions (`WorkspaceActivated`, `WindowFocused`, `WindowListChanged`, `OutputChanged`).
- **Domain Ports** (`domain/ports.rs`):
  - `DesktopSessionPort`: Query snapshot, capabilities, and execute intents.
  - `WindowManagerPort`: Query, activate, close, or minimize windows.
  - `WorkspacePort`: Query virtual desktops and switch workspaces.
  - `OutputPort`: Enumerate displays and identify focused display.
  - `FocusPort`: Window focus restoration and focus-grab management.
  - `PreviewPort`: Capture live window thumbnail buffers.
  - `CompositorEffectsPort`: Report compositor blur support and modes.
  - `TrayPort`: StatusNotifierItem system tray interactions.

---

### 3.2. Application Layer (`daemon/src/application/`)

The Application layer coordinates domain entities, ports, and external operations to fulfill user tasks. It contains application services, coordinators, and use cases.

Key components:
- **`DesktopSessionCoordinator`**: Coordinates desktop snapshot retrieval, capability validation, and intent execution across active compositor ports.
- **`WindowControlUseCase`**: Orchestrates window focus handoffs, activations, and graceful closures.
- **`WorkspaceControlUseCase`**: Coordinates virtual desktop switching and creation.
- **`PlasmaControlUseCase`**: Manages KDE Plasma panel backup, disabling, and restoration with PID-tracked watchdog protection.
- **`ShortcutControlUseCase`**: Granular snapshotting, binding, and restoring of desktop shortcuts.
- **`WineMprisService`**: Bridges non-native Windows applications (e.g., NetEase Cloud Music running under Wine/Proton) to standard Linux MPRIS D-Bus interfaces.
- **`WatchEvents`**: Event dispatching loop listening to system changes and broadcasting updates to the frontend.

---

### 3.3. Infrastructure Layer (`daemon/src/infrastructure/`)

The Infrastructure layer contains all concrete adapter implementations for interacting with operating system facilities, external D-Bus services, hardware devices, and window managers.

Key components:
- **`DesktopFactory`** (`infrastructure/desktop_factory.rs`):
  - Dynamically detects the active compositor (`KWin` vs. `Hyprland`) and environment profile (`Kde`, `Hyprland`, `Omarchy`).
  - Implements configuration precedence: Command-Line Flags > `settings.json` Config Overrides > Runtime Detection.
  - Instantiates the corresponding port implementations.
- **`KWinAdapter`** (`infrastructure/kwin_adapter.rs`):
  - Connects to KWin via D-Bus (`org.kde.KWin`).
  - Executes KWin ECMAScript scripts for window focus and virtual desktop switching.
  - Captures window previews via KWin's `org.kde.KWin.ScreenShot2` D-Bus interface.
- **`HyprlandAdapter`** (`infrastructure/hyprland_adapter.rs`):
  - Direct UNIX Domain Socket streaming via `std::os::unix::net::UnixStream`.
  - Connects to `$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket.sock` for zero-overhead JSON requests (`j/workspaces`, `j/clients`, `j/activewindow`, `j/monitors`).
  - Listens to `.socket2.sock` for real-time compositor events (`activewindow>>`, `workspace>>`, `openwindow>>`, `closewindow>>`) without polling loops.
- **`ProcMetricsAdapter`**: High-performance `/proc` filesystem parser providing CPU, memory, IO, and network metrics.
- **`PipeWire Visualizer`**: Direct PipeWire PCM audio capture with fast Fourier transform (DSP FFT) emitting physical spectral energy.
- **`EmbeddedBundle`**: Compiles the entire QML shell theme and Omarchy plugin assets directly into the standalone Rust binary (`bin/astral-plasma`).

---

### 3.4. Interfaces Layer (`daemon/src/interfaces/`)

The Interfaces layer provides entry points into the application for human users, scripts, and external tools.

Key components:
- **CLI (`interfaces/cli.rs`)**:
  - `astral-plasma run`: Launches the full self-contained shell environment.
  - `astral-plasma session snapshot`: Queries canonical session snapshot JSON.
  - `astral-plasma omarchy <install|remove|status>`: Manages hosted Omarchy plugin installation.
  - `astral-plasma doctor`: System readiness and dependency diagnosis.
  - `astral-plasma workspaces`, `shortcuts`, `metrics`, `visualizer`.
- **REST / Socket API Server (`interfaces/api_server.rs`)**:
  - Serves an embedded HTTP and Unix domain socket API for external widgets and script integration.

---

### 3.5. Presentation Layer (QML / Quickshell)

The frontend is built using **Quickshell** and **Qt Quick / QML**.

```
shell/
├── shell.qml                     # Root entry point, IPC handlers, screen scopes
├── shell/UnifiedShell.qml        # Core unified desktop surface & frame
├── services/
│   ├── DesktopSessionFacade.qml  # Canonical QML facade singleton
│   ├── WindowService.qml         # Window list and active window state
│   ├── KWinWorkspaces.qml        # Virtual desktops & workspace state
│   ├── MprisMedia.qml            # MPRIS media player arbitration
│   └── NetworkService.qml        # Network and Wi-Fi state
├── dock/
│   ├── LeftDock.qml              # Capsule dock container
│   ├── components/               # Launcher, Taskbar, Clock, StatusIcons, Tray
│   └── popouts/                  # FusedBottomPopout (Audio, Battery, Network, etc.)
├── dashboard/
│   ├── CentralDashboard.qml      # Dropdown dashboard overlay
│   └── tabs/                     # Dashboard, Media, Performance, Workspaces, AI
├── settings_gui/                 # In-shell Nexus Settings Hub
└── omarchy/                      # Hosted Omarchy plugin package
    ├── manifest.json
    ├── Service.qml
    └── Bar.qml
```

- **`DesktopSessionFacade.qml`**: Central singleton acting as the QML presentation facade. It mirrors the canonical `DesktopSessionSnapshot`, checks `capabilities`, tracks `connection` health (`connected`, `degraded`, `disconnected`), and updates reactively without hardcoded compositor checks.
- **Zero-Overlap Partitioning**: Panels and frames are mathematically partitioned to eliminate dark seam artifacts caused by stacked semi-translucent fills.
- **Concave Shoulder Fillets** (`components/CornerFillet.qml`): $C^1$-continuous inverted corner fillets blending vertical panels smoothly into the outer desktop frame.
- **Liquid Motion Physics**: All spatial transitions use Material 3 Expressive beziers with decoupled leading/trailing edge durations (500ms/750ms).

---

## 4. Multi-Compositor & Session Engine

Astral Plasma runs seamlessly across multiple Wayland compositors:

### 4.1. KDE Plasma 6 & KWin (`KdeProfile`)
- **Panel Takeover**: Safely disables KDE Plasma panels via D-Bus on startup and automatically restores original panels on exit.
- **Watchdog Protection**: If the shell process terminates unexpectedly, a detached supervisor watchdog restores the KDE panels immediately.
- **Shortcuts**: Hooks bare `Meta` and global shortcuts through KWin script packages and `KGlobalAccel`.

### 4.2. Hyprland Standalone (`HyprlandProfile`)
- **Direct IPC Socket Stream**: Communicates directly over UNIX domain sockets (`.socket.sock` and `.socket2.sock`) with zero child-process overhead.
- **Dynamic & Persistent Workspaces**: Supports Hyprland's dynamic on-demand workspace creation as well as persistent workspaces (`workspace = X, persistent:true`).
- **Layer-Shell Surface Management**: Manages Quickshell `PanelWindow` layer-shell surfaces with blur rules.

### 4.3. Hosted Omarchy Plugin (`HostedOmarchyProfile`)
- **Single Host Rule**: In an Omarchy environment, `omarchy-shell` is the sole Quickshell host process. Astral Plasma integrates as a plugin rather than spawning a competing root shell.
- **Plugin Manifest & Entry Points**:
  - `manifest.json`: Versioned plugin descriptor conforming to `schemaVersion: 1`.
  - `Service.qml`: Exposes shared Astral actions to the host.
  - `Bar.qml`: Supports dual integration modes:
    - **Widget Mode**: Compact capsule widget embedded into an existing Omarchy bar.
    - **Complete Bar Mode**: Full-featured desktop bar providing launcher, workspaces, active window, clock, and status indicators.
- **Standalone Guard**: `run_self_contained_app()` detects active Omarchy sessions and refuses to launch an independent standalone host beside `omarchy-shell` unless overridden by `ASTRAL_STANDALONE_OVERRIDE=1`.

---

## 5. Physical Data Subsystems

Astral Plasma enforces a strict **anti-fabrication principle**: every visualizer frame, playback status, and metric must represent physical ground truth.

```
                    ┌───────────────────────────────┐
                    │     Physical Audio Source     │
                    │   (PipeWire / PulseAudio)     │
                    └───────────────┬───────────────┘
                                    │ Live PCM Stream
                    ┌───────────────▼───────────────┐
                    │      PipeWire DSP Capture     │
                    │   (pw-record / rust FFT)      │
                    └───────────────┬───────────────┘
                                    │ Real Frequency Bins
┌───────────────────────────────┐   │   ┌───────────────────────────────┐
│     Live Window Capture       │   ├───┤     PipeWire Visualizer       │
│  (KWin ScreenShot2 / PipeWire)│   │   │  (Radial / Speaker / Heatmap) │
└───────────────┬───────────────┘   │   └───────────────────────────────┘
                │ Double-Buffered   │
┌───────────────▼───────────────┐   │   ┌───────────────────────────────┐
│     LiveWindowThumbnail       │   └───┤      Multi-Agent AI HUD       │
│  (Flicker-Free Slot Swap)     │       │   (Real Session Metadatas)    │
└───────────────────────────────┘       └───────────────────────────────┘
```

1. **Physical PipeWire DSP Visualizer**:
   - Audio energy is computed from live PCM streams via PipeWire.
   - When audio is silent, energy reads exactly `0.0` (no synthetic bouncing or fake beats).
2. **Double-Buffered Live Window Previews**:
   - Alternates between round-robin file slots (`preview_<uuid>_0.png` / `_1.png`) to achieve flicker-free thumbnail swapping during overview transitions.
   - Preserves original window aspect ratios using a bounded bounding box (`target_width` × 260px).
3. **Multi-Agent AI Activity HUD**:
   - Detects real developer agent activity (Antigravity CLI/Desktop, Claude Code, Cursor, OpenCode 1/2, Codex, DSH).
   - Monitors active token generation, prompt turnaround durations, and provides automatic sub-10s decay upon task completion.

---

## 6. Configuration Architecture (`config/settings.json`)

Configuration is hierarchical, reactive, and durable:

```json
{
  "session": {
    "compositor": "auto",
    "environment": "auto",
    "integration": "auto",
    "restoreOnExit": true
  },
  "profiles": {
    "kde": {},
    "hyprland": {},
    "omarchyHosted": {},
    "hyprlandStandaloneExperimental": {}
  },
  "dock": {
    "enabled": true,
    "position": "left",
    "width": 64,
    "iconSize": 32,
    "entries": ["launcher", "taskbar", "activeWindow", "tray", "clock", "statusIcons", "settings", "power"]
  },
  "dashboard": {
    "enabled": true,
    "defaultTab": "dashboard",
    "tabs": [
      { "id": "dashboard", "label": "Dashboard", "enabled": true },
      { "id": "media", "label": "Media", "enabled": true },
      { "id": "performance", "label": "Performance", "enabled": true },
      { "id": "workspaces", "label": "Workspaces", "enabled": true }
    ]
  },
  "theme": {
    "mode": "dark",
    "preset": "ocean",
    "blurStrength": 0.85,
    "cornerRadius": 20,
    "dynamicColors": true
  }
}
```

- **Read-Only Defaults**: `config/settings.json` shipped with the repository provides fallback defaults.
- **User Live Configuration**: Stored in `~/.config/astral-plasma/settings.json` and updated atomically via `astral-plasma config write`.

---

## 7. Quality Attributes & Reliability

| Attribute | Architectural Strategy |
| :--- | :--- |
| **Performance** | Native compiled Rust daemon; zero child-process spawn loops; direct UNIX domain socket streams; GPU-accelerated QtQuick scene graph primitives. |
| **Zero Regressions** | Strict Test-Driven Development (TDD); offscreen headless QML unit testing (`qml6`); comprehensive Rust unit tests; mandatory 100% test pass gate before commit. |
| **Fault Tolerance** | Automatic Plasma panel recovery watchdog; graceful degraded state reporting when compositor sockets disconnect; bounded exponential backoff reconnection. |
| **Portability** | Strict Ports-and-Adapters isolation; single codebase running natively on KDE Plasma 6, Hyprland, and Omarchy without duplicating QML presentation trees. |
| **Clean Lifecycle** | All created shortcuts, authorization desktop files, and temporary sockets are cleaned up reversibly on exit. |

---

## 8. Development & Verification Workflow

```bash
# Compile release binary with embedded assets
make build

# Run complete automated verification (Rust unit tests + all 82 QML test suites)
make test

# Launch system dependency and readiness doctor
make doctor

# Test nested Hyprland environment directly inside KDE Plasma
./scripts/test_nested_hyprland.sh
```
