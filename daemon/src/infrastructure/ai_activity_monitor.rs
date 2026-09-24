use crate::domain::ai_activity::{resolve_model_metadata, AiActivityState};
use std::collections::HashMap;
use std::fs::File;
use std::io::{Read, Seek, SeekFrom};
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};
use tokio::sync::RwLock;

pub const ACTIVE_AGENT_WINDOW_MS: u64 = 35_000; // 35s active window (sustains active state during reasoning and tool execution)
pub const TRACK_RETENTION_MS: u64 = 120_000;    // 120s track retention for rolling metrics

/// Track state for an individual agent tool during concurrent execution.
#[derive(Debug, Clone)]
pub struct AgentTrack {
    pub identity: crate::domain::ai_activity::AiAgentIdentity,
    pub recent_events_window: Vec<u64>,
    pub recent_tokens_window: Vec<(u64, u64)>,
    pub last_event_epoch_ms: u64,
}

/// Tail reader that extracts the most recent model identifier in <0.1ms without loading entire files.
pub struct AiActivityMonitor {
    pub state: Arc<RwLock<AiActivityState>>,
    watch_descriptors: Arc<RwLock<HashMap<i32, PathBuf>>>,
    recent_events_window: Arc<RwLock<Vec<u64>>>,
    recent_tokens_window: Arc<RwLock<Vec<(u64, u64)>>>,
    agent_tracks: Arc<RwLock<HashMap<String, AgentTrack>>>,
}

impl Default for AiActivityMonitor {
    fn default() -> Self {
        Self::new()
    }
}

impl AiActivityMonitor {
    pub fn new() -> Self {
        Self {
            state: Arc::new(RwLock::new(AiActivityState::default())),
            watch_descriptors: Arc::new(RwLock::new(HashMap::new())),
            recent_events_window: Arc::new(RwLock::new(Vec::new())),
            recent_tokens_window: Arc::new(RwLock::new(Vec::new())),
            agent_tracks: Arc::new(RwLock::new(HashMap::new())),
        }
    }

    pub async fn get_state(&self) -> AiActivityState {
        self.state.read().await.clone()
    }

    /// Records a new request event for the specified model and tool, updating activity metrics.
    pub async fn record_activity(&self, raw_model: &str, tool_source: &str) {
        self.record_activity_with_tokens(raw_model, tool_source, None).await;
    }

    /// Records a new request event with optional token quantity, updating RPM and TPM metrics.
    pub async fn record_activity_with_tokens(&self, raw_model: &str, tool_source: &str, tokens: Option<u64>) {
        let now_ms = current_epoch_ms();
        let identity = resolve_model_metadata(raw_model, tool_source);

        // Update global rolling request rate window
        let mut window = self.recent_events_window.write().await;
        window.retain(|&t| now_ms.saturating_sub(t) < 60_000); // 60s rolling window
        window.push(now_ms);
        let rpm = window.len() as f64;

        // Update global rolling tokens window
        let mut tok_window = self.recent_tokens_window.write().await;
        tok_window.retain(|&(t, _)| now_ms.saturating_sub(t) < 60_000);
        if let Some(tok) = tokens {
            if tok > 0 {
                tok_window.push((now_ms, tok));
            }
        }
        let total_tokens: u64 = tok_window.iter().map(|&(_, cnt)| cnt).sum();
        let tpm = total_tokens as f64;

        // Update per-agent track using composite key (tool_source:model_id) so concurrent agents never overwrite each other
        let key = format!("{}:{}", identity.tool_source, identity.model_id);
        let mut tracks = self.agent_tracks.write().await;
        let track = tracks.entry(key).or_insert_with(|| AgentTrack {
            identity: identity.clone(),
            recent_events_window: Vec::new(),
            recent_tokens_window: Vec::new(),
            last_event_epoch_ms: now_ms,
        });
        track.identity = identity.clone();
        track.recent_events_window.retain(|&t| now_ms.saturating_sub(t) < 60_000);
        track.recent_events_window.push(now_ms);
        track.recent_tokens_window.retain(|&(t, _)| now_ms.saturating_sub(t) < 60_000);
        if let Some(tok) = tokens {
            if tok > 0 {
                track.recent_tokens_window.push((now_ms, tok));
            }
        }
        track.last_event_epoch_ms = now_ms;

        // Build active_agents list for any track active within the ACTIVE_AGENT_WINDOW_MS
        let mut active_slots = Vec::new();
        for (_, t) in tracks.iter_mut() {
            t.recent_events_window.retain(|&ev| now_ms.saturating_sub(ev) < 60_000);
            t.recent_tokens_window.retain(|&(ev, _)| now_ms.saturating_sub(ev) < 60_000);
            let agent_tokens: u64 = t.recent_tokens_window.iter().map(|&(_, c)| c).sum();
            if now_ms.saturating_sub(t.last_event_epoch_ms) < ACTIVE_AGENT_WINDOW_MS {
                active_slots.push(crate::domain::ai_activity::ActiveAgentSlot {
                    tool_source: t.identity.tool_source.clone(),
                    model_id: t.identity.model_id.clone(),
                    display_name: t.identity.display_name.clone(),
                    brand_color: t.identity.brand_color.clone(),
                    brand_icon: t.identity.brand_icon.clone(),
                    request_rate_rpm: t.recent_events_window.len() as f64,
                    token_rate_tpm: agent_tokens as f64,
                    recent_tokens: agent_tokens,
                    last_event_epoch_ms: t.last_event_epoch_ms,
                });
            }
        }
        // Sort with most recently active first
        active_slots.sort_by(|a, b| b.last_event_epoch_ms.cmp(&a.last_event_epoch_ms));

        let mut st = self.state.write().await;
        st.identity = identity;
        st.is_active = true;
        st.intensity = 1.0;
        st.request_rate_rpm = rpm;
        st.token_rate_tpm = tpm;
        st.recent_tokens = total_tokens;
        st.last_event_epoch_ms = now_ms;
        st.active_agents = active_slots;
    }

