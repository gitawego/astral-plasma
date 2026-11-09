//! Where a skill comes from: a git remote, a local folder, or a URL that names one.
//!
//! Parsing is the part of the manager a user meets first, so it accepts what people paste — the
//! ecosystem's `owner/repo` shorthand, GitHub/GitLab/self-hosted URLs, `git@…`, a skills.sh page,
//! or a folder — and refuses what it cannot honestly install.

use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};

use crate::domain::skill::SkillId;

/// How a remote authenticates. Only `Credential` names a secret, and only by id (spec D6/D7).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "lowercase")]
pub enum GitAuth {
    /// git's own configuration: credential helper, `gh auth setup-git`, SSH agent.
    #[default]
    Configured,
    /// The SSH agent, optionally with a named key (a handle, not a path to a secret in a file we
    /// own).
    SshAgent,
    /// A stored credential (keyring entry), referenced by id.
    Credential,
}

/// A git remote to clone.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct GitSource {
    pub url: String,
    /// Branch, tag or full commit SHA. `None` means the remote's default branch.
    pub ref_name: Option<String>,
    /// Monorepo subdirectory that contains the skills.
    pub subpath: Option<String>,
    pub auth: GitAuth,
    /// A skill id this source was created *for* (a skills.sh page names one skill of a repo).
    pub preferred_skill: Option<SkillId>,
}

/// A folder on this machine, linked in place (spec D8).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct LocalSource {
    pub path: PathBuf,
    /// Re-scan and relink when the folder changes.
    pub watch: bool,
    /// Snapshot into the store instead of linking in place.
    pub copy: bool,
    pub subpath: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "lowercase")]
pub enum SourceSpec {
    Git(GitSource),
    Local(LocalSource),
}

impl SourceSpec {
    pub fn subpath(&self) -> Option<&str> {
        match self {
            Self::Git(git) => git.subpath.as_deref(),
            Self::Local(local) => local.subpath.as_deref(),
        }
    }

    /// The string a user typed, as close as we can render it back.
    pub fn display(&self) -> String {
        match self {
            Self::Git(git) => match &git.ref_name {
                Some(reference) => format!("{}#{}", git.url, reference),
                None => git.url.clone(),
            },
            Self::Local(local) => local.path.display().to_string(),
        }
    }
}

/// Why a source string was refused.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SourceError {
    pub input: String,
    pub reason: &'static str,
}

impl std::fmt::Display for SourceError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "cannot use '{}': {}", self.input, self.reason)
    }
}

impl std::error::Error for SourceError {}

/// Parse what a user typed into a source.
pub fn parse_source(input: &str) -> Result<SourceSpec, SourceError> {
    let raw = input.trim();
    let err = |reason: &'static str| SourceError {
        input: raw.to_string(),
        reason,
    };
    if raw.is_empty() {
        return Err(err("the source is empty"));
    }
    // A pasted token in a URL is refused rather than quietly used (spec §8.2): git copies the URL
    // into `.git/config`, error messages and reflogs.
    if has_secret_userinfo(raw) {
        return Err(err(
            "put the token in the credential field, not in the URL: a URL is copied into git config, logs and error messages",
        ));
    }

    // skills.sh page: https://skills.sh/<owner>/<repo>/<skill>
    if let Some(spec) = parse_skills_sh(raw) {
        return Ok(spec);
    }

    // GitHub/GitLab web URL, optionally with /tree/<ref>/<subpath>.
    if let Some(spec) = parse_web_url(raw) {
        return Ok(spec);
    }

    // Local path: absolute, ~, ./, ../, or a directory that exists and is not a git remote.
    if let Some(spec) = parse_local(raw) {
        return Ok(spec);
    }

    // git@host:owner/repo.git, ssh://, git://, file://
    if let Some(spec) = parse_git_url(raw) {
        return Ok(spec);
    }

    // owner/repo[#ref]
    if let Some(spec) = parse_shorthand(raw) {
        return Ok(spec);
    }

    Err(err(
        "expected owner/repo, a git URL (https, ssh, git@, file), a skills.sh page, or a folder",
    ))
}

