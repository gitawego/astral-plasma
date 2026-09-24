use astral_plasma::domain::ai_activity::{resolve_model_metadata, AiActivityState};

#[test]
fn test_resolve_mimo_xiaomi_model() {
    let id1 = resolve_model_metadata("opencode-go/mimo-v2.6-flash", "omp");
    assert_eq!(id1.tool_source, "mimo");
    assert_eq!(id1.brand_color, "#FF6900");
    assert_eq!(id1.brand_icon, "devices");
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
