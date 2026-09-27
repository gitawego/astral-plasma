import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../components"
import "../../services"

Rectangle {
    id: root

    signal closed()

    color: Qt.rgba(0, 0, 0, 0.65)
    anchors.fill: parent
    z: 200

    MouseArea {
        anchors.fill: parent
        onClicked: root.closed()
    }

    Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width - 40, 380)
        implicitHeight: dialogCol.implicitHeight + 32
        radius: 16
        color: (typeof Colors !== "undefined" && Colors.isDarkMode) ? Qt.rgba(0.12, 0.14, 0.20, 0.90) : Qt.rgba(0.96, 0.97, 1.0, 0.90)
        border.width: 1
        border.color: Colors.glassBorderSpecular

        MouseArea {
            anchors.fill: parent
            // prevent closing when clicking inside dialog
        }

        ColumnLayout {
            id: dialogCol
            anchors.fill: parent
            anchors.margins: 16
            spacing: 12

            Text {
                text: "Add AI Provider"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontTitleSmall
                font.weight: Font.Bold
                color: Colors.m3onSurface
            }

            // Provider Type Selector
            ColumnLayout {
                spacing: 4
                Layout.fillWidth: true

                Text {
                    text: "Provider Type"
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    color: Colors.m3onSurfaceVariant
                }

                RowLayout {
                    spacing: 6
                    Repeater {
                        model: ["Ollama", "OpenAI", "Anthropic"]
                        delegate: Rectangle {
                            implicitHeight: 28
                            implicitWidth: typeTxt.implicitWidth + 16
                            radius: 6
                            color: typeMouse.containsMouse ? Colors.glassCardHover : (root.selectedType === modelData ? Colors.m3primaryContainer : Colors.glassCard)
                            border.width: 1
                            border.color: root.selectedType === modelData ? Colors.primary : Colors.glassBorderSpecular

                            Text {
                                id: typeTxt
                                anchors.centerIn: parent
                                text: modelData
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                font.weight: root.selectedType === modelData ? Font.Bold : Font.Normal
                                color: root.selectedType === modelData ? Colors.m3onPrimaryContainer : Colors.m3onSurface
                            }

                            MouseArea {
                                id: typeMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.selectedType = modelData;
                                    if (modelData === "Ollama") {
                                        endpointInput.text = "http://localhost:11434/v1";
                                        modelInput.text = "llama3.2";
                                    } else if (modelData === "OpenAI") {
                                        endpointInput.text = "https://api.openai.com/v1";
                                        modelInput.text = "gpt-4o-mini";
                                    } else {
                                        endpointInput.text = "https://api.anthropic.com/v1";
                                        modelInput.text = "claude-3-5-haiku-20241022";
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Endpoint Input
            ColumnLayout {
                spacing: 4
                Layout.fillWidth: true

                Text {
                    text: "Base URL Endpoint"
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    color: Colors.m3onSurfaceVariant
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 32
                    radius: 6
                    color: (typeof Colors !== "undefined" && Colors.isDarkMode) ? Qt.rgba(0.06, 0.07, 0.10, 0.60) : Qt.rgba(0.92, 0.93, 0.96, 0.60)
                    border.width: 1
                    border.color: Colors.glassBorderSpecular

                    TextInput {
                        id: endpointInput
                        anchors.fill: parent
                        anchors.margins: 6
                        text: "http://localhost:11434/v1"
                        font.family: Theme.fontMonospace
                        font.pixelSize: 11
                        color: Colors.m3onSurface
                    }
                }
            }

            // API Key Input
            ColumnLayout {
                spacing: 4
                Layout.fillWidth: true

                Text {
                    text: "API Key (optional for Ollama)"
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    color: Colors.m3onSurfaceVariant
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 32
                    radius: 6
                    color: (typeof Colors !== "undefined" && Colors.isDarkMode) ? Qt.rgba(0.06, 0.07, 0.10, 0.60) : Qt.rgba(0.92, 0.93, 0.96, 0.60)
                    border.width: 1
                    border.color: Colors.glassBorderSpecular

                    TextInput {
                        id: keyInput
                        anchors.fill: parent
                        anchors.margins: 6
                        echoMode: TextInput.Password
                        font.family: Theme.fontMonospace
                        font.pixelSize: 11
                        color: Colors.m3onSurface
                    }
                }
            }

            // Model ID
            ColumnLayout {
                spacing: 4
                Layout.fillWidth: true

                Text {
                    text: "Model Identifier"
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    color: Colors.m3onSurfaceVariant
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 32
                    radius: 6
                    color: (typeof Colors !== "undefined" && Colors.isDarkMode) ? Qt.rgba(0.06, 0.07, 0.10, 0.60) : Qt.rgba(0.92, 0.93, 0.96, 0.60)
                    border.width: 1
                    border.color: Colors.glassBorderSpecular

                    TextInput {
                        id: modelInput
                        anchors.fill: parent
                        anchors.margins: 6
                        text: "llama3.2"
                        font.family: Theme.fontMonospace
                        font.pixelSize: 11
                        color: Colors.m3onSurface
                    }
                }
            }

            // Actions
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Item { Layout.fillWidth: true }

                Rectangle {
                    implicitHeight: 30
                    implicitWidth: 70
                    radius: 15
                    scale: cancelMouse.pressed ? 0.94 : (cancelMouse.containsMouse ? 1.04 : 1.0)
                    Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
                    color: cancelMouse.containsMouse ? Colors.glassCardHover : "transparent"
                    border.width: 1
                    border.color: cancelMouse.containsMouse ? Colors.primary : Colors.glassBorderSpecular

                    Text {
                        anchors.centerIn: parent
                        text: "Cancel"
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        color: Colors.m3onSurface
                    }

                    MouseArea {
                        id: cancelMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.closed()
                    }
                }

                Rectangle {
                    implicitHeight: 30
                    implicitWidth: 80
                    radius: 15
                    scale: saveMouse.pressed ? 0.94 : (saveMouse.containsMouse ? 1.04 : 1.0)
                    Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
                    color: saveMouse.containsMouse ? Qt.alpha(Colors.primary, 0.32) : Qt.alpha(Colors.primary, 0.18)
                    border.width: 1
                    border.color: Colors.primary

                    Behavior on color { ColorAnimation { duration: 150 } }
                    Behavior on border.color { ColorAnimation { duration: 150 } }

                    Text {
                        anchors.centerIn: parent
                        text: "Save"
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        color: Colors.primary
                    }

                    MouseArea {
                        id: saveMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            let pId = root.selectedType.toLowerCase();
                            AssistantService.selectedProviderId = pId;
                            AssistantService.selectedModelId = modelInput.text;
                            root.closed();
                        }
                    }
                }
            }
        }
    }

    property string selectedType: "Ollama"
}
