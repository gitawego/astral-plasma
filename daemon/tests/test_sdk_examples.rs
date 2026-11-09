//! Every shipped SDK example must survive the whole authoring path.
//!
//! The examples are documentation people copy. If one lints clean but fails to pack, or
//! packs but cannot be installed, the first hour of a new app author is broken and this
//! test is the only thing standing between that and a release.

use std::path::{Path, PathBuf};

use astral_plasma::application::app_install::install_file;
use astral_plasma::application::app_sdk::{lint_dir, pack_dir};
use astral_plasma::application::app_service::read_registry;
use astral_plasma::domain::app_compat::{HostApi, APP_API_LEVEL};
use astral_plasma::domain::app_manifest::Manifest;

fn examples() -> Vec<PathBuf> {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("daemon lives in the repository")
        .join("sdk/examples");
    let mut dirs: Vec<PathBuf> = std::fs::read_dir(&root)
        .unwrap_or_else(|error| panic!("sdk/examples is readable at {}: {error}", root.display()))
        .filter_map(Result::ok)
        .map(|entry| entry.path())
        .filter(|path| path.is_dir())
        .collect();
    dirs.sort();
    assert!(!dirs.is_empty(), "the SDK must ship at least one example");
    dirs
}

fn host() -> HostApi {
    // Examples may declare `minQuickshell`, so the host must claim a version (the real
    // install path reads it from `quickshell --version`).
    HostApi {
        level: APP_API_LEVEL,
        floor: APP_API_LEVEL,
        quickshell: Some("0.3.0".to_string()),
    }
}

#[test]
fn every_example_has_a_valid_manifest() {
    for dir in examples() {
        let bytes = std::fs::read(dir.join("manifest.json"))
            .unwrap_or_else(|error| panic!("{} has a manifest: {error}", dir.display()));
        let manifest = Manifest::parse(&bytes)
            .unwrap_or_else(|error| panic!("{} manifest validates: {error}", dir.display()));
        assert!(
            manifest.runtime == "hosted",
            "{} is an example of a hosted app",
            manifest.id
        );
        assert!(
            dir.join(&manifest.entry.root).is_file(),
            "{} entry file is missing",
            manifest.id
        );
    }
}

#[test]
fn every_example_lints_clean() {
    for dir in examples() {
        let problems = lint_dir(&dir).unwrap_or_else(|error| panic!("{} lints: {error}", dir.display()));
        assert!(problems.is_empty(), "{}: {problems:?}", dir.display());
    }
}

#[test]
fn every_example_packs_installs_and_records_its_payload() {
    for dir in examples() {
        let workspace = tempfile::tempdir().unwrap();
        let packed = pack_dir(&dir, Some(workspace.path()))
            .unwrap_or_else(|error| panic!("{} packs: {error}", dir.display()));

        let data = workspace.path().join("data");
        let apps = data.join("apps");
        let installed = install_file(&data, &apps, &packed.path, &host(), false, false)
            .unwrap_or_else(|error| panic!("{} installs: {error}", dir.display()));

        let registry = read_registry(&data).expect("the registry is readable");
        let entry = registry
            .get(&installed.id)
            .unwrap_or_else(|| panic!("{} is recorded", installed.id));
        assert!(entry.enabled, "a freshly installed app is enabled");
        assert!(
            !entry.payload_digest.is_empty(),
            "{} records a payload digest so a launch can verify it",
            installed.id
        );
    }
}

#[test]
fn the_examples_cover_the_surface_kinds_the_sdk_documents() {
    // A hosted window and a hosted panel: the two shapes an app author starts from.
    let kinds: Vec<String> = examples()
        .iter()
        .filter_map(|dir| {
            let bytes = std::fs::read(dir.join("manifest.json")).ok()?;
            let manifest = Manifest::parse(&bytes).ok()?;
            manifest.entry.surface.map(|surface| surface.kind)
        })
        .collect();
    assert!(kinds.contains(&"toplevel".to_string()), "got: {kinds:?}");
    assert!(kinds.contains(&"layer-shell".to_string()), "got: {kinds:?}");
}
