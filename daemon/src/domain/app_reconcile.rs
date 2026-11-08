//! Version and compatibility policy for installed apps.
//!
//! Two questions live here, and they are different questions:
//!
//! 1. **May this version be installed?** ([`decide_install`]) — forward only, a
//!    republished artifact under the same version is refused, and a downgrade is
//!    refused unless the data layout on disk can still be read.
//! 2. **The platform moved and this app no longer fits — what happens now?**
//!    ([`reconcile`]) — prefer keeping the app working (auto-update to a
//!    compatible version) over switching it off, and never uninstall anything.
//!
//! Pure functions over plain data: no filesystem, no session, no QML. That is
//! what lets the whole compatibility story be tested without a desktop.

use std::collections::BTreeSet;

use crate::domain::app_compat::{check_levels, CompatIssue, CompatVerdict, HostApi};
use crate::domain::app_manifest::permissions_within;
use crate::domain::update::{compare_versions, version_gt};

/// What the registry recorded when the app was installed.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct InstalledApp {
    pub id: String,
    pub version: String,
    pub kernel_api: u32,
    pub min_quickshell: Option<String>,
    /// Layout version of the app's data that this build writes.
    pub data_schema: Option<u32>,
    pub digest: String,
    /// The user asked to keep this version.
    pub pinned: bool,
    /// Official apps update themselves; community apps opt in.
    pub auto_update: bool,
    /// Permissions the user has already approved.
    pub granted: BTreeSet<String>,
    /// Core apps cannot be removed, so they fall back instead of switching off.
    pub core: bool,
}

/// A version offered by the catalog, or the baseline payload in the package.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Candidate {
    pub version: String,
    pub kernel_api: u32,
    pub min_quickshell: Option<String>,
    pub data_schema: Option<u32>,
    pub digest: String,
    pub permissions: BTreeSet<String>,
    /// True when this candidate is the preinstalled baseline copy.
    pub from_baseline: bool,
}

/// Why an install or update was refused.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Refusal {
    /// Outside the host's API window.
    Incompatible(CompatIssue),
    /// Not strictly newer than what is installed.
    NotNewer { installed: String, candidate: String },
    /// Same version, different digest: an artifact's digest is its identity, so a
    /// republish has to bump the version.
    RepublishedArtifact { version: String },
    /// Backwards, and the user did not ask for it.
    Downgrade { installed: String, candidate: String },
    /// Backwards *and* the target build cannot read the data on disk.
    WouldCorruptData { recorded: u32, candidate: Option<u32> },
}

