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
