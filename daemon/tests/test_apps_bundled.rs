//! Bundled apps: the index, the manifests, and what the shell is allowed to name.
//!
//! The shell loads apps from data, so two things must stay true or the desktop
//! silently loses a feature: the generated index lists exactly the apps in the tree,
//! and every bundled manifest is legal with an existing entry component.
//!
//! And one thing must stay false: `shell.qml` must not name a feature.

use astral_plasma::domain::app_manifest::{Distribution, Manifest};
use std::path::{Path, PathBuf};

fn repo_root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("daemon/ has a parent")
        .to_path_buf()
}

fn apps_dir() -> PathBuf {
    repo_root().join("modules/Astral/Apps")
}

fn index() -> serde_json::Value {
    let path = apps_dir().join("index.json");
    serde_json::from_slice(&std::fs::read(&path).expect("index.json is readable"))
        .expect("index.json is JSON")
}

fn app_dirs() -> Vec<String> {
    let mut dirs: Vec<String> = std::fs::read_dir(apps_dir())
        .expect("modules/Astral/Apps exists")
        .flatten()
        .filter(|entry| entry.path().is_dir() && entry.path().join("manifest.json").is_file())
        .map(|entry| entry.file_name().to_string_lossy().to_string())
        .collect();
    dirs.sort();
    dirs
}

fn read_manifest(dir: &str) -> Manifest {
    let path = apps_dir().join(dir).join("manifest.json");
    let bytes = std::fs::read(&path).unwrap_or_else(|err| panic!("{}: {err}", path.display()));
    Manifest::parse(&bytes).unwrap_or_else(|err| panic!("{}: {err}", path.display()))
}

#[test]
fn the_index_lists_every_bundled_app_and_nothing_else() {
    let mut listed: Vec<String> = index()["apps"]
        .as_array()
        .expect("index has an apps array")
        .iter()
        .map(|app| app["dir"].as_str().expect("entry names its dir").to_string())
        .collect();
    listed.sort();
    assert_eq!(listed, app_dirs(), "index.json is stale; run scripts/gen_apps_index.py");

    for app in index()["apps"].as_array().unwrap() {
        let dir = app["dir"].as_str().unwrap();
        let id = app["id"].as_str().unwrap();
        assert_eq!(read_manifest(dir).id, id, "{dir}: index id and manifest id disagree");
    }
}

#[test]
fn every_bundled_manifest_is_legal_and_preinstalled() {
    for dir in app_dirs() {
        let manifest = read_manifest(&dir);
        assert_eq!(
            manifest.distribution(),
            Distribution::Preinstalled,
            "{dir}: a bundled app must declare distribution=preinstalled"
        );
        assert!(manifest.is_official(), "{dir}: a bundled app is official");
        assert_eq!(manifest.runtime, "embedded", "{dir}: bundled apps run embedded");
        assert!(
            !manifest.permissions.is_empty(),
            "{dir}: declaring no permission is indistinguishable from declaring all of them"
        );
    }
}

#[test]
fn every_bundled_entry_component_exists() {
    for dir in app_dirs() {
        let manifest = read_manifest(&dir);
        let entry = apps_dir().join(&dir).join(&manifest.entry.root);
        assert!(
            entry.is_file(),
            "{dir}: entry.root '{}' does not exist in the app directory",
            manifest.entry.root
        );
    }
}

#[test]
fn shell_qml_names_no_feature() {
    let shell =
        std::fs::read_to_string(repo_root().join("shell.qml")).expect("shell.qml is readable");

    for dir in app_dirs() {
        assert!(
            !shell.contains(&format!("{dir} {{")),
            "shell.qml must not instantiate the {dir} app directly"
        );
    }
    assert!(shell.contains("AppHost"), "shell.qml must load bundled apps through AppHost");
    // The shell feeds the port from its own services; the *app* side is what the
    // boundary linter forbids (scripts/check_app_boundaries.py).
    assert!(
        shell.contains("SessionPort"),
        "shell.qml must build the injectable window model"
    );
}
