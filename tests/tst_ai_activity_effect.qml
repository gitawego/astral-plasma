import QtQuick
import "../theme"
import "../config"

// ============================================================================
// AI Agent Model Activity & Theme Effect Unit Tests
// ============================================================================
// Verifies:
// 1. Model activity ingestion, provider mapping (MiMo, Muse Spark, Grok, Ollama Cloud, Claude, etc.)
// 2. Dynamic pulse frequency modulation based on request rate (faster under load, calm when steady)
// 3. Graceful idle decay with model memory retention (no flickering back to generic icons)
// 4. Zero-idle-CPU contract (animations must disable when idle)
// 5. Dock AI pill and Capsule Rim source contracts in DockStatusIcons and UnifiedShell
Item {
    id: testRoot
    width: 800
    height: 600

    function readLocalFile(relUrl) {
        const xhr = new XMLHttpRequest();
        const bust = (relUrl.indexOf("?") < 0 ? "?v=" : "&v=") + Date.now() + Math.random();
        xhr.open("GET", Qt.resolvedUrl(relUrl) + bust, false);
        xhr.send();
        return xhr.responseText || "";
    }

    function assert(cond, msg) {
        if (!cond) {
            console.log("FAIL: " + msg);
            console.error("FAIL: " + msg);
            Qt.exit(1);
            throw new Error(msg);
        }
        return true;
    }

    // Mirror of services/AiActivityService.qml logic for deterministic offscreen execution
    QtObject {
        id: activityModel

        property string agent: "idle"
        property string model: ""
        property string displayName: "AI Agent"
        property color brandColor: "#9bcbfb"
        property string brandIcon: "auto_awesome"
        property bool isActive: false
        property real intensity: 0.0
        property real requestRate: 0.0

        readonly property int pulseDuration: Math.max(900, Math.min(2600, 2400 - Math.round(activityModel.requestRate * 180)))
        readonly property bool effectEnabled: (typeof Config !== "undefined" && Config.modelActivityEffect !== undefined)
            ? Config.modelActivityEffect
            : true

        function applyActivity(data) {
            if (!data) return;
            if (data.agent !== undefined) activityModel.agent = data.agent;
            if (data.model !== undefined) activityModel.model = data.model;
            if (data.display_name !== undefined) activityModel.displayName = data.display_name;
            if (data.brand_color !== undefined && data.brand_color) activityModel.brandColor = data.brand_color;
            if (data.brand_icon !== undefined && data.brand_icon) activityModel.brandIcon = data.brand_icon;
            if (data.is_active !== undefined) activityModel.isActive = Boolean(data.is_active);
            if (data.intensity !== undefined) activityModel.intensity = Number(data.intensity);
            if (data.request_rate !== undefined) activityModel.requestRate = Number(data.request_rate);
        }
    }

    Timer {
        interval: 50
        running: true
        repeat: false
        onTriggered: runTests()
    }

    function runTests() {
        console.log("RUNNING: AI Agent Model Activity & Theme Effect Unit Tests");

        // ---- 1. MiMo (Xiaomi) Model Ingestion ----
        activityModel.applyActivity({
            agent: "mimo",
            model: "opencode-go/mimo-v2.6-flash",
            display_name: "MiMo 2.6 Flash",
            brand_color: "#FF6900",
            brand_icon: "devices",
            is_active: true,
            intensity: 1.0,
            request_rate: 2.5
        });

        assert(activityModel.agent === "mimo", "Agent should be mimo");
        assert(activityModel.displayName === "MiMo 2.6 Flash", "Display name should be MiMo 2.6 Flash");
        assert(Qt.colorEqual(activityModel.brandColor, "#FF6900"), "Brand color should be #FF6900 (Xiaomi Vibrant Orange)");
        assert(activityModel.brandIcon === "devices", "Brand icon should be devices");
        assert(activityModel.isActive === true, "isActive should be true");
        assert(activityModel.requestRate === 2.5, "requestRate should be 2.5 req/min");
        assert(activityModel.pulseDuration === 1950, "pulseDuration should be 1950ms at 2.5 req/min (got " + activityModel.pulseDuration + ")");

        // ---- 2. Muse Spark (Meta) Model Ingestion ----
        activityModel.applyActivity({
            agent: "meta",
            model: "opencode-go/muse-spark-1.2-contributor",
            display_name: "Muse Spark 1.2",
            brand_color: "#0081FB",
            brand_icon: "flare",
            is_active: true,
            intensity: 1.0,
            request_rate: 1.0
        });

        assert(activityModel.agent === "meta", "Agent should be meta");
        assert(activityModel.displayName === "Muse Spark 1.2", "Display name should be Muse Spark 1.2");
        assert(Qt.colorEqual(activityModel.brandColor, "#0081FB"), "Brand color should be #0081FB (Meta Electric Blue)");
        assert(activityModel.brandIcon === "flare", "Brand icon should be flare");
        assert(activityModel.pulseDuration === 2220, "pulseDuration should be 2220ms at 1.0 req/min (got " + activityModel.pulseDuration + ")");

        // ---- 3. Grok (x.com) Model Ingestion ----
        activityModel.applyActivity({
            agent: "grok",
            model: "grok-3",
            display_name: "Grok 3 (x.com)",
            brand_color: "#EF4444",
            brand_icon: "rocket_launch",
            is_active: true,
            intensity: 1.0,
            request_rate: 5.0
        });

        assert(activityModel.agent === "grok", "Agent should be grok");
        assert(Qt.colorEqual(activityModel.brandColor, "#EF4444"), "Brand color should be #EF4444 (Grok Crimson)");
        assert(activityModel.brandIcon === "rocket_launch", "Brand icon should be rocket_launch");
        assert(activityModel.pulseDuration === 1500, "pulseDuration should be 1500ms at 5.0 req/min (got " + activityModel.pulseDuration + ")");

        // ---- 4. Ollama Cloud Model Ingestion ----
        activityModel.applyActivity({
            agent: "ollama",
            model: "ollama-cloud/deepseek-v4-flash",
            display_name: "Ollama (DeepSeek V4)",
            brand_color: "#F59E0B",
            brand_icon: "cloud",
            is_active: true,
            intensity: 1.0,
            request_rate: 0.5
        });

        assert(activityModel.agent === "ollama", "Agent should be ollama");
        assert(Qt.colorEqual(activityModel.brandColor, "#F59E0B"), "Brand color should be #F59E0B (Ollama Warm Amber)");
        assert(activityModel.brandIcon === "cloud", "Brand icon should be cloud");
        assert(activityModel.pulseDuration === 2310, "pulseDuration should be 2310ms at 0.5 req/min (got " + activityModel.pulseDuration + ")");

        // High load clamp test: 12 req/min clamped to 900ms minimum
        activityModel.applyActivity({
            request_rate: 12.0
        });
        assert(activityModel.pulseDuration === 900, "pulseDuration should clamp to 900ms at high load");

        // ---- 5. Idle Decay & Memory Retention ----
        activityModel.applyActivity({
            is_active: false,
            intensity: 0.0,
            request_rate: 0.0
        });

        assert(activityModel.isActive === false, "isActive should be false in idle state");
        assert(activityModel.intensity === 0.0, "intensity should decay to 0.0");
        assert(activityModel.brandIcon === "cloud", "brandIcon should remember last active model");
        assert(Qt.colorEqual(activityModel.brandColor, "#F59E0B"), "brandColor should remember last active model color");

        // ---- 6. Source Contract: services/AiActivityService.qml ----
        const serviceSrc = readLocalFile("../services/AiActivityService.qml");
        assert(serviceSrc.length > 500, "AiActivityService.qml must be readable");
        assert(/pragma Singleton/.test(serviceSrc), "AiActivityService must be a Singleton");
        assert(/command:\s*\[root\.daemonBin,\s*"ai",\s*"activity"\]/.test(serviceSrc),
            "AiActivityService must query daemonBin ['ai', 'activity'] on startup");
        assert(/applyActivity\(data\)/.test(serviceSrc),
            "AiActivityService must implement applyActivity");

        // ---- 7. Source Contract: dock/components/DockStatusIcons.qml ----
        const dockSrc = readLocalFile("../dock/components/DockStatusIcons.qml");
        assert(dockSrc.length > 1000, "DockStatusIcons.qml must be readable");
        assert(/id:\s*aiAura/.test(dockSrc),
            "DockStatusIcons must declare aiAura for breathing halo effect");
        assert(/AiActivityService\.brandColor/.test(dockSrc),
            "DockStatusIcons must bind halo and background to AiActivityService.brandColor");
        assert(/running:\s*Config\.modelActivityEffect\s*&&\s*\(typeof AiActivityService\s*!==\s*"undefined"\)\s*&&\s*AiActivityService\.isActive/.test(dockSrc),
            "DockStatusIcons must guarantee 0% idle CPU by running animation only when active");

        // ---- 8. Source Contract: shell/UnifiedShell.qml ----
        const shellSrc = readLocalFile("../shell/UnifiedShell.qml");
        assert(shellSrc.length > 1000, "UnifiedShell.qml must be readable");
        assert(/id:\s*aiCapsuleRim/.test(shellSrc),
            "UnifiedShell must declare aiCapsuleRim 1px breathing hairline");
        assert(/running:\s*Config\.modelActivityEffect\s*&&\s*\(typeof AiActivityService\s*!==\s*"undefined"\)\s*&&\s*AiActivityService\.isActive/.test(shellSrc),
            "UnifiedShell aiCapsuleRim animation must run only when active to guarantee 0% idle CPU");

        // ---- 9. Source Contract: services/WindowService.qml event routing ----
        const winServiceSrc = readLocalFile("../services/WindowService.qml");
        assert(winServiceSrc.length > 1000, "WindowService.qml must be readable");
        assert(/data\.msg_type\s*===\s*"ai_activity"/.test(winServiceSrc),
            "WindowService must route ai_activity IPC events from daemon to AiActivityService");

        // ---- 10. Config Reactivity ----
        const configSrc = readLocalFile("../config/Config.qml");
        assert(/property\s+bool\s+modelActivityEffect:/.test(configSrc),
            "Config.qml must declare modelActivityEffect property");

        console.log("PASS: All AI Agent Model Activity Unit Tests passed successfully!");
        Qt.exit(0);
    }
}
