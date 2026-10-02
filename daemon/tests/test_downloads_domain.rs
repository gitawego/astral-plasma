use astral_plasma::domain::downloads::{
    aggregate_total, clamp_split, derive_filename, eta_seconds, parse_task,
    parse_urls, DownloadStatus, NewDownloadOptions, ARIA2_RPC_PORT, DEFAULT_SPLIT, MAX_SPLIT,
};
#[test]
fn test_status_counts_in_total() {
    assert!(DownloadStatus::Active.counts_in_total());
    assert!(DownloadStatus::Waiting.counts_in_total());
    assert!(DownloadStatus::Paused.counts_in_total());
    assert!(!DownloadStatus::Complete.counts_in_total());
    assert!(!DownloadStatus::Error.counts_in_total());
    assert!(!DownloadStatus::Removed.counts_in_total());
    assert!(!DownloadStatus::Unknown.counts_in_total());
}

#[test]
fn test_status_from_aria2_strings() {
    assert_eq!(DownloadStatus::from_aria2("active"), DownloadStatus::Active);
    assert_eq!(DownloadStatus::from_aria2("waiting"), DownloadStatus::Waiting);
    assert_eq!(DownloadStatus::from_aria2("paused"), DownloadStatus::Paused);
    assert_eq!(DownloadStatus::from_aria2("complete"), DownloadStatus::Complete);
    assert_eq!(DownloadStatus::from_aria2("error"), DownloadStatus::Error);
    assert_eq!(DownloadStatus::from_aria2("removed"), DownloadStatus::Removed);
    assert_eq!(DownloadStatus::from_aria2("weird"), DownloadStatus::Unknown);
}

#[test]
fn test_total_progress_sums_bytes_not_fractions() {
    // A 90%-done small file must not outweigh a 10%-done big file.
    let tasks = vec![
        task("a", DownloadStatus::Active, 100, 90, 10),
        task("b", DownloadStatus::Active, 900, 90, 10),
    ];
    let total = aggregate_total(&tasks);
    assert_eq!(total.completed_length, 180);
    assert_eq!(total.total_length, 1000);
    assert!((total.progress - 0.18).abs() < 1e-9, "must be byte-weighted, got {}", total.progress);
    assert_eq!(total.download_speed, 20);
    assert_eq!(total.active_count, 2);
    assert!(!total.indeterminate);
}

#[test]
fn test_total_excludes_terminal_states() {
    let tasks = vec![
        task("a", DownloadStatus::Active, 100, 50, 5),
        task("done", DownloadStatus::Complete, 1000, 1000, 0),
        task("err", DownloadStatus::Error, 500, 100, 0),
        task("rm", DownloadStatus::Removed, 500, 100, 0),
    ];
    let total = aggregate_total(&tasks);
    assert_eq!(total.active_count, 1);
    assert_eq!(total.total_length, 100);
    assert!((total.progress - 0.5).abs() < 1e-9);
}

#[test]
fn test_total_paused_freezes_honestly() {
    let tasks = vec![task("p", DownloadStatus::Paused, 200, 100, 0)];
    let total = aggregate_total(&tasks);
    assert_eq!(total.active_count, 1);
    assert_eq!(total.download_speed, 0);
    assert!((total.progress - 0.5).abs() < 1e-9);
    assert!(eta_seconds(100, 0).is_none());
}

#[test]
fn test_total_indeterminate_when_no_known_length() {
    let tasks = vec![task("x", DownloadStatus::Active, 0, 0, 100)];
    let total = aggregate_total(&tasks);
    assert!(total.indeterminate);
    assert_eq!(total.progress, 0.0);
    assert_eq!(total.active_count, 1);
}

#[test]
fn test_total_empty_is_zero() {
    let total = aggregate_total(&[]);
    assert_eq!(total.progress, 0.0);
    assert_eq!(total.active_count, 0);
    assert!(!total.indeterminate);
}

#[test]
fn test_eta_seconds() {
    assert_eq!(eta_seconds(1000, 100), Some(10));
    assert_eq!(eta_seconds(0, 100), None);
    assert_eq!(eta_seconds(100, 0), None);
}

