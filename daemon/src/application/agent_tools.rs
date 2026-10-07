use crate::application::workspace_control::WorkspaceControlUseCase;
use crate::domain::ports::{DynResult, MetricsPort};
use crate::infrastructure::crash_monitor::CrashMonitor;
use crate::infrastructure::desktop_factory::{create_window_manager_port, create_workspace_port};
use crate::infrastructure::proc_metrics::ProcMetricsAdapter;
use serde_json::{json, Value};
use std::process::Command;

pub struct AgentToolsUseCase;

impl AgentToolsUseCase {
    pub fn manifest() -> Value {
        json!({
            "name": "astral_desktop",
            "version": "1.0.0",
            "description": "Astral Plasma Desktop Control Tools for AI Agents",
            "tools": [
                {
                    "name": "windows",
                    "description": "List all open application windows across the desktop, including window IDs, titles, app names, and active state",
                    "parameters": {}
                },
                {
                    "name": "window_focus",
                    "description": "Focus/activate an application window by its window ID or app name",
                    "parameters": {
                        "target": { "type": "string", "description": "The window ID or application name", "required": true }
                    }
                },
                {
                    "name": "window_close",
                    "description": "Close a window gracefully by its window ID",
                    "parameters": {
                        "target": { "type": "string", "description": "The window ID", "required": true }
                    }
                },
                {
                    "name": "workspaces",
                    "description": "Query virtual workspaces count, current active index, and names",
                    "parameters": {}
                },
                {
                    "name": "workspace_switch",
                    "description": "Switch active workspace to a given workspace number or index (1-based)",
                    "parameters": {
                        "index": { "type": "string", "description": "Workspace index or number", "required": true }
                    }
                },
                {
                    "name": "metrics",
                    "description": "Get real-time CPU, RAM, and uptime system telemetry",
                    "parameters": {}
                },
                {
                    "name": "notify",
                    "description": "Display a desktop notification to the user",
                    "parameters": {
                        "title": { "type": "string", "description": "Notification title", "required": true },
                        "body": { "type": "string", "description": "Notification body text", "required": false }
                    }
                },
                {
                    "name": "crash_recent",
                    "description": "List recent application and service crashes, segfaults, and aborts with process names and signals",
                    "parameters": {
                        "limit": { "type": "integer", "description": "Maximum crashes to return (default: 5)", "required": false }
                    }
                },
                {
                    "name": "crash_diagnose",
                    "description": "Fetch detailed stack trace and journal logs for a crashed application or PID to formulate a diagnostic prompt",
                    "parameters": {
                        "target": { "type": "string", "description": "Process name or PID", "required": true }
                    }
                }
            ]
        })
    }

    pub fn execute_tool(tool_name: &str, args: &[String]) -> DynResult<Value> {
        match tool_name {
            "manifest" | "list" => Ok(Self::manifest()),
            "windows" | "list_windows" => {
                let win_port = create_window_manager_port();
                let (windows, active) = win_port.query_windows().unwrap_or_default();
                let list: Vec<Value> = windows
                    .into_iter()
                    .map(|w| {
                        json!({
                            "id": w.id,
                            "title": w.title,
                            "appName": w.app_name,
                            "appId": w.app_id,
                            "desktopFile": w.desktop_file,
                            "isActive": w.is_active,
                            "isMaximized": w.is_maximized,
                            "isFullScreen": w.is_fullscreen,
                            "desktopIds": w.desktop_ids,
                            "onAllDesktops": w.on_all_desktops,
                        })
                    })
                    .collect();
                Ok(json!({
                    "success": true,
                    "windows": list,
                    "active_window": active.map(|w| json!({
                        "id": w.id,
                        "title": w.title,
                        "appName": w.app_name
                    }))
                }))
            }
            "window_focus" | "window-focus" | "focus" => {
                let target = args.get(0).ok_or("Target window ID required")?;
                let win_port = create_window_manager_port();
                win_port.activate_window(target)?;
                Ok(json!({ "success": true, "focused": target }))
            }
            "window_close" | "window-close" | "close" => {
                let target = args.get(0).ok_or("Target window ID required")?;
                let win_port = create_window_manager_port();
                win_port.close_window(target)?;
                Ok(json!({ "success": true, "closed": target }))
            }
            "workspaces" | "list_workspaces" => {
                let ws_ctrl = WorkspaceControlUseCase::new(create_workspace_port());
                let raw_json = ws_ctrl.query_json()?;
                let parsed: Value = serde_json::from_str(&raw_json).unwrap_or(json!({}));
                Ok(json!({ "success": true, "workspaces": parsed }))
            }
            "workspace_switch" | "workspace-switch" | "switch_workspace" => {
                let target = args.get(0).ok_or("Target workspace index required")?;
                let ws_ctrl = WorkspaceControlUseCase::new(create_workspace_port());
                ws_ctrl.switch(target)?;
                Ok(json!({ "success": true, "switched_to": target }))
            }
            "metrics" | "telemetry" => {
                let adapter = ProcMetricsAdapter::new();
                let metrics = adapter.get_metrics()?;
                Ok(json!({
                    "success": true,
                    "metrics": {
                        "cpu": metrics.cpu.usage,
                        "ram": metrics.ram,
                        "swap": metrics.memory.swap_usage,
                        "uptime": metrics.uptime,
                    }
                }))
            }
            "notify" => {
                let title = args.get(0).ok_or("Notification title required")?;
                let body = args.get(1).map(|s| s.as_str()).unwrap_or("");
                let _ = Command::new("notify-send")
                    .args([title, body, "-a", "Astral Plasma"])
                    .status();
                Ok(json!({ "success": true, "title": title, "body": body }))
            }
            "crash_recent" | "crash-recent" | "crashes" => {
                let limit = args.get(0).and_then(|s| s.parse::<usize>().ok()).unwrap_or(5);
                let crashes = CrashMonitor::scan_recent_crashes(limit);
                let list: Vec<Value> = crashes
                    .into_iter()
                    .map(|c| {
                        json!({
                            "id": c.id,
                            "process_name": c.process_name,
                            "pid": c.pid,
                            "signal": c.signal,
                            "timestamp_ms": c.timestamp_ms,
                            "summary": c.summary,
                            "count": c.count,
                        })
                    })
                    .collect();
                Ok(json!({ "success": true, "crashes": list }))
            }
            "crash_diagnose" | "crash-diagnose" | "diagnose" => {
                let target = args.get(0).ok_or("Target process name or PID required")?;
                let prompt = CrashMonitor::diagnose(target);
                Ok(json!({
                    "success": true,
                    "target": target,
                    "diagnostic_prompt": prompt
                }))
            }
            other => Err(format!("Unknown agent tool: {}", other).into()),
        }
    }
}
