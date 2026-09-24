use astral_plasma::domain::ai_activity::{resolve_model_metadata, AiActivityState};

#[test]
fn test_resolve_mimo_xiaomi_model() {
    let id1 = resolve_model_metadata("opencode-go/mimo-v2.6-flash", "omp");
    assert_eq!(id1.tool_source, "mimo");
    assert_eq!(id1.brand_color, "#FF6900");
    assert_eq!(id1.brand_icon, "token");
    assert_eq!(id1.display_name, "MiMo 2.6 Flash");

    let id2 = resolve_model_metadata("mimo-cn/mimo-v2.5-pro", "pi");
    assert_eq!(id2.tool_source, "mimo");
    assert_eq!(id2.brand_color, "#FF6900");
    assert_eq!(id2.display_name, "MiMo 2.5 Pro");
}

#[test]
fn test_resolve_muse_spark_meta_model() {
    let id = resolve_model_metadata("opencode-go/muse-spark-1.2-contributor", "opencode");
    assert_eq!(id.tool_source, "meta");
    assert_eq!(id.brand_color, "#0081FB");
    assert_eq!(id.brand_icon, "flare");
    assert_eq!(id.display_name, "Muse Spark 1.2");

    let id2 = resolve_model_metadata("muse-spark-1.3-contributor", "pi");
    assert_eq!(id2.tool_source, "meta");
    assert_eq!(id2.display_name, "Muse Spark 1.3");
}

#[test]
fn test_resolve_grok_xcom_model() {
    let id1 = resolve_model_metadata("grok-3", "xai");
    assert_eq!(id1.tool_source, "grok");
    assert_eq!(id1.brand_color, "#EF4444");
    assert_eq!(id1.brand_icon, "rocket_launch");
    assert_eq!(id1.display_name, "Grok 3 (x.com)");

    let id2 = resolve_model_metadata("grok-beta", "grok");
    assert_eq!(id2.tool_source, "grok");
    assert_eq!(id2.brand_color, "#EF4444");
}

#[test]
fn test_resolve_ollama_cloud_model() {
    let id1 = resolve_model_metadata("ollama-cloud/deepseek-v4-flash", "ollama");
    assert_eq!(id1.tool_source, "ollama");
    assert_eq!(id1.brand_color, "#F59E0B");
    assert_eq!(id1.brand_icon, "cloud");
    assert!(id1.display_name.contains("Ollama"));

    let id2 = resolve_model_metadata("ollama/minimax-m3", "pi");
    assert_eq!(id2.tool_source, "ollama");
    assert_eq!(id2.brand_color, "#F59E0B");
}

#[test]
fn test_resolve_claude_model() {
    let id1 = resolve_model_metadata("claude-3-7-sonnet-20250219", "claude");
    assert_eq!(id1.tool_source, "claude");
    assert_eq!(id1.brand_color, "#D97706");
    assert_eq!(id1.brand_icon, "psychology");
    assert_eq!(id1.display_name, "Claude 3.7 Sonnet");

    let id2 = resolve_model_metadata("claude-3-5-sonnet", "claude");
    assert_eq!(id2.display_name, "Claude 3.5 Sonnet");
}

#[test]
fn test_resolve_gemini_model() {
    let id = resolve_model_metadata("gemini-2.5-pro", "antigravity");
    assert_eq!(id.tool_source, "gemini");
    assert_eq!(id.brand_color, "#818CF8");
    assert_eq!(id.brand_icon, "auto_awesome");
    assert_eq!(id.display_name, "Gemini 2.5 Pro");
}

#[test]
fn test_resolve_openai_codex_model() {
    let id = resolve_model_metadata("gpt-4o", "codex");
    assert_eq!(id.tool_source, "openai");
    assert_eq!(id.brand_color, "#10A37F");
    assert_eq!(id.brand_icon, "terminal");
    assert_eq!(id.display_name, "GPT-4o");
}

#[test]
fn test_resolve_deepseek_model() {
    let id = resolve_model_metadata("deepseek-v4-flash", "pi");
    assert_eq!(id.tool_source, "deepseek");
    assert_eq!(id.brand_color, "#2563EB");
    assert_eq!(id.brand_icon, "smart_toy");
    assert_eq!(id.display_name, "DeepSeek V4");
}

