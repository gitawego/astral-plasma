//! Data-driven window identity: every window is identified by the same,
//! app-agnostic sources of truth the rest of the desktop uses.
//!
//! Precedence, and nothing else:
//!   1. The installed XDG desktop entry that declares this window's
//!      `StartupWMClass` (or whose id equals the window's app id) - exactly the
//!      lookup Plasma's own taskbar performs.
//!   2. For Wine executables with no entry: the window's own class name.
//!
//! There is deliberately no per-application table in these tests: a new app
//! must work by being installed, not by being added to a list in this repo.

use astral_plasma::domain::app_identity::{AppIdentityIndex, DesktopApp};
use astral_plasma::domain::meta_resolver::resolve_window_meta_with;
use std::fs;


fn entry(desktop_id: &str, name: &str, icon: &str, wm_class: Option<&str>, material: &str) -> DesktopApp {
    DesktopApp {
        desktop_id: desktop_id.to_string(),
        name: name.to_string(),
        icon: icon.to_string(),
        wm_class: wm_class.map(str::to_string),
        material_icon: material.to_string(),
        comment: String::new(),
        exec: String::new(),
    }
}

// ============================================================================
// 1. The reported regression: OpenCode
// ============================================================================

#[test]
fn a_window_resolves_from_the_desktop_entry_it_declares() {
    // /usr/share/applications/ai.opencode.desktop.desktop:
    //   Name=OpenCode  Icon=ai.opencode.desktop
    //   StartupWMClass=ai.opencode.desktop  Categories=Development;
    let index = AppIdentityIndex::from_entries(vec![entry(
        "ai.opencode.desktop",
        "OpenCode",
        "ai.opencode.desktop",
        Some("ai.opencode.desktop"),
        "code",
    )]);

    let meta = resolve_window_meta_with(
        Some(&index),
        "OpenCode",
        "ai.opencode.desktop",
        "ai.opencode.desktop",
        "",
    );

    assert_eq!(meta.app_name, "OpenCode", "the entry's Name= is the display name");
    assert_eq!(meta.icon_name, "ai.opencode.desktop", "the entry's Icon= is the icon");
    assert_eq!(meta.app_id, "ai.opencode.desktop");
    assert_eq!(meta.material_icon, "code", "the Development category supplies the glyph");
}

#[test]
fn nothing_built_in_may_override_installed_data() {
    // A class that some hand-written heuristic might recognise must still be
    // identified by the desktop entry that actually owns the window.
    let index = AppIdentityIndex::from_entries(vec![entry(
        "code",
        "VSCodium",
        "vscodium",
        Some("code"),
        "code",
    )]);

    let meta = resolve_window_meta_with(Some(&index), "VSCodium", "code", "code", "");
    assert_eq!(meta.app_name, "VSCodium");
    assert_eq!(meta.icon_name, "vscodium");

    // And the mirror case: a class containing a well-known word must not be
    // attributed to that word's application when no entry matches.
    let index = AppIdentityIndex::from_entries(vec![entry(
        "ai.opencode.desktop",
        "OpenCode",
        "ai.opencode.desktop",
        Some("ai.opencode.desktop"),
        "code",
    )]);
    let unrelated = resolve_window_meta_with(Some(&index), "Some Editor", "opencode", "opencode", "");
    assert_ne!(unrelated.app_id, "ai.opencode.desktop");
    assert_ne!(unrelated.app_name, "Antigravity");
}

// ============================================================================
// 2. Wine executables resolve through the same index
// ============================================================================

#[test]
fn a_wine_exe_class_matches_an_entry_that_declares_it() {
    // Lutris/Wine-generated entries declare the executable as StartupWMClass:
    //   StartupWMClass=ntelauncher.exe
    let index = AppIdentityIndex::from_entries(vec![entry(
        "启动异环",
        "异环",
        "ntelauncher",
        Some("ntelauncher.exe"),
        "sports_esports",
    )]);

    let meta = resolve_window_meta_with(Some(&index), "异环", "ntelauncher.exe", "", "");
    assert_eq!(meta.app_name, "异环");
    assert_eq!(meta.icon_name, "ntelauncher");
    assert_eq!(meta.app_id, "启动异环");
}

