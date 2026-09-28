# Voice Input Specification

> **Status:** Implemented
> **Scope:** Multilingual voice dictation for the Astral Copilot chat composer.
> **Authority:** This document, together with [`DESIGN.md`](../DESIGN.md), [`docs/LESSONS.md`](LESSONS.md) and [`AGENTS.md`](../AGENTS.md), is the authoritative source for the voice feature. Read it before modifying anything under `assistant/`, `services/AssistantService.qml`, or the voice modules in `daemon/`.

---

## 1. Problem & Goals

The Astral Copilot composer is the shell's only general-purpose reasoning surface. It is currently keyboard-only, which is slow for long prompts and hostile to users who dictate. This feature adds voice input covering the major world languages, with Mandarin Chinese as a first-class case.

**Goals**

1. Dictate a prompt into the chat composer in Chinese, English, French, German, Italian, Spanish and further whisper-supported locales.
2. Transcribe **locally** by default: audio never leaves the machine, there is no API key, and there is no per-word cost.
3. Degrade **honestly and visibly** when the engine or model is absent — never fake a ready state.
4. Never send a transcript without explicit user review.
5. Respect the shell's DDD boundaries and its existing process/JSONL transport.
6. Cost nothing when unused: no resident process, no held capture device, no background polling.

**Non-goals (v1)**

- System-wide dictation. Requires synthetic input injection, which `HYPRLAND-OMARCHY-SPEC.md:495` forbids as a requirement.
- Wake word / always-on listening.
- Cloud speech-to-text. The port is designed for it; no adapter ships.
- Global push-to-talk hotkey. A `voice.toggle` IPC action is registered so the door stays open, but no key is bound.

---

## 2. Architectural Decision Record

Each decision below was taken deliberately. The *reason* is recorded because it is the thing a future maintainer needs in order not to undo it by accident.

### D1 — A pluggable port, local engine in v1

`SpeechToTextPort` is a domain trait. `WhisperCppAdapter` is the only v1 adapter.

**Why a port and not a hardcoded engine:** whisper's Mandarin is its weakest major language. `large-v3-turbo` is usable but not excellent. DashScope `paraformer-realtime-v2` / Qwen-ASR is materially better at Chinese. The port exists so that adapter can be added later **without touching the UI, the capture loop, the provisioning flow, or the doctor check**. This is the single most important structural decision in the feature.

**Why not also ship a cloud adapter in v1:** it would require a new HTTP client dependency (the daemon has none — all current network access is `Command::new("curl")` at `ai_quota_adapter.rs:1159`), an API-key settings surface, and a privacy consent flow. That is a second feature, not a second adapter.

### D2 — The port owns a whole capture→transcribe session

One trait method, `run_session`, owns capture, endpointing and inference. It is deliberately **not** split into `AudioCapturePort` + `VoiceActivityPort` + `SpeechToTextPort`.

**Why:** endpointing is entangled with the engine and the capture buffer — you cannot know whether a pause is the end of an utterance until you know how the engine segments. Splitting the trait would force the composing application service to learn engine-specific segmentation semantics, which leaks the abstraction *and* costs three traits plus two fakes to maintain. The engine's quirks stay inside one adapter file instead.

The pieces that are genuinely engine-independent — `CaptureTarget`, WAV container construction, silence detection, language normalisation, event encoding — are **pure domain functions in `domain/voice.rs`**, with no I/O and no engine knowledge. They are where the unit tests live.

### D3 — A one-shot session process, not a resident daemon or a bus name

Transport is `astral-plasma voice session`: stdin carries control lines, stdout carries a JSONL event stream, and the process exits when the utterance finalises.

**Why not a D-Bus interface on the existing `org.astralplasma.WindowWatcher`:** the daemon is resident for the whole shell session. A resident voice service must either hold the capture device open continuously — lighting the hardware mic indicator and locking other applications out of the device — or gate start/stop anyway, at which point the one-shot process already does the job with strictly less machinery. The existing bus name also costs a `retry_async(120, 250ms)` guard plus a 3-second health monitor (`watch_events.rs:775-800`); a second long-lived name is a second thing to babysit.

**Why this matters for testability:** because the session is a plain child process with a line protocol, the entire transport, event contract and process lifecycle are testable by driving the binary from an integration test with a **stub engine**. See §8.

### D4 — Manual stop always wins; auto-finalize is a convenience

The stop button and `Enter` work at all times. Auto-finalize is governed by an adaptive silence detector, not a fixed threshold.

**Why:** a user must be able to cut off mid-sentence.

**Endpointing vs filtering, recorded honestly:** the original design expected whisper.cpp's Silero VAD to decide "the user stopped talking". That is still not what `--vad` does: it is an *inference-time filter over a completed file*, so live endpointing remains the daemon's **noise-floor-adaptive** `SilenceDetector` (a pure function, unit-tested against synthetic speech/noise, degradable to manual-only via `voice.autoFinalize: false`).

