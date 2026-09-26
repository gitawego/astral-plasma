import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../components"
import "../../services"

Rectangle {
    id: root

    signal sessionSelected(string sessionId)
    signal newSessionRequested()
    signal closed()

    implicitWidth: 280
    radius: 0
    color: Colors.isDarkMode ? Qt.rgba(0.04, 0.05, 0.08, 0.45) : Qt.rgba(0.96, 0.97, 0.99, 0.45)
    border.width: 0
    clip: true

    readonly property var allSessions: (typeof AssistantService !== "undefined" && AssistantService.sessions) ? AssistantService.sessions : []
    readonly property string activeId: (typeof AssistantService !== "undefined") ? AssistantService.activeSessionId : ""

    property string searchQuery: ""

    readonly property var filteredSessions: {
        let q = searchQuery.trim().toLowerCase();
        if (!q) return allSessions;
        return allSessions.filter(s => {
            return (s.title && s.title.toLowerCase().includes(q)) ||
                   (s.last_preview && s.last_preview.toLowerCase().includes(q));
        });
    }

    function formatTime(timestamp) {
        if (!timestamp) return "";
        let diffMs = Date.now() - timestamp;
        let diffSec = Math.floor(diffMs / 1000);
        let diffMin = Math.floor(diffSec / 60);
        let diffHour = Math.floor(diffMin / 60);
        let diffDay = Math.floor(diffHour / 24);

        if (diffSec < 60) return "Just now";
        if (diffMin < 60) return diffMin + "m ago";
        if (diffHour < 24) return diffHour + "h ago";
        if (diffDay < 7) return diffDay + "d ago";
        let d = new Date(timestamp);
        return d.toLocaleDateString();
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 12

        // 1. Header Bar
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            MaterialIcon {
                iconName: "history"
                size: 20
                color: Colors.primary
            }

            Text {
                text: "Chat Sessions"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontTitleSmall
                font.weight: Font.DemiBold
                color: Colors.m3onSurface
                Layout.fillWidth: true
            }

            // + New Chat Pill
            Rectangle {
                implicitHeight: 28
                implicitWidth: newChatRow.implicitWidth + 16
                radius: 14
                color: newChatMouse.containsMouse ? Colors.primary : Qt.alpha(Colors.primary, 0.85)

                RowLayout {
                    id: newChatRow
                    anchors.centerIn: parent
                    spacing: 4

                    MaterialIcon {
                        iconName: "add"
                        size: 14
                        color: Colors.isDarkMode ? "#12131A" : "#FFFFFF"
                    }

                    Text {
                        text: "New"
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        font.weight: Font.Bold
                        color: Colors.isDarkMode ? "#12131A" : "#FFFFFF"
                    }
                }

                MouseArea {
                    id: newChatMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (typeof AssistantService !== "undefined") {
                            AssistantService.createNewSession();
                        }
                        root.newSessionRequested();
                        root.closed();
                    }
                }
            }

            // Close Button
            Rectangle {
                width: 28
                height: 28
                radius: 8
                color: closeMouse.containsMouse ? Colors.glassCardHover : "transparent"

                MaterialIcon {
                    anchors.centerIn: parent
                    iconName: "close"
                    size: 16
                    color: closeMouse.containsMouse ? Colors.primary : Colors.m3onSurfaceVariant
                }

                MouseArea {
                    id: closeMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.closed()
                }
            }
        }

        // 2. Search Filter Box
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 32
            radius: 8
            color: Colors.m3surfaceContainer
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
                    font.pixelSize: Theme.fontBodySmall
                    color: Colors.m3onSurface
                    clip: true
                    onTextChanged: root.searchQuery = text

                    Text {
                        anchors.fill: parent
                        text: "Search sessions..."
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontBodySmall
                        color: Colors.m3onSurfaceVariant
                        opacity: 0.6
                        visible: !searchInput.text
                    }
                }

                // Clear search
                Rectangle {
                    visible: !!searchInput.text
                    width: 16
                    height: 16
                    radius: 8
                    color: "transparent"

                    MaterialIcon {
                        anchors.centerIn: parent
                        iconName: "close"
                        size: 12
                        color: Colors.m3onSurfaceVariant
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            searchInput.text = "";
                            root.searchQuery = "";
                        }
                    }
                }
            }
        }

        // 3. Scrollable Session List
        Flickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentHeight: sessionListCol.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            ColumnLayout {
                id: sessionListCol
                width: parent.width
                spacing: 6

                // Empty State
                Item {
                    visible: root.filteredSessions.length === 0
                    Layout.fillWidth: true
                    implicitHeight: 120

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 8

                        MaterialIcon {
                            Layout.alignment: Qt.AlignHCenter
                            iconName: "forum"
                            size: 28
                            color: Colors.m3onSurfaceVariant
                            opacity: 0.5
                        }

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: root.searchQuery ? "No matching sessions" : "No previous sessions yet"
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            color: Colors.m3onSurfaceVariant
                            opacity: 0.8
                        }
                    }
                }

                Repeater {
                    model: root.filteredSessions

                    delegate: Rectangle {
                        id: sessionCard
                        Layout.fillWidth: true
                        implicitHeight: cardContent.implicitHeight + 16
                        radius: 10

                        readonly property bool isActive: modelData.id === root.activeId

                        color: isActive
                            ? Qt.alpha(Colors.primary, 0.16)
                            : (cardMouse.containsMouse ? Colors.glassCardHover : Colors.glassCard)
                        border.width: 1
                        border.color: isActive
                            ? Qt.alpha(Colors.primary, 0.50)
                            : Colors.glassBorderSpecular

                        Behavior on color { ColorAnimation { duration: 120 } }
                        Behavior on border.color { ColorAnimation { duration: 120 } }

                        RowLayout {
                            id: cardContent
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 10

                            // Session Status Pill / Dot
                            Rectangle {
                                width: 4
                                implicitHeight: 28
                                radius: 2
                                color: sessionCard.isActive ? Colors.primary : "transparent"
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                // Title Row
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6

                                    Text {
                                        text: modelData.title || "Untitled Chat"
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 12
                                        font.weight: sessionCard.isActive ? Font.Bold : Font.DemiBold
                                        color: sessionCard.isActive ? Colors.primary : Colors.m3onSurface
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }

                                    // Message count chip
                                    Rectangle {
                                        implicitHeight: 18
                                        implicitWidth: countText.implicitWidth + 10
                                        radius: 9
                                        color: Qt.alpha(Colors.m3onSurface, 0.08)

                                        Text {
                                            id: countText
                                            anchors.centerIn: parent
                                            text: (modelData.message_count || 0) + " msg"
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 9
                                            color: Colors.m3onSurfaceVariant
                                        }
                                    }
                                }

                                // Preview snippet
                                Text {
                                    text: modelData.last_preview || "No messages"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 10
                                    color: Colors.m3onSurfaceVariant
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                    opacity: 0.8
                                }

                                // Timestamp
                                Text {
                                    text: root.formatTime(modelData.updated_at)
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 9
                                    color: Colors.m3onSurfaceVariant
                                    opacity: 0.6
                                }
                            }

                            // Delete Action Button (Visible on card hover or active)
                            Rectangle {
                                width: 26
                                height: 26
                                radius: 6
                                color: delMouse.containsMouse ? Qt.rgba(1, 0.2, 0.2, 0.2) : "transparent"
                                opacity: (cardMouse.containsMouse || delMouse.containsMouse) ? 1.0 : 0.0

                                Behavior on opacity { NumberAnimation { duration: 150 } }

                                MaterialIcon {
                                    anchors.centerIn: parent
                                    iconName: "delete"
                                    size: 14
                                    color: delMouse.containsMouse ? Colors.m3error : Colors.m3onSurfaceVariant
                                }

                                MouseArea {
                                    id: delMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (typeof AssistantService !== "undefined") {
                                            AssistantService.deleteSession(modelData.id);
                                        }
                                    }
                                }
                            }
                        }

                        MouseArea {
                            id: cardMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (typeof AssistantService !== "undefined") {
                                    AssistantService.loadSession(modelData.id);
                                }
                                root.sessionSelected(modelData.id);
                                root.closed();
                            }
                        }
                    }
                }
            }
        }
    }
}
