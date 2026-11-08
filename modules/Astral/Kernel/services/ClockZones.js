.pragma library

// Pure time-zone helpers for the shell's clocks.
//
// There is no hard-coded city list: the zone set is whatever the OS ships in
// /usr/share/zoneinfo, read once and filtered here. The shell's QML engine has
// no Intl/ECMA-402, so a zone's wall time is derived from its UTC offset (probed
// out of `date` with TZ set) relative to the reference clock. Every function is
// pure so the whole surface is unit-testable.

/// The world-clock rail shows at most three remote zones.
var MAX_ZONES = 3;

/**
 * Every zone id in a listing of /usr/share/zoneinfo.
 *
 * The tz database ships bookkeeping that is not a zone (zone.tab,
 * iso3166.tab, leapseconds, tzdata.zi, posixrules, the Factory pseudo-zone)
 * plus the posix/ and right/ duplicate trees, so those are dropped. Root-level
 * zones (UTC, GMT, CET, ...) ARE zones and are kept. The result is sorted and
 * de-duplicated.
 */
function parseZoneList(text) {
    var NON_ZONES = [
        "zone.tab", "zone1970.tab", "iso3166.tab", "leapseconds",
        "leap-seconds.list", "tzdata.zi", "posixrules", "localtime",
        "Factory", "SECURITY", "+VERSION"
    ];
    var seen = {};
    var out = [];
    var lines = String(text || "").split("\n");
    for (var i = 0; i < lines.length; i++) {
        var id = lines[i].trim();
        if (!id) continue;
        // Accept a full path as well as a relative listing.
        var at = id.indexOf("/zoneinfo/");
        if (at !== -1) id = id.substring(at + "/zoneinfo/".length);
        if (id.charAt(0) === "/" || id.charAt(0) === ".") continue;
        if (id.indexOf("posix/") === 0 || id.indexOf("right/") === 0) continue;
        if (id.indexOf("..") !== -1) continue;
        if (/\.(tab|zi|list)$/.test(id)) continue;
        if (NON_ZONES.indexOf(id) !== -1) continue;
        if (id.indexOf("leap") === 0) continue;
        if (seen[id]) continue;
        seen[id] = true;
        out.push(id);
    }
    out.sort();
    return out;
}

/**
 * Everything a person might type to reach a zone: its id, the tz database's own
 * description, and its country name. "beijing" reaches Asia/Shanghai because the
 * database describes that zone as "Beijing Time"; "china" reaches both CN zones.
 */
function zoneSearchText(zone, descriptions, countries) {
    var parts = [String(zone || "")];
    var described = descriptions ? descriptions[zone] : null;
    if (described) {
        if (described.comment) parts.push(described.comment);
        if (described.country) {
            parts.push(described.country);
            var name = countries ? countries[described.country] : "";
            if (name) parts.push(name);
        }
    }
    return parts.join(" ").toLowerCase().replace(/[_/]+/g, " ");
}

/** Case-insensitive substring match over ids, descriptions and country names. */
function filterZones(list, query, descriptions, countries) {
    var src = list || [];
    var raw = String(query || "").trim().toLowerCase();
    if (!raw) return src;
    var needle = raw.replace(/[_/]+/g, " ").replace(/\s+/g, " ");
    var out = [];
    for (var i = 0; i < src.length; i++) {
        if (zoneSearchText(src[i], descriptions, countries).indexOf(needle) !== -1) out.push(src[i]);
    }
    return out;
}

/** Secondary label for a zone: "Country · description" where the database has one. */
function zoneSubtitle(zone, descriptions, countries) {
    var described = descriptions ? descriptions[zone] : null;
    if (!described) return regionFromZoneId(zone);
    var name = (countries && countries[described.country]) || described.country || "";
    var bits = [];
    if (name) bits.push(name);
    if (described.comment && described.comment.toLowerCase() !== name.toLowerCase()) {
        bits.push(described.comment);
    }
    if (bits.length === 0) return regionFromZoneId(zone);
    return bits.join(" · ");
}

/** The three tz-database sources, split apart from one batched read. */
var ZONE_TAB_MARK = "@@zone.tab@@";
var ISO_MARK = "@@iso3166.tab@@";

function parseZoneSources(text) {
    var raw = String(text || "");
    var zoneCut = raw.indexOf(ZONE_TAB_MARK);
    var isoCut = raw.indexOf(ISO_MARK);
    return {
        zones: parseZoneList(zoneCut === -1 ? raw : raw.substring(0, zoneCut)),
        zoneTab: zoneCut === -1 ? "" : raw.substring(zoneCut + ZONE_TAB_MARK.length, isoCut === -1 ? raw.length : isoCut),
        iso3166: isoCut === -1 ? "" : raw.substring(isoCut + ISO_MARK.length)
    };
}

/** `zone.tab` rows: country code, coordinates, zone name, free-text description. */
function parseZoneDescriptions(text) {
    var out = {};
    var lines = String(text || "").split("\n");
    for (var i = 0; i < lines.length; i++) {
        var line = lines[i];
        if (!line || line.charAt(0) === "#") continue;
        var fields = line.split("\t");
        if (fields.length < 3) continue;
        var zone = (fields[2] || "").trim();
        if (!zone) continue;
        out[zone] = { country: (fields[0] || "").trim(), comment: (fields[3] || "").trim() };
    }
    return out;
}

/** `iso3166.tab` rows: two-letter code, country name. */
function parseCountryNames(text) {
    var out = {};
    var lines = String(text || "").split("\n");
    for (var i = 0; i < lines.length; i++) {
        var line = lines[i];
        if (!line || line.charAt(0) === "#") continue;
        var fields = line.split("\t");
        if (fields.length < 2) continue;
        out[(fields[0] || "").trim()] = (fields[1] || "").trim();
    }
    return out;
}

