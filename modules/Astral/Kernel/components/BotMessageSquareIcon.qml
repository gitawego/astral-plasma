import QtQuick
import QtQuick.Shapes

Item {
    id: root

    property color color: "#ffffff"
    property int size: 18
    property real strokeWidth: 2.0

    implicitWidth: size
    implicitHeight: size

    Item {
        anchors.centerIn: parent
        width: 24
        height: 24
        scale: root.size / 24.0

        Shape {
            anchors.fill: parent
            asynchronous: false
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                fillColor: "transparent"
                strokeColor: root.color
                strokeWidth: root.strokeWidth
                joinStyle: ShapePath.RoundJoin
                capStyle: ShapePath.RoundCap
                PathSvg {
                    path: "M12 6V2H8 M15 11v2 M2 12h2 M20 12h2 M20 16a2 2 0 0 1-2 2H8.828a2 2 0 0 0-1.414.586l-2.202 2.202A.71.71 0 0 1 4 20.286V8a2 2 0 0 1 2-2h12a2 2 0 0 1 2 2z M9 11v2"
                }
            }
        }
    }
}
