# Astral Plasma — Downloads: A Real Window, Per-Task Parts, And A Safe Stop

> [!NOTE]
> **Issue**: Downloads existed only inside the top drawer, so they could not be parked on screen like the Copilot; a running task's connection count could only be changed by hand over aria2 RPC; and `make stop` killed the engine (its `--input-file` path contains `astral-plasma`, so `pkill -f "astral-plasma"` matched aria2c).
>
> **Fix**:
> 1. **`shell/DownloadsWindow.qml`** - a `FloatingWindow` like the Copilot/Settings windows, hosting the same `DownloadsTab` in `windowMode`. The drawer header gains an "open in window" action, the window header a close action and a compositor-native drag; the task list fills the taller surface instead of staying at four rows. `Config.openDownloadsWindow()` closes the layer-shell drawer first, and `downloads open|close|toggle` IPC mirrors it.
> 2. **Per-task parts** - `fetch_all` enriches live tasks with the engine's own `split` (`aria2.getOption`), the row shows `- N parts +` for active/waiting/paused tasks, and `downloads set-parts <gid> <n>` calls `aria2.changeOption` with `split` + `max-connection-per-server` (clamped 1..16). aria2 restarts the task internally and resumes from the `.aria2` control file; a server that supports HTTP Range is required (real CDNs do), which the verification confirmed.
> 3. **In-window settings** - the tune button opens a modal transfer console (`DownloadSettingsPanel`): a live capacity equation (parallel × connections = total), destination field, stepper knobs, speed cap, and the border HUD. It uses the same Config setters and engine push as Settings > Downloads; `downloads settings` IPC opens it directly. The sheet floats over the task list instead of replacing it, so the manager keeps its context and there is no dead half-screen.
> 4. **Restart safety** - `make stop` targets processes by exact name (`pkill -x`), so aria2c survives; the engine also flushes its piece map every 30 s (`--auto-save-interval=30`) instead of the 60 s default.
> 5. **Window composition** - the empty state and the task list now share one full-height stage, so switching to Finished no longer moves the header or the content; the empty state is an invitation with an Add action, and a bottom ledger (live segment state, destination, Open folder) gives the tall window a base.
> 6. **Header stability & real inset** - `spaceLarge` / `spaceExtraLarge` / `spaceExtraSmall` were referenced by the tab but never defined, so the margin expressions evaluated to NaN and the content collapsed flush to the glass rim (the "no padding" report). The tokens are defined; the content inset is now `padLarge + spaceMedium` (28 px) horizontally and `padLarge + spaceExtraSmall` (20 px) vertically. Clear moved from the header row to the ledger, so the segment strip cannot shift under the pointer when a finished item appears.
> 7. **Bring to front** - a Wayland toplevel cannot raise itself, and the shell's own windows are filtered out of the watcher list (`skipTaskbar` shell surfaces), so `WindowService` has no UUID for them. The new daemon verb `activate-title <caption>` runs a KWin script that matches the caption and activates the window (Hyprland uses `hyprctl dispatch focuswindow`). Clicking the drawer's open-in-window icon while the manager is already open now raises it instead of doing nothing.
>
> **Tests** (TDD, red first): `tests/tst_downloads_window.qml` (toplevel contract, drawer action, IPC, window-mode tab), `tests/tst_downloads_parts.qml` (split fallback/clamp, service/CLI/RPC wiring), `tests/tst_downloads_settings_panel.qml` (clamp rules, Config setters, controls reuse, window-only hosting), `tests/tst_downloads_window_layout.qml` (stage top stable from empty to list; segment strip x unchanged when Clear appears; Clear lives in the ledger; ledger counts and size), `tests/tst_downloads_window.qml` (raiseWindow routes through WindowService.activateWindowByTitle), `daemon/tests/test_domain_rules.rs` (caption activation script and JSON-escaped title), `daemon/tests/test_downloads_restart_safety.rs` (persistence flags, `make stop` recipe), plus `parse_task`/`set_parts` cases in the existing Rust suites.
>
> **Verified live** (shell hot-reloaded, `spectacle`): the window opened from IPC, an active throttled download showed `4 parts`; `downloads set-parts <gid> 8` changed the row to `8 parts` and the transfer continued from 5.4/30 MiB at 18 %. `downloads settings` opened the modal console over the task list: the 5 × 4 = 20 capacity equation, destination field, two stepper knobs, speed cap, and border HUD, with one primary Done action. The empty window shows the centered invitation over the ledger (IDLE · ~/Downloads · Open folder); Finished shows its row at the same stage top with 1 FINISHED · 11.9 GiB in the ledger. The dropdown and window both show the 28 px inset around the row and header, and the Finished header no longer carries Clear - it is in the ledger, so the tab strip does not move. With the manager open behind a fullscreen Edge window, `downloads open` (the same path as the drawer icon) brought it back to the front through the caption script. Test tasks, servers and partial files were removed afterwards; the user's finished download is untouched.

---

# Astral Plasma — The Settings Gear Ends A Drawer It Has No Context For

> [!NOTE]
> **Issue**: With the AI Token Quotas drawer open, moving the pointer onto the settings gear left the drawer on screen. The gear opens a window, not a drawer, so the stale card had no context.
>
> **Root cause**: The status pill's group `HoverHandler` opened the status card whenever the pointer was over the pill, but no per-icon handler ended an open drawer. The AI icon's hover only opened its card; the gear only closed on click. Moving from the AI icon to the gear therefore changed nothing.
>
> **Fix**: The gear's `MouseArea` now closes the open drawer on `entered` (as well as on click), and the group handler checks whether the pointer entered the pill over the gear before opening the status card - entering directly onto the gear closes instead of opening. Every other status icon still opens its own drawer, and the status card still opens when the pointer is elsewhere on the pill.
>
> **Tests** (TDD, red first): `tests/tst_status_group_hover_context.qml` - the gear closes on hover and click and never opens a drawer; the group still opens its card away from the gear, and leaving the pill still schedules the drawer closed.
>
> **Verified live**: opened the AI drawer via IPC and captured it. This session's virtual pointer devices were not picked up by KWin, so the hover transition itself could not be re-observed visually; the handler wiring is pinned by the contract test.

---

# Astral Plasma — The Input Method Drawer Reads fcitx5, Not A Hardcoded "US"

