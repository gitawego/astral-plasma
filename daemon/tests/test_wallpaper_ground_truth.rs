//! The picker must focus the wallpaper the desktop actually shows.
//!
//! `WallpaperEngine.currentWallpaper` comes from `astral-plasma wallpaper get`,
//! and the picker scrolls to that card when it opens. `get` used to answer from
//! the shell's own state file first, which is only the last path the shell
//! *wrote*: whenever the desktop's wallpaper was changed outside the shell (or
//! an apply silently failed) the two drifted apart, and the picker focused a
//! wallpaper that was not on screen at all.
//!
//! The applied wallpaper - the desktop containment's image in KDE's
//! `plasma-org.kde.plasma.desktop-appletsrc` - is therefore the ground truth,
//! with the state file kept as the fallback for sessions that have no Plasma
//! desktop.

use astral_plasma::domain::wallpaper::WallpaperPort;
use astral_plasma::infrastructure::fs_wallpaper::{
    desktop_wallpaper_from_appletsrc, plasma_wallpaper_script, FsWallpaperAdapter,
};
use std::fs;
use std::path::Path;
use tempfile::tempdir;

/// A realistic appletsrc: one desktop containment plus a panel that carries its
/// own `wallpaperplugin` (panels do have one, and it must never be mistaken for
/// the desktop's wallpaper).
fn appletsrc(desktop_image: &str, panel_image: Option<&str>) -> String {
    let mut content = String::from(
        "[ActionPlugins][0]\n\
         MiddleButton;NoModifier=org.kde.paste\n\
         \n\
         [Containments][169]\n\
         activityId=12b3a111-1f92-40de-954a-00d68f430a00\n\
         formfactor=0\n\
         location=0\n\
         plugin=org.kde.plasma.folder\n\
         wallpaperplugin=org.kde.image\n",
    );
    content.push_str(&format!(
        "\n[Containments][169][Wallpaper][org.kde.image][General]\nImage={desktop_image}\n"
    ));
    content.push_str(
        "\n[Containments][282]\n\
         formfactor=2\n\
         location=3\n\
         plugin=org.kde.panel\n\
         wallpaperplugin=org.kde.image\n",
    );
    if let Some(image) = panel_image {
        content.push_str(&format!(
            "\n[Containments][282][Wallpaper][org.kde.image][General]\nImage={image}\n"
        ));
    }
    content
}

#[test]
fn the_desktop_containment_owns_the_wallpaper() {
    let content = appletsrc("file:///usr/share/wallpapers/Abstract.png", None);
    assert_eq!(
        desktop_wallpaper_from_appletsrc(&content),
        Some("/usr/share/wallpapers/Abstract.png".into()),
        "the containment image is the applied wallpaper, with `file://` stripped"
    );
}

#[test]
fn a_panels_image_never_wins() {
    let content = appletsrc(
        "file:///usr/share/wallpapers/Abstract.png",
        Some("file:///home/user/panel-decoration.png"),
    );
    assert_eq!(
        desktop_wallpaper_from_appletsrc(&content),
        Some("/usr/share/wallpapers/Abstract.png".into()),
        "only the desktop containment (plugin=org.kde.plasma.folder) carries the wallpaper"
    );
}

#[test]
fn a_config_without_a_recognised_desktop_still_answers() {
    // Older or hand-written configs may not declare the containment plugin; the
    // parser must still find the wallpaper instead of dropping to the state.
    let content = "[Containments][1][Wallpaper][org.kde.image][General]\nImage=/tmp/legacy.png\n";
    assert_eq!(
        desktop_wallpaper_from_appletsrc(content),
        Some("/tmp/legacy.png".into())
    );
}

#[test]
fn a_config_without_a_wallpaper_answers_nothing() {
    let content = "[Containments][169]\nplugin=org.kde.plasma.folder\n";
    assert_eq!(desktop_wallpaper_from_appletsrc(content), None);
    assert_eq!(
        desktop_wallpaper_from_appletsrc(
            "[Containments][169][Wallpaper][org.kde.image][General]\nImage=\n"
        ),
        None,
        "an empty Image= is not a wallpaper"
    );
}

#[test]
fn the_applied_wallpaper_wins_over_the_state_file() {
    // This is the reported bug: the shell had applied one wallpaper, the desktop
    // was showing another, and the picker focused the stale state.
    let home = tempdir().unwrap();
    let config_dir = home.path().join(".config");
    fs::create_dir_all(&config_dir).unwrap();

    let applied = home.path().join("applied.png");
    let stale = home.path().join("stale.png");
    fs::write(&applied, b"x").unwrap();
    fs::write(&stale, b"x").unwrap();

    let state_file = home.path().join("state.txt");
    fs::write(&state_file, format!("{}\n", stale.display())).unwrap();
    fs::write(
        config_dir.join("plasma-org.kde.plasma.desktop-appletsrc"),
        appletsrc(&format!("file://{}", applied.display()), None),
    )
    .unwrap();

    let adapter = FsWallpaperAdapter::with_paths(home.path().to_path_buf(), state_file);
    assert_eq!(
        adapter.get_active_wallpaper().unwrap(),
        Some(applied),
        "the picker must focus the wallpaper that is on screen, not the last one the shell wrote"
    );
}

