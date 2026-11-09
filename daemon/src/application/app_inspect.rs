//! Inspecting an artifact *before* installing it.
//!
//! Consent is only meaningful if it happens before the install, on information the user can
//! read: who published this, which version, which API level, and what it wants access to.
//! That is what `inspect` returns — read from the bundle itself, so it describes the bytes
//! on disk rather than a manifest someone could have edited after packing.

use std::path::Path;

use crate::domain::app_bundle::Bundle;
use crate::domain::app_manifest::Manifest;
use crate::domain::ports::DynResult;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Inspection {
    pub manifest: Manifest,
    /// Size of the artifact in bytes.
    pub size: u64,
    /// True when the payload carries files a hosted app cannot run (native libraries).
    pub has_native_files: bool,
}

/// Read an artifact and describe what installing it would mean.
pub fn inspect(path: &Path) -> DynResult<Inspection> {
    let bytes = std::fs::read(path)
        .map_err(|error| format!("cannot read {}: {error}", path.display()))?;
    let bundle = Bundle::from_ustar(&bytes)?;
    let manifest = bundle.validate()?;
    let has_native_files = bundle
        .files
        .keys()
        .any(|path| path.ends_with(".so") || path.contains(".so."));
    Ok(Inspection {
        manifest,
        size: bytes.len() as u64,
        has_native_files,
    })
}

/// The consent line for one permission, in words rather than in a key.
pub fn permission_summary(permission: &str) -> &'static str {
    match permission {
        "session.read" => "read the state of your desktop session",
        "session.control" => "change session state",
        "windows.read" => "see your open windows and their titles",
        "windows.control" => "focus and close your windows",
        "workspaces.read" => "see your virtual workspaces",
        "workspaces.control" => "switch virtual workspaces",
        "media.read" => "see what is playing",
        "media.control" => "control playback",
        "notifications.post" => "send you notifications",
        "network" => "reach the network",
        "files.read" => "read its own saved files",
        "files.write" => "write its own saved files",
        _ => "an unknown permission",
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::application::app_sdk::{create_app, pack_dir, Template};

    #[test]
    fn inspecting_reports_what_installing_would_grant() {
        let workspace = tempfile::tempdir().unwrap();
        let app = workspace.path().join("src");
        create_app("io.github.alice.clock", Template::Surface, &app).unwrap();
        let manifest_path = app.join("manifest.json");
        let manifest = std::fs::read_to_string(&manifest_path)
            .unwrap()
            .replace("\"permissions\": []", "\"permissions\": [\"windows.read\", \"network\"]");
        std::fs::write(&manifest_path, manifest).unwrap();
        let packed = pack_dir(&app, Some(workspace.path())).unwrap();

        let inspection = inspect(&packed.path).unwrap();
        assert_eq!(inspection.manifest.id, "io.github.alice.clock");
        assert_eq!(inspection.manifest.version, "0.1.0");
        assert_eq!(
            inspection.manifest.permissions,
            vec!["windows.read".to_string(), "network".to_string()]
        );
        assert!(inspection.size > 0);
        assert!(!inspection.has_native_files);
    }

    #[test]
    fn a_tampered_artifact_is_refused_before_consent() {
        let workspace = tempfile::tempdir().unwrap();
        let app = workspace.path().join("src");
        create_app("io.github.alice.clock", Template::Surface, &app).unwrap();
        let packed = pack_dir(&app, Some(workspace.path())).unwrap();
        let mut bytes = std::fs::read(&packed.path).unwrap();
        // A truncated archive: the user must not be asked to consent to something that
        // cannot even be read.
        bytes.truncate(bytes.len() / 2);
        let broken = workspace.path().join("broken.astralapp");
        std::fs::write(&broken, bytes).unwrap();
        assert!(inspect(&broken).is_err());
    }

    #[test]
    fn every_permission_in_the_catalogue_has_words() {
        for permission in crate::domain::app_manifest::PERMISSIONS {
            let summary = permission_summary(permission);
            assert_ne!(summary, "an unknown permission", "{permission} needs a summary");
        }
        assert_eq!(permission_summary("nonsense"), "an unknown permission");
    }
}
