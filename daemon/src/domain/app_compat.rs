//! Compatibility: does this app fit this shell?
//!
//! ```text
//! compatible(app, host)  ⟺
//!       host.apiFloor ≤ app.kernelApi ≤ host.apiLevel
//!     ∧ ( app.minQuickshell is absent ∨ runningQuickshell ≥ app.minQuickshell )
//! ```
//!
//! `kernelApi` is the level an app was **built against**, so it is a minimum. An
//! app never declares a maximum: only the host knows what it still supports.
//! Removals bump [`APP_API_LEVEL`]; retirements bump [`APP_API_FLOOR`]; additions
//! change neither, so a new release cannot break an app that already worked.
//!
//! There are deliberately no semver ranges here. A range lets an author claim
//! combinations they never ran, and a range parser would be a second comparison
//! implementation beside [`crate::domain::update`]. Floor/level expresses exactly
//! one thing — which removals an app still needs — and reuses `version_gt`.

use std::fmt;

use crate::domain::app_manifest::Manifest;
use crate::domain::update::version_gt;

/// Highest API level this build implements.
pub const APP_API_LEVEL: u32 = 1;
/// Oldest API level this build still loads.
pub const APP_API_FLOOR: u32 = 1;

/// Level -> first platform release that introduced it.
///
/// This is how a warning can say "needs Astral 0.3.0 or newer" while enforcement
/// stays integer-exact: one constant pair, no second source of truth, and no
/// author-supplied `minAstral` that could drift from the API it claims.
pub const API_LEVEL_HISTORY: [(u32, &str); 1] = [(1, "0.2.0")];

/// The platform floor a given API level needs. Levels are dense and monotonic.
pub fn platform_for_level(level: u32) -> Option<&'static str> {
    API_LEVEL_HISTORY
        .iter()
        .find(|(entry_level, _)| *entry_level == level)
        .map(|(_, release)| *release)
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct HostApi {
    pub level: u32,
    pub floor: u32,
    /// `quickshell --version` output, when it could be read.
    pub quickshell: Option<String>,
}

impl HostApi {
    pub fn current(quickshell: Option<&str>) -> Self {
        Self {
            level: APP_API_LEVEL,
            floor: APP_API_FLOOR,
            quickshell: quickshell.map(str::to_string),
        }
    }
}

impl Default for HostApi {
    fn default() -> Self {
        Self::current(None)
    }
}

/// Why an app does not fit. Every variant carries the numbers, so the UI can
/// print them instead of a shrug.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum CompatIssue {
    /// The app was built against a newer platform than this one.
    NeedsNewerPlatform {
        required_level: u32,
        required_platform: Option<&'static str>,
        host_level: u32,
    },
    /// The app was built against a level this platform has retired.
    Retired {
        app_level: u32,
        host_floor: u32,
    },
    /// The app needs a newer QML runtime than the one running.
    QuickshellTooOld {
        required: String,
        running: Option<String>,
    },
}

impl fmt::Display for CompatIssue {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::NeedsNewerPlatform {
                required_level,
                required_platform,
                host_level,
            } => {
                match required_platform {
                    Some(release) => write!(
                        f,
                        "needs Astral {release} or newer (API {required_level}); this is API {host_level}"
                    ),
                    // A level with no release recorded yet is still sayable: the
                    // numbers are the contract, the release name is the courtesy.
                    None => write!(
                        f,
                        "needs a newer Astral (API {required_level}); this is API {host_level}"
                    ),
                }
            }
            Self::Retired {
                app_level,
                host_floor,
            } => write!(
                f,
                "built for API level {app_level}, which this shell no longer loads (floor {host_floor})"
            ),
            Self::QuickshellTooOld { required, running } => write!(
                f,
                "needs Quickshell {required} or newer; this is {}",
                running.as_deref().unwrap_or("unknown")
            ),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum CompatVerdict {
    Compatible,
    Incompatible(CompatIssue),
    /// Path for callers that already have a verdict-shaped result.
    Unknown,
}

impl CompatVerdict {
    pub fn is_compatible(&self) -> bool {
        matches!(self, Self::Compatible)
    }

