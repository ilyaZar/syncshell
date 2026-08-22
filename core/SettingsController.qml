import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "../models/SettingsModel.js" as SettingsModel

QtObject {
  id: root

  readonly property string homePath: Quickshell.env("HOME")
  readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME")
    || homePath + "/.config"
  readonly property string settingsPath: configHome
    + "/omarchy/ilyazar.syncthing/settings.toml"
  readonly property string settingsTemplatePath: localPath(
    Qt.resolvedUrl("../config/settings.toml"))
  readonly property string settingsHelperPath: localPath(
    Qt.resolvedUrl("../scripts/syncthing-settings.sh"))
  readonly property string themeHelperPath: localPath(
    Qt.resolvedUrl("../scripts/syncthing-theme.sh"))
  readonly property string removeHelperPath: localPath(
    Qt.resolvedUrl("../scripts/syncthing-remove.sh"))
  readonly property string pluginRoot: localPath(Qt.resolvedUrl(".."))

  property var requestApi
  property bool apiReady: false
  property bool legacyThemedIcon: false
  property bool settingsExists: false
  property string iconStyle: SettingsModel.DefaultIconStyle
  property string webUiTheme: SettingsModel.DefaultWebUiTheme
  property string currentWebUiTheme: ""
  property string guiAssetsPath: ""
  property string error: ""
  property string notice: ""
  property bool busy: false
  property bool _settingsLoaded: false
  property bool _settingsValid: false
  property bool _reconciling: false
  property bool _reconcileAgain: false
  property string _themeBeforeGeneration: ""
  property bool _openAfterEnsure: false
  property bool _deleteSettingsAfterRemoval: false

  function localPath(url) {
    var value = String(url || "")
    if (value.indexOf("file://") === 0) value = value.slice(7)
    return decodeURIComponent(value)
  }

  function loadSettings(raw) {
    var parsed = SettingsModel.parse(raw)
    settingsExists = true
    _settingsLoaded = true
    if (parsed.error) {
      _settingsValid = false
      error = "Settings not applied: " + parsed.error
      return
    }
    _settingsValid = true
    iconStyle = parsed.iconStyle
    webUiTheme = parsed.webUiTheme
    error = ""
    scheduleReconcile()
  }

  function useImplicitDefaults() {
    var values = SettingsModel.defaults(legacyThemedIcon)
    settingsExists = false
    _settingsLoaded = true
    _settingsValid = true
    iconStyle = values.iconStyle
    webUiTheme = values.webUiTheme
    error = ""
    scheduleReconcile()
  }

  function setLegacyThemedIcon(enabled) {
    legacyThemedIcon = enabled === true
    if (!settingsExists) iconStyle = legacyThemedIcon ? "themed" : "branded"
  }

  function openSettings() {
    if (settingsExists) {
      Quickshell.execDetached([
        "omarchy", "launch", "config-editor", settingsPath
      ])
      return
    }
    if (settingsProcess.running) return
    _openAfterEnsure = true
    busy = true
    settingsProcess.command = [
      "bash", settingsHelperPath, "ensure", settingsTemplatePath,
      settingsPath, iconStyle
    ]
    settingsProcess.running = true
  }

  function clearNotice() {
    notice = ""
  }

  function requestSelfRemoval(deletePluginSettings) {
    if (!apiReady || !requestApi || busy) {
      error = "Syncthing must be available for clean removal"
      return
    }
    busy = true
    error = ""
    _deleteSettingsAfterRemoval = deletePluginSettings === true
    requestApi("getSystemPaths", {}, function(paths) {
      root.guiAssetsPath = String((paths || {}).guiAssets || "")
      if (!root.guiAssetsPath) {
        root.finishRemoval("Syncthing did not report its GUI assets path")
        return
      }
      root.requestApi("getGuiConfig", {}, function(gui) {
        var theme = String((gui || {}).theme || "default")
        if (theme === "syncthing-omarchy") {
          root.requestApi("patchGuiConfig", {
            method: "PATCH",
            json: { theme: "default" }
          }, function() {
            root.currentWebUiTheme = "default"
            root.startRemovalWorker()
          }, function(apiError) {
            root.finishRemoval(root.apiErrorMessage(apiError))
          })
        } else root.startRemovalWorker()
      }, function(apiError) {
        root.finishRemoval(root.apiErrorMessage(apiError))
      })
    }, function(apiError) {
      root.finishRemoval(root.apiErrorMessage(apiError))
    })
  }

  function startRemovalWorker() {
    removalProcess.command = [
      "bash", removeHelperPath, "start", pluginRoot, guiAssetsPath,
      _deleteSettingsAfterRemoval ? "purge" : "preserve"
    ]
    removalProcess.running = true
  }

  function finishRemoval(message) {
    busy = false
    if (message) error = message
  }

  function scheduleReconcile() {
    if (!_settingsLoaded || !_settingsValid || !apiReady) return
    reconcileTimer.restart()
  }

  function reconcile() {
    if (!_settingsLoaded || !_settingsValid || !apiReady || !requestApi) return
    if (_reconciling || themeProcess.running) {
      _reconcileAgain = true
      return
    }
    error = ""
    _reconciling = true
    busy = true
    requestApi("getSystemPaths", {}, function(paths) {
      root.guiAssetsPath = String((paths || {}).guiAssets || "")
      if (!root.guiAssetsPath) {
        root.finishReconcile("Syncthing did not report its GUI assets path")
        return
      }
      root.requestApi("getGuiConfig", {}, function(gui) {
        root.currentWebUiTheme = String((gui || {}).theme || "default")
        root.applyDesiredTheme()
      }, function(apiError) {
        root.finishReconcile(root.apiErrorMessage(apiError))
      })
    }, function(apiError) {
      root.finishReconcile(root.apiErrorMessage(apiError))
    })
  }

  function applyDesiredTheme() {
    if (!settingsExists && currentWebUiTheme !== "default"
        && currentWebUiTheme !== "syncthing-omarchy") {
      notice = "Keeping Syncthing Web UI theme " + currentWebUiTheme
      finishReconcile("")
      return
    }

    if (webUiTheme === "default") {
      if (currentWebUiTheme === "syncthing-omarchy") {
        setSyncthingTheme("default")
      } else finishReconcile("")
      return
    }

    _themeBeforeGeneration = currentWebUiTheme
    themeProcess.command = [
      "bash", themeHelperPath, "generate", guiAssetsPath
    ]
    themeProcess.running = true
  }

  function setSyncthingTheme(theme) {
    requestApi("patchGuiConfig", {
      method: "PATCH",
      json: { theme: theme }
    }, function() {
      root.currentWebUiTheme = theme
      root.notice = theme === "syncthing-omarchy"
        ? "Omarchy Web UI theme applied"
        : "Syncthing default Web UI theme restored"
      root.finishReconcile("")
    }, function(apiError) {
      root.finishReconcile(root.apiErrorMessage(apiError))
    })
  }

  function apiErrorMessage(apiError) {
    return "Could not update Syncthing Web UI: "
      + (apiError ? apiError.message : "Connection failed")
  }

  function finishReconcile(message) {
    error = message || ""
    _reconciling = false
    busy = false
    if (_reconcileAgain) {
      _reconcileAgain = false
      reconcileTimer.restart()
    }
  }

  onApiReadyChanged: scheduleReconcile()
  onLegacyThemedIconChanged: {
    if (!settingsExists) iconStyle = legacyThemedIcon ? "themed" : "branded"
  }

  property FileView settingsFile: FileView {
    id: settingsFile
    path: root.settingsPath
    watchChanges: true
    printErrors: false
    onLoaded: root.loadSettings(text())
    onLoadFailed: function(fileError) {
      if (fileError === FileViewError.FileNotFound) root.useImplicitDefaults()
      else {
        root._settingsLoaded = true
        root._settingsValid = false
        root.error = "Could not read Syncthing plugin settings: "
          + FileViewError.toString(fileError)
      }
    }
    onFileChanged: reload()
  }

  property Process settingsProcess: Process {
    id: settingsProcess
    command: []
    onExited: function(exitCode) {
      root.busy = false
      if (exitCode === 0) {
        settingsFile.reload()
        if (root._openAfterEnsure) {
          Quickshell.execDetached([
            "omarchy", "launch", "config-editor", root.settingsPath
          ])
        }
      } else root.error = "Could not create Syncthing plugin settings"
      root._openAfterEnsure = false
    }
  }

  property Process themeProcess: Process {
    id: themeProcess
    command: []
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.finishReconcile("Could not generate the Omarchy Web UI theme")
      } else if (root._themeBeforeGeneration !== "syncthing-omarchy") {
        root.setSyncthingTheme("syncthing-omarchy")
      } else {
        root.notice = "Omarchy Web UI theme updated"
        root.finishReconcile("")
      }
    }
  }

  property Process removalProcess: Process {
    id: removalProcess
    command: []
    onExited: function(exitCode) {
      if (exitCode === 0) {
        root.notice = "Clean removal started"
        root.busy = false
      } else root.finishRemoval("Could not start clean plugin removal")
    }
  }

  property Timer reconcileTimer: Timer {
    interval: 150
    repeat: false
    onTriggered: root.reconcile()
  }

  property Connections themeConnections: Connections {
    target: Color
    function onBackgroundChanged() { root.scheduleReconcile() }
    function onForegroundChanged() { root.scheduleReconcile() }
    function onAccentChanged() { root.scheduleReconcile() }
    function onMutedChanged() { root.scheduleReconcile() }
    function onUrgentChanged() { root.scheduleReconcile() }
  }
}
