//! KWin window rules: Quickshell's AI Copilot surface is a real xdg-toplevel, so
//! KWin decorates it by default. A `kwinrulesrc` entry with `noborder=true`
//! removes the titlebar/frame without disturbing the user's other rules.

use astral_plasma::domain::branding;
use astral_plasma::infrastructure::kwin_shortcuts::KdeIniFile;
use astral_plasma::infrastructure::kwin_window_rules::KWinWindowRulesAdapter;
use std::collections::BTreeMap;

const DESCRIPTION: &str = branding::KWIN_RULE_ASSISTANT_DESCRIPTION;
const WM_CLASS: &str = branding::WINDOW_CLASS_QUICKSHELL;

/// The exact five keys the rule must carry, in KWin's own spelling.
fn expected_rule_keys() -> BTreeMap<String, String> {
    BTreeMap::from([
        ("Description".to_string(), DESCRIPTION.to_string()),
        ("noborder".to_string(), "true".to_string()),
        ("noborderrule".to_string(), "2".to_string()),
        ("wmclass".to_string(), WM_CLASS.to_string()),
        ("wmclassmatch".to_string(), "1".to_string()),
    ])
}

fn render(existing: &str) -> String {
    KWinWindowRulesAdapter::render_kwinrulesrc(existing, DESCRIPTION, WM_CLASS)
}

fn groups(content: &str) -> BTreeMap<String, BTreeMap<String, String>> {
    KdeIniFile::parse(content).groups
}

/// The cloudmusic rule from docs/LESSONS.md §17, which must survive untouched.
const UNRELATED_RULE: &str = "\
[1]
Description=Wine background player
acceptfocus=true
acceptfocusrule=2
wmclass=cloudmusic.exe
wmclassmatch=1

[General]
count=1
rules=1

";

// ============================================================================
// Fresh file
// ============================================================================

#[test]
fn empty_input_creates_one_rule_and_consistent_general() {
    let ini = groups(&render(""));
    assert_eq!(ini.get("1"), Some(&expected_rule_keys()), "rule group [1] has the five keys");
    assert_eq!(ini.get("General").and_then(|g| g.get("count")).map(String::as_str), Some("1"));
    assert_eq!(ini.get("General").and_then(|g| g.get("rules")).map(String::as_str), Some("1"));
}

#[test]
fn rendered_rule_declares_every_key_with_exact_values() {
    let content = render("");
    let ini = KdeIniFile::parse(&content);
    let rule = ini.groups.get("1").expect("rule group");
    assert_eq!(rule.get("noborder").map(String::as_str), Some("true"));
    assert_eq!(rule.get("noborderrule").map(String::as_str), Some("2"));
    assert_eq!(rule.get("wmclass").map(String::as_str), Some(WM_CLASS));
    assert_eq!(rule.get("wmclassmatch").map(String::as_str), Some("1"));
}

// ============================================================================
// Coexistence with the user's rules
// ============================================================================

#[test]
fn unrelated_rule_survives_byte_for_byte_and_gains_a_sibling() {
    let content = render(UNRELATED_RULE);
    let ini = groups(&content);

    let untouched = ini.get("1").expect("cloudmusic rule");
    assert_eq!(
        untouched,
        &BTreeMap::from([
            ("Description".to_string(), "Wine background player".to_string()),
            ("acceptfocus".to_string(), "true".to_string()),
            ("acceptfocusrule".to_string(), "2".to_string()),
            ("wmclass".to_string(), "cloudmusic.exe".to_string()),
            ("wmclassmatch".to_string(), "1".to_string()),
        ])
    );
    assert_eq!(ini.get("2"), Some(&expected_rule_keys()));

    let general = ini.get("General").expect("General group");
    assert_eq!(general.get("count").map(String::as_str), Some("2"));
    assert_eq!(general.get("rules").map(String::as_str), Some("1,2"));
}

#[test]
fn new_id_is_the_successor_of_every_existing_rule_id() {
    // Non-numeric groups are bookkeeping, not rules, so they must not advance
    // the allocated id.
    let existing = "\
[2]
Description=other
wmclass=foo

[5]
Description=other two
wmclass=bar

[General]
count=2
rules=2,5

[GeneralWidgets]
size=12

";
    let ini = groups(&render(existing));
    assert!(ini.contains_key("6"), "next free id after 5 is 6");
    assert_eq!(
        ini.get("General").and_then(|g| g.get("rules")).map(String::as_str),
        Some("2,5,6")
    );
    assert_eq!(ini.get("General").and_then(|g| g.get("count")).map(String::as_str), Some("3"));
    assert_eq!(
        ini.get("GeneralWidgets").and_then(|g| g.get("size")).map(String::as_str),
        Some("12"),
        "unrelated group is preserved"
    );
}

