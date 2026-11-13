//! The skills use cases: add a source, install, enable/disable, remove, update, doctor, import.
//!
//! The domain decides what the link farm should look like (spec §5–§7); this module fetches
//! content, writes the store, and applies the plan. Everything it does is reported as data so the
//! CLI and the GUI can render the same truth.

use std::path::{Path, PathBuf};

use crate::domain::ports::DynResult;
use crate::domain::skill::{discover, SkillId, SkillMeta};
use crate::domain::skill_install::{
    plan_install, plan_remove, plan_set_state, Conflict, DesiredSkill, FsProbe, Plan, Selector,
};
use crate::domain::skill_ledger::{LinkState, Origin};
use crate::domain::skill_source::{parse_source, source_id, AddedSource, GitAuth, SourceSpec};
use crate::domain::skill_targets::{resolve_targets, Scope, Target};
use crate::infrastructure::skill_catalog::SearchHit;
use crate::infrastructure::skill_fs::{self, Applied, RealFs, SkillPaths};
use crate::infrastructure::skill_git::{FetchAuth, GitCli};
use crate::infrastructure::skill_secrets;

use crate::infrastructure::skill_fs::read_ledger;

/// Everything a use case needs, assembled once by the CLI or the daemon.
#[derive(Debug, Clone)]
pub struct SkillContext {
    pub paths: SkillPaths,
    pub git: GitCli,
    pub home: PathBuf,
    pub now: u64,
    /// Overrides the detected targets (`--target`), when given.
    pub targets: Option<String>,
    /// Target ids that receive copies instead of links (`--copy-target`), D5.
    pub copy_targets: Vec<String>,
    pub ssh_key: Option<PathBuf>,
}

impl SkillContext {
    pub fn new(paths: SkillPaths, now: u64) -> Self {
        let git = GitCli::new(paths.git_cache.clone());
        let home = std::env::var_os("HOME").map(PathBuf::from).unwrap_or_else(|| PathBuf::from("/"));
        Self {
            paths,
            git,
            home,
            now,
            targets: None,
            copy_targets: Vec::new(),
            ssh_key: None,
        }
    }

    pub fn with_targets(mut self, targets: Option<String>) -> Self {
        self.targets = targets;
        self
    }

    pub fn with_copy_targets(mut self, targets: Vec<String>) -> Self {
        self.copy_targets = targets;
        self
    }

    pub fn with_ssh_key(mut self, key: Option<PathBuf>) -> Self {
        self.ssh_key = key;
        self
    }

    fn auth(&self, spec: &SourceSpec) -> FetchAuth {
        let host = host_of(spec);
        let token = match spec {
            // D6: prove the machine first — an environment token or `gh auth token` that is
            // already there — and only then a token the user stored for this host. Without the
            // ambient step a private repository failed with "could not read Username" even
            // though `gh` was authenticated.
            SourceSpec::Git(git) if git.auth != GitAuth::SshAgent => {
                skill_secrets::ambient_token(&host).or_else(|| skill_secrets::stored_token(&host))
            }
            _ => None,
        };
        FetchAuth {
            token: token.map(|credential| credential.token),
            ssh_key: self.ssh_key.clone(),
        }
    }
}

fn host_of(spec: &SourceSpec) -> String {
    match spec {
        SourceSpec::Git(git) => {
            let url = &git.url;
            let stripped = url
                .trim_start_matches("https://")
                .trim_start_matches("http://")
                .trim_start_matches("ssh://")
                .trim_start_matches("git://")
                .trim_start_matches("git@");
            stripped
                .split(['/', ':'])
                .next()
                .unwrap_or("github.com")
                .to_string()
        }
        SourceSpec::Local(_) => "local".to_string(),
    }
}

/// One installed skill, as the CLI and UI see it.
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize)]
pub struct InstalledSkill {
    pub id: String,
    pub description: String,
    pub state: LinkState,
    pub origin: String,
    pub targets: Vec<String>,
    pub hash: String,
    pub links: Vec<String>,
}

/// One source with its skills.
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize)]
pub struct InstalledSource {
    pub id: String,
    pub label: String,
    pub spec: String,
    pub enabled: bool,
    pub skills: Vec<InstalledSkill>,
    #[serde(rename = "enabledCount")]
    pub enabled_count: usize,
}

/// A discovery result that changes nothing.
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize)]
pub struct Inspection {
    pub source: String,
    pub id: String,
    pub sha: Option<String>,
    #[serde(rename = "refName")]
    pub ref_name: Option<String>,
    pub skills: Vec<InspectedSkill>,
}

#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize)]
pub struct InspectedSkill {
    pub id: String,
    pub description: String,
    pub subpath: String,
    pub hash: String,
    pub files: u32,
    pub bytes: u64,
    pub installed: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize)]
pub struct InstallReport {
    pub source: String,
    pub sha: Option<String>,
    #[serde(rename = "refName")]
    pub ref_name: Option<String>,
    pub installed: Vec<String>,
    pub skipped: Vec<String>,
    pub created: usize,
    pub replaced: usize,
    pub conflicts: Vec<String>,
    pub plan: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize)]
pub struct UpdateReport {
    pub source: String,
    pub changed: Vec<String>,
    pub unchanged: Vec<String>,
    pub created: usize,
    pub replaced: usize,
    pub conflicts: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize)]
pub struct Finding {
    pub kind: String,
    pub path: String,
    pub detail: String,
    pub skill: String,
    pub source: String,
}

#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize)]
pub struct ImportReport {
    pub applied: bool,
    pub adopted: Vec<AdoptedSkill>,
    pub skipped: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize)]
pub struct AdoptedSkill {
    pub skill: String,
    pub link: String,
    pub by: String,
    pub hash: String,
}

