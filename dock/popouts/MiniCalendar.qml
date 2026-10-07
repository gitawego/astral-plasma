import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../components"

Rectangle {
    id: root

    property var currentDate: new Date()
    property var viewDate: new Date()

    onCurrentDateChanged: {
        root.viewDate = new Date(root.currentDate.getTime());
    }

    readonly property color safeSurface: (typeof Colors !== "undefined" && Colors.surfaceContainer) ? Colors.surfaceContainer : Qt.rgba(0.12, 0.12, 0.16, 0.65)
    readonly property color safeBorder: (typeof Theme !== "undefined" && Theme.borderSubtle) ? Theme.borderSubtle : Qt.rgba(1, 1, 1, 0.08)
    readonly property color safePrimary: (typeof Colors !== "undefined" && Colors.primary) ? Colors.primary : "#CFBCFF"
    readonly property color safeOnPrimary: (typeof Colors !== "undefined" && Colors.textOnPrimary) ? Colors.textOnPrimary : "#FFFFFF"
    readonly property color safeOnSurface: (typeof Colors !== "undefined" && Colors.textOnSurface) ? Colors.textOnSurface : "#F2EFF4"
    readonly property color safeMuted: (typeof Colors !== "undefined" && Colors.textOnSurfaceVariant) ? Colors.textOnSurfaceVariant : "#D0D3DC"
    readonly property int safePadMedium: (typeof Theme !== "undefined" && Theme.padMedium !== undefined) ? Theme.padMedium : 12
    readonly property int safeRadiusMedium: (typeof Theme !== "undefined" && Theme.radiusMedium !== undefined) ? Theme.radiusMedium : 16
    readonly property int safeRadiusFull: (typeof Theme !== "undefined" && Theme.radiusFull !== undefined) ? Theme.radiusFull : 9999
    readonly property string safeFontFamily: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
    readonly property int safeFontSmall: (typeof Theme !== "undefined" && Theme.fontSmall !== undefined) ? Theme.fontSmall : 12
    readonly property int safeFontLabel: (typeof Theme !== "undefined" && Theme.fontLabelSmall !== undefined) ? Theme.fontLabelSmall : 11

    Layout.fillWidth: true
    implicitHeight: calLayout.implicitHeight + safePadMedium * 2
    radius: safeRadiusMedium
    color: safeSurface
    border.color: safeBorder
    border.width: 1

    function getMonthCells(targetDate) {
        if (!targetDate) return [];
        const year = targetDate.getFullYear();
        const month = targetDate.getMonth();
        const firstDay = new Date(year, month, 1);
        // Week starts on Monday: (getDay() + 6) % 7 gives 0 for Monday .. 6 for Sunday
        const startDayIdx = (firstDay.getDay() + 6) % 7;
        const daysInMonth = new Date(year, month + 1, 0).getDate();
        const daysInPrevMonth = new Date(year, month, 0).getDate();

        const cells = [];
        // Trailing days of previous month
        for (let i = startDayIdx - 1; i >= 0; i--) {
            cells.push({
                day: daysInPrevMonth - i,
                isCurrentMonth: false,
                isToday: false
            });
        }
        // Current month days
        const todayDate = root.currentDate ? root.currentDate.getDate() : 0;
        const isCurrentMonthView = root.currentDate
            && (root.currentDate.getMonth() === month)
            && (root.currentDate.getFullYear() === year);

        for (let d = 1; d <= daysInMonth; d++) {
            cells.push({
                day: d,
                isCurrentMonth: true,
                isToday: Boolean(isCurrentMonthView && (d === todayDate))
            });
        }
        // Leading days of next month to complete the row
        let nextDay = 1;
        while (cells.length % 7 !== 0) {
            cells.push({
                day: nextDay++,
                isCurrentMonth: false,
                isToday: false
            });
        }
        return cells;
    }

    readonly property var monthCells: getMonthCells(root.viewDate)
    readonly property var weekdayHeaders: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]

    ColumnLayout {
        id: calLayout
        anchors.fill: parent
        anchors.margins: root.safePadMedium
        spacing: 6

        // Month & Year Header with Quick Nav
        RowLayout {
            Layout.fillWidth: true
            spacing: 4

            MaterialIcon {
                text: "event"
                size: 15
                color: root.safePrimary
            }

            Text {
                text: Qt.formatDateTime(root.viewDate, "MMMM yyyy")
                font.family: root.safeFontFamily
                font.pixelSize: root.safeFontSmall
                font.weight: Font.DemiBold
                color: root.safeOnSurface
                Layout.fillWidth: true
            }

            // Prev month button
            Rectangle {
                implicitWidth: 20
                implicitHeight: 20
                radius: root.safeRadiusFull
                color: prevHover.containsMouse ? ((typeof Colors !== "undefined" && Colors.surfaceContainerHigh) ? Colors.surfaceContainerHigh : Qt.rgba(1, 1, 1, 0.1)) : "transparent"

                MaterialIcon {
                    anchors.centerIn: parent
                    text: "chevron_left"
                    size: 14
                    color: root.safeMuted
                }
                MouseArea {
                    id: prevHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.viewDate = new Date(root.viewDate.getFullYear(), root.viewDate.getMonth() - 1, 1);
                    }
                }
            }

            // Today reset button
            Rectangle {
                visible: (root.viewDate.getMonth() !== root.currentDate.getMonth()) || (root.viewDate.getFullYear() !== root.currentDate.getFullYear())
                implicitHeight: 20
                implicitWidth: todayText.implicitWidth + 8
                radius: root.safeRadiusFull
                color: todayHover.containsMouse ? Qt.alpha(root.safePrimary, 0.25) : Qt.alpha(root.safePrimary, 0.12)

                Text {
                    id: todayText
                    anchors.centerIn: parent
                    text: "Today"
                    font.family: root.safeFontFamily
                    font.pixelSize: root.safeFontLabel
                    font.weight: Font.Bold
                    color: root.safePrimary
                }
                MouseArea {
                    id: todayHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.viewDate = new Date(root.currentDate.getTime());
                    }
                }
            }

            // Next month button
            Rectangle {
                implicitWidth: 20
                implicitHeight: 20
                radius: root.safeRadiusFull
                color: nextHover.containsMouse ? ((typeof Colors !== "undefined" && Colors.surfaceContainerHigh) ? Colors.surfaceContainerHigh : Qt.rgba(1, 1, 1, 0.1)) : "transparent"

                MaterialIcon {
                    anchors.centerIn: parent
                    text: "chevron_right"
                    size: 14
                    color: root.safeMuted
                }
                MouseArea {
                    id: nextHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.viewDate = new Date(root.viewDate.getFullYear(), root.viewDate.getMonth() + 1, 1);
                    }
                }
            }
        }

        // Weekday Column Names
        Row {
            Layout.fillWidth: true
            spacing: 0

            Repeater {
                model: root.weekdayHeaders
                delegate: Item {
                    width: Math.floor(calLayout.width / 7)
                    height: 20

                    Text {
                        anchors.centerIn: parent
                        text: modelData
                        font.family: root.safeFontFamily
                        font.pixelSize: root.safeFontLabel
                        font.weight: Font.DemiBold
                        color: root.safeMuted
                        opacity: 0.8
                    }
                }
            }
        }

        // Days Grid
        Grid {
            id: daysGrid
            Layout.fillWidth: true
            columns: 7
            spacing: 0

            Repeater {
                model: root.monthCells
                delegate: Item {
                    required property var modelData
                    width: Math.floor(calLayout.width / 7)
                    height: 25

                    Rectangle {
                        anchors.centerIn: parent
                        width: 22
                        height: 22
                        radius: root.safeRadiusFull
                        color: modelData.isToday ? root.safePrimary : "transparent"

                        Text {
                            anchors.centerIn: parent
                            text: modelData.day
                            font.family: root.safeFontFamily
                            font.pixelSize: root.safeFontLabel
                            font.weight: modelData.isToday ? Font.Bold : (modelData.isCurrentMonth ? Font.Medium : Font.Normal)
                            color: modelData.isToday
                                ? root.safeOnPrimary
                                : (modelData.isCurrentMonth ? root.safeOnSurface : root.safeMuted)
                            opacity: modelData.isCurrentMonth ? 1.0 : 0.35
                        }
                    }
                }
            }
        }
    }
}
