use astral_plasma::domain::voice::{
    filter_allowed_languages, resolve_effective_language, VoiceSettings,
};

#[test]
fn test_filter_allowed_languages() {
    let allowed = vec!["zh".to_string(), "en".to_string(), "fr".to_string()];
    
    // Exact match in allowed set
    assert_eq!(filter_allowed_languages("zh", &allowed), Some("zh".to_string()));
    assert_eq!(filter_allowed_languages("en", &allowed), Some("en".to_string()));
    assert_eq!(filter_allowed_languages("fr", &allowed), Some("fr".to_string()));

    // Region code mapping (zh-CN -> zh, fr-FR -> fr)
    assert_eq!(filter_allowed_languages("zh-CN", &allowed), Some("zh".to_string()));
    assert_eq!(filter_allowed_languages("fr-FR", &allowed), Some("fr".to_string()));

    // Language outside allowed set is rejected
    assert_eq!(filter_allowed_languages("ja", &allowed), None);
    assert_eq!(filter_allowed_languages("de", &allowed), None);
}

#[test]
fn test_resolve_effective_language_with_allowed_set() {
    let allowed = vec!["zh".to_string(), "en".to_string()];
    
    // When detected language is in allowed set, it stands
    assert_eq!(resolve_effective_language(Some("zh"), &allowed, "en"), "zh");
    assert_eq!(resolve_effective_language(Some("en"), &allowed, "en"), "en");

    // When detected language is outside allowed set (e.g. spurious Japanese detection),
    // it falls back safely to default allowed language (or fallback)
    assert_eq!(resolve_effective_language(Some("ja"), &allowed, "zh"), "zh");
    assert_eq!(resolve_effective_language(None, &allowed, "en"), "en");
}

#[test]
fn test_voice_settings_languages_field() {
    let mut settings = VoiceSettings::default();
    assert!(settings.languages.is_empty() || settings.languages.contains(&"en".to_string()));

    settings.languages = vec!["zh".to_string(), "en".to_string(), "fr".to_string()];
    let sanitized = settings.sanitized();
    assert_eq!(sanitized.languages, vec!["zh".to_string(), "en".to_string(), "fr".to_string()]);
}

#[test]
fn test_build_args_emits_prompt_when_supported() {
    use astral_plasma::domain::voice::EngineCapabilities;
    use astral_plasma::infrastructure::whisper_stt_adapter::{build_args, EngineInvocation};
    use std::path::{Path, PathBuf};

    let mut inv = EngineInvocation {
        binary: PathBuf::from("/usr/bin/whisper-cli"),
        model: PathBuf::from("/models/ggml-base.bin"),
        language: "auto".into(),
        fallback_language: "en".to_string(),
        allowed_languages: vec!["en".to_string(), "zh".to_string()],
        prompt: Some("Astral Plasma context".to_string()),
        threads: 4,
        capabilities: EngineCapabilities {
            prompt: true,
            ..Default::default()
        },
    };

    let args = build_args(&inv, Path::new("/tmp/test.wav"), 1000);
    assert!(args.windows(2).any(|w| w[0] == "--prompt" && w[1] == "Astral Plasma context"));

    // If prompt capability is false, flag is omitted
    inv.capabilities.prompt = false;
    let args2 = build_args(&inv, Path::new("/tmp/test.wav"), 1000);
    assert!(!args2.iter().any(|a| a == "--prompt"));
}

