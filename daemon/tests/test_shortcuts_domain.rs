use astral_plasma::application::shortcut_service::ShortcutControlUseCase;
use astral_plasma::domain::branding;
use astral_plasma::infrastructure::kwin_shortcuts::{KWinShortcutsAdapter, KdeIniFile};
use std::fs;

static TEST_MUTEX: std::sync::Mutex<()> = std::sync::Mutex::new(());

#[test]
fn test_kde_ini_parser_granular_modifications() {
    let raw = r#"
[kwin]
Window Close=Alt+F4,none,Close Window
Activate Window=Meta+A,none,Activate

[firefox]
_launch=Meta+B,none,Firefox
"#;

    let mut ini = KdeIniFile::parse(raw);
    assert_eq!(ini.get("kwin", "Window Close").as_deref(), Some("Alt+F4,none,Close Window"));
    assert_eq!(ini.get("firefox", "_launch").as_deref(), Some("Meta+B,none,Firefox"));

    // Granularly add one shortcut without touching other keys
    ini.set("kwin", "SampleAction", "Meta+Space,none,Sample Action");
    assert_eq!(ini.get("kwin", "SampleAction").as_deref(), Some("Meta+Space,none,Sample Action"));

    // Granularly remove it again
    let removed = ini.remove("kwin", "SampleAction");
    assert_eq!(removed.as_deref(), Some("Meta+Space,none,Sample Action"));
    assert_eq!(ini.get("kwin", "SampleAction"), None);

    // Other keys remain intact
    assert_eq!(ini.get("kwin", "Window Close").as_deref(), Some("Alt+F4,none,Close Window"));
    assert_eq!(ini.get("firefox", "_launch").as_deref(), Some("Meta+B,none,Firefox"));
}

#[test]
fn test_granular_backup_and_restore_preserves_user_modifications() {
    let _lock = TEST_MUTEX.lock().unwrap();
    let tmpdir = tempfile::tempdir().expect("Failed to create tempdir");
    let mock_config = tmpdir.path().join("config");
    let mock_data = tmpdir.path().join("data");
    fs::create_dir_all(&mock_config).unwrap();
    fs::create_dir_all(&mock_data).unwrap();

    let kglobal_path = mock_config.join("kglobalshortcutsrc");
    let initial_content = r#"[kwin]
Window Close=Alt+F4,none,Close Window

[firefox]
_launch=Meta+Shift+B,none,Firefox
"#;
    fs::write(&kglobal_path, initial_content).unwrap();

    let backup_dir = mock_data.join(branding::DATA_DIR).join(branding::SHORTCUTS_BACKUP_SUBDIR);

    std::env::set_var("XDG_CONFIG_HOME", &mock_config);
    std::env::set_var("XDG_DATA_HOME", &mock_data);
    std::env::set_var(branding::ENV_SHORTCUTS_BACKUP_DIR, &backup_dir);
    std::env::set_var(branding::ENV_TEST_MODE, "1");

    let adapter = KWinShortcutsAdapter::new();
    let use_case = ShortcutControlUseCase::new(adapter);

    // 1. Initial State: No active backup
    assert!(!use_case.is_active());

    // 2. Start Astral session (backup and bind)
    use_case.backup_and_bind("meta-space").unwrap();
    assert!(use_case.is_active(), "Session must be marked active");
    assert!(backup_dir.join("shortcuts_backup.json").exists());

    // Verify the shell's shortcuts were added
    let current_ini = KdeIniFile::parse(&fs::read_to_string(&kglobal_path).unwrap());
    assert_eq!(
        current_ini.get("kwin", branding::SHORTCUT_LAUNCHER_KEY).as_deref(),
        Some(format!("Meta+Space,none,{}", branding::SHORTCUT_LAUNCHER_LABEL).as_str())
    );

    // 3. Simulate user INTENTIONALLY modifying shortcuts during the session!
    // User changes Window Close to Meta+W, and adds a new shortcut for Spotify
    let mut modified_by_user = KdeIniFile::parse(&fs::read_to_string(&kglobal_path).unwrap());
    modified_by_user.set("kwin", "Window Close", "Meta+W,none,Close Window");
    modified_by_user.set("spotify", "_launch", "Meta+S,none,Spotify");
    fs::write(&kglobal_path, modified_by_user.serialize()).unwrap();

    // 4. Close Astral session (restore)
    let restored = use_case.restore().unwrap();
    assert!(restored, "Restore must return true");
    assert!(!use_case.is_active(), "Session must no longer be active");
    assert!(!backup_dir.join("shortcuts_backup.json").exists());

    // 5. Verify granular restoration:
    // The shell's shortcuts are REMOVED, but user changes PRESERVED!
    let final_ini = KdeIniFile::parse(&fs::read_to_string(&kglobal_path).unwrap());
    assert_eq!(
        final_ini.get("kwin", branding::SHORTCUT_LAUNCHER_KEY),
        None,
        "launcher shortcut must be cleanly removed"
    );
    assert_eq!(
        final_ini.get("kwin", branding::SHORTCUT_WALLPAPER_KEY),
        None,
        "wallpaper shortcut must be cleanly removed"
    );

    // USER MODIFICATIONS MUST BE PRESERVED:
    assert_eq!(
        final_ini.get("kwin", "Window Close").as_deref(),
        Some("Meta+W,none,Close Window"),
        "User's in-session modification to Window Close must NOT be overwritten!"
    );
    assert_eq!(
        final_ini.get("spotify", "_launch").as_deref(),
        Some("Meta+S,none,Spotify"),
        "User's newly added Spotify shortcut must NOT be erased!"
    );
    assert_eq!(
        final_ini.get("firefox", "_launch").as_deref(),
        Some("Meta+Shift+B,none,Firefox"),
        "Untouched shortcuts must remain intact"
    );
}

#[test]
fn test_granular_backup_restores_displaced_shortcut() {
    let _lock = TEST_MUTEX.lock().unwrap();
    let tmpdir = tempfile::tempdir().expect("Failed to create tempdir");
    let mock_config = tmpdir.path().join("config");
    let mock_data = tmpdir.path().join("data");
    fs::create_dir_all(&mock_config).unwrap();
    fs::create_dir_all(&mock_data).unwrap();

    let kglobal_path = mock_config.join("kglobalshortcutsrc");
    // Suppose another component initially owned Meta+Space
    let initial_content = r#"[krunner]
run command=Meta+Space,none,Run Command
"#;
    fs::write(&kglobal_path, initial_content).unwrap();

    let backup_dir = mock_data.join(branding::DATA_DIR).join(branding::SHORTCUTS_BACKUP_SUBDIR);

    std::env::set_var("XDG_CONFIG_HOME", &mock_config);
    std::env::set_var("XDG_DATA_HOME", &mock_data);
    std::env::set_var(branding::ENV_SHORTCUTS_BACKUP_DIR, &backup_dir);
    std::env::set_var(branding::ENV_TEST_MODE, "1");

    let adapter = KWinShortcutsAdapter::new();
    let use_case = ShortcutControlUseCase::new(adapter);

    // 1. Backup and bind
    use_case.backup_and_bind("meta-space").unwrap();

    // 2. Restore
    use_case.restore().unwrap();

    // 3. Verify displaced action was restored
    let final_ini = KdeIniFile::parse(&fs::read_to_string(&kglobal_path).unwrap());
    assert_eq!(
        final_ini.get("krunner", "run command").as_deref(),
        Some("Meta+Space,none,Run Command"),
        "Displaced shortcut must be restored to its original owner"
    );
}
