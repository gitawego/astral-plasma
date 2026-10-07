import QtQuick

// Geometry for one dock taskbar item.
//
// The active/running indicator is a small bar pinned to the item's leading
// edge, while the design rule keeps the app icon centred in the item. The item
// must therefore reserve the indicator's gutter on BOTH sides, otherwise the
// bar collides with the icon's leading edge. Keeping the arithmetic here makes
// the gap explicit and testable.
QtObject {
    id: root

    property int iconSize: 40

    readonly property int indicatorMargin: 2
    readonly property int indicatorWidth: 3
    readonly property int indicatorGap: 3

    /// Leading gutter the indicator occupies, including its gap to the icon.
    readonly property int indicatorReserve: indicatorMargin + indicatorWidth + indicatorGap
    /// Icon plus a symmetric gutter, so the centred icon and the bar never touch.
    readonly property int itemSize: iconSize + 2 * indicatorReserve
    readonly property int iconLeft: Math.round((itemSize - iconSize) / 2)
    readonly property int indicatorRight: indicatorMargin + indicatorWidth
    /// Distance between the indicator and the icon; must stay positive.
    readonly property int gap: iconLeft - indicatorRight
}
