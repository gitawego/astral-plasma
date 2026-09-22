//! Default calendar application resolution.
//!
//! Regression guard: clicking a dashboard date must open the user's own
//! calendar app. An earlier generation of this feature would have hardcoded
//! names (`korganizer`, `gnome-calendar`, ...), which breaks on any system
//! that ships a different calendar. These tests pin the data-driven contract:
//! MIME defaults win, installed entries are discovered by their declared
//! `MimeType=` / `Categories=`, and empty inputs resolve to empty (never a
//! baked-in application).

use astral_plasma::domain::calendar::{
    calendar_candidates, desktop_entry_name, desktop_entry_supports_calendar, is_valid_iso_date,
    normalize_desktop_id, parse_mimeapps_default, CALENDAR_MIME,
};
use astral_plasma::infrastructure::calendar::{
    calendar_app_from_settings, calendar_options, desktop_id_declares_calendar, find_desktop_file,
    open_plan, CalendarAdapter, OpenPlan,
};

// ============================================================================
// mimeapps.list parsing
// ============================================================================

const MIMEAPPS: &str = "\
[Added Associations]
text/calendar=userapp-Evolution-19QSK3.desktop;

[Default Applications]
text/calendar=org.kde.merkuro.calendar.desktop;other.desktop;
x-scheme-handler/http=firefox.desktop;
";

#[test]
fn parses_calendar_default_from_defaults_section() {
    assert_eq!(
        parse_mimeapps_default(MIMEAPPS, CALENDAR_MIME).as_deref(),
        Some("org.kde.merkuro.calendar.desktop")
    );
}

#[test]
fn ignores_added_associations_section() {
    let content = "[Added Associations]\ntext/calendar=foo.desktop;\n";
    assert_eq!(parse_mimeapps_default(content, CALENDAR_MIME), None);
}

#[test]
fn ignores_other_mime_types() {
    assert_eq!(
        parse_mimeapps_default(MIMEAPPS, "x-scheme-handler/http").as_deref(),
        Some("firefox.desktop")
    );
    assert_eq!(
        parse_mimeapps_default(MIMEAPPS, "text/plain"),
        None,
        "unlisted MIME types must resolve to None, not a fallback app"
    );
}

#[test]
fn tolerates_whitespace_and_missing_trailing_semicolon() {
    let content = "[Default Applications]\n  text/calendar  =  spaced.desktop  \n";
    assert_eq!(
        parse_mimeapps_default(content, CALENDAR_MIME).as_deref(),
        Some("spaced.desktop")
    );
    let no_semi = "[Default Applications]\ntext/calendar=bare.desktop";
    assert_eq!(
        parse_mimeapps_default(no_semi, CALENDAR_MIME).as_deref(),
        Some("bare.desktop")
    );
}

#[test]
fn empty_value_resolves_to_none() {
    let content = "[Default Applications]\ntext/calendar=;  ;\n";
    assert_eq!(parse_mimeapps_default(content, CALENDAR_MIME), None);
}

// ============================================================================
// Desktop-entry calendar support
// ============================================================================

#[test]
fn mime_type_declares_calendar_support() {
    let content = "\
[Desktop Entry]
Type=Application
Name=Some Calendar
Exec=somecal %U
MimeType=text/calendar;text/x-vcard;
";
    assert!(desktop_entry_supports_calendar(content));
}

#[test]
fn calendar_category_declares_support() {
    let content = "\
[Desktop Entry]
Type=Application
Name=Planner
Exec=planner
Categories=GTK;Office;Calendar;
";
    assert!(desktop_entry_supports_calendar(content));
}

#[test]
fn calculator_category_is_not_calendar() {
    // Exact token match: `Calculator` must not qualify via substring.
    let content = "\
[Desktop Entry]
Type=Application
Name=Calculator
Exec=kcalc
Categories=Utility;Calculator;
";
    assert!(!desktop_entry_supports_calendar(content));
}