#[test]
fn test_parse_urls_multi_line() {
    let v = parse_urls("  https://a/x.iso\n\nhttps://b/y.iso  \n   \n");
    assert_eq!(v, vec!["https://a/x.iso", "https://b/y.iso"]);
    assert!(parse_urls("   \n ").is_empty());
}

#[test]
fn test_clamp_split() {
    assert_eq!(clamp_split(4), 4);
    assert_eq!(clamp_split(0), 1);
    assert_eq!(clamp_split(-3), 1);
    assert_eq!(clamp_split(99), MAX_SPLIT);
    assert_eq!(DEFAULT_SPLIT, 4);
}

#[test]
fn test_derive_filename() {
    assert_eq!(derive_filename("/dl/ubuntu-24.04.iso"), "ubuntu-24.04.iso");
    assert_eq!(derive_filename("https://h/f.iso?token=abc#x"), "f.iso");
    assert_eq!(derive_filename("https://h/my%20file.zip"), "my file.zip");
}

#[test]
fn test_parse_task_normalises_rpc_strings() {
    let v = serde_json::json!({
        "gid": "abc123",
        "status": "active",
        "totalLength": "1000",
        "completedLength": "250",
        "downloadSpeed": "50",
        "dir": "/home/u/Downloads",
        "files": [{"path": "/home/u/Downloads/f.iso", "uris": [{"uri": "https://h/f.iso"}]}],
        "errorCode": "0"
    });
    let t = parse_task(&v).expect("must parse");
    assert_eq!(t.gid, "abc123");
    assert_eq!(t.name, "f.iso");
    assert_eq!(t.status, DownloadStatus::Active);
    assert_eq!(t.total_length, 1000);
    assert_eq!(t.completed_length, 250);
    assert_eq!(t.download_speed, 50);
    assert!((t.progress() - 0.25).abs() < 1e-9);
    assert_eq!(t.remaining(), 750);
    assert!(t.error_code.is_none());
}

#[test]
fn test_parse_task_falls_back_to_uri_then_gid() {
    // No path: first URI wins (AriaNg getFileName behaviour).
    let v = serde_json::json!({
        "gid": "g1",
        "status": "waiting",
        "totalLength": "0",
        "completedLength": "0",
        "downloadSpeed": "0",
        "files": [{"path": "", "uris": [{"uri": "https://h/some%20doc.pdf?x=1"}]}]
    });
    let t = parse_task(&v).expect("must parse");
    assert_eq!(t.name, "some doc.pdf");

    // Nothing at all: gid is the name.
    let v2 = serde_json::json!({"gid": "g2", "status": "paused"});
    let t2 = parse_task(&v2).expect("must parse");
    assert_eq!(t2.name, "g2");
    assert_eq!(t2.total_length, 0);
}

#[test]
fn test_parse_task_rejects_missing_gid() {
    assert!(parse_task(&serde_json::json!({"status": "active"})).is_none());
    assert!(parse_task(&serde_json::json!({"gid": ""})).is_none());
}

#[test]
fn test_new_options_rpc_map_split_sets_both_keys() {
    let opts = NewDownloadOptions {
        dir: Some("/tmp/dl".into()),
        split: Some(8),
        ..Default::default()
    };
    let m = opts.to_rpc_map();
    assert_eq!(m.get("dir").and_then(|v| v.as_str()), Some("/tmp/dl"));
    assert_eq!(m.get("split").and_then(|v| v.as_str()), Some("8"));
    // Per-server cap follows split so parts are not throttled (D6).
    assert_eq!(m.get("max-connection-per-server").and_then(|v| v.as_str()), Some("8"));
    // Resume-by-default (D3 reboot survival).
    assert_eq!(m.get("continue").and_then(|v| v.as_str()), Some("true"));
}

#[test]
fn test_new_options_empty_dir_omitted() {
    let opts = NewDownloadOptions { dir: Some("  ".into()), ..Default::default() };
    assert!(opts.to_rpc_map().get("dir").is_none());
}

#[test]
fn test_aria2_rpc_port_constant() {
    assert_eq!(ARIA2_RPC_PORT, 6800);
}

