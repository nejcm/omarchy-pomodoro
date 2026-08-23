// Plain assert self-check for Model.js. Run: node Model.test.js
process.env.TZ = "Europe/Ljubljana";
var assert = require("assert");
var M = require("./Model.js");

// -- mmss --
assert.strictEqual(M.mmss(0), "00:00");
assert.strictEqual(M.mmss(-5), "00:00");
assert.strictEqual(M.mmss(59), "00:59");
assert.strictEqual(M.mmss(60), "01:00");
assert.strictEqual(M.mmss(61), "01:01");
assert.strictEqual(M.mmss(1500), "25:00");
assert.strictEqual(M.mmss(3600), "60:00"); // no wrap past 60 min

// -- validMinutesOr --
assert.strictEqual(M.validMinutesOr(0, 25), 25);
assert.strictEqual(M.validMinutesOr(1, 25), 1);
assert.strictEqual(M.validMinutesOr(180, 25), 180);
assert.strictEqual(M.validMinutesOr(181, 25), 25); // falls back, does NOT clamp to 180
assert.strictEqual(M.validMinutesOr("abc", 25), 25);
assert.strictEqual(M.validMinutesOr(null, 25), 25);
assert.strictEqual(M.validMinutesOr(undefined, 25), 25);
assert.strictEqual(M.validMinutesOr(NaN, 25), 25);
assert.strictEqual(M.validMinutesOr(25.7, 25), 26); // rounds
assert.strictEqual(M.validMinutesOr(0.6, 25), 25); // raw value below range, not promoted by rounding
assert.strictEqual(M.validMinutesOr(180.4, 25), 25); // raw value above range, not promoted by rounding

// -- stepMinutes --
assert.strictEqual(M.stepMinutes(25, 5), 30); // step up
assert.strictEqual(M.stepMinutes(25, -5), 20); // step down
assert.strictEqual(M.stepMinutes(3, -5), 1); // clamps at MIN_MINUTES
assert.strictEqual(M.stepMinutes(178, 5), 180); // clamps at MAX_MINUTES
assert.strictEqual(M.stepMinutes(1, -5), 1); // already at lower bound, no-op
assert.strictEqual(M.stepMinutes(180, 5), 180); // already at upper bound, no-op
assert.strictEqual(M.stepMinutes(25, "abc"), 25); // non-numeric delta, no movement
assert.strictEqual(M.stepMinutes(25, Infinity), 25); // non-finite delta, no movement
assert.strictEqual(M.stepMinutes(0, 5), 30); // invalid value falls back to 25 first
assert.strictEqual(M.stepMinutes(25, 0.333), 25); // fractional delta rounds, does not leak a fraction

// -- adjustSession --
// remainingMs is milliseconds, never the ceil'd display seconds.
var MIN5 = 5 * 60 * 1000;
assert.deepStrictEqual(M.adjustSession(25, 25 * 60 * 1000, 5), { minutes: 30, appliedMs: MIN5 });
assert.deepStrictEqual(M.adjustSession(25, 25 * 60 * 1000, -5), { minutes: 20, appliedMs: -MIN5 });
assert.strictEqual(M.adjustSession(180, 60000, 5), null); // clamped at MAX, no-op
assert.strictEqual(M.adjustSession(1, 60000, -5), null); // clamped at MIN, no-op
assert.strictEqual(M.adjustSession(25, 0, 5), null); // deadline passed: complete, not extendable
assert.strictEqual(M.adjustSession(25, -1, 5), null); // deadline passed by a hair
assert.strictEqual(M.adjustSession(25, MIN5, -5), null); // would consume exactly what's left
assert.strictEqual(M.adjustSession(25, MIN5 - 1, -5), null); // would overshoot into the past
assert.deepStrictEqual(M.adjustSession(25, MIN5 + 1, -5), { minutes: 20, appliedMs: -MIN5 }); // 1ms to spare
assert.strictEqual(M.adjustSession(25, "abc", -5), null); // non-numeric remainder
assert.strictEqual(M.adjustSession(25, Infinity, -5), null); // non-finite remainder
// appliedMs tracks the *clamped* result, not the delta -- otherwise the
// history row stops matching the minutes actually counted down.
assert.deepStrictEqual(M.adjustSession(178, 60000, 5), { minutes: 180, appliedMs: 2 * 60 * 1000 });
assert.deepStrictEqual(M.adjustSession(4, 10 * 60 * 1000, -5), { minutes: 1, appliedMs: -3 * 60 * 1000 });

// -- wheelSteps --
assert.deepStrictEqual(M.wheelSteps(0, 120), { steps: 1, remainder: 0 }); // one notch
assert.deepStrictEqual(M.wheelSteps(0, -120), { steps: -1, remainder: 0 });
assert.deepStrictEqual(M.wheelSteps(0, 40), { steps: 0, remainder: 40 }); // sub-notch banks
assert.deepStrictEqual(M.wheelSteps(80, 40), { steps: 1, remainder: 0 }); // banked units add up
assert.deepStrictEqual(M.wheelSteps(0, 300), { steps: 2, remainder: 60 }); // flick: 2 steps, rest banked
assert.deepStrictEqual(M.wheelSteps(0, -300), { steps: -2, remainder: -60 }); // truncates toward zero
assert.deepStrictEqual(M.wheelSteps(100, -40), { steps: 0, remainder: 60 }); // reversal can't fire early
assert.deepStrictEqual(M.wheelSteps("abc", 120), { steps: 1, remainder: 0 }); // invalid accumulator
assert.deepStrictEqual(M.wheelSteps(50, "abc"), { steps: 0, remainder: 50 }); // invalid delta, bank kept
assert.deepStrictEqual(M.wheelSteps(50, NaN), { steps: 0, remainder: 50 });

// -- pushSession --
(function () {
    var h0 = [];
    var h1 = M.pushSession(h0, { startedAt: 1, minutes: 25 }, 50);
    assert.deepStrictEqual(h1, [{ startedAt: 1, minutes: 25 }]);
    assert.deepStrictEqual(h0, []); // non-mutation

    var h2 = M.pushSession(h1, { startedAt: 2, minutes: 25 }, 50);
    assert.deepStrictEqual(h2, [{ startedAt: 2, minutes: 25 }, { startedAt: 1, minutes: 25 }]);
    assert.deepStrictEqual(h1, [{ startedAt: 1, minutes: 25 }]); // still non-mutated

    // cap trimming
    var full = [{ startedAt: 9, minutes: 25 }, { startedAt: 8, minutes: 25 }];
    var trimmed = M.pushSession(full, { startedAt: 10, minutes: 25 }, 2);
    assert.strictEqual(trimmed.length, 2);
    assert.deepStrictEqual(trimmed, [{ startedAt: 10, minutes: 25 }, { startedAt: 9, minutes: 25 }]);
    assert.strictEqual(full.length, 2); // input untouched

    // omitted cap defaults to HISTORY_CAP, matching parseHistory's read-side
    // limit -- the write path must not be able to store more than the read
    // path will load back
    var over = [];
    for (var k = 0; k < M.HISTORY_CAP + 10; k++) over.push({ startedAt: k, minutes: 25 });
    assert.strictEqual(M.pushSession(over, { startedAt: 999, minutes: 25 }).length, M.HISTORY_CAP);
    assert.strictEqual(M.pushSession(over, { startedAt: 999, minutes: 25 })[0].startedAt, 999);
})();