#[test]
fn unrelated_entry_has_no_support() {
    let content = "\
[Desktop Entry]
Type=Application
Name=Editor
Exec=editor
Categories=Utility;TextEditor;
MimeType=text/plain;
";
    assert!(!desktop_entry_supports_calendar(content));
}

#[test]
fn mime_match_is_case_insensitive() {
    let content = "[Desktop Entry]\nType=Application\nName=C\nMimeType=Text/Calendar;\n";
    assert!(desktop_entry_supports_calendar(content));
}

// ============================================================================
// Candidate ordering (no hardcoded fallback)
// ============================================================================

#[test]
fn user_override_beats_mime_default_beats_scan() {
    let scan = vec!["a.desktop".to_string(), "b.desktop".to_string()];
    let out = calendar_candidates(
        Some("user.desktop"),
        &["mime.desktop".to_string()],
        &scan,
    );
    assert_eq!(
        out,
        vec![
            "user.desktop".to_string(),
            "mime.desktop".to_string(),
            "a.desktop".to_string(),
            "b.desktop".to_string(),
        ]
    );
}

#[test]
fn mime_defaults_keep_precedence_order() {
    // text/calendar first, then the webcal scheme handlers.
    let out = calendar_candidates(
        None,
        &["cal.desktop".to_string(), "webcal.desktop".to_string()],
        &[],
    );
    assert_eq!(
        out,
        vec!["cal.desktop".to_string(), "webcal.desktop".to_string()]
    );
}

#[test]
fn dedups_and_skips_blanks() {
    let scan = vec!["b.desktop".to_string(), "a.desktop".to_string()];
    let out = calendar_candidates(
        Some("  "),
        &["a.desktop".to_string()],
        &scan,
    );
    assert_eq!(out, vec!["a.desktop".to_string(), "b.desktop".to_string()]);
}

#[test]
fn empty_inputs_resolve_to_empty_never_hardcoded() {
    // The load-bearing anti-monkey-patch guard: with no system data there is
    // no fallback application. A hardcoded `korganizer` here would break on
    // systems shipping a different calendar.
    let out: Vec<String> = calendar_candidates(None, &[], &[]);
    assert!(
        out.is_empty(),
        "no system data must mean no candidates, got {out:?}"
    );
}

#[test]
fn normalize_trims_only() {
    assert_eq!(normalize_desktop_id("  foo.desktop  "), "foo.desktop");
    assert_eq!(normalize_desktop_id("bare"), "bare");
    assert_eq!(normalize_desktop_id("   "), "");
}

// ============================================================================
// ISO date validation
// ============================================================================

#[test]
fn accepts_real_dates() {
    assert!(is_valid_iso_date("2026-09-22"));
    assert!(is_valid_iso_date("2024-02-29"), "2024 is a leap year");
}

#[test]
fn rejects_impossible_dates() {
    assert!(!is_valid_iso_date("2026-13-01"));
    assert!(!is_valid_iso_date("2026-00-10"));
    assert!(!is_valid_iso_date("2026-02-30"));
    assert!(!is_valid_iso_date("2023-02-29"), "2023 is not a leap year");
    assert!(!is_valid_iso_date("2026-04-31"));
    assert!(!is_valid_iso_date("not-a-date"));
    assert!(!is_valid_iso_date("2026-9-2"));
    assert!(!is_valid_iso_date(""));
}

// ============================================================================
// Handler verification (the Kate rule)
// ============================================================================
// Observed failure: with no calendar app installed, a `.ics` opened via the
// MIME database lands in Kate (a text editor whose entry only declares
// `text/plain`). A bare association therefore never qualifies an id as a
// calendar application - the installed entry must declare it.

const EDITOR_DESKTOP: &str = "\
[Desktop Entry]
Type=Application
Name=FakeEditor
Exec=fakeeditor %U
MimeType=text/plain;
";

const CAL_DESKTOP: &str = "\
[Desktop Entry]
Type=Application
Name=FakeCal
Exec=fakecal %U
MimeType=text/calendar;
";

