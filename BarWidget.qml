import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

BarWidget {
  id: root
  moduleName: "io.github.akira.omaestrata"
  property var snapshot: null
  property string stateText: "connecting"
  property var envConfig: ({})
  readonly property var remoteConfig: ({
    mode: connectionMode,
    strataRoot: Model.sanitizeRemotePath(Model.pick(envConfig, "STRATA_ROOT", "/home/akira/Strata"), "/home/akira/Strata"),
    startScript: Model.sanitizeRemotePath(Model.pick(envConfig, "START_SCRIPT", "/home/akira/Strata/run-iq3_s.sh"), "/home/akira/Strata/run-iq3_s.sh"),
    diskPath: Model.sanitizeRemotePath(Model.pick(envConfig, "DISK_PATH", "/"), "/")
  })
  readonly property string connectionMode: String(Model.preferCustom(setting("connectionMode", "ssh"), Model.pick(envConfig, "MODE", ""), "ssh")).toLowerCase() === "local" ? "local" : "ssh"
  readonly property string sshTarget: Model.sanitizeSshTarget(Model.preferCustom(setting("sshTarget", "akira@192.168.1.168"), Model.pick(envConfig, "SSH_TARGET", ""), "akira@192.168.1.168"), "akira@192.168.1.168")
  readonly property int refreshSeconds: Math.max(5, Math.min(120, parseInt(Model.preferCustom(setting("refreshSeconds", 10), Model.pick(envConfig, "REFRESH_SECONDS", ""), 10), 10) || 10))
  readonly property string processPattern: String(Model.preferCustom(setting("strataProcessPattern", "strata"), Model.pick(envConfig, "PROCESS_PATTERN", ""), "strata")).replace(/[^A-Za-z0-9_.-]/g, "") || "strata"
  readonly property string label: Model.compact(snapshot, stateText, vertical)
  readonly property string tooltip: Model.tooltip(snapshot, stateText)
  readonly property string widgetLabel: Model.widgetActionLabel(snapshot, stateText, serverLaunchState, vertical)
  readonly property string widgetActionTooltip: serverLaunchState === "starting" ? (connectionMode === "local" ? "Starting Strata locally" : "Starting Strata over SSH") : (serverLaunchState === "stopping" ? (connectionMode === "local" ? "Stopping Strata locally" : "Stopping Strata over SSH") : (serverLaunchState === "error" ? (connectionMode === "local" ? "Click to retry starting Strata" : "Click to retry starting Strata over SSH") : (!serverOnline ? (connectionMode === "local" ? "Click to start Strata locally; right-click for details; middle-click to refresh" : "Click to start Strata over SSH; right-click for details; middle-click to refresh") : tooltip)))
  property string serverLaunchState: "idle"
  property bool startRequested: false
  property var generationTokS: null
  property var prefillTokS: null
  property string serverLaunchError: ""
  readonly property bool serverOnline: !!(snapshot && snapshot.online)
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened : false
  readonly property bool popoutSwitchClosing: false
  readonly property real openPanelIndicatorWidth: button.labelWidth
  readonly property real openPanelIndicatorHeight: Math.max(Style.space(10), Math.round(Style.bar.iconSlot * 0.55))

  function injectPanel() {
    if (!panelLoader.item) return
    panelLoader.item.bar = root.bar
    panelLoader.item.settings = root.settings
    panelLoader.item.anchorItem = button
    panelLoader.item.hostWidget = root
    panelLoader.item.snapshot = root.snapshot
    panelLoader.item.stateText = root.stateText
    panelLoader.item.sshTarget = root.sshTarget
    panelLoader.item.refreshSeconds = root.refreshSeconds
    panelLoader.item.processPattern = root.processPattern
    panelLoader.item.startScript = root.remoteConfig.startScript
    panelLoader.item.connectionMode = root.connectionMode
    panelLoader.item.serverLaunchState = root.serverLaunchState
    panelLoader.item.generationTokS = root.generationTokS
    panelLoader.item.prefillTokS = root.prefillTokS
    panelLoader.item.serverLaunchError = root.serverLaunchError
  }
  function applyEnv() {
    var plugin = ""
    var user = ""
    try { plugin = pluginEnvFile.text() } catch (e) {}
    try { user = userEnvFile.text() } catch (e) {}
    var merged = Model.parseEnv(plugin)
    var extra = Model.parseEnv(user)
    for (var key in extra) merged[key] = extra[key]
    envConfig = merged
  }

  FileView {
    id: userEnvFile
    path: Quickshell.env("HOME") + "/.config/omarchy/omaestrata.env"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.applyEnv()
    onLoadFailed: root.applyEnv()
  }

  FileView {
    id: pluginEnvFile
    path: {
      var url = String(Qt.resolvedUrl(".env"))
      return url.indexOf("file://") === 0 ? decodeURIComponent(url.slice(7)) : url
    }
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.applyEnv()
    onLoadFailed: root.applyEnv()
  }

  function refresh() { statusProc.running = false; Qt.callLater(function() { statusProc.running = true }) }
  function startServer() {
    if (serverStartProc.running || serverStopProc.running || serverOnline) return false
    if (serverLaunchState === "starting" || serverLaunchState === "stopping") return false
    serverLaunchError = ""
    generationTokS = null
    prefillTokS = null
    serverLaunchState = "starting"
    serverStartProc.running = true
    startMetrics()
    return true
  }
  function stopServer() {
    if (serverStopProc.running || serverLaunchState === "stopping") return false
    if (!serverOnline && !serverStartProc.running && serverLaunchState !== "starting") return false
    serverLaunchError = ""
    serverLaunchState = "stopping"
    if (serverStartProc.running) serverStartProc.running = false
    metricsProc.running = false
    serverStopProc.running = true
    return true
  }
  function requestStart() {
    if (serverStartProc.running || serverLaunchState === "starting" || serverLaunchState === "stopping") return false
    if (serverOnline) { togglePanel(); return false }
    if (stateText === "connecting") { startRequested = true; return true }
    return startServer()
  }
  function startMetrics() { if (!metricsProc.running) metricsProc.running = true }
  function consumeServerLine(line) {
    var rates = Model.parseThroughputLine(line)
    if (!rates) return
    if (rates.generationTokS !== null) generationTokS = rates.generationTokS
    if (rates.prefillTokS !== null) prefillTokS = rates.prefillTokS
  }
  function consumeMetricsLine(line) {
    var rates = Model.parseMetricsLine(line)
    if (!rates) return
    generationTokS = rates.generationTokS
    prefillTokS = rates.prefillTokS
    if (rates.model && snapshot) {
      var updated = {}
      for (var key in snapshot) updated[key] = snapshot[key]
      updated.model = rates.model
      if (rates.latestLog) updated.latestLog = rates.latestLog
      snapshot = updated
    }
  }
  function togglePanel() { if (panelLoader.item) panelLoader.item.toggle() }
  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function closeForPopoutSwitch() { close() }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight
  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()
  onSnapshotChanged: {
    if (serverOnline) {
      if (serverLaunchState !== "stopping") {
        serverLaunchState = "running"
        startMetrics()
      }
    } else if (!serverStartProc.running) {
      metricsProc.running = false
      if (serverLaunchState === "stopping" && !serverStopProc.running) serverLaunchState = "stopped"
    }
    if (root.startRequested) {
      root.startRequested = false
      if (root.serverOnline) Qt.callLater(root.open)
      else Qt.callLater(root.startServer)
    }
    injectPanel()
  }
  onStateTextChanged: {
    if (stateText === "error" && startRequested) startRequested = false
    injectPanel()
  }
  onServerLaunchStateChanged: injectPanel()
  onGenerationTokSChanged: injectPanel()
  onPrefillTokSChanged: injectPanel()
  onServerLaunchErrorChanged: injectPanel()
  onSshTargetChanged: refresh()
  onRemoteConfigChanged: refresh()
  Component.onCompleted: refresh()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: { root.injectPanel(); Qt.callLater(root.injectPanel) }
  }

  Process {
    id: statusProc
    command: Model.command(root.sshTarget, root.processPattern, root.remoteConfig)
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = Model.parseSnapshot(text)
        if (parsed) {
          root.snapshot = parsed
          root.stateText = "ok"
          if (parsed.online) {
            if (root.serverLaunchState !== "stopping") root.serverLaunchState = "running"
          } else if (root.serverLaunchState === "stopping" && !serverStopProc.running) {
            root.serverLaunchState = "stopped"
          }
        } else root.stateText = "error"
        root.injectPanel()
      }
    }
    onRunningChanged: if (running) root.stateText = "connecting"
  }

  Process {
    id: metricsProc
    command: Model.metricsCommand(root.sshTarget, root.remoteConfig)
    stdout: SplitParser { onRead: function(line) { root.consumeMetricsLine(line) } }
    // Scan only the newest model log; the helper emits its filename/model and
    // numeric rates, never raw log content, prompts, or generated text.
    stderr: SplitParser { onRead: function(line) {} }
  }

  Timer {
    interval: 5000
    running: true
    repeat: true
    onTriggered: {
      if ((root.serverOnline || serverStartProc.running) && !metricsProc.running) root.startMetrics()
    }
  }

  Process {
    id: serverStartProc
    command: Model.startCommand(root.sshTarget, root.remoteConfig)
    stdout: SplitParser { onRead: function(line) { root.consumeServerLine(line) } }
    // Drain but never display arbitrary remote stderr; it may contain sensitive
    // request or environment details. The exit status is enough for the UI.
    stderr: SplitParser { onRead: function(line) {} }
    onRunningChanged: {
      if (running && root.serverLaunchState !== "running" && root.serverLaunchState !== "stopping") root.serverLaunchState = "starting"
    }
    onExited: function(exitCode) {
      if (root.serverLaunchState === "stopping") return
      root.serverLaunchState = exitCode === 0 ? "stopped" : "error"
      root.serverLaunchError = exitCode === 0 ? "" : ((root.connectionMode === "local" ? "Strata startup failed" : "SSH or Strata startup failed") + " (exit " + exitCode + ").")
      root.refresh()
    }
  }

  Process {
    id: serverStopProc
    command: Model.stopCommand(root.sshTarget, root.processPattern, root.remoteConfig)
    stdout: SplitParser { onRead: function(line) {} }
    stderr: SplitParser { onRead: function(line) {} }
    onRunningChanged: {
      if (running) root.serverLaunchState = "stopping"
    }
    onExited: function(exitCode) {
      if (exitCode === 0) {
        if (!root.serverOnline) root.serverLaunchState = "stopped"
      } else {
        root.serverLaunchState = "error"
        root.serverLaunchError = (root.connectionMode === "local" ? "Strata stop failed" : "SSH or Strata stop failed") + " (exit " + exitCode + ")."
      }
      root.refresh()
    }
  }

  Timer {
    interval: root.refreshSeconds * 1000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: Model.clean(root.widgetLabel, 46)
    tooltipText: Model.clean(root.widgetActionTooltip, 450)
    fontSize: 13
    horizontalMargin: 8
    verticalPadding: 6
    onPressed: function(b) {
      if (b === Qt.MiddleButton) root.refresh()
      else if (b === Qt.RightButton) root.togglePanel()
      else if (b === Qt.LeftButton && !root.serverOnline && root.serverLaunchState !== "starting" && root.serverLaunchState !== "stopping") root.requestStart()
      else root.togglePanel()
    }
  }
}