// -- HISTORY_CAP: read and write paths agree --
assert.strictEqual(M.HISTORY_CAP, 2881);
// The cap must stay ABOVE the most pomodoros a local day can physically hold,
// or countToday() saturates and the cycle's long break stops arriving.
//
// Worst case is back-to-back work at MIN_MINUTES with NO break between them:
//   n*MIN <= dayMinutes  ->  n <= dayMinutes / MIN
// Budgeting a mandatory break per pomodoro would halve this and undersize the
// cap: skip() ends a break early, timer mode has no breaks, and autoStartBreaks
// can be off. dayMinutes is a deliberately absurd 48h rather than a real day
// length, because countToday groups by LOCAL day and a zone shifting its
// offset westward stretches one (Antarctica/Casey ran 27h in 2023).
// Derived here rather than hardcoded, so lowering the cap fails loudly.
(function () {
    var generousLocalDayMinutes = 48 * 60; // safety margin, not a real day
    var worstCasePerDay = Math.floor(generousLocalDayMinutes / M.MIN_MINUTES);
    assert.strictEqual(worstCasePerDay, 2880);
    assert.ok(M.HISTORY_CAP > worstCasePerDay,
        "HISTORY_CAP (" + M.HISTORY_CAP + ") must exceed the " + worstCasePerDay +
        " back-to-back pomodoros a generous local day can hold, or countToday saturates and long breaks stop");
    // The real-world day lengths it therefore covers, with room to spare.
    assert.ok(M.HISTORY_CAP > 1440, "an ordinary 24h day must fit");
    assert.ok(M.HISTORY_CAP > 1500, "a 25h DST fall-back day must fit");
    assert.ok(M.HISTORY_CAP > 1620, "a 27h Casey-style day must fit");
})();
(function () {
    var many = [];
    for (var i = 0; i < M.HISTORY_CAP + 10; i++) many.push({ startedAt: i + 1, minutes: 25 });
    var written = M.pushSession(many, { startedAt: 999, minutes: 25 });
    assert.strictEqual(M.parseHistory(M.serializeHistory(written)).length, written.length);
})();

// -- countToday --
(function () {
    var d = new Date(2026, 7, 16, 12, 0, 0); // Aug 16 2026, local noon
    var now = d.getTime();

    var midnight = new Date(2026, 7, 16, 0, 0, 1).getTime(); // same local day, near midnight
    var yesterdayLate = new Date(2026, 7, 15, 23, 59, 59).getTime(); // other day
    var tomorrow = new Date(2026, 7, 17, 0, 0, 1).getTime(); // other day

    var history = [
        { startedAt: midnight, minutes: 25 },
        { startedAt: yesterdayLate, minutes: 25 },
        { startedAt: tomorrow, minutes: 25 },
        { startedAt: now, minutes: 25 }
    ];
    assert.strictEqual(M.countToday(history, now), 2); // midnight entry + now entry
    assert.strictEqual(M.countToday([], now), 0);
    // asymmetric cases: local-day vs UTC-day diverge at UTC+2, unlike the aggregate count above
    assert.strictEqual(M.countToday([{ startedAt: midnight, minutes: 25 }, { startedAt: now, minutes: 25 }], now), 2);
    assert.strictEqual(M.countToday([{ startedAt: tomorrow, minutes: 25 }], now), 0);
    assert.strictEqual(M.countToday([{ startedAt: yesterdayLate, minutes: 25 }], now), 0);
    // pins month comparison: same day-of-month, different month, must not count
    assert.strictEqual(M.countToday([{ startedAt: new Date(2026, 6, 16, 12).getTime(), minutes: 25 }], now), 0);
})();

// -- groupByDay --
(function () {
    var now = new Date(2026, 10, 16, 12, 0, 0).getTime(); // Nov 16 2026, local noon
    var todayOne = { startedAt: new Date(2026, 10, 16, 15, 0, 0).getTime(), minutes: 25 };
    var todayTwo = { startedAt: new Date(2026, 10, 16, 9, 0, 0).getTime(), minutes: 25 };
    var yesterdayOne = { startedAt: new Date(2026, 10, 15, 23, 0, 0).getTime(), minutes: 25 };
    var yesterdayTwo = { startedAt: new Date(2026, 10, 15, 8, 0, 0).getTime(), minutes: 25 };
    var sep12One = { startedAt: new Date(2026, 8, 12, 18, 0, 0).getTime(), minutes: 25 };
    var sep12Two = { startedAt: new Date(2026, 8, 12, 7, 0, 0).getTime(), minutes: 25 };
    var sep3One = { startedAt: new Date(2026, 8, 3, 18, 0, 0).getTime(), minutes: 25 };
    var sep3Two = { startedAt: new Date(2026, 8, 3, 7, 0, 0).getTime(), minutes: 25 };
    var history = [
        todayOne, todayTwo, yesterdayOne, yesterdayTwo,
        sep12One, sep12Two, sep3One,
        { startedAt: NaN, minutes: 25 }, null,
        { startedAt: Infinity, minutes: 25 }, sep3Two
    ];

    assert.deepStrictEqual(M.groupByDay([], now), []);
    assert.deepStrictEqual(M.groupByDay(null, now), []);
    assert.deepStrictEqual(M.groupByDay(history, now), [
        { label: "TODAY", count: 2, sessions: [todayOne, todayTwo] },
        { label: "YESTERDAY", count: 2, sessions: [yesterdayOne, yesterdayTwo] },
        { label: "12. SEP", count: 2, sessions: [sep12One, sep12Two] },
        { label: "3. SEP", count: 2, sessions: [sep3One, sep3Two] }
    ]);
})();

(function () {
    // Mar 30 00:30 minus 24 hours lands on Mar 28 in Europe/Ljubljana.
    var now = new Date(2026, 2, 30, 0, 30, 0).getTime();
    var yesterday = { startedAt: new Date(2026, 2, 29, 23, 30, 0).getTime(), minutes: 25 };
    var older = { startedAt: new Date(2026, 2, 28, 23, 30, 0).getTime(), minutes: 25 };
    assert.deepStrictEqual(M.groupByDay([yesterday, older], now), [
        { label: "YESTERDAY", count: 1, sessions: [yesterday] },
        { label: "28. MAR", count: 1, sessions: [older] }
    ]);
})();

