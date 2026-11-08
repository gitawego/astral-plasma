//! Binary swap, rollback and the state journal the supervisor depends on.
//!
//! These are the operations where a mistake costs a bootable desktop, so they are
//! asserted on the filesystem rather than described.

use astral_plasma::application::restart::{
    consume_restart, has_previous, install_staged, restore_previous,
};
use astral_plasma::domain::update_state::{
    ClaimHandoff, RestartRequest, RollbackInfo, UpdateState, STATE_SCHEMA,
};
use std::fs;
use std::os::unix::fs::PermissionsExt;

#[test]
fn a_staged_binary_replaces_the_live_one_and_keeps_one_previous_copy() {
    let dir = tempfile::tempdir().unwrap();
    let live = dir.path().join("astral-plasma");
    let staged = dir.path().join("astral-plasma.next");
    fs::write(&live, b"old").unwrap();
    fs::write(&staged, b"new").unwrap();

    let previous = install_staged(&staged, &live).unwrap();

    assert_eq!(fs::read(&live).unwrap(), b"new");
    assert_eq!(fs::read(&previous).unwrap(), b"old");
    assert!(!staged.exists());
    assert_eq!(
        fs::metadata(&live).unwrap().permissions().mode() & 0o777,
        0o755,
        "the swapped binary must be executable"
    );
    assert!(has_previous(&live));
}

#[test]
fn an_empty_or_missing_staged_binary_is_refused_and_the_live_one_survives() {
    let dir = tempfile::tempdir().unwrap();
    let live = dir.path().join("astral-plasma");
    fs::write(&live, b"old").unwrap();

    let empty = dir.path().join("astral-plasma.next");
    fs::write(&empty, b"").unwrap();
    assert!(install_staged(&empty, &live).is_err());
    assert_eq!(fs::read(&live).unwrap(), b"old");

    assert!(install_staged(&dir.path().join("ghost"), &live).is_err());
    assert_eq!(fs::read(&live).unwrap(), b"old");
}

#[test]
fn rollback_puts_the_previous_binary_back() {
    let dir = tempfile::tempdir().unwrap();
    let live = dir.path().join("astral-plasma");
    let staged = dir.path().join("astral-plasma.next");
    fs::write(&live, b"old").unwrap();
    fs::write(&staged, b"broken").unwrap();
    install_staged(&staged, &live).unwrap();

    restore_previous(&live).unwrap();
    assert_eq!(fs::read(&live).unwrap(), b"old");
    assert!(!has_previous(&live), "a rollback consumes the kept copy");
    assert!(dir.path().join("astral-plasma.failed").exists());
}

#[test]
fn rollback_without_a_previous_binary_is_an_error_not_a_deletion() {
    let dir = tempfile::tempdir().unwrap();
    let live = dir.path().join("astral-plasma");
    fs::write(&live, b"only").unwrap();
    assert!(restore_previous(&live).is_err());
    assert_eq!(fs::read(&live).unwrap(), b"only");
}

#[test]
fn a_restart_request_is_consumed_exactly_once() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("restart-requested.json");
    RestartRequest {
        schema: STATE_SCHEMA,
        target_version: "0.2.0".into(),
        staged_binary: "/tmp/astral-plasma.next".into(),
        at_unix: 1,
        already_in_place: false,
    }
    .write(&path)
    .unwrap();

    match consume_restart(&path) {
        astral_plasma::application::restart::AfterExit::Restart(request) => {
            assert_eq!(request.target_version, "0.2.0");
        }
        other => panic!("expected a restart, got {other:?}"),
    }
    assert!(!path.exists(), "a request must not restart the shell twice");
    assert_eq!(
        consume_restart(&path),
        astral_plasma::application::restart::AfterExit::Stop
    );
}

#[test]
fn a_corrupt_state_file_loads_as_nothing_known() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("update.json");
    fs::write(&path, "}{ not json").unwrap();
    let state = UpdateState::load(&path);
    assert_eq!(state, UpdateState::default());
    assert!(state.candidate.is_none());
}

#[test]
fn a_cached_candidate_without_a_usable_digest_is_discarded() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("update.json");
    let mut state = UpdateState::default();
    state.candidate = Some(astral_plasma::domain::update::UpdateCandidate {
        version: "0.2.0".into(),
        channel: "stable".into(),
        highlights: vec![],
        changelog: None,
        url: "https://example.invalid/x".into(),
        sha256: "short".into(),
        size: 10,
    });
    state.save(&path).unwrap();

    assert!(
        UpdateState::load(&path).candidate.is_none(),
        "a candidate that cannot be verified must be re-checked, not installed"
    );
}

#[test]
fn state_round_trips_including_a_rollback_reason() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("update.json");
    let mut state = UpdateState::default();
    state.last_seen_version = Some("0.1.3".into());
    state.rollback = Some(RollbackInfo {
        version: "0.2.0".into(),
        reason: "did not answer IPC".into(),
        at_unix: 7,
    });
    state.save(&path).unwrap();

    let loaded = UpdateState::load(&path);
    assert_eq!(loaded.last_seen_version.as_deref(), Some("0.1.3"));
    assert_eq!(loaded.rollback.unwrap().reason, "did not answer IPC");
}

#[test]
fn a_claim_handoff_only_covers_this_boot_and_this_process() {
    let marker = ClaimHandoff {
        schema: STATE_SCHEMA,
        boot_id: Some("boot-a".into()),
        supervisor_pid: 42,
        at_unix: 1,
    };
    assert!(marker.covers(Some("boot-a"), 42));
    assert!(
        !marker.covers(Some("boot-b"), 42),
        "a marker from a previous boot must not make the shell skip its claim"
    );
    assert!(!marker.covers(Some("boot-a"), 43));
    assert!(
        !marker.covers(None, 42),
        "an unreadable boot id cannot prove the claim is ours"
    );
}