#[test]
fn a_wine_exe_class_matches_a_desktop_entry_id_by_stem() {
    // Entries that forgot StartupWMClass are still reachable: Wine reports the
    // executable, the desktop entry is named after it.
    let index = AppIdentityIndex::from_entries(vec![entry(
        "notepad",
        "Notepad",
        "notepad",
        None,
        "description",
    )]);

    let meta = resolve_window_meta_with(Some(&index), "Notepad", "notepad.exe", "", "");
    assert_eq!(meta.app_name, "Notepad");
    assert_eq!(meta.icon_name, "notepad");
}

#[test]
fn a_wine_class_without_extension_matches_an_entry_that_declares_the_exe() {
    let index = AppIdentityIndex::from_entries(vec![entry(
        "cloudmusic",
        "NetEase Cloud Music",
        "netease-cloud-music",
        Some("cloudmusic.exe"),
        "music_note",
    )]);

    // Some Wine builds report the class with the extension, some without.
    let meta = resolve_window_meta_with(Some(&index), "网易云音乐", "cloudmusic", "", "");
    assert_eq!(meta.app_name, "NetEase Cloud Music");
    assert_eq!(meta.icon_name, "netease-cloud-music");
}

#[test]
fn a_wine_window_without_any_entry_uses_its_own_executable_name() {
    let index = AppIdentityIndex::from_entries(vec![]);

    let meta = resolve_window_meta_with(Some(&index), "任何标题", "cloudmusic.exe", "", "");
    assert_eq!(meta.app_name, "Cloudmusic", "the executable names the window");
    assert_eq!(meta.icon_name, "wine", "a real, theme-provided icon");
    assert_eq!(meta.material_icon, "window");
    assert_eq!(meta.app_id, "cloudmusic");
    assert_eq!(meta.desktop_file, "cloudmusic");
}

#[test]
fn a_native_window_without_any_entry_uses_its_own_identity() {
    let index = AppIdentityIndex::from_entries(vec![]);

    let meta = resolve_window_meta_with(Some(&index), "Foo — some-app", "some-app", "some-app", "");
    assert_eq!(meta.app_id, "some-app");
    assert_eq!(meta.icon_name, "some-app");
    assert_eq!(meta.material_icon, "window");
}

// ============================================================================
// 3. Index scanning covers the directories Wine actually uses
// ============================================================================

#[test]
fn index_scanning_is_recursive_so_nested_wine_entries_are_found() {
    let root = std::env::temp_dir().join(format!("astral_identity_scan_{}", std::process::id()));
    let nested = root.join("wine/Programs/Some App");
    fs::create_dir_all(&nested).unwrap();
    fs::write(
        nested.join("Some App.desktop"),
        "[Desktop Entry]\nType=Application\nName=Some App\nIcon=some-app\nStartupWMClass=someapp.exe\nCategories=Game;\n",
    )
    .unwrap();
    // A hidden directory must never be scanned.
    fs::create_dir_all(root.join(".git")).unwrap();
    fs::write(
        root.join(".git/app.desktop"),
        "[Desktop Entry]\nType=Application\nName=Hidden\n",
    )
    .unwrap();

    let index = AppIdentityIndex::load_from(&[root.clone()]);

    assert_eq!(index.resolve("someapp.exe", "").unwrap().name, "Some App");
    assert!(index.resolve("hidden", "").is_none());

    let _ = fs::remove_dir_all(&root);
}

// ============================================================================
// 4. Tray identity is the SNI's own data, completed by its desktop entry
// ============================================================================

#[test]
fn tray_never_fabricates_a_title_or_icon() {
    use astral_plasma::infrastructure::tray_adapter::TrayAdapter;

    let (title, icon, glyph) = TrayAdapter::resolve_tray_meta_with(None, "my-app-id", "", "");
    assert_eq!(title, "my-app-id", "an untitled item is named by its own id");
    assert_eq!(icon, "", "no icon may be invented");
    assert_eq!(glyph, "circle", "the generic fallback glyph");
}

#[test]
fn tray_prefers_its_own_icon_and_uses_the_desktop_entry_when_missing() {
    use astral_plasma::infrastructure::tray_adapter::TrayAdapter;

    let index = AppIdentityIndex::from_entries(vec![entry(
        "dropbox",
        "Dropbox",
        "dropboxstatus-idle",
        None,
        "cloud",
    )]);

    // The SNI's own icon always wins.
    let (_, icon, glyph) =
        TrayAdapter::resolve_tray_meta_with(Some(&index), "dropbox", "Dropbox", "file:///tmp/tray.png");
    assert_eq!(icon, "file:///tmp/tray.png");
    assert_eq!(glyph, "cloud");

    // With no icon of its own, the desktop entry supplies one.
    let (title, icon, glyph) = TrayAdapter::resolve_tray_meta_with(Some(&index), "dropbox", "", "");
    assert_eq!(title, "dropbox");
    assert_eq!(icon, "dropboxstatus-idle");
    assert_eq!(glyph, "cloud");
}