// -- parseHistory --
assert.deepStrictEqual(
    M.parseHistory('{"version":1,"sessions":[{"startedAt":1,"minutes":25}]}'),
    [{ startedAt: 1, minutes: 25 }]
);
assert.deepStrictEqual(M.parseHistory("not json{{{"), []);
assert.deepStrictEqual(M.parseHistory(""), []);
assert.deepStrictEqual(M.parseHistory(null), []);
assert.deepStrictEqual(M.parseHistory(undefined), []);
assert.deepStrictEqual(M.parseHistory("{}"), []);
assert.deepStrictEqual(M.parseHistory('{"sessions":"not-an-array"}'), []);
assert.deepStrictEqual(M.parseHistory('{"sessions":[{"minutes":25}]}'), []); // missing startedAt
assert.deepStrictEqual(M.parseHistory('{"sessions":[{"startedAt":"x","minutes":25}]}'), []); // NaN startedAt
assert.deepStrictEqual(
    M.parseHistory('{"sessions":[{"startedAt":1,"minutes":25},{"startedAt":"bad","minutes":1}]}'),
    [{ startedAt: 1, minutes: 25 }] // drops the bad entry, keeps the good one
);
assert.deepStrictEqual(M.parseHistory(42), []); // regression: coerces to "42", rejected downstream regardless of the guard
assert.deepStrictEqual(M.parseHistory({ sessions: [] }), []); // regression: coerces to "[object Object]", rejected downstream regardless of the guard
assert.deepStrictEqual(M.parseHistory({ toString: function () {
    return '{"sessions":[{"startedAt":1,"minutes":25}]}';
} }), []); // distinguishes the string-type guard: a coercible object must still be rejected, not stringified and parsed
// pins the output whitelist: unknown fields on an otherwise-valid entry must be dropped
assert.deepStrictEqual(M.parseHistory('{"sessions":[{"startedAt":1,"minutes":25,"evil":"x"}]}'), [{ startedAt: 1, minutes: 25 }]);
assert.deepStrictEqual(M.parseHistory("5"), []);
assert.deepStrictEqual(M.parseHistory('"str"'), []);
assert.deepStrictEqual(M.parseHistory('{"__proto__":{"polluted":1}}'), []);
assert.strictEqual({}.polluted, undefined);

// -- parseHistory: cap --
(function () {
    var sessions = [];
    for (var i = 10; i >= 1; i--) sessions.push({ startedAt: i, minutes: 25 });
    var text = JSON.stringify({ version: 1, sessions: sessions });
    var capped = M.parseHistory(text, 3);
    assert.strictEqual(capped.length, 3);
    // newest-first order preserved, entries beyond cap dropped
    assert.deepStrictEqual(capped, [{ startedAt: 10, minutes: 25 }, { startedAt: 9, minutes: 25 }, { startedAt: 8, minutes: 25 }]);
    // default cap (omitted) is HISTORY_CAP, not unbounded
    var many = [];
    for (var j = M.HISTORY_CAP + 10; j >= 1; j--) many.push({ startedAt: j, minutes: 25 });
    var defaultCapped = M.parseHistory(JSON.stringify({ version: 1, sessions: many }));
    assert.strictEqual(defaultCapped.length, M.HISTORY_CAP);
    assert.strictEqual(defaultCapped[0].startedAt, M.HISTORY_CAP + 10);
})();

// -- parseHistory: minutes integer/>=1 guard, no upper bound --
assert.deepStrictEqual(M.parseHistory('{"sessions":[{"startedAt":1,"minutes":-3.5}]}'), []); // negative
assert.deepStrictEqual(M.parseHistory('{"sessions":[{"startedAt":1,"minutes":0}]}'), []); // below 1
assert.deepStrictEqual(M.parseHistory('{"sessions":[{"startedAt":1,"minutes":1.5}]}'), []); // non-integer
assert.deepStrictEqual(M.parseHistory('{"sessions":[{"startedAt":1,"minutes":1}]}'), [{ startedAt: 1, minutes: 1 }]); // lower bound ok
assert.deepStrictEqual(M.parseHistory('{"sessions":[{"startedAt":1,"minutes":999}]}'), [{ startedAt: 1, minutes: 999 }]); // no upper bound

// -- serialize/parse round trip --
(function () {
    var history = [{ startedAt: 1762772400000, minutes: 25 }, { startedAt: 1762770000000, minutes: 25 }];
    var text = M.serializeHistory(history);
    assert.deepStrictEqual(M.parseHistory(text), history);
})();

// -- serializeHistory: pin the literal wire format from plan section 8 --
assert.strictEqual(
    M.serializeHistory([{ startedAt: 1, minutes: 25 }]),
    '{"version":1,"sessions":[{"startedAt":1,"minutes":25}]}'
);
assert.strictEqual(M.serializeHistory(null), '{"version":1,"sessions":[]}');

// -- surveyBarEntries --
(function () {
    var ID = "io.github.nejcm.pomodoro";
    var one = { left: [], center: [], right: [{ id: ID, minutes: 25 }] };
    assert.deepStrictEqual(M.surveyBarEntries(one, ID), { total: 1, writable: 1 });
    assert.deepStrictEqual(M.surveyBarEntries(one, "omarchy.clock"), { total: 0, writable: 0 });

    // The duplicate the settings write refuses on: same id twice in one
    // section, and split across two, which is the shape a hand-edit produces.
    assert.deepStrictEqual(M.surveyBarEntries({ right: [{ id: ID }, { id: ID }] }, ID), { total: 2, writable: 2 });
    assert.deepStrictEqual(M.surveyBarEntries({ left: [{ id: ID }], right: [{ id: ID }] }, ID), { total: 2, writable: 2 });
    assert.deepStrictEqual(M.surveyBarEntries({ left: [{ id: ID }], center: [{ id: ID }], right: [{ id: ID }] }, ID), { total: 3, writable: 3 });

    // A bare-string entry is a real entry the bar renders, and one the host's
    // updateEntryInline cannot target -- counted, but not writable. This is
    // the split the two fields exist for.
    assert.deepStrictEqual(M.surveyBarEntries({ center: [ID] }, ID), { total: 1, writable: 0 });
    assert.deepStrictEqual(M.surveyBarEntries({ center: [ID, { id: ID }] }, ID), { total: 2, writable: 1 });
    assert.deepStrictEqual(M.surveyBarEntries({ left: [ID], right: [ID] }, ID), { total: 2, writable: 0 });
    // A string that is not our id is somebody else's widget.
    assert.deepStrictEqual(M.surveyBarEntries({ center: ["omarchy.clock"], right: [{ id: ID }] }, ID), { total: 1, writable: 1 });

    // Sections the config omits, or fills with the wrong type, are skipped
    // rather than throwing -- shell.json is hand-edited.
    assert.deepStrictEqual(M.surveyBarEntries({ right: [{ id: ID }] }, ID), { total: 1, writable: 1 });
    assert.deepStrictEqual(M.surveyBarEntries({ left: "nope", right: [{ id: ID }] }, ID), { total: 1, writable: 1 });
    assert.deepStrictEqual(M.surveyBarEntries({ right: [null, 0, false, {}, { id: null }, [], { id: ID }] }, ID), { total: 1, writable: 1 });
    // A section the host does not render is not a place an entry can live.
    assert.deepStrictEqual(M.surveyBarEntries({ top: [{ id: ID }] }, ID), { total: 0, writable: 0 });

    // No layout, no id: zeroes rather than a throw, so a caller can ask
    // before the config has arrived.
    assert.deepStrictEqual(M.surveyBarEntries(null, ID), { total: 0, writable: 0 });
    assert.deepStrictEqual(M.surveyBarEntries(undefined, ID), { total: 0, writable: 0 });
    assert.deepStrictEqual(M.surveyBarEntries("nope", ID), { total: 0, writable: 0 });
    assert.deepStrictEqual(M.surveyBarEntries(one, ""), { total: 0, writable: 0 });
    assert.deepStrictEqual(M.surveyBarEntries(one, null), { total: 0, writable: 0 });
})();

