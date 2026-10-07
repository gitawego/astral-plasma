import QtQuick
import Qt5Compat.GraphicalEffects
import "../theme"

// The single icon-archetype renderer: full-colour art is drawn as-is, symbolic
// art is tinted with `color`. Every icon surface (dock, popouts, settings,
// launcher, AI tabs) goes through this, so a mark never keeps a hard-coded
// brand colour on one surface while following the theme on another.
Item {
    id: root

    property string source: ""
    property color color: Colors.textOnSurface
    property int size: 18
    property bool forceColorize: false

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

    /// True while one of the two archetype branches is actually painting.
    readonly property bool hasIcon: rawIconImg.visible || overlayContainer.visible

    implicitWidth: size
    implicitHeight: size
    width: size
    height: size

    // 1. Regular full-colour app/asset icon.
    Image {
        id: rawIconImg
        anchors.fill: parent
        source: root.source
        sourceSize.width: root.size
        sourceSize.height: root.size
        fillMode: Image.PreserveAspectFit
        smooth: true
        visible: (!root.isSymbolic) && (root.source !== "") && (status === Image.Ready)
    }

    // 2. Tinted symbolic/monochrome action icon (ColorOverlay for contrast).
    Item {
        id: overlayContainer
        anchors.fill: parent
        visible: root.isSymbolic && (root.source !== "") && (symbolicSourceImg.status === Image.Ready)

        Image {
            id: symbolicSourceImg
            anchors.fill: parent
            source: root.source
            sourceSize.width: root.size
            sourceSize.height: root.size
            fillMode: Image.PreserveAspectFit
            visible: false
        }

        ColorOverlay {
            anchors.fill: symbolicSourceImg
            source: symbolicSourceImg
            color: root.color
        }
    }
}
