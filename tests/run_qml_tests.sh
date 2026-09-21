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
QML_FILES=$(find "$DIR" -maxdepth 1 -name "tst_*.qml" | sort)
COUNT=$(echo "$QML_FILES" | wc -l)

echo "=== Running $COUNT Astral Plasma QML Test Suite(s) ==="
ALL_PASSED=1

for test_file in $QML_FILES; do
    test_name=$(basename "$test_file")
    echo -n "[TEST] $test_name ... "
    if OUTPUT=$(timeout 20 qml6 -platform offscreen "$test_file" 2>&1); then
        if echo "$OUTPUT" | grep -q "PASS:"; then
            echo "✓ PASSED"
        else
            echo "✗ FAILED (No PASS output)"
            echo "$OUTPUT"
            ALL_PASSED=0
        fi
    else
        echo "✗ FAILED (Exit $?)"
        echo "$OUTPUT"
        ALL_PASSED=0
    fi
done

echo "============================================="
if [ $ALL_PASSED -eq 1 ]; then
    echo "ALL QML TESTS PASSED! No regressions detected."
    exit 0
else
    echo "SOME QML TESTS FAILED! Please fix failures."
    exit 1
fi
