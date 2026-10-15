import QtQuick
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Reserve in the bar: the battery, at its level in steps of ten, with a bolt while it charges. The tooltip has the
// level and the time left; a click opens the panel with usage, health and charging.
BarWidget {
  id: root
  moduleName: "reidenxerx.reserve"

  readonly property string pluginId: "reidenxerx.reserve"
  property var reserve: null

  function findService() {
    if (root.reserve) return
    var shell = root.bar ? root.bar.shell : null
    root.reserve = shell && typeof shell.serviceFor === "function" ? shell.serviceFor(root.pluginId) : null
  }

  Timer {
    interval: 1000
    repeat: true
    running: !root.reserve
    triggeredOnStart: true
    onTriggered: root.findService()
  }

  onBarChanged: root.findService()

  function spell(seconds) {
    var minutes = Math.round(seconds / 60)
    if (minutes < 60) return minutes + " min"
    return Math.floor(minutes / 60) + " h " + (minutes % 60 < 10 ? "0" : "") + (minutes % 60) + " min"
  }

  readonly property string tooltip: {
    var r = root.reserve
    if (!r || !r.present) return "Reserve: no battery found"
    var line = "Reserve: " + r.percent + "%"
    if (r.onBattery && r.timeToEmpty > 0) line += ", about " + root.spell(r.timeToEmpty) + " left"
    else if (!r.onBattery && r.timeToFull > 0) line += ", full in " + root.spell(r.timeToFull)
    else if (!r.onBattery) line += ", on the charger"
    return line + "\nClick for usage, health and charging"
  }

  // md-battery-10 to -90 are U+F007A to U+F0082 and md-battery U+F0079; the charging set is not in order in the font,
  // so it is listed (all checked in the font's cmap). md-battery-outline U+F008E when there is no battery to show.
  readonly property var chargingGlyphs: [0xF089C, 0xF0086, 0xF0087, 0xF0088, 0xF089D, 0xF0089, 0xF089E, 0xF008A, 0xF008B, 0xF0085]
  readonly property bool charging: root.reserve !== null && root.reserve.charging
  readonly property string glyph: {
    var r = root.reserve
    if (!r || !r.present) return String.fromCodePoint(0xF008E)
    var step = Math.max(1, Math.min(10, Math.round(r.percent / 10)))
    if (root.charging) return String.fromCodePoint(root.chargingGlyphs[step - 1])
    return String.fromCodePoint(step === 10 ? 0xF0079 : 0xF007A + step - 1)
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.glyph
    tooltipText: root.tooltip
    onPressed: function (which) {
      if (!root.reserve) return
      var p = button.mapToItem(null, button.width / 2, 0)
      root.reserve.togglePanel(p.x)
    }
  }
}