    /// Advances activity decay math. Returns `true` if state transitioned from active to inactive.
    pub async fn tick_decay(&self) -> bool {
        let now_ms = current_epoch_ms();
        let mut st = self.state.write().await;

        if !st.is_active {
            return false;
        }

        let elapsed = now_ms.saturating_sub(st.last_event_epoch_ms);

        // Decay global rolling windows
        let mut window = self.recent_events_window.write().await;
        window.retain(|&t| now_ms.saturating_sub(t) < 60_000);
        st.request_rate_rpm = window.len() as f64;

        let mut tok_window = self.recent_tokens_window.write().await;
        tok_window.retain(|&(t, _)| now_ms.saturating_sub(t) < 60_000);
        let total_tokens: u64 = tok_window.iter().map(|&(_, cnt)| cnt).sum();
        st.token_rate_tpm = total_tokens as f64;
        st.recent_tokens = total_tokens;

        // Decay per-agent tracks
        let mut tracks = self.agent_tracks.write().await;
        let mut active_slots = Vec::new();
        tracks.retain(|_, t| {
            t.recent_events_window.retain(|&ev| now_ms.saturating_sub(ev) < 60_000);
            t.recent_tokens_window.retain(|&(ev, _)| now_ms.saturating_sub(ev) < 60_000);
            now_ms.saturating_sub(t.last_event_epoch_ms) < TRACK_RETENTION_MS
        });

        for (_, t) in tracks.iter() {
            if now_ms.saturating_sub(t.last_event_epoch_ms) < ACTIVE_AGENT_WINDOW_MS {
                let agent_tokens: u64 = t.recent_tokens_window.iter().map(|&(_, c)| c).sum();
                active_slots.push(crate::domain::ai_activity::ActiveAgentSlot {
                    tool_source: t.identity.tool_source.clone(),
                    model_id: t.identity.model_id.clone(),
                    display_name: t.identity.display_name.clone(),
                    brand_color: t.identity.brand_color.clone(),
                    brand_icon: t.identity.brand_icon.clone(),
                    request_rate_rpm: t.recent_events_window.len() as f64,
                    token_rate_tpm: agent_tokens as f64,
                    recent_tokens: agent_tokens,
                    last_event_epoch_ms: t.last_event_epoch_ms,
                });
            }
        }
        active_slots.sort_by(|a, b| b.last_event_epoch_ms.cmp(&a.last_event_epoch_ms));
        let active_slots_changed = st.active_agents != active_slots;
        st.active_agents = active_slots.clone();

        if active_slots.is_empty() && elapsed > 15_000 {
            // Exponential decay after 15s idle when no agents are active
            st.intensity *= 0.50;
            if st.intensity < 0.05 {
                st.intensity = 0.0;
                st.is_active = false;
                st.request_rate_rpm = 0.0;
                st.token_rate_tpm = 0.0;
                st.recent_tokens = 0;
                st.active_agents.clear();
                return true; // Transitioned to inactive
            }
        }
        active_slots_changed
    }

    /// Reads up to `max_bytes` from the beginning of the file.
    pub fn read_head_string(path: &Path, max_bytes: usize) -> Option<String> {
        let mut file = File::open(path).ok()?;
        let len = file.metadata().ok()?.len();
        if len == 0 {
            return None;
        }

        let read_bytes = (max_bytes as u64).min(len);
        let mut buf = vec![0u8; read_bytes as usize];
        file.read_exact(&mut buf).ok()?;
        Some(String::from_utf8_lossy(&buf).to_string())
    }

    /// Reads up to `max_bytes` from the end of the file.
    pub fn read_tail_string(path: &Path, max_bytes: usize) -> Option<String> {
        let mut file = File::open(path).ok()?;
        let len = file.metadata().ok()?.len();
        if len == 0 {
            return None;
        }

        let seek_bytes = (max_bytes as u64).min(len);
        file.seek(SeekFrom::End(-(seek_bytes as i64))).ok()?;

        let mut buf = Vec::with_capacity(seek_bytes as usize);
        file.read_to_end(&mut buf).ok()?;
        Some(String::from_utf8_lossy(&buf).to_string())
    }

    /// Comprehensive file parser: examines tail, head (for initial model_change), and tool settings.
    pub fn parse_model_from_file(path: &Path) -> Option<(String, String)> {
        let path_hint = path.to_string_lossy();
        if path_hint.ends_with(".log")
            || path_hint.ends_with(".db")
            || path_hint.contains("context-mode")
            || path_hint.contains("stats-pid")
        {
            return None;
        }

        // Special handling for DSH: session.lock or session files
        if path_hint.contains(".dsh") {
            if let Some(dsh_defaults) = read_dsh_default_settings() {
                return Some(dsh_defaults);
            }
            return Some(("DSH Agent".to_string(), "dsh".to_string()));
        }

        if path_hint.ends_with(".lock") {
            return None;
        }

        if path_hint.contains("antigravity") && !path_hint.ends_with("transcript.jsonl") {
            return None;
        }

        // 1. Try reading tail (up to 32KB)
        if let Some(tail) = Self::read_tail_string(path, 32768) {
            for line in tail.lines().rev() {
                let trimmed = line.trim();
                if trimmed.is_empty() {
                    continue;
                }
                if let Some((m, prov)) = extract_model_from_json_line(trimmed) {
                    let prov = if prov.is_empty() && path_hint.contains(".codex") { "openai".to_string() } else { prov };
                    return Some((m, prov));
                }
            }
        }

        // 2. Try reading head (up to 8KB) - in pi and omp, session header has model_change on line 2
        if let Some(head) = Self::read_head_string(path, 8192) {
            for line in head.lines() {
                let trimmed = line.trim();
                if trimmed.is_empty() {
                    continue;
                }
                if let Some((m, prov)) = extract_model_from_json_line(trimmed) {
                    let prov = if prov.is_empty() && path_hint.contains(".codex") { "openai".to_string() } else { prov };
                    return Some((m, prov));
                }
            }
        }

        // 3. Fallback to tail keyword analysis or tool fallback
        if let Some(tail) = Self::read_tail_string(path, 32768) {
            if let Some(res) = Self::parse_model_from_tail(&tail, &path_hint) {
                return Some(res);
            }
        }

        // 4. Default settings fallback based on tool source
        let lower = path_hint.to_lowercase();
        if lower.contains(".pi") {
            if let Some(pi_defaults) = read_pi_default_settings() {
                return Some(pi_defaults);
            }
        } else if lower.contains(".codex") {
            if let Some(codex_defaults) = read_codex_default_settings() {
                return Some(codex_defaults);
            }
        } else if lower.contains(".dsh") {
            if let Some(dsh_defaults) = read_dsh_default_settings() {
                return Some(dsh_defaults);
            }
        }

        None
    }

