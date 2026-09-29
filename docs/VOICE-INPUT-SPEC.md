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

**Endpointing vs filtering, recorded honestly:** the original design expected whisper.cpp's Silero VAD to decide "the user stopped talking". That is not what `--vad` does: it is an *inference-time filter over a completed file*, so live endpointing remains the daemon's **noise-floor-adaptive** `SilenceDetector` (a pure function, unit-tested against synthetic speech/noise, degradable to manual-only via `voice.autoFinalize: false`).

**Engine VAD is not used at all, and that is a measured decision.** whisper.cpp applies `--vad` *before* language detection: `whisper_full` replaces the samples with the VAD-filtered audio and then calls `whisper_full_with_state`, which auto-detects the language from that filtered audio (`src/whisper.cpp`). On a music+speech mix the filtering therefore corrupts the one thing dictation depends on: at **-12 dB music-to-voice** the unfiltered run detects `fr` and returns the exact "Tu fais quoi ?", while the VAD run detects `en` and returns "Quoi ?" (clipped). The asset remains downloadable upstream (`ggml-org/whisper-vad`), but the daemon neither provisions nor passes it: endpointing and no-speech gating are the daemon's own detector, so engine VAD is both redundant and harmful.

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

### D8 — The detected language is displayed, *while it can still matter*

D8 originally said auto-detection is the default and that showing the reading turns a mystery into a one-glance override. Both halves were unimplementable as written, and the failure was a real one: **English speech came back as "会議のも学び".**

Two separate defects were behind it.

**The decision was trusted unconditionally.** `whisper_lang_auto_detect_internal` sorts the language logits, softmaxes, and returns `logits_id[0].second` — a bare `argmax` over 100 candidates. The winner is written to `state->lang_id` and the decoder is then *constrained* to it, so nothing downstream can revisit the choice. On a 1.3 s clip whose encoder window is two-thirds zero padding, that argmax landed on `ja` at **p = 0.08**: not a reading, the shape of a tie between a hundred languages. whisper prints that probability to stderr; the adapter captured stderr and discarded it on success, so the one number that would have exposed the tie was already in hand and thrown away.

**The display was structurally unreachable.** The strip rendered `"transcribing"` for the whole of the finalizing state; `voiceLanguage` was cleared at session start and set only on `Final`, which also set `voiceState = "idle"` and hid the strip. So during recording the label read "language not determined" and during finalizing it read "transcribing" — it could never render a real value. The reasoning in the code comment was correct (a language *cannot* have been detected yet at that point); the mistake was treating that as a reason to hide the field rather than as proof the affordance was in the wrong place.

What replaces it:

- **Detection is its own pass.** `whisper-cli -dl` identifies and stops, so the language decision happens *before* the decode and can be inspected. `LanguageSource` records whether the transcription used a configured language, a confident detection, or a detection that was overridden.
- **The confidence gate is real.** Below `MIN_LANGUAGE_CONFIDENCE` (0.35) the detection is *reported* but not *transcribed with*, and the user's locale is used instead. A pinned language is never overridden at any confidence.
- **The reading is on screen during the decode.** A new `Detected` event fires before the transcription pass, and the strip shows the tag — annotated `(unsure)` and tinted with the error tone when the confidence is a tie.
- **A doubtful reading is one click from a correction.** Clicking the label opens the voice section of Settings. There is deliberately no inline locale list: twenty locales in a 46 px strip would be a worse control than the page the user already knows.

The reading replaces the word "transcribing" when present. That is the right trade — the elapsed clock and the level meter already say work is happening, and a status word is worth less than the one thing the user can act on.

### D9 — Session-scoped language overrides are never persisted

`voice.language` in `settings.json` is the **default**. A per-session override lives only in `AssistantService` runtime state and is passed as `voice session --lang <tag>`. Persisting it would mean a user dictating Mandarin in one session silently reconfigures their shell.

The override property existed for the whole of v1 with **no reader and no writer**, and `tst_voice_input.qml` asserted only that the declaration was present — so the test passed on dead code. It now reaches the engine, and the test asserts the argument is built rather than the property is declared.

