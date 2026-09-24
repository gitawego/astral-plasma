import QtQuick
import QtQuick.Shapes
import QtQuick.Effects
import "../theme"
import "../services"
import "../config"

Item {
    id: root

    property bool isPlaying: false
    property string artUrl: ""
    property string title: ""
    property string artist: ""

    implicitWidth: 220
    implicitHeight: 220

    readonly property real discSize: Math.min(width, height) - 24
    readonly property real discCenterX: width / 2
    readonly property real discCenterY: height / 2 + 8

    // ==========================================
    // 1. ROTATING VINYL DISC
    // ==========================================
    Item {
        id: vinylDisc
        x: root.discCenterX - root.discSize / 2
        y: root.discCenterY - root.discSize / 2
        width: root.discSize
        height: root.discSize

        // Continuous slow rotation (16s per revolution = relaxed turntable pace)
        NumberAnimation on rotation {
            id: spinAnim
            from: 0
            to: 360
            duration: 16000
            loops: Animation.Infinite
            running: root.isPlaying && root.visible
        }

        // Dark outer vinyl plate
        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: "#121212"
            border.color: "#2a2a2a"
            border.width: 2.5

            // Outer rim bevel ring
            Rectangle {
                anchors.fill: parent
                anchors.margins: 3
                radius: width / 2
                color: "transparent"
                border.color: Qt.rgba(1, 1, 1, 0.08)
                border.width: 1
            }

            // Concentric vinyl micro-groove rings
            Repeater {
                model: [0.92, 0.87, 0.82, 0.77, 0.72, 0.67, 0.62, 0.57]
                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width * modelData
                    height: width
                    radius: width / 2
                    color: "transparent"
                    border.color: Qt.rgba(1, 1, 1, (index % 2 === 0 ? 0.045 : 0.025))
                    border.width: 1
                }
            }

            // Realistic vinyl light sheen (anisotropic reflections)
            Canvas {
                anchors.fill: parent
                onPaint: {
                    var ctx = getContext("2d");
                    ctx.reset();
                    var cx = width / 2;
                    var cy = height / 2;
                    var r = width / 2;

                    var grad1 = ctx.createRadialGradient(cx, cy, r * 0.45, cx, cy, r);
                    grad1.addColorStop(0, "rgba(255, 255, 255, 0.0)");
                    grad1.addColorStop(0.5, "rgba(255, 255, 255, 0.04)");
                    grad1.addColorStop(1, "rgba(255, 255, 255, 0.0)");

                    ctx.fillStyle = grad1;

                    // Cone 1 (top-left / bottom-right diagonal)
                    ctx.beginPath();
                    ctx.moveTo(cx, cy);
                    ctx.arc(cx, cy, r, -0.65, -0.25);
                    ctx.closePath();
                    ctx.fill();

                    ctx.beginPath();
                    ctx.moveTo(cx, cy);
                    ctx.arc(cx, cy, r, Math.PI - 0.65, Math.PI - 0.25);
                    ctx.closePath();
                    ctx.fill();

                    // Cone 2 (transverse reflection)
                    ctx.beginPath();
                    ctx.moveTo(cx, cy);
                    ctx.arc(cx, cy, r, 0.9, 1.3);
                    ctx.closePath();
                    ctx.fill();

                    ctx.beginPath();
                    ctx.moveTo(cx, cy);
                    ctx.arc(cx, cy, r, Math.PI + 0.9, Math.PI + 1.3);
                    ctx.closePath();
                    ctx.fill();
                }
            }

            // Center Circular Album Artwork Label (Perfect Circle Masked)
            Item {
                id: albumLabel
                anchors.centerIn: parent
                width: parent.width * 0.50
                height: width
                scale: (AudioVisualizer.active && Config.dashboardVisible && Config.activeDashboardTab === "media")
                       ? (1.0 + Math.min(0.05, AudioVisualizer.bass * 0.04))
                       : 1.0

                Behavior on scale {
                    NumberAnimation { duration: 60 }
                }

                // Round mask geometry
                Rectangle {
                    id: albumMask
                    anchors.fill: parent
                    radius: width / 2
                    color: "white"
                    visible: false
                    layer.enabled: true
                }

                // Fallback artwork label if no cover available
                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    visible: !(root.artUrl.length > 0 && coverImg.status === Image.Ready)
                    color: Colors.primaryContainer
                    border.color: "#1c1c1c"
                    border.width: 2

                    Column {
                        anchors.centerIn: parent
                        spacing: 2
                        MaterialIcon {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "music_note"
                            size: 24
                            color: Colors.onPrimaryContainer
                        }
                    }
                }

                // Masked Cover Image
                Item {
                    anchors.fill: parent
                    visible: root.artUrl.length > 0 && coverImg.status === Image.Ready

                    Image {
                        id: coverImg
                        anchors.fill: parent
                        source: root.artUrl
                        fillMode: Image.PreserveAspectCrop
                    }

                    layer.enabled: true
                    layer.effect: MultiEffect {
                        maskEnabled: true
                        maskSource: albumMask
                    }
                }

                // Center label outer border
                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: "transparent"
                    border.color: "#1a1a1a"
                    border.width: 2.5
                }

                // Center vinyl spindle hole
                Rectangle {
                    anchors.centerIn: parent
                    width: 16
                    height: 16
                    radius: 8
                    color: "#161616"
                    border.color: "#555555"
                    border.width: 1.5

                    // Inner silver spindle pin
                    Rectangle {
                        anchors.centerIn: parent
                        width: 6
                        height: 6
                        radius: 3
                        color: "#999999"
                    }
                }
            }
        }
    }

    // ==========================================
    // 2. TURNTABLE STYLUS TONEARM
    // ==========================================
    Item {
        id: tonearmPivot
        x: root.discCenterX - 10
        y: Math.max(4, root.discCenterY - root.discSize / 2 - 14)
        width: 75
        height: 115
        z: 10

        // Tonearm swings smoothly onto record when playing, swings away when paused
        transform: Rotation {
            origin.x: 10
            origin.y: 10
            angle: root.isPlaying ? 0 : -32

            Behavior on angle {
                NumberAnimation {
                    duration: 550
                    easing.type: Easing.OutCubic
                }
            }
        }

        // Curved Tonearm Vector Line
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeColor: "#ffffff"
                strokeWidth: 4.2
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                fillColor: "transparent"

                startX: 10
                startY: 10

                PathLine { x: 18; y: 46 }
                PathCubic {
                    x: 54
                    y: 90
                    control1X: 18
                    control1Y: 72
                    control2X: 36
                    control2Y: 88
                }
            }
        }

        // Stylus Cartridge / Headshell at the tip of the arm
        Item {
            x: 48
            y: 80
            width: 24
            height: 28
            rotation: 40

            // Headshell body
            Rectangle {
                anchors.centerIn: parent
                width: 11
                height: 20
                radius: 2.5
                color: "#ffffff"
                border.color: "#cccccc"
                border.width: 1

                // Needle tip indicator
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 2
                    width: 5
                    height: 4
                    radius: 1
                    color: "#222222"
                }
            }
        }

        // Pivot base circle at top
        Rectangle {
            x: 0
            y: 0
            width: 20
            height: 20
            radius: 10
            color: "#ffffff"
            border.color: "#b0b0b0"
            border.width: 1.5

            // Inner pivot dot
            Rectangle {
                anchors.centerIn: parent
                width: 7
                height: 7
                radius: 3.5
                color: "#222222"
            }
        }
    }
}
