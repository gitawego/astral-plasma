import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../theme"
import "../config"
import "../components"
import "../services"
import "../dock/popouts"
import "../notifications"

PanelWindow {
    id: root

    required property ShellScreen targetScreen
    screen: targetScreen

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    color: "transparent"
    WlrLayershell.layer: WlrLayer.Top
    // Keyboard focus policy.
    //
    // Requesting focus on this surface (OnDemand) makes KWin activate it - and
    // because the surface is an invisible, full-screen layer shell, KWin never
    // hands activation back when the focus request is withdrawn. The result was
    // that merely opening a drawer left a `quickshell` window as the compositor's
    // active window forever, starving the window watcher of `windowActivated`
    // events so the dock's active-app display froze on a stale application.
    //
    // So focus is requested ONLY for the power-confirmation modal, where Enter and
    // Escape are essential and a brief activation shift is what a user expects
    // from a modal. Drawers and popouts instead close on mouse-leave and on
    // scrim click, and cost nothing in activation terms.
    WlrLayershell.keyboardFocus: (typeof PowerService !== "undefined" && PowerService.confirmDialogVisible)
        ? WlrKeyboardFocus.OnDemand
        : WlrKeyboardFocus.None
    WlrLayershell.exclusionMode: ExclusionMode.Ignore

    // Wayland Native Compositor Backdrop Blur for Liquid Glass
    BackgroundEffect.blurRegion: Region {
        // Blur-region visibility gate.
        //
        // The compositor keeps applying the LAST region it received, so a
        // region that collapses through a partially-zero (degenerate) state on
        // the animation's final frame can stay on screen until some unrelated
        // repaint happens to commit the clear - which is why the blur outlives
        // a closing drawer by up to a second. Two rules prevent it:
        //
        //   1. All dimensions are gated by ONE boolean, so the region is either
        //      a valid positive-area rect or fully empty - never 980x0.
        //   2. That boolean clears while the close animation still has frames
        //      left (offset 0.06 leaves ~17 frames at 60Hz to flush the clear).
        //
        // The main body's height is clamped to the frame thickness so it can
        // never thin out to nothing while still active.
        // Left Dock
        Region {
            x: 0
            y: 0
            width: Config.dockEnabled ? root.dockW : 0
            height: root.height
        }

        // Top Border
        Region {
            x: root.dockW
            y: 0
            width: root.width - root.dockW - root.borderT
            height: root.borderT
        }

        // Right Border
        Region {
            x: root.width - root.borderT
            y: 0
            width: root.borderT
            height: root.height
        }

        // Bottom Border
        Region {
            x: root.dockW
            y: root.height - root.borderT
            width: root.width - root.dockW - root.borderT
            height: root.borderT
        }

        // Screen Inner Fillet: Top-Left
        Region { x: root.dockW; y: root.borderT + root.filletProfile.depths[0]; width: root.filletProfile.widths[0]; height: root.filletProfile.heights[0] }
        Region { x: root.dockW; y: root.borderT + root.filletProfile.depths[1]; width: root.filletProfile.widths[1]; height: root.filletProfile.heights[1] }
        Region { x: root.dockW; y: root.borderT + root.filletProfile.depths[2]; width: root.filletProfile.widths[2]; height: root.filletProfile.heights[2] }
        Region { x: root.dockW; y: root.borderT + root.filletProfile.depths[3]; width: root.filletProfile.widths[3]; height: root.filletProfile.heights[3] }
        Region { x: root.dockW; y: root.borderT + root.filletProfile.depths[4]; width: root.filletProfile.widths[4]; height: root.filletProfile.heights[4] }
        Region { x: root.dockW; y: root.borderT + root.filletProfile.depths[5]; width: root.filletProfile.widths[5]; height: root.filletProfile.heights[5] }
        Region { x: root.dockW; y: root.borderT + root.filletProfile.depths[6]; width: root.filletProfile.widths[6]; height: root.filletProfile.heights[6] }

        // Screen Inner Fillet: Top-Right
        Region { x: root.width - root.borderT - root.filletProfile.widths[0]; y: root.borderT + root.filletProfile.depths[0]; width: root.filletProfile.widths[0]; height: root.filletProfile.heights[0] }
        Region { x: root.width - root.borderT - root.filletProfile.widths[1]; y: root.borderT + root.filletProfile.depths[1]; width: root.filletProfile.widths[1]; height: root.filletProfile.heights[1] }
        Region { x: root.width - root.borderT - root.filletProfile.widths[2]; y: root.borderT + root.filletProfile.depths[2]; width: root.filletProfile.widths[2]; height: root.filletProfile.heights[2] }
        Region { x: root.width - root.borderT - root.filletProfile.widths[3]; y: root.borderT + root.filletProfile.depths[3]; width: root.filletProfile.widths[3]; height: root.filletProfile.heights[3] }
        Region { x: root.width - root.borderT - root.filletProfile.widths[4]; y: root.borderT + root.filletProfile.depths[4]; width: root.filletProfile.widths[4]; height: root.filletProfile.heights[4] }
        Region { x: root.width - root.borderT - root.filletProfile.widths[5]; y: root.borderT + root.filletProfile.depths[5]; width: root.filletProfile.widths[5]; height: root.filletProfile.heights[5] }
        Region { x: root.width - root.borderT - root.filletProfile.widths[6]; y: root.borderT + root.filletProfile.depths[6]; width: root.filletProfile.widths[6]; height: root.filletProfile.heights[6] }

        // Screen Inner Fillet: Bottom-Left
        Region { x: root.dockW; y: root.height - root.borderT - root.filletProfile.depths[1]; width: root.filletProfile.widths[0]; height: root.filletProfile.heights[0] }
        Region { x: root.dockW; y: root.height - root.borderT - root.filletProfile.depths[2]; width: root.filletProfile.widths[1]; height: root.filletProfile.heights[1] }
        Region { x: root.dockW; y: root.height - root.borderT - root.filletProfile.depths[3]; width: root.filletProfile.widths[2]; height: root.filletProfile.heights[2] }
        Region { x: root.dockW; y: root.height - root.borderT - root.filletProfile.depths[4]; width: root.filletProfile.widths[3]; height: root.filletProfile.heights[3] }
        Region { x: root.dockW; y: root.height - root.borderT - root.filletProfile.depths[5]; width: root.filletProfile.widths[4]; height: root.filletProfile.heights[4] }
        Region { x: root.dockW; y: root.height - root.borderT - root.filletProfile.depths[6]; width: root.filletProfile.widths[5]; height: root.filletProfile.heights[5] }
        Region { x: root.dockW; y: root.height - root.borderT - root.filletProfile.depths[7]; width: root.filletProfile.widths[6]; height: root.filletProfile.heights[6] }

        // Screen Inner Fillet: Bottom-Right
        Region { x: root.width - root.borderT - root.filletProfile.widths[0]; y: root.height - root.borderT - root.filletProfile.depths[1]; width: root.filletProfile.widths[0]; height: root.filletProfile.heights[0] }
        Region { x: root.width - root.borderT - root.filletProfile.widths[1]; y: root.height - root.borderT - root.filletProfile.depths[2]; width: root.filletProfile.widths[1]; height: root.filletProfile.heights[1] }
        Region { x: root.width - root.borderT - root.filletProfile.widths[2]; y: root.height - root.borderT - root.filletProfile.depths[3]; width: root.filletProfile.widths[2]; height: root.filletProfile.heights[2] }
        Region { x: root.width - root.borderT - root.filletProfile.widths[3]; y: root.height - root.borderT - root.filletProfile.depths[4]; width: root.filletProfile.widths[3]; height: root.filletProfile.heights[3] }
        Region { x: root.width - root.borderT - root.filletProfile.widths[4]; y: root.height - root.borderT - root.filletProfile.depths[5]; width: root.filletProfile.widths[4]; height: root.filletProfile.heights[4] }
        Region { x: root.width - root.borderT - root.filletProfile.widths[5]; y: root.height - root.borderT - root.filletProfile.depths[6]; width: root.filletProfile.widths[5]; height: root.filletProfile.heights[5] }
        Region { x: root.width - root.borderT - root.filletProfile.widths[6]; y: root.height - root.borderT - root.filletProfile.depths[7]; width: root.filletProfile.widths[6]; height: root.filletProfile.heights[6] }

        // Central Dropdown Dashboard (when open) - Inset bottom corners to match rounded card borders
        Region {
            x: root.blurRegionActive ? root.dropX : 0
            y: 0
            width: root.blurRegionActive ? root.dropW : 0
            height: root.blurRegionActive ? root.blurDropH : 0
        }
        Region {
            x: root.blurRegionActive ? (root.dropX + Math.round(root.filletR * 0.15)) : 0
            y: root.blurRegionActive ? root.blurDropH : 0
            width: root.blurRegionActive ? Math.max(0, root.dropW - Math.round(root.filletR * 0.30)) : 0
            height: root.blurRegionActive ? Math.round(root.filletR * 0.50) : 0
        }
        Region {
            x: root.blurRegionActive ? (root.dropX + Math.round(root.filletR * 0.40)) : 0
            y: root.blurRegionActive ? Math.max(0, root.currentDropH - Math.round(root.filletR * 0.50)) : 0
            width: root.blurRegionActive ? Math.max(0, root.dropW - Math.round(root.filletR * 0.80)) : 0
            height: root.blurRegionActive ? Math.round(root.filletR * 0.30) : 0
        }
        Region {
            x: root.blurRegionActive ? (root.dropX + root.filletR) : 0
            y: root.blurRegionActive ? Math.max(0, root.currentDropH - Math.round(root.filletR * 0.20)) : 0
            width: root.blurRegionActive ? Math.max(0, root.dropW - root.filletR * 2) : 0
            height: root.blurRegionActive ? Math.round(root.filletR * 0.20) : 0
        }

        // Central Dropdown Left Shoulder Fillet
        Region {
            x: root.blurRegionActive ? (root.dropX - root.filletW1) : 0
            y: root.blurRegionActive ? root.borderT : 0
            width: root.blurRegionActive ? root.filletW1 : 0
            height: root.blurRegionActive ? Math.min(root.filletH1, Math.max(0, root.currentDropH - root.borderT)) : 0
        }
        Region {
            x: root.blurRegionActive ? (root.dropX - root.filletW2) : 0
            y: root.blurRegionActive ? (root.borderT + root.filletD1) : 0
            width: root.blurRegionActive ? root.filletW2 : 0
            height: root.blurRegionActive ? Math.min(root.filletH2, Math.max(0, root.currentDropH - root.borderT - root.filletD1)) : 0
        }
        Region {
            x: root.blurRegionActive ? (root.dropX - root.filletW3) : 0
            y: root.blurRegionActive ? (root.borderT + root.filletD2) : 0
            width: root.blurRegionActive ? root.filletW3 : 0
            height: root.blurRegionActive ? Math.min(root.filletH3, Math.max(0, root.currentDropH - root.borderT - root.filletD2)) : 0
        }
        Region {
            x: root.blurRegionActive ? (root.dropX - root.filletW4) : 0
            y: root.blurRegionActive ? (root.borderT + root.filletD3) : 0
            width: root.blurRegionActive ? root.filletW4 : 0
            height: root.blurRegionActive ? Math.min(root.filletH4, Math.max(0, root.currentDropH - root.borderT - root.filletD3)) : 0
        }
        Region {
            x: root.blurRegionActive ? (root.dropX - root.filletW5) : 0
            y: root.blurRegionActive ? (root.borderT + root.filletD4) : 0
            width: root.blurRegionActive ? root.filletW5 : 0
            height: root.blurRegionActive ? Math.min(root.filletH5, Math.max(0, root.currentDropH - root.borderT - root.filletD4)) : 0
        }
        Region {
            x: root.blurRegionActive ? (root.dropX - root.filletW6) : 0
            y: root.blurRegionActive ? (root.borderT + root.filletD5) : 0
            width: root.blurRegionActive ? root.filletW6 : 0
            height: root.blurRegionActive ? Math.min(root.filletH6, Math.max(0, root.currentDropH - root.borderT - root.filletD5)) : 0
        }
        Region {
            x: root.blurRegionActive ? (root.dropX - root.filletW7) : 0
            y: root.blurRegionActive ? (root.borderT + root.filletD6) : 0
            width: root.blurRegionActive ? root.filletW7 : 0
            height: root.blurRegionActive ? Math.min(root.filletH7, Math.max(0, root.currentDropH - root.borderT - root.filletD6)) : 0
        }

        // Central Dropdown Right Shoulder Fillet
        Region {
            x: root.blurRegionActive ? (root.dropX + root.dropW) : 0
            y: root.blurRegionActive ? root.borderT : 0
            width: root.blurRegionActive ? root.filletW1 : 0
            height: root.blurRegionActive ? Math.min(root.filletH1, Math.max(0, root.currentDropH - root.borderT)) : 0
        }
        Region {
            x: root.blurRegionActive ? (root.dropX + root.dropW) : 0
            y: root.blurRegionActive ? (root.borderT + root.filletD1) : 0
            width: root.blurRegionActive ? root.filletW2 : 0
            height: root.blurRegionActive ? Math.min(root.filletH2, Math.max(0, root.currentDropH - root.borderT - root.filletD1)) : 0
        }
        Region {
            x: root.blurRegionActive ? (root.dropX + root.dropW) : 0
            y: root.blurRegionActive ? (root.borderT + root.filletD2) : 0
            width: root.blurRegionActive ? root.filletW3 : 0
            height: root.blurRegionActive ? Math.min(root.filletH3, Math.max(0, root.currentDropH - root.borderT - root.filletD2)) : 0
        }
        Region {
            x: root.blurRegionActive ? (root.dropX + root.dropW) : 0
            y: root.blurRegionActive ? (root.borderT + root.filletD3) : 0
            width: root.blurRegionActive ? root.filletW4 : 0
            height: root.blurRegionActive ? Math.min(root.filletH4, Math.max(0, root.currentDropH - root.borderT - root.filletD3)) : 0
        }
        Region {
            x: root.blurRegionActive ? (root.dropX + root.dropW) : 0
            y: root.blurRegionActive ? (root.borderT + root.filletD4) : 0
            width: root.blurRegionActive ? root.filletW5 : 0
            height: root.blurRegionActive ? Math.min(root.filletH5, Math.max(0, root.currentDropH - root.borderT - root.filletD4)) : 0
        }
        Region {
            x: root.blurRegionActive ? (root.dropX + root.dropW) : 0
            y: root.blurRegionActive ? (root.borderT + root.filletD5) : 0
            width: root.blurRegionActive ? root.filletW6 : 0
            height: root.blurRegionActive ? Math.min(root.filletH6, Math.max(0, root.currentDropH - root.borderT - root.filletD5)) : 0
        }
        Region {
            x: root.blurRegionActive ? (root.dropX + root.dropW) : 0
            y: root.blurRegionActive ? (root.borderT + root.filletD6) : 0
            width: root.blurRegionActive ? root.filletW7 : 0
            height: root.blurRegionActive ? Math.min(root.filletH7, Math.max(0, root.currentDropH - root.borderT - root.filletD6)) : 0
        }

        // Fused Bottom Popout (when open & fused to bottom border)
        // Top-right convex corner slices (when fused to bottom)
        Region {
            x: (root.blurPopoutFused) ? root.dockW : 0
            y: (root.blurPopoutFused) ? fusedBottomPopoutWrapper.y : 0
            width: (root.blurPopoutFused) ? Math.max(0, root.currentPopW - 15) : 0
            height: (root.blurPopoutFused) ? 1 : 0
        }
        Region {
            x: (root.blurPopoutFused) ? root.dockW : 0
            y: (root.blurPopoutFused) ? (fusedBottomPopoutWrapper.y + 1) : 0
            width: (root.blurPopoutFused) ? Math.max(0, root.currentPopW - 12) : 0
            height: (root.blurPopoutFused) ? 1 : 0
        }
        Region {
            x: (root.blurPopoutFused) ? root.dockW : 0
            y: (root.blurPopoutFused) ? (fusedBottomPopoutWrapper.y + 2) : 0
            width: (root.blurPopoutFused) ? Math.max(0, root.currentPopW - 9) : 0
            height: (root.blurPopoutFused) ? 2 : 0
        }
        Region {
            x: (root.blurPopoutFused) ? root.dockW : 0
            y: (root.blurPopoutFused) ? (fusedBottomPopoutWrapper.y + 4) : 0
            width: (root.blurPopoutFused) ? Math.max(0, root.currentPopW - 5) : 0
            height: (root.blurPopoutFused) ? 3 : 0
        }
        Region {
            x: (root.blurPopoutFused) ? root.dockW : 0
            y: (root.blurPopoutFused) ? (fusedBottomPopoutWrapper.y + 7) : 0
            width: (root.blurPopoutFused) ? Math.max(0, root.currentPopW - 3) : 0
            height: (root.blurPopoutFused) ? 3 : 0
        }
        Region {
            x: (root.blurPopoutFused) ? root.dockW : 0
            y: (root.blurPopoutFused) ? (fusedBottomPopoutWrapper.y + 10) : 0
            width: (root.blurPopoutFused) ? Math.max(0, root.currentPopW - 1) : 0
            height: (root.blurPopoutFused) ? 4 : 0
        }
        Region {
            x: (root.blurPopoutFused) ? root.dockW : 0
            // Spans the whole surface: the mask is a UNION, so overlapping the
            // corner staircases below is harmless. Any inset here would instead
            // leave a full-width band of unblurred glass, which shows the
            // wallpaper sharply and reads as the blur lagging the popout.
            // Consumes UnifiedFrame's authoritative FULL surface rect, so the mask
            // cannot diverge from the drawn glass. fullRect (not bodyRect) is
            // required: the top and bottom `filletR` bands are glass right across
            // the width - only their leftmost sliver is the concave shoulder - so a
            // body-sized mask would leave those bands unblurred.
            // (Was `root.height - wrapper.y`, sized to the screen bottom rather
            // than to the surface.)
            y: (root.blurPopoutFused) ? desktopFrame.bottomPopoutSurfaceItem.fullRect.y : 0
            width: (root.blurPopoutFused) ? desktopFrame.bottomPopoutSurfaceItem.fullRect.width : 0
            height: (root.blurPopoutFused) ? desktopFrame.bottomPopoutSurfaceItem.fullRect.height : 0
        }

        // Floating Bottom Popout (when open & floating)
        // Top-right convex corner slices (when floating)
        Region {
            x: (root.blurPopoutFloating) ? root.floatingCardRect.x : 0
            y: (root.blurPopoutFloating) ? fusedBottomPopoutWrapper.y : 0
            width: (root.blurPopoutFloating) ? Math.max(0, root.floatingCardRect.width - 15) : 0
            height: (root.blurPopoutFloating) ? 1 : 0
        }
        Region {
            x: (root.blurPopoutFloating) ? root.floatingCardRect.x : 0
            y: (root.blurPopoutFloating) ? (fusedBottomPopoutWrapper.y + 1) : 0
            width: (root.blurPopoutFloating) ? Math.max(0, root.floatingCardRect.width - 12) : 0
            height: (root.blurPopoutFloating) ? 1 : 0
        }
        Region {
            x: (root.blurPopoutFloating) ? root.floatingCardRect.x : 0
            y: (root.blurPopoutFloating) ? (fusedBottomPopoutWrapper.y + 2) : 0
            width: (root.blurPopoutFloating) ? Math.max(0, root.floatingCardRect.width - 9) : 0
            height: (root.blurPopoutFloating) ? 2 : 0
        }
        Region {
            x: (root.blurPopoutFloating) ? root.floatingCardRect.x : 0
            y: (root.blurPopoutFloating) ? (fusedBottomPopoutWrapper.y + 4) : 0
            width: (root.blurPopoutFloating) ? Math.max(0, root.floatingCardRect.width - 5) : 0
            height: (root.blurPopoutFloating) ? 3 : 0
        }
        Region {
            x: (root.blurPopoutFloating) ? root.floatingCardRect.x : 0
            y: (root.blurPopoutFloating) ? (fusedBottomPopoutWrapper.y + 7) : 0
            width: (root.blurPopoutFloating) ? Math.max(0, root.floatingCardRect.width - 3) : 0
            height: (root.blurPopoutFloating) ? 3 : 0
        }
        Region {
            x: (root.blurPopoutFloating) ? root.floatingCardRect.x : 0
            y: (root.blurPopoutFloating) ? (fusedBottomPopoutWrapper.y + 10) : 0
            width: (root.blurPopoutFloating) ? Math.max(0, root.floatingCardRect.width - 1) : 0
            height: (root.blurPopoutFloating) ? 4 : 0
        }
        Region {
            x: (root.blurPopoutFloating) ? root.floatingCardRect.x : 0
            // The floating card itself. Consumes UnifiedFrame's authoritative
            // floatingRect: the surface is larger than the glass in this state
            // (left band = concave shoulder cut, top/bottom bands exist for the
            // fused shape), so a surface-sized mask frosted bare wallpaper
            // around the drawer. The mask is a union, so overlapping the corner
            // staircases below is harmless.
            y: (root.blurPopoutFloating) ? desktopFrame.bottomPopoutSurfaceItem.floatingRect.y : 0
            width: (root.blurPopoutFloating) ? desktopFrame.bottomPopoutSurfaceItem.floatingRect.width : 0
            height: (root.blurPopoutFloating) ? desktopFrame.bottomPopoutSurfaceItem.floatingRect.height : 0
        }
        // Bottom-right convex corner slices (when floating)
        Region {
            x: (root.blurPopoutFloating) ? root.floatingCardRect.x : 0
            y: (root.blurPopoutFloating) ? (fusedBottomPopoutWrapper.y + fusedBottomPopoutWrapper.height - 14) : 0
            width: (root.blurPopoutFloating) ? Math.max(0, root.floatingCardRect.width - 1) : 0
            height: (root.blurPopoutFloating) ? 4 : 0
        }
        Region {
            x: (root.blurPopoutFloating) ? root.floatingCardRect.x : 0
            y: (root.blurPopoutFloating) ? (fusedBottomPopoutWrapper.y + fusedBottomPopoutWrapper.height - 10) : 0
            width: (root.blurPopoutFloating) ? Math.max(0, root.floatingCardRect.width - 3) : 0
            height: (root.blurPopoutFloating) ? 3 : 0
        }
        Region {
            x: (root.blurPopoutFloating) ? root.floatingCardRect.x : 0
            y: (root.blurPopoutFloating) ? (fusedBottomPopoutWrapper.y + fusedBottomPopoutWrapper.height - 7) : 0
            width: (root.blurPopoutFloating) ? Math.max(0, root.floatingCardRect.width - 5) : 0
            height: (root.blurPopoutFloating) ? 3 : 0
        }
        Region {
            x: (root.blurPopoutFloating) ? root.floatingCardRect.x : 0
            y: (root.blurPopoutFloating) ? (fusedBottomPopoutWrapper.y + fusedBottomPopoutWrapper.height - 4) : 0
            width: (root.blurPopoutFloating) ? Math.max(0, root.floatingCardRect.width - 9) : 0
            height: (root.blurPopoutFloating) ? 2 : 0
        }
        Region {
            x: (root.blurPopoutFloating) ? root.floatingCardRect.x : 0
            y: (root.blurPopoutFloating) ? (fusedBottomPopoutWrapper.y + fusedBottomPopoutWrapper.height - 2) : 0
            width: (root.blurPopoutFloating) ? Math.max(0, root.floatingCardRect.width - 12) : 0
            height: (root.blurPopoutFloating) ? 1 : 0
        }
        Region {
            x: (root.blurPopoutFloating) ? root.floatingCardRect.x : 0
            y: (root.blurPopoutFloating) ? (fusedBottomPopoutWrapper.y + fusedBottomPopoutWrapper.height - 1) : 0
            width: (root.blurPopoutFloating) ? Math.max(0, root.floatingCardRect.width - 15) : 0
            height: (root.blurPopoutFloating) ? 1 : 0
        }

        // Bottom Popout Top Shoulder Fillet (Frosted Glass Blur, when bottom-fused)
        //
        // Fused-only: while floating, the drawer is not connected to anything
        // above it, so this band would frost bare wallpaper over the card.
        Region {
            x: root.blurPopoutFused ? root.dockW : 0
            y: root.blurPopoutFused ? (fusedBottomPopoutWrapper.y - root.filletD1) : 0
            width: root.blurPopoutFused ? Math.min(root.currentPopW, root.filletW1) : 0
            height: root.blurPopoutFused ? root.filletH1 : 0
        }
        Region {
            x: root.blurPopoutFused ? root.dockW : 0
            y: root.blurPopoutFused ? (fusedBottomPopoutWrapper.y - root.filletD2) : 0
            width: root.blurPopoutFused ? Math.min(root.currentPopW, root.filletW2) : 0
            height: root.blurPopoutFused ? root.filletH2 : 0
        }
        Region {
            x: root.blurPopoutFused ? root.dockW : 0
            y: root.blurPopoutFused ? (fusedBottomPopoutWrapper.y - root.filletD3) : 0
            width: root.blurPopoutFused ? Math.min(root.currentPopW, root.filletW3) : 0
            height: root.blurPopoutFused ? root.filletH3 : 0
        }
        Region {
            x: root.blurPopoutFused ? root.dockW : 0
            y: root.blurPopoutFused ? (fusedBottomPopoutWrapper.y - root.filletD4) : 0
            width: root.blurPopoutFused ? Math.min(root.currentPopW, root.filletW4) : 0
            height: root.blurPopoutFused ? root.filletH4 : 0
        }
        Region {
            x: root.blurPopoutFused ? root.dockW : 0
            y: root.blurPopoutFused ? (fusedBottomPopoutWrapper.y - root.filletD5) : 0
            width: root.blurPopoutFused ? Math.min(root.currentPopW, root.filletW5) : 0
            height: root.blurPopoutFused ? root.filletH5 : 0
        }
        Region {
            x: root.blurPopoutFused ? root.dockW : 0
            y: root.blurPopoutFused ? (fusedBottomPopoutWrapper.y - root.filletD6) : 0
            width: root.blurPopoutFused ? Math.min(root.currentPopW, root.filletW6) : 0
            height: root.blurPopoutFused ? root.filletH6 : 0
        }
        Region {
            x: root.blurPopoutFused ? root.dockW : 0
            y: root.blurPopoutFused ? (fusedBottomPopoutWrapper.y - root.filletD7) : 0
            width: root.blurPopoutFused ? Math.min(root.currentPopW, root.filletW7) : 0
            height: root.blurPopoutFused ? root.filletH7 : 0
        }

        // Bottom Popout Bottom Shoulder Fillet (Frosted Glass Blur, when floating)
        Region {
            x: (root.blurPopoutFloating) ? root.dockW : 0
            y: (root.blurPopoutFloating) ? (fusedBottomPopoutWrapper.y + fusedBottomPopoutWrapper.height + root.filletD1 - root.filletH1) : 0
            width: (root.blurPopoutFloating) ? Math.min(root.currentPopW, root.filletW1) : 0
            height: (root.blurPopoutFloating) ? root.filletH1 : 0
        }
        Region {
            x: (root.blurPopoutFloating) ? root.dockW : 0
            y: (root.blurPopoutFloating) ? (fusedBottomPopoutWrapper.y + fusedBottomPopoutWrapper.height + root.filletD2 - root.filletH2) : 0
            width: (root.blurPopoutFloating) ? Math.min(root.currentPopW, root.filletW2) : 0
            height: (root.blurPopoutFloating) ? root.filletH2 : 0
        }
        Region {
            x: (root.blurPopoutFloating) ? root.dockW : 0
            y: (root.blurPopoutFloating) ? (fusedBottomPopoutWrapper.y + fusedBottomPopoutWrapper.height + root.filletD3 - root.filletH3) : 0
            width: (root.blurPopoutFloating) ? Math.min(root.currentPopW, root.filletW3) : 0
            height: (root.blurPopoutFloating) ? root.filletH3 : 0
        }
        Region {
            x: (root.blurPopoutFloating) ? root.dockW : 0
            y: (root.blurPopoutFloating) ? (fusedBottomPopoutWrapper.y + fusedBottomPopoutWrapper.height + root.filletD4 - root.filletH4) : 0
            width: (root.blurPopoutFloating) ? Math.min(root.currentPopW, root.filletW4) : 0
            height: (root.blurPopoutFloating) ? root.filletH4 : 0
        }
        Region {
            x: (root.blurPopoutFloating) ? root.dockW : 0
            y: (root.blurPopoutFloating) ? (fusedBottomPopoutWrapper.y + fusedBottomPopoutWrapper.height + root.filletD5 - root.filletH5) : 0
            width: (root.blurPopoutFloating) ? Math.min(root.currentPopW, root.filletW5) : 0
            height: (root.blurPopoutFloating) ? root.filletH5 : 0
        }
        Region {
            x: (root.blurPopoutFloating) ? root.dockW : 0
            y: (root.blurPopoutFloating) ? (fusedBottomPopoutWrapper.y + fusedBottomPopoutWrapper.height + root.filletD6 - root.filletH6) : 0
            width: (root.blurPopoutFloating) ? Math.min(root.currentPopW, root.filletW6) : 0
            height: (root.blurPopoutFloating) ? root.filletH6 : 0
        }
        Region {
            x: (root.blurPopoutFloating) ? root.dockW : 0
            y: (root.blurPopoutFloating) ? (fusedBottomPopoutWrapper.y + fusedBottomPopoutWrapper.height + root.filletD7 - root.filletH7) : 0
            width: (root.blurPopoutFloating) ? Math.min(root.currentPopW, root.filletW7) : 0
            height: (root.blurPopoutFloating) ? root.filletH7 : 0
        }

        // Bottom Popout Bottom-Right Concave Fillet (Frosted Glass Blur, when bottom-fused)
        Region {
            x: (root.blurPopoutFused) ? (root.dockW + root.currentPopW) : 0
            y: (root.blurPopoutFused) ? (root.height - root.borderT - root.filletD1) : 0
            width: (root.blurPopoutFused) ? root.filletW1 : 0
            height: (root.blurPopoutFused) ? root.filletH1 : 0
        }
        Region {
            x: (root.blurPopoutFused) ? (root.dockW + root.currentPopW) : 0
            y: (root.blurPopoutFused) ? (root.height - root.borderT - root.filletD2) : 0
            width: (root.blurPopoutFused) ? root.filletW2 : 0
            height: (root.blurPopoutFused) ? root.filletH2 : 0
        }
        Region {
            x: (root.blurPopoutFused) ? (root.dockW + root.currentPopW) : 0
            y: (root.blurPopoutFused) ? (root.height - root.borderT - root.filletD3) : 0
            width: (root.blurPopoutFused) ? root.filletW3 : 0
            height: (root.blurPopoutFused) ? root.filletH3 : 0
        }
        Region {
            x: (root.blurPopoutFused) ? (root.dockW + root.currentPopW) : 0
            y: (root.blurPopoutFused) ? (root.height - root.borderT - root.filletD4) : 0
            width: (root.blurPopoutFused) ? root.filletW4 : 0
            height: (root.blurPopoutFused) ? root.filletH4 : 0
        }
        Region {
            x: (root.blurPopoutFused) ? (root.dockW + root.currentPopW) : 0
            y: (root.blurPopoutFused) ? (root.height - root.borderT - root.filletD5) : 0
            width: (root.blurPopoutFused) ? root.filletW5 : 0
            height: (root.blurPopoutFused) ? root.filletH5 : 0
        }
        Region {
            x: (root.blurPopoutFused) ? (root.dockW + root.currentPopW) : 0
            y: (root.blurPopoutFused) ? (root.height - root.borderT - root.filletD6) : 0
            width: (root.blurPopoutFused) ? root.filletW6 : 0
            height: (root.blurPopoutFused) ? root.filletH6 : 0
        }
        Region {
            x: (root.blurPopoutFused) ? (root.dockW + root.currentPopW) : 0
            y: (root.blurPopoutFused) ? (root.height - root.borderT - root.filletD7) : 0
            width: (root.blurPopoutFused) ? root.filletW7 : 0
            height: (root.blurPopoutFused) ? root.filletH7 : 0
        }

        // Left Drawer / Context Menu (when open)
        Region {
            x: (appContextMenu.menuCardVisible || trayContextMenu.menuCardVisible) ? root.dockW : 0
            y: trayContextMenu.menuCardVisible ? trayContextMenu.menuCardY : (appContextMenu.menuCardVisible ? appContextMenu.menuCardY : 0)
            width: trayContextMenu.menuCardVisible ? trayContextMenu.menuCardW : (appContextMenu.menuCardVisible ? appContextMenu.menuCardW : 0)
            height: trayContextMenu.menuCardVisible ? trayContextMenu.menuCardH : (appContextMenu.menuCardVisible ? appContextMenu.menuCardH : 0)
        }

        // Right Edge Volume/Brightness Control (when open) - Precision Stepped Blur Body
        // Top-left convex corner slices
        Region {
            x: root.blurRightEdgeActive
                ? (root.width - root.borderT - (root.currentRightW - 15))
                : 0
            y: root.blurRightEdgeActive ? root.rightControlY : 0
            width: root.blurRightEdgeActive ? (Math.max(0, root.currentRightW - 15) + root.borderT) : 0
            height: root.blurRightEdgeActive ? 1 : 0
        }
        Region {
            x: root.blurRightEdgeActive
                ? (root.width - root.borderT - (root.currentRightW - 12))
                : 0
            y: root.blurRightEdgeActive ? (root.rightControlY + 1) : 0
            width: root.blurRightEdgeActive ? (Math.max(0, root.currentRightW - 12) + root.borderT) : 0
            height: root.blurRightEdgeActive ? 1 : 0
        }
        Region {
            x: root.blurRightEdgeActive
                ? (root.width - root.borderT - (root.currentRightW - 9))
                : 0
            y: root.blurRightEdgeActive ? (root.rightControlY + 2) : 0
            width: root.blurRightEdgeActive ? (Math.max(0, root.currentRightW - 9) + root.borderT) : 0
            height: root.blurRightEdgeActive ? 2 : 0
        }
        Region {
            x: root.blurRightEdgeActive
                ? (root.width - root.borderT - (root.currentRightW - 5))
                : 0
            y: root.blurRightEdgeActive ? (root.rightControlY + 4) : 0
            width: root.blurRightEdgeActive ? (Math.max(0, root.currentRightW - 5) + root.borderT) : 0
            height: root.blurRightEdgeActive ? 3 : 0
        }
        Region {
            x: root.blurRightEdgeActive
                ? (root.width - root.borderT - (root.currentRightW - 3))
                : 0
            y: root.blurRightEdgeActive ? (root.rightControlY + 7) : 0
            width: root.blurRightEdgeActive ? (Math.max(0, root.currentRightW - 3) + root.borderT) : 0
            height: root.blurRightEdgeActive ? 3 : 0
        }
        Region {
            x: root.blurRightEdgeActive
                ? (root.width - root.borderT - (root.currentRightW - 1))
                : 0
            y: root.blurRightEdgeActive ? (root.rightControlY + 10) : 0
            width: root.blurRightEdgeActive ? (Math.max(0, root.currentRightW - 1) + root.borderT) : 0
            height: root.blurRightEdgeActive ? 4 : 0
        }
        // Middle full-width body
        Region {
            x: root.blurRightEdgeActive
                ? (root.width - root.borderT - root.currentRightW)
                : 0
            y: root.blurRightEdgeActive ? (root.rightControlY + 14) : 0
            width: root.blurRightEdgeActive ? (root.currentRightW + root.borderT) : 0
            height: root.blurRightEdgeActive ? Math.max(0, root.rightControlH - 28) : 0
        }
        // Bottom-left convex corner slices
        Region {
            x: root.blurRightEdgeActive
                ? (root.width - root.borderT - (root.currentRightW - 1))
                : 0
            y: root.blurRightEdgeActive ? (root.rightControlY + root.rightControlH - 14) : 0
            width: root.blurRightEdgeActive ? (Math.max(0, root.currentRightW - 1) + root.borderT) : 0
            height: root.blurRightEdgeActive ? 4 : 0
        }
        Region {
            x: root.blurRightEdgeActive
                ? (root.width - root.borderT - (root.currentRightW - 3))
                : 0
            y: root.blurRightEdgeActive ? (root.rightControlY + root.rightControlH - 10) : 0
            width: root.blurRightEdgeActive ? (Math.max(0, root.currentRightW - 3) + root.borderT) : 0
            height: root.blurRightEdgeActive ? 3 : 0
        }
        Region {
            x: root.blurRightEdgeActive
                ? (root.width - root.borderT - (root.currentRightW - 5))
                : 0
            y: root.blurRightEdgeActive ? (root.rightControlY + root.rightControlH - 7) : 0
            width: root.blurRightEdgeActive ? (Math.max(0, root.currentRightW - 5) + root.borderT) : 0
            height: root.blurRightEdgeActive ? 3 : 0
        }
        Region {
            x: root.blurRightEdgeActive
                ? (root.width - root.borderT - (root.currentRightW - 9))
                : 0
            y: root.blurRightEdgeActive ? (root.rightControlY + root.rightControlH - 4) : 0
            width: root.blurRightEdgeActive ? (Math.max(0, root.currentRightW - 9) + root.borderT) : 0
            height: root.blurRightEdgeActive ? 2 : 0
        }
        Region {
            x: root.blurRightEdgeActive
                ? (root.width - root.borderT - (root.currentRightW - 12))
                : 0
            y: root.blurRightEdgeActive ? (root.rightControlY + root.rightControlH - 2) : 0
            width: root.blurRightEdgeActive ? (Math.max(0, root.currentRightW - 12) + root.borderT) : 0
            height: root.blurRightEdgeActive ? 1 : 0
        }
        Region {
            x: root.blurRightEdgeActive
                ? (root.width - root.borderT - (root.currentRightW - 15))
                : 0
            y: root.blurRightEdgeActive ? (root.rightControlY + root.rightControlH - 1) : 0
            width: root.blurRightEdgeActive ? (Math.max(0, root.currentRightW - 15) + root.borderT) : 0
            height: root.blurRightEdgeActive ? 1 : 0
        }

        // Right Edge Control Top Shoulder Fillet (Frosted Glass Stepped Slices)
        Region {
            x: root.blurRightEdgeActive ? (root.width - root.borderT - Math.min(root.currentRightW, root.filletW1)) : 0
            y: root.blurRightEdgeActive ? (root.rightControlY - root.filletD1) : 0
            width: root.blurRightEdgeActive ? Math.min(root.currentRightW, root.filletW1) : 0
            height: root.blurRightEdgeActive ? root.filletH1 : 0
        }
        Region {
            x: root.blurRightEdgeActive ? (root.width - root.borderT - Math.min(root.currentRightW, root.filletW2)) : 0
            y: root.blurRightEdgeActive ? (root.rightControlY - root.filletD2) : 0
            width: root.blurRightEdgeActive ? Math.min(root.currentRightW, root.filletW2) : 0
            height: root.blurRightEdgeActive ? root.filletH2 : 0
        }
        Region {
            x: root.blurRightEdgeActive ? (root.width - root.borderT - Math.min(root.currentRightW, root.filletW3)) : 0
            y: root.blurRightEdgeActive ? (root.rightControlY - root.filletD3) : 0
            width: root.blurRightEdgeActive ? Math.min(root.currentRightW, root.filletW3) : 0
            height: root.blurRightEdgeActive ? root.filletH3 : 0
        }
        Region {
            x: root.blurRightEdgeActive ? (root.width - root.borderT - Math.min(root.currentRightW, root.filletW4)) : 0
            y: root.blurRightEdgeActive ? (root.rightControlY - root.filletD4) : 0
            width: root.blurRightEdgeActive ? Math.min(root.currentRightW, root.filletW4) : 0
            height: root.blurRightEdgeActive ? root.filletH4 : 0
        }
        Region {
            x: root.blurRightEdgeActive ? (root.width - root.borderT - Math.min(root.currentRightW, root.filletW5)) : 0
            y: root.blurRightEdgeActive ? (root.rightControlY - root.filletD5) : 0
            width: root.blurRightEdgeActive ? Math.min(root.currentRightW, root.filletW5) : 0
            height: root.blurRightEdgeActive ? root.filletH5 : 0
        }
        Region {
            x: root.blurRightEdgeActive ? (root.width - root.borderT - Math.min(root.currentRightW, root.filletW6)) : 0
            y: root.blurRightEdgeActive ? (root.rightControlY - root.filletD6) : 0
            width: root.blurRightEdgeActive ? Math.min(root.currentRightW, root.filletW6) : 0
            height: root.blurRightEdgeActive ? root.filletH6 : 0
        }
        Region {
            x: root.blurRightEdgeActive ? (root.width - root.borderT - Math.min(root.currentRightW, root.filletW7)) : 0
            y: root.blurRightEdgeActive ? (root.rightControlY - root.filletD7) : 0
            width: root.blurRightEdgeActive ? Math.min(root.currentRightW, root.filletW7) : 0
            height: root.blurRightEdgeActive ? root.filletH7 : 0
        }

        // Right Edge Control Bottom Shoulder Fillet (Frosted Glass Stepped Slices)
        Region {
            x: root.blurRightEdgeActive ? (root.width - root.borderT - Math.min(root.currentRightW, root.filletW1)) : 0
            y: root.blurRightEdgeActive ? (root.rightControlY + root.rightControlH + root.filletD1 - root.filletH1) : 0
            width: root.blurRightEdgeActive ? Math.min(root.currentRightW, root.filletW1) : 0
            height: root.blurRightEdgeActive ? root.filletH1 : 0
        }
        Region {
            x: root.blurRightEdgeActive ? (root.width - root.borderT - Math.min(root.currentRightW, root.filletW2)) : 0
            y: root.blurRightEdgeActive ? (root.rightControlY + root.rightControlH + root.filletD2 - root.filletH2) : 0
            width: root.blurRightEdgeActive ? Math.min(root.currentRightW, root.filletW2) : 0
            height: root.blurRightEdgeActive ? root.filletH2 : 0
        }
        Region {
            x: root.blurRightEdgeActive ? (root.width - root.borderT - Math.min(root.currentRightW, root.filletW3)) : 0
            y: root.blurRightEdgeActive ? (root.rightControlY + root.rightControlH + root.filletD3 - root.filletH3) : 0
            width: root.blurRightEdgeActive ? Math.min(root.currentRightW, root.filletW3) : 0
            height: root.blurRightEdgeActive ? root.filletH3 : 0
        }
        Region {
            x: root.blurRightEdgeActive ? (root.width - root.borderT - Math.min(root.currentRightW, root.filletW4)) : 0
            y: root.blurRightEdgeActive ? (root.rightControlY + root.rightControlH + root.filletD4 - root.filletH4) : 0
            width: root.blurRightEdgeActive ? Math.min(root.currentRightW, root.filletW4) : 0
            height: root.blurRightEdgeActive ? root.filletH4 : 0
        }
        Region {
            x: root.blurRightEdgeActive ? (root.width - root.borderT - Math.min(root.currentRightW, root.filletW5)) : 0
            y: root.blurRightEdgeActive ? (root.rightControlY + root.rightControlH + root.filletD5 - root.filletH5) : 0
            width: root.blurRightEdgeActive ? Math.min(root.currentRightW, root.filletW5) : 0
            height: root.blurRightEdgeActive ? root.filletH5 : 0
        }
        Region {
            x: root.blurRightEdgeActive ? (root.width - root.borderT - Math.min(root.currentRightW, root.filletW6)) : 0
            y: root.blurRightEdgeActive ? (root.rightControlY + root.rightControlH + root.filletD6 - root.filletH6) : 0
            width: root.blurRightEdgeActive ? Math.min(root.currentRightW, root.filletW6) : 0
            height: root.blurRightEdgeActive ? root.filletH6 : 0
        }
        Region {
            x: root.blurRightEdgeActive ? (root.width - root.borderT - Math.min(root.currentRightW, root.filletW7)) : 0
            y: root.blurRightEdgeActive ? (root.rightControlY + root.rightControlH + root.filletD7 - root.filletH7) : 0
            width: root.blurRightEdgeActive ? Math.min(root.currentRightW, root.filletW7) : 0
            height: root.blurRightEdgeActive ? root.filletH7 : 0
        }

        // System Notifications Popup.
        //
        // Consumes the notification's own surface extents so the mask cannot
        // overhang the glass. It previously added `filletR` to both the width and
        // the height unconditionally, which blurred a 20px band of BARE desktop
        // below the panel and a 20px column to its left - observable as frosted
        // wallpaper with nothing drawn over it. The panel's real extent is:
        //   * x: the panel's left edge, extended left only by the corner fillet
        //        that is actually present (topLeft corner only)
        //   * y: 0..height (the panel is flush with the screen top)
        Region {
            x: (notifPopup.visible && !notifPopup.isDismissed) ? notifPopup.surfaceX : 0
            y: 0
            width: (notifPopup.visible && !notifPopup.isDismissed) ? notifPopup.surfaceWidth : 0
            height: (notifPopup.visible && !notifPopup.isDismissed) ? notifPopup.surfaceHeight : 0
        }
        // Shoulder stub: the concave fillet at the top-left junction is painted
        // outside the panel rect, but only in the top `borderRounding` rows. A
        // full-height column there would frost bare desktop below the shoulder.
        Region {
            x: (notifPopup.visible && !notifPopup.isDismissed) ? notifPopup.shoulderRect.x : 0
            y: 0
            width: (notifPopup.visible && !notifPopup.isDismissed) ? notifPopup.shoulderRect.width : 0
            height: (notifPopup.visible && !notifPopup.isDismissed) ? notifPopup.shoulderRect.height : 0
        }

        // Power Confirmation Dialog Card Blur (Translucent Liquid Glass Modal)
        Region {
            x: (typeof PowerService !== "undefined" && PowerService && PowerService.confirmDialogVisible && typeof powerConfirmDialog !== "undefined") ? powerConfirmDialog.cardX : 0
            y: (typeof PowerService !== "undefined" && PowerService && PowerService.confirmDialogVisible && typeof powerConfirmDialog !== "undefined") ? powerConfirmDialog.cardY : 0
            width: (typeof PowerService !== "undefined" && PowerService && PowerService.confirmDialogVisible && typeof powerConfirmDialog !== "undefined") ? powerConfirmDialog.cardW : 0
            height: (typeof PowerService !== "undefined" && PowerService && PowerService.confirmDialogVisible && typeof powerConfirmDialog !== "undefined") ? powerConfirmDialog.cardH : 0
        }
    }



    // Configuration and Tokens
    readonly property real borderT: Config.borderThickness
    readonly property real filletR: Config.borderRounding
    readonly property bool hasMaximizedWindow: (typeof WindowService !== "undefined" && WindowService && (WindowService.hasMaximizedWindow || WindowService.hasActiveMaximized)) ? true : false
    readonly property real cornerFilletR: root.filletR
    readonly property real dockW: Config.dockWidth + 6
    readonly property real iconS: Config.dockIconSize

    // Fillet blur slice cumulative depths (d1..d7) and slice heights (h1..h7)
    readonly property real filletD1: 1
    readonly property real filletD2: 2
    readonly property real filletD3: Math.round(root.filletR * 0.20)
    readonly property real filletD4: Math.round(root.filletR * 0.35)
    readonly property real filletD5: Math.round(root.filletR * 0.55)
    readonly property real filletD6: Math.round(root.filletR * 0.75)
    readonly property real filletD7: root.filletR

    readonly property real filletH1: root.filletD1
    readonly property real filletH2: root.filletD2 - root.filletD1
    readonly property real filletH3: root.filletD3 - root.filletD2
    readonly property real filletH4: root.filletD4 - root.filletD3
    readonly property real filletH5: root.filletD5 - root.filletD4
    readonly property real filletH6: root.filletD6 - root.filletD5
    readonly property real filletH7: root.filletD7 - root.filletD6

    readonly property real filletW1: Math.round(root.filletR * 0.85)
    readonly property real filletW2: Math.round(root.filletR * 0.65)
    readonly property real filletW3: Math.round(root.filletR * 0.50)
    readonly property real filletW4: Math.round(root.filletR * 0.35)
    readonly property real filletW5: Math.round(root.filletR * 0.20)
    readonly property real filletW6: Math.round(root.filletR * 0.10)
    readonly property real filletW7: 1

    // Screen-edge inner fillet: blur-mask slice profile, derived from the arc.
    //
    // These four fillets are concave arcs of radius `filletR` where the dock meets
    // the top/bottom border. The compositor can only blur axis-aligned rectangles,
    // so the arc must be approximated by stacked slices - and the mask must COVER
    // the glass, because the glass is translucent (alpha ~0.65): any glass the mask
    // misses shows sharp wallpaper through it.
    //
    // The previous profile was hand-tuned to widths 12/7/4/2/1, each sized for its
    // slice's BOTTOM depth. Because the arc widens steeply toward the tangency, the
    // top of every slice was left uncovered - up to 8px at the first slice - which
    // rendered as a stepped corner. Deriving the widths from the arc equation and
    // sizing each slice for its TOP depth makes the mask cover the glass by
    // construction, for any configured radius.
    //
    // Depth fractions (fine near the tangency, where the curve changes fastest).
    readonly property var filletProfile: {
        const R = root.filletR;
        const depths = [0, 1, 2, 4, 7, 11, 15, R];
        const heights = [];
        const widths = [];
        for (let i = 0; i < depths.length - 1; i++) {
            const d = depths[i];
            const dist = Math.max(0, R - d);
            const w = R - Math.sqrt(Math.max(0, R * R - dist * dist));
            widths.push(Math.max(1, Math.min(R, Math.ceil(w))));
            heights.push(depths[i + 1] - depths[i]);
        }
        return { widths: widths, heights: heights, depths: depths };
    }

    // Dropdown Dashboard Geometry
    readonly property real dropW: Config.dashboardWidth
    readonly property real dropH: dropdownContainer.dropH
    readonly property real targetDropH: dropdownContainer ? dropdownContainer.targetDropH : 440
    readonly property real dropX: (root.width - root.dropW) / 2
    readonly property real currentDropH: dropdownContainer.currentDropH

    // Blur-region visibility gate. The compositor keeps applying the LAST region
    // it received, so a region collapsing through a partially-zero (degenerate)
    // state on the animation's final frame can persist until some unrelated
    // repaint commits the clear - which is why the blur outlives a closing
    // drawer by up to a second. Two rules prevent it:
    //   1. Every dimension is gated by ONE boolean, so the region is either a
    //      valid positive-area rect or fully empty - never 980x0.
    //   2. That boolean clears while the close animation still has frames left
    //      (offset 0.06 leaves ~17 frames at 60Hz to flush the clear).
    readonly property real blurRegionMinProgress: 0.06
    readonly property bool blurRegionActive: dropdownContainer.offsetProgress > root.blurRegionMinProgress
    // Because every dimension switches on the same frame, the region is never a
    // degenerate strip: while active it always has positive width AND height.
    readonly property real blurDropH: root.blurRegionActive
        ? Math.max(1, root.currentDropH - root.filletR)
        : 0

    // Region probe (opt-in via Config.debugMode). Logs the exact rect handed to
    // the compositor so a blur-teardown problem can be diagnosed from the shell
    // log instead of inferred from screenshots. Costs nothing when debug is off.
    readonly property rect dropdownBlurRect: Qt.rect(
        root.blurRegionActive ? root.dropX : 0,
        0,
        root.blurRegionActive ? root.dropW : 0,
        root.blurRegionActive ? root.blurDropH : 0)
    onDropdownBlurRectChanged: {
        if (typeof Config !== "undefined" && Config.debugMode) {
            console.log("[BlurRegion] t=" + Date.now()
                + " dropdown=" + root.dropdownBlurRect.width + "x" + root.dropdownBlurRect.height.toFixed(1)
                + " popout=" + (root.blurPopoutActive ? "on" : "off")
                + " rightEdge=" + (root.blurRightEdgeActive ? "on" : "off"));
        }
    }


    // Same atomic-gate rule for the other drawers. Each is a separate region set
    // with its own progress driver, and each would otherwise collapse its width
    // and height at different offsets, leaving a degenerate region the
    // compositor may keep applying after the drawer is gone.
    readonly property bool blurPopoutActive: fusedBottomPopoutWrapper.offsetProgress > root.blurRegionMinProgress
    readonly property bool blurPopoutFused: root.blurPopoutActive && root.fusedProgress > 0.5
    readonly property bool blurPopoutFloating: root.blurPopoutActive && root.fusedProgress <= 0.5
    // The floating card's own rect (UnifiedFrame is the single source of truth).
    readonly property rect floatingCardRect: desktopFrame.bottomPopoutSurfaceItem.floatingRect
    readonly property bool blurRightEdgeActive: rightEdgeControlWrapper.offsetProgress > root.blurRegionMinProgress

    // Blur-region audit trail (opt-in via Config.debugMode; no cost when off).
    //
    // The compositor blur is the UNION of every region below, so a region that is
    // stale, mis-sized, or lingering shows as frosted glass somewhere the user
    // never opened a drawer - and because blur can only be observed in a
    // screenshot, an intermittent case is very hard to catch after the fact.
    // Logging every region-driving rect makes such a case self-reporting: with
    // debugMode on, reproduce it and read the offending rect out of the log.
    readonly property var blurDebugRects: {
        const app = appContextMenu;
        const tray = trayContextMenu;
        const popFloating = root.blurPopoutFloating;
        const popFused = root.blurPopoutFused;
        return [
            { name: "dropdown", on: root.blurRegionActive,
              x: root.dropX, y: 0, w: root.dropW, h: root.blurDropH },
            { name: "dropdownShoulders", on: root.blurRegionActive,
              x: root.dropX - root.filletW1, y: root.borderT,
              w: root.filletW1 * 2, h: Math.max(0, root.currentDropH - root.borderT) },
            { name: "popoutFloating", on: popFloating,
              x: root.dockW, y: fusedBottomPopoutWrapper.y - root.filletR,
              w: root.currentPopW, h: fusedBottomPopoutWrapper.height + root.filletR * 2 },
            { name: "popoutFused", on: popFused,
              x: root.dockW, y: fusedBottomPopoutWrapper.y,
              w: root.currentPopW, h: Math.max(0, root.height - fusedBottomPopoutWrapper.y) },
            { name: "notification", on: (notifPopup.visible && !notifPopup.isDismissed),
              x: notifPopup.surfaceX, y: 0,
              w: notifPopup.surfaceWidth, h: notifPopup.surfaceHeight },
            { name: "appMenu", on: app.menuCardVisible,
              x: root.dockW, y: app.menuCardY, w: app.menuCardW, h: app.menuCardH },
            { name: "trayMenu", on: tray.menuCardVisible,
              x: root.dockW, y: tray.menuCardY, w: tray.menuCardW, h: tray.menuCardH },
            { name: "rightEdge", on: root.blurRightEdgeActive,
              x: root.width - root.borderT - root.currentRightW, y: root.rightControlY - root.filletR,
              w: root.currentRightW + root.borderT, h: root.rightControlH + root.filletR * 2 }
        ];
    }
    property int _blurAuditTick: 0
    Timer {
        interval: 700; running: true; repeat: true
        onTriggered: {
            if (typeof Config === "undefined" || !Config.debugMode) return;
            root._blurAuditTick++;
            if (root._blurAuditTick % 3 !== 0) return;
            const rects = root.blurDebugRects;
            const active = [];
            for (let i = 0; i < rects.length; i++) {
                const r = rects[i];
                if (r.on) {
                    active.push(r.name + "=" + Math.round(r.x) + "," + Math.round(r.y)
                        + " " + Math.round(r.w) + "x" + Math.round(r.h));
                }
            }
            console.log("[BlurAudit] active: " + (active.length ? active.join("  ") : "(none)"));
        }
    }

    // =========================================================================
    // Active Frame Commit Pump for Wayland Blur Region Synchronization
    // =========================================================================
    // In the Wayland protocol (ext-background-effect-v1), set_blur_region is double-
    // buffered client state applied strictly upon the next wl_surface.commit.
    // When a drawer or popout finishes its closing animation, visual items become
    // invisible (visible: offsetProgress > 0.001) and Qt Quick's threaded renderer halts.
    // Without an active scene graph update, Mesa EGL emits NO buffer swaps and NO
    // wl_surface.commit. The pending empty/reduced blur region sits in KWin unapplied
    // until an unrelated periodic timer fires (e.g. 2000ms background audio polling),
    // causing a visible blur layer to float in place for up to 2 seconds after drawer close.
    //
    // The Active Commit Pump solves this at the protocol boundary:
    // 1. While any drawer offsetProgress is in transit (0.0001 < progress < 0.9999),
    //    or while commitFlushTimer is running (400ms post-close window), the pump is active.
    // 2. While active, commitPumpItem alternates opacity on vsync via FrameAnimation,
    //    dirtying a 1x1 subpixel (#01000000) so Qt Quick renders and Mesa EGL commits
    //    wl_surface.commit on EVERY frame in real-time.
    // 3. Any change in blur active states or drawer visibility restarts commitFlushTimer,
    //    guaranteeing that the compositor clears blur synchronously with zero residual lag.
    // 4. When idle, the animation and timer are stopped, consuming 0.0% CPU.
    Timer {
        id: commitFlushTimer
        interval: 700
        repeat: false
        running: false
    }

    function flushCommitPump(ms) {
        const dur = (ms !== undefined && ms > 0) ? ms : 700;
        commitFlushTimer.interval = dur;
        if (!commitFlushTimer.running) {
            commitFlushTimer.start();
        } else {
            commitFlushTimer.restart();
        }
    }

    readonly property bool isCommitPumpActive: commitFlushTimer.running
        || (dropdownContainer.offsetProgress > 0.0001 && dropdownContainer.offsetProgress < 0.9999)
        || (fusedBottomPopoutWrapper.offsetProgress > 0.0001 && fusedBottomPopoutWrapper.offsetProgress < 0.9999)
        || (rightEdgeControlWrapper.offsetProgress > 0.0001 && rightEdgeControlWrapper.offsetProgress < 0.9999)
        || (Math.abs(dropdownContainer.offsetProgress - (dropdownContainer.isOpen ? 1.0 : 0.0)) > 0.001)
        || (Math.abs(fusedBottomPopoutWrapper.offsetProgress - (Config.bottomPopoutVisible ? 1.0 : 0.0)) > 0.001)
        || (Math.abs(rightEdgeControlWrapper.offsetProgress - (Config.rightEdgeControlVisible ? 1.0 : 0.0)) > 0.001)

    onIsCommitPumpActiveChanged: {
        if (typeof Config !== "undefined" && Config.debugMode) {
            console.log("[CommitPump] isCommitPumpActive=" + isCommitPumpActive
                + " flushTimer=" + commitFlushTimer.running
                + " dropProg=" + dropdownContainer.offsetProgress.toFixed(3)
                + " popProg=" + fusedBottomPopoutWrapper.offsetProgress.toFixed(3));
        }
    }

    onBlurRegionActiveChanged: flushCommitPump(700)
    onBlurPopoutActiveChanged: flushCommitPump(700)
    onBlurRightEdgeActiveChanged: flushCommitPump(700)

    Connections {
        target: Config
        function onDashboardVisibleChanged() {
            root.flushCommitPump(700);
        }
        function onBottomPopoutVisibleChanged() {
            root.flushCommitPump(700);
        }
        function onRightEdgeControlVisibleChanged() {
            root.flushCommitPump(700);
        }
    }

    Connections {
        target: dropdownContainer
        function onOffsetProgressChanged() {
            if (dropdownContainer.offsetProgress <= 0.001 && !dropdownContainer.isOpen) {
                root.flushCommitPump(250);
            }
        }
    }
    Connections {
        target: fusedBottomPopoutWrapper
        function onOffsetProgressChanged() {
            if (fusedBottomPopoutWrapper.offsetProgress <= 0.001 && !Config.bottomPopoutVisible) {
                root.isFusedToBottom = false;
                root.flushCommitPump(250);
            }
        }
    }
    Connections {
        target: rightEdgeControlWrapper
        function onOffsetProgressChanged() {
            if (rightEdgeControlWrapper.offsetProgress <= 0.001 && !Config.rightEdgeControlVisible) {
                root.flushCommitPump(250);
            }
        }
    }

    // Bottom Popout Geometry & Domain Fusion Math
    readonly property real currentPopW: (typeof fusedPopout !== "undefined" ? fusedPopout.popWidth : 280) * fusedBottomPopoutWrapper.offsetProgress
    readonly property real popoutH: (typeof fusedPopout !== "undefined" ? fusedPopout.implicitHeight : 240)

    // Right Edge Volume/Brightness Control Geometry
    readonly property real rightControlW: 60
    readonly property real rightControlH: 280
    readonly property real rightControlY: Math.round((root.height - rightControlH) / 2)
    readonly property real currentRightW: root.rightControlW * rightEdgeControlWrapper.offsetProgress

    // Domain Rules:
    // Status drawers originating from bottom dock group (Power, Battery/Profiles) or near bottom
    // clamp flush to the bottom border (root.height - root.borderT - root.popoutH) with zero gap.
    readonly property bool isPopoutFusedBottom: {
        if (Config.bottomPopoutMode === "power" || Config.bottomPopoutMode === "battery" || Config.bottomPopoutMode === "default") {
            return true;
        }
        let targetCenter = Config.popoutTargetY;
        if (targetCenter <= 0) return false;
        return (targetCenter >= root.height - root.borderT - 180) || ((targetCenter + root.popoutH / 2) >= (root.height - root.borderT - 2));
    }

    readonly property real popoutHeaderCenterY: {
        if (typeof fusedPopout === "undefined" || !fusedPopout) return 49.5;
        if (Config.bottomPopoutMode === "app") {
            return fusedPopout.appIconCenterY;
        }
        if (Config.bottomPopoutMode === "tray") {
            return fusedPopout.trayIconCenterY;
        }
        return root.popoutH / 2;
    }

    readonly property real idealPopoutY: {
        if (isPopoutFusedBottom) {
            return root.height - root.borderT - root.popoutH;
        }
        let targetCenter = Config.popoutTargetY;
        if (targetCenter <= 50) {
            return Math.round(root.height / 2 - root.popoutH / 2);
        }
        // For app and tray drawers, anchor the drawer header icon to the dock item center so both icons align on the exact same line.
        const headerOffsetY = (Config.bottomPopoutMode === "app" || Config.bottomPopoutMode === "tray")
            ? root.popoutHeaderCenterY
            : (root.popoutH / 2);
        const desiredY = targetCenter - headerOffsetY;
        const minY = root.borderT + 40;
        const maxY = root.height - root.borderT - root.popoutH - 20;
        return Math.max(minY, Math.min(maxY, desiredY));
    }

    // Fusion State Policy:
    // Only fuse once the drawer has physically arrived at the bottom border.
    // While in flight from a mid-dock icon, keep it floating to prevent premature shape deformation.
    // Once docked, latch until the user selects a floating icon (!isPopoutFusedBottom) or closes the drawer.
    readonly property real popoutDistToBottom: Math.max(0, (root.height - root.borderT) - (fusedBottomPopoutWrapper.y + fusedBottomPopoutWrapper.height))
    readonly property bool isPopoutAtBottom: isPopoutFusedBottom && Config.bottomPopoutVisible && ((fusedBottomPopoutWrapper.offsetProgress <= 0.01) || (popoutDistToBottom <= 3.0))

    property bool isFusedToBottom: false

    onIsPopoutAtBottomChanged: {
        if (isPopoutAtBottom) {
            isFusedToBottom = true;
        } else if (!isPopoutFusedBottom && Config.bottomPopoutVisible) {
            isFusedToBottom = false;
        }
    }

    Connections {
        target: Config
        function onBottomPopoutVisibleChanged() {
            // Keep isFusedToBottom latched while closing!
            // When closing, isFusedToBottom is reset only after fusedBottomPopoutWrapper.offsetProgress <= 0.001
        }
        function onBottomPopoutModeChanged() {
            if (!isPopoutFusedBottom) {
                isFusedToBottom = false;
            }
        }
    }

    readonly property real fusedProgress: isFusedToBottom ? 1.0 : 0.0
    readonly property color borderColor: Colors.glassBorderSpecular
    readonly property color glassFill: (typeof Colors !== "undefined" && Colors.glassSurface) ? Colors.glassSurface : Qt.rgba(0.06, 0.08, 0.12, 0.70)

    Component.onCompleted: {
        if (Config.debugMode) {
            DebugService.log("Shell", "UnifiedShell initialized with Debug Mode active");
        }
    }

    // Domain Policy: Central Dropdown Dashboard Hover & Auto-Close
    readonly property alias topEdgeHoverAreaItem: topEdgeHoverArea
    readonly property alias topEdgeMouseAreaItem: topEdgeMouseArea
    readonly property bool isDashboardHovered: (dropdownContainer ? dropdownContainer.isHovered : false) || (typeof topEdgeMouseArea !== "undefined" && topEdgeMouseArea.containsMouse)

    onIsDashboardHoveredChanged: {
        if (isDashboardHovered) {
            closeTimer.stop();
        } else if (Config.dashboardVisible) {
            closeTimer.restart();
        }
    }

    Connections {
        target: Config
        function onDashboardVisibleChanged() {
            if (!Config.dashboardVisible) {
                closeTimer.stop();
            }
        }
    }

    // Auto-close grace timer when leaving the dropdown
    Timer {
        id: closeTimer
        interval: 350
        repeat: false
        onTriggered: {
            if (Config.debugMode) return;
            if (!root.isDashboardHovered) {
                Config.dashboardVisible = false;
            }
        }
    }

    // Input mask: only accept clicks inside the dock, border frame, open dashboard, or active popout
    mask: Region {
        // Left Dock
        Region {
            x: 0
            y: 0
            width: Config.dockEnabled ? root.dockW : 0
            height: root.height
        }

        // Top Border / Top Hover Area (Targeted strictly to central drawer range)
        Region {
            x: root.dropX
            y: 0
            width: root.dropW
            height: Math.max(root.borderT, 18)
        }

        // Right Border / Right Edge Hover Area (Targeted to volume control drawer bounds)
        Region {
            x: root.width - Math.max(root.borderT, 16)
            y: root.rightControlY - 20
            width: Math.max(root.borderT, 16)
            height: root.rightControlH + 40
        }

        // Thin Right Border Line (Top Segment outside drawer trigger)
        Region {
            x: root.width - root.borderT
            y: 0
            width: root.borderT
            height: Math.max(0, root.rightControlY - 20)
        }

        // Thin Right Border Line (Bottom Segment outside drawer trigger)
        Region {
            x: root.width - root.borderT
            y: root.rightControlY + root.rightControlH + 20
            width: root.borderT
            height: Math.max(0, root.height - (root.rightControlY + root.rightControlH + 20))
        }

        // Bottom Border
        Region {
            x: 0
            y: root.height - root.borderT
            width: root.width
            height: root.borderT
        }


        // Fused Bottom Popout Drawer (App previews, tray, network, bluetooth, audio, power, clock)
        Region {
            x: root.dockW
            y: (Config.bottomPopoutVisible && fusedBottomPopoutWrapper.offsetProgress > 0.001)
                ? Math.max(0, fusedBottomPopoutWrapper.y - root.filletR)
                : 0
            width: (Config.bottomPopoutVisible && fusedBottomPopoutWrapper.offsetProgress > 0.001)
                ? (Math.max(root.currentPopW, (typeof fusedPopout !== "undefined" ? fusedPopout.popWidth : 350)) + root.filletR)
                : 0
            height: (Config.bottomPopoutVisible && fusedBottomPopoutWrapper.offsetProgress > 0.001)
                ? (fusedBottomPopoutWrapper.height + root.filletR * 2)
                : 0
        }

        // Central Fused Dropdown Dashboard & Backdrop Scrim (when open)
        Region {
            x: 0
            y: 0
            width: dropdownContainer.offsetProgress > 0.001 ? root.width : 0
            height: dropdownContainer.offsetProgress > 0.001 ? root.height : 0
        }


        // Right Edge Volume/Brightness Control (when open, including shoulder fillets)
        Region {
            x: rightEdgeControlWrapper.offsetProgress > 0.001
                ? (root.width - root.borderT - root.rightControlW * rightEdgeControlWrapper.offsetProgress)
                : 0
            y: rightEdgeControlWrapper.offsetProgress > 0.001
                ? (root.rightControlY - root.filletR * rightEdgeControlWrapper.offsetProgress)
                : 0
            width: rightEdgeControlWrapper.offsetProgress > 0.001
                ? (root.rightControlW * rightEdgeControlWrapper.offsetProgress + root.borderT)
                : 0
            height: rightEdgeControlWrapper.offsetProgress > 0.001
                ? (root.rightControlH + root.filletR * 2 * rightEdgeControlWrapper.offsetProgress)
                : 0
        }

        // System Notifications Popup
        Region {
            x: (notifPopup.visible && !notifPopup.isDismissed) ? Math.max(0, root.width - notifPopup.width) : 0
            y: 0
            width: (notifPopup.visible && !notifPopup.isDismissed) ? notifPopup.width : 0
            height: (notifPopup.visible && !notifPopup.isDismissed) ? notifPopup.height : 0
        }

        // App Context Menu or Tray Context Menu (when open)
        Region {
            x: 0
            y: 0
            width: (appContextMenu.visible || trayContextMenu.visible) ? root.width : 0
            height: (appContextMenu.visible || trayContextMenu.visible) ? root.height : 0
        }

        // Power Confirmation Dialog Input Mask (Modal scrim & dialog card)
        Region {
            x: 0
            y: 0
            width: (typeof PowerService !== "undefined" && PowerService && PowerService.confirmDialogVisible) ? root.width : 0
            height: (typeof PowerService !== "undefined" && PowerService && PowerService.confirmDialogVisible) ? root.height : 0
        }
    }

    // Backdrop scrim strength. Kept deliberately light: a heavy scrim multiplies
    // with the glass alpha and flattens the compositor blur into a dimmed wall,
    // which is what makes the dashboard read as opaque. Bounded by the glass
    // contrast contract in tests/tst_glass_contrast_contract.qml.
    readonly property real scrimOpacity: (typeof Colors !== "undefined" && Colors.isDarkMode) ? 0.08 : 0.06

    // 0. CENTRAL DROPDOWN BACKDROP SCRIM (Soft contrast shield & click-to-dismiss)
    Rectangle {
        id: dropdownScrim
        anchors.fill: parent
        visible: dropdownContainer.offsetProgress > 0.001
        opacity: dropdownContainer.offsetProgress * root.scrimOpacity
        color: "#000000"

        MouseArea {
            anchors.fill: parent
            onClicked: {
                if (typeof Config !== "undefined") {
                    Config.dashboardVisible = false;
                }
            }
        }
    }

    // 1. DESKTOP BORDER FRAME & INNER FILLETS
    UnifiedFrame {
        id: desktopFrame
        enablePopoutSurface: false
        dockW: root.dockW
        borderT: root.borderT
        filletR: root.filletR
        borderColor: root.borderColor
        notifHeight: (notifPopup.visible && !notifPopup.isDismissed) ? notifPopup.height : 74

        dropX: root.dropX
        dropW: root.dropW
        currentDropH: root.currentDropH
        dropdownOffsetProgress: dropdownContainer.offsetProgress

        currentPopW: root.currentPopW
        popoutY: fusedBottomPopoutWrapper.y
        popoutHeight: fusedBottomPopoutWrapper.height
        popoutOffsetProgress: fusedBottomPopoutWrapper.offsetProgress
        fusedProgress: root.fusedProgress

        rightControlW: root.rightControlW
        rightControlH: root.rightControlH
        rightControlY: root.rightControlY
        rightControlOffsetProgress: rightEdgeControlWrapper.offsetProgress
    }

    // 2. TOP EDGE HOVER AREA FOR CENTRAL DROPDOWN TRIGGER (Targeted strictly to drawer range)
    Item {
        id: topEdgeHoverArea
        x: root.dropX
        y: 0
        width: root.dropW
        height: Math.max(root.borderT, 18)
        z: 900

        MouseArea {
            id: topEdgeMouseArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: {
                if (Config.dashboardShowOnHover) {
                    closeTimer.stop();
                    Config.dashboardVisible = true;
                }
            }
            onClicked: {
                Config.dashboardVisible = !Config.dashboardVisible;
                if (!Config.dashboardVisible) {
                    closeTimer.stop();
                }
            }
        }
    }

    // 2b. RIGHT BORDER EDGE HOVER AREA FOR VOLUME & BRIGHTNESS TRIGGER
    Item {
        id: rightEdgeHoverArea
        x: root.width - Math.max(root.borderT, 16)
        y: root.rightControlY - 20
        width: Math.max(root.borderT, 16)
        height: root.rightControlH + 40
        z: 900

        HoverHandler {
            id: rightEdgeHover
            onHoveredChanged: {
                if (hovered) {
                    Config.openRightEdgeControl();
                } else if (!rightEdgeControlWrapper.isHovered) {
                    Config.scheduleCloseRightEdgeControl();
                }
            }
        }
    }

    // 3. CENTRAL DROPDOWN DASHBOARD
    CentralDropdown {
        id: dropdownContainer
        dropX: root.dropX
        dropW: root.dropW
    }

    // 4. TASKBAR APP CONTEXT MENU
    AppContextMenu {
        id: appContextMenu
        dockW: root.dockW
        screenH: root.height
        onMenuCardVisibleChanged: root.flushCommitPump(400)
    }

    // 4b. SYSTEM TRAY CONTEXT MENU
    TrayContextMenu {
        id: trayContextMenu
        dockW: root.dockW
        screenH: root.height
        onMenuCardVisibleChanged: root.flushCommitPump(400)
    }

    // 5. SYSTEM NOTIFICATIONS POPUP (TOP-RIGHT FUSED)
    NotificationPopup {
        id: notifPopup
        x: Math.max(0, root.width - width)
        y: 0
        z: 1000
        visible: NotificationService.hasNotification
        onVisibleChanged: root.flushCommitPump(400)
        summary: NotificationService.currentSummary
        body: NotificationService.currentBody
        appName: NotificationService.currentAppName
        materialIcon: NotificationService.currentIcon
        iconSource: (NotificationService.currentIcon && (NotificationService.currentIcon.indexOf("/") !== -1 || NotificationService.currentIcon.indexOf("file:") !== -1)) ? NotificationService.currentIcon : ""
        imageSource: (NotificationService.currentImage && NotificationService.currentImage.length > 0) ? NotificationService.currentImage : ((NotificationService.currentIcon && (NotificationService.currentIcon.indexOf("/") !== -1 || NotificationService.currentIcon.indexOf("file:") !== -1)) ? NotificationService.currentIcon : "")
        onClosed: {
            NotificationService.dismiss();
        }
    }

    // 5b. BOTTOM-RIGHT AI ACTIVITY MATRIX BORDER EFFECT & GROWING LIGHTING
    // Strictly stays within the screen frame's 14px border thickness (NO physical border growth).
    // Features:
    // 1. Matrix digital rain streaming along bottom & right borders with leading phosphor white heads
    // 2. Ambient background lighting blooming into the desktop backdrop
    // 3. Smooth border color degradation merging seamlessly with resting desktop frame
    // 4. Integrated digital monospace HUD badge showing model name, RPM, and dancing pulses
    MatrixBorderEffect {
        id: aiMatrixBorderEffect
        anchors.fill: parent
        z: 950
        borderT: root.borderT
        cornerFilletR: root.cornerFilletR
        active: (typeof Config !== "undefined" && Config.modelActivityEffect)
            && (typeof AiActivityService !== "undefined")
            && AiActivityService.isActive
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

    // 6. LEFT DOCK CONTENT
    Item {
        id: dockArea
        visible: Config.dockEnabled
        x: 0
        y: root.borderT + 6
        width: root.dockW
        height: root.height - root.borderT * 2 - 12

        UnifiedDock {
            anchors.fill: parent
            iconS: root.iconS
            onRequestContextMenu: (app, globalY) => appContextMenu.show(app, globalY)
            onRequestTrayContextMenu: (item, globalY) => trayContextMenu.show(item, globalY)
        }
    }

    // 7. FUSED BOTTOM POPOUT (BATTERY/PROFILES, BLUETOOTH, POWER, ETC.)
    Item {
        id: fusedBottomPopoutWrapper
        x: root.dockW
        y: root.idealPopoutY
        width: root.currentPopW
        height: fusedPopout.implicitHeight
        visible: offsetProgress > 0.001
        clip: false
        z: 1000

        property real offsetProgress: Config.bottomPopoutVisible ? 1.0 : 0.0

        Behavior on offsetProgress {
            NumberAnimation {
                duration: Theme.animExpressiveDefaultSpatial
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.curveExpressiveDefaultSpatial
            }
        }

        Behavior on y {
            enabled: fusedBottomPopoutWrapper.offsetProgress > 0.01
            NumberAnimation {
                duration: 140
                easing.type: Easing.OutCubic
            }
        }

        Behavior on height {
            NumberAnimation {
                duration: 160
                easing.type: Easing.OutCubic
            }
        }

        HoverHandler {
            id: bottomPopoutHover
            onHoveredChanged: {
                if (hovered) {
                    Config.keepBottomPopout();
                } else {
                    Config.scheduleCloseBottomPopout();
                }
            }
        }

        // Encapsulated Glass Surface & Fillets (Unified visual hierarchy with content)
        Item {
            id: popoutSurface
            readonly property real filletFactor: Math.max(0.0, Math.min(1.0, fusedBottomPopoutWrapper.width / Math.max(1, root.filletR)))
            readonly property real currentFilletR: root.filletR * filletFactor
            readonly property real currentModalR: root.filletR * filletFactor
            readonly property real topR: root.filletR
            readonly property real botR: (root.fusedProgress > 0.5) ? 0 : root.filletR
            readonly property real effectiveR: (root.fusedProgress > 0.5) ? 0 : currentModalR
            readonly property real bodyW: fusedBottomPopoutWrapper.width + 1
            readonly property real fusedBottomFilletR: (root.fusedProgress > 0.5) ? currentFilletR : 0

            x: -1
            y: -topR
            width: bodyW + fusedBottomFilletR
            height: fusedBottomPopoutWrapper.height + topR + botR
            visible: fusedBottomPopoutWrapper.offsetProgress > 0.001
            opacity: fusedBottomPopoutWrapper.offsetProgress

            // 1A. Solid Glass Surface Fill Shape (Floating drawer with inverted shoulder fillets)
            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.GeometryRenderer
                visible: popoutSurface.filletFactor > 0.01 && root.fusedProgress <= 0.5

                ShapePath {
                    fillColor: root.glassFill
                    strokeColor: "transparent"
                    strokeWidth: 0

                    startX: 0
                    startY: 0

                    PathLine { x: 0; y: 0 }
                    PathArc {
                        x: popoutSurface.currentFilletR
                        y: popoutSurface.topR
                        radiusX: Math.max(0.1, popoutSurface.currentFilletR)
                        radiusY: Math.max(0.1, popoutSurface.topR)
                        direction: PathArc.Counterclockwise
                    }
                    PathLine {
                        x: Math.max(popoutSurface.currentFilletR, popoutSurface.bodyW - popoutSurface.currentModalR)
                        y: popoutSurface.topR
                    }
                    PathArc {
                        x: popoutSurface.bodyW
                        y: popoutSurface.topR + popoutSurface.currentModalR
                        radiusX: Math.max(0.1, popoutSurface.currentModalR)
                        radiusY: Math.max(0.1, popoutSurface.currentModalR)
                        direction: PathArc.Clockwise
                    }
                    PathLine {
                        x: popoutSurface.bodyW
                        y: Math.max(popoutSurface.topR + popoutSurface.currentModalR, popoutSurface.topR + fusedBottomPopoutWrapper.height - popoutSurface.currentModalR)
                    }
                    PathArc {
                        x: Math.max(popoutSurface.currentFilletR, popoutSurface.bodyW - popoutSurface.currentModalR)
                        y: popoutSurface.topR + fusedBottomPopoutWrapper.height
                        radiusX: Math.max(0.1, popoutSurface.currentModalR)
                        radiusY: Math.max(0.1, popoutSurface.currentModalR)
                        direction: PathArc.Clockwise
                    }
                    PathLine {
                        x: popoutSurface.currentFilletR
                        y: popoutSurface.topR + fusedBottomPopoutWrapper.height
                    }
                    PathArc {
                        x: 0
                        y: popoutSurface.height
                        radiusX: Math.max(0.1, popoutSurface.botR)
                        radiusY: Math.max(0.1, popoutSurface.botR)
                        direction: PathArc.Counterclockwise
                    }
                    PathLine {
                        x: 1
                        y: popoutSurface.height - popoutSurface.botR
                    }
                    PathLine {
                        x: 1
                        y: popoutSurface.topR
                    }
                    PathLine {
                        x: 0
                        y: 0
                    }
                }
            }

            // 1B. Solid Glass Surface Fill Shape (Bottom-fused drawer)
            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.GeometryRenderer
                visible: popoutSurface.filletFactor > 0.01 && root.fusedProgress > 0.5

                ShapePath {
                    fillColor: root.glassFill
                    strokeColor: "transparent"
                    strokeWidth: 0

                    startX: 0
                    startY: 0

                    PathLine { x: 0; y: 0 }
                    PathArc {
                        x: popoutSurface.currentFilletR
                        y: popoutSurface.topR
                        radiusX: Math.max(0.1, popoutSurface.currentFilletR)
                        radiusY: Math.max(0.1, popoutSurface.topR)
                        direction: PathArc.Counterclockwise
                    }
                    PathLine {
                        x: Math.max(popoutSurface.currentFilletR, popoutSurface.bodyW - popoutSurface.currentModalR)
                        y: popoutSurface.topR
                    }
                    PathArc {
                        x: popoutSurface.bodyW
                        y: popoutSurface.topR + popoutSurface.currentModalR
                        radiusX: Math.max(0.1, popoutSurface.currentModalR)
                        radiusY: Math.max(0.1, popoutSurface.currentModalR)
                        direction: PathArc.Clockwise
                    }
                    PathLine {
                        x: popoutSurface.bodyW
                        y: popoutSurface.height - popoutSurface.fusedBottomFilletR
                    }
                    PathArc {
                        x: popoutSurface.bodyW + popoutSurface.fusedBottomFilletR
                        y: popoutSurface.height
                        radiusX: Math.max(0.1, popoutSurface.fusedBottomFilletR)
                        radiusY: Math.max(0.1, popoutSurface.fusedBottomFilletR)
                        direction: PathArc.Counterclockwise
                    }
                    PathLine {
                        x: 1
                        y: popoutSurface.height
                    }
                    PathLine {
                        x: 1
                        y: popoutSurface.topR
                    }
                    PathLine {
                        x: 0
                        y: 0
                    }
                }
            }

            // 2A. Floating Continuous 1px Perimeter Stroke (Inverted shoulder fillets + outer rounded corners)
            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.GeometryRenderer
                visible: popoutSurface.filletFactor > 0.01 && root.fusedProgress <= 0.5

                ShapePath {
                    fillColor: "transparent"
                    strokeColor: root.borderColor
                    strokeWidth: 1
                    capStyle: ShapePath.FlatCap

                    startX: 0
                    startY: 0

                    PathArc {
                        x: popoutSurface.currentFilletR
                        y: popoutSurface.topR
                        radiusX: Math.max(0.1, popoutSurface.currentFilletR)
                        radiusY: Math.max(0.1, popoutSurface.topR)
                        direction: PathArc.Counterclockwise
                    }
                    PathLine {
                        x: Math.max(popoutSurface.currentFilletR, popoutSurface.bodyW - popoutSurface.currentModalR)
                        y: popoutSurface.topR
                    }
                    PathArc {
                        x: popoutSurface.bodyW
                        y: popoutSurface.topR + popoutSurface.currentModalR
                        radiusX: Math.max(0.1, popoutSurface.currentModalR)
                        radiusY: Math.max(0.1, popoutSurface.currentModalR)
                        direction: PathArc.Clockwise
                    }
                    PathLine {
                        x: popoutSurface.bodyW
                        y: Math.max(popoutSurface.topR + popoutSurface.currentModalR, popoutSurface.topR + fusedBottomPopoutWrapper.height - popoutSurface.currentModalR)
                    }
                    PathArc {
                        x: Math.max(popoutSurface.currentFilletR, popoutSurface.bodyW - popoutSurface.currentModalR)
                        y: popoutSurface.topR + fusedBottomPopoutWrapper.height
                        radiusX: Math.max(0.1, popoutSurface.currentModalR)
                        radiusY: Math.max(0.1, popoutSurface.currentModalR)
                        direction: PathArc.Clockwise
                    }
                    PathLine {
                        x: popoutSurface.currentFilletR
                        y: popoutSurface.topR + fusedBottomPopoutWrapper.height
                    }
                    PathArc {
                        x: 0
                        y: popoutSurface.height
                        radiusX: Math.max(0.1, popoutSurface.botR)
                        radiusY: Math.max(0.1, popoutSurface.botR)
                        direction: PathArc.Counterclockwise
                    }
                }
            }

            // 2B. Bottom-Fused Continuous 1px Perimeter Stroke (Top shoulder fillet + top-right corner + bottom-right concave fillet)
            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.GeometryRenderer
                visible: popoutSurface.filletFactor > 0.01 && root.fusedProgress > 0.5

                ShapePath {
                    fillColor: "transparent"
                    strokeColor: root.borderColor
                    strokeWidth: 1
                    capStyle: ShapePath.FlatCap

                    startX: 0
                    startY: 0

                    PathArc {
                        x: popoutSurface.currentFilletR
                        y: popoutSurface.topR
                        radiusX: Math.max(0.1, popoutSurface.currentFilletR)
                        radiusY: Math.max(0.1, popoutSurface.topR)
                        direction: PathArc.Counterclockwise
                    }
                    PathLine {
                        x: Math.max(popoutSurface.currentFilletR, popoutSurface.bodyW - popoutSurface.currentModalR)
                        y: popoutSurface.topR
                    }
                    PathArc {
                        x: popoutSurface.bodyW
                        y: popoutSurface.topR + popoutSurface.currentModalR
                        radiusX: Math.max(0.1, popoutSurface.currentModalR)
                        radiusY: Math.max(0.1, popoutSurface.currentModalR)
                        direction: PathArc.Clockwise
                    }
                    PathLine {
                        x: popoutSurface.bodyW
                        y: popoutSurface.height - popoutSurface.fusedBottomFilletR
                    }
                    PathArc {
                        x: popoutSurface.bodyW + popoutSurface.fusedBottomFilletR
                        y: popoutSurface.height
                        radiusX: Math.max(0.1, popoutSurface.fusedBottomFilletR)
                        radiusY: Math.max(0.1, popoutSurface.fusedBottomFilletR)
                        direction: PathArc.Counterclockwise
                    }
                }
            }
        }

        Item {
            id: popoutContentContainer
            anchors.left: parent.left
            anchors.top: parent.top
            width: fusedBottomPopoutWrapper.width
            height: parent.height
            clip: true
            opacity: fusedBottomPopoutWrapper.offsetProgress

            FusedBottomPopout {
                id: fusedPopout
                anchors.left: parent.left
                anchors.top: parent.top
                width: fusedPopout.popWidth
                mode: Config.bottomPopoutMode
            }
        }
    }

    // 8. RIGHT BORDER EDGE VOLUME & BRIGHTNESS CONTROL TAB (Mirror of fusedBottomPopoutWrapper)
    Item {
        id: rightEdgeControlWrapper
        x: root.width - root.borderT - root.currentRightW
        y: root.rightControlY
        width: root.currentRightW
        height: root.rightControlH
        visible: offsetProgress > 0.001
        clip: true
        z: 950

        property real offsetProgress: Config.rightEdgeControlVisible ? 1.0 : 0.0
        readonly property bool isHovered: rightControlHover.hovered
        opacity: Math.min(1.0, offsetProgress * 1.5)

        Behavior on offsetProgress {
            NumberAnimation {
                duration: Theme.animExpressiveDefaultSpatial
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.curveExpressiveDefaultSpatial
            }
        }

        HoverHandler {
            id: rightControlHover
            onHoveredChanged: {
                if (hovered) {
                    Config.keepRightEdgeControl();
                } else if (!rightEdgeHover.hovered) {
                    Config.scheduleCloseRightEdgeControl();
                }
            }
        }

        Item {
            id: rightControlContentContainer
            anchors.right: parent.right
            anchors.rightMargin: (-root.rightControlW - 5) * (1.0 - rightEdgeControlWrapper.offsetProgress)
            anchors.top: parent.top
            width: root.rightControlW
            height: root.rightControlH

            RightEdgeControl {
                anchors.fill: parent
            }
        }
    }

    // Focus restoration after the power-confirmation modal.
    //
    // Requesting keyboard focus on this full-screen layer surface makes KWin
    // activate it (necessary for the modal's Enter/Escape handling), but KWin
    // does not hand activation back when the request is withdrawn. Left alone,
    // the compositor keeps the invisible shell surface as its active window, so
    // the dock's active-app display freezes on a stale application. Handing
    // activation back explicitly, once the modal is gone, closes that loop.
    Process {
        id: focusRestoreProc
    }

    Connections {
        target: (typeof PowerService !== "undefined") ? PowerService : null
        function onConfirmDialogVisibleChanged() {
            if (!PowerService.confirmDialogVisible) {
                focusRestoreProc.command = [Config.daemonBin, "focus", "restore"];
                focusRestoreProc.running = true;
            }
        }
    }

    // 9. CENTRAL TRANSLUCENT VOLUME OSD (~0.6 transparency, macOS style)
    VolumeOsd {
        id: volumeOsd
        anchors.centerIn: parent
        z: 1100
    }

    // 10. POWER CONFIRMATION DIALOG (LOGOUT / RESTART / SHUTDOWN)
    PowerConfirmDialog {
        id: powerConfirmDialog
        anchors.fill: parent
        z: 2000
    }

    // 11. ACTIVE FRAME COMMIT PUMP & DRAWER DAMAGE EMITTER FOR WAYLAND BLUR SYNCHRONIZATION
    // In Wayland compositing (KWin), set_blur_region is double-buffered client state applied
    // strictly upon wl_surface.commit. Furthermore, KWin tracks damage regions to selectively
    // repaint the screen. If a drawer closes and its items become invisible (visible: false),
    // Qt Quick stops damaging that screen area. Without client buffer damage covering the
    // closed drawer bounding box, KWin skips redrawing the desktop background behind it, leaving
    // stale blurred pixels in the framebuffer until an unrelated periodic timer fires.
    //
    // The Active Damage Pump guarantees:
    // 1. Full bounding-box damage coverage across all drawer regions (Central Dropdown,
    //    Fused Bottom Popout, and Right Edge Control) while in transit and during the post-close window.
    // 2. Continuous frame rendering and vsync commits (via FrameAnimation) while active.
    // 3. Invisible alternating alpha quads (#01000000 vs #02000000) that force Mesa EGL to emit
    //    wl_surface.damage_buffer covering the exact vacated areas.
    // 4. Zero CPU consumption when idle (running: root.isCommitPumpActive).
    Item {
        id: commitPumpItem
        z: -9999
        visible: root.isCommitPumpActive

        property bool pumpToggle: false

        // 1. Central Dropdown Dashboard vacating damage rect
        Rectangle {
            x: root.dropX - root.filletR
            y: 0
            width: root.dropW + root.filletR * 2
            height: Math.max(root.borderT, root.targetDropH + root.filletR)
            color: commitPumpItem.pumpToggle ? "#01000000" : "#02000000"
        }

        // 2. Fused / Floating Bottom Popout vacating damage rect
        Rectangle {
            x: root.dockW
            y: Math.max(0, root.idealPopoutY - root.filletR)
            width: (typeof fusedPopout !== "undefined" ? fusedPopout.popWidth : 350) + root.filletR * 2
            height: root.popoutH + root.filletR * 2
            color: commitPumpItem.pumpToggle ? "#01000000" : "#02000000"
        }

        // 3. Right Edge Control vacating damage rect
        Rectangle {
            x: root.width - root.borderT - root.rightControlW - root.filletR
            y: root.rightControlY - root.filletR
            width: root.rightControlW + root.borderT + root.filletR
            height: root.rightControlH + root.filletR * 2
            color: commitPumpItem.pumpToggle ? "#01000000" : "#02000000"
        }

        FrameAnimation {
            running: root.isCommitPumpActive
            onTriggered: {
                commitPumpItem.pumpToggle = !commitPumpItem.pumpToggle;
            }
        }
    }
}