    /// Comprehensive file parser: extracts active model, provider, and recent token throughput.
    pub fn parse_model_and_tokens_from_file(path: &Path) -> Option<(String, String, Option<u64>)> {
        let path_hint = path.to_string_lossy();
        if path_hint.ends_with(".log")
            || path_hint.ends_with(".db")
            || path_hint.contains("context-mode")
            || path_hint.contains("stats-pid")
        {
            return None;
        }

        if path_hint.contains("antigravity") && !path_hint.ends_with("transcript.jsonl") {
            return None;
        }

        let tail = Self::read_tail_string(path, 32768);
        let tokens = tail.as_deref().and_then(extract_tokens_from_tail);

        let (model, tool) = Self::parse_model_from_file(path)?;
        Some((model, tool, tokens))
    }

    /// Extracts the most recent model identifier from the tail of a session or log file.
    pub fn parse_model_from_tail(tail: &str, path_hint: &str) -> Option<(String, String)> {
        let hint_lower = path_hint.to_lowercase();
        let tool_source = if hint_lower.contains("claude") {
            "claude"
        } else if hint_lower.contains("codex") {
            "codex"
        } else if hint_lower.contains("antigravity") || hint_lower.contains("gemini") {
            "antigravity"
        } else if hint_lower.contains("opencode") {
            "opencode"
        } else if hint_lower.contains(".dsh") {
            "dsh"
        } else if hint_lower.contains("cursor") {
            "cursor"
        } else if hint_lower.contains("windsurf") {
            "windsurf"
        } else if hint_lower.contains(".omp") {
            "omp"
        } else if hint_lower.contains(".pi") {
            "pi"
        } else {
            "agent"
        };

        // Scan lines in reverse order to find the latest model change or usage message
        for line in tail.lines().rev() {
            let trimmed = line.trim();
            if trimmed.is_empty() {
                continue;
            }

            // Check for direct JSON structure
            if let Some((m, prov)) = extract_model_from_json_line(trimmed) {
                let resolved_tool = if !prov.is_empty() {
                    prov
                } else if tool_source == "codex" {
                    "openai".to_string()
                } else {
                    tool_source.to_string()
                };
                return Some((m, resolved_tool));
            }
        }

        // Antigravity special handling: check for "Model Selection" or planner steps
        if hint_lower.contains("antigravity") || hint_lower.contains("gemini") {
            for line in tail.lines().rev() {
                if let Some(pos) = line.find("Model Selection` from None to ") {
                    let rem = &line[pos + 30..];
                    let candidate = rem.split(['`', '\n', '\r']).next().unwrap_or("Gemini Flash 3.8").trim();
                    let clean = candidate.trim_end_matches('.').split('(').next().unwrap_or(candidate).trim();
                    if !clean.is_empty() && clean.len() < 30 && !clean.contains('\\') && !clean.contains('{') && !clean.contains("let ") {
                        let final_name = if clean == "Gemini Flash" {
                            "Gemini Flash 3.8".to_string()
                        } else if clean == "Gemini Pro" {
                            "Gemini Pro 3.8".to_string()
                        } else {
                            clean.to_string()
                        };
                        return Some((final_name, "gemini".to_string()));
                    }
                }
            }
            if let Some(state_model) = read_antigravity_state_model() {
                return Some((state_model, "gemini".to_string()));
            }
            return Some(("Gemini Flash 3.8".to_string(), "gemini".to_string()));
        }

        // Fallback by tool source if file was actively modified and verified settings exist
        match tool_source {
            "claude" => Some(("claude-3-7-sonnet".to_string(), "claude".to_string())),
            "pi" => read_pi_default_settings(),
            "codex" => read_codex_default_settings().or_else(|| Some(("gpt-5.5".to_string(), "openai".to_string()))),
            "antigravity" => Some(("Gemini Flash 3.8".to_string(), "gemini".to_string())),
            "dsh" => read_dsh_default_settings(),
            "cursor" => Some(("Cursor".to_string(), "cursor".to_string())),
            "windsurf" => Some(("Windsurf Cascade".to_string(), "windsurf".to_string())),
            _ => None,
        }
    }

