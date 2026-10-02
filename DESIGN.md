# Astral Plasma Design System

> Authoritative specification for the visual design language, motion system, spatial physics, and component architecture of **Astral Plasma**.

---

## 1. Design Philosophy & Vision

Astral Plasma is an expressive, organic, and fluid desktop shell built on **Qt Quick** and **Quickshell** for **KDE Plasma 6**. Inspired by [caelestia-dots/shell](https://github.com/caelestia-dots/shell), its primary visual tenet is **continuous surface integration**:

1. **Continuous Surfaces**: Interfaces avoid floating disconnected rectangles. The desktop boundary, dock capsules, and morphing popouts connect organically with soft inverted corner fillets (`CornerFillet.qml`).
2. **Material 3 Expressive Motion**: Every spatial change, size adjustment, and overlay entrance utilizes Google's Material 3 Expressive easing splines with intentional spring overshoot and physical momentum.
3. **Decoupled Asymmetric Physics**: Elements that move or morph (such as workspace indicators) decouple their leading and trailing edges to simulate liquid surface tension and elastic snap.
4. **Pixel-Perfect Centering & Visual Weight**: All icons, indicators, and glyphs maintain strict bounding box symmetry and balanced visual weight.

---

## 2. Motion System & Animation Tokens

All motion parameters are formalized in [`theme/Theme.qml`](theme/Theme.qml). Never use hardcoded durations or linear easing for UI transitions.

### 2.1. Motion Token Palette

| Token | Duration | Cubic Bezier Spline `[c1x, c1y, c2x, c2y, endX, endY]` | Purpose & Dynamics |
| :--- | :--- | :--- | :--- |
| **`animExpressiveDefaultSpatial`** | 500ms | `[0.38, 1.21, 0.22, 1.0, 1.0, 1.0]` | Large position, size, dropdown, and tab shifts. Has a **21% spring overshoot** for natural elasticity. |
| **`animExpressiveFastSpatial`** | 350ms | `[0.42, 1.67, 0.21, 0.9, 1.0, 1.0]` | Snappy spatial transitions, micro-jumps. Has a **67% spring overshoot**. |
| **`animExpressiveSlowSpatial`** | 650ms | `[0.39, 1.29, 0.35, 0.98, 1.0, 1.0]` | Slow, graceful transitions (large overlays, panels). Has a **29% spring overshoot**. |
| **`animExpressiveFastEffects`** | 150ms | `[0.31, 0.94, 0.34, 1.0, 1.0, 1.0]` | Micro-fades, instant button states, active color changes. |
| **`animExpressiveDefaultEffects`**| 200ms | `[0.34, 0.80, 0.34, 1.0, 1.0, 1.0]` | Opacity fades, dual-text cross-fades, icon swaps. |
| **`animExpressiveSlowEffects`**   | 300ms | `[0.34, 0.88, 0.34, 1.0, 1.0, 1.0]` | Extended dimming, blur transitions. |
| **`curveEmphasizedDecel`**        | 400ms | `[0.05, 0.70, 0.10, 1.0, 1.0, 1.0]` | Elements entering the screen and coming to a smooth rest. |
| **`curveStandard`**               | 300ms | `[0.20, 0.00, 0.00, 1.0, 1.0, 1.0]` | Standard baseline non-spring transitions. |

### 2.2. Standard QML Implementation Pattern

To apply these bezier curves natively in Qt Quick without external physics dependencies:

```qml
Behavior on x {
    NumberAnimation {
        duration: Theme.animExpressiveDefaultSpatial
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Theme.curveExpressiveDefaultSpatial
    }
}
```

For opacity and effect animations:

```qml
Behavior on opacity {
    NumberAnimation {
        duration: Theme.animExpressiveDefaultEffects
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Theme.curveExpressiveDefaultEffects
    }
}
```

### 2.3. Liquid Asymmetric Motion (Elastic Drag & Snap)

When an indicator moves between discrete items (e.g. Workspaces in the Left Dock), it does not move as a rigid block. It stretches along the direction of travel and then snaps into place:

```
Direction: DOWN (Target index > Current index)
Step 1: Leading edge (endY) moves FIRST at standard speed (500ms).
Step 2: Trailing edge (startY) LAGS BEHIND at 1.5x duration (750ms).
Result: The indicator stretches downward like a liquid drop, then snaps shut.

Direction: UP (Target index < Current index)
Step 1: Leading edge (startY) moves FIRST at standard speed (500ms).
Step 2: Trailing edge (endY) LAGS BEHIND at 1.5x duration (750ms).
Result: The indicator stretches upward, then snaps shut.
```

Implementation in `UnifiedShell.qml`:

```qml
onTargetIndexChanged: {
    const movingDown = targetIndex > currentIndex;
    startAnim.duration = movingDown ? 750 : 500;
    endAnim.duration   = movingDown ? 500 : 750;
    wsContainer.startY = targetY;
    wsContainer.endY   = targetY + btnSize;
}
```

---

### 2.4. Decorative Motion Frame Budget

Spatial/interactive transitions above are **never** throttled — they are short,
user-driven, and must stay on the display clock. Continuously running
*decoration* is a different class of motion and must obey a frame budget:

| Rule | Value |
| :--- | :--- |
| Decorative update rate | **`Theme.decorativeMaxFps` = 30 fps** |
| Driven by | `MotionClock` (one shared tick) + `MotionPacer` (phase generators) |
| Forbidden | `NumberAnimation` / `SequentialAnimation` / `RotationAnimation` with `loops: Animation.Infinite` in always-on effects |

Qt Quick repaints the entire window on every property change, and QML animations
advance at display refresh rate (165–240 Hz on modern panels). An uncapped
decorative animation therefore pins the full-screen shell surface to the panel
refresh rate for as long as the effect is active. Decorative pulses, travelling
light packets, ambient glows, slow cover rotations and the AI/download border
effects all run at ≤ 30 fps instead.

Guidelines:

- Declare a `MotionPacer { running: <visibility gate>; period: <ms> }` and bind
  `pulse: pacer.breath` / `travel: pacer.phase`. Never animate the property with
  a looping `NumberAnimation`.
- All decorative effects share one `MotionClock`; never give an effect its own
  pacing `Timer` (N independent 30 Hz timers interleave into N frames per tick —
  measured: two pacers = 60 fps on a 60 Hz output).
- Animate **node opacity / transforms**, not gradient stops, for breathing
glows: legacy `Qt5Compat.GraphicalEffects` regenerate their offscreen source on
  every stop change and cost a second frame per tick.
- Deliver periodic decorative *content* (e.g. the matrix glyph rain) from
  `MotionClock.elapsedMs` instead of a private `Timer`.
- A stopped pacer releases the clock: an idle shell runs zero decorative work.

---

## 3. Component & Layout Architecture

### 3.1. Left Dock Anatomy

The dock (`shell/UnifiedShell.qml`) is organized into dedicated capsule pills separated by visual gaps:

1. **Top Section (`topSection`)**:
   - **Launcher Button**: Capsule with chevron / arrow glyph.
   - **Workspaces Capsule**: Vertical stack of workspace icons (crescent moon, square, circle, dot) with the asymmetric liquid active indicator underneath.
2. **Middle Section (`activeWindowPill`)**:
   - **Active App Icon**: Upright, centered application icon.
   - **Rotated Title Text (`activeTitleRotated`)**: 90° clockwise vertical rotated text using `TextMetrics` eliding and dual-text cross-fading (`titleText1` / `titleText2`) on window focus changes.
3. **Bottom Section (`bottomCol`)**:
   - **Running Apps Capsule (`appsContainer`)**:
     - Pinned applications (with running status dots).
     - Subtle divider line.
     - Unpinned running windows (with active left pill or running dot).
     - A `DockScrollCapsule` that grows into the bar as the app count rises:
       whole-item viewport snapping, capped by the vertical budget so it can
       never grow over the active-window module above it (`activeWindowReserve`)
       or the tray below, with a visible `listGap` in between.
     - Overflow is explicit: a proportional scrollbar thumb, directional end
       chevrons and wheel scrolling. `dock.maxVisibleApps` (> 0) pins an exact
       visible count instead of the automatic fit.
     - The active-window module (app icon + rotated name) lives in the middle
       section whose height is the leftover space; the taskbar budget must reserve
       its content or a long taskbar hides it.
   - **Divider Line**: Subtle horizontal separator.
   - **System Tray & Status Column**:
     - A bare icon column: no card, no rim, no fill. It reads as a secondary
       group purely through size and spacing - glyphs at 62% with tighter gaps -
       and is capped to a third of the vertical budget (scrollable like the
       taskbar) so a crowded tray can never squeeze the app list.
     - Input Method badge (`EN`, `中`, `拼`) rendered in bold high-contrast text.
     - DBus StatusNotifierItem tray icons with hover states and context menus.
     - Stacked clock (Hour over Minute in DemiBold), drawn as bare text: no
       capsule, border or fill of its own.
     - `DockStatusIcons` pill (Wi-Fi, Bluetooth, Battery/Power profile, Power).

### 3.2. Central Dashboard

The Central Dashboard (`dashboard/CentralDashboard.qml` or integrated in `UnifiedShell.qml`):
- **Slide-down Entrance**: Smooth spring descent with `Theme.curveExpressiveDefaultSpatial`.
- **Floating Tab Indicator**: Single sliding rectangle indicator with `Behavior on x` and `Behavior on width` using `Theme.curveExpressiveDefaultSpatial`.
- **Horizontal Sliding Panes**: Tab pages are arranged horizontally in a sliding row (`tabSlider.x`), dynamically resizing the container height with `Theme.curveExpressiveDefaultSpatial`.

### 3.3. Inverted Fillets & Fused Popouts

Popouts (Wi-Fi, Battery, Bluetooth, Context Menus) seamlessly attach to the outer dock margin:
- Use `components/CornerFillet.qml` to render inverted organic curve fillets between the dock edge and popout surface.
- Enter with `Theme.curveExpressiveDefaultSpatial` to give the impression of expanding outward from the dock.

### 3.4. Semantic Button & Interactive Controls System (`PillButton.qml`)

All buttons, action triggers, and capsule controls follow a unified semantic design system governed by **Variants** and **Accents**:

```qml
PillButton {
    label: "Exit Astral Plasma"
    iconText: "exit_to_app"
    accent: "error"      // "primary" | "secondary" | "error" | "warning" | "info" | "success" | "neutral"
    variant: "tonal"     // "tonal" | "filled" | "outlined" | "ghost"
    active: true
    onClicked: Config.exitShell()
}
```

#### 1. Variants (`variant`)
- **`tonal`** *(Default)*: Container fill with high-contrast on-container text (`*Container` / `textOn*Container`) and subtle border (`Qt.alpha(base, 0.40)`). Provides organic depth with optimal legibility.
- **`filled`**: Solid high-emphasis base fill (`base`) with high-contrast on-base text (`textOn*`). Used for focal actions.
- **`outlined`**: Ultra-subtle glass substrate with prominent accent border (`border.color: base`) and accent text.
- **`ghost`**: Completely transparent substrate with accent text, activating subtle glass on hover.

#### 2. Semantic Accents (`accent`)
| Accent | Purpose | Dark Tokens (Fill / Text) | Light Tokens (Fill / Text) | Contrast Ratio |
| :--- | :--- | :--- | :--- | :--- |
| **`primary`** | Default actions, active tabs | `Colors.primaryContainer` / `Colors.textOnPrimaryContainer` | `Colors.primaryContainer` / `Colors.textOnPrimaryContainer` | **$\ge 7.2:1$ (WCAG AAA)** |
| **`secondary`** | Supporting actions | `Colors.secondaryContainer` / `Colors.textOnSecondaryContainer` | `Colors.secondaryContainer` / `Colors.textOnSecondaryContainer` | **$\ge 7.0:1$ (WCAG AAA)** |
| **`error`** / **`danger`** | Destructive actions, Exit, Delete | `#93000A` (`errorContainer`) / `#FFDAD6` | `#FFDAD6` (`errorContainer`) / `#410002` | **$\ge 7.2:1$ (WCAG AAA)** |
| **`warning`** | Cautionary actions, overrides | `#5F4100` (`warningContainer`) / `#FFDEA3` | `#FFDEA3` (`warningContainer`) / `#261900` | **$\ge 7.2:1$ (WCAG AAA)** |
| **`info`** | Inspection, details, refresh | `#004A75` (`infoContainer`) / `#CEE5FF` | `#CEE5FF` (`infoContainer`) / `#001D33` | **$\ge 7.3:1$ (WCAG AAA)** |
| **`success`** | Affirmations, confirmations | `#125222` (`successContainer`) / `#B0F2B2` | `#B0F2B2` (`successContainer`) / `#002107` | **$\ge 7.2:1$ (WCAG AAA)** |
| **`neutral`** | Standard surface utilities | `#2B2930` (`surfaceContainerHigh`) / `#F3EDF6` | `#ECE6F0` (`surfaceContainerHigh`) / `#1D1B20` | **$\ge 12.5:1$ (WCAG AAA)** |

#### 3. Contrast & Architecture Invariants
- **No QML Grammar Collisions**: Colors must never be exposed or read via `Colors.on<Capital>` because QML treats `on...` properties as signal handlers. Always use `Colors.textOn*` or `Colors.m3on*`.
- **Automatic Token Resolution**: `PillButton` dynamically calculates fill, text, border, and hover colors based on `accent`, `variant`, and `isDarkMode`. Explicit overrides (`activeColor`, `activeTextColor`, `activeBorderColor`) are preserved for backward compatibility.
- **Physical Spring Micro-Physics**: Interactive depression scale ($0.95\times$) on press and elevation spring on hover are automatically applied.

---

### 3.5. Settings Pages: Pinned Identity & Zone Rail (`SettingsPage.qml`)

Every settings page roots in [`settings_gui/pages/SettingsPage.qml`](settings_gui/pages/SettingsPage.qml)
and *declares* its identity and its sections; it never draws its own page header:

```qml
SettingsPage {
    title: "Network & Internet"
    subtitle: "Wi-Fi connections, signal strength & network interfaces"
    zones: [
        { id: "wifi", label: "Wi-Fi", anchor: masterPowerCard },
        { id: "networks", label: "Networks", anchor: networksSection }
    ]

    ColumnLayout { /* the page body; SectionHeader marks the zones */ }
}
```

- **Pinned identity**: the hub renders the scaffold's `stickyHeader` *above* the
  scroll area, so the page title, its one-line purpose and the zone rail stay put
  while the content moves. A page therefore repeats its title nowhere in the body.
- **Zone rail**: two or more zones render as `PillButton`s, and the zone the
  reader is in is highlighted. One zone is a title, not navigation - it renders
  no rail.
- **Zones are live state**: a page may compute its `zones` list, so a section
  that is hidden (Wi-Fi off, no app streams) leaves the rail with it. A pill
  never scrolls to a section that is not there.
- **Section headings**: [`components/SectionHeader.qml`](components/SectionHeader.qml)
  marks a zone anchor. Its eyebrow carries the section's live state (counts,
  active preset, install status) - never a decorative index.