fn task(gid: &str, status: DownloadStatus, total: u64, done: u64, speed: u64) -> astral_plasma::domain::downloads::DownloadTask {
    astral_plasma::domain::downloads::DownloadTask {
        gid: gid.into(),
        name: gid.into(),
        status,
        total_length: total,
        completed_length: done,
        download_speed: speed,
        dir: String::new(),
        error_code: None,
        completed_at: None,
    }
}

#[test]
fn test_download_history_add_dismiss_clear() {
    use astral_plasma::domain::downloads::DownloadHistory;

    let mut hist = DownloadHistory::default();
    let t1 = task("g1", DownloadStatus::Complete, 100, 100, 0);
    let t2 = task("g2", DownloadStatus::Complete, 200, 200, 0);

    hist.add_or_update(t1.clone());
    hist.add_or_update(t2.clone());
    assert_eq!(hist.items.len(), 2);

    // Update existing task
    let mut t1_updated = t1.clone();
    t1_updated.completed_at = Some(123456);
    hist.add_or_update(t1_updated);
    assert_eq!(hist.items.len(), 2);
    assert_eq!(hist.items[0].completed_at, Some(123456));

    // Dismiss g1
    hist.dismiss("g1");
    assert_eq!(hist.items.len(), 1);
    assert_eq!(hist.items[0].gid, "g2");
    assert!(hist.dismissed.contains(&"g1".to_string()));

    // Attempting to re-add dismissed item is blocked
    hist.add_or_update(t1);
    assert_eq!(hist.items.len(), 1);

    // Clear all
    hist.clear();
    assert_eq!(hist.items.len(), 0);
    assert!(hist.dismissed.contains(&"g2".to_string()));
}


#[test]
fn test_engine_missing_message_names_the_install_command() {
    use astral_plasma::domain::downloads::engine_missing_message;

    let with_command = engine_missing_message(Some("sudo apt install aria2"));
    assert!(with_command.contains("aria2c is not installed"), "{with_command}");
    assert!(with_command.contains("sudo apt install aria2"), "{with_command}");

    // A blank command is not a command: fall back to the project's own source.
    for empty in [None, Some(""), Some("   ")] {
        let message = engine_missing_message(empty);
        assert!(message.contains("aria2c is not installed"), "{message}");
        assert!(message.contains("aria2.github.io"), "{message}");
    }
}

// ============================================================================
// Engine settings, availability and installation
// ============================================================================
// The download manager is optional, and every knob the user can change must be
// expressed once in the domain: the argv aria2c is spawned with, the payload the
// live engine is reconfigured with, the version the shell reports, and the
// outcome of the native (polkit) install flow.

#[test]
fn test_engine_settings_clamp_and_render() {
    use astral_plasma::domain::downloads::EngineSettings;

    // Out-of-range values are clamped, not rejected: a settings file edited by
    // hand must not be able to give aria2 a nonsensical value.
    let clamped = EngineSettings::clamped(0, 999_999_999, "  /tmp/dl  ");
    assert_eq!(clamped.max_concurrent_downloads, 1, "at least one download at a time");
    assert_eq!(clamped.speed_limit_kbps, 10_000_000, "an absurd limit is capped, not passed on");
    assert_eq!(clamped.dir, "/tmp/dl", "the destination is trimmed");

    assert_eq!(EngineSettings::clamped(999, 0, "").max_concurrent_downloads, 16);
    assert_eq!(EngineSettings::clamped(5, 0, "").speed_limit_kbps, 0, "0 means unlimited");

    // Spawn args: the limit is aria2's alphabetical suffix form, and an
    // unlimited engine simply has no limit flag.
    let limited = EngineSettings::clamped(3, 1500, "/dl");
    let args = limited.spawn_args();
    assert!(args.contains(&"--max-concurrent-downloads=3".to_string()), "{args:?}");
    assert!(args.contains(&"--max-overall-download-limit=1500K".to_string()), "{args:?}");
    assert!(args.contains(&"--dir=/dl".to_string()), "{args:?}");

    let unlimited = EngineSettings::clamped(5, 0, "");
    let args = unlimited.spawn_args();
    assert!(!args.iter().any(|a| a.starts_with("--max-overall-download-limit")), "{args:?}");
    assert!(!args.iter().any(|a| a.starts_with("--dir=")), "no dir = aria2's own default: {args:?}");

    // Live reconfiguration: only what is set, always in aria2's string form.
    let live = limited.to_rpc_map();
    assert_eq!(live.get("max-concurrent-downloads").and_then(|v| v.as_str()), Some("3"));
    assert_eq!(live.get("max-overall-download-limit").and_then(|v| v.as_str()), Some("1500K"));
    assert_eq!(live.get("dir").and_then(|v| v.as_str()), Some("/dl"));
    assert_eq!(unlimited.to_rpc_map().get("max-overall-download-limit").and_then(|v| v.as_str()), Some("0"),
        "clearing a limit has to reach the running engine");
}

