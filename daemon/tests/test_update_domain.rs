//! Release discovery rules: what counts as an update, and what must be refused
//! before a single byte is downloaded.

use astral_plasma::domain::update::{
    compare_versions, is_version, select, CandidateView, Channel, IgnoreReason, ReleaseManifest,
    Selection, UpdateCandidate, MAX_ARTIFACT_BYTES,
};
use std::collections::BTreeMap;

fn artifact(url: &str, sha: &str, size: u64) -> astral_plasma::domain::update::Artifact {
    astral_plasma::domain::update::Artifact {
        url: url.to_string(),
        sha256: sha.to_string(),
        size,
    }
}

fn manifest(version: &str, channel: &str) -> ReleaseManifest {
    let mut artifacts = BTreeMap::new();
    artifacts.insert(
        "x86_64".to_string(),
        artifact(
            "https://example.invalid/astral-plasma-linux-x86_64",
            &"a".repeat(64),
            22_000_000,
        ),
    );
    ReleaseManifest {
        schema: 1,
        version: version.to_string(),
        channel: channel.to_string(),
        published_at: Some("2026-11-08T00:00:00Z".to_string()),
        min_quickshell: Some("0.3.0".to_string()),
        highlights: vec!["Something changed".to_string()],
        changelog: Some("https://example.invalid/notes".to_string()),
        artifacts,
    }
}

#[test]
fn a_newer_release_on_the_same_channel_is_an_update() {
    let selection = select(
        &manifest("0.2.0", "stable"),
        "0.1.3",
        Channel::Stable,
        "x86_64",
        Some("0.3.2"),
    );
    let Selection::Available(candidate) = selection else {
        panic!("expected an update, got {selection:?}");
    };
    assert_eq!(candidate.version, "0.2.0");
    assert_eq!(candidate.sha256, "a".repeat(64));
    assert_eq!(candidate.highlights.len(), 1);
    assert_eq!(candidate.view().version, "0.2.0");
    assert_eq!(candidate.size, 22_000_000);
}

#[test]
fn the_same_version_is_not_an_update_and_neither_is_an_older_one() {
    for version in ["0.1.3", "0.1.2"] {
        assert_eq!(
            select(
                &manifest(version, "stable"),
                "0.1.3",
                Channel::Stable,
                "x86_64",
                Some("0.3.2")
            ),
            Selection::UpToDate,
            "{version} must not be offered to a 0.1.3 install"
        );
    }
}

#[test]
fn a_stable_install_never_receives_a_beta_but_a_beta_install_does() {
    assert_eq!(
        select(
            &manifest("0.2.0-beta", "beta"),
            "0.1.3",
            Channel::Stable,
            "x86_64",
            Some("0.3.2")
        ),
        Selection::Ignored(IgnoreReason::Channel)
    );
    assert!(matches!(
        select(
            &manifest("0.2.0-beta", "beta"),
            "0.1.3",
            Channel::Beta,
            "x86_64",
            Some("0.3.2")
        ),
        Selection::Available(_)
    ));
    // Leaving the beta: the stable release supersedes the beta.
    assert!(matches!(
        select(
            &manifest("0.2.0", "stable"),
            "0.2.0-beta",
            Channel::Beta,
            "x86_64",
            Some("0.3.2")
        ),
        Selection::Available(_)
    ));
}

#[test]
fn a_release_without_an_artifact_for_this_architecture_is_ignored() {
    assert_eq!(
        select(
            &manifest("0.2.0", "stable"),
            "0.1.3",
            Channel::Stable,
            "aarch64",
            Some("0.3.2")
        ),
        Selection::Ignored(IgnoreReason::Architecture {
            arch: "aarch64".to_string()
        })
    );
}