- **Section jump**: pressing a pill is a *request to the host*. The page emits
  `zoneRequested(zoneId)`; the hub owns the scroll area, so the hub scrolls -
  smoothly, with the `animExpressive*Spatial` tokens from `Theme`, damped by
  distance (`settings_gui/ScrollMotion.js`), and yielding to the reader the
  instant they wheel or drag. A page never writes a shell global to navigate
  itself: a control that depends on an identifier its own file did not import is
  dead without an error (see `docs/LESSONS.md` §36).

---

## 4. Color & Theming System (Material You)

Astral Plasma uses Material Design 3 color tokens mapped in [`theme/Colors.qml`](theme/Colors.qml):

| Token Name | Description | Default Role |
| :--- | :--- | :--- |
| `surface` | Primary desktop background surface | `#141318` |
| `surfaceContainer` | Base capsule pill background | `#1c1b20` |
| `surfaceContainerHigh` | Hovered buttons, raised surfaces | `#2b2930` |
| `surfaceContainerHighest`| Tooltips, popout dialogs, card backgrounds | `#36343b` |
| `primary` | Accent color, active indicator, switches | `#d0bcff` / dynamic |
| `primaryContainer` | Selected app/tab background | `#4f378b` |
| `onSurface` | High-emphasis text and icons | `#e6e1e6` |
| `onSurfaceVariant` | Medium-emphasis icons, inactive tabs | `#cac4d0` |
| `outlineVariant` | Popout and card borders | `#49454e` |
| `borderSubtle` | Subtle capsule pill borders | `Qt.alpha(Colors.outline, 0.18)` |

Palettes can be dynamically extracted from the user's active wallpaper via `matugen` using [`scripts/generate_palette.sh`](scripts/generate_palette.sh).

---

## 5. Iconography & Centering Rules

1. **Strict Centering**: Every icon must be positioned using `anchors.centerIn: parent` inside a square delegate item (`width: itemSize; height: itemSize`).
2. **Proportions**:
   - Small capsule icons (Wi-Fi, BT, Battery): `size = Math.round(btnSize * 0.58)` to `0.62`.
   - App taskbar icons: `width: root.iconS, height: root.iconS`.
3. **Fallbacks**: Always provide a `MaterialIcon` fallback whenever an application icon path is missing or fails to load.

---

## 6. Design Invariants (Do's and Don'ts)

- **DO** use `Easing.BezierSpline` with `Theme.curveExpressive*` for all UI movements.
- **DO** use dual-text cross-fades when transitioning between titles or labels.
- **DO** clamp dynamic lists (like running apps) so fixed dock elements (tray, clock, power) remain visible on all screen sizes.
- **DON'T** use linear animations or hard transitions for modal/popout appearances.
- **DON'T** use arbitrary padding that displaces icons off-center from their background pill.
