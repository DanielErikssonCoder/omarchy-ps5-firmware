import QtQuick
import Quickshell
import Quickshell.Io

// The headless half of the plugin: it runs the checker on a timer.
//
// All of the reading, comparing and writing lives in bin/ps5-firmware, and this
// file only decides *when* that runs. The split is deliberate: the interesting
// rules are the ones that decide whether a person hears anything at all, and
// they live in one script with a test suite rather than being spread between a
// shell process and a QML file. Here there is nothing to get subtly wrong.
//
// The check runs once at start-up unless the state file is already fresh, so a
// theme change (which restarts the shell) does not ask the API again.
Item {
  id: root

  readonly property string pluginId: "io.github.danielerikssoncoder.ps5-firmware"
  readonly property string pluginDir: {
    // A URL, not a path: percent-encoded, so decode before it is used as a
    // filesystem path or a space in the way becomes %20 and exec fails.
    var url = decodeURIComponent(Qt.resolvedUrl(".").toString())
    return url.replace(/^file:\/\//, "").replace(/\/$/, "")
  }
  readonly property string checker: pluginDir + "/bin/ps5-firmware"
  readonly property string shellConfig: {
    var home = Quickshell.env("HOME") || ""
    return home + "/.config/omarchy/shell.json"
  }

  // Defaults mirror manifest.json's `refreshMinutes`; the checker reads the
  // user's real setting from shell.json itself. This copy only decides how
  // often to try, so a stale one costs an extra call that the freshness gate in
  // the script then declines to make.
  property int refreshSeconds: 1800

  function checkNow() {
    if (check.running) return
    check.running = true
  }

  function applySettings() {
    try {
      var config = JSON.parse(configFile.text())
      var layout = (config.bar && config.bar.layout) || {}
      var minutes = 0
      for (var section in layout) {
        var entries = layout[section] || []
        for (var i = 0; i < entries.length; i++) {
          var entry = entries[i]
          if (entry && entry.id === pluginId && entry.refreshMinutes) minutes = entry.refreshMinutes
        }
      }
      if (minutes >= 5 && minutes <= 360) refreshSeconds = minutes * 60
    } catch (e) {
      // A missing or half-written shell.json keeps the defaults above. The
      // shell owns that file and rewrites it, so a parse failure here is a
      // transient state, never something to report as a plugin error.
    }
  }

  FileView {
    id: configFile
    path: root.shellConfig
    printErrors: false
    watchChanges: true
    onLoaded: root.applySettings()
    onFileChanged: {
      reload()
      root.applySettings()
    }
  }

  Process {
    id: check
    // --if-stale is what keeps a shell restart cheap, and --quiet keeps the
    // journal free of one line per check.
    command: [root.checker, "--once", "--quiet", "--if-stale", String(root.refreshSeconds)]
  }

  Timer {
    interval: root.refreshSeconds * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.checkNow()
  }
}
