import QtQuick
import Quickshell
import Quickshell.Io
import QtQuick.Effects
import qs.Commons
import qs.Ui

// The bar half of the plugin.
//
// This file is the manifest entry point, so it owns the shape the shell routes
// by: `opened`, `open()`, `close()` and the popout-switch pair. The panel it
// shows is loaded from here rather than declared as a second plugin kind,
// which is how the built-in clock and weather widgets do it.
//
// Nothing is fetched here. Service.qml owns the polling and writes what it saw
// to the plugin's state file; this widget only renders the newest reading, so a
// shell reload never costs a network request and the bar cannot be the thing
// that hangs.
BarWidget {
  id: root
  moduleName: "io.github.danielerikssoncoder.ps5-firmware"

  readonly property bool opened: panelLoader.item
    ? panelLoader.item.opened === true
    : false
  readonly property bool popoutSwitchClosing: panelLoader.item
    ? panelLoader.item.popoutSwitchClosing === true
    : false

  readonly property string statePath: {
    var home = Quickshell.env("HOME") || ""
    return home + "/.local/state/omarchy/plugins/" + moduleName + "/state.json"
  }

  readonly property string pluginDir: {
    var url = decodeURIComponent(Qt.resolvedUrl(".").toString())
    return url.replace(/^file:\/\//, "").replace(/\/$/, "")
  }
  readonly property string checker: pluginDir + "/bin/ps5-firmware"

  // ---- what a click does ---------------------------------------------------
  //
  // One list, and the hover tooltip is built from it. An interaction that is
  // not in this list is never advertised, and one that is added to the widget
  // cannot be forgotten here: the tooltip and the behaviour cannot drift apart.
  readonly property var clicks: [
    { button: "Left click", action: "firmware panel" },
    { button: "Middle click", action: "check now" }
  ]

  // ---- the newest reading --------------------------------------------------
  //
  // `reading` is bound to stateFile.text(), which is a property: FileView
  // changes it after every load, so the binding re-evaluates and the widget
  // follows the file. The field names below are the state file's own: `view`
  // is the watched scope, `takenAt` is when the check ran.
  readonly property var reading: {
    try {
      var raw = stateFile.text()
      return raw ? JSON.parse(raw) : null
    } catch (e) {
      return null
    }
  }

  readonly property var view: (reading && reading.view) ? reading.view : null

  // "5 min ago" is the unit a person actually checks: the answer is only worth
  // anything if it is fresh, and a raw timestamp makes the reader do the sums.
  function ageText(iso) {
    if (!iso) return ""
    var then = Date.parse(iso)
    if (isNaN(then)) return ""
    var minutes = Math.max(0, Math.round((Date.now() - then) / 60000))
    if (minutes < 2) return "just now"
    if (minutes < 60) return minutes + " min ago"
    var hours = Math.round(minutes / 60)
    if (hours < 48) return hours + " h ago"
    return Math.round(hours / 24) + " d ago"
  }

  readonly property string tooltipText: {
    var lines = []

    if (view && view.latest) {
      lines.push("PS5 firmware " + view.latest)
      var detail = []
      if (view.minimum) detail.push("min " + view.minimum)
      if (view.readable !== undefined && view.total) detail.push(view.readable + " of " + view.total + " regions")
      var age = ageText(reading.takenAt)
      if (age) detail.push("checked " + age)
      if (detail.length) lines.push(detail.join(" · "))
    } else {
      lines.push("PS5 firmware")
      lines.push(reading && reading.sourceOk === false ? "Source not answering" : "No reading yet")
    }

    lines.push("")
    for (var i = 0; i < clicks.length; i++) {
      lines.push(clicks[i].button + ": " + clicks[i].action)
    }
    return lines.join("\n")
  }

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function toggle() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  function refresh() {
    stateFile.reload()
    if (panelLoader.item && panelLoader.item.refresh) panelLoader.item.refresh()
  }

  // A real check, not a re-read: the same script the service runs on its timer,
  // with the same lock, so clicking twice cannot start two of them.
  function checkNow() {
    if (!root.bar) return
    root.bar.run("\"" + root.checker + "\" --once --quiet")
  }

  function injectPanel() {
    if (!panelLoader.item) return
    panelLoader.item.bar = root.bar
    panelLoader.item.anchorItem = button
    panelLoader.item.hostWidget = root
    if ("settings" in panelLoader.item) panelLoader.item.settings = root.settings
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  // ---- the mark in the bar -------------------------------------------------
  //
  // The PlayStation mark from Simple Icons (CC0 as a file; the mark itself is
  // Sony's trademark; this plugin is unofficial, see assets/playstation.svg).
  //
  // It ships monochrome, with no colour of its own, and is drawn through
  // MultiEffect: that is what lets one file follow the theme and the state
  // instead of one file per colour. The stock tray icons are tinted the same
  // way, so this is the shell's own idiom and not a trick.
  readonly property color inkColor: root.bar ? root.bar.foreground : Color.foreground
  readonly property color alertColor: root.bar ? root.bar.urgent : Color.urgent

  // The newest change we recorded, as a timestamp. Bounded by the history the
  // script keeps, so this says "something changed recently", not "something
  // changed once".
  readonly property real lastChangeAt: {
    if (!reading || !reading.history || !reading.history.length) return 0
    var newest = 0
    for (var i = 0; i < reading.history.length; i++) {
      var when = Date.parse(reading.history[i].at)
      if (!isNaN(when) && when > newest) newest = when
    }
    return newest
  }

  readonly property bool changedRecently: lastChangeAt > 0
    && (Date.now() - lastChangeAt) < 86400000

  //  quiet       nothing to report
  //  changed     a new version, a raised baseline or a rebuilt image, last day
  //  source-down the API stopped answering; the mark goes dim
  //  none        no reading yet
  readonly property string markState: {
    if (!reading) return "none"
    if (reading.sourceOk === false) return "source-down"
    if (view && view.latest && changedRecently) return "changed"
    return "quiet"
  }

  readonly property color markColor: {
    if (markState === "none") return Qt.rgba(inkColor.r, inkColor.g, inkColor.b, 0.45)
    if (markState === "quiet") return inkColor
    return alertColor
  }

  readonly property real markOpacity: markState === "source-down" ? 0.6 : 1.0

  Component {
    id: markComponent

    Item {
      id: markCanvas

      Image {
        id: logo
        anchors.centerIn: parent
        // 0.84 of the slot: the mark is a wide shape and the canvas is square,
        // so this keeps it from touching the neighbours while still filling
        // the optical size the other bar icons use.
        width: Math.round(Math.min(parent.width, parent.height) * 0.84)
        height: width
        source: Qt.resolvedUrl("assets/playstation.svg")
        sourceSize.width: 128
        sourceSize.height: 128
        fillMode: Image.PreserveAspectFit
        smooth: true
        // Never shown as-is: the effect below is what draws it, colourised.
        // A hidden source item is the documented pattern for MultiEffect and
        // the one the shell's own tray uses.
        visible: false
      }

      MultiEffect {
        anchors.fill: logo
        source: logo
        colorization: 1.0
        colorizationColor: root.markColor
        opacity: root.markOpacity
      }
    }
  }

  FileView {
    id: stateFile
    path: root.statePath
    // No state file yet is the normal first run, not a failure worth a journal
    // warning; the tooltip says "No reading yet" instead.
    printErrors: false
    watchChanges: true
    onFileChanged: reload()
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    iconComponent: markComponent
    slotSize: Style.bar.statusSlot
    tooltipText: root.tooltipText

    onPressed: function(buttonCode) {
      if (!root.bar) return
      if (buttonCode === Qt.MiddleButton) root.checkNow()
      else root.toggle()
    }
  }
}