    /// Extracts the latest session from OpenCode's SQLite database (~/.local/share/opencode/opencode.db).
    /// Returns (model_id, total_tokens, time_updated_ms).
    pub fn query_opencode_latest_session(home: &Path) -> Option<(String, u64, u64)> {
        let db_path = home.join(".local/share/opencode/opencode.db");
        if !db_path.exists() {
            return None;
        }

        let uri = format!("file:{}?mode=ro", db_path.to_string_lossy());
        let output = std::process::Command::new("sqlite3")
            .arg(&uri)
            .arg("SELECT model, tokens_input, tokens_output, time_updated FROM session_v2 ORDER BY time_updated DESC LIMIT 1;")
            .output()
            .ok()?;

        if !output.status.success() {
            return None;
        }

        let stdout = String::from_utf8_lossy(&output.stdout);
        let trimmed = stdout.trim();
        if trimmed.is_empty() {
            return None;
        }

        let parts: Vec<&str> = trimmed.split('|').collect();
        if parts.len() < 4 {
            return None;
        }

        let raw_model = parts[0].trim();
        let tokens_in: u64 = parts[1].trim().parse().unwrap_or(0);
        let tokens_out: u64 = parts[2].trim().parse().unwrap_or(0);
        let time_updated: u64 = parts[3].trim().parse().unwrap_or(0);

        let model_id = if raw_model.starts_with('{') {
            serde_json::from_str::<serde_json::Value>(raw_model)
                .ok()
                .and_then(|v| v.get("id").and_then(|id| id.as_str().map(|s| s.to_string())))
                .unwrap_or_else(|| raw_model.to_string())
        } else {
            raw_model.to_string()
        };

        Some((model_id, tokens_in + tokens_out, time_updated))
    }

    pub fn start_background_watcher(self: Arc<Self>) {
        tokio::spawn(async move {
            self.run_inotify_loop().await;
        });
    }

