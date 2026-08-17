import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import "Model.js" as Model

// Pomodoro bar widget. Mirrors shell/plugins/panels/clock/BarWidget.qml:
// state + persistence + panel-routing contract live on this root; Panel.qml
// is loaded via panelLoader and reads/drives everything through
// `hostWidget`.
BarWidget {
    id: root
    moduleName: "io.github.nejcm.pomodoro"

    // Idle glyph: nf-fa-hourglass_half (U+F252). Classic Font Awesome
    // (U+F0xx-U+F2xx), the one Nerd Fonts range v3 kept intact -- unlike the
    // legacy MDI block (U+F500-U+FD46) it deleted. Monochrome, so it inherits
    // the bar foreground. Built from a hex literal, never a pasted character:
    // a raw Private-Use-Area byte in the file is invisible in review, and
    // this keeps the source pure ASCII. Panel.qml's glyphs follow the same
    // rule; that block carries the codepoint-range rationale for all four.
    readonly property string idleGlyph: String.fromCharCode(0xf252)

    // --- settings, section 5 -----------------------------------------------
    // Trust boundary: shell.json is hand-edited, so validate through Model.
    readonly property int durationMinutes: Model.validMinutesOr(setting("minutes", 25), 25)
    readonly property bool notifyEnabled: setting("notify", true) === true

    // --- state, section 4 ----------------------------------------------
    property bool running: false
    property bool started: false
    property var history: []
    // Epoch milliseconds (~1.77e12 today) overflows QML's 32-bit int
    // (max ~2.15e9) — must be double, not int. Same for endsAt and nowMs.
    property double sessionStartedAt: 0
    // Duration in effect for the in-progress session, snapshotted at start()
    // so a mid-session durationMinutes edit can't retroactively relabel the
    // history row or notification for a session that already ran at the old
    // duration (plan section 4: duration changes apply "on the next session").
    property int sessionMinutes: 0

    // The countdown is derived from a wall-clock deadline, never decremented.
    // A Timer that misses intervals (suspend, event-loop starvation) fires
    // once on resume instead of catching up, so a counter would silently keep
    // the time that elapsed while it wasn't running; recomputing against
    // Date.now() cannot drift. Staying readonly is also what lets the idle
    // branch track durationMinutes live, with no imperative reassignment
    // anywhere: a mid-session shell.json edit can't reach an in-flight
    // session, because that session reads endsAt instead.
    property double endsAt: 0       // epoch ms; meaningful while running
    // Banked remainder as of the last pause(), in *milliseconds*. Whole
    // seconds would have to round, and the only rounding consistent with the
    // display is Math.ceil -- which hands back up to a second of extra time on
    // every pause/resume cycle, an error that accumulates rather than washing
    // out. Keeping the raw remainder makes resume exact and leaves rounding
    // where it belongs: in the display binding below.
    property double pausedMs: 0
    property double nowMs: 0        // advanced by the ticker

    readonly property int remainingSeconds: running ? Math.max(0, Math.ceil((endsAt - nowMs) / 1000))
                                                    : (started ? Math.max(0, Math.ceil(pausedMs / 1000))
                                                               : durationMinutes * 60)

    readonly property bool idle: !started
    readonly property bool paused: started && !running
    readonly property string barText: idle ? idleGlyph : Model.mmss(remainingSeconds)

    // --- transitions, section 4 table --------------------------------------
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
    // argv, not a shell string: execDetached takes the arguments directly, so
    // nothing here is parsed by a shell and no argument needs quoting. Also
    // drops the dependency on bar.run being present.
    function sendCompletionNotification() {
        Quickshell.execDetached(["notify-send", "-a", "Pomodoro", "-u", "normal",
                                 "Pomodoro complete",
                                 root.sessionMinutes + " minute session done"])
    }

    // --- persistence, section 8 --------------------------------------
    readonly property string stateDir: Quickshell.env("HOME") + "/.local/state/omarchy"
    readonly property string historyPath: stateDir + "/pomodoro.json"

    // ponytail: this widget's state (including history) is per bar-widget
    // instance, and a bar surface exists per monitor — so two monitors run
    // two independent timers, fire two completion notifications, and both
    // whole-file-write the same pomodoro.json with last-writer-wins,
    // silently losing whichever session's row lost the race. Fine for the
    // common single-bar desktop this plan targets; upgrade path is a
    // `service` kind + keepLoaded owning the one true timer/history if
    // multi-monitor ever matters (reopens plan decision 6 — plan owner's
    // call, not fixed here).

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

    // --- panel routing contract, section 5 --------------------------------
    // Must live on this bar-widget root, not the nested panel — Bar.qml's
    // popout coordinator (findPanelWidget / requestPopout) looks here.
    readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

    function open() {
        if (panelLoader.item) panelLoader.item.open()
    }

    function close() {
        if (panelLoader.item) panelLoader.item.close()
    }

    function togglePanel() {
        if (panelLoader.item) panelLoader.item.toggle()
    }

    readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

    function closeForPopoutSwitch() {
        if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
    }

    // Injects what Panel.qml needs onto the loaded instance, same shape as
    // the clock/weather plugins. Only bar/settings/anchorItem/hostWidget are
    // pushed; timer state and callbacks are read live off `hostWidget`
    // instead, because this runs only on bar/settings changes while the
    // state changes every tick.
    function injectPanel() {
        var target = panelLoader.item
        if (!target) return
        if ("bar" in target) target.bar = root.bar
        if ("settings" in target) target.settings = root.settings
        if ("anchorItem" in target) target.anchorItem = button
        if ("hostWidget" in target) target.hostWidget = root
    }

    onBarChanged: injectPanel()
    onSettingsChanged: injectPanel()

    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight

    WidgetButton {
        id: button
        anchors.fill: parent
        bar: root.bar
        text: root.barText
        dimmed: root.paused
        onPressed: function (b) {
            // Left click only — no right/middle click actions.
            if (b === Qt.LeftButton) root.togglePanel()
        }
    }

    Loader {
        id: panelLoader
        active: true
        source: Qt.resolvedUrl("Panel.qml")
        visible: false
        onLoaded: {
            root.injectPanel()
            Qt.callLater(root.injectPanel)
        }
    }

    Component.onCompleted: {
        ensureStateDirProc.running = true
    }
}