    pub fn issue(&self) -> Option<&CompatIssue> {
        match self {
            Self::Incompatible(issue) => Some(issue),
            _ => None,
        }
    }
}

/// Check a manifest against one host API window.
pub fn check(manifest: &Manifest, host: &HostApi) -> CompatVerdict {
    if manifest.kernel_api > host.level {
        return CompatVerdict::Incompatible(CompatIssue::NeedsNewerPlatform {
            required_level: manifest.kernel_api,
            required_platform: platform_for_level(manifest.kernel_api),
            host_level: host.level,
        });
    }
    if manifest.kernel_api < host.floor {
        return CompatVerdict::Incompatible(CompatIssue::Retired {
            app_level: manifest.kernel_api,
            host_floor: host.floor,
        });
    }
    if let Some(required) = manifest.min_quickshell.as_deref() {
        let satisfied = host
            .quickshell
            .as_deref()
            .map(|running| !version_gt(required, running))
            .unwrap_or(false);
        if !satisfied {
            return CompatVerdict::Incompatible(CompatIssue::QuickshellTooOld {
                required: required.to_string(),
                running: host.quickshell.clone(),
            });
        }
    }
    CompatVerdict::Compatible
}

/// The same check for a candidate that is not a full manifest yet (a catalog
/// entry): the host only needs the two numbers.
pub fn check_levels(app_level: u32, min_quickshell: Option<&str>, host: &HostApi) -> CompatVerdict {
    if app_level > host.level {
        return CompatVerdict::Incompatible(CompatIssue::NeedsNewerPlatform {
            required_level: app_level,
            required_platform: platform_for_level(app_level),
            host_level: host.level,
        });
    }
    if app_level < host.floor {
        return CompatVerdict::Incompatible(CompatIssue::Retired {
            app_level,
            host_floor: host.floor,
        });
    }
    if let Some(required) = min_quickshell {
        let satisfied = host
            .quickshell
            .as_deref()
            .map(|running| !version_gt(required, running))
            .unwrap_or(false);
        if !satisfied {
            return CompatVerdict::Incompatible(CompatIssue::QuickshellTooOld {
                required: required.to_string(),
                running: host.quickshell.clone(),
            });
        }
    }
    CompatVerdict::Compatible
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::domain::app_manifest::{Entry, Manifest, Publisher};

    fn manifest(kernel_api: u32, min_quickshell: Option<&str>) -> Manifest {
        Manifest {
            schema: 1,
            id: "io.github.alice.clock".to_string(),
            name: "Clock".to_string(),
            version: "1.0.0".to_string(),
            kernel_api,
            min_quickshell: min_quickshell.map(str::to_string),
            data_schema: None,
            trust: "community".to_string(),
            runtime: "hosted".to_string(),
            publisher: Publisher {
                name: "Alice".to_string(),
                key: String::new(),
            },
            entry: Entry {
                root: "shell.qml".to_string(),
                surface: None,
                dashboard_tab: None,
                settings_page: None,
            },
            requires: Default::default(),
            permissions: Vec::new(),
            settings: None,
        test_suites: Vec::new(),
            integrations: Vec::new(),
            distribution: None,
        }
    }

    fn host(level: u32, floor: u32, quickshell: Option<&str>) -> HostApi {
        HostApi {
            level,
            floor,
            quickshell: quickshell.map(str::to_string),
        }
    }

    #[test]
    fn an_app_inside_the_window_is_compatible() {
        assert!(check(&manifest(1, None), &host(1, 1, None)).is_compatible());
    }

    #[test]
    fn an_app_built_against_a_newer_api_is_refused_with_both_numbers() {
        let verdict = check(&manifest(2, None), &host(1, 1, None));
        let issue = verdict.issue().expect("incompatible");
        assert_eq!(
            issue,
            &CompatIssue::NeedsNewerPlatform {
                required_level: 2,
                required_platform: platform_for_level(2),
                host_level: 1,
            }
        );
        let sentence = issue.to_string();
        assert!(sentence.contains("API 2"), "got: {sentence}");
        assert!(sentence.contains("API 1"), "got: {sentence}");
    }

    #[test]
    fn an_app_built_against_a_retired_api_is_refused() {
        let verdict = check(&manifest(1, None), &host(3, 2, None));
        assert_eq!(
            verdict.issue(),
            Some(&CompatIssue::Retired {
                app_level: 1,
                host_floor: 2
            })
        );
    }

    #[test]
    fn a_missing_quickshell_version_is_not_assumed_satisfied() {
        let verdict = check(&manifest(1, Some("0.3.0")), &host(1, 1, None));
        assert!(matches!(
            verdict.issue(),
            Some(CompatIssue::QuickshellTooOld { running: None, .. })
        ));
    }

    #[test]
    fn a_newer_quickshell_satisfies_the_floor() {
        assert!(check(&manifest(1, Some("0.3.0")), &host(1, 1, Some("0.3.2")))
            .is_compatible());
        assert!(check(&manifest(1, Some("0.4.0")), &host(1, 1, Some("0.3.2")))
            .issue()
            .is_some());
    }

    #[test]
    fn level_history_phrases_warnings_as_platform_versions() {
        assert_eq!(platform_for_level(1), Some("0.2.0"));
        assert_eq!(platform_for_level(99), None);
    }

    #[test]
    fn the_current_host_window_is_coherent() {
        let host = HostApi::current(Some("0.3.2"));
        assert!(host.floor <= host.level, "floor must never exceed level");
        assert_eq!(host.level, APP_API_LEVEL);
        assert_eq!(host.floor, APP_API_FLOOR);
        // Every supported level must be phraseable, or the UI cannot explain it.
        for level in host.floor..=host.level {
            assert!(
                platform_for_level(level).is_some(),
                "API level {level} has no platform release in API_LEVEL_HISTORY"
            );
        }
    }
}
