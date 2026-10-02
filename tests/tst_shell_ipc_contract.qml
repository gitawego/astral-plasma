import QtQuick

// ============================================================================
// Shell IPC contract
// ============================================================================
// Quickshell's `IpcHandler` is how the desktop entries, the daemon and the CLI
// reach the running shell (`quickshell ipc -p <dir> call <target> <function>`).
// It has two hard limits that fail *quietly*:
//
//   * a function may take at most 10 arguments - any more and Quickshell
//     refuses to expose it at all, logging only "Error parsing function ...
//     can only have 10 arguments" at startup, so the action simply does
//     nothing when a caller tries it;
//   * a function needs a `target:` to be addressable.
//
// Both are asserted here against the real `shell.qml`, because a silently
// unavailable action is indistinguishable from a broken keybinding.
Item {
    id: testRoot
    width: 800
    height: 600

    /// Quickshell's IPC arity limit.
    readonly property int ipcArgumentLimit: 10

    function readLocalFile(relUrl) {
        const xhr = new XMLHttpRequest();
        const bust = (relUrl.indexOf("?") < 0 ? "?v=" : "&v=") + Date.now() + Math.random();
        xhr.open("GET", Qt.resolvedUrl(relUrl) + bust, false);
        xhr.send();
        return xhr.responseText || "";
    }

    function assert(condition, message) {
        if (!condition) {
            console.error("FAIL: " + message);
            Qt.exit(1);
            throw new Error(message);
        }
    }

    /// Extract every `IpcHandler { ... }` block with brace matching.
    function ipcHandlerBlocks(source) {
        const blocks = [];
        const marker = "IpcHandler";
        let index = source.indexOf(marker);
        while (index >= 0) {
            const open = source.indexOf("{", index);
            if (open < 0) break;
            let depth = 0;
            let end = -1;
            for (let i = open; i < source.length; ++i) {
                const ch = source[i];
                if (ch === "{") depth++;
                else if (ch === "}") {
                    depth--;
                    if (depth === 0) { end = i; break; }
                }
            }
            if (end < 0) break;
            blocks.push(source.substring(open, end + 1));
            index = source.indexOf(marker, end + 1);
        }
        return blocks;
    }

    Timer {
        interval: 50
        running: true
        repeat: false
        onTriggered: runTests()
    }

    function runTests() {
        console.log("RUNNING: Shell IPC Contract");

        const shell = readLocalFile("../shell.qml");
        assert(shell.length > 1000, "shell.qml must be readable by the harness");

        const blocks = ipcHandlerBlocks(shell);
        assert(blocks.length >= 5,
            "shell.qml must expose its IPC handlers, found " + blocks.length);

        let functions = 0;
        for (let i = 0; i < blocks.length; ++i) {
            const block = blocks[i];
            assert(/target\s*:/.test(block),
                "every IpcHandler needs a target, got block " + (i + 1) + ":\n" + block.substring(0, 120));

            const pattern = /function\s+([A-Za-z_$][\w$]*)\s*\(([^)]*)\)/g;
            let match;
            while ((match = pattern.exec(block)) !== null) {
                const name = match[1];
                const params = match[2].trim();
                const count = params.length === 0 ? 0 : params.split(",").length;
                functions++;
                assert(count <= testRoot.ipcArgumentLimit,
                    "IPC function \"" + name + "\" takes " + count + " arguments; Quickshell "
                    + "silently drops any function above " + testRoot.ipcArgumentLimit
                    + " arguments, so the action can never be invoked");
            }
        }

        assert(functions >= 10,
            "the IPC surface must still be there (found " + functions + " functions)");

        console.log("PASS: Shell IPC Contract");
        Qt.exit(0);
    }
}
