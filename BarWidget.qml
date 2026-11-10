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
  property var generationTokS: null
  property var prefillTokS: null
  property string serverLaunchState: "idle"
  property bool startRequested: false
  property string serverLaunchError: ""

  // rolling history for the panel graphs (48 samples ≈ 8 min at 10s)
  property var genHist: []
  property var prefillHist: []
  property var ramHist: []
  property var cpuHist: []

  readonly property color cyberCyan: "#00F0FF"
  readonly property color cyberMagenta: "#FF2E88"
  readonly property color cyberDim: "#4A6B78"
  readonly property color cyberWhite: "#E8FBFF"
  readonly property string cyberFont: "monospace"

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

  readonly property bool serverOnline: !!(snapshot && snapshot.online)
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened : false
  readonly property bool popoutSwitchClosing: false
  readonly property real openPanelIndicatorWidth: chip.implicitWidth
  readonly property real openPanelIndicatorHeight: Math.max(Style.space(10), Math.round(Style.bar.iconSlot * 0.55))

  readonly property string modelName: snapshot && snapshot.online ? String(snapshot.model || "MODEL") : "STRATA"
  readonly property string chipRate: generationTokS === null || generationTokS === undefined ? "--" : Number(generationTokS).toFixed(1)
  readonly property color chipAccent: stateText === "error" ? Color.urgent : (serverOnline ? cyberCyan : cyberMagenta)

  function pushHist(arr, v) {
    if (v === null || v === undefined || v === "") return arr
    var n = Number(v)
    if (!isFinite(n)) return arr
    var out = arr.slice(Math.max(0, arr.length - 47))
    out.push(n)
    return out
  }

  function injectPanel() {
    if (!panelLoader.item) return
    panelLoader.item.bar = root.bar
    panelLoader.item.settings = root.settings
    panelLoader.item.anchorItem = anchorProbe
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
    panelLoader.item.genHist = root.genHist
    panelLoader.item.prefillHist = root.prefillHist
    panelLoader.item.ramHist = root.ramHist
    panelLoader.item.cpuHist = root.cpuHist
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
  function hoverTip() {
    if (!root.bar) return
    var t = serverOnline
      ? modelName + " · gen " + chipRate + " tok/s" + (prefillTokS !== null ? " · prefill " + Number(prefillTokS).toFixed(1) : "")
      : (stateText === "error" ? "Strata: connection error" : "Strata offline · click to start")
    root.bar.showTooltip(root, Model.clean(t, 200))
  }

  implicitWidth: chip.implicitWidth
  implicitHeight: chip.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()
  onSnapshotChanged: {
    if (snapshot) {
      ramHist = pushHist(ramHist, snapshot.ram)
      cpuHist = pushHist(cpuHist, snapshot.cpu)
    }
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
  onGenerationTokSChanged: {
    genHist = pushHist(genHist, generationTokS)
    injectPanel()
  }
  onPrefillTokSChanged: {
    prefillHist = pushHist(prefillHist, prefillTokS)
    injectPanel()
  }
  onStateTextChanged: {
    if (stateText === "error" && startRequested) startRequested = false
    injectPanel()
  }
  onServerLaunchStateChanged: injectPanel()
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

  // zero-width probe at the chip's horizontal centre: the popup centres on this
  Item {
    id: anchorProbe
    x: chip.width / 2
    y: 0
    width: 0
    height: chip.height
  }

  // ---------- cyberpunk bar chip ----------
  Rectangle {
    id: chip
    implicitWidth: row.implicitWidth + Style.space(16)
    implicitHeight: Math.max(Style.bar.iconSlot, row.implicitHeight + Style.space(8))
    color: hover.hovered ? Qt.rgba(0, 0.94, 1, 0.12) : Qt.rgba(0.02, 0.02, 0.06, 0.55)
    radius: 3
    border.width: 1
    border.color: Qt.rgba(root.chipAccent.r, root.chipAccent.g, root.chipAccent.b, hover.hovered ? 0.9 : 0.55)

    Row {
      id: row
      anchors.centerIn: parent
      spacing: Style.space(6)

      Rectangle {
        width: 3
        height: Math.round(chip.height * 0.45)
        color: root.chipAccent
        radius: 1
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: root.serverOnline ? String(root.modelName).toUpperCase() : (root.stateText === "error" ? "! STRATA" : (root.serverLaunchState === "starting" ? "◌ STRATA" : "▶ STRATA"))
        color: root.chipAccent
        font.family: root.cyberFont
        font.pixelSize: 11
        font.bold: true
        font.letterSpacing: 0.8
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        visible: root.serverOnline
        text: "·"
        color: root.cyberDim
        font.family: root.cyberFont
        font.pixelSize: 11
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        visible: root.serverOnline
        text: root.chipRate + " t/s"
        color: root.cyberWhite
        font.family: root.cyberFont
        font.pixelSize: 11
        font.bold: true
      }

      Canvas {
        visible: root.serverOnline && root.genHist.length > 1
        width: Style.space(38)
        height: Math.round(chip.height * 0.5)
        anchors.verticalCenter: parent.verticalCenter
        onPaint: {
          var ctx = getContext("2d")
          ctx.reset()
          var vals = root.genHist
          if (vals.length < 2) return
          var maxV = 1
          for (var i = 0; i < vals.length; i++) if (vals[i] > maxV) maxV = vals[i]
          ctx.strokeStyle = root.cyberCyan
          ctx.lineWidth = 1.2
          ctx.beginPath()
          for (var j = 0; j < vals.length; j++) {
            var x = width * (j / (vals.length - 1))
            var y = height - (height - 2) * (vals[j] / maxV)
            if (j === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y)
          }
          ctx.stroke()
        }
        onWidthChanged: requestPaint()
        Connections { target: root; function onGenHistChanged() { requestPaint() } }
      }
    }

    HoverHandler { id: hover; onHoveredChanged: { if (hovered) root.hoverTip(); else if (root.bar) root.bar.hideTooltip(root) } }

    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
      onClicked: function(mouse) {
        if (mouse.button === Qt.MiddleButton) root.refresh()
        else if (mouse.button === Qt.RightButton) root.togglePanel()
        else if (!root.serverOnline && root.serverLaunchState !== "starting" && root.serverLaunchState !== "stopping") root.requestStart()
        else root.togglePanel()
      }
    }
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
}
