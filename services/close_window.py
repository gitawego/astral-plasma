#!/usr/bin/env python3
import sys
import subprocess

if len(sys.argv) < 2:
    sys.exit(0)

win_id = sys.argv[1].strip()
target_uuid = win_id.replace("0_", "").replace("{", "").replace("}", "").strip()

script = """
var target = "TARGET_UUID";
var wins = workspace.windowList();
for (var i = 0; i < wins.length; i++) {
    var w = wins[i];
    var wid = ("" + w.internalId).replace("{", "").replace("}", "");
    if (wid === target) {
        w.closeWindow();
        break;
    }
}
""".replace("TARGET_UUID", target_uuid)

with open("/tmp/caelestia_close.js", "w") as f:
    f.write(script)

try:
    num = subprocess.check_output(
        ["qdbus6", "org.kde.KWin", "/Scripting", "org.kde.kwin.Scripting.loadScript", "/tmp/caelestia_close.js"],
        stderr=subprocess.DEVNULL
    ).decode().strip()
    subprocess.run(["qdbus6", "org.kde.KWin", f"/Scripting/Script{num}", "org.kde.kwin.Script.run"], stderr=subprocess.DEVNULL)
    subprocess.run(["qdbus6", "org.kde.KWin", f"/Scripting/Script{num}", "org.kde.kwin.Script.stop"], stderr=subprocess.DEVNULL)
except Exception:
    pass
