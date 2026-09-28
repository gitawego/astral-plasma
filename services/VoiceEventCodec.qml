import QtQuick

/**
 * Pure decoders for the `astral-plasma voice session` JSONL events.
 *
 * The daemon's `VoiceEvent` enum is serde-tagged `{"type": ..., "payload": ...}`,
 * so every event carries its own payload shape: `Level` and `Partial` are
 * structs (`{"rms": 0.42}`, `{"text": "hel"}`), `Progress` is a bare fraction,
 * and `Final` is the transcript object. Reading the wrong shape is silent in
 * JavaScript - `Math.min(1, obj)` is `NaN` and an object assigned to a string
 * is `"[object Object]"` - which is how a live microphone rendered as a dead
 * level meter while the transcript still arrived.
 *
 * A component, not a singleton: `services/` ships no qmldir, so singletons do
 * not resolve in the offscreen test harness, while directory-imported
 * components do. The shell's AssistantService and `tst_voice_input.qml` then
 * exercise the very same code.
 */
QtObject {
    /**
     * Measured RMS from a `Level` event, clamped to [0, 1].
     *
     * Accepts the object payload the daemon sends and the bare-number form as a
     * tolerance for older streams; anything malformed decodes to silence rather
     * than NaN, because NaN propagates into everything the meter drives.
     */
    function level(event) {
        const payload = event ? event.payload : null;
        const rms = (payload !== null && typeof payload === "object") ? payload.rms : payload;
        const value = Number(rms);
        if (!isFinite(value)) return 0.0;
        return Math.max(0.0, Math.min(1.0, value));
    }

    /**
     * Streaming text from a `Partial` event, or `""` when there is none.
     *
     * `whisper-cli` is a whole-file engine and emits no `Partial` events today;
     * an engine that genuinely streams will, and its payload is `{"text": ...}`.
     */
    function partial(event) {
        if (!event) return "";
        const payload = event.payload;
        if (payload === null || payload === undefined) return "";
        const text = (typeof payload === "object") ? payload.text : payload;
        return (typeof text === "string") ? text : "";
    }
}
