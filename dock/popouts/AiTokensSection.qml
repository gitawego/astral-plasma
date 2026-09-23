import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../components"
import "../../services"
import "../../config"

Item {
    id: root

    implicitWidth: 320
    implicitHeight: mainLayout.implicitHeight + Theme.padLarge * 2

    property bool testMode: false
    property var testProviders: null
    property string testWarningLevel: "normal"
    property int activeProviderIndex: 0

    readonly property var providersList: {
        if (testMode && testProviders !== null) return testProviders;
        if (typeof AiTokenService !== "undefined" && AiTokenService.providers) return AiTokenService.providers;
        return [];
    }

    readonly property string warningLevel: {
        if (testMode) return testWarningLevel;
        if (typeof AiTokenService !== "undefined" && AiTokenService.warningLevel) return AiTokenService.warningLevel;
        return "normal";
    }

    readonly property bool isRefreshing: {
        if (typeof AiTokenService !== "undefined") return AiTokenService.isRefreshing;
        return false;
    }

    // Auto-select provider with the highest used percent when providers change
    onVisibleChanged: {
        if (visible && root.providersList.length > 0) {
            let bestIdx = 0;
            let maxUsed = -1;
            for (let i = 0; i < root.providersList.length; i++) {
                const p = root.providersList[i];
                for (let j = 0; j < (p.windows || []).length; j++) {
                    if (p.windows[j].used_percent > maxUsed) {
                        maxUsed = p.windows[j].used_percent;
                        bestIdx = i;
                    }
                }
            }
            activeProviderIndex = bestIdx;
        }
    }

    readonly property var currentProvider: (root.providersList && root.providersList.length > activeProviderIndex)
        ? root.providersList[activeProviderIndex]
        : null

    ColumnLayout {
        id: mainLayout
        anchors.fill: parent
        anchors.margins: Theme.padLarge
        spacing: Theme.spaceMedium

        // Header: Title & Rescan
        RowLayout {
            Layout.fillWidth: true

            MaterialIcon {
                text: "auto_awesome"
                size: 20
                color: (root.warningLevel === "critical")
                    ? "#E05353"
                    : ((root.warningLevel === "warning") ? "#F59E0B" : Colors.primary)
            }

            ColumnLayout {
                spacing: 1
                Layout.fillWidth: true

                Text {
                    text: "AI Token Quotas"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontTitleSmall
                    font.weight: Font.Bold
                    color: Colors.m3onSurface
                }

                Text {
                    text: (root.warningLevel === "critical")
                        ? "Critical Quota Alert (>= 95%)"
                        : ((root.warningLevel === "warning")
                            ? "Quota Warning (>= 80%)"
                            : "All Quotas Healthy")
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    color: (root.warningLevel === "critical")
                        ? "#E05353"
                        : ((root.warningLevel === "warning") ? "#F59E0B" : Colors.m3onSurfaceVariant)
                }
            }

            // Rescan / Refresh Button
            Rectangle {
                width: 28
                height: 28
                radius: 14
                color: rescanHover.containsMouse ? Colors.pillHover : Colors.surfaceContainerHighest
                border.color: Theme.borderSubtle
                border.width: 1

                MaterialIcon {
                    id: refreshIcon
                    anchors.centerIn: parent
                    text: "refresh"
                    size: 16
                    color: Colors.m3onSurface

                    RotationAnimation on rotation {
                        running: root.isRefreshing
                        from: 0
                        to: 360
                        duration: 800
                        loops: Animation.Infinite
                    }
                }

                MouseArea {
                    id: rescanHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (typeof AiTokenService !== "undefined") {
                            AiTokenService.refresh(true);
                        }
                    }
                }
            }
        }

        // Horizontal Segmented Provider Tabs
        Flickable {
            Layout.fillWidth: true
            Layout.preferredHeight: 32
            visible: root.providersList.length > 1
            contentWidth: providerTabRow.implicitWidth
            contentHeight: height
            boundsBehavior: Flickable.StopAtBounds
            clip: true

            Row {
                id: providerTabRow
                spacing: 6

                Repeater {
                    model: root.providersList
                    delegate: Rectangle {
                        required property var modelData
                        required property int index

                        readonly property bool isSelected: root.activeProviderIndex === index
                        readonly property bool hasWarning: {
                            for (let i = 0; i < (modelData.windows || []).length; i++) {
                                if (modelData.windows[i].used_percent >= (typeof Config !== "undefined" ? Config.aiWarningThreshold : 80)) {
                                    return true;
                                }
                            }
                            return false;
                        }

                        height: 28
                        implicitWidth: tabRow.implicitWidth + 16
                        radius: 14
                        color: isSelected
                            ? (hasWarning ? Qt.alpha("#F59E0B", 0.25) : Colors.primary)
                            : (tabHover.containsMouse ? Colors.pillHover : Colors.surfaceContainer)
                        border.color: isSelected
                            ? (hasWarning ? "#F59E0B" : Colors.primary)
                            : (hasWarning ? "#F59E0B" : Theme.borderSubtle)
                        border.width: 1

                        RowLayout {
                            id: tabRow
                            anchors.centerIn: parent
                            spacing: 4

                            Text {
                                text: modelData.display_name
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                font.weight: isSelected ? Font.Bold : Font.Normal
                                color: isSelected
                                    ? (hasWarning ? "#F59E0B" : Colors.textOnPrimary)
                                    : Colors.m3onSurface
                            }

                            Rectangle {
                                visible: hasWarning
                                width: 6
                                height: 6
                                radius: 3
                                color: "#F59E0B"
                            }
                        }

                        MouseArea {
                            id: tabHover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.activeProviderIndex = index;
                            }
                        }
                    }
                }
            }
        }

        // Provider Details & Identity
        Rectangle {
            Layout.fillWidth: true
            radius: Theme.radiusSmall
            color: Colors.surfaceContainer
            border.color: Theme.borderSubtle
            border.width: 1
            visible: root.currentProvider !== null
            implicitHeight: providerInfoCol.implicitHeight + 16

            ColumnLayout {
                id: providerInfoCol
                anchors.fill: parent
                anchors.margins: 10
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Text {
                        text: root.currentProvider ? root.currentProvider.display_name : ""
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        font.weight: Font.Bold
                        color: Colors.m3onSurface
                    }

                    Item { Layout.fillWidth: true }

                    Rectangle {
                        visible: root.currentProvider && root.currentProvider.plan_type
                        height: 18
                        implicitWidth: planText.implicitWidth + 10
                        radius: 9
                        color: Qt.alpha(Colors.primary, 0.15)
                        border.color: Qt.alpha(Colors.primary, 0.3)
                        border.width: 1

                        Text {
                            id: planText
                            anchors.centerIn: parent
                            text: root.currentProvider ? (root.currentProvider.plan_type || "") : ""
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                            color: Colors.primary
                        }
                    }
                }

                // Active Account Email
                Text {
                    visible: root.currentProvider && (root.currentProvider.account_email || root.currentProvider.account_name)
                    text: root.currentProvider ? (root.currentProvider.account_email || root.currentProvider.account_name || "") : ""
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    color: Colors.m3onSurfaceVariant
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }

                // Gemini Account Switcher (if multiple accounts exist)
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    visible: root.currentProvider && root.currentProvider.provider_id === "gemini" && root.currentProvider.accounts && root.currentProvider.accounts.length > 1

                    Rectangle {
                        Layout.fillWidth: true
                        height: 1
                        color: Theme.borderSubtle
                        opacity: 0.5
                    }

                    Text {
                        text: "Switch Active Account:"
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                        color: Colors.m3onSurfaceVariant
                    }

                    Repeater {
                        model: (root.currentProvider && root.currentProvider.accounts) ? root.currentProvider.accounts : []
                        delegate: Rectangle {
                            required property var modelData
                            Layout.fillWidth: true
                            height: 26
                            radius: 6
                            color: modelData.is_active
                                ? Qt.alpha(Colors.primary, 0.15)
                                : (accHover.containsMouse ? Colors.pillHover : "transparent")
                            border.color: modelData.is_active ? Colors.primary : "transparent"
                            border.width: 1

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 6
                                anchors.rightMargin: 6
                                spacing: 4

                                MaterialIcon {
                                    text: modelData.is_active ? "check_circle" : "account_circle"
                                    size: 14
                                    color: modelData.is_active ? Colors.primary : Colors.m3onSurfaceVariant
                                }

                                Text {
                                    text: modelData.identity || modelData.label
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    font.weight: modelData.is_active ? Font.Bold : Font.Normal
                                    color: modelData.is_active ? Colors.primary : Colors.m3onSurface
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                }

                                Rectangle {
                                    visible: !modelData.is_active
                                    height: 18
                                    implicitWidth: switchLbl.implicitWidth + 8
                                    radius: 4
                                    color: Colors.surfaceContainerHighest
                                    border.color: Theme.borderSubtle
                                    border.width: 1

                                    Text {
                                        id: switchLbl
                                        anchors.centerIn: parent
                                        text: "Switch"
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 9
                                        color: Colors.m3onSurface
                                    }
                                }
                            }

                            MouseArea {
                                id: accHover
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: modelData.is_active ? Qt.ArrowCursor : Qt.PointingHandCursor
                                onClicked: {
                                    if (!modelData.is_active && typeof AiTokenService !== "undefined") {
                                        AiTokenService.switchGeminiAccount(modelData.id || modelData.identity);
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // Quota Limit Progress Windows
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8
            visible: root.currentProvider !== null && root.currentProvider.windows && root.currentProvider.windows.length > 0

            Repeater {
                model: (root.currentProvider && root.currentProvider.windows) ? root.currentProvider.windows : []
                delegate: Rectangle {
                    required property var modelData
                    Layout.fillWidth: true
                    height: 52
                    radius: Theme.radiusSmall
                    color: Colors.surfaceContainer
                    border.color: (modelData.used_percent >= 95)
                        ? "#E05353"
                        : ((modelData.used_percent >= 80) ? "#F59E0B" : Theme.borderSubtle)
                    border.width: 1

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 4

                        RowLayout {
                            Layout.fillWidth: true

                            Text {
                                text: {
                                    switch (modelData.label) {
                                        case "5h": return "5-Hour Rolling Window";
                                        case "weekly": return "Weekly Limit";
                                        case "monthly": return "Monthly Limit";
                                        default: return modelData.label + " Limit";
                                    }
                                }
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                                color: Colors.m3onSurface
                            }

                            Item { Layout.fillWidth: true }

                            Text {
                                text: Math.round(modelData.remaining_percent) + "% remaining"
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                font.weight: Font.Bold
                                color: (modelData.used_percent >= 95)
                                    ? "#E05353"
                                    : ((modelData.used_percent >= 80) ? "#F59E0B" : Colors.primary)
                            }
                        }

                        // Progress Bar Container
                        Rectangle {
                            Layout.fillWidth: true
                            height: 6
                            radius: 3
                            color: Colors.surfaceContainerHighest

                            Rectangle {
                                width: Math.max(0, parent.width * (modelData.used_percent / 100.0))
                                height: parent.height
                                radius: 3
                                color: (modelData.used_percent >= 95)
                                    ? "#E05353"
                                    : ((modelData.used_percent >= 80) ? "#F59E0B" : Colors.primary)

                                Behavior on width {
                                    NumberAnimation { duration: Theme.animDurationNormal }
                                }
                            }
                        }

                        // Reset time
                        Text {
                            visible: modelData.reset_at !== null && modelData.reset_at !== ""
                            text: "Resets at: " + (modelData.reset_at ? modelData.reset_at.replace("T", " ").replace("Z", "") : "")
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                            color: Colors.m3onSurfaceVariant
                        }
                    }
                }
            }
        }

        // Empty state if no providers configured
        Rectangle {
            Layout.fillWidth: true
            height: 90
            radius: Theme.radiusSmall
            color: Colors.surfaceContainer
            border.color: Theme.borderSubtle
            border.width: 1
            visible: !root.providersList || root.providersList.length === 0

            ColumnLayout {
                anchors.centerIn: parent
                spacing: 4

                MaterialIcon {
                    Layout.alignment: Qt.AlignHCenter
                    text: "cloud_off"
                    size: 24
                    color: Colors.m3onSurfaceVariant
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "No configured AI models detected"
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    color: Colors.m3onSurface
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "Run 'agy auth login' or configure OpenCode Go"
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    color: Colors.m3onSurfaceVariant
                }
            }
        }
    }
}
