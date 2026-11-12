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

        // ---- a hit says what it is -------------------------------------------
        const repoHit = { kind: "repository", source: "vercel-labs/agent-skills", name: "agent-skills", installs: 2410 };
        const skillHit = { kind: "skill", source: "vercel-labs/agent-skills", name: "web-design-guidelines", installs: 842309, description: "UI review" };
        assert(Model.hitBadge(repoHit) === "repo", "a GitHub hit is a repository");
        assert(Model.hitBadge(skillHit) === "skill", "a skills.sh hit is one skill");
        assert(Model.hitTitle(repoHit) === "vercel-labs/agent-skills", "the repo is the title of a repo hit");
        assert(Model.hitTitle(skillHit) === "web-design-guidelines",
            "the skill is the title of a skill hit, not its repository");
        assert(Model.hitSubtitle(skillHit).indexOf("vercel-labs/agent-skills") >= 0,
            "and the repository is context: " + Model.hitSubtitle(skillHit));
        assert(Model.installTarget(repoHit).skills.length === 0, "a repo hit installs the whole repo");
        assert(Model.installTarget(skillHit).skills[0] === "web-design-guidelines",
            "a skill hit installs only that skill");
        assert(Model.installTarget(skillHit).source === "vercel-labs/agent-skills", "from its repository");
        assert(JSON.stringify(Model.installTarget(null)) === JSON.stringify({ source: "", skills: [] }),
            "no hit, no install");

        // ---- a hit describes itself usefully --------------------------------
        assert(Model.hitDetail({ description: "UI review" }) === "UI review", "the description wins");
        assert(Model.hitDetail({ installs: 2410 }) === "2410 installs", "else the install count");
        assert(Model.hitDetail({}) === "", "and nothing is not a lie");

        // ---- MCP server and agent registration ------------------------------
        assert(Model.mcpState(null) === "checking", "a missing probe is checking, not down");
        assert(Model.mcpStateLabel({ state: "up" }) === "Up", "an up server reads Up");
        assert(Model.mcpStateLabel({ state: "wrong-service" }) === "Wrong service",
            "a port owned by another service is named");
        assert(Model.mcpStateIcon({ state: "down" }) === "warning", "a down server is a warning");
        assert(Model.mcpDetail({ state: "up", tools: ["a", "b"], protocol: "2026-07-28" }) ===
            "2 tools · 2026-07-28", "the detail counts the real tools and protocol");
        assert(Model.agentStateLabel({ installed: true, configured: true }) === "Configured",
            "a configured agent reads Configured");
        assert(Model.agentStateLabel({ installed: true, configured: false }) === "Not configured",
            "an installed agent without the entry is Not configured");
        assert(Model.agentStateLabel({ installed: false, configured: false }) === "Not installed",
            "an absent agent is Not installed");
        assert(Model.mcpSummary({ installedCount: 3, configuredCount: 2 }) ===
            "2 of 3 installed agents configured", "the summary is the installed-agent count");

        // ---- the contract with the daemon -----------------------------------
        const service = readLocalFile("../modules/Astral/Kernel/services/SkillsService.qml");
        assert(service.indexOf('"skills", "list", "--json"') >= 0, "the list comes from the daemon");
        assert(service.indexOf('"install", String(source), "--accept"') >= 0,
            "installing passes --accept explicitly");
        assert(service.indexOf('"skills", "doctor", "--json"') >= 0, "the doctor is the daemon's");
        assert(service.indexOf('enabled ? "enable" : "disable"') >= 0, "toggles go through the daemon");
        assert(service.indexOf('"import", "--apply"') >= 0, "adoption is explicit");
        assert(service.indexOf("root.results = [];") >= 0,
            "switching catalogs drops the previous list instead of showing it under the new tab");
        assert(service.indexOf('"skills", "mcp", "status", "--json"') >= 0,
            "the MCP status comes from the daemon's probe");
        assert(service.indexOf('"mcp", "uninstall", "--agent"') >= 0,
            "uninstalling removes the agent's config entry through the daemon");
        assert(service.indexOf('"mcp", "install", "--agent"') >= 0,
            "installing registers the agent's config entry through the daemon");

        const app = readLocalFile("../modules/Astral/Apps/Skills/SkillsApp.qml");
        assert(app.indexOf("Model.hitBadge(modelData)") >= 0,
            "the row labels what kind of hit it is");
        assert(app.indexOf("root.activeSource") >= 0,
            "the chip highlight follows the service, so there is one owner of the selected source");
        assert(app.indexOf("property var skills: null") >= 0,
            "the app receives a port, not a kernel import");
        assert(app.indexOf("Kernel/services") === -1, "and never reaches the kernel's services");
        assert(app.indexOf('Model.sourceSummary(modelData)') >= 0,
            "the row summary is the tested model, not an inline expression");
        assert(app.indexOf("root.skills.uninstallMcp(modelData.id)") >= 0,
            "the agent row can remove its own MCP entry");
        assert(app.indexOf("root.skills.installMcp(modelData.id)") >= 0,
            "and register an installed agent that lacks it");
        assert(app.indexOf("pendingMcpRemoval") >= 0,
            "removal asks for a second, confirming click");
        assert(app.indexOf("property alias findAnchor") >= 0,
            "the Find zone points at a real anchor");
        assert(app.indexOf("property alias mcpAnchor") >= 0,
            "the MCP zone points at a real anchor");
        assert(app.indexOf("property alias installedAnchor") >= 0,
            "the Installed zone points at a real anchor");

        const page = readLocalFile("../settings_gui/pages/SkillsPage.qml");
        assert(page.indexOf("skills: SkillsService") >= 0, "the page injects the service as the port");
        assert(page.indexOf('{ id: "find", label: "Find"') >= 0, "the page exposes a Find zone");
        assert(page.indexOf('{ id: "mcp", label: "MCP server"') >= 0, "the page exposes an MCP zone");
        assert(page.indexOf('{ id: "installed", label: "Installed"') >= 0, "the page exposes an Installed zone");
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
