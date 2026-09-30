//! Display refresh preference.
//!
//! The panel here can run at 240 Hz, which multiplies the per-frame work of every
//! client - the shell's render thread, the compositor's blend and blur of the
//! shell's glass, and every other application (docs/LESSONS.md 33). The shell's own
//! motion budget is 30 fps, so 240 Hz scanout buys its surfaces nothing, but a user
//! may still want it for games or for a smoother desktop.
//!
//! So it is a *preference*, applied through kscreen-doctor, with `60` as the
//! default and `max` to leave the outputs exactly as the session configured them.
//! The chosen mode is always the highest refresh **at the current resolution** -
//! changing someone's resolution to reach a refresh rate would be a different,
//! much more invasive change than the one being asked for.

use astral_plasma::domain::display_modes::{
    choose_mode, kscreen_args, parse_kscreen_json, plan_outputs, RefreshPreference,
};

const FIXTURE: &str = r#"{
    "features": 255,
    "outputs": [
        {
            "id": 1,
            "name": "DP-3",
            "connected": true,
            "enabled": false,
            "currentModeId": "2",
            "modes": [
                { "id": "1", "name": "3440x1440@100", "refreshRate": 99.98, "size": { "width": 3440, "height": 1440 } },
                { "id": "2", "name": "3440x1440@165", "refreshRate": 165.0, "size": { "width": 3440, "height": 1440 } },
                { "id": "3", "name": "3440x1440@120", "refreshRate": 120.0, "size": { "width": 3440, "height": 1440 } }
            ]
        },
        {
            "id": 2,
            "name": "eDP-1",
            "connected": true,
            "enabled": true,
            "currentModeId": "37",
            "modes": [
                { "id": "37", "name": "2560x1600@240", "refreshRate": 240.0, "size": { "width": 2560, "height": 1600 } },
                { "id": "38", "name": "2560x1600@60", "refreshRate": 60.0, "size": { "width": 2560, "height": 1600 } },
                { "id": "39", "name": "1600x1200@60", "refreshRate": 59.87, "size": { "width": 1600, "height": 1200 } },
                { "id": "49", "name": "2560x1440@240", "refreshRate": 239.92, "size": { "width": 2560, "height": 1440 } }
            ]
        }
    ]
}"#;

#[test]
fn parses_outputs_with_their_current_mode_and_size() {
    let outputs = parse_kscreen_json(FIXTURE).expect("fixture parses");

    assert_eq!(outputs.len(), 2);
    let edp = outputs.iter().find(|o| o.name == "eDP-1").expect("eDP-1 present");
    assert!(edp.enabled);
    assert_eq!(edp.current_mode_id, "37");
    assert_eq!(edp.modes.len(), 4);
    let mode = edp.current_mode().expect("current mode is in the list");
    assert_eq!((mode.size.width, mode.size.height), (2560, 1600));
    assert!((mode.refresh_hz - 240.0).abs() < 0.01);
}

#[test]
fn broken_input_never_panics() {
    assert!(parse_kscreen_json("not json").is_err());
    assert!(parse_kscreen_json("{}").unwrap_or_default().is_empty());
}

#[test]
fn a_target_keeps_the_resolution_and_takes_the_highest_refresh_at_or_below_it() {
    let outputs = parse_kscreen_json(FIXTURE).unwrap();
    let edp = outputs.iter().find(|o| o.name == "eDP-1").unwrap();

    // 60 on a 240 Hz panel picks the 60 Hz mode at the same resolution.
    assert_eq!(choose_mode(edp, 60.0).as_deref(), Some("38"));
    // 120 has no exact mode: the highest below it (60) wins, never a higher one.
    assert_eq!(choose_mode(edp, 120.0).as_deref(), Some("38"));
    // 165 likewise lands on 60, not on 240.
    assert_eq!(choose_mode(edp, 165.0).as_deref(), Some("38"));
    // 240 keeps the current mode.
    assert_eq!(choose_mode(edp, 240.0).as_deref(), Some("37"));
    // 239.5 must not be rounded up into 240 Hz.
    assert_eq!(choose_mode(edp, 239.5).as_deref(), Some("38"));
}

#[test]
fn a_target_below_every_mode_asks_for_the_lowest_one() {
    let outputs = parse_kscreen_json(FIXTURE).unwrap();
    let edp = outputs.iter().find(|o| o.name == "eDP-1").unwrap();
    assert_eq!(choose_mode(edp, 30.0).as_deref(), Some("38"));
}

#[test]
fn resolution_is_never_changed_to_reach_a_refresh_rate() {
    let outputs = parse_kscreen_json(FIXTURE).unwrap();
    let edp = outputs.iter().find(|o| o.name == "eDP-1").unwrap();
    for target in [30.0, 60.0, 120.0, 165.0, 240.0, 500.0] {
        let id = choose_mode(edp, target).expect("a mode is always chosen");
        let mode = edp.modes.iter().find(|m| m.id == id).unwrap();
        assert_eq!(
            (mode.size.width, mode.size.height),
            (2560, 1600),
            "target {target} must stay at the panel's resolution"
        );
    }
}

