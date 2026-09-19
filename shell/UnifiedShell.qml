import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
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
    WlrLayershell.keyboardFocus: (PowerService.confirmDialogVisible || dropdownContainer.offsetProgress > 0.001 || Config.bottomPopoutVisible) ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    WlrLayershell.exclusionMode: ExclusionMode.Ignore

    // Wayland Native Compositor Backdrop Blur for Liquid Glass
    BackgroundEffect.blurRegion: Region {
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
        Region { x: root.dockW; y: root.borderT; width: 12; height: 2 }
        Region { x: root.dockW; y: root.borderT + 2; width: 7; height: 3 }
        Region { x: root.dockW; y: root.borderT + 5; width: 4; height: 4 }
        Region { x: root.dockW; y: root.borderT + 9; width: 2; height: 5 }
        Region { x: root.dockW; y: root.borderT + 14; width: 1; height: 6 }

        // Screen Inner Fillet: Top-Right
        Region { x: root.width - root.borderT - 12; y: root.borderT; width: 12; height: 2 }
        Region { x: root.width - root.borderT - 7; y: root.borderT + 2; width: 7; height: 3 }
        Region { x: root.width - root.borderT - 4; y: root.borderT + 5; width: 4; height: 4 }
        Region { x: root.width - root.borderT - 2; y: root.borderT + 9; width: 2; height: 5 }
        Region { x: root.width - root.borderT - 1; y: root.borderT + 14; width: 1; height: 6 }

        // Screen Inner Fillet: Bottom-Left
        Region { x: root.dockW; y: root.height - root.borderT - 2; width: 12; height: 2 }
        Region { x: root.dockW; y: root.height - root.borderT - 5; width: 7; height: 3 }
        Region { x: root.dockW; y: root.height - root.borderT - 9; width: 4; height: 4 }
        Region { x: root.dockW; y: root.height - root.borderT - 14; width: 2; height: 5 }
        Region { x: root.dockW; y: root.height - root.borderT - 20; width: 1; height: 6 }

        // Screen Inner Fillet: Bottom-Right
        Region { x: root.width - root.borderT - 12; y: root.height - root.borderT - 2; width: 12; height: 2 }
        Region { x: root.width - root.borderT - 7; y: root.height - root.borderT - 5; width: 7; height: 3 }
        Region { x: root.width - root.borderT - 4; y: root.height - root.borderT - 9; width: 4; height: 4 }
        Region { x: root.width - root.borderT - 2; y: root.height - root.borderT - 14; width: 2; height: 5 }
        Region { x: root.width - root.borderT - 1; y: root.height - root.borderT - 20; width: 1; height: 6 }

        // Central Dropdown Dashboard (when open) - Inset bottom corners to match rounded card borders
        Region {
            x: dropdownContainer.offsetProgress > 0.001 ? root.dropX : 0
            y: 0
            width: dropdownContainer.offsetProgress > 0.001 ? root.dropW : 0
            height: dropdownContainer.offsetProgress > 0.001 ? Math.max(0, root.currentDropH - root.filletR) : 0
        }
        Region {
            x: dropdownContainer.offsetProgress > 0.001 ? (root.dropX + Math.round(root.filletR * 0.15)) : 0
            y: dropdownContainer.offsetProgress > 0.001 ? Math.max(0, root.currentDropH - root.filletR) : 0
            width: dropdownContainer.offsetProgress > 0.001 ? Math.max(0, root.dropW - Math.round(root.filletR * 0.30)) : 0
            height: dropdownContainer.offsetProgress > 0.001 ? Math.round(root.filletR * 0.50) : 0
        }
        Region {
            x: dropdownContainer.offsetProgress > 0.001 ? (root.dropX + Math.round(root.filletR * 0.40)) : 0
            y: dropdownContainer.offsetProgress > 0.001 ? Math.max(0, root.currentDropH - Math.round(root.filletR * 0.50)) : 0
            width: dropdownContainer.offsetProgress > 0.001 ? Math.max(0, root.dropW - Math.round(root.filletR * 0.80)) : 0
            height: dropdownContainer.offsetProgress > 0.001 ? Math.round(root.filletR * 0.30) : 0
        }
        Region {
            x: dropdownContainer.offsetProgress > 0.001 ? (root.dropX + root.filletR) : 0
            y: dropdownContainer.offsetProgress > 0.001 ? Math.max(0, root.currentDropH - Math.round(root.filletR * 0.20)) : 0
            width: dropdownContainer.offsetProgress > 0.001 ? Math.max(0, root.dropW - root.filletR * 2) : 0
            height: dropdownContainer.offsetProgress > 0.001 ? Math.round(root.filletR * 0.20) : 0
        }

        // Central Dropdown Left Shoulder Fillet
        Region {
            x: dropdownContainer.offsetProgress > 0.001 ? (root.dropX - root.filletW1) : 0
            y: dropdownContainer.offsetProgress > 0.001 ? root.borderT : 0
            width: dropdownContainer.offsetProgress > 0.001 ? root.filletW1 : 0
            height: dropdownContainer.offsetProgress > 0.001 ? Math.min(root.filletH1, Math.max(0, root.currentDropH - root.borderT)) : 0
        }
        Region {
            x: dropdownContainer.offsetProgress > 0.001 ? (root.dropX - root.filletW2) : 0
            y: dropdownContainer.offsetProgress > 0.001 ? (root.borderT + root.filletD1) : 0
            width: dropdownContainer.offsetProgress > 0.001 ? root.filletW2 : 0
            height: dropdownContainer.offsetProgress > 0.001 ? Math.min(root.filletH2, Math.max(0, root.currentDropH - root.borderT - root.filletD1)) : 0
        }
        Region {
            x: dropdownContainer.offsetProgress > 0.001 ? (root.dropX - root.filletW3) : 0
            y: dropdownContainer.offsetProgress > 0.001 ? (root.borderT + root.filletD2) : 0
            width: dropdownContainer.offsetProgress > 0.001 ? root.filletW3 : 0
            height: dropdownContainer.offsetProgress > 0.001 ? Math.min(root.filletH3, Math.max(0, root.currentDropH - root.borderT - root.filletD2)) : 0
        }
        Region {
            x: dropdownContainer.offsetProgress > 0.001 ? (root.dropX - root.filletW4) : 0
            y: dropdownContainer.offsetProgress > 0.001 ? (root.borderT + root.filletD3) : 0
            width: dropdownContainer.offsetProgress > 0.001 ? root.filletW4 : 0
            height: dropdownContainer.offsetProgress > 0.001 ? Math.min(root.filletH4, Math.max(0, root.currentDropH - root.borderT - root.filletD3)) : 0
        }
        Region {
            x: dropdownContainer.offsetProgress > 0.001 ? (root.dropX - root.filletW5) : 0
            y: dropdownContainer.offsetProgress > 0.001 ? (root.borderT + root.filletD4) : 0
            width: dropdownContainer.offsetProgress > 0.001 ? root.filletW5 : 0
            height: dropdownContainer.offsetProgress > 0.001 ? Math.min(root.filletH5, Math.max(0, root.currentDropH - root.borderT - root.filletD4)) : 0
        }
        Region {
            x: dropdownContainer.offsetProgress > 0.001 ? (root.dropX - root.filletW6) : 0
            y: dropdownContainer.offsetProgress > 0.001 ? (root.borderT + root.filletD5) : 0
            width: dropdownContainer.offsetProgress > 0.001 ? root.filletW6 : 0
            height: dropdownContainer.offsetProgress > 0.001 ? Math.min(root.filletH6, Math.max(0, root.currentDropH - root.borderT - root.filletD5)) : 0
        }
        Region {
            x: dropdownContainer.offsetProgress > 0.001 ? (root.dropX - root.filletW7) : 0
            y: dropdownContainer.offsetProgress > 0.001 ? (root.borderT + root.filletD6) : 0
            width: dropdownContainer.offsetProgress > 0.001 ? root.filletW7 : 0
            height: dropdownContainer.offsetProgress > 0.001 ? Math.min(root.filletH7, Math.max(0, root.currentDropH - root.borderT - root.filletD6)) : 0
        }

        // Central Dropdown Right Shoulder Fillet
        Region {
            x: dropdownContainer.offsetProgress > 0.001 ? (root.dropX + root.dropW) : 0
            y: dropdownContainer.offsetProgress > 0.001 ? root.borderT : 0
            width: dropdownContainer.offsetProgress > 0.001 ? root.filletW1 : 0
            height: dropdownContainer.offsetProgress > 0.001 ? Math.min(root.filletH1, Math.max(0, root.currentDropH - root.borderT)) : 0
        }
        Region {
            x: dropdownContainer.offsetProgress > 0.001 ? (root.dropX + root.dropW) : 0
            y: dropdownContainer.offsetProgress > 0.001 ? (root.borderT + root.filletD1) : 0
            width: dropdownContainer.offsetProgress > 0.001 ? root.filletW2 : 0
            height: dropdownContainer.offsetProgress > 0.001 ? Math.min(root.filletH2, Math.max(0, root.currentDropH - root.borderT - root.filletD1)) : 0
        }
        Region {
            x: dropdownContainer.offsetProgress > 0.001 ? (root.dropX + root.dropW) : 0
            y: dropdownContainer.offsetProgress > 0.001 ? (root.borderT + root.filletD2) : 0
            width: dropdownContainer.offsetProgress > 0.001 ? root.filletW3 : 0
            height: dropdownContainer.offsetProgress > 0.001 ? Math.min(root.filletH3, Math.max(0, root.currentDropH - root.borderT - root.filletD2)) : 0
        }
        Region {
            x: dropdownContainer.offsetProgress > 0.001 ? (root.dropX + root.dropW) : 0
            y: dropdownContainer.offsetProgress > 0.001 ? (root.borderT + root.filletD3) : 0
            width: dropdownContainer.offsetProgress > 0.001 ? root.filletW4 : 0
            height: dropdownContainer.offsetProgress > 0.001 ? Math.min(root.filletH4, Math.max(0, root.currentDropH - root.borderT - root.filletD3)) : 0
        }
        Region {
            x: dropdownContainer.offsetProgress > 0.001 ? (root.dropX + root.dropW) : 0
            y: dropdownContainer.offsetProgress > 0.001 ? (root.borderT + root.filletD4) : 0
            width: dropdownContainer.offsetProgress > 0.001 ? root.filletW5 : 0
            height: dropdownContainer.offsetProgress > 0.001 ? Math.min(root.filletH5, Math.max(0, root.currentDropH - root.borderT - root.filletD4)) : 0
        }
        Region {
            x: dropdownContainer.offsetProgress > 0.001 ? (root.dropX + root.dropW) : 0
            y: dropdownContainer.offsetProgress > 0.001 ? (root.borderT + root.filletD5) : 0
            width: dropdownContainer.offsetProgress > 0.001 ? root.filletW6 : 0
            height: dropdownContainer.offsetProgress > 0.001 ? Math.min(root.filletH6, Math.max(0, root.currentDropH - root.borderT - root.filletD5)) : 0
        }
        Region {
            x: dropdownContainer.offsetProgress > 0.001 ? (root.dropX + root.dropW) : 0
            y: dropdownContainer.offsetProgress > 0.001 ? (root.borderT + root.filletD6) : 0
            width: dropdownContainer.offsetProgress > 0.001 ? root.filletW7 : 0
            height: dropdownContainer.offsetProgress > 0.001 ? Math.min(root.filletH7, Math.max(0, root.currentDropH - root.borderT - root.filletD6)) : 0
        }

        // Fused Bottom Popout (when open & fused to bottom border)
        // Top-right convex corner slices (when fused to bottom)
        Region {
            x: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress > 0.5) ? root.dockW : 0
            y: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress > 0.5) ? fusedBottomPopoutWrapper.y : 0
            width: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress > 0.5) ? Math.max(0, root.currentPopW - 15) : 0
            height: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress > 0.5) ? 1 : 0
        }
        Region {
            x: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress > 0.5) ? root.dockW : 0
            y: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress > 0.5) ? (fusedBottomPopoutWrapper.y + 1) : 0
            width: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress > 0.5) ? Math.max(0, root.currentPopW - 12) : 0
            height: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress > 0.5) ? 1 : 0
        }
        Region {
            x: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress > 0.5) ? root.dockW : 0
            y: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress > 0.5) ? (fusedBottomPopoutWrapper.y + 2) : 0
            width: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress > 0.5) ? Math.max(0, root.currentPopW - 9) : 0
            height: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress > 0.5) ? 2 : 0
        }
        Region {
            x: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress > 0.5) ? root.dockW : 0
            y: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress > 0.5) ? (fusedBottomPopoutWrapper.y + 4) : 0
            width: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress > 0.5) ? Math.max(0, root.currentPopW - 5) : 0
            height: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress > 0.5) ? 3 : 0
        }
        Region {
            x: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress > 0.5) ? root.dockW : 0
            y: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress > 0.5) ? (fusedBottomPopoutWrapper.y + 7) : 0
            width: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress > 0.5) ? Math.max(0, root.currentPopW - 3) : 0
            height: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress > 0.5) ? 3 : 0
        }
        Region {
            x: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress > 0.5) ? root.dockW : 0
            y: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress > 0.5) ? (fusedBottomPopoutWrapper.y + 10) : 0
            width: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress > 0.5) ? Math.max(0, root.currentPopW - 1) : 0
            height: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress > 0.5) ? 4 : 0
        }
        Region {
            x: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress > 0.5) ? root.dockW : 0
            y: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress > 0.5) ? (fusedBottomPopoutWrapper.y + 14) : 0
            width: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress > 0.5) ? root.currentPopW : 0
            height: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress > 0.5) ? Math.max(0, (root.height - fusedBottomPopoutWrapper.y) - 14) : 0
        }

        // Floating Bottom Popout (when open & floating)
        // Top-right convex corner slices (when floating)
        Region {
            x: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress <= 0.5) ? root.dockW : 0
            y: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress <= 0.5) ? fusedBottomPopoutWrapper.y : 0
            width: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress <= 0.5) ? Math.max(0, root.currentPopW - 15) : 0
            height: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress <= 0.5) ? 1 : 0
        }
        Region {
            x: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress <= 0.5) ? root.dockW : 0
            y: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress <= 0.5) ? (fusedBottomPopoutWrapper.y + 1) : 0
            width: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress <= 0.5) ? Math.max(0, root.currentPopW - 12) : 0
            height: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress <= 0.5) ? 1 : 0
        }
        Region {
            x: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress <= 0.5) ? root.dockW : 0
            y: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress <= 0.5) ? (fusedBottomPopoutWrapper.y + 2) : 0
            width: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress <= 0.5) ? Math.max(0, root.currentPopW - 9) : 0
            height: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress <= 0.5) ? 2 : 0
        }
        Region {
            x: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress <= 0.5) ? root.dockW : 0
            y: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress <= 0.5) ? (fusedBottomPopoutWrapper.y + 4) : 0
            width: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress <= 0.5) ? Math.max(0, root.currentPopW - 5) : 0
            height: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress <= 0.5) ? 3 : 0
        }
        Region {
            x: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress <= 0.5) ? root.dockW : 0
            y: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress <= 0.5) ? (fusedBottomPopoutWrapper.y + 7) : 0
            width: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress <= 0.5) ? Math.max(0, root.currentPopW - 3) : 0
            height: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress <= 0.5) ? 3 : 0
        }
        Region {
            x: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress <= 0.5) ? root.dockW : 0
            y: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress <= 0.5) ? (fusedBottomPopoutWrapper.y + 10) : 0
            width: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress <= 0.5) ? Math.max(0, root.currentPopW - 1) : 0
            height: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress <= 0.5) ? 4 : 0
        }
        Region {
            x: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress <= 0.5) ? root.dockW : 0
            y: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress <= 0.5) ? (fusedBottomPopoutWrapper.y + 14) : 0
            width: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress <= 0.5) ? root.currentPopW : 0
            height: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress <= 0.5) ? Math.max(0, fusedBottomPopoutWrapper.height - 28) : 0
        }
        // Bottom-right convex corner slices (when floating)
        Region {
            x: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress <= 0.5) ? root.dockW : 0
            y: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress <= 0.5) ? (fusedBottomPopoutWrapper.y + fusedBottomPopoutWrapper.height - 14) : 0
            width: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress <= 0.5) ? Math.max(0, root.currentPopW - 1) : 0
            height: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress <= 0.5) ? 4 : 0
        }
        Region {
            x: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress <= 0.5) ? root.dockW : 0
            y: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress <= 0.5) ? (fusedBottomPopoutWrapper.y + fusedBottomPopoutWrapper.height - 10) : 0
            width: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress <= 0.5) ? Math.max(0, root.currentPopW - 3) : 0
            height: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress <= 0.5) ? 3 : 0
        }
        Region {
            x: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress <= 0.5) ? root.dockW : 0
            y: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress <= 0.5) ? (fusedBottomPopoutWrapper.y + fusedBottomPopoutWrapper.height - 7) : 0
            width: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress <= 0.5) ? Math.max(0, root.currentPopW - 5) : 0
            height: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress <= 0.5) ? 3 : 0
        }
        Region {
            x: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress <= 0.5) ? root.dockW : 0
            y: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress <= 0.5) ? (fusedBottomPopoutWrapper.y + fusedBottomPopoutWrapper.height - 4) : 0
            width: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress <= 0.5) ? Math.max(0, root.currentPopW - 9) : 0
            height: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress <= 0.5) ? 2 : 0
        }
        Region {
            x: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress <= 0.5) ? root.dockW : 0
            y: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress <= 0.5) ? (fusedBottomPopoutWrapper.y + fusedBottomPopoutWrapper.height - 2) : 0
            width: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress <= 0.5) ? Math.max(0, root.currentPopW - 12) : 0
            height: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress <= 0.5) ? 1 : 0
        }
        Region {
            x: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress <= 0.5) ? root.dockW : 0
            y: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress <= 0.5) ? (fusedBottomPopoutWrapper.y + fusedBottomPopoutWrapper.height - 1) : 0
            width: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress <= 0.5) ? Math.max(0, root.currentPopW - 15) : 0
            height: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress <= 0.5) ? 1 : 0
        }

        // Bottom Popout Top Shoulder Fillet (Frosted Glass Blur)
        Region {
            x: fusedBottomPopoutWrapper.offsetProgress > 0.001 ? root.dockW : 0
            y: fusedBottomPopoutWrapper.offsetProgress > 0.001 ? (fusedBottomPopoutWrapper.y - root.filletD1) : 0
            width: fusedBottomPopoutWrapper.offsetProgress > 0.001 ? Math.min(root.currentPopW, root.filletW1) : 0
            height: fusedBottomPopoutWrapper.offsetProgress > 0.001 ? root.filletH1 : 0
        }
        Region {
            x: fusedBottomPopoutWrapper.offsetProgress > 0.001 ? root.dockW : 0
            y: fusedBottomPopoutWrapper.offsetProgress > 0.001 ? (fusedBottomPopoutWrapper.y - root.filletD2) : 0
            width: fusedBottomPopoutWrapper.offsetProgress > 0.001 ? Math.min(root.currentPopW, root.filletW2) : 0
            height: fusedBottomPopoutWrapper.offsetProgress > 0.001 ? root.filletH2 : 0
        }
        Region {
            x: fusedBottomPopoutWrapper.offsetProgress > 0.001 ? root.dockW : 0
            y: fusedBottomPopoutWrapper.offsetProgress > 0.001 ? (fusedBottomPopoutWrapper.y - root.filletD3) : 0
            width: fusedBottomPopoutWrapper.offsetProgress > 0.001 ? Math.min(root.currentPopW, root.filletW3) : 0
            height: fusedBottomPopoutWrapper.offsetProgress > 0.001 ? root.filletH3 : 0
        }
        Region {
            x: fusedBottomPopoutWrapper.offsetProgress > 0.001 ? root.dockW : 0
            y: fusedBottomPopoutWrapper.offsetProgress > 0.001 ? (fusedBottomPopoutWrapper.y - root.filletD4) : 0
            width: fusedBottomPopoutWrapper.offsetProgress > 0.001 ? Math.min(root.currentPopW, root.filletW4) : 0
            height: fusedBottomPopoutWrapper.offsetProgress > 0.001 ? root.filletH4 : 0
        }
        Region {
            x: fusedBottomPopoutWrapper.offsetProgress > 0.001 ? root.dockW : 0
            y: fusedBottomPopoutWrapper.offsetProgress > 0.001 ? (fusedBottomPopoutWrapper.y - root.filletD5) : 0
            width: fusedBottomPopoutWrapper.offsetProgress > 0.001 ? Math.min(root.currentPopW, root.filletW5) : 0
            height: fusedBottomPopoutWrapper.offsetProgress > 0.001 ? root.filletH5 : 0
        }
        Region {
            x: fusedBottomPopoutWrapper.offsetProgress > 0.001 ? root.dockW : 0
            y: fusedBottomPopoutWrapper.offsetProgress > 0.001 ? (fusedBottomPopoutWrapper.y - root.filletD6) : 0
            width: fusedBottomPopoutWrapper.offsetProgress > 0.001 ? Math.min(root.currentPopW, root.filletW6) : 0
            height: fusedBottomPopoutWrapper.offsetProgress > 0.001 ? root.filletH6 : 0
        }
        Region {
            x: fusedBottomPopoutWrapper.offsetProgress > 0.001 ? root.dockW : 0
            y: fusedBottomPopoutWrapper.offsetProgress > 0.001 ? (fusedBottomPopoutWrapper.y - root.filletD7) : 0
            width: fusedBottomPopoutWrapper.offsetProgress > 0.001 ? Math.min(root.currentPopW, root.filletW7) : 0
            height: fusedBottomPopoutWrapper.offsetProgress > 0.001 ? root.filletH7 : 0
        }

        // Bottom Popout Bottom Shoulder Fillet (Frosted Glass Blur, when floating)
        Region {
            x: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress <= 0.5) ? root.dockW : 0
            y: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress <= 0.5) ? (fusedBottomPopoutWrapper.y + fusedBottomPopoutWrapper.height + root.filletD1 - root.filletH1) : 0
            width: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress <= 0.5) ? Math.min(root.currentPopW, root.filletW1) : 0
            height: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress <= 0.5) ? root.filletH1 : 0
        }
        Region {
            x: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress <= 0.5) ? root.dockW : 0
            y: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress <= 0.5) ? (fusedBottomPopoutWrapper.y + fusedBottomPopoutWrapper.height + root.filletD2 - root.filletH2) : 0
            width: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress <= 0.5) ? Math.min(root.currentPopW, root.filletW2) : 0
            height: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress <= 0.5) ? root.filletH2 : 0
        }
        Region {
            x: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress <= 0.5) ? root.dockW : 0
            y: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress <= 0.5) ? (fusedBottomPopoutWrapper.y + fusedBottomPopoutWrapper.height + root.filletD3 - root.filletH3) : 0
            width: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress <= 0.5) ? Math.min(root.currentPopW, root.filletW3) : 0
            height: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress <= 0.5) ? root.filletH3 : 0
        }
        Region {
            x: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress <= 0.5) ? root.dockW : 0
            y: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress <= 0.5) ? (fusedBottomPopoutWrapper.y + fusedBottomPopoutWrapper.height + root.filletD4 - root.filletH4) : 0
            width: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress <= 0.5) ? Math.min(root.currentPopW, root.filletW4) : 0
            height: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress <= 0.5) ? root.filletH4 : 0
        }
        Region {
            x: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress <= 0.5) ? root.dockW : 0
            y: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress <= 0.5) ? (fusedBottomPopoutWrapper.y + fusedBottomPopoutWrapper.height + root.filletD5 - root.filletH5) : 0
            width: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress <= 0.5) ? Math.min(root.currentPopW, root.filletW5) : 0
            height: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress <= 0.5) ? root.filletH5 : 0
        }
        Region {
            x: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress <= 0.5) ? root.dockW : 0
            y: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress <= 0.5) ? (fusedBottomPopoutWrapper.y + fusedBottomPopoutWrapper.height + root.filletD6 - root.filletH6) : 0
            width: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress <= 0.5) ? Math.min(root.currentPopW, root.filletW6) : 0
            height: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress <= 0.5) ? root.filletH6 : 0
        }
        Region {
            x: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress <= 0.5) ? root.dockW : 0
            y: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress <= 0.5) ? (fusedBottomPopoutWrapper.y + fusedBottomPopoutWrapper.height + root.filletD7 - root.filletH7) : 0
            width: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress <= 0.5) ? Math.min(root.currentPopW, root.filletW7) : 0
            height: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress <= 0.5) ? root.filletH7 : 0
        }

        // Bottom Popout Bottom-Right Concave Fillet (Frosted Glass Blur, when bottom-fused)
        Region {
            x: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress > 0.5) ? (root.dockW + root.currentPopW) : 0
            y: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress > 0.5) ? (root.height - root.borderT - root.filletD1) : 0
            width: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress > 0.5) ? root.filletW1 : 0
            height: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress > 0.5) ? root.filletH1 : 0
        }
        Region {
            x: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress > 0.5) ? (root.dockW + root.currentPopW) : 0
            y: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress > 0.5) ? (root.height - root.borderT - root.filletD2) : 0
            width: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress > 0.5) ? root.filletW2 : 0
            height: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress > 0.5) ? root.filletH2 : 0
        }
        Region {
            x: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress > 0.5) ? (root.dockW + root.currentPopW) : 0
            y: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress > 0.5) ? (root.height - root.borderT - root.filletD3) : 0
            width: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress > 0.5) ? root.filletW3 : 0
            height: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress > 0.5) ? root.filletH3 : 0
        }
        Region {
            x: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress > 0.5) ? (root.dockW + root.currentPopW) : 0
            y: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress > 0.5) ? (root.height - root.borderT - root.filletD4) : 0
            width: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress > 0.5) ? root.filletW4 : 0
            height: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress > 0.5) ? root.filletH4 : 0
        }
        Region {
            x: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress > 0.5) ? (root.dockW + root.currentPopW) : 0
            y: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress > 0.5) ? (root.height - root.borderT - root.filletD5) : 0
            width: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress > 0.5) ? root.filletW5 : 0
            height: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress > 0.5) ? root.filletH5 : 0
        }
        Region {
            x: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress > 0.5) ? (root.dockW + root.currentPopW) : 0
            y: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress > 0.5) ? (root.height - root.borderT - root.filletD6) : 0
            width: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress > 0.5) ? root.filletW6 : 0
            height: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress > 0.5) ? root.filletH6 : 0
        }
        Region {
            x: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress > 0.5) ? (root.dockW + root.currentPopW) : 0
            y: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress > 0.5) ? (root.height - root.borderT - root.filletD7) : 0
            width: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress > 0.5) ? root.filletW7 : 0
            height: (fusedBottomPopoutWrapper.offsetProgress > 0.001 && root.fusedProgress > 0.5) ? root.filletH7 : 0
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
            x: rightEdgeControlWrapper.offsetProgress > 0.001
                ? (root.width - root.borderT - (root.currentRightW - 15))
                : 0
            y: rightEdgeControlWrapper.offsetProgress > 0.001 ? root.rightControlY : 0
            width: rightEdgeControlWrapper.offsetProgress > 0.001 ? (Math.max(0, root.currentRightW - 15) + root.borderT) : 0
            height: rightEdgeControlWrapper.offsetProgress > 0.001 ? 1 : 0
        }
        Region {
            x: rightEdgeControlWrapper.offsetProgress > 0.001
                ? (root.width - root.borderT - (root.currentRightW - 12))
                : 0
            y: rightEdgeControlWrapper.offsetProgress > 0.001 ? (root.rightControlY + 1) : 0
            width: rightEdgeControlWrapper.offsetProgress > 0.001 ? (Math.max(0, root.currentRightW - 12) + root.borderT) : 0
            height: rightEdgeControlWrapper.offsetProgress > 0.001 ? 1 : 0
        }
        Region {
            x: rightEdgeControlWrapper.offsetProgress > 0.001
                ? (root.width - root.borderT - (root.currentRightW - 9))
                : 0
            y: rightEdgeControlWrapper.offsetProgress > 0.001 ? (root.rightControlY + 2) : 0
            width: rightEdgeControlWrapper.offsetProgress > 0.001 ? (Math.max(0, root.currentRightW - 9) + root.borderT) : 0
            height: rightEdgeControlWrapper.offsetProgress > 0.001 ? 2 : 0
        }
        Region {
            x: rightEdgeControlWrapper.offsetProgress > 0.001
                ? (root.width - root.borderT - (root.currentRightW - 5))
                : 0
            y: rightEdgeControlWrapper.offsetProgress > 0.001 ? (root.rightControlY + 4) : 0
            width: rightEdgeControlWrapper.offsetProgress > 0.001 ? (Math.max(0, root.currentRightW - 5) + root.borderT) : 0
            height: rightEdgeControlWrapper.offsetProgress > 0.001 ? 3 : 0
        }
        Region {
            x: rightEdgeControlWrapper.offsetProgress > 0.001
                ? (root.width - root.borderT - (root.currentRightW - 3))
                : 0
            y: rightEdgeControlWrapper.offsetProgress > 0.001 ? (root.rightControlY + 7) : 0
            width: rightEdgeControlWrapper.offsetProgress > 0.001 ? (Math.max(0, root.currentRightW - 3) + root.borderT) : 0
            height: rightEdgeControlWrapper.offsetProgress > 0.001 ? 3 : 0
        }
        Region {
            x: rightEdgeControlWrapper.offsetProgress > 0.001
                ? (root.width - root.borderT - (root.currentRightW - 1))
                : 0
            y: rightEdgeControlWrapper.offsetProgress > 0.001 ? (root.rightControlY + 10) : 0
            width: rightEdgeControlWrapper.offsetProgress > 0.001 ? (Math.max(0, root.currentRightW - 1) + root.borderT) : 0
            height: rightEdgeControlWrapper.offsetProgress > 0.001 ? 4 : 0
        }
        // Middle full-width body
        Region {
            x: rightEdgeControlWrapper.offsetProgress > 0.001
                ? (root.width - root.borderT - root.currentRightW)
                : 0
            y: rightEdgeControlWrapper.offsetProgress > 0.001 ? (root.rightControlY + 14) : 0
            width: rightEdgeControlWrapper.offsetProgress > 0.001 ? (root.currentRightW + root.borderT) : 0
            height: rightEdgeControlWrapper.offsetProgress > 0.001 ? Math.max(0, root.rightControlH - 28) : 0
        }
        // Bottom-left convex corner slices
        Region {
            x: rightEdgeControlWrapper.offsetProgress > 0.001
                ? (root.width - root.borderT - (root.currentRightW - 1))
                : 0
            y: rightEdgeControlWrapper.offsetProgress > 0.001 ? (root.rightControlY + root.rightControlH - 14) : 0
            width: rightEdgeControlWrapper.offsetProgress > 0.001 ? (Math.max(0, root.currentRightW - 1) + root.borderT) : 0
            height: rightEdgeControlWrapper.offsetProgress > 0.001 ? 4 : 0
        }
        Region {
            x: rightEdgeControlWrapper.offsetProgress > 0.001
                ? (root.width - root.borderT - (root.currentRightW - 3))
                : 0
            y: rightEdgeControlWrapper.offsetProgress > 0.001 ? (root.rightControlY + root.rightControlH - 10) : 0
            width: rightEdgeControlWrapper.offsetProgress > 0.001 ? (Math.max(0, root.currentRightW - 3) + root.borderT) : 0
            height: rightEdgeControlWrapper.offsetProgress > 0.001 ? 3 : 0
        }
        Region {
            x: rightEdgeControlWrapper.offsetProgress > 0.001
                ? (root.width - root.borderT - (root.currentRightW - 5))
                : 0
            y: rightEdgeControlWrapper.offsetProgress > 0.001 ? (root.rightControlY + root.rightControlH - 7) : 0
            width: rightEdgeControlWrapper.offsetProgress > 0.001 ? (Math.max(0, root.currentRightW - 5) + root.borderT) : 0
            height: rightEdgeControlWrapper.offsetProgress > 0.001 ? 3 : 0
        }
        Region {
            x: rightEdgeControlWrapper.offsetProgress > 0.001
                ? (root.width - root.borderT - (root.currentRightW - 9))
                : 0
            y: rightEdgeControlWrapper.offsetProgress > 0.001 ? (root.rightControlY + root.rightControlH - 4) : 0
            width: rightEdgeControlWrapper.offsetProgress > 0.001 ? (Math.max(0, root.currentRightW - 9) + root.borderT) : 0
            height: rightEdgeControlWrapper.offsetProgress > 0.001 ? 2 : 0
        }
        Region {
            x: rightEdgeControlWrapper.offsetProgress > 0.001
                ? (root.width - root.borderT - (root.currentRightW - 12))
                : 0
            y: rightEdgeControlWrapper.offsetProgress > 0.001 ? (root.rightControlY + root.rightControlH - 2) : 0
            width: rightEdgeControlWrapper.offsetProgress > 0.001 ? (Math.max(0, root.currentRightW - 12) + root.borderT) : 0
            height: rightEdgeControlWrapper.offsetProgress > 0.001 ? 1 : 0
        }
        Region {
            x: rightEdgeControlWrapper.offsetProgress > 0.001
                ? (root.width - root.borderT - (root.currentRightW - 15))
                : 0
            y: rightEdgeControlWrapper.offsetProgress > 0.001 ? (root.rightControlY + root.rightControlH - 1) : 0
            width: rightEdgeControlWrapper.offsetProgress > 0.001 ? (Math.max(0, root.currentRightW - 15) + root.borderT) : 0
            height: rightEdgeControlWrapper.offsetProgress > 0.001 ? 1 : 0
        }

        // Right Edge Control Top Shoulder Fillet (Frosted Glass Stepped Slices)
        Region {
            x: rightEdgeControlWrapper.offsetProgress > 0.001 ? (root.width - root.borderT - Math.min(root.currentRightW, root.filletW1)) : 0
            y: rightEdgeControlWrapper.offsetProgress > 0.001 ? (root.rightControlY - root.filletD1) : 0
            width: rightEdgeControlWrapper.offsetProgress > 0.001 ? Math.min(root.currentRightW, root.filletW1) : 0
            height: rightEdgeControlWrapper.offsetProgress > 0.001 ? root.filletH1 : 0
        }
        Region {
            x: rightEdgeControlWrapper.offsetProgress > 0.001 ? (root.width - root.borderT - Math.min(root.currentRightW, root.filletW2)) : 0
            y: rightEdgeControlWrapper.offsetProgress > 0.001 ? (root.rightControlY - root.filletD2) : 0
            width: rightEdgeControlWrapper.offsetProgress > 0.001 ? Math.min(root.currentRightW, root.filletW2) : 0
            height: rightEdgeControlWrapper.offsetProgress > 0.001 ? root.filletH2 : 0
        }
        Region {
            x: rightEdgeControlWrapper.offsetProgress > 0.001 ? (root.width - root.borderT - Math.min(root.currentRightW, root.filletW3)) : 0
            y: rightEdgeControlWrapper.offsetProgress > 0.001 ? (root.rightControlY - root.filletD3) : 0
            width: rightEdgeControlWrapper.offsetProgress > 0.001 ? Math.min(root.currentRightW, root.filletW3) : 0
            height: rightEdgeControlWrapper.offsetProgress > 0.001 ? root.filletH3 : 0
        }
        Region {
            x: rightEdgeControlWrapper.offsetProgress > 0.001 ? (root.width - root.borderT - Math.min(root.currentRightW, root.filletW4)) : 0
            y: rightEdgeControlWrapper.offsetProgress > 0.001 ? (root.rightControlY - root.filletD4) : 0
            width: rightEdgeControlWrapper.offsetProgress > 0.001 ? Math.min(root.currentRightW, root.filletW4) : 0
            height: rightEdgeControlWrapper.offsetProgress > 0.001 ? root.filletH4 : 0
        }
        Region {
            x: rightEdgeControlWrapper.offsetProgress > 0.001 ? (root.width - root.borderT - Math.min(root.currentRightW, root.filletW5)) : 0
            y: rightEdgeControlWrapper.offsetProgress > 0.001 ? (root.rightControlY - root.filletD5) : 0
            width: rightEdgeControlWrapper.offsetProgress > 0.001 ? Math.min(root.currentRightW, root.filletW5) : 0
            height: rightEdgeControlWrapper.offsetProgress > 0.001 ? root.filletH5 : 0
        }
        Region {
            x: rightEdgeControlWrapper.offsetProgress > 0.001 ? (root.width - root.borderT - Math.min(root.currentRightW, root.filletW6)) : 0
            y: rightEdgeControlWrapper.offsetProgress > 0.001 ? (root.rightControlY - root.filletD6) : 0
            width: rightEdgeControlWrapper.offsetProgress > 0.001 ? Math.min(root.currentRightW, root.filletW6) : 0
            height: rightEdgeControlWrapper.offsetProgress > 0.001 ? root.filletH6 : 0
        }
        Region {
            x: rightEdgeControlWrapper.offsetProgress > 0.001 ? (root.width - root.borderT - Math.min(root.currentRightW, root.filletW7)) : 0
            y: rightEdgeControlWrapper.offsetProgress > 0.001 ? (root.rightControlY - root.filletD7) : 0
            width: rightEdgeControlWrapper.offsetProgress > 0.001 ? Math.min(root.currentRightW, root.filletW7) : 0
            height: rightEdgeControlWrapper.offsetProgress > 0.001 ? root.filletH7 : 0
        }

        // Right Edge Control Bottom Shoulder Fillet (Frosted Glass Stepped Slices)
        Region {
            x: rightEdgeControlWrapper.offsetProgress > 0.001 ? (root.width - root.borderT - Math.min(root.currentRightW, root.filletW1)) : 0
            y: rightEdgeControlWrapper.offsetProgress > 0.001 ? (root.rightControlY + root.rightControlH + root.filletD1 - root.filletH1) : 0
            width: rightEdgeControlWrapper.offsetProgress > 0.001 ? Math.min(root.currentRightW, root.filletW1) : 0
            height: rightEdgeControlWrapper.offsetProgress > 0.001 ? root.filletH1 : 0
        }
        Region {
            x: rightEdgeControlWrapper.offsetProgress > 0.001 ? (root.width - root.borderT - Math.min(root.currentRightW, root.filletW2)) : 0
            y: rightEdgeControlWrapper.offsetProgress > 0.001 ? (root.rightControlY + root.rightControlH + root.filletD2 - root.filletH2) : 0
            width: rightEdgeControlWrapper.offsetProgress > 0.001 ? Math.min(root.currentRightW, root.filletW2) : 0
            height: rightEdgeControlWrapper.offsetProgress > 0.001 ? root.filletH2 : 0
        }
        Region {
            x: rightEdgeControlWrapper.offsetProgress > 0.001 ? (root.width - root.borderT - Math.min(root.currentRightW, root.filletW3)) : 0
            y: rightEdgeControlWrapper.offsetProgress > 0.001 ? (root.rightControlY + root.rightControlH + root.filletD3 - root.filletH3) : 0
            width: rightEdgeControlWrapper.offsetProgress > 0.001 ? Math.min(root.currentRightW, root.filletW3) : 0
            height: rightEdgeControlWrapper.offsetProgress > 0.001 ? root.filletH3 : 0
        }
        Region {
            x: rightEdgeControlWrapper.offsetProgress > 0.001 ? (root.width - root.borderT - Math.min(root.currentRightW, root.filletW4)) : 0
            y: rightEdgeControlWrapper.offsetProgress > 0.001 ? (root.rightControlY + root.rightControlH + root.filletD4 - root.filletH4) : 0
            width: rightEdgeControlWrapper.offsetProgress > 0.001 ? Math.min(root.currentRightW, root.filletW4) : 0
            height: rightEdgeControlWrapper.offsetProgress > 0.001 ? root.filletH4 : 0
        }
        Region {
            x: rightEdgeControlWrapper.offsetProgress > 0.001 ? (root.width - root.borderT - Math.min(root.currentRightW, root.filletW5)) : 0
            y: rightEdgeControlWrapper.offsetProgress > 0.001 ? (root.rightControlY + root.rightControlH + root.filletD5 - root.filletH5) : 0
            width: rightEdgeControlWrapper.offsetProgress > 0.001 ? Math.min(root.currentRightW, root.filletW5) : 0
            height: rightEdgeControlWrapper.offsetProgress > 0.001 ? root.filletH5 : 0
        }
        Region {
            x: rightEdgeControlWrapper.offsetProgress > 0.001 ? (root.width - root.borderT - Math.min(root.currentRightW, root.filletW6)) : 0
            y: rightEdgeControlWrapper.offsetProgress > 0.001 ? (root.rightControlY + root.rightControlH + root.filletD6 - root.filletH6) : 0
            width: rightEdgeControlWrapper.offsetProgress > 0.001 ? Math.min(root.currentRightW, root.filletW6) : 0
            height: rightEdgeControlWrapper.offsetProgress > 0.001 ? root.filletH6 : 0
        }
        Region {
            x: rightEdgeControlWrapper.offsetProgress > 0.001 ? (root.width - root.borderT - Math.min(root.currentRightW, root.filletW7)) : 0
            y: rightEdgeControlWrapper.offsetProgress > 0.001 ? (root.rightControlY + root.rightControlH + root.filletD7 - root.filletH7) : 0
            width: rightEdgeControlWrapper.offsetProgress > 0.001 ? Math.min(root.currentRightW, root.filletW7) : 0
            height: rightEdgeControlWrapper.offsetProgress > 0.001 ? root.filletH7 : 0
        }

        // System Notifications Popup (when visible, including shoulder fillets)
        Region {
            x: (notifPopup.visible && !notifPopup.isDismissed) ? Math.max(0, root.width - notifPopup.width - root.filletR) : 0
            y: 0
            width: (notifPopup.visible && !notifPopup.isDismissed) ? (notifPopup.width + root.filletR) : 0
            height: (notifPopup.visible && !notifPopup.isDismissed) ? (notifPopup.height + root.filletR) : 0
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

    // Dropdown Dashboard Geometry
    readonly property real dropW: Config.dashboardWidth
    readonly property real dropH: dropdownContainer.dropH
    readonly property real dropX: (root.width - root.dropW) / 2
    readonly property real currentDropH: dropdownContainer.currentDropH

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
        return Config.bottomPopoutMode === "power" || Config.bottomPopoutMode === "battery" || Config.bottomPopoutMode === "default";
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

    property bool isFusedToBottom: isPopoutAtBottom

    onIsPopoutAtBottomChanged: {
        if (isPopoutAtBottom) {
            isFusedToBottom = true;
        } else if (!isPopoutFusedBottom || !Config.bottomPopoutVisible) {
            isFusedToBottom = false;
        }
    }

    Connections {
        target: Config
        function onBottomPopoutVisibleChanged() {
            if (!Config.bottomPopoutVisible) {
                isFusedToBottom = false;
            }
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

        // Central Fused Dropdown Dashboard (when open)
        Region {
            x: root.dropX - root.filletR
            y: 0
            width: dropdownContainer.offsetProgress > 0.001 ? (root.dropW + root.filletR * 2) : 0
            height: dropdownContainer.offsetProgress > 0.001 ? (root.currentDropH + 20) : 0
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
    }

    // 4b. SYSTEM TRAY CONTEXT MENU
    TrayContextMenu {
        id: trayContextMenu
        dockW: root.dockW
        screenH: root.height
    }

    // 5. SYSTEM NOTIFICATIONS POPUP (TOP-RIGHT FUSED)
    NotificationPopup {
        id: notifPopup
        x: Math.max(0, root.width - width)
        y: 0
        z: 1000
        visible: NotificationService.hasNotification
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
}
