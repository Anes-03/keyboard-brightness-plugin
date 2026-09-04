.pragma library

function clampPercent(value) {
  var number = Number(value)
  return isFinite(number) ? Math.max(0, Math.min(100, Math.round(number))) : 0
}

function restorePercent(lastNonZeroPercent, fallbackPercent) {
  var remembered = clampPercent(lastNonZeroPercent)
  if (remembered > 0) return remembered
  return Math.max(1, clampPercent(fallbackPercent))
}

function toggleTarget(currentPercent, lastNonZeroPercent, fallbackPercent) {
  return clampPercent(currentPercent) > 0
    ? 0
    : restorePercent(lastNonZeroPercent, fallbackPercent)
}

function iconFor(percent) {
  // Material Design Icons from Nerd Fonts: keyboard / keyboard-off.
  return clampPercent(percent) > 0 ? "󰌌" : "󰌐"
}

function normalizeDevicePattern(value) {
  var fallback = "*kbd_backlight*"
  var candidate = value === undefined || value === null
    ? ""
    : String(value).trim()

  if (candidate.length === 0 || candidate.length > 128) return fallback

  for (var i = 0; i < candidate.length; i++) {
    var code = candidate.charCodeAt(i)
    if (code <= 31 || code === 127 || candidate[i] === "/") return fallback
  }

  return candidate
}

function normalizePollIntervalMs(value) {
  var interval = Number(value)
  if (!isFinite(interval)) return 1000
  return Math.min(30000, Math.max(500, Math.round(interval)))
}

function appendBounded(current, incoming, limit) {
  var maximum = Math.floor(Number(limit))
  if (!isFinite(maximum) || maximum < 0) maximum = 0

  var existing = String(current || "")
  var chunk = String(incoming || "")
  if (existing.length > maximum) existing = existing.slice(0, maximum)

  var remaining = Math.max(0, maximum - existing.length)
  return {
    text: existing + chunk.slice(0, remaining),
    exceeded: chunk.length > remaining
  }
}

function parseBrightness(output) {
  var lines = String(output || "").trim().split(/\r?\n/)
  for (var i = 0; i < lines.length; i++) {
    var fields = lines[i].split(",")
    if (fields.length < 5) continue

    var current = Number(String(fields[2]).trim())
    var maximum = Number(String(fields[4]).trim())
    if (!isFinite(current) || !isFinite(maximum)
        || current < 0 || maximum <= 0 || current > maximum) continue

    return { valid: true, percent: clampPercent(current * 100 / maximum) }
  }
  return { valid: false, percent: 0 }
}

function failureMessage(prefix, output, exitCode) {
  var detail = String(output || "").trim().replace(/\s+/g, " ")
  if (detail.length > 160) detail = detail.slice(0, 157) + "..."
  if (detail !== "") return prefix + ": " + detail
  return prefix + " (exit code " + exitCode + ")"
}
