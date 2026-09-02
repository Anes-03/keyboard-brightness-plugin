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