/// Every source with its skills, from the ledger (the one place that knows).
pub fn list(ctx: &SkillContext) -> DynResult<Vec<InstalledSource>> {
    let ledger = read_ledger(&ctx.paths.ledger)?;
    let mut out = Vec::new();
    for source in &ledger.sources {
        let mut skills = Vec::new();
        for skill_id in ledger.skills_of(&source.id) {
            let rows: Vec<_> = ledger.for_skill(&skill_id, Some(&source.id));
            let first = rows.first();
            let state = ledger.state_of(&source.id, &skill_id).unwrap_or(LinkState::Disabled);
            let mut targets: Vec<String> = rows.iter().map(|row| row.target_id.clone()).collect();
            targets.sort();
            targets.dedup();
            let mut links: Vec<String> = rows.iter().map(|row| row.link.display().to_string()).collect();
            links.sort();
            skills.push(InstalledSkill {
                id: skill_id.as_str().to_string(),
                description: String::new(),
                state,
                origin: first.map(|row| row.origin.label()).unwrap_or_default(),
                targets,
                hash: first.map(|row| row.hash.clone()).unwrap_or_default(),
                links,
            });
        }
        let enabled_count = skills.iter().filter(|skill| skill.state == LinkState::Linked).count();
        out.push(InstalledSource {
            id: source.id.clone(),
            label: source.label.clone(),
            spec: source.spec.display(),
            enabled: source.enabled,
            skills,
            enabled_count,
        });
    }
    // A source with no rows yet (added, nothing installed) is still listed.
    for source in &ledger.sources {
        if !out.iter().any(|entry| entry.id == source.id) {
            out.push(InstalledSource {
                id: source.id.clone(),
                label: source.label.clone(),
                spec: source.spec.display(),
                enabled: source.enabled,
                skills: Vec::new(),
                enabled_count: 0,
            });
        }
    }
    out.sort_by(|a, b| a.id.cmp(&b.id));
    Ok(out)
}

/// Resolve user input to a source, accepting an added source id as well as a URL/path.
///
/// The MCP server and the GUI both name sources by the stable id the ledger recorded; a person
/// at a terminal may paste `owner/repo` instead. Both are the same source, so both resolve here.
pub fn resolve_source(ctx: &SkillContext, input: &str) -> DynResult<SourceSpec> {
    // A read must not be blocked by a ledger from a half-finished install: an added id is a
    // convenience, and a URL/path still resolves when the ledger cannot be parsed.
    let ledger = read_ledger(&ctx.paths.ledger).unwrap_or_default();
    if let Some(source) = ledger.source(input.trim()) {
        return Ok(source.spec.clone());
    }
    parse_source(input).map_err(|error| error.to_string().into())
}

/// Fetch (or scan) a source and return what it contains, without writing anything.
pub fn inspect(ctx: &SkillContext, input: &str) -> DynResult<Inspection> {
    let spec = resolve_source(ctx, input)?;
    let ledger = read_ledger(&ctx.paths.ledger).unwrap_or_default();
    let id = source_id(&spec);
    let installed_ids: Vec<String> = ledger.skills_of(&id).iter().map(|s| s.as_str().to_string()).collect();

    let (skills, sha, ref_name) = discover_source(ctx, &spec)?;
    Ok(Inspection {
        source: spec.display(),
        id,
        sha,
        ref_name,
        skills: skills
            .iter()
            .map(|skill| InspectedSkill {
                id: skill.id.as_str().to_string(),
                description: skill.description.clone(),
                subpath: skill.subpath.clone(),
                hash: skill.hash.clone(),
                files: skill.files,
                bytes: skill.bytes,
                installed: installed_ids.contains(&skill.id.as_str().to_string()),
            })
            .collect(),
    })
}

/// Read the skills of a source: git fetch, or a local folder scan (D8).
fn discover_source(
    ctx: &SkillContext,
    spec: &SourceSpec,
) -> DynResult<(Vec<SkillMeta>, Option<String>, Option<String>)> {
    let tree = source_tree(ctx, spec)?;
    let skills = discover(&tree.files, spec.subpath(), false);
    Ok((skills, tree.sha, tree.ref_name))
}

/// A source tree, plus the local directory it was read from.
struct SourceTree {
    files: Vec<(String, Vec<u8>)>,
    sha: Option<String>,
    ref_name: Option<String>,
    root: PathBuf,
}

/// The source's files, with the commit it was read at when it is a git remote.
///
/// `install` and `read_skill` both need the bytes, not just the metadata; keeping one fetch here
/// means the content a skill is loaded from is the same tree the inspection described.
fn source_tree(ctx: &SkillContext, spec: &SourceSpec) -> DynResult<SourceTree> {
    match spec {
        SourceSpec::Git(git) => {
            let auth = ctx.auth(spec);
            let fetched = ctx
                .git
                .fetch(&git.url, git.ref_name.as_deref(), &auth)
                .map_err(|error| error.to_string())?;
            Ok(SourceTree {
                files: fetched.files,
                sha: Some(fetched.sha),
                ref_name: Some(fetched.ref_name),
                root: fetched.workdir,
            })
        }
        SourceSpec::Local(local) => {
            if !local.path.is_dir() {
                return Err(format!("'{}' is not a folder", local.path.display()).into());
            }
            Ok(SourceTree {
                files: read_local_tree(&local.path)?,
                sha: None,
                ref_name: None,
                root: local.path.clone(),
            })
        }
    }
}

/// The local directory for one skill inside a source tree. Reject `..` from a pasted web URL:
/// the checkout root is a cache, but a path that escapes it is still a path traversal.
fn skill_root(root: &Path, source_subpath: Option<&str>, skill_subpath: &str) -> DynResult<PathBuf> {
    let mut path = root.to_path_buf();
    for subpath in [source_subpath.unwrap_or(""), skill_subpath] {
        for component in subpath.split('/') {
            if component.is_empty() || component == "." {
                continue;
            }
            if component == ".." {
                return Err("skill path escapes its checkout".into());
            }
            path.push(component);
        }
    }
    if !path.is_dir() {
        return Err(format!("skill checkout is missing at {}", path.display()).into());
    }
    Ok(path)
}

/// One skill's bytes, read from its source. Nothing is written to the store or the ledger.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SkillContent {
    /// The source as a person would type it.
    pub source: String,
    pub source_id: String,
    pub sha: Option<String>,
    pub ref_name: Option<String>,
    pub skill: SkillMeta,
    /// The skill's `SKILL.md`, verbatim; this is what loading returns to the agent.
    pub manifest: String,
    /// The local directory containing this skill: a shallow git checkout, or the source folder
    /// for a local source. Scripts in the skill can be run from here.
    pub local_path: PathBuf,
    /// Every file in the skill, paths relative to the skill root (`SKILL.md`, `references/…`).
    pub files: Vec<SkillFile>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SkillFile {
    pub path: String,
    pub bytes: Vec<u8>,
}