// -- mode/phase constants: the literal strings that land in shell.json --
// Renaming one of these silently changes the on-disk config contract.
assert.strictEqual(M.MODE_TIMER, "timer");
assert.strictEqual(M.MODE_POMODORO, "pomodoro");
assert.strictEqual(M.PHASE_WORK, "work");
assert.strictEqual(M.PHASE_SHORT, "short");
assert.strictEqual(M.PHASE_LONG, "long");
assert.strictEqual(M.DEFAULT_BREAK_MINUTES, 5);
assert.strictEqual(M.DEFAULT_LONG_BREAK_MINUTES, 15);
assert.strictEqual(M.DEFAULT_CYCLES, 4);
assert.strictEqual(M.MIN_CYCLES, 1);
assert.strictEqual(M.MAX_CYCLES, 12);

// -- validModeOr --
assert.strictEqual(M.validModeOr("timer", "timer"), "timer");
assert.strictEqual(M.validModeOr("pomodoro", "timer"), "pomodoro");
assert.strictEqual(M.validModeOr("Pomodoro", "timer"), "timer"); // case-sensitive, no coercion
assert.strictEqual(M.validModeOr("", "timer"), "timer");
assert.strictEqual(M.validModeOr("nonsense", "pomodoro"), "pomodoro"); // fallback is whatever the caller passed
assert.strictEqual(M.validModeOr(null, "timer"), "timer");
assert.strictEqual(M.validModeOr(undefined, "timer"), "timer");
assert.strictEqual(M.validModeOr(0, "timer"), "timer");
assert.strictEqual(M.validModeOr(true, "timer"), "timer");

// -- validCyclesOr --
// Same fall-back-don't-clamp contract as validMinutesOr.
assert.strictEqual(M.validCyclesOr(4, 4), 4);
assert.strictEqual(M.validCyclesOr(1, 4), 1);
assert.strictEqual(M.validCyclesOr(12, 4), 12);
assert.strictEqual(M.validCyclesOr(0, 4), 4); // below range
assert.strictEqual(M.validCyclesOr(13, 4), 4); // falls back, does NOT clamp to 12
assert.strictEqual(M.validCyclesOr(-3, 4), 4);
assert.strictEqual(M.validCyclesOr("4", 4), 4); // no string coercion
assert.strictEqual(M.validCyclesOr(null, 4), 4);
assert.strictEqual(M.validCyclesOr(undefined, 4), 4);
assert.strictEqual(M.validCyclesOr(NaN, 4), 4);
assert.strictEqual(M.validCyclesOr(Infinity, 4), 4);
assert.strictEqual(M.validCyclesOr(3.6, 4), 4); // rounds
assert.strictEqual(M.validCyclesOr(0.6, 4), 4); // raw value below range, not promoted by rounding
assert.strictEqual(M.validCyclesOr(12.4, 4), 4); // raw value above range, not promoted by rounding

// -- phaseMinutes --
(function () {
    var s = { minutes: 30, breakMinutes: 7, longBreakMinutes: 20 };
    assert.strictEqual(M.phaseMinutes(M.PHASE_WORK, s), 30);
    assert.strictEqual(M.phaseMinutes(M.PHASE_SHORT, s), 7);
    assert.strictEqual(M.phaseMinutes(M.PHASE_LONG, s), 20);

    // Each key falls back to its OWN default, never to another phase's number.
    assert.strictEqual(M.phaseMinutes(M.PHASE_WORK, { minutes: 2500 }), 25);
    assert.strictEqual(M.phaseMinutes(M.PHASE_SHORT, { breakMinutes: "abc" }), 5);
    assert.strictEqual(M.phaseMinutes(M.PHASE_LONG, { longBreakMinutes: 0 }), 15);
    assert.strictEqual(M.phaseMinutes(M.PHASE_SHORT, { minutes: 30 }), 5); // work's value must not leak into a break
    assert.strictEqual(M.phaseMinutes(M.PHASE_LONG, { breakMinutes: 7 }), 15);

    // Total: no settings at all, and an unknown phase, still answer.
    assert.strictEqual(M.phaseMinutes(M.PHASE_WORK, {}), 25);
    assert.strictEqual(M.phaseMinutes(M.PHASE_SHORT, null), 5);
    assert.strictEqual(M.phaseMinutes(M.PHASE_LONG, undefined), 15);
    assert.strictEqual(M.phaseMinutes("nonsense", s), 30); // unknown phase is treated as work
    assert.strictEqual(M.phaseMinutes(undefined, undefined), 25);
})();

// -- nextPhase --
// pomodorosToday counts the pomodoro just finished.
assert.strictEqual(M.nextPhase(M.PHASE_SHORT, 3, 4), M.PHASE_WORK); // any break is followed by work
assert.strictEqual(M.nextPhase(M.PHASE_LONG, 4, 4), M.PHASE_WORK);
assert.strictEqual(M.nextPhase(M.PHASE_SHORT, 0, 1), M.PHASE_WORK); // regardless of the count
assert.strictEqual(M.nextPhase(M.PHASE_WORK, 1, 4), M.PHASE_SHORT);
assert.strictEqual(M.nextPhase(M.PHASE_WORK, 2, 4), M.PHASE_SHORT);
assert.strictEqual(M.nextPhase(M.PHASE_WORK, 3, 4), M.PHASE_SHORT);
assert.strictEqual(M.nextPhase(M.PHASE_WORK, 4, 4), M.PHASE_LONG);
// The counter rolls past the long break and keeps cycling.
assert.strictEqual(M.nextPhase(M.PHASE_WORK, 5, 4), M.PHASE_SHORT);
assert.strictEqual(M.nextPhase(M.PHASE_WORK, 7, 4), M.PHASE_SHORT);
assert.strictEqual(M.nextPhase(M.PHASE_WORK, 8, 4), M.PHASE_LONG);
assert.strictEqual(M.nextPhase(M.PHASE_WORK, 9, 4), M.PHASE_SHORT);
assert.strictEqual(M.nextPhase(M.PHASE_WORK, 12, 4), M.PHASE_LONG);
// cyclesBeforeLongBreak of 1: every break is the long one.
assert.strictEqual(M.nextPhase(M.PHASE_WORK, 1, 1), M.PHASE_LONG);
assert.strictEqual(M.nextPhase(M.PHASE_WORK, 2, 1), M.PHASE_LONG);
assert.strictEqual(M.nextPhase(M.PHASE_WORK, 7, 1), M.PHASE_LONG);
// A zero count means no work interval was logged: nothing to reward yet.
// Bare `0 % n === 0` would hand out a long break here.
assert.strictEqual(M.nextPhase(M.PHASE_WORK, 0, 4), M.PHASE_SHORT);
assert.strictEqual(M.nextPhase(M.PHASE_WORK, 0, 1), M.PHASE_SHORT);
// Garbage counts and cycle counts fall back rather than throwing.
assert.strictEqual(M.nextPhase(M.PHASE_WORK, -2, 4), M.PHASE_SHORT);
assert.strictEqual(M.nextPhase(M.PHASE_WORK, "3", 4), M.PHASE_SHORT);
assert.strictEqual(M.nextPhase(M.PHASE_WORK, NaN, 4), M.PHASE_SHORT);
assert.strictEqual(M.nextPhase(M.PHASE_WORK, 4, 0), M.PHASE_LONG); // cycles falls back to 4
assert.strictEqual(M.nextPhase(M.PHASE_WORK, 4, 99), M.PHASE_LONG);
assert.strictEqual(M.nextPhase(M.PHASE_WORK, 4, undefined), M.PHASE_LONG);
assert.strictEqual(M.nextPhase(M.PHASE_WORK, 3, "1"), M.PHASE_SHORT); // "1" is not 1: falls back to 4
assert.strictEqual(M.nextPhase("nonsense", 4, 4), M.PHASE_LONG); // unknown phase is treated as work

