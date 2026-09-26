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

    // 2. Immediately after turn completion, it stays active for the 3s window
    let _ = monitor.tick_decay().await;
    let st2 = monitor.get_state().await;
    assert_eq!(st2.active_agents.len(), 1);

    // 3. Fast-forward past the 3s completion window by updating last_event_epoch_ms
    {
        let mut tracks = monitor.agent_tracks_for_test().await;
        for (_, t) in tracks.iter_mut() {
            t.last_event_epoch_ms = t.last_event_epoch_ms.saturating_sub(3500);
        }
    }

    // 4. Next tick prunes active_slots and transitions to inactive immediately
    let transitioned = monitor.tick_decay().await;
    assert!(transitioned, "Monitor must signal transition when active agents expire");
    let st3 = monitor.get_state().await;
    assert_eq!(st3.active_agents.len(), 0, "Agent must be pruned from active_agents after 3s completion window");
    assert!(!st3.is_active, "Monitor must immediately transition to inactive when all agents complete");
    assert_eq!(st3.intensity, 0.0);
}

#[test]
fn test_resolve_zcode_agent_identity() {
    let id1 = resolve_model_metadata("MiniMax-M3", "zcode");
    assert_eq!(id1.tool_source, "zcode");
    assert_eq!(id1.brand_icon, "bolt"); // Resolves MiniMax inner brand icon
    assert!(id1.display_name.starts_with("ZCode · "));

    let id2 = resolve_model_metadata("086f09bb-fee7-4ce7-95e5-ebb86f376775/deepseek-v4-pro", "zcode");
    assert_eq!(id2.tool_source, "zcode");
    assert_eq!(id2.brand_icon, "smart_toy");
    assert_eq!(id2.brand_color, "#2563EB");
    assert_eq!(id2.display_name, "ZCode · DeepSeek V4");
}

#[test]
fn test_check_turn_completed_zcode() {
    use astral_plasma::infrastructure::ai_activity_monitor::check_turn_completed_from_tail;

    let path = "/home/hlu/.zcode/cli/log/zcode-2026-09-25.jsonl";

    let tail_started = r#"{"timestamp":"2026-09-25T10:00:00.000Z","event":"turn.started","context":{"turnNumber":0}}"#;
    assert!(!check_turn_completed_from_tail(tail_started, path));

    let tail_tool = r#"{"timestamp":"2026-09-25T10:00:05.000Z","event":"model.request.completed","context":{"finishReason":"tool-calls"}}"#;
    assert!(!check_turn_completed_from_tail(tail_tool, path));

    let tail_stop = r#"{"timestamp":"2026-09-25T10:00:10.000Z","event":"model.request.completed","context":{"finishReason":"stop"}}"#;
    assert!(check_turn_completed_from_tail(tail_stop, path));

    let tail_completed = r#"{"timestamp":"2026-09-25T10:00:15.000Z","event":"turn.completed","context":{"turnNumber":0,"toolCallCount":5}}"#;
    assert!(check_turn_completed_from_tail(tail_completed, path));
}

#[test]
fn test_extract_model_from_zcode_jsonl() {
    use astral_plasma::infrastructure::ai_activity_monitor::extract_model_from_json_line;

    let line1 = r#"{"event":"model.request.completed","context":{"modelId":"muse-spark-1.3-contributor","providerId":"opencode-go-responses"}}"#;
    let res1 = extract_model_from_json_line(line1);
    assert_eq!(res1, Some(("muse-spark-1.3-contributor".to_string(), "opencode-go-responses".to_string())));

    let line2 = r#"{"event":"bootstrap.app.startup","context":{"model":"086f09bb-fee7-4ce7-95e5-ebb86f376775/deepseek-v4-pro"}}"#;
    let res2 = extract_model_from_json_line(line2);
    assert_eq!(res2, Some(("deepseek-v4-pro".to_string(), String::new())));
}

