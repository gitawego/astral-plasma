import QtQuick
import "../modules/Astral/Apps/Skills/SkillsModel.js" as Model

// ============================================================================
// Skills app: presentation logic and the contracts it relies on
// ============================================================================
// The manager's behaviour lives in the daemon (tested in Rust); this suite covers what the
// surface itself decides — how a state reads, how a repository is summarised, what the search
// box does with two characters — and the wiring the page cannot get wrong: the app receives a
// port, never a kernel import, and every action goes through `astral-plasma skills …`.
Item {
    id: testRoot
    width: 400
    height: 300

    function assert(condition, message) {
        if (!condition) {
            console.error("FAIL: " + message);
            Qt.exit(1);
            throw new Error(message);
        }
    }

    function readLocalFile(relUrl) {
        const xhr = new XMLHttpRequest();
        xhr.open("GET", Qt.resolvedUrl(relUrl) + "?v=" + Date.now(), false);
        xhr.send();
        return xhr.responseText || "";
    }

    readonly property var source: ({
        id: "local-mine",
        label: "mine",
        spec: "~/my-skills",
        enabled: true,
        enabledCount: 2,
        skills: [
            { id: "alpha", state: "linked", origin: "local · live" },
            { id: "beta", state: "disabled", origin: "local · live" },
            { id: "gamma", state: "linked", origin: "main@abc1234" }
        ]
    })

    Component.onCompleted: {
        // ---- states and summaries -------------------------------------------
        assert(Model.stateLabel({ state: "linked" }) === "Enabled", "a linked skill reads Enabled");
        assert(Model.stateLabel({ state: "disabled" }) === "Disabled", "a disabled skill says so");
        assert(Model.stateLabel(null) === "Unknown", "no skill is Unknown, not a crash");
        assert(Model.sourcePercent(testRoot.source) === 67, "2 of 3 rounds to 67%");
        assert(Model.sourcePercent({ skills: [] }) === 0, "an empty repository is 0%");
        assert(Model.sourceSummary(testRoot.source) === "2 of 3 enabled",
            "a repository row states the count: " + Model.sourceSummary(testRoot.source));

        // A QVariantList proxy is not a JS Array: the row must still count it.
        const proxy = { length: 2, 0: { state: "linked" }, 1: { state: "disabled" } };
        assert(Model.sourceSummary({ skills: proxy }) === "1 of 2 enabled",
            "a list proxy is counted: " + Model.sourceSummary({ skills: proxy }));

        // ---- the search box has a threshold ---------------------------------
        assert(Model.shouldSearch("a") === false, "one character is not a search");
        assert(Model.shouldSearch(" ab ") === true, "two characters are");
        assert(Model.shouldSearch("") === false, "and an empty box never queries");
        assert(Model.shouldSearch(null) === false, "nor does a missing query");

        // ---- findings group by kind -----------------------------------------
        const grouped = Model.groupFindings([
            { kind: "dangling", path: "/a" },
            { kind: "unmanaged", path: "/b" },
            { kind: "dangling", path: "/c" }
        ]);
        assert(grouped.length === 2, "two kinds, two groups");
        assert(grouped[0].kind === "dangling" && grouped[0].items.length === 2, "both dangling findings");
        assert(Model.groupFindings(null).length === 0, "no findings, no groups");

        // ---- a hit describes itself usefully --------------------------------
        assert(Model.hitDetail({ description: "UI review" }) === "UI review", "the description wins");
        assert(Model.hitDetail({ installs: 2410 }) === "2410 installs", "else the install count");
        assert(Model.hitDetail({}) === "", "and nothing is not a lie");

        // ---- the contract with the daemon -----------------------------------
        const service = readLocalFile("../modules/Astral/Kernel/services/SkillsService.qml");
        assert(service.indexOf('"skills", "list", "--json"') >= 0, "the list comes from the daemon");
        assert(service.indexOf('"install", String(source), "--accept"') >= 0,
            "installing passes --accept explicitly");
        assert(service.indexOf('"skills", "doctor", "--json"') >= 0, "the doctor is the daemon's");
        assert(service.indexOf('enabled ? "enable" : "disable"') >= 0, "toggles go through the daemon");
        assert(service.indexOf('"import", "--apply"') >= 0, "adoption is explicit");

        const app = readLocalFile("../modules/Astral/Apps/Skills/SkillsApp.qml");
        assert(app.indexOf("property var skills: null") >= 0,
            "the app receives a port, not a kernel import");
        assert(app.indexOf("Kernel/services") === -1, "and never reaches the kernel's services");
        assert(app.indexOf('Model.sourceSummary(modelData)') >= 0,
            "the row summary is the tested model, not an inline expression");

        const page = readLocalFile("../settings_gui/pages/SkillsPage.qml");
        assert(page.indexOf("skills: SkillsService") >= 0, "the page injects the service as the port");
        assert(page.indexOf('root.integrations["settingsPage:skills"]') >= 0,
            "and hides itself when the app is disabled");
        assert(readLocalFile("../shell.qml").indexOf("integrations: AppStates.integrations") >= 0,
            "the shell feeds the settings window with the integration map");

        const hub = readLocalFile("../settings_gui/NexusHub.qml");
        assert(hub.indexOf('{ id: "skills", label: "Skills"') >= 0, "the rail has a Skills entry");
        assert(hub.indexOf("visibleSections") >= 0,
            "the rail is filtered by the integrations an enabled app declares");

        const manifest = JSON.parse(readLocalFile("../modules/Astral/Apps/Skills/manifest.json"));
        assert(manifest.id === "org.astralplasma.skills", "the app id");
        assert(manifest.integrations.some(function (i) { return i.kind === "settingsPage" && i.id === "skills"; }),
            "the app declares the page it integrates with");

        console.log("PASS: All Skills app tests passed!");
        Qt.exit(0);
    }
}
