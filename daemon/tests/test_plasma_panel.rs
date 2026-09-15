use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::process::Command;

#[test]
fn test_plasma_panel_backup_and_restore() {
    let manifest_dir = env!("CARGO_MANIFEST_DIR");
    let script_path = format!("{}/../scripts/manage_plasma_panel.sh", manifest_dir);
    assert!(std::path::Path::new(&script_path).exists(), "manage_plasma_panel.sh must exist");

    let tmpdir = tempfile::tempdir().expect("Failed to create tempdir");
    let mock_config = tmpdir.path().join("config");
    let mock_data = tmpdir.path().join("data");
    let mock_bin = tmpdir.path().join("bin");
    fs::create_dir_all(&mock_config).unwrap();
    fs::create_dir_all(&mock_data).unwrap();
    fs::create_dir_all(&mock_bin).unwrap();

    // Mock systemctl & qdbus6
    let mock_systemctl = mock_bin.join("systemctl");
    fs::write(&mock_systemctl, "#!/bin/sh\nexit 0\n").unwrap();
    fs::set_permissions(&mock_systemctl, fs::Permissions::from_mode(0o755)).unwrap();

    let mock_qdbus = mock_bin.join("qdbus6");
    fs::write(&mock_qdbus, "#!/bin/sh\nexit 0\n").unwrap();
    fs::set_permissions(&mock_qdbus, fs::Permissions::from_mode(0o755)).unwrap();

    let appletsrc_path = mock_config.join("plasma-org.kde.plasma.desktop-appletsrc");
    let orig_appletsrc = "[Containments][10]\nplugin=org.kde.panel\nlocation=3\nactivityId=theme-xyz\n";
    fs::write(&appletsrc_path, orig_appletsrc).unwrap();

    let plasmashellrc_path = mock_config.join("plasmashellrc");
    let orig_plasmashellrc = "[PlasmaViews][Panel 10]\nfloating=0\nthickness=30\n";
    fs::write(&plasmashellrc_path, orig_plasmashellrc).unwrap();

    let backup_dir = mock_data.join("caelestia").join("plasma-backup");

    let orig_path = std::env::var("PATH").unwrap_or_default();
    let new_path = format!("{}:{}", mock_bin.to_str().unwrap(), orig_path);

    // 1. Run disable
    let out_disable = Command::new(&script_path)
        .arg("disable")
        .arg("all")
        .env("XDG_CONFIG_HOME", &mock_config)
        .env("XDG_DATA_HOME", &mock_data)
        .env("CAELESTIA_PLASMA_BACKUP_DIR", &backup_dir)
        .env("PATH", &new_path)
        .env("CAELESTIA_TEST_MODE", "1")
        .output()
        .expect("Failed to run disable");
    assert!(out_disable.status.success(), "disable must exit 0");

    let backed_appletsrc = backup_dir.join("plasma-org.kde.plasma.desktop-appletsrc");
    let backed_plasmashellrc = backup_dir.join("plasmashellrc");
    assert!(backed_appletsrc.exists(), "backup appletsrc must exist");
    assert!(backed_plasmashellrc.exists(), "backup plasmashellrc must exist");

    assert_eq!(fs::read_to_string(&backed_appletsrc).unwrap(), orig_appletsrc);
    assert_eq!(fs::read_to_string(&backed_plasmashellrc).unwrap(), orig_plasmashellrc);

    // 2. Modify active and test repeated disable idempotence
    fs::write(&appletsrc_path, "[Containments][999]\nmodified=true\n").unwrap();
    let out_disable2 = Command::new(&script_path)
        .arg("disable")
        .arg("all")
        .env("XDG_CONFIG_HOME", &mock_config)
        .env("XDG_DATA_HOME", &mock_data)
        .env("CAELESTIA_PLASMA_BACKUP_DIR", &backup_dir)
        .env("PATH", &new_path)
        .env("CAELESTIA_TEST_MODE", "1")
        .output()
        .expect("Failed to run repeated disable");
    assert!(out_disable2.status.success());
    assert_eq!(fs::read_to_string(&backed_appletsrc).unwrap(), orig_appletsrc, "Backup must not be overwritten");

    // 3. Restore
    let out_restore = Command::new(&script_path)
        .arg("restore")
        .env("XDG_CONFIG_HOME", &mock_config)
        .env("XDG_DATA_HOME", &mock_data)
        .env("CAELESTIA_PLASMA_BACKUP_DIR", &backup_dir)
        .env("PATH", &new_path)
        .env("CAELESTIA_TEST_MODE", "1")
        .output()
        .expect("Failed to run restore");
    assert!(out_restore.status.success());

    assert_eq!(fs::read_to_string(&appletsrc_path).unwrap(), orig_appletsrc);
    assert_eq!(fs::read_to_string(&plasmashellrc_path).unwrap(), orig_plasmashellrc);
}
