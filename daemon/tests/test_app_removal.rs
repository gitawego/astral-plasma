//! Removing an app — and the rule that a bundled app is not removable.
//!
//! The Apps page used to offer Remove on every row. For a bundled app that button could
//! never do what it said: the app ships with the platform, so `app list` reconciles it back
//! and the row returns. The rule is now explicit and enforced in the domain: **a bundled
//! app can be disabled, not removed**; Remove is offered only for apps the user installed.

use std::path::{Path, PathBuf};

use astral_plasma::application::app_install::{install_file, remove_app};
use astral_plasma::application::app_service::{read_registry, set_enabled};
use astral_plasma::application::preinstalled::reconcile_preinstalled;
use astral_plasma::domain::app_compat::{HostApi, APP_API_LEVEL};

fn host() -> HostApi {
    HostApi { level: APP_API_LEVEL, floor: APP_API_LEVEL, quickshell: Some("0.3.0".to_string()) }
}

struct Fixture {
    dir: tempfile::TempDir,
}

impl Fixture {
    fn new() -> Self {
        Self { dir: tempfile::tempdir().unwrap() }
    }
    fn data(&self) -> PathBuf { self.dir.path().join("data") }
    fn apps(&self) -> PathBuf { self.data().join("apps") }
    fn bundled(&self) -> PathBuf { self.dir.path().join("bundled") }

    /// A bundled app as the package ships it: `<bundled>/Media/{manifest.json, App.qml}`.
    fn bundle(&self, id: &str) {
        let dir = self.bundled().join(bundle_dir_name(id));
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::write(dir.join("manifest.json"), manifest_json(id, "official", "preinstalled")).unwrap();
        std::fs::write(dir.join("App.qml"), "import QtQuick\nItem { }\n").unwrap();
    }

    /// A packed, installable app the user owns.
    fn install(&self, id: &str) -> astral_plasma::application::app_install::Installed {
        let source = self.dir.path().join(format!("src-{id}"));
        std::fs::create_dir_all(&source).unwrap();
        std::fs::write(source.join("manifest.json"), manifest_json(id, "community", "store")).unwrap();
        std::fs::write(source.join("shell.qml"), "import QtQuick\nItem { }\n").unwrap();
        let packed = astral_plasma::application::app_sdk::pack_dir(&source, Some(self.dir.path())).unwrap();
        install_file(&self.data(), &self.apps(), &packed.path, &host(), false, false).unwrap()
    }

    fn reconcile(&self) -> Vec<String> {
        reconcile_preinstalled(&self.data(), &self.bundled()).unwrap();
        self.ids()
    }

    fn ids(&self) -> Vec<String> {
        read_registry(&self.data()).unwrap().apps.iter().map(|a| a.id.clone()).collect()
    }
}

fn bundle_dir_name(id: &str) -> String {
    let last = id.rsplit('.').next().unwrap_or(id);
    let mut chars = last.chars();
    match chars.next() {
        Some(first) => first.to_uppercase().collect::<String>() + chars.as_str(),
        None => String::new(),
    }
}

fn manifest_json(id: &str, trust: &str, distribution: &str) -> String {
    let (runtime, root) = if distribution == "preinstalled" {
        ("embedded", "App.qml")
    } else {
        ("hosted", "shell.qml")
    };
    format!(
        r#"{{
  "schema": 1, "id": "{id}", "name": "Fixture", "version": "0.1.0", "kernelApi": 1,
  "dataSchema": 1, "trust": "{trust}", "runtime": "{runtime}",
  "publisher": {{ "name": "Astral Plasma", "key": "minisign:RWSplaceholderReleaseKey" }},
  "entry": {{ "root": "{root}" }},
  "requires": {{ "capabilities": [], "qtModules": [], "apps": [] }},
  "permissions": ["session.read"], "distribution": "{distribution}"
}}"#
    )
}

#[test]
fn a_bundled_app_cannot_be_removed_and_says_why() {
    let fixture = Fixture::new();
    fixture.bundle("org.astralplasma.media");
    fixture.reconcile();

    let error = remove_app(&fixture.data(), &fixture.apps(), "org.astralplasma.media", false)
        .expect_err("a bundled app is not removable");
    let text = error.to_string();
    assert!(text.contains("bundled"), "the refusal names what it is: {text}");
    assert!(text.contains("disable"), "and names the action that does work: {text}");

    // Nothing moved: the record, the payload and the state are untouched.
    assert_eq!(fixture.ids(), vec!["org.astralplasma.media"]);
    assert!(fixture.bundled().join("Media/App.qml").is_file());
}

