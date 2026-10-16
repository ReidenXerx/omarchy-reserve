import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami

// The panel: the battery the way a phone shows it. The day's level, where the charge went, the few things worth
// knowing, and how healthy the battery is. The same panel as the Omarchy edition, in Plasma's controls and colours.
PlasmaExtras.Representation {
  id: view

  required property var reserve

  Layout.preferredWidth: Kirigami.Units.gridUnit * 24
  Layout.preferredHeight: Kirigami.Units.gridUnit * 34
  Layout.minimumWidth: Kirigami.Units.gridUnit * 18
  Layout.minimumHeight: Kirigami.Units.gridUnit * 14

  readonly property var r: view.reserve.report
  readonly property color ink: Kirigami.Theme.textColor
  readonly property color faint: Qt.rgba(ink.r, ink.g, ink.b, 0.65)
  readonly property color hairline: Qt.rgba(ink.r, ink.g, ink.b, 0.12)
  readonly property color accent: Kirigami.Theme.highlightColor
  // Sizes taken from a Plasma label: in a widget's popup Kirigami.Theme.smallFont answers differently at the root
  // and in delegates (Plasma 6.8).
  readonly property real basePt: sizer.font.pointSize
  readonly property real smallPt: Math.max(7, Math.round(view.basePt * 0.9))
  readonly property real titlePt: Math.round(view.basePt * 1.5)
  PlasmaComponents.Label { id: sizer; visible: false }

  function clock(t) {
    var d = new Date(t * 1000)
    return (d.getHours() < 10 ? "0" : "") + d.getHours() + ":" + (d.getMinutes() < 10 ? "0" : "") + d.getMinutes()
  }

  readonly property string status: {
    var res = view.reserve
    if (!res.present) return "No battery found"
    var cur = view.r ? view.r.current : null
    if (res.unplugged) {
      var left = view.r && view.r.timeLeft ? view.r.timeLeft : null
      if (left) return "About " + res.spell(left.hours * 3600) + " left at " + (left.rateMw / 1000).toFixed(1) + " W"
      if (res.timeToEmpty > 0) return "About " + res.spell(res.timeToEmpty) + " left"
      return "On battery"
    }
    if (res.charging) return "Charging" + (cur && cur.st === "C" && cur.mw ? " at " + (Math.abs(cur.mw) / 1000).toFixed(0) + " W" : "")
    if (res.state === "NoCharge" || (cur && cur.st === "N")) return "Plugged in, held at the charge limit"
    return "Plugged in"
  }

  component Heading: PlasmaComponents.Label {
    textFormat: Text.PlainText
    color: view.faint
    font.capitalization: Font.AllUppercase
    font.letterSpacing: 1
    font.pointSize: view.smallPt
    Layout.topMargin: Kirigami.Units.smallSpacing
  }

  component Note: PlasmaComponents.Label {
    Layout.fillWidth: true
    textFormat: Text.PlainText
    wrapMode: Text.Wrap
    color: view.faint
    font.pointSize: view.smallPt
  }

  component Tile: ColumnLayout {
    id: tile
    property string label: ""
    property string value: ""
    property string note: ""
    spacing: 0
    Layout.fillWidth: true
    Layout.preferredWidth: 1
    PlasmaComponents.Label {
      textFormat: Text.PlainText
      text: tile.label
      color: view.faint
      font.capitalization: Font.AllUppercase
      font.letterSpacing: 1
      font.pointSize: view.smallPt
    }
    PlasmaComponents.Label {
      textFormat: Text.PlainText
      text: tile.value
      font.pointSize: view.titlePt
      font.bold: true
    }
    PlasmaComponents.Label {
      Layout.fillWidth: true
      visible: tile.note !== ""
      textFormat: Text.PlainText
      wrapMode: Text.Wrap
      text: tile.note
      color: view.faint
      font.pointSize: view.smallPt
    }
  }

  header: PlasmaExtras.PlasmoidHeading {
    RowLayout {
      anchors.fill: parent
      spacing: Kirigami.Units.largeSpacing
      PlasmaComponents.Label {
        textFormat: Text.PlainText
        text: view.reserve.present ? view.reserve.percent + "%" : "—"
        font.pointSize: Math.round(view.basePt * 2.2)
        font.bold: true
      }
      ColumnLayout {
        Layout.fillWidth: true
        spacing: 0
        PlasmaComponents.Label {
          textFormat: Text.PlainText
          text: "Reserve"
          color: view.faint
          font.capitalization: Font.AllUppercase
          font.letterSpacing: 1
          font.pointSize: view.smallPt
        }
        PlasmaComponents.Label {
          Layout.fillWidth: true
          textFormat: Text.PlainText
          wrapMode: Text.Wrap
          text: view.status
        }
      }
    }
  }

  PlasmaComponents.ScrollView {
    id: scroller
    anchors.fill: parent
    QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AlwaysOff
    contentWidth: availableWidth

    ColumnLayout {
      id: content
      width: scroller.availableWidth
      spacing: Kirigami.Units.largeSpacing

      // ------------------------------------------------ the last 24 hours
      Canvas {
        id: chart
        Layout.fillWidth: true
        Layout.topMargin: Kirigami.Units.smallSpacing
        Layout.preferredHeight: Kirigami.Units.gridUnit * 7
        readonly property var chartData: view.r
        readonly property color ink: view.ink
        readonly property color line: view.accent
        onChartDataChanged: requestPaint()
        onWidthChanged: requestPaint()
        onInkChanged: requestPaint()
        onLineChanged: requestPaint()

        onPaint: {
          var c = getContext("2d")
          c.reset()
          var d = chart.chartData
          var caption = Math.round(view.smallPt * 4 / 3)
          var left = caption * 2 + 4, bottom = caption + 6
          var w = width - left, h = height - bottom
          c.font = caption + "px sans-serif"
          c.fillStyle = Qt.rgba(chart.ink.r, chart.ink.g, chart.ink.b, 0.6)
          c.strokeStyle = Qt.rgba(chart.ink.r, chart.ink.g, chart.ink.b, 0.12)
          c.lineWidth = 1
          c.textAlign = "right"; c.textBaseline = "middle"
          var levels = [100, 50, 0]
          for (var i = 0; i < levels.length; i++) {
            var y = h - levels[i] / 100 * h
            c.beginPath(); c.moveTo(left, y + 0.5); c.lineTo(width, y + 0.5); c.stroke()
            c.fillText(String(levels[i]), left - 4, Math.max(caption / 2, Math.min(h - 2, y)))
          }
          if (!d || !d.level || d.level.length === 0) return
          var t0 = d.chartStart, t1 = d.now
          function X(t) { return left + (t - t0) / (t1 - t0) * w }
          function Y(p) { return h - p / 100 * h }

          // Charging and sleep as bands behind the line.
          var bands = [["charging", 0.18, chart.line], ["sleeping", 0.10, chart.ink]]
          for (var b = 0; b < bands.length; b++) {
            var list = d.spans[bands[b][0]] || []
            var col = bands[b][2]
            c.fillStyle = Qt.rgba(col.r, col.g, col.b, bands[b][1])
            for (var k = 0; k < list.length; k++) {
              var a = X(Math.max(t0, list[k][0])), e = X(Math.min(t1, list[k][1]))
              if (e > a) c.fillRect(a, 0, e - a, h)
            }
          }

          // The level, with a soft fill, broken where the computer slept.
          var pts = d.level
          c.lineWidth = 2
          c.lineJoin = "round"
          c.strokeStyle = chart.line
          var run = []
          function flush() {
            if (run.length < 1) return
            c.beginPath()
            c.moveTo(X(run[0][0]), Y(run[0][1]))
            for (var q = 1; q < run.length; q++) c.lineTo(X(run[q][0]), Y(run[q][1]))
            c.stroke()
            c.lineTo(X(run[run.length - 1][0]), h); c.lineTo(X(run[0][0]), h); c.closePath()
            c.fillStyle = Qt.rgba(chart.line.r, chart.line.g, chart.line.b, 0.14)
            c.fill()
            run = []
          }
          for (var p = 0; p < pts.length; p++) {
            if (pts[p][1] === null) flush(); else run.push(pts[p])
          }
          flush()
          var last = pts[pts.length - 1]
          if (last[1] !== null) {
            c.fillStyle = chart.line
            c.beginPath(); c.arc(X(last[0]), Y(last[1]), 3.5, 0, Math.PI * 2); c.fill()
          }

          // Times along the bottom.
          c.fillStyle = Qt.rgba(chart.ink.r, chart.ink.g, chart.ink.b, 0.6)
          c.textBaseline = "alphabetic"
          var marks = [[t0, "left"], [t0 + (t1 - t0) / 2, "center"], [t1, "right"]]
          for (var m = 0; m < marks.length; m++) {
            c.textAlign = marks[m][1]
            c.fillText(m === 2 ? "now" : view.clock(marks[m][0]), X(marks[m][0]), height - 2)
          }
        }
      }

      RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.largeSpacing
        Repeater {
          model: [["Charging", view.accent, 0.35], ["Asleep", view.ink, 0.25]]
          delegate: RowLayout {
            required property var modelData
            spacing: Kirigami.Units.smallSpacing
            Rectangle {
              implicitWidth: Kirigami.Units.smallSpacing * 2.5; implicitHeight: implicitWidth; radius: 2
              color: Qt.rgba(modelData[1].r, modelData[1].g, modelData[1].b, modelData[2])
            }
            PlasmaComponents.Label {
              textFormat: Text.PlainText
              text: modelData[0]
              color: view.faint
              font.pointSize: view.smallPt
            }
          }
        }
      }

      Kirigami.Separator { Layout.fillWidth: true }

      // ------------------------------------------------ where it went
      RowLayout {
        Layout.fillWidth: true
        Heading { Layout.fillWidth: true; text: "Battery use" }
        PlasmaComponents.ToolButton {
          text: "Since unplugged"
          checkable: true
          checked: view.reserve.since !== "today"
          onClicked: view.reserve.setSince("unplug")
        }
        PlasmaComponents.ToolButton {
          text: "Today"
          checkable: true
          checked: view.reserve.since === "today"
          onClicked: view.reserve.setSince("today")
        }
      }

      Note {
        text: {
          if (!view.r) return "Reading the history…"
          var u = view.r.usage
          if (!u || u.totalMwh <= 0) return view.r.sinceLabel + ": nothing used on battery yet. Usage by app appears after the first ten minutes unplugged."
          return view.r.sinceLabel + ": " + (u.totalMwh / 1000).toFixed(1) + " Wh used. Shares are estimates from each app's CPU and GPU time."
        }
      }

      Repeater {
        model: {
          var u = view.r ? view.r.usage : null
          if (!u || u.totalMwh <= 0) return []
          var rows = u.apps.slice(0, 6).map(function (a) {
            var minutes = Math.round(a.cpuMs / 60000)
            return { name: a.name, share: a.share, detail: (minutes > 0 ? minutes + " min" : "under a minute") + " of CPU" }
          })
          rows.push({ name: "Screen and system", share: u.baseShare, detail: "what the idle computer uses" })
          return rows.sort(function (a, b) { return b.share - a.share })
        }
        delegate: RowLayout {
          required property var modelData
          Layout.fillWidth: true
          spacing: Kirigami.Units.largeSpacing
          // A fixed column for the name, so the bar beside it gets the rest of the row.
          ColumnLayout {
            Layout.preferredWidth: Kirigami.Units.gridUnit * 8
            Layout.maximumWidth: Kirigami.Units.gridUnit * 8
            spacing: 0
            PlasmaComponents.Label {
              Layout.fillWidth: true
              textFormat: Text.PlainText
              elide: Text.ElideRight
              text: modelData.name
            }
            PlasmaComponents.Label {
              Layout.fillWidth: true
              textFormat: Text.PlainText
              elide: Text.ElideRight
              text: modelData.detail
              color: view.faint
              font.pointSize: view.smallPt
            }
          }
          Item {
            Layout.fillWidth: true
            Layout.preferredHeight: Kirigami.Units.smallSpacing * 2
            Rectangle { anchors.fill: parent; radius: height / 2; color: view.hairline }
            Rectangle {
              width: parent.width * Math.max(0.02, Math.min(1, modelData.share / 100))
              height: parent.height
              radius: height / 2
              color: view.accent
            }
          }
          PlasmaComponents.Label {
            textFormat: Text.PlainText
            Layout.preferredWidth: Kirigami.Units.gridUnit * 2.5
            horizontalAlignment: Text.AlignRight
            text: Math.round(modelData.share) + "%"
          }
        }
      }

      // ------------------------------------------------ worth knowing
      Repeater {
        model: view.r ? view.r.insights : []
        delegate: RowLayout {
          required property var modelData
          Layout.fillWidth: true
          spacing: Kirigami.Units.smallSpacing * 2
          Rectangle {
            Layout.alignment: Qt.AlignTop
            Layout.topMargin: Kirigami.Units.smallSpacing * 1.5
            implicitWidth: Kirigami.Units.smallSpacing * 1.5; implicitHeight: implicitWidth; radius: implicitWidth / 2
            color: Kirigami.Theme.neutralTextColor
          }
          PlasmaComponents.Label {
            Layout.fillWidth: true
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            text: modelData.text
          }
        }
      }

      Kirigami.Separator { Layout.fillWidth: true }

      // ------------------------------------------------ the battery itself
      Heading { text: "Health" }

      RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.largeSpacing
        Tile {
          label: "Capacity"
          value: view.r && view.r.health.capacity !== null ? view.r.health.capacity.toFixed(0) + "%" : "—"
          note: "of design"
        }
        Tile {
          label: "Cycles"
          value: view.r && view.r.health.cycles !== null ? String(view.r.health.cycles) : "—"
          note: view.r && view.r.health.year ? "since " + view.r.health.year : ""
        }
        Tile {
          label: "Temperature"
          value: view.r && view.r.health.temperature !== null ? view.r.health.temperature.toFixed(0) + " °C" : "—"
          note: view.r ? view.r.health.health : ""
        }
        Tile {
          visible: view.r !== null && view.r.charger !== null
          label: "Charger"
          value: view.r && view.r.charger ? view.r.charger.watts + " W" : ""
          note: "USB-C"
        }
      }

      Note {
        visible: text !== ""
        text: view.r && view.r.charger ? view.r.charger.note : ""
      }

      Note {
        text: {
          var t = view.r ? view.r.trend : []
          if (!t || t.length < 2) return "A capacity trend appears here after a few days."
          var first = t[0], last = t[t.length - 1]
          var change = last[1] - first[1]
          return "Capacity " + (change >= 0 ? "held at " : "went from " + first[1].toFixed(1) + "% to ") + last[1].toFixed(1) + "% since " + first[0] + "."
        }
      }

      Note { text: "Charge limits and power profiles are in Plasma's Power and Battery widget." }

      Note {
        visible: view.reserve.trouble !== ""
        text: view.reserve.trouble
        color: Kirigami.Theme.negativeTextColor
      }
    }
  }
}
