pub mod antigravity;
pub mod claude;
pub mod codex;
pub mod dsh;
pub mod ide;
pub mod omp;
pub mod opencode;
pub mod pi;
pub mod zcode;

use crate::domain::ports::{ActiveSessionDescriptor, AgentSessionAdapter, SessionParseResult};
use std::fs::File;
use std::io::{Read, Seek, SeekFrom};
use std::path::{Path, PathBuf};

pub use antigravity::AntigravityAdapter;
pub use claude::ClaudeAdapter;
pub use codex::CodexAdapter;
pub use dsh::DshAdapter;
pub use ide::IdeAdapter;
pub use omp::OmpAdapter;
pub use opencode::OpenCodeAdapter;
pub use pi::PiAdapter;
pub use zcode::ZCodeAdapter;

/// Central registry managing all registered AI Agent Session Adapters.
pub struct AdapterRegistry {
    adapters: Vec<Box<dyn AgentSessionAdapter>>,
}

impl Default for AdapterRegistry {
    fn default() -> Self {
        Self::new()
    }
}

impl AdapterRegistry {
    /// Creates a registry initialized with all supported domain adapters.
    pub fn new() -> Self {
        Self {
            adapters: vec![
                Box::new(AntigravityAdapter::new()),
                Box::new(ClaudeAdapter::new()),
                Box::new(CodexAdapter::new()),
                Box::new(PiAdapter::new()),
                Box::new(OmpAdapter::new()),
                Box::new(ZCodeAdapter::new()),
                Box::new(OpenCodeAdapter::new()),
                Box::new(DshAdapter::new()),
                Box::new(IdeAdapter::new()),
            ],
        }
    }

    /// Creates a registry with custom adapters (useful for unit testing).
    pub fn with_adapters(adapters: Vec<Box<dyn AgentSessionAdapter>>) -> Self {
        Self { adapters }
    }

    /// Returns all registered adapters.
    pub fn adapters(&self) -> &[Box<dyn AgentSessionAdapter>] {
        &self.adapters
    }

    /// Finds the first adapter that handles the given file path.
    pub fn find_adapter_for_path(&self, path: &Path) -> Option<&dyn AgentSessionAdapter> {
        self.adapters.iter().find(|ad| ad.can_handle_file(path)).map(|b| b.as_ref())
    }

    /// Collects watch directories across all registered adapters.
    pub fn all_watch_directories(&self, home: &Path) -> Vec<PathBuf> {
        let mut dirs = Vec::new();
        for ad in &self.adapters {
            dirs.extend(ad.watch_directories(home));
        }
        dirs
    }

    /// Parses an active session file by delegating to its matching adapter.
    pub fn parse_file(&self, path: &Path) -> Option<SessionParseResult> {
        let path_hint = path.to_string_lossy();
        if path_hint.ends_with(".log")
            || path_hint.ends_with(".db")
            || path_hint.contains("context-mode")
            || path_hint.contains("stats-pid")
            || path_hint.contains("/cli/log/")
            || path_hint.contains("/cli/log")
        {
            return None;
        }

        if path_hint.ends_with(".lock") {
            return None;
        }

        if path_hint.contains("antigravity") && !path_hint.ends_with("transcript.jsonl") {
            return None;
        }

        let tail = read_tail_string(path, 32768);
        let head = read_head_string(path, 8192);

        if let Some(adapter) = self.find_adapter_for_path(path) {
            if let Some(res) = adapter.parse_session_file(path, tail.as_deref(), head.as_deref()) {
                return Some(res);
            }
        }

        // Generic fallback for anonymous/temp session files:
        // 1. Scan tail lines in reverse
        if let Some(tail_str) = &tail {
            for line in tail_str.lines().rev() {
                let trimmed = line.trim();
                if trimmed.is_empty() {
                    continue;
                }
                if let Some((m, prov)) = extract_model_from_json_line(trimmed) {
                    let resolved_prov = if prov.is_empty() { "agent".to_string() } else { prov };
                    let is_completed = self.check_turn_completed(tail_str, &path_hint);
                    let tokens = extract_tokens_from_tail(tail_str);
                    return Some(SessionParseResult {
                        model_id: m,
                        tool_source: resolved_prov,
                        tokens,
                        is_turn_completed: is_completed,
                        timestamp_ms: None,
                    });
                }
            }
        }

        // 2. Scan head lines
        if let Some(head_str) = &head {
            for line in head_str.lines() {
                let trimmed = line.trim();
                if trimmed.is_empty() {
                    continue;
                }
                if let Some((m, prov)) = extract_model_from_json_line(trimmed) {
                    let resolved_prov = if prov.is_empty() { "agent".to_string() } else { prov };
                    let is_completed = tail.as_deref().map(|t| self.check_turn_completed(t, &path_hint)).unwrap_or(true);
                    let tokens = tail.as_deref().and_then(extract_tokens_from_tail);
                    return Some(SessionParseResult {
                        model_id: m,
                        tool_source: resolved_prov,
                        tokens,
                        is_turn_completed: is_completed,
                        timestamp_ms: None,
                    });
                }
            }
        }

        None
    }

