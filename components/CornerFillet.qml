import QtQuick
import "../theme"

Canvas {
    id: root

    property real cornerRadius: 20
    property string orientation: "topLeft" // "topLeft", "topRight", "bottomLeft", "bottomRight", "dropdownLeft", "dropdownRight"
    property color fillColor: Colors.surface
    property color strokeColor: "transparent"
    property real strokeWidth: 0

    width: cornerRadius
    height: cornerRadius

    onFillColorChanged: requestPaint()
    onStrokeColorChanged: requestPaint()
    onCornerRadiusChanged: requestPaint()
    onOrientationChanged: requestPaint()

    onPaint: {
        var ctx = getContext("2d");
        ctx.reset();

        ctx.fillStyle = fillColor;
        ctx.beginPath();

        if (orientation === "dropdownLeft") {
            // Fused left fillet of dropdown:
            // Point (width, 0) is top-right corner against dropdown wall.
            // Arc from (0, 0) curving down to (width, height).
            ctx.moveTo(width, 0);
            ctx.lineTo(0, 0);
            ctx.arc(0, height, width, 1.5 * Math.PI, 0, false);
            ctx.lineTo(width, 0);
            ctx.closePath();
            ctx.fill();

            if (strokeWidth > 0 && strokeColor.a > 0) {
                ctx.strokeStyle = strokeColor;
                ctx.lineWidth = strokeWidth;
                ctx.beginPath();
                ctx.arc(0, height, width, 1.5 * Math.PI, 0, false);
                ctx.stroke();
            }
        } else if (orientation === "dropdownRight" || orientation === "topLeft") {
            // Concave fillet at top-left:
            // Point (0, 0) is corner. Arc connects (width, 0) to (0, height).
            ctx.moveTo(0, 0);
            ctx.lineTo(width, 0);
            ctx.arc(width, height, width, 1.5 * Math.PI, Math.PI, true);
            ctx.lineTo(0, 0);
            ctx.closePath();
            ctx.fill();

            if (strokeWidth > 0 && strokeColor.a > 0) {
                ctx.strokeStyle = strokeColor;
                ctx.lineWidth = strokeWidth;
                ctx.beginPath();
                ctx.arc(width, height, width, 1.5 * Math.PI, Math.PI, true);
                ctx.stroke();
            }
        } else if (orientation === "topRight") {
            // Concave fillet at top-right:
            // Point (width, 0) is corner. Arc connects (0, 0) to (width, height).
            ctx.moveTo(width, 0);
            ctx.lineTo(0, 0);
            ctx.arc(0, height, width, 1.5 * Math.PI, 2.0 * Math.PI, false);
            ctx.lineTo(width, 0);
            ctx.closePath();
            ctx.fill();

            if (strokeWidth > 0 && strokeColor.a > 0) {
                ctx.strokeStyle = strokeColor;
                ctx.lineWidth = strokeWidth;
                ctx.beginPath();
                ctx.arc(0, height, width, 1.5 * Math.PI, 2.0 * Math.PI, false);
                ctx.stroke();
            }
        } else if (orientation === "bottomLeft") {
            // Concave fillet at bottom-left:
            // Point (0, height) is corner. Arc connects (0, 0) to (width, height).
            ctx.moveTo(0, height);
            ctx.lineTo(0, 0);
            ctx.arc(width, 0, width, Math.PI, 0.5 * Math.PI, true);
            ctx.lineTo(0, height);
            ctx.closePath();
            ctx.fill();

            if (strokeWidth > 0 && strokeColor.a > 0) {
                ctx.strokeStyle = strokeColor;
                ctx.lineWidth = strokeWidth;
                ctx.beginPath();
                ctx.arc(width, 0, width, Math.PI, 0.5 * Math.PI, true);
                ctx.stroke();
            }
        } else if (orientation === "bottomRight") {
            // Concave fillet at bottom-right:
            // Point (width, height) is corner. Arc connects (width, 0) to (0, height).
            ctx.moveTo(width, height);
            ctx.lineTo(width, 0);
            ctx.arc(0, 0, width, 0, 0.5 * Math.PI, false);
            ctx.lineTo(width, height);
            ctx.closePath();
            ctx.fill();

            if (strokeWidth > 0 && strokeColor.a > 0) {
                ctx.strokeStyle = strokeColor;
                ctx.lineWidth = strokeWidth;
                ctx.beginPath();
                ctx.arc(0, 0, width, 0, 0.5 * Math.PI, false);
                ctx.stroke();
            }
        }
    }
}
