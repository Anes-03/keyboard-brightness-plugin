import QtQuick
import QtTest
import "../Brightness.js" as Brightness

TestCase {
  name: "KeyboardBrightness"

  function test_clampPercent_data() {
    return [
      { tag: "lower bound", input: -10, expected: 0 },
      { tag: "upper bound", input: 120, expected: 100 },
      { tag: "rounding", input: 49.4, expected: 49 },
      { tag: "numeric string", input: "50.6", expected: 51 },
      { tag: "not a number", input: "invalid", expected: 0 }
    ]
  }

  function test_clampPercent(data) {
    compare(Brightness.clampPercent(data.input), data.expected)
  }

  function test_parseBrightness_data() {
    return [
      {
        tag: "normal brightnessctl output",
        output: "kbd_backlight,leds,125,49%,255",
        valid: true,
        percent: 49
      },
      {
        tag: "prefixed device",
        output: "smc::kbd_backlight,leds,1,33%,3",
        valid: true,
        percent: 33
      },
      {
        tag: "first valid line",
        output: "malformed\ntpacpi::kbd_backlight,leds,2,67%,3\n",
        valid: true,
        percent: 67
      },
      { tag: "empty", output: "", valid: false, percent: 0 },
      { tag: "zero maximum", output: "kbd_backlight,leds,0,0%,0", valid: false, percent: 0 },
      { tag: "current above maximum", output: "kbd_backlight,leds,4,133%,3", valid: false, percent: 0 },
      { tag: "non numeric", output: "kbd_backlight,leds,nope,0%,3", valid: false, percent: 0 }
    ]
  }

  function test_restorePercent_data() {
    return [
      { tag: "remembered value", remembered: 35, fallback: 50, expected: 35 },
      { tag: "fallback value", remembered: 0, fallback: 50, expected: 50 },
      { tag: "clamped remembered value", remembered: 120, fallback: 50, expected: 100 },
      { tag: "minimum fallback", remembered: 0, fallback: 0, expected: 1 },
      { tag: "invalid fallback", remembered: 0, fallback: "invalid", expected: 1 }
    ]
  }

  function test_restorePercent(data) {
    compare(Brightness.restorePercent(data.remembered, data.fallback), data.expected)
  }

  function test_toggleTarget_data() {
    return [
      { tag: "turn off", current: 35, remembered: 35, fallback: 50, expected: 0 },
      { tag: "restore remembered", current: 0, remembered: 35, fallback: 50, expected: 35 },
      { tag: "restore fallback", current: 0, remembered: 0, fallback: 50, expected: 50 }
    ]
  }

  function test_toggleTarget(data) {
    compare(Brightness.toggleTarget(data.current, data.remembered, data.fallback), data.expected)
  }

  function test_iconFor_data() {
    return [
      { tag: "on", input: 50, expected: "󰌌" },
      { tag: "off", input: 0, expected: "󰌐" },
      { tag: "negative is off", input: -1, expected: "󰌐" },
      { tag: "invalid is off", input: "invalid", expected: "󰌐" }
    ]
  }

  function test_iconFor(data) {
    compare(Brightness.iconFor(data.input), data.expected)
  }

  function test_normalizeDevicePattern_data() {
    return [
      { tag: "exact device", input: "smc::kbd_backlight", expected: "smc::kbd_backlight" },
      { tag: "wildcard", input: "*kbd_backlight*", expected: "*kbd_backlight*" },
      { tag: "trim whitespace", input: "  tpacpi::kbd_backlight  ", expected: "tpacpi::kbd_backlight" },
      { tag: "empty", input: "   ", expected: "*kbd_backlight*" },
      { tag: "too long", input: "x".repeat(129), expected: "*kbd_backlight*" },
      { tag: "control character", input: "kbd\nbacklight", expected: "*kbd_backlight*" },
      { tag: "path separator", input: "../kbd_backlight", expected: "*kbd_backlight*" }
    ]
  }

  function test_normalizeDevicePattern(data) {
    compare(Brightness.normalizeDevicePattern(data.input), data.expected)
  }

  function test_normalizePollIntervalMs_data() {
    return [
      { tag: "normal", input: 1000, expected: 1000 },
      { tag: "rounding", input: 1250.6, expected: 1251 },
      { tag: "lower bound", input: 1, expected: 500 },
      { tag: "upper bound", input: 999999, expected: 30000 },
      { tag: "numeric string", input: "2500", expected: 2500 },
      { tag: "invalid", input: "invalid", expected: 1000 }
    ]
  }

  function test_normalizePollIntervalMs(data) {
    compare(Brightness.normalizePollIntervalMs(data.input), data.expected)
  }

  function test_appendBounded() {
    var withinLimit = Brightness.appendBounded("abc", "def", 6)
    compare(withinLimit.text, "abcdef")
    compare(withinLimit.exceeded, false)

    var truncated = Brightness.appendBounded("abc", "defghi", 6)
    compare(truncated.text, "abcdef")
    compare(truncated.exceeded, true)

    var alreadyFull = Brightness.appendBounded("abcdef", "x", 6)
    compare(alreadyFull.text, "abcdef")
    compare(alreadyFull.exceeded, true)

    var invalidLimit = Brightness.appendBounded("abc", "def", "invalid")
    compare(invalidLimit.text, "")
    compare(invalidLimit.exceeded, true)
  }

  function test_parseBrightness(data) {
    var result = Brightness.parseBrightness(data.output)
    compare(result.valid, data.valid)
    compare(result.percent, data.percent)
  }

  function test_failureMessage() {
    compare(Brightness.failureMessage("Error", "", 7), "Error (exit code 7)")
    compare(Brightness.failureMessage("Error", "  access\n denied  ", 1),
      "Error: access denied")

    var message = Brightness.failureMessage("Error", "x".repeat(200), 1)
    verify(message.length <= 168)
    verify(message.endsWith("..."))
  }
}
