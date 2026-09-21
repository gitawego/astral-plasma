//! Application identity resolution from XDG desktop entries.
//!
//! The regression these guard: resolution used to be a table of substring tests,
//! where `cls.contains("code")` also matched `zcode`, `opencode` and
//! `claude-code`. A ZCode window therefore rendered as a duplicate VS Code icon
//! and was effectively invisible to the user.

use astral_plasma::domain::branding;
use astral_plasma::domain::app_identity::{
    normalize_identity, parse_desktop_entry, AppIdentityIndex, DesktopApp,
};
use astral_plasma::domain::meta_resolver::{resolve_window_meta, resolve_window_meta_with};

// ============================================================================
// Desktop entry parsing
// ============================================================================

const ZCODE_DESKTOP: &str = "\
[Desktop Entry]
Name=ZCode
Comment=ZCode Desktop App
Exec=\"/mnt/data/Applications/ZCode\" %U
Terminal=false
Type=Application
Icon=zcode
Categories=Development;
MimeType=x-scheme-handler/zcode;
StartupWMClass=ZCode
";

#[test]
fn parses_identity_fields() {
    let app = parse_desktop_entry(ZCODE_DESKTOP, "zcode").expect("entry must parse");
    assert_eq!(app.desktop_id, "zcode");
    assert_eq!(app.name, "ZCode");
    assert_eq!(app.icon, "zcode");
    assert_eq!(app.wm_class.as_deref(), Some("ZCode"));
    assert_eq!(app.material_icon, "code");
}

#[test]
fn skips_nodisplay_entries() {
    let content = "[Desktop Entry]\nType=Application\nName=Hidden\nNoDisplay=true\n";
    assert!(parse_desktop_entry(content, "hidden").is_none());
}

#[test]
fn skips_non_application_entries() {
    let content = "[Desktop Entry]\nType=Link\nName=Some Link\nURL=https://example.com\n";
    assert!(parse_desktop_entry(content, "link").is_none());
}

#[test]
fn ignores_localized_name_keys() {
    let content = "[Desktop Entry]\nType=Application\nName[zh_CN]=云音乐\nName=CloudMusic\n";
    let app = parse_desktop_entry(content, "cloudmusic").unwrap();
    assert_eq!(app.name, "CloudMusic");
}

#[test]
fn reads_only_the_first_desktop_entry_group() {
    // VS Code ships a second [Desktop Entry] group for its "New Empty Window"
    // launcher; the first group is the canonical identity.
    let content = "\
[Desktop Entry]
Type=Application
Name=Visual Studio Code
Icon=vscode
StartupWMClass=Code

[Desktop Entry]
Type=Application
Name=New Empty Window
Icon=vscode
StartupWMClass=Code
";
    let app = parse_desktop_entry(content, "code").unwrap();
    assert_eq!(app.name, "Visual Studio Code");
    assert_eq!(app.wm_class.as_deref(), Some("Code"));
}

#[test]
fn derives_material_icons_from_categories() {
    let cases = [
        ("Development;", "code"),
        ("AudioVideo;Player;", "music_note"),
        ("Game;", "sports_esports"),
        ("Network;WebBrowser;", "language"),
        ("System;Settings;", "settings"),
        ("TerminalEmulator;", "terminal"),
        ("", "window"),
    ];
    for (cats, want) in cases {
        let content = format!("[Desktop Entry]\nType=Application\nName=App\nCategories={}\n", cats);
        let app = parse_desktop_entry(&content, "app").unwrap();
        assert_eq!(app.material_icon, want, "categories {cats:?}");
    }
}

#[test]
fn falls_back_to_desktop_id_when_icon_missing() {
    let content = "[Desktop Entry]\nType=Application\nName=NoIcon\n";
    let app = parse_desktop_entry(content, "noicon").unwrap();
    assert_eq!(app.icon, "noicon");
}

// ============================================================================
// Identity normalization
// ============================================================================

#[test]
fn normalizes_identity_strings() {
    assert_eq!(normalize_identity("ZCode"), "zcode");
    assert_eq!(normalize_identity("code.desktop"), "code");
    assert_eq!(normalize_identity("kde4/foo.desktop"), "foo");
    assert_eq!(normalize_identity("  com.mitchellh.ghostty  "), "com.mitchellh.ghostty");
}

// ============================================================================
// THE REGRESSION: ZCode must not resolve as VS Code
// ============================================================================

fn zcode_vs_code_index() -> AppIdentityIndex {
    let zcode = parse_desktop_entry(ZCODE_DESKTOP, "zcode").unwrap();
    let vscode = parse_desktop_entry(
        "[Desktop Entry]\nType=Application\nName=Visual Studio Code\nIcon=vscode\nCategories=Development;\nStartupWMClass=Code\n",
        "code",
    )
    .unwrap();
    AppIdentityIndex::from_entries(vec![zcode, vscode])
}