/// `scheme://user:password@host` or a token-looking userinfo.
fn has_secret_userinfo(raw: &str) -> bool {
    let Some((_, rest)) = raw.split_once("://") else {
        return false;
    };
    let Some((userinfo, _)) = rest.split_once('@') else {
        return false;
    };
    // `user:pass@`, `x-access-token:ghp_…@`, or anything that looks like a platform token.
    userinfo.contains(':')
        || userinfo.starts_with("ghp_")
        || userinfo.starts_with("github_pat_")
        || userinfo.starts_with("gho_")
        || userinfo.starts_with("glpat-")
}

fn parse_skills_sh(raw: &str) -> Option<SourceSpec> {
    let rest = raw
        .strip_prefix("https://skills.sh/")
        .or_else(|| raw.strip_prefix("http://skills.sh/"))
        .or_else(|| raw.strip_prefix("https://www.skills.sh/"))
        .or_else(|| raw.strip_prefix("http://www.skills.sh/"))?;
    let parts: Vec<&str> = rest.split('/').filter(|part| !part.is_empty()).collect();
    let [owner, repo, skill] = parts.as_slice() else {
        return None;
    };
    let skill = skill.split(['?', '#']).next().unwrap_or(skill);
    Some(SourceSpec::Git(GitSource {
        url: format!("https://github.com/{owner}/{repo}"),
        ref_name: None,
        subpath: None,
        auth: GitAuth::Configured,
        preferred_skill: SkillId::parse(skill).ok(),
    }))
}

fn parse_web_url(raw: &str) -> Option<SourceSpec> {
    let (scheme, rest) = raw.split_once("://")?;
    if scheme != "https" && scheme != "http" {
        return None;
    }
    let (host, path) = rest.split_once('/')?;
    let parts: Vec<&str> = path.split('/').filter(|part| !part.is_empty()).collect();
    // Any host is a candidate when the path names an owner and a repo (self-hosted GitLab,
    // Gitea, Codeberg…). A single segment is not a repository, so `https://example.com/foo`
    // stays refused instead of producing a clone that cannot work.
    if parts.len() < 2 || host.is_empty() || !host.contains('.') {
        return None;
    }
    let owner = parts[0];
    let repo = parts[1].trim_end_matches(".git");
    let mut ref_name = None;
    let mut subpath = None;
    if parts.len() >= 4 && (parts[2] == "tree" || parts[2] == "blob") {
        ref_name = Some(parts[3].to_string());
        if parts.len() > 4 {
            subpath = Some(parts[4..].join("/").trim_end_matches('/').to_string());
        }
    }
    Some(SourceSpec::Git(GitSource {
        url: format!("https://{host}/{owner}/{repo}"),
        ref_name,
        subpath: subpath.filter(|path| !path.is_empty()),
        auth: GitAuth::Configured,
        preferred_skill: None,
    }))
}

fn parse_local(raw: &str) -> Option<SourceSpec> {
    let looks_like_path = raw.starts_with('/')
        || raw.starts_with("./")
        || raw.starts_with("../")
        || raw.starts_with("~/")
        || raw == "~";
    if !looks_like_path {
        return None;
    }
    let path = if raw == "~" {
        std::env::var_os("HOME").map(PathBuf::from).unwrap_or_else(|| PathBuf::from("/"))
    } else if let Some(rest) = raw.strip_prefix("~/") {
        std::env::var_os("HOME")
            .map(PathBuf::from)
            .unwrap_or_else(|| PathBuf::from("/"))
            .join(rest)
    } else {
        PathBuf::from(raw)
    };
    Some(SourceSpec::Local(LocalSource {
        path,
        watch: true,
        copy: false,
        subpath: None,
    }))
}

