import QtQuick
import Qt5Compat.GraphicalEffects
import "../theme"

Item {
    id: root

    property string source: ""
    property string materialIcon: ""
    property color color: Colors.textOnSurface
    property int size: 18
    property bool forceColorize: false

    // Generically detect if the icon is symbolic/monochrome action icon
    readonly property bool isSymbolic: {
        if (forceColorize) return true;
        if (!source) return false;
        const s = source.toLowerCase();
        return s.indexOf("-symbolic") !== -1 || 
               s.indexOf(".symbolic") !== -1 || 
               s.indexOf("/symbolic/") !== -1 || 
               s.indexOf("/actions/") !== -1 || 
               s.indexOf("/status/") !== -1 ||
               s.indexOf("symbolic") !== -1;
    }

    implicitWidth: size
    implicitHeight: size
    width: size
    height: size

    // 1. Regular Full-Color App/Asset Icon (when not symbolic)
    Image {
        id: rawIconImg
        anchors.fill: parent
        source: root.source
        fillMode: Image.PreserveAspectFit
        visible: (!root.isSymbolic) && (root.source !== "") && (status === Image.Ready)
    }

    // 2. Tinted Symbolic / Monochrome Action Icon (ColorOverlay for high contrast)
    Item {
        id: overlayContainer
        anchors.fill: parent
        visible: root.isSymbolic && (root.source !== "") && (symbolicSourceImg.status === Image.Ready)

        Image {
            id: symbolicSourceImg
            anchors.fill: parent
            source: root.source
            fillMode: Image.PreserveAspectFit
            visible: false
        }

        ColorOverlay {
            anchors.fill: symbolicSourceImg
            source: symbolicSourceImg
            color: root.color
        }
    }

    // 3. Fallback MaterialIcon
    MaterialIcon {
        id: fallbackIcon
        anchors.centerIn: parent
        text: root.materialIcon
        size: root.size
        color: root.color
        visible: (root.materialIcon !== "") && (!rawIconImg.visible) && (!overlayContainer.visible)
    }
}
