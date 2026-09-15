import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import "../theme"
import "../components"
import "../services"

Item {
    id: root
    implicitWidth: parent ? parent.width : 1920
    implicitHeight: parent ? parent.height : 1080

    // Service state bindings with safe fallbacks and test overrides
    property bool testVisible: false
    property string testAction: ""
    property string testTitle: ""
    property string testMessage: ""
    property string testIcon: ""
    property string testConfirmLabel: ""
    property color testAccentColor: "transparent"

    readonly property bool isDialogVisible: testVisible || ((typeof PowerService !== "undefined" && PowerService) ? (PowerService.confirmDialogVisible ?? false) : false)
    readonly property string currentAction: testVisible ? testAction : ((typeof PowerService !== "undefined" && PowerService) ? (PowerService.pendingAction ?? "") : "")
    readonly property string currentTitle: testVisible ? testTitle : ((typeof PowerService !== "undefined" && PowerService) ? (PowerService.pendingTitle ?? "") : "")
    readonly property string currentMessage: testVisible ? testMessage : ((typeof PowerService !== "undefined" && PowerService) ? (PowerService.pendingMessage ?? "") : "")
    readonly property string currentIcon: testVisible ? testIcon : ((typeof PowerService !== "undefined" && PowerService) ? (PowerService.pendingIcon ?? "power_settings_new") : "power_settings_new")
    readonly property string currentConfirmLabel: testVisible ? testConfirmLabel : ((typeof PowerService !== "undefined" && PowerService) ? (PowerService.pendingConfirmLabel ?? "Confirm") : "Confirm")
    readonly property color currentAccentColor: testVisible
        ? testAccentColor
        : (((typeof PowerService !== "undefined" && PowerService && PowerService.pendingAccentColor) 
            ? PowerService.pendingAccentColor 
            : ((typeof Colors !== "undefined" && Colors.primary) ? Colors.primary : "#6B4FA0")))

    signal confirmed()
    signal canceled()

    function cancelAction() {
        if (typeof PowerService !== "undefined" && PowerService && typeof PowerService.cancelAction === "function") {
            PowerService.cancelAction();
        }
        root.canceled();
    }

    function confirmAction() {
        if (typeof PowerService !== "undefined" && PowerService && typeof PowerService.confirmAction === "function") {
            PowerService.confirmAction();
        }
        root.confirmed();
    }

    visible: opacity > 0.001
    opacity: root.isDialogVisible ? 1.0 : 0.0

    Behavior on opacity {
        NumberAnimation {
            duration: (typeof Theme !== "undefined" && Theme.animExpressiveFastEffects) ? Theme.animExpressiveFastEffects : 150
            easing.type: Easing.BezierSpline
            easing.bezierCurve: (typeof Theme !== "undefined" && Theme.curveExpressiveFastEffects) ? Theme.curveExpressiveFastEffects : [0.31, 0.94, 0.34, 1.0, 1.0, 1.0]
        }
    }

    onIsDialogVisibleChanged: {
        if (root.isDialogVisible) {
            dialogCard.forceActiveFocus();
        }
    }

    // Fullscreen Scrim Backdrop
    Rectangle {
        id: scrim
        anchors.fill: parent
        color: Qt.rgba(0.08, 0.07, 0.10, 0.48)

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onClicked: root.cancelAction()
        }
    }

    // Modal Confirmation Dialog Card
    Rectangle {
        id: dialogCard
        anchors.centerIn: parent
        width: 420
        implicitHeight: cardLayout.implicitHeight + 48
        radius: (typeof Theme !== "undefined" && Theme.radiusLarge) ? Theme.radiusLarge : 24

        color: (typeof Colors !== "undefined" && Colors.surface) ? Colors.surface : "#FAF8F5"
        border.width: 1
        border.color: (typeof Theme !== "undefined" && Theme.borderSubtle) ? Theme.borderSubtle : Qt.alpha(Colors.outline, 0.20)

        scale: root.isDialogVisible ? 1.0 : 0.93
        Behavior on scale {
            NumberAnimation {
                duration: (typeof Theme !== "undefined" && Theme.animExpressiveDefaultSpatial) ? Theme.animExpressiveDefaultSpatial : 500
                easing.type: Easing.BezierSpline
                easing.bezierCurve: (typeof Theme !== "undefined" && Theme.curveExpressiveDefaultSpatial) ? Theme.curveExpressiveDefaultSpatial : [0.38, 1.21, 0.22, 1.0, 1.0, 1.0]
            }
        }

        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            blurMax: 48
            shadowBlur: 0.85
            shadowVerticalOffset: 10
            shadowColor: Qt.rgba(0, 0, 0, 0.30)
        }

        // Catch clicks on the card
        MouseArea {
            anchors.fill: parent
            onClicked: {}
        }

        focus: true
        Keys.onEscapePressed: root.cancelAction()
        Keys.onReturnPressed: root.confirmAction()
        Keys.onEnterPressed: root.confirmAction()

        ColumnLayout {
            id: cardLayout
            anchors.fill: parent
            anchors.margins: 28
            spacing: (typeof Theme !== "undefined" && Theme.spaceLarge) ? Theme.spaceLarge : 16

            // Header Icon Badge
            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                width: 60
                height: 60
                radius: (typeof Theme !== "undefined" && Theme.radiusFull) ? Theme.radiusFull : 9999
                color: Qt.alpha(root.currentAccentColor, 0.14)

                MaterialIcon {
                    anchors.centerIn: parent
                    text: root.currentIcon
                    size: 30
                    color: root.currentAccentColor
                }
            }

            // Title
            Text {
                id: titleText
                Layout.fillWidth: true
                text: root.currentTitle
                font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
                font.pixelSize: (typeof Theme !== "undefined" && Theme.fontTitleLarge) ? Theme.fontTitleLarge : 26
                font.weight: Font.Bold
                color: (typeof Colors !== "undefined" && Colors.textMain) ? Colors.textMain : "#1D1B20"
                horizontalAlignment: Text.AlignHCenter
            }

            // Message
            Text {
                id: messageText
                Layout.fillWidth: true
                text: root.currentMessage
                font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
                font.pixelSize: (typeof Theme !== "undefined" && Theme.fontBodyMedium) ? Theme.fontBodyMedium : 15
                color: (typeof Colors !== "undefined" && Colors.onSurfaceVariant) ? Colors.onSurfaceVariant : "#49454F"
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                lineHeight: 1.25
            }

            Item {
                Layout.preferredHeight: 6
            }

            // Action Buttons
            RowLayout {
                Layout.fillWidth: true
                spacing: (typeof Theme !== "undefined" && Theme.spaceMedium) ? Theme.spaceMedium : 12

                // Cancel Button
                Rectangle {
                    id: cancelBtn
                    Layout.fillWidth: true
                    Layout.preferredHeight: 44
                    radius: (typeof Theme !== "undefined" && Theme.radiusFull) ? Theme.radiusFull : 9999
                    color: cancelHover.hovered 
                        ? ((typeof Colors !== "undefined" && Colors.surfaceContainerHigh) ? Colors.surfaceContainerHigh : "#E8E2DA")
                        : ((typeof Colors !== "undefined" && Colors.surfaceContainer) ? Colors.surfaceContainer : "#F2EDE7")
                    border.width: 1
                    border.color: (typeof Colors !== "undefined" && Colors.outlineVariant) ? Colors.outlineVariant : "#E8E2DA"

                    Behavior on color { ColorAnimation { duration: (typeof Theme !== "undefined" && Theme.animDurationFast) ? Theme.animDurationFast : 150 } }

                    Text {
                        anchors.centerIn: parent
                        text: "Cancel"
                        font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
                        font.pixelSize: (typeof Theme !== "undefined" && Theme.fontBodyMedium) ? Theme.fontBodyMedium : 15
                        font.weight: Font.Medium
                        color: (typeof Colors !== "undefined" && Colors.textMain) ? Colors.textMain : "#1D1B20"
                    }

                    HoverHandler {
                        id: cancelHover
                        cursorShape: Qt.PointingHandCursor
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.cancelAction()
                    }
                }

                // Confirm Action Button
                Rectangle {
                    id: confirmBtn
                    Layout.fillWidth: true
                    Layout.preferredHeight: 44
                    radius: (typeof Theme !== "undefined" && Theme.radiusFull) ? Theme.radiusFull : 9999
                    color: confirmHover.hovered 
                        ? Qt.darker(root.currentAccentColor, 1.12)
                        : root.currentAccentColor

                    Behavior on color { ColorAnimation { duration: (typeof Theme !== "undefined" && Theme.animDurationFast) ? Theme.animDurationFast : 150 } }

                    Text {
                        anchors.centerIn: parent
                        text: root.currentConfirmLabel
                        font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
                        font.pixelSize: (typeof Theme !== "undefined" && Theme.fontBodyMedium) ? Theme.fontBodyMedium : 15
                        font.weight: Font.DemiBold
                        color: (typeof Colors !== "undefined" && Colors.textOnPrimary) ? Colors.textOnPrimary : "#FFFFFF"
                    }

                    HoverHandler {
                        id: confirmHover
                        cursorShape: Qt.PointingHandCursor
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.confirmAction()
                    }
                }
            }
        }
    }
}
