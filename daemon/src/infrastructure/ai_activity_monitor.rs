use crate::domain::ai_activity::{resolve_model_metadata, AiActivityState};
use crate::domain::ports::{ActiveSessionDescriptor, AgentSessionAdapter, AiActivityPort};
use crate::infrastructure::ai_adapters::{
    self, AdapterRegistry, CodexAdapter, DshAdapter, OpenCodeAdapter, PiAdapter, ZCodeAdapter,
};
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};
use tokio::sync::RwLock;

pub const IN_FLIGHT_WINDOW_MS: u64 = 120_000; // 120s active window during in-flight reasoning and tool execution
pub const COMPLETED_WINDOW_MS: u64 = 3_000; // 3s active window after turn completion (shows completion state, then promptly decays)
pub const ACTIVE_AGENT_WINDOW_MS: u64 = 120_000; // alias for in-flight / active sessions scan
pub const TRACK_RETENTION_MS: u64 = 120_000; // 120s track retention for rolling metrics

pub type ActiveSessionFile = ActiveSessionDescriptor;

pub use ai_adapters::{
    extract_model_from_json_line, extract_tokens_from_json_line, extract_tokens_from_tail,
    read_head_string, read_tail_string, scan_dirs_recursive, scan_jsonl_recursive,
};

/// Track state for an individual agent tool during concurrent execution.
#[derive(Debug, Clone)]
pub struct AgentTrack {
    pub identity: crate::domain::ai_activity::AiAgentIdentity,
    pub recent_events_window: Vec<u64>,
    pub recent_tokens_window: Vec<(u64, u64)>,
    pub last_event_epoch_ms: u64,
    pub is_turn_completed: bool,
}

