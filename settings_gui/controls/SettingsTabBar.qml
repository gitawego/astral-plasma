import "../../modules/Astral/Kernel/components"
import "../../modules/Astral/Kernel/theme"
import QtQuick
import QtQuick.Layouts

// ============================================================================
// Atlas tab bar
// ============================================================================
// The one in-section navigation control. Tabs switch content; they never scroll
// the reader to an anchor. Each tab carries an icon and a label, and the active
// tab is marked by a single accent underline.
Row {
    id: root

    property var tabs: []
    property string currentTab: ""
    // Offscreen harnesses have no Quickshell, so `Theme` is absent there. Every
    // token this control measures with gets a local fallback: a NaN spacing or
    // width feeds the Row's polish loop and hangs the whole settings window.
    readonly property real gap: (typeof Theme !== "undefined" && Theme.spaceExtraSmall !== undefined) ? Theme.spaceExtraSmall : 4
    readonly property real pad: (typeof Theme !== "undefined" && Theme.spaceMedium !== undefined) ? Theme.spaceMedium : 12
    readonly property real innerGap: (typeof Theme !== "undefined" && Theme.spaceSmall !== undefined) ? Theme.spaceSmall : 8
    readonly property real tabRadius: (typeof Theme !== "undefined" && Theme.radiusSmall !== undefined) ? Theme.radiusSmall : 8
    readonly property string fontFamilyValue: (typeof Theme !== "undefined" && Theme.fontFamily !== undefined) ? Theme.fontFamily : "sans-serif"
    readonly property color accentColor: (typeof Colors !== "undefined" && Colors.primary !== undefined) ? Colors.primary : "#D0BCFF"
    readonly property color labelColor: (typeof Colors !== "undefined" && Colors.m3onSurfaceVariant !== undefined) ? Colors.m3onSurfaceVariant : "#CAC4D0"
    readonly property color hoverColor: (typeof Colors !== "undefined" && Colors.m3onSurface !== undefined) ? Qt.alpha(Colors.m3onSurface, 0.06) : "#0FFFFFFF"

    signal selected(string tabId)

    spacing: root.gap

    Repeater {
        model: root.tabs

        delegate: Item {
            id: tabItem

            required property var modelData
            readonly property bool active: root.currentTab === modelData.id
            /// Introspection: the label the reader sees, and the action the
            /// click performs. The hub's navigation test presses tabs the
            /// same way it presses the old rail's pills.
            readonly property string label: modelData.label || modelData.id
            readonly property string tabId: modelData.id

            function clicked() {
                root.selected(tabId);
            }

            implicitWidth: tabContent.implicitWidth + root.pad * 2
            implicitHeight: 34

            Rectangle {
                anchors.fill: parent
                radius: root.tabRadius
                color: tabMouse.containsMouse && !tabItem.active ? root.hoverColor : "transparent"
            }

            RowLayout {
                id: tabContent

                anchors.centerIn: parent
                spacing: root.innerGap

                MaterialIcon {
                    visible: modelData.icon !== undefined && modelData.icon !== ""
                    iconName: modelData.icon || ""
                    size: 14
                    color: tabItem.active ? root.accentColor : root.labelColor
                }

                Text {
                    text: modelData.label || modelData.id
                    font.family: root.fontFamilyValue
                    font.pixelSize: 12
                    font.weight: tabItem.active ? Font.DemiBold : Font.Medium
                    color: tabItem.active ? root.accentColor : root.labelColor
                }

            }

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 2
                radius: 1
                color: root.accentColor
                visible: tabItem.active
            }

            MouseArea {
                id: tabMouse

                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: tabItem.clicked()
            }

        }

    }

}
