//! The templates must *run*, not merely exist.
//!
//! A template is the first code an author sees; one that does not load teaches the
//! wrong shape and burns an afternoon. These tests create each template in a temp
//! dir and, when a display is available, load it with a real `quickshell`.

use astral_plasma::application::app_sdk::{create_app, lint_dir, pack_dir, Template};
use std::path::Path;

fn repo_root() -> std::path::PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).parent().unwrap().to_path_buf()
}

fn quickshell_available() -> bool {
    std::process::Command::new("quickshell")
        .arg("--version")
        .output()
        .map(|output| output.status.success())
        .unwrap_or(false)
}

fn has_display() -> bool {
    std::env::var("WAYLAND_DISPLAY").is_ok() || std::env::var("DISPLAY").is_ok()
}

#[test]
fn every_template_is_created_linted_packed_and_loadable() {
    for template in [Template::Surface, Template::LayerSurface, Template::Service] {
        let dir = tempfile::tempdir().unwrap();
        let target = dir.path().join("app");
        let id = format!("io.github.alice.{}", template.name().replace('-', ""));
        create_app(&id, template, &target).unwrap();

        let problems = lint_dir(&target).unwrap();
        assert!(problems.is_empty(), "{}: {problems:?}", template.name());

        let packed = pack_dir(&target, Some(dir.path())).unwrap();
        assert!(packed.path.is_file(), "{} produced no archive", template.name());

        if !quickshell_available() || !has_display() {
            eprintln!("skipped loading {} (no display or no quickshell)", template.name());
            continue;
        }

        // A surface stays open, so the loader is bounded: spawn, let it load, kill.
        let mut child = std::process::Command::new("quickshell")
            .arg("-p")
            .arg(&target)
            .env("QML_IMPORT_PATH", repo_root().join("modules"))
            .env("QT_ASSUME_STDERR_HAS_CONSOLE", "1")
            .stdout(std::process::Stdio::piped())
            .stderr(std::process::Stdio::piped())
            .spawn()
            .expect("quickshell runs");
        std::thread::sleep(std::time::Duration::from_secs(4));
        let _ = child.kill();
        let output = child.wait_with_output().expect("quickshell exits");
        let log = format!(
            "{}{}",
            String::from_utf8_lossy(&output.stdout),
            String::from_utf8_lossy(&output.stderr)
        );
        assert!(
            !log.contains("Failed to load configuration"),
            "{} template does not load:\n{log}",
            template.name()
        );
        assert!(
            !log.contains("is not a type"),
            "{} template references a type AppKit does not export:\n{log}",
            template.name()
        );
    }
}
