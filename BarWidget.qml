import QtQuick
import qs.Ui
import "Model.js" as Model

// Pomodoro bar widget -- a *view* onto Service.qml.
//
// A bar surface exists per monitor, so this file is instantiated once per
// screen. It therefore owns no timer state: the countdown, the completion
// notification and the session-history file all live on the single service
// instance reached through `timer` below.
//
// It does own one write, though: persistMinutes() saves a settled idle
// duration nudge back to this widget's shell.json entry. That cannot live on
// the service -- the shell injects `bar` and `settings` here and neither one
// there -- so the service says *when* and *who*, and this file does it.
//
// Everything else here is genuinely per-surface: the button, the panel
// loader, and the open/close contract Bar.qml's popout coordinator looks for
// on the bar-widget root (see the panel routing section).
BarWidget {
    id: root

    // The service is keyed in shell.qml's `_services` by the *plugin* id from
    // the manifest. `moduleName` is injected by the bar and is only the same
    // string by convention (a cloned widget entry would carry a suffixed id),
    // so the service lookups below use this constant instead.
    readonly property string pluginId: "io.github.nejcm.pomodoro"

    moduleName: pluginId

    // Idle glyph: nf-fa-hourglass_half (U+F252). Classic Font Awesome
    // (U+F0xx-U+F2xx), the one Nerd Fonts range v3 kept intact -- unlike the
    // legacy MDI block (U+F500-U+FD46) it deleted. Monochrome, so it inherits
    // the bar foreground. Built from a hex literal, never a pasted character:
    // a raw Private-Use-Area byte in the file is invisible in review, and
    // this keeps the source pure ASCII. Panel.qml's glyphs follow the same
    // rule; that block carries the codepoint-range rationale for all four.
    readonly property string idleGlyph: String.fromCharCode(0xf252)

    // --- the shared timer --------------------------------------------------
    // `_services` is a property on shell.qml, so this binding is live: it
    // flips from null to the instance the moment the service mounts, and back
    // to null if `_syncServices` tears it down. Guarded on the function's
    // existence so an older host shell without the service API degrades to a
    // visibly dead widget (idle glyph, inert panel) plus the warning in
    // ensureTimer(), instead of throwing on every binding evaluation.
    readonly property var timer: bar && bar.shell && typeof bar.shell.serviceFor === "function"
                                 ? bar.shell.serviceFor(root.pluginId) : null

    // shell.qml mounts services in its own Component.onCompleted; bar surfaces
    // are built independently, and a plugin added to the bar at runtime races
    // the pluginsChanged sync. This closes that window from our side.
    // ensureService() is idempotent -- it returns any existing instance
    // untouched -- and does not consult isEnabled(), so it is safe to call
    // from every monitor.
    function ensureTimer() {
        var host = bar ? bar.shell : null
        if (!host) return
        if (typeof host.serviceFor !== "function" || typeof host.ensureService !== "function") {
            console.warn("pomodoro: host shell has no serviceFor/ensureService;",
                         "the timer cannot start. Update omarchy-shell.")
            return
        }
        if (!host.serviceFor(root.pluginId)) host.ensureService(root.pluginId)
    }

    // The shell injects omarchyPath/shell/manifest/... into a service, but not
    // `settings` -- those live on the bar *entry*, which only this widget can
    // see. So resolve them here (setting() applies the shell.json fallbacks)
    // and hand the service already-resolved values; it still re-validates
    // `minutes` through Model, because shell.json is hand-edited.
    //
    // Called from onTimerChanged as well as onSettingsChanged, so the mount
    // order does not matter. That means N monitors push N times, and a `var`
    // property re-assignment can re-fire onTimerChanged with an unchanged
    // instance -- applySettings is idempotent for exactly this reason.
    function pushSettings() {
        // Bar.qml's injectProps() assigns `bar` before `settings`, so a push
        // driven by the bar arriving (or by the service mounting in that same
        // window) would hand over setting()'s *fallbacks* rather than the
        // entry. Harmless on the first monitor, not on a second one attached
        // later: the fallback would differ from a duration the user had
        // nudged, and applySettings would take it as a real config change and
        // stomp the nudge. So wait for the entry.
        if (!settingsReceived) return
        if (!timer || typeof timer.applySettings !== "function") return
        timer.applySettings({
            minutes: setting("minutes", Model.DEFAULT_MINUTES),
            notify: setting("notify", true) === true
        })
    }

    // Writes a settled idle nudge back to this widget's shell.json entry, so
    // a duration the user converged on survives a restart instead of being
    // discarded. Reached only through the service's debounce timer, and only
    // by the writer it elected -- once per gesture, once per shell, not once
    // per monitor.
    function persistMinutes(minutes) {
        if (!settingsReceived) return
        if (!bar || !bar.shell || typeof bar.shell.updateEntryInline !== "function") return
        if (!timer || typeof timer.claimSettingsWriter !== "function") return
        if (!timer.claimSettingsWriter(root)) return
        // Already what the entry says. Cheap, but it also covers the case
        // where a hand-edit to shell.json landed inside the debounce window
        // and the service adopted it: there is nothing of ours left to write.
        if (setting("minutes", Model.DEFAULT_MINUTES) === minutes) return

        // Every other key is carried over, not just the ones this plugin
        // knows about: the host replaces the whole entry with what it is
        // handed (shell.qml updateEntryInline), and the bar derives `settings`
        // from the entry minus `id` (BarModel.entrySettings). A key dropped
        // here is dropped from the user's shell.json -- `notify` included.
        var entry = { id: root.moduleName }
        for (var key in root.settings) if (key !== "id") entry[key] = root.settings[key]
        entry.minutes = minutes

        // Local first, as the clock widget does. `settings` is what
        // pushSettings() reads, so leaving it stale would let a later push
        // re-announce the old duration and stomp the nudge. The write below
        // comes straight back through shellConfig -> the bar -> `settings`
        // carrying this same value, which is exactly why the loop settles:
        // applySettings only acts on a value it has not already applied.
        root.settings = entry
        bar.shell.updateEntryInline(root.moduleName, entry)
    }

    // Rebinds when the service mounts or `_syncServices` tears it down; a
    // null target is inert, so no guard is needed here.
    Connections {
        target: root.timer
        function onDefaultMinutesCommitted(minutes) { root.persistMinutes(minutes) }
    }

    // Until the service mounts, `timer` is null and the widget shows the idle
    // hourglass -- the same thing a mounted-but-unstarted timer shows, so the
    // bar never flashes a bogus countdown. A click in that window still opens
    // the panel; every control in there is guarded on `timer` and reads as
    // disabled, which is the honest rendering of "no timer yet".
    readonly property string barText: !timer ? idleGlyph
                                             : (timer.idle ? idleGlyph : Model.mmss(timer.remainingSeconds))

    // --- panel routing contract -------------------------------------------
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
    // the clock/weather plugins. `hostWidget` is the panel's *identity* (the
    // bar-widget root the popout coordinator keys off); `timer` is where it
    // reads state and drives transitions. They are separate on purpose --
    // there is one panel per monitor but one timer for all of them.
    function injectPanel() {
        var target = panelLoader.item
        if (!target) return
        if ("bar" in target) target.bar = root.bar
        if ("settings" in target) target.settings = root.settings
        if ("anchorItem" in target) target.anchorItem = button
        if ("hostWidget" in target) target.hostWidget = root
        if ("timer" in target) target.timer = root.timer
    }

    // Set by the first settings injection; see pushSettings().
    property bool settingsReceived: false

    onBarChanged: {
        ensureTimer()
        injectPanel()
        pushSettings()
    }

    onSettingsChanged: {
        settingsReceived = true
        injectPanel()
        pushSettings()
    }

    // `timer` is a pushed value on the panel, not a binding, so the panel
    // would otherwise keep a stale (or destroyed) reference when the service
    // mounts late or `_syncServices` tears it down. Re-inject on every change.
    onTimerChanged: {
        injectPanel()
        pushSettings()
    }

    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight

    WidgetButton {
        id: button
        anchors.fill: parent
        bar: root.bar
        text: root.barText
        dimmed: !!root.timer && root.timer.paused
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

    // `bar` is injected after construction (Bar.qml injectProps), so this is
    // normally a no-op and onBarChanged does the work. Kept for a host that
    // passes `bar` as an initial property instead, where that signal never
    // fires; ensureTimer() is guarded on `bar` and idempotent either way.
    Component.onCompleted: ensureTimer()
}
