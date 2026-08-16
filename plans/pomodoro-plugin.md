# Plan — `io.github.nejcm.pomodoro`

An Omarchy Quattro bar widget: hourglass glyph when idle, live countdown when
running. Clicking it opens a panel with play/pause/reset above and a list of
completed sessions below.

Status: **planned, not written.** Authored on Windows; every line gets its
first execution on the Omarchy box.

---

## 1. Settled decisions

Reached by interview; recorded so nothing is silently re-litigated.

| # | Decision | Chosen | Rejected, and why |
|---|---|---|---|
| 1 | Scope | Single countdown timer, default 25 min | Full work/break cycle state machine — different state model, 3× the code, deferred to `improvements.md` |
| 2 | Kinds | `["bar-widget"]` only; `Panel.qml` loaded by the widget via `Loader` | Declaring `panel` as a second kind — built-ins (`omarchy.clock`) don't, and the bar tracks the *widget* as the panel identity |
| 3 | Bar idle | Nerd Font hourglass glyph (`nf-fa-hourglass_half`, U+F252) — revised during build; no tomato in the classic FA block this plugin draws from, block confirmed v3-safe, codepoint confirmed against two primary sources, and a clock face would collide with `omarchy.clock` on the same bar | Emoji `🍅` — color-emoji rendering in the bar is font-dependent and won't inherit `bar.foreground` |
| 4 | Bar running | `24:59` **replaces** the glyph; paused = same text at reduced opacity | Glyph + countdown together (bar space), blinking (noise) |
| 5 | Clock model | Countdown over `remainingSeconds`, ticked by a `Timer` | Target-epoch model — makes pause awkward for no gain, since we don't survive restarts |
| 6 | Restart survival | History persists; a *running* timer dies with the shell | `service` kind + `keepLoaded` to resume — an extra entry point for a rare event |
| 7 | Reset | Stop + restore full duration + discard; no history row, never auto-starts | Reset-as-restart (surprising), recording aborts (see 8) |
| 8 | History rows | Completed sessions only, no labels, last 50 | Aborted sessions (guilt, not data); text labels (needs a panel input field and a wider row) |
| 9 | Storage | `~/.local/state/omarchy/pomodoro.json` | Plugin dir (clobbered by `omarchy plugin update`, dirties `git status`); `shell.json` (config file, shell owns writes) |
| 10 | Completion | One desktop notification, urgency normal | Sound (ships an audio file + a player dependency for a *ding*); auto-opening the panel (steals focus every 25 min) |
| 11 | Settings | `minutes` (25), `notify` (true), inline in `shell.json` | `historyLimit` as a knob (hardcode 50); in-panel duration presets (deferred) |
| 12 | Control | Click toggles panel, Escape/click-outside closes | IPC methods + Hyprland hotkeys — needs `keepLoaded` to answer while closed, which reopens decision 6. Deferred |
| 13 | Publishing | `git init` + local commits only | `gh repo create --push` — not until it has run on real hardware |
| 14 | License | MIT | — |

---

## 2. Verified platform facts

Read from `basecamp/omarchy@quattro`, not assumed.

- Omarchy Quattro replaced Waybar with **Quickshell**; plugins are QML.
  Manifest is `manifest.json` at repo root, `schemaVersion: 1`.
- Kinds: `bar-widget`, `panel`, `overlay`, `menu`, `service`, `bar`.
- Installed to `~/.config/omarchy/plugins/<id>/`. Third-party plugins land
  **disabled** — enable after review. Plugins are **unsandboxed**.
- Template to mirror: `shell/plugins/panels/clock/` —
  `manifest.json`, `BarWidget.qml`, `Panel.qml`, `Model.js`. Same shape as
  this plugin (bar label + anchored popup).
- Available UI components (`qs.Ui`): `BarWidget`, `WidgetButton`, `Panel`,
  `KeyboardPanel`, `PanelKeyCatcher`, `PanelActionButton`,
  `PanelSectionHeader`, `PanelSeparator`, `PanelToolTip`, `PanelHero`,
  `OpticalGlyph`, `Button`, `TextField`, `Toggle`.
- Available singletons (`qs.Commons`): `Color` (`foreground`, `background`,
  `accent`, `urgent`, plus `Color.bar.*` / `Color.popups.*` surface roles),
  `Style` (`Style.space(n)`, `Style.cornerRadius`, `Style.spacing.*`,
  `Style.font.*`, `Style.bar.iconSlot`, `Style.hoverStateColor(...)`).
- `BarWidget` gives the subclass: `moduleName`, `settings`, `bar`,
  `vertical`, `setting(key, default)`, `broadcast(...)`.
- `bar` exposes `foreground`, `fontFamily`, `run(cmd)`, `showTooltip()`,
  `requestPopout()`, `switchPanelFrom(...)`, `shell.updateEntryInline(...)`.
