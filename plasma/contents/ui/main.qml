import QtQuick
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasma5support as P5Support

// Reserve for Plasma: the battery the way a phone shows it.
//
// The live level comes from Plasma's power management; the history from Reserve's own sampler (bin/reserve run,
// the same helper as the Omarchy edition), which this widget keeps running for as long as Plasma runs and asks for
// a report when the panel opens.
PlasmoidItem {
  id: root

  readonly property string helper: decodeURIComponent(String(Qt.resolvedUrl("../code/bin/reserve")).replace("file://", ""))

  // ---------------------------------------------------------------- live, from Plasma

  P5Support.DataSource {
    id: power
    engine: "powermanagement"
    connectedSources: ["Battery", "AC Adapter"]
  }

  readonly property var battery: power.data["Battery"] || ({})
  readonly property bool present: root.battery["Has Battery"] === true
  readonly property int percent: root.present ? Math.max(0, Math.min(100, Math.round(Number(root.battery["Percent"]) || 0))) : 0
  readonly property string state: String(root.battery["State"] || "")
  readonly property bool pluggedIn: power.data["AC Adapter"] ? power.data["AC Adapter"]["Plugged in"] === true : false
  readonly property bool onBattery: root.present && !root.pluggedIn
  readonly property bool charging: root.state === "Charging"
  // Seconds; Plasma gives milliseconds, and only while discharging.
  readonly property real timeToEmpty: Number(root.battery["Smoothed Remaining msec"] || root.battery["Remaining msec"] || 0) / 1000

  // ---------------------------------------------------------------- commands

  P5Support.DataSource {
    id: runner
    engine: "executable"
    connectedSources: []
    property var onDone: ({})
    onNewData: function (source, data) {
      disconnectSource(source)
      var cb = runner.onDone[source]
      delete runner.onDone[source]
      if (cb) cb(data["exit code"], String(data["stdout"] || ""))
    }
  }

  function quote(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'" }

  function run(command, done) {
    runner.onDone[command] = done
    runner.connectSource(command)
  }

  // ---------------------------------------------------------------- the sampler

  // Runs until Plasma goes (it follows its parent), one at a time (a second one exits at once, so two Reserve
  // widgets share one sampler). One that stops is tried again in half a minute.
  readonly property string samplerCommand: "/usr/bin/python3 -I " + root.quote(root.helper) + " run"

  // One that stops straight away (another holds the lock: a second widget, or the last Plasma's still going) is
  // tried less and less often, up to every ten minutes, instead of a new Python every half minute.
  property double samplerStarted: 0
  property int quickStops: 0
  function startSampler() {
    root.samplerStarted = Date.now()
    root.run(root.samplerCommand, function () {
      root.quickStops = Date.now() - root.samplerStarted < 20000 ? root.quickStops + 1 : 0
      restart.interval = Math.min(600000, 30000 * Math.pow(2, Math.min(5, root.quickStops)))
      restart.start()
    })
  }

  Timer {
    id: restart
    interval: 30000
    onTriggered: root.startSampler()
  }

  Component.onCompleted: root.startSampler()

  // ---------------------------------------------------------------- reports

  property var report: null
  property string trouble: ""
  property bool reporting: false
  property bool refreshAgain: false
  readonly property string since: Plasmoid.configuration.since === "today" ? "today" : "unplug"

  function refresh() {
    if (root.reporting) { root.refreshAgain = true; return }
    root.reporting = true
    root.refreshAgain = false
    // A report that has not answered in ten seconds is stopped by timeout: the panel shows what it had.
    root.run("/usr/bin/timeout -k 2 10 /usr/bin/python3 -I " + root.quote(root.helper) + " report --since " + root.quote(root.since),
             function (code, out) {
      root.reporting = false
      if (out.length > 0 && out.length < 2 * 1024 * 1024) {
        try {
          root.report = JSON.parse(out)
          root.trouble = ""
        } catch (e) {
          root.trouble = "Reserve could not read its history."
        }
      } else if (code !== 0) {
        root.trouble = "Reserve could not read its history."
      }
      if (root.refreshAgain) Qt.callLater(root.refresh)
    })
  }

  function setSince(value) {
    Plasmoid.configuration.since = value === "today" ? "today" : "unplug"
    root.refresh()
  }

  onExpandedChanged: function () { if (root.expanded) root.refresh() }

  // While the panel is open the report keeps up with the sampler.
  Timer {
    interval: 60000
    repeat: true
    running: root.expanded
    onTriggered: root.refresh()
  }

  // ---------------------------------------------------------------- the icon

  function spell(seconds) {
    var minutes = Math.round(seconds / 60)
    if (minutes < 60) return minutes + " min"
    var m = minutes % 60
    return Math.floor(minutes / 60) + " h" + (m ? " " + (m < 10 ? "0" : "") + m + " min" : "")
  }

  // Breeze's battery icons go in steps of ten, with a charging set.
  Plasmoid.icon: {
    if (!root.present) return "battery-missing"
    var step = Math.max(0, Math.min(100, Math.round(root.percent / 10) * 10))
    var level = (step < 100 ? (step < 10 ? "00" : "0") : "") + step
    return "battery-" + level + (root.charging ? "-charging" : "")
  }

  toolTipMainText: root.present ? "Reserve: " + root.percent + "%" : "Reserve: no battery found"
  toolTipSubText: {
    if (!root.present) return ""
    if (root.onBattery && root.timeToEmpty > 0) return "About " + root.spell(root.timeToEmpty) + " left"
    if (root.charging) return "Charging"
    if (root.state === "NoCharge") return "Plugged in, held at the charge limit"
    if (!root.onBattery) return "Plugged in"
    return "On battery"
  }

  Plasmoid.status: root.present ? PlasmaCore.Types.ActiveStatus : PlasmaCore.Types.PassiveStatus

  preferredRepresentation: compactRepresentation
  fullRepresentation: FullView { reserve: root }
}
