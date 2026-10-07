import QtQuick
import QtQuick.Shapes
import "../theme"

/**
 * Lucide `astroid`, drawn as vector paths.
 *
 * Used for AI token monitoring and quota tracking.
 * Lucide icon definition (ISC License): https://lucide.dev/icons/astroid
 *
 * Replaces the ambiguous font glyph (\uf51e / stacked layers) with the authentic
 * 4-pointed hypocycloid astroid curve from Lucide.
 */
Item {
    id: root

    property color color: (typeof Colors !== "undefined" && Colors.m3onSurface) ? Colors.m3onSurface : "#ffffff"
    property int size: 18
    /** Lucide's nominal stroke (2px on 24x24 box), scaled with the icon. */
    property real strokeWidth: 2.0

    implicitWidth: size
    implicitHeight: size
    width: size
    height: size

    Item {
        anchors.centerIn: parent
        width: 24
        height: 24
        scale: root.size / 24.0

        Shape {
            anchors.fill: parent
            asynchronous: false
            // docs/LESSONS.md 9.3: GeometryRenderer is mandatory on every Shape.
            preferredRendererType: Shape.GeometryRenderer

            ShapePath {
                fillColor: "transparent"
                strokeColor: root.color
                strokeWidth: root.strokeWidth
                joinStyle: ShapePath.RoundJoin
                capStyle: ShapePath.RoundCap
                PathSvg {
                    path: "M12.983 21.186a1 1 0 0 1-1.966 0 10 10 0 0 0-8.203-8.203 1 1 0 0 1 0-1.966 10 10 0 0 0 8.203-8.203 1 1 0 0 1 1.966 0 10 10 0 0 0 8.203 8.203 1 1 0 0 1 0 1.966 10 10 0 0 0-8.203 8.203"
                }
            }
        }
    }
}
