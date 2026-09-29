//! The restart hand-over between two sessions.
//!
//! A theme restart runs two watchdogs for a moment: the outgoing one hands the
//! desktop back (panels + shortcuts) while the incoming session claims it. The
//! two claims must not interleave - that is how the shortcuts ended up dead and
//! the panel configuration half-restored.

use astral_plasma::application::plasma_service::wait_for_restore_to_finish;
use astral_plasma::application::watch_events::{run_shell_ipc_command, shell_ipc_arguments};
use astral_plasma::infrastructure::plasma_adapter::remove_pid_file_owned_by;
use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::PathBuf;
use std::time::{Duration, Instant};

fn temp_dir(name: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("astral-handover-{name}-{}", std::process::id()));
    let _ = fs::remove_dir_all(&dir);
    fs::create_dir_all(&dir).expect("temp dir");
    dir
}

#[test]
fn the_outgoing_watchdog_never_deletes_the_incoming_pid_file() {
    let dir = temp_dir("pidfile");
    let pid_file = dir.join("watchdog.pid");

    // The outgoing watchdog (pid 111) must not remove a record written by the
    // incoming one (pid 222): that is how a session ended up with a live
    // watchdog and `watchdog_pid: null`.
    fs::write(&pid_file, "222").unwrap();
    assert!(!remove_pid_file_owned_by(&pid_file, 111));
    assert!(pid_file.exists(), "another process's record must survive");

    // Its own record is removed.
    fs::write(&pid_file, "111").unwrap();
    assert!(remove_pid_file_owned_by(&pid_file, 111));
    assert!(!pid_file.exists());

    // A missing or unparseable file is a no-op, not a panic.
    assert!(!remove_pid_file_owned_by(&pid_file, 111));
    fs::write(&pid_file, "not a pid").unwrap();
    assert!(!remove_pid_file_owned_by(&pid_file, 111));

    let _ = fs::remove_dir_all(&dir);
}

#[test]
fn the_incoming_session_waits_for_the_outgoing_restore() {
    let dir = temp_dir("restore-wait");
    let lock = dir.join(".restoring");

    // No lock: returns immediately.
    let start = Instant::now();
    wait_for_restore_to_finish(&dir, Duration::from_secs(5));
    assert!(start.elapsed() < Duration::from_millis(200), "no lock must not wait");

    // A live hand-back: the wait ends when the lock is released.
    fs::write(&lock, "111").unwrap();
    let waiter_dir = dir.clone();
    let waiter = std::thread::spawn(move || {
        let start = Instant::now();
        wait_for_restore_to_finish(&waiter_dir, Duration::from_secs(5));
        start.elapsed()
    });
    std::thread::sleep(Duration::from_millis(300));
    let _ = fs::remove_file(&lock);
    let waited = waiter.join().unwrap();
    assert!(waited >= Duration::from_millis(250), "the wait must observe the lock, got {waited:?}");
    assert!(waited < Duration::from_secs(5), "the wait must end when the restore does, got {waited:?}");

    // A stale lock cannot hang startup forever: the timeout bounds it.
    fs::write(&lock, "111").unwrap();
    let start = Instant::now();
    wait_for_restore_to_finish(&dir, Duration::from_millis(400));
    let elapsed = start.elapsed();
    assert!(elapsed >= Duration::from_millis(350), "a stale lock must be waited out, got {elapsed:?}");
    assert!(elapsed < Duration::from_secs(3), "the timeout must bound the wait, got {elapsed:?}");

    let _ = fs::remove_dir_all(&dir);
}

