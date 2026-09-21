//! Who is actually making sound.
//!
//! MPRIS playback state is a claim: a browser media session keeps reporting
//! `Playing` for a background tab, a muted video, or a page that has long been
//! closed. The sink inputs are the ground truth, and the shell arbitrates
//! players with them.

use astral_plasma::application::audio_streams::{
    parse_audible_streams, stream_matches_player, AudioStream,
};

const PACTL: &str = r#"
Sink Input #3933
	Driver: PipeWire
	application.name = "NetEase Cloud Music"
	application.process.binary = "wine-preloader"
	Corked: no
	Mute: no

Sink Input #4001
	Driver: PipeWire
	application.name = "Microsoft Edge"
	application.process.binary = "msedge"
	Corked: yes
	Mute: no

Sink Input #4002
	Driver: PipeWire
	application.name = "Haruna"
	application.process.binary = "haruna"
	Corked: no
	Mute: yes
"#;

#[test]
fn only_uncorked_unmuted_streams_are_audible() {
    let streams = parse_audible_streams(PACTL);

    assert_eq!(
        streams,
        vec![AudioStream {
            name: "NetEase Cloud Music".to_string(),
            binary: "wine-preloader".to_string(),
        }],
        "a corked (background tab) or muted stream is not producing sound"
    );
}

#[test]
fn an_empty_or_foreign_output_is_harmless() {
    assert!(parse_audible_streams("").is_empty());
    assert!(parse_audible_streams("No PulseAudio daemon running").is_empty());
}

#[test]
fn player_matching_is_generic_not_a_lookup_table() {
    let music = AudioStream {
        name: "NetEase Cloud Music".to_string(),
        binary: "wine-preloader".to_string(),
    };
    assert!(
        stream_matches_player(
            &music,
            "NetEase Cloud Music (Wine)",
            "org.mpris.MediaPlayer2.cloudmusic"
        ),
        "the Wine bridge's identity must match its audio stream"
    );

    let edge = AudioStream {
        name: "Microsoft Edge".to_string(),
        binary: "msedge".to_string(),
    };
    assert!(stream_matches_player(
        &edge,
        "Microsoft Edge",
        "org.mpris.MediaPlayer2.edge.instance3710"
    ));
    assert!(
        !stream_matches_player(&edge, "Haruna", "org.mpris.MediaPlayer2.haruna"),
        "a stream must not match an unrelated player"
    );
    assert!(
        !stream_matches_player(&music, "Haruna", "org.mpris.MediaPlayer2.haruna"),
        "and the Wine binary must not match every Wine application"
    );
}
