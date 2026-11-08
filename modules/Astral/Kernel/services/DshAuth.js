.pragma library

// Pure-JS helpers that let Astral's embedded DSH web view authenticate to an
// already-running `dsh web` server.
//
// DSH mints an authority-bound, HMAC-signed cookie on its process-token
// exchange (@deepseek-ai/dsh-client-connection/lib/index.js, browser-auth):
//
//   name  = "dsh-auth-" + base64url(sha256(authority))
//   value = "v1." + base64url(JSON({version,authority,issuedAt,expiresAt}))
//                 + "." + base64url(hmacSha256(secret, body))
//
// The signing secret is durable in $DSH_HOME/.credentials.yaml, so the shell can
// mint the same cookie for a server it did not start. Qt's QML exposes neither
// QWebEngineCookieStore nor btoa/atob/crypto, so the value is injected with
// `document.cookie` on the DSH origin (see dsh/DshWebWindow.qml).
//
// Every function here is validated against RFC vectors in tests/tst_dsh_auth.qml.

var B64URL = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";

var SHA256_K = [
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
];

/** ASCII/byte string -> bytes. All inputs here (base64url, JSON, host:port) are ASCII. */
function asciiBytes(s) {
    var out = new Uint8Array(s.length);
    for (var i = 0; i < s.length; i++) out[i] = s.charCodeAt(i) & 0xff;
    return out;
}

function rotr(x, n) {
    return (x >>> n) | (x << (32 - n));
}

/** SHA-256 over a byte array; returns 32 bytes. */
function sha256(msg) {
    var h = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
             0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19];
    var len = msg.length;
    var bitLen = len * 8;
    var withOne = len + 1;
    var rem = withOne % 64;
    var padLen = (rem <= 56) ? (56 - rem) : (56 + 64 - rem);
    var total = withOne + padLen + 8;
    var data = new Uint8Array(total);
    for (var i = 0; i < len; i++) data[i] = msg[i] & 0xff;
    data[len] = 0x80;
    var hi = Math.floor(bitLen / 4294967296);
    var lo = bitLen % 4294967296;
    data[total - 8] = (hi >>> 24) & 0xff;
    data[total - 7] = (hi >>> 16) & 0xff;
    data[total - 6] = (hi >>> 8) & 0xff;
    data[total - 5] = hi & 0xff;
    data[total - 4] = (lo >>> 24) & 0xff;
    data[total - 3] = (lo >>> 16) & 0xff;
    data[total - 2] = (lo >>> 8) & 0xff;
    data[total - 1] = lo & 0xff;

    var w = new Array(64);
    for (var off = 0; off < total; off += 64) {
        for (var t = 0; t < 16; t++) {
            w[t] = ((data[off + t * 4] << 24) | (data[off + t * 4 + 1] << 16)
                  | (data[off + t * 4 + 2] << 8) | data[off + t * 4 + 3]) >>> 0;
        }
        for (var t = 16; t < 64; t++) {
            var s0 = (rotr(w[t - 15], 7) ^ rotr(w[t - 15], 18) ^ (w[t - 15] >>> 3)) >>> 0;
            var s1 = (rotr(w[t - 2], 17) ^ rotr(w[t - 2], 19) ^ (w[t - 2] >>> 10)) >>> 0;
            w[t] = (w[t - 16] + s0 + w[t - 7] + s1) >>> 0;
        }
        var a = h[0], b = h[1], c = h[2], d = h[3], e = h[4], f = h[5], g = h[6], hh = h[7];
        for (var t = 0; t < 64; t++) {
            var S1 = (rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)) >>> 0;
            var ch = ((e & f) ^ (~e & g)) >>> 0;
            var temp1 = (hh + S1 + ch + SHA256_K[t] + w[t]) >>> 0;
            var S0 = (rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)) >>> 0;
            var maj = ((a & b) ^ (a & c) ^ (b & c)) >>> 0;
            var temp2 = (S0 + maj) >>> 0;
            hh = g; g = f; f = e; e = (d + temp1) >>> 0;
            d = c; c = b; b = a; a = (temp1 + temp2) >>> 0;
        }
        h[0] = (h[0] + a) >>> 0; h[1] = (h[1] + b) >>> 0; h[2] = (h[2] + c) >>> 0; h[3] = (h[3] + d) >>> 0;
        h[4] = (h[4] + e) >>> 0; h[5] = (h[5] + f) >>> 0; h[6] = (h[6] + g) >>> 0; h[7] = (h[7] + hh) >>> 0;
    }
    var out = new Uint8Array(32);
    for (var i = 0; i < 8; i++) {
        out[i * 4] = (h[i] >>> 24) & 0xff;
        out[i * 4 + 1] = (h[i] >>> 16) & 0xff;
        out[i * 4 + 2] = (h[i] >>> 8) & 0xff;
        out[i * 4 + 3] = h[i] & 0xff;
    }
    return out;
}