#[tokio::test]
async fn a_slow_shell_cannot_wedge_the_shortcut_interface() {
    let dir = temp_dir("shell-ipc");
    let stub = dir.join("quickshell");
    fs::write(&stub, "#!/bin/sh\nsleep 30\n").unwrap();
    fs::set_permissions(&stub, fs::Permissions::from_mode(0o755)).unwrap();
    let arguments = shell_ipc_arguments("overview.toggle").expect("whitelisted action");

    // A hung shell is abandoned at the deadline instead of blocking the caller:
    // this is what left every shortcut dead while the interface queued.
    let start = Instant::now();
    let ok = run_shell_ipc_command(
        stub.to_str().unwrap(),
        &dir,
        &arguments,
        Duration::from_millis(300),
    )
    .await;
    assert!(!ok, "a hung shell must report failure");
    let elapsed = start.elapsed();
    assert!(
        elapsed >= Duration::from_millis(250) && elapsed < Duration::from_secs(3),
        "the call must end at the deadline, got {elapsed:?}"
    );

    // A healthy shell still reports success.
    fs::write(&stub, "#!/bin/sh\nexit 0\n").unwrap();
    assert!(
        run_shell_ipc_command(stub.to_str().unwrap(), &dir, &arguments, Duration::from_millis(500)).await,
        "a healthy shell must report success"
    );

    let _ = fs::remove_dir_all(&dir);
}

/// Two processes stop-and-spawn the watchdog at session start (the daemon's
/// startup and the `plasma disable` the shell runs from QML). Their hand-over
/// must not interleave: a `stop` landing after the last `spawn` leaves the
/// session with no watchdog, and the shell then exits without restoring the
/// panels. This pins the lock that serializes them.
#[test]
fn watchdog_handover_is_serialized_across_processes() {
    use astral_plasma::application::plasma_service::with_watchdog_lock;
    use std::sync::atomic::{AtomicUsize, Ordering};
    use std::sync::Arc;

    let inside = Arc::new(AtomicUsize::new(0));
    let overlap = Arc::new(AtomicUsize::new(0));

    let mut handles = Vec::new();
    for _ in 0..4 {
        let inside = Arc::clone(&inside);
        let overlap = Arc::clone(&overlap);
        handles.push(std::thread::spawn(move || {
            for _ in 0..5 {
                with_watchdog_lock(|| {
                    if inside.fetch_add(1, Ordering::SeqCst) != 0 {
                        overlap.fetch_add(1, Ordering::SeqCst);
                    }
                    std::thread::sleep(std::time::Duration::from_millis(2));
                    inside.fetch_sub(1, Ordering::SeqCst);
                });
            }
        }));
    }
    for handle in handles {
        handle.join().expect("thread");
    }

    assert_eq!(
        overlap.load(Ordering::SeqCst),
        0,
        "two watchdog hand-overs ran at the same time"
    );
}

/// A killed watchdog whose parent never waits stays a zombie for the life of the
/// process. The daemon spawns one watchdog per session, so it must reap it.
#[test]
fn spawned_watchdog_children_are_reaped() {
    use astral_plasma::application::plasma_service::spawn_reaped;

    let mut command = std::process::Command::new("sh");
    command.arg("-c").arg("exit 0");
    spawn_reaped(&mut command).expect("spawn child");
    std::thread::sleep(Duration::from_millis(300));

    let zombies: Vec<String> = std::fs::read_dir("/proc/self/task")
        .map(|tasks| {
            tasks
                .filter_map(|task| task.ok())
                .flat_map(|task| {
                    std::fs::read_to_string(task.path().join("children"))
                        .unwrap_or_default()
                        .split_whitespace()
                        .map(str::to_string)
                        .collect::<Vec<_>>()
                })
                .filter(|pid| {
                    std::fs::read_to_string(format!("/proc/{pid}/stat"))
                        .map(|stat| stat.split_whitespace().nth(2) == Some("Z"))
                        .unwrap_or(false)
                })
                .collect()
        })
        .unwrap_or_default();

    assert!(
        zombies.is_empty(),
        "spawned children were left unreaped: {zombies:?}"
    );
}

