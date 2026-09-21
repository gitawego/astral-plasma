//! Window icons for applications that ship no desktop entry.
//!
//! Wine applications (and other X11 clients without an installed entry) publish
//! their own icon through `_NET_WM_ICON`; that is the only truthful source for
//! their identity. Without it the shell could only show a generic Wine glyph,
//! which is what the taskbar showed after identity resolution became data-driven.

use astral_plasma::infrastructure::window_icons::{
    decode_net_wm_icon, icon_cache_path, should_extract_window_icon,
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
fn only_wine_windows_without_a_real_icon_need_extraction() {
    // Wine class, no desktop-entry icon -> extract the window's own icon.
    assert!(should_extract_window_icon("cloudmusic.exe", "wine"));
    assert!(should_extract_window_icon("cloudmusic.exe", ""));
    // A desktop entry already supplied a real icon: it wins.
    assert!(!should_extract_window_icon("cloudmusic.exe", "netease-cloud-music"));
    // Native apps resolve from their entry and are never touched.
    assert!(!should_extract_window_icon("code", "vscode"));
    assert!(!should_extract_window_icon("ai.opencode.desktop", "ai.opencode.desktop"));
}