fn write_app(dir: &std::path::Path, id: &str, content: &str) {
    std::fs::write(dir.join(id), content).expect("fixture must write");
}

fn fixture_dirs() -> tempfile::TempDir {
    let tmp = tempfile::tempdir().expect("tempdir must create");
    let apps = tmp.path().join("applications");
    std::fs::create_dir_all(&apps).expect("apps dir must create");
    write_app(&apps, "fake-editor.desktop", EDITOR_DESKTOP);
    write_app(&apps, "real-cal.desktop", CAL_DESKTOP);
    tmp
}

fn apps_dir(tmp: &tempfile::TempDir) -> std::path::PathBuf {
    tmp.path().join("applications")
}

#[test]
fn finds_installed_entries_by_bare_and_suffixed_id() {
    let tmp = fixture_dirs();
    let dirs = vec![apps_dir(&tmp)];
    assert!(find_desktop_file("real-cal.desktop", &dirs).is_some());
    assert!(find_desktop_file("real-cal", &dirs).is_some());
    assert!(find_desktop_file("ghost.desktop", &dirs).is_none());
    assert!(find_desktop_file("  ", &dirs).is_none());
}

#[test]
fn declaration_check_follows_desktop_entry_data() {
    let tmp = fixture_dirs();
    let dirs = vec![apps_dir(&tmp)];
    assert!(desktop_id_declares_calendar("real-cal.desktop", &dirs));
    assert!(
        !desktop_id_declares_calendar("fake-editor.desktop", &dirs),
        "a text editor must not qualify as a calendar app"
    );
    assert!(
        !desktop_id_declares_calendar("ghost.desktop", &dirs),
        "unverifiable ids must not qualify"
    );
}

#[test]
fn mime_default_without_declaration_is_skipped() {
    // The Kate regression: the MIME default points at an editor, while a
    // real calendar entry is installed. Only the calendar entry resolves.
    let tmp = fixture_dirs();
    let dirs = vec![apps_dir(&tmp)];
    let adapter = CalendarAdapter::new();
    let out = adapter.resolve_from(&["fake-editor.desktop".to_string()], &dirs);
    assert_eq!(out, vec!["real-cal.desktop".to_string()]);
}

#[test]
fn unverifiable_mime_default_resolves_to_scan_only() {
    let tmp = fixture_dirs();
    let dirs = vec![apps_dir(&tmp)];
    let adapter = CalendarAdapter::new();
    let out = adapter.resolve_from(&["ghost.desktop".to_string()], &dirs);
    assert_eq!(out, vec!["real-cal.desktop".to_string()]);
}

#[test]
fn user_override_bypasses_declaration_check() {
    // Explicit user configuration is trusted: the user knows their app.
    let tmp = fixture_dirs();
    let dirs = vec![apps_dir(&tmp)];
    let adapter = CalendarAdapter::with_override("fake-editor.desktop");
    let out = adapter.resolve_from(&[], &dirs);
    assert_eq!(
        out,
        vec!["fake-editor.desktop".to_string(), "real-cal.desktop".to_string()]
    );
}

// ============================================================================
// User override from the settings file (`dashboard.calendarApp`)
// ============================================================================
// The explicit user pick in Settings > Dashboard & Widgets wins over the XDG
// MIME default. Reading and parsing stay pure here so the tests are hermetic;
// the file-path glue is covered by the `calendar resolve` smoke check.

#[test]
fn reads_override_from_settings_json() {
    let json = r#"{"dashboard":{"calendarApp":"org.example.Cal.desktop"},"topBar":{"enabled":true}}"#;
    assert_eq!(
        calendar_app_from_settings(json).as_deref(),
        Some("org.example.Cal.desktop")
    );
}

