# Astral Plasma Domain Context

This file defines the ubiquitous language for Astral Plasma's desktop-session domain. It is a glossary, not an implementation plan. The compatibility design and migration requirements live in [`docs/HYPRLAND-OMARCHY-SPEC.md`](docs/HYPRLAND-OMARCHY-SPEC.md).

## Core domain: Desktop Session

### Desktop Session

The live desktop environment in which the shell is running. A session has an identity, a connection state, a focused output, a set of capabilities, and a current environment profile.

### Compositor Backend

The adapter that translates one compositor's concepts and operations into the desktop-session language. KWin and Hyprland are compositor backends.

### Environment Profile

A deployment and policy layer applied on top of a compositor backend. KDE/Plasma, plain Hyprland, and Omarchy are environment profiles; they refine lifecycle, service ownership, configuration, and presentation policy without replacing the compositor adapter.

### Desktop Host

The long-lived environment process that owns session-critical desktop services and hosts shell plugins. Omarchy's `omarchy-shell` is a desktop host; a standalone Astral Plasma process is its own host.

### Hosted Profile

An environment profile that runs inside an existing desktop host and delegates host-owned services to that host. Astral Plasma's supported Omarchy integration is hosted.

### Standalone Profile

An environment profile where Astral Plasma owns the shell host and its session services. Standalone operation is supported for ordinary Hyprland sessions; using it against Omarchy is experimental and requires explicit user opt-in.

### Session-Critical Service

A service whose ownership affects login, lock, security, notifications, idle behavior, power, or session lifecycle. Session-critical services have explicit resource ownership and are delegated to the active desktop host when one exists.

### Plugin Entry Point

A host-loaded QML `Item` that exposes a supported shell extension point. A plugin entry point is not a second shell root or a replacement desktop host.

### Service Port

A domain-facing contract for a system or host service. The service may be provided by KDE, a standalone Linux service, or an Omarchy desktop host without changing the caller's domain language.

### Output

A physical or virtual display known to the desktop session. An output has a stable identity, geometry, scale, refresh information, focus state, and capabilities.

### Workspace

A compositor-supported container for windows. Each output has an active workspace; the session identifies the focused output. A workspace is not a shell surface and is not an application window.

### Window

An external application window managed by the desktop session. A window has a stable identity for its lifetime, application metadata, an output/workspace association, and lifecycle state.

### Shell Surface

A surface owned by Astral Plasma, such as the dashboard, launcher, overview, drawer, or dock popout. A shell surface is not an application `Window` and has its own semantic lifecycle.

### Capability

A named, queryable ability exposed by the active session or environment. Capabilities describe what can be performed, not how a particular compositor performs it.

### User Intent

A request for a user-visible outcome, such as focusing a workspace, activating a window, or opening a shell surface. User intents are independent of compositor commands.

### Action Result

The typed outcome of a user intent, including whether it was applied, is pending, unsupported, denied, unavailable, invalid, or stale.

### Domain Event

An immutable fact about a desktop-session change, such as `WorkspaceActivated`, `WindowFocused`, `OutputChanged`, or `ShellSurfaceVisibilityChanged`.

### Stale Snapshot

The last known session projection retained after the compositor connection becomes unavailable. A stale snapshot is never presented as live state.

### Resource Ownership

The explicit declaration of which shell or environment component is responsible for a desktop resource, such as a panel, notification daemon, lock screen, global shortcut, wallpaper provider, or system service.

## Supporting language

### Adapter

A boundary implementation that translates an external system into the domain language. Adapters implement ports; the domain does not depend on their protocols.

### Anti-Corruption Layer

The boundary that prevents compositor-specific payloads, naming, and lifecycle assumptions from leaking into the desktop-session domain.

### Port

A technology-independent contract expressed in domain language. A port may be implemented by more than one adapter.

### Capability Set

The complete set of capabilities available to the current session. A missing capability is represented explicitly; it is not treated as a successful no-op.

### Semantic Action

A named user outcome that may have different implementations on different backends, such as `toggle-dashboard` or `restore-focus`.

## Context boundaries

- **Desktop Session** owns the language and rules for windows, outputs, workspaces, shell surfaces, capabilities, and session lifecycle.
- **Desktop Integration** translates KWin and Hyprland into that language.
- **Environment Profiles** apply deployment policy for KDE/Plasma, plain Hyprland, and hosted or standalone Omarchy integration.
- **Desktop Host** owns session-critical services and hosts plugin entry points when Astral runs inside another shell environment.
- **System Services** expose audio, network, power, notifications, tray, input, and related capabilities through their own ports.
- **Shell Presentation** renders the shared visual language and dispatches user intents; it does not interpret raw compositor protocols.

## Boundary rules

- `Window` means an external application window; `ShellSurface` means a surface owned by Astral Plasma.
- A workspace belongs to desktop-session semantics; compositor workspace rules are translated by an adapter.
- A backend-specific name is valid only inside its adapter or profile.
- A capability describes availability, not visual preference.
- A failed action returns a typed `ActionResult`; it never silently succeeds.
- An environment profile configures a backend; it is not a second backend.
- A hosted profile runs inside an existing desktop host and does not start a competing shell root.
- A standalone profile owns its host and therefore requires explicit lifecycle responsibility.
