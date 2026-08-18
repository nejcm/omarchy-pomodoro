// Plain assert self-check for Release.js. Run: node Release.test.js
var assert = require("assert");
var R = require("./Release.js");

// -- bumpLevel: type -> level --
assert.strictEqual(R.bumpLevel("feat: add a panel", ""), "minor");
assert.strictEqual(R.bumpLevel("fix: stop the drift", ""), "patch");
assert.strictEqual(R.bumpLevel("perf: fewer redraws", ""), "patch");
assert.strictEqual(R.bumpLevel("revert: undo the drift fix", ""), "patch");
assert.strictEqual(R.bumpLevel("chore: bump the year", ""), "patch");
assert.strictEqual(R.bumpLevel("refactor: lift the parser out", ""), "patch");

// -- bumpLevel: no release --
assert.strictEqual(R.bumpLevel("docs: document the settings", ""), null);
assert.strictEqual(R.bumpLevel("ci: run the tests on PRs", ""), null);
assert.strictEqual(R.bumpLevel("style: reindent", ""), null);
assert.strictEqual(R.bumpLevel("test: cover the cap", ""), null);
assert.strictEqual(R.bumpLevel("build: pin the runner", ""), null);
assert.strictEqual(R.bumpLevel("just a plain message", ""), null); // non-conventional
assert.strictEqual(R.bumpLevel("Merge pull request #1 from nejcm/ci", ""), null);
assert.strictEqual(R.bumpLevel("", ""), null);
assert.strictEqual(R.bumpLevel(null, null), null);
assert.strictEqual(R.bumpLevel(undefined, undefined), null);

// -- bumpLevel: breaking --
assert.strictEqual(R.bumpLevel("feat!: drop the old history format", ""), "major");
assert.strictEqual(R.bumpLevel("fix!: rename the state file", ""), "major");
assert.strictEqual(R.bumpLevel("chore!: drop node 18", ""), "major");
assert.strictEqual(R.bumpLevel("fix: rename the state file", "BREAKING CHANGE: path moved"), "major");
assert.strictEqual(R.bumpLevel("docs: note the move", "BREAKING CHANGE: path moved"), "major"); // regardless of type
assert.strictEqual(R.bumpLevel("fix: something", "BREAKING CHANGE without the colon"), "patch"); // footer needs the colon

// -- bumpLevel: scopes parse like unscoped --
assert.strictEqual(R.bumpLevel("feat(panel): add a reset button", ""), "minor");
assert.strictEqual(R.bumpLevel("fix(panel): stop the drift", ""), "patch");
assert.strictEqual(R.bumpLevel("fix(panel)!: rename the state file", ""), "major");
assert.strictEqual(R.bumpLevel("docs(readme): fix a typo", ""), null);

// -- nextVersion: highest level wins, order-independent --
(function () {
    var mixed = [
        { subject: "docs: tidy", body: "" },
        { subject: "fix: drift", body: "" },
        { subject: "feat: reset button", body: "" }
    ];
    assert.strictEqual(R.nextVersion("0.1.0", mixed), "0.2.0");
    assert.strictEqual(R.nextVersion("0.1.0", mixed.slice().reverse()), "0.2.0");

    var breaking = mixed.concat([{ subject: "chore!: drop node 18", body: "" }]);
    assert.strictEqual(R.nextVersion("0.1.0", breaking), "1.0.0");
    assert.strictEqual(R.nextVersion("0.1.0", breaking.slice().reverse()), "1.0.0");
})();

// -- nextVersion: component reset --
assert.strictEqual(R.nextVersion("0.1.5", [{ subject: "fix: drift", body: "" }]), "0.1.6");
assert.strictEqual(R.nextVersion("0.1.5", [{ subject: "feat: reset", body: "" }]), "0.2.0"); // patch zeroed
assert.strictEqual(R.nextVersion("0.1.5", [{ subject: "feat!: reset", body: "" }]), "1.0.0"); // minor+patch zeroed
assert.strictEqual(R.nextVersion("1.9.9", [{ subject: "feat: reset", body: "" }]), "1.10.0"); // no decimal carry

// -- nextVersion: no release --
assert.strictEqual(R.nextVersion("0.1.0", []), null);
assert.strictEqual(R.nextVersion("0.1.0", [
    { subject: "docs: readme", body: "" },
    { subject: "ci: green", body: "" }
]), null);
assert.strictEqual(R.nextVersion("0.1.0", null), null);
assert.strictEqual(R.nextVersion("0.1.0", [null, "nope", {}]), null); // junk entries ignored, not thrown on

// -- nextVersion: malformed current falls back to null, does not guess --
assert.strictEqual(R.nextVersion("abc", [{ subject: "feat: x", body: "" }]), null);
assert.strictEqual(R.nextVersion("", [{ subject: "feat: x", body: "" }]), null);
assert.strictEqual(R.nextVersion("1.2", [{ subject: "feat: x", body: "" }]), null);
assert.strictEqual(R.nextVersion("v1.2.3", [{ subject: "feat: x", body: "" }]), null);
assert.strictEqual(R.nextVersion("1.2.3.4", [{ subject: "feat: x", body: "" }]), null);
assert.strictEqual(R.nextVersion(null, [{ subject: "feat: x", body: "" }]), null);

// -- parseRecords: the git log wire format the CLI reads --
(function () {
    var text = "feat: a\x00body a\x1e\nfix: b\x00\x1e\ndocs: c\x00BREAKING CHANGE: x\x1e\n";
    var recs = R.parseRecords(text);
    assert.strictEqual(recs.length, 3);
    assert.strictEqual(recs[0].subject, "feat: a");
    assert.strictEqual(recs[1].subject, "fix: b"); // record separator newline stripped
    assert.strictEqual(recs[2].body, "BREAKING CHANGE: x");
    assert.strictEqual(R.nextVersion("0.1.0", recs), "1.0.0");
    assert.deepStrictEqual(R.parseRecords(""), []);
    assert.deepStrictEqual(R.parseRecords(null), []);
})();

console.log("Release.test.js: all assertions passed");
