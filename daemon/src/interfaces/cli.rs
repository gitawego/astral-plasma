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
use crate::infrastructure::kwin_window_rules::KWinWindowRulesAdapter;
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
        "app" => {
            run_app_command(&args).await?;
        }
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
        "install" => {
            // The installer scripts call this so the layout has one
            // implementation: they verify the download and place the binary,
            // this decides where the bundle and the owner record go.
            use crate::application::install_service::{install, InstallPaths};
            use crate::domain::install_record::InstallMethod;

            let mut method = InstallMethod::Managed;
            let mut channel = "stable".to_string();
            let mut owner_package: Option<String> = None;
            let mut i = 2;
            while i < args.len() {
                match args[i].as_str() {
                    "--method" => {
                        method = InstallMethod::parse(args.get(i + 1).map(String::as_str).unwrap_or(""))?;
                        i += 2;
                    }
                    "--channel" => {
                        channel = args.get(i + 1).cloned().unwrap_or_else(|| "stable".to_string());
                        i += 2;
                    }
                    "--package" => {
                        owner_package = args.get(i + 1).cloned();
                        i += 2;
                    }
                    other => {
                        eprintln!("Unknown install option: {other}");
                        eprintln!("Usage: astral-plasma install [--method managed|package|checkout] [--channel stable|beta] [--package <name>]");
                        std::process::exit(2);
                    }
                }
            }

            let source = std::env::current_exe()?;
            let outcome = install(
                method,
                &channel,
                owner_package.as_deref(),
                &source,
                &InstallPaths::for_user(),
            )?;
            println!("{}", serde_json::to_string(&outcome.record)?);
        }
        "update" => {
            use crate::application::update_service::UpdateService;

            let sub = args.get(2).map(|s| s.as_str()).unwrap_or("status");
            let service = UpdateService::for_user();
            match sub {
                "status" => {
                    println!("{}", serde_json::to_string(&service.status()?)?);
                }
                "check" => {
                    let force = args.iter().any(|a| a == "--force");
                    match service.check(force) {
                        Ok(status) => println!("{}", serde_json::to_string(&status)?),
                        Err(err) => {
                            eprintln!("[!] Update check failed: {err}");
                            std::process::exit(1);
                        }
                    }
                }
                "apply" => {
                    let confirmed = args.iter().any(|a| a == "--yes" || a == "-y");
                    let status = service.status()?;
                    if !confirmed {
                        match &status.candidate {
                            Some(candidate) => {
                                eprintln!(
                                    "[{}] Ready to install {} ({} MiB):",
                                    branding::APP_NAME,
                                    candidate.version,
                                    candidate.size / (1024 * 1024)
                                );
                                for line in &candidate.highlights {
                                    eprintln!("  - {line}");
                                }
                            }
                            None => {
                                eprintln!(
                                    "[{}] No update is checked. Run `astral-plasma update check` first.",
                                    branding::APP_NAME
                                );
                                std::process::exit(1);
                            }
                        }
                        if let Some(reason) = &status.refuse_reason {
                            eprintln!("  cannot apply: {reason}");
                            std::process::exit(1);
                        }
                        eprintln!("Nothing was changed. Re-run with --yes to install and restart.");
                        std::process::exit(2);
                    }

                    // The shell is asked to exit; the supervisor swaps the
                    // binary and restarts it with the desktop claim intact.
                    let outcome = service.apply(|| {
                        crate::application::shell_lifecycle::quit_running_shell()
                    })?;
                    println!("{}", serde_json::to_string(&outcome)?);
                    if !outcome.restart_requested {
                        eprintln!(
                            "[{}] {} is staged. It starts with the next `astral-plasma run`.",
                            branding::APP_NAME,
                            outcome.version
                        );
                    }
                }
                "revert" => {
                    let confirmed = args.iter().any(|a| a == "--yes" || a == "-y");
                    if !confirmed {
                        eprintln!(
                            "[{}] This goes back to the previous installed release and restarts the shell.",
                            branding::APP_NAME
                        );
                        eprintln!("Nothing was changed. Re-run with --yes to revert.");
                        std::process::exit(2);
                    }
                    let outcome = service.revert(|| {
                        crate::application::shell_lifecycle::quit_running_shell()
                    })?;
                    println!("{}", serde_json::to_string(&outcome)?);
                }
                "seen" => {
                    let version = args
                        .get(3)
                        .cloned()
                        .unwrap_or_else(|| env!("CARGO_PKG_VERSION").to_string());
                    service.mark_seen(&version)?;
                    println!("{}", serde_json::to_string(&service.status()?)?);
                }
                _ => {
                    eprintln!("Usage: astral-plasma update <status|check [--force]|apply [--yes]|revert [--yes]|seen <version>>");
                    std::process::exit(2);
                }
            }
        }
        "changelog" => {
            use crate::infrastructure::embedded_changelog;

            if args.iter().any(|a| a == "--json") {
                println!("{}", serde_json::to_string(&embedded_changelog::all())?);
            } else {
                let since = args
                    .iter()
                    .position(|a| a == "--since")
                    .and_then(|index| args.get(index + 1).cloned());
                for note in embedded_changelog::since(since.as_deref()) {
                    println!("## {} ({})", note.version, note.date);
                    for line in &note.highlights {
                        println!("  - {line}");
                    }
                    println!();
                }
            }
        }
        "uninstall" => {
            use crate::application::uninstall_service::{uninstall, UninstallPaths};

            let confirmed = args.iter().any(|a| a == "--yes" || a == "-y");
            let keep_settings = !args.iter().any(|a| a == "--purge");
            let force = args.iter().any(|a| a == "--force");
            // Called from inside the shell: the shell must exit through its own
            // IPC after the files are gone, so the supervisor can still restore
            // the desktop. Killing the unit here would strand the panels.
            let from_shell = args.iter().any(|a| a == "--from-shell");
            let paths = UninstallPaths::for_user();

            if !confirmed {
                eprintln!("[{}] This removes Astral Plasma from this machine:", branding::APP_NAME);
                for path in [
                    &paths.data_dir,
                    &paths.state_dir,
                    &paths.cache_dir,
                    &paths.systemd_dir.join(branding::SYSTEMD_UNIT),
                ] {
                    if path.exists() {
                        eprintln!("  {}", path.display());
                    }
                }
                eprintln!(
                    "  settings: {}",
                    if keep_settings {
                        "kept (pass --purge to remove them too)"
                    } else {
                        "REMOVED (--purge)"
                    }
                );
                eprintln!("Nothing was changed. Re-run with --yes to continue.");
                std::process::exit(2);
            }

            // Stop the shell before its files disappear, and disable the unit so
            // systemd cannot restart a binary that is about to be deleted.
            if !from_shell {
                let _ = crate::application::shell_lifecycle::quit_running_shell();
            }
            if !branding::test_mode() && !from_shell {
                let _ = std::process::Command::new("systemctl")
                    .args(["--user", "disable", "--now", branding::SYSTEMD_UNIT])
                    .status();
            }

            let report = uninstall(&paths, keep_settings, force)?;
            println!("{}", serde_json::to_string(&report)?);
            for kept in &report.kept {
                eprintln!("[kept] {kept}");
            }
            eprintln!("[✓] Astral Plasma removed.");
        }
        "migrate" => {
            use crate::application::migrations::{MigrationContext, MigrationRunner};

            if args.iter().any(|a| a == "--pending") {
                let ctx = MigrationContext::for_user();
                let runner = MigrationRunner::standard(&ctx);
                let pending: Vec<String> = runner
                    .pending()
                    .iter()
                    .map(|(name, describe)| format!("{name}\t{describe}"))
                    .collect();
                println!("{}", serde_json::to_string(&pending)?);
            } else {
                let ctx = MigrationContext::for_user();
                let completed = MigrationRunner::standard(&ctx).run_pending(&ctx)?;
                println!("{}", serde_json::to_string(&completed)?);
                for entry in completed.iter().filter(|entry| entry.changed) {
                    if let Some(message) = &entry.message {
                        eprintln!("[{}] {message}", crate::domain::branding::APP_NAME);
                    } else {
                        eprintln!("[{}] Applied migration {}", crate::domain::branding::APP_NAME, entry.name);
                    }
                }
                if completed.is_empty() {
                    eprintln!("Nothing to migrate.");
                }
            }
        }
        "plasma" => {
            let sub = args.get(2).map(|s| s.as_str()).unwrap_or("status");
            let plasma = PlasmaControlUseCase::new(PlasmaAdapter::new());
            match sub {
                "disable" => {
                    let target = args.get(3).map(|s| s.as_str()).unwrap_or("all");
                    let pid = args.get(4)
                        .and_then(|p| p.parse::<u32>().ok())
                        .or_else(|| {
                            #[cfg(unix)]
                            {
                                let ppid = unsafe { libc::getppid() as u32 };
                                if ppid > 1 {
                                    Some(ppid)
                                } else {
                                    None
                                }
                            }
                            #[cfg(not(unix))]
                            None
                        });
                    // A claim a previous boot left behind belongs to nobody: hand
                    // it back before this session takes the desktop, or the user
                    // is left with dead Meta keys and a hidden panel that no shell
                    // is serving.
                    release_previous_boot_claim();
                    let removed = plasma.backup_and_disable(target, pid)?;
                    println!(r#"{{"success":true,"removed":{}}}"#, removed);
                }
                // Handing a previous boot's claim back explicitly: `run.sh` calls
                // this before it binds anything, and it is what recovers a desktop
                // left claimed by a machine that was switched off mid-session.
                "release-stale" => {
                    let released = release_previous_boot_claim()
                        .iter()
                        .map(|step| match step {
                            crate::domain::desktop_integration::HandBack::Shortcuts => "shortcuts",
                            crate::domain::desktop_integration::HandBack::Blur => "blur",
                            crate::domain::desktop_integration::HandBack::Panels => "panels",
                        })
                        .collect::<Vec<_>>();
                    println!(r#"{{"success":true,"released":{}}}"#, serde_json::to_string(&released)?);
                }
                "restore" => {
                    let restored = plasma.restore()?;
                    // Always restore shortcuts and blur as well when restoring Plasma,
                    // so the full KDE desktop session and keyboard shortcuts are restored.
                    use crate::domain::ports::ShortcutControlPort;
                    let shortcut_port = crate::infrastructure::kwin_shortcuts::KWinShortcutsAdapter::new();
                    let _ = shortcut_port.restore_relevant_shortcuts();
                    if !branding::test_mode() {
                        let _ = crate::infrastructure::kwin_blur::KWinBlurAdapter::new().restore();
                    }
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
                    eprintln!("Usage: astral-plasma plasma <disable|restore|release-stale|status|watchdog> [args...]");
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
        "desktop" => {
            use crate::application::desktop_entries_service::DesktopEntriesUseCase;
            use crate::infrastructure::desktop_entries_adapter::DesktopEntriesAdapter;
            let sub = args.get(2).map(|s| s.as_str()).unwrap_or("status");
            let use_case = DesktopEntriesUseCase::new(DesktopEntriesAdapter::new());
            match sub {
                "status" => {
                    let st = use_case.get_status()?;
                    println!("{}", serde_json::to_string(&st)?);
                }
                "install" => {
                    let st = use_case.install()?;
                    println!("{}", serde_json::to_string(&st)?);
                }
                "remove" | "cleanup" => {
                    let st = use_case.remove()?;
                    println!("{}", serde_json::to_string(&st)?);
                }
                _ => {
                    eprintln!("Usage: astral-plasma desktop <status|install|remove>");
                }
            }
        }

        // Desktop identity for the browser app window: installs DeepSeek's icon
        // and a matching .desktop so KWin shows it instead of the browser's.
        "dsh-web" => {
            use crate::infrastructure::dsh_web_desktop;
            let sub = args.get(2).map(|s| s.as_str()).unwrap_or("desktop");
            let action = args.get(3).map(|s| s.as_str()).unwrap_or("install");
            let host = args.get(4).map(|s| s.as_str()).unwrap_or("127.0.0.1");
            let width: u32 = args.get(5).and_then(|s| s.parse().ok()).unwrap_or(1440);
            let height: u32 = args.get(6).and_then(|s| s.parse().ok()).unwrap_or(900);
            match (sub, action) {
                ("desktop", "install") => {
                    let changed = dsh_web_desktop::ensure(host, width, height)?;
                    println!("{}", serde_json::json!({"success": true, "changed": changed}));
                }
                ("desktop", "remove") => {
                    let removed = dsh_web_desktop::remove()?;
                    println!("{}", serde_json::json!({"success": true, "removed": removed}));
                }
                ("desktop", "status") => {
                    println!("{}", serde_json::json!({
                        "installed": dsh_web_desktop::is_installed(),
                        "desktop_file": dsh_web_desktop::desktop_path().display().to_string(),
                        "icon_file": dsh_web_desktop::icon_path().display().to_string(),
                        "app_ids": dsh_web_desktop::wayland_app_ids(host),
                    }));
                }
                _ => {
                    eprintln!("Usage: astral-plasma dsh-web desktop [install|remove|status]");
                    std::process::exit(2);
                }
            }
        }

        "notifs" => {
            crate::application::notif_monitor::run_notif_monitor().await?;
        }
        "clipboard" => {
            use crate::infrastructure::clipboard_adapter::{
                read_clipboard, set_clipboard, clear_clipboard,
            };
            let sub = args.get(2).map(|s| s.as_str()).unwrap_or("read");
            match sub {
                "read" => {
                    let item = read_clipboard();
                    println!("{}", serde_json::to_string(&item)?);
                }
                "set" => {
                    let is_image = args.iter().any(|a| a == "--image");
                    let text_args: Vec<&str> = args
                        .iter()
                        .skip(3)
                        .filter(|a| !a.starts_with("--"))
                        .map(|s| s.as_str())
                        .collect();
                    let content = text_args.join(" ");
                    let ok = set_clipboard(&content, is_image);
                    println!(r#"{{"success":{}}}"#, ok);
                }
                "clear" => {
                    let ok = clear_clipboard();
                    println!(r#"{{"success":{}}}"#, ok);
                }
                _ => {
                    eprintln!("Usage: astral-plasma clipboard <read|set|clear> [content] [--image]");
                    std::process::exit(2);
                }
            }
        }
        "device" => {
            use crate::infrastructure::removable_devices_adapter::RemovableDevicesAdapter;
            let adapter = RemovableDevicesAdapter::new();
            let sub = args.get(2).map(|s| s.as_str()).unwrap_or("list");
            let target = args.get(3).map(|s| s.as_str());
            match sub {
                "list" => {
                    let devices = adapter.list_devices()?;
                    println!("{}", serde_json::to_string(&devices)?);
                }
                "match" => {
                    let matched = adapter.match_storage(target.unwrap_or(""))?;
                    println!("{}", serde_json::to_string(&matched)?);
                }
                "mount-open" | "open" => {
                    let mp = adapter.mount_and_open(target)?;
                    println!(r#"{{"success":true,"mountpoint":"{}"}}"#, mp);
                }
                "eject" | "remove" => {
                    adapter.safely_remove(target)?;
                    println!(r#"{{"success":true}}"#);
                }
                _ => eprintln!("Usage: astral-plasma device <list|match|mount-open|eject> [target]"),
            }
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
            // Best-effort: give the shell's xdg-toplevel windows a frameless
            // KWin rule before publishing events. Never fatal - a non-KWin
            // session simply has nothing to configure.
            if KWinWindowRulesAdapter::new().apply().unwrap_or(false) {
                eprintln!("[kwin] applied frameless window rule for the AI Copilot window");
            }
            run_event_daemon().await?;
        }
        "activate" => {
            if args.len() >= 3 {
                let win_ctrl = WindowControlUseCase::new(crate::infrastructure::desktop_factory::create_window_manager_port());
                win_ctrl.activate(&args[2])?;
            }
        }
        // Activate the shell's own toplevels by caption. The watcher filters
        // `skipTaskbar` shell surfaces out of its window list, so the download
        // manager cannot look up its own UUID there; KWin still has the window.
        "activate-title" => {
            if args.len() >= 3 {
                let title = args[2..].join(" ");
                match crate::infrastructure::desktop_factory::detect_compositor() {
                    crate::infrastructure::desktop_factory::CompositorKind::KWin => {
                        crate::infrastructure::kwin_adapter::activate_window_by_title(&title)?;
                    }
                    crate::infrastructure::desktop_factory::CompositorKind::Hyprland => {
                        let _ = std::process::Command::new("hyprctl")
                            .args(["dispatch", "focuswindow", &format!("title:^{}$", title)])
                            .output();
                    }
                }
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
        "system-monitor" | "monitor" => {
            use crate::application::open_system_monitor::OpenSystemMonitorUseCase;
            let use_case = OpenSystemMonitorUseCase::new();
            let sub = args.get(2).map(|s| s.as_str()).unwrap_or("open");
            match sub {
                "resolve" => {
                    let candidates = use_case.resolve();
                    let res = serde_json::json!({
                        "override": use_case.override_id(),
                        "candidates": candidates,
                    });
                    println!("{}", serde_json::to_string(&res)?);
                }
                "open" => {
                    let res = use_case.execute()?;
                    println!("{}", serde_json::to_string(&res)?);
                    if !res.success {
                        std::process::exit(3);
                    }
                }
                _ => {
                    eprintln!("Usage: astral-plasma system-monitor <resolve|open>");
                    std::process::exit(2);
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
                "move-window" => {
                    if args.len() >= 5 {
                        ws_ctrl.move_window(&args[3], &args[4])?;
                    }
                }
                "create" => {
                    let name = if args.len() >= 4 { Some(args[3].as_str()) } else { None };
                    ws_ctrl.create_desktop(name)?;
                }
                "remove" => {
                    if args.len() >= 4 {
                        ws_ctrl.remove_desktop(&args[3])?;
                    }
                }
                "rename" => {
                    if args.len() >= 5 {
                        ws_ctrl.set_desktop_name(&args[3], &args[4])?;
                    }
                }
                "overview" => {
                    ws_ctrl.toggle_overview()?;
                }
                "grid" => {
                    ws_ctrl.toggle_grid()?;
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
        "crash" => {
            use crate::infrastructure::crash_monitor::CrashMonitor;
            let sub = if args.len() >= 3 { args[2].as_str() } else { "recent" };
            match sub {
                "recent" | "list" => {
                    let limit = args.get(3).and_then(|s| s.parse::<usize>().ok()).unwrap_or(5);
                    let crashes = CrashMonitor::scan_recent_crashes(limit);
                    let json = serde_json::to_string_pretty(&crashes)?;
                    println!("{}", json);
                }
                "diagnose" => {
                    let target = args.get(3).map(|s| s.as_str()).unwrap_or("");
                    if target.is_empty() {
                        eprintln!("Usage: astral-plasma crash diagnose <process_name|pid>");
                        std::process::exit(1);
                    }
                    let prompt = CrashMonitor::diagnose(target);
                    println!("{}", prompt);
                }
                "prompt" => {
                    let target = args.get(3).map(|s| s.as_str()).unwrap_or("");
                    if target.is_empty() {
                        eprintln!("Usage: astral-plasma crash prompt <process_name|pid>");
                        std::process::exit(1);
                    }
                    let prompt = CrashMonitor::diagnose(target);
                    print!("{}", prompt);
                }
                _ => {
                    eprintln!("Usage: astral-plasma crash <recent|diagnose|prompt> [target]");
                    std::process::exit(1);
                }
            }
        }
        "tool" | "tools" => {
            use crate::application::agent_tools::AgentToolsUseCase;
            let sub = if args.len() >= 3 { args[2].as_str() } else { "manifest" };
            let tool_args: Vec<String> = args.iter().skip(3).cloned().collect();
            match AgentToolsUseCase::execute_tool(sub, &tool_args) {
                Ok(val) => {
                    println!("{}", serde_json::to_string_pretty(&val)?);
                }
                Err(e) => {
                    let err = serde_json::json!({ "success": false, "error": e.to_string() });
                    eprintln!("{}", serde_json::to_string_pretty(&err)?);
                    std::process::exit(1);
                }
            }
        }
        "skill" | "skills" => {
            use crate::application::skill_service::SkillService;
            let sub = if args.len() >= 3 { args[2].as_str() } else { "status" };
            let skill_name = args.get(3).map(|s| s.as_str()).unwrap_or("astral-desktop-tools");
            match sub {
                "list" => {
                    let list = SkillService::list_skills();
                    println!("{}", serde_json::to_string_pretty(&list)?);
                }
                "status" => {
                    let status = SkillService::get_status(skill_name);
                    println!("{}", serde_json::to_string_pretty(&status)?);
                }
                "install" => {
                    let status = SkillService::install(skill_name)?;
                    println!("{}", serde_json::to_string_pretty(&status)?);
                }
                "remove" | "uninstall" => {
                    let status = SkillService::uninstall(skill_name)?;
                    println!("{}", serde_json::to_string_pretty(&status)?);
                }
                _ => {
                    eprintln!("Usage: astral-plasma skill <status|install|uninstall|list> [skill_name]");
                    std::process::exit(1);
                }
            }
        }

        "metrics" => {
            let metrics_ctrl = GetMetricsUseCase::new(ProcMetricsAdapter::new());
            let json = metrics_ctrl.execute_json()?;
            println!("{}", json);
        }
        // Raw GT busy counters, printed in the state-cache format. This is what
        // the privileged helper runs: file capabilities are ignored on a nosuid
        // mount (where checkouts usually live), so a copy installed outside one
        // with `cap_perfmon=ep` answers this command for the unprivileged
        // daemon. It prints counters, never a percentage: the caller owns the
        // previous sample, so the delta window stays the caller's tick.
        "gpu-pmu-counters" => {
            match crate::infrastructure::gpu_pmu_probe::counters_state_line() {
                Some(state) => print!("{}", state),
                None => {
                    eprintln!(
                        "No GPU perf counter available: this binary needs CAP_PERFMON \
                         (sudo setcap cap_perfmon=ep <path>, or `make gpu-pmu-perms`)"
                    );
                    std::process::exit(2);
                }
            }
        }
        "downloads" => {
            use crate::application::download_service::{Aria2DownloadsPort, DownloadsUseCase};
            use crate::domain::downloads::{clamp_split, EngineSettings, NewDownloadOptions};
            use std::sync::Arc;
            let sub = args.get(2).map(|s| s.as_str()).unwrap_or("snapshot");
            // Settings-supplied defaults (QML passes --dir/--split); the
            // use case fills the rest (~/Downloads, split 4).
            let mut opt_dir: Option<String> = None;
            let mut opt_split: Option<u32> = None;
            let mut opt_max_concurrent: Option<u32> = None;
            let mut opt_limit_kbps: Option<u64> = None;
            let mut positional: Vec<String> = Vec::new();
            let mut i = 3;
            while i < args.len() {
                match args[i].as_str() {
                    "--dir" => {
                        if let Some(v) = args.get(i + 1) {
                            opt_dir = Some(v.clone());
                            i += 1;
                        }
                    }
                    "--split" => {
                        if let Some(v) = args.get(i + 1).and_then(|s| s.parse::<i64>().ok()) {
                            opt_split = Some(clamp_split(v));
                            i += 1;
                        }
                    }
                    "--max-concurrent" => {
                        if let Some(v) = args.get(i + 1).and_then(|s| s.parse::<u32>().ok()) {
                            opt_max_concurrent = Some(v);
                            i += 1;
                        }
                    }
                    "--limit-kbps" => {
                        if let Some(v) = args.get(i + 1).and_then(|s| s.parse::<u64>().ok()) {
                            opt_limit_kbps = Some(v);
                            i += 1;
                        }
                    }
                    other => positional.push(other.to_string()),
                }
                i += 1;
            }
            let resolved_dir = opt_dir.clone().unwrap_or_else(|| {
                crate::domain::branding::home_dir().join("Downloads").to_string_lossy().to_string()
            });
            let engine = EngineSettings::clamped(
                opt_max_concurrent.unwrap_or(crate::domain::downloads::DEFAULT_CONCURRENT_DOWNLOADS),
                opt_limit_kbps.unwrap_or(0),
                &resolved_dir,
            );
            let use_case = DownloadsUseCase::with_engine(
                Arc::new(Aria2DownloadsPort),
                resolved_dir,
                opt_split.unwrap_or(crate::domain::downloads::DEFAULT_SPLIT),
                engine,
            );
            match sub {
                // One-shot state query: the `watch` stream tells QML *when*
                // to re-run this, so QML never polls on a timer.
                "snapshot" => {
                    let _ = use_case.ensure_running();
                    let snap = use_case.snapshot()?;
                    println!("{}", serde_json::to_string(&snap)?);
                }                "ensure" => {
                    let started = use_case.ensure_running()?;
                    println!(r#"{{"success":true,"started":{}}}"#, started);
                }
                // The settings page asks what the engine is and how it could be
                // installed; the `install-engine` verb then performs the native
                // (polkit) install and reports what happened.
                "engine-status" => {
                    println!("{}", serde_json::to_string(&use_case.engine_status()?)?);
                }
                "install-engine" => {
                    println!("{}", serde_json::to_string(&use_case.install_engine()?)?);
                }
                "apply-settings" => {
                    let report = use_case.apply_engine_settings(use_case.engine_settings())?;
                    println!("{}", serde_json::to_string(&report)?);
                }
                "add" => {
                    let _ = use_case.ensure_running();
                    let input = positional.join("\n");
                    let opts = NewDownloadOptions {
                        dir: opt_dir,
                        split: opt_split,
                        ..Default::default()
                    };
                    let gids = use_case.add_urls(&input, opts)?;
                    println!("{}", serde_json::to_string(&serde_json::json!({"gids": gids}))?);
                }
                "pause" | "resume" | "cancel" | "remove" | "retry" => {
                    let gid = positional.first().map(|s| s.as_str()).unwrap_or("");
                    if gid.is_empty() {
                        eprintln!("Usage: astral-plasma downloads {} <gid>", sub);
                        std::process::exit(2);
                    }
                    match sub {
                        "pause" => use_case.pause(gid)?,
                        "resume" => use_case.resume(gid)?,
                        "cancel" => use_case.cancel(gid, false)?,
                        "remove" => { use_case.remove_result(gid)?; }
                        _ => {
                            let new_gid = use_case.retry(gid)?;
                            println!(r#"{{"success":true,"gid":"{}"}}"#, new_gid);
                            return Ok(());
                        }
                    }
                    println!(r#"{{"success":true}}"#);
                }
                // Per-task connection count. aria2 restarts an active task
                // internally when `split` changes and resumes from the control
                // file, so progress is kept.
                "set-parts" => {
                    let gid = positional.first().map(|s| s.as_str()).unwrap_or("");
                    let parts = positional
                        .get(1)
                        .and_then(|s| s.parse::<i64>().ok())
                        .unwrap_or(crate::domain::downloads::DEFAULT_SPLIT as i64);
                    if gid.is_empty() {
                        eprintln!("Usage: astral-plasma downloads set-parts <gid> <parts>");
                        std::process::exit(2);
                    }
                    use_case.set_parts(gid, clamp_split(parts))?;
                    println!(r#"{{"success":true,"gid":"{}","parts":{}}}"#, gid, clamp_split(parts));
                }
                "cancel-delete" => {
                    let gid = positional.first().map(|s| s.as_str()).unwrap_or("");
                    if gid.is_empty() {
                        eprintln!("Usage: astral-plasma downloads cancel-delete <gid>");
                        std::process::exit(2);
                    }
                    use_case.cancel(gid, true)?;
                    println!(r#"{{"success":true}}"#);
                }
                "purge" => {
                    use_case.purge_results()?;
                    println!(r#"{{"success":true}}"#);
                }
                // Event stream: `downloads watch [--dir ..] [--split ..]`.
                // Emits a full snapshot line on start, then re-emits ONLY on
                // change: new/removed gid, status flip, completion, error, or
                // progress crossing a 0.5% quantum. Cadence is 1s while any
                // task is active, 5s idle. Change-only + coarse quantum =
                // ~2 lines/s worst case: the UI never repaints at 60fps.
                "watch" => {
                    crate::application::download_service::run_downloads_watch(use_case).await?;
                }
                _ => {
                    eprintln!("Usage: astral-plasma downloads <snapshot|ensure|engine-status|install-engine|apply-settings|add|pause|resume|set-parts|cancel|cancel-delete|remove|retry|purge|watch> [args...]");
                    std::process::exit(2);
                }
            }
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
                    let activity_use_case = crate::application::ai_activity_service::AiActivityUseCase::default();
                    let state = activity_use_case.query_current_state();
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
                        let switched = ai_service.switch_provider_account(provider, account_target)?;
                        println!(
                            r#"{{"success":true,"provider":"{}","account":"{}"}}"#,
                            provider, switched
                        );
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
                "restore" => {
                    // Hand KWin's blur back: the shell tunes BlurStrength for
                    // its glass, and leaving that override in kwinrc means the
                    // desktop keeps the shell's blur after the shell is gone.
                    let restored = adapter.restore()?;
                    let res = serde_json::json!({ "success": true, "restored": restored });
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
                    eprintln!("Usage: astral-plasma blur <get|set <1-10> [noise]|fidelity <0.0-1.0>|restore>");
                }
            }
        }
        "preview" | "preview-batch" => {
            let cmd = args[1].as_str();
            let is_batch = (cmd == "preview-batch")
                || (args.get(2).map(|s| s.as_str()) == Some("batch"));

            if is_batch {
                let (width_idx, ids_start) = if cmd == "preview-batch" {
                    (2, 3)
                } else {
                    (3, 4)
                };
                let width: u32 = args.get(width_idx).and_then(|w| w.parse().ok()).unwrap_or(480);
                let window_ids: Vec<String> = args.iter().skip(ids_start).cloned().collect();

                // 1. Emit any existing cached previews first for 0ms frame-0 rendering
                for wid in &window_ids {
                    let clean = wid.trim_matches(|c| c == '{' || c == '}');
                    if let Some(cached) = crate::infrastructure::preview_capture::get_existing_preview(clean) {
                        println!("cached:{}:{}", clean, cached);
                    }
                }
                use std::io::Write;
                let _ = std::io::stdout().flush();

                // 2. Brief grace period so the shell entrance animation completes smoothly with zero GPU contention
                tokio::time::sleep(tokio::time::Duration::from_millis(250)).await;

                // 3. Perform parallel batch capture
                if let Err(e) = crate::infrastructure::preview_capture::capture_windows_batch(&window_ids, width).await {
                    eprintln!("Batch preview capture failed: {}", e);
                    std::process::exit(1);
                }
            } else if args.len() >= 3 {
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
                eprintln!("   or: astral-plasma preview batch <target_width> [window_ids...]");
            }
        }
        "voice" => {
            use crate::application::voice_service::{write_event, VoiceService};
            use crate::domain::voice::VoiceEvent;

            let svc = VoiceService::for_settings();
            let sub = args.get(2).map(|s| s.as_str()).unwrap_or("status");
            match sub {
                "status" => {
                    let mut settings = svc.settings().clone();
                    let mut i = 3;
                    while i < args.len() {
                        if args[i] == "--engine" {
                            if let Some(val) = args.get(i + 1) {
                                settings.engine = val.clone();
                                i += 1;
                            }
                        } else if args[i] == "--model" {
                            if let Some(val) = args.get(i + 1) {
                                settings.model = val.clone();
                                i += 1;
                            }
                        }
                        i += 1;
                    }
                    let svc = VoiceService::new(VoiceService::adapter_for_engine(&settings.engine), settings);
                    println!("{}", serde_json::to_string(&svc.status())?);
                }
                "engines" => {
                    let (models, languages) = svc.catalogs();
                    let probe = svc.probe().ok();
                    println!(
                        "{}",
                        serde_json::to_string(&serde_json::json!({
                            "probe": probe,
                            "models": models,
                            "languages": languages,
                        }))?
                    );
                }
                "remove-model" => {
                    let model_id = args
                        .get(3)
                        .cloned()
                        .or_else(|| Some(svc.settings().model.clone()))
                        .unwrap_or_default();
                    match svc.remove_model(&model_id) {
                        Ok(removed) => {
                            println!(
                                "{}",
                                serde_json::to_string(&serde_json::json!({
                                    "success": true,
                                    "model": model_id,
                                    "removed": removed,
                                    "status": svc.status(),
                                }))?
                            );
                        }
                        Err(e) => {
                            println!(
                                "{}",
                                serde_json::to_string(&serde_json::json!({
                                    "success": false,
                                    "error": e.to_string(),
                                }))?
                            );
                        }
                    }
                }
                "install-model" => {
                    let model_id = args
                        .get(3)
                        .cloned()
                        .or_else(|| Some(svc.settings().model.clone()))
                        .unwrap_or_default();
                    // Progress is emitted as JSONL so the UI can render a real
                    // bar rather than an indeterminate spinner.
                    let result = svc.install_model(&model_id, |fraction| {
                        let event = VoiceEvent::Progress(fraction);
                        let _ = write_event(&mut std::io::stdout(), &event);
                    });
                    match result {
                        Ok(path) => {
                            println!(
                                "{}",
                                serde_json::to_string(&serde_json::json!({
                                    "success": true,
                                    "model": model_id,
                                    "path": path.to_string_lossy(),
                                    "status": svc.status(),
                                }))?
                            );
                        }
                        Err(e) => {
                            eprintln!("[voice] {e}");
                            println!(
                                "{}",
                                serde_json::to_string(&serde_json::json!({
                                    "success": false,
                                    "model": model_id,
                                    "error": e.to_string(),
                                }))?
                            );
                        }
                    }
                }
                "session" => {
                    // Control arrives on stdin, events leave on stdout. The
                    // process exits when the utterance finalises, which is what
                    // releases the capture device.
                    //
                    // `--lang <tag>` is a session-scoped override (D9): it
                    // reaches the engine for this session and is never written
                    // back to settings, so dictating in a second language once
                    // does not reconfigure the shell.
                    let language = voice_language_flag(&args);
                    let stdin = std::io::stdin();
                    let stdout = std::io::stdout();
                    match language.as_deref() {
                        Some(tag) => svc.run_control_loop_with_language(stdin, stdout, tag, |w, event| {
                            write_event(w, event).map(|_| ())
                        })?,
                        None => svc.run_control_loop(stdin, stdout, |w, event| {
                            write_event(w, event).map(|_| ())
                        })?,
                    }
                }
                "install-vad-model" => {
                    // Neural endpointing asset (audit §4.2). Same JSONL progress
                    // contract as model installs; absence is never fatal.
                    let result = svc.install_vad_model(|fraction| {
                        let event = VoiceEvent::Progress(fraction);
                        let _ = write_event(&mut std::io::stdout(), &event);
                    });
                    match result {
                        Ok(path) => {
                            println!(
                                "{}",
                                serde_json::to_string(&serde_json::json!({
                                    "success": true,
                                    "model": "silero-vad",
                                    "path": path.to_string_lossy(),
                                    "status": svc.status(),
                                }))?
                            );
                        }
                        Err(e) => {
                            eprintln!("[voice] {e}");
                            println!(
                                "{}",
                                serde_json::to_string(&serde_json::json!({
                                    "success": false,
                                    "error": e.to_string(),
                                }))?
                            );
                        }
                    }
                }
                "serve" => {
                    // Resident STT server (audit §4.3): holds whisper-server
                    // with the model resident and translates the Unix-socket
                    // session protocol to its /inference endpoint, so repeat
                    // utterances skip the ~543 ms model reload entirely.
                    let socket = args.get(3).cloned().unwrap_or_default();
                    let idle_secs = args.get(4).and_then(|s| s.parse::<u64>().ok()).unwrap_or(60);
                    crate::infrastructure::voice_server::serve(socket, idle_secs)?;
                }
                "mic-check" => {
                    // Device-only check: statistics, never audio. `--secs N`
                    // clamps to 1–10; three seconds is the onboarding ritual.
                    let secs = args
                        .windows(2)
                        .find(|w| w[0] == "--secs")
                        .and_then(|w| w[1].parse::<u64>().ok())
                        .unwrap_or(3);
                    match svc.mic_check(secs) {
                        Ok(report) => println!("{}", serde_json::to_string(&report)?),
                        Err(e) => {
                            println!(
                                "{}",
                                serde_json::to_string(&serde_json::json!({
                                    "success": false,
                                    "error": e.to_string(),
                                }))?
                            );
                        }
                    }
                }
                "cloud-key" => {
                    // Opt-in cloud STT credentials. The key is read from stdin
                    // (never argv: argv leaks to history and `ps`), stored
                    // owner-only beside settings, and never printed or logged.
                    use crate::infrastructure::deepgram_stt_adapter as cloud;
                    let op = args.get(3).map(|s| s.as_str()).unwrap_or("status");
                    match op {
                        "set" => {
                            let mut key = String::new();
                            use std::io::Read;
                            std::io::stdin().read_to_string(&mut key).unwrap_or_default();
                            match cloud::store_key(&key) {
                                Ok(()) => println!("{}", serde_json::json!({"success": true})),
                                Err(e) => println!("{}", serde_json::json!({"success": false, "error": e.to_string()})),
                            }
                        }
                        "clear" => match cloud::clear_key() {
                            Ok(removed) => println!("{}", serde_json::json!({"success": true, "removed": removed})),
                            Err(e) => println!("{}", serde_json::json!({"success": false, "error": e.to_string()})),
                        },
                        "test" => match cloud::test_key() {
                            Ok(true) => println!("{}", serde_json::json!({"success": true})),
                            Ok(false) => println!("{}", serde_json::json!({"success": false, "error": "no response"})),
                            Err(e) => println!("{}", serde_json::json!({"success": false, "error": e.to_string()})),
                        },
                        _ => println!(
                            "{}",
                            serde_json::json!({
                                "present": cloud::read_key().is_some(),
                                "engine": "deepgram",
                            })
                        ),
                    }
                }
                "bench" => {
                    use crate::domain::voice::{calculate_cer, calculate_wer};
                    use crate::infrastructure::whisper_stt_adapter::WhisperCppAdapter;

                    let manifest_path = args
                        .windows(2)
                        .find(|w| w[0] == "--manifest")
                        .map(|w| std::path::PathBuf::from(&w[1]))
                        .unwrap_or_else(|| {
                            std::path::PathBuf::from("tests/fixtures/voice/dataset.json")
                        });

                    let model_id = args
                        .windows(2)
                        .find(|w| w[0] == "--model")
                        .map(|w| w[1].clone())
                        .unwrap_or_else(|| "ggml-tiny".to_string());

                    if !manifest_path.exists() {
                        eprintln!("Manifest not found at {}", manifest_path.display());
                        std::process::exit(1);
                    }

                    let content = std::fs::read_to_string(&manifest_path)?;
                    let items: Vec<serde_json::Value> = serde_json::from_str(&content)?;

                    let adapter = WhisperCppAdapter::new();
                    let parent_dir = manifest_path.parent().unwrap_or(std::path::Path::new("."));

                    let mut results = Vec::new();
                    let mut total_wer = 0.0f32;
                    let mut total_cer = 0.0f32;
                    let count = items.len();

                    let bench_start = std::time::Instant::now();

                    for item in &items {
                        let id = item.get("id").and_then(|v| v.as_str()).unwrap_or("");
                        let file = item.get("file").and_then(|v| v.as_str()).unwrap_or("");
                        let lang = item.get("language").and_then(|v| v.as_str()).unwrap_or("auto");
                        let reference = item.get("reference").and_then(|v| v.as_str()).unwrap_or("");

                        let audio_path = parent_dir.join(file);
                        let start = std::time::Instant::now();
                        match adapter.transcribe_file(&audio_path, &model_id, lang) {
                            Ok(t) => {
                                let elapsed = start.elapsed().as_millis() as u64;
                                let wer = calculate_wer(&t.text, reference);
                                let cer = calculate_cer(&t.text, reference);
                                total_wer += wer;
                                total_cer += cer;

                                results.push(serde_json::json!({
                                    "id": id,
                                    "file": file,
                                    "reference": reference,
                                    "hypothesis": t.text,
                                    "language": t.language,
                                    "wer": wer,
                                    "cer": cer,
                                    "latency_ms": elapsed,
                                    "success": true,
                                }));
                            }
                            Err(e) => {
                                results.push(serde_json::json!({
                                    "id": id,
                                    "file": file,
                                    "reference": reference,
                                    "error": e.to_string(),
                                    "success": false,
                                }));
                            }
                        }
                    }

                    let avg_wer = if count > 0 { total_wer / count as f32 } else { 0.0 };
                    let avg_cer = if count > 0 { total_cer / count as f32 } else { 0.0 };
                    let total_elapsed_ms = bench_start.elapsed().as_millis() as u64;

                    let summary = serde_json::json!({
                        "model": model_id,
                        "manifest": manifest_path.to_string_lossy(),
                        "samples": count,
                        "avg_wer": avg_wer,
                        "avg_cer": avg_cer,
                        "total_time_ms": total_elapsed_ms,
                        "results": results,
                    });

                    println!("{}", serde_json::to_string_pretty(&summary)?);
                }
                _ => {
                    eprintln!("Usage: astral-plasma voice <status|engines|install-model [id]|install-vad-model|mic-check [--secs N]|cloud-key <set|clear|test|status>|bench [--manifest path] [--model id]|session [--lang <tag>]|serve [socket] [idle-secs]>");
                }
            }
        }
        "assistant" => {
            use crate::application::assistant_service::AssistantService;
            let assistant_svc = AssistantService::new();
            let sub = args.get(2).map(|s| s.as_str()).unwrap_or("status");
            match sub {
                "status" => {
                    let harnesses = assistant_svc.list_harnesses();
                    let skills = assistant_svc.list_skills();
                    let (def_provider, def_model) = assistant_svc.get_defaults();
                    let providers = assistant_svc.list_providers();
                    let payload = serde_json::json!({
                        "harnesses": harnesses,
                        "skills_count": skills.len(),
                        "default_provider": def_provider,
                        "default_model": def_model,
                        "providers": providers,
                        "status": "ready"
                    });
                    println!("{}", serde_json::to_string(&payload)?);
                }
                "sessions" => {
                    let list = assistant_svc.list_sessions()?;
                    println!("{}", serde_json::to_string(&list)?);
                }
                "get-session" => {
                    let id = args.get(3).map(|s| s.as_str()).unwrap_or("");
                    if id.is_empty() {
                        eprintln!("Usage: astral-plasma assistant get-session <id>");
                        std::process::exit(1);
                    }
                    let session = assistant_svc.get_session(id)?;
                    println!("{}", serde_json::to_string(&session)?);
                }
                "save-session" => {
                    let raw = if let Some(arg) = args.get(3) {
                        arg.clone()
                    } else {
                        use std::io::Read;
                        let mut buf = String::new();
                        std::io::stdin().read_to_string(&mut buf)?;
                        buf
                    };
                    let session: crate::domain::assistant::ChatSession = serde_json::from_str(&raw)
                        .map_err(|e| format!("Invalid session json: {}", e))?;
                    assistant_svc.save_session(&session)?;
                    let res = serde_json::json!({
                        "success": true,
                        "id": session.id
                    });
                    println!("{}", serde_json::to_string(&res)?);
                }
                "delete-session" => {
                    let id = args.get(3).map(|s| s.as_str()).unwrap_or("");
                    if id.is_empty() {
                        eprintln!("Usage: astral-plasma assistant delete-session <id>");
                        std::process::exit(1);
                    }
                    let deleted = assistant_svc.delete_session(id)?;
                    let res = serde_json::json!({
                        "success": deleted,
                        "id": id
                    });
                    println!("{}", serde_json::to_string(&res)?);
                }
                "active-session" => {
                    if let Some(new_id) = args.get(3) {
                        assistant_svc.set_active_session_id(new_id)?;
                        let res = serde_json::json!({
                            "success": true,
                            "active_session_id": new_id
                        });
                        println!("{}", serde_json::to_string(&res)?);
                    } else {
                        let active = assistant_svc.get_active_session_id();
                        let payload = serde_json::json!({
                            "active_session_id": active
                        });
                        println!("{}", serde_json::to_string(&payload)?);
                    }
                }
                "set-model" => {
                    let provider = args.get(3).map(|s| s.as_str()).unwrap_or("");
                    let model = args.get(4).map(|s| s.as_str()).unwrap_or("");
                    if provider.is_empty() || model.is_empty() {
                        eprintln!("Usage: astral-plasma assistant set-model <provider> <model>");
                        std::process::exit(1);
                    }
                    assistant_svc.set_defaults(provider, model)?;
                    let res = serde_json::json!({
                        "success": true,
                        "provider": provider,
                        "model": model
                    });
                    println!("{}", serde_json::to_string(&res)?);
                }
                "skills" => {
                    let skills = assistant_svc.list_skills();
                    println!("{}", serde_json::to_string(&skills)?);
                }
                "sync-skills" => {
                    let linked = assistant_svc.sync_skills_to_user_agents()?;
                    println!(r#"{{"success":true,"synced":{}}}"#, linked);
                }
                "crashes" => {
                    let limit = args.get(3).and_then(|s| s.parse::<usize>().ok()).unwrap_or(5);
                    let crashes = assistant_svc.get_recent_crashes(limit);
                    println!("{}", serde_json::to_string(&crashes)?);
                }
                "provision" => {
                    assistant_svc.ensure_provisioning()?;
                    let st = crate::infrastructure::assistant_harness::runtime_provisioner::RuntimeProvisioner::get_status();
                    let payload = serde_json::json!({
                        "pi_executable": st.pi_executable.map(|p| p.to_string_lossy().to_string()),
                        "hermes_executable": st.hermes_executable.map(|p| p.to_string_lossy().to_string()),
                        "has_mcp_support": st.has_mcp_support,
                        "has_subagents": st.has_subagents,
                        "pi_version": st.pi_version,
                        "status": "ok"
                    });
                    println!("{}", serde_json::to_string(&payload)?);
                }
                // Updating the harness the user runs: the same `pi update` their
                // terminal would run, reported back as JSON (version before and
                // after, and everything pi printed).
                "update-pi" => {
                    use crate::application::assistant_service::PiUpdateTarget;
                    let target = match args.get(3).map(|a| a.as_str()) {
                        Some("--extensions") => PiUpdateTarget::Extensions,
                        Some("--models") => PiUpdateTarget::Models,
                        _ => PiUpdateTarget::Pi,
                    };
                    let report = assistant_svc.update_harness(target)?;
                    println!("{}", serde_json::to_string(&report)?);
                }
                "exec" => {
                    if let Some(cmd) = args.get(3) {
                        let sudo = args.iter().skip(4).any(|a| a == "--sudo");
                        let (stdout, stderr, code) = assistant_svc.execute_command(cmd, sudo).await?;
                        let res = serde_json::json!({
                            "stdout": stdout,
                            "stderr": stderr,
                            "code": code
                        });
                        println!("{}", serde_json::to_string(&res)?);
                    } else {
                        eprintln!("Usage: astral-plasma assistant exec <command> [--sudo]");
                    }
                }
                "chat" => {
                    let mut prompt = String::new();
                    let mut provider = None;
                    let mut model = None;
                    let mut harness = None;

                    let mut i = 3;
                    while i < args.len() {
                        match args[i].as_str() {
                            "--prompt" | "-p" => {
                                if i + 1 < args.len() {
                                    prompt = args[i + 1].clone();
                                    i += 1;
                                }
                            }
                            "--provider" => {
                                if i + 1 < args.len() {
                                    provider = Some(args[i + 1].as_str());
                                    i += 1;
                                }
                            }
                            "--model" => {
                                if i + 1 < args.len() {
                                    model = Some(args[i + 1].as_str());
                                    i += 1;
                                }
                            }
                            "--harness" => {
                                if i + 1 < args.len() {
                                    harness = Some(args[i + 1].as_str());
                                    i += 1;
                                }
                            }
                            other => {
                                if prompt.is_empty() && !other.starts_with('-') {
                                    prompt = other.to_string();
                                }
                            }
                        }
                        i += 1;
                    }

                    if prompt.is_empty() {
                        eprintln!("Usage: astral-plasma assistant chat --prompt \"<prompt>\" [--provider ...] [--model ...] [--harness ...]");
                        std::process::exit(1);
                    }

                    let (tx, mut rx) = tokio::sync::mpsc::channel(64);
                    let printer = tokio::spawn(async move {
                        while let Some(event) = rx.recv().await {
                            if let Ok(line) = serde_json::to_string(&event) {
                                println!("{}", line);
                                use std::io::Write;
                                let _ = std::io::stdout().flush();
                            }
                        }
                    });

                    let turn_result = assistant_svc.stream_turn(&prompt, harness, provider, model, tx).await;
                    let _ = printer.await;
                    turn_result?;
                }
                _ => {
                    eprintln!("Usage: astral-plasma assistant <status|skills|sync-skills|crashes|provision|exec|chat|update-pi [--extensions|--models]> [args...]");
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

/// Extracts `--lang <tag>` from a `voice session` argument vector.
///
/// Supports both `--lang en` and `--lang=en`. Returns `None` when the flag is
/// absent *or* malformed, so a bad invocation degrades to the configured default
/// rather than failing the session outright.
fn voice_language_flag(args: &[String]) -> Option<String> {
    let mut i = 0;
    while i < args.len() {
        let a = &args[i];
        if a == "--lang" {
            return args
                .get(i + 1)
                .filter(|v| !v.trim().is_empty())
                .cloned();
        }
        if let Some(value) = a.strip_prefix("--lang=") {
            return if value.trim().is_empty() {
                None
            } else {
                Some(value.to_string())
            };
        }
        i += 1;
    }
    None
}

fn print_usage() {
    eprintln!("Usage: astral-plasma <command> [args...]");
    eprintln!("Commands:");
    eprintln!("  run                     - Run full self-contained Astral Plasma desktop shell");
    eprintln!("  serve [--port <port>]   - Run native REST & Unix socket API server");
    eprintln!("  extract [target_dir]    - Extract embedded QML theme bundle");
    eprintln!("  install [--method ...]  - Install this binary and its bundle into the managed layout");
    eprintln!("  migrate [--pending]     - Run one-time repairs for existing installs");
    eprintln!("  update <status|check|apply|seen> - Check for, stage and apply a release");
    eprintln!("  changelog [--json] [--since <version>] - Release notes compiled into this build");
    eprintln!("  uninstall [--yes] [--purge] - Remove this install (settings kept unless --purge)");
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
    eprintln!("  gpu-pmu-counters        - Print raw GPU engine busy counters (needs CAP_PERFMON)");
    eprintln!("  calendar <resolve|open [YYYY-MM-DD]> - Open the default calendar application");
    eprintln!("  clipboard <read|set|clear> [content] [--image] - Rich clipboard operations");
    eprintln!("  workspaces <cmd>        - Virtual desktops: query, switch, ensure");
    eprintln!("  preview <window_id>     - Capture live window thumbnail");
    eprintln!("  desktop <install|cleanup> - Manage KWin authorization desktop entries");
    eprintln!("  shortcuts <cmd>         - Granular shortcut management: backup, bind, restore, status");
    eprintln!("  tray <cmd>              - System tray operations");
    eprintln!("  omarchy <install|remove|status> - Manage hosted Omarchy plugin package");
    eprintln!("  doctor [--json]         - Diagnose and report versions of all system dependencies");
}

/// Hand back any desktop claim a previous boot left behind.
///
/// The claim lives in files (the shortcut journal, the panel marker, KWin's blur
/// snapshot), so a machine switched off - or crashed - while the shell ran never
/// released it: the next login starts Plasma with the shell's keys still claimed
/// and no shell serving them. Every session start calls this first; a session
/// whose claim is its own gets an empty list and no side effect.
fn release_previous_boot_claim() -> Vec<crate::domain::desktop_integration::HandBack> {
    use crate::application::stale_claim::StaleClaimRelease;
    let steps = StaleClaimRelease::for_desktop().release_if_stale();
    if !steps.is_empty() {
        eprintln!(
            "[{}] Released a desktop claim from a previous boot: {:?}",
            branding::APP_NAME,
            steps
        );
    }
    steps
}

async fn run_self_contained_app() -> DynResult<()> {
    // First boot (and every start): the registry learns about the bundled apps before
    // the host reads it.
    let _ = crate::application::preinstalled::reconcile_preinstalled(
        &branding::data_dir(),
        &bundled_apps_dir(),
    );
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

    // 1. One-time repairs for installs that already exist.
    //
    // A release cannot fix an installed layout by shipping code alone: the files
    // on disk came from an older build. Migrations run before anything is
    // claimed, so a failure stops the start instead of leaving a desktop that is
    // half old and half new. A dev checkout (`shell.qml` in the working
    // directory) is not an install and must never be migrated.
    if !Path::new("shell.qml").exists() {
        for entry in crate::application::migrations::run_pending_for_user()? {
            if !entry.changed {
                continue;
            }
            if let Some(message) = entry.message {
                eprintln!("[{}] {message}", branding::APP_NAME);
            } else {
                eprintln!("[{}] Applied migration {}", branding::APP_NAME, entry.name);
            }
        }
    }

    // 2. Determine theme path: if shell.qml exists in current dir, use it (dev mode); otherwise extract embedded theme
    let theme_dir = if Path::new("shell.qml").exists() {
        std::env::current_dir()?
    } else {
        let pkg_dir = get_default_package_dir();
        extract_embedded_theme(&pkg_dir)?;
        pkg_dir
    };

    println!("[{}] Starting desktop shell using package at: {}", branding::APP_NAME, theme_dir.display());

    let is_kwin = crate::infrastructure::desktop_factory::detect_compositor() == crate::infrastructure::desktop_factory::CompositorKind::KWin;

    // 3. Start API server in background task
    tokio::spawn(async move {
        let _ = run_api_server(DEFAULT_API_PORT).await;
    });

    // Discovery belongs to the daemon: shortly after login, then every six
    // hours. It never blocks startup, and a failed check only records a reason
    // the UI can show; a shell that is offline simply stays quiet.
    if std::env::var("ASTRAL_PLASMA_DISABLE_UPDATE_CHECK").is_err() {
        tokio::spawn(async {
            tokio::time::sleep(std::time::Duration::from_secs(60)).await;
            loop {
                let _ = tokio::task::spawn_blocking(|| {
                    crate::application::update_service::UpdateService::for_user().check(false)
                })
                .await;
                tokio::time::sleep(std::time::Duration::from_secs(6 * 3600)).await;
            }
        });
    }

    // 4. Take the desktop claim once, and record that this session holds it.
    //
    // An update restarts Quickshell only. `execv` keeps this pid, and the handoff
    // marker is keyed on it: a restarted shell that found the marker would
    // otherwise take a second claim on a desktop that is still claimed, and hand
    // the user's panels back twice.
    use crate::application::restart::{exec_run, has_previous, install_staged, restore_previous};
    use crate::domain::install_record::{now_unix, record_version};
    use crate::domain::update_state::{ClaimHandoff, RestartRequest, UpdateState};

    let paths = crate::application::update_service::UpdatePaths::for_user();
    let boot_id = crate::application::stale_claim::current_claim_boot_id();
    let handoff_path = ClaimHandoff::path();
    let inherited_claim = is_kwin
        && ClaimHandoff::read(&handoff_path)
            .map(|marker| marker.covers(boot_id.as_deref(), std::process::id()))
            .unwrap_or(false);

    if is_kwin && !inherited_claim {
        let _ = crate::infrastructure::preview_capture::install_desktop_entry_with_notification(None, None);
        // A previous boot's claim comes back before this session takes one.
        release_previous_boot_claim();
        let plasma = PlasmaControlUseCase::new(PlasmaAdapter::new());
        let _ = plasma.backup_and_disable("all", Some(std::process::id()));
        let shortcuts = crate::infrastructure::kwin_shortcuts::KWinShortcutsAdapter::new();
        use crate::domain::ports::ShortcutControlPort;
        let _ = shortcuts.bind_shortcuts("meta-space");
        let _ = ClaimHandoff {
            schema: crate::domain::update_state::STATE_SCHEMA,
            boot_id: boot_id.clone(),
            supervisor_pid: std::process::id(),
            at_unix: now_unix(),
        }
        .write(&handoff_path);
    } else if inherited_claim {
        eprintln!(
            "[{}] Restarted with the desktop claim intact; panels and shortcuts stay as they are.",
            branding::APP_NAME
        );
    }

    // 5. Run the shell, restarting it when a verified update is staged.
    loop {
        // Apply a staged update before the shell starts, so an update accepted
        // while no shell was running still lands. The swap happens with
        // Quickshell down, then this process re-execs the new binary - which is
        // what makes the new code (not just the new bundle) actually run.
        if let Some(request) = RestartRequest::read(&paths.restart_path) {
            // A manual revert already put the previous binary back; only the
            // exec is left. Swapping again would delete the file it names.
            if request.already_in_place {
                RestartRequest::clear(&paths.restart_path);
                let _ = record_version(&request.target_version, now_unix());
                eprintln!(
                    "[{}] Reverted to {}; restarting.",
                    branding::APP_NAME,
                    request.target_version
                );
                exec_run(&crate::application::restart::exec_target(&paths.live_binary))?;
            }
            match install_staged(Path::new(&request.staged_binary), &paths.live_binary) {
                Ok(previous) => {
                    RestartRequest::clear(&paths.restart_path);
                    // Keep the outgoing record so a revert can name the version
                    // it is going back to.
                    let _ = std::fs::copy(
                        &paths.record_path,
                        paths.record_path.with_extension("json.prev"),
                    );
                    let _ = record_version(&request.target_version, now_unix());
                    eprintln!(
                        "[{}] Update {} is in place (previous binary kept at {}); restarting.",
                        branding::APP_NAME,
                        request.target_version,
                        previous.display()
                    );
                    exec_run(&crate::application::restart::exec_target(&paths.live_binary))?;
                }
                Err(err) => {
                    RestartRequest::clear(&paths.restart_path);
                    eprintln!("[{}] Could not apply the staged update: {err}", branding::APP_NAME);
                    let mut state = UpdateState::load(&paths.state_path);
                    state.record_error(format!("staged update not applied: {err}"));
                    let _ = state.save(&paths.state_path);
                }
            }
        }

        let mut healthy = false;
        for attempt in 1..=2 {
            let mut child = spawn_quickshell(&theme_dir)?;
            match wait_until_ready(&mut child, &theme_dir).await {
                Startup::Ready => {
                    healthy = true;
                    let mut state = UpdateState::load(&paths.state_path);
                    if state.failed_starts != 0 {
                        state.failed_starts = 0;
                        let _ = state.save(&paths.state_path);
                    }
                    wait_for_exit(&mut child).await;
                    break;
                }
                Startup::Exited => {
                    eprintln!(
                        "[{}] Quickshell exited before it answered IPC (attempt {attempt}/2).",
                        branding::APP_NAME
                    );
                }
            }
        }

        if !healthy {
            // Two starts that never came up: put the previous binary back rather
            // than leaving the user with a shell that cannot start at all.
            if has_previous(&paths.live_binary) {
                let mut state = UpdateState::load(&paths.state_path);
                state.failed_starts = state.failed_starts.saturating_add(1);
                let reason = "the restarted shell did not answer IPC after two attempts".to_string();
                // Name the release that failed, then put its record back with
                // its binary: a version claim that no longer matches the file on
                // disk would make the next update compare against a lie.
                let failed_version = crate::domain::install_record::current()
                    .ok()
                    .flatten()
                    .map(|record| record.version)
                    .unwrap_or_else(|| "the new release".to_string());
                state.rollback = Some(crate::domain::update_state::RollbackInfo {
                    version: failed_version,
                    reason: reason.clone(),
                    at_unix: now_unix(),
                });
                let _ = state.save(&paths.state_path);
                if restore_previous(&paths.live_binary).is_ok() {
                    if let Ok(Some(previous)) = crate::domain::install_record::InstallRecord::read(
                        &paths.record_path.with_extension("json.prev"),
                    ) {
                        let _ = previous.write(&paths.record_path);
                    }
                    eprintln!("[{}] Rolled back: {reason}", branding::APP_NAME);
                    exec_run(&crate::application::restart::exec_target(&paths.live_binary))?;
                }
            }
            break;
        }

        // A restart request that arrived while the shell ran is handled at the
        // top of the loop, which swaps the binary and execs it.
        if RestartRequest::read(&paths.restart_path).is_none() {
            break;
        }
    }

    // 6. On exit, restore original Plasma panels cleanly (only under KDE), restore shortcuts, and clean up authorization entry
    if is_kwin {
        println!("[{}] Quickshell stopped. Restoring original KDE Plasma panels...", branding::APP_NAME);
        let plasma = PlasmaControlUseCase::new(PlasmaAdapter::new());
        let _ = plasma.restore();
        let shortcuts = crate::infrastructure::kwin_shortcuts::KWinShortcutsAdapter::new();
        use crate::domain::ports::ShortcutControlPort;
        let _ = shortcuts.restore_relevant_shortcuts();
        let _ = crate::infrastructure::preview_capture::remove_desktop_entry(None);
        ClaimHandoff::clear(&handoff_path);
    }

    Ok(())
}

/// How a freshly started Quickshell behaved.
enum Startup {
    /// It answered its own IPC: the shell is alive and serving.
    Ready,
    /// The process ended before it ever answered.
    Exited,
}

/// `astral app ...` — the app-platform command surface.
///
/// P2 ships the read-only half (`list`, `available`) so the registry the host uses
/// and the list a user sees are the same data, read by the same code. Install,
/// update, pin, and rollback arrive with packaging (P5); until then they say so
/// instead of pretending.
async fn run_app_command(args: &[String]) -> DynResult<()> {
    use crate::application::app_service::{installed_app, read_registry};
    use crate::domain::app_compat::{check_levels, HostApi};

    let sub = args.get(2).map(String::as_str).unwrap_or("list");
    let is_json = args.iter().any(|a| a == "--json");
    let data_dir = branding::data_dir();
    let apps_root = data_dir.join("apps");

    match sub {
        "list" | "installed" => {
            // First-boot semantics: every bundled app is installed. Idempotent, and the
            // user's own state (version, pin, grants) always wins.
            if let Ok(outcome) = crate::application::preinstalled::reconcile_preinstalled(&data_dir, &bundled_apps_dir()) {
                for (id, reason) in &outcome.skipped {
                    eprintln!("skipped bundled app {id}: {reason}");
                }
            }
            let registry = read_registry(&data_dir)?;
            let host = HostApi::current(running_quickshell_version().as_deref());
            let rows: Vec<_> = registry
                .apps
                .iter()
                .map(|entry| {
                    let installed = installed_app(entry, false);
                    let fit = check_levels(
                        installed.kernel_api,
                        installed.min_quickshell.as_deref(),
                        &host,
                    );
                    // The recorded name, with the manifest as a fallback for entries
                    // written before the registry carried one.
                    let name = if entry.name.is_empty() {
                        std::fs::read_to_string(apps_root.join(&entry.id).join("manifest.json"))
                            .ok()
                            .and_then(|text| serde_json::from_str::<serde_json::Value>(&text).ok())
                            .and_then(|value| value.get("name").and_then(|n| n.as_str()).map(str::to_string))
                            .unwrap_or_else(|| entry.id.clone())
                    } else {
                        entry.name.clone()
                    };

                    serde_json::json!({
                        "id": entry.id,
                        "name": name,
                        "version": entry.version,
                        "kernelApi": entry.kernel_api,
                        "preinstalled": entry.preinstalled,
                        "enabled": entry.enabled,
                        "pinned": entry.pinned,
                        "autoUpdate": entry.auto_update,
                        "compatible": fit.is_compatible(),
                        "reason": fit.issue().map(|issue| issue.to_string()),
                        "blocked": entry.blocked,
                    })
                })
                .collect();

            if is_json {
                println!("{}", serde_json::to_string_pretty(&rows)?);
            } else if rows.is_empty() {
                println!("No apps installed.");
            } else {
                println!(
                    "{:<34} {:<10} {:>4}  {:<12} {}",
                    "ID", "VERSION", "API", "STATE", "NOTE"
                );
                for row in &rows {
                    let state = if !row["enabled"].as_bool().unwrap_or(false) {
                        "disabled"
                    } else if row["compatible"].as_bool().unwrap_or(false) {
                        "ready"
                    } else {
                        "incompatible"
                    };
                    println!(
                        "{:<34} {:<10} {:>4}  {:<12} {}",
                        row["id"].as_str().unwrap_or("-"),
                        row["version"].as_str().unwrap_or("-"),
                        row["kernelApi"].as_u64().unwrap_or(0),
                        state,
                        row["reason"].as_str().unwrap_or(""),
                    );
                }
            }
        }
        "available" => {
            use crate::application::app_catalog_service::{load, CatalogSource};

            let Some(catalog_path) = catalog_arg(args) else {
                println!("{}", apps_not_written_yet("available"));
                return Ok(());
            };
            let source = CatalogSource::parse(&catalog_path);
            let catalog = load(&source)?;
            if catalog.offerable().next().is_none() {
                println!("No apps in {}", catalog_path);
                return Ok(());
            }
            println!("{:<34} {:<10} {:>4}  {}", "ID", "VERSION", "API", "TRUST");
            for entry in catalog.offerable() {
                println!(
                    "{:<34} {:<10} {:>4}  {}",
                    entry.id,
                    entry.version,
                    entry.kernel_api,
                    entry.trust.as_deref().unwrap_or("-"),
                );
            }
        }
        "new" => {
            use crate::application::app_sdk::{create_app, Template};

            let Some(id) = args.get(3) else {
                return Err("usage: astral app new <reverse.dns.id> [--template surface|layer-surface|service] [--dir <path>]".into());
            };
            let template = args
                .iter()
                .position(|arg| arg == "--template")
                .and_then(|index| args.get(index + 1))
                .and_then(|name| Template::parse(name))
                .unwrap_or(Template::Surface);
            let target = match args.iter().position(|arg| arg == "--dir") {
                Some(index) => std::path::PathBuf::from(
                    args.get(index + 1).cloned().unwrap_or_default(),
                ),
                None => std::path::PathBuf::from(id.rsplit('.').next().unwrap_or(id)),
            };

            let created = create_app(id, template, &target)?;
            println!("Created {} ({}, {})", created.manifest.id, created.manifest.name, template.name());
            println!("  {}", target.join("manifest.json").display());
            println!("  {}", target.join("shell.qml").display());
            println!("  {}", target.join("README.md").display());
            println!();
            println!("Next:");
            println!("  astral app dev {}   # run it (needs the sandbox, P6)", target.display());
            println!("  astral app test {}", target.display());
            println!("  astral app pack {}", target.display());
        }
        "lint" => {
            use crate::application::app_sdk::lint_dir;

            let dir = app_dir_arg(args, 3)?;
            let problems = lint_dir(&dir)?;
            if problems.is_empty() {
                println!("{}: clean", dir.display());
            } else {
                for problem in &problems {
                    eprintln!("{problem}");
                }
                return Err(format!("{} problem(s) in {}", problems.len(), dir.display()).into());
            }
        }
        "pack" => {
            use crate::application::app_sdk::pack_dir;

            let dir = app_dir_arg(args, 3)?;
            let out = args
                .iter()
                .position(|arg| arg == "--out")
                .and_then(|index| args.get(index + 1))
                .map(std::path::PathBuf::from);
            let packed = pack_dir(&dir, out.as_deref())?;
            println!("{}", packed.path.display());
            println!("  digest sha256:{}", packed.digest);
            println!("  {} file(s)", packed.files);
        }
        "install" => {
            use crate::application::app_install::install_file;
            use crate::domain::app_compat::HostApi;

            let Some(target) = args.get(3) else {
                return Err("usage: astral app install <file.astralapp | app-id> [--catalog <path>] [--accept-permissions] [--allow-downgrade]".into());
            };
            let accept = args.iter().any(|flag| flag == "--accept-permissions");
            let allow_downgrade = args.iter().any(|flag| flag == "--allow-downgrade");
            let host = HostApi::current(running_quickshell_version().as_deref());
            let data_dir = branding::data_dir();
            let apps_root = data_dir.join("apps");

            let installed = if std::path::Path::new(target).is_file() {
                install_file(
                    &data_dir,
                    &apps_root,
                    std::path::Path::new(target),
                    &host,
                    accept,
                    allow_downgrade,
                )?
            } else {
                use crate::application::app_catalog_service::{install_from_catalog, load, CatalogSource};

                let catalog_path = catalog_arg(args).ok_or_else(|| {
                    format!(
                        "installing '{target}' needs a catalog: pass --catalog <path> (or install a .astralapp file)"
                    )
                })?;
                let source = CatalogSource::parse(&catalog_path);
                let catalog = load(&source)?;
                install_from_catalog(
                    &catalog,
                    &source,
                    &data_dir,
                    &apps_root,
                    target,
                    &host,
                    accept,
                    allow_downgrade,
                )?
            };
            println!("{} {} ({})", installed.outcome, installed.id, installed.version);
            println!("  payload {}", installed.payload.display());
            println!("  digest sha256:{}", installed.digest);
            println!("  {} file(s)", installed.files);
        }
        "remove" | "uninstall" => {
            use crate::application::app_install::remove_app;

            let Some(id) = args.get(3) else {
                return Err("usage: astral app remove <app-id> [--purge]".into());
            };
            let purge = args.iter().any(|flag| flag == "--purge");
            let removed = remove_app(
                &branding::data_dir(),
                &branding::data_dir().join("apps"),
                id,
                purge,
            )?;
            println!("Removed {}", removed.id);
            if removed.kept_data {
                println!("  kept app data (--purge removes it)");
            }
        }
        "dev" => {
            use crate::application::app_sdk::lint_dir;

            let dir = app_dir_arg(args, 3)?;
            let problems = lint_dir(&dir)?;
            if !problems.is_empty() {
                for problem in &problems {
                    eprintln!("{problem}");
                }
                return Err(format!("{} lint problem(s); fix them before running", problems.len()).into());
            }

            let sandboxed = args.iter().any(|arg| arg == "--sandbox");
            let print_only = args.iter().any(|arg| arg == "--print-command");
            let command = dev_command(&dir, sandboxed)?;

            if print_only {
                println!("{}", command.join(" "));
                return Ok(());
            }
            if sandboxed && which_binary("bwrap").is_none() {
                return Err("--sandbox needs bubblewrap (bwrap); install it or drop the flag".into());
            }

            println!("Running {} ({})", dir.display(), if sandboxed { "sandboxed" } else { "unsandboxed dev" });
            println!("  {}", command.join(" "));
            let status = std::process::Command::new(&command[0])
                .args(&command[1..])
                .status()?;
            if !status.success() {
                return Err(format!("app exited with {status}").into());
            }
        }
        "test" => {
            use crate::application::app_sdk::lint_dir;

            let dir = app_dir_arg(args, 3)?;
            let problems = lint_dir(&dir)?;
            if !problems.is_empty() {
                for problem in &problems {
                    eprintln!("{problem}");
                }
                return Err(format!("{} lint problem(s); not running suites", problems.len()).into());
            }
            let tests_dir = dir.join("tests");
            let mut suites: Vec<std::path::PathBuf> = std::fs::read_dir(&tests_dir)
                .map(|entries| {
                    entries
                        .flatten()
                        .map(|entry| entry.path())
                        .filter(|path| {
                            path.file_name()
                                .and_then(|name| name.to_str())
                                .map(|name| name.starts_with("tst_") && name.ends_with(".qml"))
                                .unwrap_or(false)
                        })
                        .collect()
                })
                .unwrap_or_default();
            suites.sort();
            if suites.is_empty() {
                println!("{}: no suites in tests/", dir.display());
                return Ok(());
            }
            let mut failed = 0;
            for suite in &suites {
                let output = std::process::Command::new("qml6")
                    .arg("-platform")
                    .arg("offscreen")
                    .arg(suite)
                    .env("QT_QPA_PLATFORM", "offscreen")
                    .env("QML_XHR_ALLOW_FILE_READ", "1")
                    .env("QT_ASSUME_STDERR_HAS_CONSOLE", "1")
                    .output();
                match output {
                    Ok(result) => {
                        let log = format!(
                            "{}{}",
                            String::from_utf8_lossy(&result.stdout),
                            String::from_utf8_lossy(&result.stderr)
                        );
                        let ok = result.status.success()
                            && log.contains("PASS")
                            && !log.contains("FAIL");
                        println!(
                            "{} ... {}",
                            suite.display(),
                            if ok { "PASSED" } else { "FAILED" }
                        );
                        if !ok {
                            failed += 1;
                            eprint!("{log}");
                        }
                    }
                    Err(err) => {
                        println!("{} ... skipped ({err})", suite.display());
                    }
                }
            }
            if failed > 0 {
                return Err(format!("{failed} suite(s) failed").into());
            }
        }
        "enable" | "disable" => {
            let Some(id) = args.get(3) else {
                return Err(format!("usage: astral app {sub} <app-id>").into());
            };
            let mut registry = read_registry(&data_dir)?;
            let enabled = sub == "enable";
            let changed = crate::application::app_service::set_enabled(&mut registry, id, enabled)?;
            if changed {
                crate::application::app_service::write_registry(&data_dir, &registry)?;
                println!("{} {}", if enabled { "Enabled" } else { "Disabled" }, id);
            } else {
                println!("{id} is already {}", if enabled { "enabled" } else { "disabled" });
            }
        }
        other => {
            println!("{}", apps_not_written_yet(other));
        }
    }
    Ok(())
}

/// The command that runs an app for its author.
///
/// Two modes, and the difference is honest: the plain mode runs the app on the
/// developer's own session (fast, no isolation), the sandboxed mode reuses the
/// launcher's mount set from the P0 spike. The platform's promise is the sandboxed
/// one; the plain one exists so a first `astral app dev` does not require bubblewrap
/// on day one.
fn dev_command(dir: &std::path::Path, sandboxed: bool) -> DynResult<Vec<String>> {
    let modules = sdk_modules()?;
    let payload = dir.canonicalize()?.display().to_string();
    if !sandboxed {
        return Ok(vec![
            "env".to_string(),
            format!("QML_IMPORT_PATH={modules}"),
            "quickshell".to_string(),
            "-p".to_string(),
            payload,
        ]);
    }

    let runtime = std::env::var("XDG_RUNTIME_DIR").unwrap_or_else(|_| "/run/user/1000".to_string());
    let mut command: Vec<String> = [
        "bwrap",
        "--unshare-all",
        "--die-with-parent",
        "--new-session",
        "--ro-bind", "/usr", "/usr",
        "--ro-bind", "/lib", "/lib",
        "--ro-bind", "/lib64", "/lib64",
        "--ro-bind-try", "/etc/ld.so.cache", "/etc/ld.so.cache",
        "--ro-bind", "/etc/fonts", "/etc/fonts",
        // Without the shared font cache the sandbox rebuilds it: 569 ms instead of
        // 121 ms of startup (spec C.2).
        "--ro-bind-try", "/var/cache/fontconfig", "/var/cache/fontconfig",
        "--ro-bind-try", "/etc/xdg", "/etc/xdg",
        // Without /sys, EGL falls back to software (spec C.2).
        "--ro-bind-try", "/sys", "/sys",
        "--dev", "/dev",
        "--dev-bind-try", "/dev/dri", "/dev/dri",
        "--ro-bind-try", "/dev/dri", "/dev/dri",
        "--proc", "/proc",
        "--tmpfs", "/dev/shm",
        "--tmpfs", "/tmp",
        "--dir", "/run/astral",
    ]
    .iter()
    .map(|arg| arg.to_string())
    .collect();

    let socket = format!("{runtime}/{}", std::env::var("WAYLAND_DISPLAY").unwrap_or_else(|_| "wayland-1".to_string()));
    command.push("--ro-bind".into());
    command.push(socket);
    command.push("/run/astral/wayland".into());
    command.push("--ro-bind".into());
    command.push(modules);
    command.push("/sdk".into());
    command.push("--ro-bind".into());
    command.push(payload);
    command.push("/app".into());
    command.push("--clearenv".into());
    for (key, value) in [
        ("HOME", "/run/astral/home"),
        ("XDG_RUNTIME_DIR", "/run/astral"),
        ("WAYLAND_DISPLAY", "/run/astral/wayland"),
        ("XDG_CONFIG_HOME", "/run/astral/config"),
        ("XDG_CACHE_HOME", "/run/astral/cache"),
        ("XDG_DATA_HOME", "/run/astral/data"),
        ("QML_IMPORT_PATH", "/sdk"),
        ("LC_ALL", "C.UTF-8"),
    ] {
        command.push("--setenv".into());
        command.push(key.into());
        command.push(value.into());
    }
    command.push("quickshell".into());
    command.push("-p".into());
    command.push("/app".into());
    Ok(command)
}

/// Where the SDK module tree is (`Astral.AppKit`, `Astral.Kernel.Host`).
///
/// Resolution order matters: an installed package first (that is what a real author
/// has), then `ASTRAL_SDK_PATH` for a custom install, then the checkout the running
/// binary belongs to, so `astral app dev` works from a git clone before anything is
/// installed. Nothing is guessed from the current directory: an author's app is not
/// a copy of the SDK.
fn sdk_modules() -> DynResult<String> {
    let mut candidates: Vec<std::path::PathBuf> = Vec::new();
    candidates.push(crate::domain::branding::default_package_dir().join("modules"));
    if let Ok(path) = std::env::var("ASTRAL_SDK_PATH") {
        let root = std::path::PathBuf::from(path);
        candidates.push(root.join("modules"));
        candidates.push(root);
    }
    if let Ok(exe) = std::env::current_exe() {
        // `<repo>/daemon/target/<profile>/astral-plasma` -> `<repo>/modules`
        for ancestor in exe.ancestors().skip(1) {
            let candidate = ancestor.join("modules/Astral/AppKit/qmldir");
            if candidate.is_file() {
                candidates.push(ancestor.join("modules"));
                break;
            }
        }
    }
    for candidate in candidates {
        if candidate.join("Astral/AppKit/qmldir").is_file() {
            return Ok(candidate.display().to_string());
        }
    }
    Err("cannot find the Astral SDK: install Astral, or set ASTRAL_SDK_PATH to a checkout".into())
}

/// `which`, without a dependency: look for the binary on PATH and require it to be
/// executable, so "bwrap is installed" means it can actually run.
fn which_binary(name: &str) -> Option<std::path::PathBuf> {
    use std::os::unix::fs::PermissionsExt;

    for dir in std::env::var("PATH").unwrap_or_default().split(':') {
        if dir.is_empty() {
            continue;
        }
        let candidate = std::path::Path::new(dir).join(name);
        if let Ok(metadata) = std::fs::metadata(&candidate) {
            if metadata.is_file() && metadata.permissions().mode() & 0o111 != 0 {
                return Some(candidate);
            }
        }
    }
    None
}

/// Where the bundled apps live: the installed package first, then the checkout the
/// running binary belongs to (a dev session has no package).
fn bundled_apps_dir() -> std::path::PathBuf {
    let packaged = branding::default_package_dir().join("modules/Astral/Apps");
    if packaged.is_dir() {
        return packaged;
    }
    if let Ok(exe) = std::env::current_exe() {
        for ancestor in exe.ancestors().skip(1) {
            let candidate = ancestor.join("modules/Astral/Apps");
            if candidate.is_dir() {
                return candidate;
            }
        }
    }
    packaged
}

/// `--catalog <path>` when the caller passed one.
fn catalog_arg(args: &[String]) -> Option<String> {
    args.iter()
        .position(|arg| arg == "--catalog")
        .and_then(|index| args.get(index + 1))
        .cloned()
}

fn app_dir_arg(args: &[String], index: usize) -> DynResult<std::path::PathBuf> {
    let Some(dir) = args.get(index) else {
        return Err("usage: astral app <lint|pack|test> <app-directory>".into());
    };
    let path = std::path::PathBuf::from(dir);
    if !path.join("manifest.json").is_file() {
        return Err(format!("{} has no manifest.json; is it an app?", path.display()).into());
    }
    Ok(path)
}

/// A refusal that names the phase, because a command that silently does nothing
/// is indistinguishable from one that worked.
fn apps_not_written_yet(subcommand: &str) -> String {
    match subcommand {
        "available" => "No catalog yet: catalog, install, update, pin, and rollback land with \
packaging (P5 of docs/APPS-PLATFORM-SPEC.md). Nothing was changed."
            .to_string(),
        other => format!(
            "`astral app {other}` is not implemented yet: install, update, pin and rollback land \
with the catalog in P5 of docs/APPS-PLATFORM-SPEC.md. Nothing was changed."
        ),
    }
}

/// `quickshell --version` as a plain version string, when it answers.
fn running_quickshell_version() -> Option<String> {
    let output = std::process::Command::new("quickshell")
        .arg("--version")
        .output()
        .ok()?;
    if !output.status.success() {
        return None;
    }
    let text = String::from_utf8_lossy(&output.stdout);
    text.split_whitespace()
        .find(|token| token.chars().next().is_some_and(|c| c.is_ascii_digit()))
        .map(str::to_string)
}

fn spawn_quickshell(theme_dir: &Path) -> DynResult<tokio::process::Child> {
    // A stock Quickshell cannot initialise QtWebEngine on its own (QtWebEngine
    // must run before QGuiApplication, and Chromium needs argv[0]). When the
    // user installed the runtime shim, hand it to the shell so the embedded DSH
    // web view works without rebuilding Quickshell. See domain::quickshell_host.
    let mut command = tokio::process::Command::new("quickshell");
    command.arg("-p").arg(theme_dir);
    if let Some(preload) = crate::domain::quickshell_host::preload_library() {
        let existing = env::var("LD_PRELOAD").ok();
        command.env(
            "LD_PRELOAD",
            crate::domain::quickshell_host::preload_env_value(&preload, existing.as_deref()),
        );
    }
    Ok(command.spawn()?)
}

/// Wait until the shell answers its IPC, or ends.
///
/// Health is a real answer from the shell, not a sleep: the update design rolls
/// back on this signal, so a timer that happens to expire would roll back a
/// working release.
async fn wait_until_ready(child: &mut tokio::process::Child, theme_dir: &Path) -> Startup {
    use std::time::Duration;

    let deadline = tokio::time::Instant::now() + Duration::from_secs(20);
    loop {
        if let Ok(Some(_)) = child.try_wait() {
            return Startup::Exited;
        }
        if shell_answers(theme_dir).await {
            return Startup::Ready;
        }
        if tokio::time::Instant::now() >= deadline {
            // Still running but silent: not a start we can stand behind.
            let _ = child.kill().await;
            return Startup::Exited;
        }
        tokio::time::sleep(Duration::from_millis(250)).await;
    }
}

async fn shell_answers(theme_dir: &Path) -> bool {
    use std::time::Duration;

    let probe = tokio::process::Command::new("quickshell")
        .arg("ipc")
        .arg("-p")
        .arg(theme_dir)
        .arg("show")
        .output();
    matches!(
        tokio::time::timeout(Duration::from_secs(3), probe).await,
        Ok(Ok(output)) if output.status.success()
    )
}

/// Wait for the shell to exit, forwarding termination signals to it.
async fn wait_for_exit(child: &mut tokio::process::Child) {
    use std::time::Duration;

    #[cfg(unix)]
    {
        use tokio::signal::unix::{signal, SignalKind};
        let Ok(mut sigterm) = signal(SignalKind::terminate()) else {
            let _ = child.wait().await;
            return;
        };
        let Ok(mut sigint) = signal(SignalKind::interrupt()) else {
            let _ = child.wait().await;
            return;
        };

        loop {
            tokio::select! {
                _ = sigterm.recv() => {
                    let _ = child.kill().await;
                    let _ = child.wait().await;
                    break;
                }
                _ = sigint.recv() => {
                    let _ = child.kill().await;
                    let _ = child.wait().await;
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
        let _ = child.wait().await;
    }
}
