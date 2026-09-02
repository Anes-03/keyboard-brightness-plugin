import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Brightness.js" as Brightness

Panel {
  id: root
  moduleName: "anes.keyboard-brightness"
  ipcTarget: "anes.keyboard-brightness"
  // The widget has no documented external IPC actions. Avoid registering an
  // idle handler, which also reduces hot-reload exposure while a poll exits.
  manageIpc: false

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  property int brightnessPercent: 0
  property int pendingPercent: 0
  property bool available: false
  property bool setQueued: false
  property int changeGeneration: 0
  property int readFailures: 0
  property string readError: ""
  property string writeError: ""
  property int lastNonZeroPercent: 0
  property real wheelAccumulator: 0

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property string errorMessage: writeError !== "" ? writeError : readError
  readonly property string devicePattern: {
    var configured = String(setting("device", "*kbd_backlight*")).trim()
    return configured !== "" ? configured : "*kbd_backlight*"
  }
  readonly property int pollIntervalMs: {
    var configured = Number(setting("pollIntervalMs", 1000))
    return isFinite(configured) ? Math.max(500, Math.round(configured)) : 1000
  }
  readonly property int defaultRestorePercent: {
    var configured = Number(setting("restorePercent", 50))
    return isFinite(configured) ? Math.max(1, clamp(configured)) : 50
  }

  function clamp(value) {
    return Brightness.clampPercent(value)
  }

  function parseBrightness(output) {
    return Brightness.parseBrightness(output)
  }

  function failureMessage(prefix, output, exitCode) {
    return Brightness.failureMessage(prefix, output, exitCode)
  }

  function refresh() {
    if (readProc.running || setProc.running || setDebounce.running) return
    readProc.generation = changeGeneration
    readProc.timedOut = false
    readProc.attemptActive = true
    readTimeout.restart()
    readProc.running = true
  }

  function startSet(percent) {
    setQueued = false
    setProc.command = ["brightnessctl", "-q", "-d", devicePattern, "set", percent + "%"]
    setProc.timedOut = false
    setProc.attemptActive = true
    setTimeout.restart()
    setProc.running = true
  }

  function setBrightness(value) {
    if (!available || !isFinite(Number(value))) return

    var percent = clamp(value)
    if (percent > 0) lastNonZeroPercent = percent
    changeGeneration++
    brightnessPercent = percent
    pendingPercent = percent
    writeError = ""

    if (setProc.running) {
      setQueued = true
      return
    }

    startSet(percent)
  }

  function toggleBacklight() {
    if (!available) return
    var current = clamp(brightnessPercent)
    if (current > 0) lastNonZeroPercent = current
    setBrightness(Brightness.toggleTarget(current, lastNonZeroPercent, defaultRestorePercent))
  }

  function previewBrightness(value) {
    if (!available || !isFinite(Number(value))) return
    brightnessPercent = clamp(value)
    setDebounce.restart()
  }

  function iconFor(percent) {
    return Brightness.iconFor(percent)
  }

  function open() {
    controller.show()
    refresh()
  }

  onOpenedChanged: if (opened) refresh()
  // The bar injects per-widget settings immediately after construction.
  Component.onCompleted: Qt.callLater(root.refresh)

  Timer {
    // Keyboard brightness can also change through the hardware shortcuts.
    // Poll continuously so the bar tooltip and the open slider follow those
    // changes without requiring the panel to be reopened.
    id: pollTimer
    // A missing device should not spawn a failing command twice per second.
    interval: root.available
      ? root.pollIntervalMs
      : Math.max(10000, root.pollIntervalMs * Math.min(30, root.readFailures + 5))
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  Timer {
    id: setDebounce
    interval: 100
    repeat: false
    onTriggered: root.setBrightness(root.brightnessPercent)
  }

  Timer {
    id: readTimeout
    interval: 3000
    repeat: false
    onTriggered: {
      if (!readProc.running) return
      readProc.timedOut = true
      readProc.running = false
      if (readProc.generation !== root.changeGeneration) return
      root.available = false
      root.readFailures++
      root.readError = "Timed out while reading the keyboard backlight"
    }
  }

  Timer {
    id: setTimeout
    interval: 3000
    repeat: false
    onTriggered: {
      if (!setProc.running) return
      setProc.timedOut = true
      setProc.running = false
    }
  }

  Process {
    id: readProc
    command: ["brightnessctl", "-m", "-d", root.devicePattern, "info"]
    property int generation: 0
    property bool timedOut: false
    property bool attemptActive: false
    stdout: StdioCollector {
      id: readStdout
      waitForEnd: true
    }
    stderr: StdioCollector {
      id: readStderr
      waitForEnd: true
    }
    onExited: function(exitCode) {
      attemptActive = false
      readTimeout.stop()
      // A read that started before a user change is stale, regardless of
      // whether the driver completed it before or after the write.
      if (generation !== root.changeGeneration) return
      if (timedOut) return

      if (exitCode !== 0) {
        root.available = false
        root.readFailures++
        root.readError = root.failureMessage(
          "Keyboard backlight unavailable", readStderr.text || readStdout.text, exitCode)
        return
      }

      var result = root.parseBrightness(readStdout.text)
      if (!result.valid) {
        root.available = false
        root.readFailures++
        root.readError = "Invalid output from brightnessctl"
        return
      }

      root.available = true
      root.readFailures = 0
      root.readError = ""
      if (result.percent > 0) root.lastNonZeroPercent = result.percent
      if (!brightnessSlider.dragging && !setDebounce.running
          && !setProc.running && !root.setQueued)
        root.brightnessPercent = result.percent
    }
    onRunningChanged: {
      // Quickshell does not emit exited() when the executable cannot start.
      if (running || !attemptActive || timedOut) return
      attemptActive = false
      readTimeout.stop()
      if (generation !== root.changeGeneration) return
      root.available = false
      root.readFailures++
      root.readError = "brightnessctl could not be started"
    }
  }

  Process {
    id: setProc
    property bool timedOut: false
    property bool attemptActive: false
    stdout: StdioCollector {
      id: setStdout
      waitForEnd: true
    }
    stderr: StdioCollector {
      id: setStderr
      waitForEnd: true
    }
    onExited: function(exitCode) {
      attemptActive = false
      setTimeout.stop()
      if (!root.setQueued) {
        if (timedOut)
          root.writeError = "Timed out while setting the keyboard backlight"
        else if (exitCode !== 0)
          root.writeError = root.failureMessage(
            "Could not set keyboard brightness", setStderr.text || setStdout.text, exitCode)
      }

      if (root.setQueued) {
        var nextPercent = root.pendingPercent
        root.startSet(nextPercent)
      } else {
        // Read the value accepted by the driver instead of assuming it maps
        // exactly to the requested percentage.
        Qt.callLater(root.refresh)
      }
    }
    onRunningChanged: {
      // FailedToStart changes running back to false without exited().
      if (running || !attemptActive || timedOut) return
      attemptActive = false
      setTimeout.stop()
      root.setQueued = false
      root.writeError = "brightnessctl could not be started"
      Qt.callLater(root.refresh)
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.iconFor(root.brightnessPercent)
    tooltipText: root.available
      ? (root.errorMessage !== ""
          ? root.errorMessage
          : "Keyboard brightness: " + root.brightnessPercent + "%")
      : (root.errorMessage !== ""
          ? root.errorMessage
          : "No keyboard backlight found")

    onPressed: function(mouseButton) {
      if (mouseButton === Qt.RightButton) {
        root.toggleBacklight()
      } else if (mouseButton === Qt.LeftButton) {
        root.toggle()
      }
    }

    onWheelMoved: function(delta) {
      if (!root.available) return
      var wheel = Util.wheelSteps(root.wheelAccumulator, delta)
      root.wheelAccumulator = wheel.remainder
      if (wheel.steps !== 0)
        root.setBrightness(root.brightnessPercent + wheel.steps * 10)
    }
  }

  KeyboardPanel {
    id: popup
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: fittedContentWidth(Style.space(320))
    contentHeight: fittedContentHeight(contentColumn.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (root.available && dx !== 0)
          root.setBrightness(root.brightnessPercent + dx * 10)
      }
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: contentColumn
        width: parent.width
        spacing: Style.space(14)

        Item {
          width: parent.width
          implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight)

          Text {
            id: heroIcon
            text: root.iconFor(root.brightnessPercent)
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.display
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
          }

          Column {
            id: heroLabels
            anchors.left: heroIcon.right
            anchors.leftMargin: Style.space(14)
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              text: "Keyboard backlight"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }

            Text {
              text: root.available
                ? root.brightnessPercent + "%"
                : (root.readError !== "" ? "ERROR" : "NOT AVAILABLE")
              color: Qt.darker(root.foreground, 1.4)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
            }
          }
        }

        PanelSeparator { foreground: root.foreground }

        Column {
          width: parent.width
          spacing: Style.space(6)

          Item {
            width: parent.width
            implicitHeight: Math.max(sectionTitle.implicitHeight, percentLabel.implicitHeight)

            PanelSectionHeader {
              id: sectionTitle
              text: "BRIGHTNESS"
              foreground: root.foreground
              fontFamily: root.fontFamily
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              id: percentLabel
              text: root.available
                ? Math.round(brightnessSlider.dragging
                    ? brightnessSlider.liveValue
                    : root.brightnessPercent) + "%"
                : "—"
              color: Qt.darker(root.foreground, 1.4)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
            }
          }

          PanelSlider {
            id: brightnessSlider
            enabled: root.available
            opacity: root.available ? 1 : 0.4
            width: parent.width
            bar: root.bar
            minimum: 0
            maximum: 100
            step: 5
            integer: true
            tickCount: 11
            value: root.brightnessPercent
            onMoved: function(value) { root.previewBrightness(value) }
            onReleased: function(value) {
              setDebounce.stop()
              root.setBrightness(value)
            }
          }
        }

        Text {
          width: parent.width
          text: root.errorMessage !== ""
            ? root.errorMessage
            : "Mouse wheel: ±10%  ·  Right-click: toggle"
          color: Qt.darker(root.foreground, root.errorMessage !== "" ? 1.25 : 1.5)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.Wrap
        }
      }
    }
  }
}
