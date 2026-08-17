# Pomodoro (`io.github.nejcm.pomodoro`)

Omarchy Quickshell bar widget. Hourglass glyph while idle; the glyph is replaced
by a live `mm:ss` countdown while running, dimmed while paused. Click it to
open a panel with play/pause, reset, and a log of completed sessions below.

## Install

```bash
git clone <this repo> ~/.config/omarchy/plugins/io.github.nejcm.pomodoro
omarchy plugin validate ~/.config/omarchy/plugins/io.github.nejcm.pomodoro
omarchy-shell shell rescanPlugins
omarchy-shell shell setPluginEnabled io.github.nejcm.pomodoro true
```

Third-party plugins install disabled by default; `setPluginEnabled` above
turns it on after review.

Then add it to `bar.layout.right` in `~/.config/omarchy/shell.json` — see
Settings below for the entry shape.

## Settings

Set under the widget's entry in `shell.json`:

| Key | Default | Description |
|---|---|---|
| `minutes` | `25` | Session length. Must be a JSON **number** in 1–180; anything else falls back to 25 |
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

## Usage

- Idle: hourglass glyph in the bar.
- Running: glyph is replaced by a `mm:ss` countdown; paused shows the same
  text at reduced opacity.
- Click the widget to open the panel: play/pause and reset controls above,
  a session log below.
- Reset stops the timer and restores the full duration without recording a
  history row.
- Completed sessions are recorded (no aborted sessions), newest first,
  capped at 50 rows.

## History

Stored at `~/.local/state/omarchy/pomodoro.json`. A running (or paused)
timer does **not** survive a shell restart — only completed-session history
persists.

Multi-monitor: each bar surface runs its own timer and whole-file-writes
history on completion, so a dual-head setup can produce duplicate or
last-writer-wins history entries. See improvements.md.

`preview.png` is pending a screenshot on real hardware.
