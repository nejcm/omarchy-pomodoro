# Deferred

Deliberately out of scope for v0.3.0. Each was weighed and rejected for now,
not overlooked.

- **IPC methods + Hyprland hotkeys** — the always-mounted `Service.qml` now
  removes the original blocker (the widget could not answer while closed), so
  what is left is the IPC handler itself and the hotkey wiring.
- **Session labels** — needs a panel input field and a wider history row for
  a rarely-used feature.
- **Completion sound** — ships an audio file plus a player dependency for a
  single "ding".
- **Running timer surviving a shell restart** — the `service` kind now exists
  (`Service.qml` owns the one timer), but nothing persists an *in-flight*
  session: only completed rows are written. Resuming across a restart means
  writing the deadline to disk and rehydrating it on mount, plus deciding what
  a session interrupted for an hour should do.
- **Daily/weekly stats** — the panel groups history by day
  (`Model.groupByDay`), and `Model.countToday` drives the current cycle, but
  nothing aggregates across days: there are no totals, streaks, or week view.
- **Quarantining an unparseable history file** — the plugin currently refuses
  to overwrite a history file it cannot parse, which protects the existing
  data but means new sessions go unrecorded until a human fixes or removes the
  file. Moving the bad file aside automatically (to `pomodoro.json.corrupt`)
  and carrying on would be strictly better, but the `mv` is a `Process` and
  races the `FileView` write to the same path; doing it properly means
  sequencing the write behind the process's `onExited`. Deferred rather than
  done racily.
- **Testing the QML transition logic** — the completion decision now lives in
  tested `Model.completion`, but `start` and `pause` still live in
  `Service.qml`, so `Model.test.js` cannot reach their state changes. Two
  bugs found in review (pausing past the deadline, and `ceil` inflating the
  banked remainder) were in this untested layer. Lifting those transitions
  into `Model.js` as pure functions over a state object would make them
  assertable without running the shell.
- **JS lint/format tooling (ESLint, Prettier)** — would cover the 21KB
  `Model.js` and none of the 81KB of QML where the actual bugs have been, in
  exchange for a `package.json`, a lockfile and `node_modules` in a repo
  that otherwise clones and runs. Revisit if a second contributor arrives.
- **`CHANGELOG.md` and npm-based release tooling** — the release workflow
  derives the version from conventional commits with ~60 lines of plain
  `node` (`Release.js`) rather than `np` or `semantic-release`, both of which
  need a `package.json`, a lockfile and `node_modules` in a repo that
  otherwise clones and runs. For the same reason there is no `CHANGELOG.md`:
  GitHub's auto-generated release notes already list the commits per tag, and
  a generated changelog file would be a second copy of that, kept in sync by a
  dependency. Revisit if the release process needs anything beyond
  "bump, tag, publish".
- **`qmllint` on the QML files** — tried in CI and removed. Quickshell is
  AUR-only and `qs.*` is omarchy-shell's own module namespace, so neither
  resolves on a stock Ubuntu runner; because the types in these files come
  from one of them, the run produced 317 warnings with no true positives: 144
  unresolved types, 142 cascade warnings about properties on those unresolved
  types, and 31 "unqualified access" hits that were all singletons (`Style`,
  `SystemClock`, `Quickshell`) or `parent`/`anchors` refs. Qt 6.4, which
  Ubuntu ships, has no category flag that suppresses the unresolved-type
  family, so there is no filtered version of this check either. Real coverage
  needs an Arch CI image that builds `quickshell` from the AUR and clones
  `omarchy-shell`, rebuilt whenever either moves. The four QML files now total
  81KB. Revisit when maintaining that CI environment is worth the added QML
  coverage.
