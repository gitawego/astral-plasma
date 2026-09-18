import QtQuick
import "../theme"

Rectangle {
    id: root

    // Customization tokens
    property color accentGlint: (typeof Colors !== "undefined" && Colors.primary) ? Colors.primary : "#9bcbfb"
    property color specularColor: (typeof Colors !== "undefined" && Colors.glassBorderSpecular) ? Colors.glassBorderSpecular : Qt.rgba(1, 1, 1, 0.6)
    property bool showSpecular: true
    property bool showCaustic: true
    property bool showBottomRim: true
    property bool showRefraction: true
    property bool interactive: false
    property bool hovered: false
    property bool pressed: false
    property bool selected: false
    property int padding: 0

    // Standard geometry and styling
    radius: (typeof Theme !== "undefined" && Theme.radiusGlassCard) ? Theme.radiusGlassCard : 16
    border.width: selected ? 1.5 : 1
    border.color: selected 
        ? ((typeof Colors !== "undefined" && Colors.primary) ? Colors.primary : "#9bcbfb")
        : (hovered ? specularColor : ((typeof Colors !== "undefined" && Colors.glassBorderSubtle) ? Colors.glassBorderSubtle : Qt.rgba(1, 1, 1, 0.12)))

    // Base liquid glass substrate tint (deep dark smoked glass in dark mode, crisp luminous in light mode)
    color: (typeof Colors !== "undefined" && Colors.isDarkMode)
        ? Qt.tint(Qt.rgba(0.04, 0.05, 0.08, 0.30), Qt.alpha(root.accentGlint, 0.05))
        : Qt.tint(Qt.rgba(1.0, 1.0, 1.0, 0.50), Qt.alpha(root.accentGlint, 0.08))

    Behavior on color { ColorAnimation { duration: (typeof Theme !== "undefined") ? Theme.animExpressiveFastEffects : 150 } }
    Behavior on border.color { ColorAnimation { duration: (typeof Theme !== "undefined") ? Theme.animExpressiveFastEffects : 150 } }

    // 1. Refractive Glass Gradient (Optical Depth: light gathering at top, crystalline depth at bottom)
    Rectangle {
        id: refractionGradient
        visible: root.showRefraction
        anchors.fill: parent
        radius: parent.radius
        color: "transparent"

        gradient: Gradient {
            GradientStop {
                position: 0.0
                color: (typeof Colors !== "undefined" && Colors.isDarkMode)
                    ? Qt.tint(Qt.rgba(1.0, 1.0, 1.0, 0.08), Qt.alpha(root.accentGlint, 0.06))
                    : Qt.tint(Qt.rgba(1.0, 1.0, 1.0, 0.55), Qt.alpha(root.accentGlint, 0.06))
            }
            GradientStop {
                position: 0.40
                color: (typeof Colors !== "undefined" && Colors.isDarkMode)
                    ? Qt.tint(Qt.rgba(1.0, 1.0, 1.0, 0.02), Qt.alpha(root.accentGlint, 0.02))
                    : Qt.tint(Qt.rgba(1.0, 1.0, 1.0, 0.30), Qt.alpha(root.accentGlint, 0.04))
            }
            GradientStop {
                position: 1.0
                color: (typeof Colors !== "undefined" && Colors.isDarkMode)
                    ? Qt.rgba(0.0, 0.0, 0.0, 0.15)
                    : Qt.rgba(1.0, 1.0, 1.0, 0.20)
            }
        }
    }

    // 2. Inner Caustic Ambient Glow (Simulates ambient light diffusing into top edge)
    Rectangle {
        id: causticGlow
        visible: root.showCaustic && parent.height > 20
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: 1
        height: Math.min(parent.height * 0.35, 28)
        radius: Math.max(0, parent.radius - 1)
        color: "transparent"

        gradient: Gradient {
            GradientStop {
                position: 0.0
                color: (typeof Colors !== "undefined" && Colors.isDarkMode)
                    ? Qt.alpha(root.accentGlint, 0.14)
                    : Qt.alpha(root.accentGlint, 0.09)
            }
            GradientStop {
                position: 1.0
                color: "transparent"
            }
        }
    }

    // 3. Top Specular Hairline Glare (Horizontal light catch along the top curved bevel)
    Rectangle {
        id: topGlare
        visible: root.showSpecular && parent.width > 24
        anchors.top: parent.top
        anchors.topMargin: 0.5
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Math.max(8, Math.min(parent.radius * 0.45, 28))
        anchors.rightMargin: Math.max(8, Math.min(parent.radius * 0.45, 28))
        height: 1
        opacity: root.hovered ? 1.0 : ((typeof Colors !== "undefined" && Colors.isDarkMode) ? 0.70 : 0.85)

        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop {
                position: 0.15
                color: Qt.alpha(root.specularColor, 0.45)
            }
            GradientStop {
                position: 0.50
                color: root.specularColor
            }
            GradientStop {
                position: 0.85
                color: Qt.alpha(root.specularColor, 0.45)
            }
            GradientStop { position: 1.0; color: "transparent" }
        }
    }

    // 4. Bottom Inner Rim Reflection (Subtle reflection on the bottom edge)
    Rectangle {
        id: bottomRim
        visible: root.showBottomRim && parent.width > 24
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 0.5
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Math.max(10, Math.min(parent.radius * 0.55, 32))
        anchors.rightMargin: Math.max(10, Math.min(parent.radius * 0.55, 32))
        height: 1
        opacity: (typeof Colors !== "undefined" && Colors.isDarkMode) ? 0.20 : 0.35

        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 0.50; color: Qt.rgba(1.0, 1.0, 1.0, 0.30) }
            GradientStop { position: 1.0; color: "transparent" }
        }
    }

    // 5. Interactive Luminous Feedback
    Rectangle {
        id: interactiveWash
        visible: root.interactive && (root.hovered || root.selected)
        anchors.fill: parent
        radius: parent.radius
        color: root.selected
            ? Qt.alpha(root.accentGlint, 0.12)
            : (root.hovered ? Qt.rgba(1.0, 1.0, 1.0, 0.06) : "transparent")
        Behavior on color { ColorAnimation { duration: 150 } }
    }
}
