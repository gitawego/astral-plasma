#!/usr/bin/env python3
import sys
import subprocess
import os

if len(sys.argv) < 2:
    sys.exit(0)

target = sys.argv[1].strip()

# 1. Lutris games/apps
if target.startswith("lutris:") or target in ["cloudmusic", "netease-cloud-music"]:
    game_id = target.replace("lutris:rungame/", "").replace("lutris:", "")
    if game_id in ["cloudmusic", "netease-cloud-music"]:
        game_id = "netease-cloud-music"
    subprocess.Popen(["lutris", f"lutris:rungame/{game_id}"], start_new_session=True)
    sys.exit(0)

# 2. Flatpak apps
if target.startswith("be.alexandervanhee.gradia") or target == "gradia":
    subprocess.Popen(["flatpak", "run", "be.alexandervanhee.gradia"], start_new_session=True)
    sys.exit(0)

# 3. Antigravity special handling if needed
if target in ["antigravity", "ai.opencode.desktop"]:
    for cand in ["ai.opencode.desktop", "opencode-desktop", "antigravity"]:
        try:
            ret = subprocess.run(["gtk-launch", cand], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            if ret.returncode == 0:
                sys.exit(0)
        except Exception:
            pass

# 4. General gtk-launch
try:
    desktop = target
    if desktop.endswith(".desktop"):
        desktop = desktop[:-8]
    ret = subprocess.run(["gtk-launch", desktop], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if ret.returncode == 0:
        sys.exit(0)
except Exception:
    pass

# 5. Direct executable fallback
for cmd in [target, target.lower()]:
    try:
        subprocess.Popen([cmd], start_new_session=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        sys.exit(0)
    except Exception:
        pass
