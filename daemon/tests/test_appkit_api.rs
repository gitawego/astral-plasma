//! The API freeze gate.
//!
//! `docs/APPKIT-API.md` and `daemon/tests/fixtures/appkit-surface.txt` are the recorded
//! contract. These tests fail when the QML sources drift from it without a level decision,
//! when the document drifts from the sources, and when the deprecation rules are broken.

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

use astral_plasma::domain::app_compat::{API_LEVEL_HISTORY, APP_API_FLOOR, APP_API_LEVEL};
use astral_plasma::domain::appkit_api;

fn repo_root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("daemon lives in the repository")
        .to_path_buf()
}

fn appkit_dir() -> PathBuf {
    repo_root().join("modules/Astral/AppKit")
}

fn recorded_surface() -> String {
    let path = Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/appkit-surface.txt");
    std::fs::read_to_string(&path).unwrap_or_else(|error| {
        panic!("the recorded surface is missing at {}: {error}", path.display())
    })
}

#[test]
fn the_surface_matches_its_recorded_contract() {
    let surface = appkit_api::surface(&appkit_dir()).expect("AppKit is readable");
    let drift = appkit_api::check(&recorded_surface(), &surface);
    assert!(
        drift.is_empty(),
        "the AppKit surface changed without a level decision:\n{}\n\
         If this change is deliberate, bump the level, run `astral-plasma app api --write`, \
         and update docs/APPKIT-API.md in the same commit.",
        drift.describe()
    );
}

#[test]
fn the_document_is_generated_from_the_sources() {
    let surface = appkit_api::surface(&appkit_dir()).expect("AppKit is readable");
    let mut releases = BTreeMap::new();
    for (level, release) in API_LEVEL_HISTORY {
        releases.insert(level, release.to_string());
    }
    let expected = appkit_api::render(&surface, APP_API_LEVEL, APP_API_FLOOR, &releases);
    let actual = std::fs::read_to_string(repo_root().join("docs/APPKIT-API.md"))
        .expect("docs/APPKIT-API.md exists");
    assert_eq!(
        actual, expected,
        "docs/APPKIT-API.md is stale; run `astral-plasma app api --write`"
    );
}

#[test]
fn the_documented_deprecations_obey_the_policy() {
    let surface = appkit_api::surface(&appkit_dir()).expect("AppKit is readable");
    appkit_api::validate_deprecations(&surface, APP_API_FLOOR).expect("deprecations are valid");
}

#[test]
fn every_recorded_member_belongs_to_a_shipped_type() {
    let surface = appkit_api::surface(&appkit_dir()).expect("AppKit is readable");
    // A `type` row per file: if a file is deleted, its members must leave the contract too.
    let types: Vec<&str> = surface
        .members
        .iter()
        .filter(|member| member.kind == "type")
        .map(|member| member.name.as_str())
        .collect();
    for expected in ["AppApi", "AppPalette", "AppWindow", "Colors", "Motion", "Theme"] {
        assert!(types.contains(&expected), "{expected}.qml is missing from the SDK");
    }
    for member in &surface.members {
        assert!(
            types.contains(&member.owner.as_str()),
            "{} is owned by {}, which is not an SDK type",
            member.name,
            member.owner
        );
    }
}

#[test]
fn the_level_history_covers_every_supported_level() {
    let levels: Vec<u32> = API_LEVEL_HISTORY.iter().map(|(level, _)| *level).collect();
    assert!(levels.contains(&APP_API_LEVEL), "the current level needs a release");
    assert!(levels.contains(&APP_API_FLOOR), "the floor needs a release");
    for level in APP_API_FLOOR..=APP_API_LEVEL {
        assert!(levels.contains(&level), "level {level} has no release");
    }
}

#[test]
fn an_unrecorded_member_is_reported_as_drift() {
    // The gate must actually fire, or it protects nothing.
    let surface = appkit_api::surface(&appkit_dir()).expect("AppKit is readable");
    let trimmed: String = recorded_surface()
        .lines()
        .filter(|line| !line.starts_with("AppWindow property padding"))
        .map(|line| format!("{line}\n"))
        .collect();
    let drift = appkit_api::check(&trimmed, &surface);
    assert_eq!(drift.added, vec!["AppWindow property padding".to_string()]);
    assert!(drift.removed.is_empty());
}
