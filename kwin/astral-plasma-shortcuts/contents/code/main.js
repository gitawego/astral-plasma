// Astral Plasma Launcher & Wallpaper Picker KWin Shortcuts
registerShortcut(
    "AstralLauncher",
    "Astral Plasma: Toggle Launcher",
    "Meta+Space",
    function() {
        console.info("Astral Plasma: Triggering launcher toggle");
        callDBus(
            "org.kde.kglobalaccel",
            "/component/astral_launcher_desktop",
            "org.kde.kglobalaccel.Component",
            "invokeShortcut",
            "_launch"
        );
    }
);

registerShortcut(
    "AstralWallpaper",
    "Astral Plasma: Open Wallpaper Picker",
    "Meta+Shift+W",
    function() {
        console.info("Astral Plasma: Triggering wallpaper picker");
        callDBus(
            "org.kde.kglobalaccel",
            "/component/astral_wallpaper_desktop",
            "org.kde.kglobalaccel.Component",
            "invokeShortcut",
            "_launch"
        );
    }
);
