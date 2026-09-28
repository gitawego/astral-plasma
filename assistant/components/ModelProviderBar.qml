import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../components"
import "../../services"
import "../../config"

Item {
    id: root

    implicitHeight: 44
    Layout.fillWidth: true
    z: (providerMenuOpen || modelMenuOpen) ? 200 : 1

    signal addProviderRequested()

    property bool testMode: false
    property string testProvider: "opencode-go"
    property string testModel: "mimo-v2.6-flash"

    property bool providerMenuOpen: false
    property bool modelMenuOpen: false
    property string modelSearchFilter: ""

    /// True while any dropdown is open: the drawer and the outside-click
    /// catcher key off this instead of either flag.
    readonly property bool menusOpen: providerMenuOpen || modelMenuOpen

    readonly property string currentProvider: testMode ? testProvider : ((typeof AssistantService !== "undefined" && AssistantService.selectedProviderId) ? AssistantService.selectedProviderId : testProvider)
    readonly property string currentModel: testMode ? testModel : ((typeof AssistantService !== "undefined" && AssistantService.selectedModelId) ? AssistantService.selectedModelId : testModel)
    readonly property string providerName: (typeof AssistantService !== "undefined" && typeof AssistantService.getProviderDisplayName === "function") ? AssistantService.getProviderDisplayName(currentProvider) : (currentProvider === "opencode-go" ? "OpenCode Go" : currentProvider.toUpperCase())
    readonly property var availableModels: (typeof AssistantService !== "undefined" && typeof AssistantService.getModelsForProvider === "function") ? AssistantService.getModelsForProvider(currentProvider) : ["mimo-v2.6-flash", "mimo-v2.6-pro", "deepseek-v4-flash", "qwen3.8-flash"]

    // Liquid Glass Container
    Rectangle {
        anchors.fill: parent
        anchors.leftMargin: Theme.padLarge
        anchors.rightMargin: Theme.padLarge
        radius: 10
        color: (typeof Colors !== "undefined" && Colors.isDarkMode) ? Qt.rgba(0.12, 0.13, 0.18, 0.75) : ((typeof Colors !== "undefined" && Colors.glassCard) ? Colors.glassCard : Qt.rgba(1, 1, 1, 0.5))
        border.width: 1
        border.color: (providerMenuOpen || modelMenuOpen) ? Colors.primary : Colors.glassBorderSpecular

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            spacing: 8

            // 1. Provider Selector Button
            Rectangle {
                id: providerBtn
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                implicitHeight: 34
                radius: 8
                scale: providerHover.pressed ? 0.96 : (providerHover.containsMouse ? 1.02 : 1.0)
                Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
                color: providerHover.containsMouse ? Colors.glassCardHover : (root.providerMenuOpen ? Colors.m3surfaceContainerHighest : "transparent")

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    spacing: 8

                    MaterialIcon {
                        iconName: "psychology"
                        size: 16
                        color: Colors.primary
                    }

                    ColumnLayout {
                        spacing: 0
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter

                        Text {
                            text: "PROVIDER"
                            font.family: Theme.fontMonospace
                            font.pixelSize: 8
                            font.weight: Font.Bold
                            color: Colors.m3onSurfaceVariant
                        }

                        Text {
                            text: root.providerName
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                            color: Colors.m3onSurface
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }

                    MaterialIcon {
                        iconName: "expand_more"
                        size: 16
                        color: Colors.m3onSurfaceVariant
                        rotation: root.providerMenuOpen ? 180 : 0
                        Behavior on rotation { NumberAnimation { duration: 150 } }
                    }
                }

                MouseArea {
                    id: providerHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.modelMenuOpen = false;
                        root.providerMenuOpen = !root.providerMenuOpen;
                    }
                }
            }

            // Hairline Divider
            Rectangle {
                width: 1
                implicitHeight: 22
                color: Colors.glassBorderSpecular
            }

            // 2. Model Selector Button
            Rectangle {
                id: modelBtn
                Layout.fillWidth: true
                Layout.preferredWidth: 1.2
                implicitHeight: 34
                radius: 8
                scale: modelHover.pressed ? 0.96 : (modelHover.containsMouse ? 1.02 : 1.0)
                Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
                color: modelHover.containsMouse ? Colors.glassCardHover : (root.modelMenuOpen ? Colors.m3surfaceContainerHighest : "transparent")

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    spacing: 8

                    MaterialIcon {
                        iconName: "auto_awesome"
                        size: 16
                        color: Colors.secondary
                    }

                    ColumnLayout {
                        spacing: 0
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter

                        Text {
                            text: "MODEL"
                            font.family: Theme.fontMonospace
                            font.pixelSize: 8
                            font.weight: Font.Bold
                            color: Colors.m3onSurfaceVariant
                        }

                        Text {
                            text: root.currentModel || "Select Model..."
                            font.family: Theme.fontMonospace
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                            color: Colors.m3onSurface
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }

                    MaterialIcon {
                        iconName: "expand_more"
                        size: 16
                        color: Colors.m3onSurfaceVariant
                        rotation: root.modelMenuOpen ? 180 : 0
                        Behavior on rotation { NumberAnimation { duration: 150 } }
                    }
                }

                MouseArea {
                    id: modelHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.providerMenuOpen = false;
                        root.modelSearchFilter = "";
                        root.modelMenuOpen = !root.modelMenuOpen;
                    }
                }
            }

            // 3. Settings shortcut
            Rectangle {
                implicitWidth: 30
                implicitHeight: 30
                radius: 15
                scale: settingsBtnHover.pressed ? 0.92 : (settingsBtnHover.containsMouse ? 1.06 : 1.0)
                Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
                color: settingsBtnHover.containsMouse ? Colors.glassCardHover : "transparent"
                border.width: settingsBtnHover.containsMouse ? 1 : 0
                border.color: Colors.glassBorderSpecular

                MaterialIcon {
                    anchors.centerIn: parent
                    iconName: "tune"
                    size: 16
                    color: Colors.m3onSurfaceVariant
                }

                MouseArea {
                    id: settingsBtnHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.providerMenuOpen = false;
                        root.modelMenuOpen = false;
                        if (typeof Config !== "undefined") {
                            Config.openSettings("ai");
                        }
                    }
                }
            }
        }
    }

    // Outside-click dismissal.
    //
    // A dropdown belongs to the window, not to the 44px strip that opens it: any
    // click that misses the popup closes it. The catcher sits below the popups
    // (z: 150) and above everything else, and it is sized to the window because
    // the bar itself is only one row tall.
    MouseArea {
        id: popupDismissCatcher
        visible: root.menusOpen
        enabled: root.menusOpen
        z: 100
        readonly property point windowOrigin: root.mapToItem(null, 0, 0)
        x: -windowOrigin.x
        y: -windowOrigin.y
        width: (typeof Window !== "undefined" && Window.window) ? Window.window.width : 0
        height: (typeof Window !== "undefined" && Window.window) ? Window.window.height : 0
        onClicked: {
            root.providerMenuOpen = false;
            root.modelMenuOpen = false;
        }
    }

    // Provider Dropdown Popup
    Rectangle {
        id: providerPopup
        visible: root.providerMenuOpen
        z: 150
        anchors.top: parent.bottom
        anchors.topMargin: 4
        anchors.left: parent.left
        anchors.leftMargin: Theme.padLarge
        width: 230
        height: Math.min(320, providerCol.implicitHeight + 16)
        radius: 12
        color: (typeof Colors !== "undefined" && Colors.isDarkMode) ? Qt.rgba(0.10, 0.12, 0.17, 0.90) : Qt.rgba(0.96, 0.97, 1.0, 0.90)
        border.width: 1
        border.color: Colors.glassBorderSpecular

        Flickable {
            anchors.fill: parent
            anchors.margins: 8
            contentHeight: providerCol.implicitHeight
            clip: true

            ColumnLayout {
                id: providerCol
                width: parent.width
                spacing: 2

                Text {
                    text: "SELECT PROVIDER"
                    font.family: Theme.fontMonospace
                    font.pixelSize: 9
                    font.weight: Font.Bold
                    color: Colors.m3onSurfaceVariant
                    Layout.leftMargin: 6
                    Layout.bottomMargin: 2
                }

                Repeater {
                    model: (typeof AssistantService !== "undefined" && AssistantService.availableProviders) ? AssistantService.availableProviders : []
                    delegate: Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 30
                        radius: 6
                        color: provItemHover.containsMouse ? Colors.glassCardHover : (root.currentProvider === modelData.id ? Colors.m3primaryContainer : "transparent")

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 6

                            MaterialIcon {
                                iconName: "psychology"
                                size: 14
                                color: root.currentProvider === modelData.id ? Colors.m3onPrimaryContainer : Colors.primary
                            }

                            Text {
                                text: modelData.name || modelData.id
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                font.weight: root.currentProvider === modelData.id ? Font.Bold : Font.Normal
                                color: root.currentProvider === modelData.id ? Colors.m3onPrimaryContainer : Colors.m3onSurface
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                            }

                            Rectangle {
                                width: 6
                                height: 6
                                radius: 3
                                color: root.currentProvider === modelData.id ? Colors.primary : "transparent"
                            }
                        }

                        MouseArea {
                            id: provItemHover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (typeof AssistantService !== "undefined") {
                                    AssistantService.selectProvider(modelData.id);
                                }
                                root.providerMenuOpen = false;
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: Colors.m3outlineVariant
                    Layout.topMargin: 4
                    Layout.bottomMargin: 4
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 28
                    radius: 6
                    color: addProvHover.containsMouse ? Colors.glassCardHover : "transparent"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        spacing: 6

                        MaterialIcon {
                            iconName: "add"
                            size: 14
                            color: Colors.primary
                        }

                        Text {
                            text: "Add Custom Provider..."
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            color: Colors.primary
                        }
                    }

                    MouseArea {
                        id: addProvHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.providerMenuOpen = false;
                            root.addProviderRequested();
                        }
                    }
                }
            }
        }
    }

    // Model Dropdown Popup
    Rectangle {
        id: modelPopup
        visible: root.modelMenuOpen
        z: 150
        anchors.top: parent.bottom
        anchors.topMargin: 4
        anchors.right: parent.right
        anchors.rightMargin: Theme.padLarge
        width: 280
        height: Math.min(340, modelMainCol.implicitHeight + 16)
        radius: 12
        color: (typeof Colors !== "undefined" && Colors.isDarkMode) ? Qt.rgba(0.10, 0.12, 0.17, 0.90) : Qt.rgba(0.96, 0.97, 1.0, 0.90)
        border.width: 1
        border.color: Colors.glassBorderSpecular

        ColumnLayout {
            id: modelMainCol
            anchors.fill: parent
            anchors.margins: 8
            spacing: 4

            Text {
                text: "SELECT MODEL (" + root.providerName.toUpperCase() + ")"
                font.family: Theme.fontMonospace
                font.pixelSize: 9
                font.weight: Font.Bold
                color: Colors.m3onSurfaceVariant
                Layout.leftMargin: 6
            }

            // Quick Search / Filter Input
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 28
                radius: 6
                color: (typeof Colors !== "undefined" && Colors.isDarkMode) ? Qt.rgba(0.05, 0.06, 0.09, 0.60) : Qt.rgba(0.92, 0.93, 0.96, 0.60)
                border.width: 1
                border.color: modelSearchInput.activeFocus ? Colors.primary : Colors.glassBorderSpecular

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 6
                    anchors.rightMargin: 6
                    spacing: 4

                    MaterialIcon {
                        iconName: "search"
                        size: 14
                        color: Colors.m3onSurfaceVariant
                    }

                    TextInput {
                        id: modelSearchInput
                        Layout.fillWidth: true
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        color: Colors.m3onSurface
                        text: root.modelSearchFilter
                        onTextChanged: root.modelSearchFilter = text.toLowerCase().trim()

                        Text {
                            anchors.fill: parent
                            visible: !modelSearchInput.text && !modelSearchInput.activeFocus
                            text: "Filter models..."
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            color: Colors.m3onSurfaceVariant
                        }

                        Keys.onReturnPressed: {
                            if (text.trim().length > 0) {
                                if (typeof AssistantService !== "undefined") {
                                    AssistantService.selectModel(text.trim());
                                }
                                root.modelMenuOpen = false;
                            }
                        }
                    }
                }
            }

            // Models List
            Flickable {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(200, modelListCol.implicitHeight)
                contentHeight: modelListCol.implicitHeight
                clip: true

                ColumnLayout {
                    id: modelListCol
                    width: parent.width
                    spacing: 2

                    Repeater {
                        model: {
                            let list = root.availableModels || [];
                            if (!root.modelSearchFilter) return list;
                            return list.filter(function(m) { return m.toLowerCase().includes(root.modelSearchFilter); });
                        }
                        delegate: Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 28
                            radius: 6
                            color: modelItemHover.containsMouse ? Colors.glassCardHover : (root.currentModel === modelData ? Colors.m3secondaryContainer : "transparent")

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                spacing: 6

                                MaterialIcon {
                                    iconName: "memory"
                                    size: 13
                                    color: root.currentModel === modelData ? Colors.m3onSecondaryContainer : Colors.secondary
                                }

                                Text {
                                    text: modelData
                                    font.family: Theme.fontMonospace
                                    font.pixelSize: 11
                                    font.weight: root.currentModel === modelData ? Font.Bold : Font.Normal
                                    color: root.currentModel === modelData ? Colors.m3onSecondaryContainer : Colors.m3onSurface
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                }

                                Rectangle {
                                    width: 6
                                    height: 6
                                    radius: 3
                                    color: root.currentModel === modelData ? Colors.secondary : "transparent"
                                }
                            }

                            MouseArea {
                                id: modelItemHover
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (typeof AssistantService !== "undefined") {
                                        AssistantService.selectModel(modelData);
                                    }
                                    root.modelMenuOpen = false;
                                }
                            }
                        }
                    }

                    // Empty filter notice
                    Text {
                        visible: modelListCol.children.length <= 1
                        text: "No matching models. Press Enter in search to use as custom ID."
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        color: Colors.m3onSurfaceVariant
                        Layout.margins: 8
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                }
            }
        }
    }

    property alias dismissCatcherItem: popupDismissCatcher
}
