// Metric catalog and persistence helpers for local.watts.
//
// Metrics are persisted as a plain string in shell.json so they survive
// plugin hot-reload. Nested JSON arrays can round-trip through QML as
// array-like objects that fail Array.isArray(), which previously made the
// widget fall back to watts-only after an Omarchy update/rescan.

var METRIC_DEFS = [
  { id: "arrow", label: "Charge arrow", description: "↑ charging / ↓ discharging" },
  { id: "watts", label: "Watts", description: "Power draw in watts" },
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
    { id: "arrow", enabled: true },
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
      { id: "arrow", enabled: true },
      { id: "watts", enabled: true },
      { id: "capacity", enabled: true },
      { id: "time", enabled: true }
    ]
  }
  if (mode === "time") {
    return [
      { id: "arrow", enabled: true },
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
    out.push({ id: String(list[i].id || ""), enabled: !!list[i].enabled })
  }
  return out
}

function isEnabledFlag(value) {
  return value === true || value === 1 || value === "1"
    || value === "true" || value === "on" || value === "yes"
}

// QML sometimes hands JSON arrays through as array-like objects, not real Arrays.
function asList(value) {
  if (value === undefined || value === null) return null
  if (Array.isArray(value)) return value
  if (typeof value === "object" && typeof value.length === "number" && value.length >= 0) {
    var out = []
    for (var i = 0; i < value.length; i++) out.push(value[i])
    return out
  }
  return null
}

// Stable shell.json form: "arrow:on,watts:on,capacity:off,time:off"
function serializeMetrics(metrics) {
  var parts = []
  var list = asList(metrics) || []
  for (var i = 0; i < list.length; i++) {
    var id = String(list[i].id || "")
    if (!metricDef(id)) continue
    parts.push(id + ":" + (list[i].enabled ? "on" : "off"))
  }
  return parts.join(",")
}

function parseMetricsString(raw) {
  var text = String(raw || "").trim()
  if (!text) return null
  // Legacy: allow a bare comma list of enabled ids ("watts,capacity").
  if (text.indexOf(":") === -1 && text.charAt(0) !== "[") {
    var ids = text.split(",")
    var legacy = []
    var legacySeen = ({})
    for (var i = 0; i < ids.length; i++) {
      var id = String(ids[i] || "").trim()
      if (!metricDef(id) || legacySeen[id]) continue
      legacySeen[id] = true
      legacy.push({ id: id, enabled: true })
    }
    return finalizeMetrics(legacy)
  }

  var parts = text.split(",")
  var rows = []
  var seen = ({})
  for (var p = 0; p < parts.length; p++) {
    var piece = String(parts[p] || "").trim()
    if (!piece) continue
    var bits = piece.split(":")
    var metricId = String(bits[0] || "").trim()
    var flag = String(bits[1] || "on").trim().toLowerCase()
    if (!metricDef(metricId) || seen[metricId]) continue
    seen[metricId] = true
    rows.push({
      id: metricId,
      enabled: flag !== "off" && flag !== "0" && flag !== "false" && flag !== "no"
    })
  }
  return finalizeMetrics(rows)
}

function insertMissingArrow(out, seen) {
  if (seen["arrow"]) return
  // Older configs baked the arrow into watts; keep it on and before watts.
  var wattsIdx = -1
  for (var j = 0; j < out.length; j++) {
    if (out[j].id === "watts") { wattsIdx = j; break }
  }
  var arrowRow = { id: "arrow", enabled: true }
  if (wattsIdx >= 0) out.splice(wattsIdx, 0, arrowRow)
  else out.unshift(arrowRow)
  seen["arrow"] = true
}

function finalizeMetrics(rows) {
  var seen = ({})
  var out = []
  for (var i = 0; i < rows.length; i++) {
    var id = String(rows[i].id || "")
    if (!metricDef(id) || seen[id]) continue
    seen[id] = true
    out.push({ id: id, enabled: !!rows[i].enabled })
  }
  insertMissingArrow(out, seen)
  for (var d = 0; d < METRIC_DEFS.length; d++) {
    var defId = METRIC_DEFS[d].id
    if (!seen[defId]) out.push({ id: defId, enabled: false })
  }
  if (!out.some(function(m) { return m.enabled })) return null
  return out
}

function metricsFromArray(raw) {
  var list = asList(raw)
  if (!list || list.length === 0) return null
  var rows = []
  for (var i = 0; i < list.length; i++) {
    var row = list[i]
    if (typeof row === "string") {
      rows.push({ id: row, enabled: true })
      continue
    }
    if (!row || typeof row !== "object") continue
    rows.push({
      id: String(row.id || ""),
      enabled: isEnabledFlag(row.enabled) || isEnabledFlag(row.on)
    })
  }
  return finalizeMetrics(rows)
}

// Normalize any shell.json value into a full ordered [{id, enabled}] list.
function normalizeMetrics(raw, displayFallback) {
  if (typeof raw === "string") {
    // Nested JSON array accidentally stringified, or our on/off format.
    var trimmed = raw.trim()
    if (trimmed.charAt(0) === "[") {
      try {
        var parsed = metricsFromArray(JSON.parse(trimmed))
        if (parsed) return parsed
      } catch (e) {}
    }
    var fromString = parseMetricsString(raw)
    if (fromString) return fromString
  } else {
    var fromArray = metricsFromArray(raw)
    if (fromArray) return fromArray
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
  if (id === "arrow") return values.arrow || ""
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
  var ids = []
  for (var i = 0; i < metrics.length; i++) {
    if (!metrics[i].enabled) continue
    var part = formatMetricValue(metrics[i].id, values)
    if (part === "") continue
    parts.push(part)
    ids.push(metrics[i].id)
  }
  if (parts.length === 0) return ""
  // Keep arrow glued to its neighbor with a space ("↓ 8.1 W"), not a dot.
  var out = parts[0]
  for (var j = 1; j < parts.length; j++) {
    var sep = (ids[j] === "arrow" || ids[j - 1] === "arrow") ? " " : " · "
    out += sep + parts[j]
  }
  return out
}