/// Load one skill into memory without installing it.
///
/// This is the MCP server's core use case: a session can ask for a skill by name, receive its
/// `SKILL.md`, and read its references on demand. The project and the agent directories are never
/// touched, so trying a skill cannot leave a link farm behind (the install path remains the one
/// that owns links).
pub fn read_skill(ctx: &SkillContext, input: &str, skill: &str) -> DynResult<SkillContent> {
    let spec = resolve_source(ctx, input)?;
    let tree = source_tree(ctx, &spec)?;
    let files = tree.files;
    let skills = discover(&files, spec.subpath(), false);
    let meta = skills
        .iter()
        .find(|meta| meta.id.as_str() == skill)
        .cloned()
        .ok_or_else(|| {
            let available: Vec<&str> = skills.iter().map(|meta| meta.id.as_str()).collect();
            if available.is_empty() {
                format!("{input} contains no skills (no SKILL.md found)")
            } else {
                format!("no skill '{skill}' in {input}; available: {}", available.join(", "))
            }
        })?;
    // The shallow discovery intentionally stops at a root skill; that hides nested examples from
    // the listing, but their files still live under the same prefix. Ask the deep pass only for
    // the exclusion list, so the loaded manifest matches the hash `discover` computed.
    let all_skills = discover(&files, spec.subpath(), true);
    let owned = files_under(
        &files,
        &meta.subpath,
        &all_skills
            .iter()
            .filter(|other| other.subpath != meta.subpath)
            .filter(|other| {
                meta.subpath.is_empty()
                    || other.subpath.starts_with(&format!("{}/", meta.subpath.trim_matches('/')))
            })
            .map(|other| other.subpath.clone())
            .collect::<Vec<_>>(),
    );
    let manifest = owned
        .iter()
        .find(|(path, _)| path.eq_ignore_ascii_case("SKILL.md"))
        .map(|(_, bytes)| {
            std::str::from_utf8(bytes)
                .map(str::to_string)
                .map_err(|_| format!("skill '{}' has a SKILL.md that is not UTF-8", meta.id))
        })
        .transpose()?
        .ok_or_else(|| format!("skill '{}' has no SKILL.md", meta.id))?;
    let local_path = skill_root(&tree.root, spec.subpath(), &meta.subpath)?;
    Ok(SkillContent {
        source: spec.display(),
        source_id: source_id(&spec),
        sha: tree.sha,
        ref_name: tree.ref_name,
        skill: meta,
        manifest,
        local_path,
        files: owned
            .into_iter()
            .map(|(path, bytes)| SkillFile { path, bytes })
            .collect(),
    })
}

/// The files owned by one skill directory, with paths relative to that directory.
///
/// `nested` lists skill directories inside this one. Their files belong to those skills, not to
/// the parent: loading a skill must not silently include an example's instructions as if they
/// were part of its own manifest (the content hash already excludes them).
fn files_under(
    files: &[(String, Vec<u8>)],
    subpath: &str,
    nested: &[String],
) -> Vec<(String, Vec<u8>)> {
    let prefix = subpath.trim_matches('/');
    let nested: Vec<String> = nested
        .iter()
        .filter_map(|other| {
            let other = other.trim_matches('/');
            if prefix.is_empty() {
                Some(other.to_string())
            } else {
                other
                    .strip_prefix(prefix)
                    .and_then(|rest| rest.strip_prefix('/'))
                    .map(str::to_string)
            }
        })
        .filter(|path| !path.is_empty())
        .collect();
    files
        .iter()
        .filter_map(|(path, bytes)| {
            let relative = if prefix.is_empty() {
                if path.is_empty() {
                    return None;
                }
                path.clone()
            } else {
                path.strip_prefix(prefix)
                    .and_then(|rest| rest.strip_prefix('/'))
                    .filter(|rest| !rest.is_empty())?
                    .to_string()
            };
            if nested
                .iter()
                .any(|owner| relative == *owner || relative.starts_with(&format!("{owner}/")))
            {
                return None;
            }
            Some((relative, bytes.clone()))
        })
        .collect()
}

/// Search catalogs and added sources for skills. `source` is `github`, `skills.sh`, `all`,
/// `added`, or the id of one added source.
///
/// The CLI and the MCP server share this: discovery is one implementation, rendered twice.
pub fn search(
    ctx: &SkillContext,
    query: &str,
    source: &str,
    limit: usize,
    token: Option<&str>,
) -> DynResult<Vec<SearchHit>> {
    use crate::infrastructure::skill_catalog as catalog;

    let limit = if limit == 0 { 20 } else { limit.min(50) };
    let query = query.trim();
    let source = source.trim().to_ascii_lowercase();
    if query.is_empty()
        && matches!(source.as_str(), "github" | "skills.sh" | "skillssh" | "all" | "")
    {
        return Err(
            "a search query is required for a catalog; use source 'added' to list added sources"
                .into(),
        );
    }
    let mut hits = match source.as_str() {
        "github" => catalog::github_search(query, token)?,
        "skills.sh" | "skillssh" => catalog::skills_sh_search(query)?,
        "all" | "" => {
            let mut merged = Vec::new();
            let mut errors = Vec::new();
            let mut answered = false;
            match catalog::github_search(query, token) {
                Ok(found) => {
                    answered = true;
                    merged.extend(found);
                }
                Err(error) => errors.push(error.to_string()),
            }
            match catalog::skills_sh_search(query) {
                Ok(found) => {
                    answered = true;
                    merged.extend(found);
                }
                Err(error) => errors.push(error.to_string()),
            }
            if !answered && !errors.is_empty() {
                return Err(format!("no catalog answered: {}", errors.join("; ")).into());
            }
            merged
        }
        "added" => search_added(ctx, None, query)?,
        id => {
            let ledger = read_ledger(&ctx.paths.ledger).unwrap_or_default();
            if ledger.source(id).is_none() {
                return Err(format!(
                    "unknown search source '{id}'; use github, skills.sh, all, added, or an added source id"
                )
                .into());
            }
            search_added(ctx, Some(id), query)?
        }
    };
    let mut deduped: Vec<SearchHit> = Vec::new();
    for hit in hits.drain(..) {
        if !deduped
            .iter()
            .any(|existing| existing.source == hit.source && existing.name == hit.name && existing.kind == hit.kind)
        {
            deduped.push(hit);
        }
    }
    deduped.truncate(limit);
    Ok(deduped)
}

