pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../config"

// ============================================================================
// SkillsService — the agent-skills manager, as the daemon owns it
// ============================================================================
// The Skills page and the Skills app render state and offer actions; they do not
// implement install policy. Everything here is the daemon's own vocabulary:
//
//   `astral-plasma skills list --json`     -> [{ id, label, spec, enabled, skills: [...] }]
//   `skills search <q> [--source …]`       -> [{ source, name, description, installs }]
//   `skills install <source> --accept`     -> link farm, ledger, store
//   `skills enable|disable <skill>[@src]`  -> link presence, ledger state
//   `skills remove --source <id>`          -> unlink + record + GC
//   `skills doctor --json`                 -> drift, dangling, unmanaged
//
// One short-lived process per action, then a refresh: the ledger is the single
// source of truth, so the UI never patches its own list optimistically.
Singleton {
    id: root

    property var sources: []
    property var findings: []
    property var results: []
    property bool busy: false
    property string lastError: ""
    property string lastQuery: ""
    /// True once a list has been read, so the page can tell "empty" from "not loaded".
    property bool loaded: false

    readonly property string bin: Paths.daemonBin

    readonly property int skillCount: {
        let count = 0;
        for (let index = 0; index < sources.length; index++) {
            count += (sources[index].skills || []).length;
        }
        return count;
    }
    readonly property int enabledSkillCount: {
        let count = 0;
        for (let index = 0; index < sources.length; index++) {
            count += Number(sources[index].enabledCount || 0);
        }
        return count;
    }
    readonly property int problemCount: findings.length
    readonly property bool hasSources: sources.length > 0

    function refresh() {
        root.busy = true;
        root.lastError = "";
        listProc.running = false;
        listProc.running = true;
    }

    function search(query) {
        const text = String(query || "").trim();
        if (text.length === 0) {
            root.results = [];
            return;
        }
        root.lastQuery = text;
        root.busy = true;
        root.lastError = "";
        searchProc.command = [root.bin, "skills", "search", text, "--source", root.searchSource, "--json"];
        searchProc.running = false;
        searchProc.running = true;
    }

    /// `github` (repository search) or `skills.sh` (the catalog's own public search).
    property string searchSource: "github"

    function setSearchSource(source) {
        root.searchSource = source;
        if (root.lastQuery.length > 0) root.search(root.lastQuery);
    }

    function install(source, skills) {
        root.lastError = "";
        const args = [root.bin, "skills", "install", String(source), "--accept", "--json"];
        for (let index = 0; index < (skills || []).length; index++) {
            args.push("--skill", String(skills[index]));
        }
        actionProc.command = args;
        root.busy = true;
        actionProc.running = false;
        actionProc.running = true;
    }

    function addSource(input, ref) {
        root.lastError = "";
        const args = [root.bin, "skills", "source", "add", String(input)];
        if (ref && String(ref).length > 0) args.push("--ref", String(ref));
        actionProc.command = args;
        root.busy = true;
        actionProc.running = false;
        actionProc.running = true;
    }

    function setSkillEnabled(sourceId, skill, enabled) {
        root.lastError = "";
        actionProc.command = [
            root.bin, "skills", enabled ? "enable" : "disable",
            String(skill) + "@" + String(sourceId)
        ];
        root.busy = true;
        actionProc.running = false;
        actionProc.running = true;
    }

    function setSourceEnabled(sourceId, enabled) {
        root.lastError = "";
        actionProc.command = [
            root.bin, "skills", enabled ? "enable" : "disable", "--source", String(sourceId)
        ];
        root.busy = true;
        actionProc.running = false;
        actionProc.running = true;
    }

    function updateSource(sourceId) {
        root.lastError = "";
        actionProc.command = [root.bin, "skills", "update", "--source", String(sourceId), "--json"];
        root.busy = true;
        actionProc.running = false;
        actionProc.running = true;
    }

    function removeSource(sourceId, purge) {
        root.lastError = "";
        const args = [root.bin, "skills", "remove", "--source", String(sourceId)];
        if (purge) args.push("--purge");
        actionProc.command = args;
        root.busy = true;
        actionProc.running = false;
        actionProc.running = true;
    }

    /// Put a source back one commit (the store keeps the previous version, D11).
    function rollbackSource(sourceId) {
        root.lastError = "";
        actionProc.command = [root.bin, "skills", "rollback", "--source", String(sourceId), "--json"];
        root.busy = true;
        actionProc.running = false;
        actionProc.running = true;
    }

    /// Items recoverable from the trash (replaced copies, adopted farms).
    property var trash: []

    function refreshTrash() {
        trashProc.running = false;
        trashProc.running = true;
    }

    function restoreTrash(name) {
        root.lastError = "";
        actionProc.command = [root.bin, "skills", "trash", "restore", String(name)];
        root.busy = true;
        actionProc.running = false;
        actionProc.running = true;
    }

    function runDoctor() {
        doctorProc.running = false;
        doctorProc.running = true;
    }

    /// Adopt an existing `npx skills` farm (dry-run first is the CLI's default; the page
    /// asks for confirmation before calling this).
    function adoptExisting() {
        root.lastError = "";
        actionProc.command = [root.bin, "skills", "import", "--apply", "--json"];
        root.busy = true;
        actionProc.running = false;
        actionProc.running = true;
    }

    function stateLabel(skill) {
        return skill && skill.state === "linked" ? "Enabled" : "Disabled";
    }

    function originLabel(source) {
        return source ? String(source.spec || "") : "";
    }

    function sourcePercent(source) {
        const total = (source && source.skills) ? source.skills.length : 0;
        if (total === 0) return 0;
        return Math.round(100 * Number(source.enabledCount || 0) / total);
    }

    // The ledger changes from outside this page too: the CLI, a script, an agent. Watching it
    // keeps the list honest without polling (the same pattern as the apps registry).
    FileView {
        id: ledgerWatch
        path: Paths.skillsLedgerPath
        watchChanges: true
        // `fileChanged` only announces; `reload()` is what re-reads, and `loaded` follows it.
        onFileChanged: ledgerWatch.reload()
        onLoaded: root.refresh()
    }

    Process {
        id: listProc
        command: [root.bin, "skills", "list", "--json"]

        stdout: StdioCollector {
            onStreamFinished: {
                root.busy = false;
                const text = this.text.trim();
                if (text.length === 0) return;
                try {
                    const parsed = JSON.parse(text);
                    root.sources = Array.isArray(parsed) ? parsed : [];
                    root.loaded = true;
                } catch (error) {
                    root.lastError = "could not read the skill list: " + error;
                }
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                const text = this.text.trim();
                if (text.length > 0) {
                    root.busy = false;
                    root.lastError = text.split("\n").pop();
                }
            }
        }
    }

    Process {
        id: searchProc

        stdout: StdioCollector {
            onStreamFinished: {
                root.busy = false;
                const text = this.text.trim();
                if (text.length === 0) return;
                try {
                    const parsed = JSON.parse(text);
                    root.results = Array.isArray(parsed) ? parsed : [];
                } catch (error) {
                    root.lastError = "could not read the search results: " + error;
                }
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                const text = this.text.trim();
                if (text.length > 0) {
                    root.busy = false;
                    // A refusal (skills.sh without a token) is information, not noise.
                    root.lastError = text.split("\n").pop();
                }
            }
        }
    }

    Process {
        id: trashProc
        command: [root.bin, "skills", "trash", "--json"]

        stdout: StdioCollector {
            onStreamFinished: {
                const text = this.text.trim();
                root.trash = [];
                if (text.length === 0) return;
                try {
                    const parsed = JSON.parse(text);
                    root.trash = Array.isArray(parsed) ? parsed : [];
                } catch (error) {
                    root.trash = [];
                }
            }
        }
    }

    Process {
        id: actionProc

        stdout: StdioCollector {
            onStreamFinished: {
                root.results = [];
                root.refresh();
                root.runDoctor();
                root.refreshTrash();
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                const text = this.text.trim();
                if (text.length > 0) {
                    root.busy = false;
                    root.lastError = text.split("\n").pop();
                }
            }
        }
    }

    Process {
        id: doctorProc
        command: [root.bin, "skills", "doctor", "--json"]

        stdout: StdioCollector {
            onStreamFinished: {
                const text = this.text.trim();
                if (text.length === 0) return;
                try {
                    const parsed = JSON.parse(text);
                    root.findings = Array.isArray(parsed) ? parsed : [];
                } catch (error) {
                    root.findings = [];
                }
            }
        }
    }
}
