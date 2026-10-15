import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Reserve's panel: the battery the way a phone shows it. The day's level, where the charge went, the few things
// worth knowing, and how healthy the battery is. Held by the shell as an overlay, so it outlives the bar widget.
Item {
  id: overlay

  property var shell: null
  property var manifest: null
  property var reserve: null
  property bool opened: false

  readonly property string pluginId: "reidenxerx.reserve"

  function findService() {
    if (!overlay.reserve && overlay.shell && typeof overlay.shell.serviceFor === "function")
      overlay.reserve = overlay.shell.serviceFor(overlay.pluginId)
  }

  Timer {
    interval: 1000
    repeat: true
    running: !overlay.reserve
    triggeredOnStart: true
    onTriggered: overlay.findService()
  }

  readonly property string powerPlugin: overlay.reserve ? overlay.reserve.powerPlugin : ""

  function open(payloadJson) {
    overlay.findService()
    overlay.opened = true
    if (overlay.reserve) {
      overlay.reserve.panelOpen = true
      overlay.reserve.refresh()
    }
  }

  function close() {
    if (!overlay.opened) return
    overlay.opened = false
    if (overlay.reserve) overlay.reserve.panelOpen = false
  }

  function dismiss() {
    overlay.close()
    if (overlay.shell && typeof overlay.shell.hide === "function") overlay.shell.hide(overlay.pluginId)
  }

  function toggle() {
    if (overlay.opened) overlay.dismiss()
    else overlay.open("{}")
  }

  readonly property var r: overlay.reserve ? overlay.reserve.report : null
  readonly property color ink: Commons.Color.popups.text
  readonly property color faint: Qt.rgba(overlay.ink.r, overlay.ink.g, overlay.ink.b, 0.6)
  readonly property color hairline: Qt.rgba(overlay.ink.r, overlay.ink.g, overlay.ink.b, 0.12)
  readonly property color accent: Commons.Color.accent
  readonly property color paper: Qt.rgba(Commons.Color.popups.background.r, Commons.Color.popups.background.g,
                                         Commons.Color.popups.background.b, 1)
  readonly property var borderSpec: Border.localOrSurfaceSpec("popups", "border", Commons.Color.popups.border,
                                                              Commons.Color.popups.border, Math.max(1, Style.space(2)))

  function spell(seconds) {
    var minutes = Math.round(seconds / 60)
    if (minutes < 60) return minutes + " min"
    var m = minutes % 60
    return Math.floor(minutes / 60) + " h" + (m ? " " + (m < 10 ? "0" : "") + m + " min" : "")
  }

  function clock(t) {
    var d = new Date(t * 1000)
    return (d.getHours() < 10 ? "0" : "") + d.getHours() + ":" + (d.getMinutes() < 10 ? "0" : "") + d.getMinutes()
  }

  readonly property string status: {
    var res = overlay.reserve
    if (!res || !res.present) return "No battery found"
    var cur = overlay.r ? overlay.r.current : null
    if (res.onBattery) {
      var left = overlay.r && overlay.r.timeLeft ? overlay.r.timeLeft : null
      if (left) return "About " + overlay.spell(left.hours * 3600) + " left at " + (left.rateMw / 1000).toFixed(1) + " W"
      if (res.timeToEmpty > 0) return "About " + overlay.spell(res.timeToEmpty) + " left"
      return "On battery"
    }
    if (cur && cur.st === "C") return "Charging at " + (Math.abs(cur.mw) / 1000).toFixed(0) + " W" + (res.timeToFull > 0 ? ", full in " + overlay.spell(res.timeToFull) : "")
    if (cur && cur.st === "N") return "Plugged in, held at the charge limit"
    return "Plugged in"
  }

  component Heading: Text {
    textFormat: Text.PlainText
    color: Qt.rgba(Commons.Color.popups.text.r, Commons.Color.popups.text.g, Commons.Color.popups.text.b, 0.6)
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    font.capitalization: Font.AllUppercase
    font.letterSpacing: 1
    Layout.topMargin: Style.space(4)
  }

  component Tile: ColumnLayout {
    id: tile
    property string label: ""
    property string value: ""
    property string note: ""
    readonly property color ink: Commons.Color.popups.text
    spacing: 0
    Layout.fillWidth: true
    Text {
      textFormat: Text.PlainText
      text: tile.label
      color: Qt.rgba(tile.ink.r, tile.ink.g, tile.ink.b, 0.6)
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      font.capitalization: Font.AllUppercase
      font.letterSpacing: 1
    }
    Text {
      textFormat: Text.PlainText
      text: tile.value
      color: tile.ink
      font.family: Style.font.family
      font.pixelSize: Style.font.title
      font.bold: true
    }
    Text {
      Layout.fillWidth: true
      visible: tile.note !== ""
      textFormat: Text.PlainText
      wrapMode: Text.Wrap
      text: tile.note
      color: Qt.rgba(tile.ink.r, tile.ink.g, tile.ink.b, 0.6)
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }
  }

  PanelWindow {
    id: surface
    visible: overlay.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "reserve-panel"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: overlay.opened ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    MouseArea {
      anchors.fill: parent
      onClicked: overlay.dismiss()
    }

    Item {
      anchors.fill: parent
      focus: overlay.opened
      Keys.onEscapePressed: overlay.dismiss()
    }

    BorderSurface {
      id: card
      width: Style.space(430)
      height: Math.min(surface.height - y - Style.gapsOut * 2, content.implicitHeight + Style.spacing.popupPadding * 2)
      x: {
        var want = overlay.reserve && overlay.reserve.anchorX >= 0 ? overlay.reserve.anchorX - width / 2 : surface.width - width
        return Math.max(Style.gapsOut, Math.min(surface.width - width - Style.gapsOut, want))
      }
      y: Style.bar.sizeHorizontal + Style.gapsOut * 2
      color: overlay.paper
      borderSpec: overlay.borderSpec
      radius: Style.cornerRadius
      clip: true

      MouseArea { anchors.fill: parent }

      Flickable {
        anchors.fill: parent
        anchors.margins: Style.spacing.popupPadding
        contentHeight: content.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        ColumnLayout {
          id: content
          width: parent.width
          spacing: Style.space(10)

          // ------------------------------------------------ now
          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(12)
            Text {
              textFormat: Text.PlainText
              text: overlay.reserve ? overlay.reserve.percent + "%" : ""
              color: overlay.ink
              font.family: Style.font.family
              font.pixelSize: Style.font.display
              font.bold: true
            }
            ColumnLayout {
              Layout.fillWidth: true
              spacing: 0
              Text {
                textFormat: Text.PlainText
                text: "Reserve"
                color: overlay.faint
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                font.capitalization: Font.AllUppercase
                font.letterSpacing: 1
              }
              Text {
                Layout.fillWidth: true
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                text: overlay.status
                color: overlay.ink
                font.family: Style.font.family
                font.pixelSize: Style.font.body
              }
            }
          }

          // ------------------------------------------------ the last 24 hours
          Canvas {
            id: chart
            Layout.fillWidth: true
            Layout.preferredHeight: Style.space(120)
            readonly property var data: overlay.r
            readonly property color ink: overlay.ink
            readonly property color line: overlay.accent
            onDataChanged: requestPaint()
            onWidthChanged: requestPaint()
            onInkChanged: requestPaint()

            onPaint: {
              var c = getContext("2d")
              c.reset()
              var d = chart.data
              var left = Style.space(26), bottom = Style.space(16)
              var w = width - left, h = height - bottom
              c.font = Math.round(Style.font.caption * 0.9) + "px sans-serif"
              c.fillStyle = Qt.rgba(chart.ink.r, chart.ink.g, chart.ink.b, 0.55)
              c.strokeStyle = Qt.rgba(chart.ink.r, chart.ink.g, chart.ink.b, 0.12)
              c.lineWidth = 1
              c.textAlign = "right"; c.textBaseline = "middle"
              var levels = [100, 50, 0]
              for (var i = 0; i < levels.length; i++) {
                var y = h - levels[i] / 100 * h
                c.beginPath(); c.moveTo(left, y + 0.5); c.lineTo(width, y + 0.5); c.stroke()
                c.fillText(String(levels[i]), left - Style.space(4), Math.max(6, Math.min(h - 2, y)))
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

              // The level, with a soft fill, broken where the laptop slept.
              var pts = d.level
              c.lineWidth = Math.max(2, Style.space(2))
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
                c.beginPath(); c.arc(X(last[0]), Y(last[1]), Math.max(3, Style.space(4)), 0, Math.PI * 2); c.fill()
              }

              // Times along the bottom.
              c.fillStyle = Qt.rgba(chart.ink.r, chart.ink.g, chart.ink.b, 0.55)
              c.textBaseline = "alphabetic"
              var marks = [[t0, "left"], [t0 + (t1 - t0) / 2, "center"], [t1, "right"]]
              for (var m = 0; m < marks.length; m++) {
                c.textAlign = marks[m][1]
                c.fillText(m === 2 ? "now" : overlay.clock(marks[m][0]), X(marks[m][0]), height - 2)
              }
            }
          }

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(14)
            Repeater {
              model: [["Charging", overlay.accent, 0.35], ["Asleep", overlay.ink, 0.25]]
              delegate: Row {
                required property var modelData
                spacing: Style.space(5)
                Rectangle {
                  width: Style.space(10); height: width; radius: 2
                  anchors.verticalCenter: parent.verticalCenter
                  color: Qt.rgba(modelData[1].r, modelData[1].g, modelData[1].b, modelData[2])
                }
                Text {
                  textFormat: Text.PlainText
                  text: modelData[0]
                  color: overlay.faint
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                }
              }
            }
          }

          PanelSeparator { Layout.fillWidth: true }

          // ------------------------------------------------ where it went
          RowLayout {
            Layout.fillWidth: true
            Heading { Layout.fillWidth: true; text: "Battery use" }
            ButtonGroup {
              options: [{ value: "unplug", label: "Since unplugged" }, { value: "today", label: "Today" }]
              value: overlay.reserve ? overlay.reserve.since : "unplug"
              foreground: overlay.ink
              accent: overlay.accent
              fontSize: Style.font.caption
              onChanged: function (v) { overlay.reserve.setSince(v) }
            }
          }

          Text {
            Layout.fillWidth: true
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            text: {
              if (!overlay.r) return "Reading the history…"
              var u = overlay.r.usage
              if (!u || u.totalMwh <= 0) return overlay.r.sinceLabel + ": nothing used on battery yet. Usage by app appears after the first ten minutes unplugged."
              return overlay.r.sinceLabel + ": " + (u.totalMwh / 1000).toFixed(1) + " Wh used. Shares are estimates from each app's CPU and GPU time."
            }
            color: overlay.faint
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }

          Repeater {
            model: {
              var u = overlay.r ? overlay.r.usage : null
              if (!u || u.totalMwh <= 0) return []
              var rows = u.apps.slice(0, 6).map(function (a) { return { name: a.name, share: a.share, detail: Math.round(a.cpuMs / 60000) + " min of CPU" } })
              rows.push({ name: "Screen and system", share: u.baseShare, detail: "what the laptop uses doing nothing" })
              return rows.sort(function (a, b) { return b.share - a.share })
            }
            delegate: RowLayout {
              required property var modelData
              Layout.fillWidth: true
              spacing: Style.space(10)
              ColumnLayout {
                Layout.preferredWidth: Style.space(150)
                spacing: 0
                Text {
                  Layout.fillWidth: true
                  textFormat: Text.PlainText
                  elide: Text.ElideRight
                  text: modelData.name
                  color: overlay.ink
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                }
                Text {
                  Layout.fillWidth: true
                  textFormat: Text.PlainText
                  elide: Text.ElideRight
                  text: modelData.detail
                  color: overlay.faint
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                }
              }
              Item {
                Layout.fillWidth: true
                Layout.preferredHeight: Style.space(8)
                Rectangle { anchors.fill: parent; radius: height / 2; color: overlay.hairline }
                Rectangle {
                  width: parent.width * Math.max(0.02, Math.min(1, modelData.share / 100))
                  height: parent.height
                  radius: height / 2
                  color: overlay.accent
                }
              }
              Text {
                textFormat: Text.PlainText
                Layout.preferredWidth: Style.space(44)
                horizontalAlignment: Text.AlignRight
                text: Math.round(modelData.share) + "%"
                color: overlay.ink
                font.family: Style.font.family
                font.pixelSize: Style.font.body
              }
            }
          }

          // ------------------------------------------------ worth knowing
          Repeater {
            model: overlay.r ? overlay.r.insights : []
            delegate: RowLayout {
              required property var modelData
              Layout.fillWidth: true
              spacing: Style.space(8)
              Rectangle {
                Layout.alignment: Qt.AlignTop
                Layout.topMargin: Style.space(6)
                width: Style.space(6); height: width; radius: width / 2
                color: Commons.Color.urgent
              }
              Text {
                Layout.fillWidth: true
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                text: modelData.text
                color: overlay.ink
                font.family: Style.font.family
                font.pixelSize: Style.font.body
              }
            }
          }

          PanelSeparator { Layout.fillWidth: true }

          // ------------------------------------------------ the battery itself
          Heading { text: "Health" }

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(10)
            Tile {
              label: "Capacity"
              value: overlay.r && overlay.r.health.capacity !== null ? overlay.r.health.capacity.toFixed(0) + "%" : "—"
              note: "of design"
            }
            Tile {
              label: "Cycles"
              value: overlay.r && overlay.r.health.cycles !== null ? String(overlay.r.health.cycles) : "—"
              note: overlay.r && overlay.r.health.year ? "since " + overlay.r.health.year : ""
            }
            Tile {
              label: "Temperature"
              value: overlay.r && overlay.r.health.temperature !== null ? overlay.r.health.temperature.toFixed(0) + " °C" : "—"
              note: overlay.r ? overlay.r.health.health : ""
            }
            Tile {
              visible: overlay.r !== null && overlay.r.charger !== null
              label: "Charger"
              value: overlay.r && overlay.r.charger ? overlay.r.charger.watts + " W" : ""
              note: "USB-C"
            }
          }

          Text {
            Layout.fillWidth: true
            visible: text !== ""
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            text: overlay.r && overlay.r.charger ? overlay.r.charger.note : ""
            color: overlay.faint
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }

          Text {
            Layout.fillWidth: true
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            text: {
              var t = overlay.r ? overlay.r.trend : []
              if (!t || t.length < 2) return "A capacity trend appears here after a few days."
              var first = t[0], last = t[t.length - 1]
              var change = last[1] - first[1]
              return "Capacity " + (change >= 0 ? "held at " : "went from " + first[1].toFixed(1) + "% to ") + last[1].toFixed(1) + "% since " + first[0] + "."
            }
            color: overlay.faint
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }

          // The shell lets a plugin open only its own panels, so this says where the other controls live.
          Text {
            Layout.fillWidth: true
            visible: overlay.powerPlugin !== ""
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            text: overlay.powerPlugin === "io.github.nipsen.dell-power"
              ? "The charge limit, thermal modes and fans are in Dell Power, on your bar or in the tray drawer."
              : "The power profile and charge settings are in Omarchy's power panel on your bar."
            color: overlay.faint
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }

          Text {
            Layout.fillWidth: true
            visible: overlay.reserve !== null && overlay.reserve.trouble !== ""
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            text: overlay.reserve ? overlay.reserve.trouble : ""
            color: Commons.Color.urgent
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }
}
