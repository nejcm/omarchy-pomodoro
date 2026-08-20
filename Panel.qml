// The history Repeater's delegate reads ids from this file's outer scope
// (root, historyRows). Under the default Unbound behavior that access is
// unqualified -- it happens to resolve, but qmllint flags it and the lookup
// isn't guaranteed. Bound captures the enclosing scope properly; it also
// requires delegate model properties to be declared `required`, which the
// delegate below already does.
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Pomodoro control panel: countdown + play/pause/reset + session history.
// BarWidget.qml owns all timer state and persistence. This panel never copies
// that state in -- it reads live off `hostWidget` and drives it through
// hostWidget's own start()/pause()/reset()/toggleRunning(), because
// injectPanel re-fires only on bar/settings changes, not every tick, so any
// local copy would go stale within a second.
Panel {
  id: root
  moduleName: "io.github.nejcm.pomodoro"

  // Injected by BarWidget.qml's injectPanel() on bar/settings changes.
  property var anchorItem: null
  property var hostWidget: null

  // Bar.findPanelWidget / switchPanelFrom key off the bar-widget root
  // (BarWidget.qml's `root`), not this nested panel. So route switchPanel
  // through barIdentity rather than the base Panel's own switchPanel, which
  // would pass this nested panel as the owner. Same fix the clock plugin uses.
  readonly property var barIdentity: hostWidget || root

  // hostWidget is injected in Loader.onLoaded, which fires after these
  // bindings first evaluate -- hence the null guard. Hoisted here so the
  // history views below read as plain state instead of each repeating the
  // guard, and so the empty/non-empty pair below is visibly one predicate
  // and its negation.
  readonly property int historyCount: hostWidget ? hostWidget.history.length : 0

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
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onActivateRequested: if (root.hostWidget) root.hostWidget.toggleRunning()
      onTabRequested: function (direction) { root.switchPanel(direction) }

      Column {
        id: column
        anchors.fill: parent
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
              enabled: !!root.hostWidget && root.hostWidget.canAdjust(-5)
              onClicked: if (root.hostWidget) root.hostWidget.adjustMinutes(-5)
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: root.hostWidget ? Model.mmss(root.hostWidget.remainingSeconds) : "00:00"
              color: root.contentForeground
              opacity: root.hostWidget && root.hostWidget.paused ? 0.6 : 1.0
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
              enabled: !!root.hostWidget && root.hostWidget.canAdjust(5)
              onClicked: if (root.hostWidget) root.hostWidget.adjustMinutes(5)
            }
          }

          // angleDelta.y === 0 guard: a horizontal/touchpad side-scroll
          // reports only x, and must not bank a step.
          //
          // Deliberately idle-only. adjustMinutes() would be safe while a
          // session runs -- it carries its own guard -- but a scroll is easy
          // to trigger by accident on a touchpad, and silently reshaping a
          // live countdown is worse than requiring a button press. The
          // accumulator resets with `enabled` so a banked remainder can't
          // survive a session and fire an early step later.
          WheelHandler {
            enabled: !!root.hostWidget && root.hostWidget.idle
            onEnabledChanged: root.wheelAccumulator = 0
            onWheel: function (event) {
              if (event.angleDelta.y === 0) return
              var wheel = Model.wheelSteps(root.wheelAccumulator, event.angleDelta.y)
              root.wheelAccumulator = wheel.remainder
              if (wheel.steps === 0) return
              if (root.hostWidget) root.hostWidget.adjustMinutes(wheel.steps * 5)
            }
          }
        }

        // ---- play/pause + reset ---------------------------------------
        // Wrapped in an Item, not bare in the Column: a Row anchored to
        // horizontalCenter feeds back into Column.implicitWidth. Harmless
        // here since the Column anchors.fill's, but qmllint flags it, and
        // clock/Panel.qml's hero row avoids it the same way.
        Item {
          width: parent.width
          height: controlsRow.height

          Row {
            id: controlsRow
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Style.space(18)

            PanelActionButton {
              iconText: root.hostWidget && root.hostWidget.running ? root.pauseGlyph : root.playGlyph
              tooltipText: root.hostWidget && root.hostWidget.running ? "Pause" : "Start"
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              fontSize: root.controlGlyphSize
              size: root.controlHitSize
              onClicked: if (root.hostWidget) root.hostWidget.toggleRunning()
            }

            PanelActionButton {
              iconText: root.resetGlyph
              tooltipText: "Reset"
              foreground: root.contentForeground
              hoverColor: root.bar ? root.bar.urgent : root.contentForeground
              fontFamily: root.contentFontFamily
              fontSize: root.controlGlyphSize
              size: root.controlHitSize
              enabled: !!root.hostWidget && root.hostWidget.started
              onClicked: if (root.hostWidget) root.hostWidget.reset()
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

        // Height-capped so the rows scroll instead of growing the panel
        // off-screen. history arrives newest-first (Model.pushSession
        // unshifts), so no re-sort needed.
        //
        // Flickable + Column, not ListView: ListView.contentHeight derives
        // from the delegates it instantiates, and it instantiates delegates
        // to fill its own height -- self-referential. Qt won't flag it as a
        // binding loop, it just settles wrong (a sliver, or growing a row a
        // frame). Column.implicitHeight is content-derived and independent
        // of the viewport, so the cap works. Model.HISTORY_CAP rows need no
        // virtualization. Matches clock/Panel.qml's calendarScroll.
        Flickable {
          visible: root.historyCount > 0
          width: parent.width
          height: Math.min(historyRows.implicitHeight, Style.space(220))
          contentWidth: width
          contentHeight: historyRows.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          interactive: contentHeight > height

          Column {
            id: historyRows
            width: parent.width
            spacing: Style.space(12)

            Repeater {
              model: root.hostWidget ? Model.groupByDay(root.hostWidget.history, clock.date.getTime()) : []

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