/// Scan added sources for skills whose id or description matches the query.
fn search_added(ctx: &SkillContext, only: Option<&str>, query: &str) -> DynResult<Vec<SearchHit>> {
    use crate::infrastructure::skill_catalog::{HitKind, HitTrust, SearchHit};

    let ledger = read_ledger(&ctx.paths.ledger).unwrap_or_default();
    let sources: Vec<AddedSource> = match only {
        Some(id) => ledger.source(id).cloned().into_iter().collect(),
        None => ledger.sources.clone(),
    };
    let needle = query.to_lowercase();
    let mut hits = Vec::new();
    let mut first_error: Option<String> = None;
    for source in &sources {
        let skills = match discover_source(ctx, &source.spec) {
            Ok((skills, _, _)) => skills,
            Err(error) if only.is_some() => return Err(error),
            Err(error) => {
                if first_error.is_none() {
                    first_error = Some(error.to_string());
                }
                continue;
            }
        };
        for skill in skills {
            if !needle.is_empty()
                && !skill.id.as_str().to_lowercase().contains(&needle)
                && !skill.description.to_lowercase().contains(&needle)
            {
                continue;
            }
            hits.push(SearchHit {
                source: source.id.clone(),
                name: skill.id.as_str().to_string(),
                description: skill.description,
                installs: 0,
                url: String::new(),
                kind: HitKind::Skill,
                trust: HitTrust::Community,
            });
        }
    }
    if hits.is_empty() {
        if let Some(error) = first_error {
            return Err(error.into());
        }
    }
    Ok(hits)
}

fn read_local_tree(root: &Path) -> DynResult<Vec<(String, Vec<u8>)>> {
    let mut files = Vec::new();
    let mut stack = vec![root.to_path_buf()];
    while let Some(dir) = stack.pop() {
        for entry in std::fs::read_dir(&dir)?.flatten() {
            let path = entry.path();
            let name = entry.file_name().to_string_lossy().into_owned();
            if name == ".git" || name == "node_modules" || name == ".venv" || name == "target" {
                continue;
            }
            let metadata = entry.metadata()?;
            if metadata.is_dir() {
                stack.push(path);
            } else if metadata.is_file() {
                let relative = path
                    .strip_prefix(root)
                    .unwrap_or(&path)
                    .to_string_lossy()
                    .replace('\\', "/");
                files.push((relative, std::fs::read(&path)?));
            }
        }
    }
    files.sort_by(|a, b| a.0.cmp(&b.0));
    Ok(files)
}

/// Add a source (no skills installed yet).
pub fn add_source(
    ctx: &SkillContext,
    input: &str,
    ref_override: Option<&str>,
    subpath: Option<&str>,
    watch: bool,
    copy: bool,
) -> DynResult<AddedSource> {
    let mut spec = parse_source(input).map_err(|error| error.to_string())?;
    let mut check: Option<(String, Option<String>)> = None;
    match &mut spec {
        SourceSpec::Git(git) => {
            if let Some(reference) = ref_override {
                git.ref_name = Some(reference.to_string());
            }
            git.subpath = subpath.map(str::to_string).or(git.subpath.take());
            check = Some((git.url.clone(), git.ref_name.clone()));
        }
        SourceSpec::Local(local) => {
            local.watch = watch;
            local.copy = copy;
            local.subpath = subpath.map(str::to_string).or(local.subpath.take());
            if !local.path.is_dir() {
                return Err(format!("'{}' is not a folder", local.path.display()).into());
            }
        }
    }

    // Prove access before recording the source (spec §8.2).
    if let Some((url, reference)) = check {
        let auth = ctx.auth(&spec);
        ctx.git
            .check_access(&url, reference.as_deref(), &auth)
            .map_err(|error| error.to_string())?;
    }

    let id = source_id(&spec);
    let label = match &spec {
        SourceSpec::Git(git) => git
            .url
            .trim_end_matches(".git")
            .rsplit('/')
            .take(2)
            .collect::<Vec<_>>()
            .into_iter()
            .rev()
            .collect::<Vec<_>>()
            .join("/"),
        SourceSpec::Local(local) => local.path.display().to_string(),
    };
    let source = AddedSource {
        id,
        label,
        spec,
        enabled: true,
        added_at: ctx.now,
        last_seen: Some(ctx.now),
        previous_sha: None,
        previous_ref: None,
    };
    let mut ledger = read_ledger(&ctx.paths.ledger)?;
    ledger.upsert_source(source.clone());
    skill_fs::write_ledger(&ctx.paths.ledger, &ledger)?;
    Ok(source)
}

