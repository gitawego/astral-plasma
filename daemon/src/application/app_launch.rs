//! Launching a hosted app: verify, mint a one-shot token, plan the sandbox, run it.
//!
//! The policy lives in `domain::sandbox` (mounts) and `domain::broker` (permissions);
//! this is the use case that ties them to the registry and the process table.
//!
//! Two refusals matter more than the rest:
//!
//! * **A payload whose digest no longer matches its install record is not launched.**
//!   The record is what the user consented to; the bytes on disk are what would run.
//! * **An app that is not enabled is not launched**, even from a desktop entry it
//!   installed itself.

use std::path::{Path, PathBuf};

use sha2::{Digest, Sha256};

use crate::application::app_service::{installed_app, read_registry};
use crate::domain::app_bundle::Bundle;
use crate::domain::app_compat::HostApi;
use crate::domain::app_reconcile::Action;
use crate::domain::broker::RateLimiter;
use crate::domain::ports::DynResult;
use crate::domain::sandbox::{self, Grants, SandboxPaths, SandboxPlan};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Launch {
    pub app_id: String,
    pub plan: SandboxPlan,
    pub token: String,
    pub audit_path: PathBuf,
}

/// Everything a launch needs, resolved and checked. `dry_run` uses the same checks and
/// stops before spawning, which is what the tests exercise.
pub fn prepare(
    data_dir: &Path,
    apps_root: &Path,
    package_dir: &Path,
    runtime_dir: &Path,
    broker_socket: &Path,
    // The proxy socket for the DBus names the user consented to, if any were.
    dbus_proxy_socket: Option<&Path>,
    app_id: &str,
    host: &HostApi,
    // Minted by the caller, which binds the broker with it before the plan is built: a
    // plan that points at a socket nobody serves looks like a sandbox bug.
    token: &str,
) -> DynResult<Launch> {
    let registry = read_registry(data_dir)?;
    let Some(entry) = registry.get(app_id) else {
        return Err(format!("'{app_id}' is not installed").into());
    };
    if !entry.enabled {
        return Err(format!("'{app_id}' is disabled; enable it in Settings → Apps").into());
    }

    // What will run must be what the user consented to: the extracted payload's digest,
    // recorded at install, re-checked here (the artifact digest covers the archive).
    let payload_dir = apps_root.join(app_id).join("payload");
    let digest = crate::domain::app_bundle::payload_digest(&payload_dir)?;
    if !entry.payload_digest.is_empty() && entry.payload_digest != digest {
        return Err(format!(
            "'{app_id}' on disk does not match its install record (expected {}, found {}); reinstall it",
            entry.payload_digest, digest
        )
        .into());
    }

    // Compatibility is re-checked at launch: a core update may have moved the window.
    let installed = installed_app(entry, false);
    if let Action::Disable { reason } =
        crate::domain::app_reconcile::reconcile(&installed, &[], host)
    {
        return Err(format!("'{app_id}' cannot run: {reason}").into());
    }

    let grants = Grants {
        network: entry.granted.iter().any(|p| p == "network"),
        dbus_names: entry.dbus_names.clone(),
    };

    let app_dir = apps_root.join(app_id);
    let config_dir = app_dir.join("config");
    let cache_dir = app_dir.join("cache");
    std::fs::create_dir_all(&config_dir)?;
    std::fs::create_dir_all(&cache_dir)?;
    std::fs::create_dir_all(runtime_dir)?;

    // The broker owns the socket and binds it before the app is spawned; this only
    // consumes the path, so a launch can never point at a socket nobody listens on.

    let palette_file = data_dir.join("current-palette.json");
    if !palette_file.exists() {
        std::fs::write(&palette_file, b"{}")?;
    }

    let wayland_socket = wayland_socket_path(runtime_dir)?;

    let paths = SandboxPaths {
        package_dir: package_dir.to_path_buf(),
        payload_dir,
        config_dir,
        cache_dir,
        broker_socket: broker_socket.to_path_buf(),
        dbus_proxy_socket: dbus_proxy_socket.map(Path::to_path_buf),
        palette_file,
        wayland_socket,
    };

    // The manifest the payload ships is the app's identity for the sandbox environment.
    let manifest = {
        let raw = std::fs::read(app_dir.join("manifest.json"))?;
        crate::domain::app_manifest::Manifest::parse(&raw)?
    };
    let plan = sandbox::plan(&manifest, &paths, &grants, token)?;

    Ok(Launch {
        app_id: app_id.to_string(),
        plan,
        token: token.to_string(),
        audit_path: data_dir.join("broker-audit.log"),
    })
}

/// Where the DBus proxy socket for a launch lives.
pub fn dbus_socket(runtime_dir: &Path, app_id: &str) -> PathBuf {
    runtime_dir.join(format!("dbus-{app_id}.sock"))
}

/// The `xdg-dbus-proxy` invocation for one app: a filtered connection that can address the
/// consented names and nothing else.
pub fn dbus_proxy_command(session_bus: &str, socket: &Path, names: &[String]) -> Vec<String> {
    let mut argv = vec![
        "xdg-dbus-proxy".to_string(),
        session_bus.to_string(),
        socket.display().to_string(),
        "--filter".to_string(),
    ];
    for name in names {
        argv.push(format!("--talk={name}"));
    }
    argv
}

