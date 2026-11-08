pragma Singleton

import QtQuick
import Quickshell
import "../../config"

Singleton {
    id: root

    // Instantiate built-in archetypes
    readonly property LiquidGlassArchetype liquidGlass: LiquidGlassArchetype {}
    readonly property NordicMinimalArchetype nordicMinimal: NordicMinimalArchetype {}
    readonly property CyberpunkNeonArchetype cyberpunkNeon: CyberpunkNeonArchetype {}

    // Registry table mapping archetype ID to instance
    readonly property var archetypes: ({
        "liquid_glass": root.liquidGlass,
        "nordic_minimal": root.nordicMinimal,
        "cyberpunk_neon": root.cyberpunkNeon
    })

    // Active archetype name (reactively bound to Config)
    readonly property string activeArchetypeName: {
        if (typeof Config !== "undefined" && Config.themeArchetype) {
            return Config.themeArchetype;
        }
        return "liquid_glass";
    }

    // Active archetype object instance (defaults to liquid_glass)
    readonly property ThemeArchetype activeArchetype: {
        const key = root.activeArchetypeName.toLowerCase();
        return root.archetypes[key] || root.liquidGlass;
    }

    // Helper: list of registered archetype descriptors
    function listArchetypes() {
        return [
            { id: "liquid_glass", name: root.liquidGlass.name, description: root.liquidGlass.description },
            { id: "nordic_minimal", name: root.nordicMinimal.name, description: root.nordicMinimal.description },
            { id: "cyberpunk_neon", name: root.cyberpunkNeon.name, description: root.cyberpunkNeon.description }
        ];
    }
}
