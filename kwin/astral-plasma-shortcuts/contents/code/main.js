// Astral Plasma Launcher & Wallpaper Picker KWin Shortcuts
//
// KWin scripts cannot launch processes, and invoking a `.desktop` service
// through kglobalaccel only emits a signal that nothing in this shell listens to
// (Plasma's own panel does the launching for the shortcuts it registers). The
// shortcuts therefore forward to the daemon, which runs the shell's IPC command.
// The action names are whitelisted by the daemon.
registerShortcut(
    "AstralLauncher",
    "Astral Plasma: Toggle Launcher",
    "Meta+Space",
    function() {
        console.info("Astral Plasma: Triggering launcher toggle");
        callDBus(
            "org.astralplasma.WindowWatcher",
            "/Watcher",
            "org.astralplasma.WindowWatcher",
            "ShellIpc",
            "launcher.toggle"
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
            "org.astralplasma.WindowWatcher",
            "/Watcher",
            "org.astralplasma.WindowWatcher",
            "ShellIpc",
            "launcher.wallpaper"
        );
    }
);

// Active-apps overview: bare Meta key toggles the fullscreen overview of running windows
// with live thumbnails (GNOME-style).
registerShortcut(
    "AstralOverview",
    "Astral Plasma: Active Apps Overview",
    "Meta",
    function() {
        console.info("Astral Plasma: Triggering active apps overview");
        callDBus(
            "org.astralplasma.WindowWatcher",
            "/Watcher",
            "org.astralplasma.WindowWatcher",
            "ShellIpc",
            "overview.toggle"
        );
    }
);

// AI Assistant Copilot: Meta+C toggles the right slide-out AI copilot drawer
registerShortcut(
    "AstralAssistant",
    "Astral Plasma: Toggle AI Copilot",
    "Meta+C",
    function() {
        console.info("Astral Plasma: Triggering AI copilot toggle");
        callDBus(
            "org.astralplasma.WindowWatcher",
            "/Watcher",
            "org.astralplasma.WindowWatcher",
            "ShellIpc",
            "assistant.toggle"
        );
    }
);

// Central Dashboard: Meta+D toggles the central dropdown dashboard
registerShortcut(
    "AstralDashboard",
    "Astral Plasma: Toggle Dashboard",
    "Meta+D",
    function() {
        console.info("Astral Plasma: Triggering dashboard toggle");
        callDBus(
            "org.astralplasma.WindowWatcher",
            "/Watcher",
            "org.astralplasma.WindowWatcher",
            "ShellIpc",
            "dashboard.toggle"
        );
    }
);

// Settings Hub: Meta+, toggles the Nexus settings dialog
registerShortcut(
    "AstralSettings",
    "Astral Plasma: Toggle Settings",
    "Meta+,",
    function() {
        console.info("Astral Plasma: Triggering settings toggle");
        callDBus(
            "org.astralplasma.WindowWatcher",
            "/Watcher",
            "org.astralplasma.WindowWatcher",
            "ShellIpc",
            "settings.toggle"
        );
    }
);

