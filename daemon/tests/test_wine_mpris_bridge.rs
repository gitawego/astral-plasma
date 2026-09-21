//! The bridge must own its bus name, and only claim it when it can.
//!
//! zbus requests bus names with `DoNotQueue`, so a bridge that cannot become the
//! owner has to fail loudly. It used to report success while serving objects
//! nobody could reach, and the shell then silently fell back to whatever other
//! MPRIS player was around - a stale browser session, in practice.

use astral_plasma::application::wine_mpris::{WineMprisService, WINE_MPRIS_BUS_NAME};

#[tokio::test]
async fn bridge_takes_over_a_name_a_dying_instance_released() {
    // Without a session bus there is nothing to test (headless CI).
    let Ok(conn) = zbus::Connection::session().await else {
        return;
    };
    let proxy = zbus::fdo::DBusProxy::new(&conn).await.expect("bus proxy");
    let name = zbus::names::BusName::try_from(WINE_MPRIS_BUS_NAME).expect("bus name");

    if proxy.get_name_owner(name).await.is_ok() {
        // A running shell already owns it; nothing to prove here.
        eprintln!("skipping: {WINE_MPRIS_BUS_NAME} is already owned");
        return;
    }

    // The outgoing instance owns the name.
    let outgoing = WineMprisService::new().await.expect("outgoing bridge");

    // A second bridge must *fail* rather than queue: the supervisor retries, and
    // a queued bridge would look healthy while being unreachable.
    assert!(
        WineMprisService::new().await.is_err(),
        "a taken name must be reported, not queued"
    );

    // Once the outgoing instance goes away, the name is claimable again - which is
    // what the supervisor does on its next tick.
    drop(outgoing);
    let incoming = WineMprisService::new().await;
    assert!(
        incoming.is_ok(),
        "the bridge must take over a released name: {:?}",
        incoming.err()
    );
}

/// The bridge must own its bus name, and release it when it goes away.
///
/// The shell discovers the Wine player by that name alone. The connection
/// builder's own name request can be left pending without an owner - the bridge
/// then serves objects nobody can reach, the shell loses the music player, and
/// the media widget falls back to whatever else is on the bus (a browser session
/// that merely claims to be playing). Claiming the name explicitly and checking
/// the reply is what keeps it reachable.
#[tokio::test]
async fn the_bridge_owns_its_bus_name() {
    use astral_plasma::application::wine_mpris::{WineMprisService, WINE_MPRIS_BUS_NAME};

    let conn = zbus::Connection::session().await.expect("session bus");
    let proxy = zbus::fdo::DBusProxy::new(&conn).await.expect("bus proxy");
    let name = zbus::names::BusName::try_from(WINE_MPRIS_BUS_NAME).expect("bus name");

    if proxy.get_name_owner(name.clone()).await.is_ok() {
        // A running shell already owns it; nothing to prove here.
        eprintln!("skipping: {WINE_MPRIS_BUS_NAME} is already owned");
        return;
    }

    let service = WineMprisService::new().await.expect("bridge must build");
    let owner = proxy.get_name_owner(name.clone()).await;
    assert!(
        owner.is_ok(),
        "the bridge must own {WINE_MPRIS_BUS_NAME} once built: {owner:?}"
    );

    drop(service);
    assert!(
        proxy.get_name_owner(name).await.is_err(),
        "dropping the bridge must release the name, so a restart can take over"
    );
}
