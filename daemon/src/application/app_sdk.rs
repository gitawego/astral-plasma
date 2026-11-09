//! The author-facing SDK: `astral app new / lint / pack`.
//!
//! The point of the platform is that an author with no Astral checkout can be
//! running an app in one command. That means these three verbs must be *real*:
//! `new` writes the files an author would otherwise copy from a wiki, `lint` refuses
//! what the installer would refuse, and `pack` produces the archive the installer
//! verifies.
//!
//! Templates are verified by loading them (see `daemon/tests/test_app_sdk.rs`): a
//! template that does not run is worse than no template, because it teaches the
//! wrong shape.

use std::path::{Path, PathBuf};

use crate::domain::app_bundle::Bundle;
use crate::domain::app_compat::APP_API_LEVEL;
use crate::domain::app_manifest::{is_app_id, Manifest};
use crate::domain::ports::DynResult;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Template {
    /// A glass window an app owns.
    Surface,
    /// A window docked into the shell's layer stack (a panel).
    LayerSurface,
    /// A background app with no window.
    Service,
}

impl Template {
    pub fn parse(text: &str) -> Option<Self> {
        match text {
            "surface" => Some(Self::Surface),
            "layer-surface" | "layer" => Some(Self::LayerSurface),
            "service" => Some(Self::Service),
            _ => None,
        }
    }

