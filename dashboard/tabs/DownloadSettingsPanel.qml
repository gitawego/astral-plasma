import QtQuick
import QtQuick.Layouts
import QtQuick.Dialogs
import "../../theme"
import "../../components"
import "../../config"
import "../../services"
import "DownloadSettingsMath.js" as SettingsMath

/// Transfer settings, designed as a console rather than a settings page.
///
/// One continuous sheet inside the manager window. The three numeric knobs are
/// the subject, so they lead: a live equation (parallel files × connections
/// each = total connections) sits above the controls that produce it, in the
/// shell's monospace face. There is no second page title and no stack of
/// identical cards - section eyebrows, hairline rules, and one accent.
///
/// Same Config setters and engine push as Settings > Downloads; the all-in-one
/// hub remains the canonical page.
Rectangle {
    id: sheet

    signal closeRequested()

    readonly property int pad: 22

    readonly property string dir: (typeof Config !== "undefined" && Config.downloadsDir)
        ? Config.downloadsDir : ""
    readonly property int splitParts: (typeof Config !== "undefined" && Config.downloadsSplit)
        ? Config.downloadsSplit : 4
    readonly property int parallelDownloads: (typeof Config !== "undefined" && Config.downloadsMaxConcurrent)
        ? Config.downloadsMaxConcurrent : 5
    readonly property int speedLimitKbps: (typeof Config !== "undefined" && Config.downloadsSpeedLimit !== undefined)
        ? Config.downloadsSpeedLimit : 0
    readonly property bool borderEffect: (typeof Config !== "undefined" && Config.downloadsBorderEffect !== undefined)
        ? Config.downloadsBorderEffect : true

    readonly property int capacity: SettingsMath.capacity(sheet.parallelDownloads, sheet.splitParts)
    readonly property string speedText: SettingsMath.formatKbps(sheet.speedLimitKbps)
    readonly property string engineVersion: (typeof DownloadService !== "undefined" && DownloadService
        && DownloadService.ariaVersion) ? String(DownloadService.ariaVersion) : ""

    implicitWidth: 660
    implicitHeight: content.implicitHeight + sheet.pad * 2
    radius: (typeof Theme !== "undefined") ? Theme.radiusGlassModal : 24
    color: (typeof Colors !== "undefined") ? Colors.surfaceContainerHigh : "#2b2930"
    border.width: 1
    border.color: (typeof Colors !== "undefined" && Colors.glassBorderSpecular)
        ? Colors.glassBorderSpecular : Qt.rgba(1, 1, 1, 0.18)
    clip: true

    // --- The single write path (same setters as Settings > Downloads) -------

    function chooseDir(path) {
        const value = String(path || "").trim();
        Config.setDownloadsDir(value);
        sheet.pushToEngine();
    }

    function applySplit(value) {
        Config.setDownloadsSplit(SettingsMath.parts(value));
    }

    function applyParallel(value) {
        Config.setDownloadsMaxConcurrent(SettingsMath.parallel(value));
        sheet.pushToEngine();
    }

    function applySpeed(value) {
        Config.setDownloadsSpeedLimit(SettingsMath.speedKbps(value));
        sheet.pushToEngine();
    }

    function setBorder(enabled) {
        Config.setDownloadsBorderEffect(Boolean(enabled));
    }

    function pushToEngine() {
        if (typeof DownloadService !== "undefined" && DownloadService
                && typeof DownloadService.applyEngineSettings === "function") {
            DownloadService.applyEngineSettings();
        }
    }

    onDirChanged: {
        if (pathInput && !pathInput.activeFocus) pathInput.text = sheet.dir;
    }

    FolderDialog {
        id: folderDialog
        title: "Download folder"
        onAccepted: {
            const picked = String(selectedFolder).replace(/^file:\/\//, "");
            pathInput.text = picked;
            sheet.chooseDir(picked);
        }
    }

    Flickable {
        id: scroll
        anchors.fill: parent
        anchors.margins: sheet.pad
        contentWidth: width
        contentHeight: content.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: content
            width: scroll.width
            spacing: 16

            // ---- Identity: one title, no "Download Settings" echo ----------
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1

                    Text {
                        text: "Transfer settings"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontTitleSmall
                        font.weight: Font.DemiBold
                        color: Colors.textOnSurface
                    }

                    Text {
                        text: "Applies to the running aria2 engine"
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        color: Colors.textOnSurfaceVariant
                    }
                }

            }

            // ---- The signature: the capacity equation, live -----------------
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: equation.implicitHeight + 24
                radius: Theme.radiusMedium
                color: Qt.alpha(Colors.primary, 0.09)
                border.width: 1
                border.color: Qt.alpha(Colors.primary, 0.20)

                RowLayout {
                    id: equation
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    anchors.topMargin: 12
                    anchors.bottomMargin: 12
                    spacing: 14

                    ColumnLayout {
                        spacing: 0
                        Text {
                            text: String(sheet.parallelDownloads)
                            font.family: Theme.fontMonospace
                            font.pixelSize: 24
                            font.weight: Font.DemiBold
                            color: Colors.primary
                        }
                        Text {
                            text: "files at once"
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            color: Colors.textOnSurfaceVariant
                        }
                    }

                    Text {
                        text: "×"
                        font.family: Theme.fontMonospace
                        font.pixelSize: 14
                        color: Colors.textOnSurfaceVariant
                    }

                    ColumnLayout {
                        spacing: 0
                        Text {
                            text: String(sheet.splitParts)
                            font.family: Theme.fontMonospace
                            font.pixelSize: 24
                            font.weight: Font.DemiBold
                            color: Colors.primary
                        }
                        Text {
                            text: "connections each"
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            color: Colors.textOnSurfaceVariant
                        }
                    }

                    Text {
                        text: "="
                        font.family: Theme.fontMonospace
                        font.pixelSize: 14
                        color: Colors.textOnSurfaceVariant
                    }

                    ColumnLayout {
                        spacing: 0
                        Text {
                            text: String(sheet.capacity)
                            font.family: Theme.fontMonospace
                            font.pixelSize: 24
                            font.weight: Font.Bold
                            color: Colors.textOnSurface
                        }
                        Text {
                            text: "total connections"
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            color: Colors.textOnSurfaceVariant
                        }
                    }

                    Item { Layout.fillWidth: true }

                    ColumnLayout {
                        spacing: 1
                        Text {
                            Layout.alignment: Qt.AlignRight
                            text: (sheet.engineVersion !== "" ? "aria2 " + sheet.engineVersion : "aria2")
                            font.family: Theme.fontMonospace
                            font.pixelSize: 10
                            color: Colors.textOnSurfaceVariant
                        }
                    }
                }
            }

            // ---- Destination ------------------------------------------------
            Text {
                text: "DESTINATION"
                font.family: Theme.fontFamily
                font.pixelSize: 10
                font.weight: Font.DemiBold
                font.letterSpacing: 1.2
                color: Colors.textOnSurfaceVariant
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 44
                radius: Theme.radiusMedium
                color: Colors.surfaceContainer
                border.width: 1
                border.color: pathInput.activeFocus ? Colors.primary : Theme.borderSubtle

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 8
                    spacing: 8

                    Item {
                        Layout.fillWidth: true
                        implicitHeight: 20

                        TextInput {
                            id: pathInput
                            anchors.fill: parent
                            text: sheet.dir
                            color: Colors.textOnSurface
                            font.family: Theme.fontMonospace
                            font.pixelSize: 12
                            selectByMouse: true
                            onEditingFinished: sheet.chooseDir(text)
                        }

                        Text {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            visible: pathInput.text.length === 0
                            text: "~/Downloads"
                            font.family: Theme.fontMonospace
                            font.pixelSize: 12
                            color: Colors.textOnSurfaceVariant
                        }
                    }

                    Rectangle {
                        implicitWidth: browseText.implicitWidth + 14
                        implicitHeight: 26
                        radius: 13
                        color: browseHover.hovered ? Qt.alpha(Colors.primary, 0.16) : "transparent"

                        Text {
                            id: browseText
                            anchors.centerIn: parent
                            text: "Browse"
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            color: Colors.primary
                        }

                        HoverHandler { id: browseHover }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: folderDialog.open()
                        }
                    }

                    Rectangle {
                        implicitWidth: defaultText.implicitWidth + 10
                        implicitHeight: 26
                        radius: 13
                        color: defaultHover.hovered ? Qt.alpha(Colors.textOnSurface, 0.08) : "transparent"

                        Text {
                            id: defaultText
                            anchors.centerIn: parent
                            text: "Default"
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            color: Colors.textOnSurfaceVariant
                        }

                        HoverHandler { id: defaultHover }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                pathInput.text = "";
                                sheet.chooseDir("");
                            }
                        }
                    }
                }
            }

            Text {
                text: "Empty uses aria2's default (~/Downloads)"
                font.family: Theme.fontFamily
                font.pixelSize: 10
                color: Colors.textOnSurfaceVariant
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: Theme.borderSubtle
            }

            // ---- Numeric knobs: two columns, one equation -------------------
            RowLayout {
                Layout.fillWidth: true
                spacing: 20

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Text {
                        text: "PARALLEL DOWNLOADS"
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                        font.letterSpacing: 1.2
                        color: Colors.textOnSurfaceVariant
                    }

                    RowLayout {
                        spacing: 10

                        Rectangle {
                            implicitWidth: 30
                            implicitHeight: 30
                            radius: 15
                            color: parMinus.containsMouse && sheet.parallelDownloads > 1
                                ? Qt.alpha(Colors.primary, 0.16) : "transparent"
                            border.width: 1
                            border.color: sheet.parallelDownloads > 1 ? Theme.borderSubtle : "transparent"

                            MaterialIcon {
                                anchors.centerIn: parent
                                text: "remove"
                                size: 14
                                color: Colors.textOnSurfaceVariant
                                opacity: sheet.parallelDownloads > 1 ? 1 : 0.3
                            }

                            MouseArea {
                                id: parMinus
                                anchors.fill: parent
                                hoverEnabled: true
                                enabled: sheet.parallelDownloads > 1
                                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: sheet.applyParallel(sheet.parallelDownloads - 1)
                            }
                        }

                        Text {
                            Layout.preferredWidth: 34
                            horizontalAlignment: Text.AlignHCenter
                            text: String(sheet.parallelDownloads)
                            font.family: Theme.fontMonospace
                            font.pixelSize: 24
                            font.weight: Font.DemiBold
                            color: Colors.textOnSurface
                        }

                        Rectangle {
                            implicitWidth: 30
                            implicitHeight: 30
                            radius: 15
                            color: parPlus.containsMouse && sheet.parallelDownloads < 16
                                ? Qt.alpha(Colors.primary, 0.16) : "transparent"
                            border.width: 1
                            border.color: sheet.parallelDownloads < 16 ? Theme.borderSubtle : "transparent"

                            MaterialIcon {
                                anchors.centerIn: parent
                                text: "add"
                                size: 14
                                color: Colors.textOnSurfaceVariant
                                opacity: sheet.parallelDownloads < 16 ? 1 : 0.3
                            }

                            MouseArea {
                                id: parPlus
                                anchors.fill: parent
                                hoverEnabled: true
                                enabled: sheet.parallelDownloads < 16
                                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: sheet.applyParallel(sheet.parallelDownloads + 1)
                            }
                        }
                    }

                    Text {
                        text: "files at once"
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        color: Colors.textOnSurfaceVariant
                    }
                }

                Rectangle {
                    implicitWidth: 1
                    Layout.fillHeight: true
                    color: Theme.borderSubtle
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Text {
                        text: "CONNECTIONS PER DOWNLOAD"
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                        font.letterSpacing: 1.2
                        color: Colors.textOnSurfaceVariant
                    }

                    RowLayout {
                        spacing: 10

                        Rectangle {
                            implicitWidth: 30
                            implicitHeight: 30
                            radius: 15
                            color: conMinus.containsMouse && sheet.splitParts > 1
                                ? Qt.alpha(Colors.primary, 0.16) : "transparent"
                            border.width: 1
                            border.color: sheet.splitParts > 1 ? Theme.borderSubtle : "transparent"

                            MaterialIcon {
                                anchors.centerIn: parent
                                text: "remove"
                                size: 14
                                color: Colors.textOnSurfaceVariant
                                opacity: sheet.splitParts > 1 ? 1 : 0.3
                            }

                            MouseArea {
                                id: conMinus
                                anchors.fill: parent
                                hoverEnabled: true
                                enabled: sheet.splitParts > 1
                                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: sheet.applySplit(sheet.splitParts - 1)
                            }
                        }

                        Text {
                            Layout.preferredWidth: 34
                            horizontalAlignment: Text.AlignHCenter
                            text: String(sheet.splitParts)
                            font.family: Theme.fontMonospace
                            font.pixelSize: 24
                            font.weight: Font.DemiBold
                            color: Colors.textOnSurface
                        }

                        Rectangle {
                            implicitWidth: 30
                            implicitHeight: 30
                            radius: 15
                            color: conPlus.containsMouse && sheet.splitParts < 16
                                ? Qt.alpha(Colors.primary, 0.16) : "transparent"
                            border.width: 1
                            border.color: sheet.splitParts < 16 ? Theme.borderSubtle : "transparent"

                            MaterialIcon {
                                anchors.centerIn: parent
                                text: "add"
                                size: 14
                                color: Colors.textOnSurfaceVariant
                                opacity: sheet.splitParts < 16 ? 1 : 0.3
                            }

                            MouseArea {
                                id: conPlus
                                anchors.fill: parent
                                hoverEnabled: true
                                enabled: sheet.splitParts < 16
                                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: sheet.applySplit(sheet.splitParts + 1)
                            }
                        }
                    }

                    Text {
                        text: "per file"
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        color: Colors.textOnSurfaceVariant
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: Theme.borderSubtle
            }

            // ---- Speed cap --------------------------------------------------
            RowLayout {
                Layout.fillWidth: true

                Text {
                    Layout.fillWidth: true
                    text: "SPEED CAP"
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    font.weight: Font.DemiBold
                    font.letterSpacing: 1.2
                    color: Colors.textOnSurfaceVariant
                }

                Text {
                    text: sheet.speedText
                    font.family: Theme.fontMonospace
                    font.pixelSize: 12
                    color: sheet.speedLimitKbps > 0 ? Colors.primary : Colors.textOnSurface
                }
            }

            Item {
                id: speedArea
                Layout.fillWidth: true
                implicitHeight: 26

                readonly property real ratio: Math.max(0, Math.min(1, sheet.speedLimitKbps / 10000))

                Rectangle {
                    id: speedTrack
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: 6
                    radius: 3
                    color: Qt.alpha(Colors.textOnSurface, 0.18)
                }

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: speedTrack.width * speedArea.ratio
                    height: 6
                    radius: 3
                    color: Colors.primary
                }

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    x: Math.max(0, Math.min(speedTrack.width - 16, speedTrack.width * speedArea.ratio - 8))
                    width: 16
                    height: 16
                    radius: 8
                    color: Colors.primary
                    border.width: 2
                    border.color: Colors.surfaceContainerHigh
                }

                MouseArea {
                    anchors.fill: parent
                    function commit(x) {
                        const ratio = Math.max(0, Math.min(1, x / width));
                        sheet.applySpeed(Math.round(ratio * 10000 / 100) * 100);
                    }
                    onPressed: mouse => commit(mouse.x)
                    onPositionChanged: mouse => {
                        if (pressed) commit(mouse.x);
                    }
                }
            }

            Text {
                text: "0 = no limit · aria2 --max-overall-download-limit"
                font.family: Theme.fontFamily
                font.pixelSize: 10
                color: Colors.textOnSurfaceVariant
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: Theme.borderSubtle
            }

            // ---- Screen-edge HUD -------------------------------------------
            RowLayout {
                Layout.fillWidth: true
                spacing: 16

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    Text {
                        text: "SCREEN-EDGE HUD"
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                        font.letterSpacing: 1.2
                        color: Colors.textOnSurfaceVariant
                    }

                    Text {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: "Progress and speed around the screen while a download is running"
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        color: Colors.textOnSurfaceVariant
                    }
                }

                Rectangle {
                    id: hudSwitch
                    implicitWidth: 44
                    implicitHeight: 24
                    radius: 12
                    color: sheet.borderEffect ? Colors.primary : Colors.surfaceContainerHighest

                    Rectangle {
                        width: 20
                        height: 20
                        radius: 10
                        y: 2
                        x: sheet.borderEffect ? 22 : 2
                        color: sheet.borderEffect ? Colors.textOnPrimary : Colors.textOnSurfaceVariant
                        Behavior on x {
                            NumberAnimation {
                                duration: Theme.animExpressiveFastSpatial
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: Theme.curveExpressiveFastSpatial
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: sheet.setBorder(!sheet.borderEffect)
                    }
                }
            }

            Item { Layout.preferredHeight: 4 }

            // ---- One exit ---------------------------------------------------
            RowLayout {
                Layout.fillWidth: true

                Item { Layout.fillWidth: true }

                PillButton {
                    label: "Done"
                    variant: "filled"
                    active: true
                    onClicked: sheet.closeRequested()
                }
            }
        }
    }
}
