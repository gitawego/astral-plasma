//! AppKit: the public module an app author targets.
//!
//! Two things are worth a test rather than a comment:
//!
//! 1. **The published constants cannot drift.** `AppApi.qml` and the host policy's
//!    `DEFAULT_HOST` restate numbers that also exist in Rust. A shell that tells an
//!    app "API 1" while the daemon enforces "API 2" is worse than no check at all,
//!    so these tests parse the QML/JS and compare.
//! 2. **The module actually loads.** Not "the files exist" - a real `quickshell`
//!    process resolves `import Astral.AppKit 1.0`, applies the theme tokens, and
//!    renders a window. This needs a Wayland session, so it skips (loudly) when
//!    there is none.

use astral_plasma::domain::app_compat::{platform_for_level, APP_API_FLOOR, APP_API_LEVEL};
use std::path::{Path, PathBuf};

fn repo_root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("daemon/ has a parent")
        .to_path_buf()
}

fn read(rel: &str) -> String {
    let path = repo_root().join(rel);
    std::fs::read_to_string(&path).unwrap_or_else(|err| panic!("{}: {err}", path.display()))
}

fn number_after(source: &str, needle: &str) -> i64 {
    let start = source
        .find(needle)
        .unwrap_or_else(|| panic!("'{needle}' not found"))
        + needle.len();
    let rest = &source[start..];
    let digits: String = rest
        .chars()
        .skip_while(|c| c.is_whitespace())
        .take_while(|c| c.is_ascii_digit())
        .collect();
    digits
        .parse()
        .unwrap_or_else(|_| panic!("'{needle}' is not followed by a number"))
}

#[test]
fn appkit_constants_match_the_daemon() {
    let api = read("modules/Astral/AppKit/AppApi.qml");
    assert_eq!(
        number_after(&api, "readonly property int level:"),
        i64::from(APP_API_LEVEL),
        "AppApi.level must equal domain::app_compat::APP_API_LEVEL"
    );
    assert_eq!(
        number_after(&api, "readonly property int floor:"),
        i64::from(APP_API_FLOOR),
        "AppApi.floor must equal domain::app_compat::APP_API_FLOOR"
    );
    // Every supported level must be phraseable as a release, in both places.
    for level in APP_API_FLOOR..=APP_API_LEVEL {
        let release = platform_for_level(level).expect("supported level has a release");
        assert!(
            api.contains(release),
            "AppApi.releases must name {release} for API level {level}"
        );
    }
}

#[test]
fn host_policy_default_host_matches_the_daemon() {
    let policy = read("modules/Astral/Kernel/host/AppHostPolicy.js");
    let line = policy
        .lines()
        .find(|line| line.contains("var DEFAULT_HOST"))
        .expect("AppHostPolicy declares DEFAULT_HOST");
    fn number_after(value: &str, key: &str) -> u32 {
        let rest = value
            .split(key)
            .nth(1)
            .unwrap_or_else(|| panic!("DEFAULT_HOST has no '{key}'"));
        rest.trim_start()
            .chars()
            .take_while(|c| c.is_ascii_digit())
            .collect::<String>()
            .parse()
            .unwrap_or_else(|_| panic!("'{key}' is not followed by a number in: {value}"))
    }
    let level = number_after(line, "level:");
    let floor = number_after(line, "floor:");
    assert_eq!(level, APP_API_LEVEL);
    assert_eq!(floor, APP_API_FLOOR);
}

#[test]
fn appkit_qmldir_declares_every_file_and_nothing_else() {
    let dir = repo_root().join("modules/Astral/AppKit");
    let qmldir = read("modules/Astral/AppKit/qmldir");
    let declared: Vec<String> = qmldir
        .lines()
        .filter(|line| !line.trim().is_empty() && !line.starts_with("module "))
        .map(|line| {
            line.split_whitespace()
                .last()
                .expect("entry has a file")
                .to_string()
        })
        .collect();

    let mut on_disk: Vec<String> = std::fs::read_dir(&dir)
        .unwrap()
        .flatten()
        .filter_map(|entry| {
            let name = entry.file_name().to_string_lossy().to_string();
            name.ends_with(".qml").then_some(name)
        })
        .collect();
    on_disk.sort();
    let mut declared_sorted = declared.clone();
    declared_sorted.sort();

    assert_eq!(
        on_disk, declared_sorted,
        "every AppKit .qml file must be declared in qmldir (regenerate with \
         scripts/gen_qmldir.py) and every declaration must exist"
    );

    // Singletons are the ones apps call without instantiating; they must be marked.
    for singleton in ["AppApi.qml", "AppPalette.qml", "Theme.qml", "Colors.qml", "Motion.qml"] {
        assert!(
            qmldir.contains(&format!("singleton ")) && qmldir.contains(singleton),
            "{singleton} must be declared as a singleton"
        );
        let body = read(&format!("modules/Astral/AppKit/{singleton}"));
        assert!(
            body.starts_with("pragma Singleton"),
            "{singleton} must declare pragma Singleton"
        );
    }
}

