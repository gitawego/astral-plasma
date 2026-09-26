---
name: package-cache-manager
description: Manage Arch Linux and Flatpak package caches, detect and clean orphaned packages, identify broken shared library linkages, and optimize disk usage.
---

# Package & Cache Manager Skill

Use this skill when disk space is low, package installations fail with dependency conflicts, or when the user asks to "clean package cache", "remove orphaned packages", or "check disk space".

## Diagnostic Runbook

### Step 1: Analyze Package Cache & Disk Usage
Inspect root and home partition free space:
```bash
df -h / /home
```
Check Pacman / AUR cache footprint:
```bash
du -sh /var/cache/pacman/pkg 2>/dev/null || true
du -sh ~/.cache/paru ~/.cache/yay 2>/dev/null || true
```

### Step 2: Locate Orphaned Dependencies
List unneeded packages installed as dependencies that are no longer required:
```bash
pacman -Qtdq 2>/dev/null || true
```

### Step 3: Check for Broken Shared Libraries
Detect binaries on the system with missing dynamic shared libraries:
```bash
find /usr/bin -type f -perm /111 -exec sh -c 'ldd "$1" 2>/dev/null | grep -q "not found" && echo "Broken library in: $1"' _ {} \; 2>/dev/null | head -n 10
```

### Step 4: Flatpak Cache & Unused Runtimes
Check for unused Flatpak runtimes:
```bash
flatpak list --runtime 2>/dev/null | head -n 15
```

### Step 5: Recommended Clean Actions
1. **Cleaning Pacman Cache safely**: Recommend `paccache -rk2` or `pacman -Sc` (requires confirmation).
2. **Removing Orphans**: Recommend `pacman -Rns $(pacman -Qtdq)` with explicit preview of packages to be removed.
3. **Flatpak Unused**: Recommend `flatpak uninstall --unused -y`.
4. Always request explicit confirmation before removing packages or clearing caches.
