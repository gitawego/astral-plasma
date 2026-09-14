# Astral Plasma / Caelestia KDE Design System

> Authoritative specification for the visual design language, motion system, spatial physics, and component architecture of **Astral Plasma / Caelestia KDE**.

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
     - Contained in a `Flickable` with safe `maxAppsHeight` clamping to ensure the dock never overflows regardless of window count.
   - **Divider Line**: Subtle horizontal separator.
   - **System Tray & Status Capsule**:
     - Input Method badge (`EN`, `中`, `拼`) rendered in bold high-contrast text.
     - DBus StatusNotifierItem tray icons with hover states and context menus.
     - Stacked clock (Hour over Minute in DemiBold).
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
