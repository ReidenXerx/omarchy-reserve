import QtQuick
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Reserve in the bar: a battery with a heart, because it is about how the battery is doing rather than a second
// copy of the level. The tooltip has the level and the time left; a click opens the panel.
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

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // md-battery-heart-variant U+F1211 (checked in the font's cmap).
    text: String.fromCodePoint(0xF1211)
    tooltipText: root.tooltip
    onPressed: function (which) {
      if (!root.reserve) return
      var p = button.mapToItem(null, button.width / 2, 0)
      root.reserve.togglePanel(p.x)
    }
  }
}
