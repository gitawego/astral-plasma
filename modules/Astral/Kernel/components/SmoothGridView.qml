import QtQuick
import "ScrollPhysics.js" as Physics

// Smooth wheel scrolling for a GridView. See SmoothFlickable.qml.
GridView {
    id: root

    readonly property alias wheelHandler: wheelHandler

    flickDeceleration: Physics.FLICK_DECELERATION
    maximumFlickVelocity: Physics.MAXIMUM_FLICK_VELOCITY
    boundsBehavior: Flickable.StopAtBounds

    SmoothWheelHandler {
        id: wheelHandler

        flickable: root
    }

}
