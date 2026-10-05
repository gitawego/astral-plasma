use std::process::Command;
use serde_json::Value;

fn get_bin_path() -> String {
    if let Ok(exe) = std::env::var("CARGO_BIN_EXE_astral-plasma") {
        return exe;
    }
    let manifest_dir = env!("CARGO_MANIFEST_DIR");
    let target_debug = format!("{}/target/debug/astral-plasma", manifest_dir);
    if std::path::Path::new(&target_debug).exists() {
        return target_debug;
    }
    format!("{}/../bin/astral-plasma", manifest_dir)
}

#[test]
fn test_agent_tools_manifest() {
    let bin = get_bin_path();
    let out = Command::new(&bin)
        .args(["tool", "manifest"])
        .output()
        .expect("Failed to execute tool manifest");
    assert!(out.status.success(), "tool manifest must exit 0");

    let val: Value = serde_json::from_str(String::from_utf8_lossy(&out.stdout).trim())
        .expect("Manifest must be valid JSON");
    assert_eq!(val["name"], "astral_desktop");
    assert!(val["tools"].is_array(), "tools must be an array");

    let tools = val["tools"].as_array().unwrap();
    let names: Vec<&str> = tools.iter().filter_map(|t| t["name"].as_str()).collect();
    assert!(names.contains(&"windows"), "Must contain windows tool");
    assert!(names.contains(&"workspaces"), "Must contain workspaces tool");
    assert!(names.contains(&"metrics"), "Must contain metrics tool");
    assert!(names.contains(&"notify"), "Must contain notify tool");
    assert!(names.contains(&"crash_recent"), "Must contain crash_recent tool");
    assert!(names.contains(&"crash_diagnose"), "Must contain crash_diagnose tool");
}

#[test]
fn test_agent_tools_metrics() {
    let bin = get_bin_path();
    let out = Command::new(&bin)
        .args(["tool", "metrics"])
        .output()
        .expect("Failed to execute tool metrics");
    assert!(out.status.success(), "tool metrics must exit 0");

    let val: Value = serde_json::from_str(String::from_utf8_lossy(&out.stdout).trim())
        .expect("Metrics must be valid JSON");
    assert_eq!(val["success"], true);
    assert!(val["metrics"]["uptime"].is_string());
    assert!(val["metrics"]["ram"].is_number());
}

#[test]
fn test_agent_tools_workspaces() {
    let bin = get_bin_path();
    let out = Command::new(&bin)
        .args(["tool", "workspaces"])
        .output()
        .expect("Failed to execute tool workspaces");
    assert!(out.status.success(), "tool workspaces must exit 0");

    let val: Value = serde_json::from_str(String::from_utf8_lossy(&out.stdout).trim())
        .expect("Workspaces must be valid JSON");
    assert_eq!(val["success"], true);
    assert!(val.get("workspaces").is_some());
}

#[test]
fn test_crash_recent_and_prompt() {
    let bin = get_bin_path();
    // 1. Crash recent
    let out = Command::new(&bin)
        .args(["crash", "recent"])
        .output()
        .expect("Failed to execute crash recent");
    assert!(out.status.success(), "crash recent must exit 0");

    let val: Value = serde_json::from_str(String::from_utf8_lossy(&out.stdout).trim())
        .expect("Crash recent must be valid JSON");
    assert!(val.is_array(), "Must return array of crashes");

    // 2. Crash prompt for a process
    let out = Command::new(&bin)
        .args(["crash", "prompt", "test-process"])
        .output()
        .expect("Failed to execute crash prompt");
    assert!(out.status.success(), "crash prompt must exit 0");
    let prompt = String::from_utf8_lossy(&out.stdout);
    assert!(prompt.contains("test-process"), "Prompt must reference process: {}", prompt);
    assert!(prompt.contains("diagnose"), "Prompt must ask for diagnosis");
}

#[test]
fn test_agent_skill_install_and_uninstall() {
    let bin = get_bin_path();
    let temp_home = tempfile::tempdir().unwrap();

    // 1. Initial status: uninstalled in clean HOME
    let out = Command::new(&bin)
        .env("HOME", temp_home.path())
        .args(["skill", "status", "astral-desktop-tools"])
        .output()
        .expect("skill status");
    assert!(out.status.success());
    let val: Value = serde_json::from_str(String::from_utf8_lossy(&out.stdout).trim()).unwrap();
    assert_eq!(val["name"], "astral-desktop-tools");
    assert_eq!(val["installed"], false);

    // 2. Install
    let out = Command::new(&bin)
        .env("HOME", temp_home.path())
        .args(["skill", "install", "astral-desktop-tools"])
        .output()
        .expect("skill install");
    assert!(out.status.success());
    let val: Value = serde_json::from_str(String::from_utf8_lossy(&out.stdout).trim()).unwrap();
    assert_eq!(val["installed"], true);
    assert!(!val["locations"].as_array().unwrap().is_empty());

    let skill_path = temp_home.path().join(".config/astral-plasma/skills/astral-desktop-tools/SKILL.md");
    assert!(skill_path.exists(), "SKILL.md must be written to config path");

    // 3. Status: installed
    let out = Command::new(&bin)
        .env("HOME", temp_home.path())
        .args(["skill", "status", "astral-desktop-tools"])
        .output()
        .expect("skill status");
    assert!(out.status.success());
    let val: Value = serde_json::from_str(String::from_utf8_lossy(&out.stdout).trim()).unwrap();
    assert_eq!(val["installed"], true);

    // 4. Uninstall
    let out = Command::new(&bin)
        .env("HOME", temp_home.path())
        .args(["skill", "uninstall", "astral-desktop-tools"])
        .output()
        .expect("skill uninstall");
    assert!(out.status.success());
    let val: Value = serde_json::from_str(String::from_utf8_lossy(&out.stdout).trim()).unwrap();
    assert_eq!(val["installed"], false);
    assert!(!skill_path.exists(), "SKILL.md must be removed");
}

