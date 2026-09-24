# Hyprland and Omarchy Compatibility Specification

> **Status:** Design baseline accepted; implementation pending.
>
> **Scope:** Add Hyprland support and first-class hosted Omarchy plugin support without rewriting the shared visual shell or removing KDE Plasma/KWin support.

This specification is the implementation contract for the portability work. The visual and motion rules remain governed by [`DESIGN.md`](../DESIGN.md) and [`docs/LESSONS.md`](LESSONS.md). The ubiquitous language is defined in [`CONTEXT.md`](../CONTEXT.md). Repository contribution and verification rules remain governed by [`AGENTS.md`](../AGENTS.md).

---

## 1. Decision summary

Astral Plasma will use a ports-and-adapters architecture with one compositor-neutral desktop-session language.

```text
QML presentation
        ↓
DesktopSessionFacade
(common UI-facing API)
        ↓
DesktopSessionCoordinator
        ↓
Canonical domain model and ports
        ↓
 ┌──────────────────────┬──────────────────────┐
 │ KWinAdapter          │ HyprlandAdapter      │
 │ Plasma profile       │ Omarchy profile      │
 └──────────────────────┴──────────────────────┘
```

The required decisions are:

1. Plasma/KWin remains a supported first-class environment.
2. Hyprland is added as a second compositor backend.
3. Omarchy is an environment profile over the Hyprland backend, not a third backend.
4. On Omarchy, Astral Plasma runs as a hosted plugin inside `omarchy-shell`; it does not start a competing Quickshell host.
5. The QML visual tree remains shared; backend differences are resolved through ports, capabilities, and profile policy.
6. KWin and Hyprland protocol objects never cross into the core domain or shared QML components.
7. Each subsystem exposes a small, typed interface. There is no single unbounded `DesktopAPI` containing every operation.
8. The common API is a language-neutral contract. Rust traits and QML bindings implement the same vocabulary and message schema.
9. The shell never presents unsupported actions as successful no-ops.
10. The migration is incremental: contracts and KWin extraction first, Hyprland second, hosted Omarchy integration third.

### Supported claim

Astral Plasma supports Omarchy 4.0.x as an optional Quickshell plugin integration with one active bar or bar-widget contribution, while `omarchy-shell` retains ownership of session-critical desktop services. A complete independent replacement for `omarchy-shell` is not claimed; that capability would require an upstream host API or a fork.

---

## 2. Goals and non-goals

### Goals

The implementation shall:

- Launch the existing Astral Plasma visual shell under Plasma/KWin and Hyprland.
- Preserve the current shell surfaces, layout language, motion tokens, and component boundaries.
- Provide canonical windows, outputs, workspaces, shell surfaces, capabilities, actions, and events.
- Support workspace switching, active-window tracking, window activation/closure, shell actions, and global shortcut delivery where the active environment permits them.
- Support Hyprland's native Quickshell integration for reactive compositor state.
- Support Hyprland previews, layer-shell surfaces, focus grabbing, and capability-aware blur.
- Provide a first-class hosted Omarchy plugin profile while `omarchy-shell` remains the desktop host.
- Support an explicitly experimental standalone Hyprland mode for users who are not using Omarchy.
- Centralize lifecycle ownership so panels, shortcuts, notifications, and related services are restored only by the profile that changed them.
- Keep system services behind their own ports rather than coupling them to a compositor adapter.
- Preserve the current normalized window/workspace data during migration.
- Add automated contract tests, real-session smoke tests, and visual verification.

### Non-goals

The first implementation does not:

- Rewrite the QML visual shell or replace its design system.
- Fork or embed Omarchy.
- Replace the complete `omarchy-shell` host; current Omarchy 4.0.4 exposes plugin entry points, not a general shell-replacement API.
- Start a second Quickshell host while `omarchy-shell` is active.
- Take ownership of Omarchy's notifications, lock, polkit, idle, OSD, or menu services in hosted mode.
- Claim identical compositor effects where protocols differ.
- Make X11 a supported Hyprland session; XWayland applications remain in scope.
- Add event sourcing or a persistent desktop-state database.
- Make raw `hyprctl`/IPC the first Hyprland implementation.
- Put audio, network, power, or tray state into a compositor aggregate.
- Silently terminate existing desktop services.
- Hardcode a particular user's keybinds, monitor layout, or Omarchy configuration.

