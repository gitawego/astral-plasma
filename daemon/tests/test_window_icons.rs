//! Window icons for applications that ship no desktop entry.
//!
//! X11 clients without an installed entry - Wine applications, and Proton/Steam
//! games that run as `steam_app_default` - publish their own icon through
//! `_NET_WM_ICON`; that is the only truthful source for their identity. Without
//! it the shell could only show a generic glyph, which is what the taskbar showed
//! after identity resolution became data-driven.

use astral_plasma::infrastructure::window_icons::{
    decode_net_wm_icon, icon_cache_path, should_extract_window_icon, theme_icon_exists_in,
};

#[test]
fn decodes_the_largest_image_from_net_wm_icon() {
    // Two images in one property: a 1x1 red and a 2x2 blue, both ARGB.
    let data: Vec<u32> = vec![
        1, 1, 0xFFFF0000, //
        2, 2, 0xFF0000FF, 0xFF0000FF, 0xFF0000FF, 0xFF0000FF,
    ];

    let (width, height, rgba) = decode_net_wm_icon(&data).expect("a valid property decodes");

    assert_eq!((width, height), (2, 2), "the largest image wins");
    assert_eq!(rgba.len(), 2 * 2 * 4);
    assert_eq!(&rgba[0..4], &[0x00, 0x00, 0xFF, 0xFF], "ARGB is converted to RGBA");
}

#[test]
fn rejects_truncated_or_degenerate_icon_data() {
    assert!(decode_net_wm_icon(&[]).is_none(), "an empty property has no image");
    assert!(
        decode_net_wm_icon(&[4, 4, 0xFF112233]).is_none(),
        "a pixel count that does not match width*height must be rejected"
    );
    assert!(decode_net_wm_icon(&[0, 0]).is_none(), "a zero-sized image is unusable");
}

#[test]
fn icon_cache_lives_in_the_xdg_cache_and_is_named_after_the_class() {
    let path = icon_cache_path("cloudmusic.exe");
    assert!(
        path.to_string_lossy().contains("window-icons"),
        "icons belong in their own cache subdirectory, got {}",
        path.display()
    );
    assert!(path.to_string_lossy().ends_with("cloudmusic.exe.png"));

    // A hostile class must not escape the cache directory.
    let hostile = icon_cache_path("weird/../../class name");
    assert_eq!(hostile.parent(), path.parent(), "the directory is fixed");
    let hostile_name = hostile.file_name().unwrap().to_string_lossy().to_string();
    assert!(
        !hostile_name.contains('/') && !hostile_name.contains(".."),
        "the file name must not contain separators or traversal, got {hostile_name:?}"
    );
}

#[test]
fn an_x11_window_without_a_drawable_icon_publishes_its_own() {
    // Proton/Steam games run as `steam_app_default`: no `.exe` suffix, no desktop
    // entry, and the resolver hands back the class name as an "icon" no theme can
    // draw. The window's `_NET_WM_ICON` is then the only truthful icon - gating the
    // extraction on a class suffix kept the generic window glyph instead.
    assert!(should_extract_window_icon("steam_app_default"));
    // The generic Wine glyph is not an icon either, and neither is an empty name.
    assert!(should_extract_window_icon("wine"));
    assert!(should_extract_window_icon("WINE"));
    assert!(should_extract_window_icon(""));
    assert!(should_extract_window_icon("   "));
    // Any name the icon theme cannot draw: the resolver guessed.
    assert!(should_extract_window_icon("astral-unresolvable-icon-probe"));
    // A resolved icon file is already drawable: never re-read the window for it.
    assert!(!should_extract_window_icon(
        "/mnt/data/cache/astral-plasma/window-icons/cloudmusic.exe.png"
    ));
    assert!(!should_extract_window_icon("file:///tmp/icon.png"));
}

#[test]
fn only_an_icon_the_theme_can_draw_counts_as_an_icon() {
    let root = std::env::temp_dir().join(format!("astral-icon-probe-{}", std::process::id()));
    let apps = root.join("hicolor/48x48/apps");
    std::fs::create_dir_all(&apps).expect("probe icon dir");
    std::fs::write(apps.join("real-app.png"), b"png").expect("probe icon");
    std::fs::write(apps.join("symbolic-app-symbolic.svg"), b"svg").expect("probe icon");
    std::fs::write(apps.join("notes.txt"), b"not an icon").expect("probe file");
    let roots = vec![root.clone()];

    assert!(theme_icon_exists_in(&roots, "real-app"), "a themed png is drawable");
    assert!(
        theme_icon_exists_in(&roots, "symbolic-app"),
        "a symbolic variant belongs to the icon it names"
    );
    assert!(!theme_icon_exists_in(&roots, "missing-app"), "an absent name is not an icon");
    assert!(
        !theme_icon_exists_in(&roots, "notes"),
        "a non-image file must not count as an icon"
    );
    assert!(!theme_icon_exists_in(&roots, ""));
    assert!(!theme_icon_exists_in(&roots, "../../etc/passwd"), "no path traversal");

    std::fs::remove_dir_all(&root).ok();
}
