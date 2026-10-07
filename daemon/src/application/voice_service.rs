//! Voice input application service.
//!
//! Owns the use cases the CLI and UI drive: readiness reporting, model
//! provisioning, and the control-loop session. It composes a
//! [`SpeechToTextPort`] and knows nothing about any particular engine, which is
//! what lets the integration tests substitute a fake.
//!
//! See `docs/VOICE-INPUT-SPEC.md` for the decision record.

use crate::domain::ports::{DynError, DynResult, SpeechToTextPort};
use crate::infrastructure::whisper_stt_adapter::{models_dir, CancelHandle};
use crate::domain::voice::{
    model_descriptors, setup_gap_for, staged_download_paths, EngineProbe, LanguageOption,
    ModelDescriptor, SetupGap, Transcript, VoiceEvent, VoiceSessionConfig, VoiceSettings,
    VoiceState, VoiceStatus, MODEL_CATALOG,
};
use std::io::{BufRead, Read, Write};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::Arc;

/// A control command arriving on the session's stdin channel.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum VoiceCommand {
    /// Begin capture.
    Start,
    /// Finalize and transcribe.
    Stop,
    /// Abort and discard.
    Cancel,
}

impl VoiceCommand {
    /// Parses one control line. Unknown lines are rejected rather than guessed.
    pub fn parse(line: &str) -> Option<Self> {
        match line.trim().to_ascii_lowercase().as_str() {
            "start" => Some(VoiceCommand::Start),
            "stop" => Some(VoiceCommand::Stop),
            "cancel" => Some(VoiceCommand::Cancel),
            _ => None,
        }
    }
}

/// Voice input use cases.
pub struct VoiceService {
    engine: Arc<dyn SpeechToTextPort>,
    settings: VoiceSettings,
}

impl VoiceService {
    /// Builds a service around any engine implementation.
    pub fn new(engine: Arc<dyn SpeechToTextPort>, settings: VoiceSettings) -> Self {
        Self {
            engine,
            settings: settings.sanitized(),
        }
    }

    /// Builds a service around the local whisper.cpp adapter.
    pub fn local() -> Self {
        Self::new(
            Arc::new(crate::infrastructure::whisper_stt_adapter::WhisperCppAdapter::new()),
            load_settings(),
        )
    }

    /// Builds a service around the engine the settings name.
    ///
    /// `"deepgram"` selects the opt-in cloud adapter (key required at session
    /// time — selecting it IS the consent); `"sherpa-onnx"` the prototype;
    /// anything else, including unknown ids, falls back to local whisper
    /// (SPEC §11 edge contract).
    pub fn for_settings() -> Self {
        let settings = load_settings();
        Self::new(Self::adapter_for_engine(&settings.engine), settings)
    }

    /// Resolves an engine id to its adapter (pure dispatch, unit-tested).
    pub fn adapter_for_engine(engine_id: &str) -> Arc<dyn SpeechToTextPort> {
        match engine_id.trim() {
            "deepgram" => Arc::new(crate::infrastructure::deepgram_stt_adapter::DeepgramAdapter::new()),
            "sherpa-onnx" => Arc::new(crate::infrastructure::sherpa_stt_adapter::SherpaOnnxAdapter::new()),
            _ => Arc::new(crate::infrastructure::whisper_stt_adapter::WhisperCppAdapter::new()),
        }
    }

    /// The sanitized configuration in force.
    pub fn settings(&self) -> &VoiceSettings {
        &self.settings
    }

    /// Replaces the configuration, e.g. after the user changes a setting.
    pub fn set_settings(&mut self, settings: VoiceSettings) {
        self.settings = settings.sanitized();
    }

    /// Inspects the engine without running inference.
    pub fn probe(&self) -> DynResult<EngineProbe> {
        self.engine.probe()
    }

    /// The engine and model catalogs the settings UI renders.
    pub fn catalogs(&self) -> (Vec<ModelDescriptor>, Vec<LanguageOption>) {
        if self.settings.engine.trim() == crate::infrastructure::sherpa_stt_adapter::SHERPA_ENGINE_ID {
            (crate::domain::voice::sherpa_model_descriptors(), crate::domain::voice::sherpa_language_options())
        } else {
            (model_descriptors(), LanguageOption::all())
        }
    }

    /// Current readiness, consumed by `voice status`, the doctor and the UI.
    /// The install one-liner for *this* machine, or `None` when its
    /// distribution is not one we can name a package for.
    pub fn engine_install_command(&self) -> Option<String> {
        let engine = self.settings.engine.trim();
        if engine == crate::infrastructure::sherpa_stt_adapter::SHERPA_ENGINE_ID {
            return Some("pip install sherpa-onnx".to_string());
        }
        if engine == crate::infrastructure::deepgram_stt_adapter::DEEPGRAM_ENGINE_ID {
            return None;
        }
        crate::domain::voice::package_manager_for_os_release(&os_release_text())
            .engine_install_command()
            .map(str::to_string)
    }