---

## 3. Domain context map

### Core domain: Desktop Session

The core domain models the live desktop session and the user-visible outcomes the shell coordinates.

| Concept | Responsibility |
|---|---|
| `DesktopSession` | Session identity, connection state, focused output, profile, capabilities, and snapshot revision |
| `Output` | Stable display identity and geometry/state projection |
| `Workspace` | Workspace identity, name, index, output association, and active state |
| `Window` | External application identity, metadata, placement, and lifecycle |
| `ShellSurface` | Shell-owned surface identity and semantic visibility lifecycle |
| `Capability` | Queryable support for a user-visible operation or effect |
| `UserIntent` | A backend-neutral request for a user outcome |
| `ActionResult` | Typed success, pending, unsupported, denied, unavailable, invalid, or stale outcome |
| `DesktopEvent` | Immutable canonical fact emitted after a state transition |

### Supporting context: Desktop Integration

This context contains the anti-corruption layer for external desktop systems:

- KWin D-Bus and scripting
- Plasma lifecycle and configuration
- Hyprland native Quickshell APIs
- Optional Hyprland IPC fallback
- Generic Wayland toplevel operations
- Focus restoration and focus grabbing
- Wallpaper, preview, and compositor-effect providers

### Supporting context: Environment Profiles

This context contains deployment policy:

- `KdeProfile` for Plasma/KWin
- `HyprlandProfile` for a plain Hyprland session
- `HostedOmarchyProfile` for an Astral plugin running inside `omarchy-shell`
- `StandaloneHyprlandProfile` for explicitly experimental standalone operation
- profile selection, capability policy, resource ownership, and integration lifecycle

### Supporting context: Desktop Host

Omarchy's `omarchy-shell` is the long-lived Quickshell host for its bar, menu, notifications, OSD, lock, polkit, idle, and other plugins. In hosted mode, Astral Plasma is a plugin entry point inside that host. The host owns session-critical services unless the user explicitly chooses a standalone, non-Omarchy profile.

### Generic/supporting contexts

The following remain separate from Desktop Integration:

- Audio and media
- Network and Bluetooth
- Power and session actions
- Notifications
- StatusNotifier/tray
- Keyboard and input-method services
- Brightness and power profiles
- Calendar and application launch resolution

### Dependency direction

```text
Presentation → Application → Domain ports ← Infrastructure adapters
       │              │              │
       └──── profile/capability policy ┘
```

The domain must not import compositor protocol types. Infrastructure may depend on domain ports. Presentation may consume the application facade and canonical projections, never raw backend objects.

---

## 4. Canonical language and data contract

All adapters and UI bindings shall use the following names. Existing JSON fields remain backward-compatible during migration; new fields are optional and versioned.

### `DesktopSessionSnapshot`

```json
{
  "schemaVersion": 1,
  "sessionId": "stable-session-id",
  "revision": 42,
  "connection": "starting | connected | degraded | disconnected",
  "profile": "kde | hyprland | omarchy",
  "focusedOutputId": "output-id",
  "outputs": [],
  "workspaces": [],
  "windows": [],
  "capabilities": {},
  "lastUpdated": 0
}
```

A snapshot is a complete projection at a revision. It is the startup and reconciliation baseline.

### `Output`

Required canonical fields:

- `id`
- `name`
- `geometry: { x, y, width, height }`
- `scale`
- `refreshRate`
- `focused`
- `primary`

Backend-specific fields are optional extension data and must not be required by shared UI components.

### `Workspace`

Required canonical fields:

- `id`
- `name`
- `index`
- `outputId`
- `active`

The active workspace is defined per output. The UI derives the global “current workspace” from the focused output.

### `Window`

Required canonical fields:

