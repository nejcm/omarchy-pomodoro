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

    // --- Nerd Font glyph, plan risk 3 -------------------------------------
    // Idle-state glyph: nf-fa-hourglass_half (U+F252), an hourglass -- reads
    // as a countdown, and stays distinct from omarchy.clock, which already
    // occupies the bar with a clock face. Classic Font Awesome, a codepoint
    // block Nerd Fonts v3 kept intact (confirmed: this omarchy tree itself
    // uses adjacent codepoints from the same \uf0xx-\uf2xx FA block
    // directly, e.g. Tray.qml's U+F053, SystemUpdate.qml's U+F021,
    // PolkitAgent.qml's U+F023 -- so this range is Nerd-Fonts-v3-safe).
    // Monochrome so it inherits the bar foreground -- decision 3 ruled out
    // color emoji for exactly this reason. Swap for a literal "P" if a
    // Nerd Font build ever drops classic FA too.
    readonly property string idleGlyph: "\uf252"

    // --- settings, section 5 -----------------------------------------------
    // Trust boundary: shell.json is hand-edited, so clamp through Model.
    readonly property int durationMinutes: Model.clampMinutes(setting("minutes", 25), 25)
    readonly property bool notifyEnabled: setting("notify", true) === true

    // --- state, section 4 ----------------------------------------------
    property int remainingSeconds: durationMinutes * 60
    property bool running: false
    property bool started: false
    property var history: []
    // Epoch milliseconds (~1.77e12 today) overflows QML's 32-bit int
    // (max ~2.15e9) — must be double, not int.
    property double sessionStartedAt: 0

    readonly property bool idle: !started
    readonly property bool paused: started && !running
    readonly property string barText: idle ? idleGlyph : Model.mmss(remainingSeconds)

    // durationMinutes changing while idle takes effect immediately; while a
    // session is in progress it takes effect on the next session only.
    onDurationMinutesChanged: {
        if (!started) remainingSeconds = durationMinutes * 60
    }

    // --- transitions, section 4 table --------------------------------------
    function start() {
        if (running) return
        if (!started) {
            started = true
            sessionStartedAt = Date.now()
            // Break remainingSeconds' initial live binding to durationMinutes
            // right away, so a shell.json edit in the sub-second window
            // before the first tick can't yank time from this session.
            remainingSeconds = durationMinutes * 60
        }
        running = true
    }

    function pause() {
        if (!running) return
        running = false
    }

    function reset() {
        if (!started) return
        running = false
        started = false
        remainingSeconds = durationMinutes * 60
        // No history row. Never auto-starts.
    }

    function toggleRunning() {
        if (running) pause()
        else start()
    }

    function complete() {
        history = Model.pushSession(history, { startedAt: sessionStartedAt, minutes: durationMinutes }, 50)
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
            root.remainingSeconds -= 1
            if (root.remainingSeconds <= 0) root.complete()
        }
    }

    // --- notification -------------------------------------------------
    // Arguments are literals plus an integer (durationMinutes, clamped
    // 1..180 by Model.clampMinutes) — never free text — so there's no
    // shell-quoting hole through bar.run's single command string.
    function sendCompletionNotification() {
        if (!root.bar) return
        var minutes = Math.round(root.durationMinutes)
        var cmd = "notify-send -a Pomodoro -u normal \"Pomodoro complete\" \"" + minutes + " minute session done\""
        root.bar.run(cmd)
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

    // Write API chosen: FileView.setText(), confirmed in-tree (e.g.
    // shell/shell.qml's userConfigFile.setText(...), Clipboard.qml's
    // historyFile.setText(...)). atomicWrites avoids a torn file if the
    // shell dies mid-write. Fallback if setText doesn't behave on the real
    // box: shell the JSON out via bar.run("mkdir -p ... && printf ... >
    // file") the way shell/plugins/notifications/Service.qml does for its
    // popup cache.
    FileView {
        id: historyFile
        path: root.historyPath
        watchChanges: false
        atomicWrites: true
        printErrors: false
        onLoaded: root.history = Model.parseHistory(text())
        onLoadFailed: root.history = []
    }

    function persistHistory() {
        historyFile.setText(Model.serializeHistory(root.history))
    }

    // --- panel routing contract, section 5 / plan risk 4 -------------------
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

    // Injects the properties Panel.qml needs onto the loaded instance, same
    // shape as the clock/weather plugins: bar/settings/anchorItem/hostWidget
    // injected here; everything else (remainingSeconds, running, started,
    // paused, history, and the start/pause/reset/toggleRunning callbacks)
    // read and called live off `hostWidget` rather than copied in, since
    // state changes every tick and injectPanel only re-runs on bar/settings
    // changes.
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
