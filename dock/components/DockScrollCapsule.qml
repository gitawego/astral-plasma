import QtQuick
import "../../theme"
import "../../components"

// A dock capsule whose content scrolls when it does not fit.
//
// The taskbar grows with the number of running apps and the tray grows with the
// number of StatusNotifierItems; unbounded, both collide with the modules around
// them. This capsule:
//
//   - never exceeds the `maxHeight` its owner grants it,
//   - snaps its viewport to WHOLE items, so a scroll never stops on half an icon,
//   - honours `maxVisibleItems` when the user caps the list explicitly,
//   - exposes the overflow with a proportional scrollbar thumb and directional
//     end chevrons, so "there is more, scroll" is visible without hovering.
//
// `subtle: true` renders the secondary variant used by the system-tray group
// (flatter, no accent caustic/refraction, inner rim) so app icons and tray icons
// are distinguishable at a glance.
LiquidGlassCard {
    id: root

    // Content goes here: a Repeater (or any Column children).
    default property alias content: listColumn.data

    property int itemSize: 40
    property int itemSpacing: 4
    property int vPad: 10
    // Height budget from the owner. 0 = unclamped.
    property int maxHeight: 0
    // 0 = derive the visible count from maxHeight; > 0 caps it explicitly.
    property int maxVisibleItems: 0
    property bool subtle: false

    // Secondary groups render flatter and with an inner rim.
    showCaustic: !root.subtle
    showRefraction: !root.subtle
    elevation: root.subtle ? 3 : 6

    readonly property real naturalHeight: listColumn.implicitHeight + root.vPad * 2
    readonly property real listHeight: Math.max(0, height - root.vPad * 2)
    readonly property real contentHeight: listColumn.implicitHeight
    readonly property int stride: Math.max(1, root.itemSize + root.itemSpacing)

    // The largest leading prefix of the content that fits the budget, snapped to
    // REAL child boundaries.
    //
    // Children are not uniform: the dock inserts a divider between pinned and
    // unpinned apps, and the Repeaters themselves are zero-height children of the
    // column (they still consume a spacing slot, exactly as Qt's Column lays them
    // out). Counting synthetic `itemSize + itemSpacing` strides therefore came up
    // short and cropped the last icon while forcing the scrollbar, even when the
    // budget easily fitted the whole list.
    function snapPrefix() {
        const budget = (root.maxHeight > 0) ? root.maxHeight : Number.POSITIVE_INFINITY;
        const children = listColumn.children;
        let used = root.vPad * 2;
        let first = true;
        let icons = 0;
        for (let i = 0; i < children.length; i++) {
            const child = children[i];
            if (child.visible === false) continue;
            const h = child.height || 0;
            // Zero-height children (the Repeaters that own the delegates) are not
            // laid out by Qt's Column and must not consume a spacing slot here
            // either - counting them made the snapped height fall short of the
            // content, cropping the last icon and forcing the scrollbar.
            if (h <= 0) continue;
            const isIcon = h >= root.itemSize * 0.8;
            if (root.maxVisibleItems > 0 && isIcon && icons >= root.maxVisibleItems) break;
            const add = first ? h : root.itemSpacing + h;
            if (used + add > budget) break;
            used += add;
            first = false;
            if (isIcon) icons++;
        }
        return { height: used, icons: Math.max(1, icons) };
    }

    readonly property var snapped: root.snapPrefix()
    readonly property real snappedHeight: root.snapped.height
    readonly property int visibleItemCount: root.snapped.icons
    readonly property bool overflowing: root.contentHeight > root.listHeight + 0.5
    readonly property bool atTop: listFlick.contentY <= 0.5
    readonly property bool atBottom: listFlick.contentY >= root.contentHeight - root.listHeight - 0.5

    // Never taller than the granted budget, never taller than the content.
    implicitHeight: Math.min(root.naturalHeight, root.snappedHeight)

    function scrollToTop() { listFlick.contentY = 0; }
    function scrollToBottom() { listFlick.contentY = Math.max(0, root.contentHeight - root.listHeight); }

    // Inner rim for the secondary variant (see `subtle`).
    Rectangle {
        anchors.fill: parent
        anchors.margins: 3
        radius: Math.max(0, parent.radius - 3)
        color: "transparent"
        visible: root.subtle
        border.width: 1
        border.color: (typeof Colors !== "undefined" && Colors.glassBorderSubtle)
            ? Colors.glassBorderSubtle : Qt.rgba(1, 1, 1, 0.18)
    }

    Flickable {
        id: listFlick
        anchors.fill: parent
        anchors.topMargin: root.vPad
        anchors.bottomMargin: root.vPad
        contentWidth: width
        contentHeight: root.contentHeight
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        interactive: root.overflowing

        Column {
            id: listColumn
            anchors.horizontalCenter: parent.horizontalCenter
            y: implicitHeight > parent.height
                ? 0 : Math.max(0, (parent.height - implicitHeight) / 2)
            spacing: root.itemSpacing
        }
    }

    // Scrollbar: a slim track with a proportional thumb, only when scrolling.
    Rectangle {
        id: thumbTrack
        visible: root.overflowing
        anchors.right: parent.right
        anchors.rightMargin: 3
        anchors.top: parent.top
        anchors.topMargin: root.vPad + 4
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.vPad + 4
        width: 3
        radius: 1.5
        color: (typeof Colors !== "undefined" && Colors.outlineVariant)
            ? Qt.alpha(Colors.outlineVariant, 0.35) : Qt.rgba(1, 1, 1, 0.18)
    }

    Rectangle {
        id: thumb
        visible: root.overflowing
        x: thumbTrack.x
        width: thumbTrack.width
        radius: thumbTrack.radius
        color: (typeof Colors !== "undefined" && Colors.primary) ? Colors.primary : "#9bcbfb"
        height: Math.max(18, thumbTrack.height * (root.listHeight / Math.max(1, root.contentHeight)))
        y: thumbTrack.y + (thumbTrack.height - height)
            * (listFlick.contentY / Math.max(1, root.contentHeight - root.listHeight))
    }

    // Directional hints: only the direction with hidden items is shown.
    Rectangle {
        id: moreUp
        visible: root.overflowing && !root.atTop
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: -4
        width: 14
        height: 14
        radius: 7
        color: (typeof Colors !== "undefined" && Colors.glassCard) ? Colors.glassCard : Qt.rgba(0, 0, 0, 0.4)
        border.width: 1
        border.color: (typeof Colors !== "undefined" && Colors.glassBorderSubtle)
            ? Colors.glassBorderSubtle : Qt.rgba(1, 1, 1, 0.2)

        MaterialIcon {
            anchors.centerIn: parent
            text: "keyboard_arrow_up"
            size: 10
            color: (typeof Colors !== "undefined" && Colors.primary) ? Colors.primary : "#9bcbfb"
        }
    }

    Rectangle {
        id: moreDown
        visible: root.overflowing && !root.atBottom
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: -4
        width: 14
        height: 14
        radius: 7
        color: (typeof Colors !== "undefined" && Colors.glassCard) ? Colors.glassCard : Qt.rgba(0, 0, 0, 0.4)
        border.width: 1
        border.color: (typeof Colors !== "undefined" && Colors.glassBorderSubtle)
            ? Colors.glassBorderSubtle : Qt.rgba(1, 1, 1, 0.2)

        MaterialIcon {
            anchors.centerIn: parent
            text: "keyboard_arrow_down"
            size: 10
            color: (typeof Colors !== "undefined" && Colors.primary) ? Colors.primary : "#9bcbfb"
        }
    }

    // Aliases for tests and callers.
    readonly property alias thumbItem: thumb
    readonly property alias thumbTrackItem: thumbTrack
    readonly property alias moreUpItem: moreUp
    readonly property alias moreDownItem: moreDown
    readonly property alias flickable: listFlick
}
