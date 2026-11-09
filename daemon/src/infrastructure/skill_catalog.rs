//! Searching for skills across sources (spec §8.3, D1).
//!
//! Two searchable sources exist, and they differ in a way the product must be honest about:
//! GitHub's API works anonymously (rate-limited), while skills.sh requires a Vercel OIDC token a
//! desktop app cannot mint. So GitHub is the default discovery path, skills.sh turns on with a
//! token, and a pasted skills.sh *page* still installs through the repository it names.

use crate::domain::ports::DynResult;
use crate::domain::skill_source::{parse_source, SourceSpec};

/// One search result. A repo hit is a source; a skill hit names one skill of a source.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SearchHit {
    /// `owner/repo`.
    pub source: String,
    /// The skill's name when the hit is one skill; the repository's name otherwise.
    pub name: String,
    pub description: String,
    pub installs: u64,
    /// A page a person can open.
    pub url: String,
    pub kind: HitKind,
    /// `official` when the publisher is the project's own organisation.
    pub trust: HitTrust,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum HitKind {
    Repository,
    Skill,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum HitTrust {
    Official,
    Community,
}

/// Parse GitHub's `/search/repositories` response.
pub fn parse_github_repositories(json: &[u8]) -> DynResult<Vec<SearchHit>> {
    let value: serde_json::Value = serde_json::from_slice(json)
        .map_err(|error| format!("GitHub returned something that is not JSON: {error}"))?;
    if let Some(message) = value.get("message").and_then(serde_json::Value::as_str) {
        return Err(format!("GitHub refused the search: {message}").into());
    }
    let items = value
        .get("items")
        .and_then(serde_json::Value::as_array)
        .ok_or("GitHub returned no items")?;
    Ok(items
        .iter()
        .filter_map(|item| {
            let full_name = item.get("full_name")?.as_str()?;
            Some(SearchHit {
                source: full_name.to_string(),
                name: full_name.rsplit('/').next().unwrap_or(full_name).to_string(),
                description: item
                    .get("description")
                    .and_then(serde_json::Value::as_str)
                    .unwrap_or("")
                    .to_string(),
                installs: item
                    .get("stargazers_count")
                    .and_then(serde_json::Value::as_u64)
                    .unwrap_or(0),
                url: item
                    .get("html_url")
                    .and_then(serde_json::Value::as_str)
                    .unwrap_or("")
                    .to_string(),
                kind: HitKind::Repository,
                trust: HitTrust::Community,
            })
        })
        .collect())
}

/// Parse skills.sh's `/api/v1/skills/search` response.
pub fn parse_skills_sh_search(json: &[u8]) -> DynResult<Vec<SearchHit>> {
    let value: serde_json::Value = serde_json::from_slice(json)
        .map_err(|error| format!("skills.sh returned something that is not JSON: {error}"))?;
    if let Some(error) = value.get("error").and_then(serde_json::Value::as_str) {
        let message = value
            .get("message")
            .and_then(serde_json::Value::as_str)
            .unwrap_or("");
        return Err(format!("skills.sh refused the search ({error}): {message}").into());
    }
    let items = value
        .get("data")
        .and_then(serde_json::Value::as_array)
        .ok_or("skills.sh returned no data")?;
    Ok(items
        .iter()
        .filter_map(|item| {
            let source = item.get("source")?.as_str()?;
            Some(SearchHit {
                source: source.to_string(),
                name: item
                    .get("name")
                    .and_then(serde_json::Value::as_str)
                    .unwrap_or_else(|| item.get("slug").and_then(serde_json::Value::as_str).unwrap_or(""))
                    .to_string(),
                description: item
                    .get("description")
                    .and_then(serde_json::Value::as_str)
                    .unwrap_or("")
                    .to_string(),
                installs: item.get("installs").and_then(serde_json::Value::as_u64).unwrap_or(0),
                url: item
                    .get("url")
                    .and_then(serde_json::Value::as_str)
                    .unwrap_or("")
                    .to_string(),
                kind: HitKind::Skill,
                trust: if item.get("curated").and_then(serde_json::Value::as_bool).unwrap_or(false) {
                    HitTrust::Official
                } else {
                    HitTrust::Community
                },
            })
        })
        .collect())
}

/// What a search box should do with its text.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Query {
    /// The text is a source (URL, `owner/repo`, folder) — install from it directly.
    Source(SourceSpec),
    /// The text is words to search for.
    Search(String),
}

/// Classify search-box input: anything that resolves to a source is used as one.
pub fn classify_query(text: &str) -> Query {
    match parse_source(text) {
        Ok(spec) => Query::Source(spec),
        Err(_) => Query::Search(text.trim().to_string()),
    }
}

/// `curl` is the transport: it is already a session dependency and handles TLS, proxies and
/// redirects without vendoring a second stack (the same reasoning as the app catalog, C.28).
fn http_get(url: &str, accept: &str, bearer: Option<&str>) -> DynResult<Vec<u8>> {
    let mut command = std::process::Command::new("curl");
    command.args([
        "--fail",
        "--silent",
        "--show-error",
        "--location",
        "--proto",
        "=https",
        "--max-time",
        "25",
        "--max-filesize",
        &(4 * 1024 * 1024).to_string(),
        "--header",
        &format!("Accept: {accept}"),
        "--header",
        "User-Agent: astral-plasma-skills",
    ]);
    if let Some(token) = bearer {
        command.args(["--header", &format!("Authorization: Bearer {token}")]);
    }
    command.arg(url);
    let output = command.output().map_err(|error| format!("cannot run curl: {error}"))?;
    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        let redacted = match bearer {
            Some(token) if !token.is_empty() => stderr.replace(token, "••••"),
            _ => stderr.to_string(),
        };
        return Err(format!("search failed: {}", redacted.trim()).into());
    }
    Ok(output.stdout)
}