/// Tail reader that monitors agent transcript activity and tracks real-time model metrics.
#[derive(Clone)]
pub struct AiActivityMonitor {
    pub state: Arc<RwLock<AiActivityState>>,
    pub agent_tracks: Arc<RwLock<HashMap<String, AgentTrack>>>,
    pub registry: Arc<AdapterRegistry>,
    watch_descriptors: Arc<RwLock<HashMap<i32, PathBuf>>>,
    recent_events_window: Arc<RwLock<Vec<u64>>>,
    recent_tokens_window: Arc<RwLock<Vec<(u64, u64)>>>,
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
            agent_tracks: Arc::new(RwLock::new(HashMap::new())),
            registry: Arc::new(AdapterRegistry::new()),
            watch_descriptors: Arc::new(RwLock::new(HashMap::new())),
            recent_events_window: Arc::new(RwLock::new(Vec::new())),
            recent_tokens_window: Arc::new(RwLock::new(Vec::new())),
        }
    }

    pub fn with_registry(registry: Arc<AdapterRegistry>) -> Self {
        Self {
            state: Arc::new(RwLock::new(AiActivityState::default())),
            agent_tracks: Arc::new(RwLock::new(HashMap::new())),
            registry,
            watch_descriptors: Arc::new(RwLock::new(HashMap::new())),
            recent_events_window: Arc::new(RwLock::new(Vec::new())),
            recent_tokens_window: Arc::new(RwLock::new(Vec::new())),
        }
    }

    pub async fn get_state(&self) -> AiActivityState {
        self.state.read().await.clone()
    }

    pub async fn agent_tracks_for_test(
        &self,
    ) -> tokio::sync::RwLockWriteGuard<'_, HashMap<String, AgentTrack>> {
        self.agent_tracks.write().await
    }

    /// Records a new request event for the specified model and tool, updating activity metrics.
    pub async fn record_activity(&self, raw_model: &str, tool_source: &str) {
        self.record_activity_full(raw_model, tool_source, None, false)
            .await;
    }

    /// Records a new request event with optional token quantity, updating RPM and TPM metrics.
    pub async fn record_activity_with_tokens(
        &self,
        raw_model: &str,
        tool_source: &str,
        tokens: Option<u64>,
    ) {
        self.record_activity_full(raw_model, tool_source, tokens, false)
            .await;
    }

    /// Records a new request event with token quantity and turn completion status.
    pub async fn record_activity_full(
        &self,
        raw_model: &str,
        tool_source: &str,
        tokens: Option<u64>,
        is_completed: bool,
    ) {
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
            is_turn_completed: false,
        });
        track.identity = identity.clone();
        track.is_turn_completed = is_completed;
        track.recent_events_window.retain(|&t| now_ms.saturating_sub(t) < 60_000);
        track.recent_events_window.push(now_ms);
        track.recent_tokens_window.retain(|&(t, _)| now_ms.saturating_sub(t) < 60_000);
        if let Some(tok) = tokens {
            if tok > 0 {
                track.recent_tokens_window.push((now_ms, tok));
            }
        }
        track.last_event_epoch_ms = now_ms;

        // Build active_agents list based on in-flight or completed window
        let mut active_slots = Vec::new();
        for (_, t) in tracks.iter_mut() {
            t.recent_events_window.retain(|&ev| now_ms.saturating_sub(ev) < 60_000);
            t.recent_tokens_window.retain(|&(ev, _)| now_ms.saturating_sub(ev) < 60_000);
            let agent_tokens: u64 = t.recent_tokens_window.iter().map(|&(_, c)| c).sum();
            let window = if t.is_turn_completed {
                COMPLETED_WINDOW_MS
            } else {
                IN_FLIGHT_WINDOW_MS
            };
            if now_ms.saturating_sub(t.last_event_epoch_ms) < window {
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

    /// Progresses exponential decay on intensity and request rate. Returns true if state transitioned.
    pub async fn tick_decay(&self) -> bool {
        let now_ms = current_epoch_ms();
        let mut st = self.state.write().await;
        let mut tracks = self.agent_tracks.write().await;

        let prev_active_count = st.active_agents.len();
        let prev_active = st.is_active;

        // Prune tracks older than retention window
        tracks.retain(|_, t| now_ms.saturating_sub(t.last_event_epoch_ms) < TRACK_RETENTION_MS);

        // Update active_agents list
        let mut active_slots = Vec::new();
        for (_, t) in tracks.iter_mut() {
            t.recent_events_window.retain(|&ev| now_ms.saturating_sub(ev) < 60_000);
            t.recent_tokens_window.retain(|&(ev, _)| now_ms.saturating_sub(ev) < 60_000);
            let agent_tokens: u64 = t.recent_tokens_window.iter().map(|&(_, c)| c).sum();
            let window = if t.is_turn_completed {
                COMPLETED_WINDOW_MS
            } else {
                IN_FLIGHT_WINDOW_MS
            };
            if now_ms.saturating_sub(t.last_event_epoch_ms) < window {
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
        st.active_agents = active_slots;

        // Update global active state and primary identity from newest active agent
        let top_agent_info = st.active_agents.first().map(|t| (
            crate::domain::ai_activity::AiAgentIdentity {
                tool_source: t.tool_source.clone(),
                model_id: t.model_id.clone(),
                display_name: t.display_name.clone(),
                brand_color: t.brand_color.clone(),
                brand_icon: t.brand_icon.clone(),
            },
            t.last_event_epoch_ms,
        ));

        if let Some((top_id, top_epoch)) = top_agent_info {
            st.identity = top_id;
            st.is_active = true;
            let elapsed_since_primary = now_ms.saturating_sub(top_epoch);
            let window = IN_FLIGHT_WINDOW_MS;
            st.intensity = (1.0 - (elapsed_since_primary as f64 / window as f64)).clamp(0.0, 1.0);
        } else {
            st.is_active = false;
            st.intensity = 0.0;
            st.request_rate_rpm = 0.0;
            st.token_rate_tpm = 0.0;
            st.recent_tokens = 0;
        }

        prev_active != st.is_active || prev_active_count != st.active_agents.len()
    }

    /// Queries the full ground-truth state across all adapters and active session files.
    pub async fn query_active_state(&self) -> AiActivityState {
        let home = match std::env::var("HOME").ok().map(PathBuf::from) {
            Some(h) => h,
            None => return self.get_state().await,
        };
        let now_ms = current_epoch_ms();

        // 1. Scan active session files across all adapters
        let active_files = self.registry.scan_all_active_files(&home, ACTIVE_AGENT_WINDOW_MS);
        for f in active_files {
            if let Some((m, t, tok, is_completed)) = self.registry.parse_model_tokens_and_status(&f.path) {
                if !is_completed || now_ms.saturating_sub(f.mtime) < COMPLETED_WINDOW_MS {
                    self.record_activity_full(&m, &t, tok, is_completed).await;
                }
            }
        }

        // 2. Query external stores across all adapters (e.g. OpenCode SQLite, ZCode SQLite)
        for store_res in self.registry.query_all_external_stores(&home) {
            let time_updated = store_res.timestamp_ms.unwrap_or(0);
            let window = if store_res.is_turn_completed {
                COMPLETED_WINDOW_MS
            } else {
                ACTIVE_AGENT_WINDOW_MS
            };
            let is_recent = now_ms.saturating_sub(time_updated) < window;
            if is_recent {
                self.record_activity_full(
                    &store_res.model_id,
                    &store_res.tool_source,
                    store_res.tokens,
                    store_res.is_turn_completed,
                )
                .await;
            } else if self.state.read().await.last_event_epoch_ms < time_updated
                && self.get_state().await.active_agents.is_empty()
            {
                let mut st = self.state.write().await;
                st.identity = resolve_model_metadata(&store_res.model_id, &store_res.tool_source);
                st.is_active = false;
                st.intensity = 0.0;
                st.request_rate_rpm = 0.0;
                st.last_event_epoch_ms = time_updated;
            }
        }

        // 3. Fallback when idle: display identity of latest known session
        if self.get_state().await.active_agents.is_empty() {
            if let Some((path, mtime, _)) = self.registry.find_latest_session_file(&home) {
                if let Some(parsed) = self.registry.parse_file(&path) {
                    let mut st = self.state.write().await;
                    st.identity = resolve_model_metadata(&parsed.model_id, &parsed.tool_source);
                    st.is_active = false;
                    st.intensity = 0.0;
                    st.request_rate_rpm = 0.0;
                    st.last_event_epoch_ms = mtime;
                }
            }
        }

        self.get_state().await
    }

    pub fn start_background_watcher(&self) {
        let this = self.clone();
        tokio::spawn(async move {
            this.run_inotify_loop().await;
        });
    }

    pub async fn run_inotify_loop(&self) {
        let home = match std::env::var("HOME").ok().map(PathBuf::from) {
            Some(h) => h,
            None => return,
        };

        let candidate_dirs = self.registry.all_watch_directories(&home);

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
        let mut last_seen_store_time: HashMap<String, u64> = HashMap::new();
        let mut last_seen_store_tokens: HashMap<String, u64> = HashMap::new();

        // Synchronize initial ground-truth state across all adapters
        let now_ms = current_epoch_ms();
        let initial_active_files = self.registry.scan_all_active_files(&home, ACTIVE_AGENT_WINDOW_MS);
        for file_info in initial_active_files {
            seen_sessions.insert(file_info.path.clone(), (file_info.mtime, file_info.size));
            if let Some((model, tool, tokens, is_completed)) =
                self.registry.parse_model_tokens_and_status(&file_info.path)
            {
                if !is_completed || now_ms.saturating_sub(file_info.mtime) < COMPLETED_WINDOW_MS {
                    self.record_activity_full(&model, &tool, tokens, is_completed)
                        .await;
                }
            }
        }

        // External stores initial check
        for store_res in self.registry.query_all_external_stores(&home) {
            let updated = store_res.timestamp_ms.unwrap_or(0);
            let tokens = store_res.tokens.unwrap_or(0);
            last_seen_store_time.insert(store_res.tool_source.clone(), updated);
            last_seen_store_tokens.insert(store_res.tool_source.clone(), tokens);
            let window = if store_res.is_turn_completed {
                COMPLETED_WINDOW_MS
            } else {
                ACTIVE_AGENT_WINDOW_MS
            };
            if now_ms.saturating_sub(updated) < window {
                self.record_activity_full(
                    &store_res.model_id,
                    &store_res.tool_source,
                    store_res.tokens,
                    store_res.is_turn_completed,
                )
                .await;
            }
        }

        // Fallback if completely idle: set identity from latest known session file
        if self.get_state().await.active_agents.is_empty() {
            if let Some((path, mtime, size)) = self.registry.find_latest_session_file(&home) {
                seen_sessions.insert(path.clone(), (mtime, size));
                if let Some(parsed) = self.registry.parse_file(&path) {
                    let mut st = self.state.write().await;
                    st.identity = resolve_model_metadata(&parsed.model_id, &parsed.tool_source);
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
        let mut last_heartbeat_epoch_ms: u64 = 0;
        let mut last_dir_scan_ms: u64 = 0;

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
                                    } else if let Some(adapter) = self.registry.find_adapter_for_path(&full_path) {
                                        // 1. External store update
                                        if let Some(store_res) = adapter.query_external_store(&home) {
                                            let time_updated = store_res.timestamp_ms.unwrap_or(0);
                                            let tokens = store_res.tokens.unwrap_or(0);
                                            let prev_time = last_seen_store_time.get(&store_res.tool_source).copied().unwrap_or(0);
                                            let prev_tokens = last_seen_store_tokens.get(&store_res.tool_source).copied().unwrap_or(0);
                                            let now_epoch = current_epoch_ms();
                                            let window = if store_res.is_turn_completed { COMPLETED_WINDOW_MS } else { ACTIVE_AGENT_WINDOW_MS };

                                            if now_epoch.saturating_sub(time_updated) < window
                                                && (time_updated > prev_time || tokens != prev_tokens)
                                            {
                                                let delta = tokens.saturating_sub(prev_tokens);
                                                last_seen_store_time.insert(store_res.tool_source.clone(), time_updated);
                                                last_seen_store_tokens.insert(store_res.tool_source.clone(), tokens);
                                                let reported = if delta > 0 { delta } else { tokens.min(5000) };
                                                self.record_activity_full(&store_res.model_id, &store_res.tool_source, Some(reported), store_res.is_turn_completed).await;
                                                let curr = self.get_state().await;
                                                emit_activity_payload(&curr);
                                            }
                                        } else if let Ok(meta) = full_path.metadata() {
                                            // 2. File-based session stream update
                                            let mtime = meta.modified().ok()
                                                .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
                                                .map(|d| d.as_millis() as u64)
                                                .unwrap_or(0);
                                            let size = meta.len();
                                            seen_sessions.insert(full_path.clone(), (mtime, size));
                                            let now_ms = current_epoch_ms();
                                            let is_fresh = now_ms.saturating_sub(mtime) < ACTIVE_AGENT_WINDOW_MS;
                                            if is_fresh {
                                                if let Some(parsed) = self.registry.parse_file(&full_path) {
                                                    if !parsed.is_turn_completed || now_ms.saturating_sub(mtime) < COMPLETED_WINDOW_MS {
                                                        self.record_activity_full(&parsed.model_id, &parsed.tool_source, parsed.tokens, parsed.is_turn_completed).await;
                                                        let curr = self.get_state().await;
                                                        emit_activity_payload(&curr);
                                                    }
                                                }
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
                    let now_ms = current_epoch_ms();

                    // Heartbeat: while an agent is active in-flight, emit state every 2000ms so QML is never starved
                    if self.get_state().await.is_active && now_ms.saturating_sub(last_heartbeat_epoch_ms) >= 2000 {
                        last_heartbeat_epoch_ms = now_ms;
                        should_emit = true;
                    }

                    // Dynamically scan for newly created adapter watch directories every 5s
                    if now_ms.saturating_sub(last_dir_scan_ms) >= 5000 {
                        last_dir_scan_ms = now_ms;
                        let latest_dirs = self.registry.all_watch_directories(&home);
                        for dir in latest_dirs {
                            if dir.exists() && dir.is_dir() && !watch_map.values().any(|v| v == &dir) {
                                if let Ok(c_str) = std::ffi::CString::new(dir.to_string_lossy().as_bytes()) {
                                    let new_wd = unsafe {
                                        libc::inotify_add_watch(
                                            inotify_fd,
                                            c_str.as_ptr(),
                                            libc::IN_MODIFY | libc::IN_CREATE | libc::IN_CLOSE_WRITE,
                                        )
                                    };
                                    if new_wd >= 0 {
                                        watch_map.insert(new_wd, dir.clone());
                                        let mut wds = self.watch_descriptors.write().await;
                                        *wds = watch_map.clone();
                                    }
                                }
                            }
                        }
                    }

                    // 1. Concurrent poll: scan active session files across all adapters
                    let active_files = self.registry.scan_all_active_files(&home, ACTIVE_AGENT_WINDOW_MS);
                    for file_info in active_files {
                        let prev = seen_sessions.get(&file_info.path).copied();
                        let is_new_event = match prev {
                            None => true,
                            Some((prev_mtime, prev_size)) => file_info.mtime > prev_mtime || file_info.size != prev_size,
                        };
                        if is_new_event {
                            seen_sessions.insert(file_info.path.clone(), (file_info.mtime, file_info.size));
                            if let Some(parsed) = self.registry.parse_file(&file_info.path) {
                                let now_ms = current_epoch_ms();
                                if !parsed.is_turn_completed || now_ms.saturating_sub(file_info.mtime) < COMPLETED_WINDOW_MS {
                                    self.record_activity_full(&parsed.model_id, &parsed.tool_source, parsed.tokens, parsed.is_turn_completed).await;
                                    should_emit = true;
                                }
                            }
                        }
                    }

                    // 2. Poll external stores across all adapters
                    for store_res in self.registry.query_all_external_stores(&home) {
                        let time_updated = store_res.timestamp_ms.unwrap_or(0);
                        let tokens = store_res.tokens.unwrap_or(0);
                        let prev_time = last_seen_store_time.get(&store_res.tool_source).copied().unwrap_or(0);
                        let prev_tokens = last_seen_store_tokens.get(&store_res.tool_source).copied().unwrap_or(0);
                        let now_epoch = current_epoch_ms();
                        let window = if store_res.is_turn_completed { COMPLETED_WINDOW_MS } else { ACTIVE_AGENT_WINDOW_MS };

                        if now_epoch.saturating_sub(time_updated) < window
                            && (time_updated > prev_time || tokens != prev_tokens)
                        {
                            let delta = tokens.saturating_sub(prev_tokens);
                            last_seen_store_time.insert(store_res.tool_source.clone(), time_updated);
                            last_seen_store_tokens.insert(store_res.tool_source.clone(), tokens);
                            let reported = if delta > 0 { delta } else { tokens.min(5000) };
                            self.record_activity_full(&store_res.model_id, &store_res.tool_source, Some(reported), store_res.is_turn_completed).await;
                            should_emit = true;
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
}

// -----------------------------------------------------------------------------
// AiActivityPort implementation
// -----------------------------------------------------------------------------

impl AiActivityPort for AiActivityMonitor {
    fn get_state_sync(&self) -> AiActivityState {
        self.state.blocking_read().clone()
    }

    fn record_activity_sync(
        &self,
        raw_model: &str,
        tool_source: &str,
        tokens: Option<u64>,
        is_completed: bool,
    ) {
        if let Ok(handle) = tokio::runtime::Handle::try_current() {
            tokio::task::block_in_place(|| {
                handle.block_on(self.record_activity_full(raw_model, tool_source, tokens, is_completed))
            });
        }
    }

    fn tick_decay_sync(&self) -> bool {
        if let Ok(handle) = tokio::runtime::Handle::try_current() {
            tokio::task::block_in_place(|| {
                handle.block_on(self.tick_decay())
            })
        } else {
            false
        }
    }

    fn query_active_state_sync(&self) -> AiActivityState {
        if let Ok(handle) = tokio::runtime::Handle::try_current() {
            tokio::task::block_in_place(|| {
                handle.block_on(self.query_active_state())
            })
        } else {
            self.get_state_sync()
        }
    }

    fn start_background_watcher(&self) {
        AiActivityMonitor::start_background_watcher(self);
    }
}

// -----------------------------------------------------------------------------
// Static Helper Functions (delegating to AdapterRegistry for 100% test compatibility)
// -----------------------------------------------------------------------------

impl AiActivityMonitor {
    pub fn parse_model_from_file(path: &Path) -> Option<(String, String)> {
        AdapterRegistry::new().parse_file(path).map(|r| (r.model_id, r.tool_source))
    }

    pub fn parse_model_and_tokens_from_file(path: &Path) -> Option<(String, String, Option<u64>)> {
        AdapterRegistry::new().parse_file(path).map(|r| (r.model_id, r.tool_source, r.tokens))
    }

    pub fn parse_model_tokens_and_status_from_file(path: &Path) -> Option<(String, String, Option<u64>, bool)> {
        AdapterRegistry::new().parse_model_tokens_and_status(path)
    }

    pub fn parse_model_from_tail(tail: &str, path_hint: &str) -> Option<(String, String)> {
        AdapterRegistry::new().parse_model_from_tail(tail, path_hint)
    }

    pub fn find_latest_session_file(home: &Path) -> Option<(PathBuf, u64, u64)> {
        AdapterRegistry::new().find_latest_session_file(home)
    }

    pub fn scan_all_active_session_files(home: &Path, max_age_ms: u64) -> Vec<ActiveSessionFile> {
        AdapterRegistry::new().scan_all_active_files(home, max_age_ms)
    }

    pub fn query_opencode_latest_session(home: &Path) -> Option<(String, u64, u64)> {
        OpenCodeAdapter::new().query_external_store(home).map(|r| (r.model_id, r.tokens.unwrap_or(0), r.timestamp_ms.unwrap_or(0)))
    }

    pub fn query_zcode_latest_session(home: &Path) -> Option<(String, u64, u64, bool)> {
        ZCodeAdapter::new().query_external_store(home).map(|r| (r.model_id, r.tokens.unwrap_or(0), r.timestamp_ms.unwrap_or(0), r.is_turn_completed))
    }

    pub fn check_turn_completed_from_tail(tail: &str, path_hint: &str) -> bool {
        AdapterRegistry::new().check_turn_completed(tail, path_hint)
    }
}

pub fn check_turn_completed_from_tail(tail: &str, path_hint: &str) -> bool {
    AiActivityMonitor::check_turn_completed_from_tail(tail, path_hint)
}

pub fn read_pi_default_settings() -> Option<(String, String)> {
    let home = std::env::var("HOME").ok().map(PathBuf::from)?;
    PiAdapter::new().read_default_settings(&home)
}

pub fn read_zcode_default_settings() -> Option<(String, String)> {
    let home = std::env::var("HOME").ok().map(PathBuf::from)?;
    ZCodeAdapter::new().read_default_settings(&home)
}

pub fn read_dsh_default_settings() -> Option<(String, String)> {
    let home = std::env::var("HOME").ok().map(PathBuf::from)?;
    DshAdapter::new().read_default_settings(&home)
}

pub fn read_codex_default_settings() -> Option<(String, String)> {
    let home = std::env::var("HOME").ok().map(PathBuf::from)?;
    CodexAdapter::new().read_default_settings(&home)
}

pub use ai_adapters::antigravity::read_antigravity_state_model;

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

fn current_epoch_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as u64
}
