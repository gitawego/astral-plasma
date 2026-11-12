import QtQuick
import "ScrollPhysics.js" as Physics

// ============================================================================
// Smooth Flickable
// ============================================================================
// The standard scroll surface for the shell. Use this instead of a bare
// Flickable so wheel scrolling is smooth everywhere, not only on the surfaces
// that remembered to install a handler.
Flickable {
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
