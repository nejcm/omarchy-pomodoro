import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

// The one true pomodoro timer.
//
// A bar surface exists per monitor, so BarWidget.qml is instantiated once per
// screen. Owning the timer there meant N independent countdowns, N completion
// notifications, and N whole-file writes to the same pomodoro.json with
// last-writer-wins. This service is instantiated exactly once per shell
// (shell.qml `_syncServices`, mounted from `serviceHost`), so it owns all
// timer state, the ticker, the notification, and the session-history file.
// Bar widgets are views: they read this through `bar.shell.serviceFor(...)`
// and drive it through the transitions below.
//
// Persistence is split, deliberately. The history file is this file's. The
// *settings* write -- saving an idle duration nudge back to the widget's
// shell.json entry -- is BarWidget.qml's, because the entry is only visible
// from the bar side; this file decides when a nudge has settled and which
// view writes it (see the commit section near the bottom).
//
// Lifecycle worth knowing:
//   - Mounted at startup for any enabled plugin declaring kind "service" with
//     an `entryPoints.service`. This plugin counts as enabled purely by having
//     a `bar.layout` entry (PluginRegistry.findEntryLocation), so no
//     shell.json change and no `keepLoaded` is needed.
//   - Destroyed by `_syncServices` when the plugin is disabled or removed --
//     which in practice also removes the bar entry, so the views go with it.
//   - Recreated on a plugin reload, which drops in-flight timer state. Same as
//     before this split: a running timer has never survived a shell restart.
//
// The shell injects omarchyPath/shell/manifest/barWidgetRegistry/
// pluginRegistry into a service if those properties exist -- it does NOT
// inject `settings`, because settings live on the bar *entry*. Hence
// applySettings() below.
Item {
    id: root

    // --- settings, pushed in by the bar widget(s) ---------------------------
    // Trust boundary: shell.json is hand-edited, so validate through Model.
    property int durationMinutes: Model.DEFAULT_MINUTES
    property bool notifyEnabled: true

    // The `minutes` value last accepted from shell.json, already validated.
    // Two jobs, both load-bearing:
    //   - Idempotence. Every bar widget pushes settings, and it pushes them
    //     again whenever its `timer` binding re-evaluates. On a dual-head
    //     setup that is several identical calls; only a genuine change may
    //     have an effect.
    //   - It keeps a panel +/- nudge alive. adjustMinutes() writes
    //     durationMinutes directly while idle; without this guard the second
    //     monitor re-announcing the unchanged config would stomp the nudge.
    //   - It absorbs the commit round-trip. A settled idle nudge is written
    //     back to shell.json (see the commit section below), and the widget
    //     applies the committed entry to its own `settings` *before* handing
    //     it to the host -- so appliedMinutes has already moved onto the new
    //     value by the time the config comes back through the bar, and every
    //     announcement of it from then on compares equal and does nothing.
    //     The loop settles instead of ping-ponging.
    // A real shell.json edit still lands, because the validated value differs.
    // -1 is unreachable through validMinutesOr (MIN_MINUTES is 1), so it
    // doubles as "nothing applied yet".
    property int appliedMinutes: -1

    // Settings arrive as a plain object of already-resolved values (the bar
    // widget applies its own `setting()` fallbacks first, since only it can
    // see the layout entry). Order against mount does not matter: if the
    // service mounts second, the widget's `timer` binding fires and pushes;
    // if it mounts first, the widget pushes on settings/bar changes anyway.
    function applySettings(obj) {
        var src = obj || ({})
        var minutes = Model.validMinutesOr(src.minutes, Model.DEFAULT_MINUTES)
        if (minutes !== appliedMinutes) {
            appliedMinutes = minutes
            durationMinutes = minutes
        }
        notifyEnabled = src.notify !== false
    }

    // --- state -------------------------------------------------------------
    property bool running: false
    property bool started: false
    property var history: []
    // Epoch milliseconds (~1.77e12 today) overflows QML's 32-bit int
    // (max ~2.15e9) — must be double, not int. Same for endsAt and nowMs.
    property double sessionStartedAt: 0
    // Duration in effect for the in-progress session, snapshotted at start()
    // so a mid-session durationMinutes edit can't retroactively relabel the
    // history row or notification for a session that already ran at the old
    // duration (duration changes apply "on the next session").
    property int sessionMinutes: 0

    // The countdown is derived from a wall-clock deadline, never decremented.
    // A Timer that misses intervals (suspend, event-loop starvation) fires
    // once on resume instead of catching up, so a counter would silently keep
    // the time that elapsed while it wasn't running; recomputing against
    // Date.now() cannot drift. The idle branch tracks durationMinutes live;
    // a mid-session shell.json edit still can't reach an in-flight session,
    // because that session reads endsAt/sessionMinutes instead. The one
    // deliberate write to a started session is adjustMinutes() below.
    property double endsAt: 0       // epoch ms; meaningful while running
    // Banked remainder as of the last pause(), in *milliseconds*. Whole
    // seconds would have to round, and the only rounding consistent with the
    // display is Math.ceil -- which hands back up to a second of extra time on
    // every pause/resume cycle, an error that accumulates rather than washing
    // out. Keeping the raw remainder makes resume exact and leaves rounding
    // where it belongs: in the display bindings on the views.
    property double pausedMs: 0
    property double nowMs: 0        // advanced by the ticker

    readonly property int remainingSeconds: running ? Math.max(0, Math.ceil((endsAt - nowMs) / 1000))
                                                    : (started ? Math.max(0, Math.ceil(pausedMs / 1000))
                                                               : durationMinutes * 60)

    readonly property bool idle: !started
    readonly property bool paused: started && !running

    // --- transitions -------------------------------------------------------
    function start() {
        if (running) return
        var ms = started ? pausedMs : durationMinutes * 60 * 1000
        if (!started) {
            started = true
            sessionStartedAt = Date.now()
            sessionMinutes = durationMinutes
        }
        nowMs = Date.now()
        endsAt = nowMs + ms
        running = true
    }

    function pause() {
        if (!running) return
        // Refresh nowMs before banking the remainder: pausing before the
        // first tick after a resume would otherwise store a stale value.
        nowMs = Date.now()
        // The deadline can already have passed: remainingSeconds reaches 0 the
        // moment Date.now() > endsAt, but complete() only runs on the next
        // tick, and ticks land late. Pausing inside that gap used to bank a
        // zero remainder and stop the ticker, stranding the widget on a dimmed
        // 00:00 forever -- no notification, no history row, and a reset from
        // there would discard a session that had in fact finished. Finish it
        // instead; a session past its deadline is complete, not pausable.
        if (endsAt - nowMs <= 0) {
            complete()
            return
        }
        pausedMs = endsAt - nowMs
        running = false
    }

    function reset() {
        if (!started) return
        running = false
        started = false
        // No history row. Never auto-starts.
    }

    function toggleRunning() {
        if (running) pause()
        else start()
    }

    function complete() {
        history = Model.pushSession(history, { startedAt: sessionStartedAt, minutes: sessionMinutes })
        persistHistory()
        if (notifyEnabled) sendCompletionNotification()
        reset()
    }

    // --- duration adjustment, panel +/- and wheel --------------------
    // Both route through Model.adjustSession so the clamp and the
    // never-shorten-past-what-is-left guard live once, and are testable.

    // Live remainder in milliseconds. Date.now(), not nowMs: the ticker
    // advances nowMs once a second, so a guard measured against it is up to a
    // second stale -- enough for a -5 to be allowed when it would in fact
    // land the deadline in the past.
    function liveRemainingMs() {
        if (running) return endsAt - Date.now()
        if (started) return pausedMs
        return durationMinutes * 60 * 1000
    }

    function canAdjust(delta) {
        if (idle) return Model.stepMinutes(durationMinutes, delta) !== durationMinutes
        // Reading nowMs is the binding dependency that makes the panel's +/-
        // `enabled` re-evaluate each tick; the arithmetic below deliberately
        // does not use it (see liveRemainingMs).
        var tick = nowMs
        return tick >= 0 && Model.adjustSession(sessionMinutes, liveRemainingMs(), delta) !== null
    }

    // Idle writes durationMinutes, same as any other pending-setting change
    // (and appliedMinutes above keeps a sibling monitor from stomping it),
    // and schedules the commit that makes it the persisted default.
    // Started writes sessionMinutes instead -- the comment on that property
    // above says a mid-session *config* edit can't relabel history; this is
    // the deliberate exception, an explicit user nudge, applied live to the
    // running deadline (endsAt) or banked remainder (pausedMs) so the
    // countdown reflects it immediately.
    function adjustMinutes(delta) {
        if (idle) {
            var next = Model.stepMinutes(durationMinutes, delta)
            // Clamped to the same value (the wheel can reach a bound the
            // panel's `enabled` binding would have blocked): nothing changed,
            // so nothing to commit.
            if (next === durationMinutes) return
            durationMinutes = next
            // Idle means the user is setting the *default*, so it gets
            // persisted. Only this branch: the started-session branch below
            // is scoped to the session in progress and must never reach
            // shell.json.
            commitDebounce.restart()
            return
        }
        var step = Model.adjustSession(sessionMinutes, liveRemainingMs(), delta)
        if (!step) return
        sessionMinutes = step.minutes
        if (running) endsAt += step.appliedMs
        else pausedMs += step.appliedMs
    }

    // --- persisting an idle nudge -------------------------------------
    // An idle nudge changes the default duration, so it belongs in
    // shell.json rather than only in memory. The write is deliberately not
    // ours: the shell injects `shell` into a service but never `settings`,
    // and the value lives on the bar *entry*, which only BarWidget.qml can
    // see. This side decides *when* a nudge has settled and *who* writes it.
    signal defaultMinutesCommitted(int minutes)

    // Debounce. One wheel flick is several adjustMinutes() calls tens of
    // milliseconds apart, and every write re-enters synchronously as
    // shellConfig -> barConfig -> settings -> applySettings; committing per
    // notch would rewrite shell.json a dozen times for one gesture. The
    // interval only has to outlast the gaps *within* an input burst -- not
    // the round-trip, which settles on its own -- while staying short enough
    // that the value is on disk before the hand leaves the wheel. 400ms sits
    // between the two: an order of magnitude above wheel-notch spacing, well
    // under the ~1s at which a save stops feeling immediate. restart(), not
    // start(), so a burst commits once, at its final value.
    Timer {
        id: commitDebounce
        interval: 400
        repeat: false
        // durationMinutes is read at fire time, not captured at nudge time,
        // so the burst commits where it landed. Starting a session inside the
        // window does not cancel it: the nudge was still a change to the
        // default, and start() leaves durationMinutes alone.
        onTriggered: root.defaultMinutesCommitted(root.durationMinutes)
    }

    // The elected writer. Every monitor's bar widget hears the signal above
    // and is equally able to write, so on an N-head setup N of them would
    // call updateEntryInline with the same entry. That is not corrupting --
    // the host dirty-checks, so writes 2..N compare equal to the shellConfig
    // write 1 just installed and return false -- but each still deep-clones
    // the whole config to find that out, and leaning on the host's dirty
    // check makes single-writing a property of omarchy-shell rather than of
    // this plugin. Electing here keeps it ours and costs one comparison.
    //
    // Typed `Item`, not `var`, deliberately: QML clears an object-typed
    // property when its object is destroyed, so unplugging the elected
    // monitor re-opens the election on the next commit instead of stranding
    // it on a dead widget.
    property Item settingsWriter: null

    // Claimed by the first view that asks -- which, because the widget checks
    // its own preconditions (settings received, host API present) before
    // calling, is the first view actually able to write.
    function claimSettingsWriter(view) {
        if (!settingsWriter) settingsWriter = view
        return settingsWriter === view
    }

    Timer {
        id: ticker
        interval: 1000
        repeat: true
        running: root.running
        onTriggered: {
            root.nowMs = Date.now()
            if (root.remainingSeconds <= 0) root.complete()
        }
    }

    // --- notification -------------------------------------------------
    // Fires once per completed session, not once per monitor -- the point of
    // this file. argv, not a shell string: execDetached takes the arguments
    // directly, so nothing here is parsed by a shell and no argument needs
    // quoting. Also drops the dependency on bar.run being present, which a
    // service has no access to anyway.
    function sendCompletionNotification() {
        Quickshell.execDetached(["notify-send", "-a", "Pomodoro", "-u", "normal",
                                 "Pomodoro complete",
                                 root.sessionMinutes + " minute session done"])
    }

    // --- persistence ---------------------------------------------------
    // Single writer now: one service per shell means the whole-file rewrite
    // below has no concurrent peer to clobber.
    readonly property string stateDir: Quickshell.env("HOME") + "/.local/state/omarchy"
    readonly property string historyPath: stateDir + "/pomodoro.json"

    // Ensures the state directory exists before any write. Read-on-load
    // tolerates a missing file/dir fine (FileView + Model.parseHistory both
    // degrade to []); this only matters for the first write.
    Process {
        id: ensureStateDirProc
        command: ["mkdir", "-p", root.stateDir]
        running: false
    }

    // True once we know what is on disk -- either it loaded, or it definitively
    // wasn't there. Until then `history` is an empty placeholder that merely
    // looks like an empty log, and writing it would publish that guess over
    // real data.
    property bool historyLoaded: false

    // The file exists and holds something, but parseHistory rejected all of
    // it. That is not an empty log; it is a log we failed to read (truncated
    // write, hand-edit typo, older format). Overwriting it would destroy the
    // only copy, so persistence stops until a human resolves it.
    property bool historyUnreadable: false

    // atomicWrites so a shell crash mid-write leaves the previous file
    // intact rather than a truncated one. printErrors stays off because the
    // history file is legitimately absent on first run (same setting as
    // Clipboard.qml's identically-shaped FileView); onSaveFailed covers the
    // write side that suppression would otherwise hide.
    FileView {
        id: historyFile
        path: root.historyPath
        watchChanges: false
        atomicWrites: true
        printErrors: false
        onLoaded: {
            var raw = text()
            var parsed = Model.parseHistory(raw, Model.HISTORY_CAP)
            root.history = parsed
            // Distinguishing the two ways of arriving at [] is the whole point:
            // an absent or genuinely empty file is safe to overwrite, a file
            // with bytes we couldn't parse is not.
            root.historyUnreadable = parsed.length === 0 && raw.trim().length > 0
            if (root.historyUnreadable)
                console.warn("pomodoro: could not parse", root.historyPath,
                             "- leaving it untouched; sessions will not be saved until it is fixed or removed")
            root.historyLoaded = true
        }
        onLoadFailed: {
            // Absent file on first run is the normal path, not an error.
            root.history = []
            root.historyUnreadable = false
            root.historyLoaded = true
        }
        onSaveFailed: function (error) { console.warn("pomodoro: history save failed", error) }
    }

    function persistHistory() {
        // Never write ahead of the load. complete() can only fire a full
        // session after startup, so the race is not reachable through the UI
        // today -- but the guard costs nothing and the failure it prevents
        // (publishing a placeholder [] over a real log) is unrecoverable.
        if (!historyLoaded) return
        if (historyUnreadable) {
            console.warn("pomodoro: refusing to overwrite unparseable", root.historyPath)
            return
        }
        historyFile.setText(Model.serializeHistory(root.history))
    }

    Component.onCompleted: {
        ensureStateDirProc.running = true
    }
}