- Panel routing contract: the **bar-widget root** must expose `open()`,
  `close()`, `opened`, and `closeForPopoutSwitch()` — `Bar.findPanelWidget`
  looks for them there, not on the nested panel.
- `PanelActionButton` API: `iconText`, `tooltipText`, `foreground`,
  `hoverColor` (set to `bar.urgent` for destructive actions), `enabled`,
  `focusable`, `hasCursor`, `clicked()`.
- File I/O: `FileView` from `Quickshell.Io` (`path`, `text()`, `onLoaded`).
  Reading is confirmed by `shell/plugins/emojis/Emojis.qml`. **Writing is the
  one API not yet confirmed** — see risks.

---

## 3. Repo layout

```
omarchy-pomodoro/
├── manifest.json
├── BarWidget.qml     bar label + timer state + history + Loader for the panel
├── Panel.qml         controls row + history list
├── Model.js          pure functions: formatting, history push/trim
├── README.md         install, settings, screenshot
├── improvements.md   everything deliberately deferred
├── plans/
│   └── pomodoro-plugin.md   (this file)
├── LICENSE           MIT
└── .gitignore
```

`preview.png` is left for a screenshot on the real machine.

### `manifest.json`

```json
{
  "schemaVersion": 1,
  "id": "io.github.nejcm.pomodoro",
  "name": "Pomodoro",
  "version": "0.1.0",
  "author": "Nejc",
  "license": "MIT",
  "description": "Pomodoro countdown in the bar, with a session log",
  "kinds": ["bar-widget"],
  "entryPoints": { "barWidget": "BarWidget.qml" },
  "barWidget": {
    "displayName": "Pomodoro",
    "description": "Pomodoro countdown in the bar, with a session log",
    "category": "Time",
    "allowMultiple": false
  }
}
```

---

## 4. State model

Owned entirely by `BarWidget.qml`; `Panel.qml` reads it and calls back.

```
durationMinutes : int   = setting("minutes", 25)
remainingSeconds: int   = durationMinutes * 60
running         : bool  = false      // ticking
started         : bool  = false      // has a session in progress (running or paused)
history         : array = []         // [{ startedAt: epochMs, minutes: int }, …] newest first
sessionStartedAt: int                // epoch ms, stamped on the transition idle → running
```

Derived:

```
idle      = !started
paused    = started && !running
barText   = idle ? idleGlyph : mmss(remainingSeconds)
barOpacity= paused ? 0.6 : 1.0
todayCount= history.filter(sameLocalDay(now)).length
```

Transitions:

| Action | Guard | Effect |
|---|---|---|
| `start()` | `!running` | if `!started`: `started = true`, `sessionStartedAt = Date.now()`. `running = true`, ticker on |
| `pause()` | `running` | `running = false`, ticker off. `remainingSeconds` frozen |
| `reset()` | `started` | `running = started = false`, `remainingSeconds = durationMinutes * 60`. **No history row** |
| tick | `running` | `remainingSeconds--`; at `0` → `complete()` |
| `complete()` | — | push `{startedAt: sessionStartedAt, minutes: durationMinutes}`, trim to 50, persist, notify, then reset to idle |

`durationMinutes` changing (a `shell.json` edit) while idle resets
`remainingSeconds`; while a session is in progress it takes effect on the next
session, so an edit can't yank time out from under a running timer.

The ticker is a `Timer { interval: 1000; repeat: true; running: root.running }`.
Second-granularity drift over 25 minutes is acceptable and invisible — a
session that ends a second late is not a bug worth an epoch-correction path.

---

## 5. `BarWidget.qml`

Mirrors the clock's structure.

- `BarWidget { moduleName: "io.github.nejcm.pomodoro" }`
- Settings: `minutes` (clamped to 1…180 — a trust boundary, `shell.json` is
  hand-edited), `notify` (bool).
- `WidgetButton` renders `barText` at `bar.foreground`, `opacity: barOpacity`,
  `onPressed: togglePanel()`. Left click only; no right/middle click actions.
- The panel-routing contract on the root: `opened`, `open()`, `close()`,
  `togglePanel()`, `closeForPopoutSwitch()`, `popoutSwitchClosing`, all
  forwarding to `panelLoader.item`.
- `injectPanel()` on `onBarChanged` / `onSettingsChanged`, passing `bar`,
  `settings`, `anchorItem: button`, `hostWidget: root` — same as the clock.
- History load on component completion; save on every `complete()`.
- Notification: `bar.run("notify-send -a Pomodoro 'Pomodoro complete' '25 minute session done'")`.
  Arguments are built from an integer, never from free text, so there is no
  shell-quoting hole. Skipped when `notify` is false.

## 6. `Panel.qml`

`Panel` + `KeyboardPanel` + `PanelKeyCatcher`, anchored to the bar button.
Fixed content width ~`Style.space(320)`.

