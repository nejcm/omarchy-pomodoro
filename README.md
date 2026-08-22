# Pomodoro (`io.github.nejcm.pomodoro`)

A [Pomodoro timer](https://en.wikipedia.org/wiki/Pomodoro_Technique) that lives
in your Omarchy bar, not in a separate app or browser tab. An hourglass glyph
sits idle in the bar until you click it to start a session; while running, the
glyph is replaced by a live `mm:ss` countdown (dimmed while paused) so
remaining time is visible at a glance without opening anything. Click again to
open a panel with play/pause, reset, and a log of your completed sessions.

It's built to disappear when you're not using it: no separate process, no
tray icon, no window to manage — just a widget in a bar you already look at.

Listed on [Omarchy Plugins](https://omarchyplugins.com/plugin.html?id=io.github.nejcm.pomodoro).

![The pomodoro panel: countdown, play and reset controls, and a session log](preview.png)

## Requirements

- Omarchy with the Quattro shell (`omarchy-shell`) — this is a `bar-widget`
  plugin and uses the shell's `qs.Ui` / `qs.Commons` modules.
- A Nerd Font as the bar font, for the hourglass, play, pause, and undo
  glyphs. Omarchy's default (JetBrainsMono Nerd Font) covers all four; a bar
  configured with a non-Nerd font renders them as tofu.
- `notify-send` (`libnotify`) for the completion notification, which ships with
  Omarchy. Absent, the notification is skipped silently; nothing else breaks.

No other dependencies: the plugin is four files of QML and JavaScript, and it
runs inside the existing shell process rather than spawning anything of its own
beyond `mkdir -p` for its state directory and `notify-send` on completion.

## Install

```bash
omarchy plugin add https://github.com/nejcm/omarchy-pomodoro.git --enable
```

This is the command the [marketplace listing](https://omarchyplugins.com/plugin.html?id=io.github.nejcm.pomodoro)
itself gives you. It clones the repo, validates it locally, and only then
installs and enables the plugin — review the source first if you haven't
already; it's third-party, unsandboxed code.

If you want control over where in the bar it lands, clone and enable it as
two steps instead:

```bash
git clone https://github.com/nejcm/omarchy-pomodoro.git ~/.config/omarchy/plugins/io.github.nejcm.pomodoro
omarchy plugin validate ~/.config/omarchy/plugins/io.github.nejcm.pomodoro
omarchy-shell shell rescanPlugins
omarchy plugin enable io.github.nejcm.pomodoro --section right --before omarchy.power
```

Third-party plugins are discovered disabled; `omarchy plugin enable` turns this
one on after you have reviewed it, and writes the `bar.layout.right` entry for
you — no hand-editing of `shell.json` is needed to place it. Drop
`--before omarchy.power` to append instead, or use `--section left|center`.

Two things worth knowing:

- **Clone it, don't symlink it.** `omarchy plugin validate` rejects a symlinked
  plugin folder outright, so pointing the plugin directory at a working copy
  elsewhere does not work.
- A bar widget's *enablement is its layout entry*. The top-level `plugins`
  array in `shell.json` stays `[]`; that is expected, not a failed install.

## Uninstall

```bash
omarchy plugin remove io.github.nejcm.pomodoro --yes
```

That disables the plugin (removing its bar entry), deletes the cloned folder,
and rescans — the bar updates without a restart. Session history is deliberately
left behind so a reinstall picks it back up; delete it yourself if you want it
gone:

```bash
rm -f ~/.local/state/omarchy/pomodoro.json
```

The plugin writes nothing else outside its own folder. It never edits
`shell.json`; the `omarchy plugin enable`/`remove` commands above do, on your
say-so.

## Settings

Set under the widget's entry in `shell.json`:

| Key | Default | Description |
|---|---|---|
| `minutes` | `25` | Session length. Must be a JSON **number** in 1–180; anything else falls back to 25. The panel's +/- and scroll wheel can nudge this at runtime (see Usage below), but that nudge is not written back here -- it is discarded whenever this value changes in `shell.json`, and on a shell restart |
| `notify` | `true` | Send a desktop notification on session completion. Must be a JSON **boolean** |

Types are checked strictly and fall back silently, so quote marks matter:
`"minutes": 30` works, `"minutes": "30"` leaves you on 25, and
`"notify": "false"` is not `false` — it reads as the default, `true`.

Settings go **inline on the entry**, as siblings of `id` — not nested under a
`settings` key:

```json
{
  "bar": {
    "layout": {
      "right": [
        {
          "id": "io.github.nejcm.pomodoro",
          "minutes": 25,
          "notify": true
        }
      ]
    }
  }
}
```

The bar builds a widget's settings by copying every key of the entry except
`id` (`plugins/bar/BarModel.js`, `entrySettings`), which is why a nested
`"settings": { … }` object would not work: `minutes` would silently stay at 25
while the config looked correct. The built-in `omarchy.clock` entry uses the
same inline shape.

`shell.json` hot-reloads, so a duration change applies on save. It takes effect
on the *next* session — an edit mid-session cannot yank time out from under a
running timer, and cannot relabel a session that has already finished.

## Usage

- Idle: hourglass glyph in the bar.
- Running: glyph is replaced by a `mm:ss` countdown; paused shows the same
  text at reduced opacity.
- Click the widget to open the panel: the countdown flanked by +/- (5 minute
  steps, or scroll while idle), play/pause and reset below that, and a
  session log at the bottom.
- +/- and the wheel adjust `durationMinutes` while idle. Once a session has
  started, the buttons still work but adjust that session in place instead
  (the running deadline or paused remainder), clamped so it can't be
  shortened past what's left -- the wheel is idle-only. Either way the
  adjustment is in-memory only -- it does not write `shell.json` and is
  discarded whenever `minutes` changes there, and on a shell restart; use the
  `minutes` setting above for a change that should stick.
- Reset stops the timer and restores the full duration without recording a
  history row.
- Completed sessions are recorded (no aborted sessions), newest first,
  capped at 50 rows.
- With the panel focused, Enter or Space starts and stops, and Escape closes.

## History

Stored at `~/.local/state/omarchy/pomodoro.json`. A running (or paused)
timer does **not** survive a shell restart — only completed-session history
persists.

If that file exists but cannot be parsed, the plugin stops saving rather than
overwrite it, and logs the path. That protects a file damaged by a truncated
write or a hand-edit, at the cost of new sessions going unrecorded until you
fix or delete it.

Multi-monitor: the timer, the completion notification and the history file
are owned by a single background service, not by each bar surface. Every
monitor shows the same countdown and drives the same session.

## Contributing

Want to change the code, run the tests, or understand how releases are cut?
See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT — see [LICENSE](LICENSE).
