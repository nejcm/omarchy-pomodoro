# Plan — `io.github.nejcm.pomodoro`

An Omarchy Quattro bar widget: hourglass glyph when idle, live countdown when
running. Clicking it opens a panel with play/pause/reset above and a list of
completed sessions below.

Status: **shipped and running.** Model self-check, `omarchy plugin validate`,
and `qmllint` run clean; every platform fact in section 2 is checked against
the installed tree; and the plugin is installed, enabled in `bar.layout.right`,
and has been walked idle → start → pause → completion in a live shell (see
section 9). Secondary paths — resume, reset, shell restart, uninstall — remain
unexercised.

---

## 1. Settled decisions

Reached by interview; recorded so nothing is silently re-litigated.

| # | Decision | Chosen | Rejected, and why |
|---|---|---|---|
| 1 | Scope | Single countdown timer, default 25 min | Full work/break cycle state machine — different state model, 3× the code, deferred to `improvements.md` |
| 2 | Kinds | `["bar-widget"]` only; `Panel.qml` loaded by the widget via `Loader` | Declaring `panel` as a second kind — built-ins (`omarchy.clock`) don't, and the bar tracks the *widget* as the panel identity |
| 3 | Bar idle | Nerd Font hourglass glyph (`nf-fa-hourglass_half`, U+F252) — revised during build; no tomato in the classic FA block this plugin draws from, block confirmed v3-safe, codepoint confirmed against two primary sources, and a clock face would collide with `omarchy.clock` on the same bar | Emoji `🍅` — color-emoji rendering in the bar is font-dependent and won't inherit `bar.foreground` |
| 4 | Bar running | `24:59` **replaces** the glyph; paused = same text at reduced opacity | Glyph + countdown together (bar space), blinking (noise) |
| 5 | Clock model | **Revised during build: deadline-derived.** `remainingSeconds` is computed from a wall-clock `endsAt`, with `pausedMs` banking the exact remainder across a pause — so pause stays simple *and* a Timer that misses intervals (suspend, event-loop starvation) can't silently keep time it didn't count | A decremented `remainingSeconds` counter — the original choice; drifts exactly when the machine sleeps, which is the one case that matters |
| 6 | Restart survival | History persists; a *running* timer dies with the shell | `service` kind + `keepLoaded` to resume — an extra entry point for a rare event |
| 7 | Reset | Stop + restore full duration + discard; no history row, never auto-starts | Reset-as-restart (surprising), recording aborts (see 8) |
| 8 | History rows | Completed sessions only, no labels, last 50 | Aborted sessions (guilt, not data); text labels (needs a panel input field and a wider row) |
| 9 | Storage | `~/.local/state/omarchy/pomodoro.json` | Plugin dir (clobbered by `omarchy plugin update`, dirties `git status`); `shell.json` (config file, shell owns writes) |
| 10 | Completion | One desktop notification, urgency normal | Sound (ships an audio file + a player dependency for a *ding*); auto-opening the panel (steals focus every 25 min) |
| 11 | Settings | `minutes` (25), `notify` (true), inline in `shell.json` | `historyLimit` as a knob (hardcode 50); fixed 15/25/50 presets (deferred) — superseded by the +/-5 nudge, see section 4 |
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
- Widget settings are **inline on the `shell.json` layout entry**, siblings of
  `id` — `BarModel.entrySettings` builds the settings object by copying every
  key of the entry *except* `id`. A nested `"settings": { … }` object therefore
  does not work; it would leave every `setting()` call on its fallback while
  the config looks correct. (Confirms decision 11; the README first documented
  the nested shape and has been corrected.)
- `bar` exposes `foreground`, `fontFamily`, `run(cmd)`, `showTooltip()`,
  `requestPopout()`, `switchPanelFrom(...)`, `shell.updateEntryInline(...)`.
- Panel routing contract: the **bar-widget root** must expose `open()`,
  `close()`, `opened`, and `closeForPopoutSwitch()` — `Bar.findPanelWidget`
  looks for them there, not on the nested panel.
