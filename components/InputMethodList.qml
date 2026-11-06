import QtQuick
import QtQuick.Layouts
import "../theme"
import "../services"

/// The configured input methods, one row each, plus the framework's settings.
///
/// Rows come from `InputMethodService.items` - fcitx5's group or KDE's layout
/// list - never from a hardcoded table. Clicking a row switches to it; the
/// active row is the framework's answer, not the click. The list scrolls when a
/// session has more methods than the drawer can show.
ColumnLayout {
    id: root

    spacing: 4

    readonly property var methods: (typeof InputMethodService !== "undefined") ? InputMethodService.items : []
    readonly property int activeIndex: (typeof InputMethodService !== "undefined") ? InputMethodService.currentIndex : -1

    ListView {
        id: methodList
        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(contentHeight, 220)
        visible: root.methods.length > 0
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: root.methods

        delegate: Rectangle {
            id: row
            required property var modelData
            required property int index

            readonly property bool isActive: index === root.activeIndex

            width: methodList.width
            height: 44
            radius: Theme.radiusMedium
            color: isActive
                ? Colors.primaryContainer
                : (rowHover.hovered ? Colors.surfaceContainerHigh : Colors.surfaceContainer)
            border.width: 1
            border.color: isActive ? Colors.primary : Theme.borderSubtle

            HoverHandler { id: rowHover }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 10
                spacing: 10

                Rectangle {
                    Layout.preferredWidth: 34
                    Layout.preferredHeight: 26
                    radius: 8
                    color: row.isActive ? Colors.primary : Colors.surfaceContainerHighest

                    Text {
                        anchors.centerIn: parent
                        text: row.modelData.badge || ""
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        font.weight: Font.Bold
                        color: row.isActive ? Colors.textOnPrimary : Colors.textOnSurface
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: row.modelData.name || row.modelData.id || ""
                    elide: Text.ElideRight
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSmall
                    font.weight: row.isActive ? Font.DemiBold : Font.Normal
                    color: row.isActive ? Colors.textOnPrimaryContainer : Colors.textOnSurface
                }

                MaterialIcon {
                    visible: row.isActive
                    text: "check"
                    size: 16
                    color: Colors.primary
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (typeof InputMethodService !== "undefined") InputMethodService.setLayout(row.index);
                }
            }
        }
    }

    Text {
        visible: root.methods.length === 0
        Layout.fillWidth: true
        text: "No input method service detected"
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSmall
        color: Colors.textOnSurfaceVariant
    }

    Rectangle {
        id: settingsRow
        Layout.fillWidth: true
        implicitHeight: 38
        radius: Theme.radiusMedium
        color: settingsHover.hovered ? Colors.surfaceContainerHigh : "transparent"

        HoverHandler { id: settingsHover }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            spacing: 10

            MaterialIcon {
                text: "settings"
                size: 16
                color: Colors.textOnSurfaceVariant
            }

            Text {
                Layout.fillWidth: true
                text: (typeof InputMethodService !== "undefined") ? InputMethodService.settingsLabel : "Input Method Settings"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSmall
                color: Colors.textOnSurface
                elide: Text.ElideRight
            }

            MaterialIcon {
                text: "chevron_right"
                size: 16
                color: Colors.textOnSurfaceVariant
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (typeof InputMethodService !== "undefined") InputMethodService.openSettings();
            }
        }
    }
}