impl std::fmt::Display for Refusal {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Incompatible(issue) => write!(f, "{issue}"),
            Self::NotNewer {
                installed,
                candidate,
            } => write!(f, "{candidate} is not newer than the installed {installed}"),
            Self::RepublishedArtifact { version } => write!(
                f,
                "{version} was published again with different content; the author must bump the version"
            ),
            Self::Downgrade {
                installed,
                candidate,
            } => write!(
                f,
                "{candidate} is older than the installed {installed}; downgrades are opt-in"
            ),
            Self::WouldCorruptData {
                recorded,
                candidate,
            } => write!(
                f,
                "the installed data uses schema {recorded}, which this build ({}) cannot read",
                candidate
                    .map(|schema| format!("schema {schema}"))
                    .unwrap_or_else(|| "no data schema".to_string())
            ),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Admission {
    /// Nothing installed yet.
    Install,
    /// Replaces a strictly older version.
    Update,
    /// Already at this exact build.
    UpToDate,
}

/// Decide whether `candidate` may be installed over `installed`.
pub fn decide_install(
    installed: Option<&InstalledApp>,
    candidate: &Candidate,
    host: &HostApi,
    allow_downgrade: bool,
) -> Result<Admission, Refusal> {
    if let CompatVerdict::Incompatible(issue) = check_levels(
        candidate.kernel_api,
        candidate.min_quickshell.as_deref(),
        host,
    ) {
        return Err(Refusal::Incompatible(issue));
    }

    let Some(installed) = installed else {
        return Ok(Admission::Install);
    };

    match compare_versions(&candidate.version, &installed.version) {
        std::cmp::Ordering::Greater => Ok(Admission::Update),
        std::cmp::Ordering::Equal => {
            if candidate.digest == installed.digest {
                Ok(Admission::UpToDate)
            } else {
                Err(Refusal::RepublishedArtifact {
                    version: candidate.version.clone(),
                })
            }
        }
        std::cmp::Ordering::Less => {
            if !allow_downgrade {
                return Err(Refusal::Downgrade {
                    installed: installed.version.clone(),
                    candidate: candidate.version.clone(),
                });
            }
            match installed.data_schema {
                // Nothing recorded: nothing can be corrupted by reading it again.
                None => Ok(Admission::Update),
                Some(recorded) => {
                    if candidate.data_schema.map(|schema| schema >= recorded).unwrap_or(false) {
                        Ok(Admission::Update)
                    } else {
                        Err(Refusal::WouldCorruptData {
                            recorded,
                            candidate: candidate.data_schema,
                        })
                    }
                }
            }
        }
    }
}

/// What the host does with an installed app after the platform changed.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Action {
    /// Still fits; nothing to do.
    Keep,
    /// A compatible newer version exists and the app is allowed to take it.
    AutoUpdate { version: String },
    /// Stays on disk, keeps its data and grants, stops loading.
    Disable { reason: DisableReason },
    /// Core app: promote the platform's baseline copy, which is compatible by
    /// construction because it shipped with this platform.
    BaselineRevert,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum DisableReason {
    /// A compatible update exists but adds permissions.
    NeedsReview { candidate: String },
    /// A compatible update exists but the user pinned this app.
    Pinned { candidate: String },
    /// A compatible update exists but the app does not auto-update.
    UpdateNotAutomatic { candidate: String },
    /// Nothing compatible in the catalog.
    NoCompatibleVersion { issue: CompatIssue },
    /// Only an older version fits, and downgrades are opt-in.
    OnlyOlderCompatible { candidate: String },
    /// Core app whose baseline is also outside the window: a broken release.
    BaselineAlsoIncompatible { issue: CompatIssue },
}

impl std::fmt::Display for DisableReason {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::NeedsReview { candidate } => write!(
                f,
                "{candidate} is available but asks for new permissions; review the update"
            ),
            Self::Pinned { candidate } => {
                write!(f, "pinned at this version; {candidate} is available")
            }
            Self::UpdateNotAutomatic { candidate } => {
                write!(f, "{candidate} is available; this app does not update automatically")
            }
            Self::NoCompatibleVersion { issue } => write!(f, "{issue}"),
            Self::OnlyOlderCompatible { candidate } => write!(
                f,
                "only {candidate} is compatible, and downgrades are opt-in"
            ),
            Self::BaselineAlsoIncompatible { issue } => {
                write!(f, "the bundled baseline does not fit either: {issue}")
            }
        }
    }
}

/// Reconcile one installed app against the candidates the host can see.
///
/// `candidates` may include the baseline copy; it is preferred for core apps
/// because it is guaranteed to match the running platform.
pub fn reconcile(app: &InstalledApp, candidates: &[Candidate], host: &HostApi) -> Action {
    if check_levels(app.kernel_api, app.min_quickshell.as_deref(), host).is_compatible() {
        return Action::Keep;
    }

    let compatible: Vec<&Candidate> = candidates
        .iter()
        .filter(|candidate| {
            check_levels(
                candidate.kernel_api,
                candidate.min_quickshell.as_deref(),
                host,
            )
            .is_compatible()
        })
        .collect();

    let newer = compatible
        .iter()
        .copied()
        .filter(|candidate| version_gt(&candidate.version, &app.version))
        .max_by(|left, right| compare_versions(&left.version, &right.version));

    if let Some(candidate) = newer {
        // Permissions are never laundered through a forced update.
        if !permissions_within(&app.granted, &candidate.permissions) {
            return Action::Disable {
                reason: DisableReason::NeedsReview {
                    candidate: candidate.version.clone(),
                },
            };
        }
        if app.pinned {
            return Action::Disable {
                reason: DisableReason::Pinned {
                    candidate: candidate.version.clone(),
                },
            };
        }
        if app.auto_update {
            return Action::AutoUpdate {
                version: candidate.version.clone(),
            };
        }
        if app.core && candidate.from_baseline {
            // The baseline shipped with this platform, so agree to it.
            return Action::AutoUpdate {
                version: candidate.version.clone(),
            };
        }
        return Action::Disable {
            reason: DisableReason::UpdateNotAutomatic {
                candidate: candidate.version.clone(),
            },
        };
    }

    if app.core {
        if compatible.iter().any(|candidate| candidate.from_baseline) {
            // A core app cannot be switched off: promote the factory copy that
            // shipped with this platform instead.
            return Action::BaselineRevert;
        }
        let issue = issue_for(app, host);
        return Action::Disable {
            reason: DisableReason::BaselineAlsoIncompatible { issue },
        };
    }

    if let Some(candidate) = compatible
        .iter()
        .copied()
        .filter(|candidate| !version_gt(&candidate.version, &app.version))
        .max_by(|left, right| compare_versions(&left.version, &right.version))
    {
        return Action::Disable {
            reason: DisableReason::OnlyOlderCompatible {
                candidate: candidate.version.clone(),
            },
        };
    }

    Action::Disable {
        reason: DisableReason::NoCompatibleVersion {
            issue: issue_for(app, host),
        },
    }
}