    /// Parses model, tool source, tokens, and turn completion status.
    pub fn parse_model_tokens_and_status(&self, path: &Path) -> Option<(String, String, Option<u64>, bool)> {
        let res = self.parse_file(path)?;
        Some((res.model_id, res.tool_source, res.tokens, res.is_turn_completed))
    }

    /// Parses model identity from a raw tail string and path hint.
    pub fn parse_model_from_tail(&self, tail: &str, path_hint: &str) -> Option<(String, String)> {
        let path = Path::new(path_hint);
        if let Some(adapter) = self.find_adapter_for_path(path) {
            if let Some(res) = adapter.parse_session_file(path, Some(tail), None) {
                return Some((res.model_id, res.tool_source));
            }
            if let Some(defaults) = adapter.read_default_settings(path) {
                return Some(defaults);
            }
        }

        // Generic JSON line parse fallback
        for line in tail.lines().rev() {
            let trimmed = line.trim();
            if trimmed.is_empty() {
                continue;
            }
            if let Some((m, prov)) = extract_model_from_json_line(trimmed) {
                let resolved_prov = if prov.is_empty() { "agent".to_string() } else { prov };
                return Some((m, resolved_prov));
            }
        }

        None
    }

    /// Discovers active session files across all registered adapters within the max age window.
    pub fn scan_all_active_files(&self, home: &Path, max_age_ms: u64) -> Vec<ActiveSessionDescriptor> {
        let mut results = Vec::new();
        for ad in &self.adapters {
            ad.scan_active_files(home, max_age_ms, &mut results);
        }
        results
    }

    /// Discovers the most recently modified session file across all adapters.
    pub fn find_latest_session_file(&self, home: &Path) -> Option<(PathBuf, u64, u64)> {
        let mut candidates = Vec::new();
        for ad in &self.adapters {
            ad.find_candidate_session_files(home, &mut candidates);
        }

        let mut latest_path: Option<PathBuf> = None;
        let mut latest_mtime: u64 = 0;
        let mut latest_size: u64 = 0;

        for path in candidates {
            if let Ok(meta) = path.metadata() {
                if let Ok(mtime) = meta.modified() {
                    let epoch = mtime.duration_since(std::time::UNIX_EPOCH).unwrap_or_default().as_millis() as u64;
                    if epoch > latest_mtime {
                        latest_mtime = epoch;
                        latest_size = meta.len();
                        latest_path = Some(path);
                    }
                }
            }
        }

        latest_path.map(|p| (p, latest_mtime, latest_size))
    }

    /// Queries all external stores (e.g. SQLite databases).
    pub fn query_all_external_stores(&self, home: &Path) -> Vec<SessionParseResult> {
        let mut results = Vec::new();
        for ad in &self.adapters {
            if let Some(res) = ad.query_external_store(home) {
                results.push(res);
            }
        }
        results
    }

    /// Tests whether the turn is completed according to the matching adapter.
    pub fn check_turn_completed(&self, tail: &str, path_hint: &str) -> bool {
        let path = Path::new(path_hint);
        if let Some(adapter) = self.find_adapter_for_path(path) {
            adapter.check_turn_completed(tail, path)
        } else {
            true
        }
    }
}

// -----------------------------------------------------------------------------
// Shared Parsing Primitives
// -----------------------------------------------------------------------------