#[test]
fn test_resolve_minimax_model() {
    let id = resolve_model_metadata("minimax-cn/MiniMax-M3", "pi");
    assert_eq!(id.tool_source, "minimax");
    assert_eq!(id.brand_color, "#06B6D4");
    assert_eq!(id.brand_icon, "bolt");
    assert_eq!(id.display_name, "MiniMax M3");
}

#[test]
fn test_resolve_omp_model() {
    let id = resolve_model_metadata("glm-5.2", "omp");
    assert_eq!(id.tool_source, "omp");
    assert_eq!(id.brand_color, "#EC4899");
    assert_eq!(id.brand_icon, "memory");
}

#[test]
fn test_default_activity_state() {
    let state = AiActivityState::default();
    assert!(!state.is_active);
    assert_eq!(state.intensity, 0.0);
    assert_eq!(state.request_rate_rpm, 0.0);
}

#[test]
fn test_parse_model_from_tail_mimo() {
    use astral_plasma::infrastructure::ai_activity_monitor::AiActivityMonitor;
    let sample = r#"
{"type":"some_event","id":"123"}
{"type":"model_change","id":"49df1124","parentId":"3716b5aa","timestamp":"2026-09-22T14:28:18.004Z","model":"opencode-go/mimo-v2.6-flash","role":"default"}
"#;
    let res = AiActivityMonitor::parse_model_from_tail(sample, "/home/hlu/.omp/agent/sessions/test.jsonl");
    assert!(res.is_some());
    let (model, tool) = res.unwrap();
    assert_eq!(model, "opencode-go/mimo-v2.6-flash");
    assert_eq!(tool, "omp");
}

#[test]
fn test_parse_model_from_tail_muse_spark() {
    use astral_plasma::infrastructure::ai_activity_monitor::AiActivityMonitor;
    let sample = r#"
{"type":"message","id":"27cb0f2d","message":{"role":"assistant","provider":"opencode-go","model":"muse-spark-1.2-contributor","usage":{"input":24233,"output":33}}}
"#;
    let res = AiActivityMonitor::parse_model_from_tail(sample, "/home/hlu/.pi/agent/sessions/test.jsonl");
    assert!(res.is_some());
    let (model, tool) = res.unwrap();
    assert_eq!(model, "muse-spark-1.2-contributor");
    assert_eq!(tool, "opencode-go");
}

#[tokio::test]
async fn test_ai_activity_monitor_record_and_decay() {
    use astral_plasma::infrastructure::ai_activity_monitor::AiActivityMonitor;
    let monitor = AiActivityMonitor::new();
    
    // Initial state is idle
    let st0 = monitor.get_state().await;
    assert!(!st0.is_active);

    // Record MiMo activity
    monitor.record_activity("opencode-go/mimo-v2.6-flash", "omp").await;
    let st1 = monitor.get_state().await;
    assert!(st1.is_active);
    assert_eq!(st1.intensity, 1.0);
    assert_eq!(st1.identity.tool_source, "mimo");
    assert_eq!(st1.identity.brand_color, "#FF6900");
    assert_eq!(st1.request_rate_rpm, 1.0);

    // Record second request immediately
    monitor.record_activity("opencode-go/mimo-v2.6-flash", "omp").await;
    let st2 = monitor.get_state().await;
    assert_eq!(st2.request_rate_rpm, 2.0);
}

#[test]
fn test_extract_model_from_json_line_pi_model_id() {
    use astral_plasma::infrastructure::ai_activity_monitor::extract_model_from_json_line;
    let line = r#"{"type":"model_change","id":"980bac6a","parentId":null,"timestamp":"2026-09-23T19:40:06.546Z","provider":"opencode-go","modelId":"mimo-v2.6-flash"}"#;
    let res = extract_model_from_json_line(line);
    assert!(res.is_some(), "extract_model_from_json_line must match modelId");
    let (model, prov) = res.unwrap();
    assert_eq!(model, "mimo-v2.6-flash");
    assert_eq!(prov, "opencode-go");

    let id = resolve_model_metadata(&model, &prov);
    assert_eq!(id.tool_source, "mimo");
    assert_eq!(id.brand_color, "#FF6900");
    assert_eq!(id.display_name, "MiMo 2.6 Flash");
}

