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
- **In-panel duration presets (15/25/50)** — `minutes` is a `shell.json`
  setting for now; presets are a panel UI addition (decision 11).
- **Daily/weekly stats** — no aggregation beyond today's count exists yet;
  history is a flat log.
- **History grouped by day** — history is currently a flat newest-first list;
  grouping is a panel rendering change, not a data model change.