/// Search GitHub repositories that look like skill collections.
pub fn github_search(query: &str, token: Option<&str>) -> DynResult<Vec<SearchHit>> {
    let url = format!(
        "https://api.github.com/search/repositories?q={}&per_page=20",
        urlencode(&format!("{query} skills"))
    );
    let body = http_get(&url, "application/vnd.github+json", token)?;
    parse_github_repositories(&body)
}

/// Search the skills.sh catalog. Requires a Vercel OIDC token (its API says so with a 401).
pub fn skills_sh_search(query: &str, token: Option<&str>) -> DynResult<Vec<SearchHit>> {
    let Some(token) = token.filter(|token| !token.trim().is_empty()) else {
        return Err(
            "skills.sh needs a Vercel OIDC token; search GitHub instead, or paste a skills.sh page to install from it"
                .into(),
        );
    };
    let url = format!(
        "https://skills.sh/api/v1/skills/search?q={}&limit=20",
        urlencode(query)
    );
    let body = http_get(&url, "application/json", Some(token))?;
    parse_skills_sh_search(&body)
}

/// Percent-encode a query string (only what a search box can contain).
fn urlencode(text: &str) -> String {
    let mut out = String::new();
    for byte in text.as_bytes() {
        match byte {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => out.push(*byte as char),
            b' ' => out.push_str("%20"),
            other => out.push_str(&format!("%{other:02X}")),
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn github_repositories_become_hits_with_stars_as_installs() {
        let json = br#"{
          "total_count": 2,
          "items": [
            {"full_name": "vercel-labs/agent-skills", "description": "Agent skills", "stargazers_count": 2410, "html_url": "https://github.com/vercel-labs/agent-skills"},
            {"full_name": "build-with-ai-hq/secure-llm-apps", "description": null, "stargazers_count": 87, "html_url": "https://github.com/build-with-ai-hq/secure-llm-apps"}
          ]
        }"#;
        let hits = parse_github_repositories(json).unwrap();
        assert_eq!(hits.len(), 2);
        assert_eq!(hits[0].source, "vercel-labs/agent-skills");
        assert_eq!(hits[0].name, "agent-skills");
        assert_eq!(hits[0].installs, 2410);
        assert_eq!(hits[0].kind, HitKind::Repository);
        assert_eq!(hits[1].description, "", "a missing description is empty, not a panic");
    }

    #[test]
    fn a_github_error_is_reported_not_swallowed() {
        let json = br#"{"message": "API rate limit exceeded for 1.2.3.4"}"#;
        let error = parse_github_repositories(json).unwrap_err();
        assert!(error.to_string().contains("rate limit"), "got: {error}");
        assert!(parse_github_repositories(b"not json").is_err());
    }

    #[test]
    fn skills_sh_hits_name_one_skill_of_a_repo() {
        let json = br#"{
          "data": [
            {"id":"expo/skills/react-native","slug":"react-native","name":"React Native","source":"expo/skills","installs":3842,"url":"https://skills.sh/expo/skills/react-native","curated":true}
          ],
          "count": 1
        }"#;
        let hits = parse_skills_sh_search(json).unwrap();
        assert_eq!(hits.len(), 1);
        assert_eq!(hits[0].source, "expo/skills");
        assert_eq!(hits[0].name, "React Native");
        assert_eq!(hits[0].kind, HitKind::Skill);
        assert_eq!(hits[0].trust, HitTrust::Official);
    }

    #[test]
    fn a_skills_sh_auth_error_keeps_its_explanation() {
        let json = br#"{"error":"authentication_required","message":"Pass a Vercel OIDC token"}"#;
        let error = parse_skills_sh_search(json).unwrap_err().to_string();
        assert!(error.contains("authentication_required"));
        assert!(error.contains("Vercel OIDC"));
        // The refusal without a token says what to do instead (D1).
        let refusal = skills_sh_search("design", None).unwrap_err().to_string();
        assert!(refusal.contains("GitHub"), "got: {refusal}");
    }

    #[test]
    fn the_search_box_recognises_sources() {
        assert!(matches!(classify_query("owner/repo"), Query::Source(_)));
        assert!(matches!(classify_query("https://github.com/o/r"), Query::Source(_)));
        assert!(matches!(classify_query("~/skills"), Query::Source(_)));
        assert_eq!(classify_query("react native design"), Query::Search("react native design".to_string()));
    }

    #[test]
    fn query_encoding_is_safe() {
        assert_eq!(urlencode("react native"), "react%20native");
        assert_eq!(urlencode("a+b&c=d"), "a%2Bb%26c%3Dd");
        assert_eq!(urlencode("ok-name_1.0~"), "ok-name_1.0~");
    }
}
