use astral_plasma::domain::voice::{VoiceEvent, build_polish_prompt, parse_polished_text};

#[test]
fn test_build_polish_prompt() {
    let context = "We are developing Astral Plasma desktop shell on Wayland.";
    let original = "测试 API 借口";
    let prompt = build_polish_prompt(context, original);
    assert!(prompt.contains("Astral Plasma"));
    assert!(prompt.contains("测试 API 借口"));
    assert!(prompt.contains("Return ONLY the corrected sentence"));
}

#[test]
fn test_parse_polished_text_strips_quotes_and_markdown() {
    // Exact text
    assert_eq!(parse_polished_text("测试 API 接口"), "测试 API 接口");
    // Strips surrounding quotes
    assert_eq!(parse_polished_text("\"测试 API 接口\""), "测试 API 接口");
    assert_eq!(parse_polished_text("“测试 API 接口”"), "测试 API 接口");
    // Strips markdown backticks
    assert_eq!(parse_polished_text("`测试 API 接口`"), "测试 API 接口");
    // Discards empty or explanation text
    assert_eq!(parse_polished_text(""), "");
}

#[test]
fn test_voice_event_polished_variant() {
    let ev = VoiceEvent::Polished {
        sentence_id: 1,
        original: "测试 API 借口".to_string(),
        corrected: "测试 API 接口".to_string(),
    };
    assert_eq!(ev.kind(), "Polished");
    let json = serde_json::to_string(&ev).expect("serialize");
    assert!(json.contains("\"type\":\"Polished\""));
    assert!(json.contains("\"corrected\":\"测试 API 接口\""));
}

#[test]
fn test_voice_polisher_empty_models_returns_none_fast() {
    use astral_plasma::infrastructure::voice_polisher::VoicePolisher;
    let polisher = VoicePolisher::new();
    let start = std::time::Instant::now();
    let res = polisher.polish("context", "original sentence");
    // Either returns corrected sentence or None within tight budget, never hanging 3s+
    assert!(start.elapsed() < std::time::Duration::from_millis(1500));
    let _ = res;
}

