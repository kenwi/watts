import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "local.watts"

  property string status: ""
  property int capacity: -1
  property real watts: 0
  property string timeRemaining: ""
  // Own popup: bar.showTooltip() always clears + delays, and the third-party
  // facade has no way to update text in place.
  property bool tipShown: false

  readonly property bool charging: status === "Charging"
  readonly property bool discharging: status === "Discharging"
  // Plain unicode arrows keep predictable text metrics in any font.
  readonly property string arrow: charging ? "↑" : (discharging ? "↓" : "")
  readonly property string label: arrow + (arrow !== "" ? " " : "") + watts.toFixed(1) + " W"
  readonly property string tooltipText: {
    var parts = [root.status, root.capacity + "%", root.watts.toFixed(2) + " W"]
    if (root.timeRemaining !== "") parts.push(root.timeRemaining)
    return parts.join(" • ")
  }

  // Toggle with: omarchy bar set local.watts enabled false   (or true)
  readonly property bool widgetEnabled: {
    var v = setting("enabled", true)
    return v !== false && v !== "false"
  }

  visible: capacity >= 0 && !vertical && widgetEnabled
  // Floor width to a wide sample label so digit changes do not shrink the
  // MouseArea and fire a leave/enter cycle.
  implicitWidth: visible ? Math.max(labelText.implicitWidth, widthProbe.implicitWidth) + Style.spacing.controlPaddingX * 2 : 0
  implicitHeight: barSize
  readonly property bool tooltipHovered: visible && mouseArea.containsMouse

  function formatDuration(hours) {
    if (!(hours > 0) || !isFinite(hours)) return ""
    var totalMinutes = Math.round(hours * 60)
    var h = Math.floor(totalMinutes / 60)
    var m = totalMinutes % 60
    if (h > 0) return h + "h " + m + "m"
    return Math.max(1, m) + "m"
  }

  // energy_* is µWh, power_now is µW → hours = energy / power
  function estimateTimeRemaining(statusText, energyNow, energyFull, powerNow) {
    if (!(powerNow > 0)) return ""
    var hours = 0
    var suffix = ""
    if (statusText === "Discharging") {
      hours = energyNow / powerNow
      suffix = " remaining"
    } else if (statusText === "Charging") {
      hours = (energyFull - energyNow) / powerNow
      suffix = " until full"
    } else {
      return ""
    }
    var formatted = formatDuration(hours)
    return formatted !== "" ? formatted + suffix : ""
  }

  function armTooltip() {
    hideTipTimer.stop()
    if (root.tooltipText === "") return
    if (root.tipShown) return
    showTipTimer.restart()
  }

  function scheduleHideTooltip() {
    showTipTimer.stop()
    hideTipTimer.restart()
  }

  function closeTooltip() {
    showTipTimer.stop()
    hideTipTimer.stop()
    root.tipShown = false
  }

  onVisibleChanged: if (!visible) root.closeTooltip()
  onTooltipTextChanged: {
    // Keep an open tip alive when text clears briefly; close only on leave.
    if (root.tipShown && root.tooltipText === "") root.tipShown = false
  }

  Timer {
    id: showTipTimer
    interval: 400
    onTriggered: {
      if (root.tooltipHovered && root.tooltipText !== "")
        root.tipShown = true
    }
  }

  Timer {
    id: hideTipTimer
    interval: 120
    onTriggered: {
      if (root.tooltipHovered) return
      root.tipShown = false
    }
  }

  Timer {
    interval: 5000
    running: root.widgetEnabled
    triggeredOnStart: true
    repeat: true
    onTriggered: probe.running = true
  }

  Process {
    id: probe
    command: ["sh", "-c", "cat /sys/class/power_supply/BAT0/status /sys/class/power_supply/BAT0/capacity /sys/class/power_supply/BAT0/power_now /sys/class/power_supply/BAT0/energy_now /sys/class/power_supply/BAT0/energy_full 2>/dev/null"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var lines = String(text || "").trim().split("\n")
        if (lines.length < 5 || lines[1] === "") return
        var statusText = lines[0].trim()
        var energyNow = parseInt(lines[3])
        var energyFull = parseInt(lines[4])
        var powerNow = parseInt(lines[2])
        root.status = statusText
        root.capacity = parseInt(lines[1])
        root.watts = powerNow / 1000000
        root.timeRemaining = root.estimateTimeRemaining(statusText, energyNow, energyFull, powerNow)
      }
    }
  }

  Item {
    anchors.fill: parent
    anchors.leftMargin: Style.space(8)
    anchors.rightMargin: Style.space(8)

    Text {
      id: widthProbe
      visible: false
      text: "↓ 99.9 W"
      font.family: labelText.font.family
      font.pixelSize: labelText.font.pixelSize
    }

    Text {
      id: labelText
      anchors.centerIn: parent
      text: root.label
      color: root.bar ? root.bar.barForeground : Color.foreground
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.body
    }
  }

  MouseArea {
    id: mouseArea
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor

    onClicked: function(mouse) {
      if (mouse.button === Qt.LeftButton) probe.running = true
    }
    onEntered: root.armTooltip()
    onExited: root.scheduleHideTooltip()
  }

  PopupWindow {
    id: tipWindow
    visible: root.tipShown && root.tooltipText !== ""
    color: "transparent"
    implicitWidth: Math.ceil(tipBubble.implicitWidth)
    implicitHeight: Math.ceil(tipBubble.implicitHeight)

    anchor {
      id: tipAnchor
      window: root.QsWindow ? root.QsWindow.window : null
      adjustment: PopupAdjustment.Slide
      edges: Edges.Top | Edges.Left
      gravity: Edges.Bottom | Edges.Right
      rect.width: 1
      rect.height: 1

      onAnchoring: {
        var win = root.QsWindow ? root.QsWindow.window : null
        if (!win) return

        var popupWidth = tipWindow.implicitWidth
        var popupHeight = tipWindow.implicitHeight
        var localX = root.width / 2 - popupWidth / 2
        var localY = root.height + 6
        var pos = root.bar ? root.bar.position : "top"

        if (pos === "bottom") {
          localY = -popupHeight - 6
        } else if (pos === "left") {
          localX = root.width + 6
          localY = root.height / 2 - popupHeight / 2
        } else if (pos === "right") {
          localX = -popupWidth - 6
          localY = root.height / 2 - popupHeight / 2
        }

        var point = win.contentItem.mapFromItem(root, localX, localY)
        tipAnchor.rect.x = Math.round(point.x)
        tipAnchor.rect.y = Math.round(point.y)
      }
    }

    BorderSurface {
      id: tipBubble
      implicitWidth: tipLabel.implicitWidth + 20
      implicitHeight: tipLabel.implicitHeight + 14
      color: Color.tooltip.background
      borderSpec: Border.surfaceSpec("tooltip", "border", Color.tooltip.border, 1)
      radius: Style.cornerRadius

      Text {
        id: tipLabel
        textFormat: Text.PlainText
        anchors.centerIn: parent
        text: root.tooltipText
        color: Color.tooltip.text
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.body
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
      }
    }
  }
}