    pub async fn run_inotify_loop(&self) {
        let home = match std::env::var("HOME").ok().map(PathBuf::from) {
            Some(h) => h,
            None => return,
        };

        let mut candidate_dirs = vec![
            home.join(".pi/agent/sessions"),
            home.join(".claude"),
            home.join(".claude/sessions"),
            home.join(".claude/projects"),
            home.join(".codex"),
            home.join(".codex/sessions"),
            home.join(".dsh"),
            home.join(".dsh/sessions"),
            home.join(".omp/agent/sessions"),
            home.join(".local/share/opencode"),
            home.join(".config/ai.opencode.desktop"),
            home.join(".config/Cursor"),
            home.join(".config/Windsurf"),
        ];

        // Also add immediate subdirectories of sessions
        let session_roots = [
            home.join(".pi/agent/sessions"),
            home.join(".omp/agent/sessions"),
            home.join(".claude/sessions"),
            home.join(".claude/projects"),
            home.join(".codex/sessions"),
            home.join(".dsh/sessions"),
        ];
        for sroot in &session_roots {
            if sroot.exists() && sroot.is_dir() {
                scan_dirs_recursive(sroot, 3, &mut |p| candidate_dirs.push(p.to_path_buf()));
            }
        }

        // Antigravity transcripts live in ~/.gemini/antigravity/brain/<id>/.system_generated/logs
        let brain = home.join(".gemini/antigravity/brain");
        if brain.exists() && brain.is_dir() {
            if let Ok(entries) = std::fs::read_dir(&brain) {
                for e in entries.flatten() {
                    let logs = e.path().join(".system_generated/logs");
                    if logs.exists() && logs.is_dir() {
                        candidate_dirs.push(logs);
                    }
                }
            }
        }

        let inotify_fd = unsafe { libc::inotify_init1(libc::IN_NONBLOCK | libc::IN_CLOEXEC) };
        if inotify_fd < 0 {
            return;
        }

        let mut watch_map = HashMap::new();
        for dir in candidate_dirs {
            if !dir.exists() || !dir.is_dir() {
                continue;
            }
            if let Ok(c_str) = std::ffi::CString::new(dir.to_string_lossy().as_bytes()) {
                let wd = unsafe {
                    libc::inotify_add_watch(
                        inotify_fd,
                        c_str.as_ptr(),
                        libc::IN_MODIFY | libc::IN_CREATE | libc::IN_CLOSE_WRITE,
                    )
                };
                if wd >= 0 {
                    watch_map.insert(wd, dir);
                }
            }
        }

        {
            let mut wds = self.watch_descriptors.write().await;
            *wds = watch_map.clone();
        }

        let mut seen_sessions: HashMap<PathBuf, (u64, u64)> = HashMap::new();
        let mut last_seen_opencode_time: u64 = 0;
        let mut last_seen_opencode_tokens: u64 = 0;
        let mut last_seen_opencode_mtime: u64 = 0;
        let mut last_seen_opencode_size: u64 = 0;

        // Synchronize initial ground-truth state across all active agents
        let initial_active_files = Self::scan_all_active_session_files(&home, ACTIVE_AGENT_WINDOW_MS);
        for file_info in initial_active_files {
            seen_sessions.insert(file_info.path.clone(), (file_info.mtime, file_info.size));
            if let Some((model, tool, tokens)) = Self::parse_model_and_tokens_from_file(&file_info.path) {
                self.record_activity_with_tokens(&model, &tool, tokens).await;
            }
        }

        // OpenCode initial ground-truth check
        if let Some((model, tokens, time_updated)) = Self::query_opencode_latest_session(&home) {
            let now_epoch = current_epoch_ms();
            last_seen_opencode_time = time_updated;
            last_seen_opencode_tokens = tokens;
            if now_epoch.saturating_sub(time_updated) < ACTIVE_AGENT_WINDOW_MS {
                self.record_activity_with_tokens(&model, "opencode", Some(tokens)).await;
            }
        }

        // Fallback if completely idle: set identity from latest known session file
        if self.get_state().await.active_agents.is_empty() {
            if let Some((path, mtime, size)) = Self::find_latest_session_file(&home) {
                seen_sessions.insert(path.clone(), (mtime, size));
                if let Some((model, tool)) = Self::parse_model_from_file(&path) {
                    let mut st = self.state.write().await;
                    st.identity = crate::domain::ai_activity::resolve_model_metadata(&model, &tool);
                    st.is_active = false;
                    st.intensity = 0.0;
                    st.request_rate_rpm = 0.0;
                    st.token_rate_tpm = 0.0;
                    st.recent_tokens = 0;
                    st.last_event_epoch_ms = mtime;
                }
            }
        }
        emit_activity_payload(&self.get_state().await);

        let async_fd = match tokio::io::unix::AsyncFd::new(inotify_fd) {
            Ok(fd) => fd,
            Err(_) => {
                unsafe { libc::close(inotify_fd) };
                return;
            }
        };

        let mut decay_tick = tokio::time::interval(tokio::time::Duration::from_millis(500));
        let mut buffer = [0u8; 8192];

        loop {
            tokio::select! {
                guard_res = async_fd.readable() => {
                    let mut guard = match guard_res {
                        Ok(g) => g,
                        Err(_) => break,
                    };

                    loop {
                        let n = unsafe {
                            libc::read(inotify_fd, buffer.as_mut_ptr() as *mut libc::c_void, buffer.len())
                        };

                        if n < 0 {
                            let err = std::io::Error::last_os_error();
                            if err.raw_os_error() == Some(libc::EAGAIN) || err.raw_os_error() == Some(libc::EWOULDBLOCK) {
                                guard.clear_ready();
                                break;
                            } else {
                                guard.clear_ready();
                                eprintln!("[ai_activity_monitor] inotify fatal read error: {}", err);
                                return;
                            }
                        }

                        if n == 0 {
                            guard.clear_ready();
                            return;
                        }

                        let mut offset = 0usize;
                        let bytes_read = n as usize;
                        while offset + std::mem::size_of::<libc::inotify_event>() <= bytes_read {
                            let event = unsafe {
                                &*(buffer.as_ptr().add(offset) as *const libc::inotify_event)
                            };

                            let name_len = event.len as usize;
                            if name_len > 0 && offset + std::mem::size_of::<libc::inotify_event>() + name_len <= bytes_read {
                                let name_bytes = &buffer[offset + std::mem::size_of::<libc::inotify_event>()..offset + std::mem::size_of::<libc::inotify_event>() + name_len];
                                let name_str = String::from_utf8_lossy(name_bytes).trim_matches('\0').to_string();

                                if let Some(dir) = watch_map.get(&event.wd).cloned() {
                                    let full_path = dir.join(&name_str);

                                    // Check for new subdirectory creation
                                    if event.mask & libc::IN_ISDIR != 0 && full_path.is_dir() {
                                        if let Ok(c_str) = std::ffi::CString::new(full_path.to_string_lossy().as_bytes()) {
                                            let new_wd = unsafe {
                                                libc::inotify_add_watch(
                                                    inotify_fd,
                                                    c_str.as_ptr(),
                                                    libc::IN_MODIFY | libc::IN_CREATE | libc::IN_CLOSE_WRITE,
                                                )
                                            };
                                            if new_wd >= 0 {
                                                watch_map.insert(new_wd, full_path.clone());
                                                let mut wds = self.watch_descriptors.write().await;
                                                *wds = watch_map.clone();
                                            }
                                        }
                                    } else if name_str.starts_with("opencode.db") {
                                        let is_fresh = full_path.metadata().ok()
                                            .and_then(|m| m.modified().ok())
                                            .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
                                            .map(|d| current_epoch_ms().saturating_sub(d.as_millis() as u64) < ACTIVE_AGENT_WINDOW_MS)
                                            .unwrap_or(false);
                                        if is_fresh {
                                            if let Some((model, tokens, time_updated)) = Self::query_opencode_latest_session(&home) {
                                                let now_epoch = current_epoch_ms();
                                                if now_epoch.saturating_sub(time_updated) < ACTIVE_AGENT_WINDOW_MS
                                                    && (time_updated > last_seen_opencode_time || tokens != last_seen_opencode_tokens)
                                                {
                                                    let delta = tokens.saturating_sub(last_seen_opencode_tokens);
                                                    last_seen_opencode_time = time_updated;
                                                    last_seen_opencode_tokens = tokens;
                                                    let reported = if delta > 0 { delta } else { tokens.min(5000) };
                                                    self.record_activity_with_tokens(&model, "opencode", Some(reported)).await;
                                                    let curr = self.get_state().await;
                                                    emit_activity_payload(&curr);
                                                }
                                            }
                                        }
                                    } else if name_str.ends_with(".jsonl") || name_str.ends_with(".log") || name_str == "session.lock" {
                                        if (name_str.contains("antigravity") || full_path.to_string_lossy().contains("antigravity")) && name_str != "transcript.jsonl" {
                                            offset += std::mem::size_of::<libc::inotify_event>() + name_len;
                                            continue;
                                        }
                                        let is_fresh = full_path.metadata().ok()
                                            .and_then(|m| m.modified().ok())
                                            .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
                                            .map(|d| current_epoch_ms().saturating_sub(d.as_millis() as u64) < ACTIVE_AGENT_WINDOW_MS)
                                            .unwrap_or(false);
                                        if is_fresh {
                                            if let Some((model, tool, tokens)) = Self::parse_model_and_tokens_from_file(&full_path) {
                                                self.record_activity_with_tokens(&model, &tool, tokens).await;
                                                let curr = self.get_state().await;
                                                emit_activity_payload(&curr);
                                            }
                                        }
                                    }
                                }
                            }
                            offset += std::mem::size_of::<libc::inotify_event>() + name_len;
                        }
                    }
                }
                _ = decay_tick.tick() => {
                    let mut should_emit = false;

                    // 1. Resilient concurrent poll: scan ALL active sessions across all agent tools
                    let active_files = Self::scan_all_active_session_files(&home, ACTIVE_AGENT_WINDOW_MS);
                    for file_info in active_files {
                        let prev = seen_sessions.get(&file_info.path).copied();
                        let is_new_event = match prev {
                            None => true,
                            Some((prev_mtime, prev_size)) => file_info.mtime > prev_mtime || file_info.size != prev_size,
                        };
                        if is_new_event {
                            seen_sessions.insert(file_info.path.clone(), (file_info.mtime, file_info.size));
                            if let Some((model, tool, tokens)) = Self::parse_model_and_tokens_from_file(&file_info.path) {
                                self.record_activity_with_tokens(&model, &tool, tokens).await;
                                should_emit = true;
                            }
                        }
                    }

                    // 2. Resilient poll: check OpenCode database updates
                    let opencode_wal = home.join(".local/share/opencode/opencode.db-wal");
                    let opencode_db = home.join(".local/share/opencode/opencode.db");
                    let wal_target = if opencode_wal.exists() { &opencode_wal } else { &opencode_db };
                    if let Ok(meta) = wal_target.metadata() {
                        let mtime = meta.modified().ok()
                            .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
                            .map(|d| d.as_millis() as u64)
                            .unwrap_or(0);
                        let size = meta.len();
                        if mtime > last_seen_opencode_mtime || size != last_seen_opencode_size {
                            last_seen_opencode_mtime = mtime;
                            last_seen_opencode_size = size;
                            if let Some((model, tokens, time_updated)) = Self::query_opencode_latest_session(&home) {
                                let now_epoch = current_epoch_ms();
                                if now_epoch.saturating_sub(time_updated) < ACTIVE_AGENT_WINDOW_MS {
                                    if time_updated > last_seen_opencode_time || tokens != last_seen_opencode_tokens {
                                        let delta = tokens.saturating_sub(last_seen_opencode_tokens);
                                        last_seen_opencode_time = time_updated;
                                        last_seen_opencode_tokens = tokens;
                                        let reported = if delta > 0 { delta } else { tokens.min(5000) };
                                        self.record_activity_with_tokens(&model, "opencode", Some(reported)).await;
                                        should_emit = true;
                                    }
                                }
                            }
                        }
                    }

                    // 3. Advance decay and prune inactive agents; emit payload if slots changed
                    let transitioned_or_changed = self.tick_decay().await;
                    if should_emit || transitioned_or_changed {
                        let curr = self.get_state().await;
                        emit_activity_payload(&curr);
                    }
                }
            }
        }

        unsafe { libc::close(inotify_fd) };
    }