// -- phaseLabel --
assert.strictEqual(M.phaseLabel(M.PHASE_WORK), "Focus");
assert.strictEqual(M.phaseLabel(M.PHASE_SHORT), "Short break");
assert.strictEqual(M.phaseLabel(M.PHASE_LONG), "Long break");
assert.strictEqual(M.phaseLabel("nonsense"), "Focus"); // degrades to timer-mode wording, never blank
assert.strictEqual(M.phaseLabel(undefined), "Focus");

// -- cyclePosition --
// The position of the NEXT pomodoro, so the dots show the cycle about to be
// worked. Wraps straight back to 1 after the long break.
assert.strictEqual(M.cyclePosition(0, 4), 1);
assert.strictEqual(M.cyclePosition(1, 4), 2);
assert.strictEqual(M.cyclePosition(2, 4), 3);
assert.strictEqual(M.cyclePosition(3, 4), 4);
assert.strictEqual(M.cyclePosition(4, 4), 1); // long break just earned, cycle restarts
assert.strictEqual(M.cyclePosition(5, 4), 2);
assert.strictEqual(M.cyclePosition(8, 4), 1);
// Never leaves 1..cyclesBeforeLong.
assert.strictEqual(M.cyclePosition(0, 1), 1);
assert.strictEqual(M.cyclePosition(7, 1), 1);
assert.strictEqual(M.cyclePosition(11, 12), 12);
assert.strictEqual(M.cyclePosition(12, 12), 1);
// Garbage in, a usable dot position out.
assert.strictEqual(M.cyclePosition("x", 4), 1);
assert.strictEqual(M.cyclePosition(-5, 4), 1);
assert.strictEqual(M.cyclePosition(NaN, 4), 1);
assert.strictEqual(M.cyclePosition(5, 0), 2); // cycles falls back to 4
assert.strictEqual(M.cyclePosition(undefined, undefined), 1);

// -- completion: timer mode is the regression guard for existing users --
(function () {
    var state = { phase: M.PHASE_WORK, sessionStartedAt: 1700000000000, sessionMinutes: 25, pomodorosToday: 3 };
    var expected = {
        log: { startedAt: 1700000000000, minutes: 25 },
        notify: { title: "Pomodoro complete", body: "25 minute session done" },
        next: { phase: M.PHASE_WORK, minutes: 25 },
        autoStart: false
    };
    // An install with no `mode` key behaves exactly as the plugin always has:
    // a history row, the same notification copy, back to an idle work phase.
    assert.deepStrictEqual(M.completion(state, {}), expected);
    assert.deepStrictEqual(M.completion(state, { minutes: 25 }), expected);
    assert.deepStrictEqual(M.completion(state, { mode: "timer", minutes: 25 }), expected);
    assert.deepStrictEqual(M.completion(state, { mode: "nonsense", minutes: 25 }), expected);

    // Timer mode cannot reach a break, whatever the count says.
    for (var n = 0; n <= 12; n++) {
        var out = M.completion({ phase: M.PHASE_WORK, sessionStartedAt: 1, sessionMinutes: 25, pomodorosToday: n }, {});
        assert.strictEqual(out.next.phase, M.PHASE_WORK);
        assert.strictEqual(out.autoStart, false);
    }
    // ...nor auto-start, even if the cycle's auto-start keys are present.
    var eager = M.completion(state, { autoStartBreaks: true, autoStartWork: true });
    assert.strictEqual(eager.next.phase, M.PHASE_WORK);
    assert.strictEqual(eager.autoStart, false);

    // Timer mode's guarantee is that it never ADVANCES INTO a break -- not
    // that it reinterprets one it is handed. A break session handed to the
    // timer path is still a break: see the break-identity section below.
    var stray = M.completion({ phase: M.PHASE_SHORT, sessionStartedAt: 1, sessionMinutes: 25, pomodorosToday: 3 }, { mode: "timer" });
    assert.strictEqual(stray.next.phase, M.PHASE_WORK);
    assert.strictEqual(stray.log, null);
})();

// -- completion: notify honours the existing `notify` key --
(function () {
    var state = { phase: M.PHASE_WORK, sessionStartedAt: 1, sessionMinutes: 25, pomodorosToday: 0 };
    // Service.qml applies `src.notify !== false`: absent means on.
    assert.notStrictEqual(M.completion(state, {}).notify, null);
    assert.notStrictEqual(M.completion(state, { notify: true }).notify, null);
    assert.strictEqual(M.completion(state, { notify: false }).notify, null);
    assert.notStrictEqual(M.completion(state, { notify: 0 }).notify, null); // only an explicit false silences it
    // Silencing the notification must not cost the history row.
    assert.deepStrictEqual(M.completion(state, { notify: false }).log, { startedAt: 1, minutes: 25 });
    // The body quotes the session that actually ran, not the armed duration.
    var short = { phase: M.PHASE_WORK, sessionStartedAt: 1, sessionMinutes: 3, pomodorosToday: 0 };
    assert.deepStrictEqual(M.completion(short, { minutes: 25 }).notify,
        { title: "Pomodoro complete", body: "3 minute session done" });
})();

