//! The release contract: a tag carries authored notes, and the manifest the
//! updater will read is generated from them.
//!
//! These are cheap assertions over files that ship, and they are the only place
//! that can catch the failure a user would experience as "the update says
//! nothing changed": a tag whose release notes file is missing, mismatched, or
//! empty.

use std::path::PathBuf;

fn repo_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("daemon/ has a parent")
        .to_path_buf()
}

fn read(rel: &str) -> String {
    let path = repo_root().join(rel);
    std::fs::read_to_string(&path)
        .unwrap_or_else(|err| panic!("cannot read {}: {err}", path.display()))
}

#[test]
fn the_current_version_has_authored_release_notes() {
    let version = env!("CARGO_PKG_VERSION");
    let path = format!("docs/releases/{version}.json");
    let body = read(&path);
    let notes: serde_json::Value = serde_json::from_str(&body)
        .unwrap_or_else(|err| panic!("{path} is not valid JSON: {err}"));

    assert_eq!(
        notes["version"].as_str(),
        Some(version),
        "{path} must describe the version this binary reports"
    );

    let highlights = notes["highlights"]
        .as_array()
        .unwrap_or_else(|| panic!("{path} needs a 'highlights' array"));
    assert!(
        !highlights.is_empty(),
        "{path} must say what changed; an empty release is a deliberate decision, not an omission"
    );
    for highlight in highlights {
        let line = highlight.as_str().unwrap_or_default();
        assert!(
            line.len() > 10,
            "{path}: highlight {line:?} is too short to tell a user anything"
        );
    }
}

#[test]
fn every_tagged_version_has_notes() {
    // The publishes list must never be longer than the notes list, or an
    // installed shell would receive an update with no summary.
    let dir = repo_root().join("docs/releases");
    let mut versions: Vec<String> = std::fs::read_dir(&dir)
        .unwrap_or_else(|err| panic!("cannot read {}: {err}", dir.display()))
        .flatten()
        .filter_map(|entry| {
            let name = entry.file_name().to_string_lossy().to_string();
            name.strip_suffix(".json").map(str::to_string)
        })
        .collect();
    versions.sort();
    assert!(
        versions.contains(&env!("CARGO_PKG_VERSION").to_string()),
        "the running version must have notes; found {versions:?}"
    );
    for version in &versions {
        let body = read(&format!("docs/releases/{version}.json"));
        let notes: serde_json::Value = serde_json::from_str(&body).unwrap();
        assert_eq!(notes["version"].as_str(), Some(version.as_str()));
        assert!(
            notes["date"].as_str().is_some(),
            "{version}.json needs a date"
        );
    }
}

#[test]
fn the_release_pipeline_publishes_a_manifest_and_gates_on_notes() {
    let workflow = read(".github/workflows/release.yml");
    assert!(
        workflow.contains("docs/releases/${VERSION}.json"),
        "the workflow must refuse a tag without authored notes"
    );
    assert!(
        workflow.contains("latest.json"),
        "the updater reads one manifest; the release must publish it"
    );
    assert!(
        workflow.contains("sha256") && workflow.contains("release_assets"),
        "the manifest's digests must be computed from the published artifacts"
    );
    assert!(
        workflow.contains("min_quickshell"),
        "the manifest declares the runtime floor so an old Quickshell is not silently broken"
    );
}

#[test]
fn the_local_release_script_refuses_a_tag_without_notes() {
    let script = read("scripts/release.sh");
    assert!(
        script.contains("docs/releases/"),
        "release.sh must check the notes before pushing the tag, not after"
    );
    assert!(
        script.contains("highlights"),
        "release.sh must validate the notes' highlights"
    );
}

#[test]
fn the_installer_and_uninstaller_are_shipped_next_to_the_binary() {
    // A release archive that cannot install was the original defect: the QML
    // lives in the binary, and the scripts are what extract it.
    let workflow = read(".github/workflows/release.yml");
    assert!(
        workflow.contains("install.sh") && workflow.contains("uninstall.sh"),
        "the tarball must contain both entry points"
    );
    let installer = read("install.sh");
    assert!(
        installer.contains("astral-plasma\" install --method")
            || installer.contains("' install --method"),
        "the installer must delegate the layout to the binary, not reimplement it"
    );
    let uninstaller = read("uninstall.sh");
    assert!(
        uninstaller.contains("uninstall --yes"),
        "the uninstaller must delegate removal to the binary"
    );
}