#[test]
fn test_aria2_version_is_read_from_the_probe_output() {
    use astral_plasma::domain::downloads::parse_aria2_version;

    assert_eq!(
        parse_aria2_version("aria2 version 1.37.0\nCopyright (C) 2006, 2019 Tatsuhiro Tsujikawa\n"),
        Some("1.37.0".to_string())
    );
    assert_eq!(parse_aria2_version("aria2 version 1.36.0-1\n"), Some("1.36.0-1".to_string()));
    assert_eq!(parse_aria2_version("command not found"), None);
    assert_eq!(parse_aria2_version(""), None);
}

#[test]
fn test_install_argv_names_the_package_manager() {
    use astral_plasma::domain::downloads::{aria2_install_argv, aria2_install_command};
    use astral_plasma::domain::voice::PackageManager;

    // The argv is what polkit runs; the command is what the user is shown, and
    // the two must agree (no `sudo` in the argv - pkexec is the privilege step).
    let pacman = aria2_install_argv(PackageManager::Pacman).expect("pacman");
    assert_eq!(pacman, vec!["pacman", "-S", "--noconfirm", "aria2"]);
    assert_eq!(aria2_install_command(PackageManager::Pacman), Some("sudo pacman -S aria2"));

    assert_eq!(aria2_install_argv(PackageManager::Apt).unwrap(), vec!["apt-get", "install", "-y", "aria2"]);
    assert_eq!(aria2_install_argv(PackageManager::Dnf).unwrap(), vec!["dnf", "install", "-y", "aria2"]);
    assert_eq!(
        aria2_install_argv(PackageManager::Zypper).unwrap(),
        vec!["zypper", "--non-interactive", "install", "aria2"]
    );
    assert_eq!(aria2_install_argv(PackageManager::Nix).unwrap(), vec!["nix-env", "-iA", "nixpkgs.aria2"]);

    // An unknown distribution gets no invented command - the caller points at
    // the upstream build instead.
    assert!(aria2_install_argv(PackageManager::Unknown).is_none());
    assert!(aria2_install_command(PackageManager::Unknown).is_none());
}

#[test]
fn test_polkit_exit_codes_become_actionable_outcomes() {
    use astral_plasma::domain::downloads::{install_outcome, InstallOutcome};

    assert_eq!(install_outcome(0), InstallOutcome::Installed);
    assert_eq!(install_outcome(126), InstallOutcome::AuthenticationDismissed);
    assert_eq!(install_outcome(127), InstallOutcome::NoAuthenticationAgent);
    assert_eq!(install_outcome(1), InstallOutcome::Failed(1));

    let command = "sudo pacman -S aria2";
    assert!(install_outcome(0).message(command).contains("installed"));
    // A dismissed or unanswerable prompt must hand the user the command rather
    // than leaving them with a silent failure.
    for code in [126, 127, 1] {
        let message = install_outcome(code).message(command);
        assert!(message.contains(command), "outcome {code} must show the manual command: {message}");
    }
    assert!(install_outcome(127).message(command).to_lowercase().contains("terminal"),
        "without an authentication agent the manual path is the only one left");
    assert!(InstallOutcome::Installed.succeeded());
    assert!(!install_outcome(1).succeeded());
}
