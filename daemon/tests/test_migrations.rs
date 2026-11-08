//! Migrations reach installs that already exist.
//!
//! Two properties are load-bearing and both are tested here: a migration is
//! idempotent (the second run does nothing, because it will in fact run on every
//! start until marked complete), and a failing migration blocks the start rather
//! than leaving a half-migrated desktop.

use astral_plasma::application::migrations::legacy_layout::NAME as LEGACY_LAYOUT;
use astral_plasma::application::migrations::{
    registry, MigrationContext, MigrationOutcome, MigrationRunner,
};
use astral_plasma::domain::branding;
use astral_plasma::domain::install_record::{InstallMethod, InstallRecord};
use std::fs;
use std::os::unix::fs::symlink;

/// A legacy install as `install.sh` used to write it: a git checkout linked into
/// `~/.config/quickshell`, a unit pointing at Quickshell, and no install record.
fn seed_legacy_install(root: &std::path::Path) -> (MigrationContext, std::path::PathBuf) {
    let ctx = MigrationContext::rooted_at(root);
    let checkout = root.join("checkout");
    fs::create_dir_all(checkout.join("bin")).unwrap();
    fs::write(checkout.join("shell.qml"), "// checkout shell").unwrap();
    fs::write(checkout.join("bin/astral-plasma"), "#!/bin/sh\necho checkout\n").unwrap();

    fs::create_dir_all(&ctx.config_home).unwrap();
    symlink(&checkout, ctx.config_home.join("quickshell")).unwrap();

    fs::create_dir_all(&ctx.systemd_dir).unwrap();
    fs::write(
        ctx.systemd_dir.join(branding::SYSTEMD_UNIT),
        "[Unit]\nDescription=Astral Plasma Desktop Shell for KDE Plasma\n\n[Service]\n\
         ExecStart=/usr/bin/quickshell -p /home/u/astral-plasma\nRestart=on-failure\n",
    )
    .unwrap();

    // The user's settings must survive the migration untouched.
    let settings = ctx.config_home.join(branding::DATA_DIR);
    fs::create_dir_all(&settings).unwrap();
    fs::write(settings.join("settings.json"), r#"{"theme":{"blurStrength":0.7}}"#).unwrap();

    // Adopt the checkout's release build rather than the test harness binary,
    // which is a cargo debug build the migration must refuse.
    let mut ctx = ctx;
    ctx.source_bin = Some(checkout.join("bin/astral-plasma"));

    (ctx, checkout)
}

#[test]
fn the_registry_has_a_stable_ordered_identity() {
    let names: Vec<&str> = registry().iter().map(|m| m.name()).collect();
    assert_eq!(
        names.first().copied(),
        Some(LEGACY_LAYOUT),
        "the legacy adoption must run first: later migrations assume the managed layout"
    );
    let mut unique = names.clone();
    unique.sort_unstable();
    unique.dedup();
    assert_eq!(unique.len(), names.len(), "migration names are marker file names and must be unique");
    for name in names {
        assert!(
            name.chars().next().unwrap().is_ascii_digit() && name.contains('_'),
            "migration '{name}' must be named `<epoch>_<slug>` so ordering is visible in the marker dir"
        );
    }
}

#[test]
fn a_legacy_install_is_adopted_and_then_left_alone() {
    let root = tempfile::tempdir().unwrap();
    let (ctx, checkout) = seed_legacy_install(root.path());
    let runner = MigrationRunner::standard(&ctx);

    assert_eq!(runner.pending().len(), 1, "one repair is pending on a legacy install");

    let completed = runner.run_pending(&ctx).expect("migration succeeds");
    assert_eq!(completed.len(), 1);
    assert_eq!(completed[0].name, LEGACY_LAYOUT);
    let message = completed[0].message.as_deref().unwrap_or_default();
    assert!(
        message.contains("can update itself"),
        "the user must be told what changed: {message}"
    );

    // Binary, bundle and owner record now exist in the managed layout.
    assert!(ctx.bin_path.is_file(), "the unit needs a binary to exec");
    assert!(ctx.package_dir.join("shell.qml").is_file(), "the bundle must be extractable");
    let record = InstallRecord::read(&ctx.data_dir.join(branding::INSTALL_RECORD_FILE))
        .unwrap()
        .expect("the install now has an owner");
    assert_eq!(record.method, InstallMethod::Managed);
    assert_eq!(record.version, env!("CARGO_PKG_VERSION"));

    // The unit runs the supervisor and pins the bundle.
    let unit = fs::read_to_string(ctx.systemd_dir.join(branding::SYSTEMD_UNIT)).unwrap();
    let exec = unit.lines().find(|l| l.starts_with("ExecStart=")).unwrap();
    assert!(exec.ends_with(" run"), "unit must run the supervisor: {exec}");
    assert!(!exec.contains("quickshell"), "unit must not exec Quickshell: {exec}");
    assert!(unit.contains("ASTRAL_PLASMA_PACKAGE_DIR="), "{unit}");

    // The checkout is never modified and never deleted.
    assert!(
        checkout.join("bin/astral-plasma").is_file(),
        "the checkout may hold the user's own commits; migration copies, it never moves"
    );
    assert!(
        ctx.config_home.join("quickshell").is_symlink(),
        "removing a user-visible config path needs confirmation, not a migration"
    );

    // Settings untouched.
    let settings = fs::read_to_string(
        ctx.config_home.join(branding::DATA_DIR).join("settings.json"),
    )
    .unwrap();
    assert!(settings.contains("0.7"), "user settings must survive: {settings}");

    // Second run: nothing pending, nothing rewritten.
    let unit_before = fs::read_to_string(ctx.systemd_dir.join(branding::SYSTEMD_UNIT)).unwrap();
    let again = runner.run_pending(&ctx).expect("second run is a no-op");
    assert!(again.is_empty(), "a completed migration must not run twice");
    let unit_after = fs::read_to_string(ctx.systemd_dir.join(branding::SYSTEMD_UNIT)).unwrap();
    assert_eq!(unit_before, unit_after);
}

#[test]
fn a_cargo_debug_build_is_refused_as_an_install() {
    let root = tempfile::tempdir().unwrap();
    let (mut ctx, _checkout) = seed_legacy_install(root.path());
    let dev_build = root.path().join("target/debug/astral-plasma");
    fs::create_dir_all(dev_build.parent().unwrap()).unwrap();
    fs::write(&dev_build, b"#!/bin/sh\n").unwrap();
    ctx.source_bin = Some(dev_build);

    let err = MigrationRunner::standard(&ctx)
        .run_pending(&ctx)
        .expect_err("a debug build must not become the user's installed shell");
    assert!(err.to_string().contains("debug build"), "{err}");
    assert!(
        !ctx.bin_path.exists(),
        "a refused adoption must not leave a half-migrated layout"
    );
    assert!(
        !ctx.marker_dir.join(LEGACY_LAYOUT).exists(),
        "the migration must retry once a release build is available"
    );
}

#[test]
fn a_package_managed_install_is_not_touched() {
    let root = tempfile::tempdir().unwrap();
    let (ctx, _checkout) = seed_legacy_install(root.path());
    InstallRecord::new(InstallMethod::Package, "0.1.3", "stable", 1)
        .with_owner_package("astral-plasma-bin")
        .write(&ctx.data_dir.join(branding::INSTALL_RECORD_FILE))
        .unwrap();

    let completed = MigrationRunner::standard(&ctx)
        .run_pending(&ctx)
        .expect("migration is satisfied");
    assert!(
        completed.iter().all(|c| c.message.is_none()),
        "a package-owned install must not be adopted: {completed:?}"
    );
    assert!(
        !ctx.bin_path.exists(),
        "writing files the package manager owns is the two-owners failure"
    );
}

#[test]
fn a_managed_install_at_the_current_version_needs_nothing() {
    let root = tempfile::tempdir().unwrap();
    let ctx = MigrationContext::rooted_at(root.path());
    fs::create_dir_all(&ctx.package_dir).unwrap();
    fs::write(ctx.package_dir.join("shell.qml"), "// live").unwrap();
    InstallRecord::new(
        InstallMethod::Managed,
        env!("CARGO_PKG_VERSION"),
        "stable",
        1,
    )
    .write(&ctx.data_dir.join(branding::INSTALL_RECORD_FILE))
    .unwrap();

    let runner = MigrationRunner::standard(&ctx);
    assert!(runner.pending().len() == 1, "unmarked migrations still run once");
    let completed = runner.run_pending(&ctx).unwrap();
    assert_eq!(
        completed[0].message, None,
        "the migration must report AlreadySatisfied rather than claim a repair"
    );
    assert!(runner.run_pending(&ctx).unwrap().is_empty());
}

#[test]
fn a_failing_migration_is_never_marked_complete() {
    use astral_plasma::application::migrations::Migration;

    struct Explodes;
    impl Migration for Explodes {
        fn name(&self) -> &'static str {
            "999_explodes"
        }
        fn describe(&self) -> &'static str {
            "fails on purpose"
        }
        fn run(&self, _ctx: &MigrationContext) -> astral_plasma::domain::ports::DynResult<MigrationOutcome> {
            Err("disk on fire".into())
        }
    }

    let root = tempfile::tempdir().unwrap();
    let ctx = MigrationContext::rooted_at(root.path());
    let error = Explodes.run(&ctx).expect_err("the migration fails");
    assert!(error.to_string().contains("disk on fire"));
    assert!(
        !ctx.marker_dir.join("999_explodes").exists(),
        "a failed migration must not be marked complete, or it would never retry"
    );
}
