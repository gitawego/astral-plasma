use crate::application::get_metrics::GetMetricsUseCase;
use crate::application::launch_app::LaunchAppUseCase;
use crate::application::plasma_service::{run_watchdog_loop, PlasmaControlUseCase};
use crate::application::systemd_service::SystemdControlUseCase;
use crate::application::watch_events::run_event_daemon;
use crate::application::window_control::WindowControlUseCase;
use crate::application::workspace_control::WorkspaceControlUseCase;
use crate::domain::branding;
use crate::domain::ports::DynResult;
use crate::infrastructure::embedded_bundle::{extract_embedded_theme, get_default_package_dir};
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
        "doctor" | "check" => {
            use crate::application::doctor_service::DoctorService;
            let service = DoctorService::new();
            let report = service.run_diagnostics();

            let is_json = args.iter().any(|a| a == "--json");
            if is_json {
                println!("{}", serde_json::to_string_pretty(&report)?);
            } else {
                print!("{}", report.render_terminal());
            }

            if !report.all_required_satisfied {
                std::process::exit(1);
            }
        }
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
                            run_watchdog_loop(pid).await?;
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
        "audio" => {
            use crate::application::audio_streams::audible_streams;

            match args.get(2).map(|s| s.as_str()).unwrap_or("streams") {
                "streams" => {
                    // Which applications are producing sound right now: the
                    // ground truth for "who is playing", so a browser session
                    // that merely claims Playing cannot outrank real audio.
                    let streams = audible_streams()?;
                    let payload: Vec<serde_json::Value> = streams
                        .iter()
                        .map(|s| {
                            serde_json::json!({
                                "name": s.name,
                                "binary": s.binary,
                            })
                        })
                        .collect();
                    println!("{}", serde_json::to_string(&payload)?);
                }
                _ => {
                    eprintln!("Usage: astral-plasma audio streams");
                    std::process::exit(2);
                }
            }
        }
        "shell" => {
            use crate::application::shell_lifecycle::quit_running_shell;

            match args.get(2).map(|s| s.as_str()).unwrap_or("") {
                "exit" => {
                    // Quitting is the whole job: the supervisor that started the
                    // shell restores the Plasma panels when it exits (and a
                    // session that never disabled them has nothing to restore).
                    if quit_running_shell() {
                        println!(r#"{{"success":true}}"#);
                    } else {
                        eprintln!(
                            "Could not reach the running shell. Start it again with ./run.sh"
                        );
                        std::process::exit(1);
                    }
                }
                _ => {
                    eprintln!("Usage: astral-plasma shell exit");
                    std::process::exit(2);
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
            match sub {
                "network" => {
                    use crate::infrastructure::sys_settings::SystemNetworkAdapter;
                    use crate::application::settings_service::NetworkControlUseCase;
                    use std::sync::Arc;
                    let adapter = Arc::new(SystemNetworkAdapter::new());
                    let use_case = NetworkControlUseCase::new(adapter);
                    let op = args.get(3).map(|s| s.as_str()).unwrap_or("status");
                    match op {
                        "status" => {
                            let st = use_case.get_status()?;
                            println!("{}", serde_json::to_string(&st)?);
                        }
                        "scan" => {
                            let aps = use_case.scan_networks()?;
                            println!("{}", serde_json::to_string(&aps)?);
                        }
                        "toggle" => {
                            let on = args.get(4).map(|s| s == "on" || s == "true").unwrap_or(true);
                            use_case.toggle_wifi(on)?;
                            println!(r#"{{"success":true,"wifi":{}}}"#, on);
                        }
                        "connect" => {
                            if let Some(ssid) = args.get(4) {
                                let pass = args.get(5).map(|s| s.as_str());
                                use_case.connect_wifi(ssid, pass)?;
                                println!(r#"{{"success":true,"connected":"{}"}}"#, ssid);
                            }
                        }
                        _ => eprintln!("Usage: astral-plasma settings network <status|scan|toggle|connect>"),
                    }
                }
                "bluetooth" => {
                    use crate::infrastructure::sys_settings::SystemBluetoothAdapter;
                    use crate::application::settings_service::BluetoothControlUseCase;
                    use std::sync::Arc;
                    let adapter = Arc::new(SystemBluetoothAdapter::new());
                    let use_case = BluetoothControlUseCase::new(adapter);
                    let op = args.get(3).map(|s| s.as_str()).unwrap_or("status");
                    match op {
                        "status" => {
                            let st = use_case.get_status()?;
                            println!("{}", serde_json::to_string(&st)?);
                        }
                        "toggle" => {
                            let on = args.get(4).map(|s| s == "on" || s == "true").unwrap_or(true);
                            use_case.toggle_power(on)?;
                            println!(r#"{{"success":true,"powered":{}}}"#, on);
                        }
                        "connect" => {
                            if let Some(mac) = args.get(4) {
                                use_case.connect(mac)?;
                                println!(r#"{{"success":true,"mac":"{}"}}"#, mac);
                            }
                        }
                        "disconnect" => {
                            if let Some(mac) = args.get(4) {
                                use_case.disconnect(mac)?;
                                println!(r#"{{"success":true,"mac":"{}"}}"#, mac);
                            }
                        }
                        _ => eprintln!("Usage: astral-plasma settings bluetooth <status|toggle|connect|disconnect>"),
                    }
                }
                "audio" => {
                    use crate::infrastructure::sys_settings::SystemAudioAdapter;
                    use crate::application::settings_service::AudioControlUseCase;
                    use std::sync::Arc;
                    let adapter = Arc::new(SystemAudioAdapter::new());
                    let use_case = AudioControlUseCase::new(adapter);
                    let op = args.get(3).map(|s| s.as_str()).unwrap_or("status");
                    match op {
                        "status" => {
                            let st = use_case.get_status()?;
                            println!("{}", serde_json::to_string(&st)?);
                        }
                        "volume" => {
                            if let Some(v_str) = args.get(4) {
                                if let Ok(vol) = v_str.parse::<f32>() {
                                    use_case.set_volume(vol)?;
                                    println!(r#"{{"success":true,"volume":{}}}"#, vol);
                                }
                            }
                        }
                        "mute" => {
                            use_case.toggle_mute()?;
                            println!(r#"{{"success":true,"toggled":true}}"#);
                        }
                        "app-volume" => {
                            if let (Some(id_str), Some(v_str)) = (args.get(4), args.get(5)) {
                                if let (Ok(id), Ok(vol)) = (id_str.parse::<u32>(), v_str.parse::<f32>()) {
                                    use_case.set_app_volume(id, vol)?;
                                    println!(r#"{{"success":true,"app":{},"volume":{}}}"#, id, vol);
                                }
                            }
                        }
                        "sink" => {
                            if let Some(id_str) = args.get(4) {
                                if let Ok(id) = id_str.parse::<u32>() {
                                    use_case.set_default_sink(id)?;
                                    println!(r#"{{"success":true,"sink":{}}}"#, id);
                                }
                            }
                        }
                        _ => eprintln!("Usage: astral-plasma settings audio <status|volume|mute|app-volume|sink>"),
                    }
                }
                _ => {
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
                            eprintln!("Failed to invoke Quickshell settings IPC (is Astral Plasma running?)");
                        }
                    }
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
                    eprintln!("Failed to invoke Quickshell theme IPC (is Astral Plasma running?)");
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
                // Durable avatar image import (Settings > Dashboard avatars):
                // copies the picked file into the app config dir so the
                // setting survives deletion of the original source. Prints the
                // path Config.qml must store (the copy, or the original when
                // the source is missing/unreadable).
                "import-image" => {
                    let base_dir = args
                        .get(5)
                        .map(|s| s.as_str().to_string())
                        .unwrap_or_else(|| {
                            branding::config_home()
                                .join(branding::DATA_DIR)
                                .to_string_lossy()
                                .to_string()
                        });
                    match (args.get(3).map(|s| s.as_str()), args.get(4).map(|s| s.as_str())) {
                        (Some(src), Some(kind)) => {
                            match crate::infrastructure::avatar_fs::import_image(src, kind, &base_dir)
                            {
                                Ok(stored) => println!(
                                    "{}",
                                    serde_json::json!({ "success": true, "stored": stored })
                                ),
                                Err(e) => eprintln!("config import-image: {e}"),
                            }
                        }
                        _ => {
                            eprintln!(
                                "Usage: astral-plasma config import-image <src> <host|media> [config_dir]"
                            );
                        }
                    }
                }
                // Ownership-guarded cleanup of a previously imported copy when
                // the setting is reset or its extension changed. Refuses any
                // path this feature did not generate.
                "forget-image" => {
                    let base_dir = args
                        .get(4)
                        .map(|s| s.as_str().to_string())
                        .unwrap_or_else(|| {
                            branding::config_home()
                                .join(branding::DATA_DIR)
                                .to_string_lossy()
                                .to_string()
                        });
                    match args.get(3).map(|s| s.as_str()) {
                        Some(path) => {
                            let removed =
                                crate::infrastructure::avatar_fs::forget_import(path, &base_dir);
                            println!("{}", serde_json::json!({ "success": true, "removed": removed }));
                        }
                        None => {
                            eprintln!("Usage: astral-plasma config forget-image <path> [config_dir]");
                        }
                    }
                }
                _ => {
                    eprintln!("Usage: astral-plasma config write <path> <content>");
                }
            }
        }
        "shortcuts" => {
            use crate::application::shortcut_service::ShortcutControlUseCase;
            use crate::infrastructure::kwin_shortcuts::KWinShortcutsAdapter;
            let adapter = KWinShortcutsAdapter::new();
            let use_case = ShortcutControlUseCase::new(adapter);
            let sub = args.get(2).map(|s| s.as_str()).unwrap_or("status");
            match sub {
                "snapshot" => {
                    let mode = args.get(3).map(|s| s.as_str()).unwrap_or("meta-space");
                    use_case.snapshot(mode)?;
                    println!(r#"{{"success":true,"action":"snapshot","mode":"{}"}}"#, mode);
                }
                "backup" | "bind" => {
                    let mode = args.get(3).map(|s| s.as_str()).unwrap_or("meta-space");
                    use_case.backup_and_bind(mode)?;
                    println!(r#"{{"success":true,"action":"backup_and_bind","mode":"{}"}}"#, mode);
                }
                "restore" => {
                    let restored = use_case.restore()?;
                    println!(r#"{{"success":true,"restored":{}}}"#, restored);
                }
                "status" => {
                    let active = use_case.is_active();
                    println!(r#"{{"active":{}}}"#, active);
                }
                _ => {
                    eprintln!("Usage: astral-plasma shortcuts <snapshot|backup|bind|restore|status> [mode]");
                }
            }
        }
        "watch" | "--daemon" => {
            run_event_daemon().await?;
        }
        "activate" => {
            if args.len() >= 3 {
                let win_ctrl = WindowControlUseCase::new(crate::infrastructure::desktop_factory::create_window_manager_port());
                win_ctrl.activate(&args[2])?;
            }
        }
        "close" => {
            if args.len() >= 3 {
                let win_ctrl = WindowControlUseCase::new(crate::infrastructure::desktop_factory::create_window_manager_port());
                win_ctrl.close(&args[2])?;
            }
        }
        "launch" => {
            if args.len() >= 3 {
                let launcher = LaunchAppUseCase::new(DesktopLauncherAdapter::new());
                launcher.execute(&args[2])?;
            }
        }
        "apps" => {
            let launcher = LaunchAppUseCase::new(DesktopLauncherAdapter::new());
            let list = launcher.list_apps()?;
            println!("{}", serde_json::to_string(&list)?);
        }
        "calendar" => {
            use crate::application::open_calendar::OpenCalendarUseCase;
            let use_case = OpenCalendarUseCase::new();
            let sub = args.get(2).map(|s| s.as_str()).unwrap_or("open");
            match sub {
                "resolve" => {
                    let candidates = use_case.resolve();
                    let dirs = crate::infrastructure::calendar::CalendarAdapter::search_dirs();
                    let res = serde_json::json!({
                        "mime": crate::domain::calendar::CALENDAR_MIME,
                        "mime_default": use_case.mime_default(),
                        "mime_defaults": use_case.mime_defaults(),
                        "override": use_case.override_id(),
                        "candidates": candidates,
                        "options": crate::infrastructure::calendar::calendar_options(&candidates, &dirs),
                        "fallback": crate::infrastructure::calendar::FALLBACK_SETTINGS_COMMAND.join(" "),
                        "fallback_available": use_case.fallback_available(),
                    });
                    println!("{}", serde_json::to_string(&res)?);
                }
                "open" => {
                    let date = args.get(3).map(|s| s.as_str());
                    let res = use_case.execute(date)?;
                    println!("{}", serde_json::to_string(&res)?);
                    if !res.success {
                        std::process::exit(3);
                    }
                }
                _ => {
                    eprintln!("Usage: astral-plasma calendar <resolve|open [YYYY-MM-DD]>");
                }
            }
        }
        "session" => {
            let session_port = crate::infrastructure::desktop_factory::create_desktop_session_port();
            let coordinator = crate::application::desktop_session_coordinator::DesktopSessionCoordinator::new(session_port);
            let sub = if args.len() >= 3 { args[2].as_str() } else { "snapshot" };
            match sub {
                "snapshot" => {
                    let json = coordinator.get_snapshot_json()?;
                    println!("{}", json);
                }
                "capabilities" => {
                    let json = coordinator.get_capabilities_json()?;
                    println!("{}", json);
                }
                _ => {
                    let json = coordinator.get_snapshot_json()?;
                    println!("{}", json);
                }
            }
        }
        "workspaces" => {
            let ws_ctrl = WorkspaceControlUseCase::new(crate::infrastructure::desktop_factory::create_workspace_port());
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
        "omarchy" => {
            let sub = if args.len() >= 3 { args[2].as_str() } else { "status" };
            let home = std::env::var("HOME").unwrap_or_else(|_| "/tmp".to_string());
            let target_dir = std::path::PathBuf::from(home)
                .join(".config")
                .join("omarchy")
                .join("plugins")
                .join("org.astralplasma.omarchy");

            let source_dir = crate::application::shell_lifecycle::shell_config_dir().join("omarchy");

            match sub {
                "install" => {
                    std::fs::create_dir_all(&target_dir)?;
                    let mut copied = false;
                    if source_dir.exists() {
                        for file in &["manifest.json", "Service.qml", "Bar.qml"] {
                            let src = source_dir.join(file);
                            let dst = target_dir.join(file);
                            if src.exists() {
                                std::fs::copy(&src, &dst)?;
                                copied = true;
                            }
                        }
                    }
                    if !copied {
                        crate::infrastructure::embedded_bundle::OMARCHY_DIR.extract(&target_dir)?;
                    }
                    println!("Installed Astral Plasma Omarchy plugin to {}", target_dir.display());
                }
                "remove" | "uninstall" => {
                    if target_dir.exists() {
                        std::fs::remove_dir_all(&target_dir)?;
                        println!("Removed Astral Plasma Omarchy plugin from {}", target_dir.display());
                    } else {
                        println!("Astral Plasma Omarchy plugin not installed");
                    }
                }
                "status" => {
                    let installed = target_dir.join("manifest.json").exists();
                    let payload = serde_json::json!({
                        "installed": installed,
                        "pluginId": "org.astralplasma.omarchy",
                        "path": target_dir.to_string_lossy()
                    });
                    println!("{}", payload);
                }
                _ => {
                    eprintln!("Unknown omarchy command: {}. Available: install, remove, status", sub);
                }
            }
        }
        "metrics" => {
            let metrics_ctrl = GetMetricsUseCase::new(ProcMetricsAdapter::new());
            let json = metrics_ctrl.execute_json()?;
            println!("{}", json);
        }
        "ai" => {
            use crate::application::ai_quota_service::AiQuotaUseCase;
            let ai_service = AiQuotaUseCase::default();
            let sub = if args.len() >= 3 { args[2].as_str() } else { "status" };
            match sub {
                "status" | "quota" => {
                    let warning_thr = args.get(3).and_then(|s| s.parse::<f64>().ok()).unwrap_or(80.0);
                    let critical_thr = args.get(4).and_then(|s| s.parse::<f64>().ok()).unwrap_or(95.0);
                    let snapshot = ai_service.get_status(warning_thr, critical_thr, false)?;
                    println!("{}", serde_json::to_string(&snapshot)?);
                }
                "activity" => {
                    use crate::infrastructure::ai_activity_monitor::{AiActivityMonitor, ACTIVE_AGENT_WINDOW_MS, COMPLETED_WINDOW_MS};
                    let monitor = AiActivityMonitor::new();
                    if let Some(home) = std::env::var("HOME").ok().map(std::path::PathBuf::from) {
                        let now_ms = std::time::SystemTime::now()
                            .duration_since(std::time::UNIX_EPOCH)
                            .unwrap_or_default()
                            .as_millis() as u64;
                        let active_files = AiActivityMonitor::scan_all_active_session_files(&home, ACTIVE_AGENT_WINDOW_MS);
                        for f in active_files {
                            if let Some((m, t, tok, is_completed)) = AiActivityMonitor::parse_model_tokens_and_status_from_file(&f.path) {
                                if !is_completed || now_ms.saturating_sub(f.mtime) < COMPLETED_WINDOW_MS {
                                    monitor.record_activity_full(&m, &t, tok, is_completed).await;
                                }
                            }
                        }

                        if let Some((model, tokens, time_updated)) = AiActivityMonitor::query_opencode_latest_session(&home) {
                            let is_completed = now_ms.saturating_sub(time_updated) >= 3_000;
                            let is_recent = if is_completed {
                                now_ms.saturating_sub(time_updated) < COMPLETED_WINDOW_MS
                            } else {
                                now_ms.saturating_sub(time_updated) < ACTIVE_AGENT_WINDOW_MS
                            };
                            if is_recent {
                                monitor.record_activity_full(&model, "opencode", Some(tokens), is_completed).await;
                            } else if monitor.state.read().await.last_event_epoch_ms < time_updated && monitor.get_state().await.active_agents.is_empty() {
                                let mut st = monitor.state.write().await;
                                st.identity = crate::domain::ai_activity::resolve_model_metadata(&model, "opencode");
                                st.is_active = false;
                                st.intensity = 0.0;
                                st.request_rate_rpm = 0.0;
                                st.last_event_epoch_ms = time_updated;
                            }
                        }

                        if monitor.get_state().await.active_agents.is_empty() {
                            if let Some((path, mtime, _)) = AiActivityMonitor::find_latest_session_file(&home) {
                                if let Some((m, t, _)) = AiActivityMonitor::parse_model_and_tokens_from_file(&path) {
                                    let mut st = monitor.state.write().await;
                                    st.identity = crate::domain::ai_activity::resolve_model_metadata(&m, &t);
                                    st.is_active = false;
                                    st.intensity = 0.0;
                                    st.request_rate_rpm = 0.0;
                                    st.last_event_epoch_ms = mtime;
                                }
                            }
                        }
                    }
                    let state = monitor.get_state().await;
                    println!("{}", serde_json::to_string(&serde_json::json!({
                        "agent": state.identity.tool_source,
                        "model": state.identity.model_id,
                        "display_name": state.identity.display_name,
                        "brand_color": state.identity.brand_color,
                        "brand_icon": state.identity.brand_icon,
                        "is_active": state.is_active,
                        "intensity": state.intensity,
                        "request_rate": state.request_rate_rpm,
                        "token_rate": state.token_rate_tpm,
                        "recent_tokens": state.recent_tokens,
                        "active_agents": state.active_agents,
                    }))?);
                }
                "refresh" => {
                    let warning_thr = args.get(3).and_then(|s| s.parse::<f64>().ok()).unwrap_or(80.0);
                    let critical_thr = args.get(4).and_then(|s| s.parse::<f64>().ok()).unwrap_or(95.0);
                    let snapshot = ai_service.get_status(warning_thr, critical_thr, true)?;
                    println!("{}", serde_json::to_string(&snapshot)?);
                }
                "switch-account" | "switch" => {
                    if args.len() >= 5 {
                        let provider = &args[3];
                        let account_target = &args[4];
                        if provider == "gemini" {
                            let switched = ai_service.switch_gemini_account(account_target)?;
                            println!(r#"{{"success":true,"provider":"gemini","account":"{}"}}"#, switched);
                        } else {
                            eprintln!("Provider '{}' does not currently support multiple account switching", provider);
                            std::process::exit(1);
                        }
                    } else {
                        eprintln!("Usage: astral-plasma ai switch-account <provider> <account_id_or_email>");
                        std::process::exit(1);
                    }
                }
                "login" => {
                    let provider = args.get(3).map(|s| s.as_str()).unwrap_or("gemini");
                    let email_hint = args.get(4).map(|s| s.as_str());
                    if provider == "gemini" {
                        let res = ai_service.login_gemini_oauth(email_hint)?;
                        println!("{}", res);
                    } else {
                        eprintln!("Interactive OAuth login is only supported for 'gemini'");
                        std::process::exit(1);
                    }
                }
                "remove-account" | "remove" => {
                    if args.len() >= 5 {
                        let provider = &args[3];
                        let target = &args[4];
                        let res = ai_service.remove_account(provider, target)?;
                        println!(r#"{{"success":true,"provider":"{}","removed":"{}"}}"#, provider, res);
                    } else {
                        eprintln!("Usage: astral-plasma ai remove-account <provider> <id_or_email>");
                        std::process::exit(1);
                    }
                }
                "add-account" | "add" => {
                    if args.len() >= 5 {
                        let provider = &args[3];
                        let credential = &args[4];
                        let label = args.get(5).map(|s| s.as_str());
                        let id = ai_service.add_account(provider, credential, label, false)?;
                        println!(r#"{{"success":true,"provider":"{}","account_id":"{}"}}"#, provider, id);
                    } else {
                        eprintln!("Usage: astral-plasma ai add-account <provider> <credential> [label]");
                        std::process::exit(1);
                    }
                }
                "list-accounts" | "accounts" => {
                    let provider = args.get(3).map(|s| s.as_str());
                    let list = ai_service.list_accounts(provider)?;
                    println!("{}", serde_json::to_string_pretty(&list)?);
                }
                _ => {
                    eprintln!("Usage: astral-plasma ai <status|refresh|switch-account|login|remove-account|add-account|list-accounts> [args...]");
                    std::process::exit(1);
                }
            }
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
                        let response = serde_json::json!({
                            "service": svc,
                            "menuPath": menu_path,
                            "items": items,
                        });
                        let json = serde_json::to_string(&response)?;
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
                        let (mut x, mut y) = (
                            if args.len() >= 6 { args[5].clone() } else { "0".to_string() },
                            if args.len() >= 7 { args[6].clone() } else { "0".to_string() },
                        );
                        if x == "0" && y == "0" {
                            if let Some((cx, cy)) = crate::infrastructure::x11_input::get_cursor_position() {
                                x = cx.to_string();
                                y = cy.to_string();
                            }
                        }
                        let mut ok = false;
                        if let Ok(out) = std::process::Command::new("qdbus6")
                            .args([svc, path, "org.kde.StatusNotifierItem.Activate", &x, &y])
                            .output()
                        {
                            if out.status.success() && !String::from_utf8_lossy(&out.stderr).contains("Error") {
                                ok = true;
                            }
                        }
                        if !ok {
                            let _ = std::process::Command::new("busctl")
                                .args(["--user", "call", svc, path, "org.kde.StatusNotifierItem", "Activate", "ii", &x, &y])
                                .output();
                        }
                    } else {
                        eprintln!("Usage: astral-plasma tray activate <service> <path> [x] [y]");
                    }
                }
                "context-menu" => {
                    if args.len() >= 5 {
                        let svc = &args[3];
                        let path = &args[4];
                        let (mut x, mut y) = (
                            if args.len() >= 6 { args[5].clone() } else { "0".to_string() },
                            if args.len() >= 7 { args[6].clone() } else { "0".to_string() },
                        );
                        if x == "0" && y == "0" {
                            if let Some((cx, cy)) = crate::infrastructure::x11_input::get_cursor_position() {
                                x = cx.to_string();
                                y = cy.to_string();
                            }
                        }
                        let mut ok = false;
                        if let Ok(out) = std::process::Command::new("qdbus6")
                            .args([svc, path, "org.kde.StatusNotifierItem.ContextMenu", &x, &y])
                            .output()
                        {
                            if out.status.success() && !String::from_utf8_lossy(&out.stderr).contains("Error") {
                                ok = true;
                            }
                        }
                        if !ok {
                            let _ = std::process::Command::new("busctl")
                                .args(["--user", "call", svc, path, "org.kde.StatusNotifierItem", "ContextMenu", "ii", &x, &y])
                                .output();
                        }
                    } else {
                        eprintln!("Usage: astral-plasma tray context-menu <service> <path> [x] [y]");
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
        "wallpaper" => {
            use crate::infrastructure::fs_wallpaper::FsWallpaperAdapter;
            use crate::application::wallpaper_service::{ListWallpapersUseCase, SetWallpaperUseCase, GeneratePaletteUseCase};
            use crate::domain::wallpaper::WallpaperFilter;
            use std::sync::Arc;

            let adapter = Arc::new(FsWallpaperAdapter::new());
            let sub = args.get(2).map(|s| s.as_str()).unwrap_or("list");
            match sub {
                "list" => {
                    let query = args.get(4).cloned();
                    let use_case = ListWallpapersUseCase::new(adapter);
                    let list = match args.get(3).map(|s| s.as_str()) {
                        Some(dir) if !dir.is_empty() => {
                            use_case.execute(Path::new(dir), WallpaperFilter { query, ..Default::default() })?
                        }
                        _ => {
                            use_case.execute_library(WallpaperFilter { query, ..Default::default() })?
                        }
                    };
                    println!("{}", serde_json::to_string(&list)?);
                }

                "get" => {
                    use crate::application::wallpaper_service::ActiveWallpaperUseCase;

                    let raw = args.iter().skip(3).any(|arg| arg == "--raw");
                    let use_case = ActiveWallpaperUseCase::new(adapter);
                    let active = use_case.execute()?;
                    println!("{}", ActiveWallpaperUseCase::format(active.as_deref(), raw));
                }
                "reconcile" => {
                    use crate::application::wallpaper_service::ActiveWallpaperUseCase;

                    let raw = args.iter().skip(3).any(|arg| arg == "--raw");
                    let reconciled = adapter.reconcile_active_wallpaper()?;
                    println!("{}", ActiveWallpaperUseCase::format(reconciled.as_deref(), raw));
                }
                "set" => {
                    if let Some(target) = args.get(3) {
                        let path = PathBuf::from(target);
                        let use_case = SetWallpaperUseCase::new(adapter);
                        use_case.execute(&path)?;
                        println!(r#"{{"success":true,"path":"{}"}}"#, target);
                    } else {
                        eprintln!("Usage: astral-plasma wallpaper set <path>");
                    }
                }
                "palette" => {
                    if let Some(target) = args.get(3) {
                        let path = PathBuf::from(target);
                        let use_case = GeneratePaletteUseCase::new(adapter);
                        let palette = use_case.execute(&path)?;
                        println!("{}", serde_json::to_string(&palette)?);
                    } else {
                        eprintln!("Usage: astral-plasma wallpaper palette <path>");
                    }
                }
                _ => {
                    eprintln!("Usage: astral-plasma wallpaper <list|get|set|palette> [args...]");
                }
            }
        }
        "focus" => {
            // Hand compositor activation back to the user's real window. See
            // get_focus_restore_script: KWin does not reassign activation when a
            // layer surface (the shell's modal) stops requesting keyboard focus.
            use crate::application::watch_events::get_focus_restore_script;

            let sub = args.get(2).map(|s| s.as_str()).unwrap_or("restore");
            if sub != "restore" {
                eprintln!("Usage: astral-plasma focus restore");
            } else {
                let script_file = branding::tmp_file("focus_restore.js");
                if let Err(e) = std::fs::write(&script_file, get_focus_restore_script()) {
                    eprintln!("focus restore: cannot write script to {}: {e}", script_file.display());
                } else {
                    let out = Command::new("qdbus6")
                        .args(["org.kde.KWin", "/Scripting",
                               "org.kde.kwin.Scripting.loadScript", &script_file.to_string_lossy()])
                        .output();
                    if let Ok(o) = out {
                        let num = String::from_utf8_lossy(&o.stdout).trim().to_string();
                        if !num.is_empty() {
                            let path = format!("/Scripting/Script{num}");
                            let _ = Command::new("qdbus6").args(["org.kde.KWin", &path, "org.kde.kwin.Script.run"]).output();
                            let _ = Command::new("qdbus6").args(["org.kde.KWin", &path, "org.kde.kwin.Script.stop"]).output();
                        }
                    }
                }
            }
        }
        "blur" => {
            use crate::infrastructure::kwin_blur::{BlurSettings, KWinBlurAdapter};

            let adapter = KWinBlurAdapter::new();
            let sub = args.get(2).map(|s| s.as_str()).unwrap_or("get");
            match sub {
                "get" => {
                    let current = adapter.current()?;
                    let res = serde_json::json!({
                        "strength": current.as_ref().map(|c| c.strength),
                        "noise_strength": current.as_ref().map(|c| c.noise_strength),
                        "default_strength": crate::infrastructure::kwin_blur::DEFAULT_STRENGTH,
                    });
                    println!("{}", serde_json::to_string(&res)?);
                }
                "set" => {
                    let settings = match args.get(3).and_then(|v| v.parse::<u32>().ok()) {
                        Some(strength) => BlurSettings::clamped(
                            strength,
                            args.get(4).and_then(|v| v.parse::<u32>().ok()).unwrap_or(0),
                        ),
                        None => {
                            eprintln!("Usage: astral-plasma blur set <1-10> [noise 0-10]");
                            std::process::exit(2);
                        }
                    };
                    adapter.apply(&settings)?;
                    let res = serde_json::json!({
                        "success": true,
                        "strength": settings.strength,
                        "noise_strength": settings.noise_strength,
                    });
                    println!("{}", serde_json::to_string(&res)?);
                }
                "fidelity" => {
                    // Map the shell's 0.0..1.0 blurStrength preference (glass
                    // fidelity) onto KWin's inverted 1..10 scale.
                    let pref = args.get(3).and_then(|v| v.parse::<f64>().ok()).unwrap_or(1.0);
                    let settings = BlurSettings::from_normalized(pref);
                    adapter.apply(&settings)?;
                    let res = serde_json::json!({
                        "success": true,
                        "preference": pref,
                        "strength": settings.strength,
                    });
                    println!("{}", serde_json::to_string(&res)?);
                }
                _ => {
                    eprintln!("Usage: astral-plasma blur <get|set <1-10> [noise]|fidelity <0.0-1.0>>");
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
    eprintln!("  run                     - Run full self-contained Astral Plasma desktop shell");
    eprintln!("  serve [--port <port>]   - Run native REST & Unix socket API server");
    eprintln!("  extract [target_dir]    - Extract embedded QML theme bundle");
    eprintln!("  plasma <cmd>            - Plasma panels management: disable, restore, status, watchdog");
    eprintln!("  systemd <cmd>           - User-directed systemd service management: status, install, remove");
    eprintln!("  settings [toggle|open|close] - Control Settings GUI window via IPC");
    eprintln!("  config write <path> <json> - Atomic configuration file persistence");
    eprintln!(
        "  config import-image <src> <host|media> [config_dir] - Durable avatar import (prints stored path JSON)"
    );
    eprintln!(
        "  config forget-image <path> [config_dir] - Remove an owned avatar copy (prints {{success, removed}} JSON)"
    );
    eprintln!("  watch                   - Run event-driven background watcher");
    eprintln!("  visualizer              - Stream real-time audio spectrum & energy JSON");
    eprintln!("  metrics                 - Print system metrics JSON (uptime, ram)");
    eprintln!("  calendar <resolve|open [YYYY-MM-DD]> - Open the default calendar application");
    eprintln!("  workspaces <cmd>        - Virtual desktops: query, switch, ensure");
    eprintln!("  preview <window_id>     - Capture live window thumbnail");
    eprintln!("  desktop <install|cleanup> - Manage KWin authorization desktop entries");
    eprintln!("  shortcuts <cmd>         - Granular shortcut management: backup, bind, restore, status");
    eprintln!("  tray <cmd>              - System tray operations");
    eprintln!("  omarchy <install|remove|status> - Manage hosted Omarchy plugin package");
    eprintln!("  doctor [--json]         - Diagnose and report versions of all system dependencies");
}

async fn run_self_contained_app() -> DynResult<()> {
    // 0. Guard against running standalone Quickshell root beside omarchy-shell
    if crate::infrastructure::desktop_factory::detect_profile() == crate::infrastructure::desktop_factory::EnvironmentProfile::Omarchy {
        let has_override = std::env::var("ASTRAL_STANDALONE_OVERRIDE").is_ok();
        if !has_override {
            eprintln!("[{}] Detected Omarchy host session. Astral Plasma integrates as a plugin under Omarchy.", branding::APP_NAME);
            eprintln!("To install the plugin into omarchy-shell: astral-plasma omarchy install");
            eprintln!("To force standalone execution beside omarchy-shell (experimental): export ASTRAL_STANDALONE_OVERRIDE=1");
            return Ok(());
        }
    }

    // 1. Determine theme path: if shell.qml exists in current dir, use it (dev mode); otherwise extract embedded theme
    let theme_dir = if Path::new("shell.qml").exists() {
        std::env::current_dir()?
    } else {
        let pkg_dir = get_default_package_dir();
        extract_embedded_theme(&pkg_dir)?;
        pkg_dir
    };

    println!("[{}] Starting desktop shell using package at: {}", branding::APP_NAME, theme_dir.display());

    let is_kwin = crate::infrastructure::desktop_factory::detect_compositor() == crate::infrastructure::desktop_factory::CompositorKind::KWin;

    // Register desktop authorization entry with notification (only under KWin)
    if is_kwin {
        let _ = crate::infrastructure::preview_capture::install_desktop_entry_with_notification(None, None);
    }

    // 2. Start API server in background task
    tokio::spawn(async move {
        let _ = run_api_server(DEFAULT_API_PORT).await;
    });

    // 3. Backup and disable KDE Plasma panels (only under KDE)
    if is_kwin {
        let plasma = PlasmaControlUseCase::new(PlasmaAdapter::new());
        let _ = plasma.backup_and_disable("all", Some(std::process::id()));
    }

    // 4. Launch Quickshell
    let mut child = Command::new("quickshell")
        .arg("-p")
        .arg(&theme_dir)
        .spawn()?;

    // 5. Wait for Quickshell process or signal
    #[cfg(unix)]
    {
        use std::time::Duration;
        use tokio::signal::unix::{signal, SignalKind};
        let mut sigterm = signal(SignalKind::terminate())?;
        let mut sigint = signal(SignalKind::interrupt())?;

        loop {
            tokio::select! {
                _ = sigterm.recv() => {
                    let _ = child.kill();
                    let _ = child.wait();
                    break;
                }
                _ = sigint.recv() => {
                    let _ = child.kill();
                    let _ = child.wait();
                    break;
                }
                _ = tokio::time::sleep(Duration::from_millis(200)) => {
                    if let Ok(Some(_)) = child.try_wait() {
                        break;
                    }
                }
            }
        }
    }
    #[cfg(not(unix))]
    {
        let _ = child.wait();
    }

    // 6. On exit, restore original Plasma panels cleanly (only under KDE) and clean up authorization entry
    if is_kwin {
        println!("[{}] Quickshell stopped. Restoring original KDE Plasma panels and cleaning up authorization...", branding::APP_NAME);
        let plasma = PlasmaControlUseCase::new(PlasmaAdapter::new());
        let _ = plasma.restore();
        let _ = crate::infrastructure::preview_capture::remove_desktop_entry(None);
    }

    Ok(())
}
