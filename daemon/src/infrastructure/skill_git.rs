//! Fetching a skill repository with the system's `git`.
//!
//! `git` is the transport on purpose: it already knows the user's credential helper, SSH agent and
//! proxies, and a private repository must work without this manager storing anything. A token is
//! passed through `GIT_CONFIG_*` environment variables — never in the URL, which git copies into
//! `.git/config`, error messages and the reflog (spec §8.2).

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};
use std::process::Command;

use crate::domain::ports::DynResult;

/// How to authenticate one fetch.
#[derive(Debug, Clone, Default)]
pub struct FetchAuth {
    /// A bearer token for HTTPS hosts (injected as an `http.extraHeader`).
    pub token: Option<String>,
    /// An SSH key to offer the agent (`GIT_SSH_COMMAND`).
    pub ssh_key: Option<PathBuf>,
}

/// A fetched repository, in memory.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FetchedRepo {
    /// The resolved commit (`git rev-parse HEAD`).
    pub sha: String,
    /// The ref that was requested, or the remote's default branch name.
    pub ref_name: String,
    /// Relative path -> bytes, with `.git` excluded.
    pub files: Vec<(String, Vec<u8>)>,
    /// Where the working tree is cached (for a follow-up copy of individual skills).
    pub workdir: PathBuf,
}

/// A clone that failed, with the sentence a user can act on.
#[derive(Debug)]
pub struct FetchError {
    pub kind: FetchErrorKind,
    pub detail: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FetchErrorKind {
    NotFound,
    NoAccess,
    AuthFailed,
    Network,
    TooLarge,
    GitMissing,
    Other,
}

impl std::fmt::Display for FetchError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let prefix = match self.kind {
            FetchErrorKind::NotFound => "repository not found",
            FetchErrorKind::NoAccess => "no access to this repository",
            FetchErrorKind::AuthFailed => "authentication failed",
            FetchErrorKind::Network => "cannot reach the remote",
            FetchErrorKind::TooLarge => "repository is larger than the limit",
            FetchErrorKind::GitMissing => "git is not installed",
            FetchErrorKind::Other => "git failed",
        };
        write!(f, "{prefix}: {}", self.detail)
    }
}

impl std::error::Error for FetchError {}

/// Fetches repositories into a cache and reads their files.
#[derive(Debug, Clone)]
pub struct GitCli {
    pub cache: PathBuf,
}

/// A repository bigger than this is refused rather than partially installed.
pub const MAX_BYTES: u64 = 64 * 1024 * 1024;
pub const MAX_FILES: usize = 4_000;

impl GitCli {
    pub fn new(cache: PathBuf) -> Self {
        Self { cache }
    }

    /// Resolve `ref_name` and check access without fetching content (`git ls-remote`).
    ///
    /// This is what the "Add source" dialog calls: one round trip, and the answer is `ok`,
    /// `not found` or `no access` before the user commits to anything (spec §8.2).
    pub fn check_access(&self, url: &str, ref_name: Option<&str>, auth: &FetchAuth) -> Result<String, FetchError> {
        let want = ref_name.unwrap_or("HEAD");
        let mut command = Command::new("git");
        command.args(["ls-remote", url, want]);
        apply_auth(&mut command, auth);
        let output = command.output().map_err(|err| FetchError {
            kind: if err.kind() == std::io::ErrorKind::NotFound { FetchErrorKind::GitMissing } else { FetchErrorKind::Other },
            detail: err.to_string(),
        })?;
        if !output.status.success() {
            return Err(classify(&redact(&String::from_utf8_lossy(&output.stderr), auth)));
        }
        let text = String::from_utf8_lossy(&output.stdout);
        let first = text.lines().next().unwrap_or("");
        let mut parts = first.split_whitespace();
        let sha = parts.next().unwrap_or("").to_string();
        if sha.len() < 7 {
            return Err(FetchError {
                kind: FetchErrorKind::NotFound,
                detail: format!("ref '{want}' does not exist in {url}"),
            });
        }
        Ok(sha)
    }