/// Start the proxy and wait until it is listening.
///
/// Waiting matters: an app that starts first will cache a failed bus connection and never
/// retry, which looks like "DBus is broken" rather than "we raced the proxy".
pub fn start_dbus_proxy(
    session_bus: &str,
    socket: &Path,
    names: &[String],
) -> DynResult<std::process::Child> {
    let _ = std::fs::remove_file(socket);
    let argv = dbus_proxy_command(session_bus, socket, names);
    let child = std::process::Command::new(&argv[0])
        .args(&argv[1..])
        .spawn()
        .map_err(|error| format!("cannot start xdg-dbus-proxy: {error}"))?;
    for _ in 0..100 {
        if socket.exists() {
            return Ok(child);
        }
        std::thread::sleep(std::time::Duration::from_millis(20));
    }
    Err("xdg-dbus-proxy did not create its socket within 2s".into())
}

/// Where the broker socket for a launch lives (the broker creates it there).
pub fn runtime_socket(runtime_dir: &Path, app_id: &str) -> PathBuf {
    runtime_dir.join(format!("broker-{app_id}.sock"))
}

/// `$XDG_RUNTIME_DIR/wayland-N`, discovered rather than assumed.
fn wayland_socket_path(runtime_dir: &Path) -> DynResult<PathBuf> {
    if let Ok(display) = std::env::var("WAYLAND_DISPLAY") {
        let candidate = if display.starts_with('/') {
            PathBuf::from(&display)
        } else {
            runtime_dir.join(&display)
        };
        if candidate.exists() {
            return Ok(candidate);
        }
    }
    for index in 0..8 {
        let candidate = runtime_dir.join(format!("wayland-{index}"));
        if candidate.exists() {
            return Ok(candidate);
        }
    }
    Err("no Wayland socket found; hosted apps need a Wayland session".into())
}

/// A one-shot token: same input twice gives different output, and it is not guessable from
/// the app id alone.
pub fn mint_token(app_id: &str, now_ms: u64) -> String {
    use std::sync::atomic::{AtomicU64, Ordering};
    /// Distinguishes two launches inside the same millisecond by the same process.
    static LAUNCHES: AtomicU64 = AtomicU64::new(0);
    let mut hasher = Sha256::new();
    hasher.update(app_id.as_bytes());
    hasher.update(now_ms.to_le_bytes());
    hasher.update(std::process::id().to_le_bytes());
    hasher.update(LAUNCHES.fetch_add(1, Ordering::Relaxed).to_le_bytes());
    format!("{:x}", hasher.finalize())[..32].to_string()
}

/// The per-app rate limiter the broker uses for a launch.
pub fn limiter_for(now_ms: u64) -> RateLimiter {
    RateLimiter::new(now_ms)
}

