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
  implicitWidth: visible ? labelText.implicitWidth + Style.spacing.controlPaddingX * 2 : 0
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

  function refreshTooltip() {
    if (root.tooltipHovered && root.bar)
      root.bar.showTooltip(root, root.tooltipText)
  }

  onVisibleChanged: if (!visible && root.bar) root.bar.hideTooltip(root)

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
        root.refreshTooltip()
      }
    }
  }

  Item {
    anchors.fill: parent
    anchors.leftMargin: Style.space(8)
    anchors.rightMargin: Style.space(8)

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
    onEntered: if (root.bar) root.bar.showTooltip(root, root.tooltipText)
    onExited: if (root.bar) root.bar.hideTooltip(root)
  }
}

