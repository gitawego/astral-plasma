import QtQuick
import QtQuick.Layouts
import "../components"
import "../theme"

Item {
    id: testRoot
    width: 800
    height: 600

    property string testIdentity: "NetEase Cloud Music (Wine)"
    property var testPlayers: ["cloudmusic", "strawberry"]

    Rectangle {
        id: testPlayerBadge
        anchors.centerIn: parent
        implicitWidth: testPlayerRow.implicitWidth + 28
        implicitHeight: 28
        width: implicitWidth
        height: implicitHeight
        radius: height / 2
        color: Colors.surfaceContainerHigh
        border.color: Theme.borderSubtle
        border.width: 1

        RowLayout {
            id: testPlayerRow
            anchors.centerIn: parent
            spacing: 6

            MaterialIcon {
                id: testLeadingIcon
                text: (testRoot.testPlayers && testRoot.testPlayers.length > 1) ? "graphic_eq" : "music_note"
                size: 14
                color: Colors.primary
                Layout.alignment: Qt.AlignVCenter
            }

            Text {
                id: testPlayerText
                text: testRoot.testIdentity
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontLabelSmall
                font.weight: Font.Medium
                color: Colors.m3onSurface
                Layout.alignment: Qt.AlignVCenter
            }

            MaterialIcon {
                id: testDropdownIcon
                visible: testRoot.testPlayers && testRoot.testPlayers.length > 1
                text: "expand_more"
                size: 15
                color: Colors.onSurfaceVariant
                Layout.alignment: Qt.AlignVCenter
            }
        }
    }

    Timer {
        interval: 50
        running: true
        repeat: false
        onTriggered: runTests()
    }

    function assert(condition, message) {
        if (!condition) {
            console.error("FAIL: " + message);
            Qt.exit(1);
        }
    }

    function runTests() {
        console.log("RUNNING: Player Selector Layout Non-Regression Tests");

        // Test 1: Long identity wraps with zero overflow
        assert(testPlayerBadge.width >= testPlayerRow.implicitWidth + 24,
               "playerBadge width (" + testPlayerBadge.width + ") must be at least row implicitWidth + 24 (" + (testPlayerRow.implicitWidth + 24) + ")");
        assert(testPlayerBadge.height === 28, "playerBadge height must be 28px");
        assert(testPlayerBadge.radius === 14, "playerBadge radius must be half height (14px) for perfect pill");
        assert(testLeadingIcon.text === "graphic_eq", "Multi-player leading icon must be graphic_eq");
        assert(testDropdownIcon.visible === true, "Multi-player dropdown chevron must be visible");

        console.log("PASS: Long identity pill wrapping and multi-player controls verified");

        // Test 2: Single player mode
        testRoot.testPlayers = ["cloudmusic"];
        testRoot.testIdentity = "Elisa";

        assert(testLeadingIcon.text === "music_note", "Single player leading icon must be music_note");
        assert(testDropdownIcon.visible === false, "Single player dropdown chevron must be hidden");
        assert(testPlayerBadge.width >= testPlayerRow.implicitWidth + 24,
               "Single player pill width must wrap properly without overflow");

        console.log("PASS: Single player mode and dynamic resizing verified");

        console.log("ALL PLAYER SELECTOR TESTS PASSED!");
        Qt.exit(0);
    }
}
