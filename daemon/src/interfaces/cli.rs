use crate::application::get_metrics::GetMetricsUseCase;
use crate::application::launch_app::LaunchAppUseCase;
use crate::application::plasma_service::{run_watchdog_loop, PlasmaControlUseCase};
use crate::application::systemd_service::SystemdControlUseCase;
use crate::application::watch_events::run_event_daemon;
use crate::application::window_control::WindowControlUseCase;
use crate::application::workspace_control::WorkspaceControlUseCase;
use crate::domain::ports::DynResult;
use crate::infrastructure::embedded_bundle::{extract_embedded_theme, get_default_package_dir};
use crate::infrastructure::kwin_adapter::KWinAdapter;
use crate::infrastructure::launcher::DesktopLauncherAdapter;
use crate::infrastructure::plasma_adapter::PlasmaAdapter;
use crate::infrastructure::proc_metrics::ProcMetricsAdapter;
use crate::infrastructure::systemd_adapter::SystemdAdapter;
use crate::interfaces::api_server::{run_api_server, DEFAULT_API_PORT};
use std::env;
use std::path::{Path, PathBuf};
use std::process::Command;

pub async fn run_cli() -> DynResult<()> {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        print_usage();
        return Ok(());
    }

    match args[1].as_str() {
        "run" => {
            run_self_contained_app().await?;
        }
        "serve" | "server" => {
            let port = args.get(2).and_then(|p| p.parse().ok()).unwrap_or(DEFAULT_API_PORT);
            run_api_server(port).await?;
        }
        "extract" => {
            let target = if args.len() >= 3 {
                PathBuf::from(&args[2])
            } else {
                get_default_package_dir()
            };
            println!("Extracting embedded theme to: {}", target.display());
            extract_embedded_theme(&target)?;
            println!("Theme extraction complete.");
        }
        "plasma" => {
            let sub = args.get(2).map(|s| s.as_str()).unwrap_or("status");
            let plasma = PlasmaControlUseCase::new(PlasmaAdapter::new());
            match sub {
                "disable" => {
                    let target = args.get(3).map(|s| s.as_str()).unwrap_or("all");
                    let pid = args.get(4).and_then(|p| p.parse::<u32>().ok());
                    let removed = plasma.backup_and_disable(target, pid)?;
                    println!(r#"{{"success":true,"removed":{}}}"#, removed);
                }
                "restore" => {
                    let restored = plasma.restore()?;
                    println!(r#"{{"success":true,"restored":{}}}"#, restored);
                }
                "watchdog" => {
                    if let Some(pid_str) = args.get(3) {
                        if let Ok(pid) = pid_str.parse::<u32>() {
                            run_watchdog_loop(pid)?;
                        }
                    }
                }
                "status" => {
                    let st = plasma.get_status()?;
                    println!("{}", serde_json::to_string(&st)?);
                }
                _ => {
                    eprintln!("Usage: astral-plasma plasma <disable|restore|status|watchdog> [args...]");
                }
            }
        }
        "systemd" => {
            let sub = args.get(2).map(|s| s.as_str()).unwrap_or("status");
            let systemd = SystemdControlUseCase::new(SystemdAdapter::new());
            match sub {
                "status" => {
                    let st = systemd.get_status()?;
                    println!("{}", serde_json::to_string(&st)?);
                }
                "install" => {
                    let st = systemd.install()?;
                    println!("{}", serde_json::to_string(&st)?);
                }
                "remove" => {
                    let st = systemd.remove()?;
                    println!("{}", serde_json::to_string(&st)?);
                }
                _ => {
                    eprintln!("Usage: astral-plasma systemd <status|install|remove>");
                }
            }
        }
        "notifs" => {
            crate::application::notif_monitor::run_notif_monitor().await?;
        }
        "visualizer" | "audio-vis" => {
            crate::application::audio_visualizer::run_audio_visualizer(None)?;
        }
        "settings" => {
            let sub = args.get(2).map(|s| s.as_str()).unwrap_or("toggle");
            let action = match sub {
                "open" => "open",
                "close" => "close",
                _ => "toggle",
            };
            let pkg_dir = get_default_package_dir();
            let current_dir = env::current_dir().unwrap_or_default();
            let mut cmd = Command::new("qs");
            cmd.arg("ipc");
            if current_dir.join("shell.qml").exists() {
                cmd.args(["-p", current_dir.to_str().unwrap()]);
            } else if pkg_dir.join("shell.qml").exists() {
                cmd.args(["-p", pkg_dir.to_str().unwrap()]);
            }
            cmd.args(["call", "settings", action]);
            if action == "open" {
                if let Some(page) = args.get(3) {
                    cmd.arg(page);
                }
            }
            let status = cmd.status();
            match status {
                Ok(s) if s.success() => {
                    println!(r#"{{"success":true,"action":"{}"}}"#, action);
                }
                _ => {
                    eprintln!("Failed to invoke Quickshell settings IPC (is Caelestia running?)");
                }
            }
        }
        "theme" => {
            let sub = args.get(2).map(|s| s.as_str()).unwrap_or("toggle");
            let pkg_dir = get_default_package_dir();
            let current_dir = env::current_dir().unwrap_or_default();
            let mut cmd = Command::new("qs");
            cmd.arg("ipc");
            if current_dir.join("shell.qml").exists() {
                cmd.args(["-p", current_dir.to_str().unwrap()]);
            } else if pkg_dir.join("shell.qml").exists() {
                cmd.args(["-p", pkg_dir.to_str().unwrap()]);
            }
            match sub {
                "light" => {
                    cmd.args(["call", "theme", "setMode", "light"]);
                }
                "dark" => {
                    cmd.args(["call", "theme", "setMode", "dark"]);
                }
                "preset" => {
                    let preset = args.get(3).map(|s| s.as_str()).unwrap_or("iris");
                    cmd.args(["call", "theme", "setPreset", preset]);
                }
                _ => {
                    cmd.args(["call", "theme", "toggle"]);
                }
            }
            let status = cmd.status();
            match status {
                Ok(s) if s.success() => {
                    println!(r#"{{"success":true,"theme_command":"{}"}}"#, sub);
                }
                _ => {
                    eprintln!("Failed to invoke Quickshell theme IPC (is Caelestia running?)");
                }
            }
        }
        "config" => {
            let sub = args.get(2).map(|s| s.as_str()).unwrap_or("write");
            match sub {
                "write" => {
                    if let (Some(path_str), Some(content)) = (args.get(3), args.get(4)) {
                        let path = Path::new(path_str);
                        if let Some(parent) = path.parent() {
                            let _ = std::fs::create_dir_all(parent);
                        }
                        std::fs::write(path, content)?;
                        println!(r#"{{"success":true,"path":"{}"}}"#, path_str);
                    } else {
                        eprintln!("Usage: astral-plasma config write <path> <content>");
                    }
                }
                _ => {
                    eprintln!("Usage: astral-plasma config write <path> <content>");
                }
            }
        }
        "watch" | "--daemon" => {
            run_event_daemon().await?;
        }
        "activate" => {
            if args.len() >= 3 {
                let win_ctrl = WindowControlUseCase::new(KWinAdapter::new());
                win_ctrl.activate(&args[2])?;
            }
        }
        "close" => {
            if args.len() >= 3 {
                let win_ctrl = WindowControlUseCase::new(KWinAdapter::new());
                win_ctrl.close(&args[2])?;
            }
        }
        "launch" => {
            if args.len() >= 3 {
                let launcher = LaunchAppUseCase::new(DesktopLauncherAdapter::new());
                launcher.execute(&args[2])?;
            }
        }
        "workspaces" => {
            let ws_ctrl = WorkspaceControlUseCase::new(KWinAdapter::new());
            let sub = if args.len() >= 3 { args[2].as_str() } else { "query" };
            match sub {
                "query" => {
                    let json = ws_ctrl.query_json()?;
                    println!("{}", json);
                }
                "switch" => {
                    if args.len() >= 4 {
                        ws_ctrl.switch(&args[3])?;
                    }
                }
                "ensure" => {
                    if args.len() >= 4 {
                        if let Ok(idx) = args[3].parse::<u32>() {
                            ws_ctrl.ensure_and_switch(idx)?;
                        }
                    }
                }
                _ => {
                    let json = ws_ctrl.query_json()?;
                    println!("{}", json);
                }
            }
        }
        "metrics" => {
            let metrics_ctrl = GetMetricsUseCase::new(ProcMetricsAdapter::new());
            let json = metrics_ctrl.execute_json()?;
            println!("{}", json);
        }
        "tray" => {
            use crate::domain::ports::TrayPort;
            let sub = if args.len() >= 3 { args[2].as_str() } else { "query" };
            match sub {
                "menu" => {
                    if args.len() >= 5 {
                        let svc = &args[3];
                        let menu_path = &args[4];
                        let tray = crate::infrastructure::tray_adapter::TrayAdapter::new();
                        let items = tray.fetch_menu(svc, menu_path)?;
                        let json = serde_json::to_string(&items)?;
                        println!("{}", json);
                    } else {
                        eprintln!("Usage: astral-plasma tray menu <service> <menu_path>");
                    }
                }
                "click" => {
                    if args.len() >= 6 {
                        let svc = &args[3];
                        let menu_path = &args[4];
                        let id: i32 = args[5].parse().unwrap_or(0);
                        let tray = crate::infrastructure::tray_adapter::TrayAdapter::new();
                        tray.click_item(svc, menu_path, id)?;
                    } else {
                        eprintln!("Usage: astral-plasma tray click <service> <menu_path> <id>");
                    }
                }
                "activate" => {
                    if args.len() >= 5 {
                        let svc = &args[3];
                        let path = &args[4];
                        let _ = std::process::Command::new("qdbus6")
                            .args([svc, path, "org.kde.StatusNotifierItem.Activate", "0", "0"])
                            .output();
                    } else {
                        eprintln!("Usage: astral-plasma tray activate <service> <path>");
                    }
                }
                "query" | "list" => {
                    let tray = crate::infrastructure::tray_adapter::TrayAdapter::new();
                    let items = tray.query_tray()?;
                    let json = serde_json::to_string(&items)?;
                    println!("{}", json);
                }
                _ => {
                    eprintln!("Usage: astral-plasma tray <query|menu|click|activate> [args...]");
                }
            }
        }
        "preview" => {
            if args.len() >= 3 {
                let win_id = &args[2];
                let width: u32 = args.get(3).and_then(|w| w.parse().ok()).unwrap_or(320);
                let slot = args.get(4).map(|s| s.as_str());

                match crate::infrastructure::preview_capture::capture_window(win_id, width, slot).await {
                    Ok(path) => {
                        println!("{}", path);
                    }
                    Err(e) => {
                        eprintln!("Preview capture failed: {}", e);
                        std::process::exit(1);
                    }
                }
            } else {
                eprintln!("Usage: astral-plasma preview <window_id> [target_width] [slot]");
            }
        }
        "desktop" => {
            let sub = args.get(2).map(|s| s.as_str()).unwrap_or("");
            match sub {
                "install" => {
                    let installed = crate::infrastructure::preview_capture::install_desktop_entry_with_notification(None, None)?;
                    println!(r#"{{"success":true,"installed":{}}}"#, installed);
                }
                "cleanup" | "remove" => {
                    let removed = crate::infrastructure::preview_capture::remove_desktop_entry(None)?;
                    println!(r#"{{"success":true,"removed":{}}}"#, removed);
                }
                _ => {
                    eprintln!("Usage: astral-plasma desktop <install|cleanup>");
                }
            }
        }
        _ => {
            eprintln!("Unknown command: {}", args[1]);
            print_usage();
        }
    }

    Ok(())
}

fn print_usage() {
    eprintln!("Usage: astral-plasma <command> [args...]");
    eprintln!("Commands:");
    eprintln!("  run                     - Run full self-contained Caelestia desktop shell");
    eprintln!("  serve [--port <port>]   - Run native REST & Unix socket API server");
    eprintln!("  extract [target_dir]    - Extract embedded QML theme bundle");
    eprintln!("  plasma <cmd>            - Plasma panels management: disable, restore, status, watchdog");
    eprintln!("  systemd <cmd>           - User-directed systemd service management: status, install, remove");
    eprintln!("  settings [toggle|open|close] - Control Settings GUI window via IPC");
    eprintln!("  config write <path> <json> - Atomic configuration file persistence");
    eprintln!("  watch                   - Run event-driven background watcher");
    eprintln!("  visualizer              - Stream real-time audio spectrum & energy JSON");
    eprintln!("  metrics                 - Print system metrics JSON (uptime, ram)");
    eprintln!("  workspaces <cmd>        - Virtual desktops: query, switch, ensure");
    eprintln!("  preview <window_id>     - Capture live window thumbnail");
    eprintln!("  desktop <install|cleanup> - Manage KWin authorization desktop entries");
    eprintln!("  tray <cmd>              - System tray operations");
}

async fn run_self_contained_app() -> DynResult<()> {
    // 1. Determine theme path: if shell.qml exists in current dir, use it (dev mode); otherwise extract embedded theme
    let theme_dir = if Path::new("shell.qml").exists() {
        std::env::current_dir()?
    } else {
        let pkg_dir = get_default_package_dir();
        extract_embedded_theme(&pkg_dir)?;
        pkg_dir
    };

    println!("[Caelestia] Starting desktop shell using package at: {}", theme_dir.display());

    // Register desktop authorization entry with notification
    let _ = crate::infrastructure::preview_capture::install_desktop_entry_with_notification(None, None);

    // 2. Start API server in background task
    tokio::spawn(async move {
        let _ = run_api_server(DEFAULT_API_PORT).await;
    });

    // 3. Backup and disable KDE Plasma panels
    let plasma = PlasmaControlUseCase::new(PlasmaAdapter::new());
    let _ = plasma.backup_and_disable("all", Some(std::process::id()));

    // 4. Launch Quickshell
    let mut child = Command::new("quickshell")
        .arg("-p")
        .arg(&theme_dir)
        .spawn()?;

    // 5. Wait for Quickshell process or signal
    let _ = child.wait();

    // 6. On exit, restore original Plasma panels cleanly and clean up authorization entry
    println!("[Caelestia] Quickshell stopped. Restoring original KDE Plasma panels and cleaning up authorization...");
    let _ = plasma.restore();
    let _ = crate::infrastructure::preview_capture::remove_desktop_entry(None);

    Ok(())
}
