import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower

// Reserve's service: keeps the sampler running for the life of the shell, and asks it for a report when the panel
// wants one. The live level in the bar comes from UPower, which the shell already watches; the history comes from
// the sampler's own files, because UPower keeps only a few points of it.
Item {
  id: reserve

  property var shell: null
  property var manifest: null
  readonly property string pluginId: "reidenxerx.reserve"
  readonly property string helper: String(Qt.resolvedUrl("../bin/reserve")).replace("file://", "")

  // ---------------------------------------------------------------- live, from UPower

  readonly property var device: UPower.displayDevice
  readonly property bool present: reserve.device !== null && reserve.device.isPresent === true
  // UPower's display device reports 0 to 1.
  readonly property int percent: reserve.present ? Math.round(Math.max(0, Math.min(1, reserve.device.percentage)) * 100) : 0
  readonly property bool onBattery: UPower.onBattery === true
  readonly property real timeToEmpty: reserve.present ? reserve.device.timeToEmpty : 0
  readonly property real timeToFull: reserve.present ? reserve.device.timeToFull : 0

  // ---------------------------------------------------------------- the sampler

  Process {
    id: sampler
    command: ["/usr/bin/python3", "-I", reserve.helper, "run"]
    running: true
    onExited: function (code) { restart.start() }
  }

  // A sampler that stops (a crash, a second shell that holds the lock until it goes) is tried again, not forgotten.
  Timer {
    id: restart
    interval: 30000
    onTriggered: if (!sampler.running) sampler.running = true
  }

  // ---------------------------------------------------------------- reports

  property var report: null
  property string since: "unplug"
  property string trouble: ""

  function refresh() {
    if (reporter.running) return
    reporter.command = ["/usr/bin/python3", "-I", reserve.helper, "report", "--since", reserve.since === "today" ? "today" : "unplug"]
    reporter.running = true
    deadline.restart()
  }

  function setSince(value) {
    reserve.since = value === "today" ? "today" : "unplug"
    reserve.refresh()
  }

  Process {
    id: reporter
    stdout: StdioCollector {
      onStreamFinished: {
        deadline.stop()
        var raw = text.length > 2 * 1024 * 1024 ? "" : text
        try {
          reserve.report = JSON.parse(raw)
          reserve.trouble = ""
        } catch (e) {
          reserve.trouble = "Reserve could not read its history."
        }
      }
    }
  }

  // A report that has not answered in ten seconds is stopped: the panel shows what it had.
  Timer {
    id: deadline
    interval: 10000
    onTriggered: if (reporter.running) reporter.signal(9)
  }

  // While the panel is open the report keeps up with the sampler.
  property bool panelOpen: false
  Timer {
    interval: 60000
    repeat: true
    running: reserve.panelOpen
    onTriggered: reserve.refresh()
  }

  property real anchorX: -1

  function togglePanel(x) {
    if (x !== undefined && x >= 0) reserve.anchorX = x
    if (reserve.shell && typeof reserve.shell.toggle === "function") reserve.shell.toggle(reserve.pluginId, "{}")
  }
}
