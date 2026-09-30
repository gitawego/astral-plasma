//! Window identity must be resolved in exactly one place.
//!
//! The initial compositor query, the pushed window list and focus changes each
//! used to call the meta resolver plus the icon extractor themselves. When that
//! drifted, only *some* of the sources attached the app's own `_NET_WM_ICON`, and
//! an X11 app (Proton/Steam games run as `steam_app_default`) showed a generic
//! window glyph in the taskbar until the next window event.

use astral_plasma::application::window_identity::resolve_window_identity;

#[test]
fn every_window_source_uses_the_shared_identity_resolver() {
    let sources = [
        (
            "src/application/watch_events.rs",
            "the pushed window list and focus changes",
        ),
        ("src/infrastructure/kwin_adapter.rs", "the KWin window query"),
        (
            "src/infrastructure/hyprland_adapter.rs",
            "the Hyprland window query",
        ),
    ];

    for (path, what) in sources {
        let source = std::fs::read_to_string(path).unwrap_or_else(|e| panic!("{path}: {e}"));
        assert!(
            source.contains("resolve_window_identity("),
            "{path} ({what}) must resolve identity through window_identity::resolve_window_identity"
        );
        assert!(
            !source.contains("resolve_window_meta_with(Some("),
            "{path} ({what}) resolves identity directly, so it can drift from the other sources"
        );
        assert!(
            !source.contains("window_icons::resolve_window_icon"),
            "{path} ({what}) attaches window icons on its own instead of through the shared resolver"
        );
    }
}

#[test]
fn the_shared_resolver_identifies_a_window_without_any_icon() {
    // `steam_app_default` has no desktop entry and no theme icon, so identity has
    // to come from the class itself. Whether the window's own icon could be read
    // depends on there being an X11 window to read (and a display), so only the
    // identity itself is asserted here - `window_icons` covers the extraction.
    let meta = resolve_window_identity(None, "NTEGame", "steam_app_default", "", "");

    assert_eq!(meta.app_id, "steam_app_default");
    assert_eq!(meta.material_icon, "window");
    assert!(
        meta.icon_name.is_empty() || meta.icon_name.ends_with(".png"),
        "an identity resolves to either a theme name or an extracted icon file, got {:?}",
        meta.icon_name
    );
}

#[test]
fn a_desktop_entry_identity_wins_over_the_window_class() {
    // Index resolution is the application's own declaration; the shared resolver
    // must not replace it with the class name.
    let meta = resolve_window_identity(None, "π - astral-plasma", "com.mitchellh.ghostty", "", "");
    assert_eq!(meta.app_id, "com.mitchellh.ghostty");
}
