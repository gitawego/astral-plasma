import QtQuick
import "../theme"

LiquidGlassCard {
    id: root

    property alias content: root.children
    padding: (typeof Theme !== "undefined" && Theme.padMedium) ? Theme.padMedium : 12
}