fn parse_git_url(raw: &str) -> Option<SourceSpec> {
    let is_git = raw.starts_with("git@")
        || raw.starts_with("ssh://")
        || raw.starts_with("git://")
        || raw.starts_with("file://");
    if !is_git {
        return None;
    }
    let (base, ref_name) = match raw.split_once('#') {
        Some((base, reference)) if !reference.is_empty() => (base, Some(reference.to_string())),
        _ => (raw, None),
    };
    Some(SourceSpec::Git(GitSource {
        url: base.to_string(),
        ref_name,
        subpath: None,
        auth: if raw.starts_with("git@") || raw.starts_with("ssh://") {
            GitAuth::SshAgent
        } else {
            GitAuth::Configured
        },
        preferred_skill: None,
    }))
}

fn parse_shorthand(raw: &str) -> Option<SourceSpec> {
    let (base, ref_name) = match raw.split_once('#') {
        Some((base, reference)) if !reference.is_empty() => (base, Some(reference.to_string())),
        _ => (raw, None),
    };
    let parts: Vec<&str> = base.split('/').collect();
    if parts.len() != 2 {
        return None;
    }
    let (owner, repo) = (parts[0], parts[1].trim_end_matches(".git"));
    let valid = |text: &str| {
        !text.is_empty()
            && text
                .chars()
                .all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_' || c == '.')
    };
    if !valid(owner) || !valid(repo) {
        return None;
    }
    Some(SourceSpec::Git(GitSource {
        url: format!("https://github.com/{owner}/{repo}"),
        ref_name,
        subpath: None,
        auth: GitAuth::Configured,
        preferred_skill: None,
    }))
}

/// A source the user added, with a stable id derived from what it points at (spec §8.1).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AddedSource {
    pub id: String,
    pub label: String,
    pub spec: SourceSpec,
    /// The repository-level default: disabling a repo disables the skills that have no explicit
    /// override (spec §7).
    #[serde(default = "default_true")]
    pub enabled: bool,
    pub added_at: u64,
    pub last_seen: Option<u64>,
}

fn default_true() -> bool {
    true
}

/// A stable, readable id: `owner-repo`, `git-host-owner-repo`, `local-folder`.
pub fn source_id(spec: &SourceSpec) -> String {
    let raw = match spec {
        SourceSpec::Git(git) => {
            let stripped = git
                .url
                .trim_end_matches(".git")
                .trim_start_matches("https://")
                .trim_start_matches("http://")
                .trim_start_matches("ssh://")
                .trim_start_matches("git://")
                .trim_start_matches("file://")
                .trim_start_matches("git@");
            let normalised = stripped.replace(':', "/");
            let segments: Vec<&str> = normalised.split('/').filter(|s| !s.is_empty()).collect();
            let host = segments.first().copied().unwrap_or("");
            let rest = segments.get(1..).unwrap_or(&[]).join("/");
            if host == "github.com" {
                // The default host: `owner-repo`, so the id is the same however it was typed.
                rest
            } else {
                format!("{host}/{rest}")
            }
        }
        SourceSpec::Local(local) => {
            let name = local
                .path
                .file_name()
                .map(|name| name.to_string_lossy().into_owned())
                .unwrap_or_else(|| "root".to_string());
            format!("local-{name}")
        }
    };
    slug(&raw)
}

/// Lowercase, dashes, no runs, trimmed — the same shape as an app id fragment.
pub fn slug(raw: &str) -> String {
    let mut out = String::new();
    for ch in raw.chars() {
        let next = if ch.is_ascii_alphanumeric() { ch.to_ascii_lowercase() } else { '-' };
        if next == '-' && out.ends_with('-') {
            continue;
        }
        out.push(next);
    }
    let trimmed = out.trim_matches('-').to_string();
    if trimmed.is_empty() {
        "source".to_string()
    } else {
        trimmed
    }
}