/** HMAC-SHA256; key and msg are byte arrays, returns 32 bytes. */
function hmacSha256(key, msg) {
    var blockSize = 64;
    var k = key;
    if (k.length > blockSize) k = sha256(k);
    var ipad = new Uint8Array(blockSize + msg.length);
    for (var i = 0; i < blockSize; i++) ipad[i] = ((i < k.length ? k[i] : 0) ^ 0x36) & 0xff;
    for (var i = 0; i < msg.length; i++) ipad[blockSize + i] = msg[i] & 0xff;
    var inner = sha256(ipad);
    var opad = new Uint8Array(blockSize + inner.length);
    for (var i = 0; i < blockSize; i++) opad[i] = ((i < k.length ? k[i] : 0) ^ 0x5c) & 0xff;
    for (var i = 0; i < inner.length; i++) opad[blockSize + i] = inner[i] & 0xff;
    return sha256(opad);
}

function bytesToHex(bytes) {
    var s = "";
    for (var i = 0; i < bytes.length; i++) {
        var b = bytes[i] & 0xff;
        s += (b < 16 ? "0" : "") + b.toString(16);
    }
    return s;
}

function bytesToBase64Url(bytes) {
    var out = "";
    var len = bytes.length;
    var i = 0;
    while (i < len) {
        var b0 = bytes[i++] & 0xff;
        var has1 = i < len;
        var b1 = has1 ? (bytes[i++] & 0xff) : 0;
        var has2 = i < len;
        var b2 = has2 ? (bytes[i++] & 0xff) : 0;
        out += B64URL.charAt(b0 >> 2);
        out += B64URL.charAt(((b0 & 3) << 4) | (b1 >> 4));
        if (has1) out += B64URL.charAt(((b1 & 15) << 2) | (b2 >> 6));
        if (has2) out += B64URL.charAt(b2 & 63);
    }
    return out;
}

function b64Val(code) {
    if (code >= 65 && code <= 90) return code - 65;
    if (code >= 97 && code <= 122) return code - 97 + 26;
    if (code >= 48 && code <= 57) return code - 48 + 52;
    if (code === 45) return 62; // -
    if (code === 95) return 63; // _
    return -1;
}

function base64UrlToBytes(s) {
    s = String(s || "");
    var out = [];
    var i = 0;
    while (i < s.length) {
        var c0 = b64Val(s.charCodeAt(i++));
        if (c0 < 0) break;
        if (i >= s.length) { out.push((c0 << 2) & 0xff); break; }
        var c1 = b64Val(s.charCodeAt(i++));
        if (c1 < 0) break;
        out.push(((c0 << 2) | (c1 >> 4)) & 0xff);
        if (i >= s.length) break;
        var c2 = b64Val(s.charCodeAt(i++));
        if (c2 < 0) break;
        out.push((((c1 & 15) << 4) | (c2 >> 2)) & 0xff);
        if (i >= s.length) break;
        var c3 = b64Val(s.charCodeAt(i++));
        if (c3 < 0) break;
        out.push((((c2 & 3) << 6) | c3) & 0xff);
    }
    return new Uint8Array(out);
}

// Test-facing helpers -------------------------------------------------------
function sha256Hex(s) { return bytesToHex(sha256(asciiBytes(s))); }
function hmacSha256Hex(keyStr, msgStr) {
    return bytesToHex(hmacSha256(asciiBytes(keyStr), asciiBytes(msgStr)));
}

/**
 * The browser-session signing secret from $DSH_HOME/.credentials.yaml, or "".
 *
 * The record is `records["client-connection/browser-session"].payload.secret`.
 * The file is machine-written and tiny; scan the record block rather than pull
 * in a YAML dependency.
 */
function parseSecret(credentialsYaml) {
    if (!credentialsYaml) return "";
    var lines = String(credentialsYaml).split("\n");
    var inRecord = false;
    var recordIndent = -1;
    for (var i = 0; i < lines.length; i++) {
        var line = lines[i];
        var trimmed = line.replace(/^\s+/, "");
        var indent = line.length - trimmed.length;
        if (!inRecord) {
            if (trimmed.indexOf("client-connection/browser-session:") === 0) {
                inRecord = true;
                recordIndent = indent;
            }
            continue;
        }
        if (trimmed.length === 0) continue;
        if (indent <= recordIndent) break;
        var m = /^secret:\s*(.+)$/.exec(trimmed);
        if (m) return m[1].trim().replace(/^["']|["']$/g, "");
    }
    return "";
}

/**
 * Mint the DSH browser-session cookie for one authority.
 * @returns {name, value, expiresAt} or null when the secret is unusable.
 */
function mintCookie(secretB64Url, authority, nowMs, ttlMs) {
    if (!secretB64Url || !authority) return null;
    var secret = base64UrlToBytes(secretB64Url);
    if (secret.length === 0) return null;
    var now = Math.floor(nowMs);
    var expiresAt = now + Math.floor(ttlMs);
    var name = "dsh-auth-" + bytesToBase64Url(sha256(asciiBytes(authority)));
    var payload = '{"version":1,"authority":"' + authority + '","issuedAt":' + now + ',"expiresAt":' + expiresAt + '}';
    var body = bytesToBase64Url(asciiBytes(payload));
    var sig = bytesToBase64Url(hmacSha256(secret, asciiBytes(body)));
    return { name: name, value: "v1." + body + "." + sig, expiresAt: expiresAt };
}