/// The app-facing surface must not leak kernel internals: an app that can import
/// `Astral.Kernel` has no sandbox worth the name.
#[test]
fn appkit_does_not_import_the_kernel_module() {
    for file in ["Theme.qml", "Colors.qml", "Motion.qml", "AppApi.qml", "AppWindow.qml"] {
        let body = read(&format!("modules/Astral/AppKit/{file}"));
        assert!(
            !body.contains("import Astral.Kernel"),
            "{file} must not import the kernel module"
        );
    }
}


/// Motion tokens are design constants the app carries (a sandbox mounts no kernel
/// files), so the two copies must not drift. Both are parsed and compared.
#[test]
fn appkit_motion_tokens_match_the_kernel_theme() {
    let kernel = read("modules/Astral/Kernel/theme/Theme.qml");
    let appkit = read("modules/Astral/AppKit/Motion.qml");

    let pairs = [
        ("animExpressiveFastSpatial", "fastSpatial"),
        ("animExpressiveDefaultSpatial", "defaultSpatial"),
        ("animExpressiveSlowSpatial", "slowSpatial"),
        ("animExpressiveFastEffects", "fastEffects"),
        ("animExpressiveDefaultEffects", "defaultEffects"),
        ("animExpressiveSlowEffects", "slowEffects"),
    ];
    for (kernel_name, appkit_name) in pairs {
        let expected = number_after(&kernel, &format!("{kernel_name}:"));
        let actual = number_after(&appkit, &format!("{appkit_name}:"));
        assert_eq!(
            actual, expected,
            "Motion.{appkit_name} must equal Theme.{kernel_name} (DESIGN.md is the authority)"
        );
    }

    for (kernel_name, appkit_name) in [
        ("curveExpressiveDefaultSpatial", "expressiveDefaultSpatial"),
        ("curveExpressiveDefaultEffects", "expressiveDefaultEffects"),
    ] {
        let expected = curve_after(&kernel, kernel_name);
        let actual = curve_after(&appkit, appkit_name);
        assert_eq!(actual, expected, "Motion.{appkit_name} must equal Theme.{kernel_name}");
    }
}

fn curve_after(source: &str, name: &str) -> Vec<String> {
    let start = source
        .find(&format!("{name}:"))
        .unwrap_or_else(|| panic!("'{name}' not found"))
        + name.len()
        + 1;
    let rest = &source[start..];
    let open = rest.find('[').expect("curve has an array");
    let close = rest[open..].find(']').expect("curve array is closed");
    rest[open + 1..open + close]
        .split(',')
        .map(|part| part.trim().to_string())
        .collect()
}

/// The palette file is the app-facing theme contract: whatever the kernel exports
/// must include the keys AppKit reads, or a hosted app silently falls back.
#[test]
fn the_exported_palette_carries_every_key_appkit_reads() {
    let exporter = read("modules/Astral/Kernel/services/ThemeExportService.qml");
    let palette = read("modules/Astral/AppKit/AppPalette.qml");
    let colors = read("modules/Astral/AppKit/Colors.qml");
    let theme = read("modules/Astral/AppKit/Theme.qml");

    for key in [
        "primary",
        "on_primary",
        "surface",
        "surface_container",
        "secondary",
        "tertiary",
        "outline",
        "on_surface",
        "radius_small",
        "radius_medium",
        "radius_large",
        "font_family",
        "mode",
    ] {
        assert!(
            exporter.contains(&format!("\"{key}\"")),
            "ThemeExportService must export '{key}' (AppKit reads it)"
        );
    }

    for (file, body) in [("Colors.qml", colors.as_str()), ("Theme.qml", theme.as_str())] {
        for (index, _) in body.match_indices("AppPalette.") {
            let rest = &body[index + "AppPalette.".len()..];
            let name: String = rest
                .chars()
                .take_while(|c| c.is_ascii_alphanumeric() || *c == '_')
                .collect();
            assert!(
                name == "color" || name == "number" || name == "source" || name == "tokens"
                    || name == "path",
                "{file} calls AppPalette.{name}, which AppPalette.qml does not provide"
            );
        }
    }
    // Palette itself must read the file the kernel writes, through Quickshell's
    // FileView - not an XHR the sandbox would have to allow.
    assert!(palette.contains("FileView"));
    assert!(!palette.contains("XMLHttpRequest"));
}

