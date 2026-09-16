use std::process::Command;
use serde_json::Value;

fn get_bin_path() -> String {
    if let Ok(exe) = std::env::var("CARGO_BIN_EXE_caelestia-daemon") {
        return exe;
    }
    let manifest_dir = env!("CARGO_MANIFEST_DIR");
    let target_debug = format!("{}/target/debug/caelestia-daemon", manifest_dir);
    if std::path::Path::new(&target_debug).exists() {
        return target_debug;
    }
    format!("{}/../bin/caelestia-daemon", manifest_dir)
}

#[test]
fn test_daemon_metrics_output() {
    let bin = get_bin_path();
    let out = Command::new(&bin).arg("metrics").output().expect("Failed to run daemon metrics");
    assert!(out.status.success(), "Metrics command must exit 0");

    let stdout_str = String::from_utf8_lossy(&out.stdout);
    let val: Value = serde_json::from_str(stdout_str.trim()).expect("Metrics must be valid JSON");
    assert!(val.get("uptime").is_some(), "Must have uptime field");
    assert!(val.get("ram").is_some(), "Must have ram field");

    let uptime = val["uptime"].as_str().unwrap();
    assert!(uptime.starts_with("up "), "Uptime must start with 'up '");

    let ram = val["ram"].as_f64().unwrap();
    assert!(ram >= 0.0 && ram <= 1.0, "RAM fraction must be between 0.0 and 1.0");
}

#[test]
fn test_daemon_workspaces_output() {
    let bin = get_bin_path();
    let out = Command::new(&bin).args(["workspaces", "query"]).output().expect("Failed to run workspaces query");
    assert!(out.status.success());

    let val: Value = serde_json::from_str(String::from_utf8_lossy(&out.stdout).trim()).expect("Workspaces must be valid JSON");
    assert!(val.get("count").is_some());
    assert!(val.get("current").is_some());
    assert!(val.get("items").is_some());
    assert!(val["items"].is_array());
}

#[test]
fn test_daemon_preview_usage() {
    let bin = get_bin_path();
    let out = Command::new(&bin).arg("preview").output().expect("Failed to run daemon preview");
    let stderr_str = String::from_utf8_lossy(&out.stderr);
    assert!(stderr_str.contains("Usage:"));
}

#[test]
fn test_daemon_config_write() {
    let bin = get_bin_path();
    let test_dir = std::env::temp_dir().join("caelestia_test_config");
    let test_file = test_dir.join("test_settings.json");
    let content = r#"{"test_key":"test_val"}"#;

    let out = Command::new(&bin)
        .args(["config", "write", test_file.to_str().unwrap(), content])
        .output()
        .expect("Failed to run daemon config write");
    assert!(out.status.success());

    let written = std::fs::read_to_string(&test_file).expect("Must read written config file");
    assert_eq!(written, content);
    let _ = std::fs::remove_dir_all(test_dir);
}

