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
    property bool showShadow: true
    property real elevation: 6
    property bool interactive: false
    property bool hovered: false
    property bool pressed: false
    property bool selected: false
    property int padding: 0
    // A full 1px perimeter ring suits interactive/elevated cards, but on a resting
    // container it reads as a stray box drawn inside the panel. Callers can drop
    // the ring and keep the specular hairlines, which is what actually defines a
    // glass edge (see docs/LESSONS.md 9.1 "Clean Glass Materials").
    property bool showBorder: true
    // Bare mode: no fill, shadow, caustic, refraction, specular or rim. For
    // containers that only need the interaction/scroll plumbing (the dock's
    // system-tray group), not another panel of glass.
    property bool bare: false

    // Component exposure aliases for testing & introspection
    readonly property alias topGlareItem: topGlare
    readonly property alias subGlareItem: subGlare
    readonly property alias bottomRimItem: bottomRim
    readonly property alias shadowItem: ambientShadow
    readonly property alias causticItem: causticGlow

    // Standard geometry and styling
    radius: (typeof Theme !== "undefined" && Theme.radiusGlassCard) ? Theme.radiusGlassCard : 16
    border.width: root.showBorder && !root.bare ? (selected ? 1.5 : 1) : 0
    border.color: selected 
        ? ((typeof Colors !== "undefined" && Colors.primary) ? Colors.primary : "#9bcbfb")
        : (hovered 
            ? ((typeof Colors !== "undefined" && Colors.glassBorderSpecular) ? Colors.glassBorderSpecular : Qt.rgba(1, 1, 1, 0.70))
            : ((typeof Colors !== "undefined" && Colors.glassBorderSpecular) ? Qt.alpha(Colors.glassBorderSpecular, Colors.isDarkMode ? 0.45 : 0.60) : Qt.rgba(1, 1, 1, 0.25)))

    // Base liquid glass substrate tint (crystalline translucent glass plate matching Colors.glassCard, letting background content shine through)
    color: root.bare ? "transparent"
        : ((typeof Colors !== "undefined" && Colors.glassCard)
            ? (root.selected ? Colors.glassCardActive : (root.hovered ? Colors.glassCardHover : Colors.glassCard))
            : ((typeof Colors !== "undefined" && Colors.isDarkMode)
                ? Qt.rgba(1.0, 1.0, 1.0, root.selected ? 0.16 : (root.hovered ? 0.10 : 0.06))
                : Qt.rgba(1.0, 1.0, 1.0, root.selected ? 0.60 : (root.hovered ? 0.50 : 0.40))))

    Behavior on color { ColorAnimation { duration: (typeof Theme !== "undefined") ? Theme.animExpressiveFastEffects : 150 } }
    Behavior on border.color { ColorAnimation { duration: (typeof Theme !== "undefined") ? Theme.animExpressiveFastEffects : 150 } }

    // 0. Ambient Contact Drop Shadow (Provides authentic elevation & floating depth)
    Rectangle {
        id: ambientShadow
        visible: root.showShadow && !root.bare
        z: -1
        anchors.fill: parent
        anchors.topMargin: Math.max(1, Math.round(root.elevation * 0.35))
        anchors.bottomMargin: -Math.max(2, Math.round(root.elevation * 0.45))
        anchors.leftMargin: -Math.max(1, Math.round(root.elevation * 0.12))
        anchors.rightMargin: -Math.max(1, Math.round(root.elevation * 0.12))
        radius: root.radius
        color: "transparent"
        border.color: (typeof Colors !== "undefined" && Colors.isDarkMode)
            ? Qt.rgba(0.0, 0.0, 0.0, 0.15)
            : Qt.rgba(0.0, 0.0, 0.0, 0.08)
        border.width: Math.max(1, Math.round(root.elevation * 0.25))
        opacity: (typeof Colors !== "undefined" && Colors.isDarkMode) ? 0.20 : 0.12
    }

    // 1. Refractive Glass Gradient (Optical Depth: light gathering at top, crystalline depth at bottom)
    Rectangle {
        id: refractionGradient
        visible: root.showRefraction && !root.bare
        anchors.fill: parent
        radius: parent.radius
        color: "transparent"

        gradient: Gradient {
            GradientStop {
                position: 0.0
                color: (typeof Colors !== "undefined" && Colors.isDarkMode)
                    ? Qt.tint(Qt.rgba(1.0, 1.0, 1.0, 0.08), Qt.alpha(root.accentGlint, 0.06))
                    : Qt.tint(Qt.rgba(1.0, 1.0, 1.0, 0.35), Qt.alpha(root.accentGlint, 0.06))
            }
            GradientStop {
                position: 0.40
                color: "transparent"
            }
            GradientStop {
                position: 0.85
                color: "transparent"
            }
            GradientStop {
                position: 1.0
                color: (typeof Colors !== "undefined" && Colors.isDarkMode)
                    ? Qt.tint(Qt.rgba(1.0, 1.0, 1.0, 0.04), Qt.alpha(root.accentGlint, 0.06))
                    : Qt.rgba(1.0, 1.0, 1.0, 0.15)
            }
        }
    }

    // 2. Inner Caustic Ambient Glow (Simulates ambient light diffusing into top edge)
    Rectangle {
        id: causticGlow
        visible: root.showCaustic && !root.bare && parent.height > 20
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: 1
        height: Math.min(parent.height * 0.38, 32)
        radius: Math.max(0, parent.radius - 1)
        color: "transparent"

        gradient: Gradient {
            GradientStop {
                position: 0.0
                color: (typeof Colors !== "undefined" && Colors.isDarkMode)
                    ? Qt.alpha(root.accentGlint, root.hovered ? 0.24 : 0.18)
                    : Qt.alpha(root.accentGlint, root.hovered ? 0.16 : 0.12)
            }
            GradientStop {
                position: 1.0
                color: "transparent"
            }
        }
    }

    // 3. Dual-Layer Top Specular Hairline Glare (Horizontal light catch along flat top edge)
    // NOTE: Must only be visible when parent has a flat top edge (parent.width > parent.radius * 2 + 8).
    // leftMargin and rightMargin must be >= radius to prevent detached overhanging line artifacts on curved shoulders/pills!
    Rectangle {
        id: topGlare
        visible: root.showSpecular && !root.bare && (parent.width > (parent.radius * 2 + 8))
        anchors.top: parent.top
        anchors.topMargin: 0.5
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Math.max(parent.radius + 2, 12)
        anchors.rightMargin: Math.max(parent.radius + 2, 12)
        height: 1
        opacity: root.hovered ? 1.0 : ((typeof Colors !== "undefined" && Colors.isDarkMode) ? 0.78 : 0.90)

        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop {
                position: 0.20
                color: Qt.alpha(root.specularColor, 0.60)
            }
            GradientStop {
                position: 0.50
                color: (typeof Colors !== "undefined" && Colors.glassBorderSpecular) ? Colors.glassBorderSpecular : "#FFFFFF"
            }
            GradientStop {
                position: 0.80
                color: Qt.alpha(root.specularColor, 0.60)
            }
            GradientStop { position: 1.0; color: "transparent" }
        }
    }

    // 3b. Secondary Inner Refraction Hairline (Simulates physical glass edge thickness)
    Rectangle {
        id: subGlare
        visible: root.showSpecular && !root.bare && (parent.width > (parent.radius * 2 + 16))
        anchors.top: parent.top
        anchors.topMargin: 1.5
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Math.max(parent.radius + 4, 16)
        anchors.rightMargin: Math.max(parent.radius + 4, 16)
        height: 0.5
        opacity: root.hovered ? 0.65 : ((typeof Colors !== "undefined" && Colors.isDarkMode) ? 0.35 : 0.50)

        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 0.5; color: Qt.alpha(root.accentGlint, 0.45) }
            GradientStop { position: 1.0; color: "transparent" }
        }
    }

    // 4. Bottom Inner Rim Reflection (Subtle reflection on the bottom edge)
    Rectangle {
        id: bottomRim
        visible: root.showBottomRim && !root.bare && (parent.width > (parent.radius * 2 + 8))
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 0.5
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Math.max(parent.radius + 2, 12)
        anchors.rightMargin: Math.max(parent.radius + 2, 12)
        height: 1
        opacity: (typeof Colors !== "undefined" && Colors.isDarkMode) ? 0.25 : 0.40

        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop {
                position: 0.50
                color: (typeof Colors !== "undefined" && Colors.isDarkMode)
                    ? Qt.tint(Qt.rgba(1.0, 1.0, 1.0, 0.28), Qt.alpha(root.accentGlint, 0.16))
                    : Qt.rgba(1.0, 1.0, 1.0, 0.45)
            }
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
            ? Qt.alpha(root.accentGlint, 0.14)
            : (root.hovered ? Qt.rgba(1.0, 1.0, 1.0, 0.08) : "transparent")
        Behavior on color { ColorAnimation { duration: 150 } }
    }
}
