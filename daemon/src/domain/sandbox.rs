//! The hosted-app sandbox, as a value: every mount, flag, and environment variable a
//! launch needs, computed from the app and its grants.
//!
//! This is a pure function on purpose. The P0 spike measured the mount set (C.2): `/sys`
//! for EGL, the shared font cache for startup, a private runtime directory so the app
//! never sees the session's sockets. Those findings are asserted here rather than living
//! in a shell script nobody tests.
//!
//! Invariants the plan guarantees:
//!
//! * **No `$HOME`.** Nothing from the user's home is bound, and `HOME` points at the
//!   app's own directory.
//! * **No network.** `--unshare-all` removes it; `--share-net` appears only with the
//!   `network` grant.
//! * **No kernel.** Only `<package>/Astral/AppKit` is mounted as the SDK, so
//!   `import Astral.Kernel` cannot resolve.
//! * **No host runtime dir.** The Wayland socket is bound as a single file inside the
//!   private `/run/astral`, with `WAYLAND_DISPLAY` naming an absolute path.
//! * **Only the granted broker socket**, plus the palette file the host exports.

use std::path::{Path, PathBuf};

use crate::domain::app_manifest::Manifest;

/// What a launch is allowed to do. Grants come from the registry; the manifest says what
/// the app asked for, and the two are compared before launch.
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct Grants {
    pub network: bool,
    pub dbus_names: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SandboxPaths {
    /// `<package>` — the core bundle (kernel, AppKit, baseline apps).
    pub package_dir: PathBuf,
    /// `<apps>/<id>/payload` — the app itself.
    pub payload_dir: PathBuf,
    /// `<apps>/<id>/config` and `cache` — writable, app-owned.
    pub config_dir: PathBuf,
    pub cache_dir: PathBuf,
    /// The per-launch broker socket on the host side.
    pub broker_socket: PathBuf,
    /// The exported palette the shell publishes for hosted apps.
    pub palette_file: PathBuf,
    /// The proxy socket the launcher creates for the names this app consented to. `None`
    /// when no DBus access was granted, in which case the app gets no bus at all.
    pub dbus_proxy_socket: Option<PathBuf>,
    /// `$XDG_RUNTIME_DIR/wayland-N` on the host.
    pub wayland_socket: PathBuf,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SandboxPlan {
    pub argv: Vec<String>,
    pub env: Vec<(String, String)>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SandboxError {
    /// The app was granted DBus names but no proxy was created for them: opening the real
    /// session bus instead would hand it every service on the desktop.
    DbusWithoutProxy { names: Vec<String> },
    /// A required host path is missing; the launch would fail anyway, later and worse.
    MissingPath { what: &'static str, path: PathBuf },
    /// A community app asked for a capability the sandbox cannot provide.
    Unsupported { grant: String },
}

impl std::fmt::Display for SandboxError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::DbusWithoutProxy { names } => {
                write!(
                    f,
                    "cannot launch: DBus access to [{}] was granted but no proxy socket was \
                     created (refusing to expose the session bus instead)",
                    names.join(", ")
                )
            }
            Self::MissingPath { what, path } => {
                write!(f, "cannot launch: {what} is missing at {}", path.display())
            }
            Self::Unsupported { grant } => {
                write!(f, "the sandbox cannot provide '{grant}'")
            }
        }
    }
}

impl std::error::Error for SandboxError {}

/// Where the app's world lives inside the sandbox.
pub const APP_ROOT: &str = "/app";
pub const SDK_ROOT: &str = "/sdk";
pub const RUNTIME_ROOT: &str = "/run/astral";
pub const APP_HOME: &str = "/run/astral/home";
pub const BROKER_SOCKET: &str = "/run/astral/broker.sock";
pub const PALETTE_FILE: &str = "/run/astral/palette.json";
pub const WAYLAND_SOCKET: &str = "/run/astral/wayland";
/// Where the per-app DBus proxy appears inside the sandbox.
pub const DBUS_SOCKET: &str = "/run/astral/dbus";

/// Build the command that runs `app` in the sandbox.
pub fn plan(
    app: &Manifest,
    paths: &SandboxPaths,
    grants: &Grants,
    token: &str,
) -> Result<SandboxPlan, SandboxError> {
    for (what, path) in [
        ("the app payload", &paths.payload_dir),
        ("Astral.AppKit", &paths.package_dir.join("Astral/AppKit")),
        ("the Wayland socket", &paths.wayland_socket),
        ("the broker socket", &paths.broker_socket),
    ] {
        if !path.exists() {
            return Err(SandboxError::MissingPath {
                what,
                path: path.clone(),
            });
        }
    }
    for (what, path) in [
        ("the palette file", &paths.palette_file),
        ("the app config directory", &paths.config_dir),
        ("the app cache directory", &paths.cache_dir),
    ] {
        if !path.exists() {
            return Err(SandboxError::MissingPath {
                what,
                path: path.clone(),
            });
        }
    }

    let mut argv: Vec<String> = [
        "bwrap",
        "--unshare-all",
        "--die-with-parent",
        "--new-session",
        "--ro-bind", "/usr", "/usr",
        "--ro-bind", "/lib", "/lib",
        "--ro-bind", "/lib64", "/lib64",
        "--ro-bind-try", "/etc/ld.so.cache", "/etc/ld.so.cache",
        "--ro-bind", "/etc/fonts", "/etc/fonts",
        // Measured in C.2: without the shared cache, fontconfig rebuilds one into the
        // app's fresh XDG_CACHE_HOME and startup goes 121 ms -> 569 ms.
        "--ro-bind-try", "/var/cache/fontconfig", "/var/cache/fontconfig",
        "--ro-bind-try", "/etc/xdg", "/etc/xdg",
        // Measured in C.2: without /sys, EGL cannot enumerate the GPU and rendering
        // silently falls back to software.
        "--ro-bind-try", "/sys", "/sys",
        "--dev", "/dev",
        "--dev-bind-try", "/dev/dri", "/dev/dri",
        "--proc", "/proc",
        "--tmpfs", "/dev/shm",
        "--tmpfs", "/tmp",
    ]
    .iter()
    .map(|arg| arg.to_string())
    .collect();

    if grants.network {
        // Only with the grant: `--unshare-all` already removed the network namespace.
        argv.push("--share-net".into());
    }

    let bind = |argv: &mut Vec<String>, source: &Path, target: &str| {
        argv.push("--ro-bind".into());
        argv.push(source.display().to_string());
        argv.push(target.to_string());
    };

    // The SDK: AppKit only, so `import Astral.Kernel` cannot resolve (spec §7.3).
    bind(&mut argv, &paths.package_dir.join("Astral/AppKit"), &format!("{SDK_ROOT}/Astral/AppKit"));
    bind(&mut argv, &paths.payload_dir, APP_ROOT);
    bind(&mut argv, &paths.palette_file, PALETTE_FILE);
    bind(&mut argv, &paths.wayland_socket, WAYLAND_SOCKET);

    // The broker socket: the only way out of the sandbox that the host controls.
    argv.push("--bind".into());
    argv.push(paths.broker_socket.display().to_string());
    argv.push(BROKER_SOCKET.into());

    // Writable, app-owned, and only those.
    argv.push("--bind".into());
    argv.push(paths.config_dir.display().to_string());
    argv.push("/config".into());
    argv.push("--bind".into());
    argv.push(paths.cache_dir.display().to_string());
    argv.push("/cache".into());

    argv.push("--dir".into());
    argv.push(RUNTIME_ROOT.into());
    // HOME must exist and be writable, or every app that writes a dotfile fails with
    // ENOENT instead of a permission error, which reads as a sandbox bug.
    argv.push("--dir".into());
    argv.push(APP_HOME.into());
    argv.push("--chmod".into());
    argv.push("0700".into());
    argv.push(APP_HOME.into());

    // DBus, when (and only when) the app was granted named services. The app never sees
    // the session bus: it sees a proxy that can address exactly the consented names.
    let mut dbus_socket = None;
    if !grants.dbus_names.is_empty() {
        let Some(proxy) = &paths.dbus_proxy_socket else {
            return Err(SandboxError::DbusWithoutProxy {
                names: grants.dbus_names.clone(),
            });
        };
        if !proxy.exists() {
            return Err(SandboxError::MissingPath {
                what: "the DBus proxy socket",
                path: proxy.clone(),
            });
        }
        argv.push("--bind".into());
        argv.push(proxy.display().to_string());
        argv.push(DBUS_SOCKET.into());
        dbus_socket = Some(DBUS_SOCKET.to_string());
    }

    let mut env = vec![
        ("HOME".to_string(), APP_HOME.to_string()),
        ("XDG_RUNTIME_DIR".to_string(), RUNTIME_ROOT.to_string()),
        ("XDG_CONFIG_HOME".to_string(), "/config".to_string()),
        ("XDG_CACHE_HOME".to_string(), "/cache".to_string()),
        ("XDG_DATA_HOME".to_string(), "/config/data".to_string()),
        // An absolute path inside the private runtime dir: the host's own
        // $XDG_RUNTIME_DIR is never exposed (C.2).
        ("WAYLAND_DISPLAY".to_string(), WAYLAND_SOCKET.to_string()),
        ("QML_IMPORT_PATH".to_string(), SDK_ROOT.to_string()),
        ("ASTRAL_APP_ID".to_string(), app.id.clone()),
        ("ASTRAL_APK_TOKEN".to_string(), String::new()),
        ("ASTRAL_APP_TOKEN".to_string(), token.to_string()),
        ("ASTRAL_APPKIT_PALETTE".to_string(), PALETTE_FILE.to_string()),
        ("ASTRAL_BROKER".to_string(), BROKER_SOCKET.to_string()),
        ("LC_ALL".to_string(), "C.UTF-8".to_string()),
    ];
    if let Some(socket) = &dbus_socket {
        // The address the app dials: the proxy, never the session bus.
        env.push((
            "DBUS_SESSION_BUS_ADDRESS".to_string(),
            format!("unix:path={socket}"),
        ));
    }

    argv.push("--clearenv".into());
    for (key, value) in &env {
        argv.push("--setenv".into());
        argv.push(key.clone());
        argv.push(value.clone());
    }

    argv.push("quickshell".into());
    argv.push("-p".into());
    argv.push(APP_ROOT.into());

    Ok(SandboxPlan { argv, env })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::domain::app_manifest::{Entry, Publisher};

    fn manifest(id: &str, permissions: &[&str]) -> Manifest {
        Manifest {
            schema: 1,
            id: id.to_string(),
            name: "Fixture".to_string(),
            version: "1.0.0".to_string(),
            kernel_api: 1,
            min_quickshell: None,
            data_schema: None,
            trust: "community".to_string(),
            runtime: "hosted".to_string(),
            publisher: Publisher {
                name: "Fixture".to_string(),
                key: String::new(),
            },
            entry: Entry {
                root: "shell.qml".to_string(),
                surface: None,
                dashboard_tab: None,
                settings_page: None,
            },
            requires: Default::default(),
            permissions: permissions.iter().map(|p| p.to_string()).collect(),
            settings: None,
        test_suites: Vec::new(),
            distribution: None,
        }
    }

    /// A fake install tree, so the plan's existence checks pass.
    struct Fixture {
        dir: tempfile::TempDir,
        paths: SandboxPaths,
    }

    impl Fixture {
        fn new() -> Self {
            let dir = tempfile::tempdir().unwrap();
            let root = dir.path();
            let package = root.join("package");
            std::fs::create_dir_all(package.join("Astral/AppKit")).unwrap();
            let apps = root.join("apps/io.github.fixture");
            std::fs::create_dir_all(apps.join("payload")).unwrap();
            std::fs::create_dir_all(apps.join("config")).unwrap();
            std::fs::create_dir_all(apps.join("cache")).unwrap();
            let runtime = root.join("run");
            std::fs::create_dir_all(&runtime).unwrap();
            let wayland = runtime.join("wayland-1");
            std::fs::write(&wayland, b"").unwrap();
            let broker = runtime.join("broker.sock");
            std::fs::write(&broker, b"").unwrap();
            let palette = runtime.join("palette.json");
            std::fs::write(&palette, b"{}").unwrap();
            let paths = SandboxPaths {
                package_dir: package,
                payload_dir: apps.join("payload"),
                config_dir: apps.join("config"),
                cache_dir: apps.join("cache"),
                broker_socket: broker,
                palette_file: palette,
                wayland_socket: wayland,
                dbus_proxy_socket: None,
            };
            Self { dir, paths }
        }
    }

    fn joined(argv: &[String]) -> String {
        argv.join(" ")
    }

    #[test]
    fn the_plan_unshares_the_network_by_default() {
        let fixture = Fixture::new();
        let plan = plan(&manifest("io.github.fixture", &[]), &fixture.paths, &Grants::default(), "t").unwrap();
        let text = joined(&plan.argv);
        assert!(text.contains("--unshare-all"));
        assert!(!text.contains("--share-net"), "the network namespace stays removed");
    }

    #[test]
    fn a_network_grant_adds_the_shared_network() {
        let fixture = Fixture::new();
        let grants = Grants { network: true, dbus_names: vec![] };
        let plan = plan(&manifest("io.github.fixture", &["network"]), &fixture.paths, &grants, "t").unwrap();
        assert!(joined(&plan.argv).contains("--share-net"));
    }

    #[test]
    fn only_appkit_is_mounted_so_the_kernel_cannot_resolve() {
        let fixture = Fixture::new();
        let plan = plan(&manifest("io.github.fixture", &[]), &fixture.paths, &Grants::default(), "t").unwrap();
        let text = joined(&plan.argv);
        assert!(text.contains("/sdk/Astral/AppKit"));
        assert!(!text.contains("Astral/Kernel"), "the kernel is never mounted: {text}");
    }

    #[test]
    fn the_home_directory_is_never_exposed() {
        let fixture = Fixture::new();
        let plan = plan(&manifest("io.github.fixture", &[]), &fixture.paths, &Grants::default(), "t").unwrap();
        let home = std::env::var("HOME").unwrap_or_default();
        assert!(!joined(&plan.argv).contains(&home) || home.is_empty(), "no host home in the command");
        assert!(plan.env.iter().any(|(k, v)| k == "HOME" && v == APP_HOME));
    }

    #[test]
    fn the_host_runtime_dir_is_not_exposed() {
        let fixture = Fixture::new();
        let plan = plan(&manifest("io.github.fixture", &[]), &fixture.paths, &Grants::default(), "t").unwrap();
        let text = joined(&plan.argv);
        let runtime = std::env::var("XDG_RUNTIME_DIR").unwrap_or_default();
        if !runtime.is_empty() {
            assert!(!text.contains(&runtime), "the session runtime dir is never bound");
        }
        assert!(plan.env.iter().any(|(k, v)| k == "WAYLAND_DISPLAY" && v == WAYLAND_SOCKET));
    }

    #[test]
    fn the_environment_is_cleared_and_rebuilt() {
        let fixture = Fixture::new();
        let plan = plan(&manifest("io.github.fixture", &[]), &fixture.paths, &Grants::default(), "t").unwrap();
        let text = joined(&plan.argv);
        assert!(text.contains("--clearenv"));
        let env: Vec<&str> = plan.env.iter().map(|(k, _)| k.as_str()).collect();
        for key in ["HOME", "XDG_RUNTIME_DIR", "WAYLAND_DISPLAY", "QML_IMPORT_PATH", "ASTRAL_APP_TOKEN"] {
            assert!(env.contains(&key), "{key} must be set explicitly");
        }
    }

    #[test]
    fn the_measured_mounts_are_present() {
        let fixture = Fixture::new();
        let plan = plan(&manifest("io.github.fixture", &[]), &fixture.paths, &Grants::default(), "t").unwrap();
        // The three the P0 spike proved load-bearing (C.2).
        for required in ["/var/cache/fontconfig", "/sys", "/dev/dri"] {
            assert!(joined(&plan.argv).contains(required), "{required} must be mounted");
        }
    }

    #[test]
    fn the_token_is_passed_once_and_identifies_the_app() {
        let fixture = Fixture::new();
        let plan = plan(&manifest("io.github.fixture", &[]), &fixture.paths, &Grants::default(), "tok-1").unwrap();
        let token = plan.env.iter().find(|(k, _)| k == "ASTRAL_APP_TOKEN").unwrap();
        assert_eq!(token.1, "tok-1");
        let id = plan.env.iter().find(|(k, _)| k == "ASTRAL_APP_ID").unwrap();
        assert_eq!(id.1, "io.github.fixture");
    }

    #[test]
    fn home_exists_and_is_writable_but_empty() {
        let fixture = Fixture::new();
        let plan = plan(
            &manifest("io.github.fixture", &[]),
            &fixture.paths,
            &Grants::default(),
            "tok",
        )
        .unwrap();
        let home_at = plan
            .argv
            .iter()
            .position(|arg| arg == APP_HOME)
            .expect("home is planned");
        assert_eq!(plan.argv[home_at - 1], "--dir", "home is created, not merely named");
        assert!(plan.argv.windows(3).any(|w| w == ["--chmod", "0700", APP_HOME]));
        assert_eq!(
            plan.env.iter().find(|(k, _)| k == "HOME").map(|(_, v)| v.as_str()),
            Some(APP_HOME),
            "HOME is the sandbox's own directory"
        );
    }

    #[test]
    fn a_missing_payload_is_refused_before_the_spawn() {
        let mut fixture = Fixture::new();
        fixture.paths.payload_dir = fixture.dir.path().join("nope");
        let error = plan(&manifest("io.github.fixture", &[]), &fixture.paths, &Grants::default(), "t").unwrap_err();
        assert!(error.to_string().contains("missing"), "got: {error}");
    }

    #[test]
    fn the_command_ends_with_the_app() {
        let fixture = Fixture::new();
        let plan = plan(&manifest("io.github.fixture", &[]), &fixture.paths, &Grants::default(), "t").unwrap();
        assert_eq!(&plan.argv[plan.argv.len() - 3..], ["quickshell", "-p", APP_ROOT]);
    }
}
