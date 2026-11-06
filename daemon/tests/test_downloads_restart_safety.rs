//! Restart-safety contract for the download engine.
//!
//! aria2 is a detached daemon, so restarting the shell does not stop it. Two
//! things keep that true: the engine's own persistence flags (session + piece
//! map), and `make stop` not matching aria2c by its command line (its
//! `--input-file` path contains "astral-plasma", so a broad `pkill -f` used to
//! kill the engine too).

use astral_plasma::domain::downloads::EngineSettings;
use astral_plasma::infrastructure::aria2_adapter::aria2_args;
use std::path::{Path, PathBuf};

#[test]
fn engine_persists_session_and_piece_map_on_a_bounded_cadence() {
    let args = aria2_args(
        "secret",
        &PathBuf::from("/tmp/aria2.session"),
        &PathBuf::from("/tmp/aria2.log"),
        &PathBuf::new(),
        &EngineSettings::default(),
    );
    assert!(args.contains(&"--daemon=true".to_string()), "the engine must detach from the shell");
    assert!(args.contains(&"--continue=true".to_string()), "partial files must resume");
    assert!(args.contains(&"--save-session-interval=30".to_string()));
    assert!(args.contains(&"--auto-save-interval=30".to_string()),
        "the piece map must be flushed on a bounded cadence, not the 60s default");
}

#[test]
fn make_stop_never_matches_aria2c_by_command_line() {
    let makefile = std::fs::read_to_string(
        Path::new(env!("CARGO_MANIFEST_DIR")).join("../Makefile"),
    )
    .expect("Makefile must be readable");
    let stop = makefile
        .split("\nstop:")
        .nth(1)
        .and_then(|rest| rest.split("\n\n").next())
        .expect("Makefile must define a stop target");
    // The target's own comment explains the trap; only recipe lines count.
    let recipe: String = stop
        .lines()
        .filter(|line| !line.trim_start().starts_with('#'))
        .collect::<Vec<_>>()
        .join("\n");

    assert!(!recipe.contains("-f \"astral-plasma\""),
        "a broad pkill -f matches aria2c's --input-file path and kills downloads");
    assert!(recipe.contains("pkill -9 -x quickshell"),
        "stop must target the shell by exact process name");
    assert!(recipe.contains("pkill -9 -x astral-plasma"),
        "stop must target the daemon by exact process name, not the whole command line");
}
