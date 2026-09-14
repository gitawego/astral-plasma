#!/usr/bin/env python3
import sys
import os
import unittest

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "services")))
from window_watcher import get_window_meta

class TestWindowService(unittest.TestCase):
    def test_antigravity_recognition(self):
        name, icon, mat, app_id, df = get_window_meta("Antigravity IDE", "quickshell", "ai.opencode.desktop")
        self.assertEqual(name, "Antigravity")
        self.assertEqual(icon, "antigravity")
        self.assertEqual(mat, "smart_toy")

    def test_cloudmusic_recognition(self):
        name, icon, mat, app_id, df = get_window_meta("Song - Artist", "cloudmusic.exe", "")
        self.assertEqual(name, "CloudMusic")
        self.assertEqual(icon, "netease-cloud-music")
        self.assertEqual(mat, "music_note")

    def test_terminal_recognition(self):
        name, icon, mat, app_id, df = get_window_meta("cachyos", "com.mitchellh.ghostty", "")
        self.assertEqual(name, "Terminal")
        self.assertEqual(icon, "com.mitchellh.ghostty")

    def test_vscode_recognition(self):
        name, icon, mat, app_id, df = get_window_meta("file.py - Code", "code", "code")
        self.assertEqual(name, "VS Code")
        self.assertEqual(icon, "vscode")

if __name__ == "__main__":
    unittest.main()