**The default is the user's locale, not `auto`.** A dictation UI is a committed-language interaction: the user knows what they are speaking, and the whole value of the microphone is low-friction insertion into a prompt they are about to send. Delegating the decision that determines the output alphabet to the least reliable part of the model is not a defensible default. An **absent** `voice.language` resolves to the locale; an explicit `"auto"` remains available in the picker for people who switch languages while dictating. Keeping those two apart matters — collapsing them is what made the ungated argmax the default.

### D11 — Echo cancellation is the default input path

A desktop microphone hears the machine's own speakers, and that - not the model, not the language setting - is the most common cause of bad dictation output. Measured on a reporter's machine: the built-in microphone carried the playing music at **0.64 RMS full scale** (the music itself measured 0.67–0.80), so the engine was asked to transcribe playback. The playback drove language detection (Chinese speech came back as Korean) or, once VAD filtered it, left nothing at all (English speech produced no text).

PipeWire's `module-echo-cancel` (WebRTC AEC3) subtracts the sink reference from the capture. The same music measured **0.07 RMS** through the filtered source (~19 dB down), while a live voice - uncorrelated with the reference - passes through. `voice.echoCancel` therefore defaults to on:

- The daemon provisions a source named `astral_echo_cancel` on the first session (`pactl load-module module-echo-cancel aec_method=webrtc ...`) and captures from it.
- When PipeWire, `pactl`, or the module is unavailable, it silently falls back to the default source - dictation must never break over an optional filter.
- Loading the module does not change the default sink or source, so playback routing is untouched.
- `voice status` reports both the setting (`echo_cancel`) and whether the source is present (`echo_cancel_active`); a status probe never mutates the audio graph.

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

Adaptive endpointing, per D4. It tracks **two** statistics rather than one, because a single number cannot serve both jobs at once:

- a **room estimate** — the 20th percentile of the frames that were not themselves speech, over a 2 s window, admitting only frames at or below `FLOOR_ADMIT_CEILING` (0.05);
- a **peak** — the loudest recent level, decaying with a ~1.5 s time constant.

A frame is speech when it clears `max(peak / SILENCE_HEADROOM, floor * SILENCE_HEADROOM)`. Requiring both would mean an unmeasured room could veto real speech, and a measured one could veto a quiet word.

- `push(frame_rms) -> SilenceDecision`
- `SilenceDecision { level, floor, speaking, active, silent_for_ms }`
- `speaking` drives **endpointing**; `active` is the same test at the looser `SPEECH_ACTIVITY_HEADROOM` (1.5) and drives **trimming bounds** and `has_speech()`. They are separate because "did the user stop talking" is a precision question and "was anything said at all" is a recall one, and gating the engine on the precision answer discarded whole utterances.
- Warm-up (`SILENCE_WARMUP_FRAMES`) gates **only** the silence accumulator, never speech classification. Gating classification is what discarded the first 500 ms of any utterance that began the moment the microphone opened.
- Auto-finalize fires when `silent_for_ms >= silence_hangover_ms` **or** `elapsed >= max_utterance_secs`.
- Pure, so it is tested against synthetic signal **at the levels a real microphone produces** (room 0.002, speech 0.05), not only at levels no room produces.

**Why the estimator is a low quantile and not a mean.** The previous version averaged every frame below the admission ceiling. Ordinary dictation sits just under that ceiling, so the estimate climbed to the speech level, `level > floor * 3` became unsatisfiable, and the detector latched off mid-sentence: measured, a 1.3 s utterance at 0.05 in a 0.002 room was tracked for 260 ms, and the engine was handed a 260 ms fragment. A low quantile is immune, because speech is a minority of any window shorter than a continuous utterance.

