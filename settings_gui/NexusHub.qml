import QtQuick
import QtQuick.Layouts
import "../theme"
import "../components"
import "../config"
import "pages"
import "SectionSpy.js" as SectionSpy
import "ScrollMotion.js" as ScrollMotion

Item {
    id: root

    property bool testMode: false
    property string activePage: (typeof Config !== "undefined" && Config.activeSettingsPage) ? Config.activeSettingsPage : "wallpaper"
    property var pageHistory: []

    signal closeRequested()

    implicitWidth: 800
    implicitHeight: 560

    function navigateTo(pageId) {
        if (!pageId || pageId === activePage) return;
        let h = pageHistory.slice();
        h.push(activePage);
        pageHistory = h;
        activePage = pageId;
        if (typeof Config !== "undefined") {
            Config.activeSettingsPage = pageId;
        }
    }

    /// A deep link can name a section. Pages opt in by exposing
    /// `sectionY(name)`; the scroll waits for the page layout to settle, because
    /// the target is clamped against the content height.
    property alias contentPaneItem: contentPane
    property alias navRailItem: navRail
    property alias railSeamItem: railSeam
    /// The page currently loaded in the content pane (introspection surface).
    readonly property alias pageItem: pageLoader.item

    /// A zone the reader asked for but that cannot be honoured yet: an external
    /// deep link arrives before the page is even loaded, and a page that has not
    /// been laid out reports every anchor at 0 - the same pre-layout state the
    /// zone offsets exist to defeat. The request is retried from the offsets.
    property string pendingSectionId: ""

    /// The zone the reader last asked for, kept as the highlight until they take
    /// over the scroll themselves.
    ///
    /// A trailing section can sit too low for its anchor to reach the viewport
    /// top - the page runs out of content first - so at the clamped position the
    /// geometry cannot tell "Logging" from "Display", and the pill the reader
    /// pressed would light a *different* one. The reader's own scroll clears this
    /// (see `userScrolled` and the reader-detection below): from then on, the
    /// geometry is the truth again. A name the page does not declare as a zone
    /// (a legacy deep link, e.g. the AI page's `voice`) never becomes an override.
    property string requestedSectionId: ""

    /// True while the hub itself is moving the view, so the reader-detection does
    /// not mistake its own movement for the reader's.
    property bool programmaticScroll: false

    function applyPendingSettingsSection() {
        if (typeof Config === "undefined" || !Config.settingsSection) return;
        const section = Config.settingsSection;
        Config.settingsSection = "";
        root.scrollToSection(section);
    }

    /// Bring a zone of the loaded page into view. One entry point for both the
    /// page's own rail (`zoneRequested`) and external deep links
    /// (`Config.openSettings(page, section)`), so the two cannot diverge.
    ///
    /// The request is parked and honoured from the recomputed offsets - the first
    /// moment we know the page's layout has settled, so its anchors are real.
    function scrollToSection(zoneId) {
        if (!zoneId) return;
        root.pendingSectionId = zoneId;
        root.refreshZoneOffsets();
    }

    /// Honour the parked request now that the offsets are current.
    ///
    /// This runs from the offsets recompute - i.e. after the page's layout pass -
    /// so the page's own `sectionY` is trustworthy here, and it stays the
    /// authority on names: the rail's zones are one vocabulary, and a page may
    /// resolve more (the AI page's legacy `voice` deep link lands on `setup`).
    function applyPendingSection() {
        const zoneId = root.pendingSectionId;
        if (zoneId === "") return;
        const page = pageLoader.item;
        if (page && typeof page.sectionY === "function") {
            const y = page.sectionY(zoneId);
            if (y !== undefined && y !== null && !isNaN(y)) {
                root.pendingSectionId = "";
                root.requestedSectionId = zoneId;
                root.scrollTo(y);
                return;
            }
        }
        // A loaded page that declares zones and does not resolve this name will
        // never honour the request; drop it. A page that is not loaded yet can,
        // so the request waits for it instead.
        if (page !== null && root.pageZones.length > 0) {
            root.pendingSectionId = "";
        }
    }

    /// Wire the loaded page's rail to the hub.
    ///
    /// The page emits `zoneRequested` when a pill is pressed; the hub owns the
    /// scroll area, so it is the one that moves it. Connecting here (rather than
    /// having pages write a global the hub polls) is what makes a dead rail a
    /// test failure instead of a silent no-op.
    function bindPageNavigation() {
        const page = pageLoader.item;
        if (page && page.zoneRequested !== undefined
                && typeof page.zoneRequested.connect === "function") {
            page.zoneRequested.connect(root.scrollToSection);
        }
    }

    Connections {
        target: (typeof Config !== "undefined") ? Config : null
        function onSettingsSectionChanged() { root.applyPendingSettingsSection(); }
    }

    Connections {
        target: pageFlickable
        function onContentHeightChanged() {
            root.refreshZoneOffsets();
        }
        /// Anything but the hub's own movement means the reader is scrolling: the
        /// request highlight is dropped and the geometry takes over again.
        function onContentYChanged() {
            if (!root.programmaticScroll) root.requestedSectionId = "";
        }
        function onMovingChanged() {
            if (pageFlickable.moving) root.requestedSectionId = "";
        }
    }

    function goBack() {
        if (pageHistory.length > 0) {
            let h = pageHistory.slice();
            const prev = h.pop();
            pageHistory = h;
            activePage = prev;
            if (typeof Config !== "undefined") {
                Config.activeSettingsPage = prev;
            }
        }
    }

    /// Smoothly bring `y` to the top of the viewport.
    ///
    /// Programmatic only: the animation is a spatial transition (DESIGN.md token
    /// ladder, damped for long distances), and it is stopped the instant the user
    /// wheels or drags - a scroll that fights the reader is worse than a jump.
    /// When no motion tokens are available (the offscreen harness has no Theme),
    /// the view jumps to the target instead: `ScrollMotion.motionFor` returns
    /// nothing to honour, and inventing a duration here would fork the design's
    /// motion into a second source of truth.
    function scrollTo(y) {
        const max = Math.max(0, pageFlickable.contentHeight - pageFlickable.height);
        const target = Math.max(0, Math.min(max, y));
        const distance = target - pageFlickable.contentY;
        if (Math.abs(distance) < 2) {
            pageFlickable.contentY = target;
            return;
        }
        const motion = ScrollMotion.motionFor(root.motionTokens, distance);
        if (!motion) {
            root.programmaticScroll = true;
            pageFlickable.contentY = target;
            root.programmaticScroll = false;
            return;
        }
        sectionScrollAnim.stop();
        sectionScrollAnim.from = pageFlickable.contentY;
        sectionScrollAnim.to = target;
        sectionScrollAnim.duration = motion.duration;
        sectionScrollAnim.easing.bezierCurve = motion.curve;
        root.programmaticScroll = true;
        sectionScrollAnim.start();
    }

    /// The reader is driving the scroll (wheel or trackpad): drop the in-flight
    /// programmatic scroll and the request highlight instead of fighting them -
    /// the geometry is the truth from here on.
    function userScrolled(deltaY) {
        sectionScrollAnim.stop();
        root.requestedSectionId = "";
        pageFlickable.contentY = Math.max(0, Math.min(root.contentMaxOffset,
                                                     pageFlickable.contentY - deltaY));
    }

    /// The scroll animation. `NumberAnimation` on the flickable's own contentY is
    /// the one property that can be animated without touching its bounds handling.
    NumberAnimation {
        id: sectionScrollAnim
        target: pageFlickable
        property: "contentY"
        easing.type: Easing.BezierSpline
        onStopped: root.programmaticScroll = false
    }

    readonly property bool canGoBack: pageHistory.length > 0

    /// Motion for a programmatic scroll.
    ///
    /// Bound to the shell's motion tokens (`Theme`, the single source of truth per
    /// DESIGN.md); a property rather than a bare `Theme.` read for two reasons:
    /// the offscreen harness has no Quickshell, so it cannot load `Theme` and can
    /// supply the tokens itself - which is what lets the tween, not just its maths,
    /// be asserted - and a future reduced-motion mode has exactly one seam.
    property var motionTokens: Theme

    /// Introspection surface for the content pane's scroll state (tests, and any
    /// future scrollbar work): where the viewport is, how far it can go, and
    /// whether a programmatic scroll is running.
    readonly property real contentOffset: pageFlickable.contentY
    readonly property real contentMaxOffset: Math.max(0, pageFlickable.contentHeight - pageFlickable.height)
    readonly property bool scrollAnimating: sectionScrollAnim.running
    readonly property int scrollAnimationDuration: sectionScrollAnim.duration

    // --- Sticky header + scroll spy -----------------------------------------
    // A page may provide its identity as a `stickyHeader` component: the hub then
    // renders it *outside* the flickable, so the title and the state rail stay put
    // while the zones scroll. The same zones drive the spy that tells the page
    // which section the reader is in - so the rail can highlight it.
    readonly property var pageStickyHeader: (pageLoader.item && pageLoader.item.stickyHeader)
        ? pageLoader.item.stickyHeader : null
    readonly property var pageZones: (pageLoader.item && pageLoader.item.zones) ? pageLoader.item.zones : []

    /// Anchor of every zone the loaded page declares, in page coordinates.
    ///
    /// Recomputed, not bound to the page's shape: a binding would snapshot the
    /// layout at one instant, and a page that is not laid out yet reports every
    /// anchor at y=0 - which is how the rail used to highlight the *last* zone
    /// on a short page (all offsets 0, so the spy picks the last one). The
    /// recompute below is therefore driven by every event that can move an
    /// anchor: the page being installed, its zones changing with its state, its
    /// own height settling, and the flickable's content height changing.
    property var pageZoneOffsets: ({})

    function recomputeZoneOffsets() {
        const page = pageLoader.item;
        const zones = root.pageZones;
        const offsets = {};
        if (page && zones && typeof page.sectionY === "function") {
            for (let i = 0; i < zones.length; ++i) {
                const y = page.sectionY(zones[i].id);
                if (y !== undefined && y !== null && !isNaN(y)) offsets[zones[i].id] = y;
            }
        }
        root.pageZoneOffsets = offsets;
    }

    /// Deferred by a turn of the event loop: the page's layout pass (which is
    /// what assigns the anchor positions) runs after the height that announces
    /// it, so asking immediately would still read the pre-layout geometry.
    function refreshZoneOffsets() {
        Qt.callLater(root.recomputeZoneOffsets);
    }

    onPageZonesChanged: root.refreshZoneOffsets()

    /// The recompute is what tells a parked zone request that the page's layout
    /// is now known - the offsets always arrive as a fresh object, so this fires
    /// even when the numbers are unchanged (a rail click on an already-settled
    /// page).
    onPageZoneOffsetsChanged: root.applyPendingSection()

    Connections {
        target: pageLoader
        function onItemChanged() {
            root.requestedSectionId = "";
            // A new page opens at its top: keeping the previous page's offset
            // would drop the reader into the middle (or the clamped end) of a page
            // they have not seen. A deep link's section request is parked, so it
            // survives this reset and scrolls once the layout settles.
            pageFlickable.contentY = 0;
            root.bindPageNavigation();
            root.refreshZoneOffsets();
            root.syncSectionToPage();
        }
    }

    Connections {
        target: pageLoader.item
        function onImplicitHeightChanged() { root.refreshZoneOffsets(); }
    }

    /// The zone the reader is looking at: the one they asked for while that
    /// request is still the reason the view is where it is, and otherwise the
    /// geometry. 16px of slack, so a zone is current as soon as its header
    /// touches the pinned header; `endOffset` handles the trailing section, which
    /// cannot scroll its anchor to the top.
    readonly property string activePageSection: {
        const requested = root.requestedSectionId;
        if (requested !== "" && root.pageZoneOffsets[requested] !== undefined) return requested;
        return SectionSpy.sectionAt(root.pageZones, root.pageZoneOffsets,
                                    pageFlickable.contentY + 16,
                                    pageFlickable.contentHeight - pageFlickable.height);
    }

    function syncSectionToPage() {
        const page = pageLoader.item;
        if (page && page.currentSection !== undefined) {
            page.currentSection = root.activePageSection;
        }
    }

    onActivePageSectionChanged: root.syncSectionToPage()

    // Categories structure
    readonly property var navigationSections: [
        {
            title: "Personalization",
            items: [
                { id: "wallpaper", label: "Wallpaper & Style", icon: "wallpaper" },
                { id: "theme", label: "Appearance", icon: "palette" }
            ]
        },
        {
            title: "Connectivity",
            items: [
                { id: "network", label: "Wi-Fi & Network", icon: "wifi" },
                { id: "bluetooth", label: "Bluetooth", icon: "bluetooth" },
                { id: "ai", label: "AI Token Plans", icon: "psychology" }
            ]
        },
        {
            title: "Hardware",
            items: [
                { id: "audio", label: "Sound & Audio", icon: "volume_up" }
            ]
        },
        {
            title: "Desktop Shell",
            items: [
                { id: "dock", label: "Dock & Layout", icon: "dashboard" },
                { id: "status", label: "Status Icons", icon: "tune" },
                { id: "dashboard", label: "Dashboard Tabs", icon: "calendar_month" },
                { id: "downloads", label: "Downloads", icon: "download" }
            ]
        },
        {
            title: "System",
            items: [
                { id: "system", label: "System & Services", icon: "memory" }
            ]
        }
    ]

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // Left Navigation Rail.
        //
        // A rail, not a card: it is a tinted strip inside the window's single
        // plate, closed by one hairline. Giving it its own radius and substrate
        // made it a second panel butted against the content, with the wallpaper
        // showing through the corner notches between them.
        Rectangle {
            id: navRail
            Layout.preferredWidth: 250
            Layout.minimumWidth: 250
            Layout.fillHeight: true
            color: (typeof Colors !== "undefined")
                ? (Colors.isDarkMode ? Qt.rgba(1, 1, 1, 0.03) : Qt.rgba(0, 0, 0, 0.02))
                : "transparent"
            clip: true

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Theme.padLarge
                spacing: Theme.spaceMedium

                // Hub Header & Drag Handle
                Item {
                    Layout.fillWidth: true
                    height: 32
                    clip: true

                    RowLayout {
                        anchors.fill: parent
                        spacing: Theme.spaceSmall

                        MaterialIcon {
                            text: "tune"
                            size: 22
                            color: Colors.primary
                        }

                        Text {
                            text: "Nexus Settings"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontTitleSmall
                            font.weight: Font.Bold
                            color: Colors.m3onSurface
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }

                        MaterialIcon {
                            text: "drag_indicator"
                            size: 18
                            color: hubHeaderHover.containsMouse ? Colors.primary : Colors.m3onSurfaceVariant
                            opacity: hubHeaderHover.containsMouse ? 1.0 : 0.4
                            Behavior on opacity { NumberAnimation { duration: 150 } }
                        }
                    }

                    MouseArea {
                        id: hubHeaderHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.OpenHandCursor
                        acceptedButtons: Qt.NoButton
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: Theme.borderSubtle
                }

                // Categorized Navigation List
                Flickable {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    contentHeight: navCol.implicitHeight
                    clip: true

                    Column {
                        id: navCol
                        width: parent.width - 4
                        x: 2
                        spacing: 12

                        Repeater {
                            model: root.navigationSections
                            delegate: Column {
                                required property var modelData
                                width: parent.width
                                spacing: 4

                                // Section Title
                                Text {
                                    text: modelData.title.toUpperCase()
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 10
                                    font.weight: Font.Bold
                                    color: Colors.m3onSurfaceVariant
                                    leftPadding: 8
                                    topPadding: 4
                                    bottomPadding: 2
                                }

                                Repeater {
                                    model: modelData.items
                                    delegate: PillButton {
                                        required property var modelData
                                        width: parent.width
                                        label: modelData.label
                                        iconText: modelData.icon
                                        active: root.activePage === modelData.id
                                        onClicked: root.navigateTo(modelData.id)
                                    }
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: Theme.borderSubtle
                }

                // Close Button
                PillButton {
                    Layout.fillWidth: true
                    label: "Close"
                    iconText: "close"
                    active: false
                    onClicked: root.closeRequested()
                }
            }
        }

        // The seam: one hairline, inset from the plate's edges, in the same
        // specular family as every other divider in the shell.
        Rectangle {
            id: railSeam
            Layout.fillHeight: true
            Layout.topMargin: Theme.padLarge
            Layout.bottomMargin: Theme.padLarge
            width: 1
            color: (typeof Colors !== "undefined") ? Qt.alpha(Colors.glassBorderSpecular, 0.35) : "#33ffffff"
        }

        // Right Content Pane with Breadcrumb Drill-down Header.
        //
        // It carries the same readable substrate as the Copilot card: a page of
        // options behind a fully transparent block disappears into a bright
        // wallpaper, which is exactly how the settings page read before.
        Rectangle {
            id: contentPane
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: "transparent"
            clip: true

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Theme.padExtraLarge
                spacing: Theme.spaceMedium

                // Breadcrumb Header
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    visible: root.canGoBack

                    Rectangle {
                        width: 32
                        height: 32
                        radius: (typeof Theme !== "undefined" && Theme.radiusGlassPill !== undefined) ? Math.min(Theme.radiusGlassPill, 16) : 16
                        color: backHover.containsMouse ? Colors.pillHover : "transparent"
                        border.color: (typeof Theme !== "undefined" && Theme.surfaceStyle === "neon_cyber") ? Qt.alpha(Colors.primary, 0.40) : Theme.borderSubtle
                        border.width: 1
                        z: 10

                        MaterialIcon {
                            anchors.centerIn: parent
                            text: "arrow_back"
                            size: 16
                            color: Colors.m3onSurface
                        }

                        MouseArea {
                            id: backHover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.goBack()
                        }
                    }

                    Text {
                        text: "Back"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontBodySmall
                        font.weight: Font.DemiBold
                        color: Colors.primary
                    }

                    Item { Layout.fillWidth: true }
                }

                // Pinned page header: provided by the page, rendered here so it
                // never scrolls away with the content. It carries its own surface
                // and a hairline: content scrolling underneath must pass *behind*
                // the header, not through it.
                Rectangle {
                    id: stickyHeaderSurface
                    Layout.fillWidth: true
                    visible: root.pageStickyHeader !== null
                    implicitHeight: stickyHeaderLoader.implicitHeight + Theme.spaceSmall * 2
                    color: Colors.surfaceContainer

                    Rectangle {
                        anchors.bottom: parent.bottom
                        width: parent.width
                        height: 1
                        color: Theme.borderSubtle
                        opacity: 0.6
                    }

                    Loader {
                        id: stickyHeaderLoader
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.rightMargin: 14
                        anchors.top: parent.top
                        anchors.topMargin: Theme.spaceSmall
                        sourceComponent: root.pageStickyHeader
                    }
                }

                // Page Scrollable Content Container
                Flickable {
                    id: pageFlickable
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    contentWidth: width
                    contentHeight: Math.max(height, pageLoader.item ? pageLoader.item.implicitHeight : pageLoader.implicitHeight)
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    WheelHandler {
                        target: pageFlickable
                        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                        onWheel: (event) => root.userScrolled(event.angleDelta.y)
                    }

                    Loader {
                        id: pageLoader
                        width: parent.width - 14
                        height: item ? item.implicitHeight : implicitHeight
                        onLoaded: {
                            root.applyPendingSettingsSection();
                            root.syncSectionToPage();
                        }
                        sourceComponent: {
                            switch (root.activePage) {
                                case "wallpaper":
                                case "wallpaper_style": return wallpaperPageComp;
                                case "theme":
                                case "appearance": return themePageComp;
                                case "network": return networkPageComp;
                                case "bluetooth": return bluetoothPageComp;
                                case "ai": return aiPageComp;
                                case "audio": return audioPageComp;
                                case "dock": return dockPageComp;
                                case "status": return statusPageComp;
                                case "dashboard": return dashPageComp;
                                case "downloads": return downloadsPageComp;
                                case "system": return systemPageComp;
                                default: return wallpaperPageComp;
                            }
                        }
                    }

                    // Slim Material 3 Scroll Indicator
                    Rectangle {
                        id: scrollBarIndicator
                        anchors.right: parent.right
                        anchors.rightMargin: 4
                        readonly property real scrollableRange: Math.max(1, pageFlickable.contentHeight - pageFlickable.height)
                        readonly property real thumbTravelRange: Math.max(0, pageFlickable.height - height)
                        y: pageFlickable.contentY + (pageFlickable.contentHeight > pageFlickable.height 
                            ? (pageFlickable.contentY / scrollableRange) * thumbTravelRange 
                            : 0)
                        width: 4
                        height: pageFlickable.contentHeight > pageFlickable.height 
                            ? Math.max(28, (pageFlickable.height / pageFlickable.contentHeight) * pageFlickable.height) 
                            : 0
                        radius: 2
                        color: Colors.primary
                        opacity: pageFlickable.moving || pageFlickable.contentHeight > pageFlickable.height ? 0.45 : 0.0
                        visible: pageFlickable.contentHeight > pageFlickable.height
                        Behavior on opacity { NumberAnimation { duration: 150 } }
                    }
                }
            }
        }
    }

    // Lazy Loaded Page Components
    Component { id: wallpaperPageComp; WallpaperAndStylePage { testMode: root.testMode } }
    Component { id: themePageComp; ThemePage {} }
    Component { id: networkPageComp; NetworkPage { testMode: root.testMode } }
    Component { id: bluetoothPageComp; BluetoothPage { testMode: root.testMode } }
    Component { id: aiPageComp; AiPage { testMode: root.testMode } }
    Component { id: audioPageComp; AudioPage { testMode: root.testMode } }
    Component { id: dockPageComp; DockPage {} }
    Component { id: statusPageComp; StatusIconsPage {} }
    Component { id: dashPageComp; DashboardPage { testMode: root.testMode } }
    Component { id: downloadsPageComp; DownloadsPage { testMode: root.testMode } }
    Component { id: systemPageComp; SystemPage { testMode: root.testMode } }
}
