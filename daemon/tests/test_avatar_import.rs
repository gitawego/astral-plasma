//! Durable avatar image import contract (Settings > Dashboard avatars).
//!
//! The shell stores avatar images by path (system host card + media tab).
//! Every configured image must be copied into the app config dir so the
//! setting survives deletion of the original source (e.g. a `~/Downloads`
//! cleanup), and only files this feature created may ever be deleted on
//! reset. This suite pins the full pipeline:
//!
//!   1. Pure path pipeline: normalization, boundary-safe dir containment,
//!      target naming (`<kind>-avatar.<ext>`), ownership recognition.
//!   2. Planning: import (copy / keep / reject) and forget (remove / skip).
//!   3. Filesystem execution: real copy round-trip, missing-source fallback
//!      that never stores a failed copy, ownership-guarded deletion.
//!   4. CLI: `config import-image` / `config forget-image` stdout contracts
//!      consumed by `Config.qml`.

use astral_plasma::domain::avatar_import::{
    import_target_path, is_owned_import_path, is_path_in_dir, normalize_local_path, path_extension,
    plan_forget, plan_import, ForgetPlan, ImportPlan, AVATAR_KINDS,
};
use astral_plasma::infrastructure::avatar_fs::{forget_import, import_image};

// ---------------------------------------------------------------------------
// 1. Pure path pipeline
// ---------------------------------------------------------------------------

#[test]
fn normalize_strips_scheme_and_whitespace() {
    assert_eq!(normalize_local_path("  /home/u/pics/gojo.png  "), "/home/u/pics/gojo.png");
    assert_eq!(normalize_local_path("file:///home/u/pics/gojo.png"), "/home/u/pics/gojo.png");
    // Trim happens first, then the scheme: a space after `file://` stays part of the path.
    assert_eq!(normalize_local_path(" file:// /a.png"), " /a.png");
    assert_eq!(normalize_local_path(""), "");
    assert_eq!(normalize_local_path("   "), "");
}

#[test]
fn dir_containment_is_boundary_safe() {
    let dir = "/home/u/.config/astral-plasma";
    assert!(is_path_in_dir("/home/u/.config/astral-plasma/host-avatar.png", dir));
    assert!(is_path_in_dir("/home/u/.config/astral-plasma", dir));
    assert!(is_path_in_dir("file:///home/u/.config/astral-plasma/x.png", dir));
    // Sibling dir sharing the name prefix must NOT match.
    assert!(!is_path_in_dir("/home/u/.config/astral-plasmaEVIL/x.png", dir));
    assert!(!is_path_in_dir("/home/u/Downloads/gojo.png", dir));
    assert!(!is_path_in_dir("", dir));
    assert!(!is_path_in_dir("/any/path", ""));
}

#[test]
fn path_extension_is_lowercased_and_basename_scoped() {
    assert_eq!(path_extension("/home/u/gojo.PNG"), ".png");
    assert_eq!(path_extension("/home/u/archive.tar.GZ"), ".gz");
    assert_eq!(path_extension("/home/u/noext"), "");
    assert_eq!(path_extension("/home/u/.hidden"), ""); // leading dot is not an extension
    assert_eq!(path_extension("/home/u/dir.name/file"), "");
}

#[test]
fn target_path_names_owned_copies() {
    let base = "/home/u/.config/astral-plasma";
    assert_eq!(import_target_path("", "host", base), "");
    assert_eq!(
        import_target_path("/home/u/Downloads/f37dc.png", "host", base),
        format!("{base}/host-avatar.png")
    );
    assert_eq!(
        import_target_path("/home/u/Downloads/gojo.JPG", "media", base),
        format!("{base}/media-avatar.jpg")
    );
    assert_eq!(
        import_target_path("/home/u/noext", "host", base),
        format!("{base}/host-avatar")
    );
    // Already inside: unchanged (no self-copy).
    assert_eq!(
        import_target_path(&format!("{base}/host-avatar.png"), "host", base),
        format!("{base}/host-avatar.png")
    );
}

#[test]
fn ownership_recognizes_only_our_direct_children() {
    let base = "/home/u/.config/astral-plasma";
    assert!(is_owned_import_path(&format!("{base}/host-avatar.png"), base));
    assert!(is_owned_import_path(&format!("{base}/media-avatar.gif"), base));
    assert!(is_owned_import_path(&format!("file://{base}/media-avatar.gif"), base));
    assert!(is_owned_import_path(&format!("{base}/host-avatar"), base)); // extensionless import
    // Anything else in the config dir is off-limits.
    assert!(!is_owned_import_path(&format!("{base}/settings.json"), base));
    assert!(!is_owned_import_path(&format!("{base}/evil-host-avatar.png"), base));
    assert!(!is_owned_import_path(&format!("{base}/sub/host-avatar.png"), base));
    assert!(!is_owned_import_path("/home/u/Downloads/host-avatar.png", base));
    assert!(!is_owned_import_path(base, base)); // the dir itself
}

