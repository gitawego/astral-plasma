//! The daemon must not compile a KWin script per window refresh.
//!
//! KWin runs scripts on its main thread; loading, running and stopping a fresh
//! throwaway script on every refresh is what produced
//! "The main thread was hanging temporarily!" in the compositor log, and a
//! hanging compositor main thread eats global shortcuts (Alt+Tab stops
//! responding). The resident watcher script already pushes the window list to
//! `UpdateWindowList` on every window event, so `query_windows()` consumes that
//! push whenever it is fresh.

use astral_plasma::infrastructure::kwin_adapter::{
    push_is_fresh, pushed_window_list, store_pushed_window_list,
};

#[test]
fn test_pushed_window_list_round_trip() {
    store_pushed_window_list(r#"[{"id":"abc","title":"Terminal"}]"#);
    let (age, json) = pushed_window_list().expect("a stored push must be readable");
    assert!(age.as_secs() < 5, "a fresh push must report a small age");
    assert!(json.contains("\"title\":\"Terminal\""), "payload must round-trip");
}

#[test]
fn test_only_recent_pushes_answer_a_query() {
    assert!(push_is_fresh(std::time::Duration::from_millis(0)));
    assert!(push_is_fresh(std::time::Duration::from_millis(1500)));
    assert!(!push_is_fresh(std::time::Duration::from_secs(30)),
        "a stale push must not be reused as if it were current");
}

#[test]
fn test_query_prefers_the_push_over_scripting() {
    let source = std::fs::read_to_string(
        concat!(env!("CARGO_MANIFEST_DIR"), "/src/infrastructure/kwin_adapter.rs"),
    )
    .expect("kwin_adapter.rs must be readable");
    assert!(source.contains("pushed_window_list()"),
        "query_windows must consult the pushed list before scripting KWin");
    assert!(source.contains("query_windows_via_script"),
        "the scripting query must remain as the cold-start fallback");

    let events = std::fs::read_to_string(
        concat!(env!("CARGO_MANIFEST_DIR"), "/src/application/watch_events.rs"),
    )
    .expect("watch_events.rs must be readable");
    assert!(events.contains("store_pushed_window_list"),
        "the UpdateWindowList D-Bus handler must cache the pushed list");
}