**The dividing line is a level judgement.** A *constant* signal at or below 0.05 is measurably a room; one above it is measurably an event. No energy-based detector can place that line anywhere else without a real VAD, so a steady background above it is read as speech, costing one wasted inference that returns nothing. That is the preferable trade to discarding utterances, and §11 records it.

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
    pub speech_detected: bool, // did the capture contain recognised speech?
}
```

`language: "und"` is honest for an inconclusive detection; the UI shows "not determined" rather than inventing a guess.

`speech_detected` distinguishes "the microphone heard nothing" from "the engine heard something and had no words for it". Those send the user to different places, and without the field an empty transcript arrives with no explanation at all — indistinguishable from a broken feature, leaving the user with a composer that silently refused to change. See §9a.

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

- `normalize_language("")` → `"auto"` for a *value a user typed*. An **absent** `voice.language` is a different thing and is resolved to the system locale by `VoiceSettings::sanitized`; see D8.
- `system_language()` reads `LC_ALL`, then `LC_MESSAGES`, then `LANG` — the POSIX precedence order — and strips region, codeset and modifier (`de_DE.UTF-8@euro` → `de`). An unresolvable primary falls through rather than poisoning the lookup. It returns `"auto"` only when nothing resolves, and the confidence gate is what keeps that honest.
- Region tags collapse to base: `"zh-CN"`, `"zh_TW"`, `"ZH"` → `"zh"`
- Case is canonicalised to lowercase
- An unknown non-`auto` tag falls back to `"auto"` rather than being passed to the engine, where it would produce an opaque failure
- The supported set is declared as data in `SUPPORTED_LANGUAGES`; the language picker in settings renders it
- `resolve_transcription_language(requested, fallback, detected)` is the single decision point, and it is asymmetric on purpose: a pinned `requested` language is never overridden, only an *unconfident* detection is. See D8.

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

- **Language is decided before it is trusted.** See D8. When the user has not pinned a language, the adapter runs a detection pass (`-dl`, probed like every other flag and absent on builds that predate it) and then a transcription pass with `-l <resolved>`. The engine's own `auto-detected language: <tag> (p = <float>)` line is parsed off **stderr**; below `MIN_LANGUAGE_CONFIDENCE` the detection is reported but not transcribed with. A build without `-dl` falls back to a single `-l auto` pass, which is the old behaviour, rather than emitting a flag it will reject.

- **Engine VAD is never requested.** See D4: `--vad` rewrites the audio before language detection and costs ~3 dB of detection headroom. The daemon's `SilenceDetector` gates the no-speech case instead (`has_speech` from capture), and the engine only runs when speech was detected.
- **`-oj` writes the JSON document beside the audio file (`<input>.json`), not to stdout.** stdout still carries the timestamped transcript, so parsing stdout as JSON returned an empty transcript for every utterance. The adapter reads the sidecar when the build advertises structured output, falls back to the timestamped stdout transcript when it is missing, and removes both files on every exit path.
- **The encoder window is sized to the utterance (`-ac`).** whisper.cpp encodes `n_audio_ctx * 20 ms` per window regardless of clip length, so the trained 30 s default made a one-second "hello" pay the same encoder pass as thirty seconds of speech — and with `language: auto` that pass happens twice (language detection, then transcription). `audio_context_for` computes `ceil(duration / 20 ms) + 1.28 s`, clamped to 5.12 s–30 s. Measured on a 12th-gen i9 with `ggml-small`, a 2.5 s English clip went 3.9 s → 2.5 s (`auto`) / 1.1 s (fixed language), with an identical transcript.
- **The decode is bounded (`-bs 1 -bo 1 -nf`).** whisper-cli's defaults (beam 5, best-of 5, temperature fallback to 1.0) are tuned for batch quality; on non-speech audio the decoder generated long hallucinated sequences. The same 3.3 s room capture took **45 s** with the defaults, **24 s** with greedy plus full fallback, and **~6 s** with greedy plus no fallback. Clean speech is unaffected (JFK: 0.6 s, identical transcript), so interactive dictation pins every multiplier.
- **The engine's detected language is reported.** The `-oj` sidecar carries `result.language`; the adapter reads it into `Transcript.language` (it was hardcoded to `und` whenever `language: auto`), so the UI can show `fr` or `ko` instead of "language not determined" - which is what makes a wrong detection visible and correctable from the language picker.

---

## 7. Transport — `astral-plasma voice`

```
astral-plasma voice status                  -> VoiceStatus JSON
astral-plasma voice engines                 -> engine + model catalog JSON
astral-plasma voice install-model <id>      -> progress JSONL, then final status
astral-plasma voice install-vad-model       -> Silero VAD asset, progress JSONL
astral-plasma voice session                 -> control on stdin, VoiceEvent JSONL on stdout
astral-plasma voice serve [socket] [idle-s] -> resident STT server (§14)
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
A hand-written fake `SpeechToTextPort` proving `VoiceService` orchestrates capture→finalize→`Final` and that a `cancel` produces no `Final`. Proves the application layer is engine-independent. The real-binary store suite (`test_voice_model_store.rs`) drives `install-model` and `remove-model` with a stub `curl` on `PATH`, asserting staged `.part` files, monotonic progress and the rename into place.

