use astral_plasma::domain::tool_scanner::ToolConfigScanner;
use astral_plasma::infrastructure::scanners::{
    OmpScanner, OpenCodeScanner, PiScanner, ToolConfigAggregator,
};
use std::fs;
use tempfile::tempdir;

#[test]
fn test_pi_scanner_deterministic_extraction() {
    let dir = tempdir().expect("Failed to create tempdir");
    let auth_path = dir.path().join("auth.json");

    let auth_content = r#"{
        "opencode-go": {
            "type": "api_key",
            "key": "sk-opencode-test-12345"
        },
        "minimax-cn": {
            "type": "api_key",
            "key": "sk-minimax-test-67890"
        }
    }"#;
    fs::write(&auth_path, auth_content).expect("Failed to write auth.json");

    let scanner = PiScanner::with_base_dir(dir.path().to_path_buf());
    let creds = scanner.scan();

    assert_eq!(creds.len(), 2, "Expected 2 credentials from PiScanner");

    let opencode = creds.iter().find(|c| c.provider_id == "opencode-go");
    assert!(opencode.is_some());
    assert_eq!(opencode.unwrap().credential, "sk-opencode-test-12345");
    assert_eq!(opencode.unwrap().tool_source, "pi");

    let minimax = creds.iter().find(|c| c.provider_id == "minimax-cn");
    assert!(minimax.is_some());
    assert_eq!(minimax.unwrap().credential, "sk-minimax-test-67890");
    assert_eq!(minimax.unwrap().tool_source, "pi");
}

#[test]
fn test_omp_scanner_deterministic_yaml_extraction() {
    let dir = tempdir().expect("Failed to create tempdir");
    let models_path = dir.path().join("models.yml");

    // Set a test env var for resolution
    std::env::set_var("TEST_MINIMAX_ENV_KEY_XYZ", "sk-minimax-from-env-999");

    let yaml_content = r#"
providers:
  minimax-cn:
    baseUrl: https://api.minimaxi.com/anthropic
    apiKey: TEST_MINIMAX_ENV_KEY_XYZ
    api: anthropic-messages
  ark-code:
    baseUrl: http://localhost:9876/api/proxy/omp/ark-code
    apiKey: acs_ark_direct_key_888
  unresolved-provider:
    apiKey: NON_EXISTENT_ENV_VAR_12345
"#;
    fs::write(&models_path, yaml_content).expect("Failed to write models.yml");

    let scanner = OmpScanner::with_base_dir(dir.path().to_path_buf());
    let creds = scanner.scan();

    let minimax = creds.iter().find(|c| c.provider_id == "minimax-cn");
    assert!(minimax.is_some());
    assert_eq!(
        minimax.unwrap().credential,
        "sk-minimax-from-env-999",
        "Should resolve environment variable"
    );
    assert_eq!(
        minimax.unwrap().base_url.as_deref(),
        Some("https://api.minimaxi.com/anthropic")
    );

    let ark = creds.iter().find(|c| c.provider_id == "ark-code");
    assert!(ark.is_some());
    assert_eq!(ark.unwrap().credential, "acs_ark_direct_key_888");

    // Unresolved env vars must NOT produce credentials
    let unresolved = creds.iter().find(|c| c.provider_id == "unresolved-provider");
    assert!(
        unresolved.is_none(),
        "Unresolved environment variable must be excluded"
    );
}

#[test]
fn test_opencode_scanner_file_and_literal_resolution() {
    let dir = tempdir().expect("Failed to create tempdir");
    let opencode_json_path = dir.path().join("opencode.json");
    let secret_file_path = dir.path().join("meta-api-key");

    fs::write(&secret_file_path, "acs_secret_from_external_file_777\n")
        .expect("Failed to write secret file");

    let opencode_content = format!(
        r#"{{
  "provider": {{
    "ollama": {{
      "options": {{
        "baseURL": "http://localhost:9876/api/proxy/opencode/ollama",
        "apiKey": "acs_literal_ollama_key_111"
      }}
    }},
    "meta": {{
      "options": {{
        "baseURL": "https://api.meta.ai/v1",
        "apiKey": "{{file://{}}}"
      }}
    }}
  }}
}}"#,
        secret_file_path.display()
    );

    fs::write(&opencode_json_path, opencode_content).expect("Failed to write opencode.json");

    let scanner = OpenCodeScanner::with_base_dir(dir.path().to_path_buf());
    let creds = scanner.scan();

    let ollama = creds.iter().find(|c| c.provider_id == "ollama");
    assert!(ollama.is_some());
    assert_eq!(ollama.unwrap().credential, "acs_literal_ollama_key_111");

    let meta = creds.iter().find(|c| c.provider_id == "meta");
    assert!(meta.is_some());
    assert_eq!(
        meta.unwrap().credential,
        "acs_secret_from_external_file_777",
        "Should resolve file:// path"
    );
}

#[test]
fn test_aggregator_finds_best_matching_credential() {
    let dir_pi = tempdir().expect("Failed to create tempdir");
    let dir_omp = tempdir().expect("Failed to create tempdir");

    let auth_content = r#"{
        "minimax-cn": {
            "type": "api_key",
            "key": "sk-pi-minimax-key"
        }
    }"#;
    fs::write(dir_pi.path().join("auth.json"), auth_content).unwrap();

    let yaml_content = r#"
providers:
  ark-code:
    apiKey: acs_omp_ark_key
"#;
    fs::write(dir_omp.path().join("models.yml"), yaml_content).unwrap();

    let aggregator = ToolConfigAggregator::with_scanners(vec![
        Box::new(PiScanner::with_base_dir(dir_pi.path().to_path_buf())),
        Box::new(OmpScanner::with_base_dir(dir_omp.path().to_path_buf())),
    ]);

    let cred = aggregator.find_credential_for("minimax-cn", &["minimax"]);
    assert!(cred.is_some());
    assert_eq!(cred.unwrap().credential, "sk-pi-minimax-key");

    let ark = aggregator.find_credential_for("ark-code", &["ark"]);
    assert!(ark.is_some());
    assert_eq!(ark.unwrap().credential, "acs_omp_ark_key");

    let missing = aggregator.find_credential_for("non-existent-provider", &[]);
    assert!(missing.is_none());
}
