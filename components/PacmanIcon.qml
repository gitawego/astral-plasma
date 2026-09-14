import QtQuick
import QtQuick.Shapes

Item {
    id: root

    property color color: "#ffffff"
    property int size: 18

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

            ShapePath {
                fillColor: root.color
                strokeColor: root.color
                strokeWidth: 0.5
                joinStyle: ShapePath.RoundJoin
                capStyle: ShapePath.RoundCap
                PathSvg {
                    path: "M12,12 L19.4,18.7 A10,10 0 1,1 19.4,5.3 Z"
                }
            }

            ShapePath {
                fillColor: root.color
                strokeColor: root.color
                strokeWidth: 0.5
                PathSvg {
                    path: "M16,12 a1.5,1.5 0 1,0 3,0 a1.5,1.5 0 1,0 -3,0 Z"
                }
            }
        }
    }
}
