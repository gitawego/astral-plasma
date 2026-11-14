import QtQuick
import Quickshell
import Quickshell.Wayland
import "../modules/Astral/Kernel/components"
import "../modules/Astral/Kernel/config"
import "../modules/Astral/Kernel/services"
import "../modules/Astral/Kernel/theme"

// ============================================================================
// AiActivityBorderWindow — the AI activity matrix effect on its own surface
// ============================================================================
// The effect used to live inside `UnifiedShell`, a full-screen glass layer. Qt
// Quick repaints the whole window for every frame of a 30 fps decorative
// animation, so each matrix tick damaged a 2560x1600 surface and made KWin
// re-composite (and re-blur) the entire shell while an agent was working. Under
// a loaded machine that extra full-screen work is what the user feels as lag.
//
// The effect only ever draws in the bottom-right corner (the bottom strip is at
// most 860 px wide, the right strip at most 480 px tall, plus a 220x160 ambient
// glow and the fused corner). Giving it its own small layer-shell surface keeps
// the exact same pixels and animation while limiting damage to that corner. The
// shell's glass frame and dock are no longer repainted by an agent's activity.
//
// No blur region: this surface is the effect, not a backdrop. An empty mask
// keeps it completely click-through so the desktop below stays interactive.
PanelWindow {
    id: root

    required property ShellScreen targetScreen
    screen: targetScreen

    anchors {
        bottom: true
        right: true
    }

    // The effect's own maximum extents: bottomWidth <= 860, rightHeight <= 480,
    // plus the fused corner and the ambient glow. A little headroom avoids any
    // clip at the largest measured RPM/agent counts.
    implicitWidth: Math.min(900, targetScreen.width)
    implicitHeight: Math.min(520, targetScreen.height)

    color: "transparent"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // Empty input region: this is decoration, never a click target.
    mask: Region {}

    readonly property bool effectActive: (typeof Config !== "undefined" && Config.modelActivityEffect)
        && (typeof AiActivityService !== "undefined")
        && AiActivityService.isActive

    // A bottom drawer or modal owns the same corner. The effect is ambient
    // decoration, so it yields while a real surface is there instead of drawing
    // over it.
    readonly property bool cornerAvailable: !(typeof Config !== "undefined" && Config.bottomPopoutVisible)
        && !(typeof PowerService !== "undefined" && PowerService.confirmDialogVisible)

    visible: effect.visible && root.cornerAvailable

    MatrixBorderEffect {
        id: effect
        anchors.fill: parent
        borderT: (typeof Config !== "undefined") ? Config.borderThickness : 14
        cornerFilletR: (typeof Theme !== "undefined" && Theme.filletRounding !== undefined)
            ? Theme.filletRounding
            : ((typeof Config !== "undefined") ? Config.borderRounding : 20)
        active: root.effectActive
        brandColor: (typeof AiActivityService !== "undefined" && AiActivityService.brandColor)
            ? AiActivityService.brandColor
            : ((typeof Colors !== "undefined" && Colors.primary) ? Colors.primary : "#818CF8")
        rpm: (typeof AiActivityService !== "undefined") ? AiActivityService.requestRate : 0.0
        tokenRate: (typeof AiActivityService !== "undefined") ? AiActivityService.tokenRate : 0.0
        recentTokens: (typeof AiActivityService !== "undefined") ? AiActivityService.recentTokens : 0.0
        intensity: (typeof AiActivityService !== "undefined") ? AiActivityService.intensity : 0.0
        modelDisplayName: (typeof AiActivityService !== "undefined") ? AiActivityService.displayName : ""
        activeAgents: (typeof AiActivityService !== "undefined" && AiActivityService.activeAgents) ? AiActivityService.activeAgents : []
    }
}
