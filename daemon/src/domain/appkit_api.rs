//! The AppKit surface, as data — so "frozen" is a fact and not a promise.
//!
//! An SDK is a contract with people who are not in this repository. The only durable way
//! to keep it is to make the surface machine-readable and compare it:
//!
//! * [`surface`] parses the QML in `modules/Astral/AppKit` into a stable list of members.
//! * [`render`] writes the list, plus the level history and the deprecation table, as
//!   `docs/APPKIT-API.md`.
//! * [`check`] compares a computed surface with the recorded one and names every member
//!   that appeared, disappeared, or changed kind.
//!
//! A change that is not accompanied by a level decision therefore fails a test rather than
//! shipping quietly. Deprecation is markup (`// @deprecated level: 2 removal: 3 reason: …`)
//! that [`deprecations`] parses and [`check`] enforces: nothing may be removed before its
//! declared removal level, and nothing may be deprecated without one.

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

use crate::domain::ports::DynResult;

/// A public member of the SDK: types, properties, functions and signals.
#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord)]
pub struct Member {
    /// Type name (the QML file stem) or a nested member's owner.
    pub owner: String,
    /// `type`, `property`, `function`, `signal`, or `enum`.
    pub kind: String,
    pub name: String,
}

impl Member {
    /// One stable line: `Owner kind name`. Sorted, so the file diffs only on real changes.
    pub fn line(&self) -> String {
        format!("{} {} {}", self.owner, self.kind, self.name)
    }
}

/// The parsed surface of one directory of QML.
#[derive(Debug, Clone, Default)]
pub struct Surface {
    pub members: Vec<Member>,
    pub deprecations: Vec<Deprecation>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Deprecation {
    pub owner: String,
    pub member: String,
    /// The level that introduced the deprecation.
    pub level: u32,
    /// The first level at which the member may be gone. Must exceed `level`.
    pub removal: u32,
    pub reason: String,
}

/// Parse `modules/Astral/AppKit` (or any AppKit copy) into its public surface.
pub fn surface(dir: &Path) -> DynResult<Surface> {
    let mut files: Vec<PathBuf> = std::fs::read_dir(dir)?
        .filter_map(Result::ok)
        .map(|entry| entry.path())
        .filter(|path| path.extension().is_some_and(|ext| ext == "qml"))
        .collect();
    files.sort();

    let mut surface = Surface::default();
    for file in files {
        let Some(stem) = file.file_stem().and_then(|stem| stem.to_str()) else {
            continue;
        };
        let text = std::fs::read_to_string(&file)?;
        surface.members.push(Member {
            owner: stem.to_string(),
            kind: "type".to_string(),
            name: stem.to_string(),
        });
        scan_members(stem, &text, &mut surface);
    }
    surface.members.sort();
    surface.members.dedup();
    surface.deprecations.sort_by(|a, b| (a.owner.clone(), a.member.clone()).cmp(&(b.owner.clone(), b.member.clone())));
    Ok(surface)
}

fn scan_members(owner: &str, text: &str, surface: &mut Surface) {
    for line in text.lines() {
        let trimmed = line.trim();
        if trimmed.starts_with("//") {
            if let Some(deprecation) = parse_deprecation(owner, trimmed) {
                surface.deprecations.push(deprecation);
            }
            continue;
        }
        if let Some(name) = after(trimmed, "readonly property ") {
            push(surface, owner, "property", name);
        } else if let Some(name) = after(trimmed, "property ") {
            push(surface, owner, "property", name);
        } else if let Some(name) = function_name(trimmed) {
            push(surface, owner, "function", name);
        } else if let Some(name) = after(trimmed, "signal ") {
            push(surface, owner, "signal", name);
        }
    }
}

/// `readonly property int level: 1` -> `level`; a declaration's name is the token before
/// the first `:` or `(`.
fn after<'a>(line: &'a str, prefix: &str) -> Option<&'a str> {
    let rest = line.strip_prefix(prefix)?;
    // Skip the type (`int`, `var`, `list<...>`) to the member's own name.
    let rest = rest.trim_start();
    let name = match rest.split_once(char::is_whitespace) {
        Some((_type, rest)) => rest.trim_start(),
        None => rest,
    };
    let name = name.split([':', '(']).next().unwrap_or("").trim();
    if name.is_empty() || !name.chars().next().is_some_and(|c| c.is_ascii_alphabetic()) {
        return None;
    }
    Some(name)
}