The VAD *asset* was reported missing at authoring time because it was fetched from the wrong repository: `ggml-org/whisper.cpp` is not a public Hugging Face repo, and Hugging Face answers **HTTP 401** (not 404) for paths an anonymous client may not see — which read as "unreachable / needs credentials". Upstream's own `models/download-vad-model.sh` downloads from `https://huggingface.co/ggml-org/whisper-vad`, which is public, credential-free, and 885 KiB. The daemon now provisions it (`voice install-vad`, and alongside every `install-model`) and passes `--vad --vad-model` whenever the asset is present — still never a bare `--vad`, which fails the whole transcription. Filtering non-speech before decoding is what keeps music and room noise from becoming hallucinated text.

### D4a — The hard cap is enforced by a watchdog, not by the frame loop

The utterance cap is enforced by a dedicated watchdog thread that signals the capture process, rather than being checked inside the audio frame loop.

**Why:** the frame loop blocks reading the capture pipe, so a cap checked *there* only fires when audio happens to arrive. A capture stream that stalls — a muted or held-open device delivering no frames — would block in `read` indefinitely and hold the microphone open forever. This was observed live during visual verification: a session still reported "recording" after **sixteen minutes**.

The watchdog therefore has to *act*, not merely observe. An intermediate version of this code returned early when a stop was requested, which silently defeated the mechanism: the flag was set, the watchdog exited without signalling, and the microphone stayed open. The watchdog is now the single owner of "actually terminate the capture", triggered by either an explicit stop/cancel or the cap.

**Reaping order is load-bearing.** The child is deliberately *not* reaped until after the watchdog is joined. Reaping first frees the pid while the watchdog could still be signalling it, and a detached watchdog would outlive the session entirely and eventually signal a pid the kernel has reassigned to an unrelated process.

### D4b — A closed control channel ends the session

stdin reaching EOF means the client has gone away, so the session stops and releases the microphone. This is correct, and it has a test-visible consequence: a client must hold the control pipe open for the life of a session, exactly as the real UI does.

### D4c — The UI must actually send `start`

The daemon waits for an explicit `start` line before opening the microphone, so spawning the process is not enough. The composer sends it from a `running`-change handler, once the pipe exists, guarded by a `voiceAwaitingStart` handshake so it is sent exactly once per session.

**Why this is recorded:** the first implementation set `running = true` and stopped there. The composer dutifully displayed "recording" with a running timer, while the daemon sat blocked on stdin and the microphone was never opened. Only a live screenshot surfaced it — no unit test could, because every layer was individually consistent. See §13.


### D5 — Never auto-send

The transcript is inserted into the composer. The user presses `Enter`.

**Why:** `ToolCallProposal::assess_safety` (`domain/assistant.rs:117`) only *proposes* `sudo` / `rm -rf` / `systemctl` / `pkill` for confirmation — the user has to catch it. A speech-recognition error must never be able to reach a tool-execution gate unattended. This is a safety property, not a UX preference, and it is enforced by a test (§8.6).

### D6 — Partials are never fabricated

`AGENTS.md` §4 forbids synthesising content. The `whisper-cli` binary produces no streaming partials — it emits a transcript when the file is done.

Therefore, in v1 the listening strip shows **real measured audio level** (RMS computed from the actual PCM the microphone delivered) and a real elapsed timer, and the text appears on finalisation. `VoiceEvent::Partial` exists and is rendered by the strip, but is only emitted by an adapter that genuinely streams. **No adapter fabricates a partial transcript.** A strip showing level-only is correct behaviour, not a degraded mode.

### D7 — Detect-then-offer provisioning

The engine and model are never downloaded silently. `check_voice_engine()` reports status; the settings panel offers explicit, user-initiated install with progress. Files land in `~/.cache/astral-plasma/models/`.

**Why:** silently pulling 1.5 GiB, or shelling out to a package manager unprompted, is hostile. But requiring manual setup means the feature is simply broken on first run with no route forward.

### D8 — The detected language is displayed

Auto-detection is the default, and the strip shows what was detected. This is not decoration: on a 2–5 second clip auto-detection is genuinely unreliable, and without a visible reading a wrong guess is indistinguishable from a recognition bug. Showing it turns a mystery into a one-glance override.

### D9 — Session-scoped language overrides are never persisted

`voice.language` in `settings.json` is the **default**. A per-session override lives only in `AssistantService` runtime state. Persisting it would mean a user dictating Mandarin in one session silently reconfigures their shell.

### D10 — Voice is never a required dependency

`check_voice_engine()` sets `required: false`, so `DoctorReport::all_required_satisfied` is unaffected. A shell without voice installed is a healthy shell.

---

## 3. Model Catalog

Served from `https://huggingface.co/ggerganov/whisper.cpp/resolve/main/`. Sizes verified by HTTP `HEAD` on 2026-09-27. The catalog is data, declared in `domain::voice::MODEL_CATALOG`, and the UI renders whatever it contains — adding a model is a data change, not a code change.

