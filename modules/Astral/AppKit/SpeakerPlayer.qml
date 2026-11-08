import QtQuick
import "../Kernel/components"

// AppKit's SpeakerPlayer: the public name of the kernel's HeatmapSpeakerPlayer. A thin subclass, so an
// app gets the shell's real material, its archetype radii and its motion — with one
// import spelling (`Astral.AppKit`), which is what keeps kernel singletons from being
// registered twice (spec C.13).
HeatmapSpeakerPlayer {}