fn issue_for(app: &InstalledApp, host: &HostApi) -> CompatIssue {
    check_levels(app.kernel_api, app.min_quickshell.as_deref(), host)
        .issue()
        .cloned()
        .unwrap_or(CompatIssue::NeedsNewerPlatform {
            required_level: app.kernel_api,
            required_platform: crate::domain::app_compat::platform_for_level(app.kernel_api),
            host_level: host.level,
        })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::domain::app_compat::{CompatIssue, HostApi};

    fn host(level: u32, floor: u32) -> HostApi {
        HostApi {
            level,
            floor,
            quickshell: None,
        }
    }

    fn app(version: &str, kernel_api: u32) -> InstalledApp {
        InstalledApp {
            id: "org.astralplasma.downloads".to_string(),
            version: version.to_string(),
            kernel_api,
            min_quickshell: None,
            data_schema: Some(2),
            digest: "sha256:aaa".to_string(),
            pinned: false,
            auto_update: true,
            granted: BTreeSet::new(),
            core: false,
        }
    }

    fn candidate(version: &str, kernel_api: u32) -> Candidate {
        Candidate {
            version: version.to_string(),
            kernel_api,
            min_quickshell: None,
            data_schema: Some(2),
            digest: format!("sha256:{version}"),
            permissions: BTreeSet::new(),
            from_baseline: false,
        }
    }

    #[test]
    fn install_is_admitted_on_an_empty_registry() {
        let decision = decide_install(None, &candidate("1.0.0", 1), &host(1, 1), false);
        assert_eq!(decision.unwrap(), Admission::Install);
    }

    #[test]
    fn a_newer_version_updates() {
        let installed = app("1.0.0", 1);
        let decision = decide_install(Some(&installed), &candidate("1.1.0", 1), &host(1, 1), false);
        assert_eq!(decision.unwrap(), Admission::Update);
    }

    #[test]
    fn the_same_build_is_up_to_date() {
        let installed = app("1.0.0", 1);
        let mut same = candidate("1.0.0", 1);
        same.digest = installed.digest.clone();
        assert_eq!(
            decide_install(Some(&installed), &same, &host(1, 1), false).unwrap(),
            Admission::UpToDate
        );
    }

    #[test]
    fn a_republished_artifact_is_refused_until_the_version_bumps() {
        let installed = app("1.0.0", 1);
        let mut republished = candidate("1.0.0", 1);
        republished.digest = "sha256:different".to_string();
        let refusal = decide_install(Some(&installed), &republished, &host(1, 1), false).unwrap_err();
        assert_eq!(
            refusal,
            Refusal::RepublishedArtifact {
                version: "1.0.0".to_string()
            }
        );
    }

    #[test]
    fn a_downgrade_is_opt_in() {
        let installed = app("2.0.0", 1);
        let refusal = decide_install(
            Some(&installed),
            &candidate("1.9.0", 1),
            &host(1, 1),
            false,
        )
        .unwrap_err();
        assert!(matches!(refusal, Refusal::Downgrade { .. }));
    }

    #[test]
    fn a_downgrade_into_unreadable_data_is_refused_even_when_allowed() {
        let installed = app("2.0.0", 1); // data schema 2
        let mut older = candidate("1.9.0", 1);
        older.data_schema = Some(1);
        let refusal =
            decide_install(Some(&installed), &older, &host(1, 1), true).unwrap_err();
        assert_eq!(
            refusal,
            Refusal::WouldCorruptData {
                recorded: 2,
                candidate: Some(1)
            }
        );
    }

    #[test]
    fn a_downgrade_that_can_read_the_data_is_admitted_when_allowed() {
        let installed = app("2.0.0", 1);
        let mut older = candidate("1.9.0", 1);
        older.data_schema = Some(2);
        assert_eq!(
            decide_install(Some(&installed), &older, &host(1, 1), true).unwrap(),
            Admission::Update
        );
    }

    #[test]
    fn an_app_for_a_newer_platform_is_refused_with_a_compat_issue() {
        let refusal =
            decide_install(None, &candidate("1.0.0", 2), &host(1, 1), false).unwrap_err();
        assert!(matches!(refusal, Refusal::Incompatible(_)));
        assert!(refusal.to_string().contains("API 2"));
    }

    #[test]
    fn a_compatible_app_is_left_alone() {
        assert_eq!(reconcile(&app("1.0.0", 1), &[], &host(1, 1)), Action::Keep);
    }

    #[test]
    fn an_incompatible_app_with_a_compatible_update_updates_itself() {
        let installed = app("1.0.0", 1);
        let action = reconcile(&installed, &[candidate("1.1.0", 2)], &host(2, 2));
        assert_eq!(
            action,
            Action::AutoUpdate {
                version: "1.1.0".to_string()
            }
        );
    }

    #[test]
    fn an_update_that_adds_permissions_disables_instead_of_updating() {
        let mut installed = app("1.0.0", 1);
        installed.granted = ["session.read".to_string()].into_iter().collect();
        let mut next = candidate("1.1.0", 2);
        next.permissions = ["session.read".to_string(), "network".to_string()]
            .into_iter()
            .collect();
        let action = reconcile(&installed, &[next], &host(2, 2));
        assert_eq!(
            action,
            Action::Disable {
                reason: DisableReason::NeedsReview {
                    candidate: "1.1.0".to_string()
                }
            }
        );
    }

    #[test]
    fn a_pin_wins_over_an_available_update() {
        let mut installed = app("1.0.0", 1);
        installed.pinned = true;
        let action = reconcile(&installed, &[candidate("1.1.0", 2)], &host(2, 2));
        assert_eq!(
            action,
            Action::Disable {
                reason: DisableReason::Pinned {
                    candidate: "1.1.0".to_string()
                }
            }
        );
    }

    #[test]
    fn an_app_that_does_not_auto_update_waits_for_the_user() {
        let mut installed = app("1.0.0", 1);
        installed.auto_update = false;
        let action = reconcile(&installed, &[candidate("1.1.0", 2)], &host(2, 2));
        assert!(matches!(
            action,
            Action::Disable {
                reason: DisableReason::UpdateNotAutomatic { .. }
            }
        ));
    }

    #[test]
    fn no_compatible_candidate_disables_with_the_reason() {
        let action = reconcile(&app("1.0.0", 1), &[], &host(2, 2));
        match action {
            Action::Disable { reason } => {
                let sentence = reason.to_string();
                assert!(sentence.contains("API"), "got: {sentence}");
            }
            other => panic!("expected disable, got {other:?}"),
        }
    }

    #[test]
    fn a_core_app_takes_its_baseline() {
        let mut installed = app("1.0.0", 1);
        installed.core = true;
        let mut baseline = candidate("1.0.0", 2);
        baseline.from_baseline = true;
        assert_eq!(
            reconcile(&installed, &[baseline], &host(2, 2)),
            Action::BaselineRevert
        );
    }

    #[test]
    fn a_core_app_without_a_usable_baseline_says_the_release_is_broken() {
        let mut installed = app("1.0.0", 1);
        installed.core = true;
        let action = reconcile(&installed, &[], &host(2, 2));
        assert!(matches!(
            action,
            Action::Disable {
                reason: DisableReason::BaselineAlsoIncompatible { .. }
            }
        ));
    }

    #[test]
    fn after_a_kernel_rollback_nothing_newer_fits_and_the_app_disables() {
        // Kernel rolled back from API 2 to API 1; the app requires API 2.
        let installed = app("2.0.0", 2);
        let action = reconcile(&installed, &[candidate("2.0.0", 2)], &host(1, 1));
        match action {
            Action::Disable { reason } => {
                assert!(matches!(reason, DisableReason::NoCompatibleVersion { .. }))
            }
            other => panic!("expected disable, got {other:?}"),
        }
    }

    #[test]
    fn only_an_older_compatible_version_is_not_a_silent_downgrade() {
        let installed = app("2.0.0", 2);
        let action = reconcile(&installed, &[candidate("1.5.0", 1)], &host(1, 1));
        assert_eq!(
            action,
            Action::Disable {
                reason: DisableReason::OnlyOlderCompatible {
                    candidate: "1.5.0".to_string()
                }
            }
        );
    }

    #[test]
    fn reconcile_never_uninstalls() {
        // The action set has no "remove" variant on purpose: a platform move may
        // take an app out of the running set, never off the disk.
        let moves = [
            reconcile(&app("1.0.0", 1), &[], &host(2, 2)),
            reconcile(
                &{
                    let mut pinned = app("1.0.0", 1);
                    pinned.pinned = true;
                    pinned
                },
                &[candidate("1.1.0", 2)],
                &host(2, 2),
            ),
        ];
        for action in moves {
            assert!(
                matches!(action, Action::Disable { .. }),
                "expected a disable, got {action:?}"
            );
        }
    }
}
