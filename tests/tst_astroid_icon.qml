import QtQuick
import QtQuick.Shapes
import "../components"
import "../theme"

Item {
    id: testRoot
    width: 400
    height: 400

    AstroidIcon {
        id: astroidDefault
    }

    AstroidIcon {
        id: astroidCustom
        size: 24
        color: "#EF4444"
        strokeWidth: 2.5
    }

    MaterialIcon {
        id: matIconAstroid
        text: "astroid"
        size: 20
        color: "#3B82F6"
    }

    MaterialIcon {
        id: matIconToken
        text: "token"
        size: 20
        color: "#10B981"
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

    function readLocalFile(relativePath) {
        const xhr = new XMLHttpRequest();
        xhr.open("GET", Qt.resolvedUrl(relativePath), false);
        xhr.send(null);
        return xhr.responseText;
    }

    function runTests() {
        console.log("RUNNING: AstroidIcon Unit Tests");

        // 1. Default properties
        assert(astroidDefault.size === 18, "Default size must be 18");
        assert(astroidDefault.implicitWidth === 18, "implicitWidth must equal size (18)");
        assert(astroidDefault.implicitHeight === 18, "implicitHeight must equal size (18)");
        assert(astroidDefault.strokeWidth === 2.0, "Default strokeWidth must be 2.0 (Lucide standard)");

        // 2. Custom properties
        assert(astroidCustom.size === 24, "Custom size must be 24");
        assert(astroidCustom.implicitWidth === 24, "Custom implicitWidth must be 24");
        assert(astroidCustom.implicitHeight === 24, "Custom implicitHeight must be 24");
        assert(Qt.colorEqual(astroidCustom.color, "#EF4444"), "Custom color must be #EF4444");
        assert(astroidCustom.strokeWidth === 2.5, "Custom strokeWidth must be 2.5");

        // 3. Shape renderer architecture: GeometryRenderer is mandatory
        const astroidSrc = readLocalFile("../components/AstroidIcon.qml");
        assert(astroidSrc.indexOf("Shape.GeometryRenderer") !== -1,
            "AstroidIcon must enforce Shape.GeometryRenderer for Intel Mesa stability");
        assert(astroidSrc.indexOf("M12.983 21.186a1 1 0 0 1-1.966 0") !== -1,
            "AstroidIcon must include authentic Lucide astroid SVG path");

        // 4. MaterialIcon integration
        assert(matIconAstroid.hasIcon === true, "MaterialIcon('astroid') must have icon");
        assert(matIconAstroid.isAstroid === true, "MaterialIcon('astroid') must resolve to AstroidIcon");
        assert(matIconAstroid.displaySymbol === "", "MaterialIcon('astroid') must not emit font glyph");

        assert(matIconToken.hasIcon === true, "MaterialIcon('token') must have icon");
        assert(matIconToken.isAstroid === true, "MaterialIcon('token') must resolve to AstroidIcon");
        assert(matIconToken.displaySymbol === "", "MaterialIcon('token') must not emit stacked layers glyph");

        // 5. Verify stacked layers glyph \uf51e is completely removed from token mappings
        const matIconSrc = readLocalFile("../components/MaterialIcon.qml");
        assert(!/"token":\s*"\\uf51e"/.test(matIconSrc),
            "MaterialIcon must NOT map 'token' to \\uf51e stacked-layers glyph");
        assert(!/"tokens":\s*"\\uf51e"/.test(matIconSrc),
            "MaterialIcon must NOT map 'tokens' to \\uf51e stacked-layers glyph");
        assert(!/"toll":\s*"\\uf51e"/.test(matIconSrc),
            "MaterialIcon must NOT map 'toll' to \\uf51e stacked-layers glyph");

        console.log("PASS: AstroidIcon Unit Tests");
        Qt.exit(0);
    }
}