// ---------------------------------------------------------------------------
// 2. Planning
// ---------------------------------------------------------------------------

#[test]
fn plan_import_copies_keeps_and_rejects() {
    let base = "/cfg";
    // Unknown kind must be rejected (kind is path-influencing input).
    assert!(plan_import("/a.png", "../../etc/passwd", base).is_err());
    assert!(plan_import("/a.png", "wallpaper", base).is_err());
    for kind in AVATAR_KINDS {
        assert!(plan_import("/a.png", kind, base).is_ok());
    }
    // Outside -> copy.
    assert_eq!(
        plan_import("/home/u/gojo.png", "host", base).unwrap(),
        ImportPlan::Copy { from: "/home/u/gojo.png".into(), to: "/cfg/host-avatar.png".into() }
    );
    // Inside -> keep as-is.
    assert_eq!(
        plan_import("/cfg/host-avatar.png", "host", base).unwrap(),
        ImportPlan::Keep("/cfg/host-avatar.png".into())
    );
    // Blank -> keep blank (reset semantics, nothing to copy).
    assert_eq!(plan_import("", "host", base).unwrap(), ImportPlan::Keep(String::new()));
    assert_eq!(plan_import("   ", "media", base).unwrap(), ImportPlan::Keep(String::new()));
}

#[test]
fn plan_forget_only_removes_owned_copies() {
    let base = "/cfg";
    assert_eq!(
        plan_forget("/cfg/media-avatar.png", base),
        ForgetPlan::Remove("/cfg/media-avatar.png".into())
    );
    // User originals and unrelated config files are never removable.
    assert_eq!(plan_forget("/home/u/pics/gojo.png", base), ForgetPlan::Skip);
    assert_eq!(plan_forget("/cfg/settings.json", base), ForgetPlan::Skip);
    assert_eq!(plan_forget("", base), ForgetPlan::Skip);
}

// ---------------------------------------------------------------------------
// 3. Filesystem execution
// ---------------------------------------------------------------------------

#[test]
fn import_copies_real_file_and_reports_target() {
    let tmp = tempfile::tempdir().expect("tmpdir");
    let base = tmp.path().join("cfg").to_string_lossy().to_string();
    let src_dir = tmp.path().join("src");
    std::fs::create_dir_all(&src_dir).unwrap();
    let src = src_dir.join("gojo.png").to_string_lossy().to_string();
    std::fs::write(&src, b"avatar-bytes").unwrap();

    let stored = import_image(&src, "host", &base).expect("import must succeed");
    assert_eq!(stored, format!("{base}/host-avatar.png"));
    let copied = std::fs::read(&stored).expect("imported copy must exist");
    assert_eq!(copied, b"avatar-bytes", "copy must preserve content");
    // Source stays intact (import, not move).
    assert!(std::fs::read(&src).is_ok(), "import must not consume the source");
}

#[test]
fn import_missing_source_falls_back_to_original_path() {
    let tmp = tempfile::tempdir().expect("tmpdir");
    let base = tmp.path().join("cfg").to_string_lossy().to_string();
    let missing = "/definitely/not/here.png";

    let stored = import_image(missing, "host", &base).expect("must not hard-fail");
    assert_eq!(stored, missing, "a failed copy must store the original path");
    assert!(!std::fs::exists(&format!("{base}/host-avatar.png")).unwrap_or(false));
}

#[test]
fn import_missing_source_never_clobbers_existing_copy() {
    let tmp = tempfile::tempdir().expect("tmpdir");
    let base = tmp.path().join("cfg").to_string_lossy().to_string();
    std::fs::create_dir_all(&base).unwrap();
    let good = format!("{base}/host-avatar.png");
    std::fs::write(&good, b"previous-good-copy").unwrap();

    let stored = import_image("/gone/new.png", "host", &base).expect("must not hard-fail");
    assert_eq!(stored, "/gone/new.png");
    assert_eq!(std::fs::read(&good).unwrap(), b"previous-good-copy");
}

#[test]
fn import_in_dir_source_is_a_no_op() {
    let tmp = tempfile::tempdir().expect("tmpdir");
    let base = tmp.path().join("cfg").to_string_lossy().to_string();
    std::fs::create_dir_all(&base).unwrap();
    let existing = format!("{base}/media-avatar.png");
    std::fs::write(&existing, b"keep-me").unwrap();

    let stored = import_image(&existing, "media", &base).expect("in-dir import must succeed");
    assert_eq!(stored, existing, "in-dir source must be stored unchanged");
    assert_eq!(std::fs::read(&existing).unwrap(), b"keep-me");
}

