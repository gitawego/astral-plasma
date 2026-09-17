// Caelestia Launcher & Wallpaper Picker KWin Shortcuts
registerShortcut(
    "CaelestiaLauncher",
    "Caelestia: Toggle Launcher",
    "Meta+Space",
    function() {
        console.info("Caelestia: Triggering launcher toggle");
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
    "CaelestiaWallpaper",
    "Caelestia: Open Wallpaper Picker",
    "Meta+Shift+W",
    function() {
        console.info("Caelestia: Triggering wallpaper picker");
        callDBus(
            "org.kde.kglobalaccel",
            "/component/astral_wallpaper_desktop",
            "org.kde.kglobalaccel.Component",
            "invokeShortcut",
            "_launch"
        );
    }
);
