import QtQuick
import "../theme"

Item {
    id: root

    property string source: ""
    property string materialIcon: ""
    property color color: Colors.textOnSurface
    property int size: 18
    property bool forceColorize: false

    // Public contract kept for callers/tests: symbolic when asked, or when the
    // source follows the `-symbolic` convention.
    readonly property bool isSymbolic: iconImage.isSymbolic

    implicitWidth: size
    implicitHeight: size
    width: size
    height: size

    // 1+2. The shared archetype renderer (full-colour or tinted symbolic).
    ThemedImage {
        id: iconImage
        anchors.fill: parent
        source: root.source
        color: root.color
        size: root.size
        forceColorize: root.forceColorize
    }

    // 3. Fallback MaterialIcon.
    MaterialIcon {
        id: fallbackIcon
        anchors.centerIn: parent
        text: root.materialIcon
        size: root.size
        color: root.color
        visible: (root.materialIcon !== "") && !iconImage.hasIcon
    }
}
