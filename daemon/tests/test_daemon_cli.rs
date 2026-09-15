use std::process::Command;
use serde_json::Value;

fn get_bin_path() -> String {
    let manifest_dir = env!("CARGO_MANIFEST_DIR");
    let bin_path = format!("{}/../bin/caelestia-daemon", manifest_dir);
    if std::path::Path::new(&bin_path).exists() {
        bin_path
    } else {
        format!("{}/target/debug/caelestia-daemon", manifest_dir)
    }
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
