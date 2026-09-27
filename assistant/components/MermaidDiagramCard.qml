import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../components"
import "../../services"

Rectangle {
    id: root

    property string mermaidSource: ""
    property string initialKind: "diagram"

    property bool showSource: false
    property bool isRendering: true
    property string diagramHtml: ""
    property string diagramPlain: ""
    property string diagramKind: initialKind
    property int diagramLines: 0
    property int diagramWidth: 40
    property string errorMessage: ""
    property bool copyFeedback: false

    implicitWidth: 380
    implicitHeight: colLayout.implicitHeight + 16
    radius: 12
    color: (typeof Colors !== "undefined" && Colors.isDarkMode) ? Qt.rgba(0.12, 0.14, 0.20, 0.85) : Colors.glassCard
    border.width: 1
    border.color: Colors.glassBorderSpecular

    function renderDiagram() {
        if (!mermaidSource || mermaidSource.trim().length === 0) return;
        isRendering = true;
        errorMessage = "";

        if (typeof AssistantService !== "undefined" && typeof AssistantService.renderMermaid === "function") {
            AssistantService.renderMermaid(mermaidSource.trim(), function(res) {
                if (res && res.success) {
                    root.diagramHtml = res.html || "";
                    root.diagramPlain = res.plain || "";
                    root.diagramKind = res.kind || "diagram";
                    root.diagramLines = res.lines || 0;
                    root.diagramWidth = res.width || 40;
                    root.errorMessage = "";
                } else {
                    root.errorMessage = (res && res.error) ? res.error : "Failed to render diagram";
                }
                root.isRendering = false;
            });
        } else {
            // Standalone / offscreen test fallback
            root.diagramPlain = mermaidSource.trim();
            root.diagramHtml = "<pre style='font-family: monospace;'>" + mermaidSource.trim() + "</pre>";
            root.diagramKind = root.initialKind || "diagram";
            root.isRendering = false;
        }
    }

    onMermaidSourceChanged: renderDiagram()
    Component.onCompleted: renderDiagram()

    Timer {
        id: copyTimer
        interval: 1800
        repeat: false
        onTriggered: root.copyFeedback = false
    }

    ColumnLayout {
        id: colLayout
        anchors.fill: parent
        anchors.margins: 10
        spacing: 8

        // Top Header Bar
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            MaterialIcon {
                iconName: "schema"
                size: 16
                color: Colors.primary
            }

            Text {
                text: "Mermaid Diagram"
                font.family: Theme.fontFamily
                font.pixelSize: 12
                font.weight: Font.DemiBold
                color: Colors.m3onSurface
            }

            // Kind Pill (Liquid Glass)
            Rectangle {
                implicitHeight: 18
                implicitWidth: kindTxt.implicitWidth + 10
                radius: 9
                color: Qt.alpha(Colors.primary, 0.18)
                border.width: 1
                border.color: Qt.alpha(Colors.primary, 0.35)

                Text {
                    id: kindTxt
                    anchors.centerIn: parent
                    text: root.diagramKind.toUpperCase()
                    font.family: Theme.fontMonospace
                    font.pixelSize: 9
                    font.weight: Font.Bold
                    color: Colors.primary
                }
            }

            Item { Layout.fillWidth: true }

            // Source / Diagram Toggle Button
            Rectangle {
                implicitHeight: 24
                implicitWidth: toggleRow.implicitWidth + 10
                radius: 12
                scale: toggleMouse.pressed ? 0.92 : (toggleMouse.containsMouse ? 1.04 : 1.0)
                Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
                color: toggleMouse.containsMouse ? Colors.glassCardHover : Qt.rgba(1, 1, 1, 0.06)
                border.width: 1
                border.color: toggleMouse.containsMouse ? Colors.primary : Colors.glassBorderSpecular

                RowLayout {
                    id: toggleRow
                    anchors.centerIn: parent
                    spacing: 4

                    MaterialIcon {
                        iconName: root.showSource ? "visibility" : "code"
                        size: 13
                        color: toggleMouse.containsMouse ? Colors.primary : Colors.m3onSurfaceVariant
                    }

                    Text {
                        text: root.showSource ? "Diagram" : "Source"
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        font.weight: Font.Medium
                        color: toggleMouse.containsMouse ? Colors.primary : Colors.m3onSurfaceVariant
                    }
                }

                MouseArea {
                    id: toggleMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.showSource = !root.showSource
                }
            }

            // Copy Button
            Rectangle {
                implicitHeight: 24
                implicitWidth: copyRow.implicitWidth + 10
                radius: 12
                scale: copyMouse.pressed ? 0.92 : (copyMouse.containsMouse ? 1.04 : 1.0)
                Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
                color: copyMouse.containsMouse ? Colors.glassCardHover : Qt.rgba(1, 1, 1, 0.06)
                border.width: 1
                border.color: copyMouse.containsMouse ? Colors.primary : Colors.glassBorderSpecular

                RowLayout {
                    id: copyRow
                    anchors.centerIn: parent
                    spacing: 4

                    MaterialIcon {
                        iconName: root.copyFeedback ? "check" : "content_copy"
                        size: 13
                        color: root.copyFeedback ? Colors.primary : (copyMouse.containsMouse ? Colors.primary : Colors.m3onSurfaceVariant)
                    }

                    Text {
                        text: root.copyFeedback ? "Copied!" : "Copy"
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        font.weight: Font.Medium
                        color: root.copyFeedback ? Colors.primary : (copyMouse.containsMouse ? Colors.primary : Colors.m3onSurfaceVariant)
                    }
                }

                MouseArea {
                    id: copyMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (typeof AssistantService !== "undefined" && typeof AssistantService.copyToClipboard === "function") {
                            AssistantService.copyToClipboard(root.mermaidSource);
                        }
                        root.copyFeedback = true;
                        copyTimer.start();
                    }
                }
            }
        }

        // Body Content
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: Math.max(60, Math.min(380, bodyContent.implicitHeight + 16))
            radius: 8
            color: Colors.isDarkMode ? Qt.rgba(0.05, 0.06, 0.09, 0.65) : Qt.rgba(0.95, 0.96, 0.99, 0.65)
            border.width: 1
            border.color: Colors.glassBorderSpecular
            clip: true

            Flickable {
                id: bodyScroll
                anchors.fill: parent
                anchors.margins: 8
                contentWidth: Math.max(width, bodyContent.implicitWidth)
                contentHeight: Math.max(height, bodyContent.implicitHeight)
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Item {
                    id: bodyContent
                    width: Math.max(bodyScroll.width, Math.max(diagramText.implicitWidth, sourceText.implicitWidth))
                    height: Math.max(diagramText.implicitHeight, sourceText.implicitHeight)
                    implicitWidth: root.showSource ? sourceText.implicitWidth : diagramText.implicitWidth
                    implicitHeight: root.showSource ? sourceText.implicitHeight : diagramText.implicitHeight

                    // 1. Rendered Styled RichText Diagram
                    Text {
                        id: diagramText
                        visible: !root.showSource && !root.isRendering && !root.errorMessage
                        textFormat: Text.RichText
                        text: root.diagramHtml
                        font.family: Theme.fontMonospace
                        font.pixelSize: 11
                        lineHeight: 1.25
                        color: Colors.m3onSurface
                    }

                    // 2. Raw Mermaid Source View
                    Text {
                        id: sourceText
                        visible: root.showSource
                        text: root.mermaidSource
                        font.family: Theme.fontMonospace
                        font.pixelSize: 11
                        lineHeight: 1.3
                        color: Colors.secondary
                        wrapMode: Text.NoWrap
                    }

                    // 3. Loading Indicator
                    RowLayout {
                        visible: root.isRendering
                        spacing: 8
                        MaterialIcon {
                            iconName: "hourglass_top"
                            size: 14
                            color: Colors.primary
                        }
                        Text {
                            text: "Rendering diagram..."
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            color: Colors.m3onSurfaceVariant
                        }
                    }

                    // 4. Error Fallback
                    ColumnLayout {
                        visible: !root.isRendering && !!root.errorMessage && !root.showSource
                        spacing: 4
                        Text {
                            text: "Unable to render diagram: " + root.errorMessage
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            color: Colors.m3error
                        }
                        Text {
                            text: root.mermaidSource
                            font.family: Theme.fontMonospace
                            font.pixelSize: 11
                            color: Colors.m3onSurfaceVariant
                        }
                    }
                }
            }
        }
    }
}
