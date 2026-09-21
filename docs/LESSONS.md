# Lessons Learned: Building Highly Custom Desktop Themes (Liquid Glass, Perfect Border Radii & Seamless Drawer Transitions)

> **Context**: Architectural principles, failure modes, mathematical derivations, and hard-earned engineering lessons from developing the Astral Plasma desktop shell (Quickshell, Qt Quick / QML, KWin Wayland).

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
Cartoony rainbow notes and chunky bounding handles clutter media interfaces. The upstream [caelestia-dots/shell](https://github.com/caelestia-dots/shell) design achieves its signature sleek aesthetic with a radial soundwave halo:
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
3. **Bespoke Vertical Pill Thumb**: The upstream signature slider uses a vertical rounded pill (5x15px, `radius: 2.5`) on a slim 5px track with timestamps positioned neatly below the track.
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
When modernizing UI components (such as adopting the upstream [caelestia-dots/shell](https://github.com/caelestia-dots/shell) radial spectrum halo over the original heatmap speaker):
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
  - Encapsulated directly as a native `Rectangle` component in [`components/LiquidGlassCard.qml`](file:///mnt/data/workspace/astral-plasma/components/LiquidGlassCard.qml).
  - Works anywhere a `Rectangle` was used (`radius`, `border`, `color`, `content`, `children` all native).
  - Used by [`components/Card.qml`](file:///mnt/data/workspace/astral-plasma/components/Card.qml), automatically styling all 6 Dashboard cards and Performance cards.
  - Used in [`shell/UnifiedDock.qml`](file:///mnt/data/workspace/astral-plasma/shell/UnifiedDock.qml) for the workspace pill (`wsContainer`), running apps taskbar (`appsContainer`), and system tray (`trayContainer`).
  - Used in [`dock/components/DockStatusIcons.qml`](file:///mnt/data/workspace/astral-plasma/dock/components/DockStatusIcons.qml) for the anchored status icons pill.

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
| **Tier 1: Structural Shell** | Outer Frame, Dock Capsule, Popout Drawers | `UnifiedDock`, `UnifiedFrame`, `UnifiedShell` | Material token `root.glassFill` from `Colors.glassParams` ($\alpha \approx 0.76$, ~24% backdrop transmission), KWin dual-kawase blur, organic shoulder fillets. | **YES** (Must blur raw desktop wallpaper) |
| **Tier 2: Content Cards** | Dashboard Cards, Tab Panes, Dialog Bodies | `LiquidGlassCard`, `Card.qml` | Refractive substrate gradient, caustic glow, specular hairline glare, subtle borders. Alpha is a *definition tint* only ($\alpha \approx 0.28$ effective) - it must never behave as a second opaque glass layer, or the Tier 1 blur below it is extinguished. | **NO** (Inherits blur from Tier 1; nesting blurs causes visual mud & lag) |
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
- [ ] **Blur Mask Atomicity**: Is EVERY dimension of the mask gated by a single boolean, with a positive floor on the body, so the mask is never a degenerate zero-area strip? Does that gate clear *before* the animation ends? Run `tests/tst_blur_region_teardown.qml`.
- [ ] **Zero Nested Compositor Blur**: Are inner cards and buttons relying on QML scene-graph gradients rather than secondary compositor blur regions?
- [ ] **Bounded Composite Luminance**: Does the surface stay legible over the *worst-case* backdrop (white in dark mode, black in light mode)? Run `tests/tst_glass_contrast_contract.qml`.
- [ ] **High-DPI / High-Refresh Verification**: Has the component been verified live on Wayland at native refresh rate (e.g. 240Hz) with full-resolution screenshot auditing?

---

### 9.8. The Glass Contrast Contract: Why a Fixed Alpha Is a Latent Bug
A translucent surface composites over an **arbitrary** wallpaper, so its rendered
luminance is unbounded. Picking an alpha by eye on one wallpaper therefore hides
a two-sided failure that appears on others:
- **Dark mode over a blown-out (white) backdrop**: the plate washes out toward
  the light text, contrast collapses toward $1:1$, and the panel reads as a pale
  gray slab. Text and background become "too close to the same light color."
- **Light mode over a black backdrop**: the mirror problem - a near-white surface
  can no longer carry dark text.

The second failure mode is the subtler one, because the naive fix for the first
(for example raising the dark alpha to $\approx 0.80$) *destroys transparency*:
at that alpha the panel transmits only ~20% of the backdrop, and because KWin's
blur then averages the backdrop to near-flat gray, the remaining transmission
carries no recognisable detail. The result is an opaque slab that no longer
reads as glass at all - the exact complaint "I don't see any transparency."

**The architectural rule.** Glass alphas are not free design parameters; they are
solved, and the solution has two sides that must be satisfied simultaneously:

1. **Legibility floor** - every text token reaches WCAG AA ($4.5:1$) against the
   vibrancy halo over the worst-case backdrop.
2. **Transmission floor** - the plate keeps at least $45\%$ backdrop transmission
   (measured live at $52\%$), and the **plate+card stack** keeps at least $35\%$,
   so compositor blur stays visible through the cards. Below ~$45\%$ the material
   stops reading as glass no matter how correct the alpha math is.

Note that these two floors only coexist because of **text vibrancy** (9.10): at
$52\%$ transmission the plate over a white wallpaper is mid-grey, so unprotected
light text would sit at $\approx 3:1$. The halo, not opacity, is what carries AA.

Four corollaries learned the hard way:

- **Evaluate the STACK, not the layers.** Cards are drawn on top of the plate, so
  the two alphas multiply. A $\alpha = 0.755$ plate under a $\alpha = 0.775$ card
  transmits $(1-0.755)(1-0.775) = 5.5\%$ of the wallpaper - an opaque slab - even
  though each layer validated correctly in isolation. Card alphas must therefore
  be an order of magnitude *below* the plate's. Per 9.2, cards are Tier 2 and
  inherit blur from Tier 1: a card alpha is a definition tint separating the card
  from the plate, not a second load-bearing glass layer.
- **A pure-black substrate buys transmission for free.** Contrast per unit alpha
  is maximized when the substrate is pure black (dark mode) or pure white (light
  mode). A $0.01$ grey substrate costs ~2% transmission at identical legibility,
  so the substrate must stay at exactly $0.0$/$1.0$ and the theme tint must stay
  small ($\le 0.04$ dark) - every point of tint brightens the plate and takes
  contrast away from the light text above it.
- **Darken the substrate, do not raise the alpha.** Contrast scales with
  $(1 - \alpha)\cdot\text{substrate contrast}$; darkening the substrate buys
  legibility *without* costing transmission. Raising $\alpha$ buys the same
  contrast only by giving up the glass.
- **Identify which text actually rides on which layer.** The structural plate
  carries muted text directly (`MediaTab` metadata and the dashboard tab labels
  have no card underneath), so the plate must clear AA for the *dimmer* token,
  not just primary text.
- **A backdrop scrim multiplies with the glass alpha.** A heavy scrim
  ($0.32$) behind an $\alpha = 0.80$ plate leaves $0.198 \times 0.68 \approx 13.5\%$
  of original desktop luminance - roughly a $5\times$ loss of perceived
  transparency. Scrim strength is therefore part of the same contract, bounded
  at $\le 0.15$ (currently $0.08$ dark / $0.06$ light).

All alphas live in the `glassParams` table in `theme/Colors.qml` and are pinned
by `tests/tst_glass_contrast_contract.qml`, which parses that table so parameter
drift fails the suite instead of silently shipping. The suite validates all four
directions: raising an alpha trips a transmission floor, lowering one trips the
legibility floor, an over-transparent card trips the card-distinctness floor
($\Delta \ge 12$ luminance levels, so a card cannot dissolve into the plate), and
card+plate are asserted as a stack rather than independently.

### 9.9. Compositor Blur Strength Is Part of the Material, Not a User Taste
The shell's glass is executed by KWin: `BackgroundEffect.blurRegion` declares
*where* to blur, but KWin's own `BlurStrength` decides *how much*. That makes the
compositor's blur radius a load-bearing parameter of the design, not a cosmetic
preference - and an excessive one silently defeats the transparency work above.

**The failure mode.** KWin's dual-kawase filter at high strength homogenises the
backdrop into a near-flat field. A panel can be perfectly translucent (50%+
transmission, verified against uniform backdrops) and still read as an opaque
slab, because the 50% that passes through carries no recognisable structure.
Measured on this shell's dashboard plate, backdrop structure (std across the top
strip) collapses as strength rises:

| BlurStrength | 1 | 2 | 3 | 6 | 10 |
|:---|:---|:---|:---|:---|:---|
| plate backdrop std | 29.4 | 27.0 | 20.6 | 12.1 | 9.7 |

At strength 10 the plate is flat grey; at 3 the browser toolbar and cards behind
the panel are clearly readable as frosted shapes. **Strength 3 is the default**
(`DEFAULT_STRENGTH` in `infrastructure/kwin_blur.rs`); below ~2 the frosting is so
weak that background text competes with the panel's own content.

**The dead-config trap.** `theme.blurStrength` existed in `settings.json` since
the first commit but was *never applied to KWin* - nothing read it, so KWin kept
its own default and every glass-fidelity change was fighting an invisible
constant. `astral-plasma blur fidelity <0.0-1.0>` now maps that preference onto
KWin's inverted 1-10 scale (1.0 = crispest glass) and reloads the effect, and
`run.sh` applies it at startup. Never store a tunable that no code path applies.

Enforced by `daemon/tests/test_kwin_blur.rs`, which pins the clamp bounds, the
inverted mapping, the KDE-INI round-trip (unrelated `kwinrc` keys must survive),
and asserts the default stays below the diffuse range.

### 9.10. Text Vibrancy: How to Be Transparent AND Legible
Section 9.8's two floors are in direct tension. Legibility wants a high alpha
(opaque surface, predictable contrast); transmissibility wants a low one. Solving
for both by tuning alpha alone bottoms out at roughly $45\%$ transmission - which
is still dark enough to read as a slab, as measured above.

The resolution is to stop treating text legibility and surface opacity as the
same variable. **Protect the glyphs, not the surface:**

- Draw a soft outline under every text item that sits on glass, via Qt's
  `Text.Outline` + `styleColor` (`Colors.glassTextHalo`, mode-aware: dark halo
  under light text, light halo under dark text).
- A glyph's local backdrop is then the *halo*, not the wallpaper. Contrast is
  guaranteed regardless of what the glass transmits, and the plate is free to be
  as transparent as the material wants.

Measured on a pure-white backdrop with a $0.62$ halo, the halo colour is what the
contrast ratio is computed against:

| plate $\alpha$ | transmission | plate grey | halo grey | contrast vs halo |
|:---|:---|:---|:---|:---|
| 0.63 | 37% | 94 | - | 4.66:1 (no halo, marginal) |
| 0.45 | 55% | 140 | 53 | 11.06:1 |
| 0.35 | 65% | 166 | 63 | 9.24:1 |

This is why the plate can run at $\alpha = 0.45$ (52% measured transmission) with
AA text. It is also the authentic technique: real frosted glass is legible because
the light is controlled at the glyph, not because the glass is painted over.

Implementation note: the outline must be applied to **every** Text item on glass,
including ones whose `color:` is a complex expression (the applier script matches
the block, not the colour form), and `MaterialIcon` labels inherit it through
their own `Text` child.

### 9.11. Blur Region Geometry: Why It Desyncs From The Visuals
Symptom: closing a drawer leaves the compositor blur behind, apparently until an
unrelated repaint happens ~1s later.

#### 9.11.1. The architectural root cause: no shared geometry
The instinctive fix is "put the blur and the surface in one parent container and
animate the parent once." That is not possible here, and the reason is the whole
lesson:

> `BackgroundEffect.blurRegion` is **not a visual item**. It is a Wayland protocol
> mask (`ext_background_effect_manager_v1`) - a set of rectangles sent to the
> compositor. It has no scene-graph node, so it cannot be a child of a QML
> container and cannot inherit a transform or animation.

Everything else in the shell animates by moving one item. The blur mask cannot,
so its geometry must be **re-derived** at every point it is used. That duplication
is the defect generator: any expression that disagrees with the surface's real
geometry - by one frame, or by a different rounding, or by crossing zero at a
different threshold - shows up as a mask that is out of step with what the user
sees. When adding a blur region, treat its geometry as a second implementation of
the surface layout and keep the two derived from one shared property, never
recomputed inline per dimension.

#### 9.11.2. The verified defect: dimensions collapsing at different thresholds
The dropdown's regions gated each dimension independently. Width used
`offsetProgress > 0.001`; the body height used
`Math.max(0, currentDropH - filletR)`, which reaches zero at
`offset = filletR / dropH` (0.045 for a 444px drawer). Between those two offsets
the mask handed to the compositor is a **980x0 degenerate strip** - zero area but
non-zero width. Measured on the animated close:

| offset | width gate | height | mask sent |
|:---|:---|:---|:---|
| 0.0600 | 980 | 6.64 | 980x7 |
| 0.0450 | 980 | 0.00 | **980x0** |
| 0.0011 | 980 | 0.00 | **980x0** |
| 0.0009 | 0 | 0.00 | 0x0 |

Because the compositor applies the LAST mask it receives, the degenerate strip is
what persists.

#### 9.11.3. The fix: one gate, positive floor, early teardown
Every dimension of a mask must switch on a **single** boolean, and that boolean
must clear while the animation still has frames left to flush the change:

```qml
readonly property real blurRegionMinProgress: 0.06
readonly property bool blurRegionActive: dropdownContainer.offsetProgress > root.blurRegionMinProgress
readonly property real blurDropH: root.blurRegionActive
    ? Math.max(1, root.currentDropH - root.filletR) : 0
```

The mask is then either a valid positive-area rectangle or fully empty - never a
degenerate strip - and it clears ~30ms (18 frames at 60Hz) before the animation
ends. The identical latent defect existed in three more drawers, each with its own
progress driver; all now use the same single-gate pattern
(`blurPopoutActive`, `blurPopoutFused`, `blurPopoutFloating`,
`blurRightEdgeActive`).

#### 9.11.4. Measurement traps that hid this bug
Two traps cost hours and will mislead anyone re-testing this area:

1. **Screenshot cadence cannot resolve a 500ms animation.** `spectacle` costs
   ~450ms per capture, so even back-to-back burst shots land at ~490ms - after the
   close has already finished and everything correctly reads sharp. Do not
   conclude "not reproducible" from screenshots at this cadence; instrument the
   QML instead (`Connections { function onOffsetProgressChanged() }` logging the
   mask rect) to get the real sequence.
2. **Adding any continuously-repainting element masks the symptom.** A diagnostic
   overlay (or a phase bar) keeps the surface committing frames, which flushes the
   mask change immediately. Every measurement taken with instrumentation on the
   screen was measuring a different system than the one the user sees. Observe the
   idle case with nothing extra on screen.

Also note: absolute pixel energy is a poor blur metric because the backdrop varies
per region. Compare high-frequency energy inside the footprint against control
bands at the same rows, outside it.

#### 9.11.5. Status and how to pin it down on a live session
The degenerate-strip defect is fixed and covered by tests. It does **not** fully
explain a ~1s persistence, and instrumenting the real shell showed the mask
sequence `980x14 -> 0x0` 44ms apart, which is already correct. The remaining
suspicion is the **commit boundary**: a mask update only reaches the compositor
when the surface commits a frame, and the final change lands as the surface is
about to go idle, so the clear may sit uncommitted until something else dirties
the scene. That is consistent with both traps above but is not yet proven.

To confirm on a live session, set `debugMode: true` in your settings file (`~/.config/astral-plasma/settings.json`, or the shipped default `config/settings.json` before the first run). The
shell then logs the exact rect handed to the compositor on every change:

```
[BlurRegion] t=<ms> dropdown=<w>x<h> popout=<on|off> rightEdge=<on|off>
```

Compare the timestamp of the final `dropdown=0x0` line against when the blur
visually disappears. If the log shows `0x0` well before the blur goes, the mask is
being set but not committed, and the fix belongs at the commit boundary rather
than in the geometry.

Enforced by `tests/tst_blur_region_teardown.qml`: a single gate, zero raw-epsilon
dimension tests, a positive height floor, and a non-zero teardown lead time.

> **Qt.tint alpha gotcha**: `Qt.tint(base, Qt.alpha(color, t))` yields an
> effective alpha of $t + \alpha_{\text{base}}(1 - t)$, *not* $\alpha_{\text{base}}$.
> A `0.78` base tinted at `0.10` composites at `0.802`. Any contrast math that
> uses the raw base alpha underestimates opacity by up to 10 points.

---

## 10. Robust Desktop Shell Integration: Cross-Server (XWayland/Wine) Input Injection & Wayland Drawer State Stability

Desktop shell widgets (such as Quickshell media controls, top drawers, and dashboard overlays) frequently need to interact with external non-native desktop applications—specifically legacy X11 applications and Windows applications running via Wine/Proton (e.g., NetEase CloudMusic `cloudmusic.exe`).

Integrating Wayland desktop shells with XWayland/Wine applications introduces unique cross-server edge cases that can completely break desktop UX if not handled with rigorous architectural patterns.

---

### 10.1. The Synthetic Pointer Injection Failure Mode (The "Mouse Jumps to Nowhere" Bug)

#### The Naive Pattern:
A common approach to controlling non-DBus media players is synthetic mouse input:
1. Locate the player window coordinates.
2. Query the current cursor location using `XQueryPointer(dpy, root, ...)`.
3. Use `XTestFakeMotionEvent(dpy, -1, root_x, root_y, 0)` to move the cursor over the play/pause button.
4. Click via `XTestFakeButtonEvent(dpy, 1, 1/0, 0)`.
5. Move the cursor back to the queried coordinates using `XTestFakeMotionEvent(dpy, -1, orig_x, orig_y, 0)`.

#### Why This Catastrophically Fails on Wayland:
1. **The Wayland Coordinate Black Hole**:
   Under Wayland, when the user's cursor is hovering over a native Wayland layer-shell surface (such as Quickshell's top drawer, bottom dock, or dashboard), the X11 server (XWayland) does not own the pointer focus. Calling `XQueryPointer` on the X11 root window returns $(0, 0)$ or stale coordinates from the last time an X11 surface was active.
2. **Violent Cursor Warping**:
   When the code attempts to "restore" pointer coordinates from $(0, 0)$, the user's physical mouse cursor is violently flung across the screen (often to the top-left edge or an arbitrary desktop boundary).
3. **Cascading UI Dismissal (The Closed Drawer Bug)**:
   Quickshell and Qt Quick depend on `HoverHandler` or `MouseArea.containsMouse` to keep ephemeral surfaces open. The moment the cursor is warped away:
   - `containsMouse` immediately turns `false`.
   - Any auto-close timer (e.g. 350ms hysteresis) triggers.
   - The drawer dismisses itself before the user can click any further options or see playback state.
4. **Occlusion & Mis-clicks**:
   If the Wine window is occluded by another window (such as a code editor, terminal, or browser), `XTestFakeButtonEvent` clicks whichever window is physically on top in the X11 stacking order, stealing focus and failing to toggle playback.

---

### 10.2. The Definitive Solution: Targeted Direct Window Keys (`XSendEvent`)

Instead of simulating physical mouse movements and button clicks, route media keystrokes directly into the target window using `XSendEvent`:

```
+-------------------+                      +-----------------------+
| Quickshell / QML  |                      | Wayland Pointer State |
| (Top Drawer Open) |                      | (Unchanged: dx=0,dy=0)|
+---------+---------+                      +-----------------------+
          | IPC
          v
+-------------------+
|   astral-plasma   |
|   Rust Daemon     |
+---------+---------+
          | XSendEvent(KeyPress/KeyRelease, keycode=172)
          v
+------------------------------------------------------------------+
| NetEase CloudMusic Window (win = 0x2a00009, WM_CLASS=cloudmusic) |
|   -> Wine translates X11 KeyPress to WM_KEYDOWN(VK_MEDIA_PLAY)    |
|   -> Operates 100% in background without focus or mouse motion    |
+------------------------------------------------------------------+
```

#### Key Implementation Details:
1. **Direct Window Targeting**:
   Construct an `XKeyEvent` specifically targeted at the Wine client window ID (`win`), with `KeyPressMask` (1) and `KeyReleaseMask` (2):
   ```rust
   let mut press_ev = XEvent {
       xkey: XKeyEvent {
           type_: 2, // KeyPress
           serial: 0,
           send_event: 1,
           display: dpy,
           window: win,
           root,
           subwindow: 0,
           time: 0,
           x: 0, y: 0, x_root: 0, y_root: 0,
           state: 0,
           keycode: 172, // XF86AudioPlay
           same_screen: 1,
       },
   };
   XSendEvent(dpy, win, 1, 1, &mut press_ev);
   ```
2. **Wine Translation to Virtual Keys**:
   Wine's X11 driver maps X11 keycodes directly to Windows Virtual-Key codes:
   - Keycode 172 (`XF86AudioPlay`) $\to$ `VK_MEDIA_PLAY_PAUSE (0xB3)`
   - Keycode 171 (`XF86AudioNext`) $\to$ `VK_MEDIA_NEXT_TRACK (0xB0)`
   - Keycode 173 (`XF86AudioPrev`) $\to$ `VK_MEDIA_PREV_TRACK (0xB1)`
3. **Zero Cursor Displacement**:
   The user's mouse cursor does not move a single pixel ($dx = 0, dy = 0$).
4. **100% Occlusion Tolerance**:
   The player toggles playback instantly even when completely minimized, hidden, or covered by full-screen windows.
5. **No Window Activation**:
   The external player does not steal focus, pop over current work, or disturb active window focus.
6. **No Desktop Hotkey Hijacking**:
   Because the event is sent directly to `win` rather than the X11 root window, desktop hotkey daemons (such as KDE's `kglobalaccel`) do not intercept or swallow the event.

---

### 10.3. Window Resolution on Wayland: The Two-Tier `XQueryTree` & Candidate Scoring Pattern

On Wayland compositors (KWin Wayland), `_NET_CLIENT_LIST` on the root window is only updated when XWayland windows are mapped or activated. Under many desktop states (such as when native Wayland surfaces are active), `_NET_CLIENT_LIST` is empty or missing.

#### The Robust Discovery Strategy:
1. **Tier 1 (Fast Path)**: Read `_NET_CLIENT_LIST` on the root window with `XGetWindowProperty`.
2. **Tier 2 (Fallback via Root Tree)**: If `_NET_CLIENT_LIST` returns 0 items or fails, call `XQueryTree(dpy, root, ...)` to enumerate all child windows of the root window directly from the X server display connection.

#### The Wine 1x1 Helper Window Trap & Candidate Scoring:
A naive search returns the **first** window whose `WM_CLASS` contains `"cloudmusic"`. In Wine/Proton, this almost always fails:
- Every Win32 process spawns dozens of helper X11 windows: 1x1 invisible IME windows (`Default IME`), DDE messaging windows, tooltips (`110x2`), and desktop overlay lyrics.
- If key events are delivered to a 1x1 helper window, the application completely ignores them.
- **The Scoring Metric**:
  1. Filter out all windows with $\text{width} < 200$ or $\text{height} < 200$.
  2. Query `WM_NAME` / `_NET_WM_NAME`. If the window has a non-empty title (e.g. song name `"Song - Artist"`), award a massive title boost ($+10,000,000$).
  3. Add the window area ($\text{width} \times \text{height}$) to the score.
  4. Select the candidate window with the highest score.
  This ensures the main application window (e.g. `0x2a00009` at $1290 \times 779$) is selected 100% reliably.


---

### 10.4. Wayland Ephemeral Drawer Hover & Latching Patterns

When designing hover-activated edge drawers (such as a top drawer that triggers on the top screen border):
1. **Unified Hover Domain**:
   Never rely on separate, non-overlapping `MouseArea` items with gaps between the screen border trigger and the expanded drawer body. An un-hovered gap of even 1 pixel will trigger instant dismissal.
   ```qml
   readonly property bool isDashboardHovered: topTrigger.containsMouse || drawerBody.containsMouse
   ```
2. **Hysteresis Grace Period**:
   Always introduce an exit debounce timer (e.g. 350ms):
   ```qml
   Timer {
       id: closeTimer
       interval: 350
       repeat: false
       onTriggered: {
           if (!root.isDashboardHovered && !root.pinned) {
               root.close();
           }
       }
   }
   ```
   When `isDashboardHovered` turns `false`, start the timer; if `isDashboardHovered` becomes `true` again before timeout, immediately stop the timer.
3. **Keep Drawer Open During External Actions**:
   By using targeted background input injection (`send_window_key`) instead of mouse warping, the cursor remains securely inside the drawer's bounds during media button clicks, keeping `isDashboardHovered` continuously true.

---

## 11. Wine & Legacy X11 System Tray (XEmbed to SNI Proxy) Architecture

### 11.1. The Fundamental Problem: Why Wine Tray Icons Disappear
Modern desktop environments use the **StatusNotifierItem (SNI)** DBus specification (`org.kde.StatusNotifierItem`) for system tray icons.
Legacy applications (such as Wine applications like NetEase CloudMusic `cloudmusic.exe`, WeChat, QQ, or older Java/GTK2 apps) use the legacy **XEmbed system tray protocol** (`_NET_SYSTEM_TRAY_OPCODE`), where the application asks the tray host to dock an X11 `Window`.

To bridge this gap in KDE/Wayland, `/usr/bin/xembedsniproxy` runs in the background:
1. It creates an X11 tray selection window (`_NET_SYSTEM_TRAY_S0`).
2. When a Wine application embeds a tray window, `xembedsniproxy` reparents the window into itself.
3. It exports an SNI DBus service (e.g., `:1.2122` on `/StatusNotifierItem`).

However, this proxy has unique characteristics that break naive SNI parsers:
- `Id` is set to the X11 `WindowId` as a numeric string (e.g. `"33554446"`).
- `IconName` is empty string (`""`).
- `Title` is empty string (`""`).
- **`IconPixmap`** contains the raw RGBA image data (e.g., $20 \times 20$ pixels).
- **`Menu`** property (`com.canonical.dbusmenu`) is completely absent because menus are handled internally by Wine via X11 events.

---

### 11.2. Trap: The Order-of-Operations Filtering Trap
In naive tray implementations, developers add a ghost/dummy item filter:
```rust
// FATAL FLAW: Evaluated BEFORE pixmap extraction!
if item_id.chars().all(|c| c.is_ascii_digit()) && item_icon.is_empty() && item_title.is_empty() {
    continue; // Throws away every XEmbed and Wine application!
}
```
Because `xembedsniproxy` provides neither `IconName` nor `Title`, this filter triggers immediately, discarding the tray item **before `sni_get_pixmap` is ever called**.

#### The Correct Order of Operations:
1. Read `Id`, `IconName`, `Title`, `ToolTip`.
2. Sanitize and clear error strings (`starts_with("Error")`).
3. **Extract `IconPixmap` and write cached PNG**.
4. **Resolve desktop icon** (`resolve_desktop_icon`).
5. **Resolve XEmbed identity** for numeric IDs (`resolve_xembed_identity`).
6. **Only now apply ghost filtering**: Drop the item only if after pixmap extraction and identity resolution it *still* has no icon and no title.

---

### 11.3. Resolving Real Identity for Wine Applications
The XEmbed tray window (`0x200000e`) does NOT belong to `cloudmusic.exe`—it is owned by Wine's internal desktop manager, `explorer.exe` (`WM_CLASS = "explorer.exe"`).
If an agent only inspects `WM_CLASS` of the docked window, it sees `explorer.exe`.

#### The 3-Tier Discovery Pipeline:
1. **Tier 1 (`_NET_CLIENT_LIST`)**: Enumerate active client windows on the root window. Find any window whose `WM_CLASS` ends in `.exe` (case-insensitive) excluding Wine system daemons (`explorer.exe`, `services.exe`, `winedevice.exe`, `svchost.exe`, `plugplay.exe`, `rpcss.exe`, `conhost.exe`).
2. **Tier 2 (`XQueryTree`)**: If the client window was minimized to tray and removed from `_NET_CLIENT_LIST`, traverse child windows of the root window via `XQueryTree`.
3. **Tier 3 (`/proc` Cmdline Scan)**: If the window is unmapped, scan `/proc/[0-9]*/cmdline` for `.exe` processes to identify the running Wine application.

#### Metadata Normalization:
- If `.exe` is detected:
  - `"cloudmusic"` $\to$ `id = "cloudmusic"`, `title = "NetEase Cloud Music"`, `material_icon = "music_note"`.
  - `"wechat"` $\to$ `id = "wechat"`, `title = "WeChat"`, `material_icon = "chat"`.
  - Generic `.exe` $\to$ strip `.exe`, capitalize name, default `material_icon = "widgets"`.
- If window title exists (e.g. current song `"Song - Artist"`), preserve it as the tooltip!

#### Essential X11 Safety Guard:
If `win_id == 0` or if a window was closed between query steps, calling `XGetWindowProperty` triggers Xlib's default error handler, terminating the entire daemon process with `BadWindow`.
- Guard against `win_id == 0` before any X11 property call.
- Always install a non-terminating error handler:
  ```rust
  unsafe extern "C" fn x11_silent_error_handler(_dpy: *mut libc::c_void, _event: *mut libc::c_void) -> libc::c_int { 0 }
  XSetErrorHandler(Some(x11_silent_error_handler));
  ```

---

### 11.4. Context Menu Coordinate Routing (The Exit Option Trap)
Because Wine applications lack `com.canonical.dbusmenu`, right-clicking their tray icon cannot open a QML popout menu.
Instead, they implement `org.kde.StatusNotifierItem.ContextMenu(int x, int y)`.

When `ContextMenu` is called:
1. `xembedsniproxy` delivers an X11 button press event to the Wine tray window.
2. Wine spawns a native Win32 popup menu window (`0x2a0001a`) on the X11 display containing buttons like "Previous", "Play", "Next", and crucially, **"退出 / Exit"**.
3. **The Coordinate Bug**: If `(0, 0)` is passed to `ContextMenu`, Wine positions the popup menu at `(0, 0)` (top-left of the monitor) or offscreen.
4. **The Solution**:
   - In QML (`UnifiedDock.qml`), map delegate coordinates to the root screen:
     ```qml
     const globalPt = trayDelegate.mapToItem(null, mouse.x, mouse.y);
     WindowService.contextMenuTray(modelData.service, modelData.path, globalPt.x, globalPt.y);
     ```
   - In the CLI daemon (`astral-plasma tray context-menu`), if `x == "0" && y == "0"`, automatically query the real cursor position via `XQueryPointer`:
     ```rust
     if x == "0" && y == "0" {
         if let Some((cx, cy)) = crate::infrastructure::x11_input::get_cursor_position() {
             x = cx.to_string();
             y = cy.to_string();
         }
     }
     ```
This ensures context menus consistently appear directly beneath the cursor, allowing users to exit Wine applications reliably.

---

### 11.5. Generic Synthetic Declarative Menus for Wine and Non-DBusMenu Apps
Even native KDE Plasma 6 does not theme Wine tray menus because Win32 applications create in-process popup menus via `TrackPopupMenuEx` or Chromium/CEF custom windows without exposing DBusMenu endpoints.

To provide a first-class, themed experience in Astral Plasma:
1. **The Synthetic Menu Path (`/SyntheticMenu`) Paradigm**:
   - In `tray_adapter.rs`, when `query_tray()` detects an SNI item with an empty or non-existent `menu_path`, it automatically assigns `menu_path = "/SyntheticMenu".to_string()`.
   - This notifies `UnifiedDock.qml` and `FusedBottomPopout.qml` that the item supports rich interactive popouts without special-casing inside QML.
2. **Declarative Menu Synthesis with Multi-Level Submenus**:
   - In `fetch_menu()`, queries to `"/SyntheticMenu"` return a structured JSON action tree with `hasSubmenu: true`, Material You icon identifiers, and `children: [...]`.
   - For media players (e.g. NetEase CloudMusic, QQMusic, Spotify), the menu automatically exposes:
     - `Playback Controls` (Play/Pause, Next Track, Previous Track)
     - `Window Options` (Show/Minimize, Open Native Win32 Menu fallback)
     - `Exit <App Name>` (styled with `#ffb4ab` soft red warning tint)
   - For generic Wine applications, it exposes clean window control, native context menu trigger, and application termination.
3. **Dual-Layer Sliding Transition Reusability**:
   - Because `FusedBottomPopout.qml` implements a generic dual-layer sliding engine (`layerA` $\leftrightarrow$ `layerB` with `pushSubmenu` and `popSubmenu`), synthetic submenus slide smoothly with breadcrumb navigation and item count badges without requiring any custom QML per application.
4. **Targeted Process Termination**:
   - Win32 applications running under Wine often exit only via their tray icon. When synthetic item `1006` ("Exit") is clicked, `tray_adapter.rs` resolves the specific client `.exe` PID from the SNI service metadata, cleanly terminating only the target executable without disrupting `xembedsniproxy` or other active Wine bottles.

---

### 11.6. Input Method (Fcitx5 / Rime) Active State & Instant Tray Refresh Architecture
When selecting an input method like Rime from an SNI DBusMenu:
1. **The Inactive State Trap**:
   - Sending DBusMenu Event `clicked` changes Fcitx5's profile item, but leaves Fcitx in **State 1 (Inactive)** unless the calling window has an active input context. In State 1, all keys bypass IME engines, causing the user to type in English even though Rime was clicked.
   - **Fix**: In `tray_adapter.rs` `click_item()`, detect Fcitx selections:
     - For Chinese IMEs (`rime`, `pinyin`), explicitly execute `fcitx5-remote -s <im>` and `fcitx5-remote -o` (activate state 2).
     - For English layouts (`keyboard-us`), execute `fcitx5-remote -s keyboard-us` and `fcitx5-remote -c` (deactivate state 1).
2. **The Text Badge vs Themed Icon Collision**:
   - `UnifiedDock.qml` previously displayed a text badge `imBadgeText` whenever `imBadge` was non-empty, which hid the underlying icon. For English, `"EN"` is desirable; but for Rime, users expect the iconic Rime square seal (`fcitx-rime.svg`).
   - Setting `im_badge = ""` for Rime allows `ThemedIcon` to render `/usr/share/icons/breeze-dark/status/22/fcitx-rime.svg`, automatically colorizing the symbolic vector with Material You surface colors.
3. **Instant Responsive Refresh via DBus**:
   - Rather than relying on a slow background polling loop (5000ms), `WatcherService` exposes `RefreshTray` over DBus.
   - When any menu item click completes, `qdbus6 org.astralplasma.WindowWatcher /Watcher RefreshTray` is triggered immediately, refreshing the dock and popout within milliseconds.

---

### 11.7. Wayland Modal Dialog Input Masking & Authentic Liquid Glass Dialogs
When presenting full-screen modal confirmation dialogs (Shutdown, Reboot, Log Out) on Wayland:
1. **The Modal Input Mask Void Trap**:
   - In Wayland Layer Shell (`PanelWindow`), pointer input is strictly limited to the bounding geometries declared in `mask: Region`.
   - If a shell surface spans the entire display ($1920\times1080$ or $2560\times1600$) with a restricted input mask (dock + screen borders), rendering a centered modal dialog inside that surface without expanding the mask leaves the dialog in an **input void**.
   - Pointer clicks fall straight through the dialog card and buttons to underlying application windows or the desktop.
   - **Fix**: In `UnifiedShell.qml`, conditionally expand `mask: Region` to cover the full screen whenever a modal dialog is active:
     ```qml
     Region {
         x: 0; y: 0
         width: PowerService.confirmDialogVisible ? root.width : 0
         height: PowerService.confirmDialogVisible ? root.height : 0
     }
     ```
     This ensures all clicks on action buttons and the surrounding backdrop scrim are cleanly received, while collapsing to $0\times0$ when hidden.
2. **Backdrop Compositor Dual-Kawase Blur Integration**:
   - Modal dialogs should dynamically register their card bounding box (`cardX`, `cardY`, `cardW`, `cardH`) in `BackgroundEffect.blurRegion`.
   - This routes the area behind the dialog card through KWin's dual-kawase blur filter, eliminating sharp wallpaper text and providing authentic frosted glass optics.
3. **The 6-Layer Liquid Glass Modal Optical Stack**:
   - Real glass is not an opaque flat box. A modal dialog in Astral Plasma must incorporate:
     - **Layer 0**: Ambient Contact Drop Shadow (`MultiEffect` blur 48px, vertical offset 12px, `Colors.glassShadowColor`).
     - **Layer 1**: Refractive Glass Substrate Gradient (`Qt.tint(rgba(1, 1, 1, 0.09), alpha(accent, 0.06))` to smoked absorption).
     - **Layer 2**: Inner Caustic Ambient Glow (top 38px vertical gradient decaying from `alpha(accent, 0.22)` to transparent).
     - **Layer 3**: Dual-Layer Top Specular Hairline Glare (1px horizontal reflection line along the top curved bevel).
     - **Layer 4**: Bottom Inner Rim Catch (1px subtle reflection along the bottom curved edge).
     - **Layer 5**: Perimeter Specular Bevel Stroke (`border.color: Colors.glassBorderSpecular`).
     - **Layer 6**: Dynamic Specular Cursor Glint (220px soft radial highlight tracking cursor position).
4. **Dynamic Perceptual Contrast for Semantic Buttons**:
   - Session actions use diverse dynamic Material You accents: error red (`#BA1A1A` / `#D32F2F`) for Shut Down, primary violet (`#6B4FA0`) for Restart/Log Out.
   - Relying on generic container tokens can cause dark navy text (`#003353`) on red backgrounds.
   - By calculating perceptual luminance ($L = 0.299R + 0.587G + 0.114B$), buttons dynamically set foreground text and icons to `#FFFFFF` for dark/medium accents and `#1D1B20` for light accents, guaranteeing 100% WCAG AAA contrast ratio.

---

## 12. Application Identity Resolution: Data-Driven, Never Substring-Guessed

### 12.1. The Symptom
A running ZCode AppImage showed up in the dock as a **second VS Code icon** - wrong
name, wrong icon, wrong id - so the user could not find their own window. The app
was never missing from the window list; it was mislabelled.

### 12.2. Root Cause: A Curated Substring Table
`resolve_window_meta` (now `meta_resolver.rs`) decided identity with ~38 hardcoded
`cls.contains("keyword")` tests. KWin reported the window class as `zcode`, and:

```rust
if cls_lower.contains("code") {   // "zcode".contains("code") == true
```

matched, so the ZCode window was dressed as VS Code before anything ZCode-aware
could ever run.

This is structural, not a one-off typo. Auditing that table against the 327
desktop entries installed on this machine found **23 patterns that are substrings
of other, distinct applications**:

| pattern | also swallows |
|:---|:---|
| `code` | `zcode`, `opencode`, `claude-code`, `minimax-code` |
| `terminal` | `dev.lizardbyte.app.sunshine.terminal` |
| `edge` | `knowledge` (any word containing it) |
| `lutris` | `net.lutris.lutris1` |

Any app whose name merely *contains* a curated keyword is misidentified. Adding a
`zcode` rule would only move the collision to `xzcode`.

### 12.3. The Fix: Read the Standard Instead of Guessing
Window identity mapping is already standardized. A desktop entry declares
`StartupWMClass=` - the window class the application reports - alongside `Name=`
and `Icon=`. Reading those entries makes resolution **data-driven and exact**:

```
daemon/src/domain/app_identity.rs   AppIdentityIndex
  load()      scan XDG application dirs (user -> system -> flatpak -> snap)
  resolve()   exact match on StartupWMClass, then desktop-file id
```

Resolution order, and why:

1. **Curated presentation layer** - some apps present unusable identities (Wine
   titles, AppImages without a desktop entry, opaque `Name=` values) and deserve a
   deliberate name/icon. This tier is now **token-matched** (see 12.4).
2. **Desktop-entry index** - any installed application resolves from its own
   entry. This is what makes the solution general: **no per-app code, and no
   substring ambiguity by construction.** The entry's `Icon=` is what the dock
   draws, and `Categories=` is mapped to a Material Symbols glyph so even an
   unknown app gets a sensible icon.
3. **Generic fallback** - pure heuristic naming for dotnet/odd-toolkit windows.

`StartupWMClass` is consulted before the desktop-id because it is the app's own
declaration of the class it reports; ids then cover the 61% of entries that never
set it.

The index is built once and cached in a `OnceLock<RwLock<Arc<..>>>`
(`shared_index()`), with `refresh_shared_index()` for installs while the shell is
running, so the watcher never rescans the filesystem per event.

### 12.4. Token Boundaries, Not Substrings - The General Rule
The durable rule, applicable wherever a keyword classifies anything:

> Normalize both sides to space-padded lowercase alphanumerics, then require the
> keyword to match a **whole token sequence**.

```rust
token_match("zcode",                 "code")       // false
token_match("code",                  "code")       // true
token_match("com.mitchellh.ghostty", "ghostty")    // true
token_match("microsoft-edge",        "edge")       // true
token_match("cloudmusic.exe",        "cloudmusic") // true
token_match("knowledge",             "edge")       // false
token_match("com.gitawego.token-tracker-dashboard", "token-tracker") // true
```

This keeps every legitimate reverse-DNS, hyphenated and `.exe` class working while
making the false positives impossible. `"zcode"` is one token and `"code"` is
another, so they never collide.

### 12.5. Verification
`daemon/tests/test_app_identity.rs` (20 tests) pins the contract, including the
exact regression: `zcode` resolves to ZCode and `assert_ne!(app_id, "code")`,
while `code` still resolves to VS Code. Live check across all nine windows on a
real session after the fix:

```
ZCode      -> appName "ZCode"  appId "zcode"       icon "zcode"
VS Code    -> appName "VS Code" appId "code"        icon "vscode"
```

Note the remaining asymmetry, which is by design: a desktop entry's `Name=` wins
over a curated nickname (the user named the app, so respect it), while curated
entries still apply to anything without a matching entry.

### 12.6. Not Our Bug: Apps That Register No Tray Icon
The same investigation showed ZCode absent from the system tray. That is **not
fixable from the shell**: the app registers no `StatusNotifierItem` at all
(verified against KDE's `StatusNotifierWatcher` and by the absence of any
`new Tray(...)` in its Electron bundle). No shell can display a tray icon for an
app that never creates one, and fabricating a placeholder would violate the
"never fabricate content" rule. A running app belongs on the **taskbar**, which is
what section 12.3 restores.

---

## 13. Shell Surfaces Are Not Applications: Filtering The Active Window

### 13.1. The Symptom
Hovering a dock icon, opening a popout drawer, or focusing the settings window
made the dock's active-window pill display **"Quickshell"** - an entry for the
shell itself, which is not a program the user is working in.

### 13.2. Root Cause: An Asymmetry Between Two Code Paths
The shell creates real KWin windows: the unified desktop surface, drawers,
popouts, the notification layer and the settings window. Verified live - a
running session had **6 quickshell windows**, every one of them with
`skipTaskbar: true` and an empty caption.

Identity was filtered in exactly one of the two places that needed it:

```
getWindowList()   if (w.normalWindow && w.caption && w.resourceClass !== "quickshell")
notifyActive(c)   // no filter at all   <-- the leak
```

So `activeTitle` was updated from an unfiltered source. Because a layer-surface
can become KWin's `activeWindow` (a hover or focus grab is enough), the shell
reported its own surface as the active application. The window *list* was clean,
which is why the bug only ever appeared in the active-app display - and why
grepping the list path looked correct.

### 13.3. The Fix: Use The Standard Flag, On Every Path
KWin exposes the answer directly: `w.skipTaskbar`, the EWMH flag meaning "do not
represent me in a taskbar". It cleanly separated the two populations on a live
session:

| window class | skipTaskbar | count |
|:---|:---|:---|
| `quickshell` | **true** | 6 |
| real applications (`code`, `zcode`, `microsoft-edge`, `ghostty`, ...) | **false** | 9 |

The fix has three layers, deliberately redundant because the leak had two entry
points:

1. **KWin script, active path** - `notifyActive()` now returns early for a shell
   surface (via `isShellSurface(c)`, which consults `skipTaskbar` and the class).
   Reporting nothing is the correct behaviour: the daemon then keeps the last
   genuine application, rather than blanking the pill on every hover.
2. **KWin script, list path** - the existing class check is extended to honour
   `skipTaskbar` as well, and the flag is forwarded in the payload.
3. **Daemon** - `window_activated` re-checks `is_shell_owned_surface`, because
   that interface is independently addressable on the D-Bus, and the list
   enrichment re-checks `should_skip_taskbar`.

### 13.4. Match Class And App Id, Never The Title
`is_shell_owned_surface(cls, app, title)` deliberately ignores the title. Editing
`UnifiedShell.qml` in VS Code produces a window whose *title* contains
"UnifiedShell"/"astral-plasma", and a title-based filter would hide the user's editor.
The title parameter is kept in the signature (and documented as unused) so the
omission is explicit rather than accidental. Recognised shell identities are
matched by exact class, or by the class as a dotted/hyphenated prefix
(`quickshell`, `org.quickshell`, `astral-plasma`, `astral-plasma-settings`).

### 13.5. Verification
Live, with KWin actually reporting a shell surface as the active window:

```
KWin says active: {"caption":"","cls":"quickshell","skip":true}
Shell reports   : activeTitle='Terminal'  activeAppId='ghostty'   <- last real app
```

That is the failure state reproduced and corrected in the same measurement. The
window list holds 10 entries with 0 quickshell entries. Covered by
`daemon/tests/test_app_identity.rs`, which asserts the predicate on both paths,
that a title mentioning the shell does not flag a real application, and that the
script forwards the skip flag.

### 13.6. The General Rule
> When the shell owns its own windows, ask the compositor which windows belong in
> a taskbar (`skipTaskbar`) instead of enumerating the classes to exclude.

A class-based denylist has to be extended for every new shell surface (drawer,
popout, OSD, settings window) and silently fails as soon as someone adds one
without updating it. `skipTaskbar` is set by the surface itself, so it scales with
the shell and cannot be forgotten.

### 13.7. The Deeper Root Cause: Activation Is Never Returned
Filtering the shell surface out of the *reported* active window treated the
symptom. The actual defect was upstream of that:

```
baseline            : active = ZCode
dashboard open      : active = quickshell     <- KWin activates the layer surface
dashboard closed    : active = quickshell     <- and NEVER gives it back
t+2s ... t+10s      : active = quickshell     <- still there, indefinitely
```

Requesting keyboard focus on a full-screen layer surface (`WlrKeyboardFocus.
OnDemand`) makes KWin **activate** that surface. Withdrawing the request does not
reassign activation, so the compositor keeps an invisible shell surface as its
active window forever. Two consequences, and the second is the one that looked
like a frozen dock:

1. The shell surface becomes the reported active window.
2. **No further `windowActivated` events fire at all** - the watcher is starved,
   so the dock's active-app display freezes on whatever application happened to
   be active before the interaction. This is why the symptom appeared as "always
   displaying Edge": Edge was simply the last real window seen before the drawer
   was opened.

**The fix is to not request focus in the first place.** `UnifiedShell` requested
`OnDemand` whenever a drawer, popout or modal was open - but the only thing that
genuinely needs key events is the power-confirmation modal (Enter/Escape). Drawers
and popouts close on mouse-leave, scrim click, or the toggle shortcut, so they
gain nothing from a focus request and were paying for it with permanent
activation loss:

```qml
WlrLayershell.keyboardFocus: PowerService.confirmDialogVisible
    ? WlrKeyboardFocus.OnDemand
    : WlrKeyboardFocus.None
```

Because the modal legitimately needs focus, its cycle is closed explicitly:
`astral-plasma focus restore` (a one-shot KWin script) hands activation back to
the most recent real window on modal close. Restoring automatically on *open*
would be wrong - it would strip the modal of the focus it needs.

Verified live: `workspace.activeWindow = target` does restore activation, so KWin
accepts the reassignment; it simply never does it on its own.

**The general rule**: a shell should request keyboard focus only for genuine
modal input, and any surface that does must return activation explicitly when it
finishes. Never request focus for a surface the user only hovers or clicks
through.

**Measurement note**: this class of bug is invisible to code reading alone - the
filter *looked* correct and the window list was clean. It took a KWin-script probe
(`workspace.activeWindow` logged across a scripted open/close cycle) to see that
activation never came back. Probe the compositor's own state, not the shell's
derived copy of it.

---

## 14. Screen Fillet Blur Masks: Coverage, Not Slices

### 14.1. The Symptom
The inner fillets where the dock meets the top/bottom border rendered as a
**stepped, jagged corner** instead of a smooth arc.

### 14.2. Root Cause: Slices Sized For The Wrong Depth
The compositor blurs only axis-aligned rectangles, so each concave fillet arc is
approximated by stacked slices. The fillet region has radius $R$ and its glass is
the area *outside* the inscribed circle (centre at $(R, R)$ local), so the glass
width at depth $d$ is:

$$w_{\text{glass}}(d) = R - \sqrt{R^2 - (R-d)^2}$$

The profile was hand-tuned to widths `12 / 7 / 4 / 2 / 1`, with each width sized
for its slice's **bottom** depth. Because the arc widens steeply toward the
tangency, the *top* of every slice was left uncovered:

| slice depth | mask width | glass needs | uncovered |
|:---|:---|:---|:---|
| 0-2 | 12 | 20.0 | **8.0px** |
| 2-5 | 7 | 11.3 | **4.3px** |
| 5-9 | 4 | 6.8 | **2.8px** |
| 9-14 | 2 | 3.3 | **1.3px** |

The fillet glass is translucent ($\alpha \approx 0.65$), so every uncovered wedge
showed the wallpaper through it *unblurred* - five discrete jumps reading as a
stair-stepped corner. This is the same failure mode as 9.4's "coarse inset notch"
warning, but the earlier note only warned about it; this is the measured
magnitude and the general fix.

### 14.3. The Fix: Derive The Profile From The Arc
The widths are no longer tuned by hand; they are computed from the arc equation
and sized for each slice's **top** depth, so the mask covers the glass by
construction and automatically tracks `filletR`:

```qml
readonly property var filletProfile: {
    const R = root.filletR;
    // Fine near the tangency, where the curve changes fastest.
    const depths = [0, 1, 2, 4, 7, 11, 15, R];
    // width[i] = ceil(glass width at depths[i])   // slice TOP, never underside
}
```

All four corners reference the same profile (28 regions), so a radius change
propagates everywhere. Measured coverage for the configured $R = 20$:

| depth | mask width | glass needs | gap |
|:---|:---|:---|:---|
| 0-1 | 20 | 20.0 | 0.0 |
| 1-2 | 14 | 13.8 | 0.0 |
| 2-4 | 12 | 11.3 | 0.0 |
| 4-7 | 8 | 8.0 | 0.0 |
| 7-11 | 5 | 4.8 | 0.0 |
| 11-15 | 3 | 2.1 | 0.0 |
| 15-20 | 1 | 0.6 | 0.0 |

Worst gap: **0.00px** (was 8.0px). Slice heights sum exactly to `filletR`, so the
mask spans the arc without overlap or gap. The residual outward overshoot is at
most ~1px and is feathered by the blur kernel.

### 14.4. The Two Rules
1. **Size each slice for the deepest point it must cover** - which for a convex
   arc widening downward is the slice's TOP edge, not its bottom. Sizing for the
   bottom systematically under-covers.
2. **Derive widths from the curve equation, never by hand.** A literal table
   silently under-covers as soon as the radius changes, and cannot be verified.

Enforced by `tests/tst_fillet_blur_coverage.qml`, which parses the depth list out
of the source, recomputes the arc, and asserts zero gap for $R = 12..32$ plus the
configured radius, that all four corners use all seven slices, and that the depth
fractions are fine near the tangency. Verified to fail on both a coarse-but-
increasing depth list and a non-increasing one.

### 14.5. Measurement Note
The fillet boundary has to be observed against a **high-contrast, uniform**
backdrop: the uncovered wedges only show as visible steps when the wallpaper
behind them is sharp and bright. Against normal desktop content the defect is far
subtler, and against a backdrop that the shell itself draws it is invisible
because the mask and the surface are then both sourced from the shell. A magenta
full-screen window at `WindowStaysOnTopHint` (above other windows, below the
shell's Top layer) made the artifact unambiguous and locatable in a capture.

---

## 15. Don't Ship Diagnostic Slows: Motion Tokens Are Guarded by DESIGN.md

### 15.1. The Symptom
The drawer's open animation regressed from "the border transforms and fuses into
the drawer" to "a pre-defined box sliding out", which reads as mechanical.

### 15.2. Root Cause: A Leftover Diagnostic Slowdown
`theme/Theme.qml` was left with `animExpressiveDefaultSpatial: 4000` - the
duration had been temporarily changed from **500ms to 4000ms** to make the
transition slow enough for `spectacle` (whose ~450ms capture cadence cannot
resolve a 500ms animation). The edit was never reverted.

Nothing caught it because nothing connected the token to its specification.
DESIGN.md section 2.1 documents the motion palette and names
`theme/Theme.qml` as its formalization, but no test read the table.

At 8x the intended duration every nuance of the expressive spring is lost: the
overshoot and the fast opening beat happen in what is now the first tenth of a
perceptually linear crawl. The morph still *happens*, but the eye reads the shape
as extruding rather than transforming - so the complaint ("pre-defined shape,
pushing out") is an accurate description of what a slowed spring actually looks
like.

### 15.3. Why This Class Of Bug Is Easy To Ship
Diagnostic edits are *deliberately* obvious while you are making them, and
invisible once you have moved on. Three habits prevent shipping them:

1. **Revert before running the suite, not after.** A diagnostic that changes a
   shared token affects every consumer, so the suite is the wrong place to notice.
2. **Prefer a per-call override to editing a shared token.** Slowing one
   animation for a capture is safest via a local `Behavior` override, not the
   global token every transition reads.
3. **Have a test that ties shared tokens to their documentation**, so an edit
   fails loudly instead of looking like a design choice.

### 15.4. The Guard
`tests/tst_motion_tokens.qml` parses DESIGN.md's token table and Theme.qml's
declarations and asserts they agree:

- every documented duration exists in Theme.qml with the documented value;
- every documented curve exists as a 6-value bezier with the documented control
  values;
- the three `animExpressive*Spatial` tokens exist **by name** (the shell's
  transitions depend on them) and their durations sit in the documented
  150-800ms spring range.

Validation is by content rather than by name pairing, because Theme.qml's naming
is not uniform: `animExpressiveDefaultSpatial` pairs with
`curveExpressiveDefaultSpatial`, but `animEmphasized` pairs with
`curveEmphasizedDecel`. Content matching keeps the guard robust to that while
still pinning the tokens that matter by name.

Verified to fail on the exact leftover (`4000ms`), reporting that no duration
token has the documented value.

### 15.5. The General Rule
> A shared token that a specification documents must be asserted against that
> specification. Otherwise "temporarily wrong" and "intentionally changed" are
> indistinguishable to every future reader, including the test suite.

This is the same principle as §9.8 (glass alphas solved, not chosen) and §14
(fillet widths derived, not hand-tuned): when a value has a documented contract,
encode the contract as a test so drift is a failure rather than a silent change.

---

## 16. One Definition Per Surface: Blur Masks Must Consume The Drawn Rect

### 16.1. The Recurring Bug
Every blur defect in this shell has had the same shape: the compositor mask and
the glass it must blur were **authored as two separate expressions** for one visual
object, and then drifted. Three instances, all measured:

| surface | the mask computed | the glass was | result |
|:---|:---|:---|:---|
| screen fillets | widths `12/7/4/2/1` tuned by hand | arc of radius 20 | 8px of glass unblurred, stepped corner (14) |
| bottom popout (fused) | `h = root.height - wrapper.y` | `wrapper.height + topR + botR` | mask reached the screen bottom, blurring bare desktop (15) |
| notification | `w = notifW + filletR`, `h = notifH + filletR` | `0,0,panelW,currentEnvelopeHeight` | 20px frosted wallpaper on two sides |

The third was verified live: panel bottom `y=78`, mask bottom `y=98`, and rows
78..97 read *bright* (bare wallpaper, mean 115-118) while their local energy was
suppressed to 5-11 against a sharp reference of 26.75 - frosted wallpaper with
nothing painted over it.

### 16.2. The Rule
> A blur mask must not recompute geometry. The surface that draws the glass must
> publish its painted rect, and the mask must consume it.

This is the same principle as 9.8 (alphas solved, not chosen) and 14 (fillet
widths derived, not tuned), applied to geometry instead of colour. The mask is a
Wayland protocol region and cannot be a child of the surface (9.11.1), so a shared
*property* is the only available mechanism - and it is sufficient.

### 16.3. Implementation
`UnifiedFrame.bottomPopoutSurface` publishes its own extent:

```qml
readonly property rect fullRect:  Qt.rect(x, y, width, height)      // whole painted surface
readonly property rect bodyRect:  Qt.rect(x, popoutY, popW, popoutHeight)  // straight-sided part
```

and `UnifiedShell` consumes it rather than re-deriving:

```qml
y:      desktopFrame.bottomPopoutSurfaceItem.fullRect.y
width:  desktopFrame.bottomPopoutSurfaceItem.fullRect.width
height: desktopFrame.bottomPopoutSurfaceItem.fullRect.height
```

**Use `fullRect`, not `bodyRect`, for the body mask.** The top and bottom
`filletR` bands are glass right across the width - only their leftmost sliver is
the concave shoulder - so a body-sized mask leaves those bands unblurred. This
mistake was made and caught during the fix: the first attempt consumed `bodyRect`
and would have shrunk the mask.

`NotificationPopup` does the same with `surfaceWidth/surfaceHeight/surfaceX`, plus
a separate `shoulderRect` for the single concave corner fillet, which is a quarter
disc living in the top `borderRounding` rows - not a full-height column.

### 16.4. Two Traps When Fixing This
1. **Adding `filletR` on every side is almost always wrong.** It is right only
   where a shoulder actually spans that edge across its full length. Where the
   shoulder is a corner arc, the correct mask is the panel rect plus a small stub.
2. **A stale mask is invisible in a static screenshot.** Blurring bare desktop
   looks like a slightly hazy region rather than an error. It only becomes obvious
   over a high-frequency backdrop (a checkerboard), where "blurred" and "sharp" are
   separable by local energy - or by logging the mask rect and comparing it with
   the surface's, which is what finally localised these cases.

### 16.5. Also Fixed: A Stray Inner Border
The notification's inner `LiquidGlassCard` drew its own 1px perimeter ring,
visible as a second rounded box inside the panel (measured as two hairlines at
`y=16` and `y=71` against the panel edge at `y=77-78`). A resting container should
not draw a ring: the specular hairlines already define the glass edge (9.1, "Clean
Glass Materials"). `LiquidGlassCard` now takes `showBorder`, and the notification's
inner card sets it `false`.

### 16.6. Verification
- `tests/tst_popout_blur_extent.qml` - both popout variants consume `fullRect`,
  `fullRect` equals the surface extent in fused AND floating states, no mask may be
  sized to the screen bottom, and each variant still declares a region set.
- `tests/tst_notification_blur_extent.qml` - the mask reads the panel's own
  extents plus a bounded `shoulderRect`, adds no `filletR` to width or height, and
  the inner ring is disabled.

Both are verified to fail when the respective defect is re-injected. The permanent
`[BlurAudit]` logger (`debugMode: true`) prints every active mask rect, which is
how each of these was localised:

```
[BlurAudit] active: notification=2180,0 380x78        <- after: exactly the panel
[BlurAudit] active: notification=2160,0 400x98        <- before: 20px overhang
```


---

## 17. Wine Windows, Xwayland Focus, and KWin Rules

Wine applications are X11 (Xwayland) clients, and two of their properties interact
badly with normal activation and keyboard routing. Both were diagnosed from a
single symptom - *"pressing Enter in a native app toggles the Wine music player"*.

### 17.1. `WM_HINTS.input = 0` disables click-to-focus

`xprop -id <win>` on a Wine main window can show:

```
WM_HINTS(WM_HINTS): ... InputHint, input: False
```

Wine sets this when the application declares `WS_EX_NOACTIVATE` (background
players, tray-style windows). KWin honours it: the window never takes keyboard
focus, so clicking it neither focuses nor raises it. The dock's "Bring to Front"
still works because it activates the window from *inside* KWin
(`workspace.activeWindow = w`), bypassing the hint - which is why it looked like
the only way to reach the window.

Fix, scoped to the window class in `kwinrulesrc`:

```ini
[1]
Description=Wine background player
acceptfocus=true
acceptfocusrule=2
wmclass=cloudmusic.exe
wmclassmatch=1
```

`acceptfocus` is "Controls whether or not the window becomes focused when
clicked" (KCM string). KWin's scripting API exposes the resolved state as
`w.wantsInput`, which makes the fix verifiable without clicking.

### 17.2. Extreme focus stealing prevention blocks even user actions

A rule with `fsplevel=4` (`fsplevelrule=2`) is a common way to stop a chatty
Wine app from raising itself. It also blocks *user* activation: an EWMH
`_NET_ACTIVE_WINDOW` request with source indication 2 (user action) is refused,
leaving the window stuck with `_NET_WM_STATE_DEMANDS_ATTENTION`. Lowering it to
`fsplevel=1` (Low) keeps the app from stealing focus in unambiguous cases while
allowing activation, after which `_NET_ACTIVE_WINDOW`, `_NET_WM_STATE_FOCUSED`,
`XGetInputFocus` and `workspace.activeWindow` all agree.

### 17.3. A stale Xwayland focus leaks keystrokes into the Wine window

Activating a Wine window leaves Xwayland's keyboard focus on it; when the user
then focuses a native Wayland window, KWin can keep forwarding keys to that X11
focus, so typing in any native app also drives the Wine app. Measured with a
passive `KeyPressMask` observer on the Wine window: pressing Enter in a native
chat box delivered `keycode=36 (Return)` into NetEase CloudMusic, whose focused
control was its play/pause button.

The shell therefore hands the X11 focus back whenever the active window is not a
Wine window (`XSetInputFocus(None, RevertToNone)`), re-enforced every 500 ms
because Wine re-asserts its focus after being cleared. Two consequences worth
remembering:

- `workspace.windowActivated` does **not** fire for script-driven activation
  (`workspace.activeWindow = w`), so the `activate` KWin script reports the
  activation to the daemon itself; otherwise the focus guard would immediately
  take the keyboard focus back from the window just brought to the front.
- Release only when `WM_CLASS` ends in `.exe` **and** the active window is not a
  Wine window; a Wine window that is genuinely active must keep its focus.

Decision logic lives in pure functions (`is_wine_class`,
`should_release_x11_focus`) with tests in `daemon/tests/test_x11_focus_handoff.rs`.
