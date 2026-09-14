#!/usr/bin/env python3
import sys
import os
import unittest
import subprocess
import json

BIN_PATH = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "bin", "caelestia-daemon"))

class TestCaelestiaDaemon(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not os.path.exists(BIN_PATH):
            subprocess.run(["make", "build"], check=True, cwd=os.path.join(os.path.dirname(__file__), ".."))

    def test_daemon_metrics_output(self):
        res = subprocess.run([BIN_PATH, "metrics"], capture_output=True, text=True)
        self.assertEqual(res.returncode, 0)
        data = json.loads(res.stdout.strip())
        self.assertIn("uptime", data)
        self.assertIn("ram", data)
        self.assertTrue(data["uptime"].startswith("up "))
        self.assertIsInstance(data["ram"], float)
        self.assertGreaterEqual(data["ram"], 0.0)
        self.assertLessEqual(data["ram"], 1.0)

    def test_daemon_workspaces_output(self):
        res = subprocess.run([BIN_PATH, "workspaces", "query"], capture_output=True, text=True)
        self.assertEqual(res.returncode, 0)
        data = json.loads(res.stdout.strip())
        self.assertIn("count", data)
        self.assertIn("current", data)
        self.assertIn("items", data)
        self.assertIsInstance(data["items"], list)

if __name__ == "__main__":
    unittest.main()
