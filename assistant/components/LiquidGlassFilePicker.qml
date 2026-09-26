import QtQuick
import QtQuick.Layouts
import Qt.labs.folderlistmodel
import "../../theme"
import "../../components"

Rectangle {
    id: root

    signal accepted(var files)
    signal canceled()
    signal userDragged()

    property Item dragTarget: null

    color: Qt.rgba(0, 0, 0, 0.65)
    anchors.fill: parent
    z: 250

    property string homeDir: {
        if (typeof Quickshell !== "undefined" && Quickshell.env && Quickshell.env("HOME")) {
            return Quickshell.env("HOME");
        }
        return "/home/hlu";
    }

    property string currentFolder: homeDir + "/Downloads"
    property var selectedFiles: []
    property string searchQuery: ""

    // Sorting & View Size Controls
    property int sortField: FolderListModel.Name
    property bool sortReversed: false
    property string viewMode: "grid_medium" // "grid_small", "grid_medium", "grid_large", "list"
    property int filterCategory: 0 // 0: All Files, 1: Images, 2: Code, 3: Documents

    readonly property var sortOptions: [
        { name: "Name", field: FolderListModel.Name },
        { name: "Date", field: FolderListModel.Time },
        { name: "Size", field: FolderListModel.Size },
        { name: "Type", field: FolderListModel.Type }
    ]

    readonly property var filterOptions: [
        { name: "All Files", filters: ["*"] },
        { name: "Images", filters: ["*.png", "*.jpg", "*.jpeg", "*.webp", "*.svg", "*.gif", "*.bmp", "*.PNG", "*.JPG", "*.JPEG", "*.WEBP", "*.SVG", "*.GIF", "*.BMP"] },
        { name: "Code", filters: ["*.rs", "*.py", "*.js", "*.ts", "*.qml", "*.json", "*.toml", "*.yaml", "*.yml", "*.sh", "*.css", "*.html", "*.md", "*.txt"] },
        { name: "Docs", filters: ["*.pdf", "*.doc", "*.docx", "*.odt", "*.csv", "*.log", "*.zip", "*.tar", "*.gz"] }
    ]

    function isImageFile(path) {
        if (!path) return false;
        return /\.(png|jpg|jpeg|webp|svg|gif|bmp)$/i.test(path);
    }

    function getFileExtension(path) {
        if (!path) return "FILE";
        let parts = path.split(".");
        if (parts.length > 1) {
            return parts[parts.length - 1].toUpperCase().substring(0, 4);
        }
        return "FILE";
    }

    function formatTime(timestamp) {
        if (!timestamp) return "";
        let d = new Date(timestamp);
        return d.toLocaleDateString();
    }

    readonly property var quickPlaces: [
        { name: "Downloads", icon: "download", path: root.homeDir + "/Downloads" },
        { name: "Pictures", icon: "image", path: root.homeDir + "/Pictures" },
        { name: "Screenshots", icon: "picture_in_picture", path: root.homeDir + "/Pictures/Screenshots" },
        { name: "Desktop", icon: "desktop_windows", path: root.homeDir + "/Desktop" },
        { name: "Home", icon: "home", path: root.homeDir },
        { name: "Temp (/tmp)", icon: "folder", path: "/tmp" }
    ]

    function selectFolder(path) {
        if (!path) return;
        let clean = String(path).trim();
        if (clean.startsWith("file://")) clean = clean.substring(7);
        currentFolder = clean;
        selectedFiles = [];
    }

    function toggleSelectFile(path) {
        if (!path) return;
        let clean = String(path).trim();
        if (clean.startsWith("file://")) clean = clean.substring(7);
        let list = selectedFiles.slice();
        let idx = list.indexOf(clean);
        if (idx >= 0) {
            list.splice(idx, 1);
        } else {
            list.push(clean);
        }
        selectedFiles = list;
    }

    function isSelected(path) {
        if (!path) return false;
        let clean = String(path).trim();
        if (clean.startsWith("file://")) clean = clean.substring(7);
        return selectedFiles.indexOf(clean) !== -1;
    }

    function submitSelection() {
        if (selectedFiles.length > 0) {
            root.accepted(selectedFiles.slice());
            selectedFiles = [];
        }
    }

    function formatSize(bytes) {
        if (!bytes || bytes <= 0) return "0 B";
        if (bytes < 1024) return bytes + " B";
        if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + " KB";
        return (bytes / (1024 * 1024)).toFixed(1) + " MB";
    }

    // Dismiss when clicking outside modal card
    MouseArea {
        anchors.fill: parent
        onClicked: root.canceled()
    }

    // Modal Liquid Glass Card
    Rectangle {
        id: dialogCard
        anchors.centerIn: parent
        width: Math.min(parent.width - 24, 760)
        height: Math.min(parent.height - 24, 560)
        radius: (typeof Theme !== "undefined") ? Theme.radiusGlassModal : 20
        clip: true

        color: {
            if (typeof Colors === "undefined") return "#1e1e2e";
            let base = Colors.isDarkMode ? Qt.rgba(0.09, 0.10, 0.15, 0.96) : Qt.rgba(0.96, 0.97, 1.0, 0.97);
            return Qt.tint(base, Qt.alpha(Colors.primary, Colors.isDarkMode ? 0.05 : 0.03));
        }

        border.width: 1
        border.color: Colors.glassBorderSpecular

        // Consume clicks inside dialog card
        MouseArea {
            anchors.fill: parent
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // 1. Header Bar
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 52
                color: "transparent"

                // Header drag area allowing dragging the floating window from file picker
                MouseArea {
                    anchors.fill: parent
                    z: -1
                    drag.target: root.dragTarget
                    drag.axis: Drag.XAndYAxis
                    onPositionChanged: {
                        if (drag.active) {
                            root.userDragged();
                        }
                    }
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    spacing: 12

                    // Icon & Title
                    RowLayout {
                        spacing: 8

                        Rectangle {
                            width: 32
                            height: 32
                            radius: 8
                            color: Colors.primaryContainer

                            MaterialIcon {
                                anchors.centerIn: parent
                                iconName: "attach_file"
                                size: 16
                                color: Colors.primary
                            }
                        }

                        Text {
                            text: "Select Files to Attach"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontTitleSmall
                            font.weight: Font.DemiBold
                            color: Colors.m3onSurface
                        }
                    }

                    Item { Layout.fillWidth: true }

                    // Search / Filter Input
                    Rectangle {
                        implicitWidth: 170
                        implicitHeight: 32
                        radius: 8
                        color: Colors.surfaceContainerHighest
                        border.width: 1
                        border.color: searchInput.activeFocus ? Colors.primary : Colors.glassBorderSpecular

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 6

                            MaterialIcon {
                                iconName: "search"
                                size: 14
                                color: Colors.m3onSurfaceVariant
                            }

                            TextInput {
                                id: searchInput
                                Layout.fillWidth: true
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                color: Colors.m3onSurface
                                clip: true
                                onTextChanged: root.searchQuery = text.trim().toLowerCase()

                                Text {
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: !searchInput.text && !searchInput.activeFocus
                                    text: "Filter files..."
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    color: Colors.m3onSurfaceVariant
                                }
                            }

                            MouseArea {
                                width: 14
                                height: 14
                                visible: searchInput.text.length > 0
                                cursorShape: Qt.PointingHandCursor
                                onClicked: searchInput.text = ""

                                MaterialIcon {
                                    anchors.centerIn: parent
                                    iconName: "close"
                                    size: 12
                                    color: Colors.m3onSurfaceVariant
                                }
                            }
                        }
                    }

                    // Close Button
                    Rectangle {
                        width: 30
                        height: 30
                        radius: 8
                        color: closeMouse.containsMouse ? Qt.rgba(1, 0.2, 0.2, 0.2) : "transparent"

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
                            onClicked: root.canceled()
                        }
                    }
                }

                Rectangle {
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 1
                    color: Colors.glassBorderSpecular
                }
            }

            // 2. Breadcrumb Navigation Bar
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 38
                color: Qt.rgba(0, 0, 0, 0.15)

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 6

                    // Up / Parent Directory Button
                    Rectangle {
                        width: 26
                        height: 26
                        radius: 6
                        color: upMouse.containsMouse ? Colors.glassCardHover : "transparent"
                        border.width: 1
                        border.color: Colors.glassBorderSpecular

                        MaterialIcon {
                            anchors.centerIn: parent
                            iconName: "arrow_upward"
                            size: 13
                            color: Colors.m3onSurface
                        }

                        MouseArea {
                            id: upMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                let p = root.currentFolder;
                                if (p.length > 1) {
                                    let lastSlash = p.lastIndexOf("/");
                                    if (lastSlash > 0) {
                                        root.selectFolder(p.substring(0, lastSlash));
                                    } else if (lastSlash === 0) {
                                        root.selectFolder("/");
                                    }
                                }
                            }
                        }
                    }

                    // Path Segments Breadcrumb
                    Flickable {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        contentWidth: breadcrumbRow.implicitWidth
                        contentHeight: height
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        RowLayout {
                            id: breadcrumbRow
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 4

                            readonly property var segments: {
                                let p = root.currentFolder;
                                if (!p || p === "/") return [{ name: "root", path: "/" }];
                                let parts = p.split("/").filter(Boolean);
                                let res = [{ name: "root", path: "/" }];
                                let accum = "";
                                for (let i = 0; i < parts.length; i++) {
                                    accum += "/" + parts[i];
                                    let label = (accum === root.homeDir) ? "Home" : parts[i];
                                    res.push({ name: label, path: accum });
                                }
                                return res;
                            }

                            Repeater {
                                model: breadcrumbRow.segments

                                delegate: RowLayout {
                                    spacing: 4

                                    Rectangle {
                                        implicitHeight: 24
                                        implicitWidth: segTxt.implicitWidth + 12
                                        radius: 6
                                        color: segMouse.containsMouse ? Colors.primaryContainer : "transparent"

                                        Text {
                                            id: segTxt
                                            anchors.centerIn: parent
                                            text: modelData.name
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 11
                                            font.weight: (index === breadcrumbRow.segments.length - 1) ? Font.Bold : Font.Normal
                                            color: (index === breadcrumbRow.segments.length - 1) ? Colors.primary : Colors.m3onSurfaceVariant
                                        }

                                        MouseArea {
                                            id: segMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.selectFolder(modelData.path)
                                        }
                                    }

                                    Text {
                                        visible: index < breadcrumbRow.segments.length - 1
                                        text: ">"
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 10
                                        color: Colors.m3onSurfaceVariant
                                        opacity: 0.6
                                    }
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 1
                    color: Colors.glassBorderSpecular
                }
            }

            // 3. Main Content: Sidebar + Gallery Grid
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0

                // Quick Places Sidebar
                Rectangle {
                    Layout.fillHeight: true
                    implicitWidth: 145
                    color: Qt.rgba(0, 0, 0, 0.10)

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 4

                        Text {
                            text: "QUICK PLACES"
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                            font.weight: Font.Bold
                            color: Colors.m3onSurfaceVariant
                            opacity: 0.7
                            Layout.leftMargin: 6
                            Layout.topMargin: 4
                            Layout.bottomMargin: 2
                        }

                        Repeater {
                            model: root.quickPlaces

                            delegate: Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 32
                                radius: 8
                                readonly property bool isActive: root.currentFolder === modelData.path

                                color: isActive
                                    ? Colors.primaryContainer
                                    : (placeMouse.containsMouse ? Colors.glassCardHover : "transparent")

                                border.width: isActive ? 1 : 0
                                border.color: Colors.primary

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 8
                                    spacing: 8

                                    MaterialIcon {
                                        iconName: modelData.icon
                                        size: 15
                                        color: isActive ? Colors.primary : Colors.m3onSurfaceVariant
                                    }

                                    Text {
                                        text: modelData.name
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 11
                                        font.weight: isActive ? Font.SemiBold : Font.Normal
                                        color: isActive ? Colors.m3onPrimaryContainer : Colors.m3onSurface
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                }

                                MouseArea {
                                    id: placeMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.selectFolder(modelData.path)
                                }
                            }
                        }

                        Item { Layout.fillHeight: true }
                    }

                    Rectangle {
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: 1
                        color: Colors.glassBorderSpecular
                    }
                }

                // Main File Browser Pane: Toolbar + GridView / ListView
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 0

                    // 1. Controls Toolbar: Category Filter, Sort Criteria, Sort Direction, View Size Modes
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 38
                        color: Qt.rgba(0, 0, 0, 0.12)

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 8

                            // Filter Category Selector Pills
                            RowLayout {
                                spacing: 4
                                Repeater {
                                    model: root.filterOptions
                                    delegate: Rectangle {
                                        implicitHeight: 24
                                        implicitWidth: catTxt.implicitWidth + 12
                                        radius: 6
                                        color: root.filterCategory === index
                                            ? (typeof Colors !== "undefined" ? Colors.primaryContainer : Qt.rgba(1, 1, 1, 0.2))
                                            : (catMouse.containsMouse ? Colors.glassCardHover : "transparent")
                                        border.width: 1
                                        border.color: root.filterCategory === index ? Colors.primary : Colors.glassBorderSpecular

                                        Text {
                                            id: catTxt
                                            anchors.centerIn: parent
                                            text: modelData.name
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 10
                                            font.weight: root.filterCategory === index ? Font.Bold : Font.Normal
                                            color: root.filterCategory === index ? Colors.primary : Colors.m3onSurfaceVariant
                                        }

                                        MouseArea {
                                            id: catMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.filterCategory = index
                                        }
                                    }
                                }
                            }

                            Item { Layout.fillWidth: true }

                            // Sort Criteria Button (cycles Name -> Date -> Size -> Type)
                            Rectangle {
                                implicitHeight: 26
                                implicitWidth: sortRow.implicitWidth + 14
                                radius: 6
                                color: sortBtnMouse.containsMouse ? Colors.glassCardHover : "transparent"
                                border.width: 1
                                border.color: Colors.glassBorderSpecular

                                RowLayout {
                                    id: sortRow
                                    anchors.centerIn: parent
                                    spacing: 4

                                    MaterialIcon {
                                        iconName: "sort"
                                        size: 13
                                        color: Colors.m3onSurfaceVariant
                                    }

                                    Text {
                                        text: {
                                            for (let i = 0; i < root.sortOptions.length; i++) {
                                                if (root.sortOptions[i].field === root.sortField) return root.sortOptions[i].name;
                                            }
                                            return "Name";
                                        }
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 10
                                        font.weight: Font.Medium
                                        color: Colors.m3onSurface
                                    }
                                }

                                MouseArea {
                                    id: sortBtnMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (root.sortField === FolderListModel.Name) root.sortField = FolderListModel.Time;
                                        else if (root.sortField === FolderListModel.Time) root.sortField = FolderListModel.Size;
                                        else if (root.sortField === FolderListModel.Size) root.sortField = FolderListModel.Type;
                                        else root.sortField = FolderListModel.Name;
                                    }
                                }
                            }

                            // Sort Direction Button (Ascending / Descending)
                            Rectangle {
                                width: 26
                                height: 26
                                radius: 6
                                color: sortDirMouse.containsMouse ? Colors.glassCardHover : "transparent"
                                border.width: 1
                                border.color: Colors.glassBorderSpecular

                                MaterialIcon {
                                    anchors.centerIn: parent
                                    iconName: root.sortReversed ? "arrow_downward" : "arrow_upward"
                                    size: 13
                                    color: root.sortReversed ? Colors.primary : Colors.m3onSurface
                                }

                                MouseArea {
                                    id: sortDirMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.sortReversed = !root.sortReversed
                                }
                            }

                            Rectangle {
                                width: 1
                                height: 16
                                color: Colors.glassBorderSpecular
                            }

                            // View Mode / Size Buttons
                            // Small Grid (88px)
                            Rectangle {
                                width: 26
                                height: 26
                                radius: 6
                                color: root.viewMode === "grid_small" ? Colors.primaryContainer : (viewSmallMouse.containsMouse ? Colors.glassCardHover : "transparent")
                                border.width: 1
                                border.color: root.viewMode === "grid_small" ? Colors.primary : Colors.glassBorderSpecular

                                MaterialIcon {
                                    anchors.centerIn: parent
                                    iconName: "apps"
                                    size: 13
                                    color: root.viewMode === "grid_small" ? Colors.primary : Colors.m3onSurfaceVariant
                                }

                                MouseArea {
                                    id: viewSmallMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.viewMode = "grid_small"
                                }
                            }

                            // Medium Grid (120px - Default)
                            Rectangle {
                                width: 26
                                height: 26
                                radius: 6
                                color: root.viewMode === "grid_medium" ? Colors.primaryContainer : (viewMedMouse.containsMouse ? Colors.glassCardHover : "transparent")
                                border.width: 1
                                border.color: root.viewMode === "grid_medium" ? Colors.primary : Colors.glassBorderSpecular

                                MaterialIcon {
                                    anchors.centerIn: parent
                                    iconName: "grid_view"
                                    size: 13
                                    color: root.viewMode === "grid_medium" ? Colors.primary : Colors.m3onSurfaceVariant
                                }

                                MouseArea {
                                    id: viewMedMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.viewMode = "grid_medium"
                                }
                            }

                            // Large Grid (168px)
                            Rectangle {
                                width: 26
                                height: 26
                                radius: 6
                                color: root.viewMode === "grid_large" ? Colors.primaryContainer : (viewLargeMouse.containsMouse ? Colors.glassCardHover : "transparent")
                                border.width: 1
                                border.color: root.viewMode === "grid_large" ? Colors.primary : Colors.glassBorderSpecular

                                MaterialIcon {
                                    anchors.centerIn: parent
                                    iconName: "crop_square"
                                    size: 14
                                    color: root.viewMode === "grid_large" ? Colors.primary : Colors.m3onSurfaceVariant
                                }

                                MouseArea {
                                    id: viewLargeMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.viewMode = "grid_large"
                                }
                            }

                            // Detailed List View
                            Rectangle {
                                width: 26
                                height: 26
                                radius: 6
                                color: root.viewMode === "list" ? Colors.primaryContainer : (viewListMouse.containsMouse ? Colors.glassCardHover : "transparent")
                                border.width: 1
                                border.color: root.viewMode === "list" ? Colors.primary : Colors.glassBorderSpecular

                                MaterialIcon {
                                    anchors.centerIn: parent
                                    iconName: "view_list"
                                    size: 14
                                    color: root.viewMode === "list" ? Colors.primary : Colors.m3onSurfaceVariant
                                }

                                MouseArea {
                                    id: viewListMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.viewMode = "list"
                                }
                            }
                        }

                        Rectangle {
                            anchors.bottom: parent.bottom
                            anchors.left: parent.left
                            anchors.right: parent.right
                            height: 1
                            color: Colors.glassBorderSpecular
                        }
                    }

                    // 2. Viewport: FolderListModel + GridView / ListView
                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        FolderListModel {
                            id: folderModel
                            folder: "file://" + root.currentFolder
                            nameFilters: root.filterOptions[root.filterCategory].filters
                            showDirs: true
                            showDirsFirst: true
                            showDotAndDotDot: false
                            sortField: root.sortField
                            sortReversed: root.sortReversed
                        }

                        GridView {
                            id: gridView
                            anchors.fill: parent
                            anchors.margins: 8
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds

                            cellWidth: root.viewMode === "grid_small" ? 88 : (root.viewMode === "grid_medium" ? 120 : (root.viewMode === "grid_large" ? 168 : (gridView.width - 16)))
                            cellHeight: root.viewMode === "grid_small" ? 88 : (root.viewMode === "grid_medium" ? 120 : (root.viewMode === "grid_large" ? 168 : 36))

                            model: folderModel

                            delegate: Rectangle {
                                id: itemDelegate
                                readonly property bool isList: root.viewMode === "list"
                                width: isList ? (gridView.width - 20) : (gridView.cellWidth - 8)
                                height: isList ? 32 : (gridView.cellHeight - 8)
                                radius: isList ? 6 : 10
                                clip: true

                                readonly property bool isDir: (typeof model !== "undefined" && typeof model.fileIsDir !== "undefined") ? model.fileIsDir : false
                                readonly property string fullPath: (typeof model !== "undefined" && model.filePath) ? String(model.filePath) : ""
                                readonly property string name: (typeof model !== "undefined" && model.fileName) ? String(model.fileName) : ""
                                readonly property string fileUrlSafe: (typeof model !== "undefined" && model.fileUrl) ? String(model.fileUrl) : ""
                                readonly property int fileSizeSafe: (typeof model !== "undefined" && typeof model.fileSize !== "undefined") ? model.fileSize : 0
                                readonly property var fileModSafe: (typeof model !== "undefined" && model.fileModified) ? model.fileModified : null
                                readonly property bool isImg: !isDir && root.isImageFile(fullPath)
                                readonly property bool isItemFiltered: root.searchQuery.length > 0 && name.toLowerCase().indexOf(root.searchQuery) === -1
                                readonly property bool isItemSel: root.isSelected(fullPath)

                                visible: !isItemFiltered
                                opacity: visible ? 1.0 : 0.0

                                color: isItemSel
                                    ? Qt.alpha((typeof Colors !== "undefined" && Colors.primary) ? Colors.primary : "#7aa2f7", 0.18)
                                    : (itemMouse.containsMouse ? ((typeof Colors !== "undefined" && Colors.glassCardHover) ? Colors.glassCardHover : Qt.rgba(1, 1, 1, 0.08)) : Qt.rgba(0, 0, 0, 0.18))

                                border.width: isItemSel ? 2 : 1
                                border.color: isItemSel
                                    ? ((typeof Colors !== "undefined" && Colors.primary) ? Colors.primary : "#7aa2f7")
                                    : ((typeof Colors !== "undefined" && Colors.glassBorderSpecular) ? Colors.glassBorderSpecular : Qt.rgba(1, 1, 1, 0.10))

                                // --- List View Layout ---
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 8
                                    spacing: 8
                                    visible: itemDelegate.isList

                                    // Selection Indicator or Checkbox
                                    Rectangle {
                                        width: 16
                                        height: 16
                                        radius: 4
                                        color: itemDelegate.isItemSel ? Colors.primary : Qt.rgba(1, 1, 1, 0.08)
                                        border.width: 1
                                        border.color: itemDelegate.isItemSel ? Colors.primary : Colors.glassBorderSpecular
                                        visible: !itemDelegate.isDir

                                        MaterialIcon {
                                            anchors.centerIn: parent
                                            iconName: "check"
                                            size: 11
                                            color: Colors.isDarkMode ? "#12131A" : "#FFFFFF"
                                            visible: itemDelegate.isItemSel
                                        }
                                    }

                                    // Icon / Thumbnail / Chip
                                    Item {
                                        width: 22
                                        height: 22

                                        MaterialIcon {
                                            anchors.centerIn: parent
                                            iconName: "folder"
                                            size: 20
                                            color: Colors.primary
                                            visible: itemDelegate.isDir
                                        }

                                        Image {
                                            anchors.fill: parent
                                            source: itemDelegate.isImg ? itemDelegate.fileUrlSafe : ""
                                            fillMode: Image.PreserveAspectCrop
                                            smooth: true
                                            asynchronous: true
                                            visible: itemDelegate.isImg
                                        }

                                        Rectangle {
                                            anchors.centerIn: parent
                                            width: 22
                                            height: 16
                                            radius: 3
                                            color: Qt.alpha(Colors.primary, 0.20)
                                            border.width: 1
                                            border.color: Qt.alpha(Colors.primary, 0.40)
                                            visible: !itemDelegate.isDir && !itemDelegate.isImg

                                            Text {
                                                anchors.centerIn: parent
                                                text: root.getFileExtension(itemDelegate.fullPath)
                                                font.family: Theme.fontMonospace
                                                font.pixelSize: 8
                                                font.weight: Font.Bold
                                                color: Colors.primary
                                            }
                                        }
                                    }

                                    // Name
                                    Text {
                                        text: itemDelegate.name
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 11
                                        font.weight: itemDelegate.isDir ? Font.SemiBold : Font.Normal
                                        color: itemDelegate.isDir ? Colors.primary : Colors.m3onSurface
                                        elide: Text.ElideMiddle
                                        Layout.fillWidth: true
                                    }

                                    // Size
                                    Text {
                                        text: itemDelegate.isDir ? "--" : root.formatSize(itemDelegate.fileSizeSafe)
                                        font.family: Theme.fontMonospace
                                        font.pixelSize: 10
                                        color: Colors.m3onSurfaceVariant
                                        Layout.preferredWidth: 60
                                        horizontalAlignment: Text.AlignRight
                                    }

                                    // Date Modified
                                    Text {
                                        text: root.formatTime(itemDelegate.fileModSafe)
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 10
                                        color: Colors.m3onSurfaceVariant
                                        opacity: 0.8
                                        Layout.preferredWidth: 70
                                        horizontalAlignment: Text.AlignRight
                                    }
                                }

                                // --- Grid View Layout ---
                                Item {
                                    anchors.fill: parent
                                    visible: !itemDelegate.isList

                                    // 1. Directory representation
                                    ColumnLayout {
                                        anchors.centerIn: parent
                                        spacing: 4
                                        visible: itemDelegate.isDir

                                        MaterialIcon {
                                            Layout.alignment: Qt.AlignHCenter
                                            iconName: "folder"
                                            size: root.viewMode === "grid_small" ? 28 : (root.viewMode === "grid_large" ? 44 : 34)
                                            color: Colors.primary
                                        }

                                        Text {
                                            text: itemDelegate.name
                                            font.family: Theme.fontFamily
                                            font.pixelSize: root.viewMode === "grid_small" ? 9 : 10
                                            color: Colors.m3onSurface
                                            elide: Text.ElideMiddle
                                            Layout.maximumWidth: itemDelegate.width - 12
                                            horizontalAlignment: Text.AlignHCenter
                                        }
                                    }

                                    // 2. Image thumbnail representation
                                    Image {
                                        anchors.fill: parent
                                        anchors.margins: 2
                                        visible: itemDelegate.isImg
                                        source: itemDelegate.isImg ? itemDelegate.fileUrlSafe : ""
                                        fillMode: Image.PreserveAspectCrop
                                        smooth: true
                                        asynchronous: true
                                    }

                                    // 3. Non-image file representation (Code, Docs, Configs)
                                    ColumnLayout {
                                        anchors.centerIn: parent
                                        spacing: 4
                                        visible: !itemDelegate.isDir && !itemDelegate.isImg

                                        Rectangle {
                                            Layout.alignment: Qt.AlignHCenter
                                            implicitWidth: root.viewMode === "grid_small" ? 32 : 40
                                            implicitHeight: root.viewMode === "grid_small" ? 20 : 24
                                            radius: 4
                                            color: Qt.alpha(Colors.primary, 0.20)
                                            border.width: 1
                                            border.color: Qt.alpha(Colors.primary, 0.40)

                                            Text {
                                                anchors.centerIn: parent
                                                text: root.getFileExtension(itemDelegate.fullPath)
                                                font.family: Theme.fontMonospace
                                                font.pixelSize: root.viewMode === "grid_small" ? 8 : 10
                                                font.weight: Font.Bold
                                                color: Colors.primary
                                            }
                                        }

                                        Text {
                                            text: itemDelegate.name
                                            font.family: Theme.fontFamily
                                            font.pixelSize: root.viewMode === "grid_small" ? 8 : 10
                                            color: Colors.m3onSurface
                                            elide: Text.ElideMiddle
                                            Layout.maximumWidth: itemDelegate.width - 12
                                            horizontalAlignment: Text.AlignHCenter
                                        }

                                        Text {
                                            text: root.formatSize(itemDelegate.fileSizeSafe)
                                            font.family: Theme.fontMonospace
                                            font.pixelSize: 8
                                            color: Colors.m3onSurfaceVariant
                                            Layout.alignment: Qt.AlignHCenter
                                        }
                                    }

                                    // Bottom gradient scrim for image filename readability
                                    Rectangle {
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.bottom: parent.bottom
                                        height: root.viewMode === "grid_small" ? 24 : 32
                                        visible: itemDelegate.isImg
                                        gradient: Gradient {
                                            GradientStop { position: 0.0; color: "transparent" }
                                            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.85) }
                                        }

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 6
                                            anchors.rightMargin: 6
                                            spacing: 4

                                            Text {
                                                text: itemDelegate.name
                                                font.family: Theme.fontFamily
                                                font.pixelSize: root.viewMode === "grid_small" ? 8 : 9
                                                font.weight: Font.Medium
                                                color: "#FFFFFF"
                                                elide: Text.ElideMiddle
                                                Layout.fillWidth: true
                                            }

                                            Text {
                                                text: root.formatSize(itemDelegate.fileSizeSafe)
                                                font.family: Theme.fontMonospace
                                                font.pixelSize: 7
                                                color: Qt.rgba(1, 1, 1, 0.70)
                                                visible: root.viewMode !== "grid_small"
                                            }
                                        }
                                    }

                                    // Selection Checkmark Badge
                                    Rectangle {
                                        width: 18
                                        height: 18
                                        radius: 9
                                        anchors.top: parent.top
                                        anchors.right: parent.right
                                        anchors.margins: 4
                                        visible: itemDelegate.isItemSel && !itemDelegate.isDir
                                        color: Colors.primary

                                        MaterialIcon {
                                            anchors.centerIn: parent
                                            iconName: "check"
                                            size: 11
                                            color: Colors.isDarkMode ? "#12131A" : "#FFFFFF"
                                        }
                                    }
                                }

                                MouseArea {
                                    id: itemMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor

                                    onClicked: {
                                        if (itemDelegate.isDir) {
                                            root.selectFolder(itemDelegate.fullPath);
                                        } else {
                                            root.toggleSelectFile(itemDelegate.fullPath);
                                        }
                                    }

                                    onDoubleClicked: {
                                        if (itemDelegate.isDir) {
                                            root.selectFolder(itemDelegate.fullPath);
                                        } else {
                                            root.accepted([itemDelegate.fullPath]);
                                        }
                                    }
                                }
                            }
                        }

                        // Empty Directory Placeholder
                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 8
                            visible: folderModel.count === 0

                            MaterialIcon {
                                Layout.alignment: Qt.AlignHCenter
                                iconName: "folder_open"
                                size: 40
                                color: Colors.m3onSurfaceVariant
                                opacity: 0.5
                            }

                            Text {
                                text: "No matching files found in this folder"
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                                color: Colors.m3onSurfaceVariant
                                opacity: 0.7
                            }
                        }
                    }
                }
            }

            // 4. Footer Action Bar
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 52
                color: Qt.rgba(0, 0, 0, 0.18)

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    spacing: 12

                    // Selection Summary
                    Text {
                        text: {
                            if (root.selectedFiles.length === 0) {
                                return "Click a file to select, double-click to attach immediately";
                            } else if (root.selectedFiles.length === 1) {
                                let f = root.selectedFiles[0];
                                let base = f.substring(f.lastIndexOf("/") + 1);
                                return "1 file selected: " + base;
                            } else {
                                return root.selectedFiles.length + " files selected";
                            }
                        }
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        color: root.selectedFiles.length > 0 ? Colors.primary : Colors.m3onSurfaceVariant
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }

                    // Cancel Button
                    Rectangle {
                        implicitHeight: 32
                        implicitWidth: cancelTxt.implicitWidth + 24
                        radius: 8
                        color: cancelMouse.containsMouse ? Colors.glassCardHover : "transparent"
                        border.width: 1
                        border.color: Colors.glassBorderSpecular

                        Text {
                            id: cancelTxt
                            anchors.centerIn: parent
                            text: "Cancel"
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            font.weight: Font.Medium
                            color: Colors.m3onSurface
                        }

                        MouseArea {
                            id: cancelMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.canceled()
                        }
                    }

                    // Attach Button
                    Rectangle {
                        implicitHeight: 32
                        implicitWidth: attachTxt.implicitWidth + 24
                        radius: 8
                        readonly property bool canAttach: root.selectedFiles.length > 0

                        color: canAttach
                            ? (attachMouse.containsMouse ? Qt.lighter(Colors.primary, 1.1) : Colors.primary)
                            : Qt.rgba(1, 1, 1, 0.08)

                        border.width: 1
                        border.color: canAttach ? Colors.primary : Colors.glassBorderSpecular

                        Text {
                            id: attachTxt
                            anchors.centerIn: parent
                            text: root.selectedFiles.length > 1 ? ("Attach (" + root.selectedFiles.length + ")") : "Attach File"
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            font.weight: Font.Bold
                            color: parent.canAttach ? (Colors.isDarkMode ? "#12131A" : "#FFFFFF") : Colors.m3onSurfaceVariant
                        }

                        MouseArea {
                            id: attachMouse
                            anchors.fill: parent
                            hoverEnabled: parent.canAttach
                            cursorShape: parent.canAttach ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: {
                                if (parent.canAttach) {
                                    root.submitSelection();
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 1
                    color: Colors.glassBorderSpecular
                }
            }
        }
    }
}
