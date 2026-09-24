use crate::domain::ai_activity::{resolve_model_metadata, AiActivityState};
use std::collections::HashMap;
use std::fs::File;
use std::io::{Read, Seek, SeekFrom};
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};
use tokio::sync::RwLock;

/// Tail reader that extracts the most recent model identifier in <0.1ms without loading entire files.
pub struct AiActivityMonitor {
    pub state: Arc<RwLock<AiActivityState>>,
    watch_descriptors: Arc<RwLock<HashMap<i32, PathBuf>>>,
    recent_events_window: Arc<RwLock<Vec<u64>>>,
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
        }
    }

    pub async fn get_state(&self) -> AiActivityState {
        self.state.read().await.clone()
    }

    /// Records a new request event for the specified model and tool, updating activity metrics.
    pub async fn record_activity(&self, raw_model: &str, tool_source: &str) {
        let now_ms = current_epoch_ms();
        let identity = resolve_model_metadata(raw_model, tool_source);

        // Update rolling request rate window
        let mut window = self.recent_events_window.write().await;
        window.retain(|&t| now_ms.saturating_sub(t) < 60_000); // 60s rolling window
        window.push(now_ms);
        let rpm = window.len() as f64;

        let mut st = self.state.write().await;
        st.identity = identity;
        st.is_active = true;
        st.intensity = 1.0;
        st.request_rate_rpm = rpm;
        st.last_event_epoch_ms = now_ms;
    }

    /// Advances activity decay math. Returns `true` if state transitioned from active to inactive.
    pub async fn tick_decay(&self) -> bool {
        let now_ms = current_epoch_ms();
        let mut st = self.state.write().await;

        if !st.is_active {
            return false;
        }

        let elapsed = now_ms.saturating_sub(st.last_event_epoch_ms);

        // Decay rolling window
        let mut window = self.recent_events_window.write().await;
        window.retain(|&t| now_ms.saturating_sub(t) < 60_000);
        st.request_rate_rpm = window.len() as f64;

        if elapsed > 12000 {
            // Exponential decay after 12s idle
            st.intensity *= 0.80;
            if st.intensity < 0.05 {
                st.intensity = 0.0;
                st.is_active = false;
                return true; // Transitioned to inactive
            }
        }
        false
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

        // 1. Try reading tail (up to 32KB)
        if let Some(tail) = Self::read_tail_string(path, 32768) {
            for line in tail.lines().rev() {
                let trimmed = line.trim();
                if trimmed.is_empty() {
                    continue;
                }
                if let Some((m, prov)) = extract_model_from_json_line(trimmed) {
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
        }

        None
    }

    /// Extracts the most recent model identifier from the tail of a session or log file.
    pub fn parse_model_from_tail(tail: &str, path_hint: &str) -> Option<(String, String)> {
        let hint_lower = path_hint.to_lowercase();
        let tool_source = if hint_lower.contains("claude") {
            "claude"
        } else if hint_lower.contains("codex") {
            "codex"
        } else if hint_lower.contains("opencode") {
            "opencode"
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
                let resolved_tool = if !prov.is_empty() { prov } else { tool_source.to_string() };
                return Some((m, resolved_tool));
            }
        }

        // Keyword detection in recent lines
        let lower_tail = tail.to_lowercase();
        if lower_tail.contains("mimo") {
            return Some(("mimo-v2.6-flash".to_string(), "mimo".to_string()));
        } else if lower_tail.contains("muse") || lower_tail.contains("spark") {
            return Some(("muse-spark-1.2".to_string(), "meta".to_string()));
        } else if lower_tail.contains("grok") {
            return Some(("grok-3".to_string(), "grok".to_string()));
        } else if lower_tail.contains("ollama") {
            return Some(("ollama-cloud/deepseek-v4-flash".to_string(), "ollama".to_string()));
        }

        // Fallback by tool source if file was actively modified
        match tool_source {
            "claude" => Some(("claude-3-7-sonnet".to_string(), "claude".to_string())),
            "pi" => read_pi_default_settings().or_else(|| Some(("mimo-v2.6-flash".to_string(), "opencode-go".to_string()))),
            "omp" => Some(("mimo-v2.6-flash".to_string(), "mimo".to_string())),
            "codex" => Some(("gpt-4o".to_string(), "openai".to_string())),
            "opencode" => Some(("mimo-v2.6-flash".to_string(), "mimo".to_string())),
            _ => None,
        }
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
            home.join(".codex"),
            home.join(".codex/sessions"),
            home.join(".local/share/opencode/log"),
            home.join(".omp/agent/sessions"),
        ];

        // Also add immediate subdirectories of sessions
        let session_roots = [
            home.join(".pi/agent/sessions"),
            home.join(".omp/agent/sessions"),
            home.join(".claude/sessions"),
            home.join(".claude/projects"),
        ];
        for sroot in &session_roots {
            if sroot.exists() && sroot.is_dir() {
                if let Ok(entries) = std::fs::read_dir(sroot) {
                    for e in entries.flatten() {
                        let p = e.path();
                        if p.is_dir() {
                            candidate_dirs.push(p);
                        }
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
                        libc::IN_MODIFY | libc::IN_CREATE | libc::IN_CLOSE_WRITE | libc::IN_ATTRIB,
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

        let mut last_seen_file: Option<PathBuf> = None;
        let mut last_seen_mtime: u64 = current_epoch_ms();
        let mut last_seen_size: u64 = 0;

        // Synchronize initial ground-truth state immediately
        if let Some((path, mtime, size)) = Self::find_latest_session_file(&home) {
            let now_epoch = current_epoch_ms();
            let is_recent = now_epoch.saturating_sub(mtime) < 15_000;
            if is_recent {
                last_seen_file = Some(path.clone());
                last_seen_mtime = mtime;
                last_seen_size = size;
                if let Some((model, tool)) = Self::parse_model_from_file(&path) {
                    self.record_activity(&model, &tool).await;
                }
            } else if let Some((model, tool)) = Self::parse_model_from_file(&path) {
                let mut st = self.state.write().await;
                st.identity = crate::domain::ai_activity::resolve_model_metadata(&model, &tool);
                st.is_active = false;
                st.intensity = 0.0;
                st.request_rate_rpm = 0.0;
                st.last_event_epoch_ms = mtime;
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

                    let n = unsafe {
                        libc::read(inotify_fd, buffer.as_mut_ptr() as *mut libc::c_void, buffer.len())
                    };

                    guard.clear_ready();

                    if n > 0 {
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

                                    // Check for new subdirectory creation (e.g. dynamic session directories in pi / omp)
                                    if event.mask & libc::IN_ISDIR != 0 && full_path.is_dir() {
                                        if let Ok(c_str) = std::ffi::CString::new(full_path.to_string_lossy().as_bytes()) {
                                            let new_wd = unsafe {
                                                libc::inotify_add_watch(
                                                    inotify_fd,
                                                    c_str.as_ptr(),
                                                    libc::IN_MODIFY | libc::IN_CREATE | libc::IN_CLOSE_WRITE | libc::IN_ATTRIB,
                                                )
                                            };
                                            if new_wd >= 0 {
                                                watch_map.insert(new_wd, full_path.clone());
                                                let mut wds = self.watch_descriptors.write().await;
                                                *wds = watch_map.clone();
                                            }
                                        }
                                    } else if name_str.ends_with(".jsonl") || name_str.ends_with(".log") || name_str.ends_with(".json") {
                                        if let Some((model, tool)) = Self::parse_model_from_file(&full_path) {
                                            self.record_activity(&model, &tool).await;
                                            let curr = self.get_state().await;
                                            emit_activity_payload(&curr);
                                        }
                                    }
                                }
                            }
                            offset += std::mem::size_of::<libc::inotify_event>() + name_len;
                        }
                    }
                }
                _ = decay_tick.tick() => {
                    // Resilient poll: check latest modified session across all agent directories
                    if let Some((path, mtime, size)) = Self::find_latest_session_file(&home) {
                        let now_epoch = current_epoch_ms();
                        let is_recent = now_epoch.saturating_sub(mtime) < 15_000;
                        if is_recent && (mtime > last_seen_mtime || size != last_seen_size || last_seen_file.as_ref() != Some(&path)) {
                            last_seen_file = Some(path.clone());
                            last_seen_mtime = mtime;
                            last_seen_size = size;

                            if let Some((model, tool)) = Self::parse_model_from_file(&path) {
                                self.record_activity(&model, &tool).await;
                                let curr = self.get_state().await;
                                emit_activity_payload(&curr);
                            }
                        }
                    }

                    let was_active = self.get_state().await.is_active;
                    let transitioned = self.tick_decay().await;
                    if transitioned || was_active {
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

        // 1. Pi agent sessions (purely real .jsonl session files, context-mode stats excluded)
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

        // 5. OpenCode logs
        let opencode_log = home.join(".local/share/opencode/log/opencode.log");
        if opencode_log.exists() {
            candidates.push(opencode_log);
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
    });
    if let Ok(s) = serde_json::to_string(&payload) {
        println!("{}", s);
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

        let model = direct_model.or(msg_model)?;

        let prov = v.get("provider")
            .or_else(|| msg.and_then(|m| m.get("provider")))
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

fn current_epoch_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as u64
}