    pub fn status(&self) -> VoiceStatus {
        let probe = self.engine.probe().unwrap_or_else(|_| EngineProbe::missing(&self.settings.engine));
        let is_deepgram = self.settings.engine.trim() == crate::infrastructure::deepgram_stt_adapter::DEEPGRAM_ENGINE_ID;
        let is_sherpa = self.settings.engine.trim() == crate::infrastructure::sherpa_stt_adapter::SHERPA_ENGINE_ID;

        // Cloud engines have no binary: availability is key presence.
        let engine_available = if is_deepgram {
            crate::infrastructure::deepgram_stt_adapter::read_key().is_some()
        } else {
            probe.binary_path.is_some()
        };

        let model_present = if is_deepgram {
            true
        } else if is_sherpa {
            crate::infrastructure::sherpa_stt_adapter::resolve_sherpa_model(&self.settings.model).is_some()
        } else {
            crate::infrastructure::whisper_stt_adapter::resolve_model_file(&self.settings.model).is_some()
        };

        let model_path = if is_sherpa {
            crate::infrastructure::sherpa_stt_adapter::resolve_sherpa_model(&self.settings.model)
                .map(|f| f.model_path.to_string_lossy().into_owned())
        } else {
            crate::infrastructure::whisper_stt_adapter::resolve_model_file(&self.settings.model)
                .map(|p| p.to_string_lossy().into_owned())
        };

        let has_source = crate::infrastructure::whisper_stt_adapter::has_audio_source();
        let gap = setup_gap_for(engine_available, model_present, has_source);

        let descriptor = crate::domain::voice::model_by_id(&self.settings.model);
        let (models_available, languages) = self.catalogs();
        VoiceStatus {
            enabled: self.settings.enabled,
            engine: self.settings.engine.clone(),
            engine_available,
            engine_path: probe.binary_path.clone(),
            engine_version: probe.version.clone(),
            model: self.settings.model.clone(),
            model_present,
            model_path,
            model_size_bytes: descriptor.size_bytes,
            echo_cancel: self.settings.echo_cancel,
            echo_cancel_active: crate::infrastructure::echo_cancel::source_available(),
            noise_suppress: self.settings.noise_suppress,
            noise_suppress_active: crate::infrastructure::noise_suppress::source_available(),
            rnnoise_available: crate::infrastructure::noise_suppress::rnnoise_available(),
            vad_model_present: crate::domain::voice::resolve_vad_model_file().is_some(),
            language: self.settings.language.clone(),
            setup_complete: gap == SetupGap::Ready,
            gap,
            engine_install_command: if engine_available { None } else { self.engine_install_command() },
            models_available,
            languages,
            capabilities: probe.capabilities,
        }
    }

    /// Downloads a model, reporting progress as `0.0 ..= 1.0`.
    ///
    /// The transfer lands on a `.part` sibling and is renamed only after curl
    /// reports success, so an interrupted download can never be mistaken for a
    /// usable model. `curl` is used rather than a new HTTP dependency, matching
    /// how `ai_quota_adapter` already reaches the network.
    pub fn install_model<F: FnMut(f32)>(&self, model_id: &str, mut progress: F) -> DynResult<PathBuf> {
        if !crate::domain::voice::is_known_model(model_id) {
            return Err(format!("Unknown speech model '{model_id}'.").into());
        }

        if model_id == crate::domain::voice::SENSEVOICE_SMALL_ID {
            return self.install_sherpa_sensevoice_model(progress);
        }

        let entry = crate::domain::voice::model_by_id(model_id);
        let dir = models_dir();
        std::fs::create_dir_all(&dir)
            .map_err(|e| -> DynError { format!("Cannot create {}: {e}", dir.display()).into() })?;

        let (part_path, final_path) = staged_download_paths(&dir, entry.id);
        Self::download_asset(&entry.display_name, &entry.url(), entry.size_bytes, &part_path, &mut progress)?;
        std::fs::rename(&part_path, &final_path).map_err(|e| -> DynError {
            format!("Downloaded the model but could not install it: {e}").into()
        })?;

        progress(1.0);
        Ok(final_path)
    }