#[tokio::test]
async fn test_in_flight_sustains_across_multi_second_tool_runs() {
    use astral_plasma::infrastructure::ai_activity_monitor::AiActivityMonitor;

    let monitor = AiActivityMonitor::new();
    // Simulate an in-flight tool execution (is_completed = false)
    monitor.record_activity_full("gemini-3.8-flash", "gemini", Some(500), false).await;

    let st1 = monitor.get_state().await;
    assert!(st1.is_active, "Monitor must be active when in-flight tool starts");

    // Advance time by 20 seconds (greater than old 12s timeout)
    {
        let mut tracks = monitor.agent_tracks_for_test().await;
        for (_, t) in tracks.iter_mut() {
            t.last_event_epoch_ms = t.last_event_epoch_ms.saturating_sub(20_000);
        }
    }

    // Tick decay: since IN_FLIGHT_WINDOW_MS is 120s, it MUST remain active!
    monitor.tick_decay().await;
    let st2 = monitor.get_state().await;
    assert!(st2.is_active, "In-flight tool execution at 20s must NOT decay prematurely");
    assert_eq!(st2.active_agents.len(), 1, "Agent track must be retained during in-flight operation");

    // Now turn finishes (is_completed = true)
    monitor.record_activity_full("gemini-3.8-flash", "gemini", Some(120), true).await;

    // Advance by 4 seconds (greater than 3s COMPLETED_WINDOW_MS)
    {
        let mut tracks = monitor.agent_tracks_for_test().await;
        for (_, t) in tracks.iter_mut() {
            t.last_event_epoch_ms = t.last_event_epoch_ms.saturating_sub(4_000);
        }
    }

    monitor.tick_decay().await;
    let st3 = monitor.get_state().await;
    assert!(!st3.is_active, "Turn completion must promptly decay after the 3s completion window");
    assert_eq!(st3.active_agents.len(), 0);
}

#[test]
fn test_zcode_idle_memory_sample_log_is_not_active() {
    use astral_plasma::infrastructure::ai_activity_monitor::check_turn_completed_from_tail;

    let path = "/home/hlu/.zcode/cli/log/zcode-2026-09-25.jsonl";
    let tail_memory_sample = r#"
{"timestamp":"2026-09-25T20:52:23.951Z","level":"info","event":"zcode_protocol.process.memory_sample","module":"bootstrap.zcode_protocol","message":"Process memory sample","context":{"entrypoint":"zcode_protocol","reason":"heartbeat","rssKb":197096}}
{"timestamp":"2026-09-25T20:52:28.392Z","level":"info","event":"zcode_protocol.process.memory_sample","module":"bootstrap.zcode_protocol","message":"Process memory sample","context":{"entrypoint":"zcode_protocol","reason":"changed","rssKb":197368}}
"#;

    // Periodic memory sample heartbeat must be completed/idle, NEVER in-flight
    assert!(check_turn_completed_from_tail(tail_memory_sample, path),
        "ZCode memory samples must be treated as completed/idle, never in-flight");
}

#[test]
fn test_zcode_rollout_model_io_detection() {
    use astral_plasma::infrastructure::ai_activity_monitor::{check_turn_completed_from_tail, extract_model_from_json_line, extract_tokens_from_json_line};

    let path = "/home/hlu/.zcode/cli/rollout/model-io-sess_dcce4627-4286-456b-9203-d3fc612e8d85.jsonl";

    // 1. Tool execution in flight
    let tail_tool = r#"{"type":"model_io","sessionId":"sess_1","turnId":"turn_1","response":{"modelId":"deepseek-v4.1-flash","finishReason":"tool-calls","usage":{"inputTokens":800,"outputTokens":200,"totalTokens":1000}}}"#;
    assert!(!check_turn_completed_from_tail(tail_tool, path), "tool-calls finishReason must be in-flight");

    let model = extract_model_from_json_line(tail_tool);
    assert_eq!(model, Some(("deepseek-v4.1-flash".to_string(), String::new())));

    let tokens = extract_tokens_from_json_line(tail_tool);
    assert_eq!(tokens, Some(1000));

    // 2. Turn completed
    let tail_stop = r#"{"type":"model_io","sessionId":"sess_1","turnId":"turn_1","response":{"modelId":"deepseek-v4.1-flash","finishReason":"stop","usage":{"inputTokens":800,"outputTokens":500,"totalTokens":1300}}}"#;
    assert!(check_turn_completed_from_tail(tail_stop, path), "stop finishReason must be completed");
}

