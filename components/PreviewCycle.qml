import QtQuick

// Serial capture cycle: runs ONE runner invocation at a time across a list of
// keys and restarts from the current `items` on every wrap.
//
// The discipline lives here so a single Process never has two captures in
// flight: the next invocation happens only when the caller reports the
// previous one finished (`advance()`), which WindowService hooks to the
// capture Process's exit. `items` is re-read at wrap, so windows appearing
// while the cycle runs join the rotation without a restart. `interval` paces
// consecutive captures; <= 0 pumps synchronously (deterministic in tests).
Item {
    id: root

    property var items: []
    property var runner: null
    property int interval: 120
    property bool active: false

    property var _queue: []
    property int _index: 0

    signal finishedCycle()

    function _rebuild() {
        const src = items || [];
        const out = [];
        for (let i = 0; i < src.length; i++) {
            const k = src[i];
            if (k === undefined || k === null) continue;
            if (String(k).length === 0) continue;
            out.push(k);
        }
        _queue = out;
    }

    function _pump() {
        if (!active || !runner || _queue.length === 0) return;
        runner(_queue[_index]);
    }

    function _schedule() {
        if (interval > 0) {
            nextTimer.restart();
        } else {
            _pump();
        }
    }

    function start() {
        nextTimer.stop();
        _rebuild();
        _index = 0;
        active = _queue.length > 0;
        if (active) _pump();
    }

    function stop() {
        nextTimer.stop();
        active = false;
        _queue = [];
        _index = 0;
    }

    function advance() {
        if (!active) return;
        _index++;
        if (_index >= _queue.length) {
            finishedCycle();
            _rebuild();
            _index = 0;
            if (_queue.length === 0) {
                active = false;
                return;
            }
        }
        _schedule();
    }

    Timer {
        id: nextTimer
        interval: Math.max(1, root.interval)
        onTriggered: root._pump()
    }
}
