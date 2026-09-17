use astral_plasma::application::audio_visualizer::{
    build_pw_record_args, drain_pipe_backlog, pcm_bytes_to_samples, AudioAnalyzer,
    VisualizerFrame, NUM_BANDS, SAMPLE_RATE, WINDOW_SIZE,
};

#[test]
fn test_pw_record_sink_monitor_args_capture_sink_not_mic() {
    let args = build_pw_record_args();
    assert!(args.contains(&"--raw".to_string()), "pw-record must include --raw to avoid AU container header corruption");

    let p_idx = args.iter().position(|a| a == "-P").expect("pw-record must include -P properties flag");
    let prop_json = &args[p_idx + 1];
    assert!(prop_json.contains("\"stream.capture.sink\": true") || prop_json.contains("\"stream.capture.sink\":true"),
        "pw-record must set stream.capture.sink: true so PipeWire links to speaker monitor rather than physical microphone");

    let target_idx = args.iter().position(|a| a == "--target").expect("pw-record must specify target");
    assert_eq!(args[target_idx + 1], "@DEFAULT_AUDIO_SINK@", "pw-record must target @DEFAULT_AUDIO_SINK@");
}

#[test]
fn test_pw_record_args_include_low_latency() {
    let args = build_pw_record_args();
    let lat_idx = args.iter().position(|a| a == "--latency").expect("pw-record must specify --latency flag for real-time streaming");
    assert_eq!(args[lat_idx + 1], "32ms", "pw-record must request 32ms latency to match 256-sample window @ 8000Hz");
}

#[test]
fn test_drain_pipe_backlog_drops_stale_bytes() {
    use std::io::Cursor;

    let chunk_size = 512;
    // Simulate 4 chunks (2048 bytes) queued in the pipe:
    // Chunk 0: 0x11
    // Chunk 1: 0x22
    // Chunk 2: 0x33
    // Chunk 3: 0x44 (the newest live chunk)
    let mut data = Vec::new();
    data.extend(vec![0x11u8; chunk_size]);
    data.extend(vec![0x22u8; chunk_size]);
    data.extend(vec![0x33u8; chunk_size]);
    data.extend(vec![0x44u8; chunk_size]);

    let mut cursor = Cursor::new(data);
    let skipped = drain_pipe_backlog(&mut cursor, 2048, chunk_size).expect("Draining backlog must succeed");

    // Must discard 3 chunks (1536 bytes) so exactly 1 chunk (the newest 512 bytes) remains
    assert_eq!(skipped, 1536, "Must skip (4 - 1) * 512 = 1536 stale bytes");

    let mut remaining = vec![0u8; chunk_size];
    std::io::Read::read_exact(&mut cursor, &mut remaining).expect("Must read final chunk");
    assert_eq!(remaining[0], 0x44, "The remaining chunk must be the newest live audio frame (0x44)");

    // When backlog <= chunk_size * 2, no frames should be skipped (normal jitter tolerance)
    let mut jitter_cursor = Cursor::new(vec![0xAAu8; 800]);
    let skipped_jitter = drain_pipe_backlog(&mut jitter_cursor, 800, chunk_size).expect("Jitter drain must succeed");
    assert_eq!(skipped_jitter, 0, "Do not skip bytes when backlog is within normal jitter (< 2 chunks)");
}

#[test]
fn test_rms_calculation() {
    let silence = vec![0.0f32; 256];
    assert_eq!(AudioAnalyzer::calculate_rms(&silence), 0.0);

    // Constant DC flatline (e.g. Wine paused DAC latching to -1.0 or 1.0) must produce 0.0 RMS
    let wine_paused_dc = vec![-1.0f32; 256];
    assert_eq!(AudioAnalyzer::calculate_rms(&wine_paused_dc), 0.0, "Wine paused DC flatline must be 0.0 energy");

    let positive_dc = vec![1.0f32; 256];
    assert_eq!(AudioAnalyzer::calculate_rms(&positive_dc), 0.0, "Constant DC offset must be 0.0 acoustic energy");

    // True AC square wave alternating between -1.0 and 1.0 has RMS of 1.0
    let max_ac_square: Vec<f32> = (0..256).map(|i| if i % 2 == 0 { 1.0 } else { -1.0 }).collect();
    assert!((AudioAnalyzer::calculate_rms(&max_ac_square) - 1.0).abs() < 1e-4);

    let empty: [f32; 0] = [];
    assert_eq!(AudioAnalyzer::calculate_rms(&empty), 0.0);
}