- `id`
- `appId`
- `title`
- `outputId`
- `workspaceId`
- `active`
- `maximized`
- `minimized`
- `floating`

Existing fields such as `appName` and `isActive` remain available during the compatibility period. Window identity must be stable for the lifetime of the window and must not depend on a display title.

### `CapabilitySet`

Capabilities are named values with an availability state and optional reason:

```json
{
  "workspaceSwitch": { "available": true },
  "windowPreview": { "available": true },
  "backgroundBlur": { "available": true, "mode": "region" },
  "globalShortcuts": { "available": true, "owner": "compositor" },
  "focusRestore": { "available": false, "reason": "not-supported" }
}
```

The capability set is discovered by the active backend/profile and exposed through the common API. QML components do not infer support by trying an operation.

### `UserIntent`

```json
{
  "requestId": "uuid",
  "kind": "focus-workspace | activate-window | toggle-surface | restore-focus",
  "target": {},
  "parameters": {}
}
```

The intent vocabulary is stable. Backend adapters translate an intent into backend operations.

### `ActionResult`

```json
{
  "requestId": "uuid",
  "status": "applied | pending | unsupported | permission-denied | unavailable | invalid | stale",
  "messageKey": "stable-user-message-key",
  "details": {},
  "revision": 43
}
```

A command that cannot be performed shall return a typed result. It shall never silently become a successful no-op.

### Canonical events

The first event set is:

- `SessionConnectionChanged`
- `WorkspaceActivated`
- `WindowFocused`
- `WindowListChanged`
- `OutputChanged`
- `ShellSurfaceVisibilityChanged`
- `CapabilityChanged`
- `ActionCompleted`

Raw KWin and Hyprland events remain integration events inside their adapters. They are translated before reaching the application or UI layers.

---

## 5. Ports and adapter responsibilities

The domain/application layer defines the ports. Infrastructure implements them. Each port is independently testable and may be unsupported by a backend.

| Port | Canonical responsibility | KWin implementation | Hyprland implementation |
|---|---|---|---|
| `DesktopSessionPort` | Snapshot, connection state, profile, capabilities | KWin session coordinator | Hyprland session coordinator |
| `DesktopHostPort` | Detect, handshake with, and delegate to an existing shell host | KDE session lifecycle | `omarchy-shell` plugin host/IPC |
| `SessionServicePort` | Query or delegate session-critical host services | Plasma/KDE services | Omarchy host services in hosted mode |
| `WindowManagerPort` | Query, activate, close, and minimize windows | KWin scripts/D-Bus | Generic Wayland toplevel operations plus Hyprland metadata |
| `WorkspacePort` | Query and switch workspaces | KWin virtual desktops | Hyprland workspaces/dispatcher |
| `OutputPort` | Query outputs and focused output | KWin screen state | `Quickshell.screens` and Hyprland monitor mapping |
| `DesktopEventSource` | Initial state, incremental events, reconnect | KWin watcher scripts | `Quickshell.Hyprland` event stream |
| `FocusPort` | Restore focus and manage focus-grab behavior | KWin focus restoration | Hyprland focus APIs and `HyprlandFocusGrab` |
| `ShortcutPort` | Register/restore semantic global actions | KWin shortcut package and runtime config | Hyprland native global shortcuts and user binds |
| `DesktopLifecyclePort` | Start, stop, restore, and reconcile owned resources | Plasma/KWin lifecycle | Hyprland session lifecycle and optional profile hooks |
| `WallpaperPort` | Query/apply the desktop wallpaper provider | Plasma wallpaper provider | Configured Hyprland/Omarchy wallpaper provider |
| `PreviewPort` | Capture a window preview | KWin `ScreenShot2` | Quickshell `ScreencopyView` |
| `CompositorEffectsPort` | Configure/read supported visual effects | KWin blur configuration | Region blur capability and fallback policy |
| System-service ports | Power, audio, network, tray, input, notifications | Existing providers | Pluggable Hyprland/Omarchy providers |

A port implementation may return `unsupported` or `unavailable`; it is not required to emulate another backend.

---

## 6. Adapter specifications

### 6.1 KWin adapter