/** City label for a zone id: "America/New_York" -> "New York". */
function cityFromZoneId(id) {
    if (!id) return "";
    var tail = String(id).split("/");
    return tail[tail.length - 1].replace(/_/g, " ");
}

/** Region label for a zone id: "America/New_York" -> "America". */
function regionFromZoneId(id) {
    var parts = String(id || "").split("/");
    return parts.length > 1 ? parts[0] : "";
}

/** Trim, drop blanks and duplicates, and cap the list at MAX_ZONES. */
function normalize(list) {
    var out = [];
    var src = list || [];
    for (var i = 0; i < src.length; i++) {
        var id = String(src[i] || "").trim();
        if (!id || out.indexOf(id) !== -1) continue;
        if (out.length >= MAX_ZONES) break;
        out.push(id);
    }
    return out;
}

function canAdd(list) { return normalize(list).length < MAX_ZONES; }

function addZone(list, id) {
    var next = normalize(list);
    var clean = String(id || "").trim();
    if (!clean || next.indexOf(clean) !== -1 || next.length >= MAX_ZONES) return next;
    next.push(clean);
    return next;
}

function removeZone(list, id) {
    return normalize(list).filter(function (zone) { return zone !== id; });
}

/**
 * Human offset for a difference in minutes: "=" when the clocks agree, whole
 * hours otherwise ("+8h", "−4h"), and "h:mm" for the half-hour zones. The sign
 * is always explicit so the direction is never ambiguous.
 */
function offsetLabel(deltaMinutes) {
    var d = Math.round(Number(deltaMinutes) || 0);
    if (d === 0) return "=";
    var sign = d > 0 ? "+" : "−";
    var abs = Math.abs(d);
    var hours = Math.floor(abs / 60);
    var minutes = abs % 60;
    if (minutes === 0) return sign + hours + "h";
    return sign + hours + ":" + (minutes < 10 ? "0" + minutes : minutes);
}

function _pad(n) { return (n < 10 ? "0" : "") + n; }

/** A Date whose wall clock is `date` moved by `deltaMinutes`. */
function shiftDate(date, deltaMinutes) {
    return new Date(date.getTime() + Math.round(Number(deltaMinutes) || 0) * 60000);
}

/**
 * Row view-model for one zone.
 *   referenceDate   a Date whose wall clock is the reference ("your") time
 *   refOffsetMin    the reference zone's UTC offset in minutes east of UTC
 *   zoneOffsetMin   the remote zone's offset, same convention
 *
 * The remote wall time is the reference wall clock plus the offset difference,
 * which also yields the calendar-day delta — what a world clock is really for.
 */
function zoneView(id, referenceDate, refOffsetMin, zoneOffsetMin, abbr) {
    var localMinutes = referenceDate.getHours() * 60 + referenceDate.getMinutes();
    var delta = Math.round(zoneOffsetMin) - Math.round(refOffsetMin);
    var shifted = localMinutes + delta;
    var dayShift = Math.floor(shifted / 1440);
    var minutes = ((shifted % 1440) + 1440) % 1440;
    // A word, not a "+1d" token: it reads inside the meta line ("CST · +6h ·
    // tomorrow") and keeps the time column free of a chip, so the times line up.
    var dayWord = dayShift > 0 ? "tomorrow" : (dayShift < 0 ? "yesterday" : "");
    return {
        id: id,
        city: cityFromZoneId(id),
        region: regionFromZoneId(id),
        time: _pad(Math.floor(minutes / 60)) + ":" + _pad(minutes % 60),
        abbr: abbr || "",
        offsetLabel: offsetLabel(delta),
        dayWord: dayWord
    };
}

/** Parse the batched probe: one "±HHMM|ABBR" line per requested zone, in order. */
function parseOffsets(text) {
    var out = [];
    var lines = String(text || "").split("\n");
    for (var i = 0; i < lines.length; i++) {
        var line = lines[i].trim();
        if (!line) continue;
        var parts = line.split("|");
        out.push({ offsetMinutes: offsetMinutesFromHhmm(parts[0]), abbr: (parts[1] || "").trim() });
    }
    return out;
}

/** "+0530" / "-0400" -> minutes east of UTC. */
function offsetMinutesFromHhmm(hhmm) {
    var s = String(hhmm || "").trim();
    if (s.length < 5) return 0;
    var sign = s.charAt(0) === "-" ? -1 : 1;
    var hours = parseInt(s.substring(1, 3), 10);
    var minutes = parseInt(s.substring(3, 5), 10);
    if (isNaN(hours) || isNaN(minutes)) return 0;
    return sign * (hours * 60 + minutes);
}

/** Turn a /etc/localtime target into a zone id. */
function systemZoneFromLink(target) {
    var path = String(target || "").trim();
    if (!path) return "";
    var marker = "/zoneinfo/";
    var at = path.indexOf(marker);
    var id = at === -1 ? path : path.substring(at + marker.length);
    if (id.indexOf("posix/") === 0 || id.indexOf("right/") === 0) id = id.substring(id.indexOf("/") + 1);
    return id;
}

/** Split a list into groups of at most `size` (used to lay out picker pills). */
function chunk(list, size) {
    var out = [];
    var src = list || [];
    var width = Math.max(1, Math.floor(size) || 1);
    for (var i = 0; i < src.length; i += width) {
        out.push(src.slice(i, i + width));
    }
    return out;
}

/** Shell-quote a value embedded in the batched probe command. */
function shellQuote(value) {
    return "'" + String(value).replace(/'/g, "'\\''") + "'";
}

/** HH:mm for a Date, zero-padded. */
function formatClock(date) {
    return _pad(date.getHours()) + ":" + _pad(date.getMinutes());
}
