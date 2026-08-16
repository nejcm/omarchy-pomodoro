// Pure logic for the pomodoro plugin. No QML types, no imports, no side effects.
// Loadable as a QML JS library (.import) and as a CommonJS module (node/test).

function mmss(seconds) {
    var s = Math.floor(seconds);
    if (!isFinite(s) || s < 0) s = 0;
    var m = Math.floor(s / 60);
    var r = s % 60;
    var pad = function (n) { return n < 10 ? "0" + n : "" + n; };
    return pad(m) + ":" + pad(r);
}

// Session rows kept on disk and in memory. Single source for both the write
// path (pushSession) and the read path (parseHistory) so they can't diverge.
var HISTORY_CAP = 50;

// Returns a valid whole-minute duration, or `fallback` when the input is out
// of the 1..180 contract. Deliberately falls back rather than clamping: a
// hand-typed 2500 in shell.json is a typo, and the default is a better guess
// than 180.
function validMinutesOr(value, fallback) {
    if (typeof value !== "number" || !isFinite(value) || value < 1 || value > 180) return fallback;
    return Math.round(value);
}

function pushSession(history, entry, cap) {
    if (typeof cap !== "number" || !isFinite(cap) || cap < 0) cap = HISTORY_CAP;
    var base = Array.isArray(history) ? history : [];
    var out = [entry].concat(base);
    if (out.length > cap) out = out.slice(0, cap);
    return out;
}

function sameLocalDay(aMs, bMs) {
    var a = new Date(aMs);
    var b = new Date(bMs);
    return a.getFullYear() === b.getFullYear() &&
        a.getMonth() === b.getMonth() &&
        a.getDate() === b.getDate();
}

function countToday(history, nowMs) {
    if (!Array.isArray(history)) return 0;
    var count = 0;
    for (var i = 0; i < history.length; i++) {
        var e = history[i];
        if (e && typeof e.startedAt === "number" && isFinite(e.startedAt) && sameLocalDay(e.startedAt, nowMs)) {
            count++;
        }
    }
    return count;
}

function parseHistory(text, cap) {
    if (typeof cap !== "number" || !isFinite(cap) || cap < 0) cap = HISTORY_CAP;
    if (typeof text !== "string" || text.length === 0) return [];
    var data;
    try {
        data = JSON.parse(text);
    } catch (e) {
        return [];
    }
    if (!data || typeof data !== "object" || !Array.isArray(data.sessions)) return [];

    var out = [];
    for (var i = 0; i < data.sessions.length && out.length < cap; i++) {
        var e = data.sessions[i];
        if (!e || typeof e !== "object") continue;
        if (typeof e.startedAt !== "number" || !isFinite(e.startedAt)) continue;
        if (typeof e.minutes !== "number" || !isFinite(e.minutes)) continue;
        if (Math.floor(e.minutes) !== e.minutes || e.minutes < 1) continue;
        out.push({ startedAt: e.startedAt, minutes: e.minutes });
    }
    return out;
}

function serializeHistory(history) {
    var sessions = Array.isArray(history) ? history : [];
    return JSON.stringify({ version: 1, sessions: sessions });
}

if (typeof module !== "undefined") {
    module.exports = { HISTORY_CAP: HISTORY_CAP, mmss: mmss, validMinutesOr: validMinutesOr, pushSession: pushSession, countToday: countToday, parseHistory: parseHistory, serializeHistory: serializeHistory };
}
