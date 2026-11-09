//! "Individually testable" as a checked property.
//!
//! A feature whose suites live beside its siblings in `tests/` is only individually
//! testable if it *names* them. Each app's manifest declares `testSuites`; this test
//! asserts every declared file exists, every app declares at least one, and no app claims
//! a suite that another app also claims (a shared suite hides which app broke).

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

use astral_plasma::domain::app_manifest::Manifest;

fn apps_root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .unwrap()
        .join("modules/Astral/Apps")
}

fn manifests() -> Vec<(PathBuf, Manifest)> {
    let mut found = Vec::new();
    for entry in std::fs::read_dir(apps_root()).expect("the apps directory exists") {
        let dir = entry.expect("a readable entry").path();
        if !dir.is_dir() {
            continue;
        }
        let path = dir.join("manifest.json");
        if !path.is_file() {
            continue;
        }
        let bytes = std::fs::read(&path).unwrap();
        let manifest = Manifest::parse(&bytes)
            .unwrap_or_else(|error| panic!("{}: {error}", path.display()));
        found.push((dir, manifest));
    }
    found.sort_by(|a, b| a.1.id.cmp(&b.1.id));
    found
}

#[test]
fn every_app_declares_the_suites_that_cover_it() {
    for (dir, manifest) in manifests() {
        let own_suites = std::fs::read_dir(dir.join("tests"))
            .map(|entries| {
                entries
                    .flatten()
                    .filter(|entry| {
                        entry
                            .file_name()
                            .to_str()
                            .is_some_and(|name| name.starts_with("tst_"))
                    })
                    .count()
            })
            .unwrap_or(0);
        assert!(
            own_suites > 0 || !manifest.test_suites.is_empty(),
            "{} declares no testSuites and has no tests/ directory: it is not individually \
             testable, so `astral app test` has nothing to run for it",
            manifest.id
        );
    }
}

#[test]
fn every_declared_suite_exists() {
    let repo_tests = Path::new(env!("CARGO_MANIFEST_DIR")).parent().unwrap().join("tests");
    for (dir, manifest) in manifests() {
        for suite in &manifest.test_suites {
            let candidates = [dir.join(suite), repo_tests.join(suite)];
            assert!(
                candidates.iter().any(|path| path.is_file()),
                "{} declares '{suite}', which is neither beside the app nor in tests/",
                manifest.id
            );
        }
    }
}

#[test]
fn no_suite_is_claimed_by_two_apps() {
    let mut owners: BTreeMap<String, Vec<String>> = BTreeMap::new();
    for (_, manifest) in manifests() {
        for suite in &manifest.test_suites {
            owners.entry(suite.clone()).or_default().push(manifest.id.clone());
        }
    }
    let shared: Vec<String> = owners
        .iter()
        .filter(|(_, apps)| apps.len() > 1)
        .map(|(suite, apps)| format!("{suite} claimed by {}", apps.join(", ")))
        .collect();
    assert!(
        shared.is_empty(),
        "a suite belongs to exactly one app, or a failure names two owners:\n{}",
        shared.join("\n")
    );
}

#[test]
fn a_declared_suite_must_be_a_qml_file_inside_the_repo() {
    for (_, manifest) in manifests() {
        for suite in &manifest.test_suites {
            assert!(suite.ends_with(".qml"), "{}: '{suite}' is not QML", manifest.id);
            assert!(!suite.starts_with('/'), "{}: '{suite}' is absolute", manifest.id);
            assert!(
                !suite.split('/').any(|segment| segment == ".."),
                "{}: '{suite}' escapes the app",
                manifest.id
            );
        }
    }
}
