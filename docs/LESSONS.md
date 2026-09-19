# Lessons Learned: Building Highly Custom Desktop Themes (Liquid Glass, Perfect Border Radii & Seamless Drawer Transitions)

> **Context**: Architectural principles, failure modes, mathematical derivations, and hard-earned engineering lessons from developing the Caelestia KDE / Astral Plasma desktop shell (Quickshell, Qt Quick / QML, KWin Wayland).

---

## 1. Why These Problems Are Deceptively Hard

Building a desktop theme with standard rectangular cards is straightforward. Building an **organic liquid glass shell** where floating and docked panels dynamically merge with screen borders, morph between floating and fused states, and maintain optical translucency without artifacts is exceptionally challenging.

During development, hours were spent solving recurring visual glitches that appeared trivial at first glance:
- *"The background is not fully filled into the drawer."*
- *"There is misalignment at the vertical border."*
- *"There is no border radius at the bottom-right corner."*
- *"The drawer deforms during animation."*

This document breaks down the **underlying root causes**, the **false fixes that failed**, and the **definitive architectural patterns** required to build them correctly on the first attempt.

---

## 2. The "Perfect Border Radius" Deep Dive: Concave Inverted Fillets

### 2.1. The Fundamental Confusion: Outer Convex vs. Inner Concave Corners
Standard UI toolkits (including Qt Quick `Rectangle`) only understand **convex outer corners** (`radius`, `topLeftRadius`). 

When a user circles a junction where a popout drawer meets an outer desktop frame and says *"there is no border radius"*, traditional tools fail:
- Applying `radius: 20` to the drawer rounds the outer corners of the drawer box, leaving the junction with the frame as a **sharp 90° corner**.
- The junction requires an **inverted concave fillet (shoulder fillet)** that carves into the empty desktop space, transitioning the vertical stroke of the drawer smoothly into the horizontal stroke of the frame.

```
CONVEX OUTER CORNER (Standard):
      +--------+
     /          \     Standard Rectangle { radius: R }
    |   Card     |    rounds outwards into empty space.
    |            |

CONCAVE INNER FILLET (Liquid Glass Junction):
    |
    |  Drawer Body
    \                 Inverted fillet curves inwards,
     +--------------+ bridging vertical stroke into
       Screen Frame   horizontal border stroke.
```

---

### 2.2. The 5 Traps That Cost Hours of Debugging

#### Trap 1: Inverted Y-Axis in Qt Quick Shapes
In standard Cartesian math ($+Y$ is UP), counter-clockwise rotation moves from angle $0^\circ$ (Right) to $90^\circ$ (Up).
In Qt Quick / screen coordinates, **$+Y$ is DOWN**:
- Angle $0^\circ$ is $(+R, 0)$ (Right)
- Angle $90^\circ$ ($\pi/2$) is $(0, +R)$ (**DOWN**)
- Angle $180^\circ$ ($\pi$) is $(-R, 0)$ (Left)
- Angle $270^\circ$ ($3\pi/2$) is $(0, -R)$ (Up)

If an agent specifies `PathArc.Clockwise` when moving from $(-R, 0)$ (Left) to $(0, +R)$ (Down), Qt draws an outward bulge (convex) or loops around the circle. For an inner concave fillet bridging a vertical line going down into a horizontal line going right, **`direction: PathArc.Counterclockwise` around center $(bodyW + R, height - R)$ is mathematically mandatory**.

#### Trap 2: Stroke-Only Rounding (The Leaking/Missing Fill)
Adding a `PathArc` to the perimeter stroke (Shape 2B) curves the border line, but if the glass fill shape (Shape 1B) still closes with rectangular lines $(bodyW, height) \to (0, height)$, one of two bugs occurs:
1. The translucent fill leaks outside the curved stroke, creating an ugly unbordered glass wedge.
2. The fill cuts inside the arc, leaving the corner under the curve transparent without frosted glass.
**Rule**: The fill `ShapePath` must duplicate the exact `PathArc` coordinates before continuing along the border.

#### Trap 3: The Bounding Box Clipping Trap
If `bottomPopoutSurface` has `width: root.currentPopW + 1`, any concave fillet extending to the right goes to $X = bodyW + R$. If any parent item has `clip: true`, or if layout anchors rely on `width`, the fillet arc is clipped off at the 90° boundary.
**Rule**: Always size the surface wrapper to `width: bodyW + fusedBottomFilletR`.

#### Trap 4: The Connecting Border Step Artifact
When the drawer curves into the bottom border, where does the desktop border line start?
- If `bottomBorder` starts at `currentPopW`, its 1px line runs right through the fillet, creating a stepped cross/corner artifact.
- The horizontal line must start at **$x = \text{root.currentPopW} + \text{popoutFilletR}$**.

#### Trap 5: $C^1$ Continuity (Position AND Slope)
A fillet looks glitchy if there is a slope discontinuity where it meets the straight lines:
- **At start $(bodyW, height - R)$**: $\frac{dx}{dy} = 0 \implies$ Tangent is $(0, 1)$ (purely vertical). Perfectly matches the drawer right border line.
- **At end $(bodyW + R, height)$**: $\frac{dy}{dx} = 0 \implies$ Tangent is $(1, 0)$ (purely horizontal). Perfectly matches the bottom border line.

---

### 2.3. The Complete Geometric Implementation Reference

```qml
// Item container expanded to accommodate the concave fillet
Item {
    id: bottomPopoutSurface
    readonly property real bodyW: root.currentPopW + 1
    readonly property real fusedBottomFilletR: (root.fusedProgress > 0.5) ? currentFilletR : 0

    x: root.dockW - 1
    y: root.popoutY - topR
    width: bodyW + fusedBottomFilletR
    height: root.popoutHeight + topR + botR

    // 1B. Glass Fill Shape (Bottom-Fused)
    Shape {
        ShapePath {
            fillColor: root.glassFill
            startX: 0; startY: 0
            PathLine { x: 0; y: 0 }
            // Top-left shoulder fillet
            PathArc { x: topR; y: topR; radiusX: topR; radiusY: topR; direction: PathArc.Counterclockwise }
            // Top edge to top-right corner
            PathLine { x: bodyW - currentModalR; y: topR }
            PathArc { x: bodyW; y: topR + currentModalR; radiusX: currentModalR; radiusY: currentModalR; direction: PathArc.Clockwise }
            // Right vertical edge down to fillet start
            PathLine { x: bodyW; y: height - fusedBottomFilletR }
            // Bottom-right concave fillet arc
            PathArc {
                x: bodyW + fusedBottomFilletR
                y: height
                radiusX: Math.max(0.1, fusedBottomFilletR)
                radiusY: Math.max(0.1, fusedBottomFilletR)
                direction: PathArc.Counterclockwise
            }
            // Close along bottom and left edge (at x: 1 to prevent double-translucency seam)
            PathLine { x: 1; y: height }
            PathLine { x: 1; y: topR }
            PathLine { x: 0; y: 0 }
        }
    }

    // 2B. Perimeter 1px Stroke (Bottom-Fused)
    Shape {
        ShapePath {
            fillColor: "transparent"; strokeColor: root.borderColor; strokeWidth: 1
            startX: 0; startY: 0
            PathArc { x: topR; y: topR; radiusX: topR; radiusY: topR; direction: PathArc.Counterclockwise }
            PathLine { x: bodyW - currentModalR; y: topR }
            PathArc { x: bodyW; y: topR + currentModalR; radiusX: currentModalR; radiusY: currentModalR; direction: PathArc.Clockwise }
            PathLine { x: bodyW; y: height - fusedBottomFilletR }
            PathArc {
                x: bodyW + fusedBottomFilletR
                y: height
                radiusX: Math.max(0.1, fusedBottomFilletR)
                radiusY: Math.max(0.1, fusedBottomFilletR)
                direction: PathArc.Counterclockwise
            }
            // NO bottom stroke line; NO left stroke line (completely fused)
        }
    }
}
```