#[test]
fn test_wine_paused_dc_frame_is_completely_silent() {
    let mut analyzer = AudioAnalyzer::new();
    let wine_paused = vec![-1.0f32; WINDOW_SIZE];

    let frame = analyzer.process_samples(&wine_paused);
    assert_eq!(frame.energy, 0.0, "Energy must be 0.0 on Wine paused DC latch");
    assert_eq!(frame.beat, 0.0, "Beat must be 0.0 on Wine paused DC latch");
    assert!(frame.bands.iter().all(|&b| b == 0.0), "All frequency bands must be 0.0 on Wine paused DC latch");
}

#[test]
fn test_wine_paused_rail_underrun_glitch_is_silent() {
    let mut analyzer = AudioAnalyzer::new();
    // Simulate Wine paused buffer underrun: mostly -1.0 with rail jitter between -0.85 and -1.0
    let mut glitch = vec![-1.0f32; WINDOW_SIZE];
    for i in 200..WINDOW_SIZE {
        glitch[i] = -0.85;
    }

    assert_eq!(AudioAnalyzer::calculate_rms(&glitch), 0.0, "Negative-rail glitch must be identified as 0.0 DC silence");

    let frame = analyzer.process_samples(&glitch);
    assert_eq!(frame.energy, 0.0, "Energy must be 0.0 on Wine negative-rail glitch");
    assert_eq!(frame.beat, 0.0, "Beat must never trigger on Wine negative-rail glitch");
    assert!(frame.bands.iter().all(|&b| b == 0.0), "All bands must remain 0.0 on Wine negative-rail glitch");
}

#[test]
fn test_wine_paused_step_underrun_glitch_is_silent() {
    let mut analyzer = AudioAnalyzer::new();
    // Simulate Wine paused buffer wrap / step underrun:
    // 80 samples clamped to -1.0 DAC rail, remaining 176 samples at 0.0 silence.
    // Mean = -0.3125 (mean.abs() < 0.35), but is a pure 2-state DC latch artifact.
    let mut glitch = vec![0.0f32; WINDOW_SIZE];
    for i in 0..80 {
        glitch[i] = -1.0;
    }

    assert_eq!(AudioAnalyzer::calculate_rms(&glitch), 0.0, "Step DC glitch between rail and zero must be 0.0 silence");

    let frame = analyzer.process_samples(&glitch);
    assert_eq!(frame.energy, 0.0, "Energy must be 0.0 on Wine step underrun glitch");
    assert_eq!(frame.beat, 0.0, "Beat must never trigger on Wine step underrun glitch");
    assert!(frame.bands.iter().all(|&b| b == 0.0), "All bands must remain 0.0 on Wine step underrun glitch");
}

#[test]
fn test_pcm_bytes_to_samples() {
    let mut bytes = Vec::new();
    // 0
    bytes.extend_from_slice(&0i16.to_le_bytes());
    // 32767 (max positive)
    bytes.extend_from_slice(&32767i16.to_le_bytes());
    // -32768 (min negative)
    bytes.extend_from_slice(&(-32768i16).to_le_bytes());

    let samples = pcm_bytes_to_samples(&bytes);
    assert_eq!(samples.len(), 3);
    assert_eq!(samples[0], 0.0);
    assert!((samples[1] - (32767.0 / 32768.0)).abs() < 1e-4);
    assert_eq!(samples[2], -1.0);
}

#[test]
fn test_goertzel_magnitude() {
    // Generate a pure 100 Hz sine wave at 8000 Hz
    let freq = 100.0f32;
    let mut samples = Vec::with_capacity(WINDOW_SIZE);
    for i in 0..WINDOW_SIZE {
        let t = i as f32 / SAMPLE_RATE as f32;
        samples.push((2.0 * std::f32::consts::PI * freq * t).sin());
    }

    let mag_100 = AudioAnalyzer::goertzel_magnitude(&samples, 100.0, SAMPLE_RATE as f32);
    let mag_3000 = AudioAnalyzer::goertzel_magnitude(&samples, 3000.0, SAMPLE_RATE as f32);

    assert!(mag_100 > 0.5, "Expected strong response at 100 Hz, got {}", mag_100);
    assert!(mag_3000 < 0.2, "Expected weak response at 3000 Hz for 100 Hz input, got {}", mag_3000);
}

