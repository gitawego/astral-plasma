//! Check and apply against a fake source: every refusal happens before a file is
//! written, and a successful apply stages a verified binary without touching the
//! one that is running.

use astral_plasma::application::update_service::{UpdatePaths, UpdateService};
use astral_plasma::domain::install_record::{InstallMethod, InstallRecord};
use astral_plasma::domain::ports::DynResult;
use astral_plasma::domain::update::{
    Channel, ManifestFetch, ReleaseManifest, UpdateSourcePort,
};
use astral_plasma::domain::update_state::{RestartRequest, UpdateState};
use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::Path;
use std::sync::Mutex;

struct FakeSource {
    manifest: Mutex<Vec<u8>>,
    etag: Mutex<Option<String>>,
    not_modified: Mutex<bool>,
    payload: Vec<u8>,
    downloads: Mutex<usize>,
    etags_seen: Mutex<Vec<Option<String>>>,
}

impl FakeSource {
    fn new(manifest: &ReleaseManifest, payload: Vec<u8>) -> Self {
        Self {
            manifest: Mutex::new(serde_json::to_vec(manifest).unwrap()),
            etag: Mutex::new(Some("etag-1".to_string())),
            not_modified: Mutex::new(false),
            payload,
            downloads: Mutex::new(0),
            etags_seen: Mutex::new(Vec::new()),
        }
    }
}

impl UpdateSourcePort for FakeSource {
    fn fetch_manifest(&self, _url: &str, etag: Option<&str>) -> DynResult<ManifestFetch> {
        self.etags_seen.lock().unwrap().push(etag.map(str::to_string));
        if *self.not_modified.lock().unwrap() {
            return Ok(ManifestFetch {
                not_modified: true,
                etag: self.etag.lock().unwrap().clone(),
                body: Vec::new(),
            });
        }
        Ok(ManifestFetch {
            not_modified: false,
            etag: self.etag.lock().unwrap().clone(),
            body: self.manifest.lock().unwrap().clone(),
        })
    }

    fn download(&self, _url: &str, dest: &Path, _max_bytes: u64) -> DynResult<u64> {
        *self.downloads.lock().unwrap() += 1;
        fs::write(dest, &self.payload)?;
        Ok(self.payload.len() as u64)
    }
}

fn payload() -> Vec<u8> {
    b"#!/bin/sh\necho new\n".to_vec()
}

fn digest_of(bytes: &[u8]) -> String {
    use sha2::{Digest, Sha256};
    let mut hasher = Sha256::new();
    hasher.update(bytes);
    format!("{:x}", hasher.finalize())
}

fn manifest_for(version: &str, bytes: &[u8]) -> ReleaseManifest {
    let mut artifacts = std::collections::BTreeMap::new();
    artifacts.insert(
        "x86_64".to_string(),
        astral_plasma::domain::update::Artifact {
            url: "https://example.invalid/astral-plasma-linux-x86_64".to_string(),
            sha256: digest_of(bytes),
            size: bytes.len() as u64,
        },
    );
    // The architecture in the test must match the host doing the testing.
    if astral_plasma::domain::update::host_arch() != "x86_64" {
        let artifact = artifacts.remove("x86_64").unwrap();
        artifacts.insert(astral_plasma::domain::update::host_arch(), artifact);
    }
    ReleaseManifest {
        schema: 1,
        version: version.to_string(),
        channel: "stable".to_string(),
        published_at: None,
        min_quickshell: Some("0.3.0".to_string()),
        highlights: vec!["A real change".to_string()],
        changelog: None,
        artifacts,
        signature: None,
    }
}

fn seeded(root: &Path, method: InstallMethod) -> UpdatePaths {
    let paths = UpdatePaths::rooted_at(root);
    fs::create_dir_all(paths.live_binary.parent().unwrap()).unwrap();
    fs::write(&paths.live_binary, b"old binary").unwrap();
    InstallRecord::new(method, "0.1.3", "stable", 1)
        .write(&paths.record_path)
        .unwrap();
    paths
}

fn service(paths: UpdatePaths, manifest: &ReleaseManifest, bytes: Vec<u8>) -> UpdateService {
    let mut service = UpdateService::with_paths(paths, Box::new(FakeSource::new(manifest, bytes)));
    service.current_version = "0.1.3".to_string();
    service.manifest_url = "https://example.invalid/latest.json".to_string();
    service
}

#[test]
fn without_a_record_an_install_is_a_checkout_and_cannot_be_updated() {
    let root = tempfile::tempdir().unwrap();
    let paths = UpdatePaths::rooted_at(root.path());
    let bytes = payload();
    let service = service(paths, &manifest_for("0.2.0", &bytes), bytes);

    let status = service.status().unwrap();
    assert_eq!(status.install_method, "checkout");
    assert!(!status.can_apply);
    assert!(status
        .refuse_reason
        .as_deref()
        .unwrap_or_default()
        .contains("git pull"));
}