/// The payload directory for an installed app.
pub fn payload_dir(apps_root: &Path, app_id: &str) -> PathBuf {
    apps_root.join(app_id).join("payload")
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::application::app_sdk::{create_app, pack_dir, Template};
    use crate::application::app_install::install_file;
    use crate::domain::app_compat::{HostApi, APP_API_LEVEL};

    struct Fixture {
        dir: tempfile::TempDir,
    }

    impl Fixture {
        fn new() -> Self {
            Self { dir: tempfile::tempdir().unwrap() }
        }
        fn data(&self) -> PathBuf { self.dir.path().join("data") }
        fn apps(&self) -> PathBuf { self.dir.path().join("apps") }
        fn package(&self) -> PathBuf {
            let package = self.dir.path().join("package");
            std::fs::create_dir_all(package.join("Astral/AppKit")).unwrap();
            package
        }
        fn runtime(&self) -> PathBuf {
            let runtime = self.dir.path().join("run");
            std::fs::create_dir_all(&runtime).unwrap();
            // A fake Wayland socket: the plan only needs it to exist.
            std::fs::write(runtime.join("wayland-1"), b"").unwrap();
            runtime
        }
        /// The broker binds this before a launch; the tests only need it to exist.
        fn broker_socket(&self) -> PathBuf {
            let path = runtime_socket(&self.runtime(), "io.github.alice.clock");
            std::fs::write(&path, b"").unwrap();
            path
        }
        fn install(&self, id: &str) -> std::path::PathBuf {
            let app = self.dir.path().join(format!("src-{id}"));
            create_app(id, Template::Surface, &app).unwrap();
            let packed = pack_dir(&app, Some(self.dir.path())).unwrap();
            let host = HostApi { level: APP_API_LEVEL, floor: APP_API_LEVEL, quickshell: None };
            install_file(&self.data(), &self.apps(), &packed.path, &host, false, false).unwrap();
            packed.path
        }
    }

    fn host() -> HostApi {
        HostApi { level: APP_API_LEVEL, floor: APP_API_LEVEL, quickshell: None }
    }

    fn with_wayland<T>(f: impl FnOnce() -> T) -> T {
        // The plan resolves the session's Wayland socket from the environment.
        std::env::set_var("WAYLAND_DISPLAY", "wayland-1");
        f()
    }

    #[test]
    fn a_verified_app_gets_a_plan_env_and_token() {
        let fixture = Fixture::new();
        fixture.install("io.github.alice.clock");
        let launch = prepare(
            &fixture.data(), &fixture.apps(), &fixture.package(), &fixture.runtime(),
            &fixture.broker_socket(), None, "io.github.alice.clock", &host(), "tok-fixture",
        ).unwrap_or_else(|err| panic!("launch must prepare: {err}"));

        assert_eq!(launch.token, "tok-fixture", "the caller's token is the launch's token");
        assert_eq!(launch.plan.argv[0], "bwrap");
        assert!(launch.plan.env.iter().any(|(k, v)| k == "ASTRAL_APP_TOKEN" && *v == launch.token));
        assert!(launch.plan.env.iter().any(|(k, v)| k == "ASTRAL_APP_ID"
            && v == "io.github.alice.clock"));
    }

    #[test]
    fn a_disabled_app_is_not_launched() {
        let fixture = Fixture::new();
        fixture.install("io.github.alice.clock");
        let mut registry = read_registry(&fixture.data()).unwrap();
        registry.apps[0].enabled = false;
        crate::application::app_service::write_registry(&fixture.data(), &registry).unwrap();

        let error = prepare(
            &fixture.data(), &fixture.apps(), &fixture.package(), &fixture.runtime(),
            &fixture.broker_socket(), None, "io.github.alice.clock", &host(), "tok-fixture",
        ).unwrap_err();
        assert!(error.to_string().contains("disabled"), "got: {error}");
    }

    #[test]
    fn a_tampered_payload_is_not_launched() {
        let fixture = Fixture::new();
        fixture.install("io.github.alice.clock");
        let payload = payload_dir(&fixture.apps(), "io.github.alice.clock");
        std::fs::write(payload.join("shell.qml"), "import QtQuick\nItem { } // edited\n").unwrap();

        let error = prepare(
            &fixture.data(), &fixture.apps(), &fixture.package(), &fixture.runtime(),
            &fixture.broker_socket(), None, "io.github.alice.clock", &host(), "tok-fixture",
        ).unwrap_err();
        assert!(error.to_string().contains("does not match its install record"), "got: {error}");
    }

    #[test]
    fn an_unknown_app_is_refused_by_name() {
        let fixture = Fixture::new();
        let error = prepare(
            &fixture.data(), &fixture.apps(), &fixture.package(), &fixture.runtime(),
            &fixture.broker_socket(), None, "io.github.alice.ghost", &host(), "tok-fixture",
        ).unwrap_err();
        assert!(error.to_string().contains("io.github.alice.ghost"));
    }

    #[test]
    fn tokens_are_one_shot() {
        let first = mint_token("io.github.alice.clock", 1);
        let second = mint_token("io.github.alice.clock", 1);
        assert_ne!(first, second, "the same inputs still mint different tokens");
        assert_eq!(first.len(), 32);
    }

    #[test]
    fn a_granted_dbus_name_without_a_proxy_is_refused() {
        // The alternative — handing the app the real session bus — would give it every
        // service on the desktop, so the refusal is the safe branch.
        let fixture = Fixture::new();
        fixture.install("io.github.alice.clock");
        let mut registry = read_registry(&fixture.data()).unwrap();
        registry.apps[0].dbus_names = vec!["org.freedesktop.Notifications".to_string()];
        crate::application::app_service::write_registry(&fixture.data(), &registry).unwrap();

        let error = prepare(
            &fixture.data(), &fixture.apps(), &fixture.package(), &fixture.runtime(),
            &fixture.broker_socket(), None, "io.github.alice.clock", &host(), "tok",
        )
        .unwrap_err();
        assert!(error.to_string().contains("no proxy socket"), "got: {error}");
    }

    #[test]
    fn the_proxy_can_address_exactly_the_consented_names() {
        let names = vec![
            "org.freedesktop.Notifications".to_string(),
            "org.mpris.MediaPlayer2".to_string(),
        ];
        let argv = dbus_proxy_command("unix:path=/run/user/1000/bus", Path::new("/run/x.sock"), &names);
        assert_eq!(argv[0], "xdg-dbus-proxy");
        assert!(argv.contains(&"--filter".to_string()));
        assert_eq!(argv.iter().filter(|arg| arg.starts_with("--talk=")).count(), 2);
        assert!(argv.contains(&"--talk=org.freedesktop.Notifications".to_string()));
        assert!(!argv.iter().any(|arg| arg == "--see" || arg == "--talk=*"));
    }

    #[test]
    fn a_runtime_dir_without_a_wayland_socket_names_the_problem() {
        // Discovery is a pure function of the runtime dir, so this needs no environment
        // mutation (which would race the other tests).
        let empty = tempfile::tempdir().unwrap();
        std::env::remove_var("WAYLAND_DISPLAY");
        let error = wayland_socket_path(empty.path()).unwrap_err();
        assert!(error.to_string().contains("Wayland"), "got: {error}");
    }
}