#[test]
fn blank_or_missing_override_means_system_default() {
    // "" is the shipped default: follow the system's XDG MIME default.
    assert_eq!(calendar_app_from_settings(r#"{"dashboard":{"calendarApp":"   "}}"#), None);
    assert_eq!(calendar_app_from_settings(r#"{"dashboard":{}}"#), None);
    assert_eq!(calendar_app_from_settings(r#"{"topBar":{"enabled":true}}"#), None);
    assert_eq!(calendar_app_from_settings(r#"{"dashboard":{"calendarApp":42}}"#), None);
    assert_eq!(calendar_app_from_settings("{not json"), None);
    assert_eq!(calendar_app_from_settings(""), None);
}

#[test]
fn override_is_trimmed() {
    assert_eq!(
        calendar_app_from_settings(r#"{"dashboard":{"calendarApp":"  cal.desktop  "}}"#).as_deref(),
        Some("cal.desktop")
    );
}

#[test]
fn stale_override_with_missing_desktop_file_falls_back() {
    // An uninstalled app must never dead-end the date click: the stale
    // override is dropped and the system resolution order applies.
    let tmp = fixture_dirs();
    let dirs = vec![apps_dir(&tmp)];
    let adapter = CalendarAdapter::with_override("gone.desktop");
    let out = adapter.resolve_from(&[], &dirs);
    assert_eq!(out, vec!["real-cal.desktop".to_string()]);
}

// ============================================================================
// Picker options (id + display name from the desktop entry)
// ============================================================================

#[test]
fn options_carry_id_and_display_name() {
    let tmp = fixture_dirs();
    let dirs = vec![apps_dir(&tmp)];
    let opts = calendar_options(
        &["real-cal.desktop".to_string(), "fake-editor.desktop".to_string()],
        &dirs,
    );
    assert_eq!(opts.len(), 2);
    assert_eq!(opts[0].id, "real-cal.desktop");
    assert_eq!(opts[0].name, "FakeCal");
    assert_eq!(opts[1].id, "fake-editor.desktop");
    assert_eq!(opts[1].name, "FakeEditor");
}

#[test]
fn options_fall_back_to_id_when_entry_is_missing() {
    let tmp = fixture_dirs();
    let dirs = vec![apps_dir(&tmp)];
    let opts = calendar_options(&["ghost.desktop".to_string()], &dirs);
    assert_eq!(opts.len(), 1);
    assert_eq!(opts[0].id, "ghost.desktop");
    assert_eq!(opts[0].name, "ghost.desktop");
}

// ============================================================================
// Desktop-entry Name parsing
// ============================================================================

#[test]
fn parses_name_from_first_desktop_entry_group() {
    let content = "[Desktop Entry]\nType=Application\nName=Merkuro Calendar\nComment=x\n";
    assert_eq!(desktop_entry_name(content).as_deref(), Some("Merkuro Calendar"));
}

#[test]
fn ignores_comments_localized_names_and_other_groups() {
    let content = "\
[Desktop Entry]
Name=Base Name
# Name=Commented Out
Name[de]=Deutsch
GenericName=Not This
[Desktop Action new-event]
Name=Action Name
";
    assert_eq!(desktop_entry_name(content).as_deref(), Some("Base Name"));
}

#[test]
fn name_outside_desktop_entry_group_is_ignored() {
    assert_eq!(desktop_entry_name("Name=Loose\n[Desktop Entry]\nType=Application\n"), None);
    assert_eq!(desktop_entry_name("[Desktop Entry]\nName=\n"), None);
    assert_eq!(desktop_entry_name("garbage"), None);
}

// ============================================================================
// Open plan
// ============================================================================

#[test]
fn primary_candidate_wins_over_fallback() {
    assert_eq!(
        open_plan(&["cal.desktop".to_string()], true),
        OpenPlan::Launch("cal.desktop".to_string())
    );
}

#[test]
fn blank_candidates_fall_through_to_settings() {
    assert_eq!(
        open_plan(&["  ".to_string()], true),
        OpenPlan::DateTimeSettings
    );
}

#[test]
fn no_candidates_without_settings_is_none() {
    assert_eq!(open_plan(&[], false), OpenPlan::None);
}