#[test]
fn tray_icon_names_are_single_tokens() {
    use astral_plasma::infrastructure::tray_adapter::TrayAdapter;

    let (_, icon, _) =
        TrayAdapter::resolve_tray_meta_with(None, "some-item", "Some Item", "some icon name");
    assert!(!icon.contains(' '), "icon names must be a single token: {icon:?}");
}

// ============================================================================
// 5. The application list and the launch path use the same data
// ============================================================================

#[test]
fn app_list_entries_carry_the_full_desktop_entry_data() {
    use astral_plasma::infrastructure::launcher::app_info_from_entry;

    let app = DesktopApp {
        desktop_id: "ai.opencode.desktop".to_string(),
        name: "OpenCode".to_string(),
        icon: "ai.opencode.desktop".to_string(),
        wm_class: Some("ai.opencode.desktop".to_string()),
        material_icon: "code".to_string(),
        comment: "OpenCode desktop".to_string(),
        exec: "opencode-desktop %U".to_string(),
    };

    let info = app_info_from_entry(&app);
    assert_eq!(info.name, "OpenCode");
    assert_eq!(info.desktop_file, "ai.opencode.desktop.desktop");
    assert_eq!(info.icon, "ai.opencode.desktop");
    assert_eq!(info.comment, "OpenCode desktop");
    assert_eq!(info.exec, "opencode-desktop %U");
}

#[test]
fn launching_is_decided_by_the_target_kind_not_by_the_app_name() {
    use astral_plasma::infrastructure::launcher::{resolve_launch_plan, LaunchPlan};

    // Every desktop id goes through the same resolver, whether or not this
    // repository has ever heard of the application.
    for id in ["ai.opencode.desktop", "be.alexandervanhee.gradia", "code", "org.kde.dolphin"] {
        assert_eq!(
            resolve_launch_plan(id),
            Some(LaunchPlan::DesktopEntry(id.to_string())),
            "{id} must be launched as a desktop entry"
        );
    }
    // Targeted passed through verbatim, including a trailing `.desktop`.
    assert_eq!(
        resolve_launch_plan("  ai.opencode.desktop.desktop  "),
        Some(LaunchPlan::DesktopEntry("ai.opencode.desktop.desktop".to_string()))
    );

    // A URI scheme is a protocol, not application knowledge.
    assert_eq!(
        resolve_launch_plan("lutris:rungame/whatever-game"),
        Some(LaunchPlan::Uri("lutris:rungame/whatever-game".to_string()))
    );

    assert_eq!(resolve_launch_plan("   "), None);
}

#[test]
fn xembed_tray_items_are_identified_by_their_own_window() {
    use astral_plasma::infrastructure::tray_adapter::xembed_identity_from_window;

    // Wine/XEmbed: the window class is the executable and the title is the
    // application's own text. No application is special-cased.
    let (id, title, glyph) = xembed_identity_from_window(None, "cloudmusic.exe", "");
    assert_eq!(id, "cloudmusic");
    assert_eq!(title, "Cloudmusic");
    assert_eq!(glyph, "circle");

    let (id, title, _) = xembed_identity_from_window(None, "wechat.exe", "微信");
    assert_eq!(id, "wechat");
    assert_eq!(title, "微信");

    // A desktop entry, when installed, supplies the display name and glyph.
    let index = AppIdentityIndex::from_entries(vec![entry(
        "cloudmusic",
        "NetEase Cloud Music",
        "netease-cloud-music",
        Some("cloudmusic.exe"),
        "music_note",
    )]);
    let (id, title, glyph) = xembed_identity_from_window(Some(&index), "cloudmusic.exe", "");
    assert_eq!(id, "cloudmusic");
    assert_eq!(title, "NetEase Cloud Music");
    assert_eq!(glyph, "music_note");

    // Empty window data yields an empty identity, never a fabricated one.
    let (id, title, glyph) = xembed_identity_from_window(None, "", "");
    assert!(id.is_empty() && title.is_empty());
    assert_eq!(glyph, "circle");
}
