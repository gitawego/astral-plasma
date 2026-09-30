//! The tray is a live list.
//!
//! The shell renders whatever the daemon last pushed, so the daemon has to
//! notice when the StatusNotifier watcher gains or loses an icon: an application
//! that starts after the shell did (Steam, a download manager, a game) otherwise
//! stays invisible in the dock until the user happens to click another tray item.
//!
//! Re-querying every item is expensive (a bus round trip per item, plus icon
//! extraction), so the watcher's registration list is the cheap signal: compare
//! it as a set and re-query only when it actually changed.

use astral_plasma::application::watch_events::{
    tray_item_keys, tray_registration_keys, tray_registrations_changed,
};
use astral_plasma::domain::model::TrayItem;
use astral_plasma::infrastructure::tray_adapter::split_registration;

fn item(service: &str, path: &str) -> TrayItem {
    TrayItem {
        service: service.to_string(),
        path: path.to_string(),
        id: "id".to_string(),
        title: "title".to_string(),
        material_icon: "circle".to_string(),
        raw_icon: String::new(),
        im_badge: String::new(),
        menu_path: String::new(),
        item_is_menu: false,
    }
}

fn owned(keys: &[&str]) -> Vec<String> {
    keys.iter().map(|k| k.to_string()).collect()
}

#[test]
fn a_registration_entry_splits_into_the_service_and_the_object_path() {
    assert_eq!(
        split_registration(":1.36/StatusNotifierItem"),
        (":1.36".to_string(), "/StatusNotifierItem".to_string())
    );
    assert_eq!(
        split_registration("org.kde.StatusNotifierItem-4980-1/StatusNotifierItem"),
        (
            "org.kde.StatusNotifierItem-4980-1".to_string(),
            "/StatusNotifierItem".to_string()
        )
    );
    assert_eq!(
        split_registration(":1.72/org/ayatana/NotificationItem/dropbox_client_5113"),
        (
            ":1.72".to_string(),
            "/org/ayatana/NotificationItem/dropbox_client_5113".to_string()
        )
    );
    // A registration without an explicit path lives at the root object.
    assert_eq!(split_registration(":1.99"), (":1.99".to_string(), "/".to_string()));
    assert_eq!(split_registration("   "), (String::new(), String::new()));
}

#[test]
fn registration_identity_is_a_set_not_a_sequence() {
    let baseline = tray_registration_keys(&owned(&[":1.36/StatusNotifierItem", ":1.36/Extra"]));
    let same_set = tray_registration_keys(&owned(&[
        ":1.36/Extra",
        ":1.36/StatusNotifierItem",
        ":1.36/StatusNotifierItem",
        "  :1.36/Extra  ",
    ]));

    assert_eq!(baseline, same_set, "order, duplicates and padding are not identity");
    assert!(
        !tray_registrations_changed(&baseline, &same_set),
        "an unchanged set must not trigger another tray query"
    );
}

#[test]
fn an_icon_appearing_or_leaving_is_a_change() {
    let baseline = tray_registration_keys(&owned(&[":1.36/StatusNotifierItem", ":1.224/StatusNotifierItem"]));

    // Steam (or a game) registering its icon while the shell is already running.
    let with_steam = tray_registration_keys(&owned(&[
        ":1.36/StatusNotifierItem",
        ":1.224/StatusNotifierItem",
        ":1.300/StatusNotifierItem",
    ]));
    assert!(tray_registrations_changed(&baseline, &with_steam));

    // An application quitting: its icon must go away as well.
    let without_music = tray_registration_keys(&owned(&[":1.36/StatusNotifierItem"]));
    assert!(tray_registrations_changed(&baseline, &without_music));

    // Nothing pushed yet: the first tick always queries.
    assert!(tray_registrations_changed(&[], &baseline));
    assert!(!tray_registrations_changed(&baseline, &baseline));
}

#[test]
fn the_pushed_items_are_the_baseline_that_live_registrations_are_compared_against() {
    // What refresh_tray pushed has to be comparable with what the watcher reports,
    // or every tick would look like a change.
    let items = vec![
        item(":1.36", "/StatusNotifierItem"),
        item(":1.224", "/StatusNotifierItem"),
    ];
    let pushed = tray_item_keys(&items);
    assert_eq!(
        pushed,
        tray_registration_keys(&owned(&[":1.224/StatusNotifierItem", ":1.36/StatusNotifierItem"]))
    );
    assert!(!tray_registrations_changed(
        &pushed,
        &owned(&[":1.36/StatusNotifierItem", ":1.224/StatusNotifierItem"])
    ));
    // The same item re-registering under a new unique bus name is a new identity.
    assert!(tray_registrations_changed(
        &pushed,
        &owned(&[":1.36/StatusNotifierItem", ":1.301/StatusNotifierItem"])
    ));
}
