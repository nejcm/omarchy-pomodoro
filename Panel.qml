import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Pomodoro control panel: countdown + play/pause/reset + session history.
// BarWidget.qml (already built) owns all timer state and persistence; this
// panel is loaded into it via Loader and never copies state in. Everything
// timer-related is read live off `hostWidget` (hostWidget.remainingSeconds,
// .running, .started, .paused, .history) and driven via hostWidget's own
// start()/pause()/reset()/toggleRunning() -- injectPanel only re-fires on
// bar/settings changes, not every tick, so a local copy would go stale.
Panel {
  id: root
  moduleName: "io.github.nejcm.pomodoro"

  // Injected by BarWidget.qml's injectPanel() on bar/settings changes.
  property var anchorItem: null
  property var hostWidget: null

  // Bar.findPanelWidget / switchPanelFrom key off the bar-widget root
  // (BarWidget.qml's `root`), not this nested panel -- plan risk 4. Same
  // fix the clock plugin uses: route switchPanel through barIdentity
  // instead of the base Panel's own `switchPanel`, which would pass this
  // nested panel as the owner.
  readonly property var barIdentity: hostWidget || root

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  // Guarded so the panel renders before the bar is injected, same pattern
  // as shell/plugins/panels/clock/Panel.qml.
  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family

  // ---- glyphs, plan risk 3 ---------------------------------------------
  // Classic Font Awesome block (codepoints U+F0xx through U+F2xx) -- the
  // same range BarWidget.qml's tomato glyph and this omarchy tree's own
  // Tray.qml (pin/hide) and SystemUpdate.qml (refresh) glyphs use,
  // confirmed intact in Nerd Fonts v3 unlike the deleted legacy MDI range
  // (0xF500-0xFD46). fa-play (0xF04B), fa-pause (0xF04C) and fa-undo
  // (0xF0E2) are fixed Font Awesome 4 codepoints from that same spec,
  // unrelated to Nerd Fonts' 5-hex MDI churn. Built with
  // String.fromCharCode from a plain hex literal rather than a source
  // escape or a pasted character, so the codepoint is unambiguous and the
  // file stays pure ASCII -- the earlier hazard in this plan was a raw
  // Private-Use-Area byte landing in the file invisibly.
  readonly property string playGlyph: String.fromCharCode(0xf04b)
  readonly property string pauseGlyph: String.fromCharCode(0xf04c)
  readonly property string resetGlyph: String.fromCharCode(0xf0e2)

  // Rolls TODAY's count over at midnight without needing the panel closed
  // and reopened -- same fix clock/Panel.qml uses for its date highlight.
  // Minutes precision is plenty; the count only cares that the day changed.
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

        // ---- countdown, dimmed when paused --------------------------
        Text {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          text: root.hostWidget ? Model.mmss(root.hostWidget.remainingSeconds) : "00:00"
          color: root.contentForeground
          opacity: root.hostWidget && root.hostWidget.paused ? 0.6 : 1.0
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.display
          font.bold: true
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
              onClicked: if (root.hostWidget) root.hostWidget.toggleRunning()
            }

            PanelActionButton {
              iconText: root.resetGlyph
              tooltipText: "Reset"
              foreground: root.contentForeground
              hoverColor: root.bar ? root.bar.urgent : root.contentForeground
              fontFamily: root.contentFontFamily
              enabled: !!root.hostWidget && root.hostWidget.started
              onClicked: if (root.hostWidget) root.hostWidget.reset()
            }
          }
        }

        PanelSeparator {
          foreground: root.contentForeground
        }

        // ---- history ----------------------------------------------------
        PanelSectionHeader {
          text: "TODAY " + String.fromCharCode(0xb7) + " " + (root.hostWidget ? Model.countToday(root.hostWidget.history, clock.date.getTime()) : 0)
          foreground: root.contentForeground
          fontFamily: root.contentFontFamily
        }

        Text {
          visible: !root.hostWidget || root.hostWidget.history.length === 0
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          text: "No sessions yet."
          color: Qt.darker(root.contentForeground, 1.4)
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.body
        }

        // Capped so 50 rows scroll instead of growing the panel
        // off-screen. history is already newest-first (Model.pushSession
        // unshifts), so no re-sort needed.
        //
        // Flickable + Column, not ListView: ListView.contentHeight derives
        // from the delegates it instantiates, and it instantiates delegates
        // to fill its own height -- self-referential. Qt won't flag it as a
        // binding loop, it just settles wrong (a sliver, or growing a row a
        // frame). Column.implicitHeight is content-derived and independent
        // of the viewport, so the cap works. 50 rows needs no
        // virtualization. Matches clock/Panel.qml's calendarScroll.
        Flickable {
          visible: !!root.hostWidget && root.hostWidget.history.length > 0
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
            spacing: Style.space(6)

            Repeater {
              model: root.hostWidget ? root.hostWidget.history : []

              delegate: Text {
                required property var modelData
                width: historyRows.width
                text: Qt.formatDateTime(new Date(modelData.startedAt), "HH:mm") + " " + String.fromCharCode(0xb7) + " " + modelData.minutes + " min"
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