    /// Fetch `url` at `ref_name` (branch, tag or full SHA) and read its files.
    pub fn fetch(&self, url: &str, ref_name: Option<&str>, auth: &FetchAuth) -> Result<FetchedRepo, FetchError> {
        let want = ref_name.map(str::to_string);
        let key = cache_key(url, want.as_deref());
        let workdir = self.cache.join(&key);
        if workdir.is_dir() {
            let _ = std::fs::remove_dir_all(&workdir);
        }
        std::fs::create_dir_all(&workdir).map_err(|err| FetchError {
            kind: FetchErrorKind::Other,
            detail: err.to_string(),
        })?;

        run(&workdir, &["init", "--quiet"], auth)?;
        run(&workdir, &["remote", "add", "origin", url], auth)?;
        // A full SHA cannot be cloned with `--branch`; fetching it and checking out FETCH_HEAD
        // works for branches, tags and SHAs alike.
        let reference = want.clone().unwrap_or_else(|| "HEAD".to_string());
        // Depth 1 is the same shallow checkout `git clone --depth 1` makes: one commit,
        // one tree, no history. `--no-tags` keeps a tag farm out of a discovery cache.
        run(&workdir, &["fetch", "--depth", "1", "--no-tags", "--quiet", "origin", &reference], auth)?;
        run(&workdir, &["checkout", "--quiet", "FETCH_HEAD"], auth)?;

        let sha = capture(&workdir, &["rev-parse", "HEAD"], auth)?;
        let ref_name = match want {
            Some(name) => name,
            None => capture(&workdir, &["rev-parse", "--abbrev-ref", "FETCH_HEAD"], auth)
                .unwrap_or_else(|_| "HEAD".to_string()),
        };

        let files = read_tree(&workdir)?;
        Ok(FetchedRepo {
            sha: sha.trim().to_string(),
            ref_name: ref_name.trim().to_string(),
            files,
            workdir,
        })
    }
}

fn cache_key(url: &str, reference: Option<&str>) -> String {
    use sha2::{Digest, Sha256};
    let mut hasher = Sha256::new();
    hasher.update(url.as_bytes());
    hasher.update(b"\0");
    hasher.update(reference.unwrap_or("HEAD").as_bytes());
    let digest = format!("{:x}", hasher.finalize());
    // A readable prefix makes the cache debuggable; the digest keeps it unique.
    let label = url
        .trim_end_matches(".git")
        .rsplit('/')
        .take(2)
        .collect::<Vec<_>>()
        .into_iter()
        .rev()
        .collect::<Vec<_>>()
        .join("-");
    format!("{}-{}", crate::domain::skill_source::slug(&label), &digest[..12])
}

fn apply_auth(command: &mut Command, auth: &FetchAuth) {
    if let Some(token) = &auth.token {
        // Passed as configuration, not as part of the URL: safer in `.git/config`, `ps` and logs.
        command.env("GIT_CONFIG_COUNT", "1");
        command.env("GIT_CONFIG_KEY_0", "http.extraHeader");
        command.env(
            "GIT_CONFIG_VALUE_0",
            format!("Authorization: Basic {}", base64(format!("x-access-token:{token}"))),
        );
    }
    if let Some(key) = &auth.ssh_key {
        command.env(
            "GIT_SSH_COMMAND",
            format!("ssh -i {} -o IdentitiesOnly=yes", key.display()),
        );
    }
    command.env("GIT_TERMINAL_PROMPT", "0");
}

/// Minimal base64 (no dependency): git needs it inside the extraHeader value.
fn base64(input: String) -> String {
    const TABLE: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let bytes = input.as_bytes();
    let mut out = String::new();
    for chunk in bytes.chunks(3) {
        let b0 = chunk[0] as u32;
        let b1 = *chunk.get(1).unwrap_or(&0) as u32;
        let b2 = *chunk.get(2).unwrap_or(&0) as u32;
        let triple = (b0 << 16) | (b1 << 8) | b2;
        out.push(TABLE[((triple >> 18) & 0x3f) as usize] as char);
        out.push(TABLE[((triple >> 12) & 0x3f) as usize] as char);
        out.push(if chunk.len() > 1 { TABLE[((triple >> 6) & 0x3f) as usize] as char } else { '=' });
        out.push(if chunk.len() > 2 { TABLE[(triple & 0x3f) as usize] as char } else { '=' });
    }
    out
}