#[test]
fn zcode_resolves_to_zcode_not_vscode() {
    let idx = zcode_vs_code_index();
    let app = idx.resolve("zcode", "zcode").expect("zcode must resolve");
    assert_eq!(app.name, "ZCode", "a ZCode window must not be named VS Code");
    assert_eq!(app.icon, "zcode");
    assert_eq!(app.desktop_id, "zcode");
}

#[test]
fn vs_code_still_resolves_to_vscode() {
    let idx = zcode_vs_code_index();
    let app = idx.resolve("code", "code").expect("code must resolve");
    assert_eq!(app.name, "Visual Studio Code");
    assert_eq!(app.icon, "vscode");
    assert_eq!(app.desktop_id, "code");
}

#[test]
fn identity_is_case_insensitive() {
    let idx = zcode_vs_code_index();
    // KWin may report either casing for the class.
    assert!(idx.resolve("ZCode", "").is_some());
    assert!(idx.resolve("zcode", "").is_some());
    assert!(idx.resolve("", "ZCODE").is_some());
}

#[test]
fn resolves_by_wm_class_then_desktop_id() {
    let entries = vec![
        DesktopApp {
            desktop_id: "only-id".into(),
            name: "Only Id".into(),
            icon: "only-id".into(),
            wm_class: None, // declares no StartupWMClass
            material_icon: "window".into(),
            comment: String::new(),
            exec: String::new(),
        },
        DesktopApp {
            desktop_id: "declared".into(),
            name: "Declared".into(),
            icon: "declared".into(),
            wm_class: Some("DeclaredClass".into()),
            material_icon: "window".into(),
            comment: String::new(),
            exec: String::new(),
        },
    ];
    let idx = AppIdentityIndex::from_entries(entries);
    // StartupWMClass is authoritative.
    assert_eq!(idx.resolve("DeclaredClass", "").unwrap().name, "Declared");
    // Desktop-id matching covers apps that set no StartupWMClass.
    assert_eq!(idx.resolve("only-id", "").unwrap().name, "Only Id");
    // Unknown identity must not be guessed.
    assert!(idx.resolve("something-else", "").is_none());
}

#[test]
fn earlier_entries_win_so_user_overrides_system() {
    let user = DesktopApp {
        desktop_id: "app".into(),
        name: "User App".into(),
        icon: "user-app".into(),
        wm_class: None,
        material_icon: "window".into(),
        comment: String::new(),
        exec: String::new(),
    };
    let system = DesktopApp {
        desktop_id: "app".into(),
        name: "System App".into(),
        icon: "system-app".into(),
        wm_class: None,
        material_icon: "window".into(),
        comment: String::new(),
        exec: String::new(),
    };
    let idx = AppIdentityIndex::from_entries(vec![user, system]);
    assert_eq!(idx.resolve("app", "").unwrap().name, "User App");
}

// ============================================================================
// Resolver integration: index takes precedence over heuristics
// ============================================================================

#[test]
fn resolver_prefers_desktop_entry_over_heuristics() {
    let idx = zcode_vs_code_index();
    let meta = resolve_window_meta_with(Some(&idx), "ZCode", "zcode", "zcode", "");
    assert_eq!(meta.app_name, "ZCode");
    assert_eq!(meta.icon_name, "zcode");
    assert_eq!(meta.app_id, "zcode");
    assert_ne!(meta.app_id, "code", "must never be attributed to VS Code");
    assert_eq!(meta.desktop_file, "zcode");
}

#[test]
fn resolver_falls_back_to_the_windows_own_identity() {
    let idx = zcode_vs_code_index();
    // Not installed as a desktop entry: the window's own class names it, and
    // nothing is invented on its behalf.
    let meta = resolve_window_meta_with(Some(&idx), "Quickshell", "quickshell", "quickshell", "");
    assert_eq!(meta.app_id, "quickshell");
    assert_eq!(meta.icon_name, "quickshell");
    assert_eq!(meta.material_icon, "window");
}

// ============================================================================
// Matching is exact: identities never bleed into each other
// ============================================================================

#[test]
fn substring_keywords_no_longer_collide() {
    // Without an index, "zcode" must never be attributed to VS Code.
    let meta = resolve_window_meta("ZCode", "zcode", "zcode", "");
    assert_ne!(
        meta.app_id, "code",
        "'zcode' must not be swallowed by the 'code' keyword"
    );
    assert_ne!(meta.app_name, "VS Code");
    assert_eq!(meta.app_id, "zcode");
}