| Model id | Bytes | ~Size | Role |
|---|---:|---:|---|
| `ggml-tiny` | 77,691,713 | 74 MiB | Smoke tests / very low resource |
| `ggml-base` | 147,951,465 | 141 MiB | Low-resource tier |
| **`ggml-small`** | **487,601,967** | **465 MiB** | **Default.** Balanced; near-realtime on CPU |
| `ggml-large-v3-turbo-q5_0` | 574,041,195 | 547 MiB | Best size/quality ratio |
| `ggml-medium` | 1,533,763,059 | 1463 MiB | — |
| `ggml-large-v3-turbo` | 1,624,555,275 | 1549 MiB | Best multilingual quality, CPU-heavy |
| `ggml-large-v3` | 3,095,033,483 | 2951 MiB | Marginal quality gain, 2× the disk |

**Default: `ggml-small`.** The engine ships CPU-only on every distribution we support, so the default has to be usable without a GPU. Measured on a 12th-gen i9 (16 cores / 24 threads, `whisper-cli` 1.9.4): `ggml-large-v3-turbo` needed 26.0s to transcribe a 4.9s clip and 12.2s for the 11s JFK sample, while `ggml-small` took 4.0s and 3.0s respectively — with an identical JFK transcript. An interactive dictation feature cannot default to a tier roughly 5× slower than realtime; the large tiers remain one download away in the picker, and a user who chose one is never overridden.

**Known limitation:** whisper's Mandarin accuracy is materially below dedicated Chinese ASR. This is the accepted cost of D1's local-only v1. If Chinese quality proves insufficient, the remedy is a `CloudSttAdapter` behind the same port — not a rewrite.

---

## 4. Domain Model — `daemon/src/domain/voice.rs`

Pure. No I/O, no engine knowledge, no async. Every item here is unit-tested.

### 4.1 `CaptureTarget`

The value object that generalises the audio visualizer's hardcoded capture.

```rust
pub enum CaptureTarget { Sink, Source }
```

