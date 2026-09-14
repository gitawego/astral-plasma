#!/usr/bin/env python3
import subprocess
import sys
import json

def main():
    try:
        proc = subprocess.Popen(
            ["dbus-monitor", "type='method_call',interface='org.freedesktop.Notifications',member='Notify'"],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            bufsize=1
        )
    except Exception as e:
        sys.stderr.write(f"Failed to start dbus-monitor: {e}\n")
        sys.exit(1)

    in_notify = False
    strings = []

    for line in proc.stdout:
        line = line.strip()
        if "member=Notify" in line:
            in_notify = True
            strings = []
            continue

        if in_notify:
            if line.startswith("string \""):
                val = line[8:-1]
                strings.append(val)
                # First 4 strings in Notify are:
                # 0: app_name
                # 1: app_icon
                # 2: summary
                # 3: body
                if len(strings) == 4:
                    payload = {
                        "app": strings[0],
                        "icon": strings[1] if strings[1] else "info",
                        "summary": strings[2],
                        "body": strings[3]
                    }
                    print(json.dumps(payload), flush=True)
                    in_notify = False
            elif line.startswith("method call") or line.startswith("signal"):
                in_notify = False

if __name__ == "__main__":
    main()
