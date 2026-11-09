import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import "../../Kernel/theme"
import "../../Kernel/components"
import "SkillsModel.js" as Model

// ============================================================================
// Skills — the agent-skills manager
// ============================================================================
// Search sources (GitHub by default, skills.sh when a token exists, or a folder /
// git remote you add), install a whole repository or one skill, and control the
// link farm per skill or per repository.
//
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

    property string query: ""
    /// The catalog the service is searching; the chips render this, so there is one owner.
    readonly property string activeSource: root.skills ? root.skills.searchSource : root.searchSource
    property string searchSource: "github"
    property bool addingSource: false
    property string newSource: ""
    property string newSourceRef: ""

    implicitWidth: 720
    implicitHeight: content.implicitHeight
    clip: true

    Component.onCompleted: if (root.skills) root.skills.refresh()

    function install(source) {
        if (root.skills) root.skills.install(source, []);
    }

    function toggleSkill(source, skill) {
        if (!root.skills) return;
        root.skills.setSkillEnabled(source.id, skill.id, skill.state !== "linked");
    }

    function toggleSource(source) {
        if (!root.skills) return;
        root.skills.setSourceEnabled(source.id, !source.enabled);
    }

    function runSearch() {
        if (root.skills) root.skills.search(root.query);
    }

    function addSource() {
        if (!root.skills || root.newSource.trim().length === 0) return;
        root.skills.addSource(root.newSource.trim(), root.newSourceRef.trim());
        root.addingSource = false;
        root.newSource = "";
        root.newSourceRef = "";
    }

    ColumnLayout {
        id: content
        width: parent.width
        spacing: Theme.spaceMedium

        // ---- search ---------------------------------------------------------
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: Theme.padLarge
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
                model: [
                    { id: "github", label: "GitHub" },
                    { id: "skills.sh", label: "skills.sh" }
                ]
                delegate: ActionPill {
                    required property var modelData
                    text: modelData.label
                    fixedHeight: 26
                    paddingHorizontal: 10
                    fontPixelSize: 10
                    variant: (root.activeSource === modelData.id) ? "primary" : "secondary"
                    onClicked: {
                        root.searchSource = modelData.id;
                        if (root.skills) root.skills.setSearchSource(modelData.id);
                    }
                }
            }

            Item { Layout.fillWidth: true }

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
                onClicked: if (root.skills) root.skills.refresh()
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

            Text {
                text: "Results"
                color: Colors.textOnSurface
                font.family: Theme.fontFamily
                font.pixelSize: 15
                font.weight: Font.DemiBold
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
                                if (!root.skills || target.source.length === 0) return;
                                root.skills.install(target.source, target.skills);
                            }
                        }
                    }
                }
            }
        }

        // ---- installed sources ----------------------------------------------
        ColumnLayout {
            Layout.fillWidth: true
            spacing: Theme.spaceSmall

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Theme.spaceSmall

                Text {
                    text: "Installed"
                    color: Colors.textOnSurface
                    font.family: Theme.fontFamily
                    font.pixelSize: 15
                    font.weight: Font.DemiBold
                }
                Item { Layout.fillWidth: true }
                Text {
                    text: root.skills ? (root.skills.enabledSkillCount + " of " + root.skills.skillCount + " enabled") : ""
                    color: Colors.textOnSurfaceVariant
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                }
            }

            Text {
                Layout.fillWidth: true
                visible: root.ready && root.sources.length === 0
                text: "No skills installed yet. Search for one, or add a folder or a git remote."
                color: Colors.textOnSurfaceVariant
                font.family: Theme.fontFamily
                font.pixelSize: 12
                wrapMode: Text.WordWrap
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
                                onClicked: if (root.skills) root.skills.updateSource(modelData.id)
                            }

                            ActionPill {
                                // Reversible update: the previous commit is still in the store.
                                text: "Roll back"
                                fixedHeight: 26
                                paddingHorizontal: 10
                                fontPixelSize: 10
                                variant: "secondary"
                                onClicked: if (root.skills) root.skills.rollbackSource(modelData.id)
                            }

                            ActionPill {
                                text: "Remove"
                                fixedHeight: 26
                                paddingHorizontal: 10
                                fontPixelSize: 10
                                variant: "secondary"
                                onClicked: if (root.skills) root.skills.removeSource(modelData.id, false)
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

            Text {
                Layout.topMargin: Theme.spaceSmall
                text: "Recently removed"
                color: Colors.textOnSurface
                font.family: Theme.fontFamily
                font.pixelSize: 15
                font.weight: Font.DemiBold
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
                            onClicked: if (root.skills) root.skills.restoreTrash(modelData.name)
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

            Text {
                Layout.topMargin: Theme.spaceSmall
                text: "Doctor"
                color: Colors.textOnSurface
                font.family: Theme.fontFamily
                font.pixelSize: 15
                font.weight: Font.DemiBold
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
