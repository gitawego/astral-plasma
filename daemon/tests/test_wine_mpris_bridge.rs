//! The Wine MPRIS bridge is a singleton bus name, and shell reloads are a
//! normal development occurrence: the outgoing daemon may still own the name
//! while the new one starts.
//!
//! zbus requests bus names with `DoNotQueue`, so a single failed request used
//! to leave the whole session without a Wine player - the theme then silently
//! fell back to some other MPRIS player and showed "No Media Playing".

use astral_plasma::application::wine_mpris::{connect_wine_mpris_with_retry, WineMprisService};
use std::time::Duration;

#[tokio::test]
async fn bridge_acquires_the_name_that_a_dying_instance_still_holds() {
    // Without a session bus there is nothing to test (headless CI).
    if zbus::Connection::session().await.is_err() {
        return;
    }

    // The outgoing instance owns the name.
    let outgoing = WineMprisService::new()
        .await
        .expect("first instance must obtain the free name");

    // It dies part-way through the incoming instance's retry window.
    let dying = tokio::spawn(async move {
        tokio::time::sleep(Duration::from_millis(150)).await;
        drop(outgoing);
    });

    let incoming = connect_wine_mpris_with_retry(40, Duration::from_millis(50))
        .await
        .expect("the bridge must retry until the previous owner releases the name");

    dying.await.unwrap();

    // The recovered bridge serves the interface.
    let media = astral_plasma::domain::wine_media::WineMediaInfo {
        player_id: "cloudmusic".to_string(),
        player_name: "NetEase Cloud Music (Wine)".to_string(),
        title: "Test Track".to_string(),
        artist: "Test Artist".to_string(),
        is_playing: true,
        art_url: String::new(),
        duration_ms: 1000,
    };
    incoming
        .update_media(&media)
        .await
        .expect("the recovered bridge must accept media updates");
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
