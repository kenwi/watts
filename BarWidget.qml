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
  // Hide metrics when battery is idle/full (only show while charging or discharging).
  readonly property bool activeOnly: Model.isEnabledFlag(setting("activeOnly", false))
  // When activeOnly hides metrics, optionally keep a clickable battery icon.
  readonly property bool idleIconEnabled: {
    var v = setting("idleIcon", "on")
    if (v === false || v === "false" || v === "off" || v === 0 || v === "0") return false
    return true
  }
  // Probe cadence in seconds (1-300). Plain number in shell.json.
  readonly property int intervalSec: {
    var n = Math.floor(Number(setting("intervalSec", 5)))
    if (!isFinite(n)) return 5
    return Math.max(1, Math.min(300, n))
  }
  // Horizontal padding around the bar label (px). Default matches Style.space(8).
  readonly property int padLeft: root.readPadPx(setting("padLeft", null))
  readonly property int padRight: root.readPadPx(setting("padRight", null))
  // Live end-threshold from sysfs (-1 until first successful probe).
  property int sysChargeLimit: -1
  property string chargeLimitError: ""
  property bool chargeLimitBusy: false
  // Preferred limit % when limiter is on. Unset → use current sysfs value.
  readonly property int chargeLimitPct: {
    var raw = setting("chargeLimitPct", null)
    if (raw === null || raw === undefined || raw === "") {
      if (root.sysChargeLimit > 0) return Math.max(50, Math.min(100, root.sysChargeLimit))
      return 80
    }
    var n = Math.floor(Number(raw))
    if (!isFinite(n)) return 80
    return Math.max(50, Math.min(100, n))
  }
  // Unset → on when the kernel already has a limit below 100%.
  readonly property bool chargeLimitEnabled: {
    var raw = setting("chargeLimit", null)
    if (raw === null || raw === undefined || raw === "")
      return root.sysChargeLimit > 0 && root.sysChargeLimit < 100
    return Model.isEnabledFlag(raw)
  }
  readonly property bool charging: status === "Charging"
  readonly property bool discharging: status === "Discharging"
  readonly property bool powerActive: charging || discharging
  readonly property bool showIdleGlyph: activeOnly && !powerActive && idleIconEnabled
  // Matches Omarchy's battery notification glyph; stays clickable for the menu.
  readonly property string idleGlyph: "󰁹"
  // Plain unicode arrows keep predictable text metrics in any font.
  readonly property string arrow: charging ? "↑" : (discharging ? "↓" : "")
  readonly property string wattsPart: watts.toFixed(1) + " W"
  readonly property string timeRemaining: {
    if (timeShort === "") return ""
    if (charging) return timeShort + " until full"
    if (discharging) return timeShort + " remaining"
    return timeShort
  }
  readonly property string label: root.showIdleGlyph
    ? root.idleGlyph
    : Model.formatLabel(root.metrics, {
        arrow: root.arrow,
        wattsPart: root.wattsPart,
        capacity: root.capacity,
        timeShort: root.timeShort
      })
  readonly property string tooltipText: {
    var parts = [root.status, root.capacity + "%", root.watts.toFixed(2) + " W"]
    if (root.timeRemaining !== "") parts.push(root.timeRemaining)
    if (root.sysChargeLimit > 0 && root.sysChargeLimit < 100)
      parts.push("limit " + root.sysChargeLimit + "%")
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
    && (!activeOnly || powerActive || idleIconEnabled || menuOpen)
  implicitWidth: visible ? Math.max(12, labelText.implicitWidth) + padLeft + padRight : 0
  implicitHeight: barSize
  // Bar open-panel underline defaults to ~55% of the slot; span the full widget.
  readonly property real openPanelIndicatorWidth: width
  readonly property bool tooltipHovered: visible && mouseArea.containsMouse && !root.menuOpen

  function readPadPx(raw) {
    if (raw === null || raw === undefined || raw === "") return Style.space(8)
    var n = Math.floor(Number(raw))
    if (!isFinite(n)) return Style.space(8)
    return Math.max(0, Math.min(400, n))
  }

  function close() {
    root.menuOpen = false
  }

  function closeForPopoutSwitch() {
    root.close()
  }

  function persistSettings(patch) {
    var entry = { id: root.moduleName }
    for (var key in root.settings) {
      if (key === "id" || key === "display") continue
      entry[key] = root.settings[key]
    }
    for (var p in patch) entry[p] = patch[p]
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function persistMetrics(nextMetrics) {
    // Plain string survives QML plugin reload; nested arrays may not.
    root.persistSettings({ metrics: Model.serializeMetrics(nextMetrics) })
  }

  function setActiveOnly(enabled) {
    root.persistSettings({ activeOnly: enabled ? "on" : "off" })
  }

  function setIdleIcon(enabled) {
    root.persistSettings({ idleIcon: enabled ? "on" : "off" })
  }

  function setIntervalSec(sec) {
    var n = Math.floor(Number(sec))
    if (!isFinite(n)) n = 5
    root.persistSettings({ intervalSec: Math.max(1, Math.min(300, n)) })
  }

  function setPadLeft(px) {
    root.persistSettings({ padLeft: root.readPadPx(px) })
  }

  function setPadRight(px) {
    root.persistSettings({ padRight: root.readPadPx(px) })
  }

  function chargeLimitScriptPath() {
    var url = String(Qt.resolvedUrl("set-charge-limit.sh"))
    if (url.indexOf("file://") === 0) {
      var path = url.substring(7)
      // file:///home/... → /home/...
      if (path.charAt(0) !== "/") path = "/" + path
      try { return decodeURIComponent(path) } catch (e) { return path }
    }
    return url
  }

  function desiredChargeLimitPct() {
    return root.chargeLimitEnabled ? root.chargeLimitPct : 100
  }

  function scheduleApplyChargeLimit() {
    chargeLimitApplyTimer.restart()
  }

  function applyChargeLimitNow() {
    if (chargeLimitWriter.running) {
      root.scheduleApplyChargeLimit()
      return
    }
    var pct = root.desiredChargeLimitPct()
    if (root.sysChargeLimit === pct) {
      root.chargeLimitError = ""
      return
    }
    root.chargeLimitBusy = true
    root.chargeLimitError = ""
    chargeLimitWriter.command = ["pkexec", "/bin/sh", root.chargeLimitScriptPath(), String(pct)]
    chargeLimitWriter.running = true
  }

  function setChargeLimitEnabled(enabled) {
    root.persistSettings({
      chargeLimit: enabled ? "on" : "off",
      chargeLimitPct: root.chargeLimitPct
    })
    root.scheduleApplyChargeLimit()
  }

  function setChargeLimitPct(pct) {
    var n = Math.floor(Number(pct))
    if (!isFinite(n)) n = root.chargeLimitPct
    n = Math.max(50, Math.min(100, n))
    root.persistSettings({
      chargeLimit: root.chargeLimitEnabled ? "on" : "off",
      chargeLimitPct: n
    })
    if (root.chargeLimitEnabled) root.scheduleApplyChargeLimit()
  }

  // Rewrite shell.json when normalize expands the catalog (e.g. adds arrow).
  property bool metricsMigrated: false
  function ensureMetricsPersisted() {
    if (root.metricsMigrated) return
    root.metricsMigrated = true
    var raw = setting("metrics", null)
    var serialized = Model.serializeMetrics(root.metrics)
    if (typeof raw === "string" && raw === serialized) return
    if (raw === null || raw === undefined) return
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
    interval: root.intervalSec * 1000
    running: root.widgetEnabled
    triggeredOnStart: true
    repeat: true
    onTriggered: probe.running = true
  }

  Timer {
    id: chargeLimitApplyTimer
    interval: 700
    onTriggered: root.applyChargeLimitNow()
  }

  Process {
    id: probe
    command: ["sh", "-c", "cat /sys/class/power_supply/BAT0/status /sys/class/power_supply/BAT0/capacity /sys/class/power_supply/BAT0/power_now /sys/class/power_supply/BAT0/energy_now /sys/class/power_supply/BAT0/energy_full /sys/class/power_supply/BAT0/charge_control_end_threshold 2>/dev/null"]
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
        if (lines.length >= 6 && lines[5] !== "") {
          var lim = parseInt(lines[5])
          if (isFinite(lim) && lim > 0) root.sysChargeLimit = lim
        }
      }
    }
  }

  Process {
    id: chargeLimitWriter
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var out = String(text || "").trim()
        var n = parseInt(out)
        if (isFinite(n) && n > 0) root.sysChargeLimit = n
      }
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var err = String(text || "").trim()
        if (err !== "") root.chargeLimitError = err
      }
    }
    onExited: function(exitCode) {
      root.chargeLimitBusy = false
      if (exitCode !== 0 && root.chargeLimitError === "")
        root.chargeLimitError = exitCode === 126 || exitCode === 127
          ? "Could not run charge-limit helper"
          : "Failed to set charge limit (need auth?)"
      probe.running = true
    }
  }

  Item {
    anchors.fill: parent
    anchors.leftMargin: root.padLeft
    anchors.rightMargin: root.padRight

    Text {
      id: labelText
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      text: root.label
      color: root.showIdleGlyph ? Qt.darker(root.fg, 1.45) : root.fg
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
    contentWidth: menu.fittedContentWidth(Style.space(380))
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

      Rectangle {
        width: parent.width
        height: 1
        color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.18)
      }

      Item {
        id: intervalRow
        width: parent.width
        height: Math.max(menu.metricRowHeight, intervalField.implicitHeight + Style.space(2))

        Rectangle {
          anchors.fill: parent
          anchors.margins: Style.space(1)
          color: "transparent"

          Row {
            anchors.fill: parent
            anchors.leftMargin: Style.space(4)
            anchors.rightMargin: Style.space(4)
            spacing: Style.space(8)

            Item {
              width: Style.space(22)
              height: parent.height
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width - Style.space(22) - intervalField.implicitWidth - parent.spacing * 2
              text: "Update interval (seconds)"
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
            }

            NumberField {
              id: intervalField
              anchors.verticalCenter: parent.verticalCenter
              label: ""
              value: root.intervalSec
              from: 1
              to: 300
              stepSize: 1
              fieldWidth: Style.space(56)
              foreground: root.fg
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              onModified: function(v) { root.setIntervalSec(v) }
            }
          }
        }
      }

      Item {
        id: padLeftRow
        width: parent.width
        height: Math.max(menu.metricRowHeight, padLeftField.implicitHeight + Style.space(2))

        Rectangle {
          anchors.fill: parent
          anchors.margins: Style.space(1)
          color: "transparent"

          Row {
            anchors.fill: parent
            anchors.leftMargin: Style.space(4)
            anchors.rightMargin: Style.space(4)
            spacing: Style.space(8)

            Item {
              width: Style.space(22)
              height: parent.height
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width - Style.space(22) - padLeftField.implicitWidth - parent.spacing * 2
              text: "Left padding (px)"
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
            }

            NumberField {
              id: padLeftField
              anchors.verticalCenter: parent.verticalCenter
              label: ""
              value: root.padLeft
              from: 0
              to: 400
              stepSize: 1
              fieldWidth: Style.space(56)
              foreground: root.fg
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              onModified: function(v) { root.setPadLeft(v) }
            }
          }
        }
      }

      Item {
        id: padRightRow
        width: parent.width
        height: Math.max(menu.metricRowHeight, padRightField.implicitHeight + Style.space(2))

        Rectangle {
          anchors.fill: parent
          anchors.margins: Style.space(1)
          color: "transparent"

          Row {
            anchors.fill: parent
            anchors.leftMargin: Style.space(4)
            anchors.rightMargin: Style.space(4)
            spacing: Style.space(8)

            Item {
              width: Style.space(22)
              height: parent.height
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width - Style.space(22) - padRightField.implicitWidth - parent.spacing * 2
              text: "Right padding (px)"
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
            }

            NumberField {
              id: padRightField
              anchors.verticalCenter: parent.verticalCenter
              label: ""
              value: root.padRight
              from: 0
              to: 400
              stepSize: 1
              fieldWidth: Style.space(56)
              foreground: root.fg
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              onModified: function(v) { root.setPadRight(v) }
            }
          }
        }
      }

      Rectangle {
        width: parent.width
        height: 1
        color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.18)
      }

      Item {
        id: chargeLimitRow
        width: parent.width
        height: menu.metricRowHeight

        Rectangle {
          anchors.fill: parent
          anchors.margins: Style.space(1)
          color: "transparent"
          opacity: root.sysChargeLimit > 0 ? 1 : 0.45

          Row {
            anchors.fill: parent
            anchors.leftMargin: Style.space(4)
            anchors.rightMargin: Style.space(4)
            spacing: Style.space(8)

            Item {
              width: Style.space(22)
              height: parent.height
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width - Style.space(22) - chargeLimitBtn.implicitWidth - parent.spacing * 2
              text: "Charge limiter"
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
            }

            Button {
              id: chargeLimitBtn
              anchors.verticalCenter: parent.verticalCenter
              text: root.chargeLimitEnabled ? "On" : "Off"
              foreground: root.fg
              selected: root.chargeLimitEnabled
              horizontalPadding: 8
              verticalPadding: 3
              fontSize: Style.font.bodySmall
              enabled: root.sysChargeLimit > 0 && !root.chargeLimitBusy
              onClicked: root.setChargeLimitEnabled(!root.chargeLimitEnabled)
            }
          }
        }
      }

      Item {
        id: chargeLimitPctRow
        width: parent.width
        height: Math.max(menu.metricRowHeight, chargeLimitPctField.implicitHeight + Style.space(2))

        Rectangle {
          anchors.fill: parent
          anchors.margins: Style.space(1)
          color: "transparent"
          opacity: root.sysChargeLimit > 0 && root.chargeLimitEnabled ? 1 : 0.45

          Row {
            anchors.fill: parent
            anchors.leftMargin: Style.space(4)
            anchors.rightMargin: Style.space(4)
            spacing: Style.space(8)

            Item {
              width: Style.space(22)
              height: parent.height
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width - Style.space(22) - chargeLimitPctField.implicitWidth - parent.spacing * 2
              text: "Charge limit (%)"
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
            }

            NumberField {
              id: chargeLimitPctField
              anchors.verticalCenter: parent.verticalCenter
              label: ""
              value: root.chargeLimitPct
              from: 50
              to: 100
              stepSize: 1
              fieldWidth: Style.space(56)
              foreground: root.fg
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              enabled: root.sysChargeLimit > 0 && root.chargeLimitEnabled && !root.chargeLimitBusy
              onModified: function(v) { root.setChargeLimitPct(v) }
            }
          }
        }
      }

      Text {
        visible: root.sysChargeLimit > 0 && (root.chargeLimitBusy || root.chargeLimitError !== "")
        text: root.chargeLimitBusy
          ? "Applying charge limit (auth may be required)…"
          : root.chargeLimitError
        color: root.chargeLimitError !== "" ? Color.urgent : Qt.darker(root.fg, 1.4)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
        width: parent.width
      }

      Text {
        visible: root.sysChargeLimit <= 0
        text: "Charge limit sysfs not available on this battery."
        color: Qt.darker(root.fg, 1.4)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
        width: parent.width
      }

      Item {
        id: activeOnlyRow
        width: parent.width
        height: menu.metricRowHeight

        Rectangle {
          anchors.fill: parent
          anchors.margins: Style.space(1)
          color: "transparent"

          Row {
            anchors.fill: parent
            anchors.leftMargin: Style.space(4)
            anchors.rightMargin: Style.space(4)
            spacing: Style.space(8)

            // Same width as metric drag handles so On/Off buttons share one column.
            Item {
              width: Style.space(22)
              height: parent.height
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width - Style.space(22) - activeOnlyBtn.implicitWidth - parent.spacing * 2
              text: "Only while charging / discharging"
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
            }

            Button {
              id: activeOnlyBtn
              anchors.verticalCenter: parent.verticalCenter
              text: root.activeOnly ? "On" : "Off"
              foreground: root.fg
              selected: root.activeOnly
              horizontalPadding: 8
              verticalPadding: 3
              fontSize: Style.font.bodySmall
              onClicked: root.setActiveOnly(!root.activeOnly)
            }
          }
        }
      }

      Item {
        id: idleIconRow
        width: parent.width
        height: menu.metricRowHeight

        Rectangle {
          anchors.fill: parent
          anchors.margins: Style.space(1)
          color: "transparent"
          opacity: root.activeOnly ? 1 : 0.45

          Row {
            anchors.fill: parent
            anchors.leftMargin: Style.space(4)
            anchors.rightMargin: Style.space(4)
            spacing: Style.space(8)

            Item {
              width: Style.space(22)
              height: parent.height
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width - Style.space(22) - idleIconBtn.implicitWidth - parent.spacing * 2
              text: "Idle battery icon"
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
            }

            Button {
              id: idleIconBtn
              anchors.verticalCenter: parent.verticalCenter
              text: root.idleIconEnabled ? "On" : "Off"
              foreground: root.fg
              selected: root.idleIconEnabled
              horizontalPadding: 8
              verticalPadding: 3
              fontSize: Style.font.bodySmall
              enabled: root.activeOnly
              onClicked: root.setIdleIcon(!root.idleIconEnabled)
            }
          }
        }
      }

      Text {
        text: !root.activeOnly
          ? "Turn on \"only while charging / discharging\" to use the idle icon."
          : (root.idleIconEnabled
            ? "When idle or full, show a battery icon instead of metrics."
            : "When idle or full, hide the widget completely.")
        color: Qt.darker(root.fg, 1.4)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
        width: parent.width
      }
    }
  }
}