```
┌──────────────────────────────┐
│           24 : 59            │  large, bold; dimmed when paused
│         ▶        ⟲           │  PanelActionButton ×2
├──────────────────────────────┤  PanelSeparator
│  TODAY · 4                   │  PanelSectionHeader
│  14:32 · 25 min              │  ListView, newest first
│  13:55 · 25 min              │
│  …                           │
└──────────────────────────────┘
```

- Play/pause is one button that swaps `iconText` between play and pause
  glyphs; `⟲` reset uses `hoverColor: bar.urgent` and is `enabled: started`.
- History rows: `Qt.formatDateTime(startedAt, "HH:mm")` + `· N min`.
  Clock time, not relative — relative times need a repaint timer for a list
  you only glance at.
- Empty state: centered "No sessions yet."
- List is a `ListView` inside a `Flickable`, capped at ~`Style.space(220)` so
  50 rows scroll rather than growing the panel past the screen.
- `PanelKeyCatcher`: `onCloseRequested → close()`, `onActivateRequested →
  toggleRunning()` (Enter/Space starts and stops), `onTabRequested →
  switchPanel(direction)`.

## 7. `Model.js`

Pure, no QML types — so the self-check can run under plain `qmljs`/`node`.

```
mmss(seconds)                    → "24:59", clamps negatives to "00:00"
clampMinutes(value, fallback)    → int in 1…180
pushSession(history, entry, cap) → new array, newest first, trimmed to cap
countToday(history, nowMs)       → int, local-day comparison
parseHistory(text)               → array; returns [] on malformed/absent JSON
```

`parseHistory` is a trust boundary — the state file is on disk and may be
truncated, hand-edited, or absent. It never throws; a corrupt file degrades to
an empty log rather than a broken widget.

## 8. Persistence

`~/.local/state/omarchy/pomodoro.json`:

```json
{ "version": 1, "sessions": [ { "startedAt": 1762772400000, "minutes": 25 } ] }
```

Read via `FileView` on startup → `parseHistory`. Written on each completion,
whole-file. 50 entries is a couple of KB; incremental append would be
strictly more code for a file written twice an hour.

`ponytail: whole-file rewrite per completion, and no cross-instance merge —
last writer wins if two shells run at once. Fine for one desktop session;
revisit only if the file is ever shared.`

---

## 9. Verification

One `Model.js` self-check — the logic that can actually be wrong (`mmss`
boundaries, `pushSession` trimming and ordering, `countToday` across midnight,
`parseHistory` on garbage). Plain `assert`s, runnable with `qmljs Model.test.js`
or `node`. No test framework. The QML rendering is verified by looking at it.

On the Omarchy box:

```bash
git clone <this repo> ~/.config/omarchy/plugins/io.github.nejcm.pomodoro
omarchy plugin validate ~/.config/omarchy/plugins/io.github.nejcm.pomodoro
qmllint -I "$OMARCHY_PATH/shell" ~/.config/omarchy/plugins/io.github.nejcm.pomodoro/*.qml
omarchy-shell shell rescanPlugins
omarchy-shell shell setPluginEnabled io.github.nejcm.pomodoro true
```

Then add it to `bar.layout.right` in `~/.config/omarchy/shell.json` and walk:
idle glyph → start → countdown ticks → pause dims → resume → reset discards →
run to completion (set `minutes: 1`) → notification fires → row appears →
panel reopens with history intact → shell restart keeps history, drops any
running timer → Escape closes → disable → re-enable → remove.

---

## 10. Risks

1. **Style/Color token names.** Taken from one plugin's usage. Some will be
   wrong; `qmllint` names them and each is a one-line fix. Highest-churn area.
2. **`FileView` write API.** Reads are confirmed in-tree; the write path
   (`setText` / adapter / `blockWrites`) is not. Fallback if it fights back:
   `bar.run("…")` shelling the JSON out through a `cat > file` — uglier, and
   only if the QML path doesn't work.
3. **Hourglass glyph codepoint.** Depends on the bar's Nerd Font build. Picked
   from the Nerd Font set; swap the literal if it renders as tofu.
4. **Panel routing contract.** The `opened`/`open`/`close` trio must sit on
   the *widget* root, not the panel, or the bar's popout coordinator won't
   find it. Following the clock exactly avoids this; noted because the failure
   mode (panel opens but the bar's open-dot and panel-switching misbehave) is
   non-obvious.
5. **No local execution.** Nothing here has run. First contact is on your
   machine, and the first pass will produce errors — that's expected, not a
   sign the plan is wrong.

---

## 11. Deferred (→ `improvements.md`)

Work/break cycle with auto-advance · IPC methods + Hyprland hotkeys (needs
`keepLoaded`) · session labels · completion sound · running timer surviving a
shell restart · in-panel duration presets (15/25/50) · daily/weekly stats ·
history grouped by day.
