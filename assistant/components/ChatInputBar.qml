import QtQuick
import QtQuick.Layouts
import QtQuick.Dialogs
import "../../theme"
import "../../components"
import "../../services"

Rectangle {
    id: root

    property var stagedFiles: []
    property alias stagedImages: root.stagedFiles

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

    function getFileName(path) {
        if (!path) return "";
        let parts = path.split("/");
        return parts[parts.length - 1];
    }

    function stageFile(filePath) {
        if (!filePath) return;
        let p = String(filePath).trim();
        if (p.startsWith("file://")) p = p.substring(7);
        let copy = stagedFiles.slice();
        if (copy.indexOf(p) === -1) {
            copy.push(p);
            stagedFiles = copy;
        }
    }

    function stageImage(imgPath) {
        stageFile(imgPath);
    }

    function unstageFile(index) {
        let copy = stagedFiles.slice();
        copy.splice(index, 1);
        stagedFiles = copy;
    }

    function unstageImage(index) {
        unstageFile(index);
    }

    function openNativeFileDialog() {
        nativeFileDialog.open();
    }

    implicitHeight: Math.min(190, Math.max(46, inputField.contentHeight + 20) + (stagedFiles.length > 0 ? 56 : 0))
    radius: 12
    color: (typeof Colors !== "undefined" && Colors.isDarkMode) ? Qt.rgba(0.10, 0.11, 0.16, 0.65) : Qt.rgba(0.94, 0.95, 0.98, 0.70)
    border.width: 1
    border.color: inputField.activeFocus ? Colors.primary : Colors.glassBorderSpecular

    signal submitMessage(string text, var images)
    signal requestOpenImagePicker()

    function focusInput() {
        inputField.forceActiveFocus();
    }

    readonly property bool isStreaming: (typeof AssistantService !== "undefined") ? AssistantService.isStreaming : false
    readonly property bool showSkillPopup: inputField.text.startsWith("/") && !inputField.text.includes(" ")

    // Native System File Explorer (Non-Modal to avoid layer-shell input freezes)
    FileDialog {
        id: nativeFileDialog
        title: "Select Files to Attach"
        fileMode: FileDialog.OpenFiles
        modality: Qt.NonModal
        nameFilters: [
            "All files (*)",
            "Images (*.png *.jpg *.jpeg *.webp *.svg *.gif *.bmp)",
            "Code & Config (*.rs *.py *.js *.ts *.qml *.json *.toml *.yaml *.yml *.sh *.css *.html *.md *.txt)",
            "Documents (*.pdf *.csv *.log *.doc *.docx)"
        ]
        onAccepted: {
            for (let i = 0; i < selectedFiles.length; i++) {
                root.stageFile(selectedFiles[i]);
            }
        }
    }

    DropArea {
        anchors.fill: parent
        onDropped: drop => {
            if (drop.hasUrls) {
                for (let i = 0; i < drop.urls.length; i++) {
                    let u = drop.urls[i].toString();
                    if (u.startsWith("file://")) u = u.substring(7);
                    root.stageFile(u);
                }
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 8
        anchors.topMargin: 6
        anchors.bottomMargin: 6
        spacing: 6

        // 1. Staged Files Thumbnail / Chip Strip (Visible when files are attached)
        Item {
            id: stagedStrip
            Layout.fillWidth: true
            implicitHeight: root.stagedFiles.length > 0 ? 50 : 0
            visible: root.stagedFiles.length > 0

            Flickable {
                anchors.fill: parent
                contentWidth: stagedRow.implicitWidth
                contentHeight: height
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Row {
                    id: stagedRow
                    spacing: 8
                    anchors.verticalCenter: parent.verticalCenter

                    Repeater {
                        model: root.stagedFiles

                        delegate: Rectangle {
                            id: thumbCard
                            readonly property bool isImg: root.isImageFile(modelData)
                            width: isImg ? 48 : Math.min(180, Math.max(80, fileLabelRow.implicitWidth + 28))
                            height: 44
                            radius: 8
                            color: (typeof Colors !== "undefined" && Colors.isDarkMode) ? Qt.rgba(0.12, 0.14, 0.20, 0.85) : Colors.glassCard
                            border.width: 1
                            border.color: Colors.glassBorderSpecular
                            clip: true

                            // Image thumbnail preview
                            Image {
                                visible: thumbCard.isImg
                                anchors.fill: parent
                                anchors.margins: 2
                                source: thumbCard.isImg ? (String(modelData).startsWith("file://") ? String(modelData) : ("file://" + String(modelData))) : ""
                                fillMode: Image.PreserveAspectCrop
                                smooth: true
                            }

                            // Non-image file badge with extension chip
                            RowLayout {
                                id: fileLabelRow
                                visible: !thumbCard.isImg
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 20
                                spacing: 6

                                Rectangle {
                                    implicitWidth: 26
                                    implicitHeight: 20
                                    radius: 4
                                    color: Qt.alpha(Colors.primary, 0.20)
                                    border.width: 1
                                    border.color: Qt.alpha(Colors.primary, 0.40)

                                    Text {
                                        anchors.centerIn: parent
                                        text: root.getFileExtension(modelData)
                                        font.family: Theme.fontMonospace
                                        font.pixelSize: 9
                                        font.weight: Font.Bold
                                        color: Colors.primary
                                    }
                                }

                                Text {
                                    text: root.getFileName(modelData)
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    color: Colors.m3onSurface
                                    elide: Text.ElideMiddle
                                    Layout.fillWidth: true
                                }
                            }

                            // Dismiss (x) button
                            Rectangle {
                                anchors.top: parent.top
                                anchors.right: parent.right
                                anchors.margins: 3
                                width: 16
                                height: 16
                                radius: 8
                                color: Qt.rgba(0, 0, 0, 0.70)
                                z: 10

                                MaterialIcon {
                                    anchors.centerIn: parent
                                    iconName: "close"
                                    size: 11
                                    color: "#ffffff"
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.unstageFile(index)
                                }
                            }
                        }
                    }
                }
            }
        }

        // 2. Input Row
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 8

            // Attachment Button (Native System File Uploader)
            Rectangle {
                id: attachButton
                Layout.preferredWidth: 32
                Layout.preferredHeight: 32
                implicitWidth: 32
                implicitHeight: 32
                radius: 8
                scale: attachMouse.pressed ? 0.94 : (attachMouse.containsMouse ? 1.05 : 1.0)
                Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
                color: attachMouse.containsMouse ? Colors.glassCardHover : "transparent"
                border.width: 1
                border.color: Colors.glassBorderSpecular

                MaterialIcon {
                    anchors.centerIn: parent
                    iconName: "attach_file"
                    size: 16
                    color: attachMouse.containsMouse ? Colors.primary : Colors.m3onSurfaceVariant
                }

                MouseArea {
                    id: attachMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.requestOpenImagePicker();
                    }
                }
            }


            Flickable {
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentHeight: inputField.implicitHeight
                clip: true

                TextEdit {
                    id: inputField
                    anchors.fill: parent
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontBodySmall
                    color: Colors.m3onSurface
                    selectionColor: Colors.primary
                    selectedTextColor: Colors.m3onPrimary
                    wrapMode: TextEdit.Wrap
                    verticalAlignment: TextEdit.AlignVCenter

                    Text {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !inputField.text && root.stagedImages.length === 0
                        opacity: inputField.activeFocus ? 0.6 : 0.9
                        text: "Ask Copilot, paste image, or type '/' for skills..."
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontBodySmall
                        color: Colors.m3onSurfaceVariant
                    }

                    function doSubmit(event) {
                        if (event.modifiers & Qt.ShiftModifier) {
                            event.accepted = false;
                        } else {
                            event.accepted = true;
                            if (inputField.text.trim().length > 0 || root.stagedImages.length > 0) {
                                root.submitMessage(inputField.text, root.stagedImages);
                                inputField.text = "";
                                root.stagedImages = [];
                            }
                        }
                    }

                    Keys.onReturnPressed: function(event) { doSubmit(event); }
                    Keys.onEnterPressed: function(event) { doSubmit(event); }
                    Keys.onEscapePressed: {
                        if (typeof Config !== "undefined") Config.closeAssistant();
                    }

                    // Clipboard Paste (Ctrl+V) Image Ingestion
                    Keys.onPressed: function(event) {
                        if (event.key === Qt.Key_V && (event.modifiers & Qt.ControlModifier)) {
                            if (typeof AssistantService !== "undefined" && typeof AssistantService.pasteClipboardImage === "function") {
                                AssistantService.pasteClipboardImage(function(path) {
                                    if (path && path.length > 0) {
                                        root.stageImage(path);
                                    }
                                });
                            }
                        }
                    }
                }
            }

            // Model Indicator Chip
            Rectangle {
                implicitHeight: 24
                implicitWidth: chipRow.implicitWidth + 12
                radius: 6
                color: Colors.glassCardHover
                border.width: 1
                border.color: Colors.glassBorderSpecular
                Layout.alignment: Qt.AlignVCenter

                RowLayout {
                    id: chipRow
                    anchors.centerIn: parent
                    spacing: 4

                    MaterialIcon {
                        iconName: "memory"
                        size: 12
                        color: Colors.secondary
                    }

                    Text {
                        text: ((typeof AssistantService !== "undefined") ? AssistantService.selectedModelId : "") || "auto"
                        font.family: Theme.fontMonospace
                        font.pixelSize: 10
                        font.weight: Font.Medium
                        color: Colors.m3onSurfaceVariant
                        elide: Text.ElideRight
                        Layout.maximumWidth: 110
                    }
                }
            }

            // Action Button: Send or Stop
            Rectangle {
                id: sendButton
                Layout.preferredWidth: 32
                Layout.preferredHeight: 32
                implicitWidth: 32
                implicitHeight: 32
                radius: 8
                readonly property bool hasContent: inputField.text.trim().length > 0 || root.stagedImages.length > 0
                readonly property bool isStreaming: root.isStreaming

                scale: sendMouse.pressed ? 0.94 : (sendMouse.containsMouse ? 1.05 : 1.0)
                Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }

                color: isStreaming 
                    ? (sendMouse.containsMouse ? Qt.alpha(Colors.m3error, 0.35) : Qt.alpha(Colors.m3error, 0.20))
                    : (hasContent 
                        ? (sendMouse.containsMouse ? Qt.alpha(Colors.primary, 0.32) : Qt.alpha(Colors.primary, 0.18))
                        : (sendMouse.containsMouse ? Colors.glassCardHover : "transparent"))

                border.width: 1
                border.color: isStreaming 
                    ? Colors.m3error 
                    : (hasContent ? Colors.primary : Colors.glassBorderSpecular)

                Behavior on color { ColorAnimation { duration: 150 } }
                Behavior on border.color { ColorAnimation { duration: 150 } }

                MaterialIcon {
                    anchors.centerIn: parent
                    iconName: sendButton.isStreaming ? "stop" : "send"
                    size: 16
                    color: sendButton.isStreaming 
                        ? Colors.m3error 
                        : (sendButton.hasContent 
                            ? Colors.primary 
                            : Colors.m3onSurfaceVariant)
                }

                MouseArea {
                    id: sendMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (sendButton.isStreaming) {
                            if (typeof AssistantService !== "undefined") AssistantService.stopStreaming();
                        } else if (sendButton.hasContent) {
                            root.submitMessage(inputField.text, root.stagedImages);
                            inputField.text = "";
                            root.stagedImages = [];
                        } else {
                            inputField.forceActiveFocus();
                        }
                    }
                }
            }
        }
    }

    // Skill Autocomplete Popup Modal
    Rectangle {
        id: skillPopup
        visible: root.showSkillPopup && filteredSkills.length > 0
        anchors.bottom: parent.top
        anchors.bottomMargin: 8
        anchors.left: parent.left
        anchors.right: parent.right
        implicitHeight: Math.min(220, skillCol.implicitHeight + 16)
        radius: 10
        color: (typeof Colors !== "undefined" && Colors.isDarkMode) ? Qt.rgba(0.10, 0.11, 0.16, 0.85) : Qt.rgba(0.96, 0.97, 1.0, 0.90)
        border.width: 1
        border.color: Colors.glassBorderSpecular
        clip: true

        readonly property string query: inputField.text.substring(1).toLowerCase()
        readonly property var allSkills: (typeof AssistantService !== "undefined") ? AssistantService.discoveredSkills : []
        readonly property var filteredSkills: {
            if (!query) return allSkills.slice(0, 5);
            return allSkills.filter(s => s.name.toLowerCase().includes(query) || s.description.toLowerCase().includes(query)).slice(0, 5);
        }

        Flickable {
            anchors.fill: parent
            anchors.margins: 8
            contentHeight: skillCol.implicitHeight
            clip: true

            ColumnLayout {
                id: skillCol
                width: parent.width
                spacing: 4

                Repeater {
                    model: skillPopup.filteredSkills

                    delegate: Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 36
                        radius: 6
                        color: skillMouse.containsMouse ? Qt.alpha(Colors.primary, 0.16) : "transparent"
                        border.width: skillMouse.containsMouse ? 1 : 0
                        border.color: skillMouse.containsMouse ? Qt.alpha(Colors.primary, 0.35) : "transparent"

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 8

                            MaterialIcon {
                                iconName: "bolt"
                                size: 14
                                color: Colors.primary
                            }

                            Text {
                                text: "/" + modelData.name
                                font.family: Theme.fontMonospace
                                font.pixelSize: 11
                                font.weight: Font.Bold
                                color: Colors.m3onSurface
                            }

                            Text {
                                text: modelData.description
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                color: Colors.m3onSurfaceVariant
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                        }

                        MouseArea {
                            id: skillMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                inputField.text = "/" + modelData.name + " ";
                                inputField.cursorPosition = inputField.text.length;
                                inputField.forceActiveFocus();
                            }
                        }
                    }
                }
            }
        }
    }
}
