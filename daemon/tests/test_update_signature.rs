//! Signature verification against the committed fixture.
//!
//! The fixture is a manifest signed with the project release key. These cases
//! prove three things that a "signature supported" claim usually hides: the
//! committed public key really verifies the committed signature, a single changed
//! byte does not, and an unsigned release is reported as unsigned rather than
//! silently accepted as signed.

use astral_plasma::infrastructure::update_source::{verify_signature, PINNED_MINISIGN_KEY};
use std::path::PathBuf;

fn repo_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("daemon/ has a parent")
        .to_path_buf()
}

fn fixture(name: &str) -> Vec<u8> {
    let path = repo_root().join("daemon/tests/fixtures").join(name);
    std::fs::read(&path).unwrap_or_else(|err| panic!("cannot read {}: {err}", path.display()))
}

#[test]
fn the_pinned_key_matches_the_published_public_key() {
    let path = repo_root().join("packaging/keys/astral-plasma.pub");
    let published = std::fs::read_to_string(&path)
        .unwrap_or_else(|err| panic!("cannot read {}: {err}", path.display()));
    let key_line = published
        .lines()
        .map(str::trim)
        .find(|line| !line.is_empty() && !line.starts_with("untrusted comment:"))
        .expect("the public key file has a key line");
    assert_eq!(Some(key_line), PINNED_MINISIGN_KEY);
}

#[test]
fn the_signed_fixture_verifies_with_the_pinned_key() {
    let manifest = fixture("signed-manifest.json");
    let signature = String::from_utf8(fixture("signed-manifest.json.minisig")).unwrap();

    let verified = verify_signature(&manifest, &signature, PINNED_MINISIGN_KEY.unwrap())
        .expect("a genuine signature must verify");
    assert!(verified);
}

#[test]
fn one_changed_byte_breaks_the_signature() {
    let manifest = fixture("signed-manifest.json");
    let signature = String::from_utf8(fixture("signed-manifest.json.minisig")).unwrap();

    let mut tampered = manifest.clone();
    let position = tampered
        .windows(5)
        .position(|window| window == b"0.0.1")
        .expect("fixture names its version");
    tampered[position] = b'9';

    let err = verify_signature(&tampered, &signature, PINNED_MINISIGN_KEY.unwrap())
        .expect_err("a changed manifest must not verify");
    assert!(err.to_string().contains("signature"), "{err}");
}

#[test]
fn an_unsigned_release_is_reported_as_unsigned_not_as_verified() {
    let manifest = fixture("signed-manifest.json");
    for empty in ["", "  ", "null"] {
        assert_eq!(
            verify_signature(&manifest, empty, PINNED_MINISIGN_KEY.unwrap()).unwrap(),
            false,
            "'{empty}' is not a signature"
        );
    }
}

#[test]
fn a_malformed_signature_is_an_error_not_a_pass() {
    let manifest = fixture("signed-manifest.json");
    let err = verify_signature(&manifest, "not-a-minisign-signature", PINNED_MINISIGN_KEY.unwrap())
        .expect_err("garbage must be refused");
    assert!(err.to_string().to_lowercase().contains("signature"), "{err}");
}
