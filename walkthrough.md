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

### 5.3. Focus-Aware Auto-Minimize & Always-on-Top Pin
- **Issue**: The floating chat window stayed on top covering other apps even when switching focus to external applications.
- **Root Cause**: Quickshell layer-shell surfaces (`WlrLayer.Overlay`) are rendered above normal XDG application windows by Wayland protocol.
- **Fix**:
  1. In [`services/WindowService.qml`](file:///mnt/data/workspace/astral-plasma/services/WindowService.qml), added `signal externalWindowActivated(string winId, string winTitle)` emitted whenever an external app gains focus.
  2. In [`config/Config.qml`](file:///mnt/data/workspace/astral-plasma/config/Config.qml), added `property bool assistantPinned: false` and `function toggleAssistantPinned()`.
  3. In [`assistant/components/AssistantHeader.qml`](file:///mnt/data/workspace/astral-plasma/assistant/components/AssistantHeader.qml), added an interactive **Pin / Always on Top** toggle button (`push_pin` icon).
  4. In [`assistant/AssistantWindow.qml`](file:///mnt/data/workspace/astral-plasma/assistant/AssistantWindow.qml), connected to `WindowService.externalWindowActivated`: when unpinned, focusing any external application smoothly auto-minimizes Astral Copilot to the dock capsule with its breathing dot indicator.

### Proof 3: Verified Lucide Bot Message Square Icon & Pin Toggle
Full screenshot showing the crisp vector `bot-message-square` icon in both the Dock capsule (left) and Copilot header badge (top left), along with the Pin button in the header action bar:

![Verified Lucide Bot Message Square & Pin Toggle](/home/hlu/.gemini/antigravity/brain/6243245e-1de1-4944-8e6d-a8a7cf6545aa/assistant_bot_chat_icon_and_pin_verified.png)

