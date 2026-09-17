use astral_plasma::domain::ports::AppLauncherPort;
use astral_plasma::infrastructure::launcher::DesktopLauncherAdapter;

#[test]
fn test_list_apps_finds_system_applications() {
    let launcher = DesktopLauncherAdapter::new();
    let apps = launcher.list_apps().expect("Failed to list apps");

    // On any Linux desktop with a GUI, there are dozens/hundreds of .desktop entries
    assert!(!apps.is_empty(), "Should find installed .desktop applications");

    // Check properties of entries
    for app in &apps {
        assert!(!app.name.is_empty(), "App name must not be empty");
        assert!(app.desktop_file.ends_with(".desktop"), "Desktop file must have .desktop extension");
    }

    // Verify sort order
    for i in 1..apps.len() {
        assert!(
            apps[i - 1].name.to_lowercase() <= apps[i].name.to_lowercase(),
            "Apps must be sorted alphabetically: '{}' vs '{}'",
            apps[i - 1].name,
            apps[i].name
        );
    }
}
