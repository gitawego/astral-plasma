import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../components"

Rectangle {
    id: root

    property var toolProposal: null
    signal approved()
    signal denied()

    implicitWidth: 380
    implicitHeight: col.implicitHeight + 20
    radius: 12
    color: Colors.m3surfaceContainerHigh
    border.width: 1
    border.color: (toolProposal && toolProposal.requires_sudo) ? Colors.m3error : Colors.primary

    readonly property string detectedImagePath: {
        if (!toolProposal) return "";
        const name = (toolProposal.tool_name || "").toLowerCase();
        const cmd = (toolProposal.command || "");
        if (name === "read" || name === "read_file" || name === "image") {
            if (/\.(png|jpg|jpeg|webp|svg|gif|bmp)$/i.test(cmd.trim())) {
                return cmd.trim();
            }
        }
        const match = cmd.match(/(?:^|\s)([\/\w\.-]+\.(png|jpg|jpeg|webp|svg|gif|bmp))/i);
        if (match && match[1]) {
            return match[1];
        }
        return "";
    }
    readonly property bool isImageRead: detectedImagePath.length > 0

    ColumnLayout {
        id: col
        anchors.fill: parent
        anchors.margins: 10
        spacing: 8

        // Warning Header
        RowLayout {
            spacing: 6
            Layout.fillWidth: true

            MaterialIcon {
                iconName: root.isImageRead ? "image" : ((toolProposal && toolProposal.requires_sudo) ? "lock" : "terminal")
                size: 16
                color: (toolProposal && toolProposal.requires_sudo) ? Colors.m3error : Colors.primary
            }

            Text {
                text: root.isImageRead
                    ? "AI Inspecting Image"
                    : ((toolProposal && toolProposal.requires_sudo) ? "Elevated Action Required (Sudo)" : "Command Execution Request")
                font.family: Theme.fontFamily
                font.pixelSize: 12
                font.weight: Font.Bold
                color: (toolProposal && toolProposal.requires_sudo) ? Colors.m3error : Colors.primary
            }

            Item { Layout.fillWidth: true }

            Rectangle {
                implicitHeight: 18
                implicitWidth: labelTxt.implicitWidth + 8
                radius: 4
                color: Qt.rgba(1, 1, 1, 0.08)

                Text {
                    id: labelTxt
                    anchors.centerIn: parent
                    text: root.isImageRead ? "VISION" : ((toolProposal && toolProposal.tool_name) ? toolProposal.tool_name.toUpperCase() : "BASH")
                    font.family: Theme.fontMonospace
                    font.pixelSize: 10
                    color: Colors.m3onSurfaceVariant
                }
            }
        }

        // Image Preview Container (when reading image)
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: Math.min(180, Math.max(100, previewImg.implicitHeight))
            radius: 8
            visible: root.isImageRead
            color: Colors.isDarkMode ? Qt.rgba(0.06, 0.07, 0.10, 0.98) : Qt.rgba(0.92, 0.94, 0.98, 0.98)
            border.width: 1
            border.color: Colors.glassBorderSpecular
            clip: true

            Image {
                id: previewImg
                anchors.centerIn: parent
                width: parent.width - 8
                height: parent.height - 8
                source: root.detectedImagePath ? (root.detectedImagePath.startsWith("file://") ? root.detectedImagePath : ("file://" + root.detectedImagePath)) : ""
                fillMode: Image.PreserveAspectFit
                smooth: true
            }
        }

        // Monospace Command Box
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: Math.max(34, cmdText.implicitHeight + 12)
            radius: 6
            color: Colors.m3surface
            border.width: 1
            border.color: Colors.m3outlineVariant

            Text {
                id: cmdText
                anchors.fill: parent
                anchors.margins: 6
                text: toolProposal ? toolProposal.command : ""
                font.family: Theme.fontMonospace
                font.pixelSize: 11
                color: Colors.m3onSurface
                wrapMode: Text.WrapAnywhere
            }
        }

        // Actions
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Item { Layout.fillWidth: true }

            // Deny Button
            Rectangle {
                implicitHeight: 28
                implicitWidth: 70
                radius: 6
                color: denyMouse.containsMouse ? Qt.rgba(1, 0.3, 0.3, 0.15) : "transparent"
                border.width: 1
                border.color: Colors.m3outlineVariant

                Text {
                    anchors.centerIn: parent
                    text: "Deny"
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    font.weight: Font.Medium
                    color: Colors.m3error
                }

                MouseArea {
                    id: denyMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.denied()
                }
            }

            // Approve Button
            Rectangle {
                implicitHeight: 28
                implicitWidth: 90
                radius: 6
                color: approveMouse.containsMouse ? Colors.m3primary : Qt.darker(Colors.m3primary, 1.1)

                Text {
                    anchors.centerIn: parent
                    text: (toolProposal && toolProposal.requires_sudo) ? "Run Sudo" : "Approve"
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    font.weight: Font.Bold
                    color: Colors.m3onPrimary
                }

                MouseArea {
                    id: approveMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.approved()
                }
            }
        }
    }
}