#[test]
fn the_state_file_is_the_fallback() {
    let home = tempdir().unwrap();
    let wall = home.path().join("mine.png");
    fs::write(&wall, b"x").unwrap();

    let state_file = home.path().join("state.txt");
    fs::write(&state_file, format!("{}\n", wall.display())).unwrap();

    let adapter = FsWallpaperAdapter::with_paths(home.path().to_path_buf(), state_file);
    assert_eq!(
        adapter.get_active_wallpaper().unwrap(),
        Some(wall),
        "a session without a Plasma desktop still remembers the shell's wallpaper"
    );
}

#[test]
fn a_missing_applied_file_falls_back_to_the_state() {
    let home = tempdir().unwrap();
    let config_dir = home.path().join(".config");
    fs::create_dir_all(&config_dir).unwrap();

    let wall = home.path().join("mine.png");
    fs::write(&wall, b"x").unwrap();
    let state_file = home.path().join("state.txt");
    fs::write(&state_file, format!("{}\n", wall.display())).unwrap();

    // Plasma still points at a wallpaper that has since been deleted.
    fs::write(
        config_dir.join("plasma-org.kde.plasma.desktop-appletsrc"),
        appletsrc("file:///usr/share/wallpapers/Deleted.png", None),
    )
    .unwrap();

    let adapter = FsWallpaperAdapter::with_paths(home.path().to_path_buf(), state_file);
    assert_eq!(adapter.get_active_wallpaper().unwrap(), Some(wall));
}