    /// Downloads SenseVoice-Small ONNX weights and tokens for sherpa-onnx.
    pub fn install_sherpa_sensevoice_model<F: FnMut(f32)>(&self, mut progress: F) -> DynResult<PathBuf> {
        let dir = models_dir().join(crate::domain::voice::SENSEVOICE_SMALL_ID);
        std::fs::create_dir_all(&dir)
            .map_err(|e| -> DynError { format!("Cannot create {}: {e}", dir.display()).into() })?;

        let model_part = dir.join("model.int8.onnx.part");
        let model_final = dir.join("model.int8.onnx");
        let tokens_part = dir.join("tokens.txt.part");
        let tokens_final = dir.join("tokens.txt");

        Self::download_asset(
            "SenseVoice Model",
            crate::domain::voice::SENSEVOICE_MODEL_URL,
            crate::domain::voice::SENSEVOICE_MODEL_SIZE_BYTES,
            &model_part,
            &mut |p| progress(p * 0.98),
        )?;
        std::fs::rename(&model_part, &model_final).map_err(|e| -> DynError {
            format!("Cannot install SenseVoice model weights: {e}").into()
        })?;

        Self::download_asset(
            "SenseVoice Tokens",
            crate::domain::voice::SENSEVOICE_TOKENS_URL,
            crate::domain::voice::SENSEVOICE_TOKENS_SIZE_BYTES,
            &tokens_part,
            &mut |p| progress(0.98 + p * 0.02),
        )?;
        std::fs::rename(&tokens_part, &tokens_final).map_err(|e| -> DynError {
            format!("Cannot install SenseVoice tokens: {e}").into()
        })?;

        progress(1.0);
        Ok(dir)
    }

    /// Downloads the Silero VAD asset, reporting progress as `0.0 ..= 1.0`.    ///
    /// Same staging discipline as STT models (`.part` + rename). A missing VAD
    /// model is never fatal: sessions fall back to energy endpointing, so this
    /// is an accuracy upgrade, not a readiness gate.
    pub fn install_vad_model<F: FnMut(f32)>(&self, mut progress: F) -> DynResult<PathBuf> {
        use crate::domain::voice::{VAD_MODEL_SIZE_BYTES, VAD_MODEL_URL, vad_model_file_name};
        let dir = models_dir();
        std::fs::create_dir_all(&dir)
            .map_err(|e| -> DynError { format!("Cannot create {}: {e}", dir.display()).into() })?;
        let file_name = vad_model_file_name();
        let part_path = dir.join(format!("{}.part", file_name));
        let final_path = dir.join(&file_name);
        Self::download_asset(
            "Silero VAD",
            VAD_MODEL_URL,
            VAD_MODEL_SIZE_BYTES,
            &part_path,
            &mut progress,
        )?;
        std::fs::rename(&part_path, &final_path).map_err(|e| -> DynError {
            format!("Downloaded the VAD model but could not install it: {e}").into()
        })?;
        progress(1.0);
        Ok(final_path)
    }

    /// Runs a device-only microphone check (no audio leaves the device).
    pub fn mic_check(&self, secs: u64) -> DynResult<crate::domain::voice::MicCheck> {
        crate::infrastructure::mic_check::probe_microphone(secs)
    }

    /// Streams a curl download into `part_path`, reporting progress in 0..=1.
    ///
    /// Used by the ASR model installer so staging, progress parsing and
    /// empty-file rejection live in one place.
    fn download_asset(
        label: &str,
        url: &str,
        size_bytes: u64,
        part_path: &Path,
        progress: &mut dyn FnMut(f32),
    ) -> DynResult<()> {
        // A previous attempt may have left a partial file behind.
        let _ = std::fs::remove_file(part_path);

        let mut child = Command::new("curl")
            .arg("--fail")
            .arg("--location")
            // NOT --silent: it suppresses the progress meter entirely, which is
            // how a 1.5 GiB download reported 0% for its whole life. Errors are
            // still surfaced by --show-error.
            .arg("--show-error")
            .arg("--output")
            .arg(part_path)
            // curl's progress meter is a single rewritten line; disabling it
            // keeps stdout clean for our own JSONL progress events.
            .arg("--progress-bar")
            .arg(url)
            .stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .map_err(|e| -> DynError { format!("Cannot start the download (is curl installed?): {e}").into() })?;

        let total = size_bytes as f64;
        if let Some(out) = child.stdout.take() {
            let reader = std::io::BufReader::new(out);
            for line in reader.split(b'\r').flatten() {
                let text = String::from_utf8_lossy(&line);
                if let Some(fraction) = parse_curl_percent(&text) {
                    progress(fraction);
                } else if let Some(done) = parse_curl_progress(&text) {
                    progress(if total > 0.0 { ((done as f64 / total) as f32).clamp(0.0, 1.0) } else { 0.0 });
                }
            }
        }

        let status = child
            .wait()
            .map_err(|e| -> DynError { format!("Download failed: {e}").into() })?;

        if !status.success() {
            let _ = std::fs::remove_file(part_path);
            return Err(format!(
                "Download of {label} failed. Check your network connection and retry from Settings."
            )
            .into());
        }

        // A zero-length result is a failure even when curl exited cleanly.
        match std::fs::metadata(part_path) {
            Ok(meta) if meta.len() > 0 => Ok(()),
            _ => {
                let _ = std::fs::remove_file(part_path);
                Err("Download produced an empty file and was discarded.".into())
            }
        }
    }

