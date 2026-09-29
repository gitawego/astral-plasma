# Voice Input Architecture & Tooling Audit

> **Status:** Completed  
> **Date:** 2026-09-29  
> **Scope:** Root cause diagnosis, architectural audit, and tooling evaluation of the Astral Plasma voice input system.  
> **Related Documents:** [`docs/VOICE-INPUT-SPEC.md`](VOICE-INPUT-SPEC.md), [`docs/LESSONS.md`](LESSONS.md), [`DESIGN.md`](../DESIGN.md).

---

## Executive Summary

An end-to-end investigation of the Astral Plasma voice input pipeline revealed that speech recognition fails due to a compounding sequence of **hardware pre-amp saturation**, **flawed energy-based silence thresholding**, **phantom echo cancellation routing**, and **high-latency two-pass CLI invocations of Whisper**.

While the high-level intent (local-only, privacy-preserving dictation integrated into the Copilot composer) is sound, the underlying implementation relies on CLI process orchestration and heuristic volume math that breaks down in real-world desktop environments.

---

## 1. Root Cause Analysis: Why Voice Input Fails

Live diagnostic probes on the running system revealed four primary root causes:

```
[Hardware ADC: ALC256] 
   └── +60 dB Gain (68% hard clipping) ──> Destroys acoustic formants
[PipeWire AEC Filter]
   └── No playback routed to virtual sink ──> 0 reference samples, AEC does not cancel echo; AGC distorts
[SilenceDetector & SpeechBounds]
   └── RMS energy heuristic (FLOOR_ADMIT_CEILING = 0.05) ──> Starves on noise, mutilates speech syllables
[whisper-cli Engine]
   └── Subprocess receives clipped/chopped audio ──> Hallucinates "Thank you.", "*Maniacal laughter*", or CJK text
```

### 1.1. Severe Hardware ADC Hard-Clipping (+60 dB Analog Gain)
* **Measurement**: On the host's Realtek ALC256 audio codec (`card 1, device 0`), the ALSA hardware mixer was configured with both capture controls at maximum:
  * `Capture Volume`: `63/63 (100%, +30.00 dB)`
  * `Internal Mic Boost`: `3/3 (100%, +30.00 dB)`
  * **Total Analog Gain**: **`+60.00 dB`** (a $1{,}000\times$ voltage magnification / $1{,}000{,}000\times$ power gain).
* **Observed Data**: In ambient room silence with only the laptop cooling fan active:
  ```
  Channels: 2, Rate: 48000 Hz, Duration: 2.91s
  Max: 32767, Min: -32768, RMS: 0.8877
  Clipped samples: 191,441 (68.48% hard-clipped)
  ```
* **Consequence**: Over **68% of all samples** delivered to the capture pipeline were hard-clipped against the 16-bit integer rails (`±32767`). The human voice was transformed into saturated square waves, stripping formants, pitch contours, and unvoiced consonants. Feeding this signal into Whisper causes catastrophic decoding failure, producing hallucinations like `*Maniacal laughter*`, `[water rushing]`, or arbitrary foreign phrases (`"我们身子就养回来"`).

### 1.2. Brittle RMS Energy Endpointing (`SilenceDetector` & `SpeechBounds`)
* **Mechanism**: In [`daemon/src/domain/voice.rs`](../daemon/src/domain/voice.rs), silence detection and speech trimming rely on raw RMS energy thresholds rather than a neural Voice Activity Detector (VAD):
  ```rust
  const FLOOR_ADMIT_CEILING: f32 = 0.05;
  let speaking_threshold = (self.peak / SILENCE_HEADROOM).max(floor * SILENCE_HEADROOM);
  let activity_threshold = (self.peak / SPEECH_ACTIVITY_HEADROOM)
      .max(floor * SPEECH_ACTIVITY_HEADROOM)
      .max(SPEECH_ACTIVITY_ANCHOR);
  ```