/// Install every skill of a source, or the named subset.
pub fn install(
    ctx: &SkillContext,
    input: &str,
    only: Option<Vec<String>>,
    scope: &Scope,
    accept: bool,
) -> DynResult<InstallReport> {
    // A source that is already known carries settings the typed string does not (`--copy`,
    // `--watch`, a pinned ref chosen when it was added). It is also addressed by its id, so
    // `source add <folder>` followed by the printed `install <id>` is a valid flow.
    let mut ledger = read_ledger(&ctx.paths.ledger)?;
    let parsed = match ledger.source(input.trim()) {
        Some(source) => source.spec.clone(),
        None => parse_source(input).map_err(|error| error.to_string())?,
    };
    let id = source_id(&parsed);
    let spec = ledger.source(&id).map(|source| source.spec.clone()).unwrap_or(parsed);
    let known_source = ledger.source(&id).is_some();
    if !known_source && !accept {
        return Err(format!(
            "installing from '{}' needs --accept: review it with `astral-plasma skills inspect {}`",
            spec.display(),
            spec.display()
        )
        .into());
    }

    let (mut skills, sha, ref_name) = discover_source(ctx, &spec)?;
    if let Some(preferred) = match &spec {
        SourceSpec::Git(git) => git.preferred_skill.clone(),
        _ => None,
    } {
        // A skills.sh page names one skill of its repository.
        let wanted = preferred.as_str().to_string();
        skills.retain(|skill| skill.id.as_str() == wanted);
        if skills.is_empty() {
            return Err(format!("the repository has no skill named '{wanted}'").into());
        }
    }
    if let Some(only) = &only {
        let wanted: Vec<&str> = only.iter().map(String::as_str).collect();
        let known: Vec<&str> = skills.iter().map(|skill| skill.id.as_str()).collect();
        let missing: Vec<&&str> = wanted.iter().filter(|id| !known.contains(*id)).collect();
        if !missing.is_empty() {
            return Err(format!(
                "no such skill: {}; this source has {}",
                missing.iter().map(|id| **id).collect::<Vec<_>>().join(", "),
                known.join(", ")
            )
            .into());
        }
        skills.retain(|skill| wanted.contains(&skill.id.as_str()));
    }
    if skills.is_empty() {
        return Err("this source contains no skills (no SKILL.md found)".into());
    }

    // Materialise content and build the desired state.
    let mut targets = resolve_targets(ctx.targets.as_deref(), &ctx.home).map_err(|error| error.to_string())?;
    // D5: copying is the per-target exception for an agent that does not follow links.
    if !ctx.copy_targets.is_empty() {
        for target in targets.iter_mut() {
            if ctx.copy_targets.iter().any(|id| id == target.id) {
                target.style = crate::domain::skill_targets::LinkStyle::Copy;
            }
        }
    }
    if targets.is_empty() {
        return Err(
            "no agent targets were detected; pass --target (claude-code, codex, …) to install anyway"
                .into(),
        );
    }
    let ref_label = ref_name.clone().unwrap_or_else(|| "local".to_string());
    let mut desired = Vec::new();
    let mut conflicts: Vec<String> = Vec::new();
    for skill in &skills {
        let origin = materialise(ctx, &spec, skill, sha.as_deref(), &ref_label)?;
        desired.push(DesiredSkill {
            source_id: id.clone(),
            skill: skill.clone(),
            origin,
            scope: scope.clone(),
        });
    }

    let mut plan = plan_install(&desired, &targets, &ledger, &RealFs, ctx.now);
    // Refuse to write if anything is occupied by something that is not ours: the user must
    // decide (spec §6.3), and a half-install is worse than a clear refusal.
    for conflict in &plan.conflicts {
        conflicts.push(format!("{}: {}", conflict.link.display(), conflict.detail));
    }
    if plan.is_blocked() {
        return Ok(InstallReport {
            source: spec.display(),
            sha,
            ref_name,
            installed: Vec::new(),
            skipped: skills.iter().map(|skill| skill.id.as_str().to_string()).collect(),
            created: 0,
            replaced: 0,
            conflicts,
            plan: plan.describe(),
        });
    }
    let described = plan.describe();
    let applied: Applied = skill_fs::apply(&ctx.paths, &plan, ctx.now)?;
    if !desired.is_empty() {
        ledger = read_ledger(&ctx.paths.ledger)?;
        let mut source = ledger.source(&id).cloned().unwrap_or(AddedSource {
            id: id.clone(),
            label: id.clone(),
            spec: spec.clone(),
            enabled: true,
            added_at: ctx.now,
            last_seen: None,
            previous_sha: None,
            previous_ref: None,
        });
        source.last_seen = Some(ctx.now);
        source.enabled = true;
        ledger.upsert_source(source);
        skill_fs::write_ledger(&ctx.paths.ledger, &ledger)?;
    }

    Ok(InstallReport {
        source: spec.display(),
        sha,
        ref_name,
        installed: skills.iter().map(|skill| skill.id.as_str().to_string()).collect(),
        skipped: Vec::new(),
        created: applied.created,
        replaced: applied.replaced,
        conflicts,
        plan: described,
    })
}

/// Write a skill's bytes into the immutable store, or return the local path (D8).
fn materialise(
    ctx: &SkillContext,
    spec: &SourceSpec,
    skill: &SkillMeta,
    sha: Option<&str>,
    ref_label: &str,
) -> DynResult<Origin> {
    match spec {
        SourceSpec::Local(local) if !local.copy => Ok(Origin::Local {
            path: local.path.join(&skill.subpath),
        }),
        SourceSpec::Local(local) => {
            let path = store_dir(ctx, &format!("local/{}", crate::domain::skill_source::slug(&local.path.display().to_string())), ref_label, "local", &skill.id);
            let source = local.path.join(&skill.subpath);
            if path.exists() {
                std::fs::remove_dir_all(&path)?;
            }
            skill_fs::copy_tree(&source, &path)?;
            Ok(Origin::Local { path })
        }
        SourceSpec::Git(git) => {
            let origin = ctx.git.fetch(&git.url, git.ref_name.as_deref(), &ctx.auth(spec));
            // `install` fetched already; reuse that tree rather than cloning twice.
            let (files, workdir) = match origin {
                Ok(fetched) => (fetched.files, Some(fetched.workdir)),
                Err(_) => (read_local_tree(&ctx.paths.git_cache).unwrap_or_default(), None),
            };
            let sha_label = sha.unwrap_or("unknown");
            let short = &sha_label[..sha_label.len().min(12)];
            let path = store_dir(ctx, &git.url, ref_label, short, &skill.id);
            if path.exists() {
                std::fs::remove_dir_all(&path)?;
            }
            // Copy the checked-out skill directory when we have it, so scripts keep their
            // executable bit and symlinks. The in-memory fallback is only for a cache that
            // vanished between discovery and materialisation.
            if let Some(workdir) = workdir {
                if let Ok(source) = skill_root(&workdir, git.subpath.as_deref(), &skill.subpath) {
                    skill_fs::copy_tree(&source, &path)?;
                    return Ok(Origin::Store {
                        ref_name: ref_label.to_string(),
                        sha: sha_label.to_string(),
                        path,
                    });
                }
            }
            write_skill_files(&path, &files, &skill.subpath)?;
            Ok(Origin::Store {
                ref_name: ref_label.to_string(),
                sha: sha_label.to_string(),
                path,
            })
        }
    }
}

fn store_dir(ctx: &SkillContext, url: &str, ref_label: &str, short_sha: &str, skill: &SkillId) -> PathBuf {
    let host = host_of(&SourceSpec::Git(crate::domain::skill_source::GitSource {
        url: url.to_string(),
        ref_name: None,
        subpath: None,
        auth: GitAuth::Configured,
        preferred_skill: None,
    }));
    let stripped = url
        .trim_end_matches(".git")
        .trim_start_matches("https://")
        .trim_start_matches("http://")
        .trim_start_matches("ssh://")
        .trim_start_matches("git://")
        .trim_start_matches("git@");
    let path_part = stripped
        .split_once(['/', ':'])
        .map(|(_, rest)| rest.to_string())
        .unwrap_or_else(|| stripped.to_string());
    let mut directory = ctx.paths.store.join(crate::domain::skill_source::slug(&host));
    for segment in path_part.split('/') {
        if !segment.is_empty() {
            directory = directory.join(crate::domain::skill_source::slug(segment));
        }
    }
    directory
        .join(format!("{}@{}", crate::domain::skill_source::slug(ref_label), short_sha))
        .join(skill.as_str())
}

fn write_skill_files(directory: &Path, files: &[(String, Vec<u8>)], subpath: &str) -> DynResult<()> {
    let prefix = subpath.trim_matches('/');
    for (path, bytes) in files {
        let relative = if prefix.is_empty() {
            path.as_str()
        } else {
            match path.strip_prefix(&format!("{prefix}/")) {
                Some(rest) => rest,
                None => continue,
            }
        };
        if relative.is_empty() {
            continue;
        }
        let target = directory.join(relative);
        if let Some(parent) = target.parent() {
            std::fs::create_dir_all(parent)?;
        }
        std::fs::write(&target, bytes)?;
    }
    Ok(())
}