#[test]
fn forget_removes_owned_copy_only() {
    let tmp = tempfile::tempdir().expect("tmpdir");
    let base = tmp.path().join("cfg").to_string_lossy().to_string();
    std::fs::create_dir_all(&base).unwrap();
    let owned = format!("{base}/host-avatar.png");
    let user_file = tmp.path().join("user.png");
    std::fs::write(&owned, b"ours").unwrap();
    std::fs::write(&user_file, b"theirs").unwrap();

    assert!(forget_import(&owned, &base), "owned copy must be removable");
    assert!(!std::fs::exists(&owned).unwrap_or(true));

    let user_str = user_file.to_string_lossy().to_string();
    assert!(!forget_import(&user_str, &base), "user originals must never be removed");
    assert!(std::fs::read(&user_file).is_ok(), "user original must stay intact");

    // Idempotent: forgetting again (already gone) is a harmless no-failure.
    assert!(!forget_import(&owned, &base));
}

// ---------------------------------------------------------------------------
// 4. CLI stdout contract (consumed by Config.qml)
// ---------------------------------------------------------------------------

fn daemon_bin() -> String {
    if let Ok(exe) = std::env::var("CARGO_BIN_EXE_astral-plasma") {
        return exe;
    }
    let manifest_dir = env!("CARGO_MANIFEST_DIR");
    let debug = format!("{manifest_dir}/target/debug/astral-plasma");
    if std::path::Path::new(&debug).exists() {
        return debug;
    }
    format!("{manifest_dir}/../bin/astral-plasma")
}

#[test]
fn cli_import_image_prints_stored_json() {
    let tmp = tempfile::tempdir().expect("tmpdir");
    let base = tmp.path().join("cfg").to_string_lossy().to_string();
    let src_dir = tmp.path().join("dl");
    std::fs::create_dir_all(&src_dir).unwrap();
    let src = src_dir.join("example.png").to_string_lossy().to_string();
    std::fs::write(&src, b"cli-bytes").unwrap();

    let out = std::process::Command::new(daemon_bin())
        .args(["config", "import-image", &src, "host", &base])
        .output()
        .expect("run daemon");
    assert!(out.status.success(), "import-image must exit 0");

    let v: serde_json::Value =
        serde_json::from_str(String::from_utf8_lossy(&out.stdout).trim()).expect("stdout must be JSON");
    assert_eq!(v["success"], true);
    let stored = v["stored"].as_str().expect("stored must be a string path");
    let target = format!("{base}/host-avatar.png");
    assert_eq!(stored, target, "CLI must report the durable copy path");
    assert_eq!(std::fs::read(&target).unwrap(), b"cli-bytes");
}

#[test]
fn cli_import_image_falls_back_to_source_on_missing_file() {
    let tmp = tempfile::tempdir().expect("tmpdir");
    let base = tmp.path().join("cfg").to_string_lossy().to_string();

    let out = std::process::Command::new(daemon_bin())
        .args(["config", "import-image", "/missing/asset.png", "media", &base])
        .output()
        .expect("run daemon");
    assert!(out.status.success());
    let v: serde_json::Value =
        serde_json::from_str(String::from_utf8_lossy(&out.stdout).trim()).expect("stdout must be JSON");
    assert_eq!(v["success"], true);
    assert_eq!(v["stored"], "/missing/asset.png");
}

#[test]
fn cli_forget_image_reports_removal() {
    let tmp = tempfile::tempdir().expect("tmpdir");
    let base = tmp.path().join("cfg").to_string_lossy().to_string();
    std::fs::create_dir_all(&base).unwrap();
    let owned = format!("{base}/media-avatar.gif");
    std::fs::write(&owned, b"ours").unwrap();

    let out = std::process::Command::new(daemon_bin())
        .args(["config", "forget-image", &owned, &base])
        .output()
        .expect("run daemon");
    assert!(out.status.success());
    let v: serde_json::Value =
        serde_json::from_str(String::from_utf8_lossy(&out.stdout).trim()).expect("stdout must be JSON");
    assert_eq!(v["removed"], true);
    assert!(!std::fs::exists(&owned).unwrap_or(true));

    // Foreign path: refused, reported honestly.
    let foreign = tmp.path().join("mine.png");
    std::fs::write(&foreign, b"x").unwrap();
    let out = std::process::Command::new(daemon_bin())
        .args(["config", "forget-image", &foreign.to_string_lossy(), &base])
        .output()
        .expect("run daemon");
    let v: serde_json::Value =
        serde_json::from_str(String::from_utf8_lossy(&out.stdout).trim()).expect("stdout must be JSON");
    assert_eq!(v["removed"], false);
    assert!(std::fs::read(&foreign).is_ok());
}
