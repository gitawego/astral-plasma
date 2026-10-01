use astral_plasma::application::desktop_entries_service::DesktopEntriesUseCase;
use astral_plasma::domain::branding;
use astral_plasma::infrastructure::desktop_entries_adapter::DesktopEntriesAdapter;
use std::fs;

#[test]
fn test_desktop_entries_rust_use_case() {
    let tmpdir = tempfile::tempdir().expect("Failed to create tempdir");
    let mock_applications_dir = tmpdir.path().join("applications");
    let mock_sessions_dir = tmpdir.path().join("wayland-sessions");
    let mock_theme_dir = tmpdir.path().join("theme");

    // Setup mock theme directories with test fixtures
    let theme_sessions = mock_theme_dir.join("sessions");
    let theme_shortcuts = mock_theme_dir.join("shortcuts");
    fs::create_dir_all(&theme_sessions).unwrap();
    fs::create_dir_all(&theme_shortcuts).unwrap();

    fs::write(theme_sessions.join("astral-plasma.desktop"), "[Desktop Entry]\nName=Astral Plasma\n").unwrap();
    fs::write(theme_sessions.join("astral-hyprland.desktop"), "[Desktop Entry]\nName=Astral Hyprland\n").unwrap();
    fs::write(theme_shortcuts.join("astral-launcher.desktop"), "[Desktop Entry]\nName=Launcher\n").unwrap();
    fs::write(theme_shortcuts.join("astral-dashboard.desktop"), "[Desktop Entry]\nName=Dashboard\n").unwrap();

    std::env::set_var(branding::ENV_APPLICATIONS_DIR, &mock_applications_dir);
    std::env::set_var(branding::ENV_WAYLAND_SESSIONS_DIR, &mock_sessions_dir);
    std::env::set_var(branding::ENV_THEME_DIR, &mock_theme_dir);
    std::env::set_var(branding::ENV_TEST_MODE, "1");

    let adapter = DesktopEntriesAdapter::new();
    let use_case = DesktopEntriesUseCase::new(adapter);

    // 1. Initial status: uninstalled
    let st1 = use_case.get_status().unwrap();
    assert!(!st1.installed);
    assert!(!st1.session_installed);
    assert!(!st1.shortcuts_installed);

    // 2. Install
    let st2 = use_case.install().unwrap();
    assert!(st2.installed);
    assert!(st2.session_installed);
    assert!(st2.shortcuts_installed);
    assert!(mock_sessions_dir.join("astral-plasma.desktop").exists());
    assert!(mock_sessions_dir.join("astral-hyprland.desktop").exists());
    assert!(mock_applications_dir.join("astral-launcher.desktop").exists());
    assert!(mock_applications_dir.join("astral-dashboard.desktop").exists());
    assert!(mock_applications_dir.join("astral-plasma.desktop").exists());

    // 3. Remove
    let st3 = use_case.remove().unwrap();
    assert!(!st3.installed);
    assert!(!st3.session_installed);
    assert!(!st3.shortcuts_installed);
    assert!(!mock_sessions_dir.join("astral-plasma.desktop").exists());
    assert!(!mock_applications_dir.join("astral-launcher.desktop").exists());
    assert!(!mock_applications_dir.join("astral-plasma.desktop").exists());
}
