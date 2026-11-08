import QtQuick
import "../Kernel/components"

// AppKit's RadialVisualiser: the public name of the kernel's RadialCoverVisualiser. A thin subclass, so an
// app gets the shell's real material, its archetype radii and its motion — with one
// import spelling (`Astral.AppKit`), which is what keeps kernel singletons from being
// registered twice (spec C.13).
RadialCoverVisualiser {}
