import QtQuick
import QtQuick.Layouts
import "../controls"
import "../../config"
import "../../theme"
import "../../components"
import "../../services"

// ============================================================================
// Downloads
// ============================================================================
// Everything about the download engine in one place:
//
//   * what the engine is (detected version, or nothing at all),
//   * how to get it - the native install path (pkexec → the desktop's own
//     password dialog) with the manual command as the fallback,
//   * the engine-wide settings: destination, connections per download,
//     parallel downloads, speed cap, and the border HUD.
//
// Settings that the running engine can adopt are pushed to it immediately
// (`apply-settings`), so a change applies to the downloads already queued
// instead of only to the next engine start. The page never installs anything
// without the user answering the system dialog.
SettingsPage {
    id: root

    title: "Downloads"
    subtitle: "The transfer engine, where files land, and how fast they get there"
    zones: [
        { id: "engine", label: "Engine", anchor: engineSection },
        { id: "destination", label: "Folder", anchor: dirField },
        { id: "settings", label: "Settings", anchor: settingsHeader }
    ]

    property bool testMode: false

    // --- Injected state for the offscreen harness (it cannot write Config) ---
    property bool testAriaAvailable: true
    property string testAriaVersion: "1.37.0"
    property bool testAriaInstallable: true
    property string testAriaInstallCommand: "sudo pacman -S aria2"
    property string testInstallState: "idle"
    property string testInstallMessage: ""
    property string testDir: ""
    property int testSplit: 4
    property int testMaxConcurrent: 5
    property int testSpeedLimit: 0
    property bool testBorderEffect: true

    readonly property int spaceMediumVal: (typeof Theme !== "undefined" && Theme.spaceMedium) ? Theme.spaceMedium : 12

    // --- Effective state (Config/DownloadService, or the injected values) ---
    readonly property bool ariaAvailable: testMode
        ? testAriaAvailable
        : ((typeof DownloadService !== "undefined" && DownloadService)
            ? DownloadService.ariaAvailable : true)
    readonly property string ariaVersion: testMode
        ? testAriaVersion
        : ((typeof DownloadService !== "undefined" && DownloadService) ? DownloadService.ariaVersion : "")
    readonly property bool ariaInstallable: testMode
        ? testAriaInstallable
        : ((typeof DownloadService !== "undefined" && DownloadService)
            ? DownloadService.ariaInstallable : false)
    readonly property string ariaInstallCommand: testMode
        ? testAriaInstallCommand
        : ((typeof DownloadService !== "undefined" && DownloadService && DownloadService.ariaInstallCommand)
            ? DownloadService.ariaInstallCommand : "sudo pacman -S aria2")
    readonly property string installState: testMode
        ? testInstallState
        : ((typeof DownloadService !== "undefined" && DownloadService) ? DownloadService.installState : "idle")
    readonly property string installMessage: testMode
        ? testInstallMessage
        : ((typeof DownloadService !== "undefined" && DownloadService) ? DownloadService.installMessage : "")
    readonly property string downloadDir: testMode
        ? testDir
        : ((typeof Config !== "undefined" && Config.downloadsDir) ? Config.downloadsDir : "")
    readonly property int splitParts: testMode
        ? testSplit
        : ((typeof Config !== "undefined" && Config.downloadsSplit) ? Config.downloadsSplit : 4)
    readonly property int parallelDownloads: testMode
        ? testMaxConcurrent
        : ((typeof Config !== "undefined" && Config.downloadsMaxConcurrent) ? Config.downloadsMaxConcurrent : 5)
    readonly property int speedLimitKbps: testMode
        ? testSpeedLimit
        : ((typeof Config !== "undefined" && Config.downloadsSpeedLimit !== undefined)
            ? Config.downloadsSpeedLimit : 0)
    readonly property bool borderEffect: testMode
        ? testBorderEffect
        : ((typeof Config !== "undefined" && Config.downloadsBorderEffect !== undefined)
            ? Config.downloadsBorderEffect : true)

    /// Human-readable form of the cap ("Unlimited" / "2.5 MB/s").
    function speedLimitText(kbps) {
        if (!kbps || kbps <= 0) return "Unlimited";
        return downloadServiceFormat(kbps * 1024) + "/s";
    }

    function downloadServiceFormat(bytesPerSec) {
        if (typeof DownloadService !== "undefined" && DownloadService
                && typeof DownloadService.formatBytes === "function") {
            return DownloadService.formatBytes(bytesPerSec);
        }
        const units = ["B", "KiB", "MiB", "GiB"];
        let value = bytesPerSec;
        let i = 0;
        while (value >= 1024 && i < units.length - 1) {
            value = value / 1024;
            ++i;
        }
        return value.toFixed(1) + " " + units[i];
    }

    // --- The single write path (testable without Config) ---
    function chooseDir(path) {
        if (testMode) { testDir = path; return; }
        Config.setDownloadsDir(path);
        pushToEngine();
    }

    function applySplit(value) {
        // `0` is a real value the user can drag to (and means "one connection",
        // not "the default"): only a non-numeric value falls back.
        const n = Number(value);
        const v = Math.max(1, Math.min(16, Math.round(isNaN(n) ? 4 : n)));
        if (testMode) { testSplit = v; return; }
        Config.setDownloadsSplit(v);
    }

    function applyParallelDownloads(value) {
        const n = Number(value);
        const v = Math.max(1, Math.min(16, Math.round(isNaN(n) ? 5 : n)));
        if (testMode) { testMaxConcurrent = v; return; }
        Config.setDownloadsMaxConcurrent(v);
        pushToEngine();
    }

    function applySpeedLimit(kbps) {
        const raw = Math.max(0, Math.min(10000, Math.round(Number(kbps) || 0)));
        const v = Math.round(raw / 100) * 100;   // steps the engine can honour
        if (testMode) { testSpeedLimit = v; return; }
        Config.setDownloadsSpeedLimit(v);
        pushToEngine();
    }

    function setBorderEffect(enabled) {
        if (testMode) { testBorderEffect = Boolean(enabled); return; }
        Config.setDownloadsBorderEffect(Boolean(enabled));
    }

    function installEngine() {
        if (testMode) {
            installRequests += 1;
            return;
        }
        if (typeof DownloadService !== "undefined" && DownloadService
                && typeof DownloadService.installEngine === "function") {
            DownloadService.installEngine();
        }
    }

    function copyInstallCommand() {
        if (testMode) {
            copyRequests += 1;
            return;
        }
        if (typeof DownloadService !== "undefined" && DownloadService
                && typeof DownloadService.copyToClipboard === "function") {
            DownloadService.copyToClipboard(root.ariaInstallCommand);
        }
    }

    /// A setting the engine adopts runs through one command (`apply-settings`).
    function pushToEngine() {
        if (testMode) return;
        if (typeof DownloadService !== "undefined" && DownloadService
                && typeof DownloadService.applyEngineSettings === "function") {
            DownloadService.applyEngineSettings();
        }
    }

    /// Test / introspection surface.
    property int installRequests: 0
    property int copyRequests: 0
    property alias engineStatusItem: engineStatus
    property alias engineHintItem: engineHint
    property alias installButtonItem: installButton
    property alias installMessageItem: installMessage
    property alias dirFieldItem: dirField
    property alias splitSliderItem: splitSlider
    property alias parallelSliderItem: parallelSlider
    property alias speedSliderItem: speedSlider
    property alias borderToggleItem: borderToggle
    property alias tabHintItem: tabHint

    // ========================================================================
    // Engine
    // ========================================================================
    Rectangle {
        id: engineSection
        Layout.fillWidth: true
        radius: Theme.radiusMedium
        color: Colors.surfaceContainer
        implicitHeight: engineCol.implicitHeight + Theme.padLarge * 2

        ColumnLayout {
            id: engineCol
            anchors.fill: parent
            anchors.margins: Theme.padLarge
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spaceSmall

                MaterialIcon {
                    text: root.ariaAvailable ? "cloud_done" : "cloud_off"
                    size: 20
                    color: root.ariaAvailable ? Colors.primary : Colors.m3onSurfaceVariant
                }

                Text {
                    id: engineStatus
                    Layout.fillWidth: true
                    text: root.ariaAvailable
                        ? ("aria2" + (root.ariaVersion !== "" ? (" " + root.ariaVersion) : "") + " detected")
                        : "aria2 is not installed"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontBodyMedium
                    font.weight: Font.DemiBold
                    color: Colors.m3onSurface
                }

                PillButton {
                    id: installButton
                    visible: !root.ariaAvailable
                    label: root.ariaInstallable ? "Install aria2" : "Copy install command"
                    variant: "filled"
                    onClicked: {
                        if (root.ariaInstallable) root.installEngine();
                        else root.copyInstallCommand();
                    }
                }
            }

            Text {
                id: engineHint
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                visible: !root.ariaAvailable
                text: "Astral Plasma uses aria2 for multi-connection downloads. "
                    + (root.ariaInstallable
                        ? "Installing asks for your password in the system dialog; nothing is installed without your confirmation."
                        : "Install it with your package manager: " + root.ariaInstallCommand)
                font.family: Theme.fontFamily
                font.pixelSize: 12
                color: Colors.m3onSurfaceVariant
                opacity: 0.85
            }

            Text {
                id: installMessage
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                visible: root.installMessage !== ""
                text: root.installMessage
                font.family: Theme.fontFamily
                font.pixelSize: 12
                color: root.installState === "installed"
                    ? Colors.primary
                    : (root.installState === "running" ? Colors.m3onSurfaceVariant : Colors.error)
            }

            Text {
                id: tabHint
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                visible: !root.ariaAvailable
                text: "The Downloads tab stays hidden in the dashboard until the engine is installed — "
                    + "its setting is remembered and applies as soon as aria2 is there."
                font.family: Theme.fontFamily
                font.pixelSize: 12
                color: Colors.m3onSurfaceVariant
                opacity: 0.85
            }
        }
    }

    Item { height: root.spaceMediumVal }

    // ========================================================================
    // Destination
    // ========================================================================
    FolderPathField {
        id: dirField
        title: "Download folder"
        description: "Where new downloads are written. Empty uses aria2's own default (~/Downloads)."
        placeholder: "~/Downloads"
        path: root.downloadDir
        interactive: !root.testMode
        onPathPicked: path => root.chooseDir(path)
    }

    Item { height: root.spaceMediumVal }

    // ========================================================================
    // Engine-wide settings
    // ========================================================================
    SectionHeader {
        id: settingsHeader
        title: "Engine Settings"
        eyebrow: "cap: " + root.speedLimitText(root.speedLimitKbps)
            + " · " + root.parallelDownloads + " parallel"
    }

    Text {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: "Parallel downloads and the speed cap are engine-wide: they are pushed to the running "
            + "engine, so they apply to the downloads already queued."
        font.family: Theme.fontFamily
        font.pixelSize: 13
        color: Colors.m3onSurfaceVariant
        opacity: 0.85
    }

    SettingSlider {
        id: parallelSlider
        Layout.fillWidth: true
        title: "Parallel downloads"
        value: root.parallelDownloads
        min: 1
        max: 16
        onValueModified: value => root.applyParallelDownloads(value)
    }

    SettingSlider {
        id: splitSlider
        Layout.fillWidth: true
        title: "Connections per download"
        value: root.splitParts
        min: 1
        max: 16
        onValueModified: value => root.applySplit(value)
    }

    SettingSlider {
        id: speedSlider
        Layout.fillWidth: true
        title: "Speed limit"
        value: root.speedLimitKbps
        min: 0
        max: 10000
        suffix: root.speedLimitKbps <= 0 ? "" : " KiB/s"
        onValueModified: value => root.applySpeedLimit(value)
    }

    Text {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: "Current cap: " + root.speedLimitText(root.speedLimitKbps)
            + (root.speedLimitKbps <= 0 ? " (0 = unlimited)" : "")
        font.family: Theme.fontFamily
        font.pixelSize: 12
        color: Colors.m3onSurfaceVariant
        opacity: 0.85
    }

    SettingToggle {
        id: borderToggle
        Layout.fillWidth: true
        title: "Download border HUD"
        description: "Show progress and speed around the screen edge while a download is running"
        checked: root.borderEffect
        onToggled: value => root.setBorderEffect(value)
    }

    Item { Layout.fillHeight: true }
}
