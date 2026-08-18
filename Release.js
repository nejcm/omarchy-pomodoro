// Pure conventional-commit version bump logic. No imports, no dependencies.
// Loadable as a CommonJS module (node/test) and runnable as a CLI:
//   git log <range> --format='%s%x00%b%x1e' | node Release.js <current-version>
// prints the next version, or nothing (exit 0) when no commit warrants a release.

// Bump map. Deliberately narrow: a type not listed here ships no release, so a
// `docs:` or `ci:` push cannot move the version.
var LEVELS = { major: 3, minor: 2, patch: 1 };
var TYPE_LEVEL = {
    feat: "minor",
    fix: "patch",
    perf: "patch",
    revert: "patch",
    chore: "patch",
    refactor: "patch"
};

// "major" | "minor" | "patch" | null for a single commit. A `!` after the type
// (or scope), or a BREAKING CHANGE: footer in the body, wins over the type.
function bumpLevel(subject, body) {
    if (typeof body === "string" && body.indexOf("BREAKING CHANGE:") !== -1) return "major";
    if (typeof subject !== "string") return null;
    var m = /^([a-z]+)(\([^)]*\))?(!)?:/.exec(subject);
    if (!m) return null;
    if (m[3]) return "major";
    return TYPE_LEVEL[m[1]] || null;
}

// Next version string, or null when nothing warrants a release. Returns null
// for a malformed `current` rather than guessing -- same fall-back-don't-clamp
// instinct as validMinutesOr in Model.js.
function nextVersion(current, commits) {
    if (typeof current !== "string") return null;
    var v = /^(\d+)\.(\d+)\.(\d+)$/.exec(current);
    if (!v) return null;
    var list = Array.isArray(commits) ? commits : [];

    var best = null;
    for (var i = 0; i < list.length; i++) {
        var c = list[i];
        if (!c || typeof c !== "object") continue;
        var level = bumpLevel(c.subject, c.body);
        if (level && (!best || LEVELS[level] > LEVELS[best])) best = level;
    }
    if (!best) return null;

    var major = parseInt(v[1], 10);
    var minor = parseInt(v[2], 10);
    var patch = parseInt(v[3], 10);
    if (best === "major") return (major + 1) + ".0.0";
    if (best === "minor") return major + "." + (minor + 1) + ".0";
    return major + "." + minor + "." + (patch + 1);
}

// `<subject>\x00<body>\x1e` records, as written by git log --format. Records are
// newline-separated on the wire, so each one is trimmed before splitting.
function parseRecords(text) {
    if (typeof text !== "string") return [];
    var out = [];
    var chunks = text.split("\x1e");
    for (var i = 0; i < chunks.length; i++) {
        var raw = chunks[i].replace(/^\s+/, "");
        if (!raw) continue;
        var nul = raw.indexOf("\x00");
        if (nul === -1) {
            out.push({ subject: raw, body: "" });
        } else {
            out.push({ subject: raw.slice(0, nul), body: raw.slice(nul + 1) });
        }
    }
    return out;
}

if (typeof require !== "undefined" && require.main === module) {
    var input = require("fs").readFileSync(0, "utf8");
    var next = nextVersion(process.argv[2], parseRecords(input));
    if (next) process.stdout.write(next + "\n");
}

if (typeof module !== "undefined") {
    module.exports = { bumpLevel: bumpLevel, nextVersion: nextVersion, parseRecords: parseRecords };
}