* **Failure Modes**:
  1. **Noise Starvation (Hallucination Loop)**: When ambient room noise or uncalibrated microphone gain yields an idle RMS $\ge 0.05$, `floor_samples` is never populated, causing `floor()` to return `0.0`. Every frame of fan noise clears `SPEECH_ACTIVITY_ANCHOR` ($0.005$), causing `detector.has_speech()` to evaluate to `true` on pure room silence. `trim_to_speech` then passes seconds of noise to Whisper, triggering hallucinations.
  2. **Consonant & Word Mutilation**: When gain is calibrated lower, `activity_threshold` tracks `peak / 1.5`. Because human speech has a $\sim 30\text{ dB}$ dynamic range, quieter unvoiced consonants (`s`, `t`, `k`, `f`, `th`) and trailing words fall below `peak / 1.5`.
  3. **Empirical Proof**: Playing `/usr/share/sounds/alsa/Front_Center.wav` (1.4 seconds of clear speech: *"Front, Center."*) was trimmed down to a **760 ms fragment**. Whisper received only an isolated, chopped syllable, causing it to hallucinate:
     ```json
     {"type":"Final","payload":{"text":"Thank you.","language":"en","duration_ms":760}}
     ```
     *(In Whisper, `"Thank you."` is the canonical hallucination produced when presented with chopped audio or leading/trailing silence).*

### 1.3. Ineffective Echo Cancellation (`astral_echo_cancel`)
* **Mechanism**: [`daemon/src/infrastructure/echo_cancel.rs`](../daemon/src/infrastructure/echo_cancel.rs) loads PipeWire's `module-echo-cancel` with:
  ```bash
  pactl load-module module-echo-cancel aec_method=webrtc source_name=astral_echo_cancel sink_name=astral_echo_cancel_sink
  ```