// ============================================================================
// In-place update of an existing marker rule
// ============================================================================

#[test]
fn existing_marker_rule_is_updated_not_duplicated() {
    let existing = format!(
        "[7]\nDescription={DESCRIPTION}\nnoborder=false\nwmclass=stale-class\n\n[General]\ncount=1\nrules=7\n\n"
    );
    let content = render(&existing);
    let ini = groups(&content);

    assert_eq!(ini.get("7"), Some(&expected_rule_keys()), "group 7 overwritten with the rule");
    assert_eq!(ini.get("General").and_then(|g| g.get("count")).map(String::as_str), Some("1"));
    assert_eq!(ini.get("General").and_then(|g| g.get("rules")).map(String::as_str), Some("7"));
    assert!(!ini.contains_key("8"), "no duplicate rule appended");

    let marked: Vec<&String> = ini
        .iter()
        .filter(|(_, keys)| keys.get("Description").map(|d| d == DESCRIPTION).unwrap_or(false))
        .map(|(group, _)| group)
        .collect();
    assert_eq!(marked, vec![&"7".to_string()], "exactly one group carries the marker");
}

#[test]
fn marker_rule_among_several_keeps_general_consistent() {
    let existing = format!(
        "[2]\nDescription=first\n\n[5]\nDescription=middle\n\n[9]\nDescription={DESCRIPTION}\n\n[General]\ncount=3\nrules=2,5,9\n\n"
    );
    let rendered = render(&existing);
    let ini = groups(&rendered);

    assert_eq!(
        ini.get("General").and_then(|g| g.get("rules")).map(String::as_str),
        Some("2,5,9"),
        "ascending, no duplicates, no new id"
    );
    assert_eq!(ini.get("General").and_then(|g| g.get("count")).map(String::as_str), Some("3"));
    assert_eq!(ini.get("9"), Some(&expected_rule_keys()));
    assert!(!ini.contains_key("10"), "no duplicate rule appended");
}

// ============================================================================
// Idempotency
// ============================================================================

#[test]
fn render_is_idempotent() {
    for input in ["", UNRELATED_RULE] {
        let once = render(input);
        let twice = render(&once);
        assert_eq!(once, twice, "render(render(x)) == render(x)");
    }
}

#[test]
fn rendering_already_rendered_text_is_byte_identical() {
    let once = render(UNRELATED_RULE);
    let twice = render(&once);
    assert_eq!(once.as_bytes(), twice.as_bytes());
}

#[test]
fn second_render_of_marker_rule_does_not_rewrite_file() {
    // The adapter must be a no-op once the rule is in place; this mirrors the
    // `apply` short-circuit that keeps KWin from being reconfigured on every
    // daemon start.
    let once = render(UNRELATED_RULE);
    assert_eq!(render(&once), once);
}

// ============================================================================
// Parsing tolerance
// ============================================================================

#[test]
fn crlf_and_whitespace_input_is_parsed_and_normalised() {
    let existing = "[1]\r\nDescription=Wine player\r\nwmclass=cloudmusic.exe\r\n\r\n[General]\r\ncount=1\r\nrules=1\r\n";
    let content = render(existing);
    let ini = KdeIniFile::parse(&content);

    assert_eq!(
        ini.groups.get("1").and_then(|g| g.get("wmclass")).map(String::as_str),
        Some("cloudmusic.exe"),
        "CRLF rule group parsed"
    );
    assert_eq!(ini.groups.get("2"), Some(&expected_rule_keys()));
    assert_eq!(
        ini.groups.get("General").and_then(|g| g.get("rules")).map(String::as_str),
        Some("1,2")
    );
    assert_eq!(render(&content), content, "normalised output is stable");
}

// ============================================================================
// Marker lookup helper
// ============================================================================

#[test]
fn rule_group_id_finds_only_the_marked_numeric_rule() {
    let content = format!(
        "[3]\nDescription={DESCRIPTION}\n\n[General]\ncount=1\nrules=3\n\n"
    );
    assert_eq!(KWinWindowRulesAdapter::rule_group_id(&content, DESCRIPTION).as_deref(), Some("3"));
    assert_eq!(KWinWindowRulesAdapter::rule_group_id(&content, "absent"), None);
    assert_eq!(KWinWindowRulesAdapter::rule_group_id("", DESCRIPTION), None);
}
