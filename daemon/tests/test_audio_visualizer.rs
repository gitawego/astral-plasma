use astral_plasma::application::audio_visualizer::{
    pcm_bytes_to_samples, AudioAnalyzer, VisualizerFrame, NUM_BANDS, SAMPLE_RATE, WINDOW_SIZE,
};

#[test]
fn test_rms_calculation() {
    let silence = vec![0.0f32; 256];
    assert_eq!(AudioAnalyzer::calculate_rms(&silence), 0.0);

    let max_signal = vec![1.0f32; 256];
    assert!((AudioAnalyzer::calculate_rms(&max_signal) - 1.0).abs() < 1e-5);

    let empty: [f32; 0] = [];
    assert_eq!(AudioAnalyzer::calculate_rms(&empty), 0.0);
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
fn test_synthetic_frame_generation() {
    for t in [0.0f32, 0.25, 0.5, 1.0, 2.5] {
        let frame = AudioAnalyzer::generate_synthetic_frame(t);
        assert!(frame.energy >= 0.0 && frame.energy <= 1.0);
        assert!(frame.bass >= 0.0 && frame.bass <= 1.0);
        assert!(frame.mid >= 0.0 && frame.mid <= 1.0);
        assert!(frame.treble >= 0.0 && frame.treble <= 1.0);
        assert!(frame.beat >= 0.0 && frame.beat <= 1.0);
        assert_eq!(frame.bands.len(), NUM_BANDS);
    }
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