---

## 3. The "Seamless Drawer Transition" Deep Dive

### 3.1. The 1px Dark Seam & The False Fix of Pixel-Nudging
When users reported *"there is misalignment of all the drawers"* and *"a vertical line between dock and drawer"*, previous sessions wasted time trying to nudge items by $\pm 1\text{px}$:
- Shifting the drawer $1\text{px}$ to the right ($x = \text{dockW}$) eliminated the dark line but created a **1px transparent gap** where desktop content peeked through.
- Shifting the drawer $1\text{px}$ to the left ($x = \text{dockW} - 1$) closed the gap but created a **1px dark vertical stripe** (luminance dropped from 52 to 40).

#### Why Pixel-Nudging Failed:
The seam is NOT a positional bug. It is a **translucency compositing bug**:
$$\text{Opacity} = 1 - (1 - 0.70) \times (1 - 0.70) = 91\% \text{ dark}$$
Both `dockBg` and `bottomPopoutSurface` were drawing a 70% dark translucent fill over screen pixel column 69.

#### The True Solution: Zero-Overlap Domain Partitioning
- Keep `bottomPopoutSurface.x = root.dockW - 1` so that top fillet strokes start at pixel 69, flush with the dock's 1px border.
- In the drawer's fill path, route the left edge along **local $x = 1$ (screen pixel 70)** for all $y \ge \text{topR}$.
- **Result**: Pixel 69 has exactly 1 layer of `dockBg` fill. Pixel 70 has exactly 1 layer of drawer fill. Luminance across the boundary is perfectly uniform (46–47), and the seam disappears completely.

---

### 3.2. In-Flight Morphing vs. Physical Arrival Latching
A major visual glitch occurs when switching between drawers (e.g. from Wi-Fi in mid-dock to Power at the bottom).

#### The Premature Morphing Glitch:
If `fusedProgress` is computed simply as `Config.bottomPopoutMode === "power" ? 1.0 : 0.0`:
1. The user clicks the Power icon at the bottom of the dock.
2. The active drawer is at $y = 500$ (where Wi-Fi was).
3. The drawer immediately collapses its bottom fillet and flattens its bottom into the fused shape.
4. The flat, bottomless drawer flies downward across 400px of open space, looking completely deformed until it hits the bottom.

#### The Solution: Physical Distance Latching
The drawer must remain in its **floating geometry** (with symmetrical top and bottom concave shoulder fillets) throughout flight, and latch into the fused state **only upon physical arrival**:

```qml
// Distance from current bottom of drawer to screen border
readonly property real popoutDistToBottom: Math.max(0, (root.height - root.borderT) - (fusedBottomPopoutWrapper.y + fusedBottomPopoutWrapper.height))

// Latch condition: must be fused mode, visible, and within 3px of the bottom border
readonly property bool isPopoutAtBottom: isPopoutFusedBottom && Config.bottomPopoutVisible && ((fusedBottomPopoutWrapper.offsetProgress <= 0.01) || (popoutDistToBottom <= 3.0))

property bool isFusedToBottom: isPopoutAtBottom

onIsPopoutAtBottomChanged: {
    if (isPopoutAtBottom) {
        isFusedToBottom = true;
    } else if (!isPopoutFusedBottom || !Config.bottomPopoutVisible) {
        isFusedToBottom = false; // Immediately unlatch when moving to floating icon
    }
}

readonly property real fusedProgress: isFusedToBottom ? 1.0 : 0.0
```

---

### 3.3. Synchronized Content Slide vs. Envelope Expansion
If drawer content is simply anchored inside the drawer wrapper, opening the drawer causes text and buttons to clip awkwardly against the dock edge.

**The Solution**: Asymmetric content shift coupled with envelope clipping:
1. `fusedBottomPopoutWrapper`: Has `clip: true`, width expanding from $0 \to \text{targetWidth}$.
2. `popoutContentContainer`: Has fixed width `fusedPopout.popWidth`, with:
   ```qml
   anchors.leftMargin: (-fusedPopout.popWidth - 5) * (1.0 - fusedBottomPopoutWrapper.offsetProgress)
   ```
3. As `offsetProgress` animates from $0.0 \to 1.0$ via `Theme.curveExpressiveDefaultSpatial`, the glass envelope expands to the right while the content slides out from behind the dock capsule.

---

### 3.4. Dynamic Dock Border Gap Splitting
The dock sidebar has a continuous 1px right border. When a drawer opens, this border cannot run behind the drawer.
- It must dynamically split into an **upper segment** and a **lower segment**:
  - Upper segment: $y \in [\text{topLimit}, \text{popoutGapTop}]$ where $\text{popoutGapTop} = \text{popoutY} - \text{topFilletR}$.
  - Lower segment: $y \in [\text{popoutGapBottom}, \text{bottomLimit}]$ where $\text{popoutGapBottom} = \text{popoutY} + \text{height} + \text{botFilletR}$.
- When fused to bottom (`fusedProgress > 0.5`), the lower segment must be completely hidden (`visible: false`), because the drawer and dock merge all the way into the screen border.

---

## 4. Compositor Blur Architecture for Non-Rectangular Geometries

### 4.1. The Wayland / KWin Limitation
Unlike CSS `backdrop-filter: blur()`, Wayland compositor blur (`BackgroundEffect.blurRegion`) only accepts sets of axis-aligned **rectangular `Region` items**. Passing a non-rectangular item results in no blur or undefined behavior.

### 4.2. The 7-Slice Depth-Tapered Gaussian Approximation
To blur a concave fillet with radius $R = 20\text{px}$, slice the curve into 7 stacked rectangles following $w(y) = R - \sqrt{R^2 - y^2}$:

| Slice | Cumulative Depth ($d_i$) | Slice Height ($h_i$) | Width ($w_i$) | Coverage Zone |
|:-----:|:-----------------------:|:--------------------:|:-------------:|:-------------|
| 1 | 1px | 1px | 17px ($\approx 0.85 R$) | Base of fillet (widest) |
| 2 | 2px | 1px | 13px ($\approx 0.65 R$) | Near base |
| 3 | 4px | 2px | 10px ($\approx 0.50 R$) | Lower curve |
| 4 | 7px | 3px | 7px ($\approx 0.35 R$) | Mid curve |
| 5 | 11px | 4px | 4px ($\approx 0.20 R$) | Upper curve |
| 6 | 15px | 4px | 2px ($\approx 0.10 R$) | Near tip |
| 7 | 20px | 5px | 1px ($1\text{px}$) | Tip of fillet (narrowest) |

- **Zero-Overlap Stacking**: Each slice has $y = \text{baseline} - d_i$ and height $h_i = d_i - d_{i-1}$. Summing heights gives $\sum h_i = d_7 = R$.
- Slices stack seamlessly with zero gap and zero double-blur overlap.

### 4.3. Convex Outer Corners & The Zero-Missing Stepped Staircase Architecture
When blurring convex rounded corners (e.g. radius $R = 20\text{px}$ on `rightControlSurface` or modal drawers) using axis-aligned compositor rectangular regions:

#### The Missing Corner Blur Notch Trap:
A coarse 3-tier blur approximation (`dx = 16, 5, 0`) leaves large triangular voids inside the corner curve:
- At $y = 5\text{px}$, the convex circle boundary is at $x(y) = R - \sqrt{R^2 - (R - y)^2} \approx 6.8\text{px}$.
- If the blur rectangle is inset by $16\text{px}$, a $9.2\text{px}$ wide zone inside the card's glass fill receives **zero blur**.
- Translucent `root.glassFill` ($\alpha \approx 0.22$) directly transmits raw, sharp desktop wallpaper beneath the notch, creating a stark visual defect perceived as "border radius color is not fully filled".

#### The Zero-Missing Stepped Slice Profile:
To guarantee 100% blur coverage inside the curve without noticeable outer overflow, construct a 7-tier stepped slice profile for the corner:

| Vertical Slice Range | Slice Height | Inset ($dx$) | Arc $x(y)$ at Slice Midpoint | Blur Gap Inside Arc |
|:--------------------:|:------------:|:------------:|:----------------------------:|:-------------------:|
| $y \in [0, 1]\text{px}$ | $1\text{px}$ | $15\text{px}$ | $13.8\text{px}$ | $0.0\text{px}$ |
| $y \in [1, 2]\text{px}$ | $1\text{px}$ | $12\text{px}$ | $12.3\text{px}$ | $0.0\text{px}$ |
| $y \in [2, 4]\text{px}$ | $2\text{px}$ | $9\text{px}$ | $9.9\text{px}$ | $0.0\text{px}$ |
| $y \in [4, 7]\text{px}$ | $3\text{px}$ | $5\text{px}$ | $7.1\text{px}$ | $0.0\text{px}$ |
| $y \in [7, 10]\text{px}$ | $3\text{px}$ | $3\text{px}$ | $4.8\text{px}$ | $0.0\text{px}$ |
| $y \in [10, 14]\text{px}$ | $4\text{px}$ | $1\text{px}$ | $2.5\text{px}$ | $0.0\text{px}$ |
| $y \in [14, R]\text{px}$ | $6\text{px}$ | $0\text{px}$ | $0.0\text{px}$ | $0.0\text{px}$ |

- **Zero Missing Pixels**: Guarantees exactly $0.0\text{px}$ of missing blur within the card surface.
- **Diffused Overflow**: The subpixel blur overflow ($< 1.1\text{px}$ average) is seamlessly softened by KWin's dual-kawase filter, completely eliminating both jagged unblurred notches and harsh gray rectangular halos.
- **Hardware Renderer Requirement**: Always enforce `preferredRendererType: Shape.GeometryRenderer` on both fill and stroke shapes on Intel Mesa GPUs to prevent dirty-rect tile caching anomalies.

---

## 5. Anti-Patterns & False Assumptions to Avoid

| Anti-Pattern | False Assumption | Why It Fails | Correct Architecture |
|:---|:---|:---|:---|
| **Pixel Nudging** | "The vertical line is because the drawer is 1px off." | Moving $X$ creates either a 1px desktop gap or a 1px double-translucency stripe. | Zero-overlap fill domain partitioning ($x=1$ for drawer body). |
| **Outer Border Radius** | "Border radius means `Rectangle { radius: 20 }`." | Rounds the outer card corner, leaving the 90° frame junction sharp. | Inverted concave `PathArc.Counterclockwise` fillet. |
| **Instant Shape Flipping** | "If `mode === 'power'`, the drawer is fused." | Morphs drawer shape into a bottomless block while flying mid-air. | Physical arrival distance latching (`popoutDistToBottom <= 3.0`). |
| **1px Top Highlight Bar** | "Glass needs a top specular shine line." | A flat 1px rectangle clips through rounded corners and looks skeuomorphic. | Follow perimeter curve or rely on subtle 1px translucent stroke. |
| **Single Rectangular Blur** | "KWin blur will just blur behind the drawer rectangle." | Leaves the concave shoulder fillets transparent and un-blurred against wallpaper. | 7-slice depth-tapered `Region` approximation. |
| **Test-Only Verification** | "If `tst_*.qml` passes, the UI looks right." | Tests only verify coordinates; they cannot detect 1px dark stripes or optical glitches. | Automated TDD + Wayland screenshot inspection with Python PIL pixel auditing. |

---

## 6. Step-by-Step Recipe for Any New Organic Glass Component

1. **Map Coordinate Domains**:
   - Determine exact screen bounding boxes for all touching components.
   - Ensure every screen pixel is owned by exactly ONE translucent fill shape.
2. **Identify All Junctions**:
   - Classify each corner as convex (outer) or concave (inner fillet).
   - Use `PathArc.Counterclockwise` for concave fillets in screen coordinates ($+Y$ down).
3. **Ensure $C^1$ Continuity**:
   - Verify start tangent matches previous stroke line direction.
   - Verify end tangent matches next stroke line direction.
   - Offset connecting borders so straight strokes start exactly where the arc ends.
4. **Expand Item Bounding Boxes**:
   - Container item `width` / `height` must include the fillet radius ($+R$).
5. **Construct Compositor Blur Regions**:
   - Add 7-slice depth-tapered `Region` items for any non-rectangular curved area.
6. **Implement Arrival Latching**:
   - Decouple target mode from physical fusion state; latch only within $\le 3\text{px}$ of docking border.
7. **Verify via Dual Protocol**:
   - Write offscreen unit tests in `tests/tst_*.qml` asserting geometric invariants.
   - Capture full-screen Wayland screenshots with `spectacle` and audit pixel luminance across seams with Python PIL.

