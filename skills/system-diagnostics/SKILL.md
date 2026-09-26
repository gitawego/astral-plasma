---
name: system-diagnostics
description: Diagnose Linux system-wide failures, kernel panics, systemd service crashes, coredumps, and application aborts using journalctl, coredumpctl, and dmesg.
---

# System Diagnostics Skill

Use this skill when diagnosing system crashes, service failures, application segmentation faults (SIGSEGV), GPU lockups, or when the user asks to "check system errors" or "why did an app crash?".

## Diagnostic Runbook

### Step 1: Query Systemd Journal for Recent High-Severity Errors
Run read-only log inspection for errors across the current boot:
```bash
journalctl -p 3 -xb -n 60 --no-pager
```
Filter for specific service failures if a known app or daemon is suspected:
```bash
systemctl --failed --no-pager
```

### Step 2: Inspect Coredumps
If an application crashed unexpectedly or segfaulted, locate the most recent core dump:
```bash
coredumpctl list -n 5 --no-pager 2>/dev/null
```
If a dump is present, extract stack trace details:
```bash
coredumpctl info $(coredumpctl list -n 1 --no-legend | awk '{print $5}') --no-pager 2>/dev/null
```

### Step 3: Check Kernel Rings and Hardware Alerts
Inspect `dmesg` for OOM killer invocations, I/O errors, or GPU hang warnings:
```bash
dmesg --level=err,warn -T 2>/dev/null | tail -n 40
```

### Step 4: Synthesize Root Cause and Remediation
1. **Identify the Culprit**: Specify the binary name, PID, signal (e.g. SIGSEGV, SIGABRT, OOM), and module or shared library involved.
2. **Explain in Plain Language**: Translate cryptic kernel or stack traces into a concise explanation of what failed and why.
3. **Propose Safe Recovery**: Suggest the minimal state-altering command required to recover (e.g., `systemctl restart <unit>`, or reinstalling a broken dependency). Always present state-altering commands for user approval before execution.
