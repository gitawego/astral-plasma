import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../components"
import "../../services"

Flickable {
    id: root

    contentWidth: width
    contentHeight: msgCol.implicitHeight + 40
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    property bool testMode: false
    property var testMessages: null

    readonly property var currentMessages: {
        if (testMode && testMessages !== null) return testMessages;
        if (typeof AssistantService !== "undefined") {
            let _ = AssistantService.messagesRevision;
            return AssistantService.messages;
        }
        return [];
    }

    function scrollToBottom() {
        if (contentHeight > height) {
            contentY = contentHeight - height;
        }
    }

    Connections {
        target: (typeof AssistantService !== "undefined") ? AssistantService : null
        function onMessagesChanged() {
            Qt.callLater(root.scrollToBottom);
        }
        function onActiveStreamingContentChanged() {
            Qt.callLater(root.scrollToBottom);
        }
    }

    function parseBlocks(content) {
        if (!content) return [{ type: "text", text: "" }];
        const blocks = [];
        const regex = /```mermaid\s*\n([\s\S]*?)```/g;
        let lastIndex = 0;
        let match;

        while ((match = regex.exec(content)) !== null) {
            if (match.index > lastIndex) {
                const txt = content.substring(lastIndex, match.index).trim();
                if (txt.length > 0) {
                    blocks.push({ type: "text", text: txt });
                }
            }
            blocks.push({ type: "mermaid", source: match[1].trim() });
            lastIndex = regex.lastIndex;
        }

        if (lastIndex < content.length) {
            const remaining = content.substring(lastIndex).trim();
            if (remaining.length > 0) {
                blocks.push({ type: "text", text: remaining });
            }
        }

        return blocks.length > 0 ? blocks : [{ type: "text", text: content }];
    }

    Column {
        id: msgCol
        width: root.width - (Theme.padLarge * 2)
        x: Theme.padLarge
        y: Theme.padSmall
        spacing: Theme.spaceMedium

    Repeater {
        model: root.currentMessages
        delegate: Item {
            id: delegateItem
            width: msgCol.width
            implicitHeight: delCol.implicitHeight

            readonly property bool isUser: modelData.role === "user"
            readonly property bool isTool: modelData.role === "tool"
            readonly property bool isSystem: modelData.role === "system"

            readonly property bool isLastAssistantMessage: index === (root.currentMessages.length - 1) && modelData.role === "assistant"
            readonly property bool isCurrentlyStreaming: isLastAssistantMessage && (typeof AssistantService !== "undefined" && AssistantService.isStreaming)
            readonly property int itemRevision: (typeof AssistantService !== "undefined") ? AssistantService.messagesRevision : 0

            readonly property string fullContent: {
                let _ = itemRevision;
                if (isCurrentlyStreaming) {
                    let live = (typeof AssistantService !== "undefined") ? AssistantService.activeStreamingContent : "";
                    if (live && live.length > 0) return live;
                    return "Thinking...";
                }
                let msg = (root.currentMessages && index < root.currentMessages.length) ? root.currentMessages[index] : modelData;
                return (msg && msg.content) ? msg.content : "";
            }

            readonly property var contentBlocks: root.parseBlocks(fullContent)
            readonly property var attachedImages: {
                let _ = itemRevision;
                let msg = (root.currentMessages && index < root.currentMessages.length) ? root.currentMessages[index] : modelData;
                let imgs = (msg && msg.images && msg.images.length > 0) ? msg.images : [];
                let fls = (msg && msg.files && msg.files.length > 0) ? msg.files : [];
                return imgs.concat(fls);
            }

            Column {
                id: delCol
                width: parent.width
                spacing: 6

                // Attached Files Strip (User uploads or message attachments)
                Item {
                    id: imagesContainer
                    width: parent.width
                    implicitHeight: delegateItem.attachedImages.length > 0 ? imagesRow.implicitHeight : 0
                    height: implicitHeight
                    visible: delegateItem.attachedImages.length > 0

                    Row {
                        id: imagesRow
                        anchors.right: isUser ? parent.right : undefined
                        anchors.left: isUser ? undefined : parent.left
                        spacing: 8

                        Repeater {
                            model: delegateItem.attachedImages
                            delegate: Rectangle {
                                readonly property bool isImg: /\.(png|jpg|jpeg|webp|svg|gif|bmp)$/i.test(String(modelData))
                                width: isImg ? Math.min(160, Math.round(msgCol.width * 0.38)) : Math.min(220, Math.max(120, fileCardRow.implicitWidth + 24))
                                height: isImg ? 110 : 44
                                radius: 10
                                clip: true
                                color: Colors.surfaceContainerHighest
                                border.width: 1
                                border.color: Colors.glassBorderSpecular

                                Image {
                                    visible: isImg
                                    anchors.fill: parent
                                    anchors.margins: 2
                                    source: isImg ? (String(modelData).startsWith("file://") ? String(modelData) : ("file://" + String(modelData))) : ""
                                    fillMode: Image.PreserveAspectCrop
                                    smooth: true
                                }

                                RowLayout {
                                    id: fileCardRow
                                    visible: !isImg
                                    anchors.fill: parent
                                    anchors.margins: 8
                                    spacing: 8

                                    Rectangle {
                                        implicitWidth: 28
                                        implicitHeight: 22
                                        radius: 4
                                        color: Qt.alpha(Colors.primary, 0.20)
                                        border.width: 1
                                        border.color: Qt.alpha(Colors.primary, 0.40)

                                        Text {
                                            anchors.centerIn: parent
                                            text: {
                                                let p = String(modelData);
                                                let parts = p.split(".");
                                                return parts.length > 1 ? parts[parts.length - 1].toUpperCase().substring(0, 4) : "FILE";
                                            }
                                            font.family: Theme.fontMonospace
                                            font.pixelSize: 9
                                            font.weight: Font.Bold
                                            color: Colors.primary
                                        }
                                    }

                                    Text {
                                        text: {
                                            let p = String(modelData);
                                            let parts = p.split("/");
                                            return parts[parts.length - 1];
                                        }
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 11
                                        color: Colors.m3onSurface
                                        elide: Text.ElideMiddle
                                        Layout.fillWidth: true
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        let p = String(modelData).startsWith("file://") ? String(modelData) : ("file://" + String(modelData));
                                        Qt.openUrlExternally(p);
                                    }
                                }
                            }
                        }
                    }
                }

                // Render Content Blocks (Text and Mermaid Diagrams)
                Repeater {
                    model: delegateItem.contentBlocks
                    delegate: Item {
                        id: blockItem
                        width: msgCol.width
                        implicitHeight: blockLoader.implicitHeight

                        Loader {
                            id: blockLoader
                            width: msgCol.width
                            sourceComponent: modelData.type === "mermaid" ? mermaidComp : textComp
                        }

                        // Mermaid Diagram Component
                        Component {
                            id: mermaidComp
                            Item {
                                width: msgCol.width
                                implicitHeight: mCard.implicitHeight
                                MermaidDiagramCard {
                                    id: mCard
                                    width: Math.min(msgCol.width * 0.95, 600)
                                    mermaidSource: modelData.source || ""
                                    x: isUser ? (msgCol.width - width) : 0
                                }
                            }
                        }

                        // Standard Text Bubble Component
                        Component {
                            id: textComp
                            Item {
                                width: msgCol.width
                                implicitHeight: bubbleRect.implicitHeight

                                Rectangle {
                                    id: bubbleRect
                                    x: isUser ? (msgCol.width - width) : 0
                                    width: Math.min(msgCol.width * 0.90, bubbleText.implicitWidth + 32)
                                    height: bubbleText.implicitHeight + 24
                                    implicitHeight: bubbleText.implicitHeight + 24
                                    radius: 14
                                    color: isUser 
                                        ? (Colors.isDarkMode ? Qt.tint(Colors.m3primaryContainer, Qt.rgba(0, 0, 0, 0.15)) : Colors.m3primaryContainer) 
                                        : (isTool ? Colors.m3surfaceContainerLowest : (Colors.isDarkMode ? Qt.rgba(0.14, 0.16, 0.22, 0.98) : Qt.rgba(0.92, 0.94, 0.98, 0.98)))
                                    border.width: 1
                                    border.color: isUser ? Colors.primary : (Colors.isDarkMode ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(0, 0, 0, 0.10))

                                    Text {
                                        id: bubbleText
                                        x: 16
                                        y: 12
                                        width: Math.min(implicitWidth, msgCol.width * 0.90 - 32)
                                        text: modelData.text || ""
                                        textFormat: Text.MarkdownText
                                        font.family: isTool ? Theme.fontMonospace : Theme.fontFamily
                                        font.pixelSize: (typeof Theme !== "undefined" && Theme.fontBodyMedium) ? Theme.fontBodyMedium : 13
                                        lineHeight: 1.25
                                        color: isUser ? Colors.m3onPrimaryContainer : Colors.m3onSurface
                                        wrapMode: Text.Wrap
                                    }
                                }
                            }
                        }
                    }
                }

                // Interactive Tool Proposal Cards (if any)
                Repeater {
                    model: {
                        let _ = itemRevision;
                        if (isCurrentlyStreaming && typeof AssistantService !== "undefined") {
                            return AssistantService.activeToolProposals || [];
                        }
                        return (modelData.tool_calls && modelData.tool_calls.length > 0) ? modelData.tool_calls : [];
                    }
                    delegate: ToolConfirmationCard {
                        toolProposal: modelData
                        onApproved: {
                            if (typeof AssistantService !== "undefined") AssistantService.approveToolCall(modelData);
                        }
                        onDenied: {
                            if (typeof AssistantService !== "undefined") AssistantService.denyToolCall(modelData);
                        }
                    }
                }
            }
        }
    }
}
}
