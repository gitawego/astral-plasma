//! Credentials for private remotes, stored in the OS keyring (spec D6/D7).
//!
//! Three sources, in the order the spec settled on: what the machine already has
//! (`gh auth token`, `GH_TOKEN`/`ASTRAL_SKILLS_TOKEN`), then a token the user stored — which only
//! ever lives in Secret Service. There is deliberately no plaintext file fallback: an unencrypted
//! token on disk is worse than an inconvenient one.

use std::process::Command;

use crate::domain::ports::DynResult;

/// Where a token came from, so the UI can say why a private repo works.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TokenSource {
    Environment,
    GhCli,
    Keyring,
}

impl TokenSource {
    pub fn label(&self) -> &'static str {
        match self {
            Self::Environment => "environment",
            Self::GhCli => "gh CLI",
            Self::Keyring => "keyring",
        }
    }
}

/// The token in use for a host, with its provenance.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Credential {
    pub token: String,
    pub source: TokenSource,
}

const KEYRING_SERVICE: &str = "astral-plasma-skills";

/// Is Secret Service reachable? The keyring path is offered only when it is (D7).
pub fn keyring_available() -> bool {
    Command::new("secret-tool")
        .arg("--version")
        .output()
        .map(|output| output.status.success())
        .unwrap_or(false)
}

/// Look for a token without asking the user: environment first, then `gh`.
pub fn ambient_token(host: &str) -> Option<Credential> {
    for variable in ["ASTRAL_SKILLS_TOKEN", "GH_TOKEN", "GITHUB_TOKEN"] {
        if let Ok(value) = std::env::var(variable) {
            if !value.trim().is_empty() {
                return Some(Credential {
                    token: value.trim().to_string(),
                    source: TokenSource::Environment,
                });
            }
        }
    }
    if host == "github.com" {
        if let Ok(output) = Command::new("gh").args(["auth", "token", "--hostname", host]).output() {
            if output.status.success() {
                let token = String::from_utf8_lossy(&output.stdout).trim().to_string();
                if !token.is_empty() {
                    return Some(Credential { token, source: TokenSource::GhCli });
                }
            }
        }
    }
    None
}

/// A token stored in the keyring for `host`, if any.
pub fn stored_token(host: &str) -> Option<Credential> {
    let output = Command::new("secret-tool")
        .args(["lookup", "service", KEYRING_SERVICE, "host", host])
        .output()
        .ok()?;
    if !output.status.success() {
        return None;
    }
    let token = String::from_utf8_lossy(&output.stdout).trim().to_string();
    if token.is_empty() {
        None
    } else {
        Some(Credential { token, source: TokenSource::Keyring })
    }
}

/// Store a token for `host`. Refuses rather than writing it anywhere else.
pub fn store_token(host: &str, label: &str, token: &str) -> DynResult<()> {
    if token.trim().is_empty() {
        return Err("the token is empty".into());
    }
    if !keyring_available() {
        return Err(
            "no keyring (Secret Service) is available, so the token was not stored; export GH_TOKEN instead"
                .into(),
        );
    }
    use std::io::Write;
    let mut child = Command::new("secret-tool")
        .args([
            "store",
            "--label",
            &format!("Astral skills · {label} ({host})"),
            "service",
            KEYRING_SERVICE,
            "host",
            host,
        ])
        .stdin(std::process::Stdio::piped())
        .spawn()?;
    if let Some(mut stdin) = child.stdin.take() {
        stdin.write_all(token.trim().as_bytes())?;
    }
    let status = child.wait()?;
    if !status.success() {
        return Err(format!("secret-tool failed to store the token for {host}").into());
    }
    Ok(())
}

/// Forget a stored token.
pub fn forget_token(host: &str) -> DynResult<bool> {
    let status = Command::new("secret-tool")
        .args(["clear", "service", KEYRING_SERVICE, "host", host])
        .status()?;
    Ok(status.success())
}

/// The token to use for `host`, remembering where it came from.
pub fn resolve_token(host: &str) -> Option<Credential> {
    ambient_token(host).or_else(|| stored_token(host))
}

/// Which credential a source should use, given its auth mode.
pub fn for_source(host: &str) -> Option<Credential> {
    resolve_token(host)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_environment_is_checked_before_anything_else_is_run() {
        // A distinct variable name per test avoids interfering with a real user token.
        let previous = std::env::var("ASTRAL_SKILLS_TOKEN").ok();
        std::env::set_var("ASTRAL_SKILLS_TOKEN", "env-token");
        let found = ambient_token("github.com").expect("the environment token is used");
        assert_eq!(found.source, TokenSource::Environment);
        assert_eq!(found.token, "env-token");
        match previous {
            Some(value) => std::env::set_var("ASTRAL_SKILLS_TOKEN", value),
            None => std::env::remove_var("ASTRAL_SKILLS_TOKEN"),
        }
    }

    #[test]
    fn an_empty_token_is_refused_and_never_written() {
        let error = store_token("github.com", "test", "   ").unwrap_err();
        assert!(error.to_string().contains("empty"), "got: {error}");
    }

    #[test]
    fn provenance_is_reported_in_words() {
        assert_eq!(TokenSource::Environment.label(), "environment");
        assert_eq!(TokenSource::GhCli.label(), "gh CLI");
        assert_eq!(TokenSource::Keyring.label(), "keyring");
    }
}
