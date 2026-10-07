import QtQuick
import "../services/DshAuth.js" as DshAuth

Item {
    id: testRoot
    width: 200
    height: 100

    function assert(cond, msg) {
        if (!cond) {
            console.error("FAIL: " + msg);
            Qt.exit(1);
            throw new Error(msg);
        }
        return true;
    }

    Timer {
        interval: 20
        running: true
        repeat: false
        onTriggered: runTests()
    }

    // Vectors generated with Python hashlib/hmac (see repo history). Secret is
    // base64url(bytes(range(32))) so the key is deterministic and printable.
    readonly property string secretB64: "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8"

    readonly property string sampleYaml: [
        "version: 1",
        "records:",
        "  client-connection/browser-session:",
        "    kind: grant",
        "    payload:",
        "      version: 1",
        "      secret: " + secretB64,
        "refs:",
        "  OPENCODE_GO_CUSTOM_API_KEY: sk-whatever"
    ].join("\n")

    function runTests() {
        // --- SHA-256 (FIPS 180-4 vector) ---
        assert(DshAuth.sha256Hex("abc") ===
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
            "sha256('abc') must match the FIPS vector");

        // --- HMAC-SHA256 (RFC 4231 test case 2) ---
        assert(DshAuth.hmacSha256Hex("Jefe", "what do ya want for nothing?") ===
            "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843",
            "hmacSha256 must match RFC 4231 case 2");

        // --- Credentials parsing ---
        assert(DshAuth.parseSecret(sampleYaml) === secretB64,
            "parseSecret must read the browser-session secret");
        assert(DshAuth.parseSecret("version: 1\nrecords: {}\n") === "",
            "parseSecret must return empty when the record is absent");
        assert(DshAuth.parseSecret("") === "", "parseSecret must tolerate empty input");

        // --- Cookie minting (deterministic clock) ---
        var cookie = DshAuth.mintCookie(secretB64, "127.0.0.1:3080", 1759752000000, 3600000);
        assert(cookie !== null, "mintCookie must return a cookie for a valid secret");
        assert(cookie.name === "dsh-auth-VPhEEcLKeqRDBoBalzN2Nm7CnfxKhLE00pKIDWxt1sw",
            "cookie name must be sha256(authority) in base64url");
        assert(cookie.value ===
            "v1.eyJ2ZXJzaW9uIjoxLCJhdXRob3JpdHkiOiIxMjcuMC4wLjE6MzA4MCIsImlzc3VlZEF0IjoxNzU5NzUyMDAwMDAwLCJleHBpcmVzQXQiOjE3NTk3NTU2MDAwMDB9.J42_8177PDanWYbYVhGtsBqnPKYV0S603GFIL_pdtoI",
            "cookie value must be v1.<body>.<hmac>");
        assert(cookie.expiresAt === 1759755600000, "cookie expiry must be issuedAt + ttl");

        // --- Invalid secret ---
        assert(DshAuth.mintCookie("", "127.0.0.1:3080", 0, 1) === null,
            "mintCookie must refuse an empty secret");

        console.log("PASS: tst_dsh_auth");
        Qt.exit(0);
    }
}