#[test]
fn the_plasma_script_writes_the_image_for_every_desktop() {
    let script = plasma_wallpaper_script(Path::new("/usr/share/wallpapers/My Wallpaper/图.png"));

    assert!(
        script.contains(r#"writeConfig("Image", "file:///usr/share/wallpapers/My Wallpaper/图.png")"#),
        "the script must write the containment's image, got: {script}"
    );
    assert!(script.contains("desktops()"), "it must cover every desktop");
    assert!(
        script.contains(r#"wallpaperPlugin = "org.kde.image""#),
        "the image plugin must be selected explicitly"
    );

    // A quote in the path must not break out of the JS string literal.
    let quoted = plasma_wallpaper_script(Path::new("/tmp/a\"b.png"));
    assert!(
        quoted.contains(r#"writeConfig("Image", "file:///tmp/a\"b.png")"#),
        "paths must be escaped as JS string literals, got: {quoted}"
    );
}

#[test]
fn the_cli_answers_scripts_with_a_bare_path() {
    use astral_plasma::application::wallpaper_service::ActiveWallpaperUseCase;

    let path = Path::new("/usr/share/wallpapers/My Wallpaper.png");

    // `--raw` is what the palette generator reads: a bare path, no JSON.
    assert_eq!(
        ActiveWallpaperUseCase::format(Some(path), true),
        "/usr/share/wallpapers/My Wallpaper.png"
    );
    assert_eq!(ActiveWallpaperUseCase::format(None, true), "");

    // The shell keeps the JSON interface.
    let json: serde_json::Value =
        serde_json::from_str(&ActiveWallpaperUseCase::format(Some(path), false)).unwrap();
    assert_eq!(json["path"], "/usr/share/wallpapers/My Wallpaper.png");
    let empty: serde_json::Value =
        serde_json::from_str(&ActiveWallpaperUseCase::format(None, false)).unwrap();
    assert!(empty["path"].is_null(), "no wallpaper is reported as null, not as a bogus path");
}

#[test]
fn a_kde_wallpaper_package_is_named_after_the_package() {
    use astral_plasma::domain::wallpaper::Wallpaper;

    let dir = tempdir().unwrap();
    let images = dir.path().join("Air").join("contents").join("images");
    fs::create_dir_all(&images).unwrap();
    let variant = images.join("5120x2880.png");
    fs::write(&variant, b"x").unwrap();

    // Whatever scan root the file is discovered from (or applied from), the
    // card is the wallpaper, not the resolution variant.
    let from_parent = Wallpaper::from_file(&variant, &images, None);
    assert_eq!(from_parent.name, "Air");
    assert_eq!(from_parent.category, "Air");

    let from_root = Wallpaper::from_file(&variant, dir.path(), None);
    assert_eq!(from_root.name, "Air", "the scan root must not change the identity");

    // Loose images keep their own name.
    let loose = dir.path().join("Abstract.png");
    fs::write(&loose, b"x").unwrap();
    let loose_wall = Wallpaper::from_file(&loose, dir.path(), None);
    assert_eq!(loose_wall.name, "Abstract");
    assert_eq!(loose_wall.category, "General");
}

#[test]
fn the_pickers_choice_wins_when_plasma_reverts_the_wallpaper() {
    use astral_plasma::infrastructure::fs_wallpaper::{reconcile_decision, WallpaperReconcile};

    let chosen = Path::new("/usr/share/wallpapers/Abstract.png");
    let reverted = Path::new("/usr/share/wallpapers/Air/contents/images/5120x2880.png");

    // A plasmashell restart rewrote the containment config from its own saved
    // state: the wallpaper the user picked must go back on the desktop.
    assert_eq!(
        reconcile_decision(Some(reverted), Some(chosen)),
        WallpaperReconcile::ApplyState(chosen.to_path_buf())
    );

    // The desktop has a wallpaper but the shell has no record of one (fresh
    // install, first run): follow the desktop instead of fighting it.
    assert_eq!(
        reconcile_decision(Some(reverted), None),
        WallpaperReconcile::AdoptApplied(reverted.to_path_buf())
    );

    // The shell remembers one but the desktop has none: apply it.
    assert_eq!(
        reconcile_decision(None, Some(chosen)),
        WallpaperReconcile::ApplyState(chosen.to_path_buf())
    );

    // Already in agreement (and nothing to do at all).
    assert_eq!(
        reconcile_decision(Some(chosen), Some(chosen)),
        WallpaperReconcile::AdoptApplied(chosen.to_path_buf())
    );
    assert_eq!(reconcile_decision(None, None), WallpaperReconcile::Nothing);
}

#[test]
fn reconciling_adopts_the_desktop_wallpaper_when_the_shell_has_none() {
    let home = tempdir().unwrap();
    let config_dir = home.path().join(".config");
    fs::create_dir_all(&config_dir).unwrap();

    let desktop_wall = home.path().join("desktop.png");
    fs::write(&desktop_wall, b"x").unwrap();
    fs::write(
        config_dir.join("plasma-org.kde.plasma.desktop-appletsrc"),
        appletsrc(&format!("file://{}", desktop_wall.display()), None),
    )
    .unwrap();

    let state_file = home.path().join("state.txt");
    let adapter = FsWallpaperAdapter::with_paths(home.path().to_path_buf(), state_file.clone());

    assert_eq!(
        adapter.reconcile_active_wallpaper().unwrap(),
        Some(desktop_wall.clone()),
        "a session with no shell choice follows the desktop"
    );
    assert_eq!(
        fs::read_to_string(&state_file).unwrap().trim(),
        desktop_wall.to_string_lossy(),
        "and the state file records it, so the picker focuses it"
    );
}

#[test]
fn the_plasma_apply_goes_through_qdbus() {
    use astral_plasma::infrastructure::fs_wallpaper::plasma_apply_command;

    let (program, args) = plasma_apply_command(Path::new("/w/x.png"));
    assert_eq!(program, "qdbus6");
    assert_eq!(args[0], "org.kde.plasmashell");
    assert_eq!(args[1], "/PlasmaShell");
    assert_eq!(args[2], "org.kde.PlasmaShell.evaluateScript");
    assert!(
        args[3].contains(r#"writeConfig("Image", "file:///w/x.png")"#),
        "the script must carry the image, got: {}",
        args[3]
    );
}

#[test]
fn applying_a_wallpaper_survives_a_session_without_plasma_tools() {
    // The apply is best-effort: with no Plasma tooling around it must still
    // record the choice and return, never abort. (It used to panic - a blocking
    // D-Bus client started from inside the CLI's async runtime.)
    let state_home = tempdir().unwrap();
    let wall = state_home.path().join("wall.png");
    fs::write(&wall, b"x").unwrap();

    let output = std::process::Command::new(cli_binary())
        .args(["wallpaper", "set", wall.to_str().unwrap()])
        .env("PATH", "")
        .env("HOME", state_home.path())
        .env("XDG_STATE_HOME", state_home.path())
        .env("XDG_CONFIG_HOME", state_home.path())
        .output()
        .expect("run `astral-plasma wallpaper set`");

    assert!(
        output.status.success(),
        "applying a wallpaper must stay best-effort, got {:?}: {}",
        output.status,
        String::from_utf8_lossy(&output.stderr)
    );

    let recorded = fs::read_to_string(state_home.path().join("astral-plasma/wallpaper/path.txt"))
        .expect("the state file must be written");
    assert_eq!(recorded.trim(), wall.to_str().unwrap());
}

fn cli_binary() -> std::path::PathBuf {
    if let Ok(exe) = std::env::var("CARGO_BIN_EXE_astral-plasma") {
        return exe.into();
    }
    let manifest_dir = std::path::Path::new(env!("CARGO_MANIFEST_DIR"));
    let debug = manifest_dir.join("target/debug/astral-plasma");
    if debug.exists() {
        return debug;
    }
    manifest_dir.join("../bin/astral-plasma")
}