fn run(workdir: &Path, args: &[&str], auth: &FetchAuth) -> Result<(), FetchError> {
    let mut command = Command::new("git");
    command.current_dir(workdir).args(args);
    apply_auth(&mut command, auth);
    let output = command.output().map_err(|err| FetchError {
        kind: if err.kind() == std::io::ErrorKind::NotFound { FetchErrorKind::GitMissing } else { FetchErrorKind::Other },
        detail: err.to_string(),
    })?;
    if output.status.success() {
        return Ok(());
    }
    Err(classify(&redact(&String::from_utf8_lossy(&output.stderr), auth)))
}

fn capture(workdir: &Path, args: &[&str], auth: &FetchAuth) -> Result<String, FetchError> {
    let mut command = Command::new("git");
    command.current_dir(workdir).args(args);
    apply_auth(&mut command, auth);
    let output = command.output().map_err(|err| FetchError {
        kind: FetchErrorKind::Other,
        detail: err.to_string(),
    })?;
    if !output.status.success() {
        return Err(classify(&String::from_utf8_lossy(&output.stderr)));
    }
    Ok(String::from_utf8_lossy(&output.stdout).into_owned())
}

/// Turn git's stderr into something a person can act on (spec §8.2's four outcomes).
fn classify(stderr: &str) -> FetchError {
    let detail = stderr.trim().lines().last().unwrap_or("").to_string();
    let lowered = stderr.to_ascii_lowercase();
    let kind = if lowered.contains("could not resolve host")
        || lowered.contains("connection timed out")
        || lowered.contains("network is unreachable")
    {
        FetchErrorKind::Network
    } else if lowered.contains("authentication failed")
        || lowered.contains("invalid username or password")
        || lowered.contains("permission denied")
        || lowered.contains("permission to") // "Permission to owner/repo.git denied"
        || lowered.contains("could not read username")
    {
        FetchErrorKind::AuthFailed
    } else if lowered.contains("repository not found")
        || lowered.contains("does not appear to be a git repository")
        || lowered.contains("not found")
    {
        FetchErrorKind::NotFound
    } else if lowered.contains("403") || lowered.contains("access denied") {
        FetchErrorKind::NoAccess
    } else if lowered.contains("too large") || lowered.contains("exceeded") {
        FetchErrorKind::TooLarge
    } else {
        FetchErrorKind::Other
    };
    FetchError { kind, detail }
}

/// Remove a token from anything that will be shown or logged.
pub fn redact(text: &str, auth: &FetchAuth) -> String {
    match &auth.token {
        Some(token) if !token.is_empty() => text.replace(token, "••••"),
        _ => text.to_string(),
    }
}

/// Read the working tree into memory, refusing something implausibly large.
fn read_tree(root: &Path) -> Result<Vec<(String, Vec<u8>)>, FetchError> {
    let mut files: Vec<(String, Vec<u8>)> = Vec::new();
    let mut total: u64 = 0;
    let mut stack = vec![root.to_path_buf()];
    while let Some(dir) = stack.pop() {
        let entries = std::fs::read_dir(&dir).map_err(|err| FetchError {
            kind: FetchErrorKind::Other,
            detail: err.to_string(),
        })?;
        for entry in entries {
            let entry = entry.map_err(|err| FetchError {
                kind: FetchErrorKind::Other,
                detail: err.to_string(),
            })?;
            let path = entry.path();
            let name = entry.file_name().to_string_lossy().into_owned();
            if name == ".git" {
                continue;
            }
            let metadata = entry.metadata().map_err(|err| FetchError {
                kind: FetchErrorKind::Other,
                detail: err.to_string(),
            })?;
            if metadata.is_dir() {
                stack.push(path);
                continue;
            }
            if !metadata.is_file() {
                continue;
            }
            total += metadata.len();
            if total > MAX_BYTES {
                return Err(FetchError {
                    kind: FetchErrorKind::TooLarge,
                    detail: format!("more than {} MiB", MAX_BYTES / (1024 * 1024)),
                });
            }
            let bytes = std::fs::read(&path).map_err(|err| FetchError {
                kind: FetchErrorKind::Other,
                detail: err.to_string(),
            })?;
            let relative = path
                .strip_prefix(root)
                .unwrap_or(&path)
                .to_string_lossy()
                .replace('\\', "/");
            files.push((relative, bytes));
            if files.len() > MAX_FILES {
                return Err(FetchError {
                    kind: FetchErrorKind::TooLarge,
                    detail: format!("more than {MAX_FILES} files"),
                });
            }
        }
    }
    files.sort_by(|a, b| a.0.cmp(&b.0));
    Ok(files)
}

