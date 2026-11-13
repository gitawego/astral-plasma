// ============================================================================
// Skills — the agent-skills manager
// ============================================================================
// Search sources (GitHub by default, skills.sh when a token exists, or a folder /
// git remote you add), install a whole repository or one skill, and control the
// link farm per skill or per repository.

import "../../Kernel/components"
import "../../Kernel/theme"
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "SkillsModel.js" as Model

// Everything it renders comes from the daemon through `SkillsService` (injected as
// `skills`): the ledger is the truth, so a toggle shows a pending state until the
// daemon confirms it, then settles from the list it returns.
Item {
    id: root

    property var skills: null
    property var shellState: null
    property var intents: null
    readonly property bool ready: skills !== null
    readonly property var sources: root.skills ? root.skills.sources : []
    readonly property var results: root.skills ? root.skills.results : []
    readonly property var findings: root.skills ? root.skills.findings : []
    readonly property string lastError: root.skills ? root.skills.lastError : ""
    readonly property var mcpReport: root.skills ? root.skills.mcp : null
    readonly property var mcpServer: root.mcpReport ? root.mcpReport.server : null
    readonly property var mcpAgents: root.mcpReport ? (root.mcpReport.agents || []) : []
    property string query: ""
    /// The agent whose MCP entry is waiting for the second, confirming click.
    property string pendingMcpRemoval: ""
    /// The agent matrix is a management detail, not the page's first read.
    property bool mcpExpanded: false
    /// Atlas tab: "find", "mcp", or "installed". The page scaffold owns the strip.
    property string tab: "find"
    /// The catalog the service is searching; the chips render this, so there is one owner.
    readonly property string activeSource: root.skills ? root.skills.searchSource : root.searchSource
    property string searchSource: "github"
    property bool addingSource: false
    property string newSource: ""
    property string newSourceRef: ""

    function install(source) {
        if (root.skills)
            root.skills.install(source, []);

    }

    function toggleSkill(source, skill) {
        if (!root.skills)
            return ;

        root.skills.setSkillEnabled(source.id, skill.id, skill.state !== "linked");
    }

    function toggleSource(source) {
        if (!root.skills)
            return ;

        root.skills.setSourceEnabled(source.id, !source.enabled);
    }

    function runSearch() {
        if (root.skills)
            root.skills.search(root.query);

    }

    function addSource() {
        if (!root.skills || root.newSource.trim().length === 0)
            return ;

        root.skills.addSource(root.newSource.trim(), root.newSourceRef.trim());
        root.addingSource = false;
        root.newSource = "";
        root.newSourceRef = "";
    }

    implicitWidth: 720
    implicitHeight: content.implicitHeight
    clip: true
    Component.onCompleted: {
        if (root.skills)
            root.skills.refresh();

    }

    ColumnLayout {
        id: content

        width: parent.width
        spacing: Theme.spaceMedium

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Theme.spaceMedium
            visible: root.tab === "find"

            // ---- find -----------------------------------------------------------
            SectionHeader {
                id: findHeader

                Layout.fillWidth: true
                Layout.topMargin: Theme.padLarge
                title: "Find a skill"
                eyebrow: "GitHub + skills.sh · or paste a repo / folder"
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spaceSmall

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 34
                    radius: height / 2
                    color: Colors.surfaceContainerHigh
                    border.width: 1
                    border.color: Theme.borderSubtle

                    TextField {
                        id: searchField

                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        placeholderText: "Find a skill, or paste a repo / folder…"
                        placeholderTextColor: Colors.textOnSurfaceVariant
                        color: Colors.textOnSurface
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        background: null
                        selectByMouse: true
                        text: root.query
                        onTextChanged: root.query = text
                        onAccepted: root.runSearch()
                        Keys.onEscapePressed: {
                            text = "";
                            root.query = "";
                        }
                    }

                }

                ActionPill {
                    text: "Search"
                    fixedHeight: 30
                    paddingHorizontal: 12
                    fontPixelSize: 11
                    onClicked: root.runSearch()
                }

            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spaceSmall

                Repeater {
                    model: [{
                        "id": "github",
                        "label": "GitHub"
                    }, {
                        "id": "skills.sh",
                        "label": "skills.sh"
                    }]

                    delegate: ActionPill {
                        required property var modelData

                        text: modelData.label
                        fixedHeight: 26
                        paddingHorizontal: 10
                        fontPixelSize: 10
                        variant: (root.activeSource === modelData.id) ? "primary" : "secondary"
                        onClicked: {
                            root.searchSource = modelData.id;
                            if (root.skills)
                                root.skills.setSearchSource(modelData.id);

                        }
                    }

                }

                Item {
                    Layout.fillWidth: true
                }

                ActionPill {
                    text: root.addingSource ? "Cancel" : "Add source…"
                    fixedHeight: 26
                    paddingHorizontal: 10
                    fontPixelSize: 10
                    variant: "secondary"
                    onClicked: root.addingSource = !root.addingSource
                }

                ActionPill {
                    text: "Refresh"
                    fixedHeight: 26
                    paddingHorizontal: 10
                    fontPixelSize: 10
                    variant: "secondary"
                    onClicked: {
                        if (root.skills)
                            root.skills.refresh();

                    }
                }

            }

            // ---- add a source (local folder or any git remote) -------------------
            GlassCard {
                Layout.fillWidth: true
                implicitHeight: addRow.implicitHeight + Theme.padMedium * 2
                radius: Theme.radiusMedium
                visible: root.addingSource

                ColumnLayout {
                    id: addRow

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.margins: Theme.padMedium
                    spacing: Theme.spaceSmall

                    Text {
                        text: "Add a source"
                        color: Colors.textOnSurface
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        font.weight: Font.Medium
                    }

                    Text {
                        Layout.fillWidth: true
                        text: "A folder on this machine (linked in place, so edits are live) or any git remote — including a private GitHub repository, using git's own credentials."
                        color: Colors.textOnSurfaceVariant
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        wrapMode: Text.WordWrap
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spaceSmall

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 30
                            radius: height / 2
                            color: Colors.surfaceContainerHigh
                            border.width: 1
                            border.color: Theme.borderSubtle

                            TextField {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                placeholderText: "~/my-skills  or  git@github.com:team/skills.git"
                                placeholderTextColor: Colors.textOnSurfaceVariant
                                color: Colors.textOnSurface
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                background: null
                                selectByMouse: true
                                onTextChanged: root.newSource = text
                                onAccepted: root.addSource()
                            }

                        }

                        Rectangle {
                            implicitWidth: 150
                            implicitHeight: 30
                            radius: height / 2
                            color: Colors.surfaceContainerHigh
                            border.width: 1
                            border.color: Theme.borderSubtle

                            TextField {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                placeholderText: "ref (optional)"
                                placeholderTextColor: Colors.textOnSurfaceVariant
                                color: Colors.textOnSurface
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                background: null
                                selectByMouse: true
                                onTextChanged: root.newSourceRef = text
                                onAccepted: root.addSource()
                            }

                        }

                        ActionPill {
                            text: "Add"
                            fixedHeight: 28
                            paddingHorizontal: 12
                            fontPixelSize: 10
                            onClicked: root.addSource()
                        }

                    }

                }

            }

        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Theme.spaceMedium
            visible: root.tab === "mcp"

            // ---- MCP server + agent registration --------------------------------
            SectionHeader {
                id: mcpHeader

                Layout.fillWidth: true
                title: "MCP server"
                eyebrow: Model.mcpSummary(root.mcpReport)

                ActionPill {
                    text: root.mcpExpanded ? "Hide agents" : "Manage agents"
                    fixedHeight: 24
                    paddingHorizontal: 10
                    fontPixelSize: 9
                    variant: "secondary"
                    onClicked: root.mcpExpanded = !root.mcpExpanded
                }

                ActionPill {
                    text: "Check again"
                    fixedHeight: 24
                    paddingHorizontal: 10
                    fontPixelSize: 9
                    variant: "secondary"
                    onClicked: {
                        if (root.skills)
                            root.skills.refreshMcp();

                    }
                }

            }

            GlassCard {
                Layout.fillWidth: true
                implicitHeight: mcpColumn.implicitHeight + Theme.padMedium * 2
                radius: Theme.radiusMedium

                ColumnLayout {
                    id: mcpColumn

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.margins: Theme.padMedium
                    spacing: Theme.spaceSmall

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spaceSmall

                        MaterialIcon {
                            iconName: Model.mcpStateIcon(root.mcpServer)
                            size: 14
                            color: Model.mcpState(root.mcpServer) === "up" ? Colors.primary : Colors.warning
                        }

                        Text {
                            text: Model.mcpStateLabel(root.mcpServer)
                            color: Model.mcpState(root.mcpServer) === "up" ? Colors.primary : Colors.warning
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            font.weight: Font.Medium
                        }

                        Text {
                            Layout.fillWidth: true
                            text: root.mcpServer ? String(root.mcpServer.url || "") : ""
                            color: Colors.textOnSurfaceVariant
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            elide: Text.ElideMiddle
                        }

                    }

                    Text {
                        Layout.fillWidth: true
                        text: Model.mcpDetail(root.mcpServer)
                        color: Colors.textOnSurfaceVariant
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        wrapMode: Text.WordWrap
                    }

                    Repeater {
                        model: root.mcpExpanded ? root.mcpAgents : []

                        delegate: RowLayout {
                            required property var modelData

                            Layout.fillWidth: true
                            spacing: Theme.spaceSmall

                            MaterialIcon {
                                iconName: Model.agentStateIcon(modelData)
                                size: 13
                                color: Model.agentState(modelData) === "configured" ? Colors.primary : Colors.textOnSurfaceVariant
                            }

                            Text {
                                Layout.preferredWidth: 104
                                text: modelData.label
                                color: Colors.textOnSurface
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                elide: Text.ElideRight
                            }

                            Text {
                                Layout.preferredWidth: 88
                                text: Model.agentStateLabel(modelData)
                                color: Model.agentState(modelData) === "configured" ? Colors.primary : Colors.textOnSurfaceVariant
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                            }

                            Text {
                                Layout.fillWidth: true
                                text: String(modelData.detail || "")
                                color: Colors.textOnSurfaceVariant
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                elide: Text.ElideRight
                            }

                            ActionPill {
                                visible: modelData.installed === true && modelData.configured !== true
                                interactive: root.skills ? !root.skills.mcpBusy : true
                                text: "Install"
                                fixedHeight: 22
                                paddingHorizontal: 9
                                fontPixelSize: 9
                                variant: "secondary"
                                onClicked: {
                                    if (root.skills)
                                        root.skills.installMcp(modelData.id);

                                }
                            }

                            ActionPill {
                                visible: modelData.configured === true
                                interactive: root.skills ? !root.skills.mcpBusy : true
                                text: root.pendingMcpRemoval === modelData.id ? "Remove" : "Uninstall"
                                fixedHeight: 22
                                paddingHorizontal: 9
                                fontPixelSize: 9
                                variant: root.pendingMcpRemoval === modelData.id ? "danger" : "secondary"
                                onClicked: {
                                    if (root.pendingMcpRemoval === modelData.id) {
                                        root.pendingMcpRemoval = "";
                                        if (root.skills)
                                            root.skills.uninstallMcp(modelData.id);

                                    } else {
                                        root.pendingMcpRemoval = modelData.id;
                                    }
                                }
                            }

                            ActionPill {
                                visible: root.pendingMcpRemoval === modelData.id
                                text: "Cancel"
                                fixedHeight: 22
                                paddingHorizontal: 9
                                fontPixelSize: 9
                                variant: "secondary"
                                onClicked: root.pendingMcpRemoval = ""
                            }

                        }

                    }

                }

            }

        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Theme.spaceMedium
            visible: root.tab === "find"

            // ---- a refusal is information ---------------------------------------
            Text {
                Layout.fillWidth: true
                visible: root.lastError.length > 0
                text: root.lastError
                color: Colors.error !== undefined ? Colors.error : Colors.tertiary
                font.family: Theme.fontFamily
                font.pixelSize: 11
                wrapMode: Text.WordWrap
            }

            // ---- search results --------------------------------------------------
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.spaceSmall
                visible: root.results.length > 0

                SectionHeader {
                    Layout.fillWidth: true
                    title: "Results"
                    eyebrow: root.results.length + " found"
                }

                Repeater {
                    model: root.results

                    delegate: GlassCard {
                        required property var modelData

                        Layout.fillWidth: true
                        implicitHeight: resultRow.implicitHeight + Theme.padMedium * 2
                        radius: Theme.radiusMedium

                        RowLayout {
                            id: resultRow

                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.margins: Theme.padMedium
                            spacing: Theme.spaceSmall

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: Theme.spaceSmall

                                    // What the user is looking at: a whole repository or one skill
                                    // inside one. The two catalogs answer differently, so the row says
                                    // which answer this is.
                                    Text {
                                        text: Model.hitBadge(modelData)
                                        color: Colors.primary
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 9
                                        font.weight: Font.Medium
                                    }

                                    Text {
                                        text: Model.hitTitle(modelData)
                                        color: Colors.textOnSurface
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 13
                                        font.weight: Font.Medium
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }

                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: Model.hitSubtitle(modelData)
                                    color: Colors.textOnSurfaceVariant
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    elide: Text.ElideRight
                                }

                            }

                            ActionPill {
                                // A skill hit installs that skill; a repository hit installs the repo.
                                text: Model.hitBadge(modelData) === "skill" ? "Install skill" : "Install repo"
                                fixedHeight: 26
                                paddingHorizontal: 12
                                fontPixelSize: 10
                                onClicked: {
                                    const target = Model.installTarget(modelData);
                                    if (!root.skills || target.source.length === 0)
                                        return ;

                                    root.skills.install(target.source, target.skills);
                                }
                            }

                        }

                    }

                }

            }

        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Theme.spaceMedium
            visible: root.tab === "installed"

            // ---- installed sources ----------------------------------------------
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.spaceSmall

                SectionHeader {
                    id: installedHeader

                    Layout.fillWidth: true
                    Layout.topMargin: Theme.spaceSmall
                    title: "Installed"
                    eyebrow: root.skills ? (root.skills.enabledSkillCount + " of " + root.skills.skillCount + " enabled") : ""
                }

                GlassCard {
                    Layout.fillWidth: true
                    visible: root.ready && root.sources.length === 0
                    implicitHeight: emptyRow.implicitHeight + Theme.padMedium * 2
                    radius: Theme.radiusMedium

                    RowLayout {
                        id: emptyRow

                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.margins: Theme.padMedium
                        spacing: Theme.spaceMedium

                        MaterialIcon {
                            iconName: "auto_awesome"
                            size: 18
                            color: Colors.primary
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            Text {
                                text: "No skills installed yet"
                                color: Colors.textOnSurface
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                                font.weight: Font.Medium
                            }

                            Text {
                                Layout.fillWidth: true
                                text: "Search above, or add a folder or a git remote."
                                color: Colors.textOnSurfaceVariant
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                wrapMode: Text.WordWrap
                            }

                        }

                        ActionPill {
                            text: "Add source…"
                            fixedHeight: 24
                            paddingHorizontal: 10
                            fontPixelSize: 9
                            variant: "secondary"
                            onClicked: root.addingSource = true
                        }

                    }

                }

                Repeater {
                    model: root.sources

                    delegate: GlassCard {
                        id: sourceCard

                        required property var modelData

                        Layout.fillWidth: true
                        implicitHeight: sourceColumn.implicitHeight + Theme.padMedium * 2
                        radius: Theme.radiusMedium

                        ColumnLayout {
                            id: sourceColumn

                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.margins: Theme.padMedium
                            spacing: Theme.spaceSmall

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Theme.spaceSmall

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2

                                    Text {
                                        text: modelData.label || modelData.id
                                        color: Colors.textOnSurface
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 13
                                        font.weight: Font.Medium
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }

                                    Text {
                                        text: (modelData.spec || "") + "  ·  " + Model.sourceSummary(modelData)
                                        color: Colors.textOnSurfaceVariant
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 11
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }

                                }

                                ActionPill {
                                    // A source can be added before its skills are linked; this is
                                    // the explicit install step for a local folder or a new repo.
                                    text: "Install all"
                                    fixedHeight: 26
                                    paddingHorizontal: 10
                                    fontPixelSize: 10
                                    variant: "primary"
                                    onClicked: {
                                        if (root.skills)
                                            root.skills.install(modelData.id, []);

                                    }
                                }

                                ActionPill {
                                    // One toggle for the whole repository: the operation the
                                    // ecosystem's CLI cannot do.
                                    text: modelData.enabled ? "Disable all" : "Enable all"
                                    fixedHeight: 26
                                    paddingHorizontal: 10
                                    fontPixelSize: 10
                                    variant: "secondary"
                                    onClicked: root.toggleSource(modelData)
                                }

                                ActionPill {
                                    text: "Update"
                                    fixedHeight: 26
                                    paddingHorizontal: 10
                                    fontPixelSize: 10
                                    variant: "secondary"
                                    onClicked: {
                                        if (root.skills)
                                            root.skills.updateSource(modelData.id);

                                    }
                                }

                                ActionPill {
                                    // Reversible update: the previous commit is still in the store.
                                    text: "Roll back"
                                    fixedHeight: 26
                                    paddingHorizontal: 10
                                    fontPixelSize: 10
                                    variant: "secondary"
                                    onClicked: {
                                        if (root.skills)
                                            root.skills.rollbackSource(modelData.id);

                                    }
                                }

                                ActionPill {
                                    text: "Remove"
                                    fixedHeight: 26
                                    paddingHorizontal: 10
                                    fontPixelSize: 10
                                    variant: "secondary"
                                    onClicked: {
                                        if (root.skills)
                                            root.skills.removeSource(modelData.id, false);

                                    }
                                }

                            }

                            Repeater {
                                model: modelData.skills || []

                                delegate: RowLayout {
                                    required property var modelData

                                    Layout.fillWidth: true
                                    spacing: Theme.spaceSmall

                                    MaterialIcon {
                                        iconName: modelData.state === "linked" ? "check_circle" : "radio_button_unchecked"
                                        size: 14
                                        color: modelData.state === "linked" ? Colors.primary : Colors.textOnSurfaceVariant
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: modelData.id
                                        color: Colors.textOnSurface
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 12
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        text: modelData.origin || ""
                                        color: Colors.textOnSurfaceVariant
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 10
                                    }

                                    ActionPill {
                                        text: modelData.state === "linked" ? "Disable" : "Enable"
                                        fixedHeight: 22
                                        paddingHorizontal: 9
                                        fontPixelSize: 9
                                        variant: "secondary"
                                        onClicked: root.toggleSkill(sourceCard.modelData, modelData)
                                    }

                                }

                            }

                        }

                    }

                }

            }

            // ---- trash -----------------------------------------------------------
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.spaceSmall
                visible: (root.skills ? root.skills.trash.length : 0) > 0

                SectionHeader {
                    Layout.fillWidth: true
                    Layout.topMargin: Theme.spaceSmall
                    title: "Recently removed"
                    eyebrow: (root.skills ? root.skills.trash.length : 0) + " recoverable"
                }

                Repeater {
                    model: root.skills ? root.skills.trash : []

                    delegate: GlassCard {
                        required property var modelData

                        Layout.fillWidth: true
                        implicitHeight: trashRow.implicitHeight + Theme.padSmall * 2
                        radius: Theme.radiusMedium

                        RowLayout {
                            id: trashRow

                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.margins: Theme.padSmall
                            spacing: Theme.spaceSmall

                            Text {
                                Layout.fillWidth: true
                                text: modelData.name
                                color: Colors.textOnSurface
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                elide: Text.ElideRight
                            }

                            ActionPill {
                                text: "Restore"
                                fixedHeight: 22
                                paddingHorizontal: 9
                                fontPixelSize: 9
                                variant: "secondary"
                                onClicked: {
                                    if (root.skills)
                                        root.skills.restoreTrash(modelData.name);

                                }
                            }

                        }

                    }

                }

            }

            // ---- doctor ----------------------------------------------------------
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.spaceSmall
                visible: root.findings.length > 0

                SectionHeader {
                    Layout.fillWidth: true
                    Layout.topMargin: Theme.spaceSmall
                    title: "Doctor"
                    eyebrow: root.findings.length + " finding" + (root.findings.length === 1 ? "" : "s")
                }

                Repeater {
                    model: root.findings

                    delegate: GlassCard {
                        required property var modelData

                        Layout.fillWidth: true
                        implicitHeight: findingRow.implicitHeight + Theme.padSmall * 2
                        radius: Theme.radiusMedium

                        RowLayout {
                            id: findingRow

                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.margins: Theme.padSmall
                            spacing: Theme.spaceSmall

                            MaterialIcon {
                                iconName: "warning"
                                size: 14
                                color: Colors.warning !== undefined ? Colors.warning : Colors.tertiary
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1

                                Text {
                                    text: modelData.kind + " · " + (modelData.skill || "")
                                    color: Colors.textOnSurface
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.detail || modelData.path
                                    color: Colors.textOnSurfaceVariant
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 10
                                    elide: Text.ElideMiddle
                                }

                            }

                        }

                    }

                }

            }

        }

    }

}
