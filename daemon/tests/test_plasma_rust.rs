use astral_plasma::application::plasma_service::PlasmaControlUseCase;
use astral_plasma::domain::plasma::is_panel_target_match;
use astral_plasma::domain::ports::PlasmaControlPort;
use astral_plasma::infrastructure::plasma_adapter::PlasmaAdapter;
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

static TEST_MUTEX: std::sync::Mutex<()> = std::sync::Mutex::new(());

#[test]
fn test_plasma_backup_and_restore_rust() {
    let _lock = TEST_MUTEX.lock().unwrap();
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

#[test]
fn test_plasma_status_struct_serialization() {
    use astral_plasma::domain::plasma::{PlasmaPanelInfo, PlasmaStatus};

    let panels = vec![
        PlasmaPanelInfo {
            id: 98,
            location: "top".to_string(),
            hiding: "none".to_string(),
            height: 30,
        },
        PlasmaPanelInfo {
            id: 100,
            location: "bottom".to_string(),
            hiding: "dodgewindows".to_string(),
            height: 64,
        },
    ];

    let status = PlasmaStatus {
        panels: panels.clone(),
        backup_dir: "/home/user/.local/share/caelestia/plasma-backup".to_string(),
        session_active: true,
        watchdog_pid: Some(12345),
    };

    let json_str = serde_json::to_string(&status).expect("Failed to serialize PlasmaStatus");
    assert!(json_str.contains(r#""id":98"#));
    assert!(json_str.contains(r#""location":"top""#));
    assert!(json_str.contains(r#""location":"bottom""#));
    assert!(json_str.contains(r#""session_active":true"#));
    assert!(json_str.contains(r#""watchdog_pid":12345"#));

    let deserialized: PlasmaStatus = serde_json::from_str(&json_str).expect("Failed to deserialize PlasmaStatus");
    assert_eq!(deserialized.panels.len(), 2);
    assert_eq!(deserialized.panels[0].id, 98);
    assert_eq!(deserialized.panels[1].location, "bottom");
    assert!(deserialized.session_active);
    assert_eq!(deserialized.watchdog_pid, Some(12345));
}

#[test]
fn test_plasma_layout_fallback_and_stop_watchdog() {
    let _lock = TEST_MUTEX.lock().unwrap();
    let tmpdir = tempfile::tempdir().expect("Failed to create tempdir");
    let mock_config = tmpdir.path().join("config");
    let mock_data = tmpdir.path().join("data");
    fs::create_dir_all(&mock_config).unwrap();
    fs::create_dir_all(&mock_data).unwrap();

    let backup_dir = mock_data.join("caelestia").join("plasma-backup");
    fs::create_dir_all(&backup_dir).unwrap();

    // Create a mock layout.js in backup
    let layout_content = "// Plasma layout dump\npanel.location = 'top';";
    fs::write(backup_dir.join("layout.js"), layout_content).unwrap();
    fs::write(backup_dir.join("session_active"), "").unwrap();

    std::env::set_var("XDG_CONFIG_HOME", &mock_config);
    std::env::set_var("XDG_DATA_HOME", &mock_data);
    std::env::set_var("CAELESTIA_PLASMA_BACKUP_DIR", &backup_dir);
    std::env::set_var("CAELESTIA_TEST_MODE", "1");

    let adapter = PlasmaAdapter::new();

    // Test stop_watchdog safety
    adapter.stop_watchdog();

    // Test restore restores layout and clears session
    let restored = adapter.restore_config().unwrap();
    assert!(restored);
    assert!(!backup_dir.join("session_active").exists(), "session_active flag must be cleared upon restore");
}

#[tokio::test]
async fn test_stop_watchdog_does_not_kill_self() {
    let _lock = TEST_MUTEX.lock().unwrap();
    let my_pid = std::process::id();
    let pid_file = std::path::Path::new("/tmp/caelestia-plasma-watchdog.pid");
    let _ = fs::write(pid_file, my_pid.to_string());

    let adapter = PlasmaAdapter::new();
    // Must NOT kill my_pid!
    adapter.stop_watchdog();
    assert!(unsafe { libc::kill(my_pid as i32, 0) == 0 });
    let _ = fs::remove_file(pid_file);
}

#[tokio::test]
async fn test_watchdog_loop_on_target_exit() {
    let _lock = TEST_MUTEX.lock().unwrap();
    let tmpdir = tempfile::tempdir().expect("Failed to create tempdir");
    let mock_config = tmpdir.path().join("config");
    let mock_data = tmpdir.path().join("data");
    fs::create_dir_all(&mock_config).unwrap();
    fs::create_dir_all(&mock_data).unwrap();

    let backup_dir = mock_data.join("caelestia").join("plasma-backup");
    fs::create_dir_all(&backup_dir).unwrap();
    fs::write(backup_dir.join("layout.js"), "// test layout").unwrap();
    fs::write(backup_dir.join("session_active"), "").unwrap();

    std::env::set_var("XDG_CONFIG_HOME", &mock_config);
    std::env::set_var("XDG_DATA_HOME", &mock_data);
    std::env::set_var("CAELESTIA_PLASMA_BACKUP_DIR", &backup_dir);
    std::env::set_var("CAELESTIA_TEST_MODE", "1");

    // Spawn a quick short-lived process
    let mut child = std::process::Command::new("true").spawn().unwrap();
    let child_pid = child.id();
    let _ = child.wait();

    // Run watchdog loop with exited target process
    let res = astral_plasma::application::plasma_service::run_watchdog_loop(child_pid).await;
    assert!(res.is_ok());
    assert!(!backup_dir.join("session_active").exists(), "Watchdog must restore and clear session_active flag");
}