- `PanelActionButton` API: `iconText`, `tooltipText`, `foreground`,
  `hoverColor` (set to `bar.urgent` for destructive actions), `enabled`,
  `focusable`, `hasCursor`, `clicked()`.
- File I/O: `FileView` from `Quickshell.Io` (`path`, `text()`, `onLoaded`).
  Reading is confirmed by `shell/plugins/emojis/Emojis.qml`; writing is
  confirmed too — `setText`, `atomicWrites`, and `saveFailed` are all declared
  in `quickshell-io.qmltypes` and used by `shell.qml` and `Clipboard.qml`.
- `Quickshell.execDetached([argv])` takes an argument vector directly (no
  shell), as used by `shell/plugins/emojis/Emojis.qml`; `Quickshell.env(name)`
  is used by `shell.qml`.

---

## 3. Repo layout

```
omarchy-pomodoro/
├── manifest.json
├── BarWidget.qml     bar label + timer state + history + Loader for the panel
├── Panel.qml         controls row + history list
├── Model.js          pure functions: formatting, history push/trim
├── Model.test.js     plain-assert self-check for Model.js (node)
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
durationMinutes : int    = setting("minutes", 25)   // validated, 1…180
running         : bool   = false      // ticking
started         : bool   = false      // has a session in progress (running or paused)
history         : array  = []         // [{ startedAt: epochMs, minutes: int }, …] newest first
sessionStartedAt: double              // epoch ms, stamped on the transition idle → running
sessionMinutes  : int                 // duration snapshotted at start(), for the history row
endsAt          : double              // epoch ms deadline; meaningful while running
pausedMs        : double              // exact remainder banked at the last pause()
nowMs           : double              // advanced by the ticker
```

Epoch milliseconds (~1.77e12) overflow QML's 32-bit `int` (~2.15e9), so every
timestamp is `double`, never `int`.

Derived:

```
remainingSeconds = running ? max(0, ceil((endsAt - nowMs) / 1000))
                           : (started ? max(0, ceil(pausedMs / 1000))
                                      : durationMinutes * 60)
idle      = !started
paused    = started && !running
barText   = idle ? idleGlyph : mmss(remainingSeconds)
dimmed    = paused          // WidgetButton renders dimmed as opacity 0.45
todayCount= history.filter(sameLocalDay(now)).length
```

Transitions:

| Action | Guard | Effect |
|---|---|---|
| `start()` | `!running` | if `!started`: `started = true`, `sessionStartedAt = Date.now()`, `sessionMinutes = durationMinutes`. Then `nowMs = Date.now()`, `endsAt = nowMs + secs * 1000`, `running = true` |
| `pause()` | `running` | refresh `nowMs`. **If the deadline has already passed, `complete()` instead** — see below. Otherwise bank `pausedMs = endsAt - nowMs`, `running = false` |
| `reset()` | `started` | `running = started = false`. `remainingSeconds` falls back to `durationMinutes * 60` on its own, since it is derived. **No history row** |
| tick | `running` | `nowMs = Date.now()`; at `remainingSeconds <= 0` → `complete()` |
| `complete()` | — | push `{startedAt: sessionStartedAt, minutes: sessionMinutes}`, trim to 50, persist, notify, then reset to idle |
| `adjustMinutes(d)` | `Model.adjustSession` accepts | idle: `durationMinutes = stepMinutes(durationMinutes, d)`. Started: `sessionMinutes = next` and the same shift applied to `endsAt` (running) or `pausedMs` (paused). Refused when the step clamps to a no-op, the deadline has already passed, or the shortening would consume what is left |

`durationMinutes` changing (a `shell.json` edit) while idle flows straight
through to `remainingSeconds`, because that value is derived rather than
assigned. While a session is in progress the edit cannot reach it — a running
session reads `endsAt`, and its history row and notification read the
`sessionMinutes` snapshot — so an edit can't yank time out from under a
running timer or retroactively relabel a finished one.

