use astral_plasma::application::systemd_service::SystemdControlUseCase;
use astral_plasma::infrastructure::systemd_adapter::SystemdAdapter;
use std::fs;

#[test]
fn test_systemd_service_rust_use_case() {
    let tmpdir = tempfile::tempdir().expect("Failed to create tempdir");
    let mock_systemd_dir = tmpdir.path().join("systemd").join("user");

    std::env::set_var("CAELESTIA_SYSTEMD_DIR", &mock_systemd_dir);
    std::env::set_var("CAELESTIA_TEST_MODE", "1");

    let adapter = SystemdAdapter::new();
    let use_case = SystemdControlUseCase::new(adapter);

    // 1. Initial status: uninstalled
    let st1 = use_case.get_status().unwrap();
    assert!(!st1.installed);

    let service_file = mock_systemd_dir.join("caelestia.service");
    assert!(!service_file.exists());

    // 2. Install
    let st2 = use_case.install().unwrap();
    assert!(st2.installed);
    assert!(service_file.exists());

    let content = fs::read_to_string(&service_file).unwrap();
    assert!(content.contains("[Unit]"));
    assert!(content.contains("Description=Caelestia Desktop Shell"));

    // 3. Remove
    let st3 = use_case.remove().unwrap();
    assert!(!st3.installed);
    assert!(!service_file.exists());
}