#[test]
fn max_takes_the_highest_rate_the_output_offers() {
    // A panel someone had set to 60 Hz, with `max` asking for everything it has.
    let at_sixty = FIXTURE.replace("\"currentModeId\": \"37\"", "\"currentModeId\": \"38\"");
    let outputs = parse_kscreen_json(&at_sixty).unwrap();

    let plan = plan_outputs(&outputs, &RefreshPreference::Max);
    assert_eq!(plan, vec![("eDP-1".to_string(), "37".to_string())]);

    // Already at the panel's maximum: nothing to switch.
    let at_max = parse_kscreen_json(FIXTURE).unwrap();
    assert!(plan_outputs(&at_max, &RefreshPreference::Max).is_empty());
}

#[test]
fn max_never_reaches_for_a_smaller_resolution_either() {
    // The fixture's highest rate overall is the 2560x1600@240 mode; the 239.92 Hz
    // 2560x1440 mode must not win on a rounding comparison.
    let at_sixty = FIXTURE.replace("\"currentModeId\": \"37\"", "\"currentModeId\": \"38\"");
    let outputs = parse_kscreen_json(&at_sixty).unwrap();
    let edp = outputs.iter().find(|o| o.name == "eDP-1").unwrap();
    let chosen = choose_mode(edp, f64::INFINITY).expect("a mode is chosen");
    let mode = edp.modes.iter().find(|m| m.id == chosen).unwrap();
    assert_eq!(mode.name, "2560x1600@240");
}

#[test]
fn only_enabled_outputs_are_touched_and_only_when_they_need_it() {
    let outputs = parse_kscreen_json(FIXTURE).unwrap();
    let plan = plan_outputs(&outputs, &RefreshPreference::Target(60.0));

    // DP-3 is disabled: its mode is the compositor's business.
    assert_eq!(plan, vec![("eDP-1".to_string(), "38".to_string())]);

    // Already at the requested rate: no needless mode switch (which would blank
    // the output for a moment).
    let already = plan_outputs(&outputs, &RefreshPreference::Target(240.0));
    assert!(already.is_empty(), "240 Hz is the current mode, nothing to do");
}

#[test]
fn the_plan_becomes_one_atomic_kscreen_doctor_invocation() {
    let outputs = parse_kscreen_json(FIXTURE).unwrap();
    let plan = plan_outputs(&outputs, &RefreshPreference::Target(60.0));
    assert_eq!(kscreen_args(&plan), vec!["output.eDP-1.mode.38".to_string()]);
    assert!(kscreen_args(&[]).is_empty());
}

#[test]
fn the_preference_is_a_target_in_hertz_or_max() {
    assert_eq!(RefreshPreference::from_setting("max"), RefreshPreference::Max);
    assert_eq!(RefreshPreference::from_setting("MAX"), RefreshPreference::Max);
    assert_eq!(RefreshPreference::from_setting("60"), RefreshPreference::Target(60.0));
    assert_eq!(RefreshPreference::from_setting("144"), RefreshPreference::Target(144.0));
    assert_eq!(RefreshPreference::from_setting(" 120 "), RefreshPreference::Target(120.0));
    // Unknown or absent values fall back to the shipped default (60 Hz), which is
    // what makes an old settings.json - written before this key existed - safe.
    assert_eq!(RefreshPreference::from_setting(""), RefreshPreference::default());
    assert_eq!(RefreshPreference::from_setting("banana"), RefreshPreference::default());
    assert_eq!(RefreshPreference::from_setting("-5"), RefreshPreference::default());
    assert_eq!(RefreshPreference::default(), RefreshPreference::Target(60.0));
}

#[test]
fn restoring_prefers_the_mode_name_over_a_stale_id() {
    use astral_plasma::domain::display_modes::resolve_mode_reference;

    let outputs = parse_kscreen_json(FIXTURE).unwrap();
    // Names survive a driver reload renumbering ids - `2560x1600@240` is stable,
    // `37` is not - so the snapshot's name is used when it still exists.
    assert_eq!(
        resolve_mode_reference(&outputs, "eDP-1", "2560x1600@240", "999").as_deref(),
        Some("2560x1600@240")
    );
    // A mode that no longer exists falls back to the recorded id.
    assert_eq!(
        resolve_mode_reference(&outputs, "eDP-1", "2560x1600@300", "38").as_deref(),
        Some("38")
    );
    // A mode that is gone entirely is skipped rather than guessed at.
    assert_eq!(resolve_mode_reference(&outputs, "eDP-1", "gone", "gone"), None);
    assert_eq!(resolve_mode_reference(&outputs, "HDMI-9", "2560x1600@240", "37"), None);
}
