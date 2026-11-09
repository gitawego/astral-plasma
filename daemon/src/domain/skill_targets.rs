//! Agent targets: the directories agents read skills from.
//!
//! Data, not code paths. The table below is the ecosystem's layout (the `skills` CLI records
//! the same paths, several agents share `.agents/skills`), and a user may add a target without
//! touching the planner. Every install is "a link per target" (spec §6.1).

use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};

/// How a target receives a skill.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum LinkStyle {
    /// A relative symlink into the canonical entry or the store — the default (D5).
    Relative,
    /// Copy the files. The escape hatch for an agent that does not follow links.
    Copy,
}

/// One agent's skill directories.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Target {
    pub id: &'static str,
    pub label: &'static str,
    /// Where the agent looks inside a project.
    pub project_dir: &'static str,
    /// Where the agent looks for the user (absolute, `~` expanded by [`Target::global_path`]).
    pub global_dir: &'static str,
    /// Whether this target is the canonical farm (`.agents/skills`).
    pub canonical: bool,
    pub style: LinkStyle,
}

/// The ecosystem table (spec Appendix A measured which of these exist here).
///
/// `codex` is canonical because five agents read `.agents/skills`; everyone else links into it,
/// which is also what the `skills` CLI does, so both tools agree about the tree (D10).
pub const TARGETS: [Target; 7] = [
    Target {
        id: "codex",
        label: "Codex",
        project_dir: ".agents/skills",
        global_dir: "~/.agents/skills",
        canonical: true,
        style: LinkStyle::Relative,
    },
    Target {
        id: "claude-code",
        label: "Claude Code",
        project_dir: ".claude/skills",
        global_dir: "~/.claude/skills",
        canonical: false,
        style: LinkStyle::Relative,
    },
    Target {
        id: "cursor",
        label: "Cursor",
        project_dir: ".agents/skills",
        global_dir: "~/.cursor/skills",
        canonical: false,
        style: LinkStyle::Relative,
    },
    Target {
        id: "gemini-cli",
        label: "Gemini CLI",
        project_dir: ".agents/skills",
        global_dir: "~/.gemini/skills",
        canonical: false,
        style: LinkStyle::Relative,
    },
    Target {
        id: "github-copilot",
        label: "GitHub Copilot",
        project_dir: ".agents/skills",
        global_dir: "~/.copilot/skills",
        canonical: false,
        style: LinkStyle::Relative,
    },
    Target {
        id: "opencode",
        label: "OpenCode",
        project_dir: ".agents/skills",
        global_dir: "~/.config/opencode/skills",
        canonical: false,
        style: LinkStyle::Relative,
    },
    Target {
        id: "pi",
        label: "Pi",
        project_dir: ".agents/skills",
        global_dir: "~/.pi/agent/skills",
        canonical: false,
        style: LinkStyle::Relative,
    },
];

/// Where a skill lives for one scope.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "lowercase")]
pub enum Scope {
    /// The user's own directories, for every project.
    Global,
    /// One repository's directories (`.claude/skills`, … relative to its root).
    Project { root: PathBuf },
}

impl Scope {
    pub fn key(&self) -> String {
        match self {
            Self::Global => "global".to_string(),
            Self::Project { root } => format!("project:{}", root.display()),
        }
    }

    pub fn parse(text: &str) -> Option<Self> {
        let text = text.trim();
        if text == "global" {
            return Some(Self::Global);
        }
        let root = text.strip_prefix("project:")?;
        if root.is_empty() {
            return None;
        }
        Some(Self::Project {
            root: PathBuf::from(root),
        })
    }
}

impl Target {
    /// The directory this target reads for `scope`, resolving a global path against `home`.
    ///
    /// Taking the home explicitly keeps the manager testable and honest: a daemon may run with a
    /// different `$HOME` than the caller expects, and a test never wants to touch the real one.
    pub fn dir_for_with(&self, scope: &Scope, home: &Path) -> PathBuf {
        match scope {
            Scope::Global => expand_into(home, self.global_dir),
            Scope::Project { root } => root.join(self.project_dir),
        }
    }

    /// The directory this target reads for `scope`, against the process `$HOME`.
    pub fn dir_for(&self, scope: &Scope) -> PathBuf {
        match scope {
            Scope::Global => self.global_path(),
            Scope::Project { root } => root.join(self.project_dir),
        }
    }

    fn global_path(&self) -> PathBuf {
        expand_home(self.global_dir)
    }

    /// Whether this target is in use on this machine.
    ///
    /// "In use" means its directory (or, for a fresh agent, the parent that holds it) exists:
    /// installing into 79 directories when four agents exist is noise, installing into none
    /// because a flag was forgotten is a silent no-op (D9).
    pub fn is_present(&self, home: &Path) -> bool {
        let dir = expand_into(home, self.global_dir);
        if dir.is_dir() {
            return true;
        }
        dir.parent().map(|parent| parent.is_dir()).unwrap_or(false)
    }
}

/// Expand a leading `~` against `$HOME`.
pub fn expand_home(path: &str) -> PathBuf {
    let home = std::env::var_os("HOME").map(PathBuf::from).unwrap_or_else(|| PathBuf::from("/"));
    expand_into(&home, path)
}

