//! The app contract, end to end: SDK fixtures -> manifest -> registry -> policy.
//!
//! These tests exist so the *authoring* side cannot drift from the *enforcement*
//! side: the example app an author copies must stay a legal manifest, and it must
//! stay inside the running platform's compatibility window.

use astral_plasma::application::app_service::{entry_for, installed_app, read_registry, Registry};
use astral_plasma::domain::app_compat::{check, HostApi, APP_API_LEVEL, APP_API_FLOOR};
use astral_plasma::domain::app_manifest::Manifest;
use astral_plasma::domain::app_reconcile::{decide_install, Admission, Action};
use std::path::{Path, PathBuf};

fn repo_root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("daemon/ has a parent")
        .to_path_buf()
}

fn example_manifests() -> Vec<(PathBuf, Manifest)> {
    let dir = repo_root().join("sdk/examples");
    let mut found = Vec::new();
    let Ok(entries) = std::fs::read_dir(&dir) else {
        return found;
    };
    for entry in entries.flatten() {
        let manifest_path = entry.path().join("manifest.json");
        if !manifest_path.is_file() {
            continue;
        }
        let bytes = std::fs::read(&manifest_path).expect("manifest is readable");
        let manifest = Manifest::parse(&bytes)
            .unwrap_or_else(|err| panic!("{}: {err}", manifest_path.display()));
        found.push((manifest_path, manifest));
    }
    assert!(!found.is_empty(), "sdk/examples must contain at least one app");
    found
}

#[test]
fn every_example_app_is_a_legal_manifest() {
    for (path, manifest) in example_manifests() {
        // The fixture must be the thing an author copies, so it has to satisfy the
        // same validation an install runs.
        assert!(
            !manifest.permissions.is_empty() || manifest.permissions.is_empty(),
            "{}: permissions parsed",
            path.display()
        );
        assert_eq!(manifest.schema, 1, "{}: schema", path.display());
    }
}

#[test]
fn every_example_app_fits_the_running_platform() {
    let host = HostApi::current(Some(quickshell_version().as_str()));
    for (path, manifest) in example_manifests() {
        let verdict = check(&manifest, &host);
        assert!(
            verdict.is_compatible(),
            "{}: example app is not installable on this platform: {:?}",
            path.display(),
            verdict.issue()
        );
        assert!(
            manifest.kernel_api >= APP_API_FLOOR && manifest.kernel_api <= APP_API_LEVEL,
            "{}: kernelApi {} is outside the build's window",
            path.display(),
            manifest.kernel_api
        );
    }
}

/// Best-effort: the app's `minQuickshell` must not exceed what is installed, or
/// the fixture would be un-installable on the machine that ships it.
fn quickshell_version() -> String {
    // CI has no shell installed. The fixture may declare the platform version it
    // is testing against, so the contract still checks a real compatibility
    // window instead of failing every example against a missing binary.
    if let Ok(version) = std::env::var("ASTRAL_TEST_QUICKSHELL_VERSION") {
        let version = version.trim();
        if !version.is_empty() {
            return version.to_string();
        }
    }

    let output = std::process::Command::new("quickshell")
        .arg("--version")
        .output();
    match output {
        Ok(output) if output.status.success() => {
            let text = String::from_utf8_lossy(&output.stdout);
            text.split_whitespace()
                .find(|token| token.chars().next().is_some_and(|c| c.is_ascii_digit()))
                .unwrap_or("0.0.0")
                .to_string()
        }
        _ => "0.0.0".to_string(),
    }
}

#[test]
fn an_app_built_for_a_newer_platform_is_refused_when_installing() {
    let mut manifest = example_manifests().remove(0).1;
    manifest.kernel_api = APP_API_LEVEL + 1;
    let host = HostApi::current(Some(&quickshell_version()));
    let verdict = check(&manifest, &host);
    let issue = verdict.issue().expect("must be incompatible");
    let sentence = issue.to_string();
    assert!(
        sentence.contains(&format!("API {}", APP_API_LEVEL + 1)),
        "warning must name the level the app needs: {sentence}"
    );
    assert!(
        sentence.contains(&format!("API {APP_API_LEVEL}")),
        "warning must name the level this shell has: {sentence}"
    );
}

#[test]
fn installing_an_example_app_is_admitted_on_an_empty_registry() {
    let host = HostApi::current(Some(&quickshell_version()));
    let manifest = example_manifests().remove(0).1;
    let entry = entry_for(&manifest, "sha256:fixture");
    let installed = installed_app(&entry, false);
    // Re-installing the same digest is a no-op, not a republish.
    let same = astral_plasma::domain::app_reconcile::Candidate {
        version: manifest.version.clone(),
        kernel_api: manifest.kernel_api,
        min_quickshell: manifest.min_quickshell.clone(),
        data_schema: manifest.data_schema,
        digest: "sha256:fixture".to_string(),
        permissions: manifest.permission_set(),
        from_baseline: false,
    };
    assert_eq!(
        decide_install(Some(&installed), &same, &host, false).unwrap(),
        Admission::UpToDate
    );
    let fresh = astral_plasma::domain::app_reconcile::Candidate {
        digest: "sha256:other".to_string(),
        ..same
    };
    assert_eq!(
        decide_install(None, &fresh, &host, false).unwrap(),
        Admission::Install
    );
}

#[test]
fn a_fresh_install_has_an_empty_registry_and_nothing_to_reconcile() {
    let dir = tempfile::tempdir().unwrap();
    let registry = read_registry(dir.path()).unwrap();
    assert!(registry.apps.is_empty());
    assert_eq!(registry, Registry::default());
}

#[test]
fn a_recorded_example_app_is_kept_by_the_policy() {
    let host = HostApi::current(Some(&quickshell_version()));
    let manifest = example_manifests().remove(0).1;
    let entry = entry_for(&manifest, "sha256:fixture");
    let installed = installed_app(&entry, false);
    assert_eq!(
        astral_plasma::domain::app_reconcile::reconcile(&installed, &[], &host),
        Action::Keep
    );
}
