import QtQuick

// Double-buffered live window thumbnail: two images alternate so each new
// frame loads behind the visible one and swaps in only on Image.Ready - never
// a blank or half-decoded frame.
//
// `source` alternates between the capture pipeline's two slot files per
// refresh (the daemon writes preview_<id>_0.png / _1.png round-robin), so a
// changed URL is always a genuinely new frame. Changing `identity` (a
// different window) resets both buffers, so a previous window's frame can
// never linger under another app's card. Load order between the two initial
// property assignments is irrelevant: an identity reset re-issues the load.
//
// Extracted from the dock's application-preview drawer, which keeps driving it
// through `WindowService.activePreviewThumbnail`.
Item {
    id: root

    property string source: ""
    property var identity: null
    property int fillMode: Image.PreserveAspectFit

    property string activeBuffer: "A"
    property var _lastIdentity: null
    property bool hasLoadedPreview: false

    readonly property bool hasImage: hasLoadedPreview
        || (bufA.status === Image.Ready && bufA.source !== "")
        || (bufB.status === Image.Ready && bufB.source !== "")

    onIdentityChanged: {
        root._lastIdentity = root.identity;
        root.hasLoadedPreview = false;
        bufA.source = "";
        bufB.source = "";
        root.activeBuffer = "A";
        _load();
    }

    onSourceChanged: _load()

    function _load() {
        if (root.source === "") {
            root.hasLoadedPreview = false;
            bufA.source = "";
            bufB.source = "";
            return;
        }
        // If the active visible buffer already holds this exact source, ignore redundant reload
        if ((root.activeBuffer === "A" && bufA.source === root.source && bufA.status === Image.Ready) ||
            (root.activeBuffer === "B" && bufB.source === root.source && bufB.status === Image.Ready)) {
            return;
        }
        // New frame goes into the buffer that is NOT on top; it becomes
        // active when it reports Ready.
        if (root.activeBuffer === "A") {
            if (bufB.source === root.source) return;
            bufB.source = root.source;
        } else {
            if (bufA.source === root.source) return;
            bufA.source = root.source;
        }
    }

    Image {
        id: bufA
        anchors.fill: parent
        fillMode: root.fillMode
        asynchronous: true
        cache: false
        sourceSize.width: 480
        z: root.activeBuffer === "A" ? 2 : 1
        visible: root.hasLoadedPreview ? (root.activeBuffer === "A" || root.activeBuffer === "B") : (status === Image.Ready)

        onStatusChanged: {
            if (status === Image.Ready) {
                root.hasLoadedPreview = true;
                if (root.activeBuffer === "B") {
                    root.activeBuffer = "A";
                }
            }
        }
    }

    Image {
        id: bufB
        anchors.fill: parent
        fillMode: root.fillMode
        asynchronous: true
        cache: false
        sourceSize.width: 480
        z: root.activeBuffer === "B" ? 2 : 1
        visible: root.hasLoadedPreview ? (root.activeBuffer === "A" || root.activeBuffer === "B") : (status === Image.Ready)

        onStatusChanged: {
            if (status === Image.Ready) {
                root.hasLoadedPreview = true;
                if (root.activeBuffer === "A") {
                    root.activeBuffer = "B";
                }
            }
        }
    }
}
