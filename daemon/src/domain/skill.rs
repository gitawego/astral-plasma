//! A skill: a directory with `SKILL.md`, its frontmatter, and a content hash.
//!
//! Everything here is pure over bytes so the rules are testable without a filesystem: discovery
//! takes a list of `(relative path, bytes)`, which the git/local adapters produce and the
//! planners consume.

use std::collections::BTreeMap;

use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

/// A skill's identity: the frontmatter `name`, or the directory name when it has none.
#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize)]
#[serde(try_from = "String", into = "String")]
pub struct SkillId(String);

impl SkillId {
    /// A skill id is a directory-safe slug: letters, digits, `-`, `_`, `.`.
    pub fn parse(raw: &str) -> Result<Self, String> {
        let trimmed = raw.trim();
        if trimmed.is_empty() {
            return Err("a skill id cannot be empty".to_string());
        }
        if trimmed == "." || trimmed == ".." {
            return Err(format!("'{trimmed}' is not a skill id"));
        }
        if !trimmed
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_' || c == '.')
        {
            return Err(format!(
                "'{trimmed}' is not a skill id: use letters, digits, '-', '_' or '.'"
            ));
        }
        Ok(Self(trimmed.to_string()))
    }

    pub fn as_str(&self) -> &str {
        &self.0
    }
}

impl TryFrom<String> for SkillId {
    type Error = String;
    fn try_from(value: String) -> Result<Self, Self::Error> {
        Self::parse(&value)
    }
}

impl From<SkillId> for String {
    fn from(value: SkillId) -> Self {
        value.0
    }
}

impl std::fmt::Display for SkillId {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.0)
    }
}

/// The YAML frontmatter fields the manager uses. Everything else is opaque to it.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Frontmatter {
    pub name: Option<String>,
    pub description: Option<String>,
    /// The `metadata.version` value, when a skill declares one (used by the update report).
    pub version: Option<String>,
}

/// Parse the `---`-fenced YAML block at the top of a `SKILL.md`.
///
/// Deliberately a small reader, not a YAML engine: the specification's frontmatter is flat
/// `key: value`, optionally with a `|` or `>` block for `description`, and a skill whose
/// frontmatter is more exotic than that is reported as having no frontmatter rather than
/// guessed at.
pub fn parse_frontmatter(markdown: &str) -> Frontmatter {
    let mut lines = markdown.lines();
    let first = lines.next().unwrap_or("").trim_end();
    if first.trim() != "---" {
        return Frontmatter::default();
    }

    let mut out = Frontmatter::default();
    let mut block: Option<String> = None; // key receiving an indented block
    let mut collected: Vec<String> = Vec::new();
    let mut nested = false; // inside a key whose value was a nested map (`metadata:`)

    let mut flush = |key: Option<String>, text: Vec<String>, out: &mut Frontmatter| {
        let Some(key) = key else { return };
        let joined = text.join("\n").trim().trim_matches('"').to_string();
        if joined.is_empty() {
            return;
        }
        match key.as_str() {
            "name" => out.name = Some(joined),
            "description" => out.description = Some(joined),
            "version" => out.version = Some(joined),
            _ => {}
        }
    };

    for line in lines {
        if line.trim() == "---" {
            flush(block.take(), std::mem::take(&mut collected), &mut out);
            break;
        }
        let indented = line.starts_with(' ') || line.starts_with('\t');
        if let Some(key) = &block {
            if indented {
                collected.push(line.trim().to_string());
                continue;
            }
            flush(Some(key.clone()), std::mem::take(&mut collected), &mut out);
            block = None;
        }
        if nested {
            if indented {
                // A nested map belongs to its key, not to this reader.
                continue;
            }
            nested = false;
        }
        let Some((key, value)) = line.split_once(':') else {
            continue;
        };
        let key = key.trim().to_ascii_lowercase();
        let value = value.trim();
        if value == "|" || value == ">" || value == "|-" || value == ">-" {
            block = Some(key);
            collected.clear();
            continue;
        }
        if value.is_empty() {
            nested = true;
            continue;
        }
        let cleaned = value.trim_matches('"').trim_matches('\'').to_string();
        match key.as_str() {
            "name" => out.name = Some(cleaned),
            "description" => out.description = Some(cleaned),
            "version" => out.version = Some(cleaned),
            _ => {}
        }
    }
    out
}