fn expand_into(home: &Path, path: &str) -> PathBuf {
    match path.strip_prefix("~/") {
        Some(rest) => home.join(rest),
        None => PathBuf::from(path),
    }
}

/// Look a target up by id or by its label's slug.
pub fn target_by_id(id: &str) -> Option<&'static Target> {
    let wanted = id.trim().to_ascii_lowercase();
    TARGETS.iter().find(|target| target.id == wanted)
}

/// Targets detected on this machine, in table order.
pub fn detected(home: &Path) -> Vec<&'static Target> {
    TARGETS.iter().filter(|target| target.is_present(home)).collect()
}

/// Resolve a comma-separated target list (`claude-code,codex`), or everything detected.
///
/// An unknown id is an error naming the known ones: silently installing nowhere is the failure
/// mode this function exists to prevent.
pub fn resolve_targets(list: Option<&str>, home: &Path) -> Result<Vec<&'static Target>, String> {
    let Some(list) = list.map(str::trim).filter(|value| !value.is_empty()) else {
        return Ok(detected(home));
    };
    let mut chosen: Vec<&'static Target> = Vec::new();
    for part in list.split(',') {
        let part = part.trim();
        if part.is_empty() {
            continue;
        }
        if part == "*" || part == "all" {
            return Ok(TARGETS.iter().collect());
        }
        let target = target_by_id(part).ok_or_else(|| {
            format!(
                "unknown target '{part}'; known targets: {}",
                TARGETS.iter().map(|t| t.id).collect::<Vec<_>>().join(", ")
            )
        })?;
        if !chosen.iter().any(|existing| existing.id == target.id) {
            chosen.push(target);
        }
    }
    Ok(chosen)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_table_matches_the_ecosystem_layout() {
        let claude = target_by_id("claude-code").expect("claude-code is a target");
        assert_eq!(claude.project_dir, ".claude/skills");
        assert_eq!(claude.global_dir, "~/.claude/skills");
        let codex = target_by_id("codex").expect("codex is a target");
        assert!(codex.canonical, "five agents read .agents/skills, so it is canonical");
        assert_eq!(codex.project_dir, ".agents/skills");
        // Every target has a unique id.
        let mut ids: Vec<&str> = TARGETS.iter().map(|t| t.id).collect();
        ids.sort();
        ids.dedup();
        assert_eq!(ids.len(), TARGETS.len());
    }

    #[test]
    fn a_target_dir_follows_the_scope() {
        let claude = target_by_id("claude-code").unwrap();
        let project = claude.dir_for(&Scope::Project { root: PathBuf::from("/repo") });
        assert_eq!(project, PathBuf::from("/repo/.claude/skills"));
        let global = claude.dir_for(&Scope::Global);
        assert!(global.is_absolute(), "a global path is absolute: {}", global.display());
    }

    #[test]
    fn scope_round_trips_through_its_key() {
        let project = Scope::Project { root: PathBuf::from("/repo") };
        assert_eq!(Scope::parse(&project.key()), Some(project));
        assert_eq!(Scope::parse("global"), Some(Scope::Global));
        assert_eq!(Scope::parse("project:"), None, "a project scope needs a root");
        assert_eq!(Scope::parse("nonsense"), None);
    }

    #[test]
    fn detection_reports_what_exists() {
        let home = tempfile::tempdir().unwrap();
        std::fs::create_dir_all(home.path().join(".claude/skills")).unwrap();
        std::fs::create_dir_all(home.path().join(".agents/skills")).unwrap();
        let found: Vec<&str> = detected(home.path()).iter().map(|t| t.id).collect();
        assert!(found.contains(&"claude-code"));
        assert!(found.contains(&"codex"));
        assert!(!found.contains(&"cursor"), "absent agents are not detected");
        // An agent whose directory is missing but whose config dir exists still counts.
        std::fs::create_dir_all(home.path().join(".config/opencode")).unwrap();
        let found: Vec<&str> = detected(home.path()).iter().map(|t| t.id).collect();
        assert!(found.contains(&"opencode"), "a config dir is enough to offer the target");
    }

    #[test]
    fn an_unknown_target_names_the_known_ones() {
        let home = tempfile::tempdir().unwrap();
        let error = resolve_targets(Some("claude-code,nope"), home.path()).unwrap_err();
        assert!(error.contains("nope"), "got: {error}");
        assert!(error.contains("claude-code"), "the error lists the vocabulary: {error}");
    }

    #[test]
    fn explicit_targets_win_and_star_means_all() {
        let home = tempfile::tempdir().unwrap();
        let chosen = resolve_targets(Some("claude-code, codex"), home.path()).unwrap();
        assert_eq!(chosen.len(), 2);
        let all = resolve_targets(Some("*"), home.path()).unwrap();
        assert_eq!(all.len(), TARGETS.len());
        // No list, no detection: nothing, and that is visible to the caller.
        assert!(resolve_targets(None, home.path()).unwrap().is_empty());
    }
}
