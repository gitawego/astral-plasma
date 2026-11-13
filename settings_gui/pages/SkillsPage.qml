import "../../modules/Astral/Apps/Skills"
import "../../modules/Astral/Kernel/components"
import "../../modules/Astral/Kernel/config"
import "../../modules/Astral/Kernel/services"
import "../../modules/Astral/Kernel/theme"
import "../controls"
import QtQuick
import QtQuick.Layouts

// ============================================================================
// Skills — the settings surface of the skills app
// ============================================================================
// The page is chrome: title, section anchors, and the app. The manager itself is
// `org.astralplasma.skills`, which renders through the design system and talks to
// the daemon only through `SkillsService` (spec §11).
SettingsPage {
    id: root

    property bool testMode: false
    /// `{ "kind:id": appId }` for enabled apps, from the shell.
    property var integrations: ({
    })
    /// The app declares `settingsPage:skills`; disabling the app hides this page's content.
    readonly property bool appEnabled: testMode || !!(root.integrations && root.integrations["settingsPage:skills"])

    title: "Skills"
    subtitle: "Agent skills: search sources, install, and control the link farm"
    icon: "extension"
    tabs: [{
        "id": "find",
        "label": "Find",
        "icon": "search"
    }, {
        "id": "mcp",
        "label": "MCP server",
        "icon": "lan"
    }, {
        "id": "installed",
        "label": "Installed",
        "icon": "folder"
    }]

    ColumnLayout {
        width: parent.width
        spacing: Theme.spaceMedium

        // The app, declared in the shell's context so it shares the palette (spec C.18) and
        // given the daemon through a port, not a kernel import.
        Item {
            id: appSurface

            Layout.fillWidth: true
            implicitHeight: skillsApp.visible ? skillsApp.implicitHeight : hint.implicitHeight
            Layout.preferredHeight: implicitHeight

            SkillsApp {
                id: skillsApp

                visible: root.appEnabled
                width: parent.width
                skills: SkillsService
                shellState: null
                intents: null
                tab: root.currentTab
                onTabRequested: (tabId) => {
                    return root.selectTab(tabId);
                }
            }

            Text {
                id: hint

                width: parent.width
                visible: !skillsApp.visible
                text: "The Skills app is disabled. Enable it in Settings → Apps to manage agent skills."
                color: Colors.textOnSurfaceVariant
                font.family: Theme.fontFamily
                font.pixelSize: 12
                wrapMode: Text.WordWrap
            }

        }

    }

}
