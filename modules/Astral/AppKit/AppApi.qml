pragma Singleton

import QtQuick

// ============================================================================
// AppApi — the compatibility contract, from the app's side
// ============================================================================
// An app declares the level it was built against (`kernelApi`); this singleton is
// how it (and the SDK) reads the level the running shell implements, and what that
// level is called in release terms.
//
// This file is *generated* data in spirit: `daemon/tests/test_appkit_constants.rs`
// fails when `level`, `floor`, or `releases` disagree with
// `domain::app_compat::{APP_API_LEVEL, APP_API_FLOOR, API_LEVEL_HISTORY}`. That is
// the drift guard, not a comment.
QtObject {
    /// Highest API level this shell implements.
    readonly property int level: 1
    /// Oldest API level this shell still loads.
    readonly property int floor: 1

    /// Level -> the release that introduced it, so a message can name a version
    /// a person can act on instead of an integer.
    readonly property var releases: ({ 1: "0.2.0" })

    /// True when an app built against `appLevel` fits this shell.
    function supports(appLevel) {
        const level = Number(appLevel || 0);
        return level > 0 && level >= floor && level <= self.level;
    }

    /// The release that introduced `appLevel`, or "" when unknown.
    function releaseFor(appLevel) {
        const release = releases[Number(appLevel)];
        return release ? String(release) : "";
    }
}