/// A discovered skill.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SkillMeta {
    pub id: SkillId,
    pub description: String,
    /// Directory of the skill inside its source, with no trailing slash (`""` for a root skill).
    pub subpath: String,
    /// SHA-256 over the skill's files (see [`hash_files`]).
    pub hash: String,
    pub files: u32,
    pub bytes: u64,
    pub version: Option<String>,
}

impl SkillMeta {
    /// `subpath/SKILL.md`, or `SKILL.md` for a root skill.
    pub fn manifest_path(&self) -> String {
        if self.subpath.is_empty() {
            "SKILL.md".to_string()
        } else {
            format!("{}/SKILL.md", self.subpath)
        }
    }
}

/// Content hash of one skill, ecosystem-compatible in shape: files sorted by relative path, and
/// for each file its path and then its bytes are fed into SHA-256 (spec D10).
///
/// Paths are relative to the skill directory, so moving a skill does not change its hash.
pub fn hash_files(files: &[(String, Vec<u8>)]) -> String {
    let mut sorted: Vec<&(String, Vec<u8>)> = files.iter().collect();
    sorted.sort_by(|a, b| a.0.cmp(&b.0));
    let mut hasher = Sha256::new();
    for (path, bytes) in sorted {
        hasher.update(path.as_bytes());
        hasher.update(bytes);
    }
    format!("{:x}", hasher.finalize())
}

/// Directories that never contain a distributable skill.
const IGNORED_DIRS: [&str; 5] = [".git", "node_modules", "target", ".venv", "__pycache__"];

/// Discover the skills in a source tree.
///
/// `files` are `(path, bytes)` relative to the source root. `subpath` narrows the search
/// (monorepos). `deep` keeps looking below a root `SKILL.md`; without it, a source whose root is
/// itself a skill is treated as one skill — that is what a "single skill repository" looks like.
pub fn discover(
    files: &[(String, Vec<u8>)],
    subpath: Option<&str>,
    deep: bool,
) -> Vec<SkillMeta> {
    let prefix = subpath
        .map(|path| path.trim_matches('/').to_string())
        .filter(|path| !path.is_empty());

    // Which directories hold a `SKILL.md`? Everything below one of them belongs to that skill.
    let mut skill_dirs: Vec<String> = Vec::new();
    for (path, _) in files {
        let relative = match &prefix {
            Some(prefix) => match path.strip_prefix(prefix.as_str()) {
                Some(rest) => rest.trim_start_matches('/'),
                None => continue,
            },
            None => path.as_str(),
        };
        if relative.is_empty() || in_ignored_dir(relative) {
            continue;
        }
        if let Some(dir) = skill_dir_of(relative) {
            if !skill_dirs.contains(&dir) {
                skill_dirs.push(dir);
            }
        }
    }
    // Deepest first, so a file inside a nested skill group is not claimed by its parent.
    skill_dirs.sort_by_key(|dir| std::cmp::Reverse(dir.len()));

    let mut groups: BTreeMap<String, Vec<(String, Vec<u8>)>> = BTreeMap::new();
    for (path, bytes) in files {
        let relative = match &prefix {
            Some(prefix) => match path.strip_prefix(prefix.as_str()) {
                Some(rest) => rest.trim_start_matches('/'),
                None => continue,
            },
            None => path.as_str(),
        };
        if relative.is_empty() || in_ignored_dir(relative) {
            continue;
        }
        let Some(owner) = skill_dirs.iter().find(|dir| owns(dir, relative)) else {
            continue;
        };
        let inside = relative
            .strip_prefix(owner.as_str())
            .unwrap_or(relative)
            .trim_start_matches('/')
            .to_string();
        groups
            .entry(owner.clone())
            .or_default()
            .push((inside, bytes.clone()));
    }

    let mut skills: Vec<SkillMeta> = Vec::new();
    for (dir, owned) in groups {
        let Some((_, manifest)) = owned
            .iter()
            .find(|(path, _)| path.eq_ignore_ascii_case("SKILL.md"))
        else {
            continue;
        };
        let text = String::from_utf8_lossy(manifest);
        let front = parse_frontmatter(&text);
        let leaf = dir.rsplit('/').next().unwrap_or(&dir);
        let id = match front.name.as_deref().and_then(|name| SkillId::parse(name).ok()) {
            Some(id) => id,
            None => match SkillId::parse(leaf) {
                Ok(id) => id,
                Err(_) => continue,
            },
        };
        let bytes: u64 = owned.iter().map(|(_, content)| content.len() as u64).sum();
        skills.push(SkillMeta {
            id,
            description: front.description.unwrap_or_default(),
            subpath: dir,
            hash: hash_files(&owned),
            files: owned.len() as u32,
            bytes,
            version: front.version,
        });
    }

    if !deep {
        // A source whose root is a skill is one skill: stop.
        if let Some(root) = skills.iter().find(|skill| skill.subpath.is_empty()) {
            return vec![root.clone()];
        }
    }
    skills.sort_by(|a, b| a.id.cmp(&b.id));
    // Two directories claiming the same id would collide on disk; keep the shallowest and drop
    // the rest, which is what a package with `SKILL.md` and `examples/SKILL.md` produces.
    let mut deduped: Vec<SkillMeta> = Vec::new();
    for skill in skills {
        if deduped.iter().any(|existing: &SkillMeta| existing.id == skill.id) {
            continue;
        }
        deduped.push(skill);
    }
    deduped
}

