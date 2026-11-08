pragma Singleton

import QtQuick

// ============================================================================
// AssistantContext — the assistant's injected world
// ============================================================================
// The assistant is several files (window, drawer, five components). Rather than thread
// three properties through each of them, they read one context object that the window
// fills from what the host injected:
//
//   assistant   the shell's live assistant service (sessions, models, harness)
//   shellState  the shell's read model (visibility, settings it renders)
//   intents     the bus for actions the shell owns (settings, close)
//
// A singleton can live in an app directory: it is compiled when the app is, in the same
// registration as the rest of the app (spec C.18).
QtObject {
    property var assistant: null
    property var shellState: null
    property var intents: null
}
