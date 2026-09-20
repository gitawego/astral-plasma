use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum CheckStatus {
    Pass,
    Warning,
    Fail,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct DependencyCheck {
    pub name: String,
    pub category: String,
    pub required: bool,
    pub status: CheckStatus,
    pub installed: bool,
    pub detected_version: Option<String>,
    pub required_version: Option<String>,
    pub binary_path: Option<String>,
    pub message: String,
    pub recommendation: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct DoctorReport {
    pub checks: Vec<DependencyCheck>,
    pub all_required_satisfied: bool,
    pub summary: String,
}

pub fn parse_semver(v: &str) -> Option<(u32, u32, u32)> {
    let cleaned = v.trim_start_matches(|c: char| !c.is_ascii_digit());
    let parts: Vec<&str> = cleaned.split('.').collect();
    if parts.is_empty() {
        return None;
    }
    let major: u32 = parts[0].split(|c: char| !c.is_ascii_digit()).next()?.parse().ok()?;
    let minor: u32 = parts.get(1)
        .and_then(|s| s.split(|c: char| !c.is_ascii_digit()).next())
        .and_then(|s| s.parse().ok())
        .unwrap_or(0);
    let patch: u32 = parts.get(2)
        .and_then(|s| s.split(|c: char| !c.is_ascii_digit()).next())
        .and_then(|s| s.parse().ok())
        .unwrap_or(0);
    Some((major, minor, patch))
}

pub fn is_version_compatible(detected: &str, required: &str) -> bool {
    if let (Some(det), Some(req)) = (parse_semver(detected), parse_semver(required)) {
        det >= req
    } else {
        false
    }
}

impl DoctorReport {
    pub fn new(checks: Vec<DependencyCheck>) -> Self {
        let all_required_satisfied = checks.iter().all(|c| !c.required || c.status == CheckStatus::Pass);
        let summary = if all_required_satisfied {
            "All required dependencies are satisfied! Astral Plasma is ready to run.".to_string()
        } else {
            "Some required dependencies are missing or outdated. Please review the errors above.".to_string()
        };
        Self {
            checks,
            all_required_satisfied,
            summary,
        }
    }

    pub fn render_terminal(&self) -> String {
        let mut out = String::new();
        out.push_str("\n===================================================================\n");
        out.push_str("                   ASTRAL PLASMA SYSTEM DOCTOR                     \n");
        out.push_str("===================================================================\n");

        let categories = [
            "Core Display Engine",
            "Desktop & Window Manager",
            "IPC & Audio Subsystem",
            "Optional Enhancements",
        ];

        for cat in &categories {
            let cat_checks: Vec<&DependencyCheck> = self.checks.iter().filter(|c| c.category == *cat).collect();
            if cat_checks.is_empty() {
                continue;
            }

            out.push_str(&format!("\n▶ {}\n", cat));
            for check in cat_checks {
                let badge = match check.status {
                    CheckStatus::Pass => "\x1b[32m[✓]\x1b[0m",
                    CheckStatus::Warning => "\x1b[33m[!]\x1b[0m",
                    CheckStatus::Fail => "\x1b[31m[✗]\x1b[0m",
                };

                let req_badge = if check.required {
                    ""
                } else {
                    " (optional)"
                };

                out.push_str(&format!("  {} {}{}: {}\n", badge, check.name, req_badge, check.message));

                if let Some(ref path) = check.binary_path {
                    out.push_str(&format!("      Path:    {}\n", path));
                }
                if let (Some(ref det), Some(ref req)) = (&check.detected_version, &check.required_version) {
                    out.push_str(&format!("      Version: {} (minimum required: >= {})\n", det, req));
                } else if let Some(ref det) = check.detected_version {
                    out.push_str(&format!("      Version: {}\n", det));
                }

                if let Some(ref rec) = check.recommendation {
                    out.push_str(&format!("      \x1b[36mAction:  {}\x1b[0m\n", rec));
                }
            }
        }

        out.push_str("\n===================================================================\n");
        if self.all_required_satisfied {
            out.push_str(&format!("\x1b[32mStatus: {}\x1b[0m\n\n", self.summary));
        } else {
            out.push_str(&format!("\x1b[31mStatus: {}\x1b[0m\n\n", self.summary));
        }

        out
    }
}
