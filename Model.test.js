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
assert.strictEqual(M.HISTORY_CAP, 50);
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
    // default cap (omitted) is 50, not unbounded
    var many = [];
    for (var j = 100; j >= 1; j--) many.push({ startedAt: j, minutes: 25 });
    var defaultCapped = M.parseHistory(JSON.stringify({ version: 1, sessions: many }));
    assert.strictEqual(defaultCapped.length, 50);
    assert.strictEqual(defaultCapped[0].startedAt, 100);
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

console.log("Model.test.js: all assertions passed");
