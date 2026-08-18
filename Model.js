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

var MIN_MINUTES = 1;
var MAX_MINUTES = 180;
var DEFAULT_MINUTES = 25;

// Returns a valid whole-minute duration, or `fallback` when the input is out
// of the MIN_MINUTES..MAX_MINUTES contract. Deliberately falls back rather
// than clamping: a hand-typed 2500 in shell.json is a typo, and the default
// is a better guess than 180.
function validMinutesOr(value, fallback) {
    if (typeof value !== "number" || !isFinite(value) || value < MIN_MINUTES || value > MAX_MINUTES) return fallback;
    return Math.round(value);
}

// Steps `value` (falling back to DEFAULT_MINUTES like validMinutesOr) by `delta` minutes,
// clamped to MIN_MINUTES..MAX_MINUTES. Non-numeric/non-finite delta is a no-op.
function stepMinutes(value, delta) {
    var base = validMinutesOr(value, DEFAULT_MINUTES);
    if (typeof delta !== "number" || !isFinite(delta)) return base;
    var next = Math.round(base + delta);
    if (next < MIN_MINUTES) next = MIN_MINUTES;
    if (next > MAX_MINUTES) next = MAX_MINUTES;
    return next;
}

// An in-progress session nudged by `delta` minutes. Returns
// {minutes, appliedMs} -- the new snapshot and the exact shift to apply to
// the deadline or the banked remainder -- or null when the nudge is refused.
//
// `remainingMs` is the *live* remainder in milliseconds, never the ceil'd
// display seconds: ceil rounds 300.001s up to 301, so a -5 measured against
// it can leave the deadline in the past, completing the session on the next
// tick instead of being blocked here.
//
// Refused when: the step clamps to a no-op, the deadline has already passed
// (that session is complete, not adjustable -- same rule pause() applies), or
// the shortening would consume everything that is left.
function adjustSession(sessionMinutes, remainingMs, delta) {
    if (typeof remainingMs !== "number" || !isFinite(remainingMs) || remainingMs <= 0) return null;
    var next = stepMinutes(sessionMinutes, delta);
    if (next === sessionMinutes) return null;
    // From the clamped result, not `delta`: sessionMinutes must track exactly
    // what the deadline gets shifted by, or the history row stops matching
    // the minutes actually counted down.
    var appliedMs = (next - sessionMinutes) * 60 * 1000;
    if (remainingMs + appliedMs <= 0) return null;
    return { minutes: next, appliedMs: appliedMs };
}

// One wheel notch is 120 angle units (Qt convention). Banks the sub-notch
// remainder so a touchpad's fine-grained flick can't dump a whole session's
// worth of minutes at once, and so slow scrolling still adds up to a step.
var WHEEL_NOTCH = 120;

function wheelSteps(accumulator, angleDelta) {
    var acc = (typeof accumulator === "number" && isFinite(accumulator)) ? accumulator : 0;
    if (typeof angleDelta !== "number" || !isFinite(angleDelta)) return { steps: 0, remainder: acc };
    acc += angleDelta;
    // Truncate toward zero: a banked remainder always keeps the sign of the
    // scroll it came from, so reversing direction can't fire a step early.
    var steps = acc > 0 ? Math.floor(acc / WHEEL_NOTCH) : Math.ceil(acc / WHEEL_NOTCH);
    return { steps: steps, remainder: acc - steps * WHEEL_NOTCH };
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
    module.exports = { HISTORY_CAP: HISTORY_CAP, MIN_MINUTES: MIN_MINUTES, MAX_MINUTES: MAX_MINUTES, DEFAULT_MINUTES: DEFAULT_MINUTES, mmss: mmss, validMinutesOr: validMinutesOr, stepMinutes: stepMinutes, adjustSession: adjustSession, wheelSteps: wheelSteps, pushSession: pushSession, countToday: countToday, parseHistory: parseHistory, serializeHistory: serializeHistory };
}
