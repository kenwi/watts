// Metric catalog and persistence helpers for local.watts.

var METRIC_DEFS = [
  { id: "watts", label: "Watts", description: "Power draw with charge arrow" },
  { id: "capacity", label: "Battery %", description: "Charge percentage" },
  { id: "time", label: "Time remaining", description: "Estimate to empty or full" }
]

function metricDef(id) {
  for (var i = 0; i < METRIC_DEFS.length; i++) {
    if (METRIC_DEFS[i].id === id) return METRIC_DEFS[i]
  }
  return null
}

function defaultMetrics() {
  return [
    { id: "watts", enabled: true },
    { id: "capacity", enabled: false },
    { id: "time", enabled: false }
  ]
}

// Migrate the old display=watts|time|full setting into an ordered metrics list.
function metricsFromDisplay(display) {
  var mode = String(display || "watts")
  if (mode === "full") {
    return [
      { id: "watts", enabled: true },
      { id: "capacity", enabled: true },
      { id: "time", enabled: true }
    ]
  }
  if (mode === "time") {
    return [
      { id: "watts", enabled: true },
      { id: "capacity", enabled: false },
      { id: "time", enabled: true }
    ]
  }
  return defaultMetrics()
}

function cloneMetrics(list) {
  var out = []
  for (var i = 0; i < list.length; i++) {
    out.push({ id: String(list[i].id || ""), enabled: list[i].enabled === true })
  }
  return out
}

// Normalize any shell.json value into a full ordered [{id, enabled}] list.
function normalizeMetrics(raw, displayFallback) {
  if (Array.isArray(raw) && raw.length > 0) {
    var seen = ({})
    var out = []
    for (var i = 0; i < raw.length; i++) {
      var row = raw[i]
      var id = ""
      var enabled = false
      if (typeof row === "string") {
        id = row
        enabled = true
      } else if (row && typeof row === "object") {
        id = String(row.id || "")
        enabled = row.enabled === true || row.enabled === "true" || row.on === true
      }
      if (!metricDef(id) || seen[id]) continue
      seen[id] = true
      out.push({ id: id, enabled: enabled })
    }
    for (var d = 0; d < METRIC_DEFS.length; d++) {
      var defId = METRIC_DEFS[d].id
      if (!seen[defId]) out.push({ id: defId, enabled: false })
    }
    if (out.some(function(m) { return m.enabled })) return out
  }
  return metricsFromDisplay(displayFallback)
}

function enabledMetricIds(metrics) {
  var ids = []
  for (var i = 0; i < metrics.length; i++) {
    if (metrics[i].enabled) ids.push(metrics[i].id)
  }
  return ids
}

function toggleMetric(metrics, id) {
  var next = cloneMetrics(metrics)
  var enabledCount = 0
  var target = -1
  for (var i = 0; i < next.length; i++) {
    if (next[i].enabled) enabledCount++
    if (next[i].id === id) target = i
  }
  if (target < 0) return metrics
  // Keep at least one metric visible on the bar.
  if (next[target].enabled && enabledCount <= 1) return metrics
  next[target].enabled = !next[target].enabled
  return next
}

function moveMetric(metrics, id, delta) {
  var next = cloneMetrics(metrics)
  var from = -1
  for (var i = 0; i < next.length; i++) {
    if (next[i].id === id) { from = i; break }
  }
  if (from < 0) return metrics
  var to = from + delta
  if (to < 0 || to >= next.length) return metrics
  var tmp = next[from]
  next[from] = next[to]
  next[to] = tmp
  return next
}

function formatMetricValue(id, values) {
  if (id === "watts") return values.wattsPart || ""
  if (id === "capacity") {
    if (!(values.capacity >= 0)) return ""
    return values.capacity + "%"
  }
  if (id === "time") return values.timeShort || ""
  return ""
}

function formatLabel(metrics, values) {
  var parts = []
  for (var i = 0; i < metrics.length; i++) {
    if (!metrics[i].enabled) continue
    var part = formatMetricValue(metrics[i].id, values)
    if (part !== "") parts.push(part)
  }
  return parts.join(" · ")
}