---

## 7. Content-Driven Drawer Heights & Radial Audio Visualizers

### 7.1. The "Empty Void at Bottom" Anti-Pattern
A common pitfall in modal drawers is hardcoding fixed container heights (e.g. `dropH: 520`). When different tabs require differing amounts of vertical space (e.g., Media Tab at 260px vs Dashboard at 360px):
- The shorter tab leaves a massive 100–150px dead black void at the bottom.
- Inner elements float loosely in vertical center alignment with excessive empty margins.

**The Solution**: Dynamic content-driven drawer heights.
1. Let each tab declare its natural `implicitHeight`.
2. In the tab content container, dynamically bind `implicitHeight` to the active tab's pane `implicitHeight`.
3. Ensure all intermediate separators inside `ColumnLayout` declare `Layout.preferredHeight: 1` so layout calculations sum accurately.
4. Bind the drawer's `dropH` to `cardLayout.implicitHeight + Theme.padLarge * 2` with a smooth expressive bezier spline `Behavior on dropH`.
5. Have `UnifiedShell` and `UnifiedFrame` dynamically track `dropdownContainer.dropH` so KWin blur slices and glass perimeter envelopes morph smoothly across tab switches.

### 7.2. Constructing Clean Radial Audio Spectrum Visualizers
Cartoony rainbow notes and chunky bounding handles clutter media interfaces. Upstream Caelestia achieves its signature sleek aesthetic with a radial soundwave halo:
1. **Polar Pill Bars**: 48 radial bars arranged around 360° using rotated items centered at `(centerX, centerY)`:
   ```qml
   Item {
       anchors.centerIn: parent
       rotation: index * (360 / barsCount)
       Rectangle {
           anchors.horizontalCenter: parent.horizontalCenter
           anchors.bottom: parent.top
           anchors.bottomMargin: coverRadius + spacing
           width: 3; height: baseH + barValue * maxH; radius: 1.5
           color: Colors.primary
       }
   }
   ```
2. **MultiEffect Masking Contract**: When masking circular album art with `MultiEffect`, the `maskSource` must NEVER be defined inline within the effect property; it must be a standalone sibling `Rectangle` with `layer.enabled: true` and `visible: false` to guarantee valid GPU texture rendering.
3. **Bespoke Vertical Pill Thumb**: Caelestia's signature slider uses a vertical rounded pill (5x15px, `radius: 2.5`) on a slim 5px track with timestamps positioned neatly below the track.
4. **Tonal Utility Row**: Keep shuffle, player badge pill, and loop buttons in a compact row using `surfaceContainerHigh` tonal backgrounds and dedicated Nerd Font glyphs (`󰒝` for shuffle, `󰑖` for repeat, `󰑗` for repeat_one).

---

## 8. Sliding Drawers, KWin Wayland Blur Artifacts & Dual Visualizers

### 8.1. The Static Blur Region Gray Box Glitch
When building sliding edge controls (such as the right-edge volume/brightness control drawer):
- **The Bug**: During slide-out or slide-in transitions, an opaque or frosted gray square box abruptly appears on screen. When the drawer with rounded corners ($R=20$) slides across it, the sharp 90° square corners of the gray box stick out behind the curved corners of the drawer, and on drawer close, the gray box remains until abruptly vanishing.
- **Root Cause**: KWin Wayland compositor blur regions (`BackgroundEffect.blurRegion: Region { ... }`) only support axis-aligned rectangular boxes. If a blur region declares:
  ```qml
  Region {
      x: rightEdgeControlWrapper.offsetProgress > 0.001 ? (root.width - root.borderT - root.rightControlW) : 0
      width: rightEdgeControlWrapper.offsetProgress > 0.001 ? root.rightControlW : 0
      ...
  }
  ```
  The instant `offsetProgress > 0.001`, KWin applies its blur filter over a full static $60\times 280$ sharp rectangle. The sliding drawer surface travels on top of this static box, producing severe visual clipping artifacts.
- **Definitive Fix**:
  1. Do **not** apply a static KWin blur region to sliding curved drawers. The drawer surface in `UnifiedFrame.qml` (`rightControlSurface`) already renders the liquid glass fill (`color: root.glassFill`, `radius: modalRadius`), delivering smooth translucency without compositor blur stepping.
  2. Smoothly animate the Wayland window input hit-test mask (`mask: Region`) to track the exact drawer slide:
     ```qml
     Region {
         x: Math.round(root.width - root.borderT - root.rightControlW * rightEdgeControlWrapper.offsetProgress)
         width: Math.ceil(root.rightControlW * rightEdgeControlWrapper.offsetProgress)
     }
     ```

