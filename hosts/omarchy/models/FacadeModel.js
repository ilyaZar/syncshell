.pragma library

function devices(values) {
  var projected = []
  var source = values || []
  for (var i = 0; i < source.length; i++) {
    var device = source[i] || ({})
    projected.push({
      deviceID: String(device.id || ""),
      name: String(device.name || ""),
      untrusted: device.untrusted === true
    })
  }
  return projected
}

function connections(values) {
  var projected = ({})
  var source = values || []
  for (var i = 0; i < source.length; i++) {
    var device = source[i] || ({})
    var id = String(device.id || "")
    if (id) projected[id] = { connected: device.connected === true }
  }
  return { connections: projected }
}

function folderStatus(value) {
  var status = value || ({})
  return {
    state: String(status.state || "unknown"),
    error: String(status.error || ""),
    errors: (status.errors || []).length,
    pullErrors: Number(status.pullErrors || 0),
    needTotalItems: Number(status.needTotalItems || 0),
    needBytes: Number(status.needBytes || 0),
    globalFiles: Number(status.globalFiles || 0),
    globalBytes: Number(status.globalBytes || 0)
  }
}

function folders(values) {
  var projected = []
  var source = values || []
  for (var i = 0; i < source.length; i++) {
    var folder = source[i] || ({})
    var folderDevices = []
    var shared = folder.devices || []
    for (var j = 0; j < shared.length; j++) {
      folderDevices.push({ deviceID: String((shared[j] || {}).id || "") })
    }
    projected.push({
      id: String(folder.id || ""),
      label: String(folder.label || ""),
      path: String(folder.path || ""),
      paused: folder.paused === true,
      markerName: String(folder.markerName || ".stfolder"),
      devices: folderDevices
    })
  }
  return projected
}

function folderStatuses(values) {
  var projected = ({})
  var source = values || []
  for (var i = 0; i < source.length; i++) {
    var folder = source[i] || ({})
    projected[String(folder.id || "")] = folderStatus(folder.status)
  }
  return projected
}

function syncingFiles(activity) {
  var projected = []
  var files = activity && activity.files ? activity.files : []
  for (var i = 0; i < files.length; i++) {
    projected.push(String((files[i] || {}).detail || ""))
  }
  return projected
}

function lifecyclePresentation(lifecycle) {
  var state = lifecycle || ({})
  var controllable = state.canControl === true || state.canStart === true
  return {
    available: state.targetMatch === true && controllable,
    controllable: controllable
  }
}

function truncationWarning(truncation) {
  var state = truncation || ({})
  var keys = ["devices", "folders", "folderDevices", "folderErrors",
    "pendingFolders", "pendingOffers"]
  for (var i = 0; i < keys.length; i++) {
    if (Number(state[keys[i]] || 0) > 0) {
      return "Some Syncthing items exceed panel limits; use the Web UI for "
        + "the hidden entries"
    }
  }
  return ""
}

function driftDecision(configState, lifecycle) {
  var config = String(configState || "")
  var unit = String(lifecycle && lifecycle.unitFileState || "")
  var active = String(lifecycle && lifecycle.activeState || "")
  if (["enabled", "disabled"].indexOf(config) < 0) {
    return { status: "unsupported",
      reason: "Configured service state is unsupported: " + (config || "empty") }
  }
  if (["enabled", "disabled"].indexOf(unit) < 0) {
    return { status: "unsupported",
      reason: "Systemd unit-file state is unsupported: " + (unit || "empty") }
  }
  if (config === unit) return { status: "aligned" }
  if (["active", "inactive"].indexOf(active) < 0) {
    return { status: "unsupported",
      reason: "Systemd runtime state is not settled: " + (active || "empty") }
  }
  var preferred = active === "active" ? "enabled" : "disabled"
  var system = {
    side: "system",
    value: config,
    label: config === "enabled"
      ? "Enable systemd autostart" : "Disable systemd autostart"
  }
  var host = {
    side: "config",
    value: unit,
    label: "Set Syncthing config to " + unit
  }
  system.label += system.value === preferred ? " (preferred)" : ""
  host.label += host.value === preferred ? " (preferred)" : ""
  return {
    status: "drift",
    message: "Syncthing config (" + config
      + ") differs from its systemd autostart setting (" + unit
      + ").\n\nPlease choose:",
    first: system.value === preferred ? system : host,
    second: system.value === preferred ? host : system
  }
}