/// Whether `dir` ("" for the root) contains `relative`.
fn owns(dir: &str, relative: &str) -> bool {
    if dir.is_empty() {
        return true;
    }
    relative == dir || relative.starts_with(&format!("{dir}/"))
}

fn in_ignored_dir(path: &str) -> bool {
    path.split('/').any(|segment| IGNORED_DIRS.contains(&segment))
}

/// The directory that owns `relative`, when it holds a `SKILL.md` at any depth up to it.
fn skill_dir_of(relative: &str) -> Option<String> {
    let parts: Vec<&str> = relative.split('/').collect();
    let index = parts
        .iter()
        .position(|segment| segment.eq_ignore_ascii_case("SKILL.md"))?;
    if index == 0 {
        return Some(String::new());
    }
    Some(parts[..index].join("/"))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn file(path: &str, text: &str) -> (String, Vec<u8>) {
        (path.to_string(), text.as_bytes().to_vec())
    }

    #[test]
    fn ids_are_directory_safe() {
        assert_eq!(SkillId::parse("web-design").unwrap().as_str(), "web-design");
        for bad in ["", "  ", "..", "a/b", "a b", "café"] {
            assert!(SkillId::parse(bad).is_err(), "{bad:?} must be refused");
        }
    }

    #[test]
    fn frontmatter_is_read_without_a_yaml_engine() {
        let md = "---\nname: web-design\ndescription: Reviews UI work\nmetadata:\n  version: 1.2.0\n---\n\n# Web design\n";
        let front = parse_frontmatter(md);
        assert_eq!(front.name.as_deref(), Some("web-design"));
        assert_eq!(front.description.as_deref(), Some("Reviews UI work"));
        assert_eq!(front.version, None, "nested metadata is not guessed at");
    }

    #[test]
    fn a_block_description_and_quotes_are_understood() {
        let md = "---\nname: \"quoted-skill\"\ndescription: |\n  First line\n  second line\n---\nbody\n";
        let front = parse_frontmatter(md);
        assert_eq!(front.name.as_deref(), Some("quoted-skill"));
        assert_eq!(front.description.as_deref(), Some("First line\nsecond line"));
    }

    #[test]
    fn no_frontmatter_is_not_a_guess() {
        let front = parse_frontmatter("# just markdown\n");
        assert_eq!(front, Frontmatter::default());
    }

    #[test]
    fn the_hash_depends_on_paths_and_bytes_not_on_order() {
        let a = vec![file("SKILL.md", "one"), file("scripts/run.sh", "two")];
        let mut b = a.clone();
        b.reverse();
        assert_eq!(hash_files(&a), hash_files(&b), "the hash sorts paths first");
        let mut changed = a.clone();
        changed[1].1 = b"three".to_vec();
        assert_ne!(hash_files(&a), hash_files(&changed), "content changes the hash");
        let mut renamed = a.clone();
        renamed[1].0 = "scripts/other.sh".to_string();
        assert_ne!(hash_files(&a), hash_files(&renamed), "a rename changes the hash");
    }

    #[test]
    fn discovery_finds_skills_at_any_depth() {
        let files = vec![
            file("README.md", "repo"),
            file("web-design/SKILL.md", "---\nname: web-design\ndescription: UI\n---\n"),
            file("web-design/references/checklist.md", "- contrast"),
            file("llm/secure/SKILL.md", "---\nname: secure-llm-apps\ndescription: audit\n---\n"),
        ];
        let skills = discover(&files, None, false);
        let ids: Vec<&str> = skills.iter().map(|s| s.id.as_str()).collect();
        assert_eq!(ids, vec!["secure-llm-apps", "web-design"]);
        let web = skills.iter().find(|s| s.id.as_str() == "web-design").unwrap();
        assert_eq!(web.subpath, "web-design");
        assert_eq!(web.files, 2, "the nested reference belongs to the skill");
        assert_eq!(web.manifest_path(), "web-design/SKILL.md");
    }

    #[test]
    fn a_root_skill_is_a_single_skill_unless_deep() {
        let files = vec![
            file("SKILL.md", "---\nname: whole-repo\ndescription: one skill\n---\n"),
            file("examples/other/SKILL.md", "---\nname: other\n---\n"),
        ];
        let shallow = discover(&files, None, false);
        assert_eq!(shallow.len(), 1);
        assert_eq!(shallow[0].id.as_str(), "whole-repo");
        assert_eq!(shallow[0].subpath, "");

        let deep = discover(&files, None, true);
        let ids: Vec<&str> = deep.iter().map(|s| s.id.as_str()).collect();
        assert_eq!(ids, vec!["other", "whole-repo"], "deep keeps both");
    }

    #[test]
    fn a_subpath_narrows_a_monorepo() {
        let files = vec![
            file("packages/ui/SKILL.md", "---\nname: ui\ndescription: ui\n---\n"),
            file("packages/api/SKILL.md", "---\nname: api\n---\n"),
        ];
        let skills = discover(&files, Some("packages/ui"), false);
        assert_eq!(skills.len(), 1);
        assert_eq!(skills[0].subpath, "", "the subpath becomes the root");
        assert_eq!(skills[0].id.as_str(), "ui");
    }

    #[test]
    fn ignored_directories_are_skipped_and_duplicates_resolved() {
        let files = vec![
            file("node_modules/pkg/SKILL.md", "---\nname: vendored\n---\n"),
            file("SKILL.md", "---\nname: real\n---\n"),
            file("dupe/SKILL.md", "---\nname: real\n---\n"),
        ];
        let skills = discover(&files, None, true);
        let ids: Vec<&str> = skills.iter().map(|s| s.id.as_str()).collect();
        assert_eq!(ids, vec!["real"], "no vendored skills, and one id wins");
        assert_eq!(skills[0].subpath, "", "the shallowest copy wins");
    }

    #[test]
    fn a_directory_name_is_the_fallback_id() {
        let files = vec![file("plain-skill/SKILL.md", "# no frontmatter\n")];
        let skills = discover(&files, None, false);
        assert_eq!(skills[0].id.as_str(), "plain-skill");
        assert_eq!(skills[0].description, "");
    }
}
