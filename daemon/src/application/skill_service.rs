use crate::domain::assistant::SkillStatus;
use crate::domain::ports::DynResult;
use std::fs;
use std::path::PathBuf;

pub const ASTRAL_DESKTOP_TOOLS_NAME: &str = "astral-desktop-tools";
pub const ASTRAL_DESKTOP_TOOLS_DESC: &str = "Inspect & control windows, switch workspaces, query telemetry, and trigger crash diagnosis";

pub const ASTRAL_DESKTOP_TOOLS_SKILL_MD: &str = r#"---
name: astral-desktop-tools
description: Use Astral Plasma's native machine-readable CLI tools to inspect and control the desktop environment, applications, workspaces, system telemetry, and crashes. Use when an AI coding agent or assistant needs to query open windows, focus or close apps, switch virtual workspaces, inspect system health, trigger notifications, or diagnose application crashes.
---

# Astral Desktop Tools for AI Agents

Astral Plasma provides a native, high-performance CLI tool suite designed for AI coding agents (Antigravity, Agy, Claude Code, Cursor) and automation scripts.

The tools are invoked via the `astral-plasma` binary:
```bash
astral-plasma tool <tool_name> [arguments...]
```
All tools return clean, structured JSON.

## Tool Manifest

You can query the machine-readable manifest at any time:
```bash
astral-plasma tool manifest
```

## Available Tools

### 1. `windows`
List all open application windows across the desktop with their window IDs, titles, application names, and active states.
```bash
astral-plasma tool windows
```

### 2. `window_focus`
Focus/activate an application window by its window ID or app name.
```bash
astral-plasma tool window_focus <window_id_or_app_name>
```

### 3. `window_close`
Close a window gracefully by its window ID.
```bash
astral-plasma tool window_close <window_id>
```

### 4. `workspaces`
Query the virtual workspace count, current active workspace index, and names.
```bash
astral-plasma tool workspaces
```

### 5. `workspace_switch`
Switch active workspace to a given workspace number or index (1-based).
```bash
astral-plasma tool workspace_switch <index>
```

### 6. `metrics`
Get real-time system telemetry: CPU usage, RAM utilization, and uptime.
```bash
astral-plasma tool metrics
```

### 7. `notify`
Display a native desktop notification to the user.
```bash
astral-plasma tool notify "Build Finished" "Your test suite passed with 100% success."
```

### 8. `crash_recent`
List recent application and service crashes, segfaults, and aborts recorded by `systemd-coredump` and `journalctl`.
```bash
astral-plasma tool crash_recent [limit]
```

### 9. `crash_diagnose`
Fetch detailed stack trace and journal logs for a crashed application or PID to formulate a diagnostic prompt.
```bash
astral-plasma tool crash_diagnose <process_name_or_pid>
```
"#;

pub struct SkillService;

impl SkillService {
    pub fn get_target_directories(skill_name: &str) -> Vec<PathBuf> {
        let mut dirs = Vec::new();
        let home = std::env::var("HOME").unwrap_or_else(|_| "/tmp".to_string());
        let home_path = PathBuf::from(&home);

        // 1. ~/.config/astral-plasma/skills/<skill_name>
        dirs.push(home_path.join(".config").join("astral-plasma").join("skills").join(skill_name));

        // 2. ~/.gemini/antigravity/skills/<skill_name>
        dirs.push(home_path.join(".gemini").join("antigravity").join("skills").join(skill_name));

        // 3. ~/.agents/skills/<skill_name>
        dirs.push(home_path.join(".agents").join("skills").join(skill_name));

        dirs
    }

    pub fn list_skills() -> Vec<SkillStatus> {
        vec![Self::get_status(ASTRAL_DESKTOP_TOOLS_NAME)]
    }

    pub fn get_status(name: &str) -> SkillStatus {
        let target_dirs = Self::get_target_directories(name);
        let mut locations = Vec::new();

        for dir in &target_dirs {
            let skill_file = dir.join("SKILL.md");
            if skill_file.exists() {
                locations.push(skill_file.to_string_lossy().to_string());
            }
        }

        // Also check if current workspace has .agents/skills/<name>/SKILL.md
        let local_skill = PathBuf::from(".agents").join("skills").join(name).join("SKILL.md");
        if local_skill.exists() {
            let loc_str = local_skill.to_string_lossy().to_string();
            if !locations.contains(&loc_str) {
                locations.push(loc_str);
            }
        }

        let installed = !locations.is_empty();
        let desc = if name == ASTRAL_DESKTOP_TOOLS_NAME {
            ASTRAL_DESKTOP_TOOLS_DESC.to_string()
        } else {
            "Agent Desktop Skill".to_string()
        };

        SkillStatus {
            name: name.to_string(),
            description: desc,
            installed,
            locations,
        }
    }

    pub fn install(name: &str) -> DynResult<SkillStatus> {
        if name != ASTRAL_DESKTOP_TOOLS_NAME && name != "all" {
            return Err(format!("Unknown skill: {}", name).into());
        }

        let content = ASTRAL_DESKTOP_TOOLS_SKILL_MD;
        let target_dirs = Self::get_target_directories(ASTRAL_DESKTOP_TOOLS_NAME);
        let home = std::env::var("HOME").unwrap_or_else(|_| "/tmp".to_string());
        let home_path = PathBuf::from(&home);

        for dir in target_dirs {
            // If it's antigravity dir, only write if ~/.gemini/antigravity or ~/.gemini exists
            if dir.to_string_lossy().contains(".gemini") {
                if !home_path.join(".gemini").exists() {
                    continue;
                }
            }
            let _ = fs::create_dir_all(&dir);
            let target_file = dir.join("SKILL.md");
            fs::write(target_file, content)?;
        }

        Ok(Self::get_status(ASTRAL_DESKTOP_TOOLS_NAME))
    }

    pub fn uninstall(name: &str) -> DynResult<SkillStatus> {
        if name != ASTRAL_DESKTOP_TOOLS_NAME && name != "all" {
            return Err(format!("Unknown skill: {}", name).into());
        }

        let target_dirs = Self::get_target_directories(ASTRAL_DESKTOP_TOOLS_NAME);
        for dir in target_dirs {
            let file = dir.join("SKILL.md");
            if file.exists() {
                let _ = fs::remove_file(&file);
            }
            // Remove parent dir if empty
            if dir.exists() {
                let _ = fs::remove_dir(&dir);
            }
        }

        Ok(Self::get_status(ASTRAL_DESKTOP_TOOLS_NAME))
    }
}