#[test]
fn a_release_that_needs_a_newer_quickshell_is_ignored_with_the_numbers() {
    let mut release = manifest("0.2.0", "stable");
    release.min_quickshell = Some("0.4.0".to_string());
    match select(&release, "0.1.3", Channel::Stable, "x86_64", Some("0.3.2")) {
        Selection::Ignored(IgnoreReason::RuntimeFloor { required, running }) => {
            assert_eq!(required, "0.4.0");
            assert_eq!(running.as_deref(), Some("0.3.2"));
        }
        other => panic!("expected a runtime-floor refusal, got {other:?}"),
    }

    // An unknown Quickshell version cannot satisfy a declared floor: installing
    // would risk a shell that cannot parse the bundle.
    assert!(matches!(
        select(&release, "0.1.3", Channel::Stable, "x86_64", None),
        Selection::Ignored(IgnoreReason::RuntimeFloor { .. })
    ));
}

#[test]
fn manifests_are_validated_before_they_can_offer_anything() {
    let good = serde_json::to_vec(&manifest("0.2.0", "stable")).unwrap();
    assert!(ReleaseManifest::parse(&good).is_ok());

    let mut bad_schema = manifest("0.2.0", "stable");
    bad_schema.schema = 99;
    assert!(bad_schema.validate().unwrap_err().to_string().contains("schema"));

    let mut bad_version = manifest("not-a-version", "stable");
    assert!(bad_version.validate().is_err());

    let mut no_artifacts = manifest("0.2.0", "stable");
    no_artifacts.artifacts.clear();
    assert!(no_artifacts.validate().is_err());

    let mut bad_digest = manifest("0.2.0", "stable");
    bad_digest.artifacts.insert("x86_64".into(), artifact("https://x/y", "abc", 10));
    assert!(
        bad_digest.validate().unwrap_err().to_string().contains("sha256"),
        "an artifact without a usable digest can never be verified"
    );

    let mut huge = manifest("0.2.0", "stable");
    huge.artifacts
        .insert("x86_64".into(), artifact("https://x/y", &"b".repeat(64), MAX_ARTIFACT_BYTES + 1));
    assert!(huge.validate().unwrap_err().to_string().contains("bytes"));

    assert!(ReleaseManifest::parse(b"not json").is_err());
}

#[test]
fn unknown_manifest_fields_are_ignored_so_a_newer_release_stays_installable() {
    let mut value = serde_json::to_value(manifest("0.2.0", "stable")).unwrap();
    // A release that still carries the old inline `signature` field - or any
    // future field - must parse: the signature is a detached asset now.
    value["signature"] = serde_json::Value::String("stale-inline-signature".into());
    value["future_field"] = serde_json::Value::Bool(true);
    let release = ReleaseManifest::parse(&serde_json::to_vec(&value).unwrap()).unwrap();
    assert_eq!(release.version, "0.2.0");
}

#[test]
fn version_helpers_are_semver_enough_for_releases() {
    assert!(is_version("0.1.3"));
    assert!(is_version("0.2.0-beta"));
    assert!(!is_version("0.1"));
    assert!(!is_version("v0.1.3"));

    assert_eq!(compare_versions("0.10.0", "0.9.0"), std::cmp::Ordering::Greater);
    assert_eq!(compare_versions("0.2.0-beta", "0.2.0"), std::cmp::Ordering::Less);
    assert_eq!(compare_versions("1.0.0", "1.0.0"), std::cmp::Ordering::Equal);

    // The candidate view is what the shell consumes; keep it flat and stable.
    let view = CandidateView {
        version: "0.2.0".into(),
        highlights: vec!["x".into()],
        changelog: None,
        size: 1,
    };
    let json = serde_json::to_value(&view).unwrap();
    assert_eq!(json["version"], "0.2.0");
    assert!(json.get("sha256").is_none(), "the shell has no use for the digest");
}

#[test]
fn a_candidate_round_trips_through_the_state_cache() {
    let candidate = UpdateCandidate {
        version: "0.2.0".into(),
        channel: "stable".into(),
        highlights: vec!["a".into()],
        changelog: None,
        url: "https://example.invalid/binary".into(),
        sha256: "c".repeat(64),
        size: 10,
    };
    let json = serde_json::to_string(&candidate).unwrap();
    assert_eq!(serde_json::from_str::<UpdateCandidate>(&json).unwrap(), candidate);
}
