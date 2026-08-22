// The history Repeater's delegate reads ids from this file's outer scope
// (root, historyRows). Under the default Unbound behavior that access is
// unqualified -- it happens to resolve, but qmllint flags it and the lookup
// isn't guaranteed. Bound captures the enclosing scope properly; it also
// requires delegate model properties to be declared `required`, which the
// delegate below already does.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Pomodoro control panel: countdown + play/pause/reset + session history.
// Service.qml owns all timer state and persistence. This panel never copies
// that state in -- it reads live off `timer` and drives it through the
// service's own start()/pause()/reset()/toggleRunning(), because injectPanel
// re-fires only on bar/settings/timer changes, not every tick, so any local
// copy would go stale within a second.
Panel {
  id: root
  moduleName: "io.github.nejcm.pomodoro"

  // Injected by BarWidget.qml's injectPanel().
  property var anchorItem: null

  // Two references, deliberately not one. `hostWidget` is the bar-widget root
  // that owns this panel -- an identity, one per monitor, used only for popout
  // routing and anchoring. `timer` is the single Service.qml instance shared
  // by every monitor, and is where all state and every transition lives.
  property var hostWidget: null

  // Null until the service mounts (and null again if `_syncServices` tears it
  // down), exactly like hostWidget is null before injection -- so every read
  // below stays guarded. BarWidget re-injects on change, so this never holds a
  // destroyed instance.
  property var timer: null

  // Bar.findPanelWidget / switchPanelFrom key off the bar-widget root
  // (BarWidget.qml's `root`), not this nested panel. So route switchPanel
  // through barIdentity rather than the base Panel's own switchPanel, which
  // would pass this nested panel as the owner. Same fix the clock plugin uses.
  readonly property var barIdentity: hostWidget || root

  // timer is injected in Loader.onLoaded (and again whenever the service
  // mounts), which fires after these bindings first evaluate -- hence the null
  // guard. Hoisted here so the history views below read as plain state instead
  // of each repeating the guard, and so the empty/non-empty pair below is
  // visibly one predicate and its negation.
  readonly property int historyCount: timer ? timer.history.length : 0

  // Transport controls, sized as the panel's hero affordance rather than as
  // incidental icons. The default `Style.font.icon` (= title, 14) reads as a
  // toolbar glyph next to a 24px countdown; `display` puts the two on the same
  // footing. The hit target is set explicitly instead of leaning on
  // PanelActionButton's default (`fontSize` + `spacing.sm` * 2, which leaves
  // only 4px around the glyph) -- a play/pause you press repeatedly wants
  // margin for an imprecise click. Both are tokens, so they still track the
  // theme's font and spacing scales.
  readonly property int controlGlyphSize: Style.font.display
  readonly property int controlHitSize: Style.space(44)

  // The +/- pair stays secondary to play/pause, but PanelActionButton's
  // default (14px glyph in a 22px box) reads as a right-edge row action
  // next to a 24px countdown. One step up on each scale -- still both
  // tokens, so they track the theme.
  readonly property int adjustGlyphSize: Style.font.iconLarge
  readonly property int adjustHitSize: Style.space(32)

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  // Guarded so the panel renders before the bar is injected, same pattern
  // as shell/plugins/panels/clock/Panel.qml.
  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family

  // ---- glyphs ------------------------------------------------------------
  // Classic Font Awesome (U+F0xx-U+F2xx), the range Nerd Fonts v3 kept
  // intact -- unlike the legacy MDI block (U+F500-U+FD46) it deleted. These
  // are fixed Font Awesome 4 codepoints, unaffected by Nerd Fonts' 5-hex MDI
  // churn. Same range as BarWidget.qml's hourglass, and as this omarchy
  // tree's own Tray.qml and SystemUpdate.qml glyphs.
  //
  // Always String.fromCharCode over a hex literal, never a source escape or
  // a pasted character: the codepoint stays unambiguous and the file stays
  // pure ASCII, so a stray Private-Use-Area byte can't land here invisibly.
  readonly property string playGlyph: String.fromCharCode(0xf04b)
  readonly property string pauseGlyph: String.fromCharCode(0xf04c)
  readonly property string resetGlyph: String.fromCharCode(0xf0e2)
  readonly property string plusGlyph: String.fromCharCode(0xf067)
  readonly property string minusGlyph: String.fromCharCode(0xf068)
  readonly property string dotGlyph: String.fromCharCode(0xb7)

  // Wheel-step accumulator for the countdown's duration scroll.
  // Model.wheelSteps banks the sub-notch remainder so a touchpad flick can't
  // dump 20 minutes at once. Kept in Model rather than borrowed from a shell
  // singleton: it is a dozen lines of arithmetic, it is covered by
  // Model.test.js, and it cannot break when the host shell moves a helper.
  property real wheelAccumulator: 0

  // Rolls the TODAY/YESTERDAY group labels over at midnight without needing
  // the panel closed and reopened -- same fix clock/Panel.qml uses for its
  // date highlight. Minutes precision is plenty; the labels only care that
  // the day changed.
  SystemClock {
    id: clock
    precision: SystemClock.Minutes
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(320))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onActivateRequested: if (root.timer) root.timer.toggleRunning()
      onTabRequested: function (direction) { root.switchPanel(direction) }
      // PanelKeyCatcher turns Up/Down/j/k into moveRequested and nothing else
      // consumes them; without this the keys are dead. dx is unused -- this
      // panel has no horizontal cursor. Step is one text row's worth, same
      // token agents/Panel.qml uses.
      onMoveRequested: function (dx, dy) {
        if (dy === 0) return
        panelFlick.contentY = Math.max(0, Math.min(panelFlick.contentY + dy * Style.space(56),
                                                   Math.max(0, panelFlick.contentHeight - panelFlick.height)))
      }

      // One outer Flickable over the whole column, the shape every
      // first-party panel uses: the card is capped at Style.space(560)
      // above, so anything past that -- long history, small screen --
      // has to scroll. Two wheel zones, not one: over the countdown an
      // idle vertical wheel adjusts the duration (the WheelHandler below
      // claims it); anywhere else, and over the countdown once a session
      // is under way, the wheel reaches this Flickable and scrolls.
      //
      // Flickable + Column, not ListView: ListView.contentHeight derives
      // from the delegates it instantiates, and it instantiates delegates
      // to fill its own height -- self-referential. Qt won't flag it as a
      // binding loop, it just settles wrong. Column.implicitHeight is
      // content-derived and independent of the viewport. Model.HISTORY_CAP
      // rows need no virtualization.
      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(14)

          // ---- countdown, dimmed when paused; +/- adjust the duration ----
          // Wrapped in an Item, not bare in the Column, same reason as the
          // transport row below: a Row anchored to horizontalCenter feeds back
          // into Column.implicitWidth.
          Item {
            width: parent.width
            height: countdownRow.height

            Row {
              id: countdownRow
              anchors.horizontalCenter: parent.horizontalCenter
              spacing: Style.space(18)

              // Row positions x only, so vertical anchors are free -- and
              // needed: a Row top-aligns its children, which left the buttons
              // riding high against the taller countdown Text.
              PanelActionButton {
                anchors.verticalCenter: parent.verticalCenter
                iconText: root.minusGlyph
                tooltipText: "5 minutes less"
                foreground: root.contentForeground
                fontSize: root.adjustGlyphSize
                size: root.adjustHitSize
                fontFamily: root.contentFontFamily
                enabled: !!root.timer && root.timer.canAdjust(-5)
                onClicked: if (root.timer) root.timer.adjustMinutes(-5)
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.timer ? Model.mmss(root.timer.remainingSeconds) : "00:00"
                color: root.contentForeground
                opacity: root.timer && root.timer.paused ? 0.6 : 1.0
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.display
                font.bold: true
              }

              PanelActionButton {
                anchors.verticalCenter: parent.verticalCenter
                iconText: root.plusGlyph
                tooltipText: "5 minutes more"
                foreground: root.contentForeground
                fontSize: root.adjustGlyphSize
                size: root.adjustHitSize
                fontFamily: root.contentFontFamily
                enabled: !!root.timer && root.timer.canAdjust(5)
                onClicked: if (root.timer) root.timer.adjustMinutes(5)
              }
            }

            // angleDelta.y === 0 guard: a horizontal/touchpad side-scroll
            // reports only x, and must neither bank a step nor be swallowed.
            //
            // Deliberately idle-only. adjustMinutes() would be safe while a
            // session runs -- it carries its own guard -- but a scroll is easy
            // to trigger by accident on a touchpad, and silently reshaping a
            // live countdown is worse than requiring a button press. The
            // accumulator resets with `enabled` so a banked remainder can't
            // survive a session and fire an early step later.
            WheelHandler {
              enabled: !!root.timer && root.timer.idle
              onEnabledChanged: root.wheelAccumulator = 0
              // QQuickWheelEvent.accepted defaults to TRUE, so a bare
              // `return` still swallows the event. Every path below therefore
              // sets acceptance explicitly rather than leaning on the default.
              onWheel: function (event) {
                // Not ours: hand the side-scroll back untouched.
                if (event.angleDelta.y === 0) {
                  event.accepted = false
                  return
                }
                // Ours from here, including the wheel.steps === 0 banking path:
                // the outer Flickable sits under this handler, so anything left
                // unaccepted falls through and a slow touchpad scroll that only
                // banks a remainder would scroll the panel instead of adjusting.
                event.accepted = true
                var wheel = Model.wheelSteps(root.wheelAccumulator, event.angleDelta.y)
                root.wheelAccumulator = wheel.remainder
                if (wheel.steps === 0) return
                if (root.timer) root.timer.adjustMinutes(wheel.steps * 5)
              }
            }
          }

          // ---- play/pause + reset ---------------------------------------
          // Wrapped in an Item, not bare in the Column: a Row anchored to
          // horizontalCenter feeds back into Column.implicitWidth. Harmless
          // here since the Column takes its width from the Flickable, but
          // qmllint flags it, and clock/Panel.qml's hero row avoids it the
          // same way.
          Item {
            width: parent.width
            height: controlsRow.height

            Row {
              id: controlsRow
              anchors.horizontalCenter: parent.horizontalCenter
              spacing: Style.space(18)

              PanelActionButton {
                iconText: root.timer && root.timer.running ? root.pauseGlyph : root.playGlyph
                tooltipText: root.timer && root.timer.running ? "Pause" : "Start"
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                fontSize: root.controlGlyphSize
                size: root.controlHitSize
                onClicked: if (root.timer) root.timer.toggleRunning()
              }

              PanelActionButton {
                iconText: root.resetGlyph
                tooltipText: "Reset"
                foreground: root.contentForeground
                hoverColor: root.bar ? root.bar.urgent : root.contentForeground
                fontFamily: root.contentFontFamily
                fontSize: root.controlGlyphSize
                size: root.controlHitSize
                enabled: !!root.timer && root.timer.started
                onClicked: if (root.timer) root.timer.reset()
              }
            }
          }

          PanelSeparator {
            foreground: root.contentForeground
          }

          // ---- history ----------------------------------------------------

          Text {
            visible: root.historyCount === 0
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: "No sessions yet."
            color: Qt.darker(root.contentForeground, 1.4)
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.body
          }

          // history arrives newest-first (Model.pushSession unshifts), so no
          // re-sort needed.
          Column {
            id: historyRows
            visible: root.historyCount > 0
            width: parent.width
            spacing: Style.space(12)

            Repeater {
              model: root.timer ? Model.groupByDay(root.timer.history, clock.date.getTime()) : []

              delegate: Column {
                id: dayGroup
                required property var modelData
                width: historyRows.width
                spacing: Style.space(6)

                PanelSectionHeader {
                  text: dayGroup.modelData.label + " " + root.dotGlyph + " " + dayGroup.modelData.count
                  foreground: root.contentForeground
                  fontFamily: root.contentFontFamily
                }

                Repeater {
                  model: dayGroup.modelData.sessions

                  delegate: Text {
                    required property var modelData
                    width: dayGroup.width
                    text: Qt.formatDateTime(new Date(modelData.startedAt), "HH:mm") + " " + root.dotGlyph + " " + modelData.minutes + " min"
                    color: root.contentForeground
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.body
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
