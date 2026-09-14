import QtQuick
import QtQuick.Shapes
import "../theme"

Item {
    id: root

    property real cornerRadius: 20
    property real overlap: 2
    property string orientation: "topLeft" // "topLeft", "topRight", "bottomLeft", "bottomRight", "dropdownLeft", "dropdownRight"
    property color fillColor: (typeof Colors !== "undefined" && Colors.surface) ? Colors.surface : "#141318"
    property color strokeColor: "transparent"
    property real strokeWidth: 0

    width: cornerRadius
    height: cornerRadius

    // topLeft (inner screen corner: dock on left, top border on top)
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        visible: root.orientation === "topLeft"
        ShapePath {
            fillColor: root.fillColor
            strokeColor: root.strokeColor
            strokeWidth: root.strokeWidth
            startX: -root.overlap; startY: -root.overlap
            PathLine { x: root.width; y: -root.overlap }
            PathLine { x: root.width; y: 0 }
            PathArc { x: 0; y: root.height; radiusX: root.width; radiusY: root.height; direction: PathArc.Counterclockwise }
            PathLine { x: -root.overlap; y: root.height }
            PathLine { x: -root.overlap; y: -root.overlap }
        }
    }

    // topRight (inner screen corner: top border on top, right border on right)
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        visible: root.orientation === "topRight"
        ShapePath {
            fillColor: root.fillColor
            strokeColor: root.strokeColor
            strokeWidth: root.strokeWidth
            startX: root.width + root.overlap; startY: -root.overlap
            PathLine { x: 0; y: -root.overlap }
            PathLine { x: 0; y: 0 }
            PathArc { x: root.width; y: root.height; radiusX: root.width; radiusY: root.height; direction: PathArc.Clockwise }
            PathLine { x: root.width + root.overlap; y: root.height }
            PathLine { x: root.width + root.overlap; y: -root.overlap }
        }
    }

    // bottomLeft (inner screen corner: dock on left, bottom border on bottom; or popout inverted fillet)
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        visible: root.orientation === "bottomLeft"
        ShapePath {
            fillColor: root.fillColor
            strokeColor: root.strokeColor
            strokeWidth: root.strokeWidth
            startX: -root.overlap; startY: root.height + root.overlap
            PathLine { x: -root.overlap; y: 0 }
            PathLine { x: 0; y: 0 }
            PathArc { x: root.width; y: root.height; radiusX: root.width; radiusY: root.height; direction: PathArc.Counterclockwise }
            PathLine { x: root.width; y: root.height + root.overlap }
            PathLine { x: -root.overlap; y: root.height + root.overlap }
        }
    }

    // bottomRight (inner screen corner: bottom border on bottom, right border on right)
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        visible: root.orientation === "bottomRight"
        ShapePath {
            fillColor: root.fillColor
            strokeColor: root.strokeColor
            strokeWidth: root.strokeWidth
            startX: root.width + root.overlap; startY: root.height + root.overlap
            PathLine { x: root.width + root.overlap; y: 0 }
            PathLine { x: root.width; y: 0 }
            PathArc { x: 0; y: root.height; radiusX: root.width; radiusY: root.height; direction: PathArc.Clockwise }
            PathLine { x: 0; y: root.height + root.overlap }
            PathLine { x: root.width + root.overlap; y: root.height + root.overlap }
        }
    }

    // dropdownLeft (inverted fillet: top border on top, dropdown on right)
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        visible: root.orientation === "dropdownLeft"
        ShapePath {
            fillColor: root.fillColor
            strokeColor: root.strokeColor
            strokeWidth: root.strokeWidth
            startX: 0; startY: -root.overlap
            PathLine { x: root.width + root.overlap; y: -root.overlap }
            PathLine { x: root.width + root.overlap; y: root.height }
            PathLine { x: root.width; y: root.height }
            PathArc { x: 0; y: 0; radiusX: root.width; radiusY: root.height; direction: PathArc.Counterclockwise }
            PathLine { x: 0; y: -root.overlap }
        }
    }

    // dropdownRight (inverted fillet: top border on top, dropdown on left)
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        visible: root.orientation === "dropdownRight"
        ShapePath {
            fillColor: root.fillColor
            strokeColor: root.strokeColor
            strokeWidth: root.strokeWidth
            startX: -root.overlap; startY: root.height
            PathLine { x: -root.overlap; y: -root.overlap }
            PathLine { x: root.width; y: -root.overlap }
            PathLine { x: root.width; y: 0 }
            PathArc { x: 0; y: root.height; radiusX: root.width; radiusY: root.height; direction: PathArc.Counterclockwise }
            PathLine { x: -root.overlap; y: root.height }
        }
    }
}
