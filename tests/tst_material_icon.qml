import QtQuick
import "../components"
import "../theme"

Item {
    id: testRoot
    width: 400
    height: 400

    MaterialIcon {
        id: iconByName
        iconName: "auto_awesome"
        size: 20
    }

    MaterialIcon {
        id: iconByText
        text: "psychology"
        size: 18
    }

    MaterialIcon {
        id: iconChevron
        iconName: "expand_more"
        size: 16
    }

    MaterialIcon {
        id: iconRefresh
        iconName: "refresh"
        size: 16
    }

    MaterialIcon {
        id: iconArrowUpward
        iconName: "arrow_upward"
        size: 16
    }

    MaterialIcon {
        id: iconStop
        iconName: "stop"
        size: 16
    }

    MaterialIcon {
        id: iconSend
        iconName: "send"
        size: 16
    }

    MaterialIcon {
        id: iconDownload
        iconName: "download"
        size: 16
    }

    MaterialIcon {
        id: iconCloudDownload
        iconName: "cloud_download"
        size: 16
    }

    MaterialIcon {
        id: iconFileDownload
        iconName: "file_download"
        size: 16
    }

    MaterialIcon {
        id: iconDownloadForOffline
        iconName: "download_for_offline"
        size: 16
    }

    MaterialIcon {
        id: iconLink
        iconName: "link"
        size: 16
    }

    MaterialIcon {
        id: iconTaskAlt
        iconName: "task_alt"
        size: 16
    }

    MaterialIcon {
        id: iconSpeaker
        text: "speaker"
        size: 16
    }

    MaterialIcon {
        id: iconEqualizer
        text: "equalizer"
        size: 16
    }

    MaterialIcon {
        id: iconGraphicEq
        text: "graphic_eq"
        size: 16
    }

    MaterialIcon {
        id: iconAstroid
        text: "astroid"
        size: 16
    }

    MaterialIcon {
        id: iconToken
        text: "token"
        size: 16
    }

    Timer {
        interval: 50
        running: true
        repeat: false
        onTriggered: runTests()
    }

    function assert(cond, msg) {
        if (!cond) {
            console.error("FAIL: " + msg);
            Qt.exit(1);
            throw new Error(msg);
        }
    }

    function runTests() {
        console.log("RUNNING: MaterialIcon Resolution Tests");

        // 1. iconName resolution
        assert(iconByName.hasIcon === true, "iconByName must have hasIcon === true");
        assert(iconByName.displaySymbol === "󰄧", "auto_awesome iconName must resolve to sparkle symbol");

        // 2. text resolution
        assert(iconByText.hasIcon === true, "iconByText must have hasIcon === true");
        assert(iconByText.displaySymbol === "󰧑", "psychology text must resolve to brain symbol");

        // 3. chevron resolution
        assert(iconChevron.hasIcon === true, "iconChevron must have hasIcon === true");
        assert(iconChevron.displaySymbol === "󰅀", "expand_more iconName must resolve to chevron");

        // 4. refresh resolution
        assert(iconRefresh.hasIcon === true, "iconRefresh must have hasIcon === true");
        assert(iconRefresh.displaySymbol === "󰑓" || iconRefresh.displaySymbol === "󰑐", "refresh iconName must resolve to refresh glyph");

        // 5. arrow_upward resolution
        assert(iconArrowUpward.hasIcon === true, "iconArrowUpward must have hasIcon === true");
        assert(iconArrowUpward.displaySymbol === "󰁝", "arrow_upward iconName must resolve to arrow upward glyph");

        // 6. stop resolution
        assert(iconStop.hasIcon === true, "iconStop must have hasIcon === true");
        assert(iconStop.displaySymbol === "󰓛", "stop iconName must resolve to stop square glyph");

        // 7. send resolution
        assert(iconSend.hasIcon === true, "iconSend must have hasIcon === true");
        assert(iconSend.displaySymbol === "󰒭", "send iconName must resolve to send paper plane glyph");

        // 8. download-family resolution (Downloads tab + tab-bar icon).
        //    These names silently rendered nothing before the map carried them,
        //    which left the tab's header badge and empty state blank.
        assert(iconDownload.displaySymbol === "󰇚", "download must resolve to the download glyph");
        assert(iconCloudDownload.displaySymbol === "󰅢", "cloud_download must resolve to the cloud download glyph");
        assert(iconFileDownload.displaySymbol === "󰥥", "file_download must resolve through the download heuristic");
        assert(iconDownloadForOffline.displaySymbol === "󰇚", "unmapped download_* names must resolve through the heuristic");
        assert(iconLink.displaySymbol === "󰌷", "link must resolve to the link glyph");
        assert(iconTaskAlt.displaySymbol === "󰗠", "task_alt must resolve to the check-in-circle glyph");

        // 9. speaker and equalizer resolution
        assert(iconSpeaker.displaySymbol === "󰓃", "speaker must resolve to speaker cabinet glyph (󰓃), not volume");
        assert(iconEqualizer.displaySymbol === "󰺢", "equalizer must resolve to equalizer bars glyph (󰺢)");
        assert(iconGraphicEq.displaySymbol === "󰺢", "graphic_eq must resolve to equalizer bars glyph (󰺢)");

        // 10. astroid and token vector resolution (replaces stacked layers glyph)
        assert(iconAstroid.hasIcon === true, "astroid must have hasIcon === true");
        assert(iconAstroid.isAstroid === true, "astroid must be identified as isAstroid");
        assert(iconAstroid.displaySymbol === "", "astroid must not use font glyph fallback");
        assert(iconToken.hasIcon === true, "token must have hasIcon === true");
        assert(iconToken.isAstroid === true, "token must resolve to vector astroid");
        assert(iconToken.displaySymbol === "", "token must not use misleading stacked-layers font glyph");

        console.log("PASS: MaterialIcon Resolution Tests");
        Qt.exit(0);
    }
}
