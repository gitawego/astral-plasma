import QtQuick
import "../Kernel/components"

// AppKit's PreviewLoop: the public name of the kernel's PreviewCycle. A thin subclass, so an
// app gets the shell's own implementation with one import spelling (spec C.13).
PreviewCycle {}