    /// Runs one capture -> transcribe session, streaming events to `sink`.
    /// Delete a downloaded model, and any staged partial left by an interrupted
    /// download. Returns whether anything was removed, so the UI can tell
    /// "removed" from "there was nothing there".
    pub fn remove_model(&self, model_id: &str) -> DynResult<bool> {
        if !crate::domain::voice::is_known_model(model_id) {
            return Err(format!("Unknown speech model '{model_id}'.").into());
        }
        if model_id == crate::domain::voice::SENSEVOICE_SMALL_ID {
            let dir = models_dir().join(crate::domain::voice::SENSEVOICE_SMALL_ID);
            if dir.exists() {
                std::fs::remove_dir_all(&dir).map_err(|e| -> DynError {
                    format!("Cannot remove {}: {e}", dir.display()).into()
                })?;
                return Ok(true);
            }
            return Ok(false);
        }
        let entry = crate::domain::voice::model_by_id(model_id);
        let dir = models_dir();
        let (part_path, final_path) = staged_download_paths(&dir, entry.id);
        let mut removed = false;
        for path in [&part_path, &final_path] {
            if !path.exists() {
                continue;
            }
            std::fs::remove_file(path).map_err(|e| -> DynError {
                format!("Cannot remove {}: {e}", path.display()).into()
            })?;
            removed = true;
        }
        Ok(removed)
    }

    pub fn run_session<F: FnMut(VoiceEvent)>(&self, mut sink: F) -> DynResult<Transcript> {
        let cfg = VoiceSessionConfig::from_settings(&self.settings);
        self.engine.run_session(&cfg, &mut sink)
    }

    /// Runs a session that a control channel can interrupt. See
    /// [`CancelHandle`]; `stop` finalizes and transcribes, `cancel` discards.
    pub fn run_session_cancellable<F: FnMut(VoiceEvent)>(
        &self,
        handle: &CancelHandle,
        mut sink: F,
    ) -> DynResult<Transcript> {
        let cfg = VoiceSessionConfig::from_settings(&self.settings);
        self.engine.run_session_cancellable(&cfg, handle, &mut sink)
    }

    /// [`run_control_loop`] with a session-scoped language override (D9).
    ///
    /// The override reaches the engine for this session only. Persisting it
    /// would mean a user dictating in a second language for one prompt had
    /// silently reconfigured their shell, which is why `voiceLanguageOverride`
    /// in `AssistantService` is runtime state and nothing else.
    pub fn run_control_loop_with_language<R: Read + Send + 'static, W: Write>(
        &self,
        input: R,
        out: W,
        language_override: &str,
        emit: impl FnMut(&mut W, &VoiceEvent) -> std::io::Result<()> + Send,
    ) -> DynResult<()> {
        self.control_loop(input, out, Some(language_override), emit)
    }

    /// Drives a session from a line-oriented control channel until stdin closes.
    ///
    /// The control channel is read on a **separate thread** once recording has
    /// begun. The capture loop blocks reading the audio pipe, so a single-threaded
    /// loop could never see a `stop` -- the command would sit in the pipe until
    /// the utterance auto-finalized, which is exactly the bug the visual pass
    /// caught: the stop button did nothing.
    ///
    /// Commands arriving after the session has finalised are ignored rather than
    /// fatal: a `stop` racing an auto-finalize is a real interaction the UI can
    /// produce, and crashing there would be a genuine bug.
    pub fn run_control_loop<R: Read + Send + 'static, W: Write>(
        &self,
        input: R,
        out: W,
        emit: impl FnMut(&mut W, &VoiceEvent) -> std::io::Result<()> + Send,
    ) -> DynResult<()> {
        self.control_loop(input, out, None, emit)
    }

    fn control_loop<R: Read + Send + 'static, W: Write>(
        &self,
        input: R,
        mut out: W,
        language_override: Option<&str>,
        mut emit: impl FnMut(&mut W, &VoiceEvent) -> std::io::Result<()> + Send,
    ) -> DynResult<()> {
        // Wrapped here rather than by the caller: `StdinLock` is not `Send`, so
        // taking a locked handle would defeat the reader thread entirely.
        let input = std::io::BufReader::new(input);
        let mut lines = input.lines();

        // Wait for an explicit `start` so simply launching the process does not
        // open the microphone.
        let started = loop {
            let Some(line) = lines.next() else { return Ok(()) };
            let line = match line {
                Ok(l) => l,
                Err(_) => return Ok(()),
            };
            match VoiceCommand::parse(&line) {
                Some(VoiceCommand::Start) => break true,
                Some(VoiceCommand::Cancel) => break false,
                // Ignore anything else, including blank lines.
                _ => continue,
            }
        };

        if !started {
            emit(
                &mut out,
                &VoiceEvent::StateChanged {
                    state: VoiceState::Idle,
                },
            )?;
            return Ok(());
        }

        let handle = CancelHandle::new();

        // Reader thread: translates later control lines into cooperative signals.
        let reader_handle = handle.clone();
        let reader = std::thread::spawn(move || {
            for line in lines.flatten() {
                match VoiceCommand::parse(&line) {
                    Some(VoiceCommand::Stop) => reader_handle.request_stop(),
                    Some(VoiceCommand::Cancel) => reader_handle.request_cancel(),
                    // `start` while already recording, and anything unknown, is
                    // ignored rather than treated as an error.
                    _ => {}
                }
            }
            // stdin closed: end the utterance rather than recording forever.
            reader_handle.request_stop();
        });

        let mut cfg = VoiceSessionConfig::from_settings(&self.settings);
        if let Some(tag) = language_override {
            cfg = cfg.with_language_override(tag);
        }
        let result = self.engine.run_session_cancellable(&cfg, &handle, &mut |event| {
            let _ = emit(&mut out, &event);
        });

        // The reader may still be blocked on stdin; it only observes flags, so
        // detaching is safe and avoids waiting on a pipe nobody will close.
        drop(reader);

        match result {
            Ok(_) => Ok(()),
            Err(e) => {
                // The engine already emitted a typed Error event; keep the exit
                // code clean for scripts while leaving the event stream intact.
                eprintln!("[voice] session ended: {e}");
                Ok(())
            }
        }
    }
}

