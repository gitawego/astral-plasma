#!/usr/bin/env python3
"""
manage_plasma_notifications.py
Controls suppression and restoration of KDE Plasma native notification popups.
When inhibited, KDE Plasma suppresses its native popups while Caelestia displays its own.
When restored, native popups resume immediately.
"""

import os
import sys
import signal
import time
import dbus
from gi.repository import GLib

PID_FILE = "/tmp/caelestia_notif_inhibit.pid"

def get_notification_iface():
    bus = dbus.SessionBus()
    obj = bus.get_object('org.freedesktop.Notifications', '/org/freedesktop/Notifications')
    iface = dbus.Interface(obj, 'org.freedesktop.Notifications')
    props = dbus.Interface(obj, 'org.freedesktop.DBus.Properties')
    return iface, props

def do_inhibit():
    # If already running, clean up first
    if os.path.exists(PID_FILE):
        do_restore()
        time.sleep(0.2)

    try:
        iface, props = get_notification_iface()
        hints = dbus.Dictionary({}, signature='sv')
        cookie = iface.Inhibit('Caelestia', 'Caelestia theme active', hints)
        print(f"Inhibited KDE Plasma notifications (cookie: {cookie})", flush=True)
    except Exception as e:
        print(f"Failed to inhibit notifications: {e}", file=sys.stderr)
        sys.exit(1)

    try:
        with open(PID_FILE, "w") as f:
            f.write(str(os.getpid()))
    except Exception as e:
        print(f"Failed to write PID file: {e}", file=sys.stderr)

    loop = GLib.MainLoop()

    def handle_stop(sig, frame):
        try:
            iface.UnInhibit(cookie)
            print("Uninhibited KDE Plasma notifications", flush=True)
        except Exception:
            pass
        if os.path.exists(PID_FILE):
            try:
                os.remove(PID_FILE)
            except OSError:
                pass
        loop.quit()

    signal.signal(signal.SIGINT, handle_stop)
    signal.signal(signal.SIGTERM, handle_stop)

    try:
        loop.run()
    except (KeyboardInterrupt, SystemExit):
        pass

def do_restore():
    if not os.path.exists(PID_FILE):
        print("No active notification inhibitor found.")
        return

    try:
        with open(PID_FILE, "r") as f:
            pid = int(f.read().strip())
    except Exception:
        pid = 0

    if pid > 0:
        try:
            os.kill(pid, signal.SIGTERM)
            # Wait up to 1 second for termination
            for _ in range(10):
                time.sleep(0.1)
                try:
                    os.kill(pid, 0)
                except OSError:
                    break
            else:
                os.kill(pid, signal.SIGKILL)
            print(f"Stopped notification inhibitor (PID {pid})")
        except OSError:
            print(f"Process {pid} already dead.")

    if os.path.exists(PID_FILE):
        try:
            os.remove(PID_FILE)
        except OSError:
            pass

def do_status():
    try:
        iface, props = get_notification_iface()
        inhibited = bool(props.Get('org.freedesktop.Notifications', 'Inhibited'))
        print(f"KDE Plasma Notifications Inhibited: {inhibited}")
    except Exception as e:
        print(f"Error querying notification status: {e}", file=sys.stderr)

    if os.path.exists(PID_FILE):
        try:
            with open(PID_FILE, "r") as f:
                pid = f.read().strip()
            print(f"Inhibitor daemon PID: {pid}")
        except Exception:
            pass
    else:
        print("Inhibitor daemon is not running.")

def main():
    action = sys.argv[1] if len(sys.argv) > 1 else "inhibit"
    if action in ("inhibit", "disable"):
        do_inhibit()
    elif action in ("restore", "enable", "uninhibit"):
        do_restore()
    elif action == "status":
        do_status()
    else:
        print(f"Usage: {sys.argv[0]} [inhibit|restore|status]")
        sys.exit(1)

if __name__ == "__main__":
    main()