/// Enable or disable a skill, or every skill of a source.
pub fn set_enabled(ctx: &SkillContext, selector: &Selector, enable: bool) -> DynResult<Applied> {
    let mut ledger = read_ledger(&ctx.paths.ledger)?;
    let plan = plan_set_state(&ledger, selector, enable, &RealFs, ctx.now);
    let report = skill_fs::apply(&ctx.paths, &plan, ctx.now)?;
    ledger = read_ledger(&ctx.paths.ledger)?;
    if let Selector::Source { source_id } = selector {
        if let Some(mut source) = ledger.source(source_id).cloned() {
            source.enabled = enable;
            ledger.upsert_source(source);
            skill_fs::write_ledger(&ctx.paths.ledger, &ledger)?;
        }
    }
    Ok(report)
}

/// Remove a skill or a whole source: unlink what we own, drop the rows, collect the store.
pub fn remove(ctx: &SkillContext, selector: &Selector, purge: bool) -> DynResult<Applied> {
    let ledger = read_ledger(&ctx.paths.ledger)?;
    let plan = plan_remove(&ledger, selector, &RealFs);
    let report = skill_fs::apply(&ctx.paths, &plan, ctx.now)?;
    let mut after = read_ledger(&ctx.paths.ledger)?;
    if let Selector::Source { source_id } = selector {
        if after.for_source(source_id).is_empty() {
            after.remove_source(source_id);
            skill_fs::write_ledger(&ctx.paths.ledger, &after)?;
        }
    }
    if purge {
        skill_fs::gc_store(&ctx.paths, &after)?;
    }
    Ok(report)
}

/// Re-fetch a source and relink only the skills whose content changed.
pub fn update(ctx: &SkillContext, source_id: &str) -> DynResult<UpdateReport> {
    let ledger = read_ledger(&ctx.paths.ledger)?;
    let source = ledger
        .source(source_id)
        .ok_or_else(|| format!("no source '{source_id}'"))?;
    let spec = source.spec.clone();
    let (skills, sha, ref_name) = discover_source(ctx, &spec)?;
    let ref_label = ref_name.clone().unwrap_or_else(|| "local".to_string());

    let mut changed = Vec::new();
    let mut unchanged = Vec::new();
    let mut conflicts = Vec::new();
    let mut created = 0usize;
    let mut replaced = 0usize;

    for skill in &skills {
        let rows = ledger.for_skill(&skill.id, Some(source_id));
        if rows.is_empty() {
            continue; // not installed
        }
        let current_hash = rows.first().map(|row| row.hash.clone()).unwrap_or_default();
        if current_hash == skill.hash && rows.iter().all(|row| row.state == LinkState::Linked) {
            unchanged.push(skill.id.as_str().to_string());
            continue;
        }
        let origin = materialise(ctx, &spec, skill, sha.as_deref(), &ref_label)?;
        let targets: Vec<Target> = rows
            .iter()
            .filter_map(|row| crate::domain::skill_targets::target_by_id(&row.target_id))
            .fold(Vec::new(), |mut acc: Vec<Target>, target| {
                if !acc.iter().any(|existing| existing.id == target.id) {
                    acc.push(target.clone());
                }
                acc
            });
        let desired = vec![DesiredSkill {
            source_id: source_id.to_string(),
            skill: skill.clone(),
            origin,
            scope: rows.first().map(|row| row.scope.clone()).unwrap_or(Scope::Global),
        }];
        let plan = plan_install(&desired, &targets, &ledger, &RealFs, ctx.now);
        for conflict in &plan.conflicts {
            conflicts.push(format!("{}: {}", conflict.link.display(), conflict.detail));
        }
        if plan.is_blocked() {
            continue;
        }
        let applied = skill_fs::apply(&ctx.paths, &plan, ctx.now)?;
        created += applied.created;
        replaced += applied.replaced;
        changed.push(skill.id.as_str().to_string());
    }

    // Refresh the source's stamps: the commit it was at becomes the rollback target (D11).
    let mut after = read_ledger(&ctx.paths.ledger)?;
    if let Some(mut entry) = after.source(source_id).cloned() {
        entry.last_seen = Some(ctx.now);
        if !changed.is_empty() {
            if let Some((previous_sha, previous_ref)) = previous_origin(&ledger, source_id) {
                entry.previous_sha = Some(previous_sha);
                entry.previous_ref = Some(previous_ref);
            }
        }
        after.upsert_source(entry);
        skill_fs::write_ledger(&ctx.paths.ledger, &after)?;
    }

    Ok(UpdateReport {
        source: source_id.to_string(),
        changed,
        unchanged,
        created,
        replaced,
        conflicts,
    })
}

/// The commit a source's rows currently point at.
fn previous_origin(ledger: &crate::domain::skill_ledger::Ledger, source_id: &str) -> Option<(String, String)> {
    for row in ledger.for_source(source_id) {
        if let Origin::Store { ref_name, sha, .. } = &row.origin {
            return Some((sha.clone(), ref_name.clone()));
        }
    }
    None
}

/// `<…>/<ref>@<sha12>/<skill>` -> the same skill at another commit (D11).
///
/// The store names a version `<ref-slug>@<sha12>`; splitting on `-` would have cut a ref like
/// `feature-x` in half, which is why the separator matters and is asserted in the tests.
fn store_path_with_sha(path: &Path, sha: &str) -> Option<PathBuf> {
    let parent = path.parent()?;
    let skill = path.file_name()?;
    let name = parent.file_name()?.to_str()?;
    let (ref_part, _) = name.rsplit_once('@')?;
    let short = &sha[..sha.len().min(12)];
    // The version directory *and* the skill inside it: the origin path points at the skill
    // (`…/<ref>@<sha>/<skill>`), and dropping that last component links a farm at the version.
    Some(parent.with_file_name(format!("{ref_part}@{short}")).join(skill))
}

