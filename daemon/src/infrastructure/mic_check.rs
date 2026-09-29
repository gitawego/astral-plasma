//! Device-only microphone check (`voice mic-check`).
//!
//! A three-second, on-device ritual with actionable feedback: open the same
//! capture path a session would use, measure peak RMS and clipping, and report
//! statistics — never audio. A dead or saturated mic is caught in setup, not
//! mid-dictation behind a frozen meter.
//!
//! Doubao's lesson applied: the first frame is shown but never judged (USB and
//! `pw-record` startup transients must not pass — or fail — the check alone).

use crate::domain::ports::{DynError, DynResult};
use crate::domain::voice::{
    clipping_ratio, frame_rms, mic_verdict, pcm_bytes_to_f32, pw_record_args, CaptureBackend,
    CaptureTarget, MicCheck, SPEECH_CHANNELS, SPEECH_SAMPLE_RATE,
};
use crate::infrastructure::whisper_stt_adapter::{
    CAPTURE_BACKEND_ENV, CAPTURE_BIN_ENV, INPUT_DEVICE_ENV,
};
use std::io::Read;
use std::time::{Duration, Instant};

/// Runs a device-only check for up to `secs` (clamped 1–10) and reports.
pub fn probe_microphone(secs: u64) -> DynResult<MicCheck> {
    let secs = secs.clamp(1, 10);
    let override_bin = std::env::var(CAPTURE_BIN_ENV).unwrap_or_default();
    let backend = if !override_bin.is_empty() {
        CaptureBackend::PwRecord
    } else {
        crate::domain::voice::select_capture_backend(
            &std::env::var(CAPTURE_BACKEND_ENV).unwrap_or_default(),
        )
    };
    match backend {
        CaptureBackend::PwRecord => probe_spawn(secs),
        CaptureBackend::Native => probe_native(secs),
    }
}

/// Frames per read and samples per frame (20 ms at 16 kHz).
const FRAME_LEN: usize = (SPEECH_SAMPLE_RATE as usize) / 50;

fn finish(
    backend: &str,
    device: String,
    secs: u64,
    started: Instant,
    frames: u64,
    peak: f32,
    clip_samples: &[f32],
) -> MicCheck {
    let ratio = clipping_ratio(clip_samples);
    let (verdict, advice) = mic_verdict(peak, ratio);
    MicCheck {
        backend: backend.to_string(),
        device,
        secs_requested: secs,
        secs_captured: started.elapsed().as_secs_f32(),
        frames,
        peak_rms: peak,
        clipping_ratio: ratio,
        verdict,
        advice,
    }
}

fn probe_spawn(secs: u64) -> DynResult<MicCheck> {
    let args = pw_record_args(CaptureTarget::Source, SPEECH_SAMPLE_RATE, SPEECH_CHANNELS, 32);
    let mut child = crate::infrastructure::whisper_stt_adapter::spawn_capture(&args)
        .map_err(|e| -> DynError { format!("Cannot open the microphone: {e}").into() })?;
    let mut stdout = child
        .stdout
        .take()
        .ok_or_else(|| -> DynError { "capture process produced no audio stream".into() })?;

    let frame_bytes = FRAME_LEN * 2;
    let started = Instant::now();
    let deadline = started + Duration::from_secs(secs);
    let mut buf = vec![0u8; frame_bytes * 8];
    let mut pending: Vec<u8> = Vec::new();
    let mut frames = 0u64;
    let mut peak = 0.0f32;
    let mut clip_samples: Vec<f32> = Vec::new();
    let mut first_frame = true;

    while Instant::now() < deadline {
        let n = match stdout.read(&mut buf) {
            Ok(0) => break,
            Ok(n) => n,
            Err(ref e) if e.kind() == std::io::ErrorKind::Interrupted => continue,
            Err(_) => break,
        };
        pending.extend_from_slice(&buf[..n]);
        while pending.len() >= frame_bytes {
            let floats = pcm_bytes_to_f32(&pending[..frame_bytes]);
            pending.drain(..frame_bytes);
            let level = frame_rms(&floats);
            // Shown but never judged: startup transients must not decide alone.
            if !first_frame && level.is_finite() {
                peak = peak.max(level);
            }
            first_frame = false;
            frames += 1;
            clip_samples.extend_from_slice(&floats);
        }
    }
    let _ = child.kill();
    let _ = child.wait();
    Ok(finish("pw-record", "default source".to_string(), secs, started, frames, peak, &clip_samples))
}

