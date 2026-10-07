import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import QtWebEngine
import "../theme"
import "../components"
import "../services"
import "../config"

// The embedded DSH web UI. Only ever instantiated when the hosting Quickshell
// supports QtWebEngine (DshWebService.webEngineSupported); stock Quickshell
// aborts the moment a WebEngineView is constructed.
//
// Authentication:
//   * our own managed server -> url is already the tokenised URL;
//   * an adopted server     -> the first load is the 401 page, so the window
//     mints the DSH cookie (DshWebService.authCookie) and writes it with
//     document.cookie on the DSH origin, then reloads.
// The cookie lives in the named persistent profile, so later opens are clean.
FloatingWindow {
    id: root

    property bool testMode: false

    readonly property alias webViewItem: webView
    readonly property alias toolbarItem: toolbar
    readonly property int referenceWidth: (screen && screen.width > 0) ? screen.width : 1920
    readonly property int referenceHeight: (screen && screen.height > 0) ? screen.height : 1080

    property bool cookieInjected: false

    title: "DSH Web"
    color: "transparent"
    screen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
    visible: root.testMode ? true : DshWebService.visible

    implicitWidth: Math.min(1440, Math.max(720, Math.round(root.referenceWidth * 0.72)))
    implicitHeight: Math.min(980, Math.max(520, Math.round(root.referenceHeight * 0.86)))
    minimumSize: Qt.size(560, 380)
    maximumSize: Qt.size(4096, 4096)

    // A compositor close (or our own toolbar) hides the surface; keep the
    // service's one source of truth in step so the icon can reopen it.
    onVisibleChanged: {
        if (!root.visible && !root.testMode && DshWebService.visible) DshWebService.close()
    }

    Connections {
        target: DshWebService
        function onTargetUrlChanged() { root.cookieInjected = false }
    }

    // Named, on-disk profile: the DSH auth cookie outlives the window.
    WebEngineProfile {
        id: dshProfile
        storageName: "astral-dsh-web"
        offTheRecord: false
        persistentCookiesPolicy: WebEngineProfile.ForcePersistentCookies
    }

    // A small icon button reused across the toolbar.
    component ToolButton: Rectangle {
        id: tool
        property string icon: ""
        property bool active: true
        signal activated()
        implicitWidth: 30
        implicitHeight: 30
        radius: Theme.radiusFull
        color: toolHover.hovered && tool.active ? Colors.surfaceContainerHigh : "transparent"
        opacity: tool.active ? 1.0 : 0.35
        Behavior on color { ColorAnimation { duration: Theme.animDurationFast } }

        MaterialIcon {
            anchors.centerIn: parent
            text: tool.icon
            size: 16
            color: Colors.m3onSurface
        }
        HoverHandler { id: toolHover }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            enabled: tool.active
            onClicked: tool.activated()
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusLarge
        color: Colors.surfaceContainer
        border.width: 1
        border.color: Qt.alpha(Colors.outlineVariant, 0.55)
        clip: true

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 1
            spacing: 0

            // ---- Toolbar ---------------------------------------------------
            Rectangle {
                id: toolbar
                Layout.fillWidth: true
                Layout.preferredHeight: 46
                color: Colors.surfaceContainerHigh

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 8
                    spacing: 6

                    Rectangle {
                        Layout.alignment: Qt.AlignVCenter
                        width: 8
                        height: 8
                        radius: 4
                        color: {
                            if (DshWebService.state === "error") return "#E05353";
                            if (DshWebService.state === "ready") return "#3FB950";
                            return "#F59E0B";
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        text: DshWebService.statusText
                        elide: Text.ElideRight
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        color: Colors.m3onSurfaceVariant
                    }

                    ToolButton {
                        icon: "arrow_back"
                        active: webView.canGoBack
                        onActivated: webView.goBack()
                    }
                    ToolButton {
                        icon: "arrow_forward"
                        active: webView.canGoForward
                        onActivated: webView.goForward()
                    }
                    ToolButton {
                        icon: "refresh"
                        onActivated: webView.reload()
                    }
                    ToolButton {
                        icon: "open_in_new"
                        onActivated: DshWebService.openExternal(webView.url)
                    }
                    ToolButton {
                        icon: "close"
                        onActivated: DshWebService.close()
                    }
                }
            }

            // ---- Error banner ---------------------------------------------
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: DshWebService.errorMessage.length > 0 ? 38 : 0
                visible: DshWebService.errorMessage.length > 0
                color: Qt.alpha("#E05353", 0.16)

                Text {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    verticalAlignment: Text.AlignVCenter
                    text: DshWebService.errorMessage
                    elide: Text.ElideRight
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    color: Colors.m3onSurface
                }
            }

            // ---- The web surface ------------------------------------------
            WebEngineView {
                id: webView
                Layout.fillWidth: true
                Layout.fillHeight: true
                profile: dshProfile
                url: DshWebService.targetUrl

                onLoadingChanged: function(request) {
                    if (request.status === WebEngineView.LoadFailedStatus
                        && DshWebService.injectCookie && !root.cookieInjected) {
                        root.cookieInjected = true;
                        var cookie = DshWebService.authCookie();
                        if (cookie && cookie.name && cookie.value) {
                            var js = "document.cookie = "
                                + JSON.stringify(cookie.name + "=" + cookie.value + "; path=/") + ";";
                            webView.runJavaScript(js, function() { webView.reload(); });
                        } else {
                            DshWebService.statusText = "DSH authentication needs a server started by Astral";
                        }
                    }
                }
            }
        }
    }
}
