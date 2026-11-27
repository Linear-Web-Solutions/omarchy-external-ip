import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

// The one owner of the public IP lookup, shared by this plugin's widget on
// every bar. A bar widget is instantiated once per monitor; keeping the
// timer, the route monitor and the lookup here means one request per cycle
// and one monitor process however many screens there are.
//
// The lookup itself lives in bin/bar-external-ip inside this plugin. This
// service only decides when to run it and keeps the last JSON it printed. The
// helper runs asynchronously, so the bar never waits on the network.
Item {
  id: root

  // Injected by the shell; unused, declared so injection is harmless.
  property var shell: null
  property var manifest: null

  readonly property string pluginId: "lws.external-ip"
  // The helper ships beside this file, so a git checkout of the plugin is a
  // complete install and `omarchy plugin update` updates both together.
  readonly property string helper: localPath(Qt.resolvedUrl("bin/bar-external-ip"))

  function localPath(url) {
    var s = String(url)
    if (s.indexOf("file://") !== 0) {
      console.warn(pluginId + ": plugin is not loaded from a local file; cannot find its helper")
      return ""
    }
    return decodeURIComponent(s.substring("file://".length))
  }

  // Seconds between scheduled lookups. Widgets push the `interval` setting
  // from their shell.json entry through configure().
  property int refreshSeconds: 60
  // A route change usually arrives as a burst (link, address, routes, rules);
  // look up once it settles, and never more than once per minimum gap.
  readonly property int settleMs: 2500
  readonly property int eventGapMs: 5000
  // The helper's own worst case is ~15 s; this only stops a wedged process.
  readonly property int watchdogMs: 45000

  property var status: ({})
  readonly property string ipState: typeof status.state === "string" ? status.state : "pending"
  readonly property string ip: typeof status.ip === "string" ? status.ip : ""
  readonly property string label: typeof status.label === "string" ? status.label : ""
  readonly property string tooltip: typeof status.tooltip === "string" ? status.tooltip : ""
  readonly property bool busy: fetchProc.running

  property bool pendingForced: false
  property bool pendingScheduled: false
  property real lastEventLookup: 0

  function configure(seconds) {
    var n = Math.round(Number(seconds))
    if (!isFinite(n)) return
    n = Math.max(15, Math.min(3600, n))
    if (n !== refreshSeconds) refreshSeconds = n
  }

  function apply(raw) {
    var data
    try {
      data = JSON.parse(String(raw || ""))
    } catch (e) {
      console.warn(pluginId + ": ignoring unreadable helper output")
      return
    }
    if (!data || typeof data !== "object" || Array.isArray(data)) return
    root.status = data
  }

  // force: a manual or network-change lookup, which bypasses the helper's
  // 10-second reuse window. Requests made while one runs collapse into a
  // single follow-up, so repeated clicks cannot pile up requests.
  function refresh(force) {
    if (helper === "") return
    if (fetchProc.running) {
      if (force) pendingForced = true
      else pendingScheduled = true
      return
    }
    fetchProc.command = force
      ? [helper, "fetch", "--from-bar", "--force"]
      : [helper, "fetch", "--from-bar"]
    fetchProc.running = true
    refreshTimer.restart()
  }

  // Re-read cached state and local network details. No network requests.
  function reload() {
    if (helper !== "" && !statusProc.running) statusProc.running = true
  }

  function copy() {
    if (helper !== "") Quickshell.execDetached([helper, "copy"])
  }

  function noteRouteChange() {
    if (settleTimer.running) return
    var sinceLast = Date.now() - lastEventLookup
    settleTimer.interval = Math.max(settleMs, eventGapMs - sinceLast)
    settleTimer.start()
  }

  Process {
    id: fetchProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.apply(text)
    }
    onRunningChanged: {
      if (running) {
        watchdog.restart()
        return
      }
      watchdog.stop()
      if (root.pendingForced || root.pendingScheduled) {
        const forced = root.pendingForced
        root.pendingForced = false
        root.pendingScheduled = false
        Qt.callLater(function() { root.refresh(forced) })
      }
    }
  }

  Process {
    id: statusProc
    command: [root.helper, "status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.apply(text)
    }
  }

  Timer {
    id: watchdog
    interval: root.watchdogMs
    onTriggered: {
      if (!fetchProc.running) return
      console.warn(root.pluginId + ": lookup exceeded " + (root.watchdogMs / 1000) + " s, stopping it")
      fetchProc.running = false
    }
  }

  Timer {
    id: refreshTimer
    interval: root.refreshSeconds * 1000
    repeat: true
    running: true
    onTriggered: root.refresh(false)
  }

  // IPv4 route and policy-rule changes: interfaces coming up or down, DHCP,
  // Wi-Fi roaming, and VPNs (WireGuard and Tailscale install their own tables
  // and rules). The process sleeps on a netlink socket between events.
  Process {
    id: routeMonitor
    command: ["ip", "-4", "-o", "monitor", "route", "rule"]
    running: true
    stdout: SplitParser {
      onRead: function(line) { root.noteRouteChange() }
    }
    onRunningChanged: if (!running) monitorRestart.start()
  }

  Timer {
    id: monitorRestart
    interval: 30000
    onTriggered: routeMonitor.running = true
  }

  Timer {
    id: settleTimer
    onTriggered: {
      root.lastEventLookup = Date.now()
      root.refresh(true)
    }
  }

  ShellIpc {
    target: root.pluginId

    function refresh(): void { root.refresh(true) }
    function reload(): void { root.reload() }
    function copy(): void { root.copy() }
    function status(): string { return JSON.stringify(root.status) }
    function info(): string {
      return JSON.stringify({
        refreshSeconds: root.refreshSeconds,
        lookupRunning: fetchProc.running,
        routeMonitorRunning: routeMonitor.running,
        helper: root.helper
      })
    }
  }

  Component.onCompleted: {
    reload()
    refresh(false)
  }
}
