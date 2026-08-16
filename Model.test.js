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

// -- clampMinutes --
assert.strictEqual(M.clampMinutes(0, 25), 25);
assert.strictEqual(M.clampMinutes(1, 25), 1);
assert.strictEqual(M.clampMinutes(180, 25), 180);
assert.strictEqual(M.clampMinutes(181, 25), 25);
assert.strictEqual(M.clampMinutes("abc", 25), 25);
assert.strictEqual(M.clampMinutes(null, 25), 25);
assert.strictEqual(M.clampMinutes(undefined, 25), 25);
assert.strictEqual(M.clampMinutes(NaN, 25), 25);
assert.strictEqual(M.clampMinutes(25.7, 25), 26); // rounds
assert.strictEqual(M.clampMinutes(0.6, 25), 25); // raw value below range, not promoted by rounding
assert.strictEqual(M.clampMinutes(180.4, 25), 25); // raw value above range, not promoted by rounding

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
