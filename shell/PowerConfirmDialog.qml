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

    readonly property color confirmTextColor: {
        const bg = root.currentAccentColor;
        const lum = 0.299 * bg.r + 0.587 * bg.g + 0.114 * bg.b;
        return lum > 0.65 ? "#1D1B20" : "#FFFFFF";
    }

    // Exported Card Geometry for Compositor Blur Region Integration
    readonly property real cardX: dialogCard.x
    readonly property real cardY: dialogCard.y
    readonly property real cardW: dialogCard.width
    readonly property real cardH: dialogCard.height

    // Component Exposure Aliases for Testing & Introspection
    readonly property alias dialogCardItem: dialogCard
    readonly property alias cancelButtonItem: cancelBtn
    readonly property alias confirmButtonItem: confirmBtn
    readonly property alias headerBadgeItem: headerBadge
    readonly property alias titleTextItem: titleText
    readonly property alias messageTextItem: messageText
    readonly property alias topGlareItem: topGlare
    readonly property alias causticGlowItem: causticGlow
    readonly property alias bottomRimItem: bottomRim
    readonly property alias refractionGradientItem: refractionGradient
    readonly property alias cursorGlintItem: cursorGlint

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
            duration: (typeof Theme !== "undefined" && Theme.animExpressiveFastEffects) ? Theme.animExpressiveFastEffects : 180
            easing.type: Easing.BezierSpline
            easing.bezierCurve: (typeof Theme !== "undefined" && Theme.curveExpressiveFastEffects) ? Theme.curveExpressiveFastEffects : [0.31, 0.94, 0.34, 1.0, 1.0, 1.0]
        }
    }

    onIsDialogVisibleChanged: {
        if (root.isDialogVisible) {
            dialogCard.forceActiveFocus();
        }
    }

    // =========================================================================
    // 1. FULLSCREEN FROSTED SCRIM BACKDROP
    // =========================================================================
    Rectangle {
        id: scrim
        anchors.fill: parent
        color: (typeof Colors !== "undefined" && Colors.isDarkMode)
            ? Qt.rgba(0.04, 0.03, 0.06, 0.58)
            : Qt.rgba(0.12, 0.12, 0.14, 0.38)

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.ArrowCursor
            onClicked: root.cancelAction()
        }
    }

    // =========================================================================
    // 2. MODAL LIQUID GLASS DIALOG CARD
    // =========================================================================
    Rectangle {
        id: dialogCard
        anchors.centerIn: parent
        width: 440
        height: cardLayout.implicitHeight + 52
        implicitHeight: height
        radius: (typeof Theme !== "undefined" && Theme.radiusGlassModal) ? Theme.radiusGlassModal : 28

        // Liquid Glass Base Translucent Substrate Fill
        color: (typeof Colors !== "undefined" && Colors.glassModalSurface)
            ? Colors.glassModalSurface
            : ((typeof Colors !== "undefined" && Colors.isDarkMode)
                ? Qt.rgba(0.10, 0.09, 0.14, 0.72)
                : Qt.rgba(0.96, 0.95, 0.98, 0.82))

        border.width: 1
        border.color: (typeof Colors !== "undefined" && Colors.glassBorderSpecular)
            ? Qt.alpha(Colors.glassBorderSpecular, Colors.isDarkMode ? 0.40 : 0.65)
            : Qt.rgba(1.0, 1.0, 1.0, 0.35)

        scale: root.isDialogVisible ? 1.0 : 0.92
        Behavior on scale {
            NumberAnimation {
                duration: (typeof Theme !== "undefined" && Theme.animExpressiveDefaultSpatial) ? Theme.animExpressiveDefaultSpatial : 450
                easing.type: Easing.BezierSpline
                easing.bezierCurve: (typeof Theme !== "undefined" && Theme.curveExpressiveDefaultSpatial) ? Theme.curveExpressiveDefaultSpatial : [0.38, 1.21, 0.22, 1.0, 1.0, 1.0]
            }
        }

        // Layer 0: Ambient Contact Drop Shadow (Physical surface elevation)
        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            blurMax: 48
            shadowBlur: 0.90
            shadowVerticalOffset: 12
            shadowColor: (typeof Colors !== "undefined" && Colors.glassShadowColor) ? Colors.glassShadowColor : Qt.rgba(0, 0, 0, 0.45)
        }

        // Layer 1: Refractive Glass Substrate Gradient
        Rectangle {
            id: refractionGradient
            anchors.fill: parent
            radius: parent.radius
            color: "transparent"

            gradient: Gradient {
                GradientStop {
                    position: 0.0
                    color: (typeof Colors !== "undefined" && Colors.isDarkMode)
                        ? Qt.tint(Qt.rgba(1.0, 1.0, 1.0, 0.09), Qt.alpha(root.currentAccentColor, 0.06))
                        : Qt.tint(Qt.rgba(1.0, 1.0, 1.0, 0.35), Qt.alpha(root.currentAccentColor, 0.06))
                }
                GradientStop {
                    position: 0.45
                    color: "transparent"
                }
                GradientStop {
                    position: 1.0
                    color: (typeof Colors !== "undefined" && Colors.isDarkMode)
                        ? Qt.rgba(0.0, 0.0, 0.0, 0.18)
                        : Qt.rgba(1.0, 1.0, 1.0, 0.12)
                }
            }
        }

        // Layer 2: Inner Caustic Ambient Glow (Top edge refraction)
        Rectangle {
            id: causticGlow
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 38
            radius: parent.radius
            color: "transparent"

            gradient: Gradient {
                GradientStop {
                    position: 0.0
                    color: Qt.alpha(root.currentAccentColor, (typeof Colors !== "undefined" && Colors.isDarkMode) ? 0.22 : 0.15)
                }
                GradientStop {
                    position: 1.0
                    color: "transparent"
                }
            }
        }

        // Layer 3: Dual-Layer Top Specular Hairline Glare
        Rectangle {
            id: topGlare
            anchors.top: parent.top
            anchors.topMargin: 0.5
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: Math.max(parent.radius + 2, 28)
            anchors.rightMargin: Math.max(parent.radius + 2, 28)
            height: 1
            opacity: (typeof Colors !== "undefined" && Colors.isDarkMode) ? 0.85 : 0.95

            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop {
                    position: 0.20
                    color: (typeof Colors !== "undefined" && Colors.glassBorderSpecular) ? Qt.alpha(Colors.glassBorderSpecular, 0.60) : Qt.rgba(1.0, 1.0, 1.0, 0.40)
                }
                GradientStop {
                    position: 0.50
                    color: (typeof Colors !== "undefined" && Colors.glassBorderSpecular) ? Colors.glassBorderSpecular : "#FFFFFF"
                }
                GradientStop {
                    position: 0.80
                    color: (typeof Colors !== "undefined" && Colors.glassBorderSpecular) ? Qt.alpha(Colors.glassBorderSpecular, 0.60) : Qt.rgba(1.0, 1.0, 1.0, 0.40)
                }
                GradientStop { position: 1.0; color: "transparent" }
            }
        }

        // Layer 4: Bottom Inner Rim Catch
        Rectangle {
            id: bottomRim
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 0.5
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: Math.max(parent.radius, 28)
            anchors.rightMargin: Math.max(parent.radius, 28)
            height: 1
            opacity: (typeof Colors !== "undefined" && Colors.isDarkMode) ? 0.22 : 0.35
            color: Qt.rgba(1.0, 1.0, 1.0, 0.30)
        }

        // Dynamic Specular Cursor Glint (Follows pointer across glass surface)
        property real cursorX: -1
        property real cursorY: -1
        property bool isHovered: false

        Rectangle {
            id: cursorGlint
            visible: dialogCard.cursorX >= 0 && dialogCard.cursorY >= 0
            x: dialogCard.cursorX - width / 2
            y: dialogCard.cursorY - height / 2
            width: 220
            height: 220
            radius: width / 2
            color: (typeof Colors !== "undefined" && Colors.isDarkMode) ? "#FFFFFF" : root.currentAccentColor
            opacity: dialogCard.isHovered ? ((typeof Colors !== "undefined" && Colors.isDarkMode) ? 0.05 : 0.08) : 0.0

            Behavior on opacity {
                NumberAnimation { duration: 150 }
            }

            layer.enabled: true
            layer.effect: MultiEffect {
                blurEnabled: true
                blur: 1.0
                blurMax: 48
            }
        }

        // Cursor tracking and event absorption inside dialogCard
        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onPositionChanged: (mouse) => {
                dialogCard.cursorX = mouse.x;
                dialogCard.cursorY = mouse.y;
            }
            onEntered: dialogCard.isHovered = true
            onExited: {
                dialogCard.isHovered = false;
                dialogCard.cursorX = -1;
                dialogCard.cursorY = -1;
            }
            onClicked: {} // Catch clicks to prevent dismissing scrim
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

            // Header Icon Badge (Liquid Glass Sculpted Capsule)
            Rectangle {
                id: headerBadge
                Layout.alignment: Qt.AlignHCenter
                width: 64
                height: 64
                radius: 32
                color: Qt.alpha(root.currentAccentColor, (typeof Colors !== "undefined" && Colors.isDarkMode) ? 0.16 : 0.12)
                border.width: 1
                border.color: Qt.alpha(root.currentAccentColor, 0.40)

                // Top specular glint on badge
                Rectangle {
                    anchors.top: parent.top
                    anchors.topMargin: 0.5
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 28
                    height: 1
                    color: Qt.alpha("#FFFFFF", 0.50)
                }

                MaterialIcon {
                    anchors.centerIn: parent
                    text: root.currentIcon
                    size: 32
                    color: root.currentAccentColor
                }
            }

            // Title Typography
            Text {
                id: titleText
                Layout.fillWidth: true
                text: root.currentTitle
                font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
                font.pixelSize: (typeof Theme !== "undefined" && Theme.fontHeadlineMedium) ? Theme.fontHeadlineMedium : 24
                font.weight: Font.Bold
                color: (typeof Colors !== "undefined" && Colors.textMain) ? Colors.textMain : "#FFFFFF"
                horizontalAlignment: Text.AlignHCenter
            }

            // Message Body Typography
            Text {
                id: messageText
                Layout.fillWidth: true
                text: root.currentMessage
                font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
                font.pixelSize: (typeof Theme !== "undefined" && Theme.fontBodyMedium) ? Theme.fontBodyMedium : 15
                color: (typeof Colors !== "undefined" && Colors.onSurfaceVariant) ? Colors.onSurfaceVariant : "#CAC4D0"
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                lineHeight: 1.3
            }

            Item {
                Layout.preferredHeight: 8
            }

            // =================================================================
            // 3. LIQUID GLASS ACTION BUTTONS
            // =================================================================
            RowLayout {
                Layout.fillWidth: true
                spacing: (typeof Theme !== "undefined" && Theme.spaceMedium) ? Theme.spaceMedium : 14

                // Cancel Button (Crystalline Secondary Glass Pill)
                Rectangle {
                    id: cancelBtn
                    Layout.fillWidth: true
                    Layout.preferredHeight: 44
                    radius: (typeof Theme !== "undefined" && Theme.radiusFull) ? Theme.radiusFull : 22

                    // Translucent glass fill with hover / press responses
                    color: cancelMouse.containsPress
                        ? ((typeof Colors !== "undefined" && Colors.isDarkMode) ? Qt.rgba(1.0, 1.0, 1.0, 0.16) : Qt.rgba(1.0, 1.0, 1.0, 0.65))
                        : (cancelMouse.containsMouse
                            ? ((typeof Colors !== "undefined" && Colors.isDarkMode) ? Qt.rgba(1.0, 1.0, 1.0, 0.11) : Qt.rgba(1.0, 1.0, 1.0, 0.52))
                            : ((typeof Colors !== "undefined" && Colors.isDarkMode) ? Qt.rgba(1.0, 1.0, 1.0, 0.06) : Qt.rgba(1.0, 1.0, 1.0, 0.38)))

                    border.width: 1
                    border.color: cancelMouse.containsMouse
                        ? ((typeof Colors !== "undefined" && Colors.glassBorderSpecular) ? Colors.glassBorderSpecular : Qt.rgba(1.0, 1.0, 1.0, 0.70))
                        : ((typeof Colors !== "undefined" && Colors.glassBorderSubtle) ? Colors.glassBorderSubtle : Qt.rgba(1.0, 1.0, 1.0, 0.15))

                    // Tactile Spring Micro-Physics
                    scale: cancelMouse.containsPress ? 0.95 : (cancelMouse.containsMouse ? 1.02 : 1.0)
                    Behavior on scale {
                        NumberAnimation {
                            duration: cancelMouse.containsPress ? 100 : 200
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: (typeof Theme !== "undefined" && Theme.curveGlassElastic) ? Theme.curveGlassElastic : [0.34, 1.56, 0.64, 1]
                        }
                    }
                    Behavior on color { ColorAnimation { duration: 150 } }
                    Behavior on border.color { ColorAnimation { duration: 150 } }

                    // Ambient contact drop shadow
                    Rectangle {
                        z: -1
                        anchors.fill: parent
                        anchors.topMargin: 2
                        anchors.bottomMargin: -2
                        radius: parent.radius
                        color: "transparent"
                        border.width: 1.5
                        border.color: (typeof Colors !== "undefined" && Colors.isDarkMode) ? Qt.rgba(0, 0, 0, 0.25) : Qt.rgba(0, 0, 0, 0.08)
                        opacity: 0.30
                    }

                    // Top Specular Hairline
                    Rectangle {
                        anchors.top: parent.top
                        anchors.topMargin: 0.5
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: parent.radius
                        anchors.rightMargin: parent.radius
                        height: 1
                        opacity: cancelMouse.containsMouse ? 0.80 : 0.50
                        color: Qt.rgba(1.0, 1.0, 1.0, 0.50)
                    }

                    Text {
                        anchors.centerIn: parent
                        text: "Cancel"
                        font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
                        font.pixelSize: (typeof Theme !== "undefined" && Theme.fontBodyMedium) ? Theme.fontBodyMedium : 15
                        font.weight: Font.Medium
                        color: (typeof Colors !== "undefined" && Colors.textMain) ? Colors.textMain : "#FFFFFF"
                    }

                    MouseArea {
                        id: cancelMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.cancelAction()
                    }
                }

                // Confirm Action Button (Prominent Semantic Liquid Glass Pill)
                Rectangle {
                    id: confirmBtn
                    Layout.fillWidth: true
                    Layout.preferredHeight: 44
                    radius: (typeof Theme !== "undefined" && Theme.radiusFull) ? Theme.radiusFull : 22

                    // Semantic Accent Fill with interactive depth
                    color: confirmMouse.containsPress
                        ? Qt.darker(root.currentAccentColor, 1.18)
                        : (confirmMouse.containsMouse
                            ? Qt.lighter(root.currentAccentColor, 1.10)
                            : root.currentAccentColor)

                    border.width: 1
                    border.color: confirmMouse.containsMouse
                        ? Qt.alpha("#FFFFFF", 0.70)
                        : Qt.alpha("#FFFFFF", 0.35)

                    // Tactile Spring Micro-Physics
                    scale: confirmMouse.containsPress ? 0.95 : (confirmMouse.containsMouse ? 1.02 : 1.0)
                    Behavior on scale {
                        NumberAnimation {
                            duration: confirmMouse.containsPress ? 100 : 200
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: (typeof Theme !== "undefined" && Theme.curveGlassElastic) ? Theme.curveGlassElastic : [0.34, 1.56, 0.64, 1]
                        }
                    }
                    Behavior on color { ColorAnimation { duration: 150 } }
                    Behavior on border.color { ColorAnimation { duration: 150 } }

                    // Ambient Accent Contact Drop Shadow
                    Rectangle {
                        z: -1
                        anchors.fill: parent
                        anchors.topMargin: 2
                        anchors.bottomMargin: -3
                        radius: parent.radius
                        color: "transparent"
                        border.width: 2
                        border.color: Qt.alpha(root.currentAccentColor, 0.40)
                        opacity: 0.50
                    }

                    // Top Specular Hairline Glint
                    Rectangle {
                        anchors.top: parent.top
                        anchors.topMargin: 0.5
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: parent.radius
                        anchors.rightMargin: parent.radius
                        height: 1
                        opacity: 0.85
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: "transparent" }
                            GradientStop { position: 0.5; color: Qt.alpha("#FFFFFF", 0.90) }
                            GradientStop { position: 1.0; color: "transparent" }
                        }
                    }

                    RowLayout {
                        anchors.centerIn: parent
                        spacing: (typeof Theme !== "undefined" && Theme.spaceSmall) ? Theme.spaceSmall : 8

                        MaterialIcon {
                            text: root.currentIcon
                            size: 18
                            color: root.confirmTextColor
                        }

                        Text {
                            text: root.currentConfirmLabel
                            font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
                            font.pixelSize: (typeof Theme !== "undefined" && Theme.fontBodyMedium) ? Theme.fontBodyMedium : 15
                            font.weight: Font.DemiBold
                            color: root.confirmTextColor
                        }
                    }

                    MouseArea {
                        id: confirmMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.confirmAction()
                    }
                }
            }
        }
    }
}
