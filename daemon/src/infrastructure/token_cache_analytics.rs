use crate::domain::ai_quota::TokenCacheStats;
use std::collections::HashMap;
use std::fs::File;
use std::io::{BufRead, BufReader};
use std::path::PathBuf;

pub struct TokenCacheAnalytics;

impl TokenCacheAnalytics {
    fn get_home() -> Option<PathBuf> {
        std::env::var("HOME").ok().map(PathBuf::from)
    }

    /// Scans agent tool sessions (Pi, OpenCode, etc.) and calculates real-world
    /// token prompt cache hit rates globally and per-provider.
    pub fn calculate_stats() -> (TokenCacheStats, HashMap<String, TokenCacheStats>) {
        let mut provider_stats: HashMap<String, (u64, u64, u64)> = HashMap::new(); // provider -> (cached, uncached, output)
        let mut global_cached = 0u64;
        let mut global_uncached = 0u64;
        let mut global_output = 0u64;

        if let Some(home) = Self::get_home() {
            let pi_sessions_dir = home.join(".pi/agent/sessions");
            if pi_sessions_dir.exists() {
                Self::scan_pi_sessions(
                    &pi_sessions_dir,
                    &mut provider_stats,
                    &mut global_cached,
                    &mut global_uncached,
                    &mut global_output,
                );
            }
        }

        let global_prompt = global_cached + global_uncached;
        let global_hit_rate = if global_prompt > 0 {
            (global_cached as f64 / global_prompt as f64) * 100.0
        } else {
            0.0
        };

        let global_stats = TokenCacheStats {
            cached_tokens: global_cached,
            uncached_input_tokens: global_uncached,
            output_tokens: global_output,
            total_prompt_tokens: global_prompt,
            cache_hit_rate_percent: (global_hit_rate * 100.0).round() / 100.0,
        };

        let mut per_provider: HashMap<String, TokenCacheStats> = HashMap::new();
        for (prov, (cached, uncached, output)) in provider_stats {
            let prompt = cached + uncached;
            let hit_rate = if prompt > 0 {
                (cached as f64 / prompt as f64) * 100.0
            } else {
                0.0
            };
            per_provider.insert(
                prov,
                TokenCacheStats {
                    cached_tokens: cached,
                    uncached_input_tokens: uncached,
                    output_tokens: output,
                    total_prompt_tokens: prompt,
                    cache_hit_rate_percent: (hit_rate * 100.0).round() / 100.0,
                },
            );
        }

        (global_stats, per_provider)
    }

    fn normalize_provider(raw: &str) -> String {
        let p = raw.trim().to_lowercase();
        if p.contains("minimax") {
            "minimax-cn".to_string()
        } else if p.contains("opencode") {
            "opencode-go".to_string()
        } else if p.contains("gemini") {
            "gemini".to_string()
        } else if p.contains("mimo") || p.contains("xiaomi") {
            "xiaomi-mimo-cn".to_string()
        } else {
            p
        }
    }

    fn scan_pi_sessions(
        sessions_dir: &std::path::Path,
        provider_stats: &mut HashMap<String, (u64, u64, u64)>,
        global_cached: &mut u64,
        global_uncached: &mut u64,
        global_output: &mut u64,
    ) {
        let subdirs = match std::fs::read_dir(sessions_dir) {
            Ok(dirs) => dirs,
            Err(_) => return,
        };

        for entry in subdirs.flatten() {
            let path = entry.path();
            if path.is_dir() {
                if let Ok(files) = std::fs::read_dir(&path) {
                    for f in files.flatten() {
                        let fp = f.path();
                        if fp.extension().and_then(|s| s.to_str()) == Some("jsonl") {
                            Self::parse_jsonl_session(
                                &fp,
                                provider_stats,
                                global_cached,
                                global_uncached,
                                global_output,
                            );
                        }
                    }
                }
            } else if path.extension().and_then(|s| s.to_str()) == Some("jsonl") {
                Self::parse_jsonl_session(
                    &path,
                    provider_stats,
                    global_cached,
                    global_uncached,
                    global_output,
                );
            }
        }
    }

    fn parse_jsonl_session(
        file_path: &std::path::Path,
        provider_stats: &mut HashMap<String, (u64, u64, u64)>,
        global_cached: &mut u64,
        global_uncached: &mut u64,
        global_output: &mut u64,
    ) {
        let file = match File::open(file_path) {
            Ok(f) => f,
            Err(_) => return,
        };
        let reader = BufReader::new(file);

        for line in reader.lines().flatten() {
            if !line.contains("\"usage\"") {
                continue;
            }
            if let Ok(val) = serde_json::from_str::<serde_json::Value>(&line) {
                let msg = val.get("message");
                let usage = msg
                    .and_then(|m| m.get("usage"))
                    .or_else(|| val.get("usage"));

                if let Some(u) = usage {
                    let input = u.get("input").and_then(|v| v.as_u64()).unwrap_or(0);
                    let cache_read = u.get("cacheRead").and_then(|v| v.as_u64()).unwrap_or(0);
                    let output = u.get("output").and_then(|v| v.as_u64()).unwrap_or(0);

                    let raw_provider = msg
                        .and_then(|m| m.get("provider").and_then(|p| p.as_str()))
                        .or_else(|| val.get("provider").and_then(|p| p.as_str()))
                        .unwrap_or("unknown");

                    let norm_provider = Self::normalize_provider(raw_provider);

                    *global_cached += cache_read;
                    *global_uncached += input;
                    *global_output += output;

                    let entry = provider_stats
                        .entry(norm_provider)
                        .or_insert((0u64, 0u64, 0u64));
                    entry.0 += cache_read;
                    entry.1 += input;
                    entry.2 += output;
                }
            }
        }
    }
}
