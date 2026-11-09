import QtQuick
import "../modules/Astral/Kernel/Host/AppIntegrations.js" as Integrations

// ============================================================================
// Integration locations: where each app plugs into the shell
// ============================================================================
// An app declares its locations in its manifest; the shell resolves them to the owning app,
// so disabling an app disables *all* of them (tab, dock item, drawer, page, window) instead
// of leaving surfaces that advertise a disabled app (reported as: "when app is disabled, top
// drawer should be disabled too — each app declares the locations to be integrated").
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

    readonly property var entries: [
        { id: "org.astralplasma.ai", enabled: true, integrations: [
            { kind: "dashboardTab", id: "ai" },
            { kind: "dockItem", id: "ai" },
            { kind: "drawer", id: "ai" }] },
        { id: "org.astralplasma.media", enabled: true, integrations: [
            { kind: "dashboardTab", id: "media" }] },
        { id: "org.astralplasma.downloads", enabled: false, integrations: [
            { kind: "dashboardTab", id: "downloads" },
            { kind: "settingsPage", id: "downloads" }] }
    ]

    Component.onCompleted: {
        // ---- the map ---------------------------------------------------------
        let map = Integrations.build(testRoot.entries);
        assert(map["dashboardTab:ai"] === "org.astralplasma.ai", "a tab resolves to its app");
        assert(map["dockItem:ai"] === "org.astralplasma.ai", "so does a dock item");
        assert(map["drawer:ai"] === "org.astralplasma.ai", "and a drawer");
        assert(map["dashboardTab:media"] === "org.astralplasma.media", "each app keeps its own");
        assert(map["dashboardTab:downloads"] === undefined,
            "a disabled app provides nothing: its declarations are dropped");
        assert(map["settingsPage:downloads"] === undefined, "no location survives a disable");
        assert(Integrations.providerOf(map, "dockItem", "nobody") === "", "unknown is unowned");

        // ---- filtering a configured list (the dashboard strip) ---------------
        const configured = ["dashboard", "media", "performance", "downloads", "ai"];
        const shown = Integrations.providedOnly(map, "dashboardTab", configured);
        assert(JSON.stringify(shown) === JSON.stringify(["media", "ai"]),
            "only tabs an enabled app provides survive the filter: " + JSON.stringify(shown));

        // `Config.dashboardTabs` describes tabs, it does not list ids: the filter must read
        // the id out of the descriptor and keep the descriptor's shape.
        const descriptors = [
            { id: "dashboard", label: "Dashboard", enabled: true },
            { id: "media", label: "Media", enabled: true },
            { id: "downloads", label: "Downloads", enabled: true },
            { id: "ai", label: "AI Quotas", enabled: true },
            { id: "performance", label: "Performance", enabled: false }
        ];
        const keptDescriptors = Integrations.providedOnly(map, "dashboardTab", descriptors);
        assert(keptDescriptors.length === 2, "only provided tabs survive: " + keptDescriptors.length);
        assert(keptDescriptors[0].label === "Media", "the descriptor keeps its shape");
        assert(keptDescriptors[1].id === "ai", "and the rest of its fields");
        assert(Integrations.providedOnly(map, "dashboardTab", ["media"])[0] === "media",
            "plain id lists still work");

        // An app disabling itself takes its whole row of locations with it.
        const disabled = testRoot.entries.map(function (entry) {
            if (entry.id !== "org.astralplasma.ai") return entry;
            return { id: entry.id, enabled: false, integrations: entry.integrations };
        });
        map = Integrations.build(disabled);
        assert(!Integrations.isProvided(map, "dashboardTab", "ai"), "tab gone");
        assert(!Integrations.isProvided(map, "dockItem", "ai"), "dock item gone");
        assert(!Integrations.isProvided(map, "drawer", "ai"), "drawer gone");

        // ---- tolerance -------------------------------------------------------
        assert(Integrations.build(null)["x:y"] === undefined, "no entries, no map");
        assert(Integrations.build([null, { id: "a.b" }])["x:y"] === undefined,
            "an entry without declarations provides nothing");
        const dupes = Integrations.build([
            { id: "a.one", enabled: true, integrations: [{ kind: "dashboardTab", id: "same" }] },
            { id: "a.two", enabled: true, integrations: [{ kind: "dashboardTab", id: "same" }] }
        ]);
        assert(dupes["dashboardTab:same"] === "a.one",
            "the first declaration wins, so one surface has one owner");

        console.log("PASS: All app integration tests passed!");
        Qt.exit(0);
    }
}