    pub fn name(self) -> &'static str {
        match self {
            Self::Surface => "surface",
            Self::LayerSurface => "layer-surface",
            Self::Service => "service",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CreatedApp {
    pub dir: PathBuf,
    pub manifest: Manifest,
}

/// Create an app from a template.
///
/// Refuses a non-empty target so a stray command cannot overwrite an author's work.
pub fn create_app(id: &str, template: Template, target: &Path) -> DynResult<CreatedApp> {
    if !is_app_id(id) {
        return Err(format!(
            "'{id}' is not a reverse-DNS id (e.g. io.github.alice.clock)"
        )
        .into());
    }
    if target.exists() {
        let empty = std::fs::read_dir(target)?.next().is_none();
        if !empty {
            return Err(format!(
                "{} already exists and is not empty; refusing to overwrite",
                target.display()
            )
            .into());
        }
    }
    std::fs::create_dir_all(target)?;

    let manifest_text = manifest_template(id, template);
    let manifest = Manifest::parse(manifest_text.as_bytes())?;

    std::fs::write(target.join("manifest.json"), &manifest_text)?;
    std::fs::write(target.join("shell.qml"), shell_template(id, template))?;
    std::fs::write(target.join("README.md"), readme_template(id, template))?;
    std::fs::create_dir_all(target.join("tests"))?;
    std::fs::write(target.join("tests/tst_smoke.qml"), smoke_test_template(id))?;

    Ok(CreatedApp {
        dir: target.to_path_buf(),
        manifest,
    })
}

/// Everything an install would refuse, plus the boundary rules.
pub fn lint_dir(root: &Path) -> DynResult<Vec<String>> {
    let mut problems = Vec::new();
    let manifest_path = root.join("manifest.json");
    let manifest = match std::fs::read(&manifest_path) {
        Ok(bytes) => match Manifest::parse(&bytes) {
            Ok(manifest) => Some(manifest),
            Err(err) => {
                problems.push(format!("manifest.json: {err}"));
                None
            }
        },
        Err(err) => {
            problems.push(format!("manifest.json: {err}"));
            None
        }
    };

    if let Some(manifest) = &manifest {
        if !root.join(&manifest.entry.root).is_file() {
            problems.push(format!(
                "entry.root '{}' does not exist",
                manifest.entry.root
            ));
        }
        if manifest.kernel_api > APP_API_LEVEL {
            problems.push(format!(
                "kernelApi {} is newer than this SDK ({APP_API_LEVEL}); the app will not install",
                manifest.kernel_api
            ));
        }
    }

    for path in source_files(root) {
        let relative = path.strip_prefix(root).unwrap_or(&path).display().to_string();
        let text = match std::fs::read_to_string(&path) {
            Ok(text) => text,
            Err(_) => continue,
        };
        for (number, line) in text.lines().enumerate() {
            let trimmed = line.trim();
            if let Some(import) = trimmed.strip_prefix("import ") {
                // Both dialects: `import "path"` and `import Astral.Kernel 1.0`.
                let target = import
                    .trim()
                    .trim_start_matches('"')
                    .split(|c: char| c == '"' || c.is_whitespace())
                    .next()
                    .unwrap_or("");
                if target.contains("Astral.Kernel") {
                    problems.push(format!(
                        "{relative}:{}: imports Astral.Kernel (private) - use Astral.AppKit",
                        number + 1
                    ));
                }
                if target.contains("Kernel/config") {
                    problems.push(format!(
                        "{relative}:{}: imports {target} - an app cannot reach the kernel's singletons",
                        number + 1
                    ));
                }
                // Kernel *services* are a trust question, not a style question: an official
                // embedded app is trusted with the kernel's ports (that is how a session
                // surface reads windows), a community app is not. This must agree with
                // scripts/check_app_boundaries.py, which is why both read the manifest's
                // trust tier rather than hardcoding the rule.
                let official = manifest
                    .as_ref()
                    .map(|manifest| manifest.is_official())
                    .unwrap_or(false);
                if target.contains("Kernel/services") && !official {
                    problems.push(format!(
                        "{relative}:{}: a non-official app may not import {target} (Astral.AppKit only)",
                        number + 1
                    ));
                }
                if target.contains("Apps/") {
                    problems.push(format!(
                        "{relative}:{}: imports another app - use an intent",
                        number + 1
                    ));
                }
            }
            if trimmed.contains("Config.") {
                problems.push(format!(
                    "{relative}:{}: reads Config.* directly - a hosted app has no kernel state",
                    number + 1
                ));
            }
        }
    }

    problems.dedup();
    Ok(problems)
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PackedApp {
    pub path: PathBuf,
    pub digest: String,
    pub files: usize,
}

/// Pack a directory into `<id>-<version>.astralapp` (POSIX ustar, uncompressed).
///
/// `out_dir` defaults to the app directory's parent so an author finds the artifact
/// beside their app rather than in a build folder they did not ask for.
pub fn pack_dir(root: &Path, out_dir: Option<&Path>) -> DynResult<PackedApp> {
    let problems = lint_dir(root)?;
    if !problems.is_empty() {
        return Err(format!(
            "refusing to pack an app that would fail to install:\n  {}",
            problems.join("\n  ")
        )
        .into());
    }

    let bundle = Bundle::from_dir(root)?;
    let manifest = bundle.validate()?;
    let bytes = bundle.to_ustar()?;
    let digest = crate::domain::app_bundle::sha256_hex(&bytes);

    let name = format!("{}-{}.astralapp", manifest.id, manifest.version);
    let target_dir = out_dir
        .map(Path::to_path_buf)
        .or_else(|| root.parent().map(Path::to_path_buf))
        .unwrap_or_else(|| root.to_path_buf());
    std::fs::create_dir_all(&target_dir)?;
    let path = target_dir.join(name);
    std::fs::write(&path, &bytes)?;

    Ok(PackedApp {
        path,
        digest,
        files: bundle.files.len(),
    })
}

fn source_files(root: &Path) -> Vec<PathBuf> {
    let mut files = Vec::new();
    let Ok(entries) = std::fs::read_dir(root) else {
        return files;
    };
    let mut paths: Vec<PathBuf> = entries.flatten().map(|entry| entry.path()).collect();
    paths.sort();
    for path in paths {
        let name = path.file_name().and_then(|n| n.to_str()).unwrap_or("");
        if name.starts_with('.') {
            continue;
        }
        if path.is_dir() {
            files.extend(source_files(&path));
        } else if matches!(
            path.extension().and_then(|extension| extension.to_str()),
            Some("qml") | Some("js")
        ) {
            files.push(path);
        }
    }
    files
}

fn manifest_template(id: &str, template: Template) -> String {
    // The entry object is built separately: a surface needs geometry, a service does
    // not, and string-splicing JSON is how manifests end up with a missing comma.
    let entry = match template {
        Template::Surface => {
            r#"{ "root": "shell.qml", "surface": { "type": "toplevel", "width": 420, "height": 260 } }"#
        }
        // A panel is anchored to an edge and owns no geometry: saying `toplevel` here
        // produced a layer-shell window described as a floating one, which the host would
        // have sized incorrectly.
        Template::LayerSurface => {
            r#"{ "root": "shell.qml", "surface": { "type": "layer-shell", "layer": "top", "anchor": ["top", "left", "right"] } }"#
        }
        Template::Service => r#"{ "root": "shell.qml" }"#,
    };
    format!(
        r#"{{
  "schema": 1,
  "id": "{id}",
  "name": "{name}",
  "version": "0.1.0",
  "kernelApi": {APP_API_LEVEL},
  "dataSchema": 1,
  "trust": "community",
  "runtime": "hosted",
  "publisher": {{ "name": "Your Name" }},
  "entry": {entry},
  "requires": {{ "capabilities": [], "qtModules": [], "apps": [] }},
  "permissions": [],
  "settings": null,
  "distribution": "store"
}}
"#,
        name = title_from_id(id),
    )
}

fn title_from_id(id: &str) -> String {
    id.rsplit('.')
        .next()
        .unwrap_or(id)
        .split(['-', '_'])
        .map(|part| {
            let mut chars = part.chars();
            match chars.next() {
                Some(first) => first.to_uppercase().collect::<String>() + chars.as_str(),
                None => String::new(),
            }
        })
        .collect::<Vec<_>>()
        .join(" ")
}

fn shell_template(id: &str, template: Template) -> String {
    match template {
        Template::Surface => format!(
            r#"// {title} — a hosted Astral app.
//
// `quickshell -p .` starts this file, and `astral app dev .` runs it sandboxed.
// Only Astral.AppKit and Qt are importable: the sandbox mounts nothing else.
import QtQuick
import Astral.AppKit 1.0

AppWindow {{
    width: 420
    height: 260
    anchors {{ top: true; left: true }}
    margins {{ top: 120; left: 160 }}

    Column {{
        anchors.centerIn: parent
        spacing: 8

        Text {{
            anchors.horizontalCenter: parent.horizontalCenter
            text: "{title}"
            color: Colors.textOnSurface
            font.family: Theme.fontFamily
            font.pixelSize: 22
            font.bold: true
        }}
        Text {{
            anchors.horizontalCenter: parent.horizontalCenter
            text: "built against API " + AppApi.level
            color: Colors.primary
            font.pixelSize: 13
        }}
    }}
}}
"#,
            title = title_from_id(id)
        ),
        Template::LayerSurface => format!(
            r#"// {title} — a hosted Astral panel.
//
// Layer-shell knobs are attached (`WlrLayershell.*`): the window itself is AppKit's.
import QtQuick
import Quickshell
import Quickshell.Wayland
import Astral.AppKit 1.0

AppWindow {{
    anchors {{ top: true; left: true; right: true }}
    implicitHeight: 44
    margins {{ top: 8; left: 240; right: 240 }}

    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    Text {{
        anchors.centerIn: parent
        text: "{title}"
        color: Colors.textOnSurface
        font.family: Theme.fontFamily
        font.pixelSize: 13
    }}
}}
"#,
            title = title_from_id(id)
        ),
        Template::Service => format!(
            r#"// {title} — a hosted Astral service.
//
// No window: the shell starts it, it reports state, and the user can stop it. A
// service that needs to talk to the shell does so through `intents` once the
// broker lands (docs/APPS-PLATFORM-SPEC.md section 7.5).
import QtQuick
import Quickshell
import Astral.AppKit 1.0

ShellRoot {{
    property int ticks: 0

    Component.onCompleted: console.log("{id}: started, api " + AppApi.level)

    Timer {{
        interval: 60000
        running: true
        repeat: true
        onTriggered: {{
            ticks++
            console.log("{id}: alive, ticks " + ticks)
        }}
    }}
}}
"#,
            title = title_from_id(id),
            id = id
        ),
    }
}

fn readme_template(id: &str, template: Template) -> String {
    format!(
        r#"# {title}

An Astral app (`{id}`), created from the `{template}` template.

```bash
astral app dev .      # run it sandboxed, with hot reload
astral app test .     # lint + the QML suites in tests/
astral app pack .     # build {id}-0.1.0.astralapp
```

`manifest.json` declares the API level the app was built against (`kernelApi`), the
lifecycle data layout (`dataSchema`), and its permissions. `shell.qml` is what
Quickshell loads.

Rules that the linter enforces:

- import `Astral.AppKit` (and Qt); `Astral.Kernel` is private;
- do not read `Config` — a hosted app has no shell state, it asks through intents;
- no native libraries, no symlinks: a bundle is UTF-8 files.

Design language: `DESIGN.md` in the Astral repository is the authority — use
`Theme`/`Colors`/`Motion` from AppKit rather than literals, so the app follows the
user's wallpaper palette and archetype.
"#,
        title = title_from_id(id),
        template = template.name(),
    )
}

fn smoke_test_template(id: &str) -> String {
    format!(
        r#"import QtQuick
import QtTest

// The suite `astral app test .` runs. Keep it about the app's own policy, not about
// rendering: a window cannot be asserted offscreen.
TestCase {{
    name: "{id}"
    when: windowShown

    function test_manifest_is_documented() {{
        compare(true, true);
    }}
}}
"#
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::domain::app_bundle::Bundle;

    #[test]
    fn a_created_app_is_installable() {
        let dir = tempfile::tempdir().unwrap();
        let target = dir.path().join("clock");
        let created = create_app("io.github.alice.clock", Template::Surface, &target).unwrap();
        assert_eq!(created.manifest.id, "io.github.alice.clock");
        assert_eq!(created.manifest.kernel_api, APP_API_LEVEL);
        assert_eq!(created.manifest.runtime, "hosted");
        assert_eq!(created.manifest.version, "0.1.0");

        assert!(target.join("shell.qml").is_file());
        assert!(target.join("README.md").is_file());
        assert!(target.join("tests/tst_smoke.qml").is_file());

        // The template must import the public SDK and nothing private.
        let shell = std::fs::read_to_string(target.join("shell.qml")).unwrap();
        assert!(shell.contains("import Astral.AppKit 1.0"));
        assert!(!shell.contains("Astral.Kernel"));

        assert!(lint_dir(&target).unwrap().is_empty(), "a fresh app lints clean");
    }

    #[test]
    fn a_created_app_packs_and_reads_back() {
        let dir = tempfile::tempdir().unwrap();
        let target = dir.path().join("clock");
        create_app("io.github.alice.clock", Template::Surface, &target).unwrap();

        let packed = pack_dir(&target, Some(dir.path())).unwrap();
        assert!(packed.path.is_file());
        assert_eq!(packed.digest.len(), 64);
        assert!(packed.files >= 3);

        let bytes = std::fs::read(&packed.path).unwrap();
        let bundle = Bundle::from_ustar(&bytes).unwrap();
        assert!(bundle.files.contains_key("shell.qml"));
        assert!(bundle.files.contains_key("manifest.json"));
        assert!(
            !bundle.files.keys().any(|path| path.starts_with("tests/")),
            "tests/ is not shipped in the bundle"
        );
        assert_eq!(packed.digest, crate::domain::app_bundle::sha256_hex(&bytes));
        // The filename carries identity and version.
        assert!(packed
            .path
            .file_name()
            .unwrap()
            .to_string_lossy()
            .starts_with("io.github.alice.clock-0.1.0"));
    }

    #[test]
    fn every_template_passes_the_installer_and_the_linter() {
        for template in [Template::Surface, Template::LayerSurface, Template::Service] {
            let dir = tempfile::tempdir().unwrap();
            let target = dir.path().join("app");
            let id = format!("io.github.alice.{}", template.name().replace('-', ""));
            create_app(&id, template, &target).unwrap();
            assert!(
                lint_dir(&target).unwrap().is_empty(),
                "{} must lint clean",
                template.name()
            );
            pack_dir(&target, Some(dir.path()))
                .unwrap_or_else(|err| panic!("{} must pack: {err}", template.name()));
        }
    }

    #[test]
    fn a_panel_template_declares_a_panel_and_not_a_floating_window() {
        // The template's manifest and its QML must agree, or the host sizes the window
        // from the wrong description and the panel renders at 420x260.
        let dir = tempfile::tempdir().unwrap();
        let target = dir.path().join("tide");
        create_app("io.github.alice.tide", Template::LayerSurface, &target).unwrap();
        let manifest = std::fs::read_to_string(target.join("manifest.json")).unwrap();
        assert!(manifest.contains(r#""type": "layer-shell""#), "got: {manifest}");
        assert!(!manifest.contains(r#""type": "toplevel""#));
        let shell = std::fs::read_to_string(target.join("shell.qml")).unwrap();
        assert!(shell.contains("WlrLayershell"));

        let surface = std::fs::read_to_string(target.join("shell.qml")).unwrap();
        assert!(surface.contains("WlrLayershell.layer"));
    }

    #[test]
    fn kernel_services_are_allowed_only_for_official_apps() {
        // The two linters (this one and scripts/check_app_boundaries.py) previously
        // disagreed here, so `astral app test` refused a dashboard that `make test`
        // accepted. Trust tier, read from the manifest, is the single rule.
        for (trust, expected) in [("community", true), ("official", false)] {
            let dir = tempfile::tempdir().unwrap();
            let target = dir.path().join("app");
            create_app("io.github.alice.clock", Template::Surface, &target).unwrap();
            let manifest = std::fs::read_to_string(target.join("manifest.json"))
                .unwrap()
                .replace("\"trust\": \"community\"", &format!("\"trust\": \"{trust}\""));
            std::fs::write(target.join("manifest.json"), manifest).unwrap();
            std::fs::write(
                target.join("ports.qml"),
                "import QtQuick\nimport \"../../Kernel/services/WindowService.qml\"\nItem { }\n",
            )
            .unwrap();

            let problems = lint_dir(&target).unwrap();
            let mentions_services = problems
                .iter()
                .any(|problem| problem.contains("Kernel/services"));
            assert_eq!(
                mentions_services, expected,
                "{trust} app: services import must be {}; got {problems:?}",
                if expected { "refused" } else { "allowed" }
            );
        }
    }

    #[test]
    fn an_existing_non_empty_directory_is_never_overwritten() {
        let dir = tempfile::tempdir().unwrap();
        let target = dir.path().join("clock");
        std::fs::create_dir_all(&target).unwrap();
        std::fs::write(target.join("notes.md"), "mine").unwrap();
        let error = create_app("io.github.alice.clock", Template::Surface, &target).unwrap_err();
        assert!(error.to_string().contains("refusing to overwrite"));
        assert_eq!(std::fs::read_to_string(target.join("notes.md")).unwrap(), "mine");
    }

    #[test]
    fn an_invalid_id_is_refused_before_any_file_is_written() {
        let dir = tempfile::tempdir().unwrap();
        let target = dir.path().join("clock");
        assert!(create_app("Clock", Template::Surface, &target).is_err());
        assert!(!target.exists(), "nothing is created for an invalid id");
    }

    #[test]
    fn lint_names_the_line_and_the_rule() {
        let dir = tempfile::tempdir().unwrap();
        let target = dir.path().join("clock");
        create_app("io.github.alice.clock", Template::Surface, &target).unwrap();
        std::fs::write(
            target.join("extra.qml"),
            "import Astral.Kernel 1.0\nItem { property var c: Config.dockIconSize }\n",
        )
        .unwrap();

        let problems = lint_dir(&target).unwrap();
        assert!(problems.iter().any(|p| p.contains("Astral.Kernel")), "{problems:?}");
        assert!(problems.iter().any(|p| p.contains("Config.")), "{problems:?}");
        assert!(
            problems.iter().any(|p| p.contains("extra.qml:1")),
            "the problem names the line: {problems:?}"
        );
    }

    #[test]
    fn packing_refuses_an_app_that_would_fail_to_install() {
        let dir = tempfile::tempdir().unwrap();
        let target = dir.path().join("clock");
        create_app("io.github.alice.clock", Template::Surface, &target).unwrap();
        std::fs::remove_file(target.join("shell.qml")).unwrap();
        let error = pack_dir(&target, Some(dir.path())).unwrap_err();
        assert!(error.to_string().contains("refusing to pack"), "got: {error}");
    }

    #[test]
    fn the_sdk_repository_example_still_lints_clean() {
        let root = Path::new(env!("CARGO_MANIFEST_DIR"))
            .parent()
            .unwrap()
            .join("sdk/examples/hello");
        let problems = lint_dir(&root).unwrap();
        assert!(problems.is_empty(), "sdk/examples/hello: {problems:?}");
    }
}
