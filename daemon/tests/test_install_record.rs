//! The install record is the only thing that decides whether this daemon may
//! replace the files it is running from. A record that cannot be read is not the
//! same as no record: granting update permission to an unknown owner is how a
//! self-updater ends up overwriting a package manager's files.

use astral_plasma::domain::branding;
use astral_plasma::domain::install_record::{self, InstallMethod, InstallRecord};

#[test]
fn a_record_round_trips_through_disk() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join(branding::INSTALL_RECORD_FILE);

    let record = InstallRecord::new(InstallMethod::Managed, "0.2.0", "stable", 1_760_000_000);
    record.write(&path).unwrap();

    let read = InstallRecord::read(&path).unwrap().expect("record exists");
    assert_eq!(read, record);
    assert_eq!(read.schema, branding::INSTALL_RECORD_SCHEMA);
}

#[test]
fn a_missing_record_is_none_not_an_error() {
    let dir = tempfile::tempdir().unwrap();
    let read = InstallRecord::read(&dir.path().join("install.json")).unwrap();
    assert!(read.is_none(), "a checkout or legacy install has no record yet");
}

#[test]
fn writing_is_atomic_and_leaves_no_temporary_file() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join(branding::INSTALL_RECORD_FILE);
    InstallRecord::new(InstallMethod::Managed, "0.2.0", "stable", 1)
        .write(&path)
        .unwrap();

    let leftovers: Vec<_> = std::fs::read_dir(dir.path())
        .unwrap()
        .flatten()
        .map(|e| e.file_name().to_string_lossy().to_string())
        .filter(|name| name != branding::INSTALL_RECORD_FILE)
        .collect();
    assert!(leftovers.is_empty(), "left temporary files: {leftovers:?}");
}

#[test]
fn a_malformed_record_is_an_error_and_never_a_default() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join(branding::INSTALL_RECORD_FILE);
    std::fs::write(&path, r#"{"schema":1,"method":"sideloaded""#).unwrap();

    let err = InstallRecord::read(&path).expect_err("truncated record must fail");
    assert!(
        err.to_string().contains("not a valid install record"),
        "the error must name the file and the reason: {err}"
    );
}

#[test]
fn an_unknown_method_is_refused_rather_than_guessed() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join(branding::INSTALL_RECORD_FILE);
    std::fs::write(
        &path,
        r#"{"schema":1,"method":"sideloaded","version":"0.2.0","channel":"stable","installed_at_unix":1}"#,
    )
    .unwrap();

    let err = InstallRecord::read(&path).expect_err("unknown method must fail");
    assert!(
        err.to_string().contains("sideloaded"),
        "the error must name the bad value: {err}"
    );
}

#[test]
fn only_a_managed_install_may_update_itself() {
    assert!(InstallMethod::Managed.is_self_updatable());
    assert!(
        !InstallMethod::Package.is_self_updatable(),
        "a package-managed install belongs to pacman; writing its files is the two-owners bug"
    );
    assert!(!InstallMethod::Checkout.is_self_updatable());

    assert_eq!(InstallMethod::parse("managed").unwrap(), InstallMethod::Managed);
    assert_eq!(InstallMethod::parse(" package ").unwrap(), InstallMethod::Package);
    assert_eq!(InstallMethod::parse("checkout").unwrap(), InstallMethod::Checkout);
    assert!(InstallMethod::parse("").is_err());
}

#[test]
fn a_future_schema_is_refused() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join(branding::INSTALL_RECORD_FILE);
    let mut record = InstallRecord::new(InstallMethod::Managed, "0.2.0", "stable", 1);
    record.schema = 99;

    let err = record.write(&path).expect_err("a newer schema must not be written");
    assert!(err.to_string().contains("schema"), "{err}");
}

#[test]
fn the_owner_package_survives_a_round_trip() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join(branding::INSTALL_RECORD_FILE);
    InstallRecord::new(InstallMethod::Package, "0.2.0", "stable", 1)
        .with_owner_package("astral-plasma-bin")
        .write(&path)
        .unwrap();

    let read = InstallRecord::read(&path).unwrap().unwrap();
    assert_eq!(read.owner_package.as_deref(), Some("astral-plasma-bin"));
}

#[test]
fn install_time_renders_as_iso8601_utc() {
    assert_eq!(install_record::iso8601_utc(0), "1970-01-01T00:00:00Z");
    // 2024-02-29T12:34:56Z - a leap day, which is where hand-rolled date math
    // usually breaks.
    assert_eq!(
        install_record::iso8601_utc(1_709_210_096),
        "2024-02-29T12:34:56Z"
    );
    // 2026-11-08T00:00:00Z
    assert_eq!(
        install_record::iso8601_utc(1_794_096_000),
        "2026-11-08T00:00:00Z"
    );
    assert!(install_record::now_unix() > 1_600_000_000);
}

/// The app platform writes one of these per app (`apps/<id>/install.json`,
/// APPS-PLATFORM-SPEC §11.1). A product record and an app record must share one
/// schema today, or the platform's first migration is a rewrite of every install.
#[test]
fn an_app_record_extends_the_same_schema() {
    use astral_plasma::domain::install_record::TrustLevel;

    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("install.json");
    InstallRecord::new(InstallMethod::Package, "0.1.0", "stable", 5)
        .with_owner_package("community-catalog")
        .with_app_details(
            "d".repeat(64),
            TrustLevel::Community,
            Some("minisign:abc".to_string()),
            vec!["session.read".to_string()],
        )
        .write(&path)
        .unwrap();

    let read = InstallRecord::read(&path).unwrap().unwrap();
    assert_eq!(read.digest.as_deref(), Some("d".repeat(64).as_str()));
    assert_eq!(read.trust, Some(TrustLevel::Community));
    assert_eq!(read.grants, vec!["session.read".to_string()]);

    // A product record does not grow app fields on disk.
    let product = dir.path().join("product.json");
    InstallRecord::new(InstallMethod::Managed, "0.1.3", "stable", 5)
        .write(&product)
        .unwrap();
    let body = std::fs::read_to_string(&product).unwrap();
    assert!(!body.contains("digest"), "{body}");
    assert!(!body.contains("grants"), "{body}");
}
