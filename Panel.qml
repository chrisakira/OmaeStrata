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
  property string sshTarget: "local"
  property int refreshSeconds: 10
  property string processPattern: "strata"
  property string startScript: ""
  property string connectionMode: "local"
  property string serverLaunchState: "idle"
  property var generationTokS: null
  property var prefillTokS: null
  property string serverLaunchError: ""
  property var genHist: []
  property var prefillHist: []
  property var ramHist: []
  property var cpuHist: []

  readonly property bool serverRunning: !!(snapshot && snapshot.online)
  readonly property real panelWidth: Style.space(360)

  // cyberpunk palette
  readonly property color ink: "#05040F"
  readonly property color card: "#0A0A18"
  readonly property color cyan: "#00F0FF"
  readonly property color magenta: "#FF2E88"
  readonly property color amber: "#FFD166"
  readonly property color white: "#E8FBFF"
  readonly property color dim: "#4A6B78"
  readonly property color track: "#141C26"
  readonly property string mono: "monospace"

  readonly property string modelName: snapshot && snapshot.online ? String(snapshot.model || "MODEL") : "STRATA"
  readonly property string statusText: stateText === "error" ? "OFFLINE" : (serverRunning ? "ONLINE" : "STANDBY")
  readonly property color statusColor: stateText === "error" ? Color.urgent : (serverRunning ? cyan : magenta)
  readonly property string startLabel: serverLaunchState === "starting" ? "BOOTING" : (serverLaunchState === "error" && !serverRunning ? "RETRY" : "START")
  readonly property string stopLabel: serverLaunchState === "stopping" ? "STOPPING" : "STOP"
  readonly property bool startBusy: serverLaunchState === "starting" || serverLaunchState === "stopping"
  readonly property bool stopBusy: serverLaunchState === "stopping"
  readonly property bool canStart: !serverRunning && !startBusy
  readonly property bool canStop: (serverRunning || serverLaunchState === "starting") && !stopBusy

  function refresh() { if (hostWidget && hostWidget.refresh) hostWidget.refresh() }
  function startServer() { if (hostWidget && hostWidget.startServer) hostWidget.startServer() }
  function stopServer() { if (hostWidget && hostWidget.stopServer) hostWidget.stopServer() }
  function rateNumber(v) { return v === null || v === undefined ? "--" : Number(v).toFixed(1) }
  function toggle() { if (opened) close(); else open() }
  function open() { controller.show(); refresh() }
  function close() { controller.hide() }
  function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }
  function pct(v) { return v === null || v === undefined ? "--" : Math.round(Number(v)) + "%" }

  // ---------- components ----------
  component Spark: Item {
    id: sp
    property var values: []
    property color tint: root.cyan
    property bool fillBelow: true
    implicitHeight: Style.space(30)

    Canvas {
      id: cv
      anchors.fill: parent
      onPaint: {
        var ctx = getContext("2d")
        ctx.reset()
        var w = width, h = height
        if (w <= 0 || h <= 0) return

        // grid
        ctx.strokeStyle = Qt.rgba(root.cyan.r, root.cyan.g, root.cyan.b, 0.10)
        ctx.lineWidth = 1
        for (var g = 1; g <= 2; g++) {
          var gy = h * g / 3
          ctx.beginPath(); ctx.moveTo(0, gy); ctx.lineTo(w, gy); ctx.stroke()
        }

        var vals = sp.values || []
        if (vals.length < 2) return
        var maxV = 1
        for (var i = 0; i < vals.length; i++) if (vals[i] > maxV) maxV = vals[i]

        function px(j) { return w * (j / (vals.length - 1)) }
        function py(v) { return h - 2 - (h - 6) * (v / maxV) }

        if (sp.fillBelow) {
          var grad = ctx.createLinearGradient(0, 0, 0, h)
          grad.addColorStop(0, Qt.rgba(sp.tint.r, sp.tint.g, sp.tint.b, 0.35))
          grad.addColorStop(1, Qt.rgba(sp.tint.r, sp.tint.g, sp.tint.b, 0.02))
          ctx.fillStyle = grad
          ctx.beginPath()
          ctx.moveTo(0, h)
          for (var k = 0; k < vals.length; k++) ctx.lineTo(px(k), py(vals[k]))
          ctx.lineTo(w, h)
          ctx.closePath()
          ctx.fill()
        }

        ctx.shadowColor = sp.tint
        ctx.shadowBlur = 6
        ctx.strokeStyle = sp.tint
        ctx.lineWidth = 1.6
        ctx.beginPath()
        for (var j2 = 0; j2 < vals.length; j2++) {
          if (j2 === 0) ctx.moveTo(px(j2), py(vals[j2])); else ctx.lineTo(px(j2), py(vals[j2]))
        }
        ctx.stroke()
        ctx.shadowBlur = 0
      }
      Component.onCompleted: requestPaint()
      onWidthChanged: requestPaint()
      onHeightChanged: requestPaint()
    }
    Connections { target: sp; function onValuesChanged() { cv.requestPaint() } }
  }

  component Seg: Row {
    id: seg
    property real ratio: 0
    property color tint: root.cyan
    property int segs: 14
    property real segHeight: Style.space(7)
    spacing: 2
    height: segHeight

    Repeater {
      model: seg.segs
      delegate: Rectangle {
        height: seg.segHeight
        width: Math.max(2, (seg.width - seg.spacing * (seg.segs - 1)) / seg.segs)
        radius: 1
        property bool lit: (index + 1) / seg.segs <= Math.max(0, Math.min(1, seg.ratio))
        color: lit ? (seg.ratio > 0.85 ? root.amber : seg.tint)
                   : Qt.rgba(root.track.r, root.track.g, root.track.b, 0.9)
        opacity: lit ? 1 : 0.85
        Behavior on color { ColorAnimation { duration: Style.duration(160) } }
      }
    }
  }

  component Card: Rectangle {
    id: cardRoot
    property string title: ""
    property color accent: root.cyan
    default property alias body: bodyItem.children
    property real cardHeight: Style.space(74)
    height: cardHeight
    radius: 4
    color: Qt.rgba(root.card.r, root.card.g, root.card.b, 0.92)
    border.width: 1
    border.color: Qt.rgba(root.cyan.r, root.cyan.g, root.cyan.b, 0.22)

    Rectangle {
      width: Style.space(26)
      height: 2
      color: cardRoot.accent
      radius: 1
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.leftMargin: Style.space(8)
      anchors.topMargin: -1
    }

    Column {
      id: bodyItem
      x: Style.space(10)
      y: Style.space(9)
      width: parent.width - Style.space(20)
      spacing: Style.space(5)
    }
  }

  component NeonKey: Rectangle {
    id: key
    property string label: ""
    property color tint: root.cyan
    property bool enabledKey: true
    signal activated()
    height: Style.space(30)
    radius: 3
    color: area.containsMouse && enabledKey ? Qt.rgba(tint.r, tint.g, tint.b, 0.14) : "transparent"
    border.width: 1
    border.color: Qt.rgba(tint.r, tint.g, tint.b, enabledKey ? 0.65 : 0.18)
    opacity: enabledKey ? 1 : 0.45

    Text {
      anchors.centerIn: parent
      text: key.label
      color: key.enabledKey ? key.tint : root.dim
      font.family: root.mono
      font.pixelSize: 11
      font.bold: true
      font.letterSpacing: 1.4
    }
    MouseArea {
      id: area
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      enabled: key.enabledKey
      onClicked: key.activated()
    }
  }

  KeyboardPanel {
    id: popup
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    centerOnBar: false
    focusTarget: keyCatcher
    padding: Style.spacing.md
    contentWidth: popup.fittedContentWidth(root.panelWidth + popup.padding * 2)
    contentHeight: popup.fittedContentHeight(content.childrenRect.height + Style.space(8))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) {
        if (root.bar && typeof root.bar.switchPanelFrom === "function") root.bar.switchPanelFrom(root.hostWidget || root, direction)
      }
      onReturnRequested: root.refresh()
      onTextKey: function(t) { if (t === "r" || t === "R") root.refresh() }

      Rectangle {
        anchors.fill: parent
        anchors.margins: -popup.padding
        color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.96)
        radius: Style.cornerRadius
        border.width: 1
        border.color: Qt.rgba(root.cyan.r, root.cyan.g, root.cyan.b, 0.25)
        z: -1
      }

      Column {
        id: content
        width: parent.width
        spacing: Style.space(10)
        anchors.top: parent.top

        // ---------- header ----------
        Item {
          width: parent.width
          height: Math.max(titleCol.implicitHeight, pill.implicitHeight)

          Column {
            id: titleCol
            anchors.left: parent.left
            anchors.right: pill.left
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            spacing: 0

            Text {
              text: "STRATA // " + (root.snapshot && root.snapshot.online ? String(root.modelName).toUpperCase() : "OFFLINE")
              textFormat: Text.PlainText
              elide: Text.ElideRight
              width: parent.width
              color: root.white
              font.family: root.mono
              font.pixelSize: Style.font.heading
              font.bold: true
              font.letterSpacing: 1.2
            }
            Text {
              text: (root.connectionMode === "local" ? "LOCAL" : "SSH · " + root.sshTarget) + "  ·  REFRESH " + root.refreshSeconds + "S  ·  R"
              textFormat: Text.PlainText
              elide: Text.ElideRight
              width: parent.width
              color: root.dim
              font.family: root.mono
              font.pixelSize: 9
              font.letterSpacing: 1
            }
          }

          Rectangle {
            id: pill
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: pillLabel.implicitWidth + Style.space(18)
            height: pillLabel.implicitHeight + Style.space(10)
            radius: 3
            color: Qt.rgba(root.statusColor.r, root.statusColor.g, root.statusColor.b, 0.12)
            border.width: 1
            border.color: Qt.rgba(root.statusColor.r, root.statusColor.g, root.statusColor.b, 0.7)

            Text {
              id: pillLabel
              anchors.centerIn: parent
              text: (root.serverRunning ? "● " : "○ ") + root.statusText
              color: root.statusColor
              font.family: root.mono
              font.pixelSize: 9
              font.bold: true
              font.letterSpacing: 1.2
            }
          }
        }

        // ---------- throughput ----------
        Row {
          width: parent.width
          spacing: Style.space(8)

          Card {
            width: (parent.width - parent.spacing) / 2
            cardHeight: Style.space(88)
            accent: root.cyan

            Text {
              text: "GEN TOK/S"
              color: root.dim
              font.family: root.mono
              font.pixelSize: 9
              font.letterSpacing: 1.6
            }
            Text {
              text: root.rateNumber(root.generationTokS)
              color: root.generationTokS === null || root.generationTokS === undefined ? root.dim : root.cyan
              font.family: root.mono
              font.pixelSize: 26
              font.bold: true
              font.letterSpacing: 0.5
            }
            Spark {
              width: parent.width
              values: root.genHist
              tint: root.cyan
            }
            Text {
              visible: !root.serverOnline
              text: "AWAITING TELEMETRY"
              color: root.dim
              font.family: root.mono
              font.pixelSize: 8
              font.letterSpacing: 1.4
            }

          }

          Card {
            width: (parent.width - parent.spacing) / 2
            cardHeight: Style.space(88)
            accent: root.magenta

            Text {
              text: "PREFILL TOK/S"
              color: root.dim
              font.family: root.mono
              font.pixelSize: 9
              font.letterSpacing: 1.6
            }
            Text {
              text: root.rateNumber(root.prefillTokS)
              color: root.prefillTokS === null || root.prefillTokS === undefined ? root.dim : root.magenta
              font.family: root.mono
              font.pixelSize: 26
              font.bold: true
              font.letterSpacing: 0.5
            }
            Spark {
              width: parent.width
              values: root.prefillHist
              tint: root.magenta
            }
            Text {
              visible: !root.serverOnline
              text: "AWAITING TELEMETRY"
              color: root.dim
              font.family: root.mono
              font.pixelSize: 8
              font.letterSpacing: 1.4
            }

          }
        }

        // ---------- RAM ----------
        Card {
          width: parent.width
          cardHeight: Style.space(108)
          accent: root.magenta

          Item {
            width: parent.width
            height: ramValue.implicitHeight
            Text {
              text: "RAM"
              color: root.dim
              font.family: root.mono
              font.pixelSize: 9
              font.letterSpacing: 1.6
              anchors.left: parent.left
              anchors.bottom: parent.bottom
            }
            Text {
              id: ramValue
              text: root.snapshot ? root.pct(root.snapshot.ram) : "--"
              color: root.white
              font.family: root.mono
              font.pixelSize: 20
              font.bold: true
              anchors.right: parent.right
            }
          }
          Seg {
            width: parent.width
            ratio: Model.fillRatio(root.snapshot ? root.snapshot.ram : 0)
            tint: root.magenta
            segs: 18
          }
          Spark {
            width: parent.width
            values: root.ramHist
            tint: root.magenta
            implicitHeight: Style.space(26)
          }
        }

        // ---------- CPU / DISK ----------
        Row {
          width: parent.width
          spacing: Style.space(8)

          Card {
            width: (parent.width - parent.spacing) / 2
            cardHeight: Style.space(88)
            accent: root.cyan

            Item {
              width: parent.width
              height: cpuValue.implicitHeight
              Text {
                text: "CPU"
                color: root.dim
                font.family: root.mono
                font.pixelSize: 9
                font.letterSpacing: 1.6
                anchors.left: parent.left
                anchors.bottom: parent.bottom
              }
              Text {
                id: cpuValue
                text: root.snapshot ? root.pct(root.snapshot.cpu) : "--"
                color: root.white
                font.family: root.mono
                font.pixelSize: 15
                font.bold: true
                anchors.right: parent.right
              }
            }
            Seg {
              width: parent.width
              ratio: Model.fillRatio(root.snapshot ? root.snapshot.cpu : 0)
              tint: root.cyan
              segs: 10
            }
            Spark {
              width: parent.width
              values: root.cpuHist
              tint: root.cyan
              implicitHeight: Style.space(16)
            }
          }

          Card {
            width: (parent.width - parent.spacing) / 2
            cardHeight: Style.space(66)
            accent: root.amber

            Item {
              width: parent.width
              height: diskValue.implicitHeight
              Text {
                text: "DISK"
                color: root.dim
                font.family: root.mono
                font.pixelSize: 9
                font.letterSpacing: 1.6
                anchors.left: parent.left
                anchors.bottom: parent.bottom
              }
              Text {
                id: diskValue
                text: root.snapshot ? root.pct(root.snapshot.disk) : "--"
                color: root.white
                font.family: root.mono
                font.pixelSize: 15
                font.bold: true
                anchors.right: parent.right
              }
            }
            Seg {
              width: parent.width
              ratio: Model.fillRatio(root.snapshot ? root.snapshot.disk : 0)
              tint: root.amber
              segs: 10
            }
          }
        }

        // ---------- GPUs ----------
        Repeater {
          model: root.snapshot ? root.snapshot.gpus : []
          delegate: Card {
            width: content.width
            cardHeight: Style.space(88)
            accent: root.cyan

            Item {
              width: parent.width
              height: gpuName.implicitHeight
              Text {
                id: gpuName
                text: Model.gpuSectionTitle(index, modelData.name).toUpperCase()
                textFormat: Text.PlainText
                elide: Text.ElideRight
                width: parent.width - gpuTemp.implicitWidth - Style.space(8)
                color: root.white
                font.family: root.mono
                font.pixelSize: 10
                font.bold: true
                font.letterSpacing: 1.2
              }
              Text {
                id: gpuTemp
                text: Model.tempLabel(modelData.temperature)
                color: root.amber
                font.family: root.mono
                font.pixelSize: 10
                anchors.right: parent.right
              }
            }
            Row {
              width: parent.width
              spacing: Style.space(8)
              Text {
                text: "UTIL " + Model.percent(modelData.utilization)
                color: root.dim
                font.family: root.mono
                font.pixelSize: 9
                width: Style.space(64)
              }
              Seg {
                width: parent.width - Style.space(64) - parent.spacing
                ratio: Model.fillRatio(modelData.utilization)
                tint: root.cyan
                segs: 12
              }
            }
            Row {
              width: parent.width
              spacing: Style.space(8)
              Text {
                text: "VRAM " + Model.memoryPercent(modelData)
                color: root.dim
                font.family: root.mono
                font.pixelSize: 9
                width: Style.space(64)
              }
              Seg {
                width: parent.width - Style.space(64) - parent.spacing
                ratio: Model.fillRatio(modelData.memoryUsed, modelData.memoryTotal)
                tint: root.magenta
                segs: 12
              }
            }
          }
        }

        // ---------- actions ----------
        Row {
          width: parent.width
          spacing: Style.space(8)

          NeonKey {
            width: (parent.width - parent.spacing) / 2
            label: "▶ " + root.startLabel
            tint: root.cyan
            enabledKey: root.canStart
            onActivated: root.startServer()
          }
          NeonKey {
            width: (parent.width - parent.spacing) / 2
            label: "■ " + root.stopLabel
            tint: root.magenta
            enabledKey: root.canStop
            onActivated: root.stopServer()
          }
        }

        // ---------- errors ----------
        Text {
          visible: root.serverLaunchState === "error"
          width: parent.width
          text: root.serverLaunchError || "Start/stop failed."
          textFormat: Text.PlainText
          wrapMode: Text.Wrap
          color: Color.urgent
          font.family: root.mono
          font.pixelSize: 10
        }
        Text {
          visible: root.snapshot && root.snapshot.error !== ""
          width: parent.width
          text: "GPU metrics unavailable: " + (root.snapshot ? root.snapshot.error : "")
          textFormat: Text.PlainText
          wrapMode: Text.Wrap
          color: Color.urgent
          font.family: root.mono
          font.pixelSize: 10
        }

      }
    }
  }
}