pub fn read_head_string(path: &Path, max_bytes: usize) -> Option<String> {
    let mut file = File::open(path).ok()?;
    let mut buf = vec![0u8; max_bytes];
    let n = file.read(&mut buf).ok()?;
    if n == 0 {
        return None;
    }
    String::from_utf8(buf[..n].to_vec()).ok()
}

pub fn read_tail_string(path: &Path, max_bytes: usize) -> Option<String> {
    let mut file = File::open(path).ok()?;
    let len = file.metadata().ok()?.len() as usize;
    if len == 0 {
        return None;
    }
    let read_size = len.min(max_bytes);
    let offset = len.saturating_sub(read_size);
    file.seek(SeekFrom::Start(offset as u64)).ok()?;
    let mut buf = vec![0u8; read_size];
    file.read_exact(&mut buf).ok()?;
    String::from_utf8_lossy(&buf).to_string().into()
}

pub fn scan_jsonl_recursive<F>(dir: &Path, max_depth: usize, callback: &mut F)
where
    F: FnMut(&Path),
{
    if max_depth == 0 || !dir.exists() || !dir.is_dir() {
        return;
    }
    if let Ok(entries) = std::fs::read_dir(dir) {
        for entry in entries.flatten() {
            let path = entry.path();
            if path.is_dir() {
                scan_jsonl_recursive(&path, max_depth - 1, callback);
            } else if path.extension().and_then(|s| s.to_str()) == Some("jsonl") {
                callback(&path);
            }
        }
    }
}

pub fn scan_dirs_recursive<F>(dir: &Path, max_depth: usize, callback: &mut F)
where
    F: FnMut(&Path),
{
    if max_depth == 0 || !dir.exists() || !dir.is_dir() {
        return;
    }
    if let Ok(entries) = std::fs::read_dir(dir) {
        for entry in entries.flatten() {
            let path = entry.path();
            if path.is_dir() {
                callback(&path);
                scan_dirs_recursive(&path, max_depth - 1, callback);
            }
        }
    }
}

pub fn extract_model_from_json_line(line: &str) -> Option<(String, String)> {
    let lower = line.to_lowercase();
    if !lower.contains("model") {
        return None;
    }

    if let Ok(v) = serde_json::from_str::<serde_json::Value>(line) {
        let direct_model = v.get("model")
            .or_else(|| v.get("modelId"))
            .or_else(|| v.get("model_id"))
            .or_else(|| v.get("modelName"))
            .or_else(|| v.get("model_name"))
            .and_then(|s| s.as_str());

        let msg = v.get("message");
        let msg_model = msg.and_then(|m| {
            m.get("model")
                .or_else(|| m.get("modelId"))
                .or_else(|| m.get("model_id"))
                .or_else(|| m.get("modelName"))
                .or_else(|| m.get("model_name"))
        }).and_then(|s| s.as_str());

        let resp = v.get("response");
        let resp_model = resp.and_then(|r| {
            r.get("model")
                .or_else(|| r.get("modelId"))
                .or_else(|| r.get("model_id"))
                .or_else(|| r.get("modelName"))
                .or_else(|| r.get("model_name"))
        }).and_then(|s| s.as_str());

        let req = v.get("request");
        let req_model = req.and_then(|r| {
            r.get("model")
                .or_else(|| r.get("modelId"))
                .or_else(|| r.get("model_id"))
                .or_else(|| r.get("modelName"))
                .or_else(|| r.get("model_name"))
        }).and_then(|s| s.as_str());

        let payload = v.get("payload");
        let payload_model = payload.and_then(|p| {
            p.get("model")
                .or_else(|| p.get("modelId"))
                .or_else(|| p.get("model_id"))
                .or_else(|| p.get("settings").and_then(|s| s.get("model")))
                .or_else(|| p.get("collaboration_mode").and_then(|c| c.get("settings")).and_then(|s| s.get("model")))
        }).and_then(|s| s.as_str());

        let ctx = v.get("context");
        let ctx_model = ctx.and_then(|c| {
            c.get("model")
                .or_else(|| c.get("modelId"))
                .or_else(|| c.get("model_id"))
                .or_else(|| c.get("modelName"))
                .or_else(|| c.get("model_name"))
        }).and_then(|s| s.as_str());

        let raw_m = direct_model.or(msg_model).or(resp_model).or(req_model).or(payload_model).or(ctx_model)?;
        let model = if let Some((prefix, rest)) = raw_m.split_once('/') {
            if prefix.len() == 36 && prefix.chars().all(|c| c.is_ascii_hexdigit() || c == '-') {
                rest
            } else {
                raw_m
            }
        } else {
            raw_m
        };

        let prov = v.get("provider")
            .or_else(|| msg.and_then(|m| m.get("provider")))
            .or_else(|| resp.and_then(|r| r.get("providerId").or_else(|| r.get("provider"))))
            .or_else(|| req.and_then(|r| r.get("providerId").or_else(|| r.get("provider"))))
            .or_else(|| payload.and_then(|p| p.get("provider").or_else(|| p.get("model_provider"))))
            .or_else(|| ctx.and_then(|c| c.get("providerId").or_else(|| c.get("provider"))))
            .and_then(|p| p.as_str())
            .unwrap_or("")
            .to_string();

        return Some((model.to_string(), prov));
    }

    // Fallback: fast substring extraction if line is partially truncated
    for key in &["\"modelId\":", "\"model_id\":", "\"model\":", "\"modelName\":", "\"model_name\":"] {
        if let Some(pos) = line.rfind(key) {
            let rem = &line[pos + key.len()..];
            let trimmed_rem = rem.trim_start();
            if let Some(quote_start) = trimmed_rem.find('"') {
                let inner = &trimmed_rem[quote_start + 1..];
                if let Some(quote_end) = inner.find('"') {
                    let raw_m = &inner[..quote_end];
                    let model = if let Some((prefix, rest)) = raw_m.split_once('/') {
                        if prefix.len() == 36 && prefix.chars().all(|c| c.is_ascii_hexdigit() || c == '-') {
                            rest
                        } else {
                            raw_m
                        }
                    } else {
                        raw_m
                    };
                    if !model.is_empty() {
                        return Some((model.to_string(), String::new()));
                    }
                }
            }
        }
    }

    None
}

