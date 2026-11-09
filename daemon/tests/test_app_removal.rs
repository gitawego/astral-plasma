//! Removing an app — including a bundled one — must actually remove it.
//!
//! The Apps page offers Remove on every row, bundled or not. Before this suite existed,
//! `app remove org.astralplasma.media` printed "Removed" and the app came straight back:
//! `app list` reconciles bundled apps on read, and a removal left nothing behind to say
//! "the user meant it". These tests pin the intent, its reversibility, and the data rules.

use std::path::{Path, PathBuf};

use astral_plasma::application::app_install::remove_app;
use astral_plasma::application::app_service::{read_registry, write_registry};
use astral_plasma::application::preinstalled::reconcile_preinstalled;

/// `org.astralplasma.media` -> `Media`: the layout the real package uses.
fn bundle_dir_name(id: &str) -> String {
    let last = id.rsplit('.').next().unwrap_or(id);
    let mut chars = last.chars();
    match chars.next() {
        Some(first) => first.to_uppercase().collect::<String>() + chars.as_str(),
        None => String::new(),
    }
}

/// A bundled-apps directory with one app, plus a data dir to reconcile into.
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

    /// A bundled app the package ships: `<bundled>/<Dir>/{manifest.json,payload…}`, where
    /// the directory is named for humans (`Media`) and the id is reverse-DNS.
    fn bundle(&self, id: &str) {
        let dir = self.bundled().join(bundle_dir_name(id));
        std::fs::create_dir_all(dir.join("tests")).unwrap();
        std::fs::write(
            dir.join("manifest.json"),
            format!(
                r#"{{
  "schema": 1, "id": "{id}", "name": "Bundled", "version": "0.1.0", "kernelApi": 1,
  "dataSchema": 1, "trust": "official", "runtime": "embedded",
  "publisher": {{ "name": "Astral Plasma", "key": "minisign:RWSplaceholderReleaseKey" }},
  "entry": {{ "root": "App.qml" }},
  "requires": {{ "capabilities": [], "qtModules": [], "apps": [] }},
  "permissions": ["session.read"], "distribution": "preinstalled"
}}"#
            ),
        )
        .unwrap();
        std::fs::write(dir.join("App.qml"), "import QtQuick\nItem { }\n").unwrap();
    }

    fn reconcile(&self) -> Vec<String> {
        reconcile_preinstalled(&self.data(), &self.bundled()).unwrap();
        self.ids()
    }

    fn ids(&self) -> Vec<String> {
        read_registry(&self.data()).unwrap().apps.iter().map(|a| a.id.clone()).collect()
    }
}

#[test]
fn a_removed_bundled_app_does_not_come_back_on_the_next_list() {
    let fixture = Fixture::new();
    fixture.bundle("org.astralplasma.media");
    assert_eq!(fixture.reconcile(), vec!["org.astralplasma.media"]);

    let removed = remove_app(&fixture.data(), &fixture.apps(), "org.astralplasma.media", false)
        .expect("removal succeeds");
    assert_eq!(removed.id, "org.astralplasma.media");

    // This is the bug the user reported: the refresh that follows Remove reconciles the
    // bundled apps back in, so the row returns and the button looks broken.
    assert!(
        fixture.reconcile().is_empty(),
        "a deliberate removal must survive the next reconcile"
    );
}

#[test]
fn removing_one_bundled_app_leaves_the_others_alone() {
    let fixture = Fixture::new();
    fixture.bundle("org.astralplasma.media");
    fixture.bundle("org.astralplasma.workspaces");
    fixture.reconcile();

    remove_app(&fixture.data(), &fixture.apps(), "org.astralplasma.media", false).unwrap();
    assert_eq!(fixture.reconcile(), vec!["org.astralplasma.workspaces"]);
}

#[test]
fn a_removed_app_can_be_restored_from_the_bundle() {
    let fixture = Fixture::new();
    fixture.bundle("org.astralplasma.media");
    fixture.reconcile();
    remove_app(&fixture.data(), &fixture.apps(), "org.astralplasma.media", false).unwrap();

    let restored = astral_plasma::application::preinstalled::restore_bundled(
        &fixture.data(),
        &fixture.bundled(),
        "org.astralplasma.media",
    )
    .expect("a bundled app can be restored");
    assert_eq!(restored, "org.astralplasma.media");
    assert_eq!(fixture.ids(), vec!["org.astralplasma.media"]);
    let registry = read_registry(&fixture.data()).unwrap();
    assert!(registry.removed.is_empty(), "restoring clears the tombstone");
    let entry = registry.get("org.astralplasma.media").expect("the record is back");
    assert!(entry.enabled, "a restored app is enabled");
    // A bundled app's payload is the package's own copy (embedded apps load it from
    // there), so restoring restores the record and leaves the package untouched.
    assert!(
        fixture.bundled().join("Media/App.qml").is_file(),
        "the package copy is still the payload"
    );
}