### 8.3 `daemon/tests/test_whisper_stt_adapter.rs`
`build_args` against synthetic capability sets: engine VAD never requested, `-l auto` honoured, model path always passed, a stdin-reading engine never hangs, the encoder context sized to the utterance (`audio_context_for` bounds) and the decode bounded (`-bs 1 -bo 1 -nf`) whenever the build advertises the knobs. Plus the language decision in isolation: `parse_detected_language` recovering the tag and probability from a realistic stderr, `resolve_transcription_language` overriding a tie but never a pinned language, `build_detect_args` emitting `-dl` only on a build that advertises it, and the probe finding `-dl` in a real `whisper-cli` help banner. Plus probe-parsing of a synthetic `--help` blob, sidecar-first transcript reading with the detected language (`read_transcript` -> `EngineOutput`), and speech-region trimming (`trim_to_speech`: padding, clamping, and the no-speech passthrough).

### 8.4 `daemon/tests/test_voice_session_protocol.rs`
Drives the real `astral-plasma voice session` binary with `ASTRAL_VOICE_ENGINE_BIN` pointed at a generated stub script that mirrors whisper-cli 1.9.4's actual behavior — a bare `--vad` is fatal, and `-oj` writes the JSON sidecar while stdout carries the timestamped transcript — asserting the full event contract, the control vocabulary, idempotent `stop`, clean exit, that the WAV handed to the engine is the trimmed speech region rather than the whole recording, that the cost knobs (`-ac` sized to the trimmed audio, `-bs 1 -bo 1 -nf`) reach the engine while the VAD flags never do, that the engine's detected language is reported in `Final`, and that a capture with no speech skips the engine entirely. Uses a stub capture too, so it needs no microphone.

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

### 9a. An empty result is reported, never swallowed

The composer's only path from a `Final` event to the text field is
`Connections { onVoiceTranscriptChanged }` in `ChatInputBar.qml`. QML emits **no
change signal when a property is assigned its current value**, and
`voiceTranscript` is already `""` when a session produced no words. So an empty
`Final` never invoked the handler: the microphone opened, the level meter moved
(the meter shows raw RMS for *every* frame, speech or not), the strip closed,
and the composer was untouched — with no error, no notice, and nothing in the
logs. The guard written for this case, `if (!addition ...) return`, was itself
unreachable, because the handler it lived in never ran.

This is also the structural point: **the meter and the transcript gate read two
different signals.** The meter is the raw RMS of whatever the microphone heard;
`has_speech` is a much stricter test. Displaying the first while the second
decides the outcome is fine, but it must be reconciled somewhere, or "I can see
it capturing" and "I get a transcript" are decoupled with nothing in between.

The resolution has no new mechanism, only a separation that already existed:

- `hasSetupMessage` — a persistent configuration gap. Has a destination, so the
  strip links into Settings. Unchanged.
- `emptyNotice` — a one-off outcome of the recording just finished. **No
  destination**, because a page of settings cannot explain why one recording was
  silent. Offering the link anyway would send the user somewhere that cannot
  help, which is worse than offering nothing.

