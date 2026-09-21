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
