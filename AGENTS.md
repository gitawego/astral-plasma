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

## 3. Repository Map

```
caelestia-kde/
├── AGENTS.md                 # Agent instructions & development conventions (this file)
├── DESIGN.md                 # Design system specification, motion tokens & layout rules
├── README.md                 # Public documentation and setup guide
├── shell.qml                 # Quickshell entry point loader
├── shell/
│   └── UnifiedShell.qml      # Core unified desktop surface (frame, dock, dashboard, popouts)
├── dock/
│   ├── components/           # Dock modules (ActiveWindow, Launcher, Workspaces, Status, Tray)
│   └── popouts/              # Morphing dock popouts (Audio, Battery, Bluetooth, Network, Fused)
├── dashboard/
│   ├── CentralDashboard.qml  # Fullscreen / overlay dropdown dashboard
│   └── tabs/                 # Dashboard tabs (Media, Performance, Workspaces)
├── components/               # Common primitives (CornerFillet, MaterialIcon, LevelBar, Card)
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

## 4. Development & Verification Workflow

### 4.1. Running the Shell
Run the shell in developer mode using the test launcher:
```bash
./run.sh
```
Or run directly via Quickshell:
```bash
quickshell -p /mnt/data/workspace/caelestia-kde
```

### 4.2. Hot Reloading & Diagnostics
Quickshell automatically reloads upon file changes. Monitor the console output or active daemon log for:
- QML syntax or parse errors (`ERROR: Failed to load configuration`).
- Anchor cycles or undefined binding loops.
- DBus service warnings.

### 4.3. Visual Verification
Because Wayland desktop shells cannot be inspected through headless DOM tools, verify all UI changes visually using Spectacle and ImageMagick:
```bash
spectacle -b -n -o /tmp/screen.png && magick /tmp/screen.png -crop 120x1600+0+0 /tmp/dock_crop.png
```
Inspect the resulting image using `view_file` to verify alignment, centering, and contrast.

---

## 5. QML Coding Standards & Best Practices

1. **Explicit Sizing & No Circular Anchors**:
   - Never combine `anchors.fill: parent` with an item whose parent's `implicitHeight` depends on its children.
   - Use `implicitWidth` and `implicitHeight` on custom components.
2. **Bounded Scrolling**:
   - Any dynamic list whose item count depends on user state (e.g. running application windows) MUST be wrapped in a `Flickable` and height-clamped to prevent pushing fixed dock controls off-screen on smaller displays.
3. **Dual-Text Cross-Fading**:
   - For labels that update reactively (such as the active window title), use alternating double `Text` items (`titleText1` / `titleText2`) with opacity cross-fading rather than instant text jumps.
4. **Resilient Icon Resolution**:
   - Always chain app icons: check for raw desktop file / URI path -> query `Quickshell.iconPath()` -> fallback to a Material Symbols icon via `MaterialIcon`.