`KWinAdapter` remains the reference implementation of the shared ports.

It shall:

- Preserve the current normalized window/workspace JSON shape.
- Continue to use KWin D-Bus, KWin scripting, and existing Plasma services behind ports.
- Emit canonical events from the existing watcher payloads.
- Keep KWin blur strength and Plasma lifecycle configuration inside KWin/Plasma infrastructure.
- Remain selectable when the active profile is `kde`.
- Continue to pass all existing KWin/Plasma tests.

The current hardcoded construction sites shall be replaced by a session/backend factory:

- `daemon/src/interfaces/cli.rs`
- `daemon/src/interfaces/api_server.rs`
- `daemon/src/application/watch_events.rs`

### 6.2 Hyprland adapter

The first Hyprland implementation shall use the native Quickshell Hyprland module when available.

It shall use:

- `Quickshell.Hyprland.monitors` for monitor facts.
- `Quickshell.Hyprland.workspaces` for workspace facts.
- `Quickshell.Hyprland.toplevels` for Hyprland window metadata.
- `focusedMonitor` and `focusedWorkspace` for actual focus state.
- `activeToplevel` for the active window.
- `Hyprland.dispatch()` or the corresponding workspace/window methods for supported commands.
- `GlobalShortcut` for compositor-native global actions.
- `HyprlandFocusGrab` for click-outside dismissal where appropriate.
- `Quickshell.Wayland.Toplevel` for portable activate/close/minimize operations.
- `ScreencopyView` for internal window previews.

The adapter shall observe the semantic difference between a requested workspace event and the currently focused workspace. It shall not infer current focus solely from a workspace-change event.

The native Hyprland module is optional at build time. Its import shall be isolated so a build without Hyprland support still loads the portable shell and reports Hyprland-only capabilities as unavailable.

A raw Hyprland IPC adapter may be added later behind the same ports. If implemented, each request connection shall be short-lived, bounded, and closed immediately; the adapter shall not rapidly poll a synchronous request socket.

### 6.3 Omarchy hosted profile

`HostedOmarchyProfile` is a policy and deployment layer over `HyprlandAdapter` and `DesktopHostPort`.

Omarchy 4.0.4 runs one long-lived `omarchy-shell` Quickshell process. Its bar, menu, notifications, OSD, lock, polkit, idle, and related services are host plugins. Astral Plasma shall therefore integrate as an Omarchy plugin rather than starting a second shell root.

The hosted profile shall provide:

- Versioned plugin metadata and compatibility data.
- QML `Item` entry points for supported plugin kinds.
- A service entry point for shared Astral state and actions.
- An optional bar or bar-widget entry point that delegates host-owned services.
- A panel/menu/overlay entry point only where the host contract supports it.
- Reversible plugin registration and removal.
- Optional palette/appearance bridging.
- A keybind integration that uses the user's Hyprland Lua configuration and does not claim unrelated compositor bindings.
- Delegation of notifications, lock, polkit, idle, OSD, and menu ownership to `omarchy-shell` in hosted mode.

A supported plugin package shall use a manifest with `schemaVersion: 1`, a namespaced Astral plugin ID, relative entry-point paths, and no symlinks inside the plugin directory. Plugin entry points are QML `Item`s, not the existing root `shell.qml` `ShellRoot`.

Conceptual manifest shape, to be validated against the targeted Omarchy release:

```json
{
  "schemaVersion": 1,
  "id": "org.astralplasma.omarchy",
  "name": "Astral Plasma for Omarchy",
  "version": "1.0.0",
  "kinds": ["service", "bar"],
  "entryPoints": {
    "service": "Service.qml",
    "bar": "Bar.qml"
  },
  "keepLoaded": true
}
```

The profile shall not modify Omarchy package files, start a second Quickshell host, or terminate host services. A complete independent replacement for `omarchy-shell` is outside the supported no-fork scope; it would require an upstream host API or a fork.

### 6.4 Standalone Hyprland profile

