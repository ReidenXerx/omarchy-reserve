import QtQuick
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Reserve in the bar: a usage chart, so it sits beside Omarchy's own battery icon without looking like a second one.
// The tooltip has the level and the time left; a click opens the panel with usage, health and charging.
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

  // md-chart-donut U+F07AF (checked by name in the font's cmap): what the battery went on, not how full it is.
  // Omarchy's own power widget shows the charge, so the two sit side by side without looking alike.
  readonly property string glyph: String.fromCodePoint(0xF07AF)

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
