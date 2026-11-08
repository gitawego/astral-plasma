import QtQuick
import "../theme"

// ============================================================================
// AppUnavailableHint — what a pane shows when its app is not available
// ============================================================================
// A dashboard pane whose app is disabled, incompatible or not installed must not be a
// blank rectangle: the user needs to know the surface exists and why it is empty.
// The host decides availability; this only reports it.
Item {
    id: root

    /// Why the app is not shown, as the host worded it (empty when it is simply disabled).
    property string reason: ""
    property string appName: ""

    Column {
        anchors.centerIn: parent
        spacing: 6

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.appName.length > 0 ? root.appName + " is not available" : "This app is not available"
            color: Colors.textOnSurface
            font.family: Theme.fontFamily
            font.pixelSize: 14
            font.weight: Font.Medium
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.min(360, root.width - 32)
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: root.reason.length > 0 ? root.reason
                                         : "Enable it in Settings → Apps."
            color: Colors.textOnSurfaceVariant
            font.family: Theme.fontFamily
            font.pixelSize: 12
        }
    }
}
