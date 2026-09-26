---
name: audio-display-troubleshooter
description: Troubleshoot PipeWire/WirePlumber audio glitches, missing microphones/headphones, and Wayland compositor display/screen issues without restarting the user session.
---

# Audio & Display Troubleshooter Skill

Use this skill when sound stops working, audio stutters or crackles, Bluetooth headphones fail to route audio, screens flicker, or when the user reports "no sound" or "display issues".

## Diagnostic Runbook

### Step 1: Check PipeWire and WirePlumber Status
Check user-level audio daemons:
```bash
systemctl --user status pipewire pipewire-pulse wireplumber --no-pager
```

### Step 2: Query Audio Sinks and Routing
List active sinks, sources, and default routing targets:
```bash
wpctl status
```
Check if the default sink is muted or set to an unexpected device:
```bash
wpctl get-volume @DEFAULT_AUDIO_SINK@
```

### Step 3: Test and Recover Audio Daemon
If audio daemon is deadlocked or unresponsive:
```bash
systemctl --user restart pipewire wireplumber pipewire-pulse
```
Verify audio node recovery:
```bash
pw-cli info all 2>/dev/null | grep -E "id [0-9]+, type PipeWire:Interface:Node" | wc -l
```

### Step 4: Wayland Display & Compositor Health
Check for Wayland compositor errors or display mode renegotiation issues:
```bash
journalctl --user -u plasma-kwin_wayland -n 30 --no-pager 2>/dev/null || journalctl --user -n 30 --no-pager | grep -iE "hyprland|kwin|wayland"
```

### Step 5: Safe Display Cache / Quickshell Reload
If shell panels glitch or render artifacts occur, reload Quickshell cleanly:
```bash
systemctl --user restart quickshell 2>/dev/null || killall -USR1 quickshell 2>/dev/null || true
```
