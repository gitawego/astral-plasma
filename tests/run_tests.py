#!/usr/bin/env python3
import os
import sys
import glob
import subprocess

def main():
    test_dir = os.path.dirname(os.path.abspath(__file__))
    test_files = sorted(glob.glob(os.path.join(test_dir, "tst_*.qml")))

    if not test_files:
        print("No test files found in", test_dir)
        sys.exit(1)

    print(f"=== Running {len(test_files)} Caelestia KDE Test Suite(s) ===")
    all_passed = True

    for test_file in test_files:
        test_name = os.path.basename(test_file)
        print(f"\n[TEST] {test_name} ...", flush=True)
        try:
            res = subprocess.run(
                ["qml6", "-platform", "offscreen", test_file],
                capture_output=True,
                text=True,
                timeout=10
            )
            stdout = res.stdout.strip()
            stderr = res.stderr.strip()
            if res.returncode == 0 and "PASS:" in (stdout + stderr):
                print(f"  ✓ {test_name} PASSED")
            else:
                print(f"  ✗ {test_name} FAILED (exit {res.returncode})")
                if stdout:
                    print("  STDOUT:\n   ", "\n    ".join(stdout.splitlines()))
                if stderr:
                    print("  STDERR:\n   ", "\n    ".join(stderr.splitlines()))
                all_passed = False
        except subprocess.TimeoutExpired:
            print(f"  ✗ {test_name} TIMED OUT")
            all_passed = False
        except Exception as e:
            print(f"  ✗ {test_name} ERROR: {e}")
            all_passed = False

    # Also run python test suites
    py_test_files = sorted(glob.glob(os.path.join(test_dir, "test_*.py")))
    for py_test in py_test_files:
        test_name = os.path.basename(py_test)
        print(f"\n[TEST] {test_name} ...", flush=True)
        res = subprocess.run([sys.executable, py_test], capture_output=True, text=True)
        if res.returncode == 0:
            print(f"  ✓ {test_name} PASSED")
        else:
            print(f"  ✗ {test_name} FAILED (exit {res.returncode})")
            if res.stdout: print("  STDOUT:\n   ", res.stdout)
            if res.stderr: print("  STDERR:\n   ", res.stderr)
            all_passed = False

    print("\n" + "="*45)
    if all_passed:
        print("ALL TESTS PASSED! No regressions detected.")
        sys.exit(0)
    else:
        print("SOME TESTS FAILED! Please fix failures.")
        sys.exit(1)

if __name__ == "__main__":
    main()
