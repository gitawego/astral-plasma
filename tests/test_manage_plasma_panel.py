#!/usr/bin/env python3
"""
TDD Unit Tests for scripts/manage_plasma_panel.sh
Verifies generic, agnostic, config-driven backup and restore lifecycle of KDE Plasma panel settings.
"""
import os
import sys
import shutil
import tempfile
import subprocess
import json

SCRIPT_PATH = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "scripts", "manage_plasma_panel.sh"))

def test_backup_and_restore():
    with tempfile.TemporaryDirectory() as tmpdir:
        mock_config = os.path.join(tmpdir, "config")
        mock_data = os.path.join(tmpdir, "data")
        mock_bin = os.path.join(tmpdir, "bin")
        os.makedirs(mock_config, exist_ok=True)
        os.makedirs(mock_data, exist_ok=True)
        os.makedirs(mock_bin, exist_ok=True)

        # Create mock systemctl and qdbus6 to avoid touching real system during test
        mock_systemctl = os.path.join(mock_bin, "systemctl")
        with open(mock_systemctl, "w") as f:
            f.write("#!/bin/sh\nexit 0\n")
        os.chmod(mock_systemctl, 0o755)

        mock_qdbus = os.path.join(mock_bin, "qdbus6")
        with open(mock_qdbus, "w") as f:
            f.write("#!/bin/sh\nexit 0\n")
        os.chmod(mock_qdbus, 0o755)

        # 1. Setup mock original Plasma config files (generic arbitrary theme and panels)
        appletsrc_path = os.path.join(mock_config, "plasma-org.kde.plasma.desktop-appletsrc")
        original_appletsrc_content = (
            "[Containments][10]\n"
            "plugin=org.kde.panel\n"
            "location=3\n"
            "activityId=theme-xyz-original\n"
            "[Containments][10][Applets][11]\n"
            "plugin=org.kde.plasma.kickoff\n"
            "[Containments][20]\n"
            "plugin=org.kde.panel\n"
            "location=4\n"
        )
        with open(appletsrc_path, "w") as f:
            f.write(original_appletsrc_content)

        plasmashellrc_path = os.path.join(mock_config, "plasmashellrc")
        original_plasmashellrc_content = (
            "[PlasmaViews][Panel 10]\n"
            "floating=0\n"
            "thickness=30\n"
        )
        with open(plasmashellrc_path, "w") as f:
            f.write(original_plasmashellrc_content)

        backup_dir = os.path.join(mock_data, "caelestia", "plasma-backup")

        env = os.environ.copy()
        env["XDG_CONFIG_HOME"] = mock_config
        env["XDG_DATA_HOME"] = mock_data
        env["CAELESTIA_PLASMA_BACKUP_DIR"] = backup_dir
        env["PATH"] = mock_bin + ":" + env.get("PATH", "")
        env["CAELESTIA_TEST_MODE"] = "1"

        # 2. Run backup / disable
        res = subprocess.run([SCRIPT_PATH, "disable", "all"], env=env, capture_output=True, text=True)
        assert res.returncode == 0, f"disable failed: {res.stderr}\n{res.stdout}"

        # Verify backup files were created in backupDir
        backed_appletsrc = os.path.join(backup_dir, "plasma-org.kde.plasma.desktop-appletsrc")
        backed_plasmashellrc = os.path.join(backup_dir, "plasmashellrc")
        assert os.path.exists(backed_appletsrc), "appletsrc backup missing in backupDir"
        assert os.path.exists(backed_plasmashellrc), "plasmashellrc backup missing in backupDir"

        with open(backed_appletsrc) as f:
            assert f.read() == original_appletsrc_content, "backed appletsrc content mismatch"
        with open(backed_plasmashellrc) as f:
            assert f.read() == original_plasmashellrc_content, "backed plasmashellrc content mismatch"

        # 3. Simulate second disable call while active (idempotence test)
        # Modify active config to empty / modified state
        with open(appletsrc_path, "w") as f:
            f.write("[Containments][999]\nmodified=true\n")

        res = subprocess.run([SCRIPT_PATH, "disable", "all"], env=env, capture_output=True, text=True)
        assert res.returncode == 0, f"repeated disable failed: {res.stderr}"

        # Pristine backup MUST NOT be overwritten by modified/empty active state!
        with open(backed_appletsrc) as f:
            assert f.read() == original_appletsrc_content, "Backup was overwritten by second disable call!"

        # 4. Run restore
        res = subprocess.run([SCRIPT_PATH, "restore"], env=env, capture_output=True, text=True)
        assert res.returncode == 0, f"restore failed: {res.stderr}\n{res.stdout}"

        # Verify active configs were faithfully restored to the pristine original state
        with open(appletsrc_path) as f:
            assert f.read() == original_appletsrc_content, "Restored appletsrc content does not match original!"
        with open(plasmashellrc_path) as f:
            assert f.read() == original_plasmashellrc_content, "Restored plasmashellrc content does not match original!"

        print("✓ Generic config-driven backup and restore verified successfully")

if __name__ == "__main__":
    test_backup_and_restore()
    print("PASS: test_manage_plasma_panel.py")