/// `function supports(appLevel) {` -> `supports`: the name ends at the argument list.
fn function_name(line: &str) -> Option<&str> {
    let rest = line.strip_prefix("function ")?;
    let name = rest.split(['(', ':']).next().unwrap_or("").trim();
    if name.is_empty() || !name.chars().next().is_some_and(|c| c.is_ascii_alphabetic()) {
        return None;
    }
    Some(name)
}

fn push(surface: &mut Surface, owner: &str, kind: &str, name: &str) {
    surface.members.push(Member {
        owner: owner.to_string(),
        kind: kind.to_string(),
        name: name.to_string(),
    });
}

/// `// @deprecated member: accent level: 2 removal: 3 reason: use Colors.accent`
///
/// Keys and values are separate tokens, so the parser pairs them positionally: a token
/// ending in `:` introduces the next token as its value. `reason:` takes the rest of the
/// line, because a reason is a sentence.
fn parse_deprecation(owner: &str, comment: &str) -> Option<Deprecation> {
    let rest = comment.strip_prefix("// @deprecated")?;
    let (head, reason) = match rest.split_once("reason:") {
        Some((head, reason)) => (head, reason.trim().to_string()),
        None => (rest, String::new()),
    };

    let tokens: Vec<&str> = head.split_whitespace().collect();
    let mut member = String::new();
    let mut level = None;
    let mut removal = None;
    let mut index = 0;
    while index + 1 < tokens.len() + 1 {
        let Some(key) = tokens.get(index) else { break };
        let Some(value) = tokens.get(index + 1) else { break };
        match key.trim_end_matches(':') {
            "member" => member = (*value).to_string(),
            "level" => level = value.parse().ok(),
            "removal" => removal = value.parse().ok(),
            _ => {}
        }
        index += 2;
    }

    Some(Deprecation {
        owner: owner.to_string(),
        member,
        level: level?,
        removal: removal?,
        reason,
    })
}

/// What changed between a recorded surface and a computed one.
#[derive(Debug, Default, PartialEq, Eq)]
pub struct Drift {
    pub added: Vec<String>,
    pub removed: Vec<String>,
}

impl Drift {
    pub fn is_empty(&self) -> bool {
        self.added.is_empty() && self.removed.is_empty()
    }

    pub fn describe(&self) -> String {
        let mut lines = Vec::new();
        for line in &self.added {
            lines.push(format!("+ {line}"));
        }
        for line in &self.removed {
            lines.push(format!("- {line}"));
        }
        lines.join("\n")
    }
}

/// Compare a computed surface with the recorded lines (one `Owner kind name` per line).
pub fn check(recorded: &str, surface: &Surface) -> Drift {
    let recorded: std::collections::BTreeSet<String> = recorded
        .lines()
        .map(str::trim)
        .filter(|line| !line.is_empty() && !line.starts_with('#'))
        .map(str::to_string)
        .collect();
    let computed: std::collections::BTreeSet<String> =
        surface.members.iter().map(Member::line).collect();

    Drift {
        added: computed.difference(&recorded).cloned().collect(),
        removed: recorded.difference(&computed).cloned().collect(),
    }
}

