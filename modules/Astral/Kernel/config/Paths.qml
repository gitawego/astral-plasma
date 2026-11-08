pragma Singleton

import QtQuick
import Quickshell

// ============================================================================
// Paths — where the installed (or checked-out) tree lives
// ============================================================================
// One authority for runtime paths. Services used to derive the daemon as
// `<their own directory>/../bin/astral-plasma`, which was correct while `services/`
// sat at the repository root - and silently wrong the moment the kernel moved into
// `modules/Astral/Kernel/` (spec C.12): every daemon call then targeted a directory
// that does not exist, and the shell lost windows, tray, previews and clipboard
// with no error to show for it.
//
// So the layout is resolved here, from this file's own position, and everything else
// asks. `ASTRAL_PLASMA_DAEMON` overrides it for tests and packaged installs.
QtObject {
    id: root

    /// `<root>/bin/astral-plasma` — the daemon entry point.
    ///
    ///
    /// Resolution order: explicit override, then the tree this file belongs to
    /// (`modules/Astral/Kernel/config` -> root is four levels up), then `<data dir>`
    /// for an installed package whose layout differs.
    readonly property string daemonBin: {
        const override = Quickshell.env("ASTRAL_PLASMA_DAEMON");
        if (override && override.length > 0) {
            return override;
        }
        const root = Qt.resolvedUrl("../../../..").toString();
        const base = root.startsWith("file://") ? root.substring(7) : root;
        return (base.endsWith("/") ? base.slice(0, -1) : base) + "/bin/astral-plasma";
    }

    /// The tree root this shell is running from (checkout or extracted package).
    readonly property string root: {
        const url = Qt.resolvedUrl("../../../..").toString();
        const path = url.startsWith("file://") ? url.substring(7) : url;
        return path.endsWith("/") ? path.slice(0, -1) : path;
    }

    /// `scripts/` beside the binary, for the shell scripts the UI invokes.
    readonly property string scriptsDir: root + "/scripts"
}
