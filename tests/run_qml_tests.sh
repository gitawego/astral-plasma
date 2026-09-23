#!/usr/bin/env bash
set -e

# Qt suppresses console.log when stderr is not a TTY (messages are routed to the
# systemd journal instead). This harness captures output via command substitution,
# so without this every suite reports "No PASS output" despite actually passing.
export QT_ASSUME_STDERR_HAS_CONSOLE=1

# Allows suites to read source files via XMLHttpRequest so they can assert on
# token values in the QML/JS source of truth (e.g. the glass alpha table).
export QML_XHR_ALLOW_FILE_READ=1

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

python3 - "$DIR" << 'EOF'
import os, sys, subprocess, concurrent.futures

dir_path = sys.argv[1]
qml_files = sorted([os.path.join(dir_path, f) for f in os.listdir(dir_path) if f.startswith("tst_") and f.endswith(".qml")])
count = len(qml_files)
print(f"=== Running {count} Astral Plasma QML Test Suite(s) ===")

env = os.environ.copy()
env["QT_ASSUME_STDERR_HAS_CONSOLE"] = "1"
env["QML_XHR_ALLOW_FILE_READ"] = "1"

def run_test(path):
    name = os.path.basename(path)
    try:
        res = subprocess.run(["qml6", "-platform", "offscreen", path], capture_output=True, text=True, env=env, timeout=20)
        output = (res.stdout or "") + (res.stderr or "")
        passed = (res.returncode == 0) and ("PASS:" in output)
        return name, passed, output, res.returncode
    except subprocess.TimeoutExpired:
        return name, False, "Timed out after 20s", -1
    except Exception as e:
        return name, False, str(e), -1

max_workers = min(12, max(4, os.cpu_count() or 4))
all_passed = True

with concurrent.futures.ThreadPoolExecutor(max_workers=max_workers) as executor:
    for name, passed, output, code in executor.map(run_test, qml_files):
        if passed:
            print(f"[TEST] {name} ... ✓ PASSED")
        else:
            print(f"[TEST] {name} ... ✗ FAILED (Exit {code})")
            print(output)
            all_passed = False

print("=============================================")
if all_passed:
    print("ALL QML TESTS PASSED! No regressions detected.")
    sys.exit(0)
else:
    print("SOME QML TESTS FAILED! Please fix failures.")
    sys.exit(1)
EOF