// -- completion: the cycle in pomodoro mode --
(function () {
    var cfg = { mode: "pomodoro", minutes: 25, breakMinutes: 5, longBreakMinutes: 15, cyclesBeforeLongBreak: 4 };
    var work = function (n) {
        return M.completion({ phase: M.PHASE_WORK, sessionStartedAt: 1700000000000, sessionMinutes: 25, pomodorosToday: n }, cfg);
    };

    // pomodorosToday is the count BEFORE this session is logged, so a
    // pre-log 3 is the 4th pomodoro and earns the long break.
    assert.deepStrictEqual(work(0).next, { phase: M.PHASE_SHORT, minutes: 5 });
    assert.deepStrictEqual(work(1).next, { phase: M.PHASE_SHORT, minutes: 5 });
    assert.deepStrictEqual(work(2).next, { phase: M.PHASE_SHORT, minutes: 5 });
    assert.deepStrictEqual(work(3).next, { phase: M.PHASE_LONG, minutes: 15 });
    // ...and the counter rolls past it.
    assert.deepStrictEqual(work(4).next, { phase: M.PHASE_SHORT, minutes: 5 });
    assert.deepStrictEqual(work(7).next, { phase: M.PHASE_LONG, minutes: 15 });
    assert.deepStrictEqual(work(8).next, { phase: M.PHASE_SHORT, minutes: 5 });

    // Every work interval is logged with the same copy as timer mode.
    assert.deepStrictEqual(work(3).log, { startedAt: 1700000000000, minutes: 25 });
    assert.deepStrictEqual(work(3).notify, { title: "Pomodoro complete", body: "25 minute session done" });

    // cyclesBeforeLongBreak of 1: every break is the long one.
    var one = { mode: "pomodoro", cyclesBeforeLongBreak: 1 };
    for (var n = 0; n <= 5; n++) {
        var out = M.completion({ phase: M.PHASE_WORK, sessionStartedAt: 1, sessionMinutes: 25, pomodorosToday: n }, one);
        assert.strictEqual(out.next.phase, M.PHASE_LONG);
        assert.strictEqual(out.next.minutes, 15); // default long break
    }

    // next.minutes comes from phaseMinutes, so a garbage duration falls back
    // to that phase's default rather than blocking the transition.
    var junk = { mode: "pomodoro", breakMinutes: "abc", longBreakMinutes: 9999, cyclesBeforeLongBreak: 4 };
    assert.deepStrictEqual(M.completion({ phase: M.PHASE_WORK, sessionStartedAt: 1, sessionMinutes: 25, pomodorosToday: 0 }, junk).next,
        { phase: M.PHASE_SHORT, minutes: 5 });
    assert.deepStrictEqual(M.completion({ phase: M.PHASE_WORK, sessionStartedAt: 1, sessionMinutes: 25, pomodorosToday: 3 }, junk).next,
        { phase: M.PHASE_LONG, minutes: 15 });
})();

// -- completion: the pre-log pomodorosToday convention, pinned --
// Service.qml must call completion() BEFORE pushing the row. If it ever
// pushes first, the count arrives one too high and every long break lands a
// pomodoro early -- these two assertions are what catches that.
(function () {
    var cfg = { mode: "pomodoro", cyclesBeforeLongBreak: 4 };
    var at = function (n) {
        return M.completion({ phase: M.PHASE_WORK, sessionStartedAt: 1, sessionMinutes: 25, pomodorosToday: n }, cfg).next.phase;
    };
    // Three rows already on disk + the one being logged now = the 4th.
    assert.strictEqual(at(3), M.PHASE_LONG);
    // Four rows already on disk would mean this is the 5th, not the 4th.
    assert.strictEqual(at(4), M.PHASE_SHORT);
})();

// -- completion: a break ends without a log row or a counter change --
(function () {
    var cfg = { mode: "pomodoro", minutes: 25, breakMinutes: 5, longBreakMinutes: 15, cyclesBeforeLongBreak: 4 };
    var breakDone = function (phase, n) {
        return M.completion({ phase: phase, sessionStartedAt: 1700000000000, sessionMinutes: 5, pomodorosToday: n }, cfg);
    };

    // A pomodoro is a completed WORK interval: breaks are never logged, which
    // is also what keeps the cycle position still across a break.
    assert.strictEqual(breakDone(M.PHASE_SHORT, 3).log, null);
    assert.strictEqual(breakDone(M.PHASE_LONG, 4).log, null);
    assert.deepStrictEqual(breakDone(M.PHASE_SHORT, 3).next, { phase: M.PHASE_WORK, minutes: 25 });
    assert.deepStrictEqual(breakDone(M.PHASE_LONG, 4).next, { phase: M.PHASE_WORK, minutes: 25 });
    // No log row means countToday is unmoved across the break, so the dots
    // hold their position -- and the work interval that follows the break
    // lands on the same next-phase decision the break was born from.
    assert.strictEqual(breakDone(M.PHASE_SHORT, 3).log, null);
    assert.strictEqual(M.cyclePosition(3, 4), 4);
    assert.strictEqual(M.nextPhase(M.PHASE_WORK, 4, 4), M.PHASE_LONG);

    // Breaks get their own copy, and still respect `notify`.
    assert.deepStrictEqual(breakDone(M.PHASE_SHORT, 3).notify, { title: "Break over", body: "Time to focus" });
    assert.strictEqual(M.completion({ phase: M.PHASE_SHORT, sessionStartedAt: 1, sessionMinutes: 5, pomodorosToday: 3 },
        { mode: "pomodoro", notify: false }).notify, null);
})();

// -- completion: auto-advance defaults --
(function () {
    var state = function (phase) {
        return { phase: phase, sessionStartedAt: 1, sessionMinutes: 25, pomodorosToday: 0 };
    };
    // Breaks roll on by themselves; work waits for a press.
    assert.strictEqual(M.completion(state(M.PHASE_WORK), { mode: "pomodoro" }).autoStart, true);
    assert.strictEqual(M.completion(state(M.PHASE_SHORT), { mode: "pomodoro" }).autoStart, false);
    // A missing key lands on the default, not on undefined.
    assert.strictEqual(M.completion(state(M.PHASE_WORK), { mode: "pomodoro", autoStartBreaks: false }).autoStart, false);
    assert.strictEqual(M.completion(state(M.PHASE_SHORT), { mode: "pomodoro", autoStartWork: true }).autoStart, true);
    // autoStart follows the phase being advanced TO, not the one that ended.
    assert.strictEqual(M.completion(state(M.PHASE_WORK), { mode: "pomodoro", autoStartWork: true }).autoStart, true);
    assert.strictEqual(M.completion(state(M.PHASE_WORK), { mode: "pomodoro", autoStartBreaks: false, autoStartWork: true }).autoStart, false);
    assert.strictEqual(M.completion(state(M.PHASE_LONG), { mode: "pomodoro", autoStartBreaks: true }).autoStart, false);
})();

