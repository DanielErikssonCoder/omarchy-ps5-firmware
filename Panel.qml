import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// The details panel. Loaded by BarWidget.qml, not declared as a plugin kind of
// its own: the bar identifies a panel by the widget in its slot, so the widget
// forwards opened/open/close here.
//
// Everything shown here comes from the state file the service writes. The panel
// does the arithmetic a person would otherwise do in their head, "am I behind?",
// and nothing else: no fetching, no guessing. A row that has no manifest of
// its own says so instead of showing a number borrowed from somewhere.
Panel {
  id: root
  moduleName: "io.github.danielerikssoncoder.ps5-firmware"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var settings: ({})

  readonly property string pluginId: root.moduleName
  readonly property string pluginDir: {
    var url = decodeURIComponent(Qt.resolvedUrl(".").toString())
    return url.replace(/^file:\/\//, "").replace(/\/$/, "")
  }
  readonly property string statePath: {
    var home = Quickshell.env("HOME") || ""
    return home + "/.local/state/omarchy/plugins/" + root.pluginId + "/state.json"
  }

  // Null until the service has written its first reading. `stateFile.text()` is
  // a property read, so this re-evaluates whenever a check rewrites the file.
  readonly property var state: {
    try {
      return stateFile.text() ? JSON.parse(stateFile.text()) : null
    } catch (e) {
      return null
    }
  }

  readonly property var view: (state && state.view) ? state.view : null
  readonly property bool hasReading: !!(view && view.latest)
  readonly property bool sourceDown: !!(state && state.sourceOk === false)

  // The scope the comparison uses: whatever region the widget is watching.
  readonly property string scopeCode: (view && view.code) ? String(view.code).toUpperCase() : "GLOBAL"

  readonly property color ink: root.barForeground
  readonly property color alertInk: root.bar ? root.bar.urgent : Color.urgent
  readonly property string family: root.bar ? root.bar.fontFamily : Style.font.family

  // ---- the version he types ------------------------------------------------
  //
  // Kept in the widget's own settings (shell.json), saved through the shell's
  // scoped API on Enter. The field is the source of truth while he is typing,
  // so the answer below updates per keystroke: no round trip to a file to find
  // out whether 13.60 is old.
  readonly property string savedVersion: {
    var fromFile = root.versionFromShellConfig()
    if (fromFile !== "") return fromFile
    // Fallback for the case where the widget's pushed settings arrive first.
    return String(root.setting("myVersion", "") || "")
  }

  // The widget's settings are pushed in asynchronously, and only after the
  // panel has already been built, so the field would open empty on every shell
  // start. It reads the same file the shell writes instead (the one the
  // settings UI edits, and the one the checker reads for `region`): one source
  // of truth, no ordering to get right.
  function versionFromShellConfig() {
    var raw = shellConfig.text()
    if (!raw) return ""
    try {
      var doc = JSON.parse(raw)
      var bar = doc && doc.bar ? doc.bar : doc
      var layout = bar && bar.layout ? bar.layout : null
      if (!layout) return ""
      var sections = ["left", "center", "right"]
      for (var s = 0; s < sections.length; s++) {
        var list = layout[sections[s]]
        if (!list) continue
        for (var i = 0; i < list.length; i++) {
          var entry = list[i]
          if (entry && entry.id === root.pluginId) {
            return entry.myVersion ? String(entry.myVersion) : ""
          }
        }
      }
    } catch (e) {
      return ""
    }
    return ""
  }
  property string versionText: ""
  property string saveNotice: ""
  property string pendingSave: ""

  function syncFromSettings() {
    if (!versionField.activeFocus) root.versionText = root.savedVersion
  }

  // The widget's settings arrive late and the file is the only thing that can
  // settle whether a write landed, so the notice waits for the file rather than
  // for a return value: `updateEntryInline` answers false for a write it did not
  // need to make (the value was already there), which is not a refusal.
  onSettingsChanged: root.syncFromSettings()

  onSavedVersionChanged: {
    root.syncFromSettings()
    if (root.pendingSave !== "" && root.savedVersion === root.pendingSave) {
      root.pendingSave = ""
      root.saveNotice = "Saved."
    }
  }

  function saveVersion(value) {
    root.versionText = String(value || "").trim()
    root.pendingSave = root.versionText
    if (!root.bar || !root.bar.shell || !root.bar.shell.updateEntryInline) {
      root.pendingSave = ""
      root.saveNotice = "Kept for this session only: the bar gave no settings handle."
      return
    }
    root.bar.shell.updateEntryInline(root.pluginId, { myVersion: root.versionText })
    root.saveNotice = "Saving…"
    saveCheck.restart()
  }

  // ---- version arithmetic --------------------------------------------------
  //
  // "14.00" is a version, not a number to divide: only the major.minor pair is
  // ever compared, and anything that is not a version at all is named as such
  // rather than silently treated as zero.
  function versionValue(text) {
    var raw = String(text === undefined || text === null ? "" : text).trim()
    if (!/^[0-9]+(\.[0-9]+)*$/.test(raw)) return NaN
    var parts = raw.split(".")
    return parseInt(parts[0], 10) * 1000
      + (parts.length > 1 ? parseInt(parts[1], 10) : 0)
  }

  function compareVersions(mine, theirs) {
    var a = versionValue(mine)
    var b = versionValue(theirs)
    if (isNaN(a) || isNaN(b)) return NaN
    if (a < b) return -1
    if (a > b) return 1
    return 0
  }

  // What the answer line says, in one place, so the words and the colour can
  // never disagree about how serious it is.
  //   tone: "muted" | "ok" | "alert"
  readonly property var answer: {
    var mine = root.versionText.trim()
    if (!mine) return { text: "Type your console's version to see where it stands.", tone: "muted" }
    if (isNaN(versionValue(mine))) return { text: "\"" + mine + "\" is not a version number. Try 13.60.", tone: "muted" }
    if (!root.hasReading) return { text: "No reading yet, so there is nothing to compare against.", tone: "muted" }

    var minimum = root.view.minimum
    var latest = root.view.latest
    var belowMinimum = minimum ? compareVersions(mine, minimum) : NaN
    var againstLatest = latest ? compareVersions(mine, latest) : NaN

    if (belowMinimum === -1) {
      return {
        text: "Below the minimum: PSN will not serve " + minimum + " or older. You are on " + mine + ".",
        tone: "alert"
      }
    }
    if (againstLatest === 0) {
      return { text: "You are on the latest (" + latest + ").", tone: "ok" }
    }
    if (againstLatest === -1) {
      return { text: "Update available: " + mine + " → " + latest + ".", tone: "alert" }
    }
    if (againstLatest === 1) {
      return {
        text: "Newer than the newest reading (" + latest + "): the source may lag, or you run a beta.",
        tone: "muted"
      }
    }
    return { text: "No version to compare against in the current reading.", tone: "muted" }
  }

  readonly property color answerColor: {
    if (answer.tone === "alert") return root.alertInk
    if (answer.tone === "ok") return root.ink
    return root.ink
  }

  readonly property real answerOpacity: answer.tone === "muted" ? 0.7 : 1.0

  // ---- the region matrix ---------------------------------------------------
  //
  // One row per region the source reports, GLOBAL first, then the regions that
  // answer, then the ones that publish nothing we can read. A row with no
  // manifest of its own shows a dash: the aggregate is the best answer
  // available and it already has its own row directly above.
  readonly property var rows: {
    var all = (root.state && root.state.views) ? root.state.views : null
    if (!all) return []
    var keys = Object.keys(all)
    var out = []
    for (var i = 0; i < keys.length; i++) {
      var entry = all[keys[i]]
      if (!entry) continue
      var code = String(entry.code || keys[i]).toUpperCase()
      var live = entry.status === "LIVE"
      out.push({
        code: code,
        latest: entry.latest ? String(entry.latest) : "",
        minimum: entry.minimum ? String(entry.minimum) : "",
        live: live,
        status: live
          ? "live"
          : (entry.status === "PARTIAL" ? "partial" : "no manifest")
      })
    }
    out.sort(function(a, b) {
      if (a.code === "GLOBAL") return -1
      if (b.code === "GLOBAL") return 1
      if (a.live !== b.live) return a.live ? -1 : 1
      return a.code < b.code ? -1 : (a.code > b.code ? 1 : 0)
    })
    return out
  }

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

  function humanSize(bytes) {
    if (!bytes || bytes <= 0) return ""
    var gib = bytes / 1073741824
    return (gib < 10 ? gib.toFixed(2) : Math.round(gib)) + " GiB"
  }

  // The same script the service runs on its timer, through the widget that owns
  // it: one lock, so a click here cannot start a second fetch alongside one.
  function checkNow() {
    if (root.hostWidget && root.hostWidget.checkNow) root.hostWidget.checkNow()
  }

  function open() {
    root.controller.show()
    stateFile.reload()
  }

  function close() {
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function closeForPopoutSwitch() {
    root.close()
  }

  function refresh() {
    stateFile.reload()
  }

  FileView {
    id: stateFile
    path: root.statePath
    // A missing state file is the normal first-run condition, not an error:
    // the panel says so in words instead of printing a warning nobody can act
    // on. Every real failure still has to be visible, so this suppresses only
    // the read warning, not the file's own error reporting elsewhere.
    printErrors: false
    watchChanges: true
    onFileChanged: reload()
  }

  FileView {
    id: shellConfig
    path: (Quickshell.env("HOME") || "") + "/.config/omarchy/shell.json"
    printErrors: false
    watchChanges: true
    onFileChanged: reload()
  }

  // The fallback for a write that never reaches the file: long enough for the
  // shell's own config write to land and be seen by the watch above.
  Timer {
    id: saveCheck
    interval: 1500
    repeat: false
    onTriggered: {
      if (root.pendingSave === "") return
      if (root.savedVersion === root.pendingSave) {
        root.pendingSave = ""
        root.saveNotice = "Saved."
        return
      }
      root.pendingSave = ""
      root.saveNotice = "Could not save: the bar refused the write."
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()

      Column {
        id: content
        width: parent.width
        spacing: Style.space(10)

        // ---- heading -------------------------------------------------------
        Row {
          width: parent.width
          spacing: Style.space(8)

          Text {
            width: parent.width - ageLabel.width - parent.spacing
            text: "PS5 firmware"
            color: root.ink
            font.family: root.family
            font.pixelSize: Style.font.subtitle
            font.bold: true
            elide: Text.ElideRight
          }

          Text {
            id: ageLabel
            anchors.verticalCenter: parent.verticalCenter
            visible: root.hasReading
            text: root.state ? root.ageText(root.state.takenAt) : ""
            color: root.ink
            opacity: 0.6
            font.family: root.family
            font.pixelSize: Style.font.caption
          }
        }

        Text {
          width: parent.width
          visible: !root.hasReading
          text: root.sourceDown
            ? "The source has not answered yet. The watcher keeps trying."
            : "No reading yet. The watcher writes one on its first check."
          color: root.ink
          opacity: 0.8
          font.family: root.family
          font.pixelSize: Style.font.body
          wrapMode: Text.WordWrap
        }

        Text {
          width: parent.width
          visible: root.hasReading
          text: root.hasReading
            ? "Latest " + root.view.latest + " · minimum " + root.view.minimum
            : ""
          color: root.ink
          font.family: root.family
          font.pixelSize: Style.font.body
          wrapMode: Text.WordWrap
        }

        Text {
          width: parent.width
          visible: root.hasReading
          text: {
            if (!root.hasReading) return ""
            var parts = []
            if (root.view.build) parts.push(root.view.build)
            var size = root.humanSize(root.view.size)
            if (size) parts.push(size)
            if (root.scopeCode) parts.push(root.scopeCode)
            return parts.join(" · ")
          }
          color: root.ink
          opacity: 0.75
          font.family: root.family
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        Text {
          width: parent.width
          visible: root.hasReading
          text: {
            if (!root.hasReading) return ""
            var parts = []
            if (root.view.total) parts.push(root.view.readable + " of " + root.view.total + " regions readable")
            if (root.view.status) parts.push("source " + root.view.status)
            return parts.join(" · ")
          }
          color: root.ink
          opacity: 0.75
          font.family: root.family
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        Text {
          width: parent.width
          visible: root.sourceDown
          text: (root.state && root.state.lastError)
            ? "The source is not answering: " + root.state.lastError
            : "The source is not answering."
          color: root.alertInk
          font.family: root.family
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        PanelSeparator { width: parent.width }

        // ---- your firmware -------------------------------------------------
        Row {
          width: parent.width
          spacing: Style.space(8)

          Text {
            width: parent.width - versionField.width - parent.spacing
            anchors.verticalCenter: parent.verticalCenter
            text: "Your firmware"
            color: root.ink
            font.family: root.family
            font.pixelSize: Style.font.body
          }

          TextField {
            id: versionField
            width: Style.space(96)
            text: root.versionText
            placeholderText: "13.60"
            foreground: root.ink
            accent: Color.accent
            font.family: root.family
            font.pixelSize: Style.font.body
            horizontalPadding: Style.space(6)
            // Only a real keystroke moves the answer: a programmatic
            // assignment (the settings coming back from the shell) must not.
            onTextEdited: root.versionText = text
            onAccepted: root.saveVersion(text)
            Component.onCompleted: root.syncFromSettings()
          }
        }

        Text {
          width: parent.width
          text: root.answer.text
          color: root.answerColor
          opacity: root.answerOpacity
          font.family: root.family
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        Text {
          width: parent.width
          visible: root.saveNotice !== ""
          text: root.saveNotice
          color: root.ink
          opacity: 0.6
          font.family: root.family
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        Text {
          width: parent.width
          visible: root.hasReading && root.scopeCode !== "GLOBAL"
          text: "Compared against " + root.scopeCode + " only. GLOBAL agrees across the regions that answer."
          color: root.ink
          opacity: 0.6
          font.family: root.family
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        PanelSeparator { width: parent.width }

        // ---- region matrix -------------------------------------------------
        Text {
          width: parent.width
          visible: root.rows.length > 0
          text: "Regions"
          color: root.ink
          font.family: root.family
          font.pixelSize: Style.font.body
          font.bold: true
        }

        Column {
          id: matrix
          width: parent.width
          spacing: Style.space(3)
          visible: root.rows.length > 0

          Repeater {
            model: root.rows

            Row {
              width: matrix.width
              spacing: Style.space(8)

              Text {
                width: Style.space(56)
                text: modelData.code
                color: root.ink
                opacity: modelData.live ? 1.0 : 0.55
                font.family: root.family
                font.pixelSize: Style.font.caption
                font.bold: modelData.code === "GLOBAL"
                elide: Text.ElideRight
              }

              Text {
                width: Style.space(96)
                text: modelData.live
                  ? modelData.latest + " / " + modelData.minimum
                  : "n/a"
                color: root.ink
                opacity: modelData.live ? 0.9 : 0.55
                font.family: root.family
                font.pixelSize: Style.font.caption
              }

              Text {
                width: parent.width - Style.space(56) - Style.space(96) - parent.spacing * 2
                text: modelData.status
                color: root.ink
                opacity: modelData.live ? 0.6 : 0.55
                font.family: root.family
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
              }
            }
          }
        }

        Text {
          width: parent.width
          visible: root.rows.length > 0
          text: "Rows marked \"no manifest\" publish nothing we can read directly, so they show no numbers. "
            + "The GLOBAL row is the agreed figure from the " + (root.view ? root.view.readable : 0)
            + " that answer."
          color: root.ink
          opacity: 0.55
          font.family: root.family
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        PanelSeparator { width: parent.width }

        // ---- download and a manual check -----------------------------------
        Row {
          width: parent.width
          spacing: Style.space(8)

          Text {
            width: parent.width - checkButton.width - parent.spacing
            anchors.verticalCenter: parent.verticalCenter
            visible: root.hasReading
            text: "Download image"
            color: root.ink
            font.family: root.family
            font.pixelSize: Style.font.body
          }

          Button {
            id: checkButton
            text: "Check now"
            foreground: root.ink
            accent: Color.accent
            bordered: true
            fontFamily: root.family
            fontSize: Style.font.caption
            horizontalPadding: Style.space(8)
            verticalPadding: Style.space(3)
            onClicked: root.checkNow()
          }
        }

        // Selectable on purpose: the point of showing the URL is that a person
        // can copy it out. A plain Text would look the same and copy nothing.
        TextEdit {
          width: parent.width
          visible: root.hasReading
          text: root.view && root.view.pupUrl ? root.view.pupUrl : ""
          color: root.ink
          opacity: 0.65
          font.family: root.family
          font.pixelSize: Style.font.caption
          wrapMode: TextEdit.WrapAnywhere
          readOnly: true
          selectByMouse: true
          activeFocusOnPress: false
        }

        Text {
          width: parent.width
          visible: root.hasReading && root.view && root.view.size > 0
          text: root.hasReading
            ? root.humanSize(root.view.size) + " · " + root.scopeCode + " image"
            : ""
          color: root.ink
          opacity: 0.6
          font.family: root.family
          font.pixelSize: Style.font.caption
        }

        // A toast that never reached the screen is worth saying out loud: the
        // reading is still there, but whatever changed is not on his screen.
        Text {
          width: parent.width
          visible: !!(root.state && root.state.notifyError)
          text: (root.state && root.state.notifyError)
            ? "A change could not be announced: " + root.state.notifyError
            : ""
          color: root.alertInk
          font.family: root.family
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        Text {
          width: parent.width
          text: "Data: psn.etawen.lol. Unofficial, not affiliated with Sony."
          color: root.ink
          opacity: 0.5
          font.family: root.family
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }
      }
    }
  }
}