/// The deprecation rules, checked as data: a deprecation must name its level, its removal
/// level must be later than its level, and nothing may be removed before the level the
/// shell still supports.
pub fn validate_deprecations(surface: &Surface, floor: u32) -> DynResult<()> {
    for deprecation in &surface.deprecations {
        if deprecation.member.is_empty() {
            return Err(format!(
                "{}: a deprecation must name the member it applies to (member: <name>)",
                deprecation.owner
            )
            .into());
        }
        if deprecation.removal <= deprecation.level {
            return Err(format!(
                "{}.{}: removal level {} must be later than deprecation level {}",
                deprecation.owner, deprecation.member, deprecation.removal, deprecation.level
            )
            .into());
        }
        if deprecation.removal <= floor {
            return Err(format!(
                "{}.{}: cannot be removed at level {} while the shell still supports level {floor}",
                deprecation.owner, deprecation.member, deprecation.removal
            )
            .into());
        }
        if deprecation.reason.is_empty() {
            return Err(format!(
                "{}.{}: a deprecation needs a reason an app author can act on",
                deprecation.owner, deprecation.member
            )
            .into());
        }
    }
    Ok(())
}

/// Render `docs/APPKIT-API.md`: the surface, the level history, and the deprecation table.
pub fn render(surface: &Surface, level: u32, floor: u32, releases: &BTreeMap<u32, String>) -> String {
    let mut out = String::new();
    out.push_str("# AppKit API\n\n");
    out.push_str(
        "> Generated by `astral-plasma app api --write`. Do not edit by hand: \
`daemon/tests/test_appkit_api.rs` fails when this file, the QML sources, and \
`domain::app_compat` disagree.\n\n",
    );
    out.push_str(&format!(
        "Current level **{level}**, oldest supported level **{floor}**. An app declares the \
level it was built against (`kernelApi`); the shell loads it when `floor <= kernelApi <= {level}`.\n\n"
    ));

    out.push_str("## Level history\n\n| Level | Release |\n| --- | --- |\n");
    for (level, release) in releases {
        out.push_str(&format!("| {level} | {release} |\n"));
    }

    out.push_str("\n## Surface\n\nEvery row is frozen at the current level and may only change with a level decision.\n\n");
    out.push_str("| Owner | Kind | Member |\n| --- | --- | --- |\n");
    for member in &surface.members {
        out.push_str(&format!("| {} | {} | {} |\n", member.owner, member.kind, member.name));
    }

    out.push_str("\n## Deprecations\n\n");
    if surface.deprecations.is_empty() {
        out.push_str("None. Nothing in the current surface is deprecated.\n");
    } else {
        out.push_str("| Owner | Member | Deprecated at | Removable at | Reason |\n| --- | --- | --- | --- | --- |\n");
        for deprecation in &surface.deprecations {
            out.push_str(&format!(
                "| {} | {} | {} | {} | {} |\n",
                deprecation.owner, deprecation.member, deprecation.level, deprecation.removal, deprecation.reason
            ));
        }
    }

    out.push_str("\n## Bumping the floor\n\n");
    out.push_str(
        "1. Choose the level being dropped; it must be below the current level.\n\
2. Raise `APP_API_FLOOR` and the `floor` in `modules/Astral/AppKit/AppApi.qml` together — \
`daemon/tests/test_appkit_constants.rs` fails otherwise.\n\
3. Remove only members whose `removal` level is at or below the new floor.\n\
4. Run `astral-plasma app api --write`, then `make test`: the surface snapshot must change \
in the same commit.\n\
5. Note the floor bump in `docs/UPDATES.md` so users learn why an old app stopped loading.\n",
    );

    out.push_str("\n## Releasing an app\n\n");
    out.push_str(
        "1. Bump `version` in `manifest.json` (semver; a permission change is at least minor).\n\
2. Add a changelog entry naming user-visible changes.\n\
3. `astral-plasma app lint` and `astral-plasma app test` must pass.\n\
4. `astral-plasma app pack` and add the artifact plus its digest to the catalog.\n\
5. If `kernelApi` changed, the app is rebuilt against that level and the catalog entry says so.\n",
    );
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn members_are_parsed_with_their_kinds_and_owners() {
        let dir = tempfile::tempdir().unwrap();
        std::fs::write(
            dir.path().join("Widget.qml"),
            "pragma Singleton\nQtObject {\n\
             readonly property int level: 1\n\
             property string title: \"x\"\n\
             function supports(appLevel) { return true }\n\
             signal closed()\n\
            }\n",
        )
        .unwrap();
        let surface = surface(dir.path()).unwrap();
        let lines: Vec<String> = surface.members.iter().map(Member::line).collect();
        assert_eq!(
            lines,
            vec![
                "Widget function supports".to_string(),
                "Widget property level".to_string(),
                "Widget property title".to_string(),
                "Widget signal closed".to_string(),
                "Widget type Widget".to_string(),
            ]
        );
    }

    #[test]
    fn a_deprecation_comment_is_structured_data() {
        let dir = tempfile::tempdir().unwrap();
        std::fs::write(
            dir.path().join("Theme.qml"),
            "QtObject {\n\
             // @deprecated member: accent level: 2 removal: 3 reason: use Colors.accent\n\
             property color accent: \"#fff\"\n\
            }\n",
        )
        .unwrap();
        let surface = surface(dir.path()).unwrap();
        assert_eq!(
            surface.deprecations,
            vec![Deprecation {
                owner: "Theme".to_string(),
                member: "accent".to_string(),
                level: 2,
                removal: 3,
                reason: "use Colors.accent".to_string(),
            }]
        );
    }

    #[test]
    fn drift_names_both_directions() {
        let dir = tempfile::tempdir().unwrap();
        std::fs::write(dir.path().join("A.qml"), "QtObject {\n    property int kept: 1\n}\n").unwrap();
        let surface = surface(dir.path()).unwrap();
        let drift = check("A property kept\nA property gone\n", &surface);
        // `kept` is recorded, so only the type itself is new.
        assert_eq!(drift.added, vec!["A type A".to_string()]);
        assert_eq!(drift.removed, vec!["A property gone".to_string()]);
        assert!(!drift.is_empty());
        assert!(drift.describe().contains("+ A type A"));
        assert!(drift.describe().contains("- A property gone"));
    }

    #[test]
    fn an_unchanged_surface_has_no_drift() {
        let dir = tempfile::tempdir().unwrap();
        std::fs::write(dir.path().join("A.qml"), "QtObject {\n    property int x: 1\n}\n").unwrap();
        let surface = surface(dir.path()).unwrap();
        let recorded: String = surface.members.iter().map(|m| m.line() + "\n").collect();
        assert!(check(&recorded, &surface).is_empty());
    }

    fn deprecated(level: u32, removal: u32, reason: &str) -> Surface {
        Surface {
            members: Vec::new(),
            deprecations: vec![Deprecation {
                owner: "Theme".to_string(),
                member: "accent".to_string(),
                level,
                removal,
                reason: reason.to_string(),
            }],
        }
    }

    #[test]
    fn a_deprecation_without_a_removal_level_is_rejected() {
        let error = validate_deprecations(&deprecated(2, 2, "use Colors"), 1).unwrap_err();
        assert!(error.to_string().contains("must be later"));
    }

    #[test]
    fn nothing_may_be_removed_while_the_shell_still_supports_it() {
        let error = validate_deprecations(&deprecated(2, 3, "use Colors"), 3).unwrap_err();
        assert!(error.to_string().contains("still supports level 3"));
    }

    #[test]
    fn a_deprecation_needs_a_reason() {
        let error = validate_deprecations(&deprecated(2, 3, ""), 1).unwrap_err();
        assert!(error.to_string().contains("needs a reason"));
    }

    #[test]
    fn a_well_formed_deprecation_passes() {
        validate_deprecations(&deprecated(2, 3, "use Colors.accent"), 1).unwrap();
    }

    #[test]
    fn the_rendered_document_names_levels_and_the_procedure() {
        let mut releases = BTreeMap::new();
        releases.insert(1, "0.2.0".to_string());
        let document = render(&Surface::default(), 1, 1, &releases);
        assert!(document.contains("Current level **1**"));
        assert!(document.contains("| 1 | 0.2.0 |"));
        assert!(document.contains("None. Nothing in the current surface is deprecated."));
        assert!(document.contains("## Bumping the floor"));
        assert!(document.contains("## Releasing an app"));
    }
}