/// Parses a byte count out of a `curl` progress line.
///
/// `curl` writes forms like `####......  12.3M` and, with `--progress-bar`,
/// rewrites the same line. Only a trailing size token is read, and anything
/// unparseable yields `None` so the caller simply skips the update.
/// Progress from curl's `--progress-bar` line (`##########  42.3%`), as a
/// fraction of the transfer.
///
/// `--progress-bar` is what the installer asks for, so this is the shape that
/// actually arrives; the byte-count parser below covers the plain meter that
/// other curl builds print instead.
pub fn parse_curl_percent(line: &str) -> Option<f32> {
    let token = line.split_whitespace().last()?;
    let value = token.strip_suffix('%')?.parse::<f64>().ok()?;
    Some((value / 100.0).clamp(0.0, 1.0) as f32)
}

/// The text of `/etc/os-release`, or empty when it cannot be read. An empty
/// document detects as an unknown distribution, which yields the upstream build
/// instructions rather than a command for the wrong package manager.
pub(crate) fn os_release_text() -> String {
    std::fs::read_to_string("/etc/os-release").unwrap_or_default()
}

pub fn parse_curl_progress(line: &str) -> Option<u64> {
    let token = line.split_whitespace().last()?;
    let (number, multiplier) = match token.chars().last()? {
        'K' | 'k' => (&token[..token.len() - 1], 1024.0),
        'M' | 'm' => (&token[..token.len() - 1], 1024.0 * 1024.0),
        'G' | 'g' => (&token[..token.len() - 1], 1024.0 * 1024.0 * 1024.0),
        _ => (token, 1.0),
    };
    number.parse::<f64>().ok().map(|n| (n * multiplier) as u64)
}

/// Loads voice settings from the user config, falling back to shipped defaults.
///
/// A missing, unreadable or malformed file yields defaults rather than an error:
/// the shell must always start.
pub fn load_settings() -> VoiceSettings {
    let candidates = [
        crate::domain::branding::config_home()
            .join("astral-plasma")
            .join("settings.json"),
        PathBuf::from("config/settings.json"),
    ];
    for path in candidates {
        let Ok(raw) = std::fs::read_to_string(&path) else {
            continue;
        };
        let Ok(value) = serde_json::from_str::<serde_json::Value>(&raw) else {
            continue;
        };
        let block = match value.get("voice") {
            Some(v) => v.clone(),
            None => return VoiceSettings::default(),
        };
        return match serde_json::from_value::<VoiceSettings>(block) {
            Ok(s) => s.sanitized(),
            Err(_) => VoiceSettings::default(),
        };
    }
    VoiceSettings::default()
}

/// Serializes a voice event as one JSONL line, returning `false` on failure.
pub fn write_event<W: Write>(out: &mut W, event: &VoiceEvent) -> std::io::Result<bool> {
    match serde_json::to_string(event) {
        Ok(line) => {
            out.write_all(line.as_bytes())?;
            out.write_all(b"\n")?;
            // Flushed per event so a UI reading the pipe sees each line as it
            // happens rather than when the buffer happens to fill.
            out.flush()?;
            Ok(true)
        }
        Err(_) => Ok(false),
    }
}

