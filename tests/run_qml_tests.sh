#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QML_FILES=$(find "$DIR" -maxdepth 1 -name "tst_*.qml" | sort)
COUNT=$(echo "$QML_FILES" | wc -l)

echo "=== Running $COUNT Caelestia KDE QML Test Suite(s) ==="
ALL_PASSED=1

for test_file in $QML_FILES; do
    test_name=$(basename "$test_file")
    echo -n "[TEST] $test_name ... "
    if OUTPUT=$(timeout 10 qml6 -platform offscreen "$test_file" 2>&1); then
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
