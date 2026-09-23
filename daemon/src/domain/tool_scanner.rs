use serde::{Deserialize, Serialize};

/// Represents an AI provider credential discovered deterministically from an AI agent tool configuration.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct DiscoveredCredential {
    /// Normalized provider identifier (e.g. "minimax-cn", "opencode-go", "xiaomi-mimo-cn", "gemini")
    pub provider_id: String,
    /// Originating tool source (e.g. "omp", "pi", "opencode", "antigravity")
    pub tool_source: String,
    /// Secret API key, token, or session credential
    pub credential: String,
    /// Optional base URL configured in the tool (e.g. custom proxy or official API)
    pub base_url: Option<String>,
    /// Optional identity / account email associated with the credential
    pub identity: Option<String>,
    /// Optional display label or model name
    pub label: Option<String>,
}

/// Domain boundary for tool-specific configuration scanners.
/// Each AI agent tool (OMP, Pi, OpenCode, Antigravity) implements this trait independently.
pub trait ToolConfigScanner: Send + Sync {
    /// Identifier of the tool (e.g. "pi", "omp", "opencode", "antigravity")
    fn tool_name(&self) -> &'static str;

    /// Deterministically scans local tool configurations and returns discovered credentials.
    fn scan(&self) -> Vec<DiscoveredCredential>;
}
