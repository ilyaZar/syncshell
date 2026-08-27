.pragma library

function configuredStateSupported(state) {
  return state === "enabled" || state === "disabled"
}

function unitFileStateSupported(state) {
  return state === "enabled" || state === "disabled"
}

function activeStateSupported(state) {
  return state === "active" || state === "inactive"
}

function systemAction(state) {
  return {
    side: "system",
    value: state,
    label: state === "enabled"
      ? "Enable systemd autostart" : "Disable systemd autostart"
  }
}

function configAction(state) {
  return {
    side: "config",
    value: state,
    label: "Set Syncthing config to " + state
  }
}

function markPreferred(action, preferredState) {
  return {
    side: action.side,
    value: action.value,
    preferred: action.value === preferredState,
    label: action.label + (action.value === preferredState
      ? " (preferred)" : "")
  }
}

function decision(configState, unitFileState, activeState) {
  var config = String(configState || "")
  var unit = String(unitFileState || "")
  var active = String(activeState || "")
  var key = active + "|" + config + "|" + unit

  if (!configuredStateSupported(config)) {
    return {
      status: "unsupported",
      key: key,
      reason: "Configured service state is unsupported: " + (config || "empty")
    }
  }
  if (!unitFileStateSupported(unit)) {
    return {
      status: "unsupported",
      key: key,
      reason: "Systemd unit-file state is unsupported: " + (unit || "empty")
    }
  }
  if (config === unit) return { status: "aligned", key: key }
  if (!activeStateSupported(active)) {
    return {
      status: "unsupported",
      key: key,
      reason: "Systemd runtime state is not settled: " + (active || "empty")
    }
  }

  var preferredState = active === "active" ? "enabled" : "disabled"
  var enforceConfig = markPreferred(systemAction(config), preferredState)
  var adoptSystem = markPreferred(configAction(unit), preferredState)
  var first = enforceConfig.preferred ? enforceConfig : adoptSystem
  var second = enforceConfig.preferred ? adoptSystem : enforceConfig
  return {
    status: "drift",
    key: key,
    message: "Syncthing config (" + config
      + ") differs from its systemd autostart setting (" + unit
      + ").\n\nPlease choose:",
    first: first,
    second: second
  }
}

function persistenceCommand(state) {
  if (!configuredStateSupported(state)) return []
  return [
    "systemctl", "--user", state === "enabled" ? "enable" : "disable",
    "syncthing.service"
  ]
}
