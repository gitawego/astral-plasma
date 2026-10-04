import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import "../components"
import "../theme"
import "../config"

Item {
    id: root

    property string summary: ""
    property string body: ""
    property string appName: ""
    property string timeStr: "now"
    property string materialIcon: "info"
    property string iconSource: ""
    property string imageSource: ""
    property var actions: []
    property var defaultAction: null
    property bool expanded: false
    property int timeoutMs: 5000

    readonly property var displayActions: {
        let list = [];
        if (root.actions && root.actions.length > 0) {
            for (let i = 0; i < root.actions.length; i++) {
                let act = root.actions[i];
                if (act) list.push(act);
            }
        } else if (root.defaultAction && root.defaultAction.text && root.defaultAction.text.length > 0 && root.defaultAction.text.toLowerCase() !== "default") {
            list.push(root.defaultAction);
        }
        return list;
    }

    function resolveActionIcon(identifier, text) {
        const s = ((identifier || "") + " " + (text || "")).toLowerCase();
        if (s.includes("open") || s.includes("mount") || s.includes("folder") || s.includes("dolphin") || s.includes("browse") || s.includes("dir")) return "folder_open";
        if (s.includes("eject") || s.includes("unmount") || s.includes("remove")) return "eject";
        if (s.includes("play")) return "play_arrow";
        if (s.includes("pause")) return "pause";
        if (s.includes("reply")) return "reply";
        if (s.includes("copy")) return "content_copy";
        if (s.includes("view") || s.includes("show")) return "visibility";
        if (s.includes("settings") || s.includes("configure")) return "settings";
        if (s.includes("download")) return "download";
        if (s.includes("cancel") || s.includes("dismiss")) return "close";
        return "";
    }

    readonly property bool isMediaNotification: {
        let app = (root.appName || "").toLowerCase();
        return Boolean(app.includes("strawberry") ||
                       app.includes("elisa") ||
                       app.includes("cloudmusic") ||
                       app.includes("netease") ||
                       app.includes("music") ||
                       app.includes("player") ||
                       app.includes("spotify") ||
                       root.materialIcon === "music_note");
    }

    readonly property string effectiveCover: {
        let src = (root.imageSource && root.imageSource.length > 0) ? root.imageSource : root.iconSource;
        if (src && src.length > 0) {
            if (src.startsWith("/")) return "file://" + src;
            if (src.startsWith("file://") || src.startsWith("http://") || src.startsWith("https://")) return src;
        }
        return "";
    }
    readonly property bool hasImageCover: effectiveCover.length > 0

    property real borderThickness: (typeof Config !== "undefined" && Config.borderThickness) ? Config.borderThickness : 14
    property real borderRounding: (typeof Theme !== "undefined" && Theme.filletRounding !== undefined) ? Theme.filletRounding : ((typeof Config !== "undefined" && Config.borderRounding) ? Config.borderRounding : 20)

    property bool isDismissed: false

    // --- Authoritative painted extents ---------------------------------
    // The compositor blur mask in UnifiedShell consumes these so it can never
    // overhang the glass. FusedPanel's cardRectangle fills this item's rect
    // exactly (0,0,panelWidth,currentEnvelopeHeight), so the body is simply the
    // panel's own rect - NOT extended by the border rounding.
    //
    // Extending the mask by `borderRounding` on every side (as it previously did)
    // frosted a strip of bare desktop along the bottom and left, where nothing is
    // drawn. The only painted area outside this rect is the single concave corner
    // fillet at the top-left junction, which is a quarter disc living in the top
    // `borderRounding` rows - exposed separately as `shoulderRect` so the mask can
    // cover just that stub instead of a full-height column.
    readonly property real surfaceWidth: width
    readonly property real surfaceHeight: height
    readonly property real surfaceX: x
    readonly property real shoulderWidth: (panel.filletFactor > 0.01) ? borderRounding : 0
    readonly property rect shoulderRect: Qt.rect(
        Math.max(0, x - shoulderWidth), 0,
        shoulderWidth, (panel.filletFactor > 0.01) ? borderRounding : 0)

    readonly property alias fusedPanel: panel
    readonly property alias autoCloseTimer: autoCloseTimer
    readonly property alias cardItem: notifCard
    readonly property alias iconBadgeItem: iconBadge

    signal closed()
    signal defaultActionInvoked()
    signal actionInvoked(var action)

    function toggleExpanded() {
        expanded = !expanded;
    }

    function close() {
        autoCloseTimer.stop();
        root.isDismissed = true;
        root.closed();
    }

    width: 380
    height: panel.panelHeight
    implicitWidth: width
    implicitHeight: height

    Timer {
        id: autoCloseTimer
        interval: root.timeoutMs
        repeat: false
        onTriggered: root.close()
    }

    function resetTimer() {
        if (root.visible && !root.isDismissed && root.timeoutMs > 0 && (!hoverHandler || !hoverHandler.hovered)) {
            autoCloseTimer.restart();
        } else {
            autoCloseTimer.stop();
        }
    }

    onVisibleChanged: {
        if (root.visible) {
            root.isDismissed = false;
        }
        root.resetTimer();
    }

    onSummaryChanged: {
        if (root.visible) {
            root.isDismissed = false;
        }
        root.resetTimer();
    }

    Component.onCompleted: root.resetTimer()

    FusedPanel {
        id: panel
        attachEdge: "topRight"
        panelWidth: root.width
        panelHeight: root.expanded
            ? (expandedContent.implicitHeight + (root.displayActions.length > 0 ? Math.max(26, actionsRow.implicitHeight) + 62 : 52))
            : ((root.displayActions.length > 0)
                ? (root.hasImageCover ? Math.max(116, 76 + actionsRow.implicitHeight) : Math.max(108, 70 + actionsRow.implicitHeight))
                : (root.hasImageCover ? 84 : 78))
        borderThickness: root.borderThickness
        borderRounding: root.borderRounding
        fillColor: (typeof Colors !== "undefined" && Colors.glassSurface) ? Colors.glassSurface : Qt.rgba(0.08, 0.07, 0.10, 1.0)
        borderColor: (typeof Colors !== "undefined" && Colors.glassBorderSpecular) ? Colors.glassBorderSpecular : Qt.rgba(1, 1, 1, 0.12)
        isOpen: root.visible && !root.isDismissed

        Behavior on panelHeight {
            NumberAnimation {
                duration: (typeof Theme !== "undefined" && Theme.animExpressiveDefaultSpatial) ? Theme.animExpressiveDefaultSpatial : 500
                easing.type: Easing.BezierSpline
                easing.bezierCurve: (typeof Theme !== "undefined" && Theme.curveExpressiveDefaultSpatial) ? Theme.curveExpressiveDefaultSpatial : [0.38, 1.21, 0.22, 1.0, 1.0, 1.0]
            }
        }

        HoverHandler {
            id: hoverHandler
            onHoveredChanged: root.resetTimer()
        }

        // Inner Liquid Glass Substrate Card Layer (Sculpted frosted glass plate behind notification)
        LiquidGlassCard {
            id: notifCard
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8 + root.borderThickness
            anchors.topMargin: root.borderThickness + 2
            anchors.bottomMargin: 6
            radius: (typeof Theme !== "undefined" && Theme.radiusGlassCard !== undefined) ? Theme.radiusGlassCard : 14
            elevation: 4
            // No perimeter ring: the notification is a resting container, and its
            // full-bleed silhouette is already defined by the panel's own fused
            // border plus the specular hairlines. A ring here drew a second,
            // smaller rounded box visibly inside the panel.
            showBorder: false
        }

        // Card-wide click area for default action (e.g. click notification to open USB folder)
        MouseArea {
            id: cardClickArea
            anchors.fill: notifCard
            z: 0
            hoverEnabled: true
            cursorShape: (root.defaultAction !== null || root.displayActions.length > 0) ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: {
                root.defaultActionInvoked();
            }
        }

        Item {
            id: contentContainer
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 16 + root.borderThickness
            anchors.topMargin: root.borderThickness + 4
            anchors.bottomMargin: 10



            // Left Icon Badge / Album Art Cover
            Item {
                id: iconBadge
                anchors.left: parent.left
                anchors.top: root.expanded ? parent.top : undefined
                anchors.topMargin: root.expanded ? 4 : 0
                anchors.verticalCenter: root.expanded ? undefined : parent.verticalCenter
                width: root.hasImageCover ? 42 : 36
                height: width

                readonly property int badgeRadius: {
                    if (typeof Theme !== "undefined" && Theme.isCyberpunk) {
                        return 0; // Strictly square in Cyberpunk Neon
                    }
                    if (root.hasImageCover) {
                        return width / 2;
                    }
                    return (typeof Theme !== "undefined" && Theme.radiusSmall !== undefined) ? Theme.radiusSmall : 10;
                }

                // Round / squircle mask geometry
                Rectangle {
                    id: badgeCircleMask
                    anchors.fill: parent
                    radius: iconBadge.badgeRadius
                    color: "white"
                    visible: false
                    layer.enabled: true
                }

                // Frosted glass icon plate
                Rectangle {
                    anchors.fill: parent
                    radius: iconBadge.badgeRadius
                    color: (typeof Colors !== "undefined" && Colors.glassCard) ? Colors.glassCard : Qt.rgba(1, 1, 1, 0.12)
                    border.color: (typeof Theme !== "undefined" && Theme.isCyberpunk)
                        ? Colors.primary
                        : ((typeof Colors !== "undefined" && Colors.glassBorderSpecular) ? Colors.glassBorderSpecular : Qt.rgba(1, 1, 1, 0.25))
                    border.width: 1

                    MaterialIcon {
                        anchors.centerIn: parent
                        text: (root.isMediaNotification || root.hasImageCover) ? "music_note" : root.materialIcon
                        size: root.hasImageCover ? 22 : 19
                        color: (typeof Colors !== "undefined" && Colors.primary) ? Colors.primary : "#d0bcff"
                        visible: !(root.hasImageCover && coverImg.status === Image.Ready)
                    }
                }

                // Cover image masked to shape
                Item {
                    anchors.fill: parent
                    visible: root.hasImageCover && coverImg.status === Image.Ready

                    Image {
                        id: coverImg
                        anchors.fill: parent
                        source: root.effectiveCover
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                    }

                    layer.enabled: iconBadge.badgeRadius > 0
                    layer.effect: MultiEffect {
                        maskEnabled: iconBadge.badgeRadius > 0
                        maskSource: badgeCircleMask
                    }
                }

                // Specular border ring
                Rectangle {
                    anchors.fill: parent
                    radius: iconBadge.badgeRadius
                    color: "transparent"
                    border.color: (typeof Theme !== "undefined" && Theme.isCyberpunk)
                        ? Colors.primary
                        : (root.hasImageCover ? ((typeof Colors !== "undefined" && Colors.glassBorderSpecular) ? Colors.glassBorderSpecular : Qt.rgba(1, 1, 1, 0.4)) : Qt.rgba(1, 1, 1, 0.2))
                    border.width: (typeof Theme !== "undefined" && Theme.isCyberpunk) ? 1.0 : (root.hasImageCover ? 1.5 : 1)
                }
            }

            // Right Content Area
            Item {
                anchors.left: iconBadge.right
                anchors.leftMargin: 12
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.topMargin: 2
                anchors.bottom: parent.bottom

                // Row 1: App Name + Time + Controls
                Row {
                    id: appHeaderRow
                    anchors.left: parent.left
                    anchors.right: headerControls.left
                    anchors.rightMargin: 6
                    anchors.top: parent.top
                    spacing: 6

                    Text {
                        text: (root.appName && root.appName.length > 0) ? root.appName : "System"
                        font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        renderType: Text.QtRendering
                        color: (typeof Colors !== "undefined" && Colors.primary) ? Colors.primary : "#9bcbfb"
                        elide: Text.ElideRight
                    }

                    Text {
                        text: "•"
                        font.pixelSize: 10
                        renderType: Text.QtRendering
                        color: (typeof Colors !== "undefined" && Colors.textMuted) ? Colors.textMuted : "#8F9099"
                    }

                    Text {
                        id: timeText
                        text: root.timeStr
                        font.pixelSize: 11
                        renderType: Text.QtRendering
                        color: (typeof Colors !== "undefined" && Colors.textMuted) ? Colors.textMuted : "#8F9099"
                    }
                }

                // Header Controls (Expand + Close Buttons)
                Row {
                    id: headerControls
                    anchors.right: parent.right
                    anchors.top: parent.top
                    spacing: 4

                    // Expand Chevron Button
                    Rectangle {
                        id: expandBtn
                        width: 22
                        height: 22
                        radius: 11
                        color: expandHover.containsMouse ? ((typeof Colors !== "undefined" && Colors.glassCardHover) ? Colors.glassCardHover : Qt.rgba(1, 1, 1, 0.18)) : "transparent"

                        MaterialIcon {
                            anchors.centerIn: parent
                            text: "expand_more"
                            size: 16
                            color: (typeof Colors !== "undefined" && Colors.textMain) ? Colors.textMain : "#FFFFFF"
                            rotation: root.expanded ? 180 : 0

                            Behavior on rotation {
                                NumberAnimation {
                                    duration: (typeof Theme !== "undefined" && Theme.animExpressiveFastSpatial) ? Theme.animExpressiveFastSpatial : 350
                                    easing.type: Easing.BezierSpline
                                    easing.bezierCurve: (typeof Theme !== "undefined" && Theme.curveExpressiveFastSpatial) ? Theme.curveExpressiveFastSpatial : [0.42, 1.67, 0.21, 0.9, 1.0, 1.0]
                                }
                            }
                        }

                        MouseArea {
                            id: expandHover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.toggleExpanded()
                        }
                    }

                    // Direct Close Button
                    Rectangle {
                        id: headerCloseBtn
                        width: 22
                        height: 22
                        radius: (typeof Theme !== "undefined" && Theme.radiusSmall !== undefined) ? Theme.radiusSmall : 11
                        color: closeBtnHover.containsMouse ? ((typeof Colors !== "undefined" && Colors.glassCardHover) ? Colors.glassCardHover : Qt.rgba(1, 1, 1, 0.18)) : "transparent"

                        MaterialIcon {
                            anchors.centerIn: parent
                            text: "close"
                            size: 15
                            color: (typeof Colors !== "undefined" && Colors.textMain) ? Colors.textMain : "#FFFFFF"
                        }

                        MouseArea {
                            id: closeBtnHover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.close()
                        }
                    }
                }

                // Row 2: Summary / Title
                Text {
                    id: summaryText
                    anchors.left: parent.left
                    anchors.right: headerControls.left
                    anchors.rightMargin: 6
                    anchors.top: appHeaderRow.bottom
                    anchors.topMargin: 2
                    text: root.summary
                    font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    renderType: Text.QtRendering
                    color: (typeof Colors !== "undefined" && Colors.textMain) ? Colors.textMain : "#FFFFFF"
                    elide: Text.ElideRight
                }

                // Row 3: Collapsed Body Preview
                Text {
                    id: bodyPreview
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: summaryText.bottom
                    anchors.topMargin: 2
                    visible: !root.expanded && root.body.length > 0
                    text: root.body
                    textFormat: Text.AutoText
                    onLinkActivated: link => Qt.openUrlExternally(link)
                    font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
                    font.pixelSize: 12
                    renderType: Text.QtRendering
                    color: (typeof Colors !== "undefined" && Colors.textMuted) ? Colors.textMuted : "#c7c6ca"
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }

                // Expanded Content (Full body)
                Column {
                    id: expandedContent
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: summaryText.bottom
                    anchors.topMargin: 4
                    visible: root.expanded
                    spacing: 8
                    z: 5

                    Text {
                        width: parent.width
                        text: root.body
                        textFormat: Text.AutoText
                        onLinkActivated: link => Qt.openUrlExternally(link)
                        font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
                        font.pixelSize: 12
                        renderType: Text.QtRendering
                        color: (typeof Colors !== "undefined" && Colors.textMuted) ? Colors.textMuted : "#c7c6ca"
                        wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                    }
                }

                // Action Buttons Row (Interactive system actions: e.g. USB mount/open, eject, reply, etc.)
                Flow {
                    id: actionsRow
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: root.expanded ? expandedContent.bottom : (bodyPreview.visible ? bodyPreview.bottom : summaryText.bottom)
                    anchors.topMargin: 6
                    spacing: 6
                    visible: (root.displayActions && root.displayActions.length > 0) || root.expanded
                    z: 10

                    Repeater {
                        model: root.displayActions
                        delegate: LiquidGlassButton {
                            implicitHeight: 24
                            paddingHorizontal: 8
                            paddingVertical: 2
                            fontSize: 11
                            minWidth: 0
                            isPrimary: index === 0
                            text: modelData.text || modelData.identifier || "Action"
                            iconText: root.resolveActionIcon(modelData.identifier, modelData.text)
                            iconSize: 13
                            elevation: 2
                            onClicked: {
                                root.actionInvoked(modelData);
                            }
                        }
                    }

                    // Close Button when expanded or if no specific actions were sent
                    LiquidGlassButton {
                        visible: root.expanded || (root.displayActions.length === 0)
                        implicitHeight: 24
                        paddingHorizontal: 8
                        paddingVertical: 2
                        fontSize: 11
                        minWidth: 0
                        iconText: "close"
                        iconSize: 13
                        text: "Close"
                        elevation: 2
                        onClicked: root.close()
                    }
                }
            }
        }
    }
}
