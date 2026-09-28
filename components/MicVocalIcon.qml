import QtQuick
import QtQuick.Shapes

/**
 * Lucide `mic-vocal`, drawn as vector paths.
 *
 * This exists because the shell's icon font has no microphone glyph. An earlier
 * attempt mapped the Material Design Icons private-use codepoints for
 * `microphone`, but that range is absent from the Nerd Font build in use and
 * resolved to unrelated shapes -- a factory silhouette and a pair of bars.
 * Presence in the font's `cmap` is not identity, and a plausible name failing
 * loudly would have been better than drawing the wrong thing.
 *
 * The path is Lucide's, used under the ISC License
 * (https://lucide.dev/icons/mic-vocal). It is reproduced verbatim in SVG
 * grammar, including the relative commands, so it tracks upstream exactly:
 *
 *   <path d="m11 7.601-5.994 8.19a1 1 0 0 0 .1 1.298l.817.818a1 1 0 0 0 1.314.087L15.09 12"/>
 *   <path d="M16.5 21.174C15.5 20.5 14.372 20 13 20c-2.058 0-3.928 2.356-6 2-2.072-.356-2.775-3.369-1.5-4.5"/>
 *   <circle cx="16" cy="7" r="5"/>
 *
 * The circle is expressed as two arcs on the same `ShapePath` so the whole icon
 * is a single geometry, matching the stroke joins and caps.
 *
 * Structure follows `BotMessageSquareIcon`, the existing hand-drawn icon in this
 * shell: a 24x24 design box scaled to `size`, Lucide's 2px stroke, round joins.
 */
Item {
    id: root

    property color color: "#ffffff"
    property int size: 18
    /** Lucide's nominal stroke. Scaled with the icon, like every other set. */
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
            // docs/LESSONS.md 9.3: GeometryRenderer is mandatory on every Shape.
            // CurveRenderer caches dirty rects in GPU scissor tiles and ghosts
            // on Intel Mesa at high refresh rates.
            preferredRendererType: Shape.GeometryRenderer

            ShapePath {
                fillColor: "transparent"
                strokeColor: root.color
                strokeWidth: root.strokeWidth
                joinStyle: ShapePath.RoundJoin
                capStyle: ShapePath.RoundCap
                PathSvg {
                    path: "m11 7.601-5.994 8.19a1 1 0 0 0 .1 1.298l.817.818a1 1 0 0 0 1.314.087L15.09 12"
                        + "M16.5 21.174C15.5 20.5 14.372 20 13 20c-2.058 0-3.928 2.356-6 2-2.072-.356-2.775-3.369-1.5-4.5"
                        + "M11 7a5 5 0 1 0 10 0a5 5 0 1 0-10 0"
                }
            }
        }
    }
}