#[test]
fn identities_resolve_only_through_their_own_declared_metadata() {
    let index = AppIdentityIndex::from_entries(vec![
        DesktopApp {
            desktop_id: "code".into(),
            name: "Visual Studio Code".into(),
            icon: "vscode".into(),
            wm_class: Some("code".into()),
            material_icon: "code".into(),
            comment: String::new(),
            exec: String::new(),
        },
        DesktopApp {
            desktop_id: "com.mitchellh.ghostty".into(),
            name: "Ghostty".into(),
            icon: "com.mitchellh.ghostty".into(),
            wm_class: Some("com.mitchellh.ghostty".into()),
            material_icon: "terminal".into(),
            comment: String::new(),
            exec: String::new(),
        },
        DesktopApp {
            desktop_id: "microsoft-edge".into(),
            name: "Microsoft Edge".into(),
            icon: "microsoft-edge".into(),
            wm_class: Some("microsoft-edge".into()),
            material_icon: "language".into(),
            comment: String::new(),
            exec: String::new(),
        },
    ]);

    // Bare class declared as StartupWMClass.
    assert_eq!(
        resolve_window_meta_with(Some(&index), "Untitled - Code", "code", "code", "").app_id,
        "code"
    );
    // Reverse-DNS class.
    assert_eq!(
        resolve_window_meta_with(Some(&index), "Ghostty", "com.mitchellh.ghostty", "com.mitchellh.ghostty", "").app_id,
        "com.mitchellh.ghostty"
    );
    // Hyphenated class.
    assert_eq!(
        resolve_window_meta_with(Some(&index), "Edge", "microsoft-edge", "microsoft-edge", "").app_id,
        "microsoft-edge"
    );
    // Nothing matches inside another word.
    assert!(index.resolve("knowledge", "").is_none());
    assert!(index.resolve("encode", "").is_none());
}

#[test]
fn keywords_do_not_match_inside_other_words() {
    // "edge" must not match "knowledge"; "code" must not match "encode".
    let a = resolve_window_meta("Knowledge Base", "knowledge", "knowledge", "");
    assert_ne!(a.app_id, "microsoft-edge");
    let b = resolve_window_meta("Encode", "encode", "encode", "");
    assert_ne!(b.app_id, "code");
}

// ============================================================================
// Live system sanity (non-fatal: passes on any machine)
// ============================================================================

#[test]
fn index_loads_and_is_usable() {
    let idx = AppIdentityIndex::load();
    // A desktop environment normally has many entries; if the scan found none we
    // cannot assert on content, but the empty index must still behave safely.
    assert!(idx.resolve("definitely-not-installed-xyz", "").is_none());
    if !idx.is_empty() {
        assert!(idx.len() > 1, "an index with entries should not hold just one");
    }
}

#[test]
fn shared_index_is_cached_and_refreshable() {
    let a = astral_plasma::domain::app_identity::shared_index();
    let b = astral_plasma::domain::app_identity::shared_index();
    assert!(std::sync::Arc::ptr_eq(&a, &b), "shared index must be cached");
    let refreshed = astral_plasma::domain::app_identity::refresh_shared_index();
    let c = astral_plasma::domain::app_identity::shared_index();
    assert!(std::sync::Arc::ptr_eq(&refreshed, &c), "refresh must publish the new index");
}

// ============================================================================
// Shell-owned surfaces must never appear as the active window
// ============================================================================
// The shell's own layer-surfaces (UnifiedShell, drawers, popouts, the settings
// window) are real KWin windows. They set skipTaskbar, and hovering a drawer can
// make one of them the "active window", which previously leaked into the dock's
// active-window pill as a bogus "Quickshell" entry - showing an app that is not
// what the user is actually working in.

use astral_plasma::domain::app_identity::is_shell_owned_surface;

#[test]
fn quickshell_surfaces_are_recognised_as_shell_owned() {
    assert!(is_shell_owned_surface("quickshell", "", ""));
    assert!(is_shell_owned_surface("org.quickshell", "", ""));
    assert!(is_shell_owned_surface("Quickshell", "", ""), "case-insensitive");
    // Empty class but an identifying app id.
    assert!(is_shell_owned_surface("", "quickshell", ""));
    assert!(is_shell_owned_surface("", "org.quickshell", ""));
    // The settings window belongs to the shell too.
    assert!(is_shell_owned_surface(branding::WINDOW_CLASS_SETTINGS, "", ""));
    assert!(is_shell_owned_surface(branding::WINDOW_CLASS, "", ""));
}