// -- completion: total on garbage state --
(function () {
    var cfg = { mode: "pomodoro", cyclesBeforeLongBreak: 4 };
    // A session that never really ran must not write a junk history row.
    assert.strictEqual(M.completion(null, cfg).log, null);
    assert.strictEqual(M.completion(undefined, undefined).log, null);
    assert.strictEqual(M.completion({ phase: M.PHASE_WORK }, cfg).log, null);
    assert.strictEqual(M.completion({ phase: M.PHASE_WORK, sessionStartedAt: 1, sessionMinutes: "abc", pomodorosToday: 0 }, cfg).log, null);
    assert.strictEqual(M.completion({ phase: M.PHASE_WORK, sessionStartedAt: NaN, sessionMinutes: 25, pomodorosToday: 0 }, cfg).log, null);
    // ...but still answers with a usable next phase.
    assert.deepStrictEqual(M.completion(undefined, undefined).next, { phase: M.PHASE_WORK, minutes: 25 });
})();

// -- skip: a skipped break is never logged --
(function () {
    var cfg = { mode: "pomodoro", minutes: 30, breakMinutes: 5, longBreakMinutes: 15 };
    var expected = { log: null, notify: null, next: { phase: M.PHASE_WORK, minutes: 30 }, autoStart: false };

    assert.deepStrictEqual(M.skip({ phase: M.PHASE_SHORT, sessionStartedAt: 1, sessionMinutes: 5, pomodorosToday: 3 }, cfg), expected);
    assert.deepStrictEqual(M.skip({ phase: M.PHASE_LONG, sessionStartedAt: 1, sessionMinutes: 15, pomodorosToday: 4 }, cfg), expected);
    // Skipping always lands on work ARMED, never running: autoStartWork does
    // not apply to a break the user cut short. A skip is "I am done resting",
    // not a request to be thrown straight into the next countdown.
    assert.strictEqual(M.skip({ phase: M.PHASE_SHORT }, { mode: "pomodoro", autoStartWork: true }).autoStart, false);
    assert.strictEqual(M.skip({ phase: M.PHASE_LONG }, { mode: "pomodoro", autoStartWork: true }).autoStart, false);
    assert.strictEqual(M.skip({ phase: M.PHASE_SHORT }, { mode: "pomodoro", autoStartWork: true, autoStartBreaks: true }).autoStart, false);
    assert.strictEqual(M.skip({ phase: M.PHASE_SHORT }, { autoStartWork: true }).autoStart, false);
    // Contrast: a break allowed to RUN OUT still honours autoStartWork. The
    // two paths differ deliberately.
    assert.strictEqual(M.completion({ phase: M.PHASE_SHORT, sessionStartedAt: 1, sessionMinutes: 5, pomodorosToday: 0 },
        { mode: "pomodoro", autoStartWork: true }).autoStart, true);

    // Service guards this off-break, but a stray call must not invent a row.
    assert.strictEqual(M.skip({ phase: M.PHASE_WORK, sessionStartedAt: 1, sessionMinutes: 25, pomodorosToday: 3 }, cfg).log, null);
    assert.strictEqual(M.skip(null, null).log, null);
    assert.strictEqual(M.skip(undefined, undefined).notify, null);
    assert.deepStrictEqual(M.skip(null, null).next, { phase: M.PHASE_WORK, minutes: 25 });
})();

// -- the cycle keeps rolling past every cap this file has had --
// Two undersized caps froze countToday() here before: 50 (the original) and
// 751 (a derivation that wrongly budgeted a mandatory break per pomodoro).
// Past a saturated count every completion recomputes the same position and
// the long break never arrives again. Runs back-to-back with no breaks --
// the case that actually fills the array fastest.
(function () {
    var midnight = new Date(2026, 7, 23, 0, 0, 0).getTime();
    var cfg = { mode: "pomodoro", cyclesBeforeLongBreak: 4 };
    var history = [];
    var t = midnight;
    var phases = [];

    // Drive the real Service loop: completion() first, then push the row.
    for (var i = 1; i <= 800; i++) {
        var pre = M.countToday(history, t);
        var out = M.completion({ phase: M.PHASE_WORK, sessionStartedAt: t, sessionMinutes: 1, pomodorosToday: pre }, cfg);
        history = M.pushSession(history, out.log);
        phases.push(out.next.phase);
        t += 60 * 1000;
    }

    // Nothing was evicted, so the count is the true one.
    assert.strictEqual(history.length, 800);
    assert.strictEqual(M.countToday(history, t), 800);

    // Every 4th pomodoro earns the long break, all the way out.
    for (var n = 1; n <= 800; n++) {
        assert.strictEqual(phases[n - 1], n % 4 === 0 ? M.PHASE_LONG : M.PHASE_SHORT,
            "pomodoro " + n + " got the wrong next phase");
    }
    // The three points where an undersized cap showed itself.
    assert.strictEqual(phases[51], M.PHASE_LONG); // 52nd: froze to short under cap 50
    assert.strictEqual(phases[751], M.PHASE_LONG); // 752nd: froze to short under cap 751
    assert.strictEqual(phases[799], M.PHASE_LONG); // 800th

    // Still today-scoped: tomorrow starts the cycle over.
    assert.strictEqual(M.countToday(history, t + 24 * 60 * 60 * 1000), 0);
})();

// -- an ordinary day packed back-to-back still fits under the cap --
// The bound exercised end to end rather than asserted arithmetically. No
// breaks at all -- every minute of the day is a 1-minute work interval, which
// skip() and timer mode both make reachable. An ordinary 1440-minute day
// holds 1440 of them; the 25-hour DST day pushes the worst case to 1500.
(function () {
    var midnight = new Date(2026, 7, 23, 0, 0, 0).getTime();
    var t = midnight;
    var history = [];
    for (var i = 0; i < 1440; i++) {
        history = M.pushSession(history, { startedAt: t, minutes: 1 });
        t += 60 * 1000; // back-to-back, no break
    }
    // Every row landed inside the one local day, and none was evicted.
    assert.strictEqual(history.length, 1440);
    assert.ok(history.length < M.HISTORY_CAP, "a back-to-back day must not reach the cap");
    assert.strictEqual(M.countToday(history, midnight + 12 * 60 * 60 * 1000), 1440);
    // The count is exact, so the last pomodoro of the day still cycles right.
    assert.strictEqual(M.nextPhase(M.PHASE_WORK, 1440, 4), M.PHASE_LONG); // 1440 % 4 === 0
    assert.strictEqual(M.nextPhase(M.PHASE_WORK, 1438, 4), M.PHASE_SHORT);
    // And the generous 48h bound the cap was actually sized for clears it.
    assert.ok(2880 < M.HISTORY_CAP, "the 48-hour safety bound must fit as well");
})();

