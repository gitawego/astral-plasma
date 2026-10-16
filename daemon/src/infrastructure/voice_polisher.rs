//! LLM-based sentence auto-correction and contextual proofreading.
//!
//! When an LLM backend (local `llama-server` or `ollama`) is accessible,
//! a completed sentence is asynchronously polished to fix homophones, typos,
//! and mixed Chinese/English punctuation based on conversation context.

use crate::domain::voice::{build_polish_prompt, parse_polished_text};
use std::process::Command;

pub const OLLAMA_URL_ENV: &str = "ASTRAL_VOICE_OLLAMA_URL";
pub const LLAMA_SERVER_URL_ENV: &str = "ASTRAL_VOICE_LLAMA_SERVER_URL";

pub struct VoicePolisher {
    ollama_url: String,
    llama_url: String,
}

impl Default for VoicePolisher {
    fn default() -> Self {
        Self::new()
    }
}

impl VoicePolisher {
    pub fn new() -> Self {
        Self {
            ollama_url: std::env::var(OLLAMA_URL_ENV)
                .unwrap_or_else(|_| "http://127.0.0.1:11434".to_string()),
            llama_url: std::env::var(LLAMA_SERVER_URL_ENV)
                .unwrap_or_else(|_| "http://127.0.0.1:8080".to_string()),
        }
    }

    /// Polishes an ASR sentence against context. Returns `Some(corrected)` if
    /// an LLM successfully provided a cleaned correction, or `None` on failure/timeout.
    pub fn polish(&self, context: &str, original: &str) -> Option<String> {
        let trimmed = original.trim();
        if trimmed.is_empty() {
            return None;
        }

        let prompt = build_polish_prompt(context, trimmed);

        // Try llama-server /completion first if active
        if let Some(res) = self.try_llama_server(&prompt) {
            let cleaned = parse_polished_text(&res);
            if !cleaned.is_empty() && cleaned != trimmed {
                return Some(cleaned);
            }
        }

        // Try Ollama /api/generate
        if let Some(res) = self.try_ollama(&prompt) {
            let cleaned = parse_polished_text(&res);
            if !cleaned.is_empty() && cleaned != trimmed {
                return Some(cleaned);
            }
        }

        None
    }

    fn try_llama_server(&self, prompt: &str) -> Option<String> {
        let res = self.execute_llama_completion(prompt);
        if res.is_some() {
            return res;
        }

        // If not running, attempt on-demand daemon supervision if a local GGUF model is available
        if self.ensure_llama_server() {
            return self.execute_llama_completion(prompt);
        }
        None
    }

    fn execute_llama_completion(&self, prompt: &str) -> Option<String> {
        let body = serde_json::json!({
            "prompt": prompt,
            "temperature": 0.1,
            "n_predict": 128,
            "stop": ["\n", "\n\n"]
        });
        let payload = serde_json::to_string(&body).ok()?;

        let out = Command::new("curl")
            .arg("-s")
            .arg("-m")
            .arg("1") // 1s timeout
            .arg("-X")
            .arg("POST")
            .arg(format!("{}/completion", self.llama_url.trim_end_matches('/')))
            .arg("-H")
            .arg("Content-Type: application/json")
            .arg("-d")
            .arg(payload)
            .output()
            .ok()?;

        if !out.status.success() {
            return None;
        }

        let res_str = String::from_utf8_lossy(&out.stdout);
        let val: serde_json::Value = serde_json::from_str(&res_str).ok()?;
        val.get("content")
            .and_then(|v| v.as_str())
            .map(|s| s.to_string())
    }

    fn ensure_llama_server(&self) -> bool {
        // Quick health check
        if let Ok(out) = Command::new("curl")
            .arg("-s")
            .arg("-m")
            .arg("1")
            .arg(format!("{}/health", self.llama_url.trim_end_matches('/')))
            .output()
        {
            if out.status.success() {
                return true;
            }
        }

        // Locate GGUF model
        let model_path = std::env::var("ASTRAL_VOICE_LLAMA_MODEL")
            .ok()
            .map(std::path::PathBuf::from)
            .or_else(|| {
                let cache_dir = crate::domain::branding::cache_home().join("models");
                let candidate = cache_dir.join("qwen2.5-3b-instruct.gguf");
                if candidate.exists() {
                    Some(candidate)
                } else {
                    None
                }
            });

        let Some(model) = model_path else {
            return false;
        };

        let llama_bin = std::env::var("ASTRAL_VOICE_LLAMA_SERVER_BIN")
            .unwrap_or_else(|_| "llama-server".to_string());

        let mut child = match Command::new(llama_bin)
            .arg("-m")
            .arg(model)
            .arg("--port")
            .arg("8080")
            .arg("-ngl")
            .arg("99")
            .arg("--ctx-size")
            .arg("2048")
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::null())
            .spawn()
        {
            Ok(c) => c,
            Err(_) => return false,
        };

        let deadline = std::time::Instant::now() + std::time::Duration::from_secs(1);
        while std::time::Instant::now() < deadline {
            std::thread::sleep(std::time::Duration::from_millis(150));
            if let Ok(out) = Command::new("curl")
                .arg("-s")
                .arg("-m")
                .arg("1")
                .arg(format!("{}/health", self.llama_url.trim_end_matches('/')))
                .output()
            {
                if out.status.success() {
                    return true;
                }
            }
        }
        let _ = child.kill();
        false
    }

    fn try_ollama(&self, prompt: &str) -> Option<String> {
        // Query available models from Ollama
        let tags_out = Command::new("curl")
            .arg("-s")
            .arg("-m")
            .arg("1")
            .arg(format!("{}/api/tags", self.ollama_url.trim_end_matches('/')))
            .output()
            .ok()?;

        if !tags_out.status.success() {
            return None;
        }

        let tags_val: serde_json::Value =
            serde_json::from_str(&String::from_utf8_lossy(&tags_out.stdout)).ok()?;
        let models_arr = tags_val.get("models").and_then(|m| m.as_array())?;
        if models_arr.is_empty() {
            return None;
        }
        let model = models_arr
            .first()
            .and_then(|first| first.get("name"))
            .and_then(|name| name.as_str())?;

        let body = serde_json::json!({
            "model": model,
            "prompt": prompt,
            "stream": false,
            "options": {
                "temperature": 0.1,
                "num_predict": 128
            }
        });
        let payload = serde_json::to_string(&body).ok()?;

        let gen_out = Command::new("curl")
            .arg("-s")
            .arg("-m")
            .arg("1") // 1s timeout
            .arg("-X")
            .arg("POST")
            .arg(format!("{}/api/generate", self.ollama_url.trim_end_matches('/')))
            .arg("-H")
            .arg("Content-Type: application/json")
            .arg("-d")
            .arg(payload)
            .output()
            .ok()?;

        if !gen_out.status.success() {
            return None;
        }

        let gen_val: serde_json::Value =
            serde_json::from_str(&String::from_utf8_lossy(&gen_out.stdout)).ok()?;
        gen_val
            .get("response")
            .and_then(|v| v.as_str())
            .map(|s| s.to_string())
    }
}
