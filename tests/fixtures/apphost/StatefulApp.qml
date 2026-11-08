import QtQuick
// A fixture app that consumes the injected contract: state for reads, bus for
// actions. It imports nothing from the kernel, which is the point.
Item {
    id: root
    property var shellState: null
    property var intents: null
    property int stateChanges: 0

    onShellStateChanged: stateChanges++
}