    /// Scans the newest session or log file across all known AI agents.
    pub fn find_latest_session_file(home: &Path) -> Option<(PathBuf, u64, u64)> {
        let mut candidates = Vec::new();

        // 1. Antigravity brain transcripts
        let brain = home.join(".gemini/antigravity/brain");
        if let Ok(dirs) = std::fs::read_dir(&brain) {
            for d in dirs.flatten() {
                let p = d.path();
                if p.is_dir() {
                    let log_p = p.join(".system_generated/logs/transcript.jsonl");
                    if log_p.exists() {
                        candidates.push(log_p);
                    }
                }
            }
        }

        // 2. Pi agent sessions (purely real .jsonl session files, context-mode stats excluded)
        let pi_sessions = home.join(".pi/agent/sessions");
        if let Ok(dirs) = std::fs::read_dir(&pi_sessions) {
            for d in dirs.flatten() {
                let p = d.path();
                if p.is_dir() {
                    if let Ok(files) = std::fs::read_dir(&p) {
                        for f in files.flatten() {
                            let fp = f.path();
                            if fp.extension().and_then(|s| s.to_str()) == Some("jsonl") {
                                candidates.push(fp);
                            }
                        }
                    }
                } else if p.extension().and_then(|s| s.to_str()) == Some("jsonl") {
                    candidates.push(p);
                }
            }
        }

        // 3. OMP agent sessions
        let omp_sessions = home.join(".omp/agent/sessions");
        if let Ok(dirs) = std::fs::read_dir(&omp_sessions) {
            for d in dirs.flatten() {
                let p = d.path();
                if p.is_dir() {
                    if let Ok(files) = std::fs::read_dir(&p) {
                        for f in files.flatten() {
                            let fp = f.path();
                            if fp.extension().and_then(|s| s.to_str()) == Some("jsonl") {
                                candidates.push(fp);
                            }
                        }
                    }
                }
            }
        }

        // 4. Claude projects and sessions
        let claude_projects = home.join(".claude/projects");
        if let Ok(dirs) = std::fs::read_dir(&claude_projects) {
            for d in dirs.flatten() {
                let p = d.path();
                if p.is_dir() {
                    if let Ok(files) = std::fs::read_dir(&p) {
                        for f in files.flatten() {
                            let fp = f.path();
                            if fp.extension().and_then(|s| s.to_str()) == Some("jsonl") {
                                candidates.push(fp);
                            }
                        }
                    }
                }
            }
        }

        // 5. Codex rollout sessions & history
        let codex_sessions = home.join(".codex/sessions");
        if codex_sessions.exists() {
            scan_jsonl_recursive(&codex_sessions, 4, &mut |p| candidates.push(p.to_path_buf()));
        }
        let codex_history = home.join(".codex/history.jsonl");
        if codex_history.exists() {
            candidates.push(codex_history);
        }

        // 6. DSH sessions
        let dsh_sessions = home.join(".dsh/sessions");
        if dsh_sessions.exists() {
            if let Ok(dirs) = std::fs::read_dir(&dsh_sessions) {
                for d in dirs.flatten() {
                    let p = d.path();
                    if p.is_dir() {
                        if let Ok(sub) = std::fs::read_dir(&p) {
                            for s in sub.flatten() {
                                let sp = s.path();
                                if sp.is_dir() {
                                    let lock = sp.join("session.lock");
                                    if lock.exists() {
                                        candidates.push(lock);
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        let mut newest_time = 0u64;
        let mut newest_entry = None;

        for path in candidates {
            if let Ok(meta) = path.metadata() {
                if let Ok(mtime) = meta.modified() {
                    let epoch = mtime.duration_since(std::time::UNIX_EPOCH).unwrap_or_default().as_millis() as u64;
                    if epoch > newest_time {
                        newest_time = epoch;
                        newest_entry = Some((path, epoch, meta.len()));
                    }
                }
            }
        }

        newest_entry
    }

    /// Scans all active session files modified within `max_age_ms` across all supported agent tools.
    pub fn scan_all_active_session_files(home: &Path, max_age_ms: u64) -> Vec<ActiveSessionFile> {
        let now = current_epoch_ms();
        let mut files = Vec::new();

        let mut check_file = |p: &Path| {
            if let Ok(meta) = p.metadata() {
                if let Ok(mtime) = meta.modified() {
                    let epoch = mtime.duration_since(std::time::UNIX_EPOCH).unwrap_or_default().as_millis() as u64;
                    if now.saturating_sub(epoch) < max_age_ms {
                        files.push(ActiveSessionFile {
                            path: p.to_path_buf(),
                            mtime: epoch,
                            size: meta.len(),
                        });
                    }
                }
            }
        };

        // 1. Antigravity brain transcripts
        let brain = home.join(".gemini/antigravity/brain");
        if let Ok(dirs) = std::fs::read_dir(&brain) {
            for d in dirs.flatten() {
                let p = d.path();
                if p.is_dir() {
                    let log_p = p.join(".system_generated/logs/transcript.jsonl");
                    if log_p.exists() {
                        check_file(&log_p);
                    }
                }
            }
        }

        // 2. Pi agent sessions
        let pi_sessions = home.join(".pi/agent/sessions");
        if pi_sessions.exists() {
            scan_jsonl_recursive(&pi_sessions, 3, &mut check_file);
        }

        // 3. OMP agent sessions
        let omp_sessions = home.join(".omp/agent/sessions");
        if omp_sessions.exists() {
            scan_jsonl_recursive(&omp_sessions, 3, &mut check_file);
        }

        // 4. Claude projects and sessions
        let claude_projects = home.join(".claude/projects");
        if claude_projects.exists() {
            scan_jsonl_recursive(&claude_projects, 3, &mut check_file);
        }
        let claude_sessions = home.join(".claude/sessions");
        if claude_sessions.exists() {
            scan_jsonl_recursive(&claude_sessions, 2, &mut check_file);
        }
        let claude_history = home.join(".claude/history.jsonl");
        if claude_history.exists() {
            check_file(&claude_history);
        }

        // 5. Codex rollout sessions & history
        let codex_sessions = home.join(".codex/sessions");
        if codex_sessions.exists() {
            scan_jsonl_recursive(&codex_sessions, 4, &mut check_file);
        }
        let codex_history = home.join(".codex/history.jsonl");
        if codex_history.exists() {
            check_file(&codex_history);
        }

        // 6. DSH sessions
        let dsh_sessions = home.join(".dsh/sessions");
        if dsh_sessions.exists() {
            if let Ok(dirs) = std::fs::read_dir(&dsh_sessions) {
                for d in dirs.flatten() {
                    let p = d.path();
                    if p.is_dir() {
                        if let Ok(sub) = std::fs::read_dir(&p) {
                            for s in sub.flatten() {
                                let sp = s.path();
                                if sp.is_dir() {
                                    let lock = sp.join("session.lock");
                                    if lock.exists() {
                                        check_file(&lock);
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        files
    }
}

pub fn emit_activity_payload(st: &AiActivityState) {
    let payload = serde_json::json!({
        "msg_type": "ai_activity",
        "agent": st.identity.tool_source,
        "model": st.identity.model_id,
        "display_name": st.identity.display_name,
        "brand_color": st.identity.brand_color,
        "brand_icon": st.identity.brand_icon,
        "is_active": st.is_active,
        "intensity": (st.intensity * 100.0).round() / 100.0,
        "request_rate": st.request_rate_rpm,
        "token_rate": st.token_rate_tpm,
        "recent_tokens": st.recent_tokens,
        "active_agents": st.active_agents,
    });
    if let Ok(s) = serde_json::to_string(&payload) {
        println!("{}", s);
    }
}

/// Active session file descriptor for concurrent multi-agent tracking.
#[derive(Debug, Clone)]
pub struct ActiveSessionFile {
    pub path: PathBuf,
    pub mtime: u64,
    pub size: u64,
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
            } else if let Some(ext) = path.extension().and_then(|s| s.to_str()) {
                if ext == "jsonl" || ext == "lock" {
                    callback(&path);
                }
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

/// Helper to extract token usage from a JSON line (supports pi, omp, claude, codex, openai formats).
pub fn extract_tokens_from_json_line(line: &str) -> Option<u64> {
    if let Ok(v) = serde_json::from_str::<serde_json::Value>(line) {
        // Standard message/usage format (Claude, Pi, OMP, OpenCode)
        if let Some(usage) = v.get("usage").or_else(|| v.get("message").and_then(|m| m.get("usage"))) {
            if let Some(tot) = usage.get("totalTokens").or_else(|| usage.get("total_tokens")).and_then(|t| t.as_u64()) {
                if tot > 0 {
                    return Some(tot);
                }
            }
            let input = usage.get("input").or_else(|| usage.get("input_tokens")).or_else(|| usage.get("prompt_tokens")).and_then(|t| t.as_u64()).unwrap_or(0);
            let output = usage.get("output").or_else(|| usage.get("output_tokens")).or_else(|| usage.get("completion_tokens")).and_then(|t| t.as_u64()).unwrap_or(0);
            if input + output > 0 {
                return Some(input + output);
            }
        }
        // Codex event_msg token_count format
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

/// Helper to scan tail lines for token usage or estimate from line length.
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

/// Helper to parse a single JSON line and extract model and provider.
pub fn extract_model_from_json_line(line: &str) -> Option<(String, String)> {
    let lower = line.to_lowercase();
    if !lower.contains("model") {
        return None;
    }

    if let Ok(v) = serde_json::from_str::<serde_json::Value>(line) {
        // Direct model field (supports model, modelId, model_id, modelName, model_name)
        let direct_model = v.get("model")
            .or_else(|| v.get("modelId"))
            .or_else(|| v.get("model_id"))
            .or_else(|| v.get("modelName"))
            .or_else(|| v.get("model_name"))
            .and_then(|s| s.as_str());

        // Nested message.model or message.modelId
        let msg = v.get("message");
        let msg_model = msg.and_then(|m| {
            m.get("model")
                .or_else(|| m.get("modelId"))
                .or_else(|| m.get("model_id"))
                .or_else(|| m.get("modelName"))
                .or_else(|| m.get("model_name"))
        }).and_then(|s| s.as_str());

        // Nested payload.model or payload.settings.model or payload.collaboration_mode.settings.model (Codex)
        let payload = v.get("payload");
        let payload_model = payload.and_then(|p| {
            p.get("model")
                .or_else(|| p.get("modelId"))
                .or_else(|| p.get("model_id"))
                .or_else(|| p.get("settings").and_then(|s| s.get("model")))
                .or_else(|| p.get("collaboration_mode").and_then(|c| c.get("settings")).and_then(|s| s.get("model")))
        }).and_then(|s| s.as_str());

        let model = direct_model.or(msg_model).or(payload_model)?;

        let prov = v.get("provider")
            .or_else(|| msg.and_then(|m| m.get("provider")))
            .or_else(|| payload.and_then(|p| p.get("provider").or_else(|| p.get("model_provider"))))
            .and_then(|p| p.as_str())
            .unwrap_or("")
            .to_string();

        return Some((model.to_string(), prov));
    }

    // Fallback: fast regex/substring extraction if line is partially truncated
    for key in &["\"modelId\":", "\"model_id\":", "\"model\":", "\"modelName\":", "\"model_name\":"] {
        if let Some(pos) = line.rfind(key) {
            let rem = &line[pos + key.len()..];
            let trimmed_rem = rem.trim_start();
            if let Some(quote_start) = trimmed_rem.find('"') {
                let inner = &trimmed_rem[quote_start + 1..];
                if let Some(quote_end) = inner.find('"') {
                    let model = &inner[..quote_end];
                    if !model.is_empty() {
                        return Some((model.to_string(), String::new()));
                    }
                }
            }
        }
    }

    None
}

/// Reads default model and provider configured in ~/.pi/agent/settings.json
pub fn read_pi_default_settings() -> Option<(String, String)> {
    let home = std::env::var("HOME").ok()?;
    let settings_path = PathBuf::from(home).join(".pi/agent/settings.json");
    if let Ok(content) = std::fs::read_to_string(&settings_path) {
        if let Ok(v) = serde_json::from_str::<serde_json::Value>(&content) {
            let model = v.get("defaultModel").and_then(|s| s.as_str())?;
            let prov = v.get("defaultProvider").and_then(|s| s.as_str()).unwrap_or("opencode-go");
            return Some((model.to_string(), prov.to_string()));
        }
    }
    None
}

/// Reads default model configured in ~/.dsh/settings.yaml
pub fn read_dsh_default_settings() -> Option<(String, String)> {
    let home = std::env::var("HOME").ok()?;
    let settings_path = PathBuf::from(home).join(".dsh/settings.yaml");
    if let Ok(content) = std::fs::read_to_string(&settings_path) {
        let mut in_agent_default = false;
        for line in content.lines() {
            let trimmed = line.trim();
            if trimmed.starts_with("agent-default-model:") {
                in_agent_default = true;
                continue;
            }
            if in_agent_default {
                if !line.starts_with(' ') && !line.starts_with('\t') {
                    break;
                }
                if let Some(m) = trimmed.strip_prefix("model:") {
                    let m_clean = m.trim().trim_matches('"').trim_matches('\'');
                    if !m_clean.is_empty() {
                        return Some((m_clean.to_string(), "dsh".to_string()));
                    }
                }
            }
        }
    }
    None
}

/// Reads default model configured in ~/.codex/config.toml
pub fn read_codex_default_settings() -> Option<(String, String)> {
    let home = std::env::var("HOME").ok()?;
    let config_path = PathBuf::from(home).join(".codex/config.toml");
    if let Ok(content) = std::fs::read_to_string(&config_path) {
        for line in content.lines() {
            let trimmed = line.trim();
            if trimmed.starts_with("model ") || trimmed.starts_with("model=") {
                if let Some(val) = trimmed.split('=').nth(1) {
                    let clean = val.trim().trim_matches('"').trim_matches('\'').trim();
                    if !clean.is_empty() {
                        return Some((clean.to_string(), "openai".to_string()));
                    }
                }
            }
        }
    }
    Some(("gpt-5.5".to_string(), "openai".to_string()))
}

/// Reads active model configured in ~/.gemini/antigravity/antigravity_state.pbtxt
pub fn read_antigravity_state_model() -> Option<String> {
    let home = std::env::var("HOME").ok()?;
    let pbtxt_path = PathBuf::from(home).join(".gemini/antigravity/antigravity_state.pbtxt");
    if let Ok(content) = std::fs::read_to_string(&pbtxt_path) {
        for line in content.lines() {
            if line.contains("last_selected_agent_model:") {
                if let Some(val) = line.split(':').nth(1) {
                    let trimmed = val.trim();
                    if trimmed.contains("M318") {
                        return Some("Gemini Flash 3.8".to_string());
                    } else if trimmed.contains("PRO") {
                        return Some("Gemini Pro 3.8".to_string());
                    } else if trimmed.contains("25") || trimmed.contains("2_5") {
                        return Some("Gemini Flash 2.5".to_string());
                    }
                }
            }
        }
    }
    None
}

fn current_epoch_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as u64
}
