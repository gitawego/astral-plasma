use crate::domain::ports::DynResult;
use serde::{Deserialize, Serialize};
use std::io::{self, BufReader, Read, Write};
use std::process::{Child, Command, Stdio};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::thread;
use std::time::{Duration, Instant};

pub const SAMPLE_RATE: usize = 8000;
pub const WINDOW_SIZE: usize = 256;
pub const NUM_BANDS: usize = 16;

// Target center frequencies for the 16 bands (from sub-bass up to Nyquist ~4000Hz)
pub const BAND_FREQUENCIES: [f32; NUM_BANDS] = [
    60.0, 100.0, 150.0, 220.0, 320.0, 460.0, 660.0, 950.0, 1300.0, 1800.0, 2400.0, 2900.0,
    3300.0, 3600.0, 3850.0, 4000.0,
];

// Frequency weighting curve (pink-noise / equal loudness equalization)
// Treble naturally carries ~10-20x less acoustic energy than bass; equalize so all bands are active
pub const BAND_WEIGHTS: [f32; NUM_BANDS] = [
    1.0, 1.0, 1.1, 1.25, 1.45, 1.75, 2.1, 2.6, 3.2, 3.8, 4.5, 5.0, 5.5, 6.0, 6.5, 7.0,
];

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct VisualizerFrame {
    #[serde(rename = "e")]
    pub energy: f32,
    #[serde(rename = "b")]
    pub bass: f32,
    #[serde(rename = "m")]
    pub mid: f32,
    #[serde(rename = "t")]
    pub treble: f32,
    #[serde(rename = "beat")]
    pub beat: f32,
    pub bands: Vec<f32>,
}

pub struct AudioAnalyzer {
    envelope_energy: f32,
    envelope_bass: f32,
    envelope_mid: f32,
    envelope_treble: f32,
    envelope_beat: f32,
    rolling_bass_avg: f32,
    prev_bass: f32,
    prev_energy: f32,
    envelope_bands: [f32; NUM_BANDS],
}

impl Default for AudioAnalyzer {
    fn default() -> Self {
        Self::new()
    }
}

impl AudioAnalyzer {
    pub fn new() -> Self {
        Self {
            envelope_energy: 0.0,
            envelope_bass: 0.0,
            envelope_mid: 0.0,
            envelope_treble: 0.0,
            envelope_beat: 0.0,
            rolling_bass_avg: 0.1,
            prev_bass: 0.0,
            prev_energy: 0.0,
            envelope_bands: [0.0; NUM_BANDS],
        }
    }

    /// Calculate RMS energy from normalized audio samples [-1.0 .. 1.0]
    pub fn calculate_rms(samples: &[f32]) -> f32 {
        if samples.is_empty() {
            return 0.0;
        }
        let sum_sq: f32 = samples.iter().map(|&s| s * s).sum();
        (sum_sq / samples.len() as f32).sqrt().min(1.0)
    }

    /// Goertzel algorithm to compute magnitude at a specific frequency
    pub fn goertzel_magnitude(samples: &[f32], target_freq: f32, sample_rate: f32) -> f32 {
        let n = samples.len();
        if n == 0 {
            return 0.0;
        }
        let omega = 2.0 * std::f32::consts::PI * target_freq / sample_rate;
        let coeff = 2.0 * omega.cos();

        let mut s_prev = 0.0f32;
        let mut s_prev2 = 0.0f32;

        for &sample in samples {
            let s = sample + coeff * s_prev - s_prev2;
            s_prev2 = s_prev;
            s_prev = s;
        }

        let power = s_prev * s_prev + s_prev2 * s_prev2 - coeff * s_prev * s_prev2;
        if power < 0.0 {
            0.0
        } else {
            // Normalize by window length
            (power.sqrt() / (n as f32 * 0.5) * 3.0).min(1.0)
        }
    }

