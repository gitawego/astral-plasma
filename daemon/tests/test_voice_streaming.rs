use astral_plasma::domain::voice::{
    tokenize_for_agreement, LocalAgreement, build_voice_prompt,
};

#[test]
fn test_tokenize_for_agreement_english() {
    let tokens = tokenize_for_agreement("Hello world, how are you?");
    assert_eq!(tokens, vec!["Hello", "world,", "how", "are", "you?"]);
}

#[test]
fn test_tokenize_for_agreement_cjk() {
    let tokens = tokenize_for_agreement("你好世界");
    assert_eq!(tokens, vec!["你", "好", "世", "界"]);
}

#[test]
fn test_tokenize_for_agreement_mixed_code_switch() {
    let tokens = tokenize_for_agreement("测试 API 接口 v2");
    assert_eq!(tokens, vec!["测", "试", "API", "接", "口", "v2"]);
}

#[test]
fn test_local_agreement_commits_common_prefix() {
    let mut la = LocalAgreement::new(2); // require 2 consecutive agreements
    
    // Window 1: tentative hypothesis
    let (committed, partial) = la.feed("hello world");
    assert_eq!(committed, "");
    assert_eq!(partial, "hello world");

    // Window 2: "hello world" matches again, but now extends with "how are"
    let (committed, partial) = la.feed("hello world how are");
    assert_eq!(committed, "hello world");
    assert_eq!(partial, "how are");

    // Window 3: "how are" matches again, extends with "you"
    let (committed, partial) = la.feed("hello world how are you");
    assert_eq!(committed, "how are");
    assert_eq!(partial, "you");
}

#[test]
fn test_local_agreement_cjk_character_stream() {
    let mut la = LocalAgreement::new(2);

    let (committed1, partial1) = la.feed("你好");
    assert_eq!(committed1, "");
    assert_eq!(partial1, "你好");

    let (committed2, partial2) = la.feed("你好世界");
    assert_eq!(committed2, "你好");
    assert_eq!(partial2, "世界");

    let (committed3, partial3) = la.feed("你好世界真美");
    assert_eq!(committed3, "世界");
    assert_eq!(partial3, "真美");
}

#[test]
fn test_build_voice_prompt_with_history_and_vocab() {
    let history = vec![
        "What is the system status?".to_string(),
        "Everything is running smoothly.".to_string(),
    ];
    let composer = "Please restart the";
    let vocab = vec!["PipeWire".to_string(), "Wayland".to_string(), "Astral Plasma".to_string()];

    let prompt = build_voice_prompt(&history, composer, &vocab);
    assert!(prompt.contains("PipeWire"));
    assert!(prompt.contains("Astral Plasma"));
    assert!(prompt.contains("Please restart the"));
    assert!(prompt.contains("Everything is running smoothly."));
}

#[test]
fn test_streaming_decoder_poll_events_emits_commit_and_partial() {
    use astral_plasma::domain::voice::VoiceEvent;

    let (_tx_in, rx_in) = std::sync::mpsc::sync_channel::<Option<Vec<u8>>>(1);
    let (tx_out, rx_out) = std::sync::mpsc::sync_channel::<String>(8);
    drop(rx_in);

    let mut decoder = astral_plasma::infrastructure::whisper_stt_adapter::StreamingDecoder::with_receiver(
        rx_out,
        42,
    );

    let mut emitted = Vec::new();

    // Send first hypothesis
    tx_out.send("hello world".to_string()).unwrap();
    decoder.poll_events(&mut |ev| emitted.push(ev));

    assert_eq!(emitted.len(), 1);
    assert_eq!(emitted[0], VoiceEvent::Partial { text: "hello world".to_string() });
    emitted.clear();

    // Send second hypothesis extending "hello world"
    tx_out.send("hello world how are you".to_string()).unwrap();
    decoder.poll_events(&mut |ev| emitted.push(ev));

    assert_eq!(emitted.len(), 2);
    assert_eq!(emitted[0], VoiceEvent::Commit { sentence_id: 42, text: "hello world".to_string() });
    assert_eq!(emitted[1], VoiceEvent::Partial { text: "how are you".to_string() });
    assert_eq!(decoder.committed_text, "hello world");
    assert_eq!(decoder.partial_text, "how are you");
}

