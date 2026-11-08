import QtQuick
// A fixture app that provides a dashboard tab. It consumes the injected session,
// like a real migrated tab does.
Item {
    id: root
    property var session: null
    property var shellState: null
    implicitWidth: 400
    implicitHeight: 320
    readonly property int windowCount: session !== null ? (session.windows || []).length : 0
}
