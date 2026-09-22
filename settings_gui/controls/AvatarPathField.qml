import QtQuick
import QtQuick.Layouts
import QtQuick.Dialogs
import "../../theme"
import "../../components"

// Shared avatar path card: editable path + Browse… native picker + Reset.
//
// Dumb control - it renders and reports (`pathPicked`, "" = reset) but never
// touches Config or Quickshell itself, so the page stays instantiable in the
// offscreen qml6 harness and the caller stays in charge of side effects
// (DashboardPage gates its Config setters behind `testMode`).
Rectangle {
    id: field

    Layout.fillWidth: true
    radius: Theme.radiusMedium
    color: Colors.surfaceContainer
    implicitHeight: fieldCol.implicitHeight + Theme.padLarge * 2

    /// Card heading, e.g. "System Host Card Avatar".
    property string title: ""
    /// One-line helper under the heading.
    property string description: ""
    /// Shown when no path is set and the input is not focused.
    property string placeholder: ""
    /// Stored path (bound to Config.* by the page); synced into the input
    /// whenever it changes and the user is not typing.
    property string path: ""
    /// False in offscreen tests: the native dialog must never open there.
    property bool interactive: true

    /// Optional circle-background styling (opt-in, e.g. the host avatar card):
    /// a color swatch opening a ColorDialog plus a transparency slider, both
    /// reported through bgStylePicked.
    property bool showBgOptions: false
    property color bgColor: "#ffffff"
    property real bgOpacity: 0.2

    /// The background options row (exposed for tests).
    property alias bgOptionsRow: bgRow

    /// The editable input (test / introspection surface).
    property alias inputField: input

    /// Reports the committed path; "" resets to the bundled default.
    signal pathPicked(string path)

    /// Reports the circle background: #rrggbb hex + opacity clamped to 0..1.
    signal bgStylePicked(string colorHex, real opacity)

    /// Single normalization point for every commit source (input, browse,
    /// reset): trim, then hand upstream.
    function commit(newPath) {
        field.pathPicked(String(newPath).trim());
    }

    /// Reset to the bundled default art.
    function resetPath() {
        input.text = "";
        field.commit("");
    }

    /// Single normalization point for background commits: strip any alpha
    /// from the picked color (transparency lives in its own setting), fall
    /// back to white on garbage, clamp opacity to 0..1.
    function commitBg(pickedColor, opacity) {
        const s = String(pickedColor === undefined || pickedColor === null ? "" : pickedColor)
            .trim().toLowerCase().replace(/^#/, "");
        let hex = "ffffff";
        if (/^[0-9a-f]{6}$/.test(s)) {
            hex = s;
        } else if (/^[0-9a-f]{8}$/.test(s)) {
            hex = s.substring(2); // #aarrggbb -> rrggbb
        }
        let op = Number(opacity);
        if (isNaN(op)) op = 0.2;
        op = Math.max(0, Math.min(1, op));
        field.bgStylePicked("#" + hex, op);
    }

    // Keep the input in sync with the stored path - after a durable import
    // the daemon may have rewritten it to the config-dir copy. Never fight
    // the user's cursor while they are typing.
    onPathChanged: {
        if (!input.activeFocus) {
            input.text = field.path;
        }
    }

    Component.onCompleted: {
        input.text = field.path;
    }

    ColorDialog {
        id: bgDialog
        title: "Pick circle background color"
        selectedColor: field.bgColor
        onAccepted: field.commitBg(String(selectedColor), field.bgOpacity)
    }

    FileDialog {
        id: fileDlg
        title: field.title !== "" ? field.title : "Select avatar image"
        nameFilters: [
            "Images & media (*.png *.jpg *.jpeg *.gif *.svg *.webp *.bmp *.mp4 *.webm *.mov *.mkv *.avi)",
            "All files (*)"
        ]
        onAccepted: {
            const picked = String(selectedFile).replace(/^file:\/\//, "");
            input.text = picked;
            field.commit(picked);
        }
    }

    ColumnLayout {
        id: fieldCol
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
                    width: parent.width
                    text: field.title
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontBodyMedium
                    font.weight: Font.DemiBold
                    color: Colors.m3onSurface
                    elide: Text.ElideRight
                }

                Text {
                    width: parent.width
                    text: field.description
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontLabelSmall
                    color: Colors.m3onSurfaceVariant
                    wrapMode: Text.WordWrap
                }
            }

            Row {
                spacing: 8

                Rectangle {
                    width: 70
                    height: 28
                    radius: Theme.radiusSmall
                    color: Colors.surfaceContainerHigh
                    border.color: Theme.borderSubtle
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: "Browse…"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontLabelSmall
                        color: Colors.primary
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        Accessible.role: Accessible.Button
                        Accessible.name: "Browse for avatar image file"
                        onClicked: {
                            if (field.interactive) {
                                fileDlg.open();
                            }
                        }
                    }
                }

                Rectangle {
                    width: 70
                    height: 28
                    radius: Theme.radiusSmall
                    color: Colors.surfaceContainerHigh
                    border.color: Theme.borderSubtle
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: "Reset"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontLabelSmall
                        color: Colors.primary
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        Accessible.role: Accessible.Button
                        Accessible.name: "Reset avatar image to default"
                        onClicked: field.resetPath()
                    }
                }
            }
        }

        // Circle background options (opt-in): color swatch (native picker)
        // previewed at the configured transparency + transparency slider.
        RowLayout {
            id: bgRow
            Layout.fillWidth: true
            spacing: Theme.spaceMedium
            visible: field.showBgOptions

            Text {
                text: "Circle background"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontBodySmall
                color: Colors.m3onSurfaceVariant
            }

            Rectangle {
                width: 28
                height: 28
                radius: Theme.radiusSmall
                color: Qt.alpha(field.bgColor, field.bgOpacity)
                border.color: Theme.borderSubtle
                border.width: 1

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    Accessible.role: Accessible.Button
                    Accessible.name: "Pick circle background color"
                    onClicked: {
                        if (field.interactive) {
                            bgDialog.selectedColor = field.bgColor;
                            bgDialog.open();
                        }
                    }
                }
            }

            SettingSlider {
                Layout.fillWidth: true
                title: "Transparency"
                min: 0
                max: 100
                suffix: "%"
                value: field.bgOpacity * 100
                onValueModified: v => field.commitBg(field.bgColor, v / 100)
            }
        }

        Rectangle {
            Layout.fillWidth: true
            height: 34
            radius: Theme.radiusSmall
            color: Colors.surfaceContainerLowest
            border.color: input.activeFocus ? Colors.primary : Theme.borderSubtle
            border.width: 1

            TextInput {
                id: input
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                verticalAlignment: TextInput.AlignVCenter
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontBodySmall
                color: Colors.m3onSurface
                clip: true

                Text {
                    anchors.fill: parent
                    verticalAlignment: Text.AlignVCenter
                    text: field.placeholder
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontBodySmall
                    color: Colors.m3onSurfaceVariant
                    opacity: 0.5
                    visible: !input.text && !input.activeFocus
                }

                onAccepted: field.commit(text)
                onEditingFinished: field.commit(text)
            }
        }
    }
}
