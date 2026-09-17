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

    function syncWithCurrentWallpaper() {
        if (typeof WallpaperEngine === "undefined" || !WallpaperEngine.currentWallpaper) return;
        const current = WallpaperEngine.currentWallpaper;
        for (let i = 0; i < root.wallpapersList.length; i++) {
            if (root.wallpapersList[i].path === current) {
                if (carouselView.currentIndex !== i) {
                    carouselView.currentIndex = i;
                }
                carouselView.positionViewAtIndex(i, ListView.Center);
                return;
            }
        }
    }

    onVisibleChanged: {
        if (visible) {
            syncWithCurrentWallpaper();
        }
    }

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
        clip: false
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

                // Top specular glare line
                Rectangle {
                    anchors.top: parent.top
                    anchors.topMargin: 0.5
                    anchors.left: parent.left
                    anchors.leftMargin: parent.radius * 0.35
                    anchors.right: parent.right
                    anchors.rightMargin: parent.radius * 0.35
                    height: 1
                    color: Colors.glassBorderSpecular
                    opacity: isCurrent ? 0.95 : 0.65
                    z: 5
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