`adjustMinutes()` is the one deliberate exception to that rule: an explicit
user nudge from the panel's +/- buttons (or the idle-only scroll wheel), which
*does* reach a started session. It stays honest about history because it moves
`sessionMinutes` and the deadline by the identical amount — the recorded
minutes still equal the minutes actually counted down. Since `durationMinutes`
becomes writable for the idle case, its `setting()` binding is gone after the
first nudge, so `onSettingsChanged` re-asserts it; a nudge therefore survives
until any settings change, and is not persisted to `shell.json`.

The ticker is a `Timer { interval: 1000; repeat: true; running: root.running }`,
but it only refreshes `nowMs`; it never decrements a counter. A Timer that
misses intervals fires once on resume rather than catching up, so a counter
would silently keep the time that passed while it wasn't running. Recomputing
against `Date.now()` cannot drift.

Two consequences of the deadline model, both found in review and fixed:

- **The deadline passes before the tick that notices it.** `remainingSeconds`
  reaches 0 as soon as `Date.now() > endsAt`, but `complete()` only runs on the
  next tick, and ticks land late. A `pause()` inside that gap banked a zero
  remainder and stopped the ticker, leaving a dimmed `00:00` in the bar with no
  notification and no history row — and a `reset()` from there discarded a
  session that had actually finished. `pause()` now completes instead: a
  session past its deadline is finished, not pausable.
- **The banked remainder is milliseconds, not seconds.** Rounding it to whole
  seconds would have to use `ceil` to match the display, which hands back up to
  a second of extra time on *every* pause/resume cycle — an error that
  accumulates. `pausedMs` is exact; rounding stays in the display binding.

---

## 5. `BarWidget.qml`

Mirrors the clock's structure.

- `BarWidget { moduleName: "io.github.nejcm.pomodoro" }`
- Settings: `minutes` (validated to 1…180, else falls back to 25 — a trust
  boundary, `shell.json` is hand-edited), `notify` (bool).
- `WidgetButton` renders `barText` at `bar.foreground`, `dimmed: paused`
  (the base maps `dimmed` to opacity 0.45, so the plan's original 0.6 is not a
  knob this plugin sets),
  `onPressed: togglePanel()`. Left click only; no right/middle click actions.
- The panel-routing contract on the root: `opened`, `open()`, `close()`,
  `togglePanel()`, `closeForPopoutSwitch()`, `popoutSwitchClosing`, all
  forwarding to `panelLoader.item`.
- `injectPanel()` on `onBarChanged` / `onSettingsChanged`, passing `bar`,
  `settings`, `anchorItem: button`, `hostWidget: root` — same as the clock.
- History loads via `FileView`'s implicit load when `path` is set — there is no
  explicit call in `Component.onCompleted` (which only kicks off the state-dir
  `mkdir -p`). Saved on every `complete()`, gated as described in section 8.
- Notification: `Quickshell.execDetached(["notify-send", "-a", "Pomodoro",
  "-u", "normal", "Pomodoro complete", minutes + " minute session done"])`.
  An argv, not a shell string (the planned `bar.run` form was revised during
  build): nothing is parsed by a shell, so no argument needs quoting, and it
  drops the dependency on `bar.run` being present. Skipped when `notify` is
  false.
- A `Process { command: ["mkdir", "-p", stateDir] }` runs on completion, so the
  first write has a directory to land in. Reads tolerate a missing file already.

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
- List is a `Flickable` wrapping a `Column` + `Repeater`, capped at
  ~`Style.space(220)` so 50 rows scroll rather than growing the panel past the
  screen. **Not a `ListView`** (as first planned): `ListView.contentHeight`
  derives from the delegates it has instantiated, and it instantiates
  delegates to fill its own height — self-referential, so a height capped by
  the content settles wrong instead of erroring. `Column.implicitHeight` is
  content-derived and independent of the viewport. 50 rows need no
  virtualization anyway, and `clock/Panel.qml` caps its calendar the same way.