    /// Process a chunk of normalized samples [-1.0 .. 1.0] and return a smoothed frame
    pub fn process_samples(&mut self, samples: &[f32]) -> VisualizerFrame {
        let raw_rms = Self::calculate_rms(samples);
        if raw_rms < 0.002 {
            self.envelope_energy *= 0.45;
            self.envelope_bass *= 0.45;
            self.envelope_mid *= 0.45;
            self.envelope_treble *= 0.45;
            self.envelope_beat = 0.0;
            self.prev_bass = 0.0;
            self.prev_energy = 0.0;
            for b in &mut self.envelope_bands {
                *b *= 0.45;
                if *b < 0.005 {
                    *b = 0.0;
                }
            }
            if self.envelope_energy < 0.005 { self.envelope_energy = 0.0; }
            if self.envelope_bass < 0.005 { self.envelope_bass = 0.0; }
            if self.envelope_mid < 0.005 { self.envelope_mid = 0.0; }
            if self.envelope_treble < 0.005 { self.envelope_treble = 0.0; }

            return VisualizerFrame {
                energy: round3(self.envelope_energy),
                bass: round3(self.envelope_bass),
                mid: round3(self.envelope_mid),
                treble: round3(self.envelope_treble),
                beat: 0.0,
                bands: self.envelope_bands.iter().map(|&b| round3(b)).collect(),
            };
        }

        let raw_energy = (raw_rms * 2.2).min(1.0);

        let mut raw_bands = [0.0f32; NUM_BANDS];
        for i in 0..NUM_BANDS {
            let base_mag = Self::goertzel_magnitude(samples, BAND_FREQUENCIES[i], SAMPLE_RATE as f32);
            // Apply spectral weighting so high bands have lively dynamic motion
            raw_bands[i] = (base_mag * BAND_WEIGHTS[i]).min(1.0);
        }

        // Bass: bands 0..4 (60 to 220 Hz)
        let inst_bass = (raw_bands[0..4].iter().sum::<f32>() / 4.0).min(1.0);
        let raw_bass = (inst_bass * 1.3).min(1.0);
        // Mid: bands 4..10 (320 to 1800 Hz)
        let raw_mid = (raw_bands[4..10].iter().sum::<f32>() / 6.0).min(1.0);
        // Treble: bands 10..16 (2400 to 4000 Hz)
        let raw_treble = (raw_bands[10..16].iter().sum::<f32>() / 6.0).min(1.0);

        // --- DYNAMIC BEAT ONSET & TRANSIENT FLUX ---
        // Positive flux / derivative detection: measure sharp rises in bass and full-spectrum energy
        let bass_delta = (inst_bass - self.prev_bass).max(0.0);
        let energy_delta = (raw_energy - self.prev_energy).max(0.0);
        self.prev_bass = inst_bass;
        self.prev_energy = raw_energy;

        // Adapt moving bass baseline to adapt to song loudness
        self.rolling_bass_avg += (inst_bass - self.rolling_bass_avg) * 0.05;

        // Transient onset occurs when instantaneous bass delta or energy delta spikes above noise threshold
        let onset_flux = bass_delta * 0.75 + energy_delta * 0.25;
        let flux_threshold = 0.05f32.max(self.rolling_bass_avg * 0.07);

        if onset_flux > flux_threshold {
            let transient = ((onset_flux - flux_threshold) * 4.0).min(1.0);
            if transient > self.envelope_beat {
                self.envelope_beat = transient.max(0.70); // Strong, punchy kick on beat onset
            } else {
                self.envelope_beat *= 0.70;
            }
        } else {
            self.envelope_beat *= 0.70;
        }

        if self.envelope_beat < 0.05 {
            self.envelope_beat = 0.0;
        }

        // Smooth envelope follower: fast attack, responsive decay
        Self::apply_envelope(&mut self.envelope_energy, raw_energy, 0.80, 0.22);
        Self::apply_envelope(&mut self.envelope_bass, raw_bass, 0.85, 0.20);
        Self::apply_envelope(&mut self.envelope_mid, raw_mid, 0.75, 0.25);
        Self::apply_envelope(&mut self.envelope_treble, raw_treble, 0.70, 0.28);

        for i in 0..NUM_BANDS {
            Self::apply_envelope(&mut self.envelope_bands[i], raw_bands[i], 0.82, 0.24);
        }

        VisualizerFrame {
            energy: round3(self.envelope_energy),
            bass: round3(self.envelope_bass),
            mid: round3(self.envelope_mid),
            treble: round3(self.envelope_treble),
            beat: round3(self.envelope_beat),
            bands: self.envelope_bands.iter().map(|&b| round3(b)).collect(),
        }
    }

    fn apply_envelope(current: &mut f32, target: f32, attack: f32, decay: f32) {
        if target > *current {
            *current += (target - *current) * attack;
        } else {
            *current += (target - *current) * decay;
        }
        if *current < 0.001 {
            *current = 0.0;
        }
    }

