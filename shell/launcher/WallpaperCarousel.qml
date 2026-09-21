import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../components"
import "../../services"

Item {
    id: root

    property bool testMode: false
    property var testModel: []
    property int cardWidth: 210
    property int cardHeight: 130
    property string activeCategory: "All"
    property alias currentIndex: carouselView.currentIndex

    /// Whether the focused card is inside the viewport.
    ///
    /// A card can be the `currentIndex` and still be scrolled out of sight,
    /// which is what "the picker is not focusing my wallpaper" looks like on
    /// screen.
    readonly property bool focusedCardIsVisible: {
        const item = carouselView.currentItem;
        if (!item || carouselView.width <= 0) return false;
        const left = item.x - carouselView.contentX;
        return left < carouselView.width && (left + item.width) > 0;
    }

    readonly property color colPrimary: (typeof Colors !== "undefined" && Colors.primary) ? Colors.primary : "#cba6f7"
    readonly property color colOnPrimary: (typeof Colors !== "undefined" && Colors.onPrimary) ? Colors.onPrimary : "#11111b"
    readonly property color colSurfaceContainerHighest: (typeof Colors !== "undefined" && Colors.surfaceContainerHighest) ? Colors.surfaceContainerHighest : "#282a36"
    readonly property color colSurfaceContainerHigh: (typeof Colors !== "undefined" && Colors.surfaceContainerHigh) ? Colors.surfaceContainerHigh : "#21222c"
    readonly property color colTextOnSurface: (typeof Colors !== "undefined" && Colors.textOnSurface) ? Colors.textOnSurface : "#f8f8f2"
    readonly property color colTextMuted: (typeof Colors !== "undefined" && Colors.textMuted) ? Colors.textMuted : "#6272a4"
    readonly property color colBorderSubtle: (typeof Theme !== "undefined" && Theme.borderSubtle) ? Theme.borderSubtle : "#22ffffff"
    property string searchQuery: ""

    readonly property var rawWallpapersList: {
        if (testMode && testModel.length > 0) return testModel;
        if (typeof WallpaperEngine !== "undefined" && WallpaperEngine.wallpapers && WallpaperEngine.wallpapers.length > 0) {
            return WallpaperEngine.wallpapers;
        }
        return [];
    }

    readonly property var wallpapersList: {
        if (!searchQuery || !searchQuery.trim()) return rawWallpapersList;
        const q = searchQuery.trim().toLowerCase();
        return rawWallpapersList.filter(item => {
            const name = (item.name || "").toLowerCase();
            const cat = (item.category || "").toLowerCase();
            return name.indexOf(q) !== -1 || cat.indexOf(q) !== -1;
        });
    }

    /// The wallpaper the picker must focus: the one applied to the desktop.
    ///
    /// Overridable so the focus contract can be exercised without the
    /// WallpaperEngine singleton (which talks to the daemon).
    property string currentWallpaperSource: (typeof WallpaperEngine !== "undefined") ? WallpaperEngine.currentWallpaper : ""

    onCurrentWallpaperSourceChanged: syncWithCurrentWallpaper()

    /// True while the picker is open but the view has not been laid out yet.
    ///
    /// The modal animates open, and positioning a list that has no size does
    /// nothing - the focused card would then stay off-screen and no card would
    /// look focused at all. The sync is retried as soon as the layout settles.
    property bool pendingFocusSync: false

    /// Identity of a wallpaper file.
    ///
    /// KDE ships a wallpaper as a package directory
    /// (`<package>/contents/images/<resolution>.png`), so the same wallpaper can
    /// be applied as any of several files while the picker lists only one of
    /// them. The package directory - or, for loose images, the file name - is
    /// what makes the applied wallpaper and its card the same wallpaper.
    function wallpaperIdentity(path) {
        if (!path) return "";
        let p = String(path);
        if (p.startsWith("file://")) p = p.substring(7);
        p = p.replace(/\/+$/, "");
        const parts = p.split("/").filter(part => part.length > 0);
        if (parts.length === 0) return "";
        const contents = parts.lastIndexOf("contents");
        if (contents >= 2 && (parts[contents + 1] === "images" || parts[contents + 1] === "wallpaper")) {
            return parts.slice(0, contents).join("/").toLowerCase();
        }
        return parts[parts.length - 1].toLowerCase();
    }

    function syncWithCurrentWallpaper() {
        if (!currentWallpaperSource) return;
        const current = currentWallpaperSource;

        let index = -1;
        for (let i = 0; i < root.wallpapersList.length; i++) {
            if (root.wallpapersList[i].path === current) {
                index = i;
                break;
            }
        }
        if (index < 0) {
            // The exact file may differ: another resolution of the same KDE
            // wallpaper package, or a re-encoded copy of a loose image.
            const identity = wallpaperIdentity(current);
            for (let i = 0; i < root.wallpapersList.length; i++) {
                if (wallpaperIdentity(root.wallpapersList[i].path) === identity) {
                    index = i;
                    break;
                }
            }
        }
        if (index < 0) return;

        if (carouselView.currentIndex !== index) {
            carouselView.currentIndex = index;
        }
        carouselView.positionViewAtIndex(index, ListView.Center);
        if (carouselView.width > 0 && carouselView.height > 0) {
            pendingFocusSync = false;
        }
    }

    onVisibleChanged: {
        if (!visible) {
            pendingFocusSync = false;
            return;
        }
        pendingFocusSync = true;
        syncWithCurrentWallpaper();
    }

    onWidthChanged: if (pendingFocusSync) syncWithCurrentWallpaper()
    onHeightChanged: if (pendingFocusSync) syncWithCurrentWallpaper()

    Connections {
        target: (typeof WallpaperEngine !== "undefined") ? WallpaperEngine : null
        function onCurrentWallpaperChanged() {
            root.syncWithCurrentWallpaper();
        }
        function onWallpapersChanged() {
            root.syncWithCurrentWallpaper();
        }
    }

    Component.onCompleted: {
        syncWithCurrentWallpaper();
    }

    signal wallpaperSelected(string path)
    signal wallpaperPreviewed(string path)
    signal cancelled()

    implicitWidth: 1160
    implicitHeight: 180


    function formatWallpaperName(name, path) {
        let n = name || "";
        if (!n && path) {
            n = path.substring(path.lastIndexOf('/') + 1);
        }
        n = n.replace(/\.[^/.]+$/, "");
        return n.toLowerCase();
    }

    // Horizontal 5-Card Carousel with Smooth Centering
    ListView {
        id: carouselView
        anchors.fill: parent
        orientation: ListView.Horizontal
        spacing: 16
        clip: true
        snapMode: ListView.SnapToItem
        highlightRangeMode: ListView.StrictlyEnforceRange
        preferredHighlightBegin: Math.max(0, (width - root.cardWidth) / 2)
        preferredHighlightEnd: Math.max(0, (width - root.cardWidth) / 2)
        highlightMoveDuration: 250
        boundsBehavior: Flickable.StopAtBounds
        cacheBuffer: 1200
        model: root.wallpapersList

        header: Item {
            width: Math.max(0, (carouselView.width - root.cardWidth) / 2)
            height: 1
        }

        footer: Item {
            width: Math.max(0, (carouselView.width - root.cardWidth) / 2)
            height: 1
        }

        onCurrentIndexChanged: {
            if (currentIndex >= 0 && currentIndex < count) {
                const item = root.wallpapersList[currentIndex];
                if (item && item.path) {
                    if (!root.testMode && typeof WallpaperEngine !== "undefined" && WallpaperEngine.preview) {
                        WallpaperEngine.preview(item.path);
                    }
                    root.wallpaperPreviewed(item.path);
                }
            }
        }

        // Mouse wheel navigation
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.NoButton
            onWheel: (wheel) => {
                if (wheel.angleDelta.y > 0 || wheel.angleDelta.x < 0) {
                    root.selectPrevious();
                } else if (wheel.angleDelta.y < 0 || wheel.angleDelta.x > 0) {
                    root.selectNext();
                }
            }
        }

        delegate: Item {
            id: delegateRoot
            required property var modelData
            required property int index

            width: root.cardWidth
            height: root.cardHeight + 36
            anchors.verticalCenter: parent ? parent.verticalCenter : undefined


            readonly property bool isCurrent: carouselView.currentIndex === index
            readonly property int dist: Math.abs(carouselView.currentIndex - index)

            // Scaled prominent active card, smoothly scaled side cards
            scale: isCurrent ? 1.12 : (dist === 1 ? 0.95 : 0.82)
            opacity: isCurrent ? 1.0 : (dist === 1 ? 0.85 : 0.55)
            z: isCurrent ? 10 : (dist === 1 ? 5 : 1)

            Behavior on scale {
                NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
            }
            Behavior on opacity {
                NumberAnimation { duration: 200 }
            }

            Rectangle {
                id: cardFrame
                anchors.top: parent.top
                anchors.horizontalCenter: parent.horizontalCenter
                width: root.cardWidth
                height: root.cardHeight
                radius: Theme.radiusGlassCard
                color: Colors.glassCard
                border.color: isCurrent ? Colors.primary : (cardHover.containsMouse ? Colors.glassBorderSpecular : Colors.glassBorderSubtle)
                border.width: isCurrent ? 2 : 1
                clip: true

                Image {
                    anchors.fill: parent
                    source: {
                        const p = modelData.thumbnail_path || modelData.path || "";
                        if (!p) return "";
                        return p.startsWith("file://") ? p : ("file://" + p);
                    }
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: true
                    smooth: true
                }



                // Video indicator badge if animated wallpaper
                Rectangle {
                    visible: !!modelData.is_video
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.margins: 6
                    width: 20
                    height: 20
                    radius: 10
                    color: Qt.rgba(0, 0, 0, 0.6)
                    z: 6

                    MaterialIcon {
                        anchors.centerIn: parent
                        text: "videocam"
                        size: 12
                        color: "white"
                    }
                }
            }

            // Lowercase wallpaper name centered directly beneath the card
            Text {
                anchors.top: cardFrame.bottom
                anchors.topMargin: 8
                anchors.horizontalCenter: cardFrame.horizontalCenter
                width: root.cardWidth + 40
                text: root.formatWallpaperName(modelData.name, modelData.path)
                font.pixelSize: 12
                font.weight: isCurrent ? Font.DemiBold : Font.Normal
                color: isCurrent ? "#FFFFFF" : Colors.textMuted
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
            }

            MouseArea {
                id: cardHover
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (carouselView.currentIndex === index) {
                        root.applyCurrent();
                    } else {
                        carouselView.currentIndex = index;
                    }
                }
            }
        }
    }

    function selectNext() {
        if (carouselView.count > 0) {
            carouselView.currentIndex = (carouselView.currentIndex + 1) % carouselView.count;
        }
    }

    function selectPrevious() {
        if (carouselView.count > 0) {
            carouselView.currentIndex = (carouselView.currentIndex - 1 + carouselView.count) % carouselView.count;
        }
    }

    function applyCurrent() {
        if (carouselView.currentIndex >= 0 && carouselView.currentIndex < root.wallpapersList.length) {
            const item = root.wallpapersList[carouselView.currentIndex];
            if (item && item.path) {
                if (!root.testMode && typeof WallpaperEngine !== "undefined" && WallpaperEngine.setWallpaper) {
                    WallpaperEngine.setWallpaper(item.path);
                }
                root.wallpaperSelected(item.path);
            }
        }
    }

    function cancel() {
        if (!root.testMode && typeof WallpaperEngine !== "undefined" && WallpaperEngine.stopPreview) {
            WallpaperEngine.stopPreview();
        }
        root.cancelled();
    }
}