#[test]
fn test_parse_model_from_tail_pi_mimo() {
    use astral_plasma::infrastructure::ai_activity_monitor::AiActivityMonitor;
    let sample = r#"
{"type":"session","version":3,"id":"01a0cfc8-4239-7245-8032-3507206090fc","timestamp":"2026-09-23T19:40:03.001Z","cwd":"/mnt/data/workspace/astral-plasma"}
{"type":"model_change","id":"980bac6a","parentId":null,"timestamp":"2026-09-23T19:40:06.546Z","provider":"opencode-go","modelId":"mimo-v2.6-flash"}
{"type":"thinking_level_change","id":"3fa343dd","parentId":"980bac6a","timestamp":"2026-09-23T19:40:06.546Z","thinkingLevel":"high"}
"#;
    let res = AiActivityMonitor::parse_model_from_tail(sample, "/home/hlu/.pi/agent/sessions/--mnt-data-workspace--/test.jsonl");
    assert!(res.is_some());
    let (model, prov) = res.unwrap();
    assert_eq!(model, "mimo-v2.6-flash");
    assert_eq!(prov, "opencode-go");
}

#[test]
fn test_parse_model_from_file_head_fallback() {
    use astral_plasma::infrastructure::ai_activity_monitor::AiActivityMonitor;
    use std::io::Write;
    let mut temp = tempfile::NamedTempFile::new().unwrap();
    writeln!(temp, r#"{{"type":"session","version":3,"id":"test-123","cwd":"/test"}}"#).unwrap();
    writeln!(temp, r#"{{"type":"model_change","id":"m1","provider":"opencode-go","modelId":"mimo-v2.6-flash"}}"#).unwrap();
    // Write 50KB of filler content (e.g. huge tool calls or context messages)
    let filler = "x".repeat(1000);
    for _ in 0..40 {
        writeln!(temp, r#"{{"type":"message","id":"f","message":{{"role":"tool","content":"{}"}}}}"#, filler).unwrap();
    }
    // End with user prompt lacking model
    writeln!(temp, r#"{{"type":"message","id":"u1","message":{{"role":"user","content":[{{"type":"text","text":"can you check this?"}}]}}}}"#).unwrap();
    temp.flush().unwrap();

    let res = AiActivityMonitor::parse_model_from_file(temp.path());
    assert!(res.is_some(), "parse_model_from_file must find model from file head when tail is filled with messages");
    let (model, prov) = res.unwrap();
    assert_eq!(model, "mimo-v2.6-flash");
    assert_eq!(prov, "opencode-go");
}

#[test]
fn test_find_latest_session_file_ignores_context_mode_stats() {
    use astral_plasma::infrastructure::ai_activity_monitor::AiActivityMonitor;
    use std::fs;
    let temp_home = tempfile::tempdir().unwrap();
    let pi_session_dir = temp_home.path().join(".pi/agent/sessions/--test-workspace--");
    let pi_ctx_dir = temp_home.path().join(".pi/context-mode/sessions");
    fs::create_dir_all(&pi_session_dir).unwrap();
    fs::create_dir_all(&pi_ctx_dir).unwrap();

    let session_file = pi_session_dir.join("2026-09-24_real.jsonl");
    fs::write(&session_file, r#"{"type":"session"}"#).unwrap();

    // Create a context-mode stats json with a newer timestamp
    let stats_file = pi_ctx_dir.join("stats-pid-9999.json");
    fs::write(&stats_file, r#"{"schemaVersion":2,"bytes_returned":0}"#).unwrap();

    let latest = AiActivityMonitor::find_latest_session_file(temp_home.path());
    assert!(latest.is_some());
    let (path, _, _) = latest.unwrap();
    assert_eq!(path, session_file, "find_latest_session_file must return the real session jsonl and ignore context-mode stats json");
}

#[test]
fn test_find_latest_session_file_detects_antigravity_brain_transcripts() {
    use astral_plasma::infrastructure::ai_activity_monitor::AiActivityMonitor;
    use std::fs;
    let temp_home = tempfile::tempdir().unwrap();
    let brain_dir = temp_home.path().join(".gemini/antigravity/brain/session-123/.system_generated/logs");
    fs::create_dir_all(&brain_dir).unwrap();

    let transcript = brain_dir.join("transcript.jsonl");
    fs::write(&transcript, "`Model Selection` from None to Gemini Flash 3.8.\n").unwrap();

    let latest = AiActivityMonitor::find_latest_session_file(temp_home.path());
    assert!(latest.is_some());
    let (path, _, _) = latest.unwrap();
    assert_eq!(path, transcript, "find_latest_session_file must detect active antigravity brain transcripts");

    let parsed = AiActivityMonitor::parse_model_from_file(&path);
    assert!(parsed.is_some());
    let (model, tool) = parsed.unwrap();
    assert_eq!(model, "Gemini Flash 3.8");
    assert_eq!(tool, "gemini");
}

#[tokio::test]
async fn test_ai_activity_inactive_when_session_older_than_15s() {
    use astral_plasma::infrastructure::ai_activity_monitor::AiActivityMonitor;
    let monitor = AiActivityMonitor::new();
    
    // An inactive/idle monitor must start with is_active = false
    let st = monitor.get_state().await;
    assert!(!st.is_active);
    assert_eq!(st.intensity, 0.0);
    assert_eq!(st.request_rate_rpm, 0.0);
}

#[test]
fn test_parse_model_from_file_ignores_non_transcript_antigravity_files() {
    use astral_plasma::infrastructure::ai_activity_monitor::AiActivityMonitor;
    use std::fs;
    let temp_home = tempfile::tempdir().unwrap();
    let brain_dir = temp_home.path().join(".gemini/antigravity/brain/session-123/.system_generated");
    fs::create_dir_all(brain_dir.join("tasks")).unwrap();
    fs::create_dir_all(brain_dir.join("messages")).unwrap();

    let task_log = brain_dir.join("tasks/task-10540.log");
    fs::write(&task_log, "some task log").unwrap();
    let msg_json = brain_dir.join("messages/read.json");
    fs::write(&msg_json, "{}").unwrap();
    let transcript_full = brain_dir.join("logs/transcript_full.jsonl");
    fs::create_dir_all(brain_dir.join("logs")).unwrap();
    fs::write(&transcript_full, "{}").unwrap();

    assert!(AiActivityMonitor::parse_model_from_file(&task_log).is_none());
    assert!(AiActivityMonitor::parse_model_from_file(&msg_json).is_none());
    assert!(AiActivityMonitor::parse_model_from_file(&transcript_full).is_none());

    let transcript = brain_dir.join("logs/transcript.jsonl");
    fs::write(&transcript, "`Model Selection` from None to Gemini Flash 3.8.\n").unwrap();
    assert!(AiActivityMonitor::parse_model_from_file(&transcript).is_some());
}

#[test]
fn test_resolve_gemini_flash_38() {
    let id1 = resolve_model_metadata("gemini-3.8-flash", "antigravity");
    assert_eq!(id1.display_name, "Gemini Flash 3.8");

    let id2 = resolve_model_metadata("Gemini Flash", "antigravity");
    assert_eq!(id2.display_name, "Gemini Flash 3.8");
}

#[test]
fn test_opencode_log_is_ignored_and_does_not_trigger_mimo() {
    use astral_plasma::infrastructure::ai_activity_monitor::AiActivityMonitor;
    use std::fs;
    let temp_home = tempfile::tempdir().unwrap();
    let opencode_dir = temp_home.path().join(".local/share/opencode/log");
    fs::create_dir_all(&opencode_dir).unwrap();

    let log_file = opencode_dir.join("opencode.log");
    fs::write(
        &log_file,
        "timestamp=2026-09-24T14:55:03.721Z level=INFO event.type=model.updated event.data={}\n",
    )
    .unwrap();

    // parse_model_from_file MUST return None for server log files
    assert!(AiActivityMonitor::parse_model_from_file(&log_file).is_none());
    assert!(AiActivityMonitor::parse_model_and_tokens_from_file(&log_file).is_none());

    // find_latest_session_file MUST NOT select opencode.log
    assert!(AiActivityMonitor::find_latest_session_file(temp_home.path()).is_none());
}

#[tokio::test]
async fn test_multi_agent_concurrency_tracking() {
    use astral_plasma::infrastructure::ai_activity_monitor::AiActivityMonitor;
    let monitor = AiActivityMonitor::new();

    // 1. Record Gemini activity
    monitor.record_activity_with_tokens("gemini-3.8-flash", "antigravity", Some(12000)).await;
    let st1 = monitor.get_state().await;
    assert!(st1.is_active);
    assert_eq!(st1.active_agents.len(), 1);
    assert_eq!(st1.active_agents[0].tool_source, "gemini");
    assert_eq!(st1.active_agents[0].display_name, "Gemini Flash 3.8");
    assert_eq!(st1.active_agents[0].brand_color, "#818CF8");
    assert_eq!(st1.active_agents[0].recent_tokens, 12000);

    // Ensure distinct epoch milliseconds for chronological ordering
    tokio::time::sleep(tokio::time::Duration::from_millis(5)).await;

    // 2. Concurrently record Claude Code activity
    monitor.record_activity_with_tokens("claude-3-7-sonnet", "claude", Some(6500)).await;
    let st2 = monitor.get_state().await;
    assert!(st2.is_active);
    assert_eq!(st2.active_agents.len(), 2, "Both Gemini and Claude must be tracked concurrently in active_agents");

    // Most recent agent is first
    assert_eq!(st2.active_agents[0].tool_source, "claude");
    assert_eq!(st2.active_agents[0].display_name, "Claude 3.7 Sonnet");
    assert_eq!(st2.active_agents[0].brand_color, "#D97706");
    assert_eq!(st2.active_agents[0].recent_tokens, 6500);

    assert_eq!(st2.active_agents[1].tool_source, "gemini");
    assert_eq!(st2.active_agents[1].display_name, "Gemini Flash 3.8");
    assert_eq!(st2.active_agents[1].brand_color, "#818CF8");
    assert_eq!(st2.active_agents[1].recent_tokens, 12000);

    // Aggregate tokens and request rates reflect combined load
    assert_eq!(st2.recent_tokens, 18500);
    assert_eq!(st2.request_rate_rpm, 2.0);
}

#[tokio::test]
async fn test_multi_agent_decay_prunes_inactive_agent_first() {
    use astral_plasma::infrastructure::ai_activity_monitor::AiActivityMonitor;
    let monitor = AiActivityMonitor::new();

    monitor.record_activity_with_tokens("gemini-3.8-flash", "antigravity", Some(5000)).await;
    monitor.record_activity_with_tokens("claude-3-7-sonnet", "claude", Some(3000)).await;

    let st = monitor.get_state().await;
    assert_eq!(st.active_agents.len(), 2);

    // If no decay interval exceeded, tick_decay returns false and retains active agents
    let transitioned = monitor.tick_decay().await;
    assert!(!transitioned);
    let st2 = monitor.get_state().await;
    assert_eq!(st2.active_agents.len(), 2);
}

#[test]
fn test_resolve_opencode_space_bunny_alpha_model() {
    let id1 = resolve_model_metadata("stealth/space-bunny-alpha", "opencode");
    assert_eq!(id1.tool_source, "opencode");
    assert_eq!(id1.brand_color, "#10B981");
    assert_eq!(id1.brand_icon, "terminal");
    assert_eq!(id1.display_name, "Space Bunny Alpha");

    // Test JSON formatted model string from SQLite
    let raw_json = r#"{"id":"stealth/space-bunny-alpha","providerID":"openrouter","variant":"max"}"#;
    let id2 = resolve_model_metadata(raw_json, "opencode");
    assert_eq!(id2.tool_source, "opencode");
    assert_eq!(id2.brand_color, "#10B981");
    assert_eq!(id2.display_name, "Space Bunny Alpha");
}

#[test]
fn test_resolve_generic_models_without_hardcoded_overrides() {
    let id1 = resolve_model_metadata("deepseek/deepseek-r1", "custom");
    assert_eq!(id1.display_name, "DeepSeek R1");

    let id2 = resolve_model_metadata("qwen-2.5-coder", "opencode");
    assert_eq!(id2.display_name, "Qwen 2.5 Coder");

    let id3 = resolve_model_metadata("custom-local-model", "other");
    assert_eq!(id3.display_name, "Custom Local Model");
}

#[test]
fn test_query_opencode_latest_session_sqlite() {
    use astral_plasma::infrastructure::ai_activity_monitor::AiActivityMonitor;
    use std::fs;
    let temp_home = tempfile::tempdir().unwrap();
    let opencode_dir = temp_home.path().join(".local/share/opencode");
    fs::create_dir_all(&opencode_dir).unwrap();

    let db_path = opencode_dir.join("opencode.db");
    // Initialize SQLite database table and test row via sqlite3 CLI
    let status = std::process::Command::new("sqlite3")
        .arg(&db_path)
        .arg("CREATE TABLE session_v2 (id text PRIMARY KEY, project_id text NOT NULL, slug text NOT NULL, directory text NOT NULL, version text NOT NULL, model text, tokens_input integer DEFAULT 0 NOT NULL, tokens_output integer DEFAULT 0 NOT NULL, time_created integer NOT NULL, time_updated integer NOT NULL);
              INSERT INTO session_v2 (id, project_id, slug, directory, version, model, tokens_input, tokens_output, time_created, time_updated) VALUES ('ses_test', 'proj_1', 'slug_1', '/test', '2.0', '{\"id\":\"stealth/space-bunny-alpha\",\"providerID\":\"openrouter\"}', 12000, 4500, 1000, 1790264509833);")
        .status();

    if let Ok(st) = status {
        if st.success() {
            let res = AiActivityMonitor::query_opencode_latest_session(temp_home.path());
            assert!(res.is_some(), "query_opencode_latest_session must extract row from SQLite");
            let (model_id, total_tokens, time_updated) = res.unwrap();
            assert_eq!(model_id, "stealth/space-bunny-alpha");
            assert_eq!(total_tokens, 16500);
            assert_eq!(time_updated, 1790264509833);
        }
    }
}

#[test]
fn test_resolve_codex_models() {
    let id1 = resolve_model_metadata("gpt-5.5", "codex");
    assert_eq!(id1.tool_source, "openai");
    assert_eq!(id1.brand_color, "#10A37F");
    assert_eq!(id1.brand_icon, "terminal");
    assert_eq!(id1.display_name, "GPT-5.5");

    let id2 = resolve_model_metadata("o3-mini", "codex");
    assert_eq!(id2.tool_source, "openai");
    assert_eq!(id2.brand_color, "#10A37F");
    assert_eq!(id2.display_name, "OpenAI o3-mini");

    let id3 = resolve_model_metadata("gpt-4o", "codex");
    assert_eq!(id3.tool_source, "openai");
    assert_eq!(id3.display_name, "GPT-4o");
}

#[test]
fn test_resolve_dsh_models() {
    let id1 = resolve_model_metadata("muse-spark-1.3", "dsh");
    assert_eq!(id1.tool_source, "dsh");
    assert_eq!(id1.brand_color, "#06B6D4");
    assert_eq!(id1.brand_icon, "bolt");
    assert_eq!(id1.display_name, "Muse Spark 1.3");

    let id2 = resolve_model_metadata("", "dsh");
    assert_eq!(id2.tool_source, "dsh");
    assert_eq!(id2.brand_color, "#06B6D4");
    assert_eq!(id2.brand_icon, "bolt");
    assert_eq!(id2.display_name, "DSH Agent");
}

#[test]
fn test_resolve_cursor_and_windsurf() {
    let id_cursor = resolve_model_metadata("claude-3-7-sonnet", "cursor");
    assert_eq!(id_cursor.tool_source, "cursor");
    assert_eq!(id_cursor.brand_color, "#6366F1");
    assert_eq!(id_cursor.brand_icon, "smart_toy");
    assert_eq!(id_cursor.display_name, "Claude 3.7 Sonnet");

    let id_cursor_generic = resolve_model_metadata("", "cursor");
    assert_eq!(id_cursor_generic.tool_source, "cursor");
    assert_eq!(id_cursor_generic.brand_color, "#6366F1");
    assert_eq!(id_cursor_generic.brand_icon, "smart_toy");
    assert_eq!(id_cursor_generic.display_name, "Cursor");

    let id_windsurf = resolve_model_metadata("", "windsurf");
    assert_eq!(id_windsurf.tool_source, "windsurf");
    assert_eq!(id_windsurf.brand_color, "#0EA5E9");
    assert_eq!(id_windsurf.brand_icon, "waves");
    assert_eq!(id_windsurf.display_name, "Windsurf Cascade");
}

#[test]
fn test_codex_token_and_model_extraction() {
    use astral_plasma::infrastructure::ai_activity_monitor::{extract_model_from_json_line, extract_tokens_from_json_line};

    // Codex turn_context with model
    let model_line = r#"{"type":"turn_context","payload":{"model":"gpt-5.5","model_provider":"openai"}}"#;
    let extracted_model = extract_model_from_json_line(model_line);
    assert!(extracted_model.is_some());
    let (m, prov) = extracted_model.unwrap();
    assert_eq!(m, "gpt-5.5");
    assert_eq!(prov, "openai");

    // Codex event_msg with token usage
    let token_line = r#"{"type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"total_tokens":4250,"input_tokens":3800,"output_tokens":450}}}}"#;
    let tokens = extract_tokens_from_json_line(token_line);
    assert_eq!(tokens, Some(4250));
}

#[tokio::test]
async fn test_concurrent_multi_agent_three_tools_simultaneous() {
    use astral_plasma::infrastructure::ai_activity_monitor::AiActivityMonitor;
    let monitor = AiActivityMonitor::new();

    // 1. Start Codex (GPT-5.5)
    monitor.record_activity_with_tokens("gpt-5.5", "codex", Some(4000)).await;
    let st1 = monitor.get_state().await;
    assert_eq!(st1.active_agents.len(), 1);
    assert_eq!(st1.active_agents[0].display_name, "GPT-5.5");

    tokio::time::sleep(tokio::time::Duration::from_millis(5)).await;

    // 2. Concurrently start OpenCode (Space Bunny Alpha)
    monitor.record_activity_with_tokens("stealth/space-bunny-alpha", "opencode", Some(8000)).await;
    let st2 = monitor.get_state().await;
    assert_eq!(st2.active_agents.len(), 2, "Both Codex and OpenCode must be active simultaneously without overwriting");

    tokio::time::sleep(tokio::time::Duration::from_millis(5)).await;

    // 3. Concurrently start DSH (Muse Spark 1.3)
    monitor.record_activity_with_tokens("muse-spark-1.3", "dsh", Some(3500)).await;
    let st3 = monitor.get_state().await;
    assert_eq!(st3.active_agents.len(), 3, "All three agents (Codex, OpenCode, DSH) must be tracked concurrently in active_agents");

    // Ensure order is most recent first
    assert_eq!(st3.active_agents[0].display_name, "Muse Spark 1.3");
    assert_eq!(st3.active_agents[0].tool_source, "dsh");

    assert_eq!(st3.active_agents[1].display_name, "Space Bunny Alpha");
    assert_eq!(st3.active_agents[1].tool_source, "opencode");

    assert_eq!(st3.active_agents[2].display_name, "GPT-5.5");
    assert_eq!(st3.active_agents[2].tool_source, "openai");

    // Aggregate tokens reflect total throughput across all three agents
    assert_eq!(st3.recent_tokens, 15500);
}

#[test]
fn test_check_turn_completed_antigravity() {
    use astral_plasma::infrastructure::ai_activity_monitor::check_turn_completed_from_tail;

    // 1. Tool call in-flight
    let tail_tool = r#"
{"step_index":100,"source":"MODEL","type":"PLANNER_RESPONSE","status":"DONE","tool_calls":[{"name":"view_file","args":{}}]}
"#;
    assert!(!check_turn_completed_from_tail(tail_tool, "/home/hlu/.gemini/antigravity/brain/session/logs/transcript.jsonl"));

    // 2. Final response to user (no tool calls)
    let tail_done = r#"
{"step_index":101,"source":"MODEL","type":"PLANNER_RESPONSE","status":"DONE"}
"#;
    assert!(check_turn_completed_from_tail(tail_done, "/home/hlu/.gemini/antigravity/brain/session/logs/transcript.jsonl"));

    // 3. User input received (new turn started)
    let tail_user = r#"
{"step_index":101,"source":"MODEL","type":"PLANNER_RESPONSE","status":"DONE"}
{"step_index":102,"source":"USER_EXPLICIT","type":"USER_INPUT","status":"DONE"}
"#;
    assert!(!check_turn_completed_from_tail(tail_user, "/home/hlu/.gemini/antigravity/brain/session/logs/transcript.jsonl"));
}

#[test]
fn test_check_turn_completed_claude() {
    use astral_plasma::infrastructure::ai_activity_monitor::check_turn_completed_from_tail;

    let tail_tool = r#"{"type":"message","message":{"role":"assistant","stop_reason":"tool_use"}}"#;
    assert!(!check_turn_completed_from_tail(tail_tool, "/home/hlu/.claude/projects/test.jsonl"));

    let tail_done = r#"{"type":"message","message":{"role":"assistant","stop_reason":"end_turn"}}"#;
    assert!(check_turn_completed_from_tail(tail_done, "/home/hlu/.claude/projects/test.jsonl"));
}

#[test]
fn test_check_turn_completed_codex() {
    use astral_plasma::infrastructure::ai_activity_monitor::check_turn_completed_from_tail;

    let tail_tool = r#"{"type":"event_msg","payload":{"type":"tool_call","finish_reason":"tool_calls"}}"#;
    assert!(!check_turn_completed_from_tail(tail_tool, "/home/hlu/.codex/sessions/test.jsonl"));

    let tail_done = r#"{"type":"event_msg","payload":{"type":"task_complete"}}"#;
    assert!(check_turn_completed_from_tail(tail_done, "/home/hlu/.codex/sessions/test.jsonl"));
}

#[tokio::test]
async fn test_turn_completion_decays_promptly() {
    use astral_plasma::infrastructure::ai_activity_monitor::AiActivityMonitor;
    let monitor = AiActivityMonitor::new();

    // 1. Record completed turn
    monitor.record_activity_full("gemini-flash-3.8", "antigravity", Some(500), true).await;
    let st1 = monitor.get_state().await;
    assert!(st1.is_active);
    assert_eq!(st1.active_agents.len(), 1);

    // 2. Immediately after turn completion, it stays active for the 4s window
    let _ = monitor.tick_decay().await;
    let st2 = monitor.get_state().await;
    assert_eq!(st2.active_agents.len(), 1);

    // 3. Fast-forward past the 4s completion window by updating last_event_epoch_ms
    {
        let mut tracks = monitor.agent_tracks_for_test().await;
        for (_, t) in tracks.iter_mut() {
            t.last_event_epoch_ms = t.last_event_epoch_ms.saturating_sub(4500);
        }
    }

    // Next tick prunes active_slots and initiates exponential decay immediately
    let transitioned = monitor.tick_decay().await;
    assert!(transitioned);
    let st3 = monitor.get_state().await;
    assert_eq!(st3.active_agents.len(), 0, "Agent must be pruned from active_agents after 4s completion window");
    assert!(st3.intensity < 1.0, "Intensity must immediately begin decaying");

    // Advance decay ticks until intensity < 0.05
    for _ in 0..10 {
        monitor.tick_decay().await;
    }
    let st_final = monitor.get_state().await;
    assert!(!st_final.is_active, "Monitor must smoothly transition to inactive in sub-10s instead of hanging for 1 minute");
    assert_eq!(st_final.intensity, 0.0);
}


