# Deferred

Deliberately out of scope for v0.1. Each was weighed and rejected for now,
not overlooked — see `plans/pomodoro-plugin.md` section 1 for the full
decision table.

- **Work/break cycle with auto-advance** — a different state model than a
  single countdown, roughly 3x the code (decision 1).
- **IPC methods + Hyprland hotkeys** — requires `keepLoaded` so the widget
  can answer while closed, which reopens the restart-survival question
  (decision 12, decision 6).
- **Session labels** — needs a panel input field and a wider history row for
  a rarely-used feature (decision 8).
- **Completion sound** — ships an audio file plus a player dependency for a
  single "ding" (decision 10).
- **Running timer surviving a shell restart** — needs a `service` kind plus
  `keepLoaded` to resume, an extra entry point for a rare event (decision 6).
- **Daily/weekly stats** — no aggregation beyond today's count exists yet;
  history is a flat log.
- **History grouped by day** — history is currently a flat newest-first list;
  grouping is a panel rendering change, not a data model change.
- **Multi-monitor: one timer per bar instance** — a bar surface exists per
  monitor, so two monitors run two independent timers and both
  whole-file-write the history (last writer wins). Upgrade path is a
  `service` kind + `keepLoaded` owning one timer (reopens decision 6).
- **Persistence: whole-file rewrite per completion** — no cross-instance
  merge; each completed session rewrites the entire history file rather than
  appending, so concurrent writers (see multi-monitor above) can clobber
  each other's rows (plan section 8).
- **Quarantining an unparseable history file** — the plugin currently refuses
  to overwrite a history file it cannot parse, which protects the existing
  data but means new sessions go unrecorded until a human fixes or removes the
  file. Moving the bad file aside automatically (to `pomodoro.json.corrupt`)
  and carrying on would be strictly better, but the `mv` is a `Process` and
  races the `FileView` write to the same path; doing it properly means
  sequencing the write behind the process's `onExited`. Deferred rather than
  done racily (plan section 8).
- **Testing the QML transition logic** — `start`/`pause`/`complete` live in
  `BarWidget.qml`, so `Model.test.js` cannot reach them; the two state bugs
  found in review (pausing past the deadline, and `ceil` inflating the banked
  remainder) were both in that untested layer. Lifting the transitions into
  `Model.js` as pure functions over a state object would make them assertable
  without a running shell.
- **JS lint/format tooling (ESLint, Prettier)** — would cover `Model.js`
  (3KB of 26KB) and none of the QML where the actual bugs have been, in
  exchange for a `package.json`, a lockfile and `node_modules` in a repo
  that otherwise clones and runs. Revisit if a second contributor arrives.
- **`qmllint` on the QML files** — tried in CI and removed. Quickshell is
  AUR-only and `qs.*` is omarchy-shell's own module namespace, so neither
  resolves on a stock Ubuntu runner; because every type in both files comes
  from one of them, the run produced 317 warnings with no true positives: 144
  unresolved types, 142 cascade warnings about properties on those unresolved
  types, and 31 "unqualified access" hits that were all singletons (`Style`,
  `SystemClock`, `Quickshell`) or `parent`/`anchors` refs. Qt 6.4, which
  Ubuntu ships, has no category flag that suppresses the unresolved-type
  family, so there is no filtered version of this check either. Real coverage
  needs an Arch CI image that builds `quickshell` from the AUR and clones
  `omarchy-shell`, rebuilt whenever either moves — worth it only if the QML
  grows well past its current 23KB.
