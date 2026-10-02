import QtQuick
import QtQuick.Layouts
import QtQuick.Dialogs
import "../../theme"
import "../../components"

// Folder path card: editable path + Browse… native picker + Reset.
//
// Dumb control - it renders and reports (`pathPicked`, "" = default) but never
// touches Config or Quickshell itself, so the page stays instantiable in the
// offscreen qml6 harness and the caller stays in charge of side effects
// (the downloads page gates its Config setters behind `testMode`).
Rectangle {
    id: field

    Layout.fillWidth: true
    radius: Theme.radiusMedium
    color: Colors.surfaceContainer
    implicitHeight: fieldCol.implicitHeight + Theme.padLarge * 2

    /// Card heading, e.g. "Download folder".
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
    /// Label of the reset button; the empty value means "the application default".
    property string resetLabel: "Default"

    /// Reports the committed path; "" resets to the default.
    signal pathPicked(string path)

    /// The editable input (test / introspection surface).
    property alias inputField: input
    /// The Browse button (test surface).
    property alias browseButton: browse

    /// Single normalization point for every commit source (input, browse, reset).
    function commit(newPath) {
        field.pathPicked(String(newPath).trim());
    }

    function resetPath() {
        input.text = "";
        field.commit("");
    }

    // Keep the input in sync with the stored path - never fight the user's
    // cursor while they are typing.
    onPathChanged: {
        if (!input.activeFocus) {
            input.text = field.path;
        }
    }

    Component.onCompleted: {
        input.text = field.path;
    }

    // Qt's dedicated folder picker: `FileDialog` has no folder mode in Qt 6, and
    // the destination of a download is a folder, not a file.
    FolderDialog {
        id: folderDialog
        title: field.title !== "" ? field.title : "Select folder"
        onAccepted: {
            const picked = String(selectedFolder).replace(/^file:\/\//, "");
            input.text = picked;
            field.commit(picked);
        }
    }

    ColumnLayout {
        id: fieldCol
        anchors.fill: parent
        anchors.margins: Theme.padLarge
        spacing: 8

        Text {
            text: field.title
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontBodyMedium
            font.weight: Font.DemiBold
            color: Colors.m3onSurface
        }

        Text {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: field.description
            font.family: Theme.fontFamily
            font.pixelSize: 12
            color: Colors.m3onSurfaceVariant
            opacity: 0.85
            visible: field.description !== ""
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spaceSmall

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 40
                radius: Theme.radiusSmall
                color: Colors.surfaceContainerHighest
                border.color: input.activeFocus ? Colors.primary : Colors.outlineVariant
                border.width: 1

                TextInput {
                    id: input
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    verticalAlignment: TextInput.AlignVCenter
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontBodyMedium
                    color: Colors.m3onSurface
                    selectByMouse: true
                    clip: true
                    enabled: field.interactive
                    onEditingFinished: field.commit(text)
                }

                Text {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    verticalAlignment: Text.AlignVCenter
                    text: field.placeholder
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontBodyMedium
                    color: Colors.m3onSurfaceVariant
                    opacity: 0.6
                    visible: input.text === "" && !input.activeFocus
                }
            }

            PillButton {
                id: browse
                label: "Browse…"
                onClicked: {
                    if (field.interactive) {
                        folderDialog.open();
                    }
                }
            }

            PillButton {
                label: field.resetLabel
                onClicked: field.resetPath()
            }
        }
    }
}
