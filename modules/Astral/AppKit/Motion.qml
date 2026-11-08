pragma Singleton

import QtQuick

// ============================================================================
// Motion — the public motion tokens
// ============================================================================
// An app animates with the shell's Material 3 Expressive physics, not with numbers
// it invented. These are design constants (DESIGN.md owns them), so a hosted app
// carries them rather than reading them: a sandbox mounts no kernel files.
//
// The constants are pinned to `modules/Astral/Kernel/theme/Theme.qml` by
// `daemon/tests/test_appkit.rs`, so the two cannot drift silently.
QtObject {
    readonly property int fastSpatial: 350
    readonly property int defaultSpatial: 500
    readonly property int slowSpatial: 650

    readonly property int fastEffects: 150
    readonly property int defaultEffects: 200
    readonly property int slowEffects: 300

    readonly property var expressiveDefaultSpatial: [0.38, 1.21, 0.22, 1.0, 1.0, 1.0]
    readonly property var expressiveDefaultEffects: [0.34, 0.80, 0.34, 1.0, 1.0, 1.0]
}
