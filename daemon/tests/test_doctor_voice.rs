//! Tests for the voice entry in `astral-plasma doctor`.
//!
//! The property that matters most here is negative: voice is an optional
//! convenience, so its absence must never make the shell look broken. See
//! `docs/VOICE-INPUT-SPEC.md` §8.5 and D10.

use astral_plasma::application::doctor_service::DoctorService;
use astral_plasma::domain::doctor::CheckStatus;

#[test]
fn voice_check_appears_in_the_report() {
    let report = DoctorService::new().run_diagnostics();
    let check = report
        .checks
        .iter()
        .find(|c| c.name.contains("Voice Input"))
        .expect("doctor must report on voice input");
    assert_eq!(check.category, "Optional Enhancements");
}

#[test]
fn voice_check_is_actually_rendered_in_the_terminal_output() {
    // `render_terminal` iterates a hardcoded category list, so a check can be
    // present in the report data and still never appear on screen. That is
    // exactly what happened on the first implementation: the check existed, the
    // tests passed, and `astral-plasma doctor` said nothing about voice.
    let report = DoctorService::new().run_diagnostics();
    let rendered = report.render_terminal();
    assert!(
        rendered.contains("Voice Input"),
        "the voice check must be visible in `astral-plasma doctor` output"
    );
    assert!(
        rendered.contains("(optional)"),
        "voice must be advertised as an optional enhancement, not a requirement"
    );
}

#[test]
fn voice_is_never_a_required_dependency() {
    // This is the load-bearing assertion. If voice were required, a user who
    // never installs whisper.cpp would see a healthy shell reported as broken.
    let report = DoctorService::new().run_diagnostics();
    let check = report
        .checks
        .iter()
        .find(|c| c.name.contains("Voice Input"))
        .expect("voice check must exist");
    assert!(
        !check.required,
        "voice input must never be marked required; a shell without it is healthy"
    );
}

#[test]
fn a_missing_voice_engine_is_a_warning_not_a_failure() {
    // On a host without whisper.cpp installed the check must be a Warning with
    // an actionable recommendation, never a Fail.
    let report = DoctorService::new().run_diagnostics();
    let check = report
        .checks
        .iter()
        .find(|c| c.name.contains("Voice Input"))
        .expect("voice check must exist");

    if !check.installed {
        assert_eq!(
            check.status,
            CheckStatus::Warning,
            "a missing optional engine must not be a hard failure"
        );
        assert!(
            check.message.to_lowercase().contains("not found"),
            "the message must state what is missing, got {:?}",
            check.message
        );
        let rec = check
            .recommendation
            .as_ref()
            .expect("a missing engine must come with an install hint");
        assert!(
            rec.contains("whisper-cpp") || rec.contains("whisper.cpp"),
            "recommendation must name the package: {rec}"
        );
    }
}

#[test]
fn voice_absence_does_not_break_the_overall_report() {
    // Belt and braces: assert the aggregate verdict is unaffected. This runs
    // on a host with no engine, so it is the real scenario.
    let report = DoctorService::new().run_diagnostics();
    let voice_problems = report
        .checks
        .iter()
        .filter(|c| c.name.contains("Voice Input"))
        .filter(|c| c.status == CheckStatus::Fail)
        .count();
    assert_eq!(voice_problems, 0, "voice must never contribute a hard failure");
}

#[test]
fn doctor_report_stays_well_formed_with_the_voice_entry() {
    let report = DoctorService::new().run_diagnostics();
    // The voice check must not disturb the existing checks or ordering contract.
    assert!(report.checks.len() >= 10, "expected the full check list, got {}", report.checks.len());
    for name in ["Quickshell", "PipeWire Audio Subsystem"] {
        assert!(
            report.checks.iter().any(|c| c.name == name),
            "existing check {name} must still be present"
        );
    }
    assert!(!report.summary.is_empty(), "the report summary must remain populated");
}
