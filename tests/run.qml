import QtQuick
import "../hosts/omarchy/models/PanelModel.js" as PanelModel
import "../hosts/omarchy/models/SettingsModel.js" as SettingsModel
import "../hosts/omarchy/models/FacadeModel.js" as FacadeModel

QtObject {
  id: root

  function compare(actual, expected, name) {
    if (JSON.stringify(actual) !== JSON.stringify(expected)) {
      throw new Error(name + ": expected " + JSON.stringify(expected)
        + ", got " + JSON.stringify(actual))
    }
  }

  function testPanelModel() {
    var service = {
      localDeviceId: "local",
      folders: [{
        id: "folder",
        label: "Configured label",
        path: "/tmp/truthful-folder",
        devices: [{ deviceID: "local" }]
      }],
      folderStatuses: {
        folder: { state: "idle", globalFiles: 3, globalBytes: 12 }
      }
    }
    var rows = PanelModel.buildFolderRows(service, "/home/test")
    compare(rows[0].label, "truthful-folder", "folder display label")
    compare(PanelModel.folderMeta(rows[0]),
      "3 files · local only · Configured label", "folder metadata")
    compare(PanelModel.folderState(rows[0], ""), "SYNCED", "folder state")
    compare(PanelModel.folderState(rows[0], "", true), "SYNCING",
      "active folder state")
    compare(PanelModel.folderMeta(rows[0], true),
      "Scanning local changes · Configured label", "rescan folder metadata")
    compare(PanelModel.folderState(rows[0], "", false, true),
      "RESCANNING", "optimistic rescan state")
    compare(PanelModel.localDeviceName({
      displayDeviceName: "optiplex-sff",
      localDeviceId: "",
      devices: []
    }, "fallback"), "optiplex-sff", "remembered local device name")
  }

  function testSettingsModel() {
    compare(SettingsModel.parse([
      "version = 1",
      "",
      "[style]",
      "icon_style = \"themed\"",
      "web_ui_theme = \"default\"",
      "",
      "[service]",
      "service_state = \"disabled\"",
      "probe_interval_seconds = 27"
    ].join("\n")), {
      error: "",
      iconStyle: "themed",
      webUiTheme: "default",
      serviceState: "disabled",
      probeIntervalSeconds: 27
    }, "versioned settings")
    compare(SettingsModel.defaults(false), {
      iconStyle: "branded",
      webUiTheme: "omarchy",
      serviceState: "enabled",
      probeIntervalSeconds: 15
    }, "implicit defaults")
    compare(SettingsModel.parse([
      "icon_style = \"branded\"",
      "web_ui_theme = \"unknown\""
    ].join("\n")).error,
      "web_ui_theme must be default or omarchy", "invalid Web UI theme")
    compare(SettingsModel.parse([
      "version = 1",
      "",
      "[style]",
      "icon_style = \"themed\"",
      "web_ui_theme = \"default\"",
      "",
      "[service]",
      "service_state = \"disabled\"",
      "probe_interval_seconds = 27",
      "",
      "[future]",
      "retained_value = \"untouched\""
    ].join("\n")), {
      error: "",
      iconStyle: "themed",
      webUiTheme: "default",
      serviceState: "disabled",
      probeIntervalSeconds: 27
    }, "unknown additive section")
  }

  function testFacadeProjection() {
    var sourceDevices = [{
      id: "local", name: "desktop", untrusted: false, connected: true
    }, {
      id: "remote", name: "phone", untrusted: true, connected: false
    }]
    compare(FacadeModel.devices(sourceDevices), [{
      deviceID: "local", name: "desktop", untrusted: false
    }, {
      deviceID: "remote", name: "phone", untrusted: true
    }], "device projection")
    compare(FacadeModel.connections(sourceDevices), {
      connections: {
        local: { connected: true },
        remote: { connected: false }
      }
    }, "connection projection")
    compare(FacadeModel.folderStatuses([{
      id: "folder",
      status: {
        state: "error",
        errors: [{ path: "file", error: "denied" }],
        pullErrors: 2
      }
    }]).folder.errors, 1, "folder error projection")
    compare(FacadeModel.linkedFolderIds([
      { id: "linked", paused: false },
      { id: "paused", paused: true }
    ]), ["linked"], "linked rescan targets")
    compare(FacadeModel.rescanTargets("rescan", "linked", []),
      ["linked"], "single rescan target")
    compare(FacadeModel.rescanTargets("rescan-all", "", [
      { id: "linked", paused: false },
      { id: "paused", paused: true }
    ]), ["linked"], "global rescan targets")
  }

  function testDriftPresentation() {
    compare(FacadeModel.lifecyclePresentation({
      available: true,
      targetMatch: false,
      canControl: false,
      canStart: false
    }), {
      available: false,
      controllable: false
    }, "external lifecycle hidden")
    compare(FacadeModel.lifecyclePresentation({
      available: true,
      targetMatch: true,
      canControl: true,
      canStart: false
    }), {
      available: true,
      controllable: true
    }, "trusted lifecycle shown")
    var decision = FacadeModel.driftDecision("enabled", {
      unitFileState: "disabled",
      activeState: "inactive"
    })
    compare(decision.status, "drift", "drift status")
    compare(decision.first.side, "config", "inactive preferred side")
    compare(decision.second.side, "system", "inactive alternate side")
    compare(FacadeModel.driftDecision("enabled", {
      unitFileState: "enabled",
      activeState: "active"
    }).status, "aligned", "aligned state")
  }

  Component.onCompleted: {
    try {
      testPanelModel()
      testSettingsModel()
      testFacadeProjection()
      testDriftPresentation()
      console.log("all QML model tests passed")
      Qt.exit(0)
    } catch (error) {
      console.error(error)
      Qt.exit(1)
    }
  }
}