* **The Fatal Flaw**: As documented in [`docs/VOICE-INPUT-SPEC.md`](VOICE-INPUT-SPEC.md#L142), desktop audio routing was left untouched:
  > *"Loading the module does not change the default sink or source, so playback routing is untouched."*
* **Consequence**: All system audio (browsers, media players, Spotify) plays to the hardware default sink (`Jeecoo M20`), **not** to `astral_echo_cancel_sink`. Because the echo canceller receives **zero reference playback samples**, WebRTC AEC3 cannot cancel any speaker sound. Instead, it operates blindly in the capture path, applying non-linear Automatic Gain Control (AGC) and aggressive noise suppression that introduce phase distortion and volume pumping into the microphone signal.

### 1.4. Flawed Two-Pass Language Detection (`-dl`)
* **Mechanism**: In [`daemon/src/infrastructure/whisper_stt_adapter.rs`](../daemon/src/infrastructure/whisper_stt_adapter.rs), when `language` is `"auto"`, the daemon runs a detection pass with `whisper-cli -dl`.
* **The Failure**: Whisper's language detection is an unconstrained `argmax` over 100 language logits. On short utterances (1–2 seconds) or degraded acoustics, the argmax frequently lands on an incorrect language (e.g., clean English speech was auto-detected as **`ja` (Japanese, $p=0.29$)**).
* **The Locale Trap**: Because $p = 0.29 < \text{MIN\_CONFIDENCE} (0.35)$, the adapter falls back to the system locale (`en`) and forces the second pass with `-l en`. If a user dictates in Mandarin Chinese or French, an unconfident detection forces an English decode, generating gibberish.

---

## 2. Architectural Audit

| Architecture Dimension | Current Implementation | Critical Vulnerabilities | Modern Architecture Alternative |
| :--- | :--- | :--- | :--- |
| **Engine Lifecycle** | One-shot CLI subprocess (`astral-plasma voice session` spawns `whisper-cli`) | **Extreme Latency (7–25s)**:<br>1. Spawns `whisper-cli` **twice** per utterance (`-dl` pass + transcribe pass).<br>2. Each run re-reads the 487 MB model from disk into RAM (543 ms load time) and re-allocates 100+ MB GGML buffers.<br>3. An interactive composer cannot tolerate 7–25s turnaround for short dictation. | **Resident In-Process Engine**:<br>Keep model in memory via native Rust FFI bindings (`whisper-rs`) or a lightweight background server over a Unix domain socket. Model load latency drops from $500\text{ ms} \times 2$ to **0 ms**, with an idle unload timer. |
| **Audio Capture** | Spawning `stdbuf -o0 pw-record` stdout pipe + `SIGKILL` watchdog thread | **Fragile Process Supervision**:<br>1. Piping stdout over an OS pipe requires a 25ms polling loop that issues `libc::kill(pid, SIGKILL)` to prevent hung reads.<br>2. Prone to orphaned processes and pipe deadlocks. | **Native In-Process Capture**:<br>Use native Rust PipeWire/ALSA bindings (such as `pipewire-rs` or `cpal`) to capture PCM directly in-process via buffer callbacks with zero sub-process overhead. |
| **Input Health & Gain Staging** | Assumes OS ALSA settings are valid | **No Hardware Gain Auditing**:<br>1. The system has no clipping detection or automatic gain calibration.<br>2. If the OS defaults to $+60\text{ dB}$ boost (common on laptop ALC codecs), the feature fails completely without warning. | **Gain & Clipping Guard**:<br>Check ALSA input levels during initialization or `doctor` check. Emit a clear diagnostic if clipping exceeds $1\%$. |
| **Safety Contract** | Transcripts inserted into composer, never auto-submitted | **Sound Decision**:<br>Appending dictation into the composer for manual user confirmation (Enter key) is correct. It prevents hallucinated text or misrecognized commands from triggering destructive bash/IPC actions. | **Retain**:<br>Keep manual submission discipline. |

---

## 3. Tooling Evaluation

### 3.1. Whisper (`whisper.cpp`) for Voice Dictation
* **Verdict**: **Sub-optimal for interactive desktop dictation**.
* **Analysis**:
  1. **Designed for Batch, Not Real-Time Streaming**: Whisper was designed to transcribe 30-second non-causal audio chunks (podcasts, YouTube). It cannot stream partial tokens as you speak without re-running the entire encoder over and over.
  2. **Hallucination Prone**: Whisper’s autoregressive language model decoder hallucinates text when fed silence, room noise, or truncated clips (*"Thank you for watching"*, *"Please subscribe"*).
  3. **Mandarin Chinese Quality**: Whisper's Mandarin accuracy is noticeably inferior to dedicated Chinese ASR models.
* **Modern Alternatives for Local Desktop Linux Dictation**:
  * **Sherpa-ONNX (SenseVoice / Paraformer / Zipformer)**:
    * **`SenseVoice-Small`** (Alibaba): $5\times$ faster than Whisper-small, runs in $\sim 50\text{ ms}$ on CPU, exceptional Chinese/English accuracy, zero hallucinations on noise, includes built-in audio event and VAD support.
    * **`Streaming Zipformer`**: True causal streaming ASR with $<100\text{ ms}$ latency and $<50\text{ MB}$ RAM footprint. Emits words in real time as the user speaks.
  * **Vosk / Kaldi**: Ultra-lightweight, deterministic, zero hallucinations on ambient silence, ideal for quick desktop commands.

### 3.2. Custom Energy Thresholding vs. Neural VAD
* **Verdict**: **Incorrect Tool**.
* **Analysis**: Human speech has a $30\text{ dB}$ dynamic range. Unvoiced consonants (`s`, `th`, `p`, `t`) have low acoustic energy, while laptop fans, typing, and HVAC have high acoustic energy. An energy threshold cannot separate the two.
* **Correct Tool**:
  * **Silero VAD** (runs via ONNX or native C/C++, $\sim 2\text{ MB}$ model, $<1\text{ ms}$ evaluation). Neural VADs evaluate spectral phoneme probabilities rather than raw volume, detecting human vocal cords with $>99\%$ accuracy regardless of microphone gain or background noise.

### 3.3. PipeWire `module-echo-cancel` via `pactl load-module`
* **Verdict**: **Misconfigured Architecture**.
* **Analysis**: Loading a PulseAudio compatibility echo-cancel module via CLI `pactl` without routing desktop playback through `astral_echo_cancel_sink` renders the acoustic echo cancellation algorithm completely non-functional while adding unnecessary filtering distortion. A desktop dictation tool should either properly route the playback sink through the filter graph or rely on a dedicated noise-suppression filter (such as `rnnoise` / PipeWire's `filter-chain-noise-suppression`).

---

## 4. Remediation Roadmap

1. **Immediate Gain & Clipping Guard**:
   * Add a clipping detector in `capture_loop`: if $>2\%$ of samples in the first 500 ms are clipped at $32767$, emit a warning event and advise the user to lower mic boost in `alsamixer` / system settings.
   * Add an automated ALSA gain sanitizer or diagnostic check in `doctor_service.rs`.
2. **Replace RMS Energy SilenceDetector with Neural VAD**:
   * Integrate **Silero VAD** (via ONNX runtime or a lightweight C library).
   * Replace manual `SpeechBounds` and `trim_to_speech` with neural speech probability gating ($p > 0.5$).
3. **Eliminate CLI Re-spawning Latency**:
   * Move from `Command::new("whisper-cli")` to an in-process worker using `whisper-rs` (C++ FFI) or a persistent background process over a local domain socket.
   * Eliminate the separate `-dl` pass by performing single-pass decoding with language priors.
4. **Evaluate Next-Generation STT Engines**:
   * Prototype a backend adapter for **Sherpa-ONNX / SenseVoice-Small** to achieve sub-100ms response times, superior multilingual accuracy, and elimination of silence hallucinations.
