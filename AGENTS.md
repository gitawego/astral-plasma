# AGENTS.md

> Guidelines, architecture map, and development conventions for AI coding assistants working in **Astral Plasma**.

---

## 1. Project Overview

**Astral Plasma** is a high-performance, fluid, and expressive desktop shell for **KDE Plasma 6 & KWin** (Wayland / X11), built with [Quickshell](https://quickshell.outfoxxed.me/) and Qt 6 QML.

The design language is adapted from upstream [caelestia-dots/shell](https://github.com/caelestia-dots/shell), featuring a seamless outer screen frame, an organic capsule dock, fluid Material 3 Expressive motion physics, and wallpaper-driven dynamic palettes.

**Portability specification:** [`docs/HYPRLAND-OMARCHY-SPEC.md`](docs/HYPRLAND-OMARCHY-SPEC.md) defines the shared Desktop Session language, ports-and-adapters boundary, Hyprland backend, hosted Omarchy plugin profile, standalone experimental boundary, migration phases, and acceptance gates. Read it before changing compositor integration, desktop lifecycle, global shortcuts, window/workspace services, wallpaper, previews, or compositor effects. The domain glossary lives in [`CONTEXT.md`](CONTEXT.md).

---

## 2. Design System Authority & Custom Theme Architecture

> [!IMPORTANT]
> **[DESIGN.md](DESIGN.md) and [docs/LESSONS.md](docs/LESSONS.md) are the authoritative sources of truth for visual design, motion physics, and custom theme engineering.**
> Before modifying or creating any UI components, animations, popouts, or layouts, consult [DESIGN.md](DESIGN.md) and [docs/LESSONS.md](docs/LESSONS.md).
>
> - **Liquid Glass & Geometry Fusion Guide**: Review **[`docs/LESSONS.md`](docs/LESSONS.md)** for the essential rules on:
>   - **Zero-Overlap Partitioning**: Preventing 1px dark seams caused by double-translucent fills.
>   - **Concave Shoulder Fillets**: Correct $C^1$-continuous inverted corner radii and coordinate math in Qt Quick Shapes.
>   - **Compositor Blur Approximation**: 7-slice depth-tapered KWin `BackgroundEffect.blurRegion` coverage.
>   - **In-Flight State Latching**: Preventing premature geometry morphing during transit animations.
>   - **Clean Glass Materials**: Avoiding fake 1px top highlight bars and boxy button clutter.
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
>    - **A QML suite passes only if it exits 0, prints `PASS:`, and never prints `FAIL:`** (`tests/run_qml_tests.sh` enforces all three). An `assert()` must therefore `throw` after `Qt.exit(1)` — `Qt.exit` schedules an exit, it does not stop JavaScript, so a failure would otherwise be followed by the suite's own `PASS:` line and an exit-0 override: a masked failure (see [docs/LESSONS.md](docs/LESSONS.md) §37).
> 5. **Test Scope Coverage**:
>    - **Backend (Rust Daemon)**: Domain models, DBus error filtering, system metrics parsing, and process resolvers must have full unit test coverage.
>    - **Frontend (QML)**: Geometry calculations, non-overlapping borders, corner fillets, auto-close timers, and component boundaries must have dedicated offscreen QML test suites (`tests/tst_*.qml`).

---

## 4. Mandatory Rule: Never Ever Fabricate Content, Must Be Data Driven

> [!CAUTION]
> **CRITICAL MANDATORY RULE: NEVER EVER FABRICATE CONTENT, MUST BE DATA DRIVEN.**
> All animations, audio visualizers, indicators, badges, and layout states must be purely driven by physical ground-truth system telemetry, audio data, and reactive configuration. Fabricating, faking, simulating, or synthesizing content is strictly forbidden:
>
> 1. **Strict Physical Ground-Truth (No Synthetic Content)**:
>    - You must NEVER fabricate, fake, or synthesize content (e.g. generating synthetic beats with hardcoded BPM timers, generating fake sine waves or idle wobbles, generating artificial frequency bands, or guessing playback state with isolated booleans).
>    - Audio visualizers, bar heights, and beat pulses must reflect ground-truth PCM streaming through the PipeWire audio sink output monitor (`CaptureTarget::Sink` with `stream.capture.sink=true`) and live DSP spectral flux. Audio capture MUST NEVER capture from the physical microphone or inject artificial noise.
> 2. **Follow The Music Beats — If No Beat, Then No Jumping**:
>    - Visualizer elements (speaker rings, notes, bars, dots, album covers) **MUST strictly follow physical music beats**. If there is no beat transient, there must be **ZERO jumping**.
>    - When music is stopped, paused, or silent, all energy, band heights, and beat values must cleanly settle to `0.0`. All bouncing, hopping, and scaling must be completely stationary.
>    - Never use artificial timers (`MotionPacer`, periodic sine bobbing, or idle wave oscillators) to move visualizer elements when there is no physical audio activity.
> 3. **Generic & Edge-Case Resilient Architecture**:
>    - All solutions must be architectural, generic, and resilient to all player backends (Wine, native MPRIS, browser media sessions).
>    - Avoid ad-hoc monkey patches, hardcoded player identities, brittle boolean flipping, or arbitrary pixel offsets.
> 4. **High-Performance & Built-In Primitives**:
>    - Audio visualizers, canvas renders, and animations must use built-in Qt Quick primitives, GPU-accelerated items (`Canvas`, `ShaderEffect`), and native system facilities rather than CPU-heavy polling loops or uncoordinated subprocesses.

---


## 4b. Mandatory Rule: Resolve The Subject Before Deleting Anything

> [!CAUTION]
> **A screenshot is the subject of the request.** When a request attaches a picture, the
> change is to what is **in** the picture; the caption usually names the surface that must
> **survive** ("they are at right sidebar" = the right rail stays, the pictured dock copies go).
>
> - **Name both surfaces before editing.** For any delete / de-duplicate / "remove this"
>   request, state in one line which surface is removed and which is kept, then start. If the
>   two are near-synonyms in this repo — here "sidebar" means the **dock** in `README.md` but
>   the **right rail** (`RightEdgeControl`) in ordinary speech, while the in-dock drawer is
>   `FusedBottomPopout` — that sentence is mandatory.
> - **Deletion is a confirmation point.** Removing a user-facing surface, or any destructive
>   change over ~100 lines, gets a one-line confirmation even when confident. A revert costs
>   a round trip plus the user's trust; asking costs one message.
> - **Green tests never validate intent.** TDD proves the code matches the written contract;
>   whether that contract matches the request is reviewed separately, against the request's
>   own words and artefacts. A suite authored against a misreading passes perfectly.
> - Worked example: [`docs/POST-MORTEM-2026-11-03-control-home.md`](docs/POST-MORTEM-2026-11-03-control-home.md).

---

## 4c. Mandatory Rule: Never Claim A Fix Without Proof

> [!CAUTION]
> **"Fixed" is a claim about the running system, not about the diff.** A passing suite, a
> compiled binary, a clean `git status` or a plausible root-cause story are **not** proof that
> the user's problem is gone. State a fix only after observing the new behaviour on the live
> desktop, and say plainly what was *not* verified.
>
> ### What counts as proof
> 1. **Live observation of the reported symptom, before and after.** Reproduce the failure
>    first (the wrong title on screen, the number that reads 60 %), then observe the corrected
>    behaviour in the same conditions.
> 2. **The evidence must show the thing the user complained about**, not a proxy for it. A
>    screenshot that happens to miss the widget proves nothing; a pixel diff against a region
>    that contains a browser window proves nothing either.
> 3. **Say which surface you actually saw.** "Captured X and it showed Y" — with the name of
>    the view, not just "verified live".
>
> ### Anti-patterns that have already burned this project
> - **Calling a screenshot "proof" when it never contained the UI.** Captures taken while a
>   hover-driven drawer had already auto-closed (dashboard closes 350 ms after the pointer
>   leaves) were presented as verification. They showed a browser window.
> - **Proving the code path instead of the outcome.** A live A/B of a decision function on
>   real session data shows what the function *would* choose; it does not show that the
>   running shell imported it, that the surface re-evaluated, or that the user's screen
>   changed.
> - **Asserting success after a self-authored test passes.** Tests encode the contract you
>   inferred; when the inference is wrong they pass perfectly (see §4b).
> - **Reporting "all green" as the headline** when the user's screenshot still shows the bug.
>
> ### Required phrasing
> - Verified: *"Captured the media tab with music playing; it shows `恭喜发财`, NetEase — not
>   x.com."*
> - Verified, partially: *"The election returns NetEase for these live inputs (command
>   output below). I did not capture the widget itself; the surface was closed during capture."*
> - Not verified: *"Logic and tests are in place; the live UI still showed Edge, so this is
>   not fixed."*
>
> **If the live evidence contradicts the change, the change is not finished** — keep
> investigating, and report the contradiction instead of the intention.

---

## 4d. Mandatory Rule: No Hard-Coded Content, No Secrets In Git

> [!CAUTION]
> **Two things must never enter this repository: fabricated content and credentials.**
>
> 1. **Never hard-code or fabricate content.**
>    - Every value a surface renders must come from ground truth: system telemetry, the audio
>      stream, the filesystem, a database, or reactive configuration. If a value is unavailable,
>      render an explicit empty/unavailable state — never an invented number, title, beat, or
>      status.
>    - Test fixtures are the only exception, and they must be unmistakably synthetic: names like
>      `test-minimax-key-999`, RFC vectors, or values generated in the test itself. Never copy a
>      real credential into a fixture, even an expired or revoked one.
>    - Do not hard-code player identities, device names, user paths, ports, or content that the
>      system can discover. See §4 for the data-driven visualizer rules.
>
> 2. **Never store secrets in git.**
>    - Never commit API keys, access/refresh tokens, passwords, cookies, session secrets, private
>      keys, keyring exports, `.env` files, or credentials embedded in URLs, JSON, YAML, logs,
>      screenshots, or test fixtures.
>    - Pass secrets through environment variables, the OS keyring, stdin, or one-shot runtime
>      tokens. Redact them from logs, errors, `--json` payloads, and command arguments.
>    - Commit only placeholders (`${OPENAI_API_KEY}`, `test-…`, `<token>`), never a real value.
>    - **If a secret is committed: assume it is compromised.** Rotate/revoke it first, then
>      rewrite the history that contains it (for example `git filter-repo --replace-text`) and
>      force-push the rewritten refs. Deleting the file in a new commit does **not** remove it
>      from history.
>    - Before pushing, scan the tree **and all history** (`gitleaks git --log-opts=--all`) and
>      run `cargo audit` for the daemon. A finding may be accepted only with a written
>      false-positive justification; a real credential is never waived.
>    - `.gitignore` must cover `.env*`, private keys, credential stores, and local secret files.

---

## 5. Repository Map

```
astral-plasma/
├── Makefile                  # Build, test, and run automation (make test, make build, make run)
├── AGENTS.md                 # Agent instructions & development conventions (this file)
├── DESIGN.md                 # Design system specification, motion tokens & layout rules
├── README.md                 # Public documentation and setup guide
├── docs/                     # Architectural documentation & technical deep dives
│   └── LESSONS.md            # Lessons learned: liquid glass, concave fillets & zero-overlap partitioning
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
│   └── settings.json         # Shipped default settings (live user settings:
│                             #   ~/.config/astral-plasma/settings.json)
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
make build        # Compiles release Rust daemon (bin/astral-plasma)
make test-rust    # Runs Rust unit tests
make test-qml     # Runs QML offscreen test suites
make run          # Runs shell with daemon
```

### 5.2. Hot Reloading & Diagnostics
Quickshell automatically reloads upon file changes. Monitor the console output or active daemon log for:
- QML syntax or parse errors (`ERROR: Failed to load configuration`).
- Anchor cycles or undefined binding loops.
- DBus service warnings.

### 5.3. Visual Verification & Proof of Work
Because Wayland desktop shells cannot be inspected through headless DOM tools, automated unit tests alone CANNOT verify visual appeal, optical blur, transparency, or styling fidelity.
You MUST verify all UI changes visually using Spectacle and inspect the resulting images:
```bash
spectacle -b -n -o /tmp/screen.png
```
Inspect the resulting image using `view_file` to verify alignment, centering, contrast, transparency, and corner radii.

---

## 7. Mandatory Visual Proof of Work & First-Round Completeness Policy

> [!CAUTION]
> ### WHY FIRST ROUNDS FAIL & HOW TO PREVENT IT
> AI agents frequently fail the first round of visual and UI development due to four specific antipatterns:
>
> 1. **Tunnel Vision & Incomplete Surface Audits**:
>    - Modifying only the immediate component mentioned (e.g., just the launcher) while leaving primary shell surfaces (Central Dropdown, Media Drawer, Popouts, UnifiedFrame) untouched and clashing.
>    - **RULE**: Before starting, audit ALL shell windows (`UnifiedShell`, `UnifiedFrame`, `CentralDropdown`, `LeftDock`, `CommandLauncher`). If a design language changes, it MUST be comprehensively and consistently applied across ALL surfaces.
>
> 2. **Confusing Unit Test Passing with Visual Correctness**:
>    - Unit tests (`cargo test`, `tst_*.qml`) verify geometry numbers and business logic, NOT optical beauty, translucency, or aesthetic harmony. Passing tests is a prerequisite, NOT proof of visual success.
>    - **RULE**: Never declare a visual task complete based on test passes alone.
>
> 3. **Superficial "Checklist" Styling vs. Authentic Material Physics**:
>    - Slapping on harsh borders, glowing cyan fills, or shiny 2005-era skeuomorphic chrome lines instead of authentic, restrained, context-aware materials (subtle 1px hairline rims, true compositor blur, concentric curvature).
>    - **RULE**: Follow optical principles strictly:
>      - True backdrop blur via `BackgroundEffect.blurRegion` on Wayland.
>      - Concentric corner geometry: $R_{\text{inner}} = R_{\text{outer}} - \text{padding}$.
>      - Translucent materials (55–65% alpha), never opaque `#16171a` masquerading as glass.
>      - Focus states must refine the container (subtle border/ring), NEVER replace frosted glass with solid opaque neon colors.
>
> 4. **Failing to Test in Real-World Context**:
>    - Taking screenshots against an empty black screen where translucency is invisible.
>    - **RULE**: Always test and capture screenshots with realistic content beneath (browser windows, text, colorful wallpaper) to PROVE transparency, blur, and contrast.
>
> ### MANDATORY PROTOCOL BEFORE DECLARING WORK COMPLETE:
> 1. **Capture Visual Proof**: Use `spectacle` to capture full-resolution screenshots of EVERY affected view and state (Launcher, Dashboard, Media Drawer, Popout).
> 2. **Self-Inspect the Proof**: Use `view_file` on the captured images to rigorously verify corner radii, transparency, typography, and contrast.
> 3. **Report The Evidence, Never Commit It**: proof screenshots are local-only. Capture them outside the repository (e.g. `/tmp` or `~/Pictures/astral-plasma-proof/`) and describe what was verified in the conversation and in `walkthrough.md` prose - image files are never committed (`docs/proof/` is git-ignored).

---

## 8. Mandatory Post-Work Verification & Non-Regression Gate (Never Break Existing Features)

> [!CAUTION]
> ### CRITICAL MANDATORY RULE: VERIFY AFTER EACH WORK DONE TO ENSURE NOTHING IS BROKEN
> Fixing one issue or adding a feature must NEVER break another existing feature, degrade surfaces, or swap out ground-truth data. Every modification MUST pass this non-regression gate before being declared complete:
>
> 1. **Zero Side-Effects on Shared Primitives (No Monkey Patching)**:
>    - You must NEVER fix a localized problem by applying a broad short-circuit, heuristic bypass, or monkey patch in low-level primitives (such as `MaterialIcon.qml`, `ThemedIcon.qml`, `ThemedImage.qml`, or `Config.qml`).
>    - Low-level primitives serve multiple consumers across the shell (Dock, Taskbar, App Launchers, System Tray, Popouts, Copilot). Any change to a shared primitive MUST be audited against all its consumers.
> 2. **Never Fabricate or Hardcode Fallback Content**:
>    - Real application desktop entries, icons, and system telemetry are authoritative ground truth. Never intercept or replace valid application icons, window titles, or status telemetry with synthetic or hardcoded fallbacks.
> 3. **Mandatory 360-Degree Shell Verification**:
>    - After each code modification, do not just test the one component you changed.
>    - You MUST verify that other shell surfaces (Dock icons, taskbar pins, active window indicators, status group, tray, dashboard) remain fully operational and intact.
> 4. **Live Visual Capture & Self-Inspection**:
>    - Take a full-resolution screenshot using `spectacle -b -n -o /tmp/screen_verify.png`.
>    - Inspect the captured screenshot with `view_file` to confirm that all application icons (e.g. Edge, VS Code, Terminal, Dolphin), badges, and geometries are displaying their authentic, intended visuals.

---

## 9. QML Coding Standards & Best Practices

1. **Explicit Sizing & No Circular Anchors**:
   - Never combine `anchors.fill: parent` with an item whose parent's `implicitHeight` depends on its children.
   - Use `implicitWidth` and `implicitHeight` on custom components.
2. **Bounded Scrolling**:
   - Any dynamic list whose item count depends on user state (e.g. running application windows) MUST be wrapped in a `SmoothFlickable` (or `SmoothListView`) and height-clamped to prevent pushing fixed dock controls off-screen on smaller displays.
3. **Dual-Text Cross-Fading**:
   - For labels that update reactively (such as the active window title), use alternating double `Text` items (`titleText1` / `titleText2`) with opacity cross-fading rather than instant text jumps.
4. **Resilient Icon Resolution**:
   - Always chain app icons: check for raw desktop file / URI path -> query `Quickshell.iconPath()` -> fallback to a Material Symbols icon via `MaterialIcon`.
5. **Smooth Scrolling Everywhere**:
   - Every scrollable surface MUST use the shared [`SmoothFlickable`](modules/Astral/Kernel/components/SmoothFlickable.qml), [`SmoothListView`](modules/Astral/Kernel/components/SmoothListView.qml), or [`SmoothGridView`](modules/Astral/Kernel/components/SmoothGridView.qml). Never declare a bare `Flickable`/`ListView`/`GridView` in the shell.
   - Wheel normalization and the spring-damper live in [`ScrollPhysics.js`](modules/Astral/Kernel/components/ScrollPhysics.js) and [`SmoothWheelHandler.qml`](modules/Astral/Kernel/components/SmoothWheelHandler.qml). Never assign `contentY`/`contentX` directly from a wheel handler, and never replace the spring with a fixed-duration tween; scrolling must carry momentum and an elastic overshoot.
   - The only intentional exception is a wheel-driven carousel (`WallpaperCarousel.qml`), where a wheel step selects an item rather than scrolling a viewport.

