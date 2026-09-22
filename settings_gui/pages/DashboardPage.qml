import QtQuick
import QtQuick.Layouts
import "../controls"
import "../../config"
import "../../theme"
import "../../components"

ColumnLayout {
    id: root

    // Suppresses the real daemon resolve / settings write in offscreen tests;
    // the picker model and pick plumbing remain fully testable.
    property bool testMode: false

    /// `[{ id, name }]` of installed calendar-capable apps (from the daemon).
    property var calendarOptions: []
    /// Desktop id the daemon reports as the system's text/calendar default.
    property string systemDefaultId: ""
    /// Display name of `systemDefaultId`, for the "System default" subtitle.
    property string systemDefaultLabel: ""
    /// Records the last pick and announces it (test plumbing).
    property string lastPickedId: ""
    signal calendarAppPicked(string desktopId)

    /// Persist the pick (blank/`""` = system default).
    function selectCalendarApp(desktopId) {
        const id = (desktopId || "").trim();
        root.lastPickedId = id;
        root.calendarAppPicked(id);
        if (!root.testMode && typeof Config !== "undefined" && Config.setCalendarApp) {
            Config.setCalendarApp(id);
        }
    }

    /// Picker rows: always "System default" first, then every installed option.
    readonly property var calendarPickerOptions: {
        const opts = [{
            id: "",
            name: "System default",
            subtitle: root.systemDefaultLabel !== "" ? ("Now: " + root.systemDefaultLabel) : "Desktop's text/calendar handler"
        }];
        for (let i = 0; i < root.calendarOptions.length; i++) {
            const c = root.calendarOptions[i];
            opts.push({ id: c.id, name: c.name, subtitle: c.id });
        }
        return opts;
    }

    spacing: Theme.spaceMedium

    Text {
        text: "Dashboard & Widgets"
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontTitleMedium
        font.weight: Font.Bold
        color: Colors.m3onSurface
    }

    SettingToggle {
        Layout.fillWidth: true
        title: "Central Popout Dashboard"
        description: "Enable the top-center modal overlay (toggled via dock clock or shortcut)"
        checked: Config.settings.dashboard ? (Config.settings.dashboard.enabled ?? true) : true
        onToggled: val => Config.setDashboardEnabled(val)
    }

    Repeater {
        model: Config.settings.dashboard && Config.settings.dashboard.tabs ? Config.settings.dashboard.tabs : []

        delegate: SettingToggle {
            Layout.fillWidth: true
            title: modelData.label + " Tab"
            description: "Show " + modelData.label + " tab inside the Central Dashboard"
            checked: modelData.enabled
            onToggled: val => Config.setDashboardTabEnabled(modelData.id, val)
        }
    }

    // Calendar App picker (dashboard date click target)
    Rectangle {
        Layout.fillWidth: true
        radius: Theme.radiusMedium
        color: Colors.surfaceContainer
        implicitHeight: calCol.implicitHeight + Theme.padLarge * 2

        ColumnLayout {
            id: calCol
            anchors.fill: parent
            anchors.margins: Theme.padLarge
            spacing: 8

            Text {
                text: "Calendar App"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontBodyMedium
                font.weight: Font.DemiBold
                color: Colors.m3onSurface
            }

            Text {
                Layout.fillWidth: true
                text: "Application opened when clicking a date in the dashboard calendar"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontLabelSmall
                color: Colors.m3onSurfaceVariant
            }

            Repeater {
                model: root.calendarPickerOptions

                delegate: Rectangle {
                    id: calRow
                    required property var modelData
                    required property int index

                    Layout.fillWidth: true
                    implicitHeight: calRowContent.implicitHeight + 16
                    radius: Theme.radiusSmall
                    readonly property bool isSelected: modelData.id ===
                        ((typeof Config !== "undefined") ? Config.calendarApp : "")
                    color: calRow.isSelected
                        ? Qt.alpha(Colors.primary, 0.16)
                        : (calRowMouse.containsMouse ? Qt.alpha(Colors.primary, 0.10) : "transparent")
                    border.color: calRow.isSelected ? Qt.alpha(Colors.primary, 0.45) : "transparent"
                    border.width: 1

                    Behavior on color {
                        ColorAnimation { duration: Theme.animDurationFast }
                    }

                    RowLayout {
                        id: calRowContent
                        anchors.left: parent.left
                        anchors.leftMargin: 12
                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.spaceMedium

                        MaterialIcon {
                            text: calRow.isSelected ? "event_available" : "event"
                            size: 18
                            color: calRow.isSelected ? Colors.primary : Colors.m3onSurfaceVariant
                        }

                        Column {
                            Layout.fillWidth: true
                            spacing: 1

                            Text {
                                width: parent.width
                                text: calRow.modelData.name
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontBodySmall
                                font.weight: calRow.isSelected ? Font.Bold : Font.DemiBold
                                color: Colors.m3onSurface
                                elide: Text.ElideRight
                            }

                            Text {
                                width: parent.width
                                text: calRow.modelData.subtitle
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontLabelSmall
                                color: Colors.m3onSurfaceVariant
                                elide: Text.ElideRight
                            }
                        }

                        MaterialIcon {
                            text: "check"
                            size: 18
                            visible: calRow.isSelected
                            color: Colors.primary
                        }
                    }

                    MouseArea {
                        id: calRowMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        Accessible.role: Accessible.Button
                        Accessible.name: "Use " + calRow.modelData.name + " for calendar dates"
                        onClicked: root.selectCalendarApp(calRow.modelData.id)
                    }
                }
            }
        }
    }

    // Media Visualizer Style setting card
    Rectangle {
        Layout.fillWidth: true
        radius: Theme.radiusMedium
        color: Colors.surfaceContainer
        implicitHeight: vizCol.implicitHeight + Theme.padLarge * 2

        ColumnLayout {
            id: vizCol
            anchors.fill: parent
            anchors.margins: Theme.padLarge
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spaceMedium

                Column {
                    Layout.fillWidth: true
                    spacing: 2

                    Text {
                        text: "Media Visualizer Style"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontBodyMedium
                        font.weight: Font.DemiBold
                        color: Colors.m3onSurface
                    }

                    Text {
                        text: "Select audio visualizer style in the Media tab"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontLabelSmall
                        color: Colors.m3onSurfaceVariant
                    }
                }

                // Material 3 Segmented Pill
                Rectangle {
                    id: pillWrapper
                    implicitHeight: 38
                    implicitWidth: 260
                    radius: Theme.radiusFull
                    color: Colors.surfaceContainerHigh
                    border.color: Theme.borderSubtle
                    border.width: 1

                    readonly property bool isSpeaker: (Config.mediaVisualizerStyle === "speaker" || Config.mediaVisualizerStyle === "heatmap")

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 2
                        spacing: 2

                        // Radial Halo Segment
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            radius: Theme.radiusFull
                            color: !pillWrapper.isSpeaker ? Colors.primaryContainer : (radialHover.containsMouse ? Colors.pillHover : "transparent")
                            border.color: !pillWrapper.isSpeaker ? Qt.alpha(Colors.primary, 0.4) : "transparent"
                            border.width: !pillWrapper.isSpeaker ? 1 : 0

                            Behavior on color { ColorAnimation { duration: Theme.animDurationFast } }

                            Row {
                                anchors.centerIn: parent
                                spacing: 6

                                MaterialIcon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "album"
                                    size: 16
                                    color: !pillWrapper.isSpeaker ? Colors.m3onPrimaryContainer : Colors.m3onSurfaceVariant
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "Radial Halo"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontBodySmall
                                    font.weight: !pillWrapper.isSpeaker ? Font.Bold : Font.Normal
                                    color: !pillWrapper.isSpeaker ? Colors.m3onPrimaryContainer : Colors.m3onSurfaceVariant
                                }
                            }

                            MouseArea {
                                id: radialHover
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Config.setMediaVisualizerStyle("radial")
                            }
                        }

                        // Speaker Segment
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            radius: Theme.radiusFull
                            color: pillWrapper.isSpeaker ? Colors.primaryContainer : (speakerHover.containsMouse ? Colors.pillHover : "transparent")
                            border.color: pillWrapper.isSpeaker ? Qt.alpha(Colors.primary, 0.4) : "transparent"
                            border.width: pillWrapper.isSpeaker ? 1 : 0

                            Behavior on color { ColorAnimation { duration: Theme.animDurationFast } }

                            Row {
                                anchors.centerIn: parent
                                spacing: 6

                                MaterialIcon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "speaker"
                                    size: 16
                                    color: pillWrapper.isSpeaker ? Colors.m3onPrimaryContainer : Colors.m3onSurfaceVariant
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "Speaker"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontBodySmall
                                    font.weight: pillWrapper.isSpeaker ? Font.Bold : Font.Normal
                                    color: pillWrapper.isSpeaker ? Colors.m3onPrimaryContainer : Colors.m3onSurfaceVariant
                                }
                            }

                            MouseArea {
                                id: speakerHover
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Config.setMediaVisualizerStyle("speaker")
                            }
                        }
                    }
                }
            }
        }
    }

    // System Host Card avatar (dashboard info card). The picked file is
    // imported into the app config folder by Config.setHostAvatar, so the
    // image survives deletion of the original source (e.g. ~/Downloads).
    AvatarPathField {
        Layout.fillWidth: true
        title: "System Host Card Avatar"
        description: "Avatar for the dashboard system host card - copied into the app config folder so it survives deleting the original"
        placeholder: "Default (Dino)"
        path: Config.hostAvatar
        interactive: !root.testMode
        showBgOptions: true
        bgColor: (typeof Config !== "undefined" && Config.hostAvatarBg) ? Config.hostAvatarBg : "#ffffff"
        bgOpacity: (typeof Config !== "undefined" && Config.hostAvatarBgOpacity !== undefined && !isNaN(Config.hostAvatarBgOpacity)) ? Number(Config.hostAvatarBgOpacity) : 0.2
        onPathPicked: p => {
            if (!root.testMode && typeof Config !== "undefined" && Config.setHostAvatar) {
                Config.setHostAvatar(p);
            }
        }
        onBgStylePicked: (hex, op) => {
            if (!root.testMode && typeof Config !== "undefined" && Config.setHostAvatarBgColor && Config.setHostAvatarBgOpacity) {
                Config.setHostAvatarBgColor(hex);
                Config.setHostAvatarBgOpacity(op);
            }
        }
    }

    // Media Tab avatar (same durable import pipeline).
    AvatarPathField {
        Layout.fillWidth: true
        title: "Media Tab Avatar"
        description: "Custom avatar file path (GIF, SVG, PNG, JPG, video) - copied into the app config folder so it survives deleting the original"
        placeholder: "Default (Boba Cat)"
        path: Config.mediaAvatar
        interactive: !root.testMode
        onPathPicked: p => {
            if (!root.testMode && typeof Config !== "undefined" && Config.setMediaAvatar) {
                Config.setMediaAvatar(p);
            }
        }
    }

    // Loads the installed calendar-capable apps (with display names) from the
    // daemon: the picker stays data-driven - no application name is hardcoded.
    // The Process lives in its own Quickshell-importing file so this page
    // stays instantiable in the offscreen qml6 harness; testMode keeps the
    // loader detached there.
    Loader {
        id: calResolverLoader
        source: root.testMode ? "" : "CalendarAppResolver.qml"
        onLoaded: {
            if (item) {
                item.optionsLoaded.connect(function (options) {
                    root.calendarOptions = options;
                });
                item.defaultLoaded.connect(function (desktopId, name) {
                    root.systemDefaultId = desktopId;
                    root.systemDefaultLabel = name;
                });
                if (item.start) item.start();
            }
        }
    }
}