- The file sets `pragma ComponentBehavior: Bound` so the delegate can read the
  enclosing scope's ids cleanly; the delegate declares `required property var
  modelData` accordingly.
- `PanelKeyCatcher`: `onCloseRequested → close()`, `onActivateRequested →
  toggleRunning()` (Enter/Space starts and stops), `onTabRequested →
  switchPanel(direction)`.

## 7. `Model.js`

Pure, no QML types — so the self-check can run under plain `qmljs`/`node`.

```
mmss(seconds)                     → "24:59", clamps negatives to "00:00"
validMinutesOr(value, fallback)   → int in 1…180, else fallback
pushSession(history, entry, cap)  → new array, newest first, trimmed to cap
countToday(history, nowMs)        → int, local-day comparison
parseHistory(text, cap)           → array; [] on malformed/absent JSON
serializeHistory(history)         → '{"version":1,"sessions":[…]}'
HISTORY_CAP = 50                  → shared by the read and write paths
```

`validMinutesOr` **falls back rather than clamping** (the name change from the
planned `clampMinutes` is the point): a hand-typed `2500` in `shell.json` is a
typo, and 25 is a better recovery than 180.

`HISTORY_CAP` is exported and used as the default on both `pushSession` and
`parseHistory`, so the write path cannot store more rows than the read path
will load back — a divergence the self-check pins explicitly.

`parseHistory` is a trust boundary — the state file is on disk and may be
truncated, hand-edited, or absent. It never throws; a corrupt file degrades to
an empty log rather than a broken widget.

## 8. Persistence

`~/.local/state/omarchy/pomodoro.json`:

```json
{ "version": 1, "sessions": [ { "startedAt": 1762772400000, "minutes": 25 } ] }
```

**Writes are gated on the read having settled.** `history` starts as `[]`,
which is indistinguishable from a genuinely empty log, so persisting before the
load resolves would publish that placeholder over real data. A `historyLoaded`
flag blocks writes until either `onLoaded` or `onLoadFailed` has fired.

**A file we cannot parse is never overwritten.** `parseHistory` degrades to
`[]` by design, but "absent" and "present and unreadable" are very different:
the second is a log we failed to read (truncated write, hand-edit typo, older
format), and rewriting it destroys the only copy. `onLoaded` separates the two
by checking whether the raw text was non-empty, and `historyUnreadable` then
stops persistence with a warning naming the path. The cost is that new sessions
go unsaved until a human fixes or removes the file; the alternative — found in
review, reproduced against a truncated 40-session file — was silently deleting
all 40. Quarantining the bad file automatically would avoid both, but the `mv`
races the write, so it is deferred rather than done badly.

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
`parseHistory` on garbage). Plain `assert`s, runnable with `node`. No test
framework. The QML rendering is verified by looking at it.

### Done (static, run on the Omarchy box)

```bash
node Model.test.js                 # all assertions passed
omarchy plugin validate .          # exit 0
```

The validator's silence was itself checked: feeding it a manifest with `id`
removed exits 1 with a named error, so the clean pass means something.

**qmllint needs an import root the plan originally got wrong.** The modules
declare `module qs.Ui` / `module qs.Commons`, so the import path must contain
a directory literally named `qs`; pointing `-I` straight at
`$OMARCHY_PATH/shell` fails every `qs.*` import and buries the real output in
cascade errors. Quickshell supplies that mapping at runtime, qmllint does not
— so make it explicit:

```bash
mkdir -p /tmp/qsimports && ln -sfn "$OMARCHY_PATH/shell" /tmp/qsimports/qs
qmllint -I /tmp/qsimports BarWidget.qml Panel.qml
```

Result: exit 0. The only remaining warnings are 15 `missing-property` on
members of untyped `QObject`/`var` holders (`bar`, `panelLoader.item`) —
unavoidable without static types, and the shell's own `clock` plugin emits 37
of exactly the same class. The 4 `unqualified` warnings in the history
delegate were real and are fixed with `pragma ComponentBehavior: Bound`.

### Done (live, in a running shell)

Installed as a git clone of the work tree — **not a symlink**, which
`omarchy plugin validate` rejects outright ("symlinks are not allowed inside a
plugin folder"), so the convenient dev-loop install is not available:

```bash
git clone <repo> ~/.config/omarchy/plugins/io.github.nejcm.pomodoro
omarchy plugin validate ~/.config/omarchy/plugins/io.github.nejcm.pomodoro
omarchy-shell shell rescanPlugins
omarchy plugin enable io.github.nejcm.pomodoro --section right --before omarchy.power
```

`omarchy plugin enable` writes the `bar.layout.right` entry itself; hand-editing
`shell.json` for placement is unnecessary. Note that a bar widget's enablement
*is* its layout entry — the top-level `plugins` array stays `[]`.

Walked with `minutes: 1`: idle glyph renders as a glyph (not tofu) → panel opens
and the bar's open-dot appears under the widget → start → countdown ticks →
pause freezes and dims → run to completion → notification fires → `TODAY · 1`
and the row appear → `~/.local/state/omarchy/pomodoro.json` written on first
completion, state dir created by the `mkdir -p`. No pomodoro output of any kind
in the shell log across the whole walkthrough.

The panel centers on the bar rather than anchoring under the widget. That is
`centerOnBar: true` behaving as designed — `clock` and `weather` both set it —
not a misanchor.

Still unexercised: resume-after-pause, `reset()`, Escape-to-close, panel
switching via Tab, shell restart (history survives, running timer does not),
and disable → re-enable → remove.

**The walkthrough and the qmllint run above both predate the duration-adjust
feature.** The +/- buttons and the scroll wheel have not been exercised live,
and `qmllint` has not been re-run since; CI covers `node Model.test.js` and a
manifest parse only. `Model.adjustSession` / `Model.wheelSteps` carry the
arithmetic and are unit-tested, so what is unverified is the QML wiring, not
the logic.

---

## 10. Risks

1. ~~**Style/Color token names.**~~ **Closed.** Every token used resolves in
   the installed tree: `Style.space()`, `Style.font.display` / `.body` /
   `.caption` / `.family`, and on `bar` both `foreground` (Bar.qml:68) and
   `urgent` (Bar.qml:72). Component APIs likewise — `WidgetButton.text` /
   `.dimmed` / `pressed(int button)`, `PanelActionButton.iconText` /
   `.tooltipText` / `.foreground` / `.hoverColor` / `.fontFamily`,
   `PanelSectionHeader` (a `Text`, so `text` is inherited),
   `PanelSeparator.foreground`, and `KeyboardPanel.fittedContentWidth/Height`
   / `.centerOnBar` / `.focusTarget` / `.owner`.
2. ~~**`FileView` write API.**~~ **Closed.** `quickshell-io.qmltypes` declares
   `setText(QString)`, the `saveFailed(error)` and `loadFailed(error)`
   signals, and `atomicWrites` — all of which this plugin uses. The shell
   itself writes the same way (`shell.qml`, `plugins/clipboard/Clipboard.qml`).
   The `bar.run("cat > file")` fallback is not needed.
3. ~~**Hourglass glyph codepoint.**~~ **Closed.** `fc-match monospace` resolves
   to JetBrainsMono Nerd Font, whose cmap names the four codepoints exactly as
   documented: `f252 → fa-hourglass_half`, `f04b → fa-play`,
   `f04c → fa-pause`, `f0e2 → fa-undo` (plus `00b7 → periodcentered`). Still
   font-dependent in principle — a user on a non-Nerd-Font bar gets tofu.
4. ~~**Panel routing contract.**~~ **Closed.** The bar's open-dot renders under
   the widget while the panel is open, which is the coordinator finding the
   `opened`/`open`/`close` trio on the widget root — the exact failure mode
   this risk named. Panel switching via Tab is the one part of the contract
   still unexercised.
5. ~~**No local execution.**~~ **Closed for the main path.** The plugin has run
   in a live shell: tick loop, panel layout and anchoring, notification, and
   the first write to `~/.local/state/omarchy/pomodoro.json` all worked on the
   first load, with nothing in the shell log. The unexercised remainder is
   listed at the end of section 9 — all of it secondary paths, none of it the
   first-contact risk this entry was about.

---

## 11. Deferred (→ `improvements.md`)

Work/break cycle with auto-advance · IPC methods + Hyprland hotkeys (needs
`keepLoaded`) · session labels · completion sound · running timer surviving a
shell restart · persisting an adjusted duration back to `shell.json` ·
daily/weekly stats ·
history grouped by day.
