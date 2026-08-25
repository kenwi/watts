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

  readonly property bool charging: status === "Charging"
  readonly property bool discharging: status === "Discharging"
  // Plain unicode arrows keep predictable text metrics in any font.
  readonly property string arrow: charging ? "↑" : (discharging ? "↓" : "")
  readonly property string label: arrow + (arrow !== "" ? " " : "") + watts.toFixed(1) + " W"

  // Toggle with: omarchy bar set local.watts enabled false   (or true)
  readonly property bool widgetEnabled: {
    var v = setting("enabled", true)
    return v !== false && v !== "false"
  }

  visible: capacity >= 0 && !vertical && widgetEnabled
  implicitWidth: visible ? labelText.implicitWidth + Style.spacing.controlPaddingX * 2 : 0
  implicitHeight: barSize
  readonly property bool tooltipHovered: visible && mouseArea.containsMouse

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
    command: ["sh", "-c", "cat /sys/class/power_supply/BAT0/status /sys/class/power_supply/BAT0/capacity /sys/class/power_supply/BAT0/power_now 2>/dev/null"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var lines = String(text || "").trim().split("\n")
        if (lines.length < 3 || lines[1] === "") return
        root.status = lines[0].trim()
        root.capacity = parseInt(lines[1])
        root.watts = parseInt(lines[2]) / 1000000
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
    onEntered: if (root.bar) root.bar.showTooltip(root, root.status + " • " + root.capacity + "% • " + root.watts.toFixed(2) + " W")
    onExited: if (root.bar) root.bar.hideTooltip(root)
  }
}