// -- break identity survives a mode change --
// Reachable, not theoretical: with autoStartBreaks off, a finished work
// interval leaves the timer idle but ARMED on a break. Armed is neither
// running nor paused, so Phase D2's mode switch is live and the user can flip
// to Timer while a break sits armed. If completion() decided from the current
// mode it would log that break as a pomodoro and announce it as work, which
// is the one thing "breaks are never logged" exists to prevent.
(function () {
    var armedBreak = function (phase, cfg) {
        return M.completion({ phase: phase, sessionStartedAt: 1700000000000, sessionMinutes: 5, pomodorosToday: 3 }, cfg);
    };

    [M.PHASE_SHORT, M.PHASE_LONG].forEach(function (phase) {
        // Whatever mode currently reads, a break is a break.
        ["timer", "pomodoro", "nonsense", undefined].forEach(function (mode) {
            var out = armedBreak(phase, { mode: mode });
            assert.strictEqual(out.log, null, phase + " under mode=" + mode + " must not be logged");
            assert.deepStrictEqual(out.notify, { title: "Break over", body: "Time to focus" },
                phase + " under mode=" + mode + " must not send the work notification");
            assert.strictEqual(out.next.phase, M.PHASE_WORK);
        });
    });

    // The specific regression: a 5-minute break must never become a pomodoro
    // row, and must never claim "5 minute session done".
    var flipped = armedBreak(M.PHASE_SHORT, { mode: "timer", minutes: 25, breakMinutes: 5 });
    assert.strictEqual(flipped.log, null);
    assert.notStrictEqual(flipped.notify.body, "5 minute session done");
    assert.deepStrictEqual(flipped.next, { phase: M.PHASE_WORK, minutes: 25 });

    // Timer mode still never auto-starts, even settling a stray break.
    assert.strictEqual(armedBreak(M.PHASE_SHORT, { mode: "timer", autoStartWork: true }).autoStart, false);
    assert.strictEqual(armedBreak(M.PHASE_LONG, { mode: "timer", autoStartWork: true }).autoStart, false);
    // ...while pomodoro mode still honours autoStartWork on a completed break.
    assert.strictEqual(armedBreak(M.PHASE_SHORT, { mode: "pomodoro", autoStartWork: true }).autoStart, true);

    // A break silenced by `notify` is still not logged.
    assert.strictEqual(armedBreak(M.PHASE_LONG, { mode: "timer", notify: false }).log, null);
    assert.strictEqual(armedBreak(M.PHASE_LONG, { mode: "timer", notify: false }).notify, null);

    // The converse still holds: a WORK session in pomodoro mode is logged and
    // announced as work, so this fix did not blunt the work path.
    var work = M.completion({ phase: M.PHASE_WORK, sessionStartedAt: 1, sessionMinutes: 25, pomodorosToday: 3 }, { mode: "pomodoro" });
    assert.deepStrictEqual(work.log, { startedAt: 1, minutes: 25 });
    assert.strictEqual(work.notify.title, "Pomodoro complete");
})();

// -- the count a transition decides against survives midnight --
// History rows are dated by startedAt, so a session begun before local
// midnight and finished after it belongs to YESTERDAY and countToday() will
// not see it. The invariant: the count completion() decided against must
// equal countToday() of the history the instant after the row is pushed --
// otherwise the dots and the very next completion contradict the decision
// just made.
//
// Note cyclesBeforeLongBreak is swept, not fixed at 4. Crossing midnight the
// true count is 0 and the inflated one is 1, and BOTH map to a short break at
// 4 -- the discrepancy is only observable at 1, where 0 is short and 1 is
// long. A test pinned to 4 passes with the bug still in.
(function () {
    // The real invariant, asserted as an equality rather than via a symptom:
    // the phase chosen must be the phase the post-push count implies.
    var check = function (history, startedAt, nowMs, cycles, label) {
        var cfg = { mode: "pomodoro", cyclesBeforeLongBreak: cycles };
        var pre = M.countToday(history, nowMs);
        var out = M.completion({ phase: M.PHASE_WORK, sessionStartedAt: startedAt, sessionMinutes: 5, pomodorosToday: pre, nowMs: nowMs }, cfg);
        var after = M.pushSession(history, out.log);
        var countAfter = M.countToday(after, nowMs);
        assert.strictEqual(out.next.phase, M.nextPhase(M.PHASE_WORK, countAfter, cycles),
            label + " (cycles=" + cycles + "): transition disagrees with countToday() after the push");
        return { out: out, after: after, countAfter: countAfter };
    };

    // Three pomodoros already logged yesterday evening.
    var y = [];
    var eve = new Date(2026, 7, 23, 21, 0, 0).getTime();
    for (var i = 0; i < 3; i++) y = M.pushSession(y, { startedAt: eve + i * 60000, minutes: 25 });

    var startedAt = new Date(2026, 7, 23, 23, 58, 0).getTime();
    var nowMs = new Date(2026, 7, 24, 0, 3, 0).getTime();

    // The discriminating case: at cycles=1 an inflated count claims the long
    // break for a pomodoro today has no record of.
    var one = check(y, startedAt, nowMs, 1, "23:58 -> 00:03");
    assert.strictEqual(one.countAfter, 0); // the row landed on yesterday
    assert.strictEqual(one.out.next.phase, M.PHASE_SHORT); // NOT long
    // The row itself is still logged, dated by when it started.
    assert.deepStrictEqual(one.out.log, { startedAt: startedAt, minutes: 5 });
    assert.strictEqual(M.countToday(one.after, startedAt), 4); // yesterday now has 4

    // Control: the same session finishing on the day it started still counts,
    // at every cycle length.
    var sameDayStart = new Date(2026, 7, 23, 23, 40, 0).getTime();
    var sameDayNow = new Date(2026, 7, 23, 23, 45, 0).getTime();
    assert.strictEqual(check(y, sameDayStart, sameDayNow, 4, "same-day control").countAfter, 4);
    assert.strictEqual(check(y, sameDayStart, sameDayNow, 4, "same-day control").out.next.phase, M.PHASE_LONG);
    assert.strictEqual(check(y, sameDayStart, sameDayNow, 1, "same-day control").out.next.phase, M.PHASE_LONG);

    // The invariant holds walking a session across the boundary minute by
    // minute, on both sides, at every cycle length that can expose it.
    var midnight = new Date(2026, 7, 24, 0, 0, 0).getTime();
    [1, 2, 3, 4].forEach(function (cycles) {
        for (var m = -5; m <= 5; m++) {
            check(y, startedAt, midnight + m * 60000, cycles, "boundary " + m);
            check(y, midnight + m * 60000, midnight + 6 * 60000, cycles, "started near boundary " + m);
        }
    });

    // A garbage session logs nothing, so it must not move the count either.
    var g = M.completion({ phase: M.PHASE_WORK, sessionStartedAt: NaN, sessionMinutes: 25, pomodorosToday: 3, nowMs: nowMs },
        { mode: "pomodoro", cyclesBeforeLongBreak: 4 });
    assert.strictEqual(g.log, null);
    assert.strictEqual(g.next.phase, M.nextPhase(M.PHASE_WORK, 3, 4)); // 3, not 4
    assert.strictEqual(g.next.phase, M.PHASE_SHORT);

    // nowMs omitted: assume the session finished on the day it started, which
    // is what every same-day caller gets and what this did before the field.
    var noClock = M.completion({ phase: M.PHASE_WORK, sessionStartedAt: 1, sessionMinutes: 25, pomodorosToday: 3 },
        { mode: "pomodoro", cyclesBeforeLongBreak: 4 });
    assert.strictEqual(noClock.next.phase, M.PHASE_LONG);
})();

console.log("Model.test.js: all assertions passed");
