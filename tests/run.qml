import QtQuick
import "../core"
import "../models/FolderModel.js" as FolderModel
import "../models/PanelModel.js" as PanelModel
import "../models/ServiceStateModel.js" as ServiceStateModel
import "../models/SettingsModel.js" as SettingsModel

QtObject {
  id: root

  property ActivityTracker tracker: ActivityTracker {}

  function compare(actual, expected, name) {
    if (JSON.stringify(actual) !== JSON.stringify(expected)) {
      throw new Error(name + ": expected " + JSON.stringify(expected)
        + ", got " + JSON.stringify(actual))
    }
  }

  function testActivityStates() {
    tracker.stop()
    tracker.processIndexedChanges("folder", [{
      path: "nested/file.txt", deleted: false
    }])
    compare(tracker.dots, ".  ", "first aligned dot frame")
    tracker._dotIndex = 1
    compare(tracker.dots, ".. ", "second aligned dot frame")
    tracker._dotIndex = 2
    compare(tracker.dots, "...", "third aligned dot frame")

    tracker.processIndexedChanges("second-folder", [{
      path: "second.txt", deleted: false
    }])
    tracker.advanceFile()
    compare(tracker.folderId, "second-folder", "file cycle folder")
    compare(tracker.detail, "second.txt", "file cycle detail")

    tracker.stop()
    tracker.processEvent({
      type: "RemoteDownloadProgress",
      data: {
        device: "device",
        folder: "folder",
        state: { "video.mp4": { bytesDone: 1, bytesTotal: 2 } }
      }
    })
    compare(tracker.action, "upload", "upload action")
    compare(tracker.detail, "Upload video.mp4", "upload detail")
  }

  function testNestedIndexedState() {
    var scans = []
    var fileInfo = {
      name: "new-directory",
      type: "FILE_INFO_TYPE_DIRECTORY",
      deleted: false
    }
    tracker.stop()
    tracker.requestApi = function(name, options, onSuccess, onError) {
      if (name === "getFileInfo") {
        onSuccess({ local: fileInfo })
      } else if (name === "scanFolder") {
        scans.push(options.query)
        onSuccess({})
      } else {
        onError({})
      }
      return { abort: function() {} }
    }
    tracker.processLocalIndexUpdate({
      data: { folder: "folder", filenames: ["new-directory"] }
    })
    compare(scans, [{ folder: "folder", sub: "new-directory" }],
      "new directory scan")

    fileInfo = {
      name: "new-directory/file.txt",
      type: "FILE_INFO_TYPE_FILE",
      deleted: false
    }
    tracker.processLocalIndexUpdate({
      data: { folder: "folder", filenames: [fileInfo.name] }
    })
    compare(tracker.action, "syncing", "nested addition action")
    compare(tracker.detail, "file.txt", "nested addition detail")

    fileInfo.deleted = true
    tracker.processLocalIndexUpdate({
      data: { folder: "folder", filenames: [fileInfo.name] }
    })
    compare(tracker.action, "removing", "nested removal action")
    compare(tracker.detail, "Removing file.txt", "nested removal detail")
  }

  function testModels() {
    var rows = PanelModel.buildFolderRows({
      localDeviceId: "local",
      folders: [{
        id: "folder", label: "Configured label", path: "/tmp/truthful-folder",
        devices: [{ deviceID: "local" }]
      }],
      folderStatuses: {
        folder: { state: "idle", globalFiles: 3, globalBytes: 12 }
      }
    }, "/home/test")
    var folder = rows[0]
    compare(folder.label, "truthful-folder", "folder display label")
    compare(PanelModel.folderMeta(folder),
      "3 files · local only · Configured label", "folder metadata")
    compare(PanelModel.folderState(folder, ""), "SYNCED", "folder state")
    compare(PanelModel.folderState(folder, "", true), "SYNCING",
      "active folder state")
    compare(PanelModel.folderState({ paused: true }, "", true), "UNLINKED",
      "paused folder state")
    compare(PanelModel.folderState({ problem: true }, "", true), "ERROR",
      "problem folder state")

    var config = FolderModel.buildConfig({}, {
      id: "folder",
      label: "Folder",
      path: "/tmp/folder",
      selectedDeviceIds: ["remote"]
    }, "local", function(path) { return path })
    compare(config.devices.map(function(device) { return device.deviceID }),
      ["local", "remote"], "configured devices")

    compare(PanelModel.localDeviceName({
      localDeviceId: "local",
      devices: [{ deviceID: "local", name: "optiplex" }]
    }, "fallback"), "optiplex", "configured local device name")
    compare(PanelModel.localDeviceName(null, "optiplex-sff"),
      "optiplex-sff", "host name fallback")
  }

  function testPendingFolderOffers() {
    var offer = {
      localDeviceId: "local",
      devices: [{ deviceID: "remote", name: "pixel" }],
      pendingFolders: {
        "shared-folder": {
          offeredBy: {
            remote: { label: "Shared folder" }
          }
        }
      }
    }
    compare(PanelModel.pendingOfferOptions(offer), [{
      value: JSON.stringify(["shared-folder", "remote"]),
      label: "Shared folder from pixel"
    }], "pending folder option")
    compare(FolderModel.offerSnapshotError({
      id: "shared-folder", pendingDeviceId: "remote"
    }, offer.pendingFolders), "", "current folder offer")
    compare(FolderModel.offerSnapshotError({
      id: "shared-folder", pendingDeviceId: "missing"
    }, offer.pendingFolders),
      "The selected remote folder offer is no longer available",
      "stale folder offer")

    offer.pendingFolders["shared-folder"].offeredBy.remote.receiveEncrypted = true
    compare(PanelModel.pendingOfferOptions(offer), [],
      "encrypted folder offer hidden")
    compare(FolderModel.offerSnapshotError({
      id: "shared-folder", pendingDeviceId: "remote"
    }, offer.pendingFolders),
      "Encrypted folder offers must be accepted in the Syncthing Web UI",
      "encrypted folder offer rejected")
  }

  function testSettings() {
    var parsed = SettingsModel.parse([
      "# Syncthing plugin preferences",
      "version = 1",
      "",
      "[style]",
      "icon_style   = \"themed\" # follows the Omarchy palette",
      "web_ui_theme = 'default' # keep the Syncthing Web UI"
    ].join("\n"))
    compare(parsed, {
      error: "",
      iconStyle: "themed",
      webUiTheme: "default",
      serviceState: "enabled",
      probeIntervalSeconds: 15
    }, "versioned settings")
    compare(SettingsModel.parse([
      "icon_style = \"branded\"",
      "web_ui_theme = \"omarchy\""
    ].join("\n")), {
      error: "",
      iconStyle: "branded",
      webUiTheme: "omarchy",
      serviceState: "enabled",
      probeIntervalSeconds: 15
    }, "legacy flat settings")
    compare(SettingsModel.defaults(true), {
      iconStyle: "themed",
      webUiTheme: "omarchy",
      serviceState: "enabled",
      probeIntervalSeconds: 15
    }, "legacy themed icon migration")
    compare(SettingsModel.defaults(false), {
      iconStyle: "branded",
      webUiTheme: "omarchy",
      serviceState: "enabled",
      probeIntervalSeconds: 15
    }, "implicit defaults")
    compare(SettingsModel.parse([
      "version = 1",
      "",
      "[style]",
      "icon_style = \"branded\"",
      "web_ui_theme = \"omarchy\"",
      "",
      "[service]",
      "service_state = \"disabled\"",
      "probe_interval_seconds = 27"
    ].join("\n")), {
      error: "",
      iconStyle: "branded",
      webUiTheme: "omarchy",
      serviceState: "disabled",
      probeIntervalSeconds: 27
    }, "service settings")
    compare(SettingsModel.parse([
      "icon_style = \"themed\"",
      "web_ui_theme = \"default\"",
      "",
      "[service]",
      "service_state = \"disabled\""
    ].join("\n")), {
      error: "",
      iconStyle: "themed",
      webUiTheme: "default",
      serviceState: "disabled",
      probeIntervalSeconds: 15
    }, "legacy settings with service section")
    compare(SettingsModel.parse([
      "icon_style = \"branded\"",
      "web_ui_theme = \"unknown\""
    ].join("\n")).error,
      "web_ui_theme must be default or omarchy", "invalid Web UI theme")
    compare(SettingsModel.parse([
      "icon_style = \"branded\"",
      "icon_style = \"themed\"",
      "web_ui_theme = \"omarchy\""
    ].join("\n")).error,
      "Duplicate setting icon_style on line 2", "duplicate setting")
    compare(SettingsModel.parse([
      "version = 2",
      "",
      "[style]",
      "icon_style = \"branded\"",
      "web_ui_theme = \"omarchy\""
    ].join("\n")).error,
      "Unsupported settings version 2", "unsupported settings version")
    compare(SettingsModel.parse([
      "version = 1",
      "icon_style = \"branded\"",
      "",
      "[style]",
      "web_ui_theme = \"omarchy\""
    ].join("\n")).error,
      "Style settings must be inside [style]", "unscoped style setting")
    compare(SettingsModel.parse([
      "icon_style = \"branded\"",
      "web_ui_theme = \"omarchy\"",
      "[service]",
      "service_state = \"automatic\""
    ].join("\n")).error,
      "service_state must be enabled or disabled", "invalid service state")
    compare(SettingsModel.parse([
      "icon_style = \"branded\"",
      "web_ui_theme = \"omarchy\"",
      "[service]",
      "probe_interval_seconds = 0"
    ].join("\n")).error,
      "probe_interval_seconds must be an integer between 1 and 3600",
      "invalid probe interval")
  }

  function actionSummary(action) {
    return {
      side: action.side,
      value: action.value,
      preferred: action.preferred,
      label: action.label
    }
  }

  function testServiceStateModel() {
    var runtimeStates = ["active", "inactive"]
    var configuredStates = ["enabled", "disabled"]
    for (var runtimeIndex = 0; runtimeIndex < runtimeStates.length;
        runtimeIndex++) {
      for (var configIndex = 0; configIndex < configuredStates.length;
          configIndex++) {
        var aligned = ServiceStateModel.decision(
          configuredStates[configIndex], configuredStates[configIndex],
          runtimeStates[runtimeIndex])
        compare(aligned.status, "aligned", "aligned service state")
      }
    }

    var cases = [{
      runtime: "active", config: "enabled", unit: "disabled",
      message: "Syncthing config (enabled) differs from its systemd "
        + "autostart setting (disabled).\n\nPlease choose:",
      first: ["system", "enabled",
        "Enable systemd autostart (preferred)"],
      second: ["config", "disabled", "Set Syncthing config to disabled"]
    }, {
      runtime: "active", config: "disabled", unit: "enabled",
      message: "Syncthing config (disabled) differs from its systemd "
        + "autostart setting (enabled).\n\nPlease choose:",
      first: ["config", "enabled",
        "Set Syncthing config to enabled (preferred)"],
      second: ["system", "disabled", "Disable systemd autostart"]
    }, {
      runtime: "inactive", config: "disabled", unit: "enabled",
      message: "Syncthing config (disabled) differs from its systemd "
        + "autostart setting (enabled).\n\nPlease choose:",
      first: ["system", "disabled",
        "Disable systemd autostart (preferred)"],
      second: ["config", "enabled", "Set Syncthing config to enabled"]
    }, {
      runtime: "inactive", config: "enabled", unit: "disabled",
      message: "Syncthing config (enabled) differs from its systemd "
        + "autostart setting (disabled).\n\nPlease choose:",
      first: ["config", "disabled",
        "Set Syncthing config to disabled (preferred)"],
      second: ["system", "enabled", "Enable systemd autostart"]
    }]
    for (var i = 0; i < cases.length; i++) {
      var current = cases[i]
      var decision = ServiceStateModel.decision(
        current.config, current.unit, current.runtime)
      compare(decision.status, "drift", "divergent service state")
      compare(decision.message, current.message, "service state message")
      compare(actionSummary(decision.first), {
        side: current.first[0], value: current.first[1], preferred: true,
        label: current.first[2]
      }, "preferred service action")
      compare(actionSummary(decision.second), {
        side: current.second[0], value: current.second[1], preferred: false,
        label: current.second[2]
      }, "alternate service action")
    }

    compare(ServiceStateModel.decision(
      "enabled", "masked", "inactive").status,
      "unsupported", "masked unit state")
    compare(ServiceStateModel.decision(
      "enabled", "disabled", "activating").status,
      "unsupported", "transitional runtime state")
    compare(ServiceStateModel.persistenceCommand("enabled"), [
      "systemctl", "--user", "enable", "syncthing.service"
    ], "enable persistence command")
    compare(ServiceStateModel.persistenceCommand("disabled"), [
      "systemctl", "--user", "disable", "syncthing.service"
    ], "disable persistence command")
    compare(ServiceStateModel.persistenceCommand("masked"), [],
      "unsupported persistence command")
  }

  Component.onCompleted: {
    try {
      testActivityStates()
      testNestedIndexedState()
      testModels()
      testPendingFolderOffers()
      testSettings()
      testServiceStateModel()
      console.log("all tests passed")
      Qt.exit(0)
    } catch (error) {
      console.error(error)
      Qt.exit(1)
    }
  }
}