#[test]
fn test_pi_omp_turn_completion_detection() {
    use astral_plasma::infrastructure::ai_activity_monitor::check_turn_completed_from_tail;

    let pi_path = "/home/hlu/.pi/agent/sessions/--test--/session.jsonl";
    let omp_path = "/home/hlu/.omp/agent/sessions/--test--/session.jsonl";

    // 1. Assistant tool call in progress -> in-flight
    let tail_tool = r#"{"type":"message","message":{"role":"assistant","stopReason":"toolUse","model":"mimo-v2.6-flash"}}"#;
    assert!(!check_turn_completed_from_tail(tail_tool, pi_path), "toolUse in Pi session must be in-flight");
    assert!(!check_turn_completed_from_tail(tail_tool, omp_path), "toolUse in OMP session must be in-flight");

    // 2. User input sent -> in-flight
    let tail_user = r#"{"type":"message","message":{"role":"user","content":[{"type":"text","text":"hello"}]}}"#;
    assert!(!check_turn_completed_from_tail(tail_user, pi_path), "User input in Pi session must be in-flight");

    // 3. Final stop -> completed
    let tail_stop = r#"{"type":"message","message":{"role":"assistant","stopReason":"stop","model":"mimo-v2.6-flash"}}"#;
    assert!(check_turn_completed_from_tail(tail_stop, pi_path), "stop in Pi session must be completed");
    assert!(check_turn_completed_from_tail(tail_stop, omp_path), "stop in OMP session must be completed");
}

#[test]
fn test_idle_transcript_defaults_to_completed() {
    use astral_plasma::infrastructure::ai_activity_monitor::check_turn_completed_from_tail;

    // A transcript tail that doesn't have an active in-flight request must return completed (true)
    let idle_tail = r#"{"status":"idle","message":"session initialized"}"#;
    assert!(check_turn_completed_from_tail(idle_tail, "/home/hlu/.gemini/antigravity/brain/sess/logs/transcript.jsonl"),
        "Idle transcript without active input/tools must default to completed");
    assert!(check_turn_completed_from_tail(idle_tail, "/home/hlu/.claude/projects/sess.jsonl"),
        "Idle Claude log without tool_use must default to completed");
}

#[test]
fn test_ai_activity_use_case_application_port_contract() {
    use astral_plasma::application::ai_activity_service::AiActivityUseCase;
    use astral_plasma::domain::ports::AiActivityPort;
    use astral_plasma::domain::ai_activity::AiActivityState;
    use std::sync::Arc;

    struct MockAiPort {
        state: std::sync::Mutex<AiActivityState>,
    }

    impl AiActivityPort for MockAiPort {
        fn get_state_sync(&self) -> AiActivityState {
            self.state.lock().unwrap().clone()
        }
        fn record_activity_sync(&self, raw_model: &str, tool_source: &str, _tokens: Option<u64>, _is_completed: bool) {
            let mut st = self.state.lock().unwrap();
            st.identity.model_id = raw_model.to_string();
            st.identity.tool_source = tool_source.to_string();
            st.is_active = true;
        }
        fn tick_decay_sync(&self) -> bool {
            true
        }
        fn query_active_state_sync(&self) -> AiActivityState {
            self.get_state_sync()
        }
        fn start_background_watcher(&self) {}
    }

    let mock_port = Arc::new(MockAiPort {
        state: std::sync::Mutex::new(AiActivityState::default()),
    });

    let use_case = AiActivityUseCase::new(mock_port);
    let initial = use_case.get_state();
    assert!(!initial.is_active);

    use_case.record_activity("custom-model-v1", "test-tool", Some(100), false);
    let after = use_case.query_current_state();
    assert!(after.is_active);
    assert_eq!(after.identity.model_id, "custom-model-v1");
    assert_eq!(after.identity.tool_source, "test-tool");
    assert!(use_case.tick_decay());
}