#[test]
fn test_analyzer_process_samples() {
    let mut analyzer = AudioAnalyzer::new();
    // 150 Hz tone
    let mut samples = Vec::with_capacity(WINDOW_SIZE);
    for i in 0..WINDOW_SIZE {
        let t = i as f32 / SAMPLE_RATE as f32;
        samples.push(0.8 * (2.0 * std::f32::consts::PI * 150.0 * t).sin());
    }

    let frame = analyzer.process_samples(&samples);
    assert!(frame.energy >= 0.0 && frame.energy <= 1.0);
    assert!(frame.bass >= 0.0 && frame.bass <= 1.0);
    assert!(frame.mid >= 0.0 && frame.mid <= 1.0);
    assert!(frame.treble >= 0.0 && frame.treble <= 1.0);
    assert!(frame.beat >= 0.0 && frame.beat <= 1.0);
    assert_eq!(frame.bands.len(), NUM_BANDS);

    for &b in &frame.bands {
        assert!(b >= 0.0 && b <= 1.0, "Band value {} out of range [0, 1]", b);
    }
}

#[test]
fn test_dsp_beat_transient_response() {
    let mut analyzer = AudioAnalyzer::new();

    // 1. Steady baseline tone -> beat should stay near 0.0 after adaptation
    let mut steady = Vec::with_capacity(WINDOW_SIZE);
    for i in 0..WINDOW_SIZE {
        let t = i as f32 / SAMPLE_RATE as f32;
        steady.push(0.3 * (2.0 * std::f32::consts::PI * 80.0 * t).sin());
    }
    for _ in 0..8 {
        analyzer.process_samples(&steady);
    }

    // 2. Sudden sharp kick burst (2.5x amplitude spike) -> must register real transient beat
    let mut kick = Vec::with_capacity(WINDOW_SIZE);
    for i in 0..WINDOW_SIZE {
        let t = i as f32 / SAMPLE_RATE as f32;
        kick.push(0.95 * (2.0 * std::f32::consts::PI * 70.0 * t).sin());
    }
    let kick_frame = analyzer.process_samples(&kick);
    assert!(kick_frame.beat > 0.1, "Dynamic DSP beat must trigger on sudden kick drum transient, got {}", kick_frame.beat);

    // 3. Dead silence -> beat must be exactly 0.0
    let silence = vec![0.0f32; WINDOW_SIZE];
    for _ in 0..5 {
        analyzer.process_samples(&silence);
    }
    let silent_frame = analyzer.process_samples(&silence);
    assert_eq!(silent_frame.beat, 0.0, "Beat must be 0.0 on silence");
}

#[test]
fn test_json_serialization() {
    let frame = VisualizerFrame {
        energy: 0.42,
        bass: 0.68,
        mid: 0.35,
        treble: 0.18,
        beat: 0.75,
        bands: vec![0.1; NUM_BANDS],
    };

    let json = serde_json::to_string(&frame).expect("Failed to serialize frame");
    assert!(json.contains("\"e\":0.42"));
    assert!(json.contains("\"b\":0.68"));
    assert!(json.contains("\"m\":0.35"));
    assert!(json.contains("\"t\":0.18"));
    assert!(json.contains("\"beat\":0.75"));
    assert!(json.contains("\"bands\":["));

    let deserialized: VisualizerFrame = serde_json::from_str(&json).expect("Failed to deserialize frame");
    assert_eq!(deserialized, frame);
}

#[test]
fn test_analyzer_silence_decay() {
    let mut analyzer = AudioAnalyzer::new();
    let silence = vec![0.0f32; WINDOW_SIZE];

    // Initially silent
    let frame = analyzer.process_samples(&silence);
    assert_eq!(frame.energy, 0.0);
    assert_eq!(frame.beat, 0.0);
    assert!(frame.bands.iter().all(|&b| b == 0.0));

    // Play some audio
    let mut tone = Vec::with_capacity(WINDOW_SIZE);
    for i in 0..WINDOW_SIZE {
        let t = i as f32 / SAMPLE_RATE as f32;
        tone.push(0.9 * (2.0 * std::f32::consts::PI * 120.0 * t).sin());
    }
    let active_frame = analyzer.process_samples(&tone);
    assert!(active_frame.energy > 0.0);

    // Stop playback (pause / silence) -> should decay cleanly to 0.0 within a few frames
    let mut final_frame = active_frame;
    for _ in 0..10 {
        final_frame = analyzer.process_samples(&silence);
    }
    assert_eq!(final_frame.energy, 0.0, "Energy must decay to 0.0 on pause/silence");
    assert_eq!(final_frame.beat, 0.0, "Beat must be 0.0 on pause/silence");
    assert!(final_frame.bands.iter().all(|&b| b == 0.0), "All bands must decay to 0.0 on silence");
}