| Variant | `--target` | `-P` properties |
|---|---|---|
| `Sink` | `@DEFAULT_AUDIO_SINK@` | `{"stream.capture.sink": true}` |
| `Source` | `@DEFAULT_AUDIO_SOURCE@` | *omitted* (pw-record's default is source capture) |

`pw_record_args(target, rate, channels, latency_ms)` is the single builder for both.

**Non-regression contract:** `application::audio_visualizer::build_pw_record_args()` becomes
`voice::pw_record_args(CaptureTarget::Sink, SAMPLE_RATE, 1, 32)` and must produce
**byte-identical argv**. `daemon/tests/test_audio_visualizer.rs::test_pw_record_sink_monitor_args_capture_sink_not_mic`
and `::test_pw_record_args_include_low_latency` assert this and must pass **unmodified**.

This is how a source is added properly: generalise the existing function. Do **not** add a second, parallel builder.

### 4.2 `PcmSpec` and WAV construction

Speech capture is fixed at **16 kHz, mono, signed 16-bit little-endian** — whisper's native rate. Re-encoding is out of scope; pw-record converts.

- `wav_header(spec, data_len) -> Vec<u8>` — canonical 44-byte RIFF/WAVE PCM header.
- `wav_container(spec, pcm) -> Vec<u8>` — header followed by payload.

### 4.3 `SilenceDetector`

Adaptive endpointing, per D4. Holds an exponential moving average of the observed quiet floor and compares the live frame level against it.

- `push(frame_rms) -> SilenceDecision`
- `SilenceDecision { level: f32, silent: bool, silent_for_ms: u64 }`
- Floor tracks the low percentile of recent frames; a frame is silent when it sits below `floor * SILENCE_HEADROOM` for at least `SILENCE_FLOOR_WARMUP_FRAMES` frames. Warm-up prevents the very first silent frames from being read as a completed utterance.
- Auto-finalize fires when `silent_for_ms >= silence_hangover_ms` **or** `elapsed >= max_utterance_secs`.
- Pure, so it is tested against synthetic signal: a tone burst in quiet noise must detect the trailing silence; a constant DC latch must never be read as speech; an all-silent buffer must not immediately finalize.

### 4.4 `VoiceState` and `VoiceEvent`

```rust
pub enum VoiceState { Idle, Recording, Finalizing, Failed }
```

`VoiceState::Finalizing` covers transcription. A distinct state — rather than overloading `Recording` — is what lets the UI show a spinner and keep the send button honest while no microphone is being held.

```rust
#[serde(tag = "type", content = "payload")]
pub enum VoiceEvent {
    StateChanged { state: VoiceState },
    Level { rms: f32 },
    Partial { text: String },
    Final { transcript: Transcript },
    Error { message: String, recoverable: bool },
}
```

Adjacent tagging, matching `domain::assistant::AssistantEvent`, so the QML `SplitParser` sees `{"type":"Final","payload":{…}}`.

`Error` carries `recoverable`. A missing model is a **setup gap** — recoverable, belongs in the persistent inline notice. A killed engine mid-utterance is **not** recoverable in-session and belongs in the crash carousel. Conflating them was rejected in Q12: setup instructions do not belong in a transient banner.

### 4.5 `Transcript`

```rust
pub struct Transcript {
    pub text: String,
    pub language: String,      // BCP-47-ish tag, or "und" when undetermined
    pub duration_ms: u64,
    pub engine: String,
    pub model: String,
}
```

`language: "und"` is honest for an inconclusive detection; the UI shows "not determined" rather than inventing a guess.

### 4.6 `VoiceSettings`

Serde struct with `#[serde(default = …)]` on every field, so a partial or absent `voice` block in `settings.json` yields a valid configuration rather than a startup failure. Out-of-range values are clamped, not rejected:

| Key | Default | Clamp |
|---|---|---|
| `enabled` | `true` | — |
| `engine` | `"whisper-cpp"` | must be a known engine id |
| `model` | `"ggml-large-v3-turbo"` | must be in `MODEL_CATALOG` |
| `language` | `"auto"` | normalised, see §4.7 |
| `maxUtteranceSeconds` | `30` | `5 … 300` |
| `silenceHangoverMs` | `1200` | `300 … 5000` |
| `autoFinalize` | `true` | — |
| `installModelOnDemand` | `true` | — |

`silenceHangoverMs` and `autoFinalize` are additions beyond the original six keys, required by the D4 correction. They are exposed because a threshold the user cannot see is a threshold the user cannot distrust.

### 4.7 Language handling

- `normalize_language("")` → `"auto"`
- Region tags collapse to base: `"zh-CN"`, `"zh_TW"`, `"ZH"` → `"zh"`
- Case is canonicalised to lowercase
- An unknown non-`auto` tag falls back to `"auto"` rather than being passed to the engine, where it would produce an opaque failure
- The supported set is declared as data in `SUPPORTED_LANGUAGES`; the language picker in settings renders it

### 4.8 `VoiceStatus` and `ModelDescriptor`

`VoiceStatus { engine_available, engine_path, engine_version, model_present, model_path, model_size_bytes, setup_complete, error }` is what `voice status` prints and what the UI binds to. `setup_complete` is the single boolean the mic button's enabled state derives from — one source of truth, so the button cannot disagree with the doctor.

---

## 5. Port — `SpeechToTextPort`

Declared in `domain/ports.rs` alongside the existing ports, with the standard blanket `impl for Arc<T>`.

```rust
pub trait SpeechToTextPort: Send + Sync {
    fn probe(&self) -> DynResult<EngineProbe>;
    fn run_session(&self, cfg: &VoiceSessionConfig, sink: &mut dyn FnMut(VoiceEvent)) -> DynResult<Transcript>;
}
```

`EngineProbe { engine_id, binary_path, version, capabilities }` is the **capability probe** that replaces hardcoded flag assumptions. `WhisperCppAdapter` runs `whisper-cli --help` once, parses which flags the installed build actually supports, and `build_args` emits only supported flags — including the cost knobs (`-ac`, `-bs`, `-bo`, `-nf`) that keep dictation interactive (§6).

This exists because the exact CLI surface of `whisper-cpp` 1.9.4 could not be verified at authoring time (the package is not installed and the host has no passwordless `sudo`). Probing at runtime is more robust than any hardcoded list, and it is testable as a pure function over a synthetic capability set.

Passing a `&mut dyn FnMut(VoiceEvent)` sink keeps the trait synchronous and trivially fakeable, which is what makes §8.2 possible.

---

## 6. Infrastructure — `WhisperCppAdapter`

`daemon/src/infrastructure/whisper_stt_adapter.rs`.

**Engine discovery** mirrors `RuntimeProvisioner`: `which whisper-cli`, then `whisper-cli` (the un-suffixed name, which upstream also installs), then `~/.local/share/astral-plasma/bin/`. An explicit override, `ASTRAL_VOICE_ENGINE_BIN`, takes precedence — this is the hook the integration test uses to inject a stub, and it is also a legitimate escape hatch for unusual installs.

**Session lifecycle**

1. Spawn `pw-record` with `pw_record_args(CaptureTarget::Source, 16_000, 1, 32)`, stdout piped, wrapped in `stdbuf -o0` exactly as `spawn_pw_record` already does for the visualizer.
2. Read raw PCM, feed each frame through `SilenceDetector`, emit `Level`, and enforce `max_utterance_seconds`.
3. On finalize or manual stop, terminate `pw-record`, then trim the captured PCM to the region around detected speech (`trim_to_speech`, 250 ms margin). Whisper pays inference time for every sample it is handed, and the quiet stretches are where hallucinated text comes from. When no speech was detected the full buffer is kept, so "nothing was said" stays distinguishable from a capture failure.
4. Assemble `wav_container` and write it to a temp file under the cache dir, then run the engine on it. A file rather than stdin, because a file is re-runnable for debugging and does not depend on the engine's stdin handling.
5. Parse the engine's output (`read_transcript`: the `-oj` sidecar first, timestamped stdout as the fallback) into a `Transcript`, emit `Final`, return.
6. Remove the temp file, its sidecar and every staged path on all exit paths, including cancellation and engine failure.

**Cancellation** is cooperative: a `stop` control line flips an `AtomicBool` that the capture loop observes. No `SIGKILL` races.

**Model resolution** is `$XDG_CACHE_HOME/astral-plasma/models/<model-id>.bin`, overridable by `ASTRAL_VOICE_MODEL_DIR`. A model is considered present only if the file exists and is non-empty — a zero-byte file left by an interrupted download is treated as absent, not as a corrupt engine input.

**Engine invocation facts, verified live against whisper-cli 1.9.4.** Each of these was learned the hard way and is now pinned by tests:

- **`--vad` is only ever passed together with `--vad-model`.** `--help` advertises the flag, but a bare `--vad` makes whisper-cli exit 10 with `failed to process audio` — it turns on Silero inference with no fallback model, and the asset is not provisioned (D4). `build_args` emits the pair only when `EngineInvocation.vad_model` resolves to a real file (`resolve_vad_model`, the canonical `ggml-silero-v5.1.2.bin` beside the speech models); it is `None` in every install we ship, and endpointing is the daemon's own `SilenceDetector`, so nothing is lost.
- **`-oj` writes the JSON document beside the audio file (`<input>.json`), not to stdout.** stdout still carries the timestamped transcript, so parsing stdout as JSON returned an empty transcript for every utterance. The adapter reads the sidecar when the build advertises structured output, falls back to the timestamped stdout transcript when it is missing, and removes both files on every exit path.
- **The encoder window is sized to the utterance (`-ac`).** whisper.cpp encodes `n_audio_ctx * 20 ms` per window regardless of clip length, so the trained 30 s default made a one-second "hello" pay the same encoder pass as thirty seconds of speech — and with `language: auto` that pass happens twice (language detection, then transcription). `audio_context_for` computes `ceil(duration / 20 ms) + 1.28 s`, clamped to 5.12 s–30 s. Measured on a 12th-gen i9 with `ggml-small`, a 2.5 s English clip went 3.9 s → 2.5 s (`auto`) / 1.1 s (fixed language), with an identical transcript.
- **The decode is bounded (`-bs 1 -bo 1 -nf`).** whisper-cli's defaults (beam 5, best-of 5, temperature fallback to 1.0) are tuned for batch quality; on non-speech audio the decoder generated long hallucinated sequences. The same 3.3 s room capture took **45 s** with the defaults, **24 s** with greedy plus full fallback, and **~6 s** with greedy plus no fallback. Clean speech is unaffected (JFK: 0.6 s, identical transcript), so interactive dictation pins every multiplier.
- **The VAD asset is provisioned and used when present.** `--vad --vad-model <path>` is emitted only when `ggml-silero-v5.1.2.bin` exists (never a bare `--vad`: it fails every transcription). Silero filters non-speech before decoding; measured on a room capture dominated by music, the engine returned an empty transcript in **~0.2 s** instead of 6–45 s of hallucinated text, while clean speech was unchanged (JFK still exact).

---

## 7. Transport — `astral-plasma voice`

```
astral-plasma voice status                  -> VoiceStatus JSON
astral-plasma voice engines                 -> engine + model catalog JSON
astral-plasma voice install-model <id>      -> progress JSONL, then final status
astral-plasma voice session                 -> control on stdin, VoiceEvent JSONL on stdout
```

**`voice session` control vocabulary** (one command per line on stdin):

| Line | Effect |
|---|---|
| `start` | Begin capture. No-op if already recording. |
| `stop` | Finalize and transcribe. No-op if idle. |
| `cancel` | Abort, discard audio, emit `StateChanged{Idle}`. No transcription. |

Commands after the process has finalised are ignored rather than fatal, so a `stop` racing an auto-finalize is harmless — a real race the UI can produce, and a crash there would be a genuine bug.

**`install-model` downloads** to `<path>.part`, then renames on completion, so an interrupted download is never mistaken for a present model. A `VoiceEvent`-shaped progress line is emitted per chunk.

---

## 8. Verification

`AGENTS.md` §3 mandates TDD. The ordering is deliberate: **steps 1–5 require no engine, no model and no network.** Only step 7 touches a real engine. That is what makes the feature shippable rather than a script that works on one machine.

### 8.1 `daemon/tests/test_voice_domain.rs`
`CaptureTarget` argv for both variants; byte-identical visualizer argv; WAV header field-by-field and round-trip; silence detector against synthetic tone/noise/DC; `VoiceSettings` defaults, clamping, and survival of a partial JSON block; language normalisation table; `VoiceEvent` JSON round-trip; `MODEL_CATALOG` internal consistency (unique ids, non-zero sizes, all ids end in `.bin`).

### 8.2 `daemon/tests/test_voice_service.rs`
A hand-written fake `SpeechToTextPort` proving `VoiceService` orchestrates capture→finalize→`Final` and that a `cancel` produces no `Final`. Proves the application layer is engine-independent. The real-binary store suite (`test_voice_model_store.rs`) drives `install-model`, `install-vad` and `remove-model` with a stub `curl` on `PATH`, asserting staged `.part` files, monotonic progress, the rename into place, and that a model install also provisions the VAD asset.

### 8.3 `daemon/tests/test_whisper_stt_adapter.rs`
`build_args` against synthetic capability sets: VAD flags omitted when unsupported, VAD never emitted without its model asset, `-l auto` honoured, model path always passed, a stdin-reading engine never hangs, the encoder context sized to the utterance (`audio_context_for` bounds) and the decode bounded (`-bs 1 -bo 1 -nf`) whenever the build advertises the knobs. Plus probe-parsing of a synthetic `--help` blob, sidecar-first transcript reading (`read_transcript`), and speech-region trimming (`trim_to_speech`: padding, clamping, and the no-speech passthrough).

### 8.4 `daemon/tests/test_voice_session_protocol.rs`
Drives the real `astral-plasma voice session` binary with `ASTRAL_VOICE_ENGINE_BIN` pointed at a generated stub script that mirrors whisper-cli 1.9.4's actual behavior — a bare `--vad` is fatal, and `-oj` writes the JSON sidecar while stdout carries the timestamped transcript — asserting the full event contract, the control vocabulary, idempotent `stop`, clean exit, that the WAV handed to the engine is the trimmed speech region rather than the whole recording, and that the cost knobs (`-ac` sized to the trimmed audio, `-bs 1 -bo 1 -nf`, `--vad --vad-model` when the asset is installed) reach the engine. Uses a stub capture too, so it needs no microphone.

### 8.5 `daemon/tests/test_doctor_voice.rs`
`check_voice_engine()` appears in the report; `all_required_satisfied` is unaffected by voice being absent (D10).

### 8.6 `tests/tst_voice_input.qml`
Mic button disabled when unconfigured but **still visible** (D-in-Q12: a vanishing mic is undiscoverable); listening-strip geometry; concentric radii per `DESIGN.md` §9.4; dual-`Text` cross-fade present; transcript insertion **appends** and never truncates typed text; **and the safety property from D5 — a completed transcript never triggers a submit.** Also asserts the strip reads `Level` from real PCM and shows `und` honestly rather than a fabricated language, and that the finalizing readout says `transcribing` instead of reporting a language that cannot have been detected yet. `VoiceEventCodec` is exercised directly for the typed payload shapes (`{"rms": x}`, `{"text": s}`), with malformed input degrading to silence rather than NaN, and a scoping probe plus source contract pin that session handlers reference child ids lexically (`voiceElapsedTimer.stop()`), never as undefined `root.childId`.

### 8.7 `daemon/tests/test_audio_visualizer.rs`
**Unmodified.** Its continued passage is the proof that D4's capture generalisation did not regress the visualizer.

### 8.8 Visual proof
`spectacle` captures of the idle composer, the recording strip, and the completed-transcript state, inspected for concentric curvature, translucency, and seam-free compositing per `docs/LESSONS.md` §9.5.

---

## 9. UI — Liquid Glass

The listening strip is a **Tier 2 content card** (`docs/LESSONS.md` §9.2): it inherits the Tier 1 structural blur and must not add a second load-bearing glass layer, or the blur beneath it is extinguished. It is built from `components/LiquidGlassCard.qml`, never a bespoke `Rectangle` with an ad-hoc alpha. It carries `showBorder: false`: the composer already draws the perimeter ring, and a second ring inside it reads as a box drawn inside the panel rather than a glass edge (`docs/LESSONS.md` §9.1) — the specular hairlines keep the glass edge defined.

**Placement.** A strip row between the staged-files strip and the input row inside `ChatInputBar`'s `ColumnLayout`, so the composer grows upward and the send button never moves.

**Height accounting.** `ChatInputBar.qml:63` clamps total height to 190 px. The strip is included in that budget rather than added on top, so a listening composer cannot push the fixed controls off-screen on a short display — the same bounding discipline `AGENTS.md` §7.2 requires of the dock's taskbar. When the clamp is reached, the strip's text elides; the level meter and timer never clip, because they are the parts carrying live state.

**Motion.** Every transition uses `Theme` tokens — `animExpressiveFastSpatial` / `curveExpressiveFastSpatial` for the strip's entrance, `animExpressiveDefaultEffects` / `curveExpressiveDefaultEffects` for the level meter's decay and the dual-text cross-fade. No hardcoded durations, no `Easing.Linear`, per `AGENTS.md` §2.

**Partial text cross-fade.** When `Partial` events do arrive, the strip alternates two `Text` items and cross-fades them, per `AGENTS.md` §7.3. It never writes into `inputField.text` while recording.

**Honesty.** The strip renders from real state only: measured RMS, real elapsed milliseconds, the engine's reported language, and the real transcript. No placeholder shimmer, no synthetic progress, no invented partials (D6).

**Setup notice.** A setup gap (`ModelMissing`, `EngineMissing`) renders as a persistent inline notice above the input row carrying the install action, per Q12 — distinct from the existing crash carousel, which is reserved for genuine runtime deaths. The reason stays plain body text; the destination is rendered by the notice as its own chip (see §11a), which is why `describeVoiceGap` messages name the reason alone instead of composing a "— Settings › AI › Voice input" tail that would only duplicate it.

---

## 10. Configuration

`config/settings.json` gains a `voice` block with exactly the keys in §4.6. `Config.qml` exposes them through the established pattern at `Config.qml:916` (`mediaVisualizerStyle`): a `readonly` derived property for reads, a setter that mutates `root.settings` and calls `saveSettings()`. Every getter tolerates an absent block.

The settings UI is a **"Voice input" group inside the existing `settings_gui/pages/AiPage.qml`**, not a new page. Voice is a feature of the assistant, and `AGENTS.md` §6 warns specifically against adding surface that does not match the existing design language.

---

## 11. Edge Cases

| Condition | Behaviour |
|---|---|
| Engine binary absent | `EngineMissing`, recoverable. Button disabled, notice offers install. |
| Model absent | `ModelMissing`, recoverable. Same, naming the model. |
| Model file zero-length (interrupted download) | Treated as absent. `.part` suffix prevents the case entirely. |
| No microphone / source unavailable | `CaptureFailed`, recoverable. `pw-record` exits non-zero; surfaced, not swallowed. |
| Microphone already held by another app | `pw-record` fails to start → `CaptureFailed`. Honest message, no retry storm. |
| `stop` races auto-finalize | Idempotent. No crash, no duplicate `Final`. |
| `cancel` mid-utterance | Audio discarded, no `Final`, mic released. |
| Utterance exceeds cap | Auto-finalize at `maxUtteranceSeconds`. Reported in the transcript duration. |
| Engine exits non-zero | `Error{recoverable:false}` → crash carousel. Temp file removed. |
| Engine produces empty output | `Final` with empty text; **no** `Final` is fabricated from nothing. Strip clears. |
| Language undetermined | `language: "und"`. UI shows "not determined". Never guesses. |
| All-silent utterance | Silence detector warm-up prevents premature finalize; cap eventually fires. |
| Config block missing / partial | `#[serde(default)]` everywhere. Shell starts normally. |
| Out-of-range config value | Clamped to the documented range, not rejected. |
| Voice disabled in config | Button hidden, `voice session` still runnable manually via IPC. |
| Shell reload mid-recording | Session process is a child of the invoking QML `Process`; it dies with the shell, releasing the mic. |
| Unknown engine id in config | Falls back to the default engine, reported in `VoiceStatus`. |

---

## 11a. When Voice Speaks, and What It Says

Decided after seeing the first build in the running shell.

**The probe reports; it never speaks.** A readiness probe runs on startup and on
demand, entirely unprompted. Having it raise "whisper.cpp is not installed" meant
a banner about a feature the user had not asked for, in the composer, every time
the drawer opened — and it looked like an error the *shell* had made. So the probe
only sets `voiceStatus`. The mic button's dimmed state and hover tooltip already
carry the same information before any click.

**The mic click is a question, and is answered in place.** Clicking an
unconfigured mic calls `showVoiceSetupNotice()`: it clears the per-gap dismissal
and re-derives the message from live status. The strip appears in the composer and
*is* the link into the settings page, so the explanation and the fix are the same
gesture. It deliberately does **not** navigate: a page change the user did not ask
for hides the answer behind it. The keyboard shortcut and IPC route through the
same `toggleVoiceInput`, so both triggers behave identically.

**The notice is dismissible, per gap.** Dismissal is scoped to the current
`voiceStatus.gap`, so closing it is not permanent, and a *different* problem later
still surfaces on its own. An un-dismissible notice is a wall, and a wall teaches
users to ignore the composer.

**A failure is never dressed as a session.** In the error state the level meter,
the detected-language reading and the elapsed clock do not exist. Showing them
claimed a recording was under way and hearing nothing, which reads as a broken
microphone rather than a missing engine. The status glyph becomes a warning mark in
the error tone. The message itself states the reason in plain body text; the way
out is its own monospace path chip (`Settings › AI › Voice input ›`) with a
chevron, echoing the composer's model chip. One object on the row is the link — so
the affordance no longer needs an underline across the whole sentence, and the
error tone no longer needs to paint all of it.

**Recording starts only from an explicit trigger** — the mic click, the shortcut,
or IPC. `startVoiceInput` is additionally gated on `voiceMicUsable`, so a missing
engine cannot open the microphone even if something calls it directly. A probe is
never allowed to start capture.

---

## 12. Non-Regression Guarantees

1. `daemon/tests/test_audio_visualizer.rs` passes **unmodified** — the capture refactor is proven inert for the visualizer.
2. `tests/tst_assistant_drawer.qml` passes unmodified — the composer's existing geometry and source contracts are unchanged.
3. `ChatInputBar`'s existing submit semantics (`doSubmit`, `Keys.onReturnPressed`, Shift+Enter newline) are untouched.
4. The transcript insert **appends**. Existing typed text is never truncated.
5. No existing `settings.json` key changes meaning, type, or default.
6. `assistant chat` and every other `assistant` subcommand are unaffected; voice adds subcommands only.
7. `DoctorReport::all_required_satisfied` never depends on voice.
8. No new D-Bus name, so no new bus-name health monitor and no new failure mode for the existing one.

---

## 13. Defects Found by Visual Verification

`AGENTS.md` §6 is right that passing tests are a prerequisite, not proof. Four real defects survived a fully green test suite and were caught only by driving the running shell and looking at it. All four now have regression tests.

| # | Defect | Why tests missed it | Guard |
|---|---|---|---|
| 1 | `stop` was written to stdin but never read: the control loop blocked inside the session, so the stop button did nothing. | Every test sent `start` and let auto-finalize end the session, so the stop path was never exercised concurrently. | `a_stop_on_the_control_channel_interrupts_a_blocked_session`, `a_stop_after_start_still_transcribes` |
| 2 | The hard cap only ran inside the frame loop, so a stalled capture held the mic open indefinitely (observed: still recording after 16 minutes). | The test stub always delivered audio, so the loop always ran. | `a_stalled_capture_still_hits_the_hard_cap` |
| 3 | A detached watchdog could signal a reaped, possibly recycled pid. | Not reachable from any test without deliberately racing process teardown. | Watchdog is joined and the child reaped only afterwards; ordering documented at the call site |
| 4 | `start` was never sent, so the daemon blocked on stdin and the microphone was never opened, while the UI showed "recording" from its own timer. | Every layer was individually correct and self-consistent. | `write("start\n)`, `onRunningChanged` and `voiceAwaitingStart` source assertions in `tst_voice_input.qml` |

### 13a. Defects found in the interaction between voice and the rest of the shell

The same live-driving discipline surfaced five more, all in shared code that voice merely made reachable. Each is a case where a test could have caught it and didn't, because the assertion was made against the wrong thing.

| # | Defect | Why tests missed it | Guard |
|---|---|---|---|
| 5 | `Quickshell.Io.Process` has no `terminate()`. Nine call sites invoked it, so the call threw a `TypeError` that **aborted the caller**: restarting a probe while one was in flight silently did nothing, and `loadActiveSession` never ran. | Every test drove the happy path where the process was not already running, so the guard `if (proc.running)` short-circuited before the missing method. | `cancelProc`/`runProc` are now the only two places a process is started or stopped; `tst_voice_input.qml` asserts no `terminate()` survives and that `runProc` is the sole start site |
| 6 | A stopped process still finishes its output stream, truncated mid-line. With cancellation actually working, that partial output was parsed — a spurious `JSON.parse` error, and in the worst case a half-written payload applied. | The `terminate()` bug meant cancellation never happened, so this path was unreachable. | `discardOutput` is set on cancel and cleared on start; each collector checks it |
| 7 | Cancelling *and* restarting raced: the flag is re-armed immediately, so the superseded run's stream ended with the flag already false. A single boolean cannot distinguish the two orderings. | Only one ordering ever occurred in testing. | Completed-output collectors test `discardOutput \|\| running`; the two orderings are documented at the guard |
| 8 | A `SplitParser` emits chunks **while the process is still running**, so the `\|\| running` guard added for #7 silently discarded *every* event the voice status probe and the chat stream produced. Voice then looked permanently unconfigured and the mic stayed dimmed with no reason. | The guard was verified only for `StdioCollector`, the other collector kind. Offscreen the layout and parsers never run, so nothing noticed. | Streaming parsers are gated on `discardOutput` only; `tst_voice_input.qml` asserts the two kinds do not share a guard, and `voiceStatus` non-null is asserted live |
| 9 | The two startup probes (`active-session` and the sessions list) both decided to load the same session into one process slot, so the second superseded the first and the chat history silently failed to load. | Nothing asserted that startup was *complete*; each probe was correct in isolation. | `loadSession` is idempotent for the id already in flight |

Two more were found by looking at the strip rather than at any test:

- **A setup error was dressed as a recording.** The notice sat next to a level meter, a `0s` clock and "language not determined" — a live session apparently hearing nothing, i.e. a broken microphone. Those are capture readouts, so they now only exist while something is actually being captured, and the error shows a warning mark in the error tone. The fix needed `Layout.minimumWidth: 0` as well as `preferredWidth: 0`: a `Text`'s `implicitWidth` is the layout's *minimum*, so `preferredWidth: 0` alone is clamped away. That is why the meter (a plain `Item`) collapsed and the clock did not. The contract is asserted from source, because a headless harness does not run the real layout and would report `0` for the wrong reason.
- **`toggleVoiceInput` referenced `voiceRecording`, which is not a declared property** — the correct name is `isVoiceRecording`. The resulting `ReferenceError` fired on the function's first statement, so *every* branch after it, including the not-ready path, never ran. The mic button inlines its own routing and so never touched it, which is exactly why the on-screen button could work while the shortcut did nothing.

Two further issues were caught the same way and are not defects in the shipped code, but are worth recording because they shaped it:

- **The `mic` and `hourglass_top` glyphs do not exist** in this shell's Nerd Font build, and the Material Design Icons private-use range maps to unrelated shapes. Adding them anyway rendered a factory silhouette and a pair of bars rather than a missing-glyph box. Presence in `cmap` is not identity; only rendering the component settled it. Voice now uses glyphs proven to render (`chat`, `stop`, `graphic_eq`, `info`), and `tst_voice_input.qml` asserts the unverified names are never requested.
- **`services/` and `theme/` ship no `qmldir`**, so `AssistantService`, `Theme` and `Colors` resolve as *types* rather than registered singletons in a plain `qml` offscreen test. This is why the existing assistant suite asserts on source text rather than live values. Rather than add a `qmldir` — which would change module resolution for the whole shell — `ChatInputBar` takes its voice backend as an injectable property, which also decouples the component properly.