#[test]
fn real_applications_are_not_treated_as_shell_owned() {
    for (cls, app, title) in [
        ("code", "code", "settings.json - VS Code"),
        ("zcode", "zcode", "ZCode"),
        ("org.kde.dolphin", "org.kde.dolphin", "Dolphin"),
        ("microsoft-edge", "microsoft-edge", "Edge"),
        ("com.mitchellh.ghostty", "ghostty", "~/dev"),
        // A title mentioning the shell must NOT flag a real app: the shell's own
        // editor session editing this repo is still VS Code.
        ("code", "code", "UnifiedShell.qml - astral-plasma - VS Code"),
        ("ghostty", "ghostty", "quickshell"),
        // The title is never consulted: an identity appearing only in the title
        // must not flag the window.
        ("", "", "org.quickshell"),
        ("", "", "Quickshell"),
    ] {
        assert!(
            !is_shell_owned_surface(cls, app, title),
            "{cls:?}/{app:?}/{title:?} must not be treated as a shell surface"
        );
    }
}

#[test]
fn skip_taskbar_flag_is_honoured() {
    // EWMH: a window asking not to appear in a taskbar must be excluded from the
    // active-window reporting too, not only from the window list.
    assert!(astral_plasma::domain::app_identity::should_skip_taskbar(true, "code", "code", "VS Code"));
    assert!(!astral_plasma::domain::app_identity::should_skip_taskbar(false, "code", "code", "VS Code"));
    // Even without the flag, a shell surface is skipped.
    assert!(astral_plasma::domain::app_identity::should_skip_taskbar(false, "quickshell", "", ""));
}

// ============================================================================
// The KWin watcher script must filter shell surfaces on BOTH paths
// ============================================================================

#[test]
fn kwin_script_filters_shell_surfaces_on_the_active_path() {
    let script = astral_plasma::application::watch_events::get_kwin_watcher_script();

    // There must be a reusable shell-surface predicate...
    assert!(
        script.contains("isShellSurface"),
        "the watcher script must define a shell-surface predicate"
    );
    // ...that consults the EWMH flag...
    assert!(
        script.contains("skipTaskbar"),
        "the shell-surface predicate must consult w.skipTaskbar"
    );
    // ...and is applied on the ACTIVE path, which is the one that leaked.
    let notify_idx = script.find("function notifyActive").expect("notifyActive must exist");
    let body = &script[notify_idx..];
    let end = body.find("\nfunction ").unwrap_or(body.len());
    let notify_body = &body[..end];
    assert!(
        notify_body.contains("isShellSurface"),
        "notifyActive must reject shell surfaces, otherwise hovering a drawer \
         reports a bogus active window"
    );
}

#[test]
fn kwin_script_forwards_the_skip_taskbar_flag() {
    let script = astral_plasma::application::watch_events::get_kwin_watcher_script();
    assert!(
        script.contains("skipTaskbar: isShell"),
        "the window payload must carry the skip flag so the daemon can filter too"
    );
}


// ============================================================================
// The shell's own surface must not STEAL activation (not merely be filtered)
// ============================================================================
// Filtering the shell surface out of reporting was not enough: requesting
// keyboard focus on the full-screen shell surface made KWin activate it, and KWin
// never reassigns activation when that request is withdrawn. The watcher then
// received no further windowActivated events, so the dock froze on a stale app.
// The durable fix is to not request keyboard focus on the shell surface at all,
// except for the power-confirmation modal where Enter/Escape are essential.

#[test]
fn shell_surface_does_not_request_keyboard_focus_for_drawers() {
    let src = std::fs::read_to_string(
        concat!(env!("CARGO_MANIFEST_DIR"), "/../shell/UnifiedShell.qml"),
    )
    .expect("UnifiedShell.qml must be readable");

    let line = src
        .lines()
        .find(|l| l.contains("WlrLayershell.keyboardFocus:"))
        .expect("UnifiedShell must declare a keyboardFocus policy");

    // It must not be a blanket OnDemand: that is what activated the surface.
    assert!(
        !line.contains("dropdownContainer.offsetProgress"),
        "the dashboard drawer must not request keyboard focus - requesting it makes KWin          activate the invisible shell surface and activation is never returned. Line: {line}"
    );
    assert!(
        !line.contains("bottomPopoutVisible"),
        "popouts must not request keyboard focus for the same reason. Line: {line}"
    );
    // Focus is reserved for the genuine modal.
    assert!(
        line.contains("confirmDialogVisible"),
        "only the power-confirmation modal should request keyboard focus. Line: {line}"
    );
}

#[test]
fn kwin_script_restores_activation_after_a_shell_surface() {
    let script = astral_plasma::application::watch_events::get_kwin_watcher_script();
    assert!(
        script.contains("restoreActivationAfterShellSurface"),
        "the watcher must be able to hand activation back, so a modal taking focus          does not permanently starve the watcher"
    );
    // It must actually reassign the compositor's active window.
    assert!(
        script.contains("workspace.activeWindow = "),
        "restoring activation requires assigning workspace.activeWindow"
    );
}