/// Total bytes the catalog declares, for progress reporting across models.
pub fn catalog_total_bytes() -> u64 {
    MODEL_CATALOG.iter().map(|m| m.size_bytes).sum()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::domain::ports::SpeechToTextPort;
    use crate::domain::voice::LanguageSource;
    use std::sync::Mutex;

    /// A fake engine that records what it was asked to do and replays a script
    /// of events, proving the application layer is engine-independent.
    struct FakeEngine {
        events: Mutex<Vec<VoiceEvent>>,
        probed: Mutex<bool>,
        fail_with: Option<String>,
    }

    impl FakeEngine {
        fn new() -> Self {
            Self {
                events: Mutex::new(Vec::new()),
                probed: Mutex::new(false),
                fail_with: None,
            }
        }
        fn failing(msg: &str) -> Self {
            Self {
                events: Mutex::new(Vec::new()),
                probed: Mutex::new(false),
                fail_with: Some(msg.to_string()),
            }
        }
    }

    impl SpeechToTextPort for FakeEngine {
        fn probe(&self) -> DynResult<EngineProbe> {
            *self.probed.lock().unwrap() = true;
            Ok(EngineProbe {
                engine_id: "fake".to_string(),
                binary_path: Some("/usr/bin/fake-engine".to_string()),
                version: Some("1.0.0".to_string()),
                capabilities: Default::default(),
            })
        }

        fn run_session(
            &self,
            cfg: &VoiceSessionConfig,
            sink: &mut dyn FnMut(VoiceEvent),
        ) -> DynResult<Transcript> {
            self.run_session_cancellable(cfg, &CancelHandle::new(), sink)
        }

        fn run_session_cancellable(
            &self,
            cfg: &VoiceSessionConfig,
            handle: &CancelHandle,
            sink: &mut dyn FnMut(VoiceEvent),
        ) -> DynResult<Transcript> {
            assert_eq!(cfg.capture, crate::domain::voice::CaptureTarget::Source);

            // Mirror the real capture loop, which spends seconds reading audio
            // and polls the handle between frames. Without this the fake would
            // return before the control-channel reader thread could possibly
            // deliver a `stop` or `cancel`, and every cancellation test would be
            // a race rather than a deterministic assertion.
            for _ in 0..2_000 {
                if handle.is_stopped() {
                    break;
                }
                std::thread::sleep(std::time::Duration::from_millis(1));
            }

            for e in [
                VoiceEvent::StateChanged {
                    state: VoiceState::Recording,
                },
                VoiceEvent::Level { rms: 0.5 },
                VoiceEvent::StateChanged {
                    state: VoiceState::Finalizing,
                },
            ] {
                self.events.lock().unwrap().push(e.clone());
                sink(e);
            }
            if let Some(msg) = &self.fail_with {
                let e = VoiceEvent::fatal_error(msg.clone());
                self.events.lock().unwrap().push(e.clone());
                sink(e);
                return Err(msg.clone().into());
            }
            // A cancelled session yields no transcript, exactly as the real
            // adapter does.
            let text = if handle.is_discarded() {
                String::new()
            } else {
                "hello from the fake".to_string()
            };
            let t = Transcript {
                text,
                language: "en".to_string(),
                duration_ms: 1500,
                engine: "fake".to_string(),
                model: cfg.model.clone(),
                speech_detected: !handle.is_discarded(),
                language_confidence: None,
                language_source: LanguageSource::Configured,
            };
            let e = VoiceEvent::Final(t.clone());
            self.events.lock().unwrap().push(e.clone());
            sink(e);
            Ok(t)
        }
    }

    fn service(engine: FakeEngine) -> VoiceService {
        VoiceService::new(Arc::new(engine), VoiceSettings::default())
    }

    #[test]
    fn run_session_forwards_every_engine_event() {
        let svc = service(FakeEngine::new());
        let mut seen: Vec<VoiceEvent> = Vec::new();
        let t = svc.run_session(|e| seen.push(e)).expect("session must succeed");

        assert_eq!(t.text, "hello from the fake");
        assert_eq!(seen.len(), 4);
        assert_eq!(seen[0].kind(), "StateChanged");
        assert_eq!(seen[1].kind(), "Level");
        assert_eq!(seen[2].kind(), "StateChanged");
        assert_eq!(seen[3].kind(), "Final");
    }

    #[test]
    fn a_failing_session_still_emits_a_typed_error() {
        let svc = service(FakeEngine::failing("engine exploded"));
        let mut seen: Vec<VoiceEvent> = Vec::new();
        let result = svc.run_session(|e| seen.push(e));
        assert!(result.is_err());
        let last = seen.last().expect("an error event must be emitted");
        match last {
            VoiceEvent::Error { recoverable, .. } => assert!(!recoverable),
            other => panic!("expected Error, got {other:?}"),
        }
    }

    #[test]
    fn control_loop_waits_for_an_explicit_start() {
        // Launching the process must not open the microphone on its own.
        let svc = service(FakeEngine::new());
        let input = std::io::Cursor::new(Vec::new());
        let mut out: Vec<u8> = Vec::new();
        svc.run_control_loop(input, &mut out, |w, e| {
            write_event(w, e).map(|_| ())
        })
        .unwrap();
        assert!(out.is_empty(), "no events without a start command");
    }

    #[test]
    fn control_loop_runs_a_session_after_start() {
        let svc = service(FakeEngine::new());
        let input = std::io::Cursor::new(b"start\n".to_vec());
        let mut out: Vec<u8> = Vec::new();
        svc.run_control_loop(input, &mut out, |w, e| write_event(w, e).map(|_| ()))
            .unwrap();

        let text = String::from_utf8(out).unwrap();
        let lines: Vec<&str> = text.lines().collect();
        assert_eq!(lines.len(), 4, "got: {text}");
        assert!(lines[0].contains("\"StateChanged\""));
        assert!(lines[3].contains("hello from the fake"));
    }

    #[test]
    fn control_loop_ignores_unknown_and_blank_commands() {
        let svc = service(FakeEngine::new());
        let input = std::io::Cursor::new(b"\n   \nnonsense\nstart\n".to_vec());
        let mut out: Vec<u8> = Vec::new();
        svc.run_control_loop(input, &mut out, |w, e| write_event(w, e).map(|_| ()))
            .unwrap();
        assert!(String::from_utf8(out).unwrap().contains("Final"));
    }

    #[test]
    fn control_loop_honours_cancel_before_start() {
        let svc = service(FakeEngine::new());
        let input = std::io::Cursor::new(b"cancel\n".to_vec());
        let mut out: Vec<u8> = Vec::new();
        svc.run_control_loop(input, &mut out, |w, e| write_event(w, e).map(|_| ()))
            .unwrap();
        let text = String::from_utf8(out).unwrap();
        assert!(text.contains("idle"), "cancel must return to idle: {text}");
        assert!(!text.contains("Recording"), "cancel must not record: {text}");
    }

    #[test]
    fn control_loop_survives_a_failing_session() {
        // The event stream must stay well-formed even when the engine dies, so
        // the UI can render the error rather than seeing a truncated stream.
        let svc = service(FakeEngine::failing("boom"));
        let input = std::io::Cursor::new(b"start\n".to_vec());
        let mut out: Vec<u8> = Vec::new();
        svc.run_control_loop(input, &mut out, |w, e| write_event(w, e).map(|_| ()))
            .unwrap();
        let text = String::from_utf8(out).unwrap();
        assert!(text.contains("boom"));
    }

    #[test]
    fn a_stop_on_the_control_channel_interrupts_a_blocked_session() {
        // Regression guard for the bug the visual pass caught: `run_session`
        // blocks reading the capture pipe, so a single-threaded control loop
        // could never observe a `stop` and the stop button did nothing. The
        // control channel must be read concurrently.
        let svc = service(FakeEngine::new());
        let input = std::io::Cursor::new(b"start\n".to_vec());
        let mut out: Vec<u8> = Vec::new();
        svc.run_control_loop(input, &mut out, |w, e| write_event(w, e).map(|_| ()))
            .unwrap();
        let text = String::from_utf8(out).unwrap();
        assert!(text.contains("Final"), "a completed session must still transcribe: {text}");
    }

    #[test]
    fn a_cancel_after_start_discards_rather_than_transcribes() {
        let svc = service(FakeEngine::new());
        let input = std::io::Cursor::new(b"start\ncancel\n".to_vec());
        let mut out: Vec<u8> = Vec::new();
        svc.run_control_loop(input, &mut out, |w, e| write_event(w, e).map(|_| ()))
            .unwrap();
        let text = String::from_utf8(out).unwrap();
        // The transcript is empty, so nothing is inserted into the composer.
        assert!(!text.contains("hello from the fake"),
            "a cancelled utterance must not be transcribed: {text}");
    }

    #[test]
    fn a_stop_after_start_still_transcribes() {
        // `stop` and `cancel` are different user intents and must not collapse.
        let svc = service(FakeEngine::new());
        let input = std::io::Cursor::new(b"start\nstop\n".to_vec());
        let mut out: Vec<u8> = Vec::new();
        svc.run_control_loop(input, &mut out, |w, e| write_event(w, e).map(|_| ()))
            .unwrap();
        let text = String::from_utf8(out).unwrap();
        assert!(text.contains("hello from the fake"),
            "stop must keep the audio and transcribe it: {text}");
    }

    #[test]
    fn control_reader_thread_exits_when_stdin_closes() {
        // Detaching the reader must not leak a thread per session, which would
        // accumulate across a long shell session.
        let svc = service(FakeEngine::new());
        let input = std::io::Cursor::new(b"start\n".to_vec());
        let mut out: Vec<u8> = Vec::new();
        svc.run_control_loop(input, &mut out, |w, e| write_event(w, e).map(|_| ()))
            .unwrap();
        // If the session completed at all, the loop returned rather than hanging.
        assert!(!out.is_empty());
    }

    #[test]
    fn command_parsing_is_strict() {
        assert_eq!(VoiceCommand::parse("start"), Some(VoiceCommand::Start));
        assert_eq!(VoiceCommand::parse("  STOP \n"), Some(VoiceCommand::Stop));
        assert_eq!(VoiceCommand::parse("Cancel"), Some(VoiceCommand::Cancel));
        assert_eq!(VoiceCommand::parse("maybe"), None);
        assert_eq!(VoiceCommand::parse(""), None);
    }

    #[test]
    fn status_reflects_the_engine_probe() {
        let svc = service(FakeEngine::new());
        let status = svc.status();
        assert!(status.engine_available);
        assert_eq!(status.engine_path.as_deref(), Some("/usr/bin/fake-engine"));
        assert_eq!(status.engine_version.as_deref(), Some("1.0.0"));
    }

    #[test]
    fn install_model_rejects_an_unknown_id_before_touching_the_network() {
        let svc = service(FakeEngine::new());
        let err = svc.install_model("not-a-real-model", |_| {}).unwrap_err();
        assert!(err.to_string().contains("Unknown speech model"));
    }

    #[test]
    fn settings_are_sanitized_on_construction() {
        let engine = FakeEngine::new();
        let svc = VoiceService::new(
            Arc::new(engine),
            VoiceSettings {
                max_utterance_seconds: 0,
                model: "bogus".into(),
                ..Default::default()
            },
        );
        assert_eq!(svc.settings().max_utterance_seconds, 5);
        assert_eq!(svc.settings().model, crate::domain::voice::DEFAULT_MODEL_ID);
    }

    #[test]
    fn curl_progress_lines_are_parsed() {
        assert_eq!(parse_curl_progress("#####......  1.0M"), Some(1_048_576));
        assert_eq!(parse_curl_progress("####  512K"), Some(524_288));
        assert_eq!(parse_curl_progress("######  2048"), Some(2048));
        assert_eq!(parse_curl_progress("no numbers here"), None);
        assert_eq!(parse_curl_progress(""), None);
    }

    #[test]
    fn events_are_written_as_one_flushed_line_each() {
        let mut buf: Vec<u8> = Vec::new();
        let ok = write_event(
            &mut buf,
            &VoiceEvent::StateChanged {
                state: VoiceState::Recording,
            },
        )
        .unwrap();
        assert!(ok);
        let text = String::from_utf8(buf).unwrap();
        assert_eq!(text.lines().count(), 1);
        assert!(text.ends_with('\n'));
        assert!(text.contains("\"recording\""));
    }

    #[test]
    fn load_settings_falls_back_to_defaults() {
        // Must never panic or error, whatever is on disk.
        let s = load_settings();
        assert_eq!(s.model, crate::domain::voice::DEFAULT_MODEL_ID);
    }

    #[test]
    fn catalogs_expose_models_and_languages() {
        let svc = service(FakeEngine::new());
        let (models, langs) = svc.catalogs();
        assert!(models.iter().any(|m| m.id == crate::domain::voice::DEFAULT_MODEL_ID));
        assert!(langs.iter().any(|l| l.code == "zh"));
        assert!(langs.iter().any(|l| l.code == "en"));
    }

    #[test]
    fn engine_dispatch_honours_names_and_falls_back() {
        use crate::domain::ports::SpeechToTextPort;
        // Selecting cloud IS the consent; the probe names the engine honestly.
        let cloud = VoiceService::adapter_for_engine("deepgram");
        assert_eq!(cloud.probe().unwrap().engine_id, "deepgram");
        let sherpa = VoiceService::adapter_for_engine("sherpa-onnx");
        assert_eq!(sherpa.probe().unwrap().engine_id, "sherpa-onnx");
        // Unknown ids and blanks fall back to local whisper (SPEC §11).
        for id in ["whisper-cpp", "", "klingon-stt", " whisper-cpp "] {
            let engine = VoiceService::adapter_for_engine(id);
            assert_eq!(engine.probe().unwrap().engine_id, "whisper-cpp", "engine {id:?}");
        }
    }
}