#[test]
fn test_adapter_registry_routes_to_specialized_adapters() {
    use astral_plasma::infrastructure::ai_adapters::AdapterRegistry;
    use std::path::Path;

    let registry = AdapterRegistry::new();
    assert!(registry.adapters().len() >= 9, "Registry must contain all specialized adapters");

    // Antigravity
    let ad_anti = registry.find_adapter_for_path(Path::new("/home/user/.gemini/antigravity/brain/session1/.system_generated/logs/transcript.jsonl"));
    assert!(ad_anti.is_some());
    assert_eq!(ad_anti.unwrap().tool_id(), "antigravity");

    // Claude
    let ad_claude = registry.find_adapter_for_path(Path::new("/home/user/.claude/sessions/session1.jsonl"));
    assert!(ad_claude.is_some());
    assert_eq!(ad_claude.unwrap().tool_id(), "claude");

    // Codex
    let ad_codex = registry.find_adapter_for_path(Path::new("/home/user/.codex/sessions/session1.jsonl"));
    assert!(ad_codex.is_some());
    assert_eq!(ad_codex.unwrap().tool_id(), "codex");

    // Pi
    let ad_pi = registry.find_adapter_for_path(Path::new("/home/user/.pi/agent/sessions/test/session.jsonl"));
    assert!(ad_pi.is_some());
    assert_eq!(ad_pi.unwrap().tool_id(), "pi");

    // Omp
    let ad_omp = registry.find_adapter_for_path(Path::new("/home/user/.omp/agent/sessions/test/session.jsonl"));
    assert!(ad_omp.is_some());
    assert_eq!(ad_omp.unwrap().tool_id(), "omp");

    // ZCode
    let ad_zcode = registry.find_adapter_for_path(Path::new("/home/user/.zcode/cli/rollout/model-io.jsonl"));
    assert!(ad_zcode.is_some());
    assert_eq!(ad_zcode.unwrap().tool_id(), "zcode");

    // OpenCode
    let ad_open = registry.find_adapter_for_path(Path::new("/home/user/.local/share/opencode/opencode.db"));
    assert!(ad_open.is_some());
    assert_eq!(ad_open.unwrap().tool_id(), "opencode");

    // Dsh
    let ad_dsh = registry.find_adapter_for_path(Path::new("/home/user/.dsh/sessions/s1/sub/session.lock"));
    assert!(ad_dsh.is_some());
    assert_eq!(ad_dsh.unwrap().tool_id(), "dsh");

    // IDE
    let ad_cursor = registry.find_adapter_for_path(Path::new("/home/user/.config/Cursor/session.json"));
    assert!(ad_cursor.is_some());
    assert_eq!(ad_cursor.unwrap().tool_id(), "ide");
}

#[test]
fn test_data_driven_catalog_table_declarative() {
    use astral_plasma::domain::ai_activity::STATIC_BRAND_RULES;

    assert!(STATIC_BRAND_RULES.len() >= 15, "Static brand catalog must contain all defined agent brand rules");

    let claude_rule = STATIC_BRAND_RULES.iter().find(|r| r.tool_id == "claude");
    assert!(claude_rule.is_some());
    let cr = claude_rule.unwrap();
    assert_eq!(cr.brand_color, "#D97706");
    assert_eq!(cr.brand_icon, "psychology");

    let gemini_rule = STATIC_BRAND_RULES.iter().find(|r| r.tool_id == "gemini");
    assert!(gemini_rule.is_some());
    let gr = gemini_rule.unwrap();
    assert_eq!(gr.brand_color, "#818CF8");
    assert_eq!(gr.brand_icon, "auto_awesome");
}