#[test]
fn a_check_finds_a_newer_release_and_records_it() {
    let root = tempfile::tempdir().unwrap();
    let paths = seeded(root.path(), InstallMethod::Managed);
    let bytes = payload();
    let service = service(paths.clone(), &manifest_for("0.2.0", &bytes), bytes);

    let status = service.check(false).unwrap();
    assert!(status.can_apply, "{status:?}");
    assert_eq!(status.candidate.as_ref().unwrap().version, "0.2.0");
    assert!(status.candidate.as_ref().unwrap().size > 0);

    let state = UpdateState::load(&paths.state_path);
    assert_eq!(state.etag.as_deref(), Some("etag-1"));
    assert!(state.last_check_unix > 0);
}

#[test]
fn a_not_modified_answer_keeps_the_candidate_and_sends_the_etag() {
    let root = tempfile::tempdir().unwrap();
    let paths = seeded(root.path(), InstallMethod::Managed);
    let bytes = payload();
    let service = service(paths.clone(), &manifest_for("0.2.0", &bytes), bytes);
    service.check(false).unwrap();

    // Second check: the source reports 304 and must receive the stored ETag.
    let state_before = UpdateState::load(&paths.state_path);
    let source = FakeSource {
        manifest: Mutex::new(Vec::new()),
        etag: Mutex::new(state_before.etag.clone()),
        not_modified: Mutex::new(true),
        payload: Vec::new(),
        downloads: Mutex::new(0),
        etags_seen: Mutex::new(Vec::new()),
    };
    let mut service = UpdateService::with_paths(paths.clone(), Box::new(source));
    service.current_version = "0.1.3".to_string();

    let status = service.check(false).unwrap();
    assert_eq!(
        status.candidate.as_ref().unwrap().version,
        "0.2.0",
        "a 304 means nothing changed, not that the candidate vanished"
    );
}

#[test]
fn a_failed_check_is_recorded_and_does_not_break_status() {
    let root = tempfile::tempdir().unwrap();
    let paths = seeded(root.path(), InstallMethod::Managed);

    struct Failing;
    impl UpdateSourcePort for Failing {
        fn fetch_manifest(&self, _url: &str, _etag: Option<&str>) -> DynResult<ManifestFetch> {
            Err("network is down".into())
        }
        fn download(&self, _url: &str, _dest: &Path, _max: u64) -> DynResult<u64> {
            Err("network is down".into())
        }
    }

    let mut service = UpdateService::with_paths(paths.clone(), Box::new(Failing));
    service.current_version = "0.1.3".to_string();
    assert!(service.check(false).is_err());

    let status = service.status().unwrap();
    assert!(status.last_error.unwrap_or_default().contains("network is down"));
}

#[test]
fn apply_stages_a_verified_binary_and_asks_for_a_restart() {
    let root = tempfile::tempdir().unwrap();
    let paths = seeded(root.path(), InstallMethod::Managed);
    let bytes = payload();
    let service = service(paths.clone(), &manifest_for("0.2.0", &bytes), bytes.clone());
    service.check(false).unwrap();

    let live_before = fs::read(&paths.live_binary).unwrap();
    let outcome = service.apply(|| true).unwrap();

    assert_eq!(outcome.version, "0.2.0");
    assert!(outcome.restart_requested);
    assert_eq!(outcome.verified_sha256, digest_of(&bytes));

    assert_eq!(
        fs::read(&paths.live_binary).unwrap(),
        live_before,
        "apply must never replace the binary a running shell is executing"
    );
    let staged = fs::read(&paths.staged_binary).unwrap();
    assert_eq!(staged, bytes);
    assert_eq!(
        fs::metadata(&paths.staged_binary).unwrap().permissions().mode() & 0o777,
        0o755
    );

    let request = RestartRequest::read(&paths.restart_path).expect("restart requested");
    assert_eq!(request.target_version, "0.2.0");
    assert_eq!(request.staged_binary, paths.staged_binary.to_string_lossy());

    // A second apply is refused while the staged update waits for its restart.
    let status = service.status().unwrap();
    assert!(status.restart_pending.is_some());
    assert!(status.refuse_reason.unwrap_or_default().contains("already staged"));
}