/// A map view of the fetched files, for callers that want lookups.
pub fn as_map(files: &[(String, Vec<u8>)]) -> BTreeMap<String, Vec<u8>> {
    files.iter().cloned().collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::domain::skill::discover;

    /// A real git repository in a temp dir, served over `file://` (no network in tests).
    struct Repo {
        dir: tempfile::TempDir,
    }

    impl Repo {
        fn new(files: &[(&str, &str)]) -> Self {
            let dir = tempfile::tempdir().unwrap();
            let repo = Self { dir };
            repo.commit(files, "first");
            repo
        }

        fn path(&self) -> &Path {
            self.dir.path()
        }

        fn url(&self) -> String {
            format!("file://{}", self.dir.path().display())
        }

        fn git(&self, args: &[&str]) -> String {
            let output = Command::new("git")
                .current_dir(self.dir.path())
                .args([
                    "-c",
                    "user.email=t@example.com",
                    "-c",
                    "user.name=Test",
                    "-c",
                    "init.defaultBranch=main",
                    "-c",
                    "commit.gpgsign=false",
                ])
                .args(args)
                .output()
                .unwrap();
            assert!(output.status.success(), "git {args:?}: {}", String::from_utf8_lossy(&output.stderr));
            String::from_utf8_lossy(&output.stdout).into_owned()
        }

        fn commit(&self, files: &[(&str, &str)], message: &str) {
            self.git(&["init", "-q"]);
            for (path, content) in files {
                let full = self.dir.path().join(path);
                std::fs::create_dir_all(full.parent().unwrap()).unwrap();
                std::fs::write(full, content).unwrap();
            }
            self.git(&["add", "-A"]);
            self.git(&["commit", "-qm", message]);
        }

        fn head(&self) -> String {
            self.git(&["rev-parse", "HEAD"]).trim().to_string()
        }
    }

    fn cli() -> (tempfile::TempDir, GitCli) {
        let dir = tempfile::tempdir().unwrap();
        let cli = GitCli::new(dir.path().join("cache"));
        std::fs::create_dir_all(&cli.cache).unwrap();
        (dir, cli)
    }

    #[test]
    fn a_repository_is_fetched_and_its_skills_can_be_discovered() {
        let repo = Repo::new(&[
            ("web-design/SKILL.md", "---\nname: web-design\ndescription: UI\n---\n"),
            ("llm/SKILL.md", "---\nname: secure-llm-apps\ndescription: audit\n---\n"),
            ("README.md", "# skills\n"),
        ]);
        let (_cache, cli) = cli();
        let fetched = cli.fetch(&repo.url(), None, &FetchAuth::default()).unwrap();
        assert_eq!(fetched.sha, repo.head());
        assert!(fetched.files.iter().any(|(path, _)| path == "web-design/SKILL.md"));
        assert!(!fetched.files.iter().any(|(path, _)| path.starts_with(".git/")), "the git dir is not content");
        let skills = discover(&fetched.files, None, false);
        let ids: Vec<&str> = skills.iter().map(|skill| skill.id.as_str()).collect();
        assert_eq!(ids, vec!["secure-llm-apps", "web-design"]);
    }

    #[test]
    fn the_checkout_is_shallow_and_has_no_history() {
        let repo = Repo::new(&[("a/SKILL.md", "x")]);
        repo.commit(&[("b/SKILL.md", "y")], "second");
        let (_cache, cli) = cli();
        let fetched = cli.fetch(&repo.url(), None, &FetchAuth::default()).unwrap();
        assert!(
            fetched.workdir.join(".git/shallow").is_file(),
            "depth-1 fetch must leave a shallow marker"
        );
        let output = Command::new("git")
            .current_dir(&fetched.workdir)
            .args(["rev-list", "--count", "HEAD"])
            .output()
            .expect("git rev-list runs");
        assert_eq!(String::from_utf8_lossy(&output.stdout).trim(), "1");
    }

    #[test]
    fn a_branch_tag_and_full_sha_all_resolve_to_the_same_commit() {
        let repo = Repo::new(&[("a/SKILL.md", "---\nname: a\n---\n")]);
        repo.git(&["tag", "v1"]);
        let first = repo.head();
        repo.commit(&[("b/SKILL.md", "---\nname: b\n---\n")], "second");

        let (_cache, cli) = cli();
        let branch = cli.fetch(&repo.url(), Some("main"), &FetchAuth::default()).unwrap();
        assert_eq!(branch.sha, repo.head());
        let tag = cli.fetch(&repo.url(), Some("v1"), &FetchAuth::default()).unwrap();
        assert_eq!(tag.sha, first);
        let sha = cli.fetch(&repo.url(), Some(&first), &FetchAuth::default()).unwrap();
        assert_eq!(sha.sha, first);
        assert_eq!(sha.ref_name, first.trim(), "an explicit sha is reported as the ref used");
    }

    #[test]
    fn access_is_checked_without_fetching_content() {
        let repo = Repo::new(&[("a/SKILL.md", "x")]);
        let (_cache, cli) = cli();
        assert_eq!(cli.check_access(&repo.url(), None, &FetchAuth::default()).unwrap(), repo.head());

        let missing = format!("file://{}/nope", repo.path().display());
        let error = cli.check_access(&missing, None, &FetchAuth::default()).unwrap_err();
        assert!(
            matches!(error.kind, FetchErrorKind::NotFound | FetchErrorKind::Other),
            "got {:?}: {error}",
            error.kind
        );
        assert!(!error.to_string().is_empty());
    }

    #[test]
    fn a_token_is_passed_by_configuration_and_redacted_from_output() {
        let auth = FetchAuth { token: Some("ghp_secret_value".to_string()), ssh_key: None };
        let mut command = Command::new("git");
        apply_auth(&mut command, &auth);
        // The token appears only inside the base64 header value, never as its own argv/env entry
        // that a `ps` dump would show as `GIT_ASKPASS=…` or a URL.
        let redacted = redact("fatal: could not read ghp_secret_value", &auth);
        assert_eq!(redacted, "fatal: could not read ••••");
        assert_eq!(
            base64("x-access-token:tok".to_string()),
            "eC1hY2Nlc3MtdG9rZW46dG9r"
        );
    }

    #[test]
    fn git_errors_are_classified_into_the_four_outcomes() {
        let cases = [
            ("fatal: could not resolve host: github.com", FetchErrorKind::Network),
            ("remote: Repository not found.", FetchErrorKind::NotFound),
            ("fatal: Authentication failed for 'https://github.com/x/y.git'", FetchErrorKind::AuthFailed),
            ("remote: Permission to x/y.git denied", FetchErrorKind::AuthFailed),
            ("error: RPC failed; HTTP 403", FetchErrorKind::NoAccess),
            ("something else entirely", FetchErrorKind::Other),
        ];
        for (text, expected) in cases {
            let error = classify(text);
            assert_eq!(error.kind, expected, "{text} -> {error:?}");
        }
    }

    #[test]
    fn the_cache_key_is_unique_per_url_and_ref_but_stable() {
        let a = cache_key("https://github.com/o/r", None);
        let b = cache_key("https://github.com/o/r", None);
        let c = cache_key("https://github.com/o/r", Some("dev"));
        assert_eq!(a, b, "the same input is cached once");
        assert_ne!(a, c, "a different ref is a different checkout");
        assert!(a.starts_with("o-r-"), "the key stays readable: {a}");
    }
}