pub fn extract_tokens_from_json_line(line: &str) -> Option<u64> {
    if let Ok(v) = serde_json::from_str::<serde_json::Value>(line) {
        if let Some(usage) = v.get("usage")
            .or_else(|| v.get("message").and_then(|m| m.get("usage")))
            .or_else(|| v.get("response").and_then(|r| r.get("usage")))
        {
            if let Some(tot) = usage.get("totalTokens").or_else(|| usage.get("total_tokens")).and_then(|t| t.as_u64()) {
                if tot > 0 {
                    return Some(tot);
                }
            }
            let input = usage.get("input")
                .or_else(|| usage.get("input_tokens"))
                .or_else(|| usage.get("inputTokens"))
                .or_else(|| usage.get("prompt_tokens"))
                .and_then(|t| t.as_u64())
                .unwrap_or(0);
            let output = usage.get("output")
                .or_else(|| usage.get("output_tokens"))
                .or_else(|| usage.get("outputTokens"))
                .or_else(|| usage.get("completion_tokens"))
                .and_then(|t| t.as_u64())
                .unwrap_or(0);
            if input + output > 0 {
                return Some(input + output);
            }
        }
        if let Some(payload) = v.get("payload") {
            if let Some(info) = payload.get("info") {
                if let Some(last_tok) = info.get("last_token_usage").and_then(|u| u.get("total_tokens")).and_then(|t| t.as_u64()) {
                    if last_tok > 0 {
                        return Some(last_tok);
                    }
                }
                if let Some(tot) = info.get("total_token_usage").and_then(|u| u.get("total_tokens")).and_then(|t| t.as_u64()) {
                    if tot > 0 {
                        return Some(tot);
                    }
                }
            }
        }
    }
    None
}

pub fn extract_tokens_from_tail(tail: &str) -> Option<u64> {
    for line in tail.lines().rev() {
        let trimmed = line.trim();
        if trimmed.is_empty() {
            continue;
        }
        if let Some(tok) = extract_tokens_from_json_line(trimmed) {
            return Some(tok);
        }
    }
    let last_len = tail.lines().rev().find(|l| !l.trim().is_empty()).map(|l| l.len()).unwrap_or(0);
    if last_len > 60 {
        Some(((last_len / 4) as u64).min(4096))
    } else {
        None
    }
}
