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
// Service.qml owns all timer state and the session-history file (the one
// other write, saving an idle duration nudge back to the widget's shell.json
// entry, is BarWidget.qml's). This panel never copies
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

  // Duration scrolling is idle-only. adjustMinutes() carries its own guard,
  // but a touchpad brush is easy to trigger by accident and silently
  // reshaping a live countdown is worse than requiring a button press. The
  // accumulator clears on the transition so a remainder banked while idle
  // cannot survive a session and fire an early step afterwards.
  readonly property bool wheelAdjusts: !!timer && timer.idle
  onWheelAdjustsChanged: wheelAccumulator = 0

  // Clamped scroll of the content Flickable, in text-row steps. Two callers:
  // the keyboard cursor, and the wheel shields on the button rows. The
  // shields cannot simply decline an event they do not want -- the button
  // MouseAreas they sit in front of would eat it before the Flickable ever
  // saw it -- so they move it here instead.
  function scrollPanelRows(rows) {
    var max = Math.max(0, panelFlick.contentHeight - panelFlick.height)
    panelFlick.contentY = Math.max(0, Math.min(panelFlick.contentY + rows * Style.space(56), max))
  }

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
        root.scrollPanelRows(dy)
      }

      // One outer Flickable over the whole column, the shape every
      // first-party panel uses: the card is capped at Style.space(560)
      // above, so anything past that -- long history, small screen --
      // has to scroll. It gets the wheel directly over the history and any
      // empty space. It does *not* over the two button rows: the buttons
      // swallow the wheel before it can travel this far, so each row carries
      // a shield that reads the notch itself and either adjusts the duration
      // or calls scrollPanelRows() -- see the countdown shield for why
      // declining is not an option there.
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

            // Wheel shield.
            //
            // PanelActionButton's own MouseArea (Ui/PanelActionButton.qml:81-92)
            // declares no onWheel, and a MouseArea without one still consumes
            // the wheel -- which is precisely why Ui/WidgetButton.qml:116 has
            // to forward it by hand. Those MouseAreas are descendants of this
            // wrapper, so they are hit before any handler on the wrapper
            // itself: resting the pointer on +/-, the natural place to aim
            // before nudging, killed the notch outright. It read as random
            // rather than broken, because a disabled MouseArea drops out of
            // the hit test -- at 180 the greyed-out + let the wheel through
            // while - still ate it.
            //
            // A later sibling of countdownRow is hit first, so the event lands
            // here instead, across the whole row. This Item carries no
            // MouseArea and no hover handler, so clicks, tooltips and the
            // disabled states still belong to the buttons underneath.
            Item {
              anchors.fill: parent

              WheelHandler {
                // QQuickWheelEvent.accepted defaults to TRUE, so a bare
                // `return` still swallows the event. Every path below sets
                // acceptance explicitly rather than leaning on the default.
                onWheel: function (event) {
                  // Belt and braces, and kept deliberately. WheelHandler
                  // filters by `orientation`, which defaults to Qt.Vertical,
                  // so a pure side-scroll should never reach this function at
                  // all -- but that is a default this file neither sets nor
                  // controls, and the guard is two lines. Declining is the
                  // honest answer to an event that is not ours; it is not a
                  // route to the Flickable, which sits behind the button
                  // MouseAreas and would not see the notch either way.
                  if (event.angleDelta.y === 0) {
                    event.accepted = false
                    return
                  }
                  event.accepted = true

                  // Direction-checked, not just idle-checked: at a clamp the
                  // notch cannot move the duration, and eating it there left
                  // the panel unscrollable for as long as the pointer sat on
                  // the countdown. Scroll rather than swallow.
                  var direction = event.angleDelta.y > 0 ? 5 : -5
                  if (root.wheelAdjusts && root.timer.canAdjust(direction)) {
                    // steps === 0 means the notch banked a sub-notch
                    // remainder -- real work, so it keeps the event instead of
                    // also scrolling the panel.
                    var wheel = Model.wheelSteps(root.wheelAccumulator, event.angleDelta.y)
                    root.wheelAccumulator = wheel.remainder
                    if (wheel.steps !== 0) root.timer.adjustMinutes(wheel.steps * 5)
                    return
                  }

                  // Not adjusting: a partial notch banked for an adjustment
                  // that is no longer happening would fire late.
                  root.wheelAccumulator = 0
                  root.scrollPanelRows(-event.angleDelta.y / 120)
                }
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

            // The same shield, with the simpler intent: nothing on this row
            // reads the wheel, so every notch is panel scroll. It still has to
            // be a shield rather than nothing at all -- the play/pause and
            // reset MouseAreas swallow the wheel exactly like the +/- ones, so
            // without this the panel sits still under the pointer.
            Item {
              anchors.fill: parent

              WheelHandler {
                onWheel: function (event) {
                  // Same not-ours guard as the countdown shield, same caveat.
                  if (event.angleDelta.y === 0) {
                    event.accepted = false
                    return
                  }
                  event.accepted = true
                  root.scrollPanelRows(-event.angleDelta.y / 120)
                }
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
