use caelestia_daemon::application::plasma_service::PlasmaControlUseCase;
use caelestia_daemon::domain::plasma::is_panel_target_match;
use caelestia_daemon::infrastructure::plasma_adapter::PlasmaAdapter;
use std::fs;

#[test]
fn test_plasma_target_matching_rules() {
    assert!(is_panel_target_match("all", "top"));
    assert!(is_panel_target_match("all", "bottom"));
    assert!(is_panel_target_match("", "top"));
    assert!(is_panel_target_match("top", "top"));
    assert!(!is_panel_target_match("top", "bottom"));
    assert!(is_panel_target_match("top,bottom", "bottom"));
    assert!(!is_panel_target_match("top,bottom", "left"));
}

#[test]
fn test_plasma_backup_and_restore_rust() {
    let tmpdir = tempfile::tempdir().expect("Failed to create tempdir");
    let mock_config = tmpdir.path().join("config");
    let mock_data = tmpdir.path().join("data");
    fs::create_dir_all(&mock_config).unwrap();
    fs::create_dir_all(&mock_data).unwrap();

    let appletsrc = mock_config.join("plasma-org.kde.plasma.desktop-appletsrc");
    let orig_applet = "[Containments][42]\nplugin=org.kde.panel\n";
    fs::write(&appletsrc, orig_applet).unwrap();

    let shellrc = mock_config.join("plasmashellrc");
    let orig_shell = "[PlasmaViews][Panel 42]\nthickness=40\n";
    fs::write(&shellrc, orig_shell).unwrap();

    let backup_dir = mock_data.join("caelestia").join("plasma-backup");

    std::env::set_var("XDG_CONFIG_HOME", &mock_config);
    std::env::set_var("XDG_DATA_HOME", &mock_data);
    std::env::set_var("CAELESTIA_PLASMA_BACKUP_DIR", &backup_dir);
    std::env::set_var("CAELESTIA_TEST_MODE", "1");

    let adapter = PlasmaAdapter::new();
    let use_case = PlasmaControlUseCase::new(adapter);

    // 1. Initial status before backup
    let st1 = use_case.get_status().unwrap();
    assert!(!st1.session_active);

    // 2. Disable & Backup
    let count = use_case.backup_and_disable("all", None).unwrap();
    assert_eq!(count, 0); // In test mode, returns 0 mock

    let backed_applet = backup_dir.join("plasma-org.kde.plasma.desktop-appletsrc");
    assert!(backed_applet.exists());
    assert_eq!(fs::read_to_string(&backed_applet).unwrap(), orig_applet);

    // 3. Status during active session
    let st2 = use_case.get_status().unwrap();
    assert!(st2.session_active);

    // 4. Overwrite active config to test idempotence
    fs::write(&appletsrc, "[Modified]").unwrap();
    let _ = use_case.backup_and_disable("all", None).unwrap();
    assert_eq!(fs::read_to_string(&backed_applet).unwrap(), orig_applet, "Pristine backup must not be overwritten");

    // 5. Restore
    let restored = use_case.restore().unwrap();
    assert!(restored);
    assert_eq!(fs::read_to_string(&appletsrc).unwrap(), orig_applet, "Original config restored");

    let st3 = use_case.get_status().unwrap();
    assert!(!st3.session_active);
}
