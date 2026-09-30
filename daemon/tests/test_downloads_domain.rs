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
    }
}
