---
name: astral-desktop-tools
description: Use Astral Plasma's native machine-readable CLI tools to inspect and control the desktop environment, applications, workspaces, system telemetry, and crashes. Use when an AI coding agent or assistant needs to query open windows, focus or close apps, switch virtual workspaces, inspect system health, trigger notifications, or diagnose application crashes.
---

# Astral Desktop Tools for AI Agents

Astral Plasma provides a native, high-performance CLI tool suite designed for AI coding agents (Antigravity, Agy, Claude Code, Cursor) and automation scripts.

The tools are invoked via the `astral-plasma` binary:
```bash
astral-plasma tool <tool_name> [arguments...]
```
All tools return clean, structured JSON.

## Tool Manifest

You can query the machine-readable manifest at any time:
```bash
astral-plasma tool manifest
```

## Available Tools

### 1. `windows`
List all open application windows across the desktop with their window IDs, titles, application names, and active states.
```bash
astral-plasma tool windows
```
**Output Example:**
```json
{
  "success": true,
  "windows": [
    {
      "id": "win_104",
      "title": "Alacritty",
      "appName": "Terminal",
      "isActive": true
    }
  ],
  "active_window": {
    "id": "win_104",
    "title": "Alacritty",
    "appName": "Terminal"
  }
}
```

### 2. `window_focus`
Focus/activate an application window by its window ID or app name.
```bash
astral-plasma tool window_focus <window_id_or_app_name>
```

### 3. `window_close`
Close a window gracefully by its window ID.
```bash
astral-plasma tool window_close <window_id>
```

### 4. `workspaces`
Query the virtual workspace count, current active workspace index, and names.
```bash
astral-plasma tool workspaces
```

### 5. `workspace_switch`
Switch active workspace to a given workspace number or index (1-based).
```bash
astral-plasma tool workspace_switch <index>
```

### 6. `metrics`
Get real-time system telemetry: CPU usage, RAM utilization, and uptime.
```bash
astral-plasma tool metrics
```

### 7. `notify`
Display a native desktop notification to the user.
```bash
astral-plasma tool notify "Build Finished" "Your test suite passed with 100% success."
```

### 8. `crash_recent`
List recent application and service crashes, segfaults, and aborts recorded by `systemd-coredump` and `journalctl`.
```bash
astral-plasma tool crash_recent [limit]
```

### 9. `crash_diagnose`
Fetch detailed stack trace and journal logs for a crashed application or PID to formulate a diagnostic prompt.
```bash
astral-plasma tool crash_diagnose <process_name_or_pid>
```
