import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Brightness.js" as Brightness

Panel {
  id: root
  moduleName: "io.github.anes-03.keyboard-brightness"
  ipcTarget: "io.github.anes-03.keyboard-brightness"
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
  property bool destroying: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property string errorMessage: writeError !== "" ? writeError : readError
  readonly property string brightnessctlPath: "/usr/bin/brightnessctl"
  readonly property int maxProcessStreamChars: 2048
  readonly property int terminationGraceMs: 250
  readonly property int sigTerm: 15
  readonly property int sigKill: 9
  readonly property var processEnvironment: ({
    "LANG": "C",
    "LC_ALL": "C"
  })
  readonly property string tooltipMessage: {
    if (available) {
      return errorMessage !== ""
        ? "Keyboard brightness error — open for details"
        : "Keyboard brightness: " + brightnessPercent + "%"
    }
    return readError !== ""
      ? "Keyboard backlight unavailable — open for details"
      : "No keyboard backlight found"
  }
  readonly property string devicePattern: Brightness.normalizeDevicePattern(
    setting("device", "*kbd_backlight*"))
  readonly property int pollIntervalMs: Brightness.normalizePollIntervalMs(
    setting("pollIntervalMs", 1000))
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

  function resetProcess(proc) {
    proc.timedOut = false
    proc.outputExceeded = false
    proc.stopRequested = false
    proc.attemptActive = true
    proc.startedSuccessfully = false
    proc.stdoutText = ""
    proc.stderrText = ""
  }

  function requestProcessStop(proc, killTimer) {
    if (!proc.running || proc.stopRequested) return
    proc.stopRequested = true
    proc.signal(sigTerm)
    killTimer.restart()
  }

  function captureProcessOutput(proc, channel, data, killTimer) {
    if (destroying) return
    var current = channel === "stdout" ? proc.stdoutText : proc.stderrText
    var result = Brightness.appendBounded(current, data, maxProcessStreamChars)
    if (channel === "stdout") proc.stdoutText = result.text
    else proc.stderrText = result.text

    if (result.exceeded) {
      proc.outputExceeded = true
      requestProcessStop(proc, killTimer)
    }
  }

  function cleanupProcesses() {
    destroying = true
    pollTimer.stop()
    setDebounce.stop()
    readTimeout.stop()
    setTimeout.stop()
    readKillTimer.stop()
    setKillTimer.stop()

    // Destruction cannot wait for a grace timer, so explicitly signal both
    // stages before the Process wrappers themselves are destroyed.
    if (readProc.running) {
      readProc.signal(sigTerm)
      if (readProc.running) readProc.signal(sigKill)
    }
    if (setProc.running) {
      setProc.signal(sigTerm)
      if (setProc.running) setProc.signal(sigKill)
    }
  }

  function refresh() {
    if (destroying || readProc.running || setProc.running || setDebounce.running) return
    readProc.generation = changeGeneration
    resetProcess(readProc)
    readTimeout.restart()
    readProc.running = true
  }

  function startSet(percent) {
    if (destroying) return
    setQueued = false
    setProc.command = [brightnessctlPath, "-q", "-d", devicePattern, "set", percent + "%"]
    resetProcess(setProc)
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
  Component.onDestruction: root.cleanupProcesses()

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
      root.requestProcessStop(readProc, readKillTimer)
    }
  }

  Timer {
    id: readKillTimer
    interval: root.terminationGraceMs
    repeat: false
    onTriggered: if (readProc.running) readProc.signal(root.sigKill)
  }

  Timer {
    id: setTimeout
    interval: 3000
    repeat: false
    onTriggered: {
      if (!setProc.running) return
      setProc.timedOut = true
      root.requestProcessStop(setProc, setKillTimer)
    }
  }

  Timer {
    id: setKillTimer
    interval: root.terminationGraceMs
    repeat: false
    onTriggered: if (setProc.running) setProc.signal(root.sigKill)
  }

  Process {
    id: readProc
    command: [root.brightnessctlPath, "-m", "-d", root.devicePattern, "info"]
    clearEnvironment: true
    environment: root.processEnvironment
    property int generation: 0
    property bool timedOut: false
    property bool outputExceeded: false
    property bool stopRequested: false
    property bool attemptActive: false
    property bool startedSuccessfully: false
    property string stdoutText: ""
    property string stderrText: ""
    stdout: SplitParser {
      // An empty marker forwards arbitrary chunks without retaining an
      // unterminated line inside SplitParser.
      splitMarker: ""
      onRead: function(data) {
        root.captureProcessOutput(readProc, "stdout", data, readKillTimer)
      }
    }
    stderr: SplitParser {
      splitMarker: ""
      onRead: function(data) {
        root.captureProcessOutput(readProc, "stderr", data, readKillTimer)
      }
    }
    onStarted: startedSuccessfully = true
    onExited: function(exitCode) {
      // This callback is the reaping boundary. No replacement process is
      // started before Quickshell confirms that this child has exited.
      attemptActive = false
      stopRequested = false
      readTimeout.stop()
      readKillTimer.stop()
      if (root.destroying) return
      // A read that started before a user change is stale, regardless of
      // whether the driver completed it before or after the write.
      if (generation !== root.changeGeneration) return

      if (outputExceeded) {
        root.available = false
        root.readFailures++
        root.readError = "brightnessctl produced too much output"
        return
      }

      if (timedOut) {
        root.available = false
        root.readFailures++
        root.readError = "Timed out while reading the keyboard backlight"
        return
      }

      if (exitCode !== 0) {
        root.available = false
        root.readFailures++
        root.readError = root.failureMessage(
          "Keyboard backlight unavailable", stderrText || stdoutText, exitCode)
        return
      }

      var result = root.parseBrightness(stdoutText)
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
      if (running || !attemptActive || startedSuccessfully || root.destroying) return
      attemptActive = false
      readTimeout.stop()
      readKillTimer.stop()
      if (generation !== root.changeGeneration) return
      root.available = false
      root.readFailures++
      root.readError = "brightnessctl could not be started"
    }
  }

  Process {
    id: setProc
    clearEnvironment: true
    environment: root.processEnvironment
    property bool timedOut: false
    property bool outputExceeded: false
    property bool stopRequested: false
    property bool attemptActive: false
    property bool startedSuccessfully: false
    property string stdoutText: ""
    property string stderrText: ""
    stdout: SplitParser {
      splitMarker: ""
      onRead: function(data) {
        root.captureProcessOutput(setProc, "stdout", data, setKillTimer)
      }
    }
    stderr: SplitParser {
      splitMarker: ""
      onRead: function(data) {
        root.captureProcessOutput(setProc, "stderr", data, setKillTimer)
      }
    }
    onStarted: startedSuccessfully = true
    onExited: function(exitCode) {
      // Treat onExited as the reap confirmation before consuming a queued set.
      attemptActive = false
      stopRequested = false
      setTimeout.stop()
      setKillTimer.stop()
      if (root.destroying) return

      if (outputExceeded) {
        root.setQueued = false
        root.writeError = "brightnessctl produced too much output"
        Qt.callLater(root.refresh)
        return
      }

      if (timedOut) {
        root.setQueued = false
        root.writeError = "Timed out while setting the keyboard backlight"
        Qt.callLater(root.refresh)
        return
      }

      if (root.setQueued) {
        var nextPercent = root.pendingPercent
        root.startSet(nextPercent)
      } else {
        if (exitCode !== 0)
          root.writeError = root.failureMessage(
            "Could not set keyboard brightness", stderrText || stdoutText, exitCode)
        // Read the value accepted by the driver instead of assuming it maps
        // exactly to the requested percentage.
        Qt.callLater(root.refresh)
      }
    }
    onRunningChanged: {
      // FailedToStart changes running back to false without exited().
      if (running || !attemptActive || startedSuccessfully || root.destroying) return
      attemptActive = false
      setTimeout.stop()
      setKillTimer.stop()
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
    // The shell's shared tooltip uses Text.AutoText. Keep external process
    // output out of that sink and show details only in our PlainText field.
    tooltipText: root.tooltipMessage

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
          textFormat: Text.PlainText
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