/// Whether a local path exists and looks like a skill source (has at least one `SKILL.md`, or is a
/// directory we may still scan).
pub fn local_path_exists(path: &Path) -> bool {
    path.is_dir()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn git(spec: &SourceSpec) -> &GitSource {
        match spec {
            SourceSpec::Git(git) => git,
            other => panic!("expected a git source, got {other:?}"),
        }
    }

    #[test]
    fn shorthand_and_refs_resolve_to_github() {
        let spec = parse_source("vercel-labs/agent-skills").unwrap();
        assert_eq!(git(&spec).url, "https://github.com/vercel-labs/agent-skills");
        assert_eq!(git(&spec).ref_name, None);

        let pinned = parse_source("vercel-labs/agent-skills#v1.7.4").unwrap();
        assert_eq!(git(&pinned).ref_name.as_deref(), Some("v1.7.4"));
    }

    #[test]
    fn web_urls_keep_their_ref_and_subpath() {
        let spec = parse_source("https://github.com/team/mono/tree/main/packages/ui").unwrap();
        assert_eq!(git(&spec).url, "https://github.com/team/mono");
        assert_eq!(git(&spec).ref_name.as_deref(), Some("main"));
        assert_eq!(git(&spec).subpath.as_deref(), Some("packages/ui"));

        let plain = parse_source("https://github.com/team/mono.git").unwrap();
        assert_eq!(git(&plain).url, "https://github.com/team/mono");
    }

    #[test]
    fn a_skills_sh_page_becomes_a_repo_and_one_skill() {
        let spec = parse_source("https://skills.sh/build-with-ai-hq/secure-llm-apps/secure-llm-apps").unwrap();
        assert_eq!(git(&spec).url, "https://github.com/build-with-ai-hq/secure-llm-apps");
        assert_eq!(
            git(&spec).preferred_skill.as_ref().map(|id| id.as_str()),
            Some("secure-llm-apps"),
            "the page names one skill of the repo"
        );
    }

    #[test]
    fn local_folders_are_local_and_expand_home() {
        let spec = parse_source("~/my-skills").unwrap();
        match spec {
            SourceSpec::Local(local) => {
                assert!(local.path.is_absolute());
                assert!(local.watch, "a local source is watched by default");
                assert!(!local.copy, "and linked in place (D8)");
            }
            other => panic!("expected a local source, got {other:?}"),
        }
        assert!(matches!(parse_source("/absolute/path").unwrap(), SourceSpec::Local(_)));
        assert!(matches!(parse_source("./here").unwrap(), SourceSpec::Local(_)));
    }

    #[test]
    fn ssh_and_file_urls_are_git() {
        let ssh = parse_source("git@github.com:team/private-skills.git").unwrap();
        assert_eq!(git(&ssh).auth, GitAuth::SshAgent);
        assert_eq!(git(&ssh).url, "git@github.com:team/private-skills.git");

        let file = parse_source("file:///tmp/repo.git").unwrap();
        assert_eq!(git(&file).auth, GitAuth::Configured);
    }

    #[test]
    fn a_token_in_the_url_is_refused_with_the_reason() {
        let error = parse_source("https://ghp_secret@github.com/team/private.git").unwrap_err();
        assert!(error.to_string().contains("credential field"), "got: {error}");
    }

    #[test]
    fn nonsense_is_refused_naming_what_is_accepted() {
        for bad in ["", "   ", "one", "a b/c", "https://example.com/foo"] {
            let error = parse_source(bad).unwrap_err();
            assert!(
                error.reason.contains("owner/repo") || error.reason.contains("empty"),
                "{bad:?} -> {error}"
            );
        }
    }

    #[test]
    fn ids_are_stable_and_readable() {
        let public = parse_source("vercel-labs/agent-skills").unwrap();
        assert_eq!(source_id(&public), "vercel-labs-agent-skills");
        let ssh = parse_source("git@github.com:Team/Private.git").unwrap();
        assert_eq!(source_id(&ssh), "team-private", "github keeps owner-repo on every transport");
        let self_hosted = parse_source("https://git.example.com/team/skills.git").unwrap();
        assert_eq!(source_id(&self_hosted), "git-example-com-team-skills",
            "another host keeps its name so two hosts cannot collide");
        let local = parse_source("/home/me/my-skills").unwrap();
        assert_eq!(source_id(&local), "local-my-skills");
        assert_eq!(slug("a--b__c"), "a-b-c");
        assert_eq!(source_id(&public), source_id(&parse_source("https://github.com/vercel-labs/agent-skills").unwrap()),
            "the same repo has one id however it was typed");
    }
}