#[test]
fn reinstalling_a_removed_app_also_clears_its_removal() {
    let fixture = Fixture::new();
    fixture.bundle("org.astralplasma.media");
    fixture.reconcile();
    remove_app(&fixture.data(), &fixture.apps(), "org.astralplasma.media", false).unwrap();

    // Installing from a file is a second consent: it must not be shadowed by a tombstone.
    // `upsert_entry` is the path every install goes through, so the rule lives there.
    let manifest = astral_plasma::domain::app_manifest::Manifest::parse(
        &std::fs::read(fixture.bundled().join("Media/manifest.json")).unwrap(),
    )
    .unwrap();
    let mut registry = read_registry(&fixture.data()).unwrap();
    astral_plasma::application::app_service::upsert_entry(
        &mut registry,
        astral_plasma::application::app_service::entry_for(&manifest, "sha256:x"),
    );
    write_registry(&fixture.data(), &registry).unwrap();
    let removed = astral_plasma::application::app_service::read_registry(&fixture.data())
        .unwrap()
        .removed;
    assert!(removed.is_empty(), "installing an app clears its tombstone: {removed:?}");
}

#[test]
fn removal_keeps_the_apps_own_data_unless_purged() {
    let fixture = Fixture::new();
    fixture.bundle("org.astralplasma.media");
    fixture.reconcile();
    let app_dir = fixture.apps().join("org.astralplasma.media");
    std::fs::create_dir_all(app_dir.join("config")).unwrap();
    std::fs::create_dir_all(app_dir.join("cache")).unwrap();
    std::fs::write(app_dir.join("config/settings.json"), "{}").unwrap();

    let removed = remove_app(&fixture.data(), &fixture.apps(), "org.astralplasma.media", false).unwrap();
    assert!(removed.kept_data, "settings survive a plain removal");
    assert!(!app_dir.join("payload").exists(), "the payload is gone");
    assert!(!app_dir.join("manifest.json").exists(), "the manifest is gone");
    assert!(app_dir.join("config/settings.json").is_file(), "settings are kept");
}

#[test]
fn purge_removes_the_apps_data_too() {
    let fixture = Fixture::new();
    fixture.bundle("org.astralplasma.media");
    fixture.reconcile();
    let app_dir = fixture.apps().join("org.astralplasma.media");
    std::fs::create_dir_all(app_dir.join("config")).unwrap();
    std::fs::write(app_dir.join("config/settings.json"), "{}").unwrap();

    let removed = remove_app(&fixture.data(), &fixture.apps(), "org.astralplasma.media", true).unwrap();
    assert!(!removed.kept_data);
    assert!(!app_dir.exists(), "--purge leaves nothing behind");
}

#[test]
fn removing_an_app_that_is_not_installed_is_an_error_not_a_silent_no_op() {
    let fixture = Fixture::new();
    let error = remove_app(&fixture.data(), &fixture.apps(), "io.github.nobody.here", false).unwrap_err();
    assert!(error.to_string().contains("not installed"), "got: {error}");
}

#[test]
fn the_removal_list_names_what_was_removed_and_why_it_matters() {
    let fixture = Fixture::new();
    fixture.bundle("org.astralplasma.media");
    fixture.bundle("org.astralplasma.workspaces");
    fixture.reconcile();
    remove_app(&fixture.data(), &fixture.apps(), "org.astralplasma.media", false).unwrap();

    let registry = read_registry(&fixture.data()).unwrap();
    assert_eq!(registry.removed, vec!["org.astralplasma.media".to_string()]);
    // Only bundled apps can be restored, so the list is what the UI offers.
    let restorable = astral_plasma::application::preinstalled::restorable(&registry, &fixture.bundled());
    assert_eq!(restorable, vec!["org.astralplasma.media".to_string()]);
    assert!(!Path::new("/nonexistent").exists());
}