/// The pid file names the watchdog that supervises the session. A second
/// watchdog must not steal it, or the session loses track of its watchdog and
/// can end up with none (the panels then never come back). A *recycled* pid, on
/// the other hand, must not block the claim - and must never be signalled.
#[test]
fn a_second_watchdog_cannot_steal_the_pid_file() {
    use astral_plasma::application::plasma_service::claim_watchdog_pid_file;

    let dir = temp_dir("claim");
    let pid_file = dir.join("watchdog.pid");
    let live = std::process::id();

    // No file yet: the first watchdog claims it.
    assert!(claim_watchdog_pid_file(&pid_file, live), "first claim");
    assert_eq!(fs::read_to_string(&pid_file).expect("pid file"), live.to_string());

    // A live *watchdog* keeps its claim. `yes` stands in for one: it ignores its
    // arguments and stays alive, so its argv is `<exe> plasma watchdog <pid>`.
    let mut owner = std::process::Command::new("yes")
        .args(["plasma", "watchdog", "4242"])
        .stdout(std::process::Stdio::null())
        .spawn()
        .expect("spawn stand-in watchdog");
    std::thread::sleep(Duration::from_millis(200));
    fs::write(&pid_file, owner.id().to_string()).expect("pid file");
    assert!(
        !claim_watchdog_pid_file(&pid_file, live),
        "a live watchdog must keep the pid file"
    );
    assert_eq!(
        fs::read_to_string(&pid_file).expect("pid file"),
        owner.id().to_string()
    );
    let _ = owner.kill();
    let _ = owner.wait();

    // A recycled pid (alive, but not a watchdog) is replaced, not obeyed.
    fs::write(&pid_file, live.to_string()).expect("pid file");
    assert!(
        claim_watchdog_pid_file(&pid_file, live + 1),
        "a recycled pid must not block the claim"
    );
    assert_eq!(
        fs::read_to_string(&pid_file).expect("pid file"),
        (live + 1).to_string()
    );

    // A stale entry (no such process) is replaced too.
    fs::write(&pid_file, "999999").expect("stale pid");
    assert!(claim_watchdog_pid_file(&pid_file, live), "stale claim");
    assert_eq!(fs::read_to_string(&pid_file).expect("pid file"), live.to_string());

    let _ = fs::remove_dir_all(&dir);
}

/// The pid file lives in `/tmp`: it can outlive its watchdog and its pid can be
/// recycled by an unrelated process. Signalling it blindly has killed the wrong
/// process, so every signal path verifies the target first.
#[test]
fn only_real_watchdogs_are_signalled_from_the_pid_file() {
    use astral_plasma::infrastructure::plasma_adapter::{is_watchdog_argv, is_watchdog_process};

    fn argv(items: &[&str]) -> Vec<String> {
        items.iter().map(|item| item.to_string()).collect()
    }

    // The watchdog's argv is `<exe> plasma watchdog <pid>`.
    assert!(is_watchdog_argv(&argv(&[
        "/mnt/data/workspace/astral-plasma/bin/astral-plasma",
        "plasma",
        "watchdog",
        "3380954"
    ])));
    // A renamed executable is still a watchdog: the subcommand is what matters.
    assert!(is_watchdog_argv(&argv(&["/tmp/astral-plasma.hidden", "plasma", "watchdog", "1"])));

    // Anything else is not: the daemon itself, a plain command, and - the case
    // that used to be misread - a path that merely contains both words.
    assert!(!is_watchdog_argv(&argv(&["astral-plasma", "watch"])));
    assert!(!is_watchdog_argv(&argv(&["astral-plasma", "plasma", "disable", "all"])));
    assert!(!is_watchdog_argv(&argv(&[
        "/mnt/data/workspace/astral-plasma/daemon/target/debug/deps/test_watchdog_handover-abc"
    ])));

    // Against the real /proc: this test process is not a watchdog.
    assert!(!is_watchdog_process(std::process::id() as i32));
    assert!(!is_watchdog_process(0));
    assert!(!is_watchdog_process(-1));
    assert!(!is_watchdog_process(999_999));
}
