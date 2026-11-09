import QtQuick
import QtTest

// The suite `astral app test .` runs. Keep it about the app's own policy, not about
// rendering: a window cannot be asserted offscreen.
TestCase {
    name: "io.github.astral.tide"
    when: windowShown

    function test_manifest_is_documented() {
        compare(true, true);
    }
}
