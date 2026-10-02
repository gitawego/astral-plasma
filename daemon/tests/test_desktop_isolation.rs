//! The Rust suite must not reach the live desktop.
//!
//! Port-level tests write real INI files (`kwinrc`, `kglobalshortcutsrc`) and the
//! X11 helpers open `$DISPLAY`. A suite that inherits the developer's session
//! therefore edits the *running* desktop: the reported symptom was a live
//! `~/.config/kwinrc` carrying `[Xwayland] XwaylandEisNoPromptApps=<test binary>`,
//! written by KWin because a test binary had connected to the session's Xwayland.
//!
//! `make test-rust` runs cargo inside a throwaway desktop (isolated `XDG_*_HOME`,
//! no `DISPLAY`/`WAYLAND_DISPLAY`) and sets `ASTRAL_PLASMA_REQUIRE_ISOLATION=1`,
//! which turns this suite into the proof that the isolation is actually in force.
//! Running `cargo test` by hand skips the proof rather than pretending to run it.

use astral_plasma::domain::branding;

/// Set by the test runner once the environment has been isolated.
const REQUIRE_ISOLATION: &str = "ASTRAL_PLASMA_REQUIRE_ISOLATION";

/// The runner's isolation promise, checked from the inside.
#[test]
fn the_suite_runs_against_a_throwaway_desktop() {
    if std::env::var(REQUIRE_ISOLATION).as_deref() != Ok("1") {
        return;
    }

    let home = branding::home_dir();
    for (var, path) in [
        ("XDG_CONFIG_HOME", branding::config_home()),
        ("XDG_DATA_HOME", branding::data_home()),
        ("XDG_CACHE_HOME", branding::cache_home()),
        ("XDG_STATE_HOME", branding::state_home()),
    ] {
        assert!(
            std::env::var_os(var).is_some(),
            "{var} must be set for the test run, or a port test writes into the live desktop"
        );
        assert!(
            !path.starts_with(&home),
            "{var}={} points into the user's home ({}): the suite would edit the live desktop",
            path.display(),
            home.display()
        );
    }

    // Opening `$DISPLAY` from a test registers the test binary with the session's
    // Xwayland, which KWin records in the user's `XwaylandEisNoPromptApps` list.
    for var in ["DISPLAY", "WAYLAND_DISPLAY"] {
        assert!(
            std::env::var_os(var).is_none(),
            "{var} must be unset for the test run: a test must never talk to the live compositor"
        );
    }
}
