import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import "../../theme"
import "../../components"
import "../../services"
import "../../config"

Item {
    id: root

    implicitHeight: 52
    Layout.fillWidth: true

    property bool testMode: false
    property string testHarness: "pi"
    property string testProvider: "gemini"
    property Item dragTarget: null

    signal userDragged()
    signal sessionsRequested()
    signal newChatRequested()
    signal closeRequested()
    signal minimizeRequested()
    signal addProviderRequested()

    property bool providerMenuOpen: false

    readonly property string activeHarness: testMode ? testHarness : ((typeof AssistantService !== "undefined" && AssistantService.selectedHarness) ? AssistantService.selectedHarness : testHarness)
    readonly property string activeProvider: testMode ? testProvider : ((typeof AssistantService !== "undefined" && AssistantService.selectedProviderId) ? AssistantService.selectedProviderId : "opencode-go")
    readonly property string activeModel: testMode ? "mimo-v2.6-flash" : ((typeof AssistantService !== "undefined" && AssistantService.selectedModelId) ? AssistantService.selectedModelId : "mimo-v2.6-flash")
    readonly property string activeProviderName: (typeof AssistantService !== "undefined" && typeof AssistantService.getProviderDisplayName === "function") ? AssistantService.getProviderDisplayName(root.activeProvider) : root.activeProvider

    // Header Background Drag Area: Enables dragging from title/spacer while NEVER covering action buttons
    MouseArea {
        id: headerBackgroundDragArea
        anchors.fill: parent
        z: 0
        hoverEnabled: true
        cursorShape: drag.active ? Qt.ClosedHandCursor : (containsMouse ? Qt.OpenHandCursor : Qt.ArrowCursor)
        drag.target: root.dragTarget
        drag.axis: Drag.XAndYAxis
        drag.minimumX: 16
        drag.maximumX: Math.max(16, (root.dragTarget && root.dragTarget.parent ? root.dragTarget.parent.width : 1920) - (root.dragTarget ? root.dragTarget.width : 480) - 16)
        drag.minimumY: 16
        drag.maximumY: Math.max(16, (root.dragTarget && root.dragTarget.parent ? root.dragTarget.parent.height : 1080) - (root.dragTarget ? root.dragTarget.height : 520) - 16)

        onPositionChanged: {
            if (drag.active) {
                root.userDragged();
            }
        }
        onDoubleClicked: {
            if (root.dragTarget && typeof root.dragTarget.resetPosition === "function") {
                root.dragTarget.resetPosition();
            }
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.padLarge
        anchors.rightMargin: Theme.padLarge
        spacing: Theme.spaceMedium
        z: 1

        // Left Branding & Liquid Glass Badge
        Rectangle {
            width: 34
            height: 34
            radius: 10
            color: (typeof Colors !== "undefined" && Colors.isDarkMode)
                ? Qt.rgba(Colors.primary.r, Colors.primary.g, Colors.primary.b, 0.14)
                : Qt.rgba(Colors.primary.r, Colors.primary.g, Colors.primary.b, 0.20)
            border.width: 1
            border.color: (typeof Colors !== "undefined" && Colors.primary)
                ? Qt.alpha(Colors.primary, 0.35)
                : Colors.glassBorderSpecular

            MaterialIcon {
                anchors.centerIn: parent
                iconName: "auto_awesome"
                size: 18
                color: (typeof Colors !== "undefined" && Colors.primary) ? Colors.primary : "#CFBCFF"
            }
        }

        ColumnLayout {
            spacing: 0
            Layout.alignment: Qt.AlignVCenter
            Layout.fillWidth: true

            Text {
                text: "Astral Copilot"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontTitleSmall
                font.weight: Font.DemiBold
                color: Colors.m3onSurface
            }

            Text {
                text: (root.activeHarness === "pi" ? "Pi Engine" : "Hermes Engine") + " • " + root.activeProviderName + (root.activeModel ? (" / " + root.activeModel) : "")
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontLabelSmall
                color: Colors.m3onSurfaceVariant
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
        }

        Item { Layout.fillWidth: true }

        // Action Buttons Row with explicit high-priority z: 10
        RowLayout {
            id: actionButtonsRow
            z: 10
            spacing: Theme.spaceMedium
            Layout.alignment: Qt.AlignVCenter

            // Harness Switcher Pill
            Rectangle {
                implicitHeight: 30
                implicitWidth: harnessRow.implicitWidth + 14
                radius: 15
                scale: harnessMouse.pressed ? 0.94 : (harnessMouse.containsMouse ? 1.04 : 1.0)
                Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
                color: harnessMouse.containsMouse ? Colors.glassCardHover : Colors.glassCard
                border.width: 1
                border.color: Colors.glassBorderSpecular

                RowLayout {
                    id: harnessRow
                    anchors.centerIn: parent
                    spacing: 4

                    Text {
                        text: root.activeHarness.toUpperCase()
                        font.family: Theme.fontMonospace
                        font.pixelSize: 11
                        font.weight: Font.Bold
                        color: Colors.m3primary
                    }
                }

                MouseArea {
                    id: harnessMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    z: 10
                    onClicked: {
                        let next = (root.activeHarness === "pi") ? "hermes" : "pi";
                        if (typeof AssistantService !== "undefined") {
                            AssistantService.selectedHarness = next;
                        }
                        root.testHarness = next;
                    }
                }
            }

            // New Chat Button
            Rectangle {
                width: 30
                height: 30
                radius: 15
                scale: newChatMouse.pressed ? 0.92 : (newChatMouse.containsMouse ? 1.06 : 1.0)
                Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
                color: newChatMouse.containsMouse ? Colors.glassCardHover : "transparent"
                border.width: newChatMouse.containsMouse ? 1 : 0
                border.color: Colors.glassBorderSpecular

                MaterialIcon {
                    anchors.centerIn: parent
                    iconName: "add"
                    size: 18
                    color: newChatMouse.containsMouse ? Colors.primary : Colors.m3onSurfaceVariant
                }

                MouseArea {
                    id: newChatMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    z: 10
                    onClicked: root.newChatRequested()
                }
            }

            // Sessions List Button
            Rectangle {
                width: 30
                height: 30
                radius: 15
                scale: sessionsMouse.pressed ? 0.92 : (sessionsMouse.containsMouse ? 1.06 : 1.0)
                Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
                color: sessionsMouse.containsMouse ? Colors.glassCardHover : "transparent"
                border.width: sessionsMouse.containsMouse ? 1 : 0
                border.color: Colors.glassBorderSpecular

                MaterialIcon {
                    anchors.centerIn: parent
                    iconName: "history"
                    size: 16
                    color: sessionsMouse.containsMouse ? Colors.primary : Colors.m3onSurfaceVariant
                }

                MouseArea {
                    id: sessionsMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    z: 10
                    onClicked: root.sessionsRequested()
                }
            }

            // Clear Chat Button
            Rectangle {
                width: 30
                height: 30
                radius: 15
                scale: clearMouse.pressed ? 0.92 : (clearMouse.containsMouse ? 1.06 : 1.0)
                Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
                color: clearMouse.containsMouse ? Colors.glassCardHover : "transparent"
                border.width: clearMouse.containsMouse ? 1 : 0
                border.color: Colors.glassBorderSpecular

                MaterialIcon {
                    anchors.centerIn: parent
                    iconName: "refresh"
                    size: 16
                    color: Colors.m3onSurfaceVariant
                }

                MouseArea {
                    id: clearMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    z: 10
                    onClicked: {
                        if (typeof AssistantService !== "undefined") {
                            AssistantService.clearChat();
                        }
                    }
                }
            }

            // Settings Button
            Rectangle {
                width: 30
                height: 30
                radius: 15
                scale: settingsMouse.pressed ? 0.92 : (settingsMouse.containsMouse ? 1.06 : 1.0)
                Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
                color: settingsMouse.containsMouse ? Colors.glassCardHover : "transparent"
                border.width: settingsMouse.containsMouse ? 1 : 0
                border.color: Colors.glassBorderSpecular

                MaterialIcon {
                    anchors.centerIn: parent
                    iconName: "settings"
                    size: 16
                    color: Colors.m3onSurfaceVariant
                }

                MouseArea {
                    id: settingsMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    z: 10
                    onClicked: {
                        if (typeof Config !== "undefined") {
                            Config.openSettings("ai");
                        }
                    }
                }
            }

            // Minimize Button
            Rectangle {
                id: minimizeButton
                width: 30
                height: 30
                radius: 15
                scale: minMouse.pressed ? 0.92 : (minMouse.containsMouse ? 1.06 : 1.0)
                Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
                color: minMouse.containsMouse ? Colors.glassCardHover : "transparent"
                border.width: minMouse.containsMouse ? 1 : 0
                border.color: Colors.glassBorderSpecular

                MaterialIcon {
                    anchors.centerIn: parent
                    iconName: "remove"
                    size: 16
                    color: minMouse.containsMouse ? Colors.primary : Colors.m3onSurfaceVariant
                }

                MouseArea {
                    id: minMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    z: 10
                    onClicked: root.minimizeRequested()
                }
            }

            // Close Button
            Rectangle {
                width: 30
                height: 30
                radius: 15
                scale: closeMouse.pressed ? 0.92 : (closeMouse.containsMouse ? 1.06 : 1.0)
                Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
                color: closeMouse.containsMouse ? Qt.alpha(Colors.m3error, 0.18) : "transparent"
                border.width: closeMouse.containsMouse ? 1 : 0
                border.color: closeMouse.containsMouse ? Qt.alpha(Colors.m3error, 0.40) : "transparent"

                MaterialIcon {
                    anchors.centerIn: parent
                    iconName: "close"
                    size: 16
                    color: closeMouse.containsMouse ? Colors.m3error : Colors.m3onSurfaceVariant
                }

                MouseArea {
                    id: closeMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    z: 10
                    onClicked: root.closeRequested()
                }
            }
        }
    }

    // Interactive button mouse aliases for E2E and automated testing
    property alias harnessMouseItem: harnessMouse
    property alias newChatMouseItem: newChatMouse
    property alias sessionsMouseItem: sessionsMouse
    property alias clearMouseItem: clearMouse
    property alias settingsMouseItem: settingsMouse
    property alias minMouseItem: minMouse
    property alias closeMouseItem: closeMouse
}