#[test]
fn the_refusal_survives_a_reconcile_so_the_row_cannot_vanish_then_return() {
    let fixture = Fixture::new();
    fixture.bundle("org.astralplasma.media");
    fixture.reconcile();
    assert!(remove_app(&fixture.data(), &fixture.apps(), "org.astralplasma.media", true).is_err());
    assert_eq!(fixture.reconcile(), vec!["org.astralplasma.media"]);
}

#[test]
fn a_bundled_app_can_be_disabled_instead() {
    let fixture = Fixture::new();
    fixture.bundle("org.astralplasma.media");
    fixture.reconcile();

    let mut registry = read_registry(&fixture.data()).unwrap();
    assert!(set_enabled(&mut registry, "org.astralplasma.media", false).unwrap());
    astral_plasma::application::app_service::write_registry(&fixture.data(), &registry).unwrap();

    // Reconciliation keeps the user's state: re-enabling is the user's decision, not boot's.
    fixture.reconcile();
    let registry = read_registry(&fixture.data()).unwrap();
    let entry = registry.get("org.astralplasma.media").expect("still installed");
    assert!(!entry.enabled, "a disabled bundled app stays disabled");
}

#[test]
fn an_installed_app_is_still_removable() {
    let fixture = Fixture::new();
    let installed = fixture.install("io.github.alice.clock");
    assert_eq!(fixture.ids(), vec!["io.github.alice.clock"]);

    let removed = remove_app(&fixture.data(), &fixture.apps(), "io.github.alice.clock", false).unwrap();
    assert!(removed.removed_files, "the payload went with it");
    assert!(fixture.ids().is_empty(), "and so did the record");
    assert!(!fixture.apps().join(&installed.id).join("payload").exists());
}

#[test]
fn removal_keeps_the_apps_own_settings_unless_purged() {
    let fixture = Fixture::new();
    fixture.install("io.github.alice.clock");
    let app_dir = fixture.apps().join("io.github.alice.clock");
    std::fs::create_dir_all(app_dir.join("config")).unwrap();
    std::fs::write(app_dir.join("config/settings.json"), "{}").unwrap();

    let removed = remove_app(&fixture.data(), &fixture.apps(), "io.github.alice.clock", false).unwrap();
    assert!(removed.kept_data, "settings survive a plain removal");
    assert!(app_dir.join("config/settings.json").is_file(), "settings are kept");
    assert!(!app_dir.join("payload").exists(), "the payload is gone");
    assert!(!app_dir.join("manifest.json").exists(), "the manifest is gone");
}

#[test]
fn purge_removes_the_apps_settings_too() {
    let fixture = Fixture::new();
    fixture.install("io.github.alice.clock");
    let app_dir = fixture.apps().join("io.github.alice.clock");
    std::fs::create_dir_all(app_dir.join("config")).unwrap();
    std::fs::write(app_dir.join("config/settings.json"), "{}").unwrap();

    let removed = remove_app(&fixture.data(), &fixture.apps(), "io.github.alice.clock", true).unwrap();
    assert!(!removed.kept_data);
    assert!(!app_dir.exists(), "--purge leaves nothing behind");
}

#[test]
fn removing_an_app_that_is_not_installed_names_it() {
    let fixture = Fixture::new();
    let error = remove_app(&fixture.data(), &fixture.apps(), "io.github.nobody.here", false).unwrap_err();
    assert!(error.to_string().contains("io.github.nobody.here"), "got: {error}");
}

#[test]
fn the_registry_no_longer_carries_a_removal_list() {
    // The tombstone existed only to stop reconcile from resurrecting a bundled app that
    // could be removed. Bundled apps cannot be removed now, so the state is gone: one
    // rule, one representation (disable).
    let fixture = Fixture::new();
    fixture.bundle("org.astralplasma.media");
    fixture.reconcile();
    let text = std::fs::read_to_string(fixture.data().join("apps.json")).unwrap();
    assert!(!text.contains("\"removed\""), "no tombstone field: {text}");
    assert!(Path::new(&fixture.data()).exists());
}
