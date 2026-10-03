use astral_plasma::application::open_system_monitor::OpenSystemMonitorUseCase;
use astral_plasma::domain::ports::SystemMonitorPort;
use astral_plasma::domain::system_monitor::{
    desktop_entry_supports_system_monitor, parse_exec_command, system_monitor_app_from_settings,
    system_monitor_candidates,
};
use astral_plasma::infrastructure::system_monitor::SystemMonitorAdapter;

#[test]
fn test_desktop_entry_supports_system_monitor() {
    let plasma_desktop = r#"
[Desktop Entry]
Name=System Monitor
GenericName=System Monitor
Comment=Monitor app and system resource usage
Exec=plasma-systemmonitor
Icon=utilities-system-monitor
Type=Application
Categories=Qt;KDE;System;
Keywords=task;manager;process;cpu;memory;
"#;
    assert!(
        desktop_entry_supports_system_monitor(plasma_desktop, "org.kde.plasma-systemmonitor"),
        "plasma-systemmonitor desktop entry must be recognized as system monitor"
    );

    let mission_center_desktop = r#"
[Desktop Entry]
Name=Mission Center
Comment=Monitor system resource usage
Exec=mission-center %u
Icon=io.missioncenter.MissionCenter
Type=Application
Categories=GNOME;GTK;System;Monitor;
"#;
    assert!(
        desktop_entry_supports_system_monitor(mission_center_desktop, "io.missioncenter.MissionCenter"),
        "Mission Center desktop entry must be recognized"
    );

    let gnome_desktop = r#"
[Desktop Entry]
Name=System Monitor
GenericName=System Monitor
Comment=View current processes and monitor system state
Exec=gnome-system-monitor
Icon=org.gnome.SystemMonitor
Type=Application
Categories=GNOME;GTK;System;Monitor;
"#;
    assert!(
        desktop_entry_supports_system_monitor(gnome_desktop, "org.gnome.SystemMonitor"),
        "GNOME System Monitor must be recognized"
    );

    let btop_desktop = r#"
[Desktop Entry]
Type=Application
Name=btop
GenericName=Resource Monitor
Comment=Resource monitor that shows usage and stats
Exec=btop
Terminal=true
Categories=System;Monitor;ConsoleOnly;
"#;
    assert!(
        desktop_entry_supports_system_monitor(btop_desktop, "btop"),
        "btop resource monitor must be recognized"
    );

    // Negative tests: non-system-monitors must NOT be recognized
    let calc_desktop = r#"
[Desktop Entry]
Name=Calculator
Exec=kcalc
Type=Application
Categories=Qt;KDE;Utility;Calculator;
"#;
    assert!(
        !desktop_entry_supports_system_monitor(calc_desktop, "org.kde.kcalc"),
        "Calculator must not be recognized as system monitor"
    );

    let text_desktop = r#"
[Desktop Entry]
Name=Kate
Exec=kate -b %U
Type=Application
Categories=Qt;KDE;Utility;TextEditor;
"#;
    assert!(
        !desktop_entry_supports_system_monitor(text_desktop, "org.kde.kate"),
        "Text editor must not be recognized as system monitor"
    );
}

#[test]
fn test_system_monitor_candidates_ordering() {
    let installed = vec![
        "org.gnome.SystemMonitor".to_string(),
        "org.kde.plasma-systemmonitor".to_string(),
    ];
    let fallbacks = vec!["btop".to_string(), "htop".to_string()];

    // Without override: well-known monitors are prioritized
    let res1 = system_monitor_candidates(None, &installed, &fallbacks);
    assert!(!res1.is_empty());
    assert_eq!(res1[0], "org.kde.plasma-systemmonitor");

    // With user override: override always comes first
    let res2 = system_monitor_candidates(Some("custom-monitor"), &installed, &fallbacks);
    assert_eq!(res2[0], "custom-monitor");

    // Deduplication check
    let dup_installed = vec!["btop".to_string(), "btop.desktop".to_string()];
    let dup_res = system_monitor_candidates(None, &dup_installed, &["btop".to_string()]);
    let btop_count = dup_res.iter().filter(|c| c.as_str() == "btop").count();
    assert_eq!(btop_count, 1, "Candidates must be deduplicated");
}

#[test]
fn test_parse_exec_command() {
    // Normal command with page ID
    let (prog, args) = parse_exec_command("plasma-systemmonitor --page-id overview.page").unwrap();
    assert_eq!(prog, "plasma-systemmonitor");
    assert_eq!(args, vec!["--page-id", "overview.page"]);

    // Strips %u, %f, %F, %U
    let (prog2, args2) = parse_exec_command("gnome-system-monitor %U").unwrap();
    assert_eq!(prog2, "gnome-system-monitor");
    assert!(args2.is_empty());

    // Quoted arguments
    let (prog3, args3) = parse_exec_command("foo --title \"System Activity\" %f").unwrap();
    assert_eq!(prog3, "foo");
    assert_eq!(args3, vec!["--title", "System Activity"]);

    // Empty command
    assert!(parse_exec_command("").is_none());
    assert!(parse_exec_command("   ").is_none());
}

#[test]
fn test_system_monitor_app_from_settings() {
    let json1 = r#"{"dashboard": {"systemMonitorApp": "io.missioncenter.MissionCenter"}}"#;
    assert_eq!(
        system_monitor_app_from_settings(json1),
        Some("io.missioncenter.MissionCenter".to_string())
    );

    let json2 = r#"{"system": {"monitorApp": "btop"}}"#;
    assert_eq!(
        system_monitor_app_from_settings(json2),
        Some("btop".to_string())
    );

    let json_empty = r#"{"dashboard": {"systemMonitorApp": ""}}"#;
    assert_eq!(system_monitor_app_from_settings(json_empty), None);

    let json_missing = r#"{"dashboard": {"width": 800}}"#;
    assert_eq!(system_monitor_app_from_settings(json_missing), None);
}

#[test]
fn test_system_monitor_adapter_and_use_case_resolution() {
    let adapter = SystemMonitorAdapter::new();
    let candidates = adapter.resolve();

    // On this Linux system, plasma-systemmonitor is installed
    assert!(
        !candidates.is_empty(),
        "Candidate list should find installed system monitor applications on Linux"
    );

    let use_case = OpenSystemMonitorUseCase::new();
    let resolved = use_case.resolve();
    assert_eq!(candidates, resolved);

    // With explicit override
    let override_uc = OpenSystemMonitorUseCase::with_override("my-special-monitor");
    assert_eq!(override_uc.override_id(), Some("my-special-monitor"));
    let res_override = override_uc.resolve();
    assert_eq!(res_override.first().map(|s| s.as_str()), Some("my-special-monitor"));
}