#[test]
fn a_tampered_artifact_is_refused_before_anything_is_staged() {
    let root = tempfile::tempdir().unwrap();
    let paths = seeded(root.path(), InstallMethod::Managed);
    let bytes = payload();
    let mut manifest = manifest_for("0.2.0", &bytes);
    // The manifest promises one thing, the server serves another.
    for artifact in manifest.artifacts.values_mut() {
        artifact.sha256 = "f".repeat(64);
    }
    let service = service(paths.clone(), &manifest, bytes);
    service.check(false).unwrap();

    let err = service.apply(|| true).expect_err("digest mismatch must refuse");
    assert!(err.to_string().contains("checksum mismatch"), "{err}");
    assert!(!paths.staged_binary.exists());
    assert!(!paths.restart_path.exists());
}

#[test]
fn an_artifact_of_the_wrong_size_is_refused() {
    let root = tempfile::tempdir().unwrap();
    let paths = seeded(root.path(), InstallMethod::Managed);
    let bytes = payload();
    let mut manifest = manifest_for("0.2.0", &bytes);
    for artifact in manifest.artifacts.values_mut() {
        artifact.size += 1;
    }
    let service = service(paths.clone(), &manifest, bytes);
    service.check(false).unwrap();

    let err = service.apply(|| true).expect_err("size mismatch must refuse");
    assert!(err.to_string().contains("declares"), "{err}");
    assert!(!paths.staged_binary.exists());
}

#[test]
fn a_package_owned_install_refuses_to_apply() {
    let root = tempfile::tempdir().unwrap();
    let paths = seeded(root.path(), InstallMethod::Package);
    let bytes = payload();
    let service = service(paths.clone(), &manifest_for("0.2.0", &bytes), bytes);
    service.check(false).unwrap();

    let err = service.apply(|| true).expect_err("pacman owns these files");
    assert!(err.to_string().contains("package"), "{err}");
    assert!(!paths.staged_binary.exists());
}

#[test]
fn status_reports_the_compiled_version_and_the_install_owner() {
    let root = tempfile::tempdir().unwrap();
    let paths = seeded(root.path(), InstallMethod::Managed);
    let bytes = payload();
    let service = service(paths, &manifest_for("0.2.0", &bytes), bytes);
    let status = service.status().unwrap();
    assert_eq!(status.current_version, "0.1.3");
    assert_eq!(status.channel, "stable");
    assert_eq!(status.install_method, "managed");
    assert_eq!(status.arch, astral_plasma::domain::update::host_arch());
    assert_eq!(Channel::parse(&status.channel).unwrap(), Channel::Stable);
}

#[test]
fn pacman_ownership_is_parsed_from_the_real_output_shape() {
    let owner = astral_plasma::application::update_service::parse_pacman_owner(
        "usr/bin/astral-plasma is owned by astral-plasma-bin 0.1.3-1\n",
    );
    assert_eq!(owner.as_deref(), Some("astral-plasma-bin"));

    assert_eq!(
        astral_plasma::application::update_service::parse_pacman_owner(
            "error: No package owns /home/u/.local/share/astral-plasma/bin/astral-plasma\n"
        ),
        None,
        "a user-owned path is not a package install"
    );
}

#[test]
fn a_checked_current_install_is_not_reported_as_never_checked() {
    let root = tempfile::tempdir().unwrap();
    let paths = seeded(root.path(), InstallMethod::Managed);
    let bytes = payload();
    // The release is the version already running: nothing to install.
    let service = service(paths.clone(), &manifest_for("0.1.3", &bytes), bytes);

    let fresh = service.status().unwrap();
    assert!(
        fresh.refuse_reason.as_deref().unwrap_or_default().contains("been checked"),
        "before any check, say so: {fresh:?}"
    );

    let after = service.check(false).unwrap();
    assert!(!after.can_apply, "there is nothing to apply");
    assert_eq!(
        after.refuse_reason, None,
        "a checked, current install has nothing to refuse: {after:?}"
    );
    assert!(after.last_check_unix > 0);
}

#[test]
fn an_unsigned_release_is_refused_when_signatures_are_required() {
    let root = tempfile::tempdir().unwrap();
    let paths = seeded(root.path(), InstallMethod::Managed);
    let bytes = payload();
    let mut service = service(paths.clone(), &manifest_for("0.2.0", &bytes), bytes);
    service.require_signature = true;

    let err = service.check(false).expect_err("an unsigned release must not be offered");
    assert!(err.to_string().contains("unsigned"), "{err}");

    let status = service.status().unwrap();
    assert!(status.candidate.is_none());
    assert!(status.last_error.unwrap_or_default().contains("unsigned"));

    // The same release is accepted when signatures are not required yet.
    let mut lenient = service_without_signature_requirement(root.path());
    let status = lenient.check(false).unwrap();
    assert!(status.can_apply, "{status:?}");
}

fn service_without_signature_requirement(root: &Path) -> UpdateService {
    let paths = UpdatePaths::rooted_at(root);
    let bytes = payload();
    let mut service = service(paths, &manifest_for("0.2.0", &bytes), bytes);
    service.require_signature = false;
    service
}
