.pragma library

// ============================================================================
// Harness update messages
// ============================================================================
// The AI page shows one line for an update plus pi's own last words underneath.
// Pure, so the wording is asserted by tests instead of by clicking:
//
//   * an update that moved the version says which versions it moved between -
//     "Update finished" would leave the user guessing whether anything happened;
//   * an update that moved nothing says so;
//   * package and catalog updates are not version claims at all, so they say what
//     they did and leave the evidence to pi's output.

/// Human line for one `assistant update-pi` report.
function describe(report) {
    if (!report || typeof report !== "object") {
        return "Update finished";
    }
    const target = report.target ? String(report.target) : "pi";
    const before = report.before !== undefined && report.before !== null ? String(report.before) : "";
    const after = report.after !== undefined && report.after !== null ? String(report.after) : "";

    if (target === "extensions") {
        return "Packages reconciled with npm";
    }
    if (target === "models") {
        return "Model catalogs refreshed";
    }
    if (report.changed === true) {
        return "Updated " + (before !== "" ? before : "?") + " → " + (after !== "" ? after : "?");
    }
    if (report.changed === false) {
        return "Already up to date" + (after !== "" ? " (" + after + ")" : "");
    }
    return "Update finished" + (after !== "" ? " (" + after + ")" : "");
}

/// Last non-empty line of the update output, for the detail row.
///
/// pi prints progress and then its verdict; the last line is the verdict, and the
/// detail row has one line.
function tail(output) {
    const lines = String(output === undefined || output === null ? "" : output)
        .split("\n")
        .map(function (line) { return line.trim(); })
        .filter(function (line) { return line.length > 0; });
    return lines.length > 0 ? lines[lines.length - 1] : "";
}
