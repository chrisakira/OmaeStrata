import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "io.github.akira.omaestrata"
  ipcTarget: "io.github.akira.omaestrata"
  manageIpc: false
  property var anchorItem: null
  property var hostWidget: null
  property var snapshot: null
  property string stateText: "connecting"
  property string sshTarget: "akira@192.168.1.168"
  property int refreshSeconds: 10
  property string processPattern: "strata"
  property string startScript: "/home/akira/Strata/run-iq3_s.sh"
  property string connectionMode: "ssh"
  property string serverLaunchState: "idle"
  property var generationTokS: null
  property var prefillTokS: null
  property string serverLaunchError: ""
  readonly property bool serverRunning: !!(snapshot && snapshot.online)
  readonly property real panelWidth: Style.space(352)
  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(fg, 1.5)
  readonly property color accent: Color.accent
  readonly property color card: Qt.rgba(fg.r, fg.g, fg.b, 0.20)
  readonly property color track: Qt.rgba(0, 0, 0, 0.38)
  readonly property var cardBorder: Border.flat(Qt.rgba(fg.r, fg.g, fg.b, 0.28), 1)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property string modelName: snapshot && snapshot.online ? snapshot.model : "—"
  readonly property string startLabel: serverLaunchState === "starting" ? "Starting…" : (serverLaunchState === "error" && !serverRunning ? "Retry start" : "Start")
  readonly property string stopLabel: serverLaunchState === "stopping" ? "Stopping…" : "Stop"
  readonly property bool startBusy: serverLaunchState === "starting" || serverLaunchState === "stopping"
  readonly property bool stopBusy: serverLaunchState === "stopping"
  readonly property bool canStart: !serverRunning && !startBusy
  readonly property bool canStop: (serverRunning || serverLaunchState === "starting") && !stopBusy

  function refresh() { if (hostWidget && hostWidget.refresh) hostWidget.refresh() }
  function startServer() { if (hostWidget && hostWidget.startServer) hostWidget.startServer() }
  function stopServer() { if (hostWidget && hostWidget.stopServer) hostWidget.stopServer() }
  function rateNumber(value) { return value === null || value === undefined ? "—" : Number(value).toFixed(1) }
  function toggle() { if (opened) close(); else open() }
  function open() { controller.show(); refresh() }
  function close() { controller.hide() }
  function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

  component StatMeter: Column {
    id: meter
    property string label: ""
    property string valueText: ""
    property real ratio: 0
    width: parent ? parent.width : 0
    spacing: Style.space(5)

    Item {
      width: parent.width
      height: Math.max(meterLabel.implicitHeight, meterValue.implicitHeight)
      Text {
        id: meterLabel
        text: meter.label
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
      }
      Text {
        id: meterValue
        text: meter.valueText
        textFormat: Text.PlainText
        color: root.fg
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
      }
    }
    Item {
      width: parent.width
      height: Style.space(8)
      Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: root.track
      }
      Rectangle {
        height: parent.height
        implicitWidth: parent.width * Math.max(0, Math.min(1, meter.ratio))
        width: implicitWidth
        radius: height / 2
        color: root.accent
        Behavior on width {
          NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
        }
      }
    }
  }

  KeyboardPanel {
    id: popup
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    padding: Style.spacing.md
    contentWidth: popup.fittedContentWidth(root.panelWidth + popup.padding * 2)
    contentHeight: popup.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) {
        if (root.bar && typeof root.bar.switchPanelFrom === "function") root.bar.switchPanelFrom(root.hostWidget || root, direction)
      }
      onReturnRequested: root.refresh()
      onTextKey: function(t) { if (t === "r" || t === "R") root.refresh() }

      Column {
        id: content
        width: parent.width
        spacing: Style.space(12)
        anchors.top: parent.top

        Item {
          width: parent.width
          height: Math.max(modelTitle.implicitHeight, statusPill.implicitHeight)

          Text {
            id: modelTitle
            text: root.modelName
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: root.fg
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            anchors.left: parent.left
            anchors.right: statusPill.left
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
          }

          BorderSurface {
            id: statusPill
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            implicitWidth: statusLabel.implicitWidth + Style.space(14)
            implicitHeight: statusLabel.implicitHeight + Style.space(8)
            radius: height / 2
            color: root.stateText === "error" ? root.alpha(Color.urgent, 0.16) : (root.serverRunning ? root.alpha(root.accent, 0.18) : root.card)
            borderSpec: Border.none()

            Text {
              id: statusLabel
              anchors.centerIn: parent
              text: Model.statusLabel(root.snapshot, root.stateText)
              textFormat: Text.PlainText
              color: root.stateText === "error" ? Color.urgent : (root.serverRunning ? root.accent : root.dim)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }
          }
        }

        Row {
          width: parent.width
          spacing: Style.space(8)

          BorderSurface {
            width: (parent.width - parent.spacing) / 2
            implicitHeight: genCol.implicitHeight + Style.space(18)
            radius: Style.cornerRadius
            color: root.card
            borderSpec: root.cardBorder
            Column {
              id: genCol
              x: Style.space(10)
              y: Style.space(9)
              width: parent.width - Style.space(20)
              spacing: Style.space(2)
              Text {
                text: root.rateNumber(root.generationTokS)
                textFormat: Text.PlainText
                color: root.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
              }
              Text {
                text: "gen tok/s"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }

          BorderSurface {
            width: (parent.width - parent.spacing) / 2
            implicitHeight: prefillCol.implicitHeight + Style.space(18)
            radius: Style.cornerRadius
            color: root.card
            borderSpec: root.cardBorder
            Column {
              id: prefillCol
              x: Style.space(10)
              y: Style.space(9)
              width: parent.width - Style.space(20)
              spacing: Style.space(2)
              Text {
                text: root.rateNumber(root.prefillTokS)
                textFormat: Text.PlainText
                color: root.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
              }
              Text {
                text: "prefill tok/s"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }
        }

        Row {
          width: parent.width
          spacing: Style.space(8)

          Button {
            width: (parent.width - parent.spacing) / 2
            text: root.startLabel
            iconText: root.serverLaunchState === "starting" ? "◌" : "▶"
            iconSpinning: root.serverLaunchState === "starting"
            bordered: true
            leftAlign: true
            active: false
            enabled: root.canStart
            tooltipText: root.serverRunning ? "Strata is already running" : (root.connectionMode === "local" ? "Run " + root.startScript : "SSH to " + root.sshTarget + " and run " + root.startScript)
            onClicked: root.startServer()
          }

          Button {
            width: (parent.width - parent.spacing) / 2
            text: root.stopLabel
            iconText: root.serverLaunchState === "stopping" ? "◌" : "■"
            iconSpinning: root.serverLaunchState === "stopping"
            bordered: true
            leftAlign: true
            active: root.serverRunning
            enabled: root.canStop
            tooltipText: !root.serverRunning && root.serverLaunchState !== "starting" ? "Strata is not running" : (root.connectionMode === "local" ? "Stop the local Strata server" : "SSH to " + root.sshTarget + " and stop Strata")
            onClicked: root.stopServer()
          }
        }

        BorderSurface {
          width: parent.width
          implicitHeight: cpuBody.implicitHeight + Style.space(20)
          radius: Style.cornerRadius
          color: root.card
          borderSpec: root.cardBorder
          Column {
            id: cpuBody
            x: Style.space(10)
            y: Style.space(10)
            width: parent.width - Style.space(20)
            spacing: Style.space(8)
            PanelSectionHeader {
              width: parent.width
              text: "HOST"
              foreground: root.fg
              fontFamily: root.fontFamily
            }
            StatMeter {
              label: "CPU"
              valueText: root.snapshot ? Model.percent(root.snapshot.cpu) : "—"
              ratio: Model.fillRatio(root.snapshot ? root.snapshot.cpu : 0)
            }
            StatMeter {
              label: "RAM"
              valueText: root.snapshot ? Model.percent(root.snapshot.ram) : "—"
              ratio: Model.fillRatio(root.snapshot ? root.snapshot.ram : 0)
            }
            StatMeter {
              label: "Disk"
              valueText: root.snapshot ? Model.percent(root.snapshot.disk) : "—"
              ratio: Model.fillRatio(root.snapshot ? root.snapshot.disk : 0)
            }
          }
        }

        Repeater {
          model: root.snapshot ? root.snapshot.gpus : []
          delegate: BorderSurface {
            width: content.width
            implicitHeight: gpuBody.implicitHeight + Style.space(20)
            radius: Style.cornerRadius
            color: root.card
            borderSpec: root.cardBorder
            Column {
              id: gpuBody
              x: Style.space(10)
              y: Style.space(10)
              width: parent.width - Style.space(20)
              spacing: Style.space(8)
              Item {
                width: parent.width
                height: Math.max(gpuHead.implicitHeight, gpuTemp.implicitHeight)
                PanelSectionHeader {
                  id: gpuHead
                  text: Model.gpuSectionTitle(index, modelData.name)
                  foreground: root.fg
                  fontFamily: root.fontFamily
                  anchors.left: parent.left
                  anchors.right: gpuTemp.left
                  anchors.rightMargin: Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                  id: gpuTemp
                  text: Model.tempLabel(modelData.temperature)
                  textFormat: Text.PlainText
                  color: root.fg
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                }
              }
              StatMeter {
                label: "Usage"
                valueText: Model.percent(modelData.utilization)
                ratio: Model.fillRatio(modelData.utilization)
              }
              StatMeter {
                label: "Memory"
                valueText: Model.memoryPercent(modelData)
                ratio: Model.fillRatio(modelData.memoryUsed, modelData.memoryTotal)
              }
            }
          }
        }

        Text {
          visible: root.serverLaunchState === "error"
          width: parent.width
          text: root.serverLaunchError || (root.connectionMode === "local" ? "Strata start/stop failed." : "SSH or Strata start/stop failed.")
          textFormat: Text.PlainText
          wrapMode: Text.Wrap
          color: Color.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
        Text {
          visible: root.snapshot && root.snapshot.error !== ""
          width: parent.width
          text: "GPU metrics unavailable: " + (root.snapshot ? root.snapshot.error : "")
          textFormat: Text.PlainText
          wrapMode: Text.Wrap
          color: Color.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
        Text {
          visible: root.stateText === "error"
          width: parent.width
          text: root.snapshot ? (root.connectionMode === "local" ? "Status check failed. Values above are from the last successful check." : "SSH failed. Values above are from the last successful check.") : (root.connectionMode === "local" ? "Status check failed. Confirm STRATA_ROOT and python3 on this machine." : "SSH failed. Check key-based login to " + root.sshTarget + ".")
          textFormat: Text.PlainText
          wrapMode: Text.Wrap
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        Row {
          spacing: Style.space(10)
          Text {
            text: "Refresh  R"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.refresh() }
          }
          Text {
            text: "every " + root.refreshSeconds + "s"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }
}
