import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

BarWidget {
  id: root
  moduleName: "local.watts"

  property string status: ""
  property int capacity: -1
  property real watts: 0
  property string timeShort: ""
  // Own popup tip: bar.showTooltip() always clears + delays, and the
  // third-party facade has no way to update text in place.
  property bool tipShown: false
  property bool menuOpen: false

  readonly property var metrics: Model.normalizeMetrics(setting("metrics", null), setting("display", "watts"))
  readonly property bool charging: status === "Charging"
  readonly property bool discharging: status === "Discharging"
  // Plain unicode arrows keep predictable text metrics in any font.
  readonly property string arrow: charging ? "↑" : (discharging ? "↓" : "")
  readonly property string wattsPart: arrow + (arrow !== "" ? " " : "") + watts.toFixed(1) + " W"
  readonly property string timeRemaining: {
    if (timeShort === "") return ""
    if (charging) return timeShort + " until full"
    if (discharging) return timeShort + " remaining"
    return timeShort
  }
  readonly property string label: Model.formatLabel(root.metrics, {
    wattsPart: root.wattsPart,
    capacity: root.capacity,
    timeShort: root.timeShort
  })
  readonly property string tooltipText: {
    var parts = [root.status, root.capacity + "%", root.watts.toFixed(2) + " W"]
    if (root.timeRemaining !== "") parts.push(root.timeRemaining)
    return parts.join(" • ")
  }
  readonly property color fg: root.bar ? root.bar.barForeground : Color.foreground
  readonly property string fontFamily: root.bar ? root.bar.fontFamily : Style.font.family

  // Toggle with: omarchy bar set local.watts enabled false   (or true)
  readonly property bool widgetEnabled: {
    var v = setting("enabled", true)
    return v !== false && v !== "false"
  }

  visible: capacity >= 0 && !vertical && widgetEnabled
  implicitWidth: visible ? Math.max(12, labelText.implicitWidth) + Style.space(8) * 2 : 0
  implicitHeight: barSize
  // Bar open-panel underline defaults to ~55% of the slot; span the full widget.
  readonly property real openPanelIndicatorWidth: width
  readonly property bool tooltipHovered: visible && mouseArea.containsMouse && !root.menuOpen

  function close() {
    root.menuOpen = false
  }

  function closeForPopoutSwitch() {
    root.close()
  }

  function persistMetrics(nextMetrics) {
    var entry = { id: root.moduleName }
    for (var key in root.settings) {
      if (key === "id" || key === "display") continue
      entry[key] = root.settings[key]
    }
    // Plain string survives QML plugin reload; nested arrays may not.
    entry.metrics = Model.serializeMetrics(nextMetrics)
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  // One-shot migration: rewrite nested-array metrics to the string form.
  property bool metricsMigrated: false
  function ensureMetricsPersisted() {
    if (root.metricsMigrated) return
    root.metricsMigrated = true
    var raw = setting("metrics", null)
    if (raw === null || raw === undefined) return
    if (typeof raw === "string" && raw.indexOf(":") !== -1) return
    root.persistMetrics(root.metrics)
  }

  function syncMetricsModel() {
    metricsModel.clear()
    var list = root.metrics
    for (var i = 0; i < list.length; i++) {
      metricsModel.append({
        metricId: String(list[i].id || ""),
        metricEnabled: list[i].enabled === true
      })
    }
  }

  function metricsFromModel() {
    var next = []
    for (var i = 0; i < metricsModel.count; i++) {
      var row = metricsModel.get(i)
      next.push({ id: String(row.metricId || ""), enabled: row.metricEnabled === true })
    }
    return next
  }

  function persistFromModel() {
    root.persistMetrics(root.metricsFromModel())
  }

  function toggleMetricAt(index) {
    if (index < 0 || index >= metricsModel.count) return
    var row = metricsModel.get(index)
    var enabledCount = 0
    for (var i = 0; i < metricsModel.count; i++) {
      if (metricsModel.get(i).metricEnabled) enabledCount++
    }
    if (row.metricEnabled && enabledCount <= 1) return
    metricsModel.setProperty(index, "metricEnabled", !row.metricEnabled)
    root.persistFromModel()
  }

  function formatDuration(hours) {
    if (!(hours > 0) || !isFinite(hours)) return ""
    var totalMinutes = Math.round(hours * 60)
    var h = Math.floor(totalMinutes / 60)
    var m = totalMinutes % 60
    if (h > 0) return h + "h " + m + "m"
    return Math.max(1, m) + "m"
  }

  // energy_* is µWh, power_now is µW → hours = energy / power
  function estimateTimeShort(statusText, energyNow, energyFull, powerNow) {
    if (!(powerNow > 0)) return ""
    var hours = 0
    if (statusText === "Discharging") hours = energyNow / powerNow
    else if (statusText === "Charging") hours = (energyFull - energyNow) / powerNow
    else return ""
    return formatDuration(hours)
  }

  function armTooltip() {
    if (root.menuOpen) return
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

  function toggleMenu() {
    root.closeTooltip()
    root.menuOpen = !root.menuOpen
    if (root.menuOpen) {
      root.syncMetricsModel()
      probe.running = true
    }
  }

  onVisibleChanged: {
    if (!visible) {
      root.closeTooltip()
      root.close()
    }
  }
  onBarChanged: if (root.bar) Qt.callLater(root.ensureMetricsPersisted)
  Component.onCompleted: Qt.callLater(root.ensureMetricsPersisted)
  onTooltipTextChanged: {
    if (root.tipShown && root.tooltipText === "") root.tipShown = false
  }
  onMenuOpenChanged: if (root.menuOpen) root.closeTooltip()

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
        root.timeShort = root.estimateTimeShort(statusText, energyNow, energyFull, powerNow)
      }
    }
  }

  Item {
    anchors.fill: parent
    anchors.leftMargin: Style.space(8)
    anchors.rightMargin: Style.space(8)

    Text {
      id: labelText
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      text: root.label
      color: root.fg
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }
  }

  MouseArea {
    id: mouseArea
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor

    onClicked: function(mouse) {
      if (mouse.button === Qt.LeftButton) root.toggleMenu()
    }
    onEntered: root.armTooltip()
    onExited: root.scheduleHideTooltip()
  }

  PopupWindow {
    id: tipWindow
    visible: root.tipShown && root.tooltipText !== "" && !root.menuOpen
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
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
      }
    }
  }

  ListModel {
    id: metricsModel
  }

  PopupCard {
    id: menu
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.menuOpen
    contentWidth: menu.fittedContentWidth(Style.space(320))
    contentHeight: menu.fittedContentHeight(menuColumn.implicitHeight)

    readonly property int metricRowHeight: Style.space(36)

    Column {
      id: menuColumn
      anchors.fill: parent
      spacing: Style.space(8)

      Text {
        text: "Bar metrics"
        color: root.fg
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
      }

      Text {
        text: "Toggle metrics on or off. Drag the handle to change order."
        color: Qt.darker(root.fg, 1.4)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
        width: parent.width
      }

      Item {
        id: metricsListHost
        width: parent.width
        height: Math.max(menu.metricRowHeight, metricsModel.count * menu.metricRowHeight)

        // Manual drag reorder: DropArea/Drag fires on press and shoved rows
        // to the middle. Reorder only after a movement threshold, by Y index.
        property int dragFrom: -1
        property bool dragging: false

        Column {
          id: metricsColumn
          anchors.fill: parent
          spacing: 0

          Repeater {
            model: metricsModel

            delegate: Item {
              id: metricRow
              required property string metricId
              required property bool metricEnabled
              required property int index

              width: metricsColumn.width
              height: menu.metricRowHeight

              readonly property var def: Model.metricDef(metricId)
              readonly property bool canDisable: {
                var n = 0
                for (var i = 0; i < metricsModel.count; i++) {
                  if (metricsModel.get(i).metricEnabled) n++
                }
                return !(metricEnabled && n <= 1)
              }
              readonly property bool held: metricsListHost.dragging && metricsListHost.dragFrom === index

              Rectangle {
                anchors.fill: parent
                anchors.margins: Style.space(1)
                radius: Style.cornerRadius
                color: metricRow.held ? Style.hoverFillFor(root.fg, root.fg) : "transparent"

                Row {
                  anchors.fill: parent
                  anchors.leftMargin: Style.space(4)
                  anchors.rightMargin: Style.space(4)
                  spacing: Style.space(8)

                  Item {
                    id: dragHandle
                    width: Style.space(22)
                    height: parent.height

                    Text {
                      anchors.centerIn: parent
                      text: "⠿"
                      color: Qt.darker(root.fg, metricRow.held ? 1.0 : 1.5)
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                    }

                    MouseArea {
                      anchors.fill: parent
                      preventStealing: true
                      cursorShape: metricsListHost.dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor

                      onPressed: function(mouse) {
                        metricsListHost.dragFrom = metricRow.index
                        metricsListHost.dragging = false
                        // Track press in list coordinates so threshold is absolute.
                        metricsListHost._pressY = mapToItem(metricsListHost, mouse.x, mouse.y).y
                      }

                      onPositionChanged: function(mouse) {
                        if (!pressed || metricsListHost.dragFrom < 0) return
                        var y = mapToItem(metricsListHost, mouse.x, mouse.y).y
                        if (!metricsListHost.dragging) {
                          if (Math.abs(y - metricsListHost._pressY) < 6) return
                          metricsListHost.dragging = true
                        }

                        var to = Math.floor(y / menu.metricRowHeight)
                        to = Math.max(0, Math.min(metricsModel.count - 1, to))
                        if (to === metricsListHost.dragFrom) return
                        metricsModel.move(metricsListHost.dragFrom, to, 1)
                        metricsListHost.dragFrom = to
                      }

                      onReleased: function(mouse) {
                        if (metricsListHost.dragging)
                          root.persistFromModel()
                        metricsListHost.dragging = false
                        metricsListHost.dragFrom = -1
                      }

                      onCanceled: {
                        metricsListHost.dragging = false
                        metricsListHost.dragFrom = -1
                      }
                    }
                  }

                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - dragHandle.width - toggleBtn.width - parent.spacing * 2
                    text: metricRow.def ? metricRow.def.label : metricRow.metricId
                    color: root.fg
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    elide: Text.ElideRight
                  }

                  Button {
                    id: toggleBtn
                    anchors.verticalCenter: parent.verticalCenter
                    text: metricEnabled ? "On" : "Off"
                    foreground: root.fg
                    selected: metricEnabled
                    horizontalPadding: 8
                    verticalPadding: 3
                    fontSize: Style.font.bodySmall
                    enabled: metricRow.canDisable || !metricEnabled
                    onClicked: root.toggleMetricAt(metricRow.index)
                  }
                }
              }
            }
          }
        }

        property real _pressY: 0
      }
    }
  }
}