`StandaloneHyprlandProfile` is supported for ordinary Hyprland sessions that do not run `omarchy-shell`. It may own the complete shell lifecycle, notifications, lock, polkit, idle, and related services only when the user explicitly selects standalone mode and accepts responsibility for those resources.

Running Astral Plasma as a standalone process against Omarchy is experimental. It is not the definition of Omarchy support and shall not be enabled automatically.

---

## 7. Runtime profile and lifecycle

### Profile selection

Selection precedence shall be:

1. Explicit command-line override.
2. Explicit user configuration.
3. Runtime compositor/environment detection.
4. Safe portable fallback.

Detection shall verify availability, not only an environment variable. A failed handshake produces a visible degraded state rather than a false backend selection.

Proposed command-line concepts:

```text
--compositor kwin|hyprland
--environment kde|hyprland|omarchy
--integration hosted|standalone-experimental
```

Exact CLI spelling may be aligned with existing command conventions during Phase 0, but the three concepts shall remain independently configurable. A hosted Omarchy integration is selected when `omarchy-shell` responds to its documented health/IPC command and the Astral plugin is installed. A standalone integration is selected only through an explicit override or a confirmed non-Omarchy Hyprland session.

### Startup sequence

1. Load shared configuration and explicit overrides.
2. Detect or select the environment profile.
3. For Omarchy, detect `omarchy-shell` and validate plugin/host availability before constructing a second host.
4. Validate required modules, sockets, services, and capabilities.
5. Construct the selected backend and profile.
6. In hosted mode, load the Astral plugin entry points into the existing host.
7. In standalone mode, load a complete initial snapshot and start Astral as the host.
8. Start the event source.
9. Reconcile the snapshot with the first event batch.
10. Apply only opt-in resource ownership changes.
11. Expose `connected` or `degraded` state to the UI.
12. Start or restore shell surfaces.

### Shutdown sequence

1. Stop accepting new mutating intents.
2. Stop event sources and timers.
3. Close shell surfaces.
4. In hosted mode, release Astral plugin resources without stopping `omarchy-shell`.
5. In standalone mode, restore only resources recorded as owned by the active profile.
6. Restore shortcut/config state.
7. Persist shared user configuration.
8. Release the session.

Plasma takeover shall be performed only by the KDE profile. In hosted Omarchy mode, `omarchy-shell` remains the owner of notifications, lock, polkit, idle, OSD, and menu services. The current unconditional Plasma lifecycle calls in `shell.qml`, `run.sh`, and CLI entry points shall move behind the lifecycle coordinator.

### Reconnection

When an event source disconnects:

- Set connection state to `disconnected` or `degraded`.
- Mark the retained snapshot as stale.
- Disable mutating actions that cannot be safely retried.
- Preserve read-only presentation with an explicit stale indicator.
- Retry with bounded backoff.
- Reload a complete snapshot after reconnection and reconcile events.

---

## 8. Hyprland and Wayland behavior

### Layer-shell

`PanelWindow` and `zwlr_layer_shell_v1` remain the portable surface technology. The shell shall keep stable layer-shell namespaces for translucent surfaces.

KWin-specific tiling offsets or 1px shims shall not be copied to Hyprland. Each profile owns its reserved-space and focus policy.

### Focus

- Modal surfaces may request exclusive keyboard focus.
- Non-modal popouts should use ordinary input regions and Hyprland focus grabbing where supported.
- Closing an overview or popout shall request semantic focus restoration through `FocusPort`.
- Focus restoration shall be capability-gated and shall not invoke a KWin script on Hyprland.

### Blur and materials

The existing glass geometry and material tokens remain shared. The compositor effect is capability-driven:

- Use region blur when the active Hyprland/Quickshell build provides it.
- Use a documented layer-rule or translucency fallback otherwise.
- Keep KWin blur-strength configuration inside the KWin adapter.
- Never display a fake blur state when the effect is unavailable.

The first tested Hyprland baseline is Quickshell 0.3.1+ and Hyprland 0.56.0+ for the region-blur path. The first hosted Omarchy compatibility target is the versioned Omarchy 4.0.4/Quattro contract with Hyprland 0.56.2 and Quickshell 0.3.1. Older Hyprland versions receive explicit reduced-effect behavior; older Omarchy generations require a separate legacy profile.

