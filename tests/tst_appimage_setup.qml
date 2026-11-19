import QtQuick
import QtQuick.Controls

Item {
    id: root
    width: 320
    height: 240

    Component.onCompleted: {
        try {
            console.log("[TEST] Verifying AppImage installer contract");

            const wizard = readLocalFile("../appimage/SetupWindow.qml");
            assert(wizard.indexOf("\"appimage\", \"install\"") !== -1,
                "the wizard must call the AppImage install backend");
            assert(wizard.indexOf("\"appimage\", \"uninstall\"") !== -1,
                "the wizard must offer a real uninstall");
            assert(wizard.indexOf("\"appimage\", \"status\"") !== -1,
                "the wizard must read the install status instead of guessing");
            assert(wizard.indexOf("install.sh") === -1,
                "the wizard must not shell out to the managed install.sh");

            const appRun = readLocalFile("../packaging/appimage/AppRun");
            assert(appRun.indexOf("ASTRAL_APPIMAGE_PAYLOAD") !== -1,
                "AppRun must export the stable payload path");
            assert(appRun.indexOf("app/") !== -1 && appRun.indexOf("current") !== -1,
                "AppRun must use the versioned app directory and current link");
            assert(appRun.indexOf("cp -a \"$HERE/.\"") !== -1,
                "AppRun must copy the mount into stable storage");
            assert(appRun.indexOf("appimage-setup.qml") !== -1,
                "AppRun must launch the package-root setup entry, not a subdirectory config");
            assert(appRun.indexOf("exec \"$HERE/usr/bin/astral-plasma\"") === -1,
                "the installed shell must never execute from the temporary AppImage mount");
            assert(appRun.indexOf("astral-plasma.AppImage") !== -1,
                "AppRun must keep the canonical AppImage as the update source");
            assert(appRun.indexOf("ASTRAL_APPIMAGE_UPDATER") !== -1,
                "AppRun must expose the bundled AppImageUpdate tool");

            const build = readLocalFile("../packaging/appimage/build.sh");
            assert(build.indexOf("--custom-apprun") !== -1,
                "the build must install the project AppRun, not linuxdeploy's symlink");
            assert(build.indexOf("HostLibraryExecutables") !== -1,
                "the staged qmake must expose Qt's real libexec so qmlimportscanner is found");
            assert(build.indexOf("rsvg-convert") !== -1 && build.indexOf("astral-plasma.png") !== -1,
                "the build must provide a top-level PNG for appimagetool's .DirIcon");
            assert(build.indexOf("appimageupdatetool") !== -1,
                "the image must bundle the AppImageUpdate CLI");
            assert(build.indexOf("gh-releases-zsync") !== -1,
                "the image must embed its zsync update information");
            assert(build.indexOf("appimage install --payload") === -1,
                "build-time packaging must not perform a user install");

            const release = readLocalFile("../.github/workflows/release.yml");
            assert(release.indexOf("  appimage:") !== -1,
                "the release workflow must build an AppImage");
            assert(release.indexOf("build-appimage-x86_64") !== -1,
                "the AppImage must be uploaded as a release artifact");
            assert(/needs:\s*\[prepare, build, appimage\]/.test(release),
                "publishing must wait for the AppImage job");
            assert(release.indexOf("*.AppImage") !== -1,
                "the published assets must include the AppImage");
            assert(release.indexOf("*.AppImage.zsync") !== -1,
                "the published assets must include the zsync delta metadata");

            console.log("PASS: AppImage installer contract is intact.");
            Qt.exit(0);
        } catch (e) {
            console.error("TEST FAILED:", e.message);
            Qt.exit(1);
            throw e;
        }
    }

    function readLocalFile(relativePath) {
        const xhr = new XMLHttpRequest();
        xhr.open("GET", Qt.resolvedUrl(relativePath), false);
        xhr.send(null);
        return xhr.responseText;
    }

    function assert(condition, message) {
        if (!condition) {
            console.error("ASSERTION FAILED: " + message);
            throw new Error(message);
        }
    }
}