    /// Generate synthetic rhythmic frame when audio capture is offline or silent
    pub fn generate_synthetic_frame(t_secs: f32) -> VisualizerFrame {
        // 124 BPM rhythm base = ~2.067 Hz (period = ~0.484s)
        let beat_period = 60.0 / 124.0;
        let phase = (t_secs % beat_period) / beat_period;

        // Clean beat impulse: peaks at 1.0 at start of beat, decays cleanly to 0 by 30% of beat
        let beat = if phase < 0.30 {
            let p = phase / 0.30;
            ((1.0 - p).powi(2)).max(0.0)
        } else {
            0.0
        };

        let bass = ((phase * std::f32::consts::PI * 2.0).cos().max(0.0) * 0.6 + beat * 0.4).min(1.0);
        let mid = ((t_secs * 3.7).sin().abs() * 0.5 + 0.15).min(1.0);
        let treble = ((t_secs * 7.1).cos().abs() * 0.4 + 0.1).min(1.0);
        let energy = (bass * 0.5 + mid * 0.3 + treble * 0.2).min(1.0);

        let mut bands = Vec::with_capacity(NUM_BANDS);
        for i in 0..NUM_BANDS {
            let offset = i as f32 * 0.35;
            let val = ((t_secs * 4.0 + offset).sin() * 0.4 + 0.4) * (0.3 + (NUM_BANDS - i) as f32 / NUM_BANDS as f32 * 0.5) * energy + beat * 0.2;
            bands.push(round3(val.min(1.0)));
        }

        VisualizerFrame {
            energy: round3(energy),
            bass: round3(bass),
            mid: round3(mid),
            treble: round3(treble),
            beat: round3(beat),
            bands,
        }
    }
}

fn round3(val: f32) -> f32 {
    (val * 1000.0).round() / 1000.0
}

/// Convert 16-bit little-endian PCM bytes into normalized [-1.0 .. 1.0] floats
pub fn pcm_bytes_to_samples(bytes: &[u8]) -> Vec<f32> {
    let num_samples = bytes.len() / 2;
    let mut samples = Vec::with_capacity(num_samples);
    for i in 0..num_samples {
        let sample_i16 = i16::from_le_bytes([bytes[i * 2], bytes[i * 2 + 1]]);
        samples.push(sample_i16 as f32 / 32768.0);
    }
    samples
}

/// Run the audio visualizer process loop streaming to stdout
pub fn run_audio_visualizer(running_flag: Option<Arc<AtomicBool>>) -> DynResult<()> {
    let running = running_flag.unwrap_or_else(|| Arc::new(AtomicBool::new(true)));

    // Try starting pw-record targeting the default sink monitor
    let mut child: Option<Child> = Command::new("pw-record")
        .args([
            "--target",
            "@DEFAULT_AUDIO_SINK@.monitor",
            "--rate",
            &SAMPLE_RATE.to_string(),
            "--channels",
            "1",
            "--format",
            "s16",
            "-",
        ])
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .ok();

    let mut analyzer = AudioAnalyzer::new();
    let stdout = io::stdout();
    let mut out_handle = stdout.lock();

    // 256 samples * 2 bytes = 512 bytes per frame
    let chunk_bytes = WINDOW_SIZE * 2;
    let mut buf = vec![0u8; chunk_bytes];
    let mut prev_buf = vec![0u8; chunk_bytes];
    let mut stall_count: usize = 0;

    // Frame interval ~32ms = ~31.25 FPS
    let frame_duration = Duration::from_millis(32);

    if let Some(ref mut proc) = child {
        if let Some(pipe_stdout) = proc.stdout.take() {
            let mut reader = BufReader::new(pipe_stdout);

            while running.load(Ordering::Relaxed) {
                let frame_start = Instant::now();

                match reader.read_exact(&mut buf) {
                    Ok(_) => {
                        if buf == prev_buf {
                            stall_count += 1;
                        } else {
                            stall_count = 0;
                            prev_buf.copy_from_slice(&buf);
                        }

                        // If stalled for >= 2 consecutive frames (e.g. Wine paused without corking),
                        // feed silence so visualizer envelopes decay smoothly to 0.0
                        let samples = if stall_count >= 2 {
                            vec![0.0f32; WINDOW_SIZE]
                        } else {
                            pcm_bytes_to_samples(&buf)
                        };

                        let frame = analyzer.process_samples(&samples);
                        if let Ok(json) = serde_json::to_string(&frame) {
                            if writeln!(out_handle, "{}", json).is_err() || out_handle.flush().is_err() {
                                break;
                            }
                        }
                    }
                    Err(_) => {
                        // Stream broke or ended; break to fallback
                        break;
                    }
                }

                let elapsed = frame_start.elapsed();
                if elapsed < frame_duration {
                    thread::sleep(frame_duration - elapsed);
                }
            }
        }
        let _ = proc.kill();
    }

    // Fallback loop if child could not spawn or exited early: stream silent zero-energy frames
    let silent_frame = VisualizerFrame {
        energy: 0.0,
        bass: 0.0,
        mid: 0.0,
        treble: 0.0,
        beat: 0.0,
        bands: vec![0.0; NUM_BANDS],
    };
    let silent_json = serde_json::to_string(&silent_frame).unwrap_or_default();

    while running.load(Ordering::Relaxed) {
        let frame_start = Instant::now();

        if writeln!(out_handle, "{}", silent_json).is_err() || out_handle.flush().is_err() {
            break;
        }

        let elapsed = frame_start.elapsed();
        if elapsed < frame_duration {
            thread::sleep(frame_duration - elapsed);
        }
    }

    Ok(())
}