/// Put a source back to the commit it had before its last update (one-deep rollback, D11).
///
/// The store keeps the previous ref until the next successful update, so this is a relink, not a
/// fetch: it works offline and cannot change what the previous version contained.
pub fn rollback(ctx: &SkillContext, source_id: &str) -> DynResult<UpdateReport> {
    let ledger = read_ledger(&ctx.paths.ledger)?;
    let source = ledger
        .source(source_id)
        .ok_or_else(|| format!("no source '{source_id}'"))?;
    let Some(previous_sha) = source.previous_sha.clone() else {
        return Err(format!("'{source_id}' has no previous version recorded (nothing to roll back to)").into());
    };
    let previous_ref = source.previous_ref.clone().unwrap_or_else(|| "main".to_string());
    // What the rows point at *now* becomes the next rollback target, so rolling back twice
    // returns to where it started instead of bouncing between the same pair forever.
    let current_origin = previous_origin(&ledger, source_id);

    let mut changed = Vec::new();
    let mut unchanged = Vec::new();
    let mut conflicts = Vec::new();
    let mut created = 0usize;
    let mut replaced = 0usize;

    for row in ledger.for_source(source_id) {
        let Origin::Store { path, .. } = &row.origin else {
            unchanged.push(row.skill.as_str().to_string());
            continue;
        };
        let Some(old_path) = store_path_with_sha(path, &previous_sha) else {
            conflicts.push(format!("cannot locate the previous content for '{}'", row.skill));
            continue;
        };
        if !old_path.is_dir() {
            conflicts.push(format!(
                "the previous version of '{}' is no longer in the store ({})",
                row.skill,
                old_path.display()
            ));
            continue;
        }
        let files = read_local_tree(&old_path)?;
        let meta = crate::domain::skill::SkillMeta {
            id: row.skill.clone(),
            description: String::new(),
            subpath: String::new(),
            hash: crate::domain::skill::hash_files(&files),
            files: files.len() as u32,
            bytes: files.iter().map(|(_, bytes)| bytes.len() as u64).sum(),
            version: None,
        };
        let desired = DesiredSkill {
            source_id: source_id.to_string(),
            skill: meta,
            origin: Origin::Store {
                ref_name: previous_ref.clone(),
                sha: previous_sha.clone(),
                path: old_path,
            },
            scope: row.scope.clone(),
        };
        let Some(target) = crate::domain::skill_targets::target_by_id(&row.target_id) else {
            continue;
        };
        let plan = plan_install(&[desired], &[target.clone()], &ledger, &RealFs, ctx.now);
        if plan.is_blocked() {
            conflicts.extend(conflict_lines(&plan.conflicts));
            continue;
        }
        let applied = skill_fs::apply(&ctx.paths, &plan, ctx.now)?;
        created += applied.created;
        replaced += applied.replaced;
        changed.push(row.skill.as_str().to_string());
    }

    // Swap the stamps so the rollback is reversible (in both directions).
    let mut after = read_ledger(&ctx.paths.ledger)?;
    if let Some(mut entry) = after.source(source_id).cloned() {
        if let Some((current_sha, current_ref)) = current_origin {
            entry.previous_sha = Some(current_sha);
            entry.previous_ref = Some(current_ref);
        }
        after.upsert_source(entry);
        skill_fs::write_ledger(&ctx.paths.ledger, &after)?;
    }

    changed.sort();
    changed.dedup();
    Ok(UpdateReport {
        source: source_id.to_string(),
        changed,
        unchanged,
        created,
        replaced,
        conflicts,
    })
}

/// Compare the ledger with the filesystem (spec §11, the Doctor section).
pub fn doctor(ctx: &SkillContext) -> DynResult<Vec<Finding>> {
    let ledger = read_ledger(&ctx.paths.ledger)?;
    let mut findings = Vec::new();
    for row in &ledger.links {
        // A disabled row has no link on purpose: that is the recorded state, not drift.
        if row.state == LinkState::Disabled && RealFs.probe(&row.link) == crate::domain::skill_install::Probe::Missing {
            continue;
        }
        match RealFs.probe(&row.link) {
            crate::domain::skill_install::Probe::Missing => findings.push(Finding {
                kind: "missing".to_string(),
                path: row.link.display().to_string(),
                detail: "the ledger has a record but nothing is at this path".to_string(),
                skill: row.skill.as_str().to_string(),
                source: row.source_id.clone(),
            }),
            crate::domain::skill_install::Probe::Symlink { target, dangling } => {
                if target != row.target {
                    findings.push(Finding {
                        kind: "drifted".to_string(),
                        path: row.link.display().to_string(),
                        detail: format!("points at {target}, the ledger recorded {}", row.target),
                        skill: row.skill.as_str().to_string(),
                        source: row.source_id.clone(),
                    });
                } else if dangling {
                    findings.push(Finding {
                        kind: "dangling".to_string(),
                        path: row.link.display().to_string(),
                        detail: "the content this link points at is gone".to_string(),
                        skill: row.skill.as_str().to_string(),
                        source: row.source_id.clone(),
                    });
                }
            }
            crate::domain::skill_install::Probe::Directory | crate::domain::skill_install::Probe::File => {
                // An adopted farm *is* a real directory; only a change since adoption is a finding.
                if matches!(row.origin, Origin::Adopted { .. }) {
                    let files = read_local_tree(&row.link).unwrap_or_default();
                    let current = crate::domain::skill::hash_files(&files);
                    if current != row.hash {
                        findings.push(Finding {
                            kind: "modified".to_string(),
                            path: row.link.display().to_string(),
                            detail: "content changed since it was adopted; review it again".to_string(),
                            skill: row.skill.as_str().to_string(),
                            source: row.source_id.clone(),
                        });
                    }
                } else {
                    findings.push(Finding {
                        kind: "replaced".to_string(),
                        path: row.link.display().to_string(),
                        detail: "the managed link was replaced by a real file or directory".to_string(),
                        skill: row.skill.as_str().to_string(),
                        source: row.source_id.clone(),
                    });
                }
            }
        }
    }
    // Unmanaged skills: something an agent will load that this manager did not create. Scan the
    // global farm and every project farm the ledger mentions.
    // Detected agents *and* every target the ledger manages: a farm is worth checking even if the
    // agent was uninstalled after we wrote to it.
    let mut targets = resolve_targets(None, &ctx.home).map_err(|error| error.to_string())?;
    for row in &ledger.links {
        if let Some(target) = crate::domain::skill_targets::target_by_id(&row.target_id) {
            if !targets.iter().any(|known| known.id == target.id) {
                targets.push(target.clone());
            }
        }
    }
    let mut scopes = vec![Scope::Global];
    for row in &ledger.links {
        if !scopes.iter().any(|scope| scope.key() == row.scope.key()) {
            scopes.push(row.scope.clone());
        }
    }
    let mut seen: Vec<PathBuf> = Vec::new();
    for target in targets {
      for scope in &scopes {
        let dir = target.dir_for_with(scope, &ctx.home);
        if !dir.is_dir() || seen.contains(&dir) {
            continue;
        }
        seen.push(dir.clone());
        for entry in read_skill_entries(&dir) {
            if ledger.row_for(&entry).is_none() {
                findings.push(Finding {
                    kind: "unmanaged".to_string(),
                    path: entry.display().to_string(),
                    detail: format!("a skill in the {} directory that Astral did not install", target.label),
                    skill: entry
                        .file_name()
                        .map(|name| name.to_string_lossy().into_owned())
                        .unwrap_or_default(),
                    source: String::new(),
                });
            }
        }
      }
    }
    findings.sort_by(|a, b| a.path.cmp(&b.path));
    Ok(findings)
}