fn probe_native(secs: u64) -> DynResult<MicCheck> {
    use crate::infrastructure::whisper_stt_adapter::{
        ChannelFrameRead, FrameRead, open_native_input,
    };
    let wanted = std::env::var(INPUT_DEVICE_ENV).unwrap_or_default();
    let (stream, rx, device) = open_native_input(SPEECH_SAMPLE_RATE)?;
    let mut source = ChannelFrameRead::new(rx);
    let frame_bytes = FRAME_LEN * 2;
    let started = Instant::now();
    let deadline = started + Duration::from_secs(secs);
    let mut buf = vec![0u8; frame_bytes * 8];
    let mut pending: Vec<u8> = Vec::new();
    let mut frames = 0u64;
    let mut peak = 0.0f32;
    let mut clip_samples: Vec<f32> = Vec::new();
    let mut first_frame = true;

    while Instant::now() < deadline {
        let n = match source.read_chunk(&mut buf) {
            Ok(0) => break,
            Ok(n) => n,
            Err(ref e) if e.kind() == std::io::ErrorKind::Interrupted => continue,
            Err(_) => break,
        };
        pending.extend_from_slice(&buf[..n]);
        while pending.len() >= frame_bytes {
            let floats = pcm_bytes_to_f32(&pending[..frame_bytes]);
            pending.drain(..frame_bytes);
            let level = frame_rms(&floats);
            if !first_frame && level.is_finite() {
                peak = peak.max(level);
            }
            first_frame = false;
            frames += 1;
            clip_samples.extend_from_slice(&floats);
        }
    }
    drop(stream);
    let label = if wanted.trim().is_empty() {
        format!("native: {device}")
    } else {
        format!("native: {device} (matched '{wanted}')", wanted = wanted.trim())
    };
    Ok(finish("native", label, secs, started, frames, peak, &clip_samples))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn capture_env_lock() -> &'static std::sync::Mutex<()> {
        static LOCK: std::sync::OnceLock<std::sync::Mutex<()>> = std::sync::OnceLock::new();
        LOCK.get_or_init(|| std::sync::Mutex::new(()))
    }

    #[test]
    fn probe_reports_synthetic_capture_honestly() {
        // Loud tone through the stub capture path: usable signal, no clipping.
        let dir = tempfile::tempdir().unwrap();
        let capture = dir.path().join("stub-cap.sh");
        std::fs::write(
            &capture,
            "#!/usr/bin/env bash\npython3 - <<'PY'\nimport sys,math,struct\nout=bytearray()\nfor i in range(16000*2):\n out.extend(struct.pack('<h',int(0.3*32767*math.sin(2*math.pi*220*i/16000))))\nsys.stdout.buffer.write(bytes(out))\nPY\n",
        )
        .unwrap();
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let mut p = std::fs::metadata(&capture).unwrap().permissions();
            p.set_mode(0o755);
            std::fs::set_permissions(&capture, p).unwrap();
        }
        let _guard = capture_env_lock().lock().unwrap();
        std::env::set_var(CAPTURE_BIN_ENV, &capture);
        let report = probe_microphone(2).unwrap();
        std::env::remove_var(CAPTURE_BIN_ENV);
        assert_eq!(report.backend, "pw-record");
        assert!(report.frames > 40, "two seconds must yield frames");
        assert!(report.peak_rms > 0.05, "tone peak must register: {}", report.peak_rms);
        assert_eq!(report.verdict, crate::domain::voice::MicVerdict::Ok);
    }

    #[test]
    fn probe_calls_silence_silent() {
        let dir = tempfile::tempdir().unwrap();
        let capture = dir.path().join("sil-cap.sh");
        std::fs::write(
            &capture,
            "#!/usr/bin/env bash\npython3 -c 'import sys; sys.stdout.buffer.write(bytes(16000*2*2))'\n",
        )
        .unwrap();
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let mut p = std::fs::metadata(&capture).unwrap().permissions();
            p.set_mode(0o755);
            std::fs::set_permissions(&capture, p).unwrap();
        }
        let _guard = capture_env_lock().lock().unwrap();
        std::env::set_var(CAPTURE_BIN_ENV, &capture);
        let report = probe_microphone(1).unwrap();
        std::env::remove_var(CAPTURE_BIN_ENV);
        assert_eq!(report.verdict, crate::domain::voice::MicVerdict::Silent);
        assert!(report.advice.contains("Unmute") || report.advice.contains("muted") || report.advice.contains("nothing"));
    }
}
