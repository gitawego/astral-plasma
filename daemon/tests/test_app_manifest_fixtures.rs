//! The manifest contract, checked from both sides against the same fixtures.
//!
//! The installer (Rust) and the host (QML) each validate a manifest, and they must
//! agree: if Rust accepts something the host refuses, an app installs and then
//! never appears; if Rust refuses something the host accepts, the host loads code
//! the installer would have rejected. Neither is acceptable, so both sides read
//! `tests/fixtures/apps/` — this file for Rust, `tst_app_manifest_validation.qml`
//! for QML — with one `expect.json` per case.

use astral_plasma::domain::app_manifest::Manifest;
use serde_json::Value;
use std::path::{Path, PathBuf};

fn repo_root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("daemon/ has a parent")
        .to_path_buf()
}

fn fixtures_dir() -> PathBuf {
    repo_root().join("tests/fixtures/apps")
}

struct Case {
    name: String,
    manifest: PathBuf,
    expect: Value,
}

fn cases() -> Vec<Case> {
    let dir = fixtures_dir();
    let index = std::fs::read_to_string(dir.join("index.json"))
        .expect("tests/fixtures/apps/index.json lists the cases");
    let names: Vec<String> = serde_json::from_str(&index).expect("index.json is a list");
    assert!(!names.is_empty(), "the fixture index must not be empty");
    names
        .into_iter()
        .map(|name| Case {
            manifest: dir.join(&name).join("manifest.json"),
            expect: serde_json::from_str(
                &std::fs::read_to_string(dir.join(&name).join("expect.json"))
                    .unwrap_or_else(|err| panic!("{name}/expect.json: {err}")),
            )
            .unwrap_or_else(|err| panic!("{name}/expect.json is not JSON: {err}")),
            name,
        })
        .collect()
}

#[test]
fn every_fixture_case_has_a_manifest_and_an_expectation() {
    for case in cases() {
        assert!(
            case.manifest.is_file(),
            "{}: manifest.json is missing",
            case.name
        );
    }
}

#[test]
fn rust_accepts_exactly_what_the_fixtures_say() {
    for case in cases() {
        let expected = case.expect["load"].as_bool().expect("expect.json has `load`");
        let bytes = std::fs::read(&case.manifest).unwrap();
        let outcome = Manifest::parse(&bytes);
        assert_eq!(
            outcome.is_ok(),
            expected,
            "{}: Rust {} the manifest but the fixture expects load={expected}{}",
            case.name,
            if outcome.is_ok() { "accepted" } else { "refused" },
            match &outcome {
                Err(err) => format!(": {err}"),
                Ok(_) => String::new(),
            }
        );
        if !expected {
            // The QML side words its own refusal; when it declares a `rustReason`
            // the two must still agree on *which* rule fired.
            if let Some(needle) = case.expect["rustReason"].as_str() {
                let error = outcome.unwrap_err().to_string();
                assert!(
                    error.contains(needle),
                    "{}: Rust refusal must mention '{needle}', got: {error}",
                    case.name
                );
            }
        }
    }
}

#[test]
fn a_fixture_manifest_that_rust_accepts_survives_a_round_trip() {
    for case in cases() {
        if case.expect["load"].as_bool() != Some(true) {
            continue;
        }
        let bytes = std::fs::read(&case.manifest).unwrap();
        let manifest = Manifest::parse(&bytes).unwrap();
        let json = serde_json::to_vec(&manifest).unwrap();
        let parsed = Manifest::parse(&json).unwrap();
        assert_eq!(parsed, manifest, "{}: round trip changed the manifest", case.name);
    }
}