fn quickshell_available() -> bool {
    std::process::Command::new("quickshell")
        .arg("--version")
        .output()
        .map(|output| output.status.success())
        .unwrap_or(false)
}

#[test]
fn a_hosted_app_loads_with_appkit_on_a_real_quickshell() {
    if !quickshell_available() {
        eprintln!("skipped: quickshell is not installed");
        return;
    }
    if std::env::var("WAYLAND_DISPLAY").is_err() && std::env::var("DISPLAY").is_err() {
        eprintln!("skipped: no display server; AppWindow is layer-shell backed");
        return;
    }

    let dir = tempfile::tempdir().unwrap();
    let palette = dir.path().join("current-palette.json");
    std::fs::write(
        &palette,
        r##"{"mode":"light","primary":"#123456","surface":"#fefefe","on_surface":"#010101",
            "outline":"#abcdef","surface_container":"#eeeeee","secondary":"#222222",
            "tertiary":"#333333","radius_small":4,"radius_medium":8,"radius_large":12,
            "font_family":"Test Sans"}"##,
    )
    .unwrap();
    std::fs::write(
        dir.path().join("shell.qml"),
        r#"
import QtQuick
import Astral.AppKit 1.0

AppWindow {
    width: 320
    height: 200
    anchors { top: true; left: true }
    margins { top: 80; left: 80 }

    Column {
        anchors.centerIn: parent
        spacing: 6
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "APPKIT_OK api=" + AppApi.level + " floor=" + AppApi.floor
            color: Colors.textOnSurface
            font.family: Theme.fontFamily
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "radius=" + Theme.radiusLarge + " motion=" + Motion.defaultSpatial
                + " surface=#" + Colors.surface.toString().slice(3)
                + " source=" + Theme.source + " font=" + Theme.fontFamily
            color: Colors.primary
        }
    }
    Component.onCompleted: {
        console.log("APPKIT_OK api=" + AppApi.level + " floor=" + AppApi.floor
            + " radius=" + Theme.radiusLarge
            + " source=" + Theme.source
            + " font=" + Theme.fontFamily
            + " surface=#" + Colors.surface.toString().slice(3))
        Qt.callLater(Qt.quit)
    }
    Timer { interval: 4000; running: true; onTriggered: Qt.quit() }
}
"#,
    )
    .unwrap();

    let output = std::process::Command::new("quickshell")
        .arg("-p")
        .arg(dir.path())
        .env(
            "QML_IMPORT_PATH",
            repo_root().join("modules").display().to_string(),
        )
        .env("QT_ASSUME_STDERR_HAS_CONSOLE", "1")
        .env("ASTRAL_APPKIT_PALETTE", palette.display().to_string())
        .output()
        .expect("quickshell runs");

    let log = format!(
        "{}{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        !log.contains("Failed to load configuration"),
        "AppKit failed to load:\n{log}"
    );
    assert!(
        log.contains("APPKIT_OK api="),
        "the app never reached onCompleted; AppKit did not initialise:\n{log}"
    );
    // Tokens must be real values, not empty bindings.
    assert!(!log.contains("api=0"), "AppApi.level resolved to 0:\n{log}");
    assert!(
        log.contains("source=palette"),
        "the app did not read the host's palette file:\n{log}"
    );
    // And the values must be the ones in the file, not the fallbacks.
    assert!(
        log.contains("radius=12"),
        "Theme.radiusLarge did not come from the palette:\n{log}"
    );
    assert!(
        log.contains("font=Test Sans"),
        "Theme.fontFamily did not come from the palette:\n{log}"
    );
}