### Screen capture

Internal previews use direct compositor capture through the preview port. A denied or unsupported capture returns a typed result and the UI displays its existing fallback treatment. User-driven screen sharing is a separate portal workflow and is not required for the first Hyprland milestone.

### Input

The shell shall not require synthetic global input injection. Normal QML input, compositor-native global shortcuts, and focus grabbing are the supported paths.

---

## 9. Omarchy support profile

### Hosted plugin mode (supported)

Omarchy 4.0.4 runs one long-lived `omarchy-shell` Quickshell host. Astral Plasma shall integrate as a plugin inside that host and shall not start a second Quickshell configuration.

The supported plugin integration shall provide:

- A versioned `manifest.json` with `schemaVersion: 1`, a namespaced Astral plugin ID, and relative QML entry points.
- A service entry point for shared Astral state and semantic actions.
- A complete bar or bar-widget entry point, selected deliberately according to the desired visual ownership.
- Optional panel, menu, or overlay entry points only where the host contract supports them.
- Reversible installation under `~/.config/omarchy/plugins/<astral-plugin-id>/`.
- No symlinks inside the plugin directory.
- Host-theme and host-state integration through documented Omarchy APIs.

A plugin entry point is a QML `Item`; it is not the current root `shell.qml` `ShellRoot`. The plugin may create per-monitor `PanelWindow`s through the host's supported variants, but it shall not assume that it owns the host scene graph or all built-in service registries.

### Host-owned services

In hosted mode, the following remain owned by `omarchy-shell` unless an upstream host contract explicitly delegates them:

- notifications
- lock screen
- polkit agent
- idle/screensaver behavior
- OSD
- application menu
- background/wallpaper ownership
- shell restart and update supervision

Astral may add actions to the existing menu through the supported menu-extension mechanism. It shall not start a second notification server, lock agent, polkit agent, or background process.

### Bar and panel ownership

Omarchy permits one active full bar. Astral shall support both integration levels:

1. **Bar-widget mode:** Astral contributes widgets while the existing Omarchy bar remains active. This is the lowest-risk integration.
2. **Complete bar mode:** Astral supplies the full bar plugin and provides the service capabilities it needs. This is higher visual fidelity and requires testing every affected widget.

A panel or overlay shall remain a separate plugin entry point and shall not silently replace the host menu or lock surface.

### Theme integration

Astral Plasma’s palette and motion system remain the default for standalone mode. In hosted mode, the plugin may consume Omarchy’s injected `Color`/`Style` values and theme IPC. An independent Astral process may observe the active theme state and hook data, but it shall not write Plasma/KWin theme files or package-owned Omarchy files.

The supported user integration points are under the user's Omarchy configuration and state directories, including plugin, theme, hook, menu-extension, and background configuration locations documented by the targeted Omarchy release. Package-owned files under `/usr/share/omarchy` are read-only.

### Keybindings

Hyprland/Omarchy keybindings use the user's Lua configuration under `~/.config/hypr/`, with the current bind helpers such as `o.rebind`/`hl.bind`. Astral shall:

- provide semantic action names;
- rebind only keys explicitly owned by Astral;
- use non-blocking external command dispatch;
- avoid KWin `registerShortcut`, KDE Global Accel, and KDE desktop metadata as the primary mechanism;
- report conflicts with existing Omarchy defaults;
- restore only bindings that Astral created.

### Standalone experimental mode

A standalone Astral process is supported for ordinary Hyprland sessions. Running it while Omarchy is active is experimental and requires the user to explicitly disable or bypass `omarchy-shell` and accept ownership of notifications, lock, polkit, idle, OSD, background, and lifecycle. The application shall detect an active Omarchy host and refuse to enter this mode automatically.

### Installation and removal

The repository owns a distributable plugin package and documentation. It does not fork Omarchy or replace package-owned files. Installation and removal shall be reversible, and removal shall restore the previous bar selection, bindings, plugin state, and any resource recorded by the ownership manifest.