`AssistantService` decides between them from `Transcript.speech_detected`, and
`ChatInputBar.showVoiceStrip` holds the strip open for either, so the
explanation is not created and destroyed in the same tick. The two notices
collapse the live readouts exactly as a setup gap does: a level meter reading
for a session that is over is the same "dead microphone" misread as a setup
error shown next to a live meter (D-in-Q12).

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
| Engine produces empty output | `Final` with empty text and `speech_detected: true`; **no** text is fabricated from nothing. The composer shows an outcome notice (see §9a) — the result is empty, but it is never unexplained. |
| Language undetermined | `language: "und"`. UI shows "not determined". Never guesses. |
| All-silent utterance | `has_speech()` is false, the engine is skipped, and `Final` carries empty text with `speech_detected: false`. The composer shows "No speech was detected in that recording". Honest, and said out loud. |
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

---

## 14. Audit Remediation Amendments (2026-09-29)

Implements `docs/VOICE-INPUT-AUDIT.md` §4. Each item supersedes the section noted; the original reasoning above is kept for history. All verified live on ALC256 + whisper.cpp 1.9.4 (`ggml-small`, `ggml-silero-v5.1.2`).

### A1 — Gain guard (new; no prior section)

`capture_loop` audits the first 500 ms: `clipping_ratio() >= 0.02` emits one warn-only `VoiceEvent::Warning` with the `amixer` remediation and the session continues. `doctor` warns when `Capture ~100%` + `Internal Mic Boost ~100%`. Never auto-mutes (D7). QML handles `Warning` into `voiceWarning` without failing the session.

### A2 — Neural VAD replaces energy gating (supersedes D4's "engine VAD is not used", extends §4.3)

`whisper-vad-speech-segments` + provisioned `ggml-silero-v5.1.2.bin` (`voice install-vad-model`, `VoiceStatus.vad_model_present`) judges the FULL capture; its union span trims via the single `trim_to_speech` margin and its silence skips inference. Proven: `Front_Center.wav` → 2 segments (the two words); a full-scale sine → 0 segments (energy would call it speech); a live room → empty `Final`, no wasted inference. Absent binary/model degrades to the energy detector, never breaks. `ASTRAL_VOICE_VAD_BIN` injects a stub in tests.

### A3 — Single-pass decode + resident server (supersedes D8's `-dl` two-pass)

One decode with `-l <pinned|locale>`; the sidecar `result.language` is display-only `Detected` before `Final`. `voice serve` supervises `whisper-server` (model resident, per-request `language` field verified: `fr` → "Centre", `auto` → detected) behind the Unix-socket protocol; `ASTRAL_VOICE_SERVER_SOCK` selects it with one-shot CLI fallback. Proven: repeat requests, one backend boot. `build_detect_args` / `parse_detected_language` retained for probe compat but spawn nothing.

### A4 — Echo cancellation off by default (supersedes D11)

The legacy `module-echo-cancel` path loads nothing without sink routing (zero reference samples + blind AGC distortion, audit §3.3). `echoCancel` defaults `false`; `ensure_source()` requires `ASTRAL_VOICE_AEC_ALLOW_LEGACY=1`; `rnnoise` filter-chain is the evaluated replacement.

Implemented as `voice.noiseSuppress` (default `false`, Settings toggle): capture-side only, operator-provisioned node (`ASTRAL_VOICE_NOISE_SUPPRESS_SOURCE` override wins), presence-probed with default-source fallback. `voice status` reports `noise_suppress{,_active}` + `rnnoise_available` (LADSPA scan). Verdict on this host: plugin absent, no sudo — path code-complete with stubs, suppression effect unevaluated-live; VAD gating already covers noise-induced hallucinations.

### A5 — Native capture backend (extends §4.1/§6)

`ASTRAL_VOICE_CAPTURE_BACKEND=native` captures in-process via `cpal` (exact 16 kHz mono s16/f32, else honest `CaptureFailed`) through the same frame loop (`FrameRead`), endpointing, watchdog (deadline, no signals needed) and trim contract. Proven live: 7.76 s ALC256 capture end-to-end. Default stays `pw-record`; an explicit capture-binary override always takes the spawn path (the test seam).