> [!NOTE]
> **Issue**: The dock's input-method icon showed "US", and its drawer offered only "US" plus a "Switch" button. The methods the user had added (Rime) were missing, there was no settings entry, and clicking the icon appeared to do nothing. The user asked for the drawer to be configuration-driven rather than hardcoded.
>
> **Root cause**: `KbLayoutService` hardcoded `layouts: ["US"]` and only asked KDE for the current index. The added input methods live in **fcitx5**, not in KDE's layout list, and `switchToNextLayout` on KDE with a single layout is a no-op - so the icon and drawer could never change.
>
> **Fix**:
> 1. **`services/InputMethods.js`** parses the real `busctl --json=short` payloads: fcitx5's `FullInputMethodGroupInfo` (configured methods), `CurrentInputMethod`, and KDE's `getLayoutsList` / `getLayout`. The dock badge comes from each method's own label (`en` -> `EN`, Rime's `ㄓ`); malformed output yields no items rather than a fabricated list.
> 2. **`services/InputMethodService.qml`** reads fcitx5 first (group -> methods -> current), falls back to KDE layouts, switches with `SetCurrentIM` / `setLayout`, opens the owner's settings (`Configure`, or `kcmshell6 kcm_keyboard`), and coalesces refreshes so a drawer opened mid-poll never shows a stale active row.
> 3. **`components/InputMethodList.qml`** renders one row per configured method (active row = framework's answer, click = switch) plus the settings entry, capped and scrollable; the fused drawer and the legacy dock popout both use it. The dock icon shows the active badge and is hidden when neither framework answers.
>
> **Tests** (TDD, red first): `tests/tst_input_method_config.qml` - parses the exact live fcitx5/KDE payloads, pins badge derivation, active-index lookup, malformed-input degradation, and source contracts for the service, list, drawer and dock icon.
>
> **Verified live** (shell hot-reloaded, `spectacle`): the drawer lists "Keyboard - English (US)" (EN, active) and "Rime" (ㄓ) with a "fcitx5 Settings" entry; switching fcitx5 to Rime with `SetCurrentIM` changed the highlighted row and the dock badge to ㄓ, and switching back restored EN.

---

# Astral Plasma — The Dock's Second Battery Icon (Power Profile) Is Gone

> [!NOTE]
> **Issue**: The dock's status column showed a battery icon and, directly below it, a second icon that opened the same "Battery / Power profile" card and appeared to do nothing. The user circled it and asked *"why there is a duplicated icon which does nothing?"*
>
> **Root cause**: `DockStatusIcons` declared a standalone `profileItem` beside `batteryItem`. Both requested the fused drawer, and `FusedBottomPopout` renders one section for both modes (`"battery"` and `"default"`), so the second icon's left click re-opened a panel that was already showing. Its only distinct action was middle-click `PowerService.cycleProfile()`. It was also absent from the Settings status-icon list and had no visibility guard, so it survived turning the battery indicator off.
>
> **Fix**: removed `profileItem`. The battery indicator now owns the drawer and the quick-switch gesture: left click opens the battery/profile card, middle click cycles the profile. Drawer content is unchanged - the three profile pills still live in `FusedBottomPopout`. Because the removed icon was always visible, `PowerService.hasPowerProfiles` now keeps the battery slot reachable on desktops with no battery but with `powerprofilesctl`.
>
> **Tests** (TDD, red first): `tests/tst_dock_power_profile_single_entry.qml` - no `profileItem`, exactly one `batteryItem`, that block keeps `openBottomPopout("battery")`, `PowerService.cycleProfile()`, `LeftButton | MiddleButton` and the `hasPowerProfiles` guard, and the drawer still offers power-saver/balanced/performance via `setProfile`.
>
> **Verified live** (shell hot-reloaded, `spectacle`): the rail now shows one battery entry (Bluetooth, clipboard, notifications, battery, AI, settings, power). `popout open battery` still slides out "Battery: 96% (fully-charged)", "Power profile: Balanced" and the three profile pills. `make test-rust` and `make test-qml` green.

---

# Astral Plasma — GPU "Usage" Is Measured Engine Time, Not A Clock Ratio

> [!NOTE]
> **Issue**: The dashboard showed **GPU 0 at 60 %** (and later 100 %) while the machine was idle and the NVIDIA card sat at 0 %. The user asked *"why there is high gpu usage?"*
>
> **Root cause**: For Intel GPUs the daemon derived "usage" from the RPS frequency counters:
>
> ```
> usage = (gt_act_freq_mhz − gt_min_freq_mhz) / (gt_max_freq_mhz − gt_min_freq_mhz)
> ```
>
> That is a *clock ratio*, not utilisation. On this laptop the panel runs at **240 Hz**, so the iGPU governor parks near `gt_max_freq_mhz` almost continuously: 60 % of 10 s of samples sat at the 1550 MHz ceiling. Measured independently from `/proc/<pid>/fdinfo`, the render engine was only ~33 % busy — and 0 % in `quickshell`. The number was a frequency ratio wearing a utilisation label.
>
> **Fix** — measure real engine time:
> 1. **`daemon/src/domain/gpu_engine.rs`**: parse `drm-pdev` + `drm-engine-{render,copy,video}: <ns>` from fdinfo; a client's busy time is its *busiest* engine (engines run in parallel, so summing them can exceed wall time); deltas are clamped to 0..=1; satellite PCI-slot forms (`0000:00:02.0` vs `00:02.0`) are matched explicitly, never by prefix.
> 2. **`daemon/src/infrastructure/gpu_engine_probe.rs`**: scan `/proc/*/fdinfo/*` unprivileged, fold several fds of one DRM client into one sample (they repeat the same client-wide totals), and persist the counters to `/dev/shm/astral_gpu_engine` — the shell runs `metrics` as a fresh process every tick, so a rate needs cross-process state (same pattern as `/dev/shm/astral_cpu_stat`).
> 3. **`proc_metrics.rs`**: `resolve_usage(measured, fallback)` — measurement wins; the clock ratio (Intel) and `gpu_busy_percent` (AMD) remain only as fallbacks. NVIDIA already reported real engine utilisation via `nvidia-smi`, which is why only GPU 0 looked wrong.
>
> **Tests** (TDD, red first — `cargo test --test test_gpu_engine_usage` failed to compile before the module existed):
> - `daemon/tests/test_gpu_engine_usage.rs` (12 tests): fdinfo parsing, non-DRM fds ignored, malformed/negative counters degrade to 0, busiest-engine accounting, fd duplication, clamping, slot matching, cache round-trip, partial cache corruption, counter restart (no negative load), non-monotonic timestamps.
> - `tests/tst_gpu_usage_is_measured.qml`: the daemon contract at source level — measured value feeds `usage`, `/dev/shm` cache exists, restarted counters yield no rate. Verified to fail against `HEAD` (no `gpu_engine` module, no `drm-engine-render` read, no cache).
>
> **Verified live** (rebuilt `bin/astral-plasma`):
> - Before: `GPU 0 100 %` while `gt_act_freq_mhz` sat at max and the engine was ~5–33 % busy.
> - After: `GPU 0 18–28 %` **while the clock still reads 1.55 GHz** — the number no longer follows the clock; it follows the engine, and it agrees with the independent fdinfo probe (33 % over the same period).
> - `metrics` latency unchanged (avg 117 ms vs 136 ms baseline), despite reading ~16 000 fdinfo files per tick.
> - `make test`: all Rust suites green (77), all 144 QML suites green.

---

# Astral Plasma — Volume & Brightness Leave The Dock; The Right Rail Owns Them

> [!NOTE]
> **Issue**: The dock's status column carried a volume indicator, a brightness indicator, and an in-dock "Display Brightness" drawer with preset pills — a second copy of controls the right-edge rail already provides. The user asked for the dock copies to be removed.
>
> **Root cause**: When the dock grew `audio` and `brightness` status icons, the older right-edge rail (`shell/RightEdgeControl.qml`, commit `a7814d6`) was never retired. Two writers for the same PipeWire/BrightnessService state, two visual languages for one control.
>
> **The rail stays** — it is the surface the user uses: vertical sliders, wheel scrub, click-to-mute, live glyph. What was removed is the dock duplicate:
> 1. **Indicators** (`dock/components/DockStatusIcons.qml`): `audioItem` and `brightnessItem` deleted with their hover/click/wheel wiring, so no dock item binds `PipewireAudio` or `BrightnessService` any more.
> 2. **In-dock drawers** (`dock/popouts/FusedBottomPopout.qml`): `audioSection` and `brightnessSection` (including the "Display Brightness" card with 25/50/75/100 % pills) removed, along with their `targetPopWidth` / `targetContentHeight` switch arms and stale mode names in the `mode` / `bottomPopoutMode` comments.
> 3. **Configuration**: the two ids dropped from `config/settings.json` and from the `Config.qml` fallback list.
> 4. **Stale user settings**: an existing `~/.config/astral-plasma/settings.json` still lists `brightness` and `audio`. `StatusIconsPage` now filters the list through `knownIconIds`, so the page cannot offer a switch for a control that no longer exists and its "N of M shown" header cannot lie. The user's file is left untouched.
> 5. **Ghost drawer guard** (`config/PopoutModes.js` + `Config.openBottomPopout`): a retired mode has no section, and `UnifiedShell` sizes the sliding wrapper from the active section's height — so a leftover `quickshell ipc call popout open brightness` used to slide out an empty glass card. `PopoutModes.isRetired()` makes such a request a no-op, including not hijacking a drawer that is already open.
>
> **Tests** (TDD, red first):
> - `tests/tst_dock_audio_brightness_removed.qml` — the dock declares no volume/brightness indicator and never touches the two services; the fused popout has no `audioSection` / `brightnessSection` / "Display Brightness"; `settings.json` and the `Config` defaults ship neither id; the surviving drawers (network, bluetooth, clock) are intact; and the rail still drives both services. It strips comments and string literals before scanning, so prose cannot satisfy a contract.
> - `tests/tst_retired_popout_modes.qml` — drives the pure `PopoutModes.js` rule: retired ids are inert, matching ignores case, a retired request cannot hijack an open drawer, and live modes pass through untouched.
> - `tests/tst_status_icons_stale_filter.qml` — instantiates the real `StatusIconsPage` and proves the rendered list contains only known ids.
> - `tests/tst_clipboard_and_notifications.qml` / `tst_omarchy_borrowed_features.qml` updated: they asserted the removed dock icons, so they now assert that the *rail* keeps the mute/scrub gestures and that the dock does not duplicate the volume icon.
>
> **Verified live** (shell hot-reloaded, `spectacle`):
> - The dock status column no longer shows the speaker or brightness glyphs; the remaining indicators (Bluetooth, clipboard, notifications, battery, power) still render and their drawers still open (network / bluetooth / clock each produce a full drawer diff).
> - `quickshell ipc call rightedge open` still slides the rail out (right-edge pixel diff 62x320 px) — the rail is untouched.
> - `quickshell ipc call popout open brightness` now leaves the screen at its steady frame instead of drawing a card; `popout open clock` still opens.
> - `make test`: all Rust suites green, all 143 QML suites green.
>
> **Post-mortem**: the first attempt deleted the right rail (the surface the user asked to keep) and kept the dock copies; it was reverted in full. Cause, recovery and corrective actions: [`docs/POST-MORTEM-2026-11-03-control-home.md`](docs/POST-MORTEM-2026-11-03-control-home.md).

---

# Astral Plasma — Cyberpunk Radial Cover Visualizer & Multi-Archetype Presentation

> [!NOTE]
> **Issue**: 
> 1. The user requested that the song cover visualizer be based on the radial equalizer ring effect (radial frequency bars around the circular album cover), but styled in an authentic Cyberpunk aesthetic.
> 2. Previously, the radial visualizer had cartoonish yellow/green/pink orbiting emojis (`♪ ♫ ♬`) or soft pastel rounded pills that did not fit the high-tech sci-fi theme.
>
> **Solution**:
> 1. **High-Tech Cyberpunk Radial Visualizer ([`components/RadialCoverVisualiser.qml`](file:///mnt/data/workspace/astral-plasma/components/RadialCoverVisualiser.qml) & [`components/RadialCoverRing.qml`](file:///mnt/data/workspace/astral-plasma/components/RadialCoverRing.qml))**:
>    - **Laser Sharp Geometry**: Replaced rounded ends with razor-sharp laser cuts (`ctx.lineCap = "butt"`).
>    - **Inner Laser Track & Cardinal Reticle**: Added a continuous circular laser track (`Colors.primary` at base) with 4 cardinal reticle ticks / crosshairs at 0°, 90°, 180°, and 270°.
>    - **Dual-Color Cyber Gradient**: Frequency bars smoothly gradient from Laser Cyan (`#00F0FF` / `Colors.primary`) to Hot Neon Magenta (`#FF007F` / `Colors.secondary`) at peak amplitude.
>    - **Floating Peak Caps**: Active high-energy frequencies project floating neon magenta peak caps at transient bursts.
>    - **Cyber HUD Enclosure**: Framed the visualizer with 4 sharp laser cyan corner brackets (`⌜ ⌝ ⌞ ⌟`) and micro-telemetry tags (`RADIAL // 48K`, `EQ // [20Hz - 20kHz]`).
> 2. **Dashboard Tab Presentation ([`dashboard/tabs/DashboardTab.qml`](file:///mnt/data/workspace/astral-plasma/dashboard/tabs/DashboardTab.qml))**:
>    - Enabled `RadialCoverRing` in Cyberpunk mode with `innerRadius: 42` framing the circular album art.
>    - Framed the artwork container with 4 Cyber HUD Corner Brackets (`⌜ ⌝ ⌞ ⌟`).
>    - Gated `HeatmapCoverRing` and `vizSwitchBtn` to prevent accidental switching to cartoon rainbow notes in Cyberpunk.
>    - Clean linear seek bar with laser cyan track and neon magenta playhead thumb.
> 3. **Media Tab Presentation ([`dashboard/tabs/MediaTab.qml`](file:///mnt/data/workspace/astral-plasma/dashboard/tabs/MediaTab.qml))**:
>    - `RadialCoverVisualiser` serves as the primary visualizer in Cyberpunk mode with full 240x240 dimensions.
>    - Zero regressions in Liquid Glass and Nordic Minimal modes.
> 4. **Automated Verification**:
>    - Full test suite verification across [`tests/tst_cyberpunk_media_cover.qml`](file:///mnt/data/workspace/astral-plasma/tests/tst_cyberpunk_media_cover.qml) and [`tests/tst_theme_archetype_architecture.qml`](file:///mnt/data/workspace/astral-plasma/tests/tst_theme_archetype_architecture.qml).
>    - 100% pass across Rust tests and all 121 QML test suites (`make test`).
>
> ## Visual Proof of Work
> ````carousel
> ![Dashboard Tab: Cyberpunk Radial Equalizer Cover Ring](screen_dashboard_cyber_radial_final.png)
> <!-- slide -->
> ![Media Tab: 240px Cyberpunk Radial Cover Visualizer with Reticle & Peak Caps](screen_media_cyber_radial_final.png)
> <!-- slide -->
> ![Liquid Glass: Circular Media Player (Zero Regressions)](screen_liquid_media_final.png)
> ````


---

# Astral Plasma — Design Archetype Consistency Resolution Across Buttons, Window Edges & Controls

> [!NOTE]
> **Issue**: When switching design archetypes (Liquid Glass, Nordic Minimal, Cyberpunk Neon), visual glitches appeared (e.g. detached specular hairline glint at the top of windows, orphaned caustic glow), while buttons (`PillButton`, `LiquidGlassButton`, segmented mode pills, navigation rail pills) and internal controls remained locked in round stadium pills (`radius: 9999`) and ignored archetype geometry, borders, and typography.
>
> **Root Cause**:
> 1. **Hardcoded Stadium Pill Radius in `PillButton.qml` & `LiquidGlassButton.qml`**: `PillButton.qml` computed `radius` as `(typeof Theme !== "undefined" && Theme.radiusFull) ? Theme.radiusFull : Math.round(height / 2)`. Because `radiusFull` was `9999` across archetypes, every `PillButton` across the shell and settings remained an immutable stadium pill, ignoring `Theme.radiusGlassPill` (`4` in Cyberpunk Neon, `6` in Nordic Minimal).
> 2. **Unconformed Nordic Minimal Pill Radius**: In [`theme/archetypes/NordicMinimalArchetype.qml`](file:///mnt/data/workspace/astral-plasma/theme/archetypes/NordicMinimalArchetype.qml), `radiusGlassPill` was set to `9999` instead of disciplined compact Scandinavian `6`.
> 3. **Ungated & Misaligned Specular / Caustic Optics in `SettingsWindow.qml`**: Top specular hairline glint and inner caustic ambient glow in `SettingsWindow.qml` lacked visibility gates (`Theme.material.specularEnabled` and `Theme.material.causticEnabled`), rendering an orphaned floating line across the top edge in Nordic Minimal. Furthermore, margins were hardcoded to `24px` instead of tracking `parent.radius + 2`, causing misaligned glints in low-radius modes like Cyberpunk (4px).
> 4. **Hardcoded Control & Pill Geometry in `SettingsWindow.qml`, `NexusHub.qml`, `ThemePage.qml`, and `CommandLauncher.qml`**:
>    - Close button and breadcrumb Back button hardcoded `radius: 16`.
>    - Appearance mode segmented pill and archetype selection cards hardcoded `valRadiusFull: 9999` or fixed radii.
>    - Command Launcher search bar and modal sheet hardcoded `radius: 23` and un-gated specular/caustic effects.
>
> **Solution**:
> 1. **Dynamically Bound `PillButton.qml` & `LiquidGlassButton.qml`**:
>    - Added `customRadius` and bound default radius to `Theme.radiusGlassPill` (4 in Cyberpunk Neon, 6 in Nordic Minimal, 9999 pill in Liquid Glass).
>    - Gated drop shadow (`showShadow`), top specular glare (`topGlare`), and bottom caustic rim (`bottomRim`) by `Theme.material.shadowsEnabled`, `Theme.material.specularEnabled`, and `Theme.material.causticEnabled`.
>    - Enabled neon outline borders (`border.width: Theme.glassBorderWidth`) and monospace typography (`Theme.fontMonospace`) in Cyberpunk Neon (`neon_cyber`).
> 2. **Refined `NordicMinimalArchetype.qml`**:
>    - Set `radiusGlassPill: 6`, establishing a disciplined geometric hierarchy: Modal (12px) -> Medium (8px) -> Card/Pill (6px) -> Item (4px).
> 3. **Fixed Window Glints & Margins in `SettingsWindow.qml`**:
>    - Gated top specular glint by `Theme.material.specularEnabled` and caustic glow by `Theme.material.causticEnabled`.
>    - Dynamically bound glint horizontal margins to `Math.max(parent.radius + 2, 8)`, perfectly conforming to window corners across all archetypes.
>    - Bound window close button to `Math.min(Theme.radiusGlassPill, 16)` with neon perimeter styling in Cyberpunk mode.
> 4. **Unified Settings, Dock Popouts & Command Launcher**:
>    - Updated `NexusHub.qml` back button and navigation rail items.
>    - Updated `ThemePage.qml` segmented appearance pill, archetype cards, and sample chip.
>    - Updated `CommandLauncher.qml` modal sheet and search bar to respect archetype radius, borders, and typography.
>    - Updated `GlassPill.qml`, `LiquidGlassCard.qml`, `LevelBar.qml`, and `TabBar.qml`.
> 5. **Comprehensive Verification**:
>    - Extended [`tests/tst_theme_archetype_architecture.qml`](file:///mnt/data/workspace/astral-plasma/tests/tst_theme_archetype_architecture.qml) to assert `radiusGlassPill`, `samplePillButton.radius`, `showShadow`, and `sampleGlassPill`.
>    - Passed all Rust unit tests and all 120 QML test suites (100% pass rate).
>    - Visually verified live shell and settings across all three archetypes using Spectacle and `view_file`.
>
> ## Visual Proof of Work Across Archetypes
>
> ````carousel
> ![Cyberpunk Neon: Sharp 4px rect buttons, monospace typography, neon perimeter borders, zero glint glitches](/home/hlu/.gemini/antigravity/brain/32363dec-5dab-44d7-9c38-6db78b60757d/screen_theme_cyberpunk5.png)
> <!-- slide -->
> ![Nordic Minimal: Disciplined 6px rounded rect buttons, flat matte substrate, zero specular/caustic glare](/home/hlu/.gemini/antigravity/brain/32363dec-5dab-44d7-9c38-6db78b60757d/screen_theme_nordic5.png)
> <!-- slide -->
> ![Liquid Glass: Fluid capsule buttons, 24px concentric rounds, luminous specular hairlines & caustics](/home/hlu/.gemini/antigravity/brain/32363dec-5dab-44d7-9c38-6db78b60757d/screen_theme_liquid5.png)
> <!-- slide -->
> ![Command Launcher in Cyberpunk Neon: 6px modal, 4px sharp search bar, monospace font & neon borders](/home/hlu/.gemini/antigravity/brain/32363dec-5dab-44d7-9c38-6db78b60757d/screen_launcher_cyberpunk.png)
> ````
>
> ---
>
> # Astral Plasma — Theming & Appearance Section Navigation Resolution

> [!NOTE]
> **Issue**: In the Settings "Theming & Appearance" view, clicking the section navigation pills (`Style`, `Colors`, `Shape`, `Preview`) highlighted the pill but did nothing to the page content.
>
> **Root Cause**:
> 1. **Insufficient Scroll Content Height**: `ThemePage.qml` was a minimal 290px stub containing only 5 raw items without explicit `SectionHeader` items or bottom scroll runway. Because `pageFlickable.contentHeight` was clamped to `pageFlickable.height` (~500px), `contentMaxOffset` evaluated to `0`, making scrolling physically impossible (`scrollTo` clamped any target offset to `0`).
> 2. **Missing Architectural Headers & Archetype Controls**: Unlike `SystemPage` or `DockPage`, `ThemePage` lacked `SectionHeader` anchors matching the declared zones (`styleHeader`, `colorsHeader`, `shapeHeader`, `previewHeader`), and omitted registered settings from `Theme.archetypes` (Liquid Glass, Nordic Minimal, Cyberpunk Neon) and `blurStrength`.
> 3. **Absence of Focus Feedback**: When a section zone was requested or active, no visual transition or border highlight reflected which section was currently targeted.
>
> **Solution**:
> 1. **Upgraded `ThemePage.qml` with Rich Material 3 Sections**:
>    - **Style**: Added `SectionHeader` ("Theme Style"), Dark/Light segmented switch, and full **Design Archetype** selector cards (Liquid Glass, Nordic Minimal, Cyberpunk Neon).
>    - **Colors**: Added `SectionHeader` ("Colors & Palettes"), Dynamic Wallpaper Colors toggle, and 11 chromatic swatches.
>    - **Shape**: Added `SectionHeader` ("Shape & Geometry"), Corner Radius slider (12–32px), and Blur & Specular intensity slider (30–100%).
>    - **Preview**: Added `SectionHeader` ("Live Theme Preview") with live palette swatches and sample interactive components (Filled, Tonal, Chips).
> 2. **Added Bottom Scroll Runway**: Added bottom overscroll spacing so trailing sections (`Shape`, `Preview`) can smoothly scroll to the top of the viewport.
> 3. **Reactive Focus Accent Highlights**: Bound card border colors to `root.isZoneCurrent(zoneId)`, giving instant visual feedback when navigating to any section.
> 4. **Config Integration**: Added `themeBlurStrength` and `setThemeBlurStrength` to [`config/Config.qml`](file:///mnt/data/workspace/astral-plasma/config/Config.qml).
> 5. **Automated Verification**: Wrote [`tests/tst_theme_page_navigation.qml`](file:///mnt/data/workspace/astral-plasma/tests/tst_theme_page_navigation.qml) asserting zones, anchor monotonicity, scroll runway height, archetype selection, and reactivity. 100% pass across all 120 QML suites and Rust suites (`make test`).

## Visual Proof of Work

````carousel
![Theme Page - Initial View (Style active)](/home/hlu/.gemini/antigravity/brain/32363dec-5dab-44d7-9c38-6db78b60757d/screen_theme_settings.png)
<!-- slide -->
![Theme Page - Scrolled to Shape & Geometry](/home/hlu/.gemini/antigravity/brain/32363dec-5dab-44d7-9c38-6db78b60757d/screen_theme_shape_scrolled2.png)
<!-- slide -->
![Theme Page - Scrolled to Live Theme Preview](/home/hlu/.gemini/antigravity/brain/32363dec-5dab-44d7-9c38-6db78b60757d/screen_theme_preview_scrolled.png)
<!-- slide -->
![Theme Page - Scrolled back to Theme Style](/home/hlu/.gemini/antigravity/brain/32363dec-5dab-44d7-9c38-6db78b60757d/screen_theme_style_scrolled.png)
<!-- slide -->
![Theme Page - Cyberpunk Neon Archetype Active](/home/hlu/.gemini/antigravity/brain/32363dec-5dab-44d7-9c38-6db78b60757d/screen_theme_cyberpunk.png)
<!-- slide -->
![Theme Page - Nordic Minimal Archetype Active](/home/hlu/.gemini/antigravity/brain/32363dec-5dab-44d7-9c38-6db78b60757d/screen_theme_nordic.png)
````

---

# Astral Plasma — Design Archetype Selection Resolution

> [!NOTE]
> **Issue**: Clicking the **Design Archetype** selector cards (**Liquid Glass**, **Nordic Minimal**, **Cyberpunk Neon**) in the Settings window had no effect.
>
> **Root Cause**:
> 1. **Undefined Function `root.updateSetting`**: In [`config/Config.qml`](file:///mnt/data/workspace/astral-plasma/config/Config.qml), `setThemeArchetype` called `root.updateSetting("theme", "archetype", archetypeId);`. However, `updateSetting` was never defined on `Config` (all other settings methods call `updateSettings(callback)`). When clicked, QML threw `TypeError: root.updateSetting is not a function`, silently halting execution and leaving the configuration unchanged.
> 2. **Missing `archetype` Default**: `Config.defaultSettings.theme` omitted `"archetype": "liquid_glass"`.
> 3. **Missing IPC Endpoint**: `IpcHandler { target: "theme" }` in `shell.qml` lacked `setArchetype(archetype)`.
> 4. **Missing Import in `Theme.qml`**: In [`theme/Theme.qml`](file:///mnt/data/workspace/astral-plasma/theme/Theme.qml), `import "../config"` was omitted. `typeof Config` silently evaluated to `"undefined"`, so `Theme.archetypeName` remained permanently stuck on `"liquid_glass"`, never reacting when `Config.themeArchetype` changed.
> 5. **Unconnected Glass & Border Tokens in `Colors.qml`**: [`theme/Colors.qml`](file:///mnt/data/workspace/astral-plasma/theme/Colors.qml) hardcoded `glassParams` and `glassBorderSpecular` rather than binding to `Theme.activeArchetype.glassParams` and `Theme.material.surfaceStyle`. As a result, surface alphas and border glints never adapted to the active archetype.
>
> **Solution**:
> 1. **Implemented `Config.setThemeArchetype` & `updateSetting`**: Updated `setThemeArchetype` to mutate `cfg.theme.archetype` through `updateSettings(cfg => ...)`, and added generic `updateSetting(section, key, value)` on `Config`.
> 2. **Added `defaultSettings.theme.archetype: "liquid_glass"`**: Ensures deep merges retain the canonical default archetype.
> 3. **Exposed IPC Target**: Added `setArchetype(archetype: string): void` to `IpcHandler { target: "theme" }` in [`shell.qml`](file:///mnt/data/workspace/astral-plasma/shell.qml).
> 4. **Connected `Theme.qml` to `Config`**: Added `import "../config"` to [`theme/Theme.qml`](file:///mnt/data/workspace/astral-plasma/theme/Theme.qml). `Theme.activeArchetype` now reactively switches between `LiquidGlassArchetype`, `NordicMinimalArchetype`, and `CyberpunkNeonArchetype`, dynamically driving `Theme.radiusLarge`, `Theme.radiusMedium`, `Theme.fontFamily`, and `Theme.material`.
> 5. **Connected `Colors.qml` to Dynamic Archetype Optical Parameters**:
>    - Bound `Colors.glassActive` to `Theme.activeArchetype.glassParams` (high matte alpha for Nordic Minimal, deep OLED black for Cyberpunk Neon, crystalline transparency for Liquid Glass).
>    - Bound `Colors.glassBorderSpecular` to `Theme.material.surfaceStyle`: glowing laser neon for Cyberpunk, understated hairline outline for Nordic Minimal, and white/accent specular glint for Liquid Glass.
> 6. **Resilient Card Binding**: Added `archetypeId` fallback and bound `archId` on `archCard` in [`settings_gui/pages/ThemePage.qml`](file:///mnt/data/workspace/astral-plasma/settings_gui/pages/ThemePage.qml).
> 7. **Automated Verification**: Updated [`tests/tst_theme_archetype_architecture.qml`](file:///mnt/data/workspace/astral-plasma/tests/tst_theme_archetype_architecture.qml) asserting `setThemeArchetype`, `updateSetting`, and `archetype` settings mutation contracts. 100% pass across all 120 QML test suites and Rust suites.

## Live Archetype Comparison

````carousel
![Cyberpunk Neon: Monospace fonts, 4px sharp corners, glowing neon perimeter border](/home/hlu/.gemini/antigravity/brain/32363dec-5dab-44d7-9c38-6db78b60757d/screen_theme_cyberpunk4.png)
<!-- slide -->
![Nordic Minimal: Clean sans fonts, 12px disciplined corners, matte subtle border](/home/hlu/.gemini/antigravity/brain/32363dec-5dab-44d7-9c38-6db78b60757d/screen_theme_nordic4.png)
<!-- slide -->
![Liquid Glass: Fluid sans fonts, 24px concentric rounds, specular top glint](/home/hlu/.gemini/antigravity/brain/32363dec-5dab-44d7-9c38-6db78b60757d/screen_theme_liquid4.png)
````

---

# Astral Plasma — Omarchy Features & AI-Centric Theme Integration

> Complete architectural report and proof of work: see [`REPORT.md`](file:///mnt/data/workspace/astral-plasma/REPORT.md).

We have implemented curated workflow patterns and developer aesthetics from Omarchy (`omacom/omarchy`), centering the theme on an **AI-first architecture**:
1. **Curated Developer & Signature AI Palettes**: Added 7 Material 3 schemes (`astral-ai`, `catppuccin`, `tokyo-night`, `nord`, `everforest`, `gruvbox`, `rose-pine`) in [`theme/Colors.qml`](file:///mnt/data/workspace/astral-plasma/theme/Colors.qml), 100% WCAG AA 4.5:1 contrast certified.
2. **AI-Centric Reactive System**: Dynamic aura tokens (`Colors.aiActive`, `Colors.aiActivityColor`, `Colors.aiActivityIntensity`, `Colors.aiGlowColor`) reacting to live agent activity.
3. **AI-First Command Launcher Prompt Dispatch**: `>ai <prompt>`, `>ask`, and `>agent` dispatch mode in [`shell/CommandLauncher.qml`](file:///mnt/data/workspace/astral-plasma/shell/CommandLauncher.qml) with interactive card preview and instant terminal summon.
4. **System-Wide Palette Broadcasting**: [`services/ThemeExportService.qml`](file:///mnt/data/workspace/astral-plasma/services/ThemeExportService.qml) exporting `colors.toml`, `current-palette.json`, and `agent-theme.env` with user hook execution.
5. **Multi-Action Mouse Gestures**: Left/right/middle click support across dock pills (Terminal, Command Launcher, 12h/24h Clock, Audio volume/mute, Bluetooth power, Power profile cycle, AI agent launch).
6. **"Make Sense of a Crash" (Crash-to-Agent Diagnostics)**: Omarchy's signature diagnostic workflow in [`services/NotificationService.qml`](file:///mnt/data/workspace/astral-plasma/services/NotificationService.qml) and [`daemon/src/infrastructure/crash_monitor.rs`](file:///mnt/data/workspace/astral-plasma/daemon/src/infrastructure/crash_monitor.rs) injecting interactive *"Diagnose with <Agent>"* actions on application crashes to summon the agent CLI with stack traces and journal logs.
7. **Desktop Agent Tools & Skill Specification (`astral-plasma tool`)**: Native machine-readable CLI tools (`windows`, `workspaces`, `metrics`, `crash`, `notify`) and Agent Skill definition ([`.agents/skills/astral-desktop-tools/SKILL.md`](file:///mnt/data/workspace/astral-plasma/.agents/skills/astral-desktop-tools/SKILL.md)).
8. **Zero Regressions**: 100% Rust unit tests passed; all 123 QML test suites passed ([`tests/tst_crash_diagnostics_service.qml`](file:///mnt/data/workspace/astral-plasma/tests/tst_crash_diagnostics_service.qml), [`tests/tst_omarchy_borrowed_features.qml`](file:///mnt/data/workspace/astral-plasma/tests/tst_omarchy_borrowed_features.qml)).

---

# Astral Plasma — AI Assistant Copilot & Global Shortcuts Resolution

We have resolved all reported issues regarding the AI Copilot chat streaming, brand styling, provider/model configuration discovery, and KWin global shortcut conflicts.

---

## 1. Key Accomplishments

### 1.1. AI Copilot Chat Streaming Fix (Root Cause Resolution)

- **Root Causes of the "Thinking..." Hang**:
  1. **Node.js Subprocess Pipe Deadlock**: When `pi` was spawned through Rust `std::process::Command` without `cmd.stdin(Stdio::null())`, Node.js inherited an open stdin handle from Quickshell and kept listening for interactive input indefinitely, deadlocking before emitting the final turn completion.
  2. **Quickshell `SplitParser` Missing Delimiter**: In [`services/AssistantService.qml`](file:///mnt/data/workspace/astral-plasma/services/AssistantService.qml), `streamProc`'s `SplitParser` lacked `splitMarker: "\n"`, causing chunks to buffer until process termination rather than streaming line by line.
  3. **Unsupported `--thinking minimal` Parameter**: CLI argument `--thinking minimal` caused providers like `opencode-go` to fail with HTTP 400 (`Invalid request parameters`).

- **Permanent Architectural Solution**:
  - In [`daemon/src/infrastructure/assistant_harness/pi_harness.rs`](file:///mnt/data/workspace/astral-plasma/daemon/src/infrastructure/assistant_harness/pi_harness.rs), piped stdin to `Stdio::null()`, invoked `pi` with `--mode json`, and parsed line-delimited events:
    - `message_update` (`text_delta`) $\to$ `AssistantEvent::TextChunk`
    - `tool_execution_start` $\to$ `AssistantEvent::ToolProposal`
    - `agent_settled` $\to$ `AssistantEvent::TurnCompleted`
  - In [`services/AssistantService.qml`](file:///mnt/data/workspace/astral-plasma/services/AssistantService.qml), added `splitMarker: "\n"` to both `stdout` and `stderr` `SplitParser` handlers, updating chat bubbles incrementally as tokens stream in.
  - Verified live: Prompt "hi" responds with formatted markdown in under 4 seconds.

---

### 1.2. Brand Icon Redesign (Eliminated the Ugly Blue Box)

- **Root Cause**:
  - The previous header icon container used a solid, opaque `#0c4a6e` blue square (`Colors.m3primaryContainer`), clashing with the translucent frosted glass panel.
  - `MaterialIcon` only checked `root.text` instead of `root.iconName`, rendering an empty glyph and leaving an ugly dark blue box.

- **Solution**:
  - Redesigned the brand icon into a refined **Liquid Glass Squircle** (`34×34`, `radius: 10`) with subtle translucent substrate (`Qt.rgba(Colors.primary.r, Colors.primary.g, Colors.primary.b, 0.14)`), `1px` specular border (`Qt.alpha(Colors.primary, 0.35)`), and a top glare hairline.
  - Replaced font-dependent glyphs with a crisp, geometric vector sparkle mark (`auto_awesome`) that inherits dynamic palette tinting.

---

### 1.3. Provider & Model Configuration

- **Settings Hub Integration**:
  - Added a dedicated **AI Copilot & Assistant Configuration** section to [`settings_gui/pages/AiPage.qml`](file:///mnt/data/workspace/astral-plasma/settings_gui/pages/AiPage.qml) accessible via `Meta+,` or the gear/tune icons.
  - Provides interactive chips to select engine harnesses (Pi Agent / Hermes Agent), providers (OpenCode Go, Gemini, Claude, DeepSeek, OpenAI, MiniMax, Ollama), and dynamic model lists.
- **In-Drawer Model Selector**:
  - In [`assistant/components/ModelProviderBar.qml`](file:///mnt/data/workspace/astral-plasma/assistant/components/ModelProviderBar.qml), fixed dropdown menu z-index (`z: 200`) so dropdowns pop over chat messages rather than hiding beneath them.
  - Added a direct `tune` settings shortcut button in both `ModelProviderBar` and `AssistantHeader`.

---

### 1.4. Meta (Super) Key & Global Shortcut Resolution (Root Cause & Permanent Fix)

- **Root Cause Analysis**:
  1. **Premature Removal of Bare `Meta`**: In an earlier change, `AstralOverview` was rebound from `"Meta"` to `"Meta+W"` out of a mistaken belief that registering `"Meta"` in KWin caused modifier key hijacking. This left the physical `Meta` key completely unbound across the desktop (`kglobalacceld` returned `[]` for keycode `16777250` and `268435456`).
  2. **KWin 6.7 / Plasma 6.1+ Modifier-Only Architecture**: In Plasma 6.1+ Wayland, modifier-only shortcuts are handled natively by `kglobalacceld` on key-release (tap-only). They do NOT intercept `Meta` when used in combination with other keys (such as `Meta+C`, `Meta+Space`, `Meta+D`, or `Ctrl+Meta+Left/Right`).
  3. **KWin Script Load Path**: In [`scripts/bind_shortcuts.sh`](file:///mnt/data/workspace/astral-plasma/scripts/bind_shortcuts.sh), `qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.loadScript` was passing the directory path rather than the script entry point (`contents/code/main.js`), failing to dynamically reload the script package in running KWin sessions.

- **Permanent Architectural Solution**:
  1. In [`kwin/astral-plasma-shortcuts/contents/code/main.js`](file:///mnt/data/workspace/astral-plasma/kwin/astral-plasma-shortcuts/contents/code/main.js), restored bare `"Meta"` for `AstralOverview`.
  2. In [`scripts/bind_shortcuts.sh`](file:///mnt/data/workspace/astral-plasma/scripts/bind_shortcuts.sh), configured dual binding for `AstralOverview` (`Meta\tMeta+W`, with both `16777250` and `268435543` registered over D-Bus).
  3. Released `plasmashell`'s claim on `Meta` by assigning its fallback to `Alt+F1`, ensuring single ownership by Astral Plasma without competing triggers.
  4. Fixed KWin script reload to invoke `loadScript "$KWIN_SCRIPT_DEST/contents/code/main.js"`.
  5. Updated test assertions in [`daemon/tests/test_shortcuts_domain.rs`](file:///mnt/data/workspace/astral-plasma/daemon/tests/test_shortcuts_domain.rs) and [`tests/tst_active_apps_overview_wiring.qml`](file:///mnt/data/workspace/astral-plasma/tests/tst_active_apps_overview_wiring.qml) to verify the restored `Meta` key contract.

---

## 2. Global Shortcuts Reference Table

| Action | Shortcut | Target / Mechanism |
| :--- | :--- | :--- |
| **Active Apps Overview** | `Meta` (bare tap) / `Meta+W` | KWin action $\to$ daemon $\to$ `quickshell ipc call overview toggle` |
| **Command Launcher** | `Meta+Space` | KWin action $\to$ daemon $\to$ `quickshell ipc call launcher toggle` |
| **AI Assistant Copilot** | `Meta+C` | KWin action $\to$ daemon $\to$ `quickshell ipc call assistant toggle` |
| **Central Dashboard** | `Meta+D` | KWin action $\to$ daemon $\to$ `quickshell ipc call dashboard toggle` |
| **Nexus Settings** | `Meta+,` | KWin action $\to$ daemon $\to$ `quickshell ipc call settings toggle` |
| **Wallpaper Picker** | `Meta+Shift+W` | KWin action $\to$ daemon $\to$ `quickshell ipc call launcher open wallpaper` |
| **KDE Desktop Switch** | `Ctrl+Meta+Left/Right` | KDE Native (no modifier interception) |

---

## 3. Visual Proof of Work

### Proof 1: Real-Time AI Chat Response in Astral Copilot
The chat response to `"hi"` renders with instant real-time markdown formatting and no stalling on "Thinking...":

![AI Chat Streaming Proof](/home/hlu/.gemini/antigravity/brain/6243245e-1de1-4944-8e6d-a8a7cf6545aa/chat_streaming_response.png)

### Proof 2: Settings Hub AI Copilot & Provider/Model Configuration
The Nexus Settings page (`Meta+,` or via Copilot `tune` / `settings` icon) showing active Harness, Provider, and Model selection:

![Settings AI Configuration Proof](/home/hlu/.gemini/antigravity/brain/6243245e-1de1-4944-8e6d-a8a7cf6545aa/settings_ai_configuration.png)

### Proof 3: Bare Meta Key Triggering Active Apps Overview
Tapping the bare `Meta` key (or `Meta+W`) opens the fullscreen Active Apps Overview with live thumbnails, backdrop blur, and search:

![Meta Shortcut Overview Proof](/home/hlu/.gemini/antigravity/brain/6243245e-1de1-4944-8e6d-a8a7cf6545aa/meta_shortcut_overview_proof.png)

---

## 4. Automated Test Verification

All tests pass 100% with zero regressions across all suites:

```bash
make test
```

- **Rust Daemon Suites**: 300+ tests passed (`test_shell_ipc`, `test_shortcuts`, `test_shortcuts_domain`, `test_branding`, `test_shell_scripts`, etc.).
- **QML Offscreen Suites**: 90/90 suites passed (`tst_assistant_drawer`, `tst_ai_page`, `tst_active_apps_overview_wiring`, `tst_command_launcher`, `tst_nexus_hub`, etc.).

---

## 5. Lucide Bot Message Square Icon, Session Deletion & Auto-Minimize Fixes

### 5.1. Session Deletion Click Priority Fix
- **Issue**: Clicking the session trash/delete icon failed to delete sessions and instead loaded the clicked session.
- **Root Cause**: In [`assistant/components/SessionListDrawer.qml`](file:///mnt/data/workspace/astral-plasma/assistant/components/SessionListDrawer.qml), `cardMouse` (the MouseArea to load a session) was declared after `RowLayout` in the QML tree, silently overlaying `delMouse` and consuming all click events.
- **Fix**: Reordered `cardMouse` with `z: 0` before the card content, and gave `delButtonRect` / `delMouse` explicit `z: 10` priority with `mouse.accepted = true;`. Deletions now trigger immediately.

### 5.2. Official Lucide `bot-message-square` Vector Mark
- **Issue**: The Copilot icon displayed an ugly area chart / spline graph icon (`󰄧` / `nf-md-chart_areaspline`) instead of a chat icon.
- **Root Cause**: In Nerd Fonts, `\udb80\udd27` maps to a statistics graph.
- **Fix**: Integrated the official vector path from [Lucide Bot Message Square](https://lucide.dev/icons/bot-message-square) into [`components/BotMessageSquareIcon.qml`](file:///mnt/data/workspace/astral-plasma/components/BotMessageSquareIcon.qml) using Qt Quick Shapes with `RoundCap` and `RoundJoin`. Updated both the Dock capsule in [`shell/UnifiedDock.qml`](file:///mnt/data/workspace/astral-plasma/shell/UnifiedDock.qml) and the Copilot header badge in [`assistant/components/AssistantHeader.qml`](file:///mnt/data/workspace/astral-plasma/assistant/components/AssistantHeader.qml).

### 5.3. Focus-Aware Auto-Minimize & Always-on-Top Pin (superseded by §7)
- **Issue**: The floating chat window stayed on top covering other apps even when switching focus to external applications.
- **Root Cause**: Quickshell layer-shell surfaces (`WlrLayer.Overlay`) are rendered above normal XDG application windows by Wayland protocol.
- **Fix**:
  1. In [`services/WindowService.qml`](file:///mnt/data/workspace/astral-plasma/services/WindowService.qml), added `signal externalWindowActivated(string winId, string winTitle)` emitted whenever an external app gains focus.
  2. In [`config/Config.qml`](file:///mnt/data/workspace/astral-plasma/config/Config.qml), added `property bool assistantPinned: false` and `function toggleAssistantPinned()`.
  3. In [`assistant/components/AssistantHeader.qml`](file:///mnt/data/workspace/astral-plasma/assistant/components/AssistantHeader.qml), added an interactive **Pin / Always on Top** toggle button (`push_pin` icon).
  4. In [`assistant/AssistantWindow.qml`](file:///mnt/data/workspace/astral-plasma/assistant/AssistantWindow.qml), connected to `WindowService.externalWindowActivated`: when unpinned, focusing any external application smoothly auto-minimizes Astral Copilot to the dock capsule with its breathing dot indicator.

> [!NOTE]
> The auto-minimize and its Pin toggle were the *workaround* for the overlay being
> un-stackable. §7 replaces the overlay with a real toplevel window, which stacks
> normally, so both the signal handler and the Pin button are gone.

### Proof 3: Verified Lucide Bot Message Square Icon & Pin Toggle
Full screenshot showing the crisp vector `bot-message-square` icon in both the Dock capsule (left) and Copilot header badge (top left), along with the Pin button in the header action bar:

![Verified Lucide Bot Message Square & Pin Toggle](/home/hlu/.gemini/antigravity/brain/6243245e-1de1-4944-8e6d-a8a7cf6545aa/assistant_bot_chat_icon_and_pin_verified.png)

---

## 6. Chat Cannot Be Backgrounded & Ugly Setup Notice

### 6.1. Auto-Minimize Never Fired For The Window You Came From
- **Issue**: Opening the chat and switching back to the application you were using left the chat pinned on top. Switching to a *different* window did minimize it, which made the failure look intermittent.
- **Root Cause**: In [`services/WindowService.qml`](file:///mnt/data/workspace/astral-plasma/services/WindowService.qml), the activation routing read `data.msg_type === "active"` — but every watch payload serialises that field as `type` (`#[serde(rename = "type")]` in `domain/model.rs`; `msg_type` is only used by the AI-activity monitor). The branch was dead code, so `externalWindowActivated` fired only when the active window **id changed**. The daemon never records the chat itself (shell surfaces are filtered), so returning to the window you came from produced an unchanged id and no signal.
- **Fix**: Route the real wire key — `data.type === "active"` — in addition to the id-change fallback. On Hyprland, `hyprland_event_is_activation` now scopes the `active` label to genuine `activewindow` events, so a background title/move refresh stays a `windows` payload and cannot dismiss the chat mid-sentence.
- **Verification**: `tests/tst_active_window_watcher.qml` now mirrors the routing, asserts same-id re-activation announces, that window-list refreshes stay silent, and pins the `data.type` key as a source contract; `daemon/tests/test_watch_events.rs` covers the Hyprland classification.

**Before** (re-activating the same KWrite window — chat stayed pinned) / **After** (same action backgrounds it):

![Background bug — before](docs/voice-proof/background-before-same-window.png)

![Background fix — after](docs/voice-proof/background-after-same-window.png)

### 6.2. Setup Notice Redesign
- **Issue**: The `whisper.cpp` setup notice was one salmon-coloured sentence underlined end to end, inside its own 1px ring nested inside the composer's ring — it read as a raw hyperlink boxed in a box.
- **Fix**: In [`assistant/components/VoiceListeningStrip.qml`](file:///mnt/data/workspace/astral-plasma/assistant/components/VoiceListeningStrip.qml):
  - the reason is plain body text (`m3onSurface`, no underline);
  - the destination is its own chip — monospace path (`Settings › AI › Voice input ›`), primary tint, chevron — echoing the composer's model chip, and the whole row is the link;
  - the error tone is confined to the warning mark;
  - `showBorder: false` drops the second perimeter ring (`docs/LESSONS.md` §9.1);
  - [`services/AssistantService.qml`](file:///mnt/data/workspace/astral-plasma/services/AssistantService.qml) `describeVoiceGap` now names the reason alone, since the chip carries the destination.
- **Verification**: `tests/tst_voice_input.qml` pins the no-underline contract at runtime and by source, the chip's visibility in notice/recording/idle states, and the token-based styling.

![Redesigned setup notice](docs/voice-proof/strip-error-state.png)

### 6.3. Automated verification

```bash
make test
```

- **Rust**: 50 test binaries, 0 failures (includes the new `test_hyprland_event_classification`).
- **QML**: all suites green, including `tst_active_window_watcher` (new activation-routing assertions) and `tst_voice_input` (new notice-design assertions).


---

## 7. The Copilot Is Now A Real Window (Alt+Tab Reachable)

### 7.1. Alt+Tab Never Listed The Chat
- **Issue**: `Alt+Tab` could not find the AI Copilot in the window list — it only ever offered the other applications.
- **Root Cause**: The copilot was a full-screen layer-shell overlay (`WlrLayershell.layer: WlrLayer.Overlay`). KWin sets `skipSwitcher` on every `zwlr_layer_shell_v1` surface (`src/layershellv1window.cpp`), and the switcher only offers windows passing `wantsTabFocus() && !skipSwitcher()` (`src/tabbox/tabbox.cpp`). A layer surface can therefore never be listed, whatever the shell asks for.
- **Fix**: [`assistant/AssistantWindow.qml`](file:///mnt/data/workspace/astral-plasma/assistant/AssistantWindow.qml) is now a `Quickshell.FloatingWindow` — a real xdg-toplevel:
  - **Identity**: `title: "Astral Copilot"`, so the switcher, taskbars and window lists have a name to show.
  - **Frameless**: KWin decorates every toplevel by default, so the daemon installs a `kwinrulesrc` rule (`noborder=true`, `noborderrule=2`, `wmclass=org.quickshell`) at startup — [`daemon/src/infrastructure/kwin_window_rules.rs`](file:///mnt/data/workspace/astral-plasma/daemon/src/infrastructure/kwin_window_rules.rs). The card keeps drawing its own glass edge and `BackgroundEffect.blurRegion` still blurs the backdrop.
  - **Size**: the drawer publishes `preferredWidth`/`preferredHeight` (screen-aware, and wide enough for the sessions sidebar when it is visible) and the window binds `implicitWidth`/`implicitHeight` to them; `minWidth`/`minHeight`/`maxWidth`/`maxHeight` travel as the window's size hints. The compositor owns the geometry once the surface is mapped.
  - **Move & resize**: the card background and the header call `startSystemMove()`, the edge handles call `startSystemResize(edges)`. All item-coordinate dragging, clamping and recentering are gone.
  - **Parking**: `Config.assistantMinimized` still hides the window to the dock capsule. A Wayland client may request a minimize but has no request that undoes one, so the parked state has to stay shell-owned.
  - **Retired**: the overlay's input `mask` and click-through contract, the auto-minimize on external activation, and the Pin button — the last two existed only to compensate for an overlay that floated above everything.

### 7.2. Verification
- `make test`: Rust and QML suites green, 0 failures. New coverage: `daemon/tests/test_kwin_window_rules.rs` (rule rendering, group-id allocation, idempotency) and the rewritten toplevel contracts in `tests/tst_assistant_drawer.qml`.
- Live KWin window-list dump of the running chat:

  ```
  caption=Astral Copilot class=org.quickshell normal=true skipTaskbar=false skipSwitcher=false noBorder=true
  ```

  `skipSwitcher=false` → it is in `Alt+Tab`; `noBorder=true` → frameless; `normal=true` → a first-class window.
- Switching to another application leaves the window mapped, behind it, and still listed (`minimized=false`, `active=false`); the dock capsule parks and restores it as before.

**Open** (frameless glass card over the editor behind it) / **parked in the dock capsule**:

![Copilot as a real window](docs/voice-proof/copilot-toplevel-open.png)

![Copilot parked in the dock](docs/voice-proof/copilot-toplevel-parked.png)

---

## 8. The Desktop Session Has An Owner Now (Shortcut Outage Fix)

### 8.1. Every Shortcut Was Dead After A Shell Restart
- **Issue**: Restarting the shell left every global shortcut dead — bare `Meta`, `Meta+Space`, `Meta+C`, `Meta+D`. Nothing reported an error, and a second restart often brought them back, so it read as a flaky daemon.
- **Root Cause**: four independent restore paths and no owner of the session:
  1. The daemon restored the desktop on SIGTERM/SIGINT ([`daemon/src/application/watch_events.rs`](file:///mnt/data/workspace/astral-plasma/daemon/src/application/watch_events.rs)).
  2. It restored again on stdin EOF — that is, when the shell exited.
  3. [`shell.qml`](file:///mnt/data/workspace/astral-plasma/shell.qml) restored in `Component.onDestruction`, which also runs on a QML **reload**.
  4. Taking the keys back afterwards depended on the daemon's watcher starting promptly, so the gap between "desktop given back" and "keys claimed again" belonged to nobody.

  A reload is not an exit, and a signal is not a request.
- **Fix**:
  - **Claim through the journal**: `bind_shortcuts()` is now a no-op when the requested mode is already claimed, and the daemon claims via `ShortcutControlUseCase::backup_and_bind`, so the session journal (`AstralShortcutSessionBackup`, now carrying `mode`) is written *before* the keys are taken.
  - **One reconciler owns desired state**: [`daemon/src/application/desktop_reconciler.rs`](file:///mnt/data/workspace/astral-plasma/daemon/src/application/desktop_reconciler.rs) replaces the panel-only watchdog. Every 5 s it repairs drift in the Plasma panels, the shortcut claim, the shortcut KWin script, and the frameless window rule, in the fixed order defined by `plan_repairs` in [`daemon/src/domain/desktop_integration.rs`](file:///mnt/data/workspace/astral-plasma/daemon/src/domain/desktop_integration.rs).
  - **Signals never release the desktop**: SIGTERM/SIGINT and stdin EOF now exit without mutating anything. Release happens only through the watchdog — which supervises the **shell** pid (`libc::getppid()`) and honours `plasma.autoRestoreOnExit` ([`daemon/src/application/plasma_service.rs`](file:///mnt/data/workspace/astral-plasma/daemon/src/application/plasma_service.rs)) — or through the explicit `astral-plasma plasma restore`. `shell.qml` no longer restores on `Component.onDestruction`.
  - **The reported dropdown bug, same round**: the Copilot's provider/model menus in [`assistant/components/ModelProviderBar.qml`](file:///mnt/data/workspace/astral-plasma/assistant/components/ModelProviderBar.qml) only closed when the pointer left the 44px strip that opens them. An outside-click catcher sized to the window (below the popups in z-order, above everything else) now dismisses them from a click anywhere else.
  - **The reported missing scrollbar, same round**: the chat stream had no scroll affordance at all, so a long session read as clipped. [`components/GlassScrollIndicator.qml`](file:///mnt/data/workspace/astral-plasma/components/GlassScrollIndicator.qml) is now the shell's single scroll indicator — a thin capsule that tracks `contentY`/`contentHeight`, faintly visible at rest for a stream and hidden at rest for the dock's transient menu, which now uses the same component instead of its own copy.

### 8.2. Verification

```bash
make test
```

- **Rust**: 579 passed, 0 failed.
- **QML**: all suites green.
- **New coverage**: [`daemon/tests/test_desktop_lifecycle.rs`](file:///mnt/data/workspace/astral-plasma/daemon/tests/test_desktop_lifecycle.rs) spawns the *real* binary against a temp `XDG_CONFIG_HOME` and asserts `claiming_twice_changes_nothing`, `releasing_gives_the_original_keys_back` (original keys restored byte-for-byte), `a_termination_signal_is_not_user_intent` (SIGTERM mutates no external file), `a_restart_resumes_the_recorded_mode`, and `a_legacy_journal_learns_its_mode`; [`daemon/tests/test_shell_scripts.rs`](file:///mnt/data/workspace/astral-plasma/daemon/tests/test_shell_scripts.rs) adds the startup-claim contract, the bind/restore lock, "already bound is left alone", the cross-language label agreement, and the single-writer ownership contract.

---

## 9. Legibility & Intent Round: Scrollbars, Hover Dwell, Settings Deep Links

Four reports from the same sitting, each fixed at its cause rather than at the symptom.

### 9.1. The Chat Had No Scroll Affordance
- **Issue**: a long session read as a clipped one - nothing showed that the chat scrolls, and the bar that did exist could not be grabbed.
- **Fix**: [`components/GlassScrollIndicator.qml`](file:///mnt/data/workspace/astral-plasma/components/GlassScrollIndicator.qml) is now the shell's single scroll affordance, used by the chat stream *and* the dock's popout menu (which previously kept a private copy):
  - it tracks `contentY`/`contentHeight`, sizes itself to the visible fraction (`max(24px, track²/content)`) and maps position over the full travel;
  - it is **draggable**: press the bar to keep your grab offset, press the track to centre the bar there - so a click jumps and the same press scrubs;
  - its pointer target is 12px wide (`hitWidth`) while the bar stays 3-4px, because a 3px capsule is not a grab target;
  - the chat keeps it faintly visible at rest (`restingOpacity: 0.45`), the transient menu hides it (`0`) - same component, both behaviours.
- **The resize-handle collision**: the window's own resize handles sit on the card's edge and were stealing the bar (the pointer became a resize cursor and the window resized instead of scrolling). The chat area now reserves a 14px lane (`chatHost.Layout.rightMargin`), the bar rides the *content's* edge, the right handle narrowed to 8px, the corner handle to 12×12, and the strip's cursor is an arrow (closed hand while dragging) - never a resize cursor.
- **Tests**: `tst_assistant_drawer.qml` §27 - visibility and mapping on probe flickables (top/middle/bottom/clamped), a simulated drag that must land exactly at the end, `hitWidth > barWidth`, and the geometry contract that the strip sits clear of the widest resize handle.

### 9.2. The Top Drawer Opened On An Accidental Top-Edge Touch
- **Issue**: reaching for a browser tab crosses the top edge, and the dashboard opened instantly.
- **Fix**: [`shell/UnifiedShell.qml`](file:///mnt/data/workspace/astral-plasma/shell/UnifiedShell.qml) arms a 450ms **hover-intent** timer on `onEntered` instead of opening; `onExited` cancels it; a click still toggles immediately. The 350ms auto-close grace is unchanged.
- **Tests**: `tst_top_drawer_autoclose.qml` mirrors the dwell behaviour and pins the shell's own source (the hover must arm the timer, must not set `dashboardVisible` directly, must cancel on exit). That file's `assert` also now aborts instead of only logging - it used to print PASS while failing.

### 9.3. "Settings › AI › Voice input" Opened The Page, Not The Section
- **Issue**: the Copilot's setup notice promised the voice section; clicking it opened the AI page at the top, so nothing appeared to happen.
- **Fix**: `Config.openSettings(page, section)` carries a section request; [`settings_gui/NexusHub.qml`](file:///mnt/data/workspace/astral-plasma/settings_gui/NexusHub.qml) resolves it through an opt-in `sectionY(name)` on the page and scrolls once the layout settles (it re-tries on `contentHeight` changes, and clamps). [`settings_gui/pages/AiPage.qml`](file:///mnt/data/workspace/astral-plasma/settings_gui/pages/AiPage.qml) maps the voice panel into the page's coordinate space - its own `y` is relative to the card it sits in. The `settings open` IPC gained the section argument so the link is testable end to end.
- **Verified live**: `settings open ai voice` lands with the **Voice Input** heading on screen.

### 9.4. The Settings Window Was Two Rounded Panels Butted Together
- **Issue**: the right pane was fully transparent, so a page of options dissolved into the wallpaper - and once it got a substrate of its own it became a second rounded panel sitting against the rounded rail, with the wallpaper showing through the corner notches between them.
- **Fix - one plate, one hairline**: the substrate moved into the palette as `Colors.glassPanelSubstrate` (lifted dark base at 0.82 alpha in dark mode, near-white at 0.84 in light) and now sits on the **window card** (`dialogBox`), not on a pane. The navigation rail is a tinted strip *inside* that plate (a whisper of lift, no radius), the content pane is transparent and square, and a single specular hairline inset from the plate's edges divides them. The outer radius stays the card's alone, so the corners are concentric instead of competing - the rule from LESSONS 9.1, applied to the window itself. The Copilot card uses the same token, so both surfaces share one recipe.
- **Tests**: `tst_nexus_hub.qml` pins the token's definition and both alphas (0.75 ≤ a < 1.0), that the window card carries the substrate, that **neither** the rail nor the content pane declares a radius, that the pane is transparent, and that the hairline seam exists; `tst_assistant_drawer.qml` pins that the Copilot card uses the shared token and does not re-inline the recipe.

**Verification**: `make test` - Rust 579 passed / 0 failed, all QML suites green.

---

## 10. Speech Models: Real Progress, A Remove Path, And A Drawer That Stays Shut

### 10.1. The Download Sat At 0% And Then Said "Downloaded"
- **Issue**: a 1.5 GiB model download showed `0%` for its whole life and then announced itself as done.
- **Two causes, both silent**:
  1. **The meter was silenced.** The installer passed `curl --silent` *and* `--progress-bar`; `--silent` suppresses the meter, so curl emitted nothing to parse. Dropped `--silent` (errors still surface through `--show-error`).
  2. **The event carried an object where the UI read a number.** Install progress reused `VoiceEvent::Level { rms }`, which serialises as `{"type":"Level","payload":{"rms":0.42}}`; the UI's guard is `typeof ev.payload === "number"`, so it never matched. Progress is now its own newtype, `VoiceEvent::Progress(f32)` → `{"type":"Progress","payload":0.42}`, and the bar parser reads the percentage curl actually prints (`#####  42.3%`) with the byte-count meter kept as a fallback.
- **Tests**: `daemon/tests/test_voice_model_store.rs` drives the real binary with a stub `curl` on `PATH` and asserts the stream is monotonic, inside 0..1, and ends at 1.0; `tst_voice_input.qml` pins that the installer parses `Progress` and not the session's `Level`.

### 10.2. A Downloaded Model Could Not Be Removed
- **Fix**: `VoiceService::remove_model` deletes the model and any staged `.part` file (returning whether anything was there), the daemon exposes `voice remove-model [id]`, `AssistantService.removeVoiceModel` drives it, and the settings' model row grows a **delete** control that appears only while a model is present. Removing an absent model is a no-op, not an error, so the UI can call it blind.
- **Tests**: the model-store test covers install → remove → remove-again (`"removed":true` then `"removed":false`); `tst_ai_page.qml` pins that the control exists and follows model presence.

### 10.3. The Engine And The Model Are Different Things
- **Issue**: the settings said "Downloaded" while the chat said the engine was missing, which read as a contradiction.
- **Fix**: the gap copy names the engine explicitly ("whisper.cpp engine not installed") in both surfaces, and the installer's model directory now resolves through the same env-aware helper the readiness probe uses (`ASTRAL_VOICE_MODEL_DIR`), so "installed to X, checked at Y" cannot happen.

### 10.4. The Top Drawer Opened On Every Reload
- **Issue**: every theme restart popped the top drawer open.
- **Root cause**: `Config.dashboardVisible` initialised from `settings.dashboardVisible`, and `config/settings.json` shipped `"dashboardVisible": true`. A transient overlay state was being restored from disk.
- **Fix**: the initialiser reads only the test override (`ASTRAL_PLASMA_DASHBOARD_OPEN`), exactly like `settingsVisible`; the shipped defaults no longer carry the key. `tst_top_drawer_autoclose.qml` pins both (no settings read in the initialiser, no transient key in the defaults).

### 10.5. The Install Command Assumed Arch
- **Issue**: "whisper.cpp engine not installed. Run: `sudo pacman -S whisper-cpp`" - true on Arch, a dead end on Debian, Fedora, openSUSE or NixOS, where the package manager and even the package name differ.
- **Fix**: the suggestion is now derived from `/etc/os-release` (`ID` **and** `ID_LIKE`, since derivatives like CachyOS declare the family rather than the id): `pacman`, `apt` (`whisper.cpp`), `dnf`, `zypper`, `nix-shell`, or - for a distribution we cannot name a package for - the upstream build link, never an invented command. `VoiceStatus.engine_install_command` carries it to the UI, and the doctor's engine recommendation uses the same helper.
- **Tests**: `test_voice_domain.rs` maps eight distributions (including `ID=cachyos`/`ID_LIKE=arch`, `ID_LIKE="rhel centos fedora"`, and an unknown id) and requires every named manager's command to be runnable and to name the engine; `test_voice_model_store.rs` asserts a missing engine's status carries that command; `tst_ai_page.qml` renders the daemon's command and falls back to the upstream link, and `tst_voice_input.qml` forbids a hardcoded package manager in the page.

- **Staleness**: the settings page only re-probed readiness when its cached status was `null`, so a status captured at shell start could describe an engine that had since been installed. The page now re-probes whenever it becomes visible (the probe is documented as cheap and safe to call often).

**Verification**: `make test` - Rust 583 passed / 0 failed, all QML suites green. Live: the settings row reads "Run: sudo pacman -S whisper-cpp" on this CachyOS host, rendered from `voice status` rather than from any string in the QML.

---

## 11. Backgroundable Settings & The Stale Voice Probe

### 11.1. The Settings Panel Could Not Be Backgrounded

- **Issue**: the settings window stayed above every application window. Clicking a browser left the panel pinned on top, and `Alt+Tab` could not reach it.
- **Root Cause**: [`settings_gui/SettingsWindow.qml`](file:///mnt/data/workspace/astral-plasma/settings_gui/SettingsWindow.qml) was still the overlay the Copilot retired in §7 - a full-screen `PanelWindow` on `WlrLayer.Overlay` plus a card-sized input `mask`. A layer surface is protocol-pinned above all xdg-toplevels, so no rule or flag could ever send it to the background.
- **Fix**: migrated the settings surface to `Quickshell.FloatingWindow`, exactly like [`assistant/AssistantWindow.qml`](file:///mnt/data/workspace/astral-plasma/assistant/AssistantWindow.qml):
  - **Identity**: `title: "Astral Settings"`, so the switcher and window lists have a name to show.
  - **Frameless**: the daemon's existing KWin rule (`kwinrulesrc`, `wmclass=org.quickshell`, `noborder=true`/`noborderrule=2`) already covers every Quickshell toplevel - no daemon change was required. The card keeps drawing its own glass edge.
  - **Size**: `implicitWidth`/`implicitHeight` publish the opening size (52% x 60% of the target screen, clamped to the hub's 940x640-1240x860 bounds) and the same bounds travel as `minimumSize`/`maximumSize`; the compositor owns the geometry from then on.
  - **Drag**: the card background and the header bar call `startSystemMove()`; the overlay-era `userMoved` / `clampPosition` / `resetPosition` bookkeeping was retired.
  - **Blur**: `BackgroundEffect.blurRegion` tracks the card `item` (`dialogBox`), which is now the whole surface, instead of recomputing screen coordinates.
- **Tests**: [`tests/tst_settings_draggable.qml`](file:///mnt/data/workspace/astral-plasma/tests/tst_settings_draggable.qml) was rewritten from a drag mock into the real toplevel contract (`FloatingWindow`, no `WlrLayershell`, no `mask`, window title, size hints, `startSystemMove`, no item-coordinate dragging, blur tracking `dialogBox`, shared glass substrate kept).

### 11.2. "whisper.cpp engine not installed" Survived The Install

- **Issue**: with `whisper-cpp 1.9.4` installed (`/usr/bin/whisper-cli`) and `astral-plasma voice status` reporting `engine_available: true`, the AI page still showed **"whisper.cpp engine not installed. Run: sudo pacman -S whisper-cpp"**.
- **Root Cause**: `NexusHub` loads pages through a `Loader`, so [`settings_gui/pages/AiPage.qml`](file:///mnt/data/workspace/astral-plasma/settings_gui/pages/AiPage.qml) is constructed **already visible** - `visible` never changes on the first show, so the `onVisibleChanged` re-probe the page relied on never fired. `Component.onCompleted` additionally probed only when the cached `AssistantService.voiceStatus` was `null`, so a status captured at shell start (before the engine was found) survived every page visit.
- **Fix**: `AiPage` now re-probes unconditionally on construction (`refreshVoiceReadiness()`), keeps the visibility hook, and adds a `Connections` edge on `Config.settingsVisible` so a close/re-open re-probes even while the Loader keeps the page instantiated. The probe stays cheap by contract; it is never trusted from a cached value.
- **Tests**: [`tests/tst_voice_settings.qml`](file:///mnt/data/workspace/astral-plasma/tests/tst_voice_settings.qml) pins the unconditional construction probe (no `voiceStatus === null` guard), the retained `onVisibleChanged` hook and the settings-window edge.

### 11.3. Visual Proof

**Before** - stale probe: the page says the engine is missing while the terminal behind reports `engine_available: True | gap: ready | path: /usr/bin/whisper-cli`:

![Stale voice probe before](docs/voice-proof/settings-voice-stale-before.png)

**After** - the same page re-probes on open and reads **"Ready · ggml-large-v3-turbo"**, model downloaded:

![Voice input ready](docs/voice-proof/settings-voice-ready.png)

**After** - the settings window is a normal stacked toplevel: ZCode is the active window and the panel sits behind it (its right/bottom edges occluded, still mapped and listed):

![Settings in the background](docs/voice-proof/settings-toplevel-background.png)

Live KWin window-list dump with the panel open:

```
caption='Astral Settings' cls=org.quickshell normal=True skipTaskbar=False skipSwitcher=False noBorder=True
```

`skipSwitcher=false` → reachable from `Alt+Tab`; `noBorder=true` → frameless; `normal=true` → a first-class window that stacks and backgrounds.

**Automated verification**: `make test` - all Rust and QML suites green, including the rewritten `tst_settings_draggable` toplevel contract and the new `tst_voice_settings` re-probe contracts.

---

## 12. Voice Input Was Not Using The Microphone - It Was Three Separate Failures

### 12.1. `--vad` Without Its Model Made Every Transcription Fail

- **Issue**: dictation captured audio (the strip meter moved) but every utterance ended in `Speech engine failed: /usr/bin/whisper-cli: failed to process audio`, so nothing was ever transcribed.
- **Reproduced headlessly**: driving `voice session` with `start` → 5 s → `stop` produced 244 `Level` events (RMS up to 0.63) and then the error. Running whisper-cli directly showed the same on valid WAV input: `with --vad` → exit 10, `failed to process audio`; without it the same file transcribed fine.
- **Root Cause**: the capability probe correctly reported that whisper-cli 1.9.4 advertises `--vad`, and [`build_args`](file:///mnt/data/workspace/astral-plasma/daemon/src/infrastructure/whisper_stt_adapter.rs) emitted it - but `--vad` turns on Silero inference and is fatal without `--vad-model`, and the VAD asset is deliberately not provisioned (the upstream URL 404s; spec D4). "Supported flag" was true but unusable.
- **Fix**: the VAD flags now travel as a pair or not at all. `EngineInvocation.vad_model: Option<PathBuf>` is resolved from the canonical asset (`resolve_vad_model`), and `build_args` emits `--vad --vad-model <p>` only when it exists. In every shipped install the asset is absent, so a bare `--vad` is unreachable by construction - and the daemon's own `SilenceDetector` already does the endpointing.

### 12.2. The Test Stub Encoded Our Assumption, Not whisper-cli's Behavior

- **Issue**: after the VAD fix the session exited cleanly (`Final` emitted) but the transcript was **empty** while the same engine transcribed the same audio from a shell prompt.
- **Root Cause**: `whisper-cli -oj` does not print JSON to stdout - it writes `<input>.json` beside the audio file and still prints the timestamped transcript to stdout (`output_json: saving output to '/tmp/mic2.wav.json'`). The adapter parsed stdout as JSON, failed, and returned `""` by design. The session-protocol stub printed JSON to stdout, so the test suite encoded the same wrong assumption and passed.
- **Fix**: the adapter reads the `<audio>.json` sidecar when the build advertises structured output, falls back to the timestamped stdout transcript when the sidecar is missing, and removes both files on every exit path. The protocol stub now mirrors 1.9.4 exactly - bare `--vad` is fatal, `-oj` writes the sidecar - so the regression test is meaningful.
- **Live proof of the daemon side**:
  ```
  {"type":"StateChanged","payload":{"state":"recording"}}
  {"type":"StateChanged","payload":{"state":"finalizing"}}
  {"type":"Final","payload":{"text":"*Burps*","language":"und","duration_ms":3740,
                             "engine":"whisper-cpp","model":"ggml-large-v3-turbo"}}
  ```

### 12.3. `root.childId` Is Undefined: The Session Cleanup Never Ran

- **Issue**: the shell log filled with `TypeError: Cannot read property 'stop' of undefined` at `services/AssistantService.qml[1147]` and `[1173]` on every session, so the elapsed timer never reset, the exit handshake was never re-armed, and the chat stream watchdog could not cancel a timed-out stream (`root.streamProc`).
- **Root Cause**: QML child ids are lexical captures, not properties of the root object. `root.voiceElapsedTimer` is `undefined` inside nested handlers; the bare id resolves. A minimal offscreen probe confirms both (`root.timer` → `undefined`, `timer` → `QQmlTimer`). A repo-wide audit found exactly five occurrences, all in `AssistantService.qml`.
- **Fix**: all five references now use the lexical id (`voiceElapsedTimer.stop()`, `cancelProc(streamProc)`), matching the root-scope functions that already did. `tests/tst_voice_input.qml` gained an executable scoping probe plus source contracts forbidding the pattern.
- **Live proof**: after a fresh `startVoice`/`stopVoice` session the shell log shows no `AssistantService` TypeErrors (the last lines are unrelated pre-existing `LiquidGlassFilePicker` warnings).

### 12.4. Live end-to-end proof

`quickshell ipc call assistant startVoice` → 5 s of real microphone audio → `stopVoice` → whisper inference → the transcript lands in the composer, untruncated and never auto-submitted:

![Live voice transcript](docs/voice-proof/voice-transcript-live.png)

**Automated verification**: `make test` - Rust 587 passed / 0 failed, all QML suites green. New coverage: asset-gated VAD and sidecar-first transcript reading (`test_whisper_stt_adapter.rs`), a 1.9.4-faithful engine stub with the fatal bare `--vad` and sidecar output (`test_voice_session_protocol.rs`), and payload decoding + id-scoping contracts (`tst_voice_input.qml`).

---

## 13. Voice Latency: A Faster Default, A Trimmed Utterance, And An Honest Wait

### 13.1. A Four-Second Utterance Took Twenty Seconds

- **Issue**: after clicking stop, the transcript took ~20s to appear; short dictation felt unusable.
- **Measured root cause**: the catalog default was `ggml-large-v3-turbo`, and the engine is CPU-only on every supported distribution. `whisper-cli` 1.9.4 on this 12th-gen i9 (16 cores / 24 threads) needed **26.0s for a 4.9s clip** and **12.2s for the 11s JFK sample** - roughly 5x slower than realtime.
- **Fix**: the default is now `ggml-small`, the largest tier that runs near realtime on CPU:
  - [`daemon/src/domain/voice.rs`](file:///mnt/data/workspace/astral-plasma/daemon/src/domain/voice.rs) `DEFAULT_MODEL_ID`, the catalog labels, `config/settings.json`, `Config.qml` and `AiPage.qml` fallbacks all agree on it.
  - `ggml-small`: **4.0s** for the 4.9s clip, **3.0s** for the JFK sample - with an *identical* JFK transcript:

    ```
    small       3.0s  "And so my fellow Americans, ask not what your country can do for you,
                       ask what you can do for your country."
    large-turbo 12.2s "And so, my fellow Americans, ..."   (same words)
    ```
  - The large tiers remain in the picker; a user who explicitly chose one keeps it.

### 13.2. The Engine Was Decoding Silence

- **Issue**: inference cost scaled with the whole recording, not the utterance, and quiet tails invited hallucinated text.
- **Fix**: `trim_to_speech` in [`whisper_stt_adapter.rs`](file:///mnt/data/workspace/astral-plasma/daemon/src/infrastructure/whisper_stt_adapter.rs) ships the engine the region around the frames the `SilenceDetector` already classified as speech, plus a 250 ms margin. No new threshold: the trim reuses the endpointing decision, and a no-speech capture is passed through unchanged so "nothing was said" cannot be confused with a capture failure.
- **Test**: the session-protocol stub engine logs the byte size of the WAV it receives; the suite asserts the 3.7s fixture reaches the engine as ~1.5s, not 3.7s.

### 13.3. "language not determined" During Inference

- **Issue**: the multi-second decode showed a readout that looked like a hang.
- **Fix**: the strip's state readout says **`transcribing`** while the engine runs (`VoiceListeningStrip.stateLabelText`), pinned by `tst_voice_input.qml`.

![Transcribing state](docs/voice-proof/voice-transcribing.png)

### 13.4. Live Verification

The same `voice session` invocation that used to take ~20s after stop, timestamped by event:

```
    37ms StateChanged {'state': 'recording'}
  3997ms StateChanged {'state': 'finalizing'}     <- stop clicked
  8219ms Final {'text': ..., 'duration_ms': 3400, 'model': 'ggml-small'}
```

**4.2s** of inference for a 3.4s utterance, with the trimmed capture. The transcript in the live room is still the room's audio (the built-in mic hears the speakers); that is an environment limit, not a pipeline bug - the same pipeline transcribes the JFK sample exactly.

**Automated verification**: `make test` - Rust 592 passed / 0 failed, all QML suites green.

---

## 14. Real Latency Root Causes: The Encoder Window And The Decoder Loop

### 14.1. A 2.5s "Hello" Cost 3.8s - 89% Of It Encoding 30 Seconds Of Nothing

whisper-cli's own timing breakdown for a 2.5s clip (`ggml-small`, 16 threads):

```
encode time = 3364.05 ms / 2 runs (1682.03 ms per run)
decode time =   39.54 ms / 2 runs
total time =  3790.83 ms
```

whisper.cpp always encodes its full trained context (`n_audio_ctx` 1500 = 30 s) regardless of clip length, and `language: auto` runs that encode **twice** - once to detect the language, once to transcribe. A one-word utterance paid the same encoder bill as 30 seconds of speech.

- **Fix**: [`whisper_stt_adapter.rs`](file:///mnt/data/workspace/astral-plasma/daemon/src/infrastructure/whisper_stt_adapter.rs) now sizes the encoder window to the trimmed utterance: `-ac <audio_context_for(ms)>` = `ceil(ms / 20ms) + 1.28s`, clamped to 5.12s–30s. Below the floor the engine re-processes segments (`-ac 128` duplicated the transcript and took longer than the default), above the utterance the context is pure waste.
- **Measured**: 2.5s English clip 3.9s → **2.5s** (`auto`) / **1.1s** (fixed language), identical transcript; 11s JFK 4.8s → 3.5s.

### 14.2. The Decoder Loop: 45 Seconds Of Garbage On Non-Speech Audio

The decoder is cheap on clean speech (40ms) but explodes on music: the model emits long hallucinated token sequences, and the CLI defaults multiply each one - beam 5, best-of 5, and temperature fallback retrying the whole decode up to 1.0. Same 3.3s room capture:

| Decode configuration | Time | Output |
|---|---:|---|
| CLI defaults (beam 5, best-of 5, fallback) | **44.8 s** | garbage |
| Greedy + full fallback | 24.2 s | garbage |
| Greedy + one fallback | 8.6 s | garbage |
| **Greedy + no fallback** (`-bs 1 -bo 1 -nf`) | **6.8 s** | bounded |
| Greedy + no fallback, clean JFK | **0.6 s** | exact transcript |

- **Fix**: `build_args` pins `-bs 1 -bo 1 -nf` whenever the probed build advertises them. Clean speech is unaffected; the fallback never triggered there. Every multiplier is now a capability probe, not a CLI default.

### 14.3. Live Verification

The daemon-built engine arguments (logged by a wrapper around the real `whisper-cli`):

```
-m .../ggml-small.bin -f .../utterance-*.wav -l auto -np -oj -t 24 -ac 256 -bs 1 -bo 1 -nf
```

Four consecutive live-room sessions (5s capture each) now finish in **6.4–6.8s total**, i.e. **~1.5s of inference** - previously the same class of audio took 6–45s. A clean 11s speech sample through the full daemon pipeline transcribes correctly in **3.3s** end to end.

**Automated verification**: `make test` - Rust 594 passed / 0 failed, all QML suites green. New coverage: `audio_context_for` bounds, bounded-decode flag emission, and session-protocol assertions that the daemon passes the sized `-ac` and the decode limits to the engine.

---

## 15. Why The VAD Asset Was "Unreachable" (It Was Not), And The Fix It Unlocks

### 15.1. The 401 Was A Wrong Path, Not A Credential Problem

**Answer: no Hugging Face credentials are needed.** The 401 was Hugging Face's generic response for a path an anonymous client may not see - it returns **401, not 404**, for non-public/nonexistent repos. Proof: a deliberately made-up repo (`ggml-org/definitely-not-a-real-repo-xyz`) returns the same 401 on both the API and `resolve` endpoints. `ggml-org/whisper.cpp` is simply not a public HF repo, and the old public repo (`ggerganov/whisper.cpp`, which serves all the ASR models) never contained the VAD file (verified against its full file tree).

The asset lives in its own **public, non-gated** repository, and upstream whisper.cpp's own `models/download-vad-model.sh` is the source of truth for where:

```
src="https://huggingface.co/ggml-org/whisper-vad"
→ ggml-silero-v5.1.2.bin   885,098 bytes   HTTP 200, no credentials
```

`ggml-org/silero-v5.1.2` also serves the identical file. **The lesson**: read the project's own download script before concluding an asset is gone.

### 15.2. Provisioning It Fixes The Music-Transcription Problem

The daemon now provisions the asset and passes `--vad --vad-model` only when it is present:

- `voice install-vad` - installs it on its own (staged `.part`, progress JSONL, same store as the ASR models).
- `voice install-model <id>` - also fetches it, best-effort, so new installs get it automatically.
- `voice status` - reports `vad_model_present`.
- A bare `--vad` remains unreachable: whisper-cli fails every transcription without a model.

Measured on the same room captures:

| Audio | Before | After |
|---|---|---|
| Room with loud music (3.4s) | 6–45s, hallucinated text ("Mario", "ვვვ…") | **~0.2s, empty transcript** (VAD found no speech) |
| Clean JFK speech (11s) | 3.3s, exact transcript | 2.9s end to end, exact transcript |

Daemon-built engine arguments, logged live:

```
-m .../ggml-small.bin -f .../utterance-*.wav -l auto -np -oj -t 24
-ac 572 -bs 1 -bo 1 -nf
--vad --vad-model /mnt/data/cache/astral-plasma/models/ggml-silero-v5.1.2.bin
```

Note `-ac 572`: the encoder window is sized to the actual 10.16s utterance (`ceil(ms/20) + 64`), not the 30s default.

**Automated verification**: `make test` - Rust 597 passed / 0 failed, all QML suites green. New coverage: VAD constants pinned to the public repo, `install-vad` + auto-provision-on-model-install against a stub `curl`, `vad_model_present` in `voice status`, and session-protocol assertions that `--vad --vad-model` reach the engine.

---

## 16. "Chinese Becomes Korean, English Becomes Nothing" Was One Input Problem

### 16.1. Diagnosis

- Measured the room through the built-in microphone while the music played: **0.64 RMS full scale** (the music's own monitor measured 0.67–0.80). The engine was being handed the speakers' playback.
- Language detection keyed off that playback - Chinese speech came back as Korean - and once VAD filtered the music, nothing was left, so English speech produced an empty transcript.
- No model, prompt, or threshold change can fix a microphone whose dominant content is the machine's own output.

### 16.2. Fix: PipeWire echo cancellation, on by default

- New setting `voice.echoCancel` (Settings → AI → Voice input → **Echo cancellation**), default on.
- The daemon provisions a source named `astral_echo_cancel` on the first session (`pactl load-module module-echo-cancel aec_method=webrtc source_name=astral_echo_cancel sink_name=astral_echo_cancel_sink`) and captures from it. If PipeWire, `pactl`, or the module is unavailable, it silently falls back to the default source.
- Loading the module leaves the default sink and source unchanged, so playback routing is untouched.
- Measured effect: the same music through the echo-cancelled source is **0.07 RMS** — ~19 dB below the raw microphone.
- `voice status` reports `echo_cancel` (the setting) and `echo_cancel_active` (the source is present); a status probe never loads the module.

### 16.3. Live verification

Capture arguments built by the daemon during a real session:

```
--raw --target astral_echo_cancel --latency 32ms --rate 16000 --channels 1 --format s16 -
```

A music-only session (no speech) finished with an empty transcript in ~0.3 s of inference — the correct outcome, and previously 6–45 s of hallucinated text.

**Automated verification**: `make test` - Rust 605 passed / 0 failed, all QML suites green. New coverage: echo-cancel source detection and load-argument tests, stub-`pactl` provisioning + fallback + status-does-not-load tests, `pw_record_args_for_node`, and the settings/toggle contracts.

### 16.4. What to expect now

Chinese and English speech are captured with the music removed, so language detection sees the voice and the transcript should follow the spoken language. The toggle is in **Settings → AI → Voice input → Echo cancellation**; turning it off reverts to the raw microphone.

---

## 17. "Chinese Becomes Korean / French Becomes Chinese" - The Input Was The Root Cause

### 17.1. Diagnosis With Numbers

- The built-in microphone carried the playing music at **0.58–0.78 RMS** while the music's own monitor measured 0.67–0.80: the engine was being asked to transcribe the speakers.
- Whisper's language detection follows whatever is loudest. Measured detection vs the music-to-voice ratio: 0 to -9 dB → `nn`/`en` garbage; **-12 dB → `fr` + "Tu fais quoi ?"**. The voice must be ~12 dB louder than the music at the microphone.
- **Engine VAD made it worse**: whisper.cpp applies `--vad` before language detection (`whisper_full` swaps in the VAD-filtered samples, then `whisper_full_with_state` detects from them - `src/whisper.cpp`). At -12 dB the unfiltered run detected `fr` with the exact transcript while the VAD run detected `en` and returned "Quoi ?". VAD is removed.
- **The input gain was +60 dB** (`Capture` 63/63 = +30 dB, `Internal Mic Boost` 3/3 = +30 dB) with **5.6–25.4% of samples hard-clipped** (peak exactly 1.000). Lowering the boost to 1 removed all clipping. Clipping distorts the waveform and limits AEC, which needs a linear echo path.
- AEC (previous round) removes ~19 dB of the playback; the webcam microphone hears the music just as loudly, so a device swap is not a fix.

### 17.2. Code Changes

- **Engine VAD removed** (`build_args`): it corrupted detection and clipped speech; the daemon's own `SilenceDetector` gates the no-speech case.
- **The detected language is reported**: `read_transcript` now parses `result.language` from the `-oj` sidecar into `Transcript.language` (it was hardcoded to `und` whenever `language: auto`), so the strip shows `fr`/`ko` instead of "language not determined" - making a wrong detection visible and correctable from the language picker.
- **No-speech gate**: a capture the detector saw no speech in returns an empty transcript without invoking the engine (no music annotations).
- AEC stays on by default (previous round).

### 17.3. Proof

The exact case that previously produced `en`/"Quoi ?", run through the rebuilt daemon with the real engine:

```
fr + music at -12 dB   Final: language='fr'  text='Tu fais quoi ?'
fr clean               Final: language='fr'  text='Tu fais quoi ?'
music only             Final: language='nn'  text=''
```

`make test`: Rust 603 passed / 0 failed, all QML suites green. New coverage: the engine's detected language surfaces in `Final`; a no-speech capture skips the engine; VAD flags are never requested.

### 17.4. What Only You Can Fix

The remaining failures are physical: at your current speaker level the music reaches the microphone louder than your voice. Options, in order of effect:

1. **Headphones** (removes the problem entirely).
2. **Lower the speaker volume**, or move the microphone closer.
3. **Fix the input gain** - `Capture` and `Internal Mic Boost` are both at maximum:
   ```bash
   amixer -c 1 sset 'Internal Mic Boost' 1
   amixer -c 1 sset 'Capture' 60%
   ```
4. If you speak one language for a session, pin it in **Settings → AI → Voice input → Language**; a fixed language skips detection entirely and is ~2x faster.

---

## 18. "Car Engine Revving / Speaking In Foreign Language" - The Sound Wasn't From The PC

### 18.1. The Decisive Measurement

| Signal (`parec`) | RMS |
|---|---|
| Jeecoo sink monitor (PC playback) | **0.0000** (paused) |
| Built-in sink monitor | **0.0000** |
| Built-in microphone | **0.73**, peak 1.000, **18.4% clipped** |
| Echo-cancelled source | 0.16 (AEC + WebRTC noise suppression, ~15 dB) |

Both playback monitors were silent while the microphone was clipping: the loud
sound was **external**. Echo cancellation subtracts the sink signal from the
capture, so it has no reference for sound the machine never played; its noise
suppression still removed ~15 dB, but the remaining 0.08-0.16 RMS floor still
competes with a normal voice. Whisper therefore transcribed the room (engine
/ music) and annotated the buried Chinese speech as "foreign language", with
language detection following the noise (`en`).

Note: `pw-record --target <name>` silently falls back to the default source when
a name does not resolve, which briefly made the microphone look bit-identical to
the sink monitor. `parec --device=<node>` is the reliable way to read a specific
node and is what produced the table above.

### 18.2. No Code Fix Remains For External Noise

The pipeline is already doing what it can: AEC + noise suppression on by
default, engine VAD removed, the detected language reported, and a no-speech
gate that skips the engine entirely. What remains is physical:

1. **A microphone at your mouth** (headset/earbud) - rejects the room, the only
   complete fix.
2. **A quieter place** or lower ambient volume.
3. **Fix the input gain** (still `Capture` 63/63 +30 dB and `Internal Mic Boost`
   3/3 +30 dB, 18% of samples clipped):
   ```bash
   amixer -c 1 sset 'Internal Mic Boost' 1
   amixer -c 1 sset 'Capture' 60%
   ```
4. **Pin the language** - Settings → AI → Voice input → Language. Detection is
   what fails in noise; a pinned language skips it entirely and is ~2x faster.

---

## 19. Voice Input: The Three Silent Failures, Fixed

Three defects made voice input look broken in ways that produced no error at
all. They are documented together because they share a shape: each produced
output that *looked* right and was never questioned.

### 19.1 English Speech Came Back As Japanese

`会議のも学び` from "can you help me". Two independent causes.

**The decision was trusted unconditionally.** whisper auto-detects by taking a
bare `argmax` over 100 language logits
(`whisper_lang_auto_detect_internal` → `return logits_id[0].second`). The
winner is written to `state->lang_id` and the decoder is then *constrained* to
it, so nothing downstream can revisit the choice. The measured run: `p = 0.08`
— not a reading, the shape of a tie between a hundred languages. whisper prints
that probability to **stderr**; the adapter captured stderr and discarded it on
the success path, so the one number that would have exposed the tie was already
in hand and thrown away.

**The display was structurally unreachable.** The strip rendered `"transcribing"`
for the whole finalizing state, the language arrived only with the transcript,
and the transcript's arrival also closed the strip. During recording the label
read "language not determined"; during finalizing it read "transcribing". It
could never render a real value.

The fix: detection is now **its own pass** (`whisper-cli -dl`, probed like every
other flag and verified against the installed `whisper-cli 1.9.4`), so the
language is known *before* the decode and can be gated, shown and corrected. A
reading below `MIN_LANGUAGE_CONFIDENCE` (0.35) is reported but not transcribed
with. **And the default is no longer `auto`** — it is the user's system locale,
read from `LC_ALL` / `LC_MESSAGES` / `LANG`. `auto` remains available in the
picker for people who switch languages while dictating.

A pinned language is never overridden, at any confidence: a bilingual user who
sets Chinese has said what they meant.

| | before | after |
|---|---|---|
| Default language | `auto` (ungated argmax) | system locale |
| Detection | fused into the decode | separate pass, pre-decode |
| Confidence | logged to stderr, discarded | parsed, gated, shown |
| A wrong reading | invisible | `ja (unsure)`, error-tinted, one click to fix |

![Confident reading](docs/voice-proof/language-confident-reading.png)

A confident reading is shown while the decode runs. It replaces the word
"transcribing" — the level meter and clock already say work is happening, and a
status word is worth less than the one thing the user can act on.

![Doubtful reading](docs/voice-proof/language-doubtful-reading.png)

A doubtful one says so. `ja (unsure)`, tinted with the error tone, clickable
straight into the language picker. This is the case that produced the Japanese
transcript, and it is the case a user can now catch in time.

### 19.2 The Microphone Worked And Nothing Was Written

`Final` arrived with an empty `text`. The service assigned
`voiceTranscript = ""` — which it already was — and **QML emits no change
signal when a property is assigned its current value.** So
`onVoiceTranscriptChanged` never ran, and the composer's only dictation path was
never entered. Mic opens, meter moves, strip closes, composer untouched. No
error, no notice, nothing in the logs. The guard written for exactly this case
lived inside a function that never ran.

Fixed by handling the empty case in the producer, on its own channel
(`voiceEmptyNotice`), and holding the strip open for it. `Transcript` also
grew `speech_detected`, because "the microphone heard nothing" and "the engine
heard something and had no words for it" send the user to different places.

![No speech reported](docs/voice-proof/no-speech-reported.png)

Note what is *not* there: a Settings chip. A session that heard nothing is a
fact about one recording, and a settings page cannot explain it. Offering the
link anyway would send the user somewhere that cannot help.

### 19.3 The Detector Latched Off Mid-Sentence

The floor was estimated by **averaging** every frame below a hard ceiling. Normal
dictation sits just under that ceiling, so speech was averaged in. The floor
climbed to the speech level, `level > floor * 3` became unsatisfiable, and the
detector stopped responding — while the user kept talking.

| scenario (20 ms frames) | before | after |
|---|---|---|
| 1.3 s @ 0.05 RMS, quiet room | tracked **260 ms** | tracked **1300 ms** |
| continuous speech 10 s | — | no premature finalize |
| 0.06 speech over 0.03 room noise | `has_speech = false` | `has_speech = true` |
| speech starting at mic-open | discarded | classified |
| quiet room / fan / busy room, nothing said | — | `has_speech = false` |

Three fixes: the floor is a **low quantile** of the frames that were not
themselves speech (a quantile is robust to a minority of loud frames, and still
rises in a quiet room where every frame is background); a **decaying peak** is
followed alongside it; and `has_speech` is now a **cumulative** verdict over 120
ms at a deliberately loose 1.5× ratio, because gating the engine on a
single-frame precision test discarded whole utterances.

The constant the old code used (0.05) was *right* — it is the dividing line
between "a constant signal is the room" and "a constant signal is an event", and
no energy-based detector can place it elsewhere without a trained VAD. The mean
was the defect, not the constant.

### 19.4 Why The Test Suite Missed All Three

Every speech test used **0.35 RMS**, seven times above the admission ceiling, so
speech never entered the floor window and the estimator was never exercised. The
"loud room" test used 0.09 — *above* the ceiling, i.e. the branch that does not
populate the window. The suite passed, in the regime where the code worked.

One test asserted `floor() < 0.06` — a number from the estimator itself, which
pins a test to one implementation and to no user-visible property. The fix was
to assert observable classifications ("background reads as silence", "the whole
utterance is tracked") at levels a real microphone produces.

The same blindness appeared in QML: `tst_voice_input.qml` asserted that
`voiceLanguageOverride` was *declared*, and it passed for the whole of v1 on a
property with no reader and no writer. It now asserts the `--lang` argument is
built.

### 19.5 One More Dead Readout, Found In The Render

Rendering the states caught a fourth: the level meter stayed up through
`finalizing`, when the microphone has already been released. Any level on screen
there is a frozen reading of audio that has stopped — the "dead microphone"
misread pointed the other way. The meter is now gated on `isRecording`; the
clock and the language reading stay up through the decode, because those are not
live capture readings.

![All states](docs/voice-proof/language-and-empty-outcome-states.png)

Seven states, all reachable: idle, recording (honestly "language not
determined" — detection has not happened yet), finalizing, a confident reading,
a doubtful reading, an empty outcome, and a setup gap.

---

## 20. The Downloads Surface: Tab-Switch Freeze, Design Round, And Keyboard Paste

Three reported defects, all root-caused, plus the design revision they surfaced.

### 20.1 "When I switch tab, it stays in the dashboard tab"

**Root cause.** The Downloads-tab commit deleted two lines from `shell/CentralDropdown.qml`'s
`tabSlider`:

```qml
height: parent.height
x: -tabContentContainer.activeTabIndex * tabContentContainer.width
```

Without the `x` binding the six-pane content strip never moved, so every tab showed
pane 0 (Dashboard) while the header indicator and `Config.activeDashboardTab`
happily changed. The same commit also unwired the standalone
`dashboard/CentralDashboard.qml` TabBar from `Config`.

**Fix.** Restored the binding and the height, re-bound the standalone TabBar
(`activeTab: Config.activeDashboardTab` + `onTabSelected`), and added
`tests/tst_dropdown_tab_switching.qml`: it clicks the real header MouseArea of
every tab, waits for the spatial slide to settle, and asserts the strip position,
pane visibility, pane layout, indicator index, and Config persistence. The suite
was written first and failed on the deleted lines before the fix.


### 20.2 The "totally broken and ugly" Downloads design

**What was wrong.**
1. The tab was a fixed 320px void: a title row, then ~200px of empty glass.
2. The Active/Queued/Finished control sat on its own line, wasting vertical space.
3. Two buttons ("Add" and "Add download") did exactly the same thing.
4. `MaterialIcon` had no `download`, `cloud_download`, `link` or `task_alt`
   mappings, so the header badge, the empty-state icon and the dropdown tab-bar
   icon rendered as blank glyphs (the map/heuristics now carry them, pinned by
   `tst_material_icon.qml` and the tab-icon resolution loop in
   `tst_dropdown_tab_switching.qml`).

**What it is now.**
- One header line: badge + title/subtitle | Active/Queued/Finished | single Add
  action. The segmented control is a single glass track with a sliding selection
  pill (Theme spatial tokens).
- A composed empty state per segment (icon, headline, hint) instead of a void.
- A content-driven, bounded task list (4 rows max, then it scrolls) with per-row
  status badge, name, `done / total · speed · ETA`, percent, actions and a
  progress track.
- The add sheet replaces the list while open: URL field with a Paste button,
  a 1..16 connections stepper, the destination, and Cancel/Download.


### 20.3 "I can't paste with Ctrl+V — it pastes into another app"

**Root cause.** `UnifiedShell` is a full-screen layer surface that deliberately
runs with `WlrKeyboardFocus.None` (pointer-only drawers, see the focus-policy
comment in that file). The add sheet's `TextEdit` therefore never received
keyboard events: Ctrl+V went to whichever window the compositor still had
focused — the user's editor.

**Fix.**
- `DownloadsTab.wantsKeyboard` → `CentralDropdown.textInputActive` →
  `UnifiedShell` requests `WlrKeyboardFocus.Exclusive` while the sheet is open
  (the same mode the Command Launcher and Overview already use), and returns to
  `None` when it closes.
- The URL field takes focus when the sheet opens; Escape closes the sheet
  (a second Escape closes the drawer).
- Hover auto-close is suppressed while a text sheet is open, and closing the
  dashboard releases the capture.
- Added a Paste button and a right-click context menu (Paste / Select all /
  Clear) backed by `TextEdit.paste()`, so pasting does not depend on input
  method quirks.

**Verified live** (introspection IPC, removed afterwards): with the sheet open the
field reported `inputFocus: true`, and a real `wl-copy` URL pasted through
`TextEdit.paste()` landed in the field byte-for-byte.


### 20.4 Live end-to-end proof (real aria2, throttled local source)

A 300 MiB file served from a throttled local HTTP server, added with
`--split 4`, then a second 3 MiB file to trigger the completion edge:

- aggregate header (`58% · 1.6 MiB/s · ETA 1m`), segment counts, per-row
  progress and actions all tracked live events;
- the top-right border HUD filled with aggregate progress (idle vs active,
  pixel-verified);
- the completion notification fired exactly once.


`make test` is green: full Rust suite + all QML suites, including the new
`tst_dropdown_tab_switching.qml` and the extended Downloads/material-icon
contracts. Proof artifacts (aria2 tasks, server, temp files) were removed
afterwards; `~/Downloads` was never touched.

**Integration note.** The top-right HUD and the dropdown header share the screen
band occupied by the KDE Plasma panel on this machine (`plasma status` reports
no panels disabled even though `disablePanels` is `"all"`), so the panel is
visible through the glass and partially covers the HUD. That is a
session-provisioning question (Plasma panel hand-over), not a Downloads-tab
defect; it is recorded here because it is visible in the screenshots.

---

## 21. "The GPU Is Always At 100%": Decorative Motion Was On The Display Clock

### 21.1 The report

> *"there is critical performance issue of the theme, the GPU is always around
> 100% usage. do a general performance audit of the whole theme app"*
> *"I can feel the extrem lag when I started the theme, sometimes my whole
> system is stuck"*

This machine drives a 3440×1440@165 Hz ultrawide and a 2560×1600@240 Hz panel.
At what should be idle (no drawer open, no media playing) the shell was burning
about **1.2 CPU cores** and the Intel iGPU was pinned:

- `quickshell`: `QSGRenderThread` ≈ 49%, main thread ≈ 41% of a core;
- iGPU `rc6_residency` grew only ~130 ms per 5 s (it almost never idled), actual
  frequency held at/near max;
- KWin was pushed to ~25% of a core compositing the result.

### 21.2 The decisive experiment

Instead of reading code first, the suspect was switched off and the machine
re-measured. The only thing that ever runs continuously on this desktop is the
**AI agent activity border** (`components/MatrixBorderEffect.qml`) — it is active
whenever any AI agent is running (live proof: the daemon reported a DeepSeek
agent with token events seconds old). Patching its `active` binding to `false`
(one temporary edit, automatically hot-reloaded by Quickshell) changed:

| | shell CPU | iGPU |
| :--- | ---: | :--- |
| AI border active | **~47%** of a core | busy/never idling |
| AI border inactive | **0.3%** | idle |

The "performance problem of the whole theme" was one decorative effect.

### 21.3 The general audit

Every infinite animation in the repository was inventoried with its `running:`
gate. The dangerous class is not "is it infinite" but **"does it stay visible
for hours"**:

| Component | Gate | Persistence |
| :--- | :--- | :--- |
| `MatrixBorderEffect` (AI border) | any AI agent active | hours |
| `DownloadBorderEffect` | any active download | hours |
| `DockStatusIcons` AI quota pulse | quota critical | hours |
| `VinylPlayer`, `RadialCoverVisualiser`, `RadialCoverRing`, `HeatmapCoverRing`, `HeatmapSpeakerPlayer`, `DashboardTab` cover | media playing + visible | hours |
| launch/refresh spinners (`UnifiedDock`, `AiTokensSection`, `AiPage`) | user-initiated loading | seconds |

Only the last row is allowed to keep a vsync-rate animation; everything else
must run on a **decorative frame budget**.

### 21.4 The mechanism (and three traps)

Qt Quick repaints the **entire window** on every property change, and a QML
animation advances at **display refresh rate**. A full-screen decorative
animation therefore forces *refresh-rate* full-window renders for as long as the
feature is on — 165–240 per second per screen on this desk. Three traps showed up
while fixing it, each caught by counting actual swapped frames in a controlled
compositor (`kwin_wayland --virtual`, 2560×1600@60 Hz, `Window.onFrameSwapped`):

1. **N timers = N frames.** Two independent 30 Hz pacers interleave, so the
   "30 fps" effect measured **60 fps**. All decorative updates must land on the
   *same* tick.
2. **Gradient churn costs an extra frame.** A `Qt5Compat.GraphicalEffects`
   `RadialGradient` regenerates its offscreen source on every gradient-stop
   change — each pulse tick produced two frames (60 fps for a 30 Hz pulse).
3. **Periodic content is a frame source too.** The matrix glyph rain had its own
   10 Hz timer, adding 10 frames/s on top of the motion.

### 21.5 The fix

A single shared clock for all decoration, in a new proper QML module
`components/motion/`:

- **`Theme.decorativeMaxFps: 30`** — the budget. Interactive/spatial transitions
  are never throttled (see `DESIGN.md` §2.4).
- **`MotionClock`** — one reference-counted ticker for the whole shell; it stops
  when the last consumer releases it, so an idle shell does zero decorative work.
- **`MotionPacer`** — derives `phase`/`breath` from `MotionClock.elapsedMs` with
  wall-clock math (a late tick samples the phase; it never slows the cycle). It
  owns no timer and no animation.

Applied to every persistent decorative host: AI and download border effects, the
dock quota pulse, all six media visualizers/rotations. The AI border's ambient
glow now breathes via **node opacity** (static gradient), and the digital rain
samples `MotionClock.elapsedMs` instead of running a private timer.

### 21.6 Benchmark proof

Nested KWin virtual output, 2560×1600@60 Hz, full-screen AI border, 12 s windows:

| Variant | Rendered frames/s | Client CPU per 12 s |
| :--- | ---: | ---: |
| Effect inactive (idle) | 0 | 0.00 s |
| Original animation | 60 (= refresh) | 1.40 s |
| `MotionClock` @ 30 fps | 30 | 0.85 s |

On this 60 Hz output the fix halves both frames and client CPU; on a 240 Hz panel
the uncapped row scales to 240 fps while the capped row **stays at 30** — the
decoration is no longer a function of the panel at all. Pixel comparison of the
client-rendered frames confirms the effect is unchanged: capped frames differ
from the uncapped baseline by mean 0.067/255 (0.12 % of pixels, animation phase
only), while consecutive capped frames differ by 0.18 % of pixels — i.e. it still
animates.


### 21.7 Regression guards

- `tests/tst_motion_pacer.qml` — idle rest state, wall-clock accuracy, “two
  consumers never exceed the budget”, refcount balance, envelope math,
  degenerate periods.
- `tests/tst_decorative_animation_budget.qml` — repo-wide source contract: no
  `loops: Animation.Infinite` in any decorative host, every host drives motion
  through `MotionPacer`, the clock is reference-counted and token-driven, and
  neither primitive owns a vsync animation.
- `make test` is green (full Rust suite + all QML suites).

**Measurement note.** The machine's displays powered off mid-audit (DPMS), so the
live numbers above were taken while they were on; the frame counts and CPU
comparison come from the controlled nested compositor so they remain
reproducible. The high-refresh claim is a direct consequence of the mechanism
(uncapped decoration follows the output refresh rate) and is pinned by the
contract tests rather than by a single breadcrumb.

---

## 22. "The Game Is Closed But The GPU Is Still Pegged" -> Two Invisible-App Bugs

While chasing the iGPU load after Firefox was stopped, the user's report was:
*"I already closed that game - it means there is a system tray not rendered on the
theme task bar, we should fix it."* The instinct was right, and there were two
independent failures behind it.

### What the instrument said first

Per-process engine counters (`/proc/*/fdinfo`, Intel `drm-pdev: 0000:00:02.0`,
5 s windows) showed the load was not the theme:

| Consumer | Render-engine share |
| :--- | ---: |
| Xwayland | 239-296 % |
| `CrGpuMain` (Edge) | 154-183 % |
| ghostty | 74-88 % |
| msedge | 33-43 % |
| quickshell (dashboard open) | 17-33 % |
| quickshell (dashboard closed) | 3-5 % |

Xwayland that high means X11 clients rendering through it. `xprop -root
_NET_CLIENT_LIST` named them: `0x3600008 pid=21677 "steam_app_default"` - the
Neverness-to-Everness launcher, **still alive 51 minutes with an iconified
window** (`_NET_WM_STATE_HIDDEN`, 110 % CPU). "Closed" was true of the window and
false of the process.

### Bug 1 - the app was in the taskbar, drawn as an anonymous box

The dock's taskbar *did* list the window (the daemon's KWin script enumerates
`normalWindow && caption`, and it had both). It was drawn with the generic
material `window` glyph, because the daemon never extracted the app's own icon:

```rust
let is_wine = class.trim().to_lowercase().ends_with(".exe");   // `steam_app_default` is not
if !is_wine { return false; }
```

The window publishes a real 32x32 `_NET_WM_ICON`; the gate keyed off the shape of
the class name instead. See [LESSONS §28](docs/LESSONS.md) for the full
inversion (`theme_icon_exists` + a memoized icon index).

Result: `steam_app_default` now resolves to
`~/.cache/astral-plasma/window-icons/steam_app_default.png`, and the taskbar shows
the game's own icon, before and after.

### Bug 2 - the tray was a snapshot, so late icons never rendered

The dock's tray is fed by the daemon's pushed list, and that list was only built
at daemon start and on the shell's `RefreshTray` call (which only a tray *click*
triggered). An application registering its icon later was invisible in the dock
indefinitely. Fixed with a cheap registration poll (3 s) that re-queries and
pushes only when the registration *set* actually changed
([LESSONS §29](docs/LESSONS.md)).

### The fix was two-sided: the initial query resolved identity differently

The window-icon gate above lives in the *pushed* window list. The compositor's
initial query resolved identity on its own and never attached the app's own icon,
so right after a shell/daemon restart the game fell back to the generic glyph
until some window event arrived - half a fix.

All four window sources (initial KWin query, pushed KWin list, focus change,
Hyprland query) now call one composition point,
`application::window_identity::resolve_window_identity`, verified live by running
the port in a fresh process:

```
PROBE com.mitchellh.ghostty | icon=com.mitchellh.ghostty | mat=terminal
PROBE microsoft-edge        | icon=microsoft-edge        | mat=language
PROBE steam_app_default     | icon=/mnt/data/cache/astral-plasma/window-icons/steam_app_default.png | mat=window
PROBE cloudmusic            | icon=/mnt/data/cache/astral-plasma/window-icons/cloudmusic.exe.png       | mat=window
```

Contracts keep the sources from drifting again: a Rust test fails if any of them
resolves identity directly or attaches icons on its own, and the dock suite pins
the same rule for the QML side.

### Live proof

`diag`-dumped dock state (shell IPC) while a probe SNI was registered and killed:

```
probe up,   t+1.4s: 6 items -> [Fcitx, Cachy-Update, dropbox-client-5113, Sunshine, cloudmusic, tray-probe]
probe down, t+1.4s: 5 items -> [Fcitx, Cachy-Update, dropbox-client-5113, Sunshine, cloudmusic]
```

No clicks, no reload. The probe glyph appeared at the bottom of the tray column
(Firefox glyph; the game's own icon one capsule above).

### Tests

- `daemon/tests/test_window_icons.rs` — the gate: `steam_app_default` with a
  non-drawable "icon" name must extract; a real icon file must not; the
  icon-theme lookup is testable against explicit roots (tmpdir fixture) and
  ignores non-image files and traversal.
- `daemon/tests/test_tray_registrations.rs` — registration identity is a set
  (order/duplicates/padding), an icon appearing or leaving is a change, and the
  pushed items are the baseline the live list is compared against.
- `daemon/src/domain/ports.rs` — `TrayPort::registered_item_keys`, the cheap read
  that makes the poll affordable.
- `tests/tst_dock_tray_liveness.qml` — repo-wide source contract: the `.exe`
  class gate is gone, the icon-theme index is the gate, the poll + baseline exist
  in the watcher, and the dock renders every pushed tray item with the
  raw-icon -> URL -> material-glyph chain.
- `make test` is green (714 Rust tests + all QML suites).

### Note on the numbers

The GPU figures above were measured with the displays on; the panel is
2560x1600@240 Hz, so every compositing client scales with that refresh rate. The
two fixes remove *hidden* apps from the picture (a wrong glyph and a frozen tray
list), they do not make X11 clients cheap: Xwayland remains the largest single
iGPU consumer whenever a Wine/Proton app is alive.

---

## 23. "The GPU Jumps To 38 % And Stays There While The Performance Tab Is Open"

Reported right after the taskbar/tray work: with the Performance tab left open, the
iGPU settled at ~38 % and stayed; closed, it was ~8 %.

### Reproduction

`scripts/measure_render.py` (written for this audit) reports per-process GPU time
from the i915 DRM engine counters, CPU time, and the RC6 busy share:

| State | quickshell iGPU | quickshell CPU |
| :--- | ---: | ---: |
| Dashboard closed | 0.3 % | 1.9 % |
| Performance tab open | **43.8 %** | **45.1 %** |

Steady state, not a transient: measured after the tab had been open for seconds and
maintained over an 8 s window.

### Root cause

Six `NumberAnimation`/`Behavior` tweens of **450 ms** in
`dashboard/tabs/PerformanceTab.qml`, three of which are driven by metrics that
arrive every **400 ms** (CPU 400 ms, RAM/GPU 1000 ms). Each sample called
`slideAnim.stop(); slideProgress = 0; slideAnim.restart()`, so the animation was
restarted before it ever finished: the tab animated 100 % of the time at *display
refresh* (240 Hz here). Every one of those frames repainted a Canvas that draws a
full grid, axis labels and a 61-point area path, and re-rendered the whole tab.

### Fix

Two new motion primitives, both on the shared `MotionClock`
(`components/motion/`), so data-driven decoration obeys the same frame budget as
every other decorative effect (`Theme.decorativeMaxFps = 30`):

- **`MotionTween`** - one-shot transition: `from` → `to` over `duration`, advanced
  on clock ticks, wall-clock accurate (a coalesced tick never slows it), lands
  exactly on `to`, emits `advanced()` for Canvas hosts, and releases the clock when
  it finishes. `restart()` while running never takes a second clock reference.
- **`MotionValue`** - the companion for meters: eases towards `target`, takes over
  from wherever it is when the target moves mid-flight, and tracks the target
  exactly (holding no clock reference at all) while `animated` is false - which is
  what a hidden surface wants.

The tab now uses `slideTween` for the telemetry slide, one `MotionValue` per usage
meter (CPU/RAM/GPU/battery + the big device readout), with durations and bezier
curves from the design tokens (`animExpressiveFastEffects`, `animExpressiveFastSpatial`).

| Performance tab | quickshell iGPU | quickshell CPU |
| :--- | ---: | ---: |
| Before, open | 43.8 % | 45.1 % |
| After, open | **3.6-7.8 %** (settled runs: 1.6-17 % ambient noise) | **19-28 %** |
| After, closed | 0.3-1.1 % | 1.9 % |

Visual check: the tab still draws its trace, grid, labels, per-card meters and
metric values correctly.

### Why the reading can still look high

For Intel, the shell's GPU percentage is a **frequency proxy**: the daemon derives
it from `gt_act_freq_mhz` between `gt_min_freq_mhz` and `gt_max_freq_mhz`
(`proc_metrics.rs`, `parse_intel_gpu_freq`). Anything that wakes the GPU - other
applications, the compositor re-blending and blurring two high-refresh outputs -
keeps that frequency ramped, and the governor decays slowly, so the number jumps
back up as soon as any load returns.

Measured here over 8 s windows with the dashboard **closed**:

| | GT frequency |
| :--- | ---: |
| Dashboard closed (settled) | mean 1248-1350 MHz of 300-1550 (78-84 %) |
| Performance tab open (settled) | mean 1209-1399 MHz |

So the frequency proxy is dominated by ambient GPU activity, not by this tab:
the tab's own share is the 43.8 % -> ~5 % column above. To read the tab's real
cost, compare it while nothing else is running (this session had Edge, Xwayland
with Wine apps, a system monitor and a terminal continuously rendering).

### Measurement honesty

Per-process A/B comparisons in this session were also noisy (the same
configuration measured 5.5 % and 17.1 % in consecutive runs): writing measurement
output to the terminal makes the terminal re-render, which is itself GPU work.
Runs that differ by less than a factor of two here are not evidence.

The first version of the measuring script summed fdinfo rows without collapsing
duplicated fds (quickshell holds four fds for one DRM file) and without pairing
samples (fds for render targets come and go, which produced a `-4703 %` reading
during bisection). Both are fixed in `scripts/measure_render.py`, and the earlier
inflated numbers in this document were re-measured where it mattered. See
[LESSONS §31](docs/LESSONS.md).

### Follow-up found by the same sweep

Sweeping every dashboard tab with the fixed instrument shows the *other* tabs have
their own cost, unrelated to this fix:

| Tab | quickshell iGPU | quickshell CPU |
| :--- | ---: | ---: |
| Dashboard (default) | 16.6 % | ~85 % |
| Media | 14.1 % | ~81 % |
| Performance (fixed) | 5.4-7.8 % | 20-28 % |
| Workspaces / Downloads | ~1 % | ~2.2 % |

The follow-up turned out to be the audio visualiser, and it is now fixed:

- **Disabling the visualiser path entirely** (`isEffectVisible = false`) drops the
  dashboard tab from 96.5 % to **13 %** CPU, with the tab's own content unchanged.
- **Suppressing the stream's property writes** (parsing kept) drops it to
  **11.5 %** - so the cost is the reactive dependents of those writes, not the
  stream's plumbing (the daemon sends only ~4.5 KB/s at ~31 fps).

What was reacting:

1. `MprisMedia.isPlayerPlaying()` read `AudioVisualizer.energy`/`beat` directly in
   its Wine-player branch. It is called from bindings, so every binding that
   reached it registered a dependency on values that change with every stream
   frame. The predicate is identical to `AudioVisualizer.active`, which flips only
   when sound starts or stops.
2. The stream frame counter (`frameCount`, ~90 changes/s) was used as a
   re-evaluation *tick* in two MprisMedia bindings. The audio-arbitration re-check
   now runs on a deliberate 4 Hz `arbitrationTick` in the audio service.
3. The visualisers bound to the raw `bands`/`energy`/`beat`, so 40+ bars
   re-evaluated per stream frame. They now read clock-paced mirrors
   (`displayBands`/`displayEnergy`/`displayBass`/`displayTreble`/`displayBeat`)
   produced by a `MotionTick` on the shared clock - real samples of the real
   stream, at `Theme.decorativeMaxFps`, and a silent stream settles once and then
   holds no clock at all.

Residual after the mirrors: the dashboard tab still cost ~25 % CPU with audio
playing. The audit (LESSONS §34) found why - every spectrum bar was its own `Item`
with a 75 ms `Behavior on height` and a 200 ms `Behavior on opacity` that the 33 ms
data stream re-triggered before they could finish. 40 bars × 2 permanent animations
is 80 animations running at display refresh to draw forty 2.5×13 px bars, forever.

Fixed across every visualiser:

- `RadialCoverRing` and `RadialCoverVisualiser` now draw their spectrum in **one
  Canvas** repainted on the shared clock. Measured: the ring's repaints cost ~2 %
  CPU (A/B with the repaint stopped), where the animation churn they replaced
  dominated the tab.
- The data-driven `Behavior`s in `HeatmapCoverRing`/`HeatmapSpeakerPlayer` were
  deleted (the mirror already delivers 30 fps updates). `VinylPlayer`'s two
  remaining animations are user-driven (tonearm, surface visibility) and keep their
  M3 transitions.

Per-tab shell cost with music playing, after all of the above (60 Hz panel):

| Tab | iGPU | CPU |
| :--- | ---: | ---: |
| Performance (the reported one) | 4.9 % | 7.2 % |
| Dashboard | 9.1 % | 22.8 % |
| Media | 8.0 % | 26.7 % |
| Workspaces / Downloads | ~1.6 % | ~2.1 % |

The remaining 20-26 % on the two audio tabs is the live visualiser's honest work -
a 48-bar spectrum plus 40 live bindings redrawn 30 times a second, with the stream
itself costing ~11.5 % before anything is drawn. The tabs that show no spectrum sit
at ~2 %, i.e. the surfaces people are not looking at cost nothing.

### The display refresh was the other half

The panel ran at 240 Hz. Every client's per-frame work scales with it, so capping
it (there is no 120 Hz mode at 2560x1600 on this panel - the choices are 240 and
60) changed the numbers more than any code change in this document:

| | 240 Hz | 60 Hz |
| :--- | ---: | ---: |
| Performance tab, shell CPU | 23 % | **7.3 %** |
| Performance tab, shell iGPU | 8.9 % | **5.4 %** |
| Dashboard tab, shell CPU | 96.5 % | **25 %** |
| GT frequency mean (the user-facing number) | 1100-1400 MHz (78-100 %) | **565 MHz (21 %)** |

Applied with `kscreen-doctor output.eDP-1.mode.38`; reverting is
`kscreen-doctor output.eDP-1.mode.37`. The DP-3 output (currently disabled) does
have a 120 Hz mode if it is ever re-enabled.

**Caveat on the 60 Hz columns.** Changing an output mode locks the session, and
these runs happened with the lock screen up, so the shell's windows were not being
composited - the *CPU* columns are unaffected by that (bindings, timers and timer
driven work keep running) and carry the proof, while the GPU column at 60 Hz
understates what an unlocked session will show. The structural claim is unaffected:
every client's per-frame work scales with the refresh rate, and the shell's own
motion budget is 30 fps, so 240 Hz scanout bought it nothing.

### Tests

- `tests/tst_performance_tab_motion.qml` - behavioural: a tween advances only on
  clock ticks (never more often than the clock), stays inside the frame budget for
  its duration, lands exactly on `to`, releases the clock, and restarts cleanly
  with new endpoints; source contracts: no free-running `NumberAnimation` for the
  slide, no `Behavior on width` meters, every metric-driven duration from `Theme`,
  visibility gating intact.
- `make test` is green (717 Rust tests + every QML suite, now 99).

---

## 24. Making The Refresh Cap A Setting (Default 60 Hz) — Superseded

> **Superseded.** The automatic apply described below was removed after a user
> reported that starting Astral knocked a 240 Hz session down to 60 Hz. The shell
> must never modify the refresh rate; see `docs/LESSONS.md` §35 and
> `tests/tst_display_refresh_never_modified.qml`. The rest of this section records
> the original implementation.

The 60 Hz cap from §23 was the biggest single win of the audit and the only change
a user *feels* - it slows the cursor, scrolling and games, not the shell, whose
motion budget is 30 fps. So it became a preference:

- **Setting**: `display.refreshRate` in `settings.json`, shipped default `"60"`,
  with any target rate or `"max"` available; `SystemPage` renders the picker
  ("60 / 120 / 144 / 165 / Max") and shows what was actually applied.
- **Daemon owns the switch**: `astral-plasma display apply [rate|auto|max]`,
  `display restore`, `display get`. The pure choice logic
  (`domain/display_modes.rs`) picks, per enabled output, the highest refresh **at
  the current resolution** that does not exceed the target - never a smaller mode
  to reach a rate, never a no-op re-switch that would blank the screen.
- **Reversible by construction**: the first switch journals the modes the session
  was running (`display_backup.json`, next to the blur backup) and `run.sh` puts
  them back on exit. `run.sh` also applies the preference before the shell starts,
  so a session never renders a frame at a rate the user asked not to pay for.

Verified live on this machine (240 Hz panel, preference 60):

```
$ astral-plasma display get          -> eDP-1 2560x1600@60
$ astral-plasma display apply max    -> {"applied":[{"output":"eDP-1","mode":"37"}]}
$ astral-plasma display get          -> eDP-1 2560x1600@240
$ astral-plasma display restore      -> {"restored":true}
$ astral-plasma display get          -> eDP-1 2560x1600@60
```

Historical tests: `daemon/tests/test_display_modes.rs` (parsing, the ≤-target
choice, the resolution invariant, no-op suppression, snapshot resolution
preferring mode names over ids) and `tests/tst_display_refresh_setting.qml`
(setting default, service apply-on-start/on-change, settings UI wiring, run.sh
apply-then-restore ordering). Both were removed with the feature; the gate that
replaced them is `tests/tst_display_refresh_never_modified.qml`.

---

## 25. Settings Pages: A Pinned Identity, A Zone Rail, And A Jump That Actually Moves

Reported: *"on section headers clicking a section does not smooth-scroll; improve
the design, then apply it to all relevant settings pages."*

All three were real, and the middle one hid the worst bug of the round.

**Where the pages were.** Every page drew its own header inside its own scrolling
column, so the moment you scrolled, the page no longer told you what you were
looking at. Only the AI page had a section rail, hand-written; the other ten
pages had sections that were private (no rail, no deep link target). Clicking a
rail pill assigned `contentY` directly - a teleport.

**What changed.**

- **One page contract.** Every page now roots in
  [`settings_gui/pages/SettingsPage.qml`](settings_gui/pages/SettingsPage.qml)
  and declares its identity and its zones:
  `title`, `subtitle`, and `zones: [{ id, label, anchor }]`. The hub renders that
  declaration's `stickyHeader` above the scroll area, so the title, its one-line
  purpose and the rail stay pinned while the content moves. Pages no longer repeat
  their title in the body (a test asserts it).
- **A rail where there is navigation.** Two or more zones render as pills in the
  pinned header, with the zone the reader is in highlighted. One zone renders no
  rail - a single pill is decoration. `zones` may be computed, so a hidden section
  (Wi-Fi off, no app streams, adapter off) leaves the rail with it.
- **Section headers carry state.** `components/SectionHeader.qml` now marks every
  zone: eyebrow = live telemetry ("13 networks in range", "6 of 6 shown",
  "service · not installed"), title = the section's name. The
  eyebrow is never a decorative index.
- **The jump is a spatial transition.** `settings_gui/ScrollMotion.js`: the
  `animExpressive*Spatial` tokens, the fast/default rung picked by distance, and
  the spring overshoot damped by distance (a 1000 px jump on the raw curve would
  fling ~200 px past the section). It yields to the reader the instant they wheel
  or drag.
- **The scroll spy's input was stale - the actual bug.** The hub computed each
  zone's offset once, before the page was laid out; a pre-layout page reports
  every anchor at `y = 0`, so the spy (whose own tests were green) reported the
  *last* zone as current, and every jump target was `0`. The offsets are now
  recomputed after every event that can move an anchor, deferred a turn past the
  layout pass. See `docs/LESSONS.md` §36.
- **A trailing section now lights up.** A section shorter than the viewport can
  never reach the top of the screen; the spy now treats the end of a scrollable
  page as its last zone - while a page that fits entirely stays on its first
  (that is the same rule that used to lie on the short pages).

### Visual proof

The pinned header and the zone rail, live, were checked on the System page (six
zones, state eyebrows) and the Dock page (three sections, hatched from a flat list
of switches).


The scroll spy's input is live per page: the audio page (short, fits the window)
sits on "Output" instead of lighting the last pill, and the trailing-zone rule
lands "Display" after a deep link to the end of the System page.


The same contract holds on the other surfaces - section headers with live state,
the rail on pages with more than one zone, no rail where there is nothing to
navigate.


### Tests

- `tests/tst_settings_pages_contract.qml` (new) - every page roots in
  `SettingsPage`, names itself, declares zones whose anchors resolve in document
  order, answers the hub's four members, and drops a zone when its section is
  hidden. The harness-instantiability rule (no direct `Quickshell` import in a
  page) is enforced by the fact that it instantiates all of them.
- `tests/tst_settings_hub_rail.qml` (new) - the live hub: a short page stays on
  its first zone (the regression), a long page's zones ascend, a token-less jump
  lands on the target and lights the trailing zone, and with tokens the jump is a
  tween that starts, is mid-flight one tick in, arrives at the clamped target and
  uses the default spatial rung.
- `tests/tst_settings_sticky_header.qml` (extended) - the trailing-zone rule and
  `motionFor` (ladder, damping, no tokens ⇒ no invented motion), plus the hub's
  source contracts.
- `tests/tst_settings_page_scaffold.qml` (path update) - the scaffold's own
  contract.
- `tests/tst_settings_hub_rail.qml` caught the bug the unit tests could not:
  the spy was pure and correct, its *input* was a photograph.
- `make test` green: 796 Rust tests + 116 QML suites (including the four
  settings suites above).

### Follow-up: the rail was there and dead

The first live check of this round found pills that hovered, highlighted, and did
nothing when pressed. Root cause, proven with a two-file probe: `jumpToZone()`
wrote `Config.settingsSection` behind a `typeof Config !== "undefined"` guard, and
`SettingsPage.qml` never imported `config/` - an unimported singleton is not in a
component's scope, so the guard was permanently false and **every press was a
silent no-op** (the guard existed precisely to avoid the error that would have
revealed it). This is the failure mode of a control talking to a global instead of
an interface.

The rail now asks its host: the page emits `zoneRequested(zoneId)` and the hub -
which owns the scroll area - answers through the same `scrollToSection` it uses
for external deep links. A request that arrives before the page is loaded or laid
out is parked and retried from the recalculated offsets, and a request for a zone
the page does not declare is dropped rather than kept alive.

Verification: `tests/tst_settings_hub_rail.qml` walks the instantiated sticky
header, presses the **rendered** "Display" and "Desktop" pills, and asserts the
view moves, arrives on the anchor, uses the token rung the distance earns, and
that the spy follows. `tst_settings_pages_contract.qml` asserts every page emits
the request; `tst_settings_page_scaffold.qml` asserts the scaffold carries no
`Config` write. Live, the parked path was exercised end-to-end from the AI page:
`settings openSection system display` switches page and lands at the trailing zone
with its pill lit.
`make test` green: 796 Rust tests + 116 QML suites.

---

## 26. The Harness Was Passing Suites That Failed

While verifying the rail fix I ran the suites' raw output instead of trusting the
summary line, and `make test` - which had been reporting *"ALL QML TESTS PASSED!
No regressions detected."* - was hiding ten failing suites. They all fail
identically in a clean worktree at `HEAD`, so this had been true for real work,
not just for this round.

The mechanism: the runner accepted a suite that **exited 0 and printed `PASS:`**,
and these suites' `assert()` did

```qml
    if (!cond) { console.error("FAIL: " + msg); Qt.exit(1); }   // does not stop JS
```

`Qt.exit(1)` schedules an exit; JavaScript keeps running, the suite reaches its
final `PASS:` line and `Qt.exit(0)`, and the exit code is overwritten. A failing
suite reported green - the worst possible test bug, because it converts "we
broke something" into silence.

**The fix, in three parts.**

- `tests/run_qml_tests.sh` now requires exit 0 **and** `PASS:` **and** the absence
  of any failure marker (`FAIL:`, `✗`), prints the raw output of a failed suite,
  and a probe suite that prints `FAIL:` then `PASS:` and exits 0 is now reported
  as `✗ FAILED (Exit 0)` (verified by running one).
- Every repaired suite's `assert()` now `throw`s after `Qt.exit(1)`, so the first
  failed assertion stops the suite. The rule is recorded in `AGENTS.md` §3.4 and
  `docs/LESSONS.md` §37.
- The 16 masked assertions were repaired for their real causes, not to fit the
  harness:
  - **Impossible comparisons** (5): `item.color === "#1c1b1f"`,
    `iconColor === Colors.primary` - a colour value is an object, never the string
    it was written as, and two colour objects are never `===`. These now use
    `Qt.colorEqual`, which is already the repository's idiom.
  - **Stale design expectations** (7): MenuCard's radius/border (the card now
    takes `Theme.radiusGlassCard` and draws its fused edge with a `Shape`), the
    Card's edge policy (a `LiquidGlassCard` shows one hairline ring; nested cards
    drop it), the fused panel's morphing (the card *is* the envelope, and the
    assertion must wait for the `Behavior` tween), and a dock-pill mode
    (`"warning"`) that never existed in the always/never/dynamic ladder.
  - **Tests fighting their own subject** (4): one broke the reactive binding it
    existed to verify by assigning `dropdown.isOpen` directly; the token
    assertions compared values the offscreen harness cannot resolve, so they now
    assert the *token binding* where it lives (the popout's source) and the
    component's plumbing with literal colours - `ActionToggleItem` gained a
    documented `iconItem` alias for that.

**Verification.** The ten suites pass with no `FAIL:` lines; the whole run is
green: `make test` = 796 Rust tests + 116 QML suites, now with a harness that
cannot report a failing suite as passing.

---

# Astral Plasma — Installed Apps Are Discovered Without Restarting The Shell

> [!NOTE]
> **Issue**: After installing Herdr desktop (`herdr-app.desktop` in
> `~/.local/share/applications/`, `herdr-app.svg` in the hicolor theme), Herdr
> launched fine from the system and appeared in `astral-plasma apps`, but the
> Astral command launcher never offered it - searching `herdr` returned nothing.
>
> **Root cause**: the launcher's application list is a cache, and it was only
> invalidated while empty. `CommandLauncher` ran `astral-plasma apps` at
> `Component.onCompleted` and on open **only if** `installedApps.length === 0`;
> a cache that is already populated therefore never saw an entry installed later
> in the same session. `ActiveAppsOverview` wrapped
> `WindowService.reloadInstalledApps()` in the identical empty-cache gate. The
> daemon half was already correct - its index re-stamps on the `applications/`
> directory's mtime - so the shell had a fresh answer available and never asked
> for it. See [LESSONS §29](docs/LESSONS.md).
>
> **Solution**:
> 1. **Re-read on every open** (`shell/CommandLauncher.qml`): a new
>    `refreshInstalledApps()` is the single entry point for both startup and open.
>    It coalesces an in-flight query instead of spawning a second process.
> 2. **Never blank the launcher**: a failed or unparseable payload keeps the last
>    good list, and the previous list stays on screen until the fresh one arrives,
>    so typing is never blocked by the spawn.
> 3. **Selection follows identity, not position**: applying a payload re-anchors
>    `selectedAppIndex` on the highlighted row's `desktop_file` (a single new
>    entry shifts every index after it) and clamps when the row is gone.
> 4. **One policy for both surfaces** (`shell/ActiveAppsOverview.qml`): the
>    overview calls `WindowService.reloadInstalledApps()` on every open, so the
>    shared index behind the dock's identity mapping is refreshed by use as well.
> 5. **Tests** (`tests/tst_launcher_app_discovery.qml`): source contracts (no
>    empty-cache gate, coalescing, `desktop_file` re-anchoring, overview policy)
>    plus a deterministic model of the cache: warm-cache open still queries,
>    re-open during an in-flight query does not double-spawn, a newly installed
>    entry becomes searchable, a failed query keeps the list, and the highlighted
>    row follows its app across an insertion and clamps when it is removed.
>
> **Verified live** with the shell running throughout: a throwaway desktop entry
> written into `~/.local/share/applications/` was absent from the already-open
> launcher, then appeared on the next open after the fix, and disappeared again
> when its file was removed. Herdr is found at its alphabetical slot with its own
> hicolor icon.

---

# Astral Plasma — The App Drawer's Windows Are Live, Not Remembered

> [!NOTE]
> **Issue**: Hovering the Edge icon in the dock opened the app drawer showing
> "2 Open Windows". Clicking the × on the second window closed the window, but the
> drawer kept the row - and its "2 Open Windows" header, and "Close All Windows" -
> while the dock itself (fed by the same push) had already noticed.
>
> **Root cause**: the drawer displayed `WindowService.activePreviewApp`, an object
> whose `windows` array was a snapshot taken when the drawer opened. Every other
> surface rebuilds from the live window model; the drawer alone compared against a
> photograph. See [LESSONS §29](docs/LESSONS.md).
>
> **Solution**:
> 1. **Split seed from state** (`services/WindowService.qml`): `_previewAppSeed`
>    (labels), `_previewWindowIds` (which windows the drawer stands for) and
>    `_previewAnchorId` (which window the preview is about) are the snapshot;
>    `activePreviewApp` is re-derived from `windows` on every push.
> 2. **One pure module** (`services/PreviewAppState.js`): `trackedIds`,
>    `derive` and `signature` are exercised directly by the offscreen suite, so the
>    behaviour is tested as written rather than re-implemented in the test.
> 3. **Identity, anchor, churn** - membership is by window id (a display name would
>    let a foreign window in); the preview stays on the window the drawer opened on
>    (or the row under the pointer) and only falls back to focus when that window
>    closes; a `signature` keeps consumers from being handed a new object when
>    nothing visible moved, so the 1 s preview capture is not restarted needlessly.
> 4. **Close All iterates a copy** (`dock/popouts/FusedBottomPopout.qml`) - the row
>    list is live now, and a live list must not shrink under its own loop.
> 5. **Tests** (`tests/tst_app_preview_live_state.qml`): a closed window leaves the
>    drawer, the last close ends the app view ("Ready to launch") while keeping its
>    labels, focus only takes over when the anchor dies, a same-named foreign window
>    cannot enter, braced KWin uuids match, the signature is stable for identical
>    data, and exactly one `onWindowsChanged` handler exists (a duplicate silently
>    fails the whole configuration load - see [LESSONS §38](docs/LESSONS.md)).
>
> **Verified live**, drawer left open across every step: two windows gave two rows;
> closing one left one row and the header "Active Window"; closing the last gave
> "Ready to launch" with no rows. Before the fix the rows and the "2 Open Windows"
> header survived even with zero windows left.

---

# Astral Plasma — The Drawer Always Shows A Preview, Even When The Pointer Moves Fast

> [!NOTE]
> **Issue**: A drawer with two or more windows showed nothing but title bars - the
> single-window card had a live preview, the multi-window list had none ("in some
> cases, the preview is not showing"). And moving the pointer quickly between the
> two rows made the preview stop appearing altogether.
>
> **Root causes**:
> 1. A row only expanded while it was *the hovered row*, so with the pointer on the
>    dock icon (or between rows) the drawer had no preview at all.
> 2. Every hover force-restarted the capture process
>    (`running = false; command = ...; running = true`), which drops the start while
>    the previous instance is still terminating - the preview then stayed empty
>    until something else triggered a capture. The same pattern mis-cached a frame
>    if stdout arrived after the requested window changed.
> 3. Because the rows are re-derived on every window push, the drawer reset its
>    hover on every list update, collapsing the expanded row under the pointer
>    whenever a browser tab retitled itself.
>
> **Solution**:
> 1. **One expanded row, always** (`PreviewAppState.expandedWindowId`): the hovered
>    row wins; with nothing hovered the drawer's subject is expanded, so a
>    multi-window drawer reads like the single-window card.
> 2. **A hover survives a list update** (`rowsSignature` + `hoverAfterRowsChange`):
>    only a change in *which* windows are listed can end a hover - not a retitle or
>    a focus change.
> 3. **Single-slot capture queue** (`PreviewAppState.captureRequest` /
>    `captureFinished` + `WindowService._dispatchPreview`): a request that arrives
>    during a capture is remembered and dispatched when it finishes; nothing ever
>    restarts a live process, and a frame is always attributed to the key it was
>    requested for.
> 4. **Tests** (`tests/tst_app_preview_live_state.qml`): the expansion policy
>    (hover, subject, stale hover, empty list), hover survival across retitles,
>    signature changes on membership only, and the queue (idle dispatch, in-flight
>    request remembered, latest-wins, exactly one hand-over on finish) - plus
>    contracts that `loadAppPreview` goes through the queue and never starts the
>    capture process directly.
>
> **Verified live**: a two-window drawer now opens with one row expanded and its
> live thumbnail, and two back-to-back preview requests (the fast-hover race) still
> leave the second application with a working preview.

---

## 27. No Release Could Be Installed, And The Service Unit Skipped Its Own Supervisor

> [!NOTE]
> **Issue**: the theme shipped tagged releases, checksums and a tarball, but the
> tarball could not produce a working install. Separately, a shell installed as a
> systemd unit ran `quickshell -p <dir>` directly, so it never took the Plasma
> claim, never journalled the shortcuts it replaced, and never restored them.
>
> **Root causes**:
> 1. The QML tree lives *inside* the binary (`include_dir!`), and the tarball
>    shipped only `bin/astral-plasma` plus docs. `install.sh` then symlinked the
>    directory it ran from into `~/.config/quickshell` - a directory with no
>    `shell.qml`. Only a checkout that built itself worked.
> 2. The unit generator wrote `ExecStart=<quickshell> -p <dir>`, bypassing
>    `astral-plasma run`: a service install displaced the desktop with nothing
>    that knew how to put it back.
> 3. There was no install record, so nothing could tell a self-updating install
>    from a package manager's or a developer's checkout.
>
> **Solution**:
> 1. **One layout, one implementation** (`application/install_service.rs`): the
>    binary, its extracted bundle and `install.json` are written by
>    `astral-plasma install`; `install.sh` only fetches, verifies and delegates.
>    The installer works from a checkout, a tarball, a given binary (`--from`) or
>    a bare `curl | bash` (manifest + SHA-256 verified download).
> 2. **The unit runs the supervisor** (`domain/systemd.rs`,
>    `systemd_adapter.rs`): `ExecStart=<bin> astral-plasma run` plus
>    `ASTRAL_PLASMA_PACKAGE_DIR`, so service installs get the claim, the shortcut
>    journal and restore-on-exit.
> 3. **Migrations reach existing installs** (`application/migrations/`):
>    timestamped, idempotent, per-user markers under the state dir; a failure
>    stops the start instead of half-migrating. `001_adopt_legacy_install` copies
>    the running binary, extracts the matching bundle, records the owner and
>    rewrites a Quickshell-only unit - without moving the checkout, deleting
>    `~/.config/quickshell`, or adopting a `target/debug` build.
> 4. **Removal knows what it owns** (`application/uninstall_service.rs`): the
>    binary, bundle, rollback copy, update state and the unit/entries it wrote
>    are removed; the AI harness's sessions, the Plasma and shortcut backups,
>    download history, caches and settings are kept, with `--purge` as the
>    explicit opt-out for caches and settings.
> 5. **Every release must say what changed**: `docs/releases/<version>.json` is
>    required by `scripts/release.sh` and CI, and the publish job emits
>    `latest.json` (per-arch URL, size, SHA-256, highlights) for the updater.
> 6. **Tests**: `test_install_record`, `test_install_service`,
>    `test_uninstall_service`, `test_migrations`, `test_migration_runner`,
>    `test_release_install` (drives the real scripts against a throwaway
>    `$HOME`), `test_release_manifest`, plus the unit-contract assertions in
>    `test_systemd_rust`.
>
> **Verified live** (this machine, a symlinked checkout install):
> `./bin/astral-plasma migrate` adopted the install - `install.json` recorded
> `managed` 0.1.3, `~/.local/share/astral-plasma/package/shell.qml` and its 13
> QML directories appeared, `~/.config/quickshell` still pointed at the checkout,
> and the settings file's checksum was unchanged. `migrate --pending` then
> printed `[]`, and `astral-plasma uninstall` without `--yes` listed what it
> would remove and exited 2 having changed nothing.
>
> **Not verified**: the download path of `install.sh` (needs a published
> `latest.json`, i.e. the next release) and the CI publish job itself.

---

## 28. The Updates Page Could Not Be Reached, And The Curtain Took The Whole Shell Down

> [!NOTE]
> **Issue**: adding "Updates & About" to the settings rail produced a page nobody
> could navigate to, and the restart curtain - loaded by `shell.qml` on every
> start - made the shell fail to load at all.
>
> **Root causes**:
> 1. `shell/UpdateCurtain.qml` used `MaterialIcon { icon: ... }`; the component's
>    property is `text`/`iconName`. The type failed to instantiate, and because
>    `shell.qml` instantiates it eagerly, the whole configuration failed with
>    "Type UpdateCurtain unavailable". Found by starting the real shell, not by
>    the test suite.
> 2. The settings rail is a clipped `Flickable` that never scrolled to the active
>    page. The rail had exactly enough room for the old list; one more item left
>    "Updates & About" below the fold, so `settings open updates` showed the page
>    with no rail entry to explain where it came from.
> 3. A disabled update action used `variant: "filled"`, which does not encode
>    inactiveness in its fill, so "Update and restart" looked pressable while the
>    page said there was nothing to install.
>
> **Solution**:
> 1. `MaterialIcon.text` - and the acceptance that a component which loads on
>    every start needs a live boot to prove it.
> 2. The rail scrolls to the active pill (`activeNavPill` + `revealActiveNavPill`,
>    one event-loop turn after navigation so the delegate has geometry), with
>    `boundsBehavior: StopAtBounds`.
> 3. Disabled actions use the tonal variant and drop to 55 % opacity; the apply
>    and revert handlers also re-check `active`, so a stale click cannot apply an
>    update the daemon already refused.
>
> **Verified live** (real KWin session, shell started with `./run.sh`, browser and
> editor behind it): `settings open updates` shows Version 0.1.3, "Updated by the
> shell · channel stable", "This install is up to date", an inert "Update and
> restart", and the four compiled release notes; the rail scrolled itself to
> reveal and highlight "Updates & About". Quitting restored plasmashell and the
> shortcuts (`[✓] Shortcuts restored`, `plasma-plasmashell` active).
>
> **Not verified**: the curtain mid-update (it only appears while an apply is
> running; the swap and rollback are proven in `test_update_supervisor.rs` and in
> the throwaway-root run against a local HTTP release).

---

## 29. "Up To Date" On An Install That Had Never Been Checked

> [!NOTE]
> **Issue**: the Updates page said "This install is up to date." while its own
> subtitle said "No update has been checked yet." Both were rendered from the
> same daemon status, so one of them was a lie.
>
> **Root cause**: `refusal()` treated "no candidate" as "nothing has been
> checked". Those are different states - an install that was checked and is
> current has no candidate *and* nothing to refuse - and `can_apply` was derived
> from the refusal alone, so the two collapsed into one.
>
> **Solution**: refusal now distinguishes never-checked (from `last_check_unix`)
> from checked-and-current, `can_apply` requires a candidate *and* no refusal, and
> the page's eyebrow reads "not checked" until a check has actually happened.
> Tests pin both states, plus the staged-update refusal.
>
> **Also in this round**: the settings rail shows an opt-in attention dot
> (`PillButton.badgeVisible`) when a release is waiting; release signing is wired
> end to end (`scripts/astral-sign.sh`, conditional CI signing with
> `MINISIGN_SECRET_KEY`, `PINNED_MINISIGN_KEY`, `ASTRAL_PLASMA_REQUIRE_SIGNATURE`)
> and a signature with no key to check it against is refused instead of being
> compared with the user's own keyring.
>
> **Verified live**: with a candidate served by a local release server, the page
> showed "AVAILABLE · 0.2.0", a real size, an enabled "Update and restart", and
> the rail carried the dot on "Updates & About"; the candidate state was removed
> afterwards. Quitting restored plasmashell and shortcuts.
>
> **Not verified**: executing `scripts/astral-sign.sh` end to end - `minisign` is
> not installed on this machine, so only its syntax and its wiring are proven.

---

## 30. Signing A Document By Writing The Signature Into It Cannot Verify

> [!NOTE]
> **Issue**: the signing pipeline "worked" as a script but could not verify: the
> signature was computed over `latest.json` and then written back into a
> `signature` field of that same file.
>
> **Root cause**: a detached-signature tool signs bytes. Adding the signature to
> the document changes the bytes that were signed, so every signed release would
> have failed verification at the exact moment it mattered. The first live test of
> a signed manifest is what exposed it.
>
> **Solution**:
> 1. The signature is a sibling asset (`latest.json.minisig`), verified over the
>    exact bytes fetched. The manifest no longer has a `signature` field; an old
>    release that still carries one stays installable (unknown fields are
>    ignored).
> 2. Verification happens **in-process** with `minisign-verify`, so an installed
>    shell needs no signing tool; only CI signs. A signature with no pinned key is
>    refused rather than checked against the user's own keyring.
> 3. The project key exists: public half committed
>    (`packaging/keys/astral-plasma.pub`, key id `47F66C1650F9EE59`), pinned as
>    `PINNED_MINISIGN_KEY`, secret half in `~/.minisign/astral-plasma.key` and the
>    repository secret `MINISIGN_SECRET_KEY`; CI installs `minisign` and signs.
> 4. A verification failure is now recorded in the update state, so the page can
>    explain it instead of showing a silent "failed".
> 5. `quit_running_shell` no longer inherits the child's stdout: `update apply`
>    prints JSON, and "No running instances…" on the same stream made it
>    unparseable.
> 6. A signed fixture (`daemon/tests/fixtures/`) pins the contract: the committed
>    key verifies the committed signature, one changed byte does not, an unsigned
>    release is reported as unsigned, and garbage is an error.
>
> **Verified live** against a local release server: a signed `latest.json` was
> accepted and staged (sha256 `d5ac868b…`); editing the version after signing made
> the check fail with "release signature verification failed" and the reason
> appeared in `update status`; with `ASTRAL_PLASMA_REQUIRE_SIGNATURE=1` a signed
> release was accepted and an unsigned one refused with "only installs signed
> releases".
>
> **Not verified**: the GitHub Actions signing step itself (it needs a tagged
> release), and enforcement is deliberately left off until one signed release has
> shipped.

---

## P1 — kernel moved into `modules/Astral/Kernel` (2026-11-08)

The kernel (`theme/`, `components/`, `config/`, `services/`) now lives at
`modules/Astral/Kernel/`, so the tree can grow apps beside it instead of beside
a flat pile of directories. This is a move, not a redesign: no behaviour changed,
no `qmldir` was introduced yet.

> **Verified**: `make test` exit 0 — 153 QML suites and 988 Rust tests pass after
> the move. The shell was started on the running KWin/Wayland session
> (`quickshell -p <checkout>`, zero `ERROR` lines in the log) and three surfaces
> were captured: the dock with real application icons and the outer frame; the
> dashboard with all seven tabs, live weather, calendar and power controls; and
> Nexus Settings showing the real wallpaper thumbnail and the wallpaper-derived
> accent palette.
>
> **Not verified**: a before/after pixel diff. The claim is that the surfaces
> load and render their real content, not that the rendering is pixel-identical.

Two things the move taught, both recorded in `docs/APPS-PLATFORM-SPEC.md`
Appendix C.6:

1. **Two import dialects.** Three files used `qs.theme` / `qs.services`, which
   Quickshell resolves against the shell root. A codemod that only understands
   `../` reports success and leaves the shell unloadable — the live run is what
   caught it.
2. **A `qmldir` is not a rename.** Importing a QML module compiles its singleton
   entries eagerly; the kernel's singletons import `Quickshell`; `qml6` has no
   Quickshell plugin, so a module URI would turn all 153 suites red even though
   `quickshell` loads the same code fine. The module URI is therefore a P2
   change, made where the real shell owns the import path.

---

## P2 (first slice) — app contract, policy, registry, `astral app list` (2026-11-08)

The platform now has a contract, and the contract is enforced by code rather than
prose:

- **Manifest** (`domain/app_manifest.rs`) — one validator, every refusal naming
  the field: an `entry.root` that escapes the payload, an unknown permission, a
  community app claiming `embedded`, a hosted app whose root is not `shell.qml`.
- **Compatibility** (`domain/app_compat.rs`) — `APP_API_LEVEL`/`APP_API_FLOOR`
  plus `API_LEVEL_HISTORY`, so a warning can say *"needs Astral 0.2.0 or newer
  (API 2); this is API 1"* while enforcement stays integer-exact.
- **Policy** (`domain/app_reconcile.rs`) — install/update admission (forward only,
  a republished digest refused, downgrades behind the `dataSchema` guard) and the
  whole §8.5.4 platform-move table: auto-update when a compatible version exists,
  otherwise disable with a recorded reason, core apps take their baseline, and
  nothing is ever uninstalled.
- **Registry** (`application/app_service.rs`) — `apps.json` with duplicate-id
  refusal; a missing file is an empty registry, not an error.
- **`astral app list [--json]`** — reads that registry through the same policy the
  host will, and every unimplemented subcommand names the phase it lands in
  instead of silently doing nothing.
- **`sdk/examples/hello/`** — the fixture an author copies, validated by the same
  code that validates an install, so the authoring side cannot drift.

> **Verified**: `make test` exit 0 — 1041 Rust tests (53 new) and 153 QML suites.
> `astral app list` printed `No apps installed.` on an empty data dir; with a
> three-app fixture it printed `ready` / `incompatible  needs a newer Astral
> (API 2); this is API 1` / `disabled`, and `astral app install foo` refused with
> the phase that will implement it.
>
Registry writer, host policy, and the CLI verbs followed in the same phase:

- **Writer** (`application/app_service.rs`) — `apps.json.tmp` + `sync_all` +
  rename + directory sync; a corrupt existing file is never clobbered, and a
  registry a reader would refuse is never persisted.
- **Host policy** (`modules/Astral/Kernel/Host/AppHostPolicy.js`, 30 assertions in
  `tests/tst_app_host_policy.qml`) — who loads, why the rest do not, dependency
  order, cycles, duplicate ids, and a coherent-window clamp. No app is named.
- **`astral app enable|disable <id>`** — verified live: `Disabled
  org.astralplasma.downloads` then `already disabled`, `app list` showing
  `disabled`, and an unknown id refused with `"'io.github.ghost' is not
  installed"` and exit 1.

> **Verified**: `make test` exit 0 twice in a row — 1049 Rust tests and 154 QML
> suites.
>
> **Not done**: `AppHost.qml` itself, `SurfaceBroker`/`IntentBus`, and moving
> `overview` out as the first app. Those are the rest of P2.
>
> **One flake, not fixed**: `test_doctor::pi_harness_check_…` failed once in
> three full runs (a spawn of the fake `pi` script returned no version under
> parallel load). The probe now retries a failed *spawn* only, but the flake did
> not reproduce afterwards, so the fix is unproven.

---

## P3 (first slice) — `Astral.AppKit`, and a real app through it (2026-11-08)

`modules/Astral/AppKit/` is the public module an app author targets:

| Type | What it is |
| :--- | :--- |
| `AppApi` | level/floor + level→release history, pinned to the daemon by test |
| `AppPalette` | reads the host's exported palette (internal) |
| `Colors`, `Theme` | public roles, radii, typeface — from that palette, with Material 3 fallbacks |
| `Motion` | design constants, pinned to `theme/Theme.qml` by test |
| `AppWindow` | the glass toplevel, self-contained |

The sandbox decided the architecture: a hosted app mounts `Astral/AppKit` and
nothing else, so AppKit cannot import the kernel — it reads the palette the kernel
already writes. `ThemeExportService` now exports `radius_*` and `font_family` too,
so an archetype change reaches community apps without a rebuild.

> **Verified**: `daemon/tests/test_appkit.rs`, 7 tests. The live one starts
> `quickshell` on a temp app, sets `ASTRAL_APPKIT_PALETTE` to a palette with
> `radius_large: 12` and `font_family: "Test Sans"`, and asserts the app logs
> `radius=12`, `source=palette`, `font=Test Sans` — i.e. it painted with the
> host's data, not with AppKit's fallbacks. `sdk/examples/hello` was also run on
> the running session and captured: a glass card reading "Hello Astral / built
> against API 1" beside the real dock.
>
> **Not verified**: the sandbox itself (no `bwrap` mount of a real app yet), and
> the SDK verbs (`new/dev/test/lint/pack`) — P3 remainder.

---

## P2 (second slice) — the host, and the registry that feeds it (2026-11-08)

`modules/Astral/Kernel/Host/` is now the `Astral.Kernel.Host` module:

| File | Job |
| :--- | :--- |
| `AppManifest.js` | load-time manifest validation (identity, version, API level, entry root) |
| `AppHostPolicy.js` | the pure plan: who loads, why the rest do not, dependency order |
| `AppHost.qml` | one inactive `Loader` per planned app, `activate(id)`, failure reporting |
| `AppRegistry.qml` | reads `apps.json` + each manifest, merges registry state, reports errors |

> **Verified on the live session**: a temp registry with one embedded fixture app
> printed `PLAN loaded=[io.github.fixture.embedded] skipped=[] errors=[]` and then
> `EMBEDDED_APP_LOADED` after `activate()`. QML suites cover the rest: a corrupt
> manifest beside good ones still plans and loads the good ones; a payload whose
> QML does not compile reports `appFailed` and `activate` returns null; a missing
> payload is reported once; every planned loader is `active === false` at boot;
> and a hosted app is skipped as `hosted` because it is a separate process.
>
> The manifest contract is now checked from **both** sides against the same
> fixtures (`tests/fixtures/apps/`): Rust via `test_app_manifest_fixtures.rs`, QML
> via `tst_app_manifest_validation.qml`. If either validator drifts, one suite
> fails.
>
> **Verified**: `make test` exit 0 — 1059 Rust tests, 156 QML suites.
>
> **Not done**: `SurfaceBroker`/`IntentBus`, and routing `overview` through the
> host (that is the change that touches `shell.qml`).

---

## P2 close-out attempt — reverted, and why (2026-11-08)

I tried to move the overview out of `shell.qml` and load it through `AppHost`, with
a generated `modules/Astral/Apps/index.json` instead of an import. The pieces all
worked — the host planned it, activated it, and reported `app loaded`; the IPC
handler flipped `Config.overviewVisible` from `false` to `true` — and the surface
still did nothing.

The reason is a real one: **a component loaded through a `Loader` gets its own
singleton instance for a directory import.** The app's `Config.overviewVisible`
stayed `false` on every tick while the shell's copy was `true`. So a migrated
surface reads stale settings, and no relative path fixes that.

> **Verified**: `IPC overview toggle; was false` / `now true` in the shell, while
> the app logged `app sees Config.overviewVisible=false` on a 700 ms timer, with
> three screenshots showing no overlay.
>
> **Reverted**: `shell.qml`, the surface file, and the three suites it touched are
> back to committed state; the app directory and index generator are gone. `make
> test` green again — 1059 Rust tests, 156 QML suites.

Kept from the attempt: the packaging fix (a package must ship `modules/` as one
tree, or an installed shell has no AppKit and no host).

Conclusion, now recorded in the spec as a prerequisite: migrating an embedded app
needs `IntentBus` for shell state and a port for the settings it reads. That is the
next unit of work, and it is a design change — not a file move.

---

## P2 — IntentBus, ShellState, injection, boundary gate (2026-11-08)

The pipeline a migrated surface needs, each piece tested:

| Piece | Job |
| :--- | :--- |
| `Host/IntentBus.qml` | named intents → typed `ActionResult`; unknown = `unsupported`, thrown handler = `invalid` |
| `Host/ShellState.qml` | read model with **no kernel imports**; the shell binds its values |
| `AppHost.state/.intents/.eager` | injection contract + boot activation for shell-owned surfaces |
| `scripts/check_app_boundaries.py` | CI gate in `make test`: no `Kernel/config`, no cross-app imports, AppKit-only for non-official apps |

> **Verified**: `make test` exit 0 — 1059 Rust tests, **159** QML suites (three new:
> `tst_intent_bus`, `tst_app_host_injection`, `tst_shell_state`), boundary linter
> clean. The injection suite proves identity, not equality: the app receives *the
> same* state object the shell mutates, and a later mutation is visible in it.
>
> **Also verified, then reverted**: the overview migrated as an app, opened on
> `overview toggle`, and obeyed the injected state (`overview tick: state=true`).
> It rendered an **empty preview grid** — its `WindowService`, imported from
> `Kernel/services`, is a different instance with no windows. Same defect as
> `Config`, one layer down (spec C.10).

So the remaining blocker is named: a **session port** (windows, thumbnails,
activation) injected like `ShellState`, then `overview` and the rest. The host,
the bus, the state, and the gate exist; the data model does not.

---

## P2 — the overview is an app (2026-11-08)

`shell/ActiveAppsOverview.qml` is now `modules/Astral/Apps/Overview/Main.qml`,
loaded from the generated `modules/Astral/Apps/index.json` through `AppHost`
(`eager`, because the shell shows and hides it). `shell.qml` no longer names it.

| Reads | Was | Now |
| :--- | :--- | :--- |
| open/closed | `Config.overviewVisible` | `shellState.overviewVisible` |
| windows | `WindowService.windows` | `session.windows` |
| thumbnails | `WindowService.overviewThumbnails` | `session.overviewThumbnails` |
| actions | `Config.*` / `WindowService.*` | `intents.request(...)` / `session.*` |

The app has **0** `Config.` and **0** `WindowService.` uses, enforced by
`scripts/check_app_boundaries.py` inside `make test`.

> **Verified**: `make test` exit 0 — 1063 Rust tests, 160 QML suites, boundary gate
> clean. Live: `overview toggle` opens the surface (`open=true` in the app's own
> log), and binding a single stub window to `SessionPort.windows` rendered a
> **Probe Window** card in the grid — proof that the injected model reaches the UI,
> not just the port. The stub was removed afterwards.
>
> **Not verified**: a populated grid from real windows. The shell's own
> `WindowService.windows` is empty on this dev box (no claimed Plasma session), and
> it was empty before the migration too — the same data source, so nothing is lost,
> but "eleven real windows in a 4-column grid" remains unobserved here.

---

## P3 — the author path works end to end (2026-11-08)

```
astral app new io.github.alice.clock --template surface --dir clock
  → manifest.json, shell.qml, README.md, tests/

astral app lint clock        → clock: clean
astral app pack clock        → io.github.alice.clock-0.1.0.astralapp
                               digest sha256:79e62409…
                               3 file(s)
```

| Piece | Where |
| :--- | :--- |
| ustar writer/reader, validation, digest | `domain/app_bundle.rs` (10 tests) |
| templates, lint, pack | `application/app_sdk.rs` (8 tests) |
| CLI verbs | `astral app new\|lint\|pack\|test` |
| templates load for real | `daemon/tests/test_app_sdk_templates.rs` — spawns `quickshell` for each template, bounded to 4 s |

`Bundle::validate` refuses a bundle whose `entry.root` is missing from the archive,
so a truncated `.astralapp` fails at install instead of at launch. Packing is
offline: no archive dependency, mtime pinned to 0 so the same source packs to the
same digest.

> **Verified**: `make test` exit 0 — **1082 Rust tests**, 160 QML suites, boundary
> gate clean. All three templates load under a live `quickshell` (surface,
> layer-surface, service) with zero load errors, and the surface one was captured
> rendering its window.
>
> **Not verified**: `astral app dev` (the sandbox is P6), install/update (catalog is
> P5), and signing (needs a private key the daemon must not own).

---

## Regression fixed: the kernel move disconnected the daemon (2026-11-08)

Reported live: no taskbar app icons, no window previews, no system tray. My fault,
and the cause was P1.

Twelve services computed the daemon as `<their own directory>/../bin/astral-plasma`.
That was right when `services/` sat at the repository root; after the move it pointed
at `modules/Astral/Kernel/bin/`, which does not exist. Every daemon `Process` call
failed with a warning the shell never showed — windows, tray, previews, clipboard,
network, downloads, metrics.

Why 153 suites stayed green: nothing asserted where the shell thinks the daemon is.

**Fix**: `modules/Astral/Kernel/config/Paths.qml` owns the layout (`daemonBin`,
`root`, `scriptsDir`), resolved from its own position with an
`ASTRAL_PLASMA_DAEMON` override. `Config.daemonBin` delegates to it; the services
ask it; none of them computes a path.

**Guard**: `daemon/tests/test_runtime_paths.rs` — fails if any kernel file derives
the daemon from its own directory, if `Config` computes a second path, if a
`daemonBin` property does not delegate, or if the resolved binary is not a file.

> **Verified**: `make test` exit 0 (1086 Rust tests, 160 QML suites). The shell was
> restarted with the project's own launcher (`run.sh`, exactly one instance) and the
> dock came back with running-window icons and badges, and the tray reappeared.
>
> The "second background out of sync" report was two `quickshell` instances running
> simultaneously from my debugging restarts; only one runs now.