/// Real skill directories or links in one target directory (a name with a `SKILL.md`, or a link).
fn read_skill_entries(dir: &Path) -> Vec<PathBuf> {
    let Ok(entries) = std::fs::read_dir(dir) else {
        return Vec::new();
    };
    entries
        .flatten()
        .map(|entry| entry.path())
        .filter(|path| {
            path.is_symlink()
                || path.join("SKILL.md").is_file()
                || path.join("skill.md").is_file()
        })
        .collect()
}

/// Adopt a farm built by `npx skills` instead of duplicating it (D4).
///
/// Reads what is on disk and records it as `Origin::Adopted`; nothing is rewritten, and the rows
/// let `remove`/`disable` work on links Astral did not create.
pub fn import_npx(ctx: &SkillContext, apply: bool) -> DynResult<ImportReport> {
    let mut ledger = read_ledger(&ctx.paths.ledger)?;
    let mut adopted = Vec::new();
    let mut skipped = Vec::new();
    let targets = resolve_targets(None, &ctx.home).map_err(|error| error.to_string())?;
    for target in targets {
        let dir = target.dir_for_with(&Scope::Global, &ctx.home);
        for entry in read_skill_entries(&dir) {
            if ledger.row_for(&entry).is_some() {
                continue;
            }
            let name = entry
                .file_name()
                .map(|name| name.to_string_lossy().into_owned())
                .unwrap_or_default();
            let skill = match SkillId::parse(&name) {
                Ok(skill) => skill,
                Err(_) => {
                    skipped.push(format!("{}: not a skill name", entry.display()));
                    continue;
                }
            };
            // Hash what the link resolves to, so a later change is visible.
            let resolved = std::fs::canonicalize(&entry).unwrap_or_else(|_| entry.clone());
            let files = read_local_tree(&resolved).unwrap_or_default();
            let hash = crate::domain::skill::hash_files(&files);
            let link_target = std::fs::read_link(&entry)
                .map(|target| target.to_string_lossy().into_owned())
                .unwrap_or_else(|_| resolved.display().to_string());
            let source_id = format!("adopted-{}", crate::domain::skill_source::slug(&resolved.display().to_string()));
            adopted.push(AdoptedSkill {
                skill: skill.as_str().to_string(),
                link: entry.display().to_string(),
                by: "npx skills".to_string(),
                hash: hash.clone(),
            });
            if apply {
                ledger.upsert_source(AddedSource {
                    id: source_id.clone(),
                    label: format!("adopted · {}", resolved.display()),
                    spec: SourceSpec::Local(crate::domain::skill_source::LocalSource {
                        path: resolved.clone(),
                        watch: false,
                        copy: false,
                        subpath: None,
                    }),
                    enabled: true,
                    added_at: ctx.now,
                    last_seen: Some(ctx.now),
        previous_sha: None,
        previous_ref: None,
                });
                ledger.upsert(crate::domain::skill_ledger::LinkRecord {
                    link: entry.clone(),
                    target: link_target,
                    target_id: target.id.to_string(),
                    source_id,
                    skill,
                    origin: Origin::Adopted {
                        by: "npx skills".to_string(),
                        hash: hash.clone(),
                    },
                    scope: Scope::Global,
                    state: LinkState::Linked,
                    hash: hash.clone(),
                    created_at: ctx.now,
                });
            }
        }
    }
    if apply && !adopted.is_empty() {
        skill_fs::write_ledger(&ctx.paths.ledger, &ledger)?;
    }
    Ok(ImportReport {
        applied: apply,
        adopted,
        skipped,
    })
}

/// Recover transactions left by a crash, and report how many were finished.
pub fn recover(ctx: &SkillContext) -> DynResult<usize> {
    skill_fs::recover(&ctx.paths)
}

/// The plan for a would-be install, for `--dry-run` and the consent card.
pub fn preview(ctx: &SkillContext, input: &str, scope: &Scope) -> DynResult<Vec<String>> {
    let parsed = parse_source(input).map_err(|error| error.to_string())?;
    let id = source_id(&parsed);
    let ledger = read_ledger(&ctx.paths.ledger)?;
    let spec = ledger.source(&id).map(|source| source.spec.clone()).unwrap_or(parsed);
    let (skills, sha, ref_name) = discover_source(ctx, &spec)?;
    let targets = resolve_targets(ctx.targets.as_deref(), &ctx.home).map_err(|error| error.to_string())?;
    let ref_label = ref_name.unwrap_or_else(|| "local".to_string());
    let mut desired = Vec::new();
    for skill in &skills {
        let origin = match &spec {
            SourceSpec::Local(local) if !local.copy => Origin::Local { path: local.path.join(&skill.subpath) },
            _ => Origin::Store {
                ref_name: ref_label.clone(),
                sha: sha.clone().unwrap_or_else(|| "preview".to_string()),
                path: PathBuf::from(format!("/preview/{}/{}", ref_label, skill.id)),
            },
        };
        desired.push(DesiredSkill {
            source_id: id.clone(),
            skill: skill.clone(),
            origin,
            scope: scope.clone(),
        });
    }
    let plan: Plan = plan_install(&desired, &targets, &ledger, &RealFs, ctx.now);
    Ok(plan.describe())
}

/// Which skills a source has, for the CLI's completion and the GUI's tree.
pub fn skills_in_source(ctx: &SkillContext, source_id: &str) -> DynResult<Vec<String>> {
    let ledger = read_ledger(&ctx.paths.ledger)?;
    Ok(ledger.skills_of(source_id).iter().map(|skill| skill.as_str().to_string()).collect())
}

/// Conflicts in a plan are data, not an error: the callers decide how loud to be.
pub fn conflict_lines(conflicts: &[Conflict]) -> Vec<String> {
    conflicts
        .iter()
        .map(|conflict| format!("{}: {}", conflict.link.display(), conflict.detail))
        .collect()
}