### 8.2. Dual Visualizer Architecture & User Choice
When modernizing UI components (such as adopting Caelestia's radial spectrum halo over the original heatmap speaker):
- **Preserve User Choice**: Always retain the original component as a first-class selectable option.
- **Coexistence Slot Pattern**:
  1. Standardize both visualizers to the same geometry slot (`240x240`).
  2. Store selection in `Config.mediaVisualizerStyle` (`"radial"` vs `"speaker"`).
  3. Provide 3 easy ways to toggle:
     - In-tab subtle pill button in the top-right corner of the visualizer (toggles instantly with dedicated disc `󰀥` and speaker `󰕾` glyphs).
     - Segmented Material 3 pill in Settings GUI (`DashboardPage.qml`).
     - IPC commands: `quickshell ipc call media setVisualizer <radial|speaker>` and `quickshell ipc call media toggleVisualizer`.
  4. **CPU Guarding**: Ensure inactive visualizers have `isTargetVisible: ... && visible` so their internal paint timers, canvas redrawing, and spectrum calculations pause when hidden.

### 8.3. Right-Border Edge Drawer Concave Fillets & Seamless Continuity
When building sliding edge drawers on the right screen border (e.g. `RightEdgeControl.qml`):
- **The Gap Bug**: When `rightBorder` is partitioned into upper and lower segments to make room for an open drawer, setting gaps `rightControlGapTop = rightControlY - filletR` and `rightControlGapBottom = rightControlY + rightControlH + filletR` without drawing the matching concave shoulder arcs leaves two visible 20px holes in the right desktop border.
- **The Geometry Solution**:
  1. Expand the surface item `rightControlSurface` to `y: root.rightControlY - root.filletR` and `height: root.rightControlH + root.filletR * 2`.
  2. Top Shoulder Concave Fillet: Start at `startX: currentW, startY: offsetY - activeR` on the right border line, and curve to `(currentW - activeR, offsetY)` with `direction: PathArc.Clockwise`.
  3. Bottom Shoulder Concave Fillet: From `(currentW - activeR, offsetY + h)` curve to `(currentW, offsetY + h + activeR)` with `direction: PathArc.Clockwise`.
  4. Both the liquid glass fill shape and the 1px perimeter stroke must trace this exact path, ensuring $C^1$ position and slope continuity with zero subpixel stepping.

### 8.4. Edge Trigger Ergonomics, Contrast & Accidental Hover Prevention
- **The Window Close Button Hover Trap**: If a hover trigger on the right border (`rightEdgeHoverArea`) has `height: root.height` (1600px), moving the cursor towards the top-right to close a window (`X`), click a maximize button, or drag a window scrollbar accidentally pops out the volume drawer.
  - **Rule**: Never make edge hover triggers span the full screen height. Clamp `y` and `height` to the visual drawer bounds plus a modest travel pad: `y: root.rightControlY - 20`, `height: root.rightControlH + 40`.
  - Match this restricted height in the Wayland `mask: Region` so background windows receive native clicks across the rest of the right border.
- **Knob Icon Contrast (WCAG AA/AAA)**: Never place `#FFFFFF` icons on a pastel `Colors.primary` knob (e.g., `#9bcaff` in dark mode produces an unreadable ~1.5:1 contrast). Always use `Colors.onPrimary` (e.g., `#00325b`), ensuring crisp readability across both dark and light modes.
- **Track Color Balance**: Avoid using `primaryContainer` for the unfilled track background against a `primary` fill, which causes an inverted or confusing appearance. Use `Colors.surfaceContainerHighest` with a 1px `outlineVariant` stroke for a clean frosted capsule.
- **Grace Auto-Close Interval**: 450ms is too fast for natural human mouse travel from the screen edge onto the sliders. Set grace auto-close timers to 850–900ms.

### 8.5. The Backward Line Collision Trap & Edge Drawer Architecture Symmetry
- **The Symptom**: During drawer opening/closing animations, two horizontal white lines appear at the top and bottom of the volume/brightness control drawer, flashing across the width during flight instead of fusing organically into the desktop border.
- **Root Cause (The Backward Line Collision Trap)**:
  In a sliding drawer of expanding width $W$:
  - The shoulder concave fillet sweeps from the screen border line at $x = W$ to $x = W - R_{\text{fillet}}$.
  - The outer convex corner starts at $x = R_{\text{modal}}$ and sweeps to $x = 0$.
  - In a static drawer where $W \gg R_{\text{fillet}} + R_{\text{modal}}$, a horizontal straight line connects them: `PathLine { x: R_modal; y: ... }`.
  - However, during animation when $W < R_{\text{fillet}} + R_{\text{modal}}$ (e.g. $W = 10\text{px}$ while $R_{\text{fillet}} + R_{\text{modal}} = 20 + 20 = 40\text{px}$):
    - The shoulder fillet ends at $x = W - R_{\text{fillet}} = -10\text{px}$ (or clamped at $0$).
    - The naive next point is $x = R_{\text{modal}} = 20\text{px}$.
    - `PathLine` is forced to draw backwards to the right ($dx > 0$), crossing over itself and generating visible horizontal white stroke lines at the top and bottom of the drawer.
- **The Mathematical Clamping Solution**:
  Eliminate the intermediate horizontal segment when the drawer is narrow by dynamically computing effective corner geometry:
  ```qml
  cornerStartX: Math.max(0.0, Math.min(bodyW - topR, currentModalR))
  effectiveModalR: Math.min(currentModalR, cornerStartX)
  ```
  - When $bodyW \le topR$, `cornerStartX` collapses to $0$, and `effectiveModalR` collapses to $0$.
  - The concave shoulder arc transitions directly into the outer corner with zero backward coordinate reversal, guaranteeing $dx \le 0$ at every millisecond of the animation.
- **Architecture Symmetry with Taskbar Dock Drawers**:
  Both the left dock popouts (`fusedBottomPopoutWrapper`) and right edge drawers (`rightEdgeControlWrapper`) now follow the identical two-layer architectural pattern:
  1. **Expanding Clipping Outer Shell**:
     Anchored to the border, expanding its bounding box with `clip: true`:
     ```qml
     x: root.width - root.borderT - root.currentRightW
     width: root.currentRightW
     clip: true
     ```
  2. **Internal Content Sliding Container**:
     Fixed width, sliding smoothly out from behind the screen border:
     ```qml
     anchors.right: parent.right
     anchors.rightMargin: (-root.rightControlW - 5) * (1.0 - offsetProgress)
     ```
  3. **Lockstep Screen Border Splitting**:
     The screen border splits into upper and lower segments whose gap boundaries dynamically reference the drawer surface's fillet radii (`rightControlSurface.topR` and `botR`), ensuring subpixel seam alignment throughout expansion and retraction.

### 8.6. The Double-Alpha Overlap Trap, KWin Wayland Blur Limitations & Domain Partitioning
- **The Symptom**: When an edge drawer opens, a visible vertical line runs down through the glass along the desktop border edge, and the background behind the border strip appears distinctly darker or mismatched. Furthermore, when trying to blur the sliding drawer with compositor blur regions, an aliased 90° gray staircase box with 16px notches pokes out whenever the drawer is close to the border.
- **Root Causes**:
  1. **Double-Alpha Stacking**:
     If the 14px screen border (`rightBorder`) runs behind the drawer while the drawer surface (`rightControlSurface`) also renders translucent `root.glassFill` across the border zone, alpha compounds ($1 - (1 - 0.70)^2 = 0.91$), producing a visible darker vertical stripe.
  2. **The KWin Wayland Blur Region Fallacy**:
     Attempting to blur a sliding drawer using `BackgroundEffect.blurRegion` (e.g., nested inset rectangles) fails fundamentally on Wayland:
     - KWin compositor blur regions are **1-bit binary, axis-aligned rectangular masks**. They do NOT support opacity, anti-aliasing, or arbitrary curve shapes.
     - Compositor blur updates can lag Qt Quick scene graph frame rendering by 1 frame during animations.
     - When the drawer is close to the border ($W < 16\text{px}$), inner inset regions collapse to width 0, leaving a naked, stepped rectangular gray blur box protruding into the desktop with sharp 16px top and bottom notches.
  3. **The False Fix of Cutting Border Gaps with Opacity Fading**:
     Splitting the border background into upper and lower segments while fading the drawer surface with `opacity: filletFactor = W / 20` creates a 280px black hole / transparent cutout in the border whenever the drawer is close to the screen edge.
- **The Definitive Architectural Pattern (Continuous Border + Zero-Overlap Domain Partitioning)**:
  1. **Continuous Border Background Fill**:
     Screen borders must **NEVER** cut gaps in their background fill during drawer animations. The desktop frame's `rightBorder` remains a solid, uninterrupted `Rectangle` (`x: root.width - root.borderT`, `width: root.borderT`, `color: root.glassFill`).
  2. **Subpixel Specular Stroke Splitting**:
     Only the 1px specular line (`borderColor`) splits into upper and lower segments to seamlessly bridge into the drawer's shoulder fillets (`rightControlGapTop` and `rightControlGapBottom`).
  3. **Strict Domain Partitioning for Drawer Surface**:
     The drawer liquid glass fill (`rightControlSurface`) terminates cleanly at the border seam line (`x = bodyW = currentRightW + 1`). It covers only the space inside the screen frame ($x \le \text{root.width} - \text{root.borderT}$), never overlapping the border.
  4. **Pure Liquid Glass for Sliding Edge Controls**:
     Sliding narrow edge controls ($W \le 60\text{px}$) rely exclusively on Qt Quick liquid glass shaders / fills (`root.glassFill` with smooth bezier and arc geometry) without compositor blur regions. This completely eliminates gray boxes, staircase artifacts, and black cutout holes across the entire animation range.

### 8.7. The Generic LiquidGlassCard Architecture (Authentic Liquid Glass on Translucent Panels)
- **The Dual Failure Mode (Opaque Gray Cardboard vs. Empty Wireframe Air)**:
  1. **The Opaque Gray Box Trap**: Setting card/pill backgrounds to a white tint (`Qt.rgba(1.0, 1.0, 1.0, 0.28)`) on dark frosted panels (`Colors.glassSurface`) elevates perceptual lightness to ~50% L*, transforming sleek glass into milky, washed-out chalky plastic blocks.
  2. **The Empty Wireframe Trap**: Setting `color: "transparent"` removes the milky gray, but leaves behind a flat, hollow outline. The user rightly perceives *"I don't see any liquid glass effect on the transparency"* because physical glass is not a wireframe.
- **The Optical Anatomy of Authentic Liquid Glass**:
  Physical glass has thickness, index of refraction (~1.5), and reflective specular bevels. To produce authentic liquid glass in Qt Quick without heavy multi-pass shader overhead:
  1. **Refractive Glass Substrate Gradient**:
     In dark mode, the glass body uses a vertical linear gradient:
     - Top ($y=0.0$): `Qt.tint(Qt.rgba(1.0, 1.0, 1.0, 0.08), Qt.alpha(accentGlint, 0.06))` (ambient light gathering).
     - Mid ($y=0.40$): `Qt.tint(Qt.rgba(1.0, 1.0, 1.0, 0.02), Qt.alpha(accentGlint, 0.02))` (crystalline translucent body).
     - Bottom ($y=1.0$): `Qt.rgba(0.0, 0.0, 0.0, 0.15)` (smoked depth absorption).
     This maintains >85% optical transparency while providing real tactile depth.
  2. **Inner Caustic Ambient Glow**:
     A 28px vertical glow at the top edge (`GradientStop { position: 0; color: Qt.alpha(accentGlint, 0.14) }`, `GradientStop { position: 1; color: "transparent" }`) simulating light entering the glass volume.
  3. **Top Specular Hairline Glare**:
     A 1px horizontal reflection line along the top curved bevel (`anchors.top: parent.top; height: 1`), inset from corners, with a horizontal gradient fading from `transparent` at edges to bright specular in the center (`Colors.glassBorderSpecular`).
  4. **Bottom Inner Rim Catch**:
     A faint 1px reflection along the bottom curved edge (`opacity: 0.20`, `color: Qt.rgba(1, 1, 1, 0.30)`).
  5. **1px Specular / Subtle Rim Stroke**:
     The outer perimeter outline (`border.width: 1`, `border.color: Colors.glassBorderSubtle`).
- **Generic, Reusable Implementation (`LiquidGlassCard.qml`)**:
  - Encapsulated directly as a native `Rectangle` component in [`components/LiquidGlassCard.qml`](file:///mnt/data/workspace/caelestia-kde/components/LiquidGlassCard.qml).
  - Works anywhere a `Rectangle` was used (`radius`, `border`, `color`, `content`, `children` all native).
  - Used by [`components/Card.qml`](file:///mnt/data/workspace/caelestia-kde/components/Card.qml), automatically styling all 6 Dashboard cards and Performance cards.
  - Used in [`shell/UnifiedDock.qml`](file:///mnt/data/workspace/caelestia-kde/shell/UnifiedDock.qml) for the workspace pill (`wsContainer`), running apps taskbar (`appsContainer`), and system tray (`trayContainer`).
  - Used in [`dock/components/DockStatusIcons.qml`](file:///mnt/data/workspace/caelestia-kde/dock/components/DockStatusIcons.qml) for the anchored status icons pill.

### 8.8. Wayland PanelWindow Lifecycle, Dynamic Input Masking, and Drawer Re-entry
- **The Invisible Window Input Trap in Wayland Layer Shell**:
  In Wayland compositors (KWin / wlroots), a `PanelWindow` covering the whole screen (`anchors { top: true; bottom: true; left: true; right: true }`) creates a top-level layer surface.
  1. If `mask: Region` is omitted, the compositor's input hit-test region spans the entire 1920x1080 display.
  2. Setting `visible: false` without dynamic input region masking or setting `WlrLayershell.layer: WlrLayer.Overlay` can leave an invisible surface consuming or blocking pointer events on lower surfaces sharing the `Top` layer (such as `UnifiedShell`).
  3. **The Solution**:
     - Constrain the window's input mask to zero when invisible:
       ```qml
       mask: Region {
           width: Config.settingsVisible ? root.width : 0
           height: Config.settingsVisible ? root.height : 0
       }
       ```
     - Set `WlrLayershell.layer: WlrLayer.Overlay` so modal settings windows never contend with the shell surface.
     - Manage keyboard focus explicitly: `WlrLayershell.keyboardFocus: Config.settingsVisible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None`.
- **Preserving Reactive Bindings against Keyboard Event Overwrites**:
  - In QML, writing directly to a bound property (`root.isOpen = false;`) on keyboard shortcuts (such as `Keys.onEscapePressed`) destroys the declarative reactive binding.
  - Any subsequent state changes on `Config.dashboardVisible = true` fail to propagate to `isOpen`, permanently disabling the drawer.
  - **The Solution**:
     1. Delegate state changes strictly to the single source of truth:
        ```qml
        Keys.onEscapePressed: {
            if (typeof Config !== "undefined") {
                Config.dashboardVisible = false;
            } else {
                root.isOpen = false;
            }
        }
        ```
     2. Reinforce the binding with a declarative `Connections` listener so any re-assignment is automatically restored:
        ```qml
        Connections {
            target: (typeof Config !== "undefined" && Config.dashboardVisible !== undefined) ? Config : null
            function onDashboardVisibleChanged() {
                root.isOpen = Config.dashboardVisible;
            }
        }
        ```
- **Targeted Drawer-Range Top Edge Trigger Architecture**:
  - Covering the entire top border (`width: root.width`) causes unwanted drawer activations whenever the cursor touches the top edge to interact with window titlebars, browser tabs, or close buttons on the left or right of the screen.
  - **The Solution**:
    - Constrain `topEdgeHoverArea` and the top border in `mask: Region` strictly to the horizontal range of the drawer (`x: root.dropX`, `width: root.dropW`, `height: Math.max(root.borderT, 18)`).
    - Use `hoverEnabled: true` so `onEntered: if (Config.dashboardShowOnHover) { closeTimer.stop(); Config.dashboardVisible = true; }` and click via `onClicked: Config.dashboardVisible = !Config.dashboardVisible`.
    - Outside `[dropX, dropX + dropW]`, the top edge passes pointer events cleanly through to underlying windows without triggering or toggling the drawer.
- **The Wayland Input Mask Void Trap on Dynamic Popout Drawers**:
  - **The Symptom**: When hovering a dock icon, the popout drawer opens smoothly, but as soon as the mouse moves from the dock into the drawer, the drawer automatically closes, and clicks on action buttons ("Bring to Front", "Unpin from Dock", "Close Window") pass through to windows beneath the shell.
  - **Root Cause**:
    In Wayland layer shell (`PanelWindow`), pixels outside `mask: Region` are completely transparent to input. The compositor routes mouse events strictly according to the mask. If `mask: Region` omits `fusedBottomPopoutWrapper` (or tests a stale legacy property), the entire popout envelope is a "black hole" to the compositor. The instant the cursor crosses the dock border ($X > \text{dockW}$), the compositor generates an `onExited` event, `popoutCloseTimer` starts, and `HoverHandler` inside the drawer never receives any pointer events.
  - **The Solution**:
    1. **Envelope Masking**: Add `fusedBottomPopoutWrapper` to `mask: Region` whenever `Config.bottomPopoutVisible && offsetProgress > 0.001`, covering the full target width (`fusedPopout.popWidth + filletR`) and height (`height + filletR * 2`).
    2. **Multi-Tier Hover Protection**: Add `HoverHandler` to `popCard` and call `Config.keepBottomPopout()` inside `ActionItem.onEntered` and `appPreviewCard.onEntered`.
    3. **Surface Stacking**: Explicitly set `z: 1000` on `fusedBottomPopoutWrapper` so it stacks evenly with the dock.

---

## 9. The Definitive Engineering Guide to Building the Liquid Glass Theme Correctly

### 9.1. The Optical Anatomy of Authentic Liquid Glass
A fundamental trap when building "glassmorphism" is treating glass as a simple semi-transparent flat gray box (`rgba(255, 255, 255, 0.2)` or `rgba(0, 0, 0, 0.2)`).
- **The Chalky Gray Trap**: Setting an item background to flat translucent white or gray produces a milky, muddy plastic slab that washes out dark desktop wallpapers and looks like untextured cardboard.
- **The Empty Wireframe Trap**: Setting `color: "transparent"` with a 1px border produces a hollow CAD blueprint outline with zero tangible body.

Real physical glass exhibits thickness, refractive index ($n \approx 1.5$), internal caustic transmission, and Fresnel edge reflections. To construct true Liquid Glass in Qt Quick:

```
+-------------------------------------------------------------+  <- 1px Specular Border Bevel (fades to edges)
| \ \ \ \ \  Top Specular Hairline Glare (1px)  / / / / / / / |  <- Ambient light gathering
|-------------------------------------------------------------|
|           Caustic Ambient Glow (28px vertical decay)        |  <- Internal caustic refraction
|                                                             |
|                                                             |
|           Refractive Glass Substrate Gradient               |  <- >85% optical transparency
|           (Subtle tint at top, crystal mid, smoked base)    |
|                                                             |
|                                                             |
|-------------------------------------------------------------|
|              Bottom Inner Rim Catch (1px)                   |  <- Ground bounce reflection
+-------------------------------------------------------------+  <- 1px Subtle Rim Stroke
      ( ( ( ( ( Ambient Contact Drop Shadow ) ) ) ) )            <- Spatial surface separation
```

1. **Ambient Contact Drop Shadow (Layer 0)**:
   - Physical separation from the background. In `LiquidGlassButton.qml` and `LiquidGlassCard.qml`, a Gaussian-blurred or tiered rectangle beneath the glass body provides depth without muddying the transparency.
2. **Refractive Substrate Gradient (Layer 1)**:
   - A vertical linear gradient:
     - Top ($y=0.0$): `Qt.tint(Qt.rgba(1, 1, 1, 0.08), Qt.alpha(accentGlint, 0.06))`
     - Mid ($y=0.40$): `Qt.tint(Qt.rgba(1, 1, 1, 0.02), Qt.alpha(accentGlint, 0.02))`
     - Bottom ($y=1.0$): `Qt.rgba(0, 0, 0, 0.15)`
   - This keeps the core content readable while giving the panel tangible volume.
3. **Inner Caustic Ambient Glow (Layer 2)**:
   - Simulates internal reflections where light enters the curved top bevel. A 28px vertical gradient decaying from `Qt.alpha(accentGlint, 0.14)` to `transparent`.
4. **Top Specular Hairline Glare (Layer 3)**:
   - A 1px horizontal reflection line along the top curved bevel (`height: 1`). Inset from the left and right corners, with a horizontal gradient fading from `transparent` at edges to bright specular in the center (`Colors.glassBorderSpecular`).
5. **Bottom Inner Rim Catch (Layer 4)**:
   - A faint 1px reflection along the bottom curved edge (`opacity: 0.20`, `color: Qt.rgba(1, 1, 1, 0.30)`), simulating ground-bounce light catching the bottom bevel.
6. **Perimeter Stroke (Layer 5)**:
   - A 1px outer outline (`border.width: 1`, `border.color: Colors.glassBorderSubtle`).

---

### 9.2. The Three-Tier Architectural Hierarchy
Never attempt to apply compositor blur uniformly to every layer in the shell. Compositor blur must strictly follow a three-tier hierarchy:

| Tier | Component Type | Example | Visual Strategy | Compositor Blur (`BackgroundEffect.blurRegion`) |
|:---|:---|:---|:---|:---:|
| **Tier 1: Structural Shell** | Outer Frame, Dock Capsule, Popout Drawers | `UnifiedDock`, `UnifiedFrame`, `UnifiedShell` | Material token `root.glassFill` ($\alpha \approx 0.22$), KWin dual-kawase blur, organic shoulder fillets. | **YES** (Must blur raw desktop wallpaper) |
| **Tier 2: Content Cards** | Dashboard Cards, Tab Panes, Dialog Bodies | `LiquidGlassCard`, `Card.qml` | Refractive substrate gradient, caustic glow, specular hairline glare, subtle borders. | **NO** (Inherits blur from Tier 1; nesting blurs causes visual mud & lag) |
| **Tier 3: Micro-Controls** | Buttons, Pills, Segmented Switches, Sliders | `LiquidGlassButton`, `PillButton`, `GlassPill` | Elastic spring physics, contact drop shadows, depression compression ($0.96\times$), specular glints. | **NO** (Pure QML scene graph rendering) |

---

### 9.3. Renderer Architecture: Why `Shape.GeometryRenderer` is Mandatory
When rendering organic glass shapes (curved capsules, concave shoulder fillets, fused drawers) using Qt Quick `Shape`:
- **The `Shape.CurveRenderer` Flaw**:
  Qt Quick's `preferredRendererType: Shape.CurveRenderer` computes bezier arcs in the GPU fragment shader and caches dirty rectangles in GPU scissor tiles. On Intel Mesa GPU drivers (especially with high-refresh displays at 120Hz-240Hz):
  1. Dirty-rect scissor boxes often fail to clear synchronously across consecutive Wayland surface commits.
  2. Sweeping the mouse rapidly over dock icons or drawers causes ghost curve outlines, black flickering rectangular tiles, and leftover border fragments.
  3. Video recorders (running at 60fps) frequently miss these 1-frame glitches, while the human eye sees persistent flashing in realtime.
- **The `Shape.GeometryRenderer` Solution**:
  Enforce `preferredRendererType: Shape.GeometryRenderer` on every `Shape` in the shell:
  ```qml
  Shape {
      preferredRendererType: Shape.GeometryRenderer
      // ...
  }
  ```
  `GeometryRenderer` tessellates path curves directly into vertex buffers (triangles) on the CPU/vertex pipeline and renders them with hardware multisample anti-aliasing (MSAA). It completely eliminates dirty-rect caching bugs, prevents outline ghosting, and maintains smooth 240Hz frame delivery.

---

### 9.4. Compositor Blur Approximation: Concave vs. Convex Slicing
Because Wayland compositors (KWin) only accept sets of axis-aligned **rectangular `Region` masks** for `BackgroundEffect.blurRegion`, curved glass edges must be sliced into staircase approximations.

#### 1. Concave Inverted Fillets (Inner Shoulders, $R = 20\text{px}$):
- Sliced into 7 depth-tapered horizontal rectangles expanding outward:
  $$w(y) = R - \sqrt{R^2 - y^2}$$
- Slice heights: $[1, 1, 2, 3, 4, 4, 5]\text{px}$.
- Each slice starts at the base of the curve and steps inward to meet the straight border.

#### 2. Convex Outer Corners (Card Corners, $R = 20\text{px}$):
- **The Coarse Inset Notch Bug**: Using coarse 3-tier insets ($dx = 16, 5, 0\text{px}$) leaves a triangular gap up to $9.2\text{px}$ wide inside the corner arc with zero blur. Because the glass fill has low alpha ($\alpha \approx 0.22$), raw, sharp wallpaper text ("GAMES", icons) shines through, creating the illusion that the border radius was not filled.
- **The Zero-Missing Staircase Profile**:
  To eliminate unblurred notches without creating harsh gray boxes, use a 7-tier stepped slice profile:
  - $y \in [0, 1]\text{px} \implies dx = 15\text{px}$
  - $y \in [1, 2]\text{px} \implies dx = 12\text{px}$
  - $y \in [2, 4]\text{px} \implies dx = 9\text{px}$
  - $y \in [4, 7]\text{px} \implies dx = 5\text{px}$
  - $y \in [7, 10]\text{px} \implies dx = 3\text{px}$
  - $y \in [10, 14]\text{px} \implies dx = 1\text{px}$
  - $y \in [14, R]\text{px} \implies dx = 0\text{px}$
- **Outcome**: Guarantees exactly $0.0\text{px}$ missing blur inside the glass shape. The tiny subpixel outer overflow ($< 1.1\text{px}$) is naturally diffused into the background by KWin's dual-kawase filter, producing a 100% smooth, gapless frosted glass corner.

---

### 9.5. Translucent Compositing & Zero-Overlap Domain Partitioning
Translucency compositing does not behave like opaque paint. In opaque rendering, overlapping two shapes by 1 pixel hides subpixel gaps cleanly. In translucent rendering:
$$\alpha_{\text{combined}} = 1 - (1 - \alpha_1)(1 - \alpha_2)$$
- Overlapping two $\alpha = 0.22$ layers yields $\alpha = 0.39$—a 77% increase in darkness.
- This creates the dreaded **1px vertical dark seam line** where a drawer touches a dock or frame.
- **The Domain Partitioning Law**:
  Every screen pixel column must belong to **strictly one translucent fill**:
  - Dock capsule fill: screen pixels $X \le 69$.
  - Drawer surface fill: starts at screen pixel $X = 70$ (local $x = 1$).
  - Specular stroke: bridges continuously from $X = 69$ to drawer perimeter.
  - Pixel luminance across the junction remains completely uniform with zero optical seam.

---

### 9.6. Spring Micro-Physics & Organic Glass Interaction Design
Static glass feels synthetic and rigid. Liquid glass should feel fluid, tactile, and responsive:
1. **Elastic Bezier Spring Splines**:
   Replace linear or standard cubic easing with expressive glass spring curves:
   ```qml
   easing.type: Easing.BezierSpline
   easing.bezierCurve: [0.34, 1.56, 0.64, 1] // Theme.curveGlassElastic
   ```
2. **Tactile Depress & Elevation**:
   - Idle state: scale $1.0$, elevation shadow $6\text{px}$.
   - Hovered state: scale $1.02$, elevation shadow $10\text{px}$, glare opacity $+30\%$.
   - Pressed state: scale $0.96$, elevation shadow $2\text{px}$, glare dimming $-20\%$.
3. **Physical Distance Latching**:
   Never trigger shape morphing (e.g. from floating pill to fused panel) based on instantaneous cursor coordinates or logical modes while an element is flying across the screen. Latch morphing **strictly upon physical arrival** ($\text{distance} \le 3\text{px}$) to prevent in-flight deformation.

---

### 9.7. The Universal Checklist for New Liquid Glass Components
Before considering any new liquid glass component complete, verify:
- [ ] **Material Consistency**: Does it use `Colors.glassSurface` or `LiquidGlassCard` rather than hardcoded `rgba(255, 255, 255, ...)`?
- [ ] **Layer Domain Partitioning**: Does the fill avoid overlapping adjacent translucent borders or capsules by even 1px?
- [ ] **Closed Geometry**: Do all `PathArc` and `PathLine` closures meet at $(0, 0)$ without cutting corner fillets?
- [ ] **Hardware Tessellation**: Are all `Shape` items set to `preferredRendererType: Shape.GeometryRenderer`?
- [ ] **Compositor Blur Alignment**: If using `BackgroundEffect.blurRegion`, does the corner use the zero-missing stepped slice profile ($dx \le \text{arc}$)?
- [ ] **Zero Nested Compositor Blur**: Are inner cards and buttons relying on QML scene-graph gradients rather than secondary compositor blur regions?
- [ ] **High-DPI / High-Refresh Verification**: Has the component been verified live on Wayland at native refresh rate (e.g. 240Hz) with full-resolution screenshot auditing?



