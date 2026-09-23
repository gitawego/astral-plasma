pub mod antigravity_scanner;
pub mod omp_scanner;
pub mod opencode_scanner;
pub mod pi_scanner;

use crate::domain::tool_scanner::{DiscoveredCredential, ToolConfigScanner};
pub use antigravity_scanner::AntigravityScanner;
pub use omp_scanner::OmpScanner;
pub use opencode_scanner::OpenCodeScanner;
pub use pi_scanner::PiScanner;

/// Aggregates and coordinates deterministic scans across all supported AI agent tools.
pub struct ToolConfigAggregator {
    scanners: Vec<Box<dyn ToolConfigScanner>>,
}

impl Default for ToolConfigAggregator {
    fn default() -> Self {
        Self::new()
    }
}

impl ToolConfigAggregator {
    /// Creates an aggregator with the standard suite of agent tool scanners.
    pub fn new() -> Self {
        Self {
            scanners: vec![
                Box::new(PiScanner::new()),
                Box::new(OmpScanner::new()),
                Box::new(OpenCodeScanner::new()),
                Box::new(AntigravityScanner::new()),
            ],
        }
    }

    /// Creates an aggregator with custom scanners (useful for deterministic tests).
    pub fn with_scanners(scanners: Vec<Box<dyn ToolConfigScanner>>) -> Self {
        Self { scanners }
    }

    /// Runs all registered tool scanners and returns all discovered credentials.
    pub fn scan_all(&self) -> Vec<DiscoveredCredential> {
        let mut results = Vec::new();
        for scanner in &self.scanners {
            let found = scanner.scan();
            results.extend(found);
        }
        results
    }

    /// Finds the best matching credential for a given provider ID, matching aliases.
    pub fn find_credential_for(&self, provider_id: &str, alt_keys: &[&str]) -> Option<DiscoveredCredential> {
        let all = self.scan_all();
        let target = provider_id.to_lowercase();

        // 1. Exact match on normalized provider_id
        for cred in &all {
            if cred.provider_id.to_lowercase() == target {
                return Some(cred.clone());
            }
        }

        // 2. Match against alt_keys
        for alt in alt_keys {
            let alt_target = alt.to_lowercase();
            for cred in &all {
                if cred.provider_id.to_lowercase() == alt_target {
                    return Some(cred.clone());
                }
            }
        }

        None
    }
}