---

## 10. Configuration model

Shared configuration remains in `config/settings.json` and the user settings file. Backend-specific values are grouped under a profile section rather than spread through existing UI settings.

Conceptual shape:

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
  }
}
```

Rules:

- Shared shell behavior uses shared settings.
- Backend-specific settings live under the relevant profile.
- A profile may override a shared default only when the setting is explicitly marked as overridable.
- Unknown or unsupported settings produce a diagnostic, not a silent fallback.
- The shipped Plasma defaults remain valid for KDE sessions.
- Hosted Omarchy integration is installed as a plugin under the user's Omarchy plugin directory and does not replace the global Quickshell configuration symlink.
- Standalone experimental integration uses a named Quickshell configuration or explicit path and is never enabled automatically while `omarchy-shell` is active.

---

## 11. Migration plan and file map

### Phase 0 — Contracts and tests

- Extend `daemon/src/domain/ports.rs` with the common ports.
- Extend `daemon/src/domain/model.rs` with versioned session, capability, intent, result, and event contracts.
- Add domain tests for workspace/output/focus semantics and capability gating.
- Add adapter contract fixtures shared by KWin and Hyprland.
- Add QML tests for the common facade and unsupported-control states.
- Add this specification and the glossary to the repository documentation.

### Phase 1 — KWin extraction

- Refactor `daemon/src/infrastructure/kwin_adapter.rs` behind the common ports.
- Split `daemon/src/application/watch_events.rs` into a generic event coordinator and a KWin event source.
- Introduce a session/backend factory.
- Centralize Plasma lifecycle ownership.
- Preserve existing CLI/API payloads and KWin tests.

### Phase 2 — Common QML facade

- Add a canonical `DesktopSessionFacade` service.
- Refactor `services/WindowService.qml` and `services/KWinWorkspaces.qml` to consume it.
- Keep compatibility wrappers during migration.
- Add connection, stale-state, capability, and profile properties.
- Update shared labels and controls to consume profile data.

### Phase 3 — Hyprland adapter

- Add the native Hyprland observation/event adapter.
- Add workspace/output/window mappings and semantic actions.
- Add focus grabbing, global shortcut integration, and preview support.
- Add capability-aware blur and focus behavior.
- Expose the same adapter through both standalone Hyprland and hosted Omarchy integration without duplicating the visual tree.
- Add a real Hyprland smoke test.

### Phase 4 — Omarchy hosted integration and system services

- Add `HostedOmarchyProfile`, plugin manifest, service entry point, and supported bar/panel entry points.
- Package the plugin under the user's Omarchy plugin directory without symlinks or package-file edits.
- Keep `omarchy-shell` as the host and delegate notifications, lock, polkit, idle, OSD, menu, background, and restart ownership to it.
- Add bar-widget and complete-bar integration modes with explicit conflict behavior.
- Add user Hyprland Lua binding integration, theme/host-state bridging, and reversible plugin removal.
- Add an explicitly experimental standalone Hyprland profile with a hard guard against running beside `omarchy-shell`.
- Replace KDE-only service calls with provider ports and Hyprland/Omarchy implementations where required for full support.
- Make X11/XTest linkage optional or isolate it to the XWayland compatibility path.

### Phase 5 — Cleanup and documentation

- Remove direct backend conditionals from shared QML.
- Retire compatibility wrappers after migration gates pass.
- Update `README.md`, `DESIGN.md`, `docs/LESSONS.md`, and `walkthrough.md`.
- Remove stale KDE-only runtime assumptions from doctor output and installers.

---

## 12. Testing and acceptance

### Automated tests

The project must retain the existing regression suite and add:

- Rust unit tests for canonical models, invariants, event translation, and typed results.
- Contract tests for every desktop-integration port.
- KWin adapter contract tests.
- Hyprland adapter contract tests using deterministic fixtures/fakes.
- QML tests for facade projections, capability gating, stale state, and profile selection.
- QML tests proving shared components do not require compositor-specific object types.
- Installer/uninstaller tests for ownership restoration.

Run the mandatory suite with:

```bash
make test
```

### Real-session smoke tests

A real Hyprland session shall verify:

- backend detection and health
- initial snapshot and event updates
- multi-monitor workspace state
- active-window updates
- activate/close/minimize actions
- dashboard/launcher/overview actions
- global shortcut delivery
- focus restoration and popout dismissal
- previews and fallback thumbnail
- region blur and reduced-effect fallback
- disconnect/reconnect behavior

An Omarchy hosted profile shall additionally verify:

- `omarchy-shell shell ping` and plugin discovery
- plugin manifest validation and QML loading
- no second Quickshell host/configuration is started
- bar-widget and complete-bar modes
- coexistence with the existing Omarchy bar
- delegated notifications, lock, polkit, idle, OSD, menu, and background ownership
- theme and palette updates through the host
- keybind conflict reporting and reversible bindings
- install, upgrade, restart, exit, and plugin removal

A standalone Hyprland profile shall separately verify explicit opt-in, complete lifecycle ownership, and the hard guard against running beside `omarchy-shell`.

### Visual verification

UI changes require screenshots under realistic wallpaper and window content. Capture and inspect every affected view, including:

- launcher
- dashboard
- active-apps overview
- dock popout
- settings
- notifications
- Hyprland and Plasma fallback states

Use the repository’s visual-proof workflow and the motion tokens in `DESIGN.md`.

---

## 13. Compatibility references

The production compatibility target is the versioned Omarchy release rather than the moving `quattro` branch. The initial research baseline is:

- Omarchy 4.0.4 / Quattro
- Hyprland 0.56.2
- Quickshell 0.3.1

Primary references:

- [Omarchy v4.0.4 shell README](https://github.com/omacom/omarchy/blob/v4.0.4/shell/README.md)
- [Omarchy shell reference](https://github.com/omacom/omarchy/blob/v4.0.4/docs/omarchy-shell.md)
- [Omarchy shell-plugin manual](https://omarchy.org/manual/shell-plugins/)
- [Omarchy v4.0.4 Hyprland entrypoint](https://github.com/omacom/omarchy/blob/v4.0.4/config/hypr/hyprland.lua)
- [Omarchy v4.0.4 shell launcher](https://github.com/omacom/omarchy/blob/v4.0.4/bin/omarchy-launch-shell)
- [Omarchy theming reference](https://github.com/omacom/omarchy/blob/v4.0.4/docs/theming.md)
- [Quickshell Hyprland API](https://quickshell.org/docs/v0.3.1/types/Quickshell.Hyprland/Hyprland/)
- [Quickshell distribution guide](https://quickshell.org/docs/v0.3.1/guide/distribution)
- [Hyprland IPC](https://wiki.hypr.land/ipc/)
- [Hyprland Lua configuration](https://wiki.hypr.land/configuring/core/)

---

## 14. Definition of done

The feature is complete only when:

- [ ] Plasma/KWin remains supported and its tests pass.
- [ ] Hyprland launches the shared shell without backend-specific QML rewrites.
- [ ] Canonical windows, outputs, workspaces, surfaces, capabilities, intents, results, and events are implemented.
- [ ] KWin and Hyprland implement the same port contracts.
- [ ] No raw KWin or Hyprland protocol objects leak into shared QML.
- [ ] Unsupported actions are visibly capability-gated and return typed results.
- [ ] Plasma lifecycle takeover is profile-scoped and reversible.
- [ ] Hyprland lifecycle takeover is profile-scoped and reversible.
- [ ] Omarchy hosted plugin mode works inside `omarchy-shell` without a second host.
- [ ] Omarchy bar-widget and complete-bar modes have documented ownership behavior.
- [ ] Standalone Hyprland mode is explicit, tested, and refuses to run beside `omarchy-shell`.
- [ ] `make test` passes with zero failures.
- [ ] Real Hyprland, hosted Omarchy, and standalone-profile smoke tests pass.
- [ ] Visual proof is captured and inspected.
- [ ] Documentation reflects the new supported environments and limitations.
