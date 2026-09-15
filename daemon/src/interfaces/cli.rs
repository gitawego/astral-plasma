use crate::application::get_metrics::GetMetricsUseCase;
use crate::application::launch_app::LaunchAppUseCase;
use crate::application::watch_events::run_event_daemon;
use crate::application::window_control::WindowControlUseCase;
use crate::application::workspace_control::WorkspaceControlUseCase;
use crate::domain::ports::DynResult;
use crate::infrastructure::kwin_adapter::KWinAdapter;
use crate::infrastructure::launcher::DesktopLauncherAdapter;
use crate::infrastructure::proc_metrics::ProcMetricsAdapter;
use std::env;

pub async fn run_cli() -> DynResult<()> {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        eprintln!("Usage: caelestia-daemon <command> [args...]");
        eprintln!("Commands:");
        eprintln!("  watch                   - Run event-driven background watcher");
        eprintln!("  activate <window_id>    - Activate window by internal UUID");
        eprintln!("  close <window_id>       - Close window by internal UUID");
        eprintln!("  launch <app/desktop>    - Launch application");
        eprintln!("  workspaces query        - Query virtual desktops JSON");
        eprintln!("  workspaces switch <id>  - Switch to virtual desktop by ID");
        eprintln!("  workspaces ensure <idx> - Ensure virtual desktop at index exists and switch");
        eprintln!("  metrics                 - Print system metrics JSON (uptime, ram)");
        eprintln!("  preview <window_id>     - Capture live window thumbnail");
        eprintln!("  notifs                  - Monitor desktop notifications (Notify)");
        return Ok(());
    }

    match args[1].as_str() {
        "notifs" => {
            crate::application::notif_monitor::run_notif_monitor();
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
                        eprintln!("Usage: caelestia-daemon tray menu <service> <menu_path>");
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
                        eprintln!("Usage: caelestia-daemon tray click <service> <menu_path> <id>");
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
                        eprintln!("Usage: caelestia-daemon tray activate <service> <path>");
                    }
                }
                _ => {
                    eprintln!("Usage: caelestia-daemon tray <menu|click|activate> [args...]");
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
                eprintln!("Usage: caelestia-daemon preview <window_id> [target_width] [slot]");
            }
        }
        _ => {
            eprintln!("Unknown command: {}", args[1]);
        }
    }

    Ok(())
}
