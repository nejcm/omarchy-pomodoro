# 0001: Derive cycle position from history

## Status

Accepted.

## Context

The timer needs the number of completed pomodoros today to choose a short or
long break. Counting them only in memory would lose the cycle position on a
plugin reload. Persisting a separate counter would duplicate information
already present in the tested history model.

## Decision

Derive the cycle position from today's rows in `pomodoro.json`. This survives
a reload and reuses the history parsing and counting code. A hand-edit that
adds, removes, or changes today's rows also moves the cycle position; that is
an accepted consequence of treating history as the source.

## Consequences

The history array used to retain 50 rows. Once the cycle count came from that
array, reaching the cap froze today's count even as new rows replaced old
ones. The frozen count silently stopped long breaks.

`HISTORY_CAP` therefore rose to 2,881. The bound allows a deliberately
generous 48-hour local day at the minimum one-minute duration:
`48 * 60 / 1 = 2,880`, plus one. Local days can exceed 25 hours after an
offset change, so an ordinary 24- or 25-hour bound is not enough. The 48-hour
figure is a safety margin, not an expected day length.

Retaining up to 2,881 rows made the old history view too expensive: its nested
`Repeater` could instantiate thousands of delegates. The file still retains
up to 2,881 rows for cycle correctness, while the history screen independently
renders only the newest 200.
