---
name: process-optimizer
description: Inspect system resource consumption, identify CPU/memory hog processes, locate zombie/defunct tasks, and recommend safe process termination or priority adjustments.
---

# Process Optimizer Skill

Use this skill when the system feels sluggish, fans spin at maximum speed, battery drains abnormally fast, or when the user asks to "check high CPU", "free memory", or "find runaway processes".

## Diagnostic Runbook

### Step 1: Identify Top Resource Consumers
Scan top processes by CPU and memory without interactive curses:
```bash
ps -eo pid,ppid,user,%cpu,%mem,stat,comm --sort=-%cpu | head -n 15
```
Top memory consumers specifically:
```bash
ps -eo pid,ppid,user,%cpu,%mem,rss,comm --sort=-%mem | head -n 15
```

### Step 2: Check for Zombie or Defunct Tasks
Locate processes in zombie `Z` or uninterruptible sleep `D` states:
```bash
ps -eo pid,ppid,user,stat,comm | grep -E "^[[:space:]]*[0-9]+[[:space:]]+[0-9]+[[:space:]]+[^[:space:]]+[[:space:]]+[ZD]"
```

### Step 3: Assess GPU and I/O Bottlenecks
If GPU tools are available, query utilization:
```bash
nvidia-smi --query-gpu=utilization.gpu,utilization.memory,temperature.gpu,power.draw --format=csv,noheader 2>/dev/null || true
```

### Step 4: Propose Remediations
1. **Never Kill Blindly**: Never suggest killing desktop session components (`kwin_wayland`, `Hyprland`, `systemd`, `dbus-daemon`, `quickshell`) without warning the user that it will terminate the session.
2. **Graceful Before Force**: Always recommend `kill -15 <pid>` (SIGTERM) before `kill -9` (SIGKILL).
3. **Safety Approval**: Any `kill` or `renice` action must be presented as a confirmation card for user approval.
